import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'marathon_training_service.dart';
import 'training_feedback_service.dart';

/// Generic plan revisions. Never overwrite the source plan.
class AdaptiveTrainingService {
  static const _revisionKey = 'adaptive_training_revision_v1';
  static const _historyKey = 'adaptive_training_history_v1';

  static Future<Map<String, double>> overrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_revisionKey);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((date, value) => MapEntry(date, (value as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<List<TrainingTask>> effectiveTasks() async {
    final base = await MarathonTrainingService.load();
    final edited = await overrides();
    return base.map((t) => TrainingTask(
      t.date, t.type, t.title, edited[t.date] ?? t.km, t.notes,
      easyPace: t.easyPace, slowPace: t.slowPace,
    )).toList();
  }

  static Future<Map<String, dynamic>?> suggest({
    required DateTime now,
    required Map<String, double> actualKm,
  }) async {
    final tasks = await effectiveTasks();
    final feedback = await TrainingFeedbackService.all();
    final today = DateTime(now.year, now.month, now.day);
    final lastWeekStart = today.subtract(const Duration(days: 7));
    final recent = tasks.where((t) {
      final day = DateTime.parse(t.date);
      return !day.isBefore(lastWeekStart) && day.isBefore(today);
    }).toList();
    final planned = recent.fold<double>(0, (sum, t) => sum + t.km);
    final actual = recent.fold<double>(0, (sum, t) => sum + (actualKm[t.date] ?? 0));
    final recentScores = recent.map((t) => feedback[t.date]).whereType<Map<String, int>>();
    final maxPain = recentScores.fold<int>(0, (v, item) => item['pain']! > v ? item['pain']! : v);
    final maxFatigue = recentScores.fold<int>(0, (v, item) => item['fatigue']! > v ? item['fatigue']! : v);
    // Any risk or missed mileage calls for conservative changes; never add missed miles.
    final ratio = planned > 0 ? actual / planned : 1.0;
    final factor = maxPain >= 4 ? 0.0 : maxFatigue >= 7 ? 0.7 : ratio < 0.7 ? 0.8 : ratio < 0.9 ? 0.9 : 1.0;
    if (factor == 1) return null;
    final candidates = tasks.where((t) {
      final day = DateTime.parse(t.date);
      return day.isAfter(today) && !day.isAfter(today.add(const Duration(days: 7))) &&
          t.type != 'RACE' && t.km > 0;
    }).toList();
    final changes = candidates.map((t) => {
      'date': t.date, 'from': t.km,
      'to': double.parse((t.km * factor).toStringAsFixed(1)),
    }).toList();
    if (changes.isEmpty) return null;
    return {
      'factor': factor, 'actualKm': actual, 'plannedKm': planned,
      'maxPain': maxPain, 'maxFatigue': maxFatigue,
      'reason': maxPain >= 4 ? '疼痛评分偏高，暂停未来7天跑步建议并评估伤痛' :
          maxFatigue >= 7 ? '近期疲劳偏高，建议降低训练负荷' :
          '近期实际跑量低于计划，建议暂缓加量',
      'changes': changes,
    };
  }

  static Future<void> apply(Map<String, dynamic> proposal) async {
    final current = await overrides();
    final base = await MarathonTrainingService.load();
    final byDate = {for (final task in base) task.date: task};
    final changes = (proposal['changes'] as List).cast<Map<String, dynamic>>();
    for (final change in changes) {
      final date = change['date'] as String;
      final task = byDate[date];
      final next = (change['to'] as num).toDouble();
      if (task == null || task.type == 'RACE' || next < 0 ||
          next > task.km || DateTime.parse(date).isBefore(DateTime.now())) {
        throw StateError('调整方案未通过本地安全验证');
      }
      current[date] = next;
    }
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? <String>[];
    final revision = jsonEncode({
      'at': DateTime.now().toIso8601String(),
      'reason': proposal['reason'],
      'changes': changes,
    });
    if (!await prefs.setString(_revisionKey, jsonEncode(current))) {
      throw StateError('保存计划失败');
    }
    if (!await prefs.setStringList(_historyKey, [...history, revision])) {
      throw StateError('保存调整历史失败');
    }
  }

  static Future<List<String>> history() async =>
      (await SharedPreferences.getInstance()).getStringList(_historyKey) ?? [];
}
