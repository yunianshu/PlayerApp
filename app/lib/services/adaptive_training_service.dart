import 'dart:convert';

import 'training_plan_catalog.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'marathon_training_service.dart';
import 'training_feedback_service.dart';

/// Generic plan revisions. Never overwrite the source plan.
class AdaptiveTrainingService {
  static const _revisionKey = 'adaptive_training_revision_v1';
  static const _historyKey = 'adaptive_training_history_v1';

  static Future<Map<String, double>> overrides({String? planId}) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    if (await TrainingPlanCatalog.revision(id) > 0) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
      TrainingPlanCatalog.scopedKey(_revisionKey, id),
    );
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map(
        (date, value) => MapEntry(date, (value as num).toDouble()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<List<TrainingTask>> effectiveTasks({String? planId}) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    final base = await MarathonTrainingService.load(planId: id);
    final edited = await overrides(planId: id);
    return base
        .map(
          (t) => TrainingTask(
            t.date,
            t.type,
            t.title,
            edited[t.date] ?? t.km,
            t.notes,
            easyPace: t.easyPace,
            slowPace: t.slowPace,
          ),
        )
        .toList();
  }

  static Future<Map<String, dynamic>?> suggest({
    required DateTime now,
    required Map<String, double> actualKm,
  }) async {
    final id = await TrainingPlanCatalog.activeId();
    final revision = await TrainingPlanCatalog.revision(id);
    final tasks = await effectiveTasks(planId: id);
    final completed = await MarathonTrainingService.completed(planId: id);
    final feedback = await TrainingFeedbackService.all(planId: id);
    final today = DateTime(now.year, now.month, now.day);
    final lastWeekStart = today.subtract(const Duration(days: 7));
    final recent = tasks.where((t) {
      final day = DateTime.parse(t.date);
      return !day.isBefore(lastWeekStart) && day.isBefore(today);
    }).toList();
    final planned = recent.fold<double>(0, (sum, t) => sum + t.km);
    final actual = recent.fold<double>(
      0,
      (sum, t) => sum + (actualKm[t.date] ?? 0),
    );
    final recentScores = recent
        .map((t) => feedback[t.date])
        .whereType<Map<String, int>>();
    final maxPain = recentScores.fold<int>(
      0,
      (v, item) => item['pain']! > v ? item['pain']! : v,
    );
    final maxFatigue = recentScores.fold<int>(
      0,
      (v, item) => item['fatigue']! > v ? item['fatigue']! : v,
    );
    // Any risk or missed mileage calls for conservative changes; never add missed miles.
    final ratio = planned > 0 ? actual / planned : 1.0;
    final factor = maxPain >= 4
        ? 0.0
        : maxFatigue >= 7
        ? 0.7
        : ratio < 0.7
        ? 0.8
        : ratio < 0.9
        ? 0.9
        : 1.0;
    if (factor == 1) return null;
    final candidates = tasks.where((t) {
      final day = DateTime.parse(t.date);
      return day.isAfter(today) &&
          !day.isAfter(today.add(const Duration(days: 7))) &&
          t.type != 'RACE' &&
          !completed.contains(t.date) &&
          t.km > 0;
    }).toList();
    final changes = candidates
        .map(
          (t) => {
            'date': t.date,
            'from': t.km,
            'to': double.parse((t.km * factor).toStringAsFixed(1)),
          },
        )
        .toList();
    if (changes.isEmpty) return null;
    return {
      'planId': id,
      'revision': revision,
      'completedSnapshot': completed.toList(),
      'feedbackSnapshot': feedback,
      'factor': factor,
      'actualKm': actual,
      'plannedKm': planned,
      'maxPain': maxPain,
      'maxFatigue': maxFatigue,
      'reason': maxPain >= 4
          ? '疼痛评分偏高，暂停未来7天跑步建议并评估伤痛'
          : maxFatigue >= 7
          ? '近期疲劳偏高，建议降低训练负荷'
          : '近期实际跑量低于计划，建议暂缓加量',
      'changes': changes,
    };
  }

  static Future<void> apply(
    Map<String, dynamic> proposal, {
    DateTime? now,
  }) async {
    final id =
        proposal['planId'] as String? ?? await TrainingPlanCatalog.activeId();
    if (id != await TrainingPlanCatalog.activeId()) {
      throw StateError('当前计划已切换，请重新生成建议');
    }
    final revision =
        proposal['revision'] as int? ?? await TrainingPlanCatalog.revision(id);
    final rawPlan = await TrainingPlanCatalog.plan(id);
    final tasks = await effectiveTasks(planId: id);
    final completed = proposal['completedSnapshot'] is List
        ? (proposal['completedSnapshot'] as List).cast<String>().toSet()
        : await MarathonTrainingService.completed(planId: id);
    final feedback =
        proposal['feedbackSnapshot'] as Map<String, Map<String, int>>?;
    final byDate = {for (final task in tasks) task.date: task};
    final changes = (proposal['changes'] as List).cast<Map<String, dynamic>>();
    final replacements = <String, double>{};
    for (final change in changes) {
      final date = change['date'] as String;
      final task = byDate[date];
      final next = (change['to'] as num).toDouble();
      if (task == null ||
          task.type == 'RACE' ||
          !next.isFinite ||
          next < 0 ||
          next > task.km ||
          (change['from'] as num).toDouble() != task.km) {
        throw StateError('调整方案未通过本地安全验证或已过期');
      }
      replacements[date] = next;
    }
    await TrainingPlanCatalog.applyFutureRevision(
      planId: id,
      expectedRevision: revision,
      tasks: (rawPlan['tasks'] as List).map((value) {
        final raw = Map<String, dynamic>.from(value as Map);
        final date = raw['date'] as String;
        final next = replacements[date];
        return <String, dynamic>{
          ...raw,
          'km': next ?? byDate[date]!.km,
          if (next == 0) ...{
            'type': 'REST',
            'title': '恢复休息',
            'easyPace': null,
            'slowPace': null,
          },
        };
      }).toList(),
      now: now ?? DateTime.now(),
      completedSnapshot: completed,
      expectedFeedbackSnapshot: feedback,
      reason: proposal['reason'] as String? ?? '本地保守调整',
    );
  }

  static Future<List<String>> history({String? planId}) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    final newer = await TrainingPlanCatalog.history(id);
    final older =
        (await SharedPreferences.getInstance()).getStringList(
          TrainingPlanCatalog.scopedKey(_historyKey, id),
        ) ??
        [];
    return [...older, ...newer.map(jsonEncode)];
  }
}
