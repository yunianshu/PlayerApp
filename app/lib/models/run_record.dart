/// 一次跑步记录及其轨迹点。
class RunRecord {
  final int? id;
  final String? sessionId;
  final DateTime start;
  final DateTime end;
  final double distanceM; // 米
  final int durationS; // 运动时长（暂停不计入）
  final int calories;
  final double climbM; // 累计爬升

  /// 记录来源：'gps'（定位记录）、'manual'（手动补录，无轨迹）
  /// 或 'gpx'（从 GPX 文件导入，含轨迹）。
  final String source;

  /// 可选标题与备注（详情页可编辑）。
  final String title;
  final String notes;

  static const sourceGps = 'gps';
  static const sourceManual = 'manual';
  static const sourceGpx = 'gpx';

  const RunRecord({
    this.id,
    this.sessionId,
    required this.start,
    required this.end,
    required this.distanceM,
    required this.durationS,
    required this.calories,
    this.climbM = 0,
    this.source = sourceGps,
    this.title = '',
    this.notes = '',
  });

  double get distanceKm => distanceM / 1000;
  String get sessionKey => sessionId ?? 'run-${start.microsecondsSinceEpoch}';
  double get avgPaceSecPerKm => distanceM > 10 ? durationS / distanceKm : 0;
  bool get isManual => source == sourceManual;

  /// 列表/详情的展示标题：用户标题优先，否则按开始时间生成。
  String get displayTitle => title.trim().isEmpty ? '' : title.trim();

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'session_id': sessionKey,
    'start_ms': start.millisecondsSinceEpoch,
    'end_ms': end.millisecondsSinceEpoch,
    'distance_m': distanceM,
    'duration_s': durationS,
    'calories': calories,
    'climb_m': climbM,
    'source': source,
    'title': title,
    'notes': notes,
  };

  static RunRecord fromMap(Map<String, Object?> m) => RunRecord(
    id: m['id'] as int,
    sessionId: m['session_id'] as String?,
    start: DateTime.fromMillisecondsSinceEpoch(m['start_ms'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(m['end_ms'] as int),
    distanceM: (m['distance_m'] as num).toDouble(),
    durationS: m['duration_s'] as int,
    calories: m['calories'] as int,
    climbM: (m['climb_m'] as num?)?.toDouble() ?? 0,
    source: (m['source'] as String?) ?? sourceGps,
    title: (m['title'] as String?) ?? '',
    notes: (m['notes'] as String?) ?? '',
  );

  RunRecord copyWith({
    int? id,
    String? title,
    String? notes,
  }) => RunRecord(
    id: id ?? this.id,
    sessionId: sessionId,
    start: start,
    end: end,
    distanceM: distanceM,
    durationS: durationS,
    calories: calories,
    climbM: climbM,
    source: source,
    title: title ?? this.title,
    notes: notes ?? this.notes,
  );
}

class RunPoint {
  final double lat;
  final double lng;
  final double altitude;
  final DateTime time;

  /// A new segment has no connecting distance/time from the preceding point.
  final bool startsSegment;

  /// Active time since the run started, excluding pauses; null for old records.
  final int? elapsedMs;

  const RunPoint({
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.time,
    this.startsSegment = false,
    this.elapsedMs,
  });

  Map<String, Object?> toMap(int runId) => {
    'run_id': runId,
    'lat': lat,
    'lng': lng,
    'altitude': altitude,
    'time_ms': time.millisecondsSinceEpoch,
    'starts_segment': startsSegment ? 1 : 0,
    'elapsed_ms': elapsedMs,
  };

  static RunPoint fromMap(Map<String, Object?> m) => RunPoint(
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    altitude: (m['altitude'] as num?)?.toDouble() ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(m['time_ms'] as int),
    startsSegment: m['starts_segment'] == 1,
    elapsedMs: m['elapsed_ms'] as int?,
  );
}
