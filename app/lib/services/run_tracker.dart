import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../models/run_record.dart';
import 'app_data.dart';
import 'background_service.dart';
import 'diagnostics.dart';
import 'run_draft.dart';
import 'run_math.dart';
import 'tracking_location_settings.dart';
import 'tracking_policies.dart';

enum RunState { idle, running, paused }

/// 自动暂停位置锚点：暂停期间用于检测恢复移动。
class _Anchor {
  final double lat;
  final double lng;
  final DateTime time;
  const _Anchor(this.lat, this.lng, this.time);
}

/// GPS tracking with explicit segment boundaries and recoverable sessions.
/// 支持低速自动暂停：暂停期间保持定位流，检测到持续移动自动续跑。
class RunTracker extends ChangeNotifier {
  RunTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;

  /// 当前时间（构造器可注入）：页面播报防抖等逻辑复用同一时钟便于测试。
  DateTime currentTime() => _now();

  static const _minAccM = 25.0;
  static const _minSegM = 2.5;
  static const _jumpSpeed = 12.0;
  static const _paceWindow = Duration(seconds: 25);
  static const _draftInterval = Duration(seconds: 15);

  RunState state = RunState.idle;
  final List<RunPoint> points = [];
  double distanceM = 0;
  double climbM = 0;
  int movingMs = 0;
  bool gpsError = false;
  bool poorAccuracy = false;
  bool backgroundError = false;
  bool storageError = false;

  /// 当前是否处于自动暂停（区别于手动暂停）。
  bool get autoPaused => _autoPaused;
  bool _autoPaused = false;
  _Anchor? _autoAnchor;
  final AutoPauseDetector _autoPause = AutoPauseDetector();

  int _intervalM = 1000;
  int _announcedUnits = 0;
  int _lastUnitElapsedSec = 0;
  int _announcedKm = 0;
  int _lastKmElapsedSec = 0;

  /// 每完成一个播报间隔回调（跑步页接 TTS 播报），间隔由语音设置决定
  /// （500/1000/2000 米，Keep 同款自定义间隔播报）。
  /// [splitSeconds] 为本间隔分段用时（跨多段补记时为平均值），比瞬时 GPS
  /// 配速稳定；恰好越过整公里边界时 [km] > 0 且 [kmSplitSeconds] 为该整公里
  /// 的分段用时——破纪录/里程碑按公里点判定，与播报间隔解耦。
  void Function(
    int unitIndex,
    int intervalM,
    int splitSeconds,
    int totalSeconds,
    int km,
    int? kmSplitSeconds,
  )? onInterval;

  /// GPS 信号丢失/恢复事件（true=丢失）。仅在状态翻转时触发。
  void Function(bool lost)? onGpsStatus;

  /// 自动暂停/恢复事件（true=暂停，false=恢复）。
  void Function(bool paused)? onAutoPause;

  bool _starting = false;
  bool _stopping = false;
  bool _disposed = false;
  int _startEpoch = 0;
  String? _sessionId;
  DateTime? _startTime;
  DateTime? _pauseTime;
  DateTime? _segmentStartedAt;
  DateTime? _lastFixAt;
  DateTime? _lastDraftAt;
  int _totalPausedMs = 0;
  RunPoint? _lastPoint;
  double? _elevationBase;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Future<void> _streamWork = Future.value();
  Future<void> _backgroundWork = Future.value();
  int _streamEpoch = 0;
  Timer? _ticker;
  Timer? _retry;
  final List<(DateTime, DateTime, double)> _paceSegments = [];

  bool get isBusy => _starting || _stopping || state != RunState.idle;
  Duration get elapsed => _startTime == null
      ? Duration.zero
      : Duration(
          milliseconds: math.max(
            0,
            RunMath.settledElapsedMs(
              start: _startTime!,
              totalPausedMs: _totalPausedMs,
              pauseStart: state == RunState.paused ? _pauseTime : null,
              now: _now(),
            ),
          ),
        );
  double get km => distanceM / 1000;
  double get avgPace => distanceM > 10 ? elapsed.inMilliseconds / 1000 / km : 0;
  int get calories => (km * 65 * 1.036).round();
  bool get hasFix =>
      !gpsError &&
      !poorAccuracy &&
      _lastFixAt != null &&
      _now().difference(_lastFixAt!) <= const Duration(seconds: 6);

  /// 定位流应保持活跃的状态：跑步中，或自动暂停中（需要检测恢复移动）。
  bool get _streamActive =>
      state == RunState.running || (state == RunState.paused && _autoPaused);

