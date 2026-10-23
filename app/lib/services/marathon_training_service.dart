import 'package:shared_preferences/shared_preferences.dart';

import 'training_plan_catalog.dart';

class TrainingTask {
  final String date, type, title, notes;
  final double km;
  final int? easyPace, slowPace;
  const TrainingTask(
    this.date,
    this.type,
    this.title,
    this.km,
    this.notes, {
    this.easyPace,
    this.slowPace,
  });
  factory TrainingTask.fromJson(Map<String, dynamic> j) => TrainingTask(
    j['date'] as String,
    j['type'] as String,
    j['title'] as String,
    (j['km'] as num).toDouble(),
    j['notes'] as String,
    easyPace: j['easyPace'] as int?,
    slowPace: j['slowPace'] as int?,
  );
  bool get isRun => km > 0;
}

class MarathonTrainingService {
  static const id = 'xiamen-marathon-2027';
  static const _completeKey = 'training-complete-v1';
  static Future<List<TrainingTask>> load({String? planId}) async {
    final data = await TrainingPlanCatalog.plan(
      planId ?? await TrainingPlanCatalog.activeId(),
    );
    return (data['tasks'] as List)
        .map((e) => TrainingTask.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<Set<String>> completed({String? planId}) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(
              TrainingPlanCatalog.scopedKey(_completeKey, id),
            ) ??
            [])
        .toSet();
  }

  static Future<void> setComplete(
    String date,
    bool value, {
    String? planId,
  }) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    await TrainingPlanCatalog.serialized(() async {
      TrainingPlanCatalog.strictDate(date);
      final prefs = await SharedPreferences.getInstance();
      final dates = await completed(planId: id);
      if (value) {
        dates.add(date);
      } else {
        dates.remove(date);
      }
      try {
        if (!await prefs.setStringList(
          TrainingPlanCatalog.scopedKey(_completeKey, id),
          dates.toList()..sort(),
        )) {
          throw StateError('训练状态保存失败');
        }
      } catch (_) {
        await prefs.reload();
        rethrow;
      }
    });
  }
}
