import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Reusable schema for 5K/10K/half/full/custom plans.
class TrainingPlanCatalog {
  static const _key = 'training_plan_catalog_v1';
  static const _active = 'training_plan_active_v1';

  static Future<List<Map<String, dynamic>>> plans() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static void validate(Map<String, dynamic> plan) {
    final id = plan['id'];
    final name = plan['name'];
    final distance = plan['raceDistanceKm'];
    final days = plan['tasks'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty ||
        distance is! num || distance <= 0 || days is! List || days.isEmpty) {
      throw const FormatException('训练计划缺少必要字段');
    }
    final seen = <String>{};
    for (final value in days) {
      if (value is! Map) throw const FormatException('训练任务格式不正确');
      final date = value['date'];
      final km = value['km'];
      if (date is! String || DateTime.tryParse(date) == null ||
          !seen.add(date) || km is! num || !km.isFinite || km < 0 ||
          km > 100) {
        throw const FormatException('训练任务日期或距离无效');
      }
    }
  }

  static Future<void> importJson(String source) async {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('训练计划必须是JSON对象');
    }
    validate(value);
    final p = await SharedPreferences.getInstance();
    final current = await plans();
    current.removeWhere((item) => item['id'] == value['id']);
    current.add(value);
    if (!await p.setString(_key, jsonEncode(current))) {
      throw StateError('训练计划保存失败');
    }
  }

  static Future<void> activate(String id) async {
    final exists = (await plans()).any((item) => item['id'] == id);
    if (!exists) throw StateError('训练计划不存在');
    if (!await (await SharedPreferences.getInstance()).setString(_active, id)) {
      throw StateError('激活训练计划失败');
    }
  }

  static Future<Map<String, dynamic>?> activePlan() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_active);
    if (id == null) return null;
    for (final item in await plans()) {
      if (item['id'] == id) return item;
    }
    return null;
  }
}
