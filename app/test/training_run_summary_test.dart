import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/training_run_results.dart';
import 'package:runtrail/services/marathon_training_service.dart';

void main() {
  final now = DateTime(2027, 1, 15);
  RunRecord run(
    int day,
    double km,
    int seconds, {
    int hour = 8,
    String source = 'gps',
  }) => RunRecord(
    start: DateTime(2027, 1, day, hour),
    end: DateTime(2027, 1, day, hour).add(Duration(seconds: seconds)),
    distanceM: km * 1000,
    durationS: seconds,
    calories: 0,
    source: source,
  );
  test('run-day count derives tasks not available weekdays', () {
    final tasks = [
      for (final entry in [
        'EASY',
        'LONG',
        'EASY',
        'STRENGTH',
        'REST',
        'CROSS',
        'RACE',
      ].asMap().entries)
        TrainingTask(
          '2027-01-${entry.key + 1}',
          entry.value,
          '任务',
          const {'STRENGTH', 'REST', 'CROSS'}.contains(entry.value) ? 0 : 5,
          '',
        ),
    ];
    expect(TrainingRunResults.plannedRunDays(tasks), 3);
  });
  test('weighted pace uses eligible seconds and longest is single run', () {
    final json = TrainingRunSummary([
      run(14, 5, 1500),
      run(14, 10, 3600, hour: 18),
      run(15, 3, 0, source: 'manual'),
    ], now).toJson();
    expect(json['totalKm'], 18);
    expect(json['longestSingleRunKm'], 10);
    expect(json['weightedAveragePaceSecondsPerKm'], 340);
    expect(json['paceEligibleActivityCount'], 2);
    expect(json['heartRate'], null);
    expect(json['sleep'], null);
    expect(json.containsKey('notes'), false);
  });
  test('dedup aligns summary and daily results and excludes future dates', () {
    final r = run(14, 5, 1500);
    final summary = TrainingRunSummary([r, r, run(16, 9, 3600)], now);
    expect(summary.count, 1);
    expect(summary.longestSingleRunKm, 5);
    expect(TrainingRunResults.aggregate([r, r])['2027-01-14'], 5);
  });
  test('duration-only edit invalidates snapshot', () {
    expect(
      TrainingRunSummary([run(14, 5, 1500)], now).fingerprint,
      isNot(TrainingRunSummary([run(14, 5, 1800)], now).fingerprint),
    );
  });
  test('source-only edit invalidates snapshot', () {
    expect(
      TrainingRunSummary([run(14, 5, 1500)], now).fingerprint,
      isNot(
        TrainingRunSummary([
          run(14, 5, 1500, source: 'manual'),
        ], now).fingerprint,
      ),
    );
  });
  test('no records or missing duration never fabricates pace', () {
    expect(
      TrainingRunSummary([], now).toJson()['weightedAveragePaceSecondsPerKm'],
      null,
    );
    expect(TrainingRunSummary([], now).toJson()['longestSingleRunKm'], null);
    expect(
      TrainingRunSummary([
        run(14, 5, 0),
      ], now).toJson()['weightedAveragePaceSecondsPerKm'],
      null,
    );
  });
}
