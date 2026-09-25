import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/run_record.dart';
import 'background_service.dart';
import 'run_draft.dart';
import 'run_math.dart';

enum RunState { idle, running, paused }

/// GPS 跑步追踪：定位流、里程累计、配速与卡路里估算。
/// 所有计算在本地完成，不依赖服务器。
class RunTracker extends ChangeNotifier {
  /// 可注入时钟，便于测试暂停/窗口逻辑。
  RunTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  static const _userWeightKg = 65.0; // 卡路里估算体重
  static const _minAccM = 25.0; // 超出精度的点直接丢弃
  static const _minSegM = 2.5; // 小于该距离视为 GPS 静止漂移，不计入里程
  static const _jumpSpeed = 12.0; // m/s，视为 GPS 漂移
  static const _paceWindowMs = 25000; // 实时配速窗口
  static const _draftIntervalMs = 15000; // 草稿落盘最小间隔

  RunState state = RunState.idle;

  final List<RunPoint> points = [];
  double distanceM = 0;
  double climbM = 0;
  int movingMs = 0;

  /// 定位流错误（权限被系统撤销、服务中途关闭等）。
  bool gpsError = false;
  DateTime? _lastFixAt;

  StreamSubscription<Position>? _posSub;
  Timer? _ticker;
  RunPoint? _lastPoint;

  DateTime? _startTime;
  DateTime? _pauseTime;
  int _totalPausedMs = 0;

  /// 实时配速滑动窗口内接受的段（时间，段长米），按时间升序。
  final List<(DateTime, double)> _paceSegments = [];
  DateTime? _lastDraftAt;

  bool get isBusy => state != RunState.idle;