  /// Clip both distance and time to the same live window, including time at rest.
  double? get currentPace {
    if (state != RunState.running || _paceSegments.isEmpty) return null;
    final now = _now();
    final cutoff = now.subtract(_paceWindow);
    DateTime? first;
    var distance = 0.0;
    for (final (start, end, meters) in _paceSegments) {
      if (!end.isAfter(cutoff) || start.isAfter(now)) continue;
      final a = start.isBefore(cutoff) ? cutoff : start;
      final b = end.isAfter(now) ? now : end;
      final whole = end.difference(start).inMicroseconds;
      final part = b.difference(a).inMicroseconds;
      if (whole <= 0 || part <= 0) continue;
      first ??= a;
      distance += meters * part / whole;
    }
    if (first == null || distance < _minSegM) return null;
    return now.difference(first).inMilliseconds / distance;
  }

  Future<bool> ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<bool> start() async {
    if (isBusy || _disposed) return false;
    _starting = true;
    final epoch = ++_startEpoch;
    try {
      // A previous session must be explicitly saved or discarded first.
      final draft = await RunDraft.load();
      if (draft != null && draft.recoverable) return false;
      if (!await ensurePermission() ||
          !await isServiceEnabled() ||
          _disposed ||
          epoch != _startEpoch) {
        return false;
      }
      if (draft != null) await RunDraft.clear(sessionId: draft.sessionKey);
      if (_disposed || epoch != _startEpoch) return false;
      points.clear();
      distanceM = 0;
      climbM = 0;
      movingMs = 0;
      _paceSegments.clear();
      _lastPoint = null;
      _elevationBase = null;
      _lastDraftAt = null;
      _lastFixAt = null;
      gpsError = poorAccuracy = backgroundError = storageError = false;
      _autoPaused = false;
      _autoAnchor = null;
      _autoPause.reset();
      _announcedKm = 0;
      _lastKmElapsedSec = 0;
      _intervalM = Prefs.instance.voiceIntervalM;
      _announcedUnits = 0;
      _lastUnitElapsedSec = 0;
      _lastLiveText = null;
      _startTime = _now();
      _segmentStartedAt = _startTime;
      _sessionId =
          '${_startTime!.microsecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
      _pauseTime = null;
      _totalPausedMs = 0;
      state = RunState.running;
      _watchService();
      await _listen();
      if (_disposed || epoch != _startEpoch || state != RunState.running) {
        return false;
      }
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state == RunState.running) {
          _maybeSaveDraft();
          _notify();
        } else if (state == RunState.paused && _autoPaused) {
          // 设置在跑步中途被关闭：立即结束自动暂停。
          if (!Prefs.instance.autoPauseEnabled) unawaited(resume());
        }
      });
      // 屏幕常亮可被设置关闭（息屏省电，成绩靠锁屏通知查看）。
      if (Prefs.instance.keepScreenOn) unawaited(_setWakeLock(true));
      unawaited(_setBackground(true));
      _notify();
      return true;
    } finally {
      _starting = false;
    }
  }

  LocationSettings get locationSettings =>
      trackingLocationSettings(Platform.operatingSystem);

  void _watchService() {
    try {
      _serviceSub = Geolocator.getServiceStatusStream().listen((status) {
        if (!_streamActive || _disposed) return;
        if (status == ServiceStatus.enabled) {
          _retry?.cancel();
          unawaited(_listen());
        } else {
          _locationFailed();
        }
      }, onError: (Object _) => _scheduleRetry());
    } on UnimplementedError {
      // Some platform implementations do not provide a service status stream.
    } catch (_) {
      _scheduleRetry();
    }
  }

  Future<void> _listen() {
    final epoch = ++_streamEpoch;
    _streamWork = _streamWork
        .then((_) async {
          await _posSub?.cancel();
          _posSub = null;
          if (_disposed || !_streamActive || epoch != _streamEpoch) {
            return;
          }
          try {
            if (!await isServiceEnabled()) {
              _locationFailed();
              return;
            }
            if (_disposed || !_streamActive || epoch != _streamEpoch) {
              return;
            }
            final settings = locationSettings;
            unawaited(Diagnostics.log('GPS subscribe ${settings.toJson()}'));
            _posSub = Geolocator.getPositionStream(locationSettings: settings)
                .listen(
                  (position) {
                    if (epoch == _streamEpoch && !_disposed) {
                      _onPosition(position);
                    }
                  },
                  onError: (Object error, StackTrace stack) {
                    if (epoch == _streamEpoch && !_disposed) {
                      unawaited(
                        Diagnostics.logError('GPS stream', error, stack),
                      );
                      _locationFailed();
                    }
                  },
                  onDone: () {
                    if (epoch == _streamEpoch && !_disposed) _locationFailed();
                  },
                );
          } catch (error, stack) {
            unawaited(Diagnostics.logError('GPS subscribe', error, stack));
            _locationFailed();
          }
        })
        .catchError((Object _) {
          _locationFailed();
        });
    return _streamWork;
  }

  void _locationFailed() {
    if (_disposed || !_streamActive) return;
    _setGpsError(true);
    _lastFixAt = null;
    // Unknown movement during a disconnected interval must not form a jump.
    _lastPoint = null;
    _elevationBase = null;
    _paceSegments.clear();
    _autoAnchor = null;
    _segmentStartedAt = _now();
    _scheduleRetry();
    _notify();
  }

  void _scheduleRetry() {
    if (_disposed || !_streamActive || (_retry?.isActive ?? false)) {
      return;
    }
    _retry = Timer(const Duration(seconds: 5), () => unawaited(_listen()));
  }

  void _onPosition(Position pos) {
    if (_disposed) return;
    if (state == RunState.paused) {
      // 自动暂停期间保持定位流，仅用于检测恢复移动。
      if (_autoPaused) _detectResume(pos);
      return;
    }
    if (state != RunState.running) return;
    if (!pos.accuracy.isFinite ||
        pos.accuracy < 0 ||
        pos.accuracy > _minAccM ||
        !pos.latitude.isFinite ||
        pos.latitude.abs() > 90 ||
        !pos.longitude.isFinite ||
        pos.longitude.abs() > 180) {
      poorAccuracy = true;
      _notify();
      return;
    }
    final time = pos.timestamp.toLocal();
    if ((_segmentStartedAt != null && time.isBefore(_segmentStartedAt!)) ||
        time.isAfter(_now().add(const Duration(seconds: 2)))) {
      return;
    }
    final prev = _lastPoint;
    if (prev != null && !time.isAfter(prev.time)) return;
    _lastFixAt = _now();
    _setGpsError(false);
    poorAccuracy = false;
    _retry?.cancel();
    final activeMs = math.max(
      0,
      time.difference(_startTime!).inMilliseconds - _totalPausedMs,
    );
    final p = RunPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      altitude: pos.altitude.isFinite ? pos.altitude : 0,
      time: time,
      startsSegment: prev == null,
      elapsedMs: activeMs,
    );
    if (prev == null) {
      unawaited(Diagnostics.log('GPS first fix accuracy=${pos.accuracy}m'));
      _lastPoint = p;
      points.add(p);
      _elevationBase = null;
      _accumulateClimb(pos);
    } else {
      final dt = time.difference(prev.time).inMilliseconds;
      final distance = RunMath.haversineM(prev.lat, prev.lng, p.lat, p.lng);
      if (distance >= _minSegM && distance / (dt / 1000) < _jumpSpeed) {
        _lastPoint = p;
        points.add(p);
        distanceM += distance;
        movingMs += dt;
        _accumulateClimb(pos);
        _paceSegments.add((prev.time, time, distance));
        final cutoff = _now().subtract(_paceWindow);
        _paceSegments.removeWhere((segment) => !segment.$2.isAfter(cutoff));
        _checkUnit();
      }
      // 无论位移是否达到最小段距，都参与自动暂停的移动判定。
      _feedAutoPause(distance, dt / 1000, p);
    }
    _maybeSaveDraft();
    _notify();
  }

  /// 低速自动暂停：设置开启时，连续低速达到阈值触发暂停。
  void _feedAutoPause(double distanceMeters, double dtSeconds, RunPoint p) {
    if (!Prefs.instance.autoPauseEnabled || _autoPause.isPaused) return;
    final speed = dtSeconds > 0 ? distanceMeters / dtSeconds : 0.0;
    final event = _autoPause.feed(speed, dtSeconds);
    if (event == AutoPauseEvent.shouldPause) {
      // 锚点取触发暂停前的最后一个位置，用于恢复检测。
      _autoAnchor = _Anchor(p.lat, p.lng, p.time);
      pause(auto: true);
    }
  }

  /// 自动暂停期间的定位回调：只做恢复移动检测，不记录轨迹。
  void _detectResume(Position pos) {
    if (!pos.accuracy.isFinite ||
        pos.accuracy < 0 ||
        pos.accuracy > _minAccM ||
        !pos.latitude.isFinite ||
        !pos.longitude.isFinite) {
      return; // 精度差的漂移点不得误触发恢复。
    }
    final time = pos.timestamp.toLocal();
    if (time.isAfter(_now().add(const Duration(seconds: 2)))) return;
    _lastFixAt = _now();
    _setGpsError(false);
    poorAccuracy = false;
    _retry?.cancel();
    final anchor = _autoAnchor;
    if (anchor == null) {
      _autoAnchor = _Anchor(pos.latitude, pos.longitude, time);
      return;
    }
    if (!time.isAfter(anchor.time)) return;
    final dt = time.difference(anchor.time).inMilliseconds / 1000;
    final distance = RunMath.haversineM(
      anchor.lat,
      anchor.lng,
      pos.latitude,
      pos.longitude,
    );
    _autoAnchor = _Anchor(pos.latitude, pos.longitude, time);
    final event = _autoPause.feed(distance / dt, dt);
    if (event == AutoPauseEvent.shouldResume) {
      unawaited(resume());
    }
  }

  /// GPS 状态翻转时触发播报回调；未变化时不触发（防抖，供 TTS 播报）。
  void _setGpsError(bool value) {
    if (gpsError == value) return;
    gpsError = value;
    onGpsStatus?.call(value);
  }

  void _checkUnit() {
    final units = distanceM ~/ _intervalM;
    if (_announcedUnits >= units) return;
    final total = elapsed.inSeconds;
    // 一次跨过多段（GPS 断档补记）时按平均分段播报，避免单段数据失真成极值。
    final delta = units - _announcedUnits;
    final split = delta > 0 ? ((total - _lastUnitElapsedSec) / delta).round() : 0;
    if (split < 0) return;
    _lastUnitElapsedSec = total;

    // 整公里边界与真实 1 公里分段：破纪录/里程碑按公里点判定，与播报间隔解耦。
    var km = 0;
    int? kmSplit;
    final kmIndex = distanceM ~/ 1000;
    if (kmIndex > _announcedKm) {
      final kmDelta = kmIndex - _announcedKm;
      km = kmIndex;
      kmSplit = ((total - _lastKmElapsedSec) / kmDelta).round();
      if (kmSplit < 0) kmSplit = null;
      _announcedKm = kmIndex;
      _lastKmElapsedSec = total;
    }

    while (_announcedUnits < units) {
      _announcedUnits++;
      onInterval?.call(_announcedUnits, _intervalM, split, total, km, kmSplit);
    }
  }

  void _accumulateClimb(Position pos) {
    if (!pos.altitude.isFinite ||
        !pos.altitudeAccuracy.isFinite ||
        pos.altitudeAccuracy > 25) {
      return;
    }
    final base = _elevationBase;
    if (base == null) {
      _elevationBase = pos.altitude;
      return;
    }
    // Accumulate sub-threshold rises against a stable anchor, not the last fix.
    final threshold = pos.altitudeAccuracy > 0
        ? pos.altitudeAccuracy.clamp(1.0, 5.0)
        : 3.0;
    final change = pos.altitude - base;
    if (change >= threshold) {
      climbM += change;
      _elevationBase = pos.altitude;
    } else if (change <= -threshold) {
      _elevationBase = pos.altitude;
    }
  }

  RunDraft? _snapshotDraft() => points.isEmpty || _startTime == null
      ? null
      : RunDraft(
          sessionId: _sessionId,
          start: _startTime!,
          end: _now(),
          elapsedMs: elapsed.inMilliseconds,
          distanceM: distanceM,
          climbM: climbM,
          points: List.of(points),
        );

  Future<void> _persist(RunDraft draft) async {
    try {
      await RunDraft.save(draft);
      storageError = false;
    } catch (_) {
      storageError = true;
      _lastDraftAt = null;
    }
    _notify();
  }

  void _maybeSaveDraft() {
    if (distanceM < 20 || points.length < 2) return;
    final now = _now();
    if (_lastDraftAt != null &&
        now.difference(_lastDraftAt!) < _draftInterval) {
      return;
    }
    _lastDraftAt = now;
    final draft = _snapshotDraft();
    if (draft != null) unawaited(_persist(draft));
  }

  void _cancelPositionStream() {
    ++_streamEpoch;
    _retry?.cancel();
    _streamWork = _streamWork
        .then((_) async {
          await _posSub?.cancel();
          _posSub = null;
        })
        .catchError((Object _) {});
  }

  /// [auto] 为 true 时保持定位流与后台服务，用于检测恢复移动。
  void pause({bool auto = false}) {
    if (state != RunState.running) return;
    _pauseTime = _now();
    state = RunState.paused;
    _autoPaused = auto;
    _lastPoint = null;
    _elevationBase = null;
    _paceSegments.clear();
    if (!auto) {
      _cancelPositionStream();
      unawaited(_setBackground(false));
    } else {
      onAutoPause?.call(true);
    }
    final draft = _snapshotDraft();
    if (draft != null) unawaited(_persist(draft));
    _notify();
  }

  Future<void> resume() async {
    if (state != RunState.paused) return;
    final now = _now();
    if (_pauseTime != null) {
      _totalPausedMs += now.difference(_pauseTime!).inMilliseconds;
    }
    _pauseTime = null;
    final wasAuto = _autoPaused;
    _autoPaused = false;
    _autoAnchor = null;
    _autoPause.reset();
    state = RunState.running;
    _segmentStartedAt = now;
    _lastFixAt = null;
    _lastPoint = null;
    _elevationBase = null;
    if (wasAuto) {
      onAutoPause?.call(false);
    } else {
      await _listen();
      unawaited(_setBackground(true));
    }
    _notify();
  }

  /// Persist the final snapshot before presenting the save screen.
  Future<RunRecord?> stop() async {
    if (state == RunState.idle || _startTime == null || _stopping) return null;
    _stopping = true;
    final draft = _snapshotDraft();
    _endTracking();
    try {
      if (draft == null || !draft.recoverable) {
        await RunDraft.clear(sessionId: _sessionId);
        AppData.instance.bump();
        return null;
      }
      await _persist(draft);
      AppData.instance.bump();
      return draft.record;
    } finally {
      _stopping = false;
    }
  }

  void _endTracking() {
    ++_startEpoch;
    state = RunState.idle;
    _startTime = null;
    _pauseTime = null;
    _autoPaused = false;
    _autoAnchor = null;
    _cancelPositionStream();
    unawaited(_serviceSub?.cancel());
    _serviceSub = null;
    _ticker?.cancel();
    unawaited(_setWakeLock(false));
    unawaited(_setBackground(false));
    _notify();
  }

  Future<void> discard() async {
    _endTracking();
    await RunDraft.clear(sessionId: _sessionId);
    AppData.instance.bump();
  }

  Future<void> _setWakeLock(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Screen wake lock failure does not prevent recording or persistence.
    }
  }

  Future<void> _setBackground(bool enabled) {
    _backgroundWork = _backgroundWork.then((_) async {
      if (enabled) {
        if (_disposed || state != RunState.running) return;
        backgroundError = !await BackgroundService.start();
        _notify();
      } else {
        await BackgroundService.stop();
      }
    });
    return _backgroundWork;
  }

  String? _lastLiveText;
  DateTime? _lastLiveUpdateAt;
  double _lastLiveUpdateDist = 0;

  void _notify() {
    if (!_disposed) notifyListeners();
    _updateLiveNotification();
  }

  /// 把实时成绩刷进前台通知：息屏/锁屏抬手可见（Keep 同款交互）。
  /// 每秒 notify 会被系统通知频控降级（demoted/muted，锁屏看不到），
  /// 改为 10 秒节流 + 距离每前进 100 米立即刷新。
  void _updateLiveNotification() {
    if (_disposed || state != RunState.running) return;
    final now = currentTime();
    final last = _lastLiveUpdateAt;
    final distAdvanced = distanceM - _lastLiveUpdateDist >= 100;
    if (last != null && !distAdvanced && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    final text = lockScreenStatsText(
      distanceM: distanceM,
      elapsedSeconds: elapsed.inSeconds,
      paceSecPerKm: avgPace > 0 ? avgPace : null,
      english: LocaleController.instance.isEnglish,
    );
    if (text == _lastLiveText) return;
    _lastLiveText = text;
    _lastLiveUpdateAt = now;
    _lastLiveUpdateDist = distanceM;
    unawaited(BackgroundService.updateStats(text));
  }

  @override
  void dispose() {
    _disposed = true;
    _endTracking();
    super.dispose();
  }
}
