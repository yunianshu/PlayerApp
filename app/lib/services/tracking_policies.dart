/// 跑步追踪的纯逻辑判定器：自动暂停/恢复与目标配速偏离提醒。
/// 不依赖平台与 GPS 插件，可独立单测。
library;

/// 自动暂停事件。
enum AutoPauseEvent { none, shouldPause, shouldResume }

/// 低速自动暂停判定：累计低速时长触发暂停，恢复需持续高于Resume阈值。
/// 迟滞（still < resume 阈值）防止临界速度反复横跳；恢复还要求窗口内
/// 累计位移达到下限——静止时 GPS 漂移速度偶可瞬时超阈值，但位移凑不齐，
/// 从根上避免"暂停↔恢复"反复翻转（每次翻转都会震动+播报打断音乐）。
class AutoPauseDetector {
  AutoPauseDetector({
    this.stillSeconds = 10,
    this.resumeSeconds = 5,
    this.stillSpeedMps = 0.5,
    this.resumeSpeedMps = 1.5,
    this.resumeDistanceM = 10,
  });

  /// 低速（≤ stillSpeedMps）持续多少秒触发自动暂停。
  final double stillSeconds;

  /// 速度（≥ resumeSpeedMps）持续多少秒触发自动恢复。
  final double resumeSeconds;

  final double stillSpeedMps;
  final double resumeSpeedMps;

  /// 恢复窗口内累计位移下限（米）：区分真实起跑与原地 GPS 漂移。
  final double resumeDistanceM;

  bool _paused = false;
  double _stillFor = 0;
  double _movingFor = 0;
  double _movingDistance = 0;

  bool get isPaused => _paused;

  void reset() {
    _paused = false;
    _stillFor = 0;
    _movingFor = 0;
    _movingDistance = 0;
  }

  /// [speedMps] 相邻有效定位点间的平均速度；[dtSeconds] 两点间隔。
  AutoPauseEvent feed(double speedMps, double dtSeconds) {
    if (!dtSeconds.isFinite || dtSeconds <= 0) return AutoPauseEvent.none;
    if (!_paused) {
      if (speedMps.isFinite && speedMps <= stillSpeedMps) {
        _stillFor += dtSeconds;
        if (_stillFor >= stillSeconds) {
          _paused = true;
          _movingFor = 0;
          _movingDistance = 0;
          return AutoPauseEvent.shouldPause;
        }
      } else {
        _stillFor = 0;
      }
    } else {
      if (speedMps.isFinite && speedMps >= resumeSpeedMps) {
        _movingFor += dtSeconds;
        if (speedMps.isFinite) _movingDistance += speedMps * dtSeconds;
        if (_movingFor >= resumeSeconds && _movingDistance >= resumeDistanceM) {
          _paused = false;
          _stillFor = 0;
          _movingFor = 0;
          _movingDistance = 0;
          return AutoPauseEvent.shouldResume;
        }
      } else {
        _movingFor = 0;
        _movingDistance = 0;
      }
    }
    return AutoPauseEvent.none;
  }
}

/// 配速偏离方向。
enum PaceDeviation { tooSlow, tooFast }

/// 目标配速提醒判定：持续偏离达到确认时长才提示，
/// 提示后进入冷却，避免每个定位点都震动。
class PaceTargetEvaluator {
  PaceTargetEvaluator({
    required this.targetSecPerKm,
    this.toleranceSec = 20,
    this.confirmSeconds = 15,
    this.coolDownSeconds = 90,
  }) : assert(targetSecPerKm > 0);

  final double targetSecPerKm;

  /// 偏离目标多少秒/公里以内算正常。
  final double toleranceSec;

  /// 持续偏离多久（秒）才提示。
  final double confirmSeconds;

  /// 一次提示后，持续偏离时隔多久再次提示。
  final double coolDownSeconds;

