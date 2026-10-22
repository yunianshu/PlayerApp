import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/training_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('feedback persists independently per training day', () async {
    await TrainingFeedbackService.save('2026-11-01', pain: 2, fatigue: 4);
    await TrainingFeedbackService.save('2026-11-02', pain: 5, fatigue: 7);
    final all = await TrainingFeedbackService.all();
    expect(all['2026-11-01'], {'pain': 2, 'fatigue': 4});
    expect(all['2026-11-02'], {'pain': 5, 'fatigue': 7});
  });

  test('feedback rejects invalid values', () async {
    expect(
      () => TrainingFeedbackService.save('2026-11-01', pain: 11, fatigue: 0),
      throwsArgumentError,
    );
  });

  test('advisory prioritizes pain', () {
    expect(TrainingFeedbackService.advisory(4, 8), contains('疼痛'));
    expect(TrainingFeedbackService.advisory(0, 8), contains('疲劳'));
  });
}
