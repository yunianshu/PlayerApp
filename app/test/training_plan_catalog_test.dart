import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:runtrail/services/training_plan_catalog.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/services/training_feedback_service.dart';
import 'package:runtrail/services/adaptive_training_service.dart';

class _FailedWrite extends InMemorySharedPreferencesStore {
  _FailedWrite() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

Map<String, dynamic> task(String date, {double km = 4, String type = 'EASY'}) =>
    {'date': date, 'type': type, 'title': '训练', 'notes': '轻松', 'km': km};
Map<String, dynamic> example(String id) => {
  'id': id,
  'name': '其他马拉松',
  'raceDistanceKm': 42.195,
  'raceDate': '2027-02-03',
  'tasks': [
    task('2027-02-01'),
    task('2027-02-02'),
    task('2027-02-03', km: 42.195, type: 'RACE'),
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'failed completion and feedback writes restore persisted cache',
    () async {
      SharedPreferencesStorePlatform.instance = _FailedWrite();
      SharedPreferences.resetStatic();
      await expectLater(
        MarathonTrainingService.setComplete(
          '2027-01-01',
          true,
          planId: TrainingPlanCatalog.builtInId,
        ),
        throwsStateError,
      );
      expect(
        await MarathonTrainingService.completed(
          planId: TrainingPlanCatalog.builtInId,
        ),
        isEmpty,
      );
      await expectLater(
        TrainingFeedbackService.save(
          '2027-01-01',
          pain: 0,
          fatigue: 4,
          planId: TrainingPlanCatalog.builtInId,
        ),
        throwsStateError,
      );
      expect(
        await TrainingFeedbackService.all(
          planId: TrainingPlanCatalog.builtInId,
        ),
        isEmpty,
      );
    },
  );
  test(
    'bundled plan remains accessible and default; new plan inactive',
    () async {
      expect(
        await TrainingPlanCatalog.activeId(),
        TrainingPlanCatalog.builtInId,
      );
      await TrainingPlanCatalog.addDraft(example('other'));
      expect((await TrainingPlanCatalog.plans()).length, 2);
      expect(
        await TrainingPlanCatalog.activeId(),
        TrainingPlanCatalog.builtInId,
      );
      await TrainingPlanCatalog.activate('other');
      expect((await MarathonTrainingService.load()).first.date, '2027-02-01');
      await TrainingPlanCatalog.activate(TrainingPlanCatalog.builtInId);
      expect((await MarathonTrainingService.load()).length, 80);
    },
  );
  test('legacy completion and feedback kept, custom plans isolated', () async {
    SharedPreferences.setMockInitialValues({
      'training-complete-v1': ['2027-02-01'],
      'marathon_training_feedback_v1': jsonEncode({
        '2027-02-01': {'pain': 2, 'fatigue': 3},
      }),
    });
    await TrainingPlanCatalog.addDraft(example('other'));
    await TrainingPlanCatalog.activate('other');
    expect(await MarathonTrainingService.completed(), isEmpty);
    expect(await TrainingFeedbackService.all(), isEmpty);
    await MarathonTrainingService.setComplete('2027-02-02', true);
    await TrainingFeedbackService.save('2027-02-01', pain: 1, fatigue: 1);
    await TrainingPlanCatalog.activate(TrainingPlanCatalog.builtInId);
    expect(await MarathonTrainingService.completed(), {'2027-02-01'});
    expect((await TrainingFeedbackService.all())['2027-02-01']!['pain'], 2);
  });
  test('duplicate plan rejected without erasing original', () async {
    await TrainingPlanCatalog.addDraft(example('other'));
    await expectLater(
      TrainingPlanCatalog.addDraft({...example('other'), 'name': '覆盖'}),
      throwsStateError,
    );
    expect((await TrainingPlanCatalog.plan('other'))['name'], '其他马拉松');
  });
  test(
    'v1 custom catalog and selected ID migrate on next atomic mutation',
    () async {
      SharedPreferences.setMockInitialValues({
        'training_plan_catalog_v1': jsonEncode([example('old')]),
        'training_plan_active_v1': 'old',
      });
      expect(await TrainingPlanCatalog.activeId(), 'old');
      await TrainingPlanCatalog.addDraft(example('new'));
      expect(await TrainingPlanCatalog.activeId(), 'old');
      expect((await TrainingPlanCatalog.plans()).length, 3);
      expect(
        (await SharedPreferences.getInstance()).containsKey(
          'training_plan_catalog_v1',
        ),
        isTrue,
      );
    },
  );
  test('concurrent saves and completion writes do not lose records', () async {
    await Future.wait([
      TrainingPlanCatalog.addDraft(example('a')),
      TrainingPlanCatalog.addDraft(example('b')),
    ]);
    await TrainingPlanCatalog.activate('a');
    await Future.wait([
      MarathonTrainingService.setComplete('2027-02-01', true),
      MarathonTrainingService.setComplete('2027-02-02', true),
    ]);
    expect(await MarathonTrainingService.completed(), {
      '2027-02-01',
      '2027-02-02',
    });
    expect((await TrainingPlanCatalog.plans()).length, 3);
  });
  test(
    'revision atomic history, stale preview, today/completed/race protection',
    () async {
      await TrainingPlanCatalog.addDraft(example('a'));
      await TrainingPlanCatalog.activate('a');
      Future<void> apply(
        List<Map<String, dynamic>> tasks, {
        int rev = 0,
        Set<String> done = const {},
      }) => TrainingPlanCatalog.applyFutureRevision(
        planId: 'a',
        expectedRevision: rev,
        tasks: tasks,
        now: DateTime(2027, 2, 1),
        completedSnapshot: done,
        reason: '恢复',
      );
      final original = (example('a')['tasks'] as List)
          .cast<Map<String, dynamic>>();
      await expectLater(
        apply([task('2027-02-01', km: 2), ...original.skip(1)]),
        throwsStateError,
      );
      await MarathonTrainingService.setComplete('2027-02-02', true);
      await expectLater(apply(original), throwsStateError);
      await expectLater(
        apply(
          [original[0], task('2027-02-02', km: 2), original[2]],
          done: {'2027-02-02'},
        ),
        throwsStateError,
      );
      await MarathonTrainingService.setComplete('2027-02-02', false);
      await apply([original[0], task('2027-02-02', km: 2), original[2]]);
      expect(await TrainingPlanCatalog.revision('a'), 1);
      expect((await TrainingPlanCatalog.history('a')).single['reason'], '恢复');
      expect((await MarathonTrainingService.load())[1].km, 2);
      await expectLater(apply(original), throwsStateError);
    },
  );
  test(
    'old overrides folded into revision then no longer override AI tasks',
    () async {
      await TrainingPlanCatalog.addDraft(example('a'));
      await TrainingPlanCatalog.activate('a');
      await (await SharedPreferences.getInstance()).setString(
        TrainingPlanCatalog.scopedKey('adaptive_training_revision_v1', 'a'),
        jsonEncode({'2027-02-01': 2, '2027-02-02': 3}),
      );
      await TrainingPlanCatalog.applyFutureRevision(
        planId: 'a',
        expectedRevision: 0,
        tasks: [
          task('2027-02-01', km: 2),
          task('2027-02-02', km: 1),
          task('2027-02-03', km: 42.195, type: 'RACE'),
        ],
        now: DateTime(2027, 2, 1),
        completedSnapshot: {},
      );
      expect((await AdaptiveTrainingService.effectiveTasks())[1].km, 1);
      expect((await AdaptiveTrainingService.effectiveTasks())[0].km, 2);
    },
  );
  test(
    'feedback changes queued before apply reject stale preview atomically',
    () async {
      await TrainingPlanCatalog.addDraft(example('a'));
      await TrainingPlanCatalog.activate('a');
      final snapshot = await TrainingFeedbackService.all(planId: 'a');
      final changed = TrainingFeedbackService.save(
        '2027-02-01',
        pain: 4,
        fatigue: 5,
        planId: 'a',
      );
      final apply = TrainingPlanCatalog.applyFutureRevision(
        planId: 'a',
        expectedRevision: 0,
        tasks: (example('a')['tasks'] as List).cast<Map<String, dynamic>>(),
        now: DateTime(2027, 2, 1),
        completedSnapshot: {},
        expectedFeedbackSnapshot: snapshot,
      );
      await expectLater(apply, throwsStateError);
      await changed;
      expect(await TrainingPlanCatalog.revision('a'), 0);
      expect(await TrainingPlanCatalog.history('a'), isEmpty);
      await TrainingPlanCatalog.applyFutureRevision(
        planId: 'a',
        expectedRevision: 0,
        tasks: (example('a')['tasks'] as List).cast<Map<String, dynamic>>(),
        now: DateTime(2027, 2, 1),
        completedSnapshot: {},
        expectedFeedbackSnapshot: await TrainingFeedbackService.all(
          planId: 'a',
        ),
      );
      expect(await TrainingPlanCatalog.revision('a'), 1);
    },
  );
  test(
    'local adjustment preserves null fields and skips completed future days',
    () async {
      final days = [
        for (final date in [
          '2027-01-31',
          '2027-02-01',
          '2027-02-02',
          '2027-02-03',
        ])
          {...task(date), 'easyPace': null, 'slowPace': null},
        {
          ...task('2027-02-04', km: 42.195, type: 'RACE'),
          'easyPace': null,
          'slowPace': null,
        },
      ];
      await TrainingPlanCatalog.addDraft({
        ...example('a'),
        'raceDate': '2027-02-04',
        'tasks': days,
      });
      await TrainingPlanCatalog.activate('a');
      await MarathonTrainingService.setComplete(
        '2027-02-02',
        true,
        planId: 'a',
      );
      await TrainingFeedbackService.save(
        '2027-01-31',
        pain: 4,
        fatigue: 2,
        planId: 'a',
      );
      final proposal = await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {},
      );
      expect(proposal, isNotNull);
      expect((proposal!['changes'] as List).single['date'], '2027-02-03');
      await AdaptiveTrainingService.apply(proposal, now: DateTime(2027, 2, 1));
      final saved = (await TrainingPlanCatalog.plan('a'))['tasks'] as List;
      for (final index in [0, 1, 2, 4]) {
        expect(saved[index], days[index]);
      }
      expect(saved[3]['type'], 'REST');
      expect(saved[3]['title'], '恢复休息');
      expect(saved[3]['km'], 0);
      expect(saved[3]['easyPace'], isNull);
      expect(saved[3]['slowPace'], isNull);
      await expectLater(
        AdaptiveTrainingService.apply(proposal, now: DateTime(2027, 2, 1)),
        throwsStateError,
      );
      expect(await TrainingPlanCatalog.revision('a'), 1);
    },
  );
  test(
    'local adjustment rejects stale revision even with unchanged distances',
    () async {
      final days = [task('2027-01-31'), ...(example('a')['tasks'] as List)];
      await TrainingPlanCatalog.addDraft({...example('a'), 'tasks': days});
      await TrainingPlanCatalog.activate('a');
      final proposal = await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {'2027-01-31': 0}, // Explicit zero, not missing history.
      );
      await TrainingPlanCatalog.applyFutureRevision(
        planId: 'a',
        expectedRevision: 0,
        tasks: days.cast<Map<String, dynamic>>(),
        now: DateTime(2027, 2, 1),
        completedSnapshot: {},
      );
      await expectLater(
        AdaptiveTrainingService.apply(proposal!, now: DateTime(2027, 2, 1)),
        throwsStateError,
      );
      expect(await TrainingPlanCatalog.revision('a'), 1);
    },
  );
  test('strict dates reject overflow and malformed fields', () {
    expect(
      () => TrainingPlanCatalog.strictDate('2027-02-30'),
      throwsFormatException,
    );
    expect(
      () => TrainingPlanCatalog.strictDate('2027-2-01'),
      throwsFormatException,
    );
    expect(
      () => TrainingPlanCatalog.validate({
        ...example('a'),
        'tasks': [task('2027-02-30')],
      }),
      throwsFormatException,
    );
  });
}
