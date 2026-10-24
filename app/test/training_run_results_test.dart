import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/services/training_run_results.dart';

const day = '2026-10-23';
const task = TrainingTask(day, 'EASY', '轻松跑', 5, '');
RunRecord run(
  String session,
  double metres, {
  DateTime? start,
  int? id,
  DateTime? end,
  String source = RunRecord.sourceGps,
}) {
  final at = start ?? DateTime(2026, 10, 23, 7);
  return RunRecord(
    id: id,
    sessionId: session,
    start: at,
    end: end ?? at.add(const Duration(minutes: 30)),
    distanceM: metres,
    durationS: 1800,
    calories: 100,
    source: source,
  );
}

void main() {
  test(
    'exact and excess distance count automatically, never fudge shortfall',
    () {
      for (final actual in [5.0, 6.0]) {
        final result = TrainingRunResults.forTask(task, actualKm: actual);
        expect(result.distanceCompleted, isTrue);
        expect(result.isComplete, isTrue);
        expect(result.manuallyCompleted, isFalse);
        expect(result.status, 'completed');
        expect(result.deltaKm, actual - 5);
      }
      final partial = TrainingRunResults.forTask(task, actualKm: 4.999999);
      expect(partial.isComplete, isFalse);
      expect(partial.status, 'partial');
      expect(partial.deltaLabel, '少跑 <0.01 km');
    },
  );

  test(
    'missing record and zero activity remain distinct, neither means missed',
    () {
      final missing = TrainingRunResults.forTask(task);
      final zero = TrainingRunResults.forTask(task, actualKm: 0);
      expect(missing.status, 'no_record');
      expect(missing.deltaKm, isNull);
      expect(zero.status, 'no_activity');
      expect(zero.deltaKm, -5);
      expect(zero.isComplete, isFalse);
      expect(missing.toJson()['actualKm'], isNull);
      for (final invalid in [double.nan, double.infinity, -1.0]) {
        expect(
          TrainingRunResults.forTask(task, actualKm: invalid).actualKm,
          isNull,
        );
      }
    },
  );

  test('rest, strength and cross training cannot be inferred from running', () {
    for (final type in ['REST', 'STRENGTH', 'CROSS']) {
      for (final km in [0.0, 5.0]) {
        final result = TrainingRunResults.forTask(
          TrainingTask(day, type, '非跑步任务', km, ''),
          actualKm: 10,
        );
        expect(result.isComplete, isFalse);
        expect(result.status, 'not_distance_based');
        expect(result.deltaKm, isNull);
      }
    }
    expect(
      TrainingRunResults.forTask(
        const TrainingTask(day, 'RACE', '马拉松', 42.195, ''),
        actualKm: 42.195,
      ).distanceCompleted,
      isTrue,
    );
    expect(
      TrainingRunResults.forTask(
        const TrainingTask(day, 'EASY', '无距离', 0, ''),
        actualKm: 5,
      ).distanceCompleted,
      isFalse,
    );
  });

  test('manual completion survives partial, missing and deleted activity', () {
    for (final actual in <double?>[null, 0, 3, 5, 7]) {
      final result = TrainingRunResults.forTask(
        task,
        actualKm: actual,
        manuallyCompleted: true,
      );
      expect(result.isComplete, isTrue);
      expect(result.toJson()['manualCompleted'], isTrue);
      expect(result.actualKm, actual);
    }
    final unmarked = TrainingRunResults.forTask(task, actualKm: 6);
    expect(
      unmarked.isComplete,
      isTrue,
      reason: 'Removing a manual mark cannot erase real distance.',
    );
  });

  test(
    'multiple runs aggregate once with duplicate sessions, IDs and GPX exports',
    () {
      final first = run('gps-a', 2000, id: 1);
      final second = run(
        'gps-b',
        3000,
        id: 2,
        start: DateTime(2026, 10, 23, 18),
      );
      final gpx = run('gpx-a', 2000, id: 3, source: RunRecord.sourceGpx);
      final totals = TrainingRunResults.aggregate([first, first, gpx, second]);
      expect(totals, {day: 5});
      expect(TrainingRunResults.aggregate([second, gpx, first]), totals);
      expect(
        TrainingRunResults.forTask(task, actualKm: totals[day]).isComplete,
        isTrue,
      );
      expect(
        TrainingRunResults.aggregate([first, run('duplicate-id', 3000, id: 1)]),
        {day: 2},
      );
    },
  );

  test(
    'fresh snapshots reflect edited and deleted records, no cached truth',
    () {
      expect(TrainingRunResults.aggregate([run('a', 6000)])[day], 6);
      expect(TrainingRunResults.aggregate([run('a', 3000)])[day], 3);
      expect(TrainingRunResults.aggregate([])[day], isNull);
      expect(TrainingRunResults.aggregate([run('a', 0)])[day], 0);
      expect(
        TrainingRunResults.aggregate([run('a', -5), run('b', double.nan)]),
        isEmpty,
      );
    },
  );

  test(
    'midnight run stays on local start date, UTC instants normalize to local',
    () {
      final late = run(
        'late',
        5000,
        start: DateTime(2026, 10, 23, 23, 50),
        end: DateTime(2026, 10, 24, 0, 20),
      );
      expect(TrainingRunResults.aggregate([late]), {day: 5});
      final utc = run('utc', 1000, start: DateTime.utc(2026, 10, 23, 23, 50));
      final localDay = utc.start.toLocal().toIso8601String().substring(0, 10);
      expect(TrainingRunResults.aggregate([utc]), {localDay: 1});
    },
  );

  test(
    'each plan derives against its own task; dates outside plan do not link',
    () {
      final totals = TrainingRunResults.aggregate([run('history', 6000)]);
      final secondPlanTask = TrainingTask(day, 'LONG', '长距离', 10, '');
      expect(
        TrainingRunResults.forTask(
          task,
          actualKm: totals[task.date],
        ).isComplete,
        isTrue,
      );
      final second = TrainingRunResults.forTask(
        secondPlanTask,
        actualKm: totals[secondPlanTask.date],
      );
      expect(second.status, 'partial');
      expect(second.manuallyCompleted, isFalse);
      expect(second.deltaKm, -4);
      const otherDay = TrainingTask('2026-10-24', 'EASY', '轻松跑', 5, '');
      expect(
        TrainingRunResults.forTask(
          otherDay,
          actualKm: totals[otherDay.date],
        ).status,
        'no_record',
      );
    },
  );
}
