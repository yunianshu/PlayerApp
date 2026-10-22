import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'training_plan_catalog.dart';

class TrainingTask {
  final String date, type, title, notes;
  final double km;
  final int? easyPace, slowPace;
  const TrainingTask(this.date, this.type, this.title, this.km, this.notes,
      {this.easyPace, this.slowPace});
  factory TrainingTask.fromJson(Map<String, dynamic> j) => TrainingTask(
      j['date'] as String, j['type'] as String, j['title'] as String,
      (j['km'] as num).toDouble(), j['notes'] as String,
      easyPace: j['easyPace'] as int?, slowPace: j['slowPace'] as int?);
  bool get isRun => km > 0;
}

class MarathonTrainingService {
  static const id = 'xiamen-marathon-2027';
  static const _completeKey = 'training-complete-v1';
  static Future<List<TrainingTask>> load() async {
    final active = await TrainingPlanCatalog.activePlan();
    final data = active ?? jsonDecode(
      await rootBundle.loadString('assets/training/xiamen_marathon_2027.json'))
        as Map<String, dynamic>;
    return (data['tasks'] as List)
        .map((e) => TrainingTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  static Future<Set<String>> completed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_completeKey) ?? []).toSet();
  }
  static Future<void> setComplete(String date, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final dates = await completed();
    if (value) { dates.add(date); } else { dates.remove(date); }
    if (!await prefs.setStringList(_completeKey, dates.toList()..sort())) {
      throw StateError('训练状态保存失败');
    }
  }
}
