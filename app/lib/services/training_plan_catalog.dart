import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local plan catalog. Each catalog mutation is committed as one preferences value.
/// The bundled plan remains available; its original asset and legacy records are
/// never deleted or overwritten when another race is created.
class TrainingPlanCatalog {
  static const builtInId = 'xiamen-marathon-2027';
  static const _envelope = 'training_plan_catalog_v2';
  static Future<void> _work = Future<void>.value();

  static Future<T> serialized<T>(Future<T> Function() action) {
    final result = _work.then((_) => action());
    _work = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  static String scopedKey(String legacyKey, String id) =>
      id == builtInId ? legacyKey : '$legacyKey:${Uri.encodeComponent(id)}';

  static Future<Map<String, dynamic>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_envelope);
    if (raw != null) {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['plans'] is! List) {
        throw const FormatException('训练计划目录损坏，未覆盖已有数据');
      }
      return data;
    }
    final old = prefs.getString('training_plan_catalog_v1');
    final plans = old == null ? <dynamic>[] : jsonDecode(old) as List;
    return {
      'plans': plans,
      'active': prefs.getString('training_plan_active_v1') ?? builtInId,
    };
  }

  static Future<void> _write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (!await prefs.setString(_envelope, jsonEncode(value))) {
        throw StateError('训练计划保存失败');
      }
    } catch (_) {
      // Preferences caches attempted writes before platform persistence finishes.
      // Refresh on failure so readers do not mistake that cache for a commit.
      await prefs.reload();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _builtIn() async {
    final value = jsonDecode(
      await rootBundle.loadString('assets/training/xiamen_marathon_2027.json'),
    ) as Map<String, dynamic>;
    return {...value, 'raceDistanceKm': 42.195, 'revision': 0};
  }

  static Future<List<Map<String, dynamic>>> plans() async {
    final saved = (await _read())['plans'] as List;
    final result = saved
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!result.any((p) => p['id'] == builtInId)) {
      result.insert(0, await _builtIn());
    }
    return result;
  }

  static Future<String> activeId() async {
    final id = (await _read())['active'];
    return id is String && (await plans()).any((p) => p['id'] == id)
        ? id
        : builtInId;
  }

  static Future<Map<String, dynamic>> plan(String id) async =>
      (await plans()).firstWhere(
        (p) => p['id'] == id,
        orElse: () => throw StateError('训练计划不存在'),
      );

  static Future<Map<String, dynamic>> activePlan() async =>
      plan(await activeId());
  static Future<int> revision(String id) async =>
      (await plan(id))['revision'] as int? ?? 0;

  static DateTime strictDate(String value) {
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('日期必须为有效的 YYYY-MM-DD');
    }
    return date;
  }

  static void validate(Map<String, dynamic> plan) {
    final id = plan['id'];
    final name = plan['name'];
    final distance = plan['raceDistanceKm'];
    final days = plan['tasks'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 200 ||
        name is! String ||
        name.trim().isEmpty ||
        distance is! num ||
        !distance.isFinite ||
        distance <= 0 ||
        days is! List ||
        days.isEmpty ||
        days.length > 732) {
      throw const FormatException('训练计划缺少必要字段');
    }
    final seen = <String>{};
    for (final value in days) {
      if (value is! Map) throw const FormatException('训练任务格式不正确');
      final date = value['date'];
      final km = value['km'];
      if (date is! String ||
          !seen.add(date) ||
          km is! num ||
          !km.isFinite ||
          km < 0 ||
          km > 100 ||
          value['type'] is! String ||
          value['title'] is! String ||
          value['notes'] is! String) {
        throw const FormatException('训练任务日期、内容或距离无效');
      }
      strictDate(date);
      for (final key in ['easyPace', 'slowPace']) {
        final pace = value[key];
        if (pace != null && (pace is! int || pace <= 0)) {
          throw const FormatException('配速单位应为秒/公里');
        }
      }
    }
    if (plan['raceDate'] != null) strictDate(plan['raceDate'] as String);
  }

  static Future<void> importJson(String source) async {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('训练计划必须是JSON对象');
    }
    await addDraft(value);
  }

  /// Called only after the user's preview confirmation. Does not activate it.
  static Future<void> addDraft(Map<String, dynamic> value) =>
      serialized(() async {
        validate(value);
        if ((await plans()).any((p) => p['id'] == value['id'])) {
          throw StateError('计划 ID 已存在，不能覆盖已有记录');
        }
        final data = await _read();
        (data['plans'] as List).add({
          ...value,
          'revision': 0,
          'history': <dynamic>[],
        });
        await _write(data);
      });

  static Future<void> activate(String id) => serialized(() async {
    await plan(id);
    final data = await _read();
    data['active'] = id;
    await _write(data);
  });

  static Future<List<Map<String, dynamic>>> history(String id) async =>
      ((await plan(id))['history'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  /// Atomically saves revised future tasks and the prior plan in the same value.
  /// Rechecks revision, active plan, and completed dates to reject stale previews.
  static Future<void> applyFutureRevision({
    required String planId,
    required int expectedRevision,
    required List<Map<String, dynamic>> tasks,
    required DateTime now,
    required Set<String> completedSnapshot,
    Map<String, Map<String, int>>? expectedFeedbackSnapshot,
    String reason = '',
  }) => serialized(() async {
    if (await activeId() != planId) throw StateError('当前计划已切换，请重新生成调整建议');
    final current = await plan(planId);
    if ((current['revision'] as int? ?? 0) != expectedRevision) {
      throw StateError('计划已更新，请重新生成调整建议');
    }
    final prefs = await SharedPreferences.getInstance();
    final completed =
        (prefs.getStringList(scopedKey('training-complete-v1', planId)) ?? [])
            .toSet();
    if (completed.length != completedSnapshot.length ||
        !completed.containsAll(completedSnapshot)) {
      throw StateError('完成状态已变化，请重新生成调整建议');
    }
    if (expectedFeedbackSnapshot != null) {
      final feedbackRaw = prefs.getString(
        scopedKey('marathon_training_feedback_v1', planId),
      );
      final feedback = feedbackRaw == null
          ? <String, dynamic>{}
          : jsonDecode(feedbackRaw);
      if (!_same(feedback, expectedFeedbackSnapshot)) {
        throw StateError('训练反馈已变化，请重新生成调整建议');
      }
    }
    // Fold pre-v2 distance-only adjustments into the first full revision.
    if ((current['revision'] as int? ?? 0) == 0) {
      final raw = prefs.getString(
        scopedKey('adaptive_training_revision_v1', planId),
      );
      if (raw != null) {
        final overrides = jsonDecode(raw) as Map<String, dynamic>;
        current['tasks'] = (current['tasks'] as List)
            .map(
              (t) => {
                ...Map<String, dynamic>.from(t as Map),
                if (overrides.containsKey(t['date']))
                  'km': overrides[t['date']],
              },
            )
            .toList();
      }
    }
    final next = {...current, 'tasks': tasks};
    validate(next);
    final oldTasks = {
      for (final v in current['tasks'] as List) (v as Map)['date'] as String: v,
    };
    final newTasks = {for (final v in tasks) v['date'] as String: v};
    if (oldTasks.length != newTasks.length ||
        !oldTasks.keys.every(newTasks.containsKey)) {
      throw StateError('调整不能新增或删除训练日期');
    }
    final today = DateTime(now.year, now.month, now.day);
    for (final entry in oldTasks.entries) {
      if (!strictDate(entry.key).isAfter(today) ||
          completed.contains(entry.key) ||
          entry.value['type'] == 'RACE') {
        if (!_same(entry.value, newTasks[entry.key])) {
          throw StateError('不能修改今天、过去、已完成或比赛日安排');
        }
      }
    }
    final previous = Map<String, dynamic>.from(current)..remove('history');
    next['history'] = [
      ...(current['history'] as List? ?? []),
      {'at': now.toIso8601String(), 'reason': reason, 'plan': previous},
    ];
    next['revision'] = expectedRevision + 1;
    final data = await _read();
    final list = data['plans'] as List;
    list.removeWhere((p) => (p as Map)['id'] == planId);
    list.add(next);
    await _write(data);
  });

  static bool _same(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
    }
    return a == b;
  }
}
