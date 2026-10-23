import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/ai_plan_generator.dart';
import 'package:runtrail/services/training_plan_catalog.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/services/training_feedback_service.dart';

Map<String, dynamic> _custom() => {
  'id': 'synthetic-race',
  'name': '合成测试赛事',
  'raceDistanceKm': 42.195,
  'raceDate': '2027-02-05',
  'tasks': [
    for (var day = 1; day <= 5; day++)
      {
        'date': '2027-02-0$day',
        'type': day == 5 ? 'RACE' : 'EASY',
        'title': day == 5 ? '比赛' : '轻松跑',
        'notes': '合成测试数据',
        'km': day == 5 ? 42.195 : 4.0,
        'easyPace': null,
        'slowPace': null,
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final useBuiltIn in [true, false]) {
    test(
      'parse and persist ${useBuiltIn ? 'built-in' : 'created'} adjustment preserves protected days, history and isolation',
      () async {
        await TrainingPlanCatalog.addDraft(_custom());
        final id = useBuiltIn
            ? TrainingPlanCatalog.builtInId
            : 'synthetic-race';
        final otherId = useBuiltIn
            ? 'synthetic-race'
            : TrainingPlanCatalog.builtInId;
        await TrainingPlanCatalog.activate(id);
        final original = await TrainingPlanCatalog.plan(id);
        final otherBefore = await TrainingPlanCatalog.plan(otherId);
        final tasks = (original['tasks'] as List).cast<Map<String, dynamic>>();
        final now = DateTime.parse(tasks.first['date'] as String);
        final completedDay = tasks[1]['date'] as String;
        final candidate = tasks
            .skip(2)
            .firstWhere(
              (task) => task['type'] != 'RACE' && (task['km'] as num) > 0,
            );
        await MarathonTrainingService.setComplete(
          completedDay,
          true,
          planId: id,
        );
        await TrainingFeedbackService.save(
          completedDay,
          pain: 1,
          fatigue: 6,
          planId: id,
        );
        await TrainingFeedbackService.save(
          completedDay,
          pain: 0,
          fatigue: 2,
          planId: otherId,
        );
        final completed = await MarathonTrainingService.completed(planId: id);
        final feedback = await TrainingFeedbackService.all(planId: id);
        final draft = AiPlanGenerator.parseAdjustment(
          jsonEncode({
            'schemaVersion': 1,
            'summary': '合成测试：下调为恢复日',
            'warnings': <String>[],
            'changes': [
              {
                'date': candidate['date'],
                'type': 'REST',
                'km': 0,
                'easyPace': null,
                'slowPace': null,
                'notes': '恢复休息，不补跑',
              },
            ],
          }),
          existingPlan: original,
          now: now,
          completed: completed,
        );
        await TrainingPlanCatalog.applyFutureRevision(
          planId: id,
          expectedRevision: 0,
          tasks: (draft.plan['tasks'] as List).cast<Map<String, dynamic>>(),
          now: now,
          completedSnapshot: completed,
          expectedFeedbackSnapshot: feedback,
          reason: draft.summary,
        );
        final saved = await TrainingPlanCatalog.plan(id);
        expect(saved['revision'], 1);
        final updated = (saved['tasks'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < tasks.length; i++) {
          if (tasks[i]['date'] != candidate['date']) {
            expect(updated[i], tasks[i]);
          }
        }
        final changed = updated.firstWhere(
          (t) => t['date'] == candidate['date'],
        );
        expect(changed['type'], 'REST');
        expect(changed['km'], 0);
        expect(changed['easyPace'], isNull);
        expect(changed['slowPace'], isNull);
        expect((saved['history'] as List).single['plan']['tasks'], tasks);
        expect(await TrainingPlanCatalog.plan(otherId), otherBefore);
        expect(await MarathonTrainingService.completed(planId: id), completed);
        expect(
          await MarathonTrainingService.completed(planId: otherId),
          isEmpty,
        );
        expect(await TrainingFeedbackService.all(planId: id), feedback);
        expect(
          (await TrainingFeedbackService.all(
            planId: otherId,
          ))[completedDay]!['fatigue'],
          2,
        );
        await expectLater(
          TrainingPlanCatalog.applyFutureRevision(
            planId: id,
            expectedRevision: 0,
            tasks: (draft.plan['tasks'] as List).cast<Map<String, dynamic>>(),
            now: now,
            completedSnapshot: completed,
          ),
          throwsStateError,
        );
        expect((await TrainingPlanCatalog.plan(id))['revision'], 1);
      },
    );
  }
}
