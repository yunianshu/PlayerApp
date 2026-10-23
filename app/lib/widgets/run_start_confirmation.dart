import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';
import '../services/courses.dart';

enum RunStartChoice { warmup, run }

/// App-local acknowledgement, intentionally not coupled to a particular run.
/// Only an explicit choice acknowledges the advice; barrier/back/close do not.
/// Storage failure propagates to the caller, so no unconfirmed run is started.
Future<RunStartChoice?> showRunStartConfirmation(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return null;
  const key = 'run_warmup_advice_acknowledged';
  final acknowledged = prefs.get(key) == true;
  var resolved = false;
  void finish(BuildContext dialogContext, [RunStartChoice? choice]) {
    if (resolved) return;
    resolved = true;
    Navigator.pop(dialogContext, choice);
  }

  final choice = await showDialog<RunStartChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text((acknowledged ? '是否直接开跑？' : '跑前热身？').tr)),
          IconButton(
            tooltip: '取消'.tr,
            onPressed: () => finish(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: Text(
        acknowledged
            ? '确认后进入开跑倒计时。'.tr
            : LocaleController.instance.isEnglish
            ? 'Wake up joints and muscles first, about '
                  '${warmupCourse.total.inMinutes} min'
            : '先活动关节、唤醒肌肉，约${warmupCourse.total.inMinutes}分钟',
      ),
      actions: [
        // A row preserves the requested physical left/right ordering, including
        // large text sizes where AlertDialog's default OverflowBar would stack.
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: const ValueKey('run-start-warmup'),
                onPressed: () => finish(context, RunStartChoice.warmup),
                child: Text('热身'.tr, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const ValueKey('run-start-direct'),
                onPressed: () => finish(context, RunStartChoice.run),
                child: Text('开跑'.tr, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  if (choice != null && !acknowledged) {
    try {
      if (!await prefs.setBool(key, true)) {
        throw StateError('无法保存热身提醒偏好');
      }
    } catch (_) {
      // The preferences plugin updates its cache before reporting write failure.
      await prefs.reload();
      rethrow;
    }
  }
  return choice;
}
