import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../core/prefs.dart';
import '../data/database.dart';
import '../models/run_record.dart';
import 'body_weight_service.dart';

/// 全量备份 / 恢复：runs + points + 偏好设置，JSON 单文件。
/// 导出走系统分享（用户自选保存位置）；恢复通过原生文件选择
/// （Android SAF / iOS 文档选择器），鸿蒙端降级提示。
class BackupService {
  BackupService._();

  static const formatVersion = 1;

  static Map<String, Object?> build(
    List<RunRecord> runs,
    Map<String, List<RunPoint>> pointsBySession,
  ) => {
    'app': 'RunTrail',
    'format': formatVersion,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'runs': [
      for (final r in runs)
        {
          ...r.toMap(),
          'points': [
            for (final p in pointsBySession[r.sessionKey] ?? const <RunPoint>[])
              [
                p.lat,
                p.lng,
                p.altitude,
                p.time.millisecondsSinceEpoch,
                p.startsSegment,
                p.elapsedMs,
              ],
          ],
        },
    ],
    'prefs': {
      'weekly_goal_km': Prefs.instance.weeklyGoalKm,
      'yearly_goal_km': Prefs.instance.yearlyGoalKm,
      'auto_pause_enabled': Prefs.instance.autoPauseEnabled,
      'voice_announce_enabled': Prefs.instance.voiceEnabled,
      'pace_target_sec_per_km': Prefs.instance.paceTargetSecPerKm,
      'app_language': LocaleController.instance.pref.name,
    },
  };

  /// 导出全部数据为 JSON 字符串（分离 IO 便于单测）。
  static Future<String> exportJson({bool includeWeight = false}) async {
    final runs = await RunDatabase.instance.listRuns();
    final points = <String, List<RunPoint>>{};
    for (final r in runs) {
      final id = r.id;
      if (id != null) {
        points[r.sessionKey] = await RunDatabase.instance.getPoints(id);
      }
    }
    final data = build(runs, points);
    if (includeWeight) {
      data['body_weight_records'] =
          (await BodyWeightService.instance.snapshot()).records
              .map((r) => r.toJson())
              .toList();
    }
    return jsonEncode(data);
  }

  /// 解析并导入备份，返回成功导入的记录数。
  /// 会话 ID 已存在的记录自动跳过（幂等），损坏的条目跳过并计数。
  static Future<RestoreResult> restoreJson(String json) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException();
    }
    if (decoded is! Map<String, dynamic>) throw const BackupFormatException();
    final app = decoded['app'];
    if (app != 'RunTrail') throw const BackupFormatException();
    final runsRaw = decoded['runs'];
    if (runsRaw is! List) throw const BackupFormatException();
    final weights = decoded['body_weight_records'];
    if (weights != null) {
      if (weights is! List) throw const BackupFormatException();
      try {
        await BodyWeightService.instance.mergeBackup(weights);
      } on FormatException {
        throw const BackupFormatException();
      }
    }
    await _restorePrefs(decoded['prefs']);
    var imported = 0;
    var skipped = 0;
    for (final raw in runsRaw) {
      if (raw is! Map<String, dynamic>) {
        skipped++;
        continue;
      }
      try {
        final record = _recordFromBackup(raw);
        if (record == null) {
          skipped++;
          continue;
        }
        // 会话已存在则跳过（幂等），避免重复导入。
        if (await RunDatabase.instance.hasSession(record.sessionKey)) {
          skipped++;
          continue;
        }
        final points = <RunPoint>[];
        final ptsRaw = raw['points'];
        if (ptsRaw is List) {
          for (final row in ptsRaw) {
            if (row is! List || row.length < 4) continue;
            points.add(
              RunPoint(
                lat: (row[0] as num).toDouble(),
                lng: (row[1] as num).toDouble(),
                altitude: (row[2] as num?)?.toDouble() ?? 0,
                time: DateTime.fromMillisecondsSinceEpoch(
                  (row[3] as num).toInt(),
                ),
                startsSegment: row.length > 4 && row[4] == true,
                elapsedMs: row.length > 5 ? (row[5] as num?)?.toInt() : null,
              ),
            );
          }
        }
        await RunDatabase.instance.insertRun(record, points);
        imported++;
      } on Object {
        skipped++;
      }
    }
    return RestoreResult(imported: imported, skipped: skipped);
  }

  /// 备份条目 → 记录。缺关键数值字段时返回 null（计入跳过）。
  static RunRecord? _recordFromBackup(Map<String, dynamic> raw) {
    final startMs = raw['start_ms'];
    final endMs = raw['end_ms'];
    final distance = raw['distance_m'];
    final duration = raw['duration_s'];
    if (startMs is! num ||
        endMs is! num ||
        distance is! num ||
        duration is! num) {
      return null;
    }
    final calories = raw['calories'];
    final km = distance.toDouble() / 1000;
    return RunRecord(
      sessionId: raw['session_id'] is String
          ? raw['session_id'] as String
          : null,
      start: DateTime.fromMillisecondsSinceEpoch(startMs.toInt()),
      end: DateTime.fromMillisecondsSinceEpoch(endMs.toInt()),
      distanceM: distance.toDouble(),
      durationS: duration.toInt(),
      calories: calories is num ? calories.toInt() : (km * 65 * 1.036).round(),
      climbM: raw['climb_m'] is num ? (raw['climb_m'] as num).toDouble() : 0,
      source: raw['source'] is String
          ? raw['source'] as String
          : RunRecord.sourceGps,
      title: raw['title'] is String ? raw['title'] as String : '',
      notes: raw['notes'] is String ? raw['notes'] as String : '',
    );
  }

  static Future<void> _restorePrefs(Object? prefsRaw) async {
    if (prefsRaw is! Map) return;
    final sp = await SharedPreferences.getInstance();
    final weekly = prefsRaw['weekly_goal_km'];
    if (weekly is num && Prefs.validGoal(weekly.toDouble())) {
      await sp.setDouble('weekly_goal_km', weekly.toDouble());
      Prefs.instance.weeklyGoalKm = weekly.toDouble();
    }
    final yearly = prefsRaw['yearly_goal_km'];
    if (yearly is num && Prefs.validGoal(yearly.toDouble())) {
      await sp.setDouble('yearly_goal_km', yearly.toDouble());
      Prefs.instance.yearlyGoalKm = yearly.toDouble();
    }
    final autoPause = prefsRaw['auto_pause_enabled'];
    if (autoPause is bool) {
      await sp.setBool('auto_pause_enabled', autoPause);
      Prefs.instance.autoPauseEnabled = autoPause;
    }
    final voice = prefsRaw['voice_announce_enabled'];
    if (voice is bool) {
      await sp.setBool('voice_announce_enabled', voice);
      Prefs.instance.voiceEnabled = voice;
    }
  }
}

class RestoreResult {
  final int imported;
  final int skipped;
  const RestoreResult({required this.imported, required this.skipped});
}

class BackupFormatException implements Exception {
  const BackupFormatException();
}
