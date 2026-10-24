import 'dart:convert';

import '../models/run_record.dart';
import 'marathon_training_service.dart';

/// Derived view only: never persists or overwrites a user's manual check mark.
/// Runs belong to their start day in the device's current local timezone, matching
/// the history/calendar. A run crossing midnight belongs wholly to its start day.
/// Recompute from the database after any save/import/edit/delete, and for each
/// plan's own tasks. Historical runs can therefore satisfy an overlapping plan.
class TrainingRunResults {
  TrainingRunResults._();

  static List<RunRecord> uniqueValid(Iterable<RunRecord> records) {
    final valid = <RunRecord>[];
    final sessions = <String>{};
    final ids = <int>{};
    final fingerprints = <String>{};
    for (final run in records) {
      if (!run.distanceM.isFinite ||
          run.distanceM < 0 ||
          run.durationS < 0 ||
          run.end.isBefore(run.start)) {
        continue;
      }
      // Session IDs make restore/import idempotent. Exact activity fingerprints
      // also avoid counting a GPS activity and its re-imported GPX export twice.
      final fingerprint =
          '${run.start.microsecondsSinceEpoch}:'
          '${run.end.microsecondsSinceEpoch}:${run.distanceM}:${run.durationS}';
      final duplicate =
          sessions.contains(run.sessionKey) ||
          (run.id != null && ids.contains(run.id)) ||
          fingerprints.contains(fingerprint);
      sessions.add(run.sessionKey);
      if (run.id != null) ids.add(run.id!);
      fingerprints.add(fingerprint);
      if (duplicate) continue;
      valid.add(run);
    }
    return valid;
  }

  static Map<String, double> aggregate(Iterable<RunRecord> records) {
    final metres = <String, double>{};
    for (final run in uniqueValid(records)) {
      final day = run.start.toLocal().toIso8601String().substring(0, 10);
      metres[day] = (metres[day] ?? 0) + run.distanceM;
    }
    return {
      for (final day in metres.keys.toList()..sort()) day: metres[day]! / 1000,
    };
  }

  static int plannedRunDays(Iterable<TrainingTask> tasks) => tasks
      .where(
        (t) =>
            t.km > 0 &&
            !const {
              'REST',
              'STRENGTH',
              'CROSS',
              'RACE',
            }.contains(t.type.toUpperCase()),
      )
      .map((t) => t.date)
      .toSet()
      .length;

  static TrainingRunResult forTask(
    TrainingTask task, {
    double? actualKm,
    bool manuallyCompleted = false,
  }) => TrainingRunResult(
    task: task,
    actualKm: actualKm != null && actualKm.isFinite && actualKm >= 0
        ? actualKm
        : null,
    manuallyCompleted: manuallyCompleted,
  );
}

class TrainingRunResult {
  const TrainingRunResult({
    required this.task,
    required this.actualKm,
    required this.manuallyCompleted,
  });

  final TrainingTask task;
  final double? actualKm;
  final bool manuallyCompleted;
  bool get isRunningTask =>
      task.km.isFinite &&
      task.km > 0 &&
      !const {'REST', 'STRENGTH', 'CROSS'}.contains(task.type.toUpperCase());
  double? get deltaKm =>
      isRunningTask && actualKm != null ? actualKm! - task.km : null;
  // No completion tolerance: even a small shortfall remains explicitly partial.
  bool get distanceCompleted =>
      isRunningTask && actualKm != null && actualKm! >= task.km;
  bool get isComplete => manuallyCompleted || distanceCompleted;
  String get status => !isRunningTask
      ? 'not_distance_based'
      : actualKm == null
      ? 'no_record'
      : actualKm == 0
      ? 'no_activity'
      : distanceCompleted
      ? 'completed'
      : 'partial';
  String get statusLabel => distanceCompleted
      ? '距离已达标'
      : manuallyCompleted
      ? '已手动完成'
      : !isRunningTask
      ? '非跑步任务'
      : actualKm == null
      ? '暂无跑步记录'
      : actualKm == 0
      ? '已记录 0 km'
      : '已完成部分距离';

