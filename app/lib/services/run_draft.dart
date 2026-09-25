import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/run_record.dart';

/// 进行中跑步的草稿：每 15 秒左右落盘一次，
/// 应用进程被杀后下次启动可恢复（保存为记录或放弃）。
class RunDraft {
  final DateTime start;
  final int elapsedMs; // 已扣除暂停的运动时长
  final double distanceM;
  final double climbM;
  final List<RunPoint> points;

  const RunDraft({
    required this.start,
    required this.elapsedMs,
    required this.distanceM,
    required this.climbM,
    required this.points,
  });

  static const _fileName = 'runtrail_draft.json';

  Map<String, Object?> toMap() => {
    'start_ms': start.millisecondsSinceEpoch,
    'elapsed_ms': elapsedMs,
    'distance_m': distanceM,
    'climb_m': climbM,
    'points': [
      for (final p in points)
        [p.lat, p.lng, p.altitude, p.time.millisecondsSinceEpoch],
    ],
  };

  static RunDraft? fromMap(Map<String, Object?> m) {
    final raw = m['points'];
    if (raw is! List) return null;
    final pts = <RunPoint>[];
    for (final row in raw) {
      if (row is! List || row.length < 4) continue;
      pts.add(RunPoint(
        lat: (row[0] as num).toDouble(),
        lng: (row[1] as num).toDouble(),
        altitude: (row[2] as num?)?.toDouble() ?? 0,
        time: DateTime.fromMillisecondsSinceEpoch((row[3] as num).toInt()),
      ));
    }
    if (pts.isEmpty) return null;
    return RunDraft(
      start: DateTime.fromMillisecondsSinceEpoch((m['start_ms'] as num).toInt()),
      elapsedMs: (m['elapsed_ms'] as num?)?.toInt() ?? 0,
      distanceM: (m['distance_m'] as num?)?.toDouble() ?? 0,
      climbM: (m['climb_m'] as num?)?.toDouble() ?? 0,
      points: pts,
    );
  }

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(RunDraft draft) async {
    final f = await _file();
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(draft.toMap()), flush: true);
    } catch (_) {
      // 落盘失败为尽力而为，不阻塞跑步。
    }
  }

  static Future<RunDraft?> load() async {
    final f = await _file();
    if (f == null || !await f.exists()) return null;
    try {
      final m = jsonDecode(await f.readAsString());
      if (m is! Map<String, Object?>) return null;
      return fromMap(m);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final f = await _file();
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 忽略。
    }
  }
}
