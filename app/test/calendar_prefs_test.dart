import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/calendar.dart';
import 'package:runtrail/core/prefs.dart';
import 'package:runtrail/services/app_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'calendar arithmetic crosses DST dates, months and years as civil days',
    () {
      expect(Calendar.addDays(DateTime(2026, 3, 8), 1), DateTime(2026, 3, 9));
      expect(Calendar.addDays(DateTime(2026, 11, 1), 1), DateTime(2026, 11, 2));
      expect(Calendar.addDays(DateTime(2026, 12, 31), 1), DateTime(2027));
      expect(
        Calendar.daysBetween(DateTime(2026, 3, 9), DateTime(2026, 3, 8)),
        1,
      );
      expect(Calendar.monday(DateTime(2027, 1, 3)), DateTime(2026, 12, 28));
    },
  );
  test('date changes notify cached pages once per date', () {
    final data = AppData.instance;
    data.refreshForDate(now: DateTime(2026, 12, 31));
    final version = data.version;
    expect(data.refreshForDate(now: DateTime(2027)), isTrue);
    expect(data.version, version + 1);
    expect(data.refreshForDate(now: DateTime(2027, 1, 1, 20)), isFalse);
    expect(data.version, version + 1);
    data.refreshForDate();
  });
  test('goals reject invalid numbers and preserve fractional values', () async {
    SharedPreferences.setMockInitialValues({
      'weekly_goal_km': double.nan,
      'yearly_goal_km': 'broken',
    });
    final prefs = Prefs.instance;
    await prefs.load();
    expect(prefs.weeklyGoalKm, 20);
    expect(prefs.yearlyGoalKm, 500);
    for (final invalid in [double.nan, double.infinity, -1.0, 0.5, 1000.1]) {
      await expectLater(prefs.setWeeklyGoal(invalid), throwsArgumentError);
    }
    await prefs.setWeeklyGoal(12.75);
    await prefs.load();
    expect(prefs.weeklyGoalKm, 12.75);
    expect(Prefs.formatGoal(prefs.weeklyGoalKm), '12.75');
  });
}