  static String km(double value) => value.toStringAsFixed(2);
  String get deltaLabel {
    final delta = deltaKm;
    if (delta == null) return '';
    if (delta == 0) return '与计划一致';
    final magnitude = delta.abs() < .005 ? '<0.01' : km(delta.abs());
    return '${delta > 0 ? '多跑' : '少跑'} $magnitude km';
  }

  String get summary => isRunningTask
      ? '计划 ${km(task.km)} km · ${actualKm == null ? '暂无跑步记录' : '实际 ${km(actualKm!)} km · $deltaLabel'}'
      : '${actualKm == null ? '暂无跑步记录' : '当日跑步 ${km(actualKm!)} km'} · 跑量不代替本项完成';
  Map<String, dynamic> toJson() => {
    'date': task.date,
    'type': task.type,
    'plannedKm': task.km,
    'actualKm': actualKm,
    'deltaKm': deltaKm,
    'status': status,
    'manualCompleted': manuallyCompleted,
    'distanceCompleted': distanceCompleted,
  };
}

/// Factual, bounded activity evidence. No GPS, notes or invented HR/sleep.
class TrainingRunSummary {
  final DateTime asOf;
  final List<RunRecord> _runs;
  TrainingRunSummary(Iterable<RunRecord> records, DateTime now)
    : asOf = DateTime.utc(now.year, now.month, now.day),
      _runs = List.unmodifiable(
        TrainingRunResults.uniqueValid(records).where((r) {
          final local = r.start.toLocal();
          final day = DateTime.utc(local.year, local.month, local.day);
          final end = DateTime.utc(now.year, now.month, now.day);
          return !day.isBefore(end.subtract(const Duration(days: 27))) &&
              !day.isAfter(end);
        }).toList()..sort((a, b) => a.start.compareTo(b.start)),
      );
  String get fingerprint => jsonEncode([
    for (final r in _runs)
      [
        r.sessionKey,
        r.start.microsecondsSinceEpoch,
        r.end.microsecondsSinceEpoch,
        r.distanceM,
        r.durationS,
        r.source,
      ],
  ]);
  double get longestSingleRunKm => _runs.fold<double>(
    0,
    (longest, r) => r.distanceKm > longest ? r.distanceKm : longest,
  );
  int get count => _runs.length;
  Map<String, Object?> toJson() {
    final timed = _runs.where(
      (r) =>
          r.durationS > 0 &&
          r.distanceM > 10 &&
          r.durationS <= r.end.difference(r.start).inSeconds,
    );
    final timedKm = timed.fold<double>(0, (sum, r) => sum + r.distanceKm);
    final seconds = timed.fold<int>(0, (sum, r) => sum + r.durationS);
    final sources = <String, int>{};
    for (final r in _runs) {
      final source = const {'gps', 'manual', 'gpx'}.contains(r.source)
          ? r.source
          : 'unknown';
      sources[source] = (sources[source] ?? 0) + 1;
    }
    return {
      'windowDays': 28,
      'asOfDate': asOf.toIso8601String().substring(0, 10),
      'activityCount': count,
      'totalKm': _runs.fold<double>(0, (sum, r) => sum + r.distanceKm),
      'longestSingleRunKm': count == 0 ? null : longestSingleRunKm,
      'paceEligibleActivityCount': timed.length,
      'paceEligibleKm': timedKm,
      'recordedActiveSeconds': seconds,
      'weightedAveragePaceSecondsPerKm': timedKm > 0 ? seconds / timedKm : null,
      'sourceCounts': sources,
      'heartRate': null,
      'sleep': null,
      'missingData': [
        'Heart rate not collected',
        'Sleep not collected',
        'No activity record does not establish a missed session',
      ],
      'interpretation': 'Observed records only; manual and imported records may be incomplete. Pace is active seconds divided by distance for records with usable duration, not a race prediction. Longest run is a single recorded activity, not daily aggregate. Never infer heart rate, sleep, or positive progression readiness.',
    };
  }
}