  /// 当前持续的偏离方向（供横幅显示）；正常或数据不足时为 null。
  PaceDeviation? deviation;

  double _deviatingFor = 0;
  double _sinceAlert = double.infinity;

  void reset() {
    deviation = null;
    _deviatingFor = 0;
    _sinceAlert = double.infinity;
  }

  /// [paceSecPerKm] 实时配速（数据不足时传 null，会清除偏离状态）。
  /// 返回需要立即提醒（震动/播报）的偏离，无需提醒时返回 null。
  PaceDeviation? feed(double? paceSecPerKm, double dtSeconds) {
    if (!dtSeconds.isFinite || dtSeconds <= 0) return null;
    final dev = _deviationOf(paceSecPerKm);
    if (dev == null) {
      if (deviation != null) {
        deviation = null;
        _deviatingFor = 0;
      }
      _sinceAlert = double.infinity;
      return null;
    }
    if (dev != deviation) {
      deviation = dev;
      _deviatingFor = 0;
      return null;
    }
    _deviatingFor += dtSeconds;
    if (_deviatingFor < confirmSeconds) return null;
    if (_sinceAlert.isInfinite) {
      _sinceAlert = 0;
      return dev;
    }
    _sinceAlert += dtSeconds;
    if (_sinceAlert >= coolDownSeconds) {
      _sinceAlert = 0;
      return dev;
    }
    return null;
  }

  PaceDeviation? _deviationOf(double? pace) {
    if (pace == null || !pace.isFinite || pace <= 0) return null;
    final diff = pace - targetSecPerKm;
    if (diff > toleranceSec) return PaceDeviation.tooSlow;
    if (diff < -toleranceSec) return PaceDeviation.tooFast;
    return null;
  }
}

/// 目标配速输入解析：接受 "5:30"、"530"？不——只接受 m:ss 或纯分钟小数。
/// 返回秒/公里；格式非法返回 null。
double? parsePaceInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final colon = text.indexOf(':');
  if (colon < 0) {
    final minutes = double.tryParse(text);
    if (minutes == null || !minutes.isFinite || minutes <= 0) return null;
    return minutes * 60;
  }
  final minutesPart = text.substring(0, colon);
  final secondsPart = text.substring(colon + 1);
  final minutes = int.tryParse(minutesPart);
  final seconds = secondsPart.isEmpty ? 0 : int.tryParse(secondsPart);
  if (minutes == null || seconds == null) return null;
  if (seconds < 0 || seconds > 59 || minutes < 0) return null;
  return minutes * 60 + seconds.toDouble();
}

/// 时长输入解析（手动补录用）："30:00" → 1800 秒；"1:05:00" → 3900 秒；
/// "90" → 90 分钟 = 5400 秒。返回秒；非法返回 null。
int? parseDurationInput(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) return null;
  if (parts.length == 1) {
    final minutes = double.tryParse(text);
    if (minutes == null || !minutes.isFinite || minutes <= 0) return null;
    return (minutes * 60).round();
  }
  final values = <int>[];
  for (final part in parts) {
    final v = int.tryParse(part);
    if (v == null || v < 0) return null;
    values.add(v);
  }
  if (values.last > 59) return null;
  if (values.length == 3 && values[1] > 59) return null;
  var seconds = values.last;
  if (values.length >= 2) seconds += values[values.length - 2] * 60;
  if (values.length == 3) seconds += values[0] * 3600;
  if (seconds <= 0) return null;
  return seconds;
}