  /// 总时长：从按下开始到现在的真实流逝时间（扣除暂停）。
  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    return Duration(
      milliseconds: RunMath.settledElapsedMs(
        start: _startTime!,
        totalPausedMs: _totalPausedMs,
        pauseStart: state == RunState.paused ? _pauseTime : null,
        now: _now(),
      ),
    );
  }

  double get km => distanceM / 1000;
  double get avgPace => distanceM > 10 ? movingMs / 1000 / km : 0;
  int get calories => (km * _userWeightKg * 1.036).round();

  /// GPS 信号状态：正常（6 秒内有点）/ 搜索中 / 出错。
  bool get hasFix {
    if (gpsError) return false;
    final last = _lastFixAt;
    return last != null && _now().difference(last).inSeconds <= 6;
  }

  /// 实时配速：取最近 25 秒滑动窗口，段不足时退回全程平均。
  double? get currentPace {
    if (_paceSegments.isEmpty) return avgPace;
    final latest = _paceSegments.last.$1;
    var dist = 0.0;
    for (final (t, d) in _paceSegments.reversed) {
      if (latest.difference(t).inMilliseconds > _paceWindowMs) break;
      dist += d;
    }
    final windowStart = _oldestInWindow(latest);
    if (windowStart == null) return avgPace;
    final secs =
        latest.difference(windowStart).inMilliseconds / 1000;
    if (secs < 8 || dist < 20) return avgPace;
    return secs / (dist / 1000);
  }

  DateTime? _oldestInWindow(DateTime latest) {
    for (final (t, _) in _paceSegments) {
      if (latest.difference(t).inMilliseconds <= _paceWindowMs) return t;
    }
    return null;
  }

  Future<bool> ensurePermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  Future<bool> start() async {
    if (state != RunState.idle) return false;
    if (!await ensurePermission()) return false;
    if (!await isServiceEnabled()) return false;

    points.clear();
    distanceM = 0;
    climbM = 0;
    movingMs = 0;
    _lastPoint = null;
    _paceSegments.clear();
    _lastDraftAt = null;
    gpsError = false;
    _lastFixAt = null;
    _startTime = _now();
    _pauseTime = null;
    _totalPausedMs = 0;
    state = RunState.running;
    await RunDraft.clear(); // 新跑步开始，清除上一份草稿
    _listen();
    _startTicker();
    WakelockPlus.enable();
    unawaited(BackgroundService.start());
    notifyListeners();
    return true;
  }

  void _listen() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 4,
      ),
    ).listen(_onPosition, onError: (Object _) {
      gpsError = true;
      notifyListeners();
    });
  }

  void _onPosition(Position pos) {
    if (state != RunState.running) return;
    _lastFixAt = _now();
    gpsError = false;
    if (pos.accuracy > _minAccM) {
      notifyListeners();
      return;
    }

    // 统一转本地时间：geolocator 的 timestamp 为 UTC，
    // 后续展示（SummaryPage 的"今天 HH:mm"/晨跑夜跑）直接读 .hour。
    final p = RunPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      altitude: pos.altitude,
      time: pos.timestamp.toLocal(),
    );

    final prev = _lastPoint;
    if (prev != null) {
      final dt = p.time.difference(prev.time).inMilliseconds / 1000;
      // 乱序晚到的旧点：直接丢弃，否则会造成里程虚增与轨迹回跳。
      if (dt <= 0) {
        notifyListeners();
        return;
      }
      final seg = RunMath.haversineM(prev.lat, prev.lng, p.lat, p.lng);
      final speed = seg / dt;

      // 过滤静止漂移：距离过小视为噪声；速度过大视为 GPS 跳点。
      if (seg >= _minSegM && speed < _jumpSpeed) {
        _lastPoint = p;
        points.add(p);
        distanceM += seg;
        if (p.altitude > prev.altitude + 1) {
          climbM += p.altitude - prev.altitude;
        }
        movingMs += (dt * 1000).round();
        _pushPaceSegment(p.time, seg);
      } else {
        // 漂移点不进入轨迹，但保留最近有效点不变。
      }
    } else {
      _lastPoint = p;
      points.add(p);
    }
    _maybeSaveDraft();
    notifyListeners();
  }

  void _pushPaceSegment(DateTime time, double segM) {
    _paceSegments.add((time, segM));
    // 裁掉窗口外的老段，保持列表有界。
    while (_paceSegments.length > 1 &&
        time.difference(_paceSegments.first.$1).inMilliseconds >
            _paceWindowMs) {
      _paceSegments.removeAt(0);
    }
  }

  void _maybeSaveDraft() {
    if (points.length < 5 || distanceM < 20) return;
    final now = _now();
    final last = _lastDraftAt;
    if (last != null && now.difference(last).inMilliseconds < _draftIntervalMs) {
      return;
    }
    _lastDraftAt = now;
    unawaited(RunDraft.save(_snapshotDraft()));
  }

  RunDraft _snapshotDraft() => RunDraft(
    start: points.first.time,
    elapsedMs: elapsed.inMilliseconds,
    distanceM: distanceM,
    climbM: climbM,
    points: List.of(points),
  );

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // 无 GPS 更新时兜底计时（室内/隧道）
      if (state == RunState.running) notifyListeners();
    });
  }

  void pause() {
    if (state != RunState.running) return;
    state = RunState.paused;
    _pauseTime = _now();
    _paceSegments.clear();
    // 暂停期间停止接收定位（省电）；恢复时重新监听。
    unawaited(_posSub?.cancel());
    _posSub = null;
    unawaited(RunDraft.save(_snapshotDraft()));
    notifyListeners();
  }

  void resume() {
    if (state != RunState.paused) return;
    if (_pauseTime != null) {
      _totalPausedMs += _now().difference(_pauseTime!).inMilliseconds;
      _pauseTime = null;
    }
    state = RunState.running;
    _lastFixAt = null; // 重新搜索信号
    _listen();
    notifyListeners();
  }

  /// 结束并返回记录；轨迹太短时返回 null。
  RunRecord? stop() {
    if (state == RunState.idle || _startTime == null) return null;
    final end = _now();
    // 结算时长必须包含"暂停中"尚未累计的部分，否则暂停时停止会虚增运动时长。
    final durationS = Duration(
      milliseconds: RunMath.settledElapsedMs(
        start: _startTime!,
        totalPausedMs: _totalPausedMs,
        pauseStart: _pauseTime,
        now: end,
      ),
    ).inSeconds;
    _pauseTime = null;

    _posSub?.cancel();
    _ticker?.cancel();
    WakelockPlus.disable();
    unawaited(BackgroundService.stop());
    state = RunState.idle;
    _startTime = null;
    notifyListeners();

    if (distanceM < 20 || points.isEmpty) {
      unawaited(RunDraft.clear());
      return null;
    }
    final record = RunRecord(
      start: points.first.time,
      end: end,
      distanceM: distanceM,
      durationS: durationS,
      calories: calories,
      climbM: climbM,
    );
    // 记录即将进入 SummaryPage 保存，草稿使命完成；若用户放弃保存，也无需恢复。
    unawaited(RunDraft.clear());
    return record;
  }

  void discard() {
    _posSub?.cancel();
    _ticker?.cancel();
    WakelockPlus.disable();
    unawaited(BackgroundService.stop());
    state = RunState.idle;
    _startTime = null;
    _pauseTime = null;
    _totalPausedMs = 0;
    unawaited(RunDraft.clear());
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
