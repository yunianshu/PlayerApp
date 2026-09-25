/// 一次跑步记录及其轨迹点。
class RunRecord {
  final int? id;
  final DateTime start;
  final DateTime end;
  final double distanceM; // 米
  final int durationS; // 运动时长（暂停不计入）
  final int calories;
  final double climbM; // 累计爬升

  const RunRecord({
    this.id,
    required this.start,
    required this.end,
    required this.distanceM,
    required this.durationS,
    required this.calories,
    this.climbM = 0,
  });

  double get distanceKm => distanceM / 1000;
  double get avgPaceSecPerKm => distanceM > 10 ? durationS / distanceKm : 0;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'start_ms': start.millisecondsSinceEpoch,
    'end_ms': end.millisecondsSinceEpoch,
    'distance_m': distanceM,
    'duration_s': durationS,
    'calories': calories,
    'climb_m': climbM,
  };

  static RunRecord fromMap(Map<String, Object?> m) => RunRecord(
    id: m['id'] as int,
    start: DateTime.fromMillisecondsSinceEpoch(m['start_ms'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(m['end_ms'] as int),
    distanceM: (m['distance_m'] as num).toDouble(),
    durationS: m['duration_s'] as int,
    calories: m['calories'] as int,
    climbM: (m['climb_m'] as num?)?.toDouble() ?? 0,
  );

  RunRecord copyWith({int? id}) => RunRecord(
    id: id ?? this.id,
    start: start,
    end: end,
    distanceM: distanceM,
    durationS: durationS,
    calories: calories,
    climbM: climbM,
  );
}

class RunPoint {
  final double lat;
  final double lng;
  final double altitude;
  final DateTime time;

  const RunPoint({
    required this.lat,
    required this.lng,
    required this.altitude,
    required this.time,
  });

  Map<String, Object?> toMap(int runId) => {
    'run_id': runId,
    'lat': lat,
    'lng': lng,
    'altitude': altitude,
    'time_ms': time.millisecondsSinceEpoch,
  };

  static RunPoint fromMap(Map<String, Object?> m) => RunPoint(
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    altitude: (m['altitude'] as num?)?.toDouble() ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(m['time_ms'] as int),
  );
}