/// 秒/公里 → "m:ss"。
String formatPaceInput(double secPerKm) {
  final m = secPerKm ~/ 60;
  final s = (secPerKm - m * 60).round();
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 配速提醒播报文案：报出当前配速与目标数值，跑步中直接可纠偏。
/// 纯函数（语言由调用方传入），便于单测；秒位四舍五入带 60 进位。
String paceAlertText({
  required PaceDeviation deviation,
  required double? paceSecPerKm,
  required double targetSecPerKm,
  required bool english,
}) {
  String spoken(double? sec) {
    if (sec == null || !sec.isFinite || sec <= 0) return '';
    final total = sec.round();
    final m = total ~/ 60;
    final s = total % 60;
    return english
        ? '$m minutes $s seconds'
        : '$m分${s.toString().padLeft(2, '0')}秒';
  }

  final pacePart = spoken(paceSecPerKm);
  final targetPart = spoken(targetSecPerKm);
  if (english) {
    final dir = deviation == PaceDeviation.tooSlow
        ? 'slower than target'
        : 'faster than target';
    return pacePart.isEmpty
        ? '$dir $targetPart'
        : 'Current pace $pacePart, $dir $targetPart';
  }
  final dir = deviation == PaceDeviation.tooSlow ? '慢于目标' : '快于目标';
  return pacePart.isEmpty ? '$dir$targetPart' : '当前配速$pacePart，$dir$targetPart';
}

/// 锁屏/前台通知的实时成绩文案（息屏后抬手可见，Keep 同款交互）。
/// 纯函数便于单测；配速数据不足时省略配速段。
/// 中文示例："3.42 公里 · 5'30"/公里 · 18:52"。
String lockScreenStatsText({
  required double distanceM,
  required int elapsedSeconds,
  double? paceSecPerKm,
  required bool english,
}) {
  final km = distanceM / 1000;
  final shownKm = km >= 99.95 ? km.toStringAsFixed(0) : km.toStringAsFixed(2);
  final h = elapsedSeconds ~/ 3600;
  final m = (elapsedSeconds % 3600) ~/ 60;
  final s = elapsedSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  final time = h > 0 ? '$h:$mm:$ss' : '$m:$ss';
  final parts = <String>[
    english ? '$shownKm km' : '$shownKm 公里',
    if (paceSecPerKm != null &&
        paceSecPerKm.isFinite &&
        paceSecPerKm > 0 &&
        paceSecPerKm < 3600)
      "${formatPaceInput(paceSecPerKm)}${english ? " /km" : " /公里"}",
    time,
  ];
  return parts.join(' · ');
}

/// 半马/全马里程碑距离（米），达成时播报（Keep 同款：Rhalf/full_marathon_distance）。
const double halfMarathonM = 21097.5;
const double fullMarathonM = 42195.0;

/// 目标配速偏差"米数化"（Keep 同款 rt_layout_pace_target_diff 交互）：
/// 把配速差换算成按目标配速应完成的距离与实际距离的差值——
/// "快 37 米"比"慢于目标 20 秒/公里"对跑者直观得多。
/// 返回正值 = 领先目标，负值 = 落后目标；数据不足返回 null。
double? paceTargetDiffMeters({
  required double targetSecPerKm,
  required double elapsedSeconds,
  required double distanceM,
}) {
  if (targetSecPerKm <= 0 ||
      elapsedSeconds <= 0 ||
      distanceM <= 0 ||
      !elapsedSeconds.isFinite ||
      !distanceM.isFinite) {
    return null;
  }
  // 按目标配速，同样时长应完成的距离（米）。
  final targetDistanceM = elapsedSeconds / targetSecPerKm * 1000;
  return distanceM - targetDistanceM;
}

/// 每公里/每间隔播报文案（参照 Keep 的播报结构：距离 + 最近一分段用时 +
/// 平均配速；命中个人纪录或半马/全马里程碑时追加播报）。
/// 纯函数便于单测；text 为 null 表示无内容可播（对应开关全关），
/// 各 new* 标志供调用方更新"本次跑步已播报"状态。
({String? text, bool newBest1km, bool newLongest, bool newHalf, bool newFull})
kmAnnouncementText({
  required bool english,
  required bool sayDistance,
  required bool sayTime,
  required bool sayPace,
  required int unitIndex,
  required int intervalM,
  required int splitSeconds,
  required int totalSeconds,
  int km = 0,
  int? kmSplitSeconds,
  double? best1kmSec,
  double? longestDistanceM,
  double? currentDistanceM,
  bool longestAlreadyAnnounced = false,
  bool halfMarathonAnnounced = false,
  bool fullMarathonAnnounced = false,
}) {
  final empty = (
    text: null,
    newBest1km: false,
    newLongest: false,
    newHalf: false,
    newFull: false,
  );
  if (unitIndex <= 0 ||
      intervalM <= 0 ||
      splitSeconds < 0 ||
      totalSeconds < 0) {
    return empty;
  }
  final parts = <String>[];
  if (sayDistance) {
    if (intervalM == 1000) {
      parts.add(english ? 'Kilometer $unitIndex' : '第$unitIndex公里');
    } else {
      final kmNow = unitIndex * intervalM / 1000;
      final shown = intervalM % 1000 == 0
          ? kmNow.toInt().toString()
          : kmNow.toStringAsFixed(1);
      parts.add(english ? 'ran $shown km' : '已跑$shown公里');
    }
  }
  if (sayTime) {
    final label = intervalM == 1000
        ? (english ? 'km' : '一公里')
        : intervalM == 500
        ? (english ? '500 m' : '500米')
        : (english ? '2 km' : '两公里');
    parts.add(
      english
          ? 'last $label ${_spokenDuration(splitSeconds, english)}'
          : '最近$label用时${_spokenDuration(splitSeconds, english)}',
    );
  }
  if (sayPace && totalSeconds > 0) {
    // 平均配速 = 累计用时/公里：整段平滑，不受 GPS 瞬时抖动影响。
    final avg = (totalSeconds * 1000 / (unitIndex * intervalM)).round();
    parts.add(
      english
          ? 'average pace ${_spokenDuration(avg, english)} per kilometer'
          : '平均配速${_spokenDuration(avg, english)}',
    );
  }
  // 破纪录播报（Keep 同款能力：最快 1 公里 / 最长距离）。
  // 最快 1 公里允许本次跑步内连续刷新时再次播报；最长距离只报一次。
  // 依据整公里边界提供的 kmSplitSeconds（与播报间隔解耦）。
  final newBest1km =
      km > 0 &&
      kmSplitSeconds != null &&
      kmSplitSeconds > 0 &&
      best1kmSec != null &&
      best1kmSec > 0 &&
      kmSplitSeconds < best1kmSec;
  if (newBest1km) {
    parts.add(english ? 'new fastest kilometer!' : '刷新一公里最快纪录！');
  }
  final newLongest =
      !longestAlreadyAnnounced &&
      longestDistanceM != null &&
      longestDistanceM > 0 &&
      currentDistanceM != null &&
      currentDistanceM > longestDistanceM;
  if (newLongest) {
    parts.add(english ? 'new longest run!' : '刷新最长跑步距离纪录！');
  }
  // 半马/全马里程碑：按累计距离判定，各播一次；全马达成时半马一并算已过。
  final distance = currentDistanceM ?? 0;
  final newFull = !fullMarathonAnnounced && distance >= fullMarathonM;
  final newHalf = !halfMarathonAnnounced &&
      !newFull &&
      distance >= halfMarathonM &&
      distance < fullMarathonM;
  if (newHalf) {
    parts.add(english ? 'half marathon distance done!' : '完成半马距离！');
  }
  if (newFull) {
    parts.add(english ? 'full marathon distance done!' : '完成全马距离！');
  }
  if (parts.isEmpty) return empty;
  return (
    text: parts.join(english ? ', ' : '，'),
    newBest1km: newBest1km,
    newLongest: newLongest,
    newHalf: newHalf,
    newFull: newFull,
  );
}

String _spokenDuration(int seconds, bool english) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return english
      ? '$m minutes $s seconds'
      : '$m分${s.toString().padLeft(2, '0')}秒';
}
