import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/adaptive_training_service.dart';
import 'package:runtrail/services/training_plan_catalog.dart';
import 'package:runtrail/services/training_feedback_service.dart';

import 'training_plan_catalog_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await TrainingPlanCatalog.addDraft({
      ...fixtures.example('coverage'),
      'tasks': [
        fixtures.task('2027-01-30'),
        fixtures.task('2027-01-31'),
        ...(fixtures.example('coverage')['tasks'] as List),
      ],
    });
    await TrainingPlanCatalog.activate('coverage');
  });
  test('missing all records is unknown not low adherence', () async {
    expect(
      await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {},
      ),
      isNull,
    );
  });
  test('partially imported history is not low completion week', () async {
    expect(
      await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {'2027-01-30': 1},
      ),
      isNull,
    );
  });
  test('explicit observed zero differs from absent day', () async {
    final proposal = await AdaptiveTrainingService.suggest(
      now: DateTime(2027, 2, 1),
      actualKm: {'2027-01-30': 0, '2027-01-31': 0},
    );
    expect(proposal, isNotNull);
    expect(proposal!['completeRunCoverage'], true);
    expect(proposal['observedRunDays'], 2);
    expect(proposal['factor'], .8);
  });
  test(
    'reported fatigue supports recovery despite missing activity data',
    () async {
      await TrainingFeedbackService.save(
        '2027-01-31',
        pain: 0,
        fatigue: 8,
        planId: 'coverage',
      );
      final proposal = await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {},
      );
      expect(proposal!['factor'], .7);
      expect(proposal['completeRunCoverage'], false);
      expect(proposal['reason'], contains('疲劳'));
    },
  );
  test('invalid observed values remain unknown', () async {
    expect(
      await AdaptiveTrainingService.suggest(
        now: DateTime(2027, 2, 1),
        actualKm: {'2027-01-30': double.nan, '2027-01-31': -1},
      ),
      isNull,
    );
  });
}
