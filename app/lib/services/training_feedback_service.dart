import 'dart:convert';

import 'training_plan_catalog.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// Recovery feedback stays on device; it never changes planned mileage silently.
class TrainingFeedbackService {
  static const _key = 'marathon_training_feedback_v1';
  static Future<Map<String, Map<String, int>>> all({String? planId}) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(TrainingPlanCatalog.scopedKey(_key, id));
    if (raw == null) return {};
    try {
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      return obj.map(
        (key, value) => MapEntry(key, Map<String, int>.from(value as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(
    String date, {
    required int pain,
    required int fatigue,
    String? planId,
  }) async {
    final id = planId ?? await TrainingPlanCatalog.activeId();
    if (pain < 0 || pain > 10 || fatigue < 0 || fatigue > 10) {
      throw ArgumentError('疼痛或疲劳分值无效');
    }
    await TrainingPlanCatalog.serialized(() async {
      TrainingPlanCatalog.strictDate(date);
      final p = await SharedPreferences.getInstance();
      final data = await all(planId: id);
      data[date] = {'pain': pain, 'fatigue': fatigue};
      try {
        if (!await p.setString(
          TrainingPlanCatalog.scopedKey(_key, id),
          jsonEncode(data),
        )) {
          throw StateError('训练反馈保存失败');
        }
      } catch (_) {
        await p.reload();
        rethrow;
      }
    });
  }

  static String advisory(int pain, int fatigue) {
    if (pain >= 4) return '疼痛达到4分或以上：停止增加跑量；若持续或影响步态，暂停跑步并考虑就医。';
    if (fatigue >= 7) return '疲劳偏高：建议减少下一次训练量，不补跑遗漏公里。';
    return '正常记录恢复状况，继续根据体感调整训练。';
  }
}
