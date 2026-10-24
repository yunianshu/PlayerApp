import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local calendar-day measurements. Bounds are input-error guards, not health
/// targets. No BMI, readiness classification, or automatic training changes.
class BodyWeightRecord {
  final String date;
  final double kg;
  const BodyWeightRecord({required this.date, required this.kg});

  static String dateKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  void validate({DateTime? now}) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        dateKey(parsed) != date ||
        parsed.year < 1900 ||
        date.compareTo(dateKey(now ?? DateTime.now())) > 0) {
      throw const FormatException('请选择有效日期，不能记录未来体重');
    }
    if (!kg.isFinite || kg < 20 || kg > 500) {
      throw const FormatException('请核对单位：输入 20–500 kg，仅用于防止录入错误');
    }
  }

  Map<String, Object> toJson() => {'date': date, 'kg': kg};
  factory BodyWeightRecord.fromJson(Map<String, dynamic> json) {
    final record = BodyWeightRecord(
      date: json['date'] as String,
      kg: (json['kg'] as num).toDouble(),
    );
    record.validate();
    return record;
  }
}

/// Descriptive calendar-window trend, never a clinical/readiness score.
/// Three distinct measurements per adjacent week is a product data-quality
/// gate, not a medical threshold. Missing measurements are never interpolated.
class BodyWeightSummary {
  final List<BodyWeightRecord> records;
  final DateTime asOf;
  BodyWeightSummary(List<BodyWeightRecord> values, {DateTime? asOf})
    : this._(_bounded(values, asOf), asOf);
  BodyWeightSummary._(List<BodyWeightRecord> values, DateTime? date)
    : records = List.unmodifiable(values),
      asOf = _calendarDay(date ?? DateTime.parse(values.last.date));
  static DateTime _calendarDay(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
  static List<BodyWeightRecord> _bounded(
    List<BodyWeightRecord> values,
    DateTime? asOf,
  ) {
    if (values.isEmpty) throw ArgumentError('体重摘要不能为空');
    final sorted = List<BodyWeightRecord>.of(values)
      ..sort((a, b) => a.date.compareTo(b.date));
    final day = _calendarDay(asOf ?? DateTime.parse(sorted.last.date));
    for (final record in sorted) {
      record.validate(now: day);
    }
    if (sorted.map((r) => r.date).toSet().length != sorted.length) {
      throw const FormatException('体重摘要存在重复日期');
    }
    final start = BodyWeightRecord.dateKey(
      day.subtract(const Duration(days: 27)),
    );
    final recent = sorted.where((r) => r.date.compareTo(start) >= 0).toList();
    if (recent.isEmpty) throw ArgumentError('最近 28 天没有体重记录');
    return recent;
  }

  List<BodyWeightRecord> _week(int offset) {
    final end = BodyWeightRecord.dateKey(asOf.subtract(Duration(days: offset)));
    final start = BodyWeightRecord.dateKey(
      asOf.subtract(Duration(days: offset + 6)),
    );
    return records
        .where(
          (r) => r.date.compareTo(start) >= 0 && r.date.compareTo(end) <= 0,
        )
        .toList();
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(2));
  static double? _mean(List<BodyWeightRecord> values) => values.isEmpty
      ? null
      : _round(values.fold<double>(0, (sum, r) => sum + r.kg) / values.length);
  bool get trendUsable => _week(0).length >= 3 && _week(7).length >= 3;
  double? get changeInWeeklyMeanKg =>
      trendUsable ? _round(_mean(_week(0))! - _mean(_week(7))!) : null;
  Map<String, Object?> toJson() => {
    'windowDays': 28,
    'asOfDate': BodyWeightRecord.dateKey(asOf),
    'measurementCount': records.length,
    'firstDate': records.first.date,
    'lastDate': records.last.date,
    'firstKg': records.first.kg,
    'lastKg': records.last.kg,
    'changeKg': _round(records.last.kg - records.first.kg),
    'latestMeasurementAgeDays': asOf
        .difference(_calendarDay(DateTime.parse(records.last.date)))
        .inDays,
    'previous7DaysCount': _week(7).length,
    'latest7DaysCount': _week(0).length,
    'previous7DaysMeanKg': _mean(_week(7)),
    'latest7DaysMeanKg': _mean(_week(0)),
    'trendUsable': trendUsable,
    'changeInWeeklyMeanKg': changeInWeeklyMeanKg,
    'interpretation': 'Descriptive measurements only. Compare adjacent calendar-week means only when trendUsable is true (at least 3 distinct measurement days in each week). Missing days are unknown. Insufficient or stale measurements must not drive a plan change. Weight is not fitness or readiness; never prescribe weight loss, diet, faster pace or increased load from weight changes. A usable trend is context only alongside actual training and recovery feedback, never a dose formula.',
  };
  String get trendDescription => trendUsable
      ? '前 7 天均值 ${_mean(_week(7))!.toStringAsFixed(2)} kg（${_week(7).length} 次），近 7 天均值 ${_mean(_week(0))!.toStringAsFixed(2)} kg（${_week(0).length} 次）；变化 ${changeInWeeklyMeanKg! >= 0 ? '+' : ''}${changeInWeeklyMeanKg!.toStringAsFixed(2)} kg。仅作训练与恢复的辅助背景，不等于体能变化。'
      : '体重趋势证据不足：前 7 天 ${_week(7).length} 次、近 7 天 ${_week(0).length} 次；每段至少 3 个测量日才比较均值。本次不据此增减训练。';
  String get disclosure =>
      '${records.first.date} 至 ${records.last.date}，${records.length} 次记录；'
      '首末 ${records.first.kg.toStringAsFixed(1)} → ${records.last.kg.toStringAsFixed(1)} kg。'
      '发送首末日期/体重/差值、记录数、摘要日期、距末次测量天数、前后两个 7 天的均值/次数、均值差及趋势可用标记，不发送逐日明细。\n$trendDescription';
}

class BodyWeightSnapshot {
  final List<BodyWeightRecord> records;
  final String fingerprint;
  const BodyWeightSnapshot(this.records, this.fingerprint);
  BodyWeightSummary? summary(DateTime now) {
    final end = BodyWeightRecord.dateKey(now);
    final start = BodyWeightRecord.dateKey(
      DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 27)),
    );
    final recent = records
        .where(
          (r) => r.date.compareTo(start) >= 0 && r.date.compareTo(end) <= 0,
        )
        .toList();
    return recent.isEmpty ? null : BodyWeightSummary(recent, asOf: now);
  }
}

class BodyWeightService {
  static const storageKey = 'body_weight_records_v1';
  static final instance = BodyWeightService();
  final Future<SharedPreferences> Function() _prefs;
  final Future<bool> Function(SharedPreferences, String, String)? write;
  Future<void>? _tail;
  Object? _queueMarker;
  BodyWeightService({Future<SharedPreferences> Function()? prefs, this.write})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  Future<BodyWeightSnapshot> snapshot() async {
    final p = await _prefs();
    final raw = p.getString(storageKey);
    if (raw == null) return const BodyWeightSnapshot([], '');
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('体重记录读取失败，请勿覆盖原数据');
    final records =
        decoded
            .map(
              (e) => BodyWeightRecord.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (records.map((r) => r.date).toSet().length != records.length) {
      throw const FormatException('体重记录存在重复日期，请先检查备份');
    }
    return BodyWeightSnapshot(List.unmodifiable(records), raw);
  }

  Future<bool> unchanged(BodyWeightSnapshot old) async =>
      (await snapshot()).fingerprint == old.fingerprint;

  Future<void> _update(
    List<BodyWeightRecord> Function(List<BodyWeightRecord>) action,
  ) {
    final previous = _tail;
    final marker = Object();
    _queueMarker = marker;
    final result = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {
          /* A failed write does not poison the queue. */
        }
      }
      try {
        final p = await _prefs();
        final records = action(List.of((await snapshot()).records))
          ..sort((a, b) => a.date.compareTo(b.date));
        try {
          final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
          final saved =
              await (write?.call(p, storageKey, encoded) ??
                  p.setString(storageKey, encoded));
          if (!saved) {
            throw StateError('体重记录保存失败');
          }
        } catch (_) {
          // SharedPreferences updates its memory before native persistence. Reload
          // prevents failed writes being displayed or sent to an AI provider.
          await p.reload();
          rethrow;
        }
      } finally {
        // Clear before the operation settles, without clearing a queued successor.
        // Do not retain a completed Future tied to a previous event/test zone.
        if (identical(_queueMarker, marker)) {
          _tail = null;
          _queueMarker = null;
        }
      }
    }();
    _tail = result;
    return result;
  }

  Future<void> save(
    BodyWeightRecord record, {
    bool replace = false,
    DateTime? now,
  }) {
    record.validate(now: now);
    return _update((records) {
      if (!replace && records.any((r) => r.date == record.date)) {
        throw StateError('当天已有体重记录，请选择编辑');
      }
      records.removeWhere((r) => r.date == record.date);
      return records..add(
        BodyWeightRecord(
          date: record.date,
          kg: double.parse(record.kg.toStringAsFixed(2)),
        ),
      );
    });
  }

  Future<void> delete(String date) =>
      _update((records) => records..removeWhere((r) => r.date == date));

  /// Backup import keeps existing dates; it never silently overwrites a newer
  /// local measurement. Validation happens before any weight record is written.
  Future<void> mergeBackup(List<dynamic> raw) {
    final incoming = raw
        .map(
          (e) => BodyWeightRecord.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    return _update((records) {
      final dates = records.map((r) => r.date).toSet();
      for (final record in incoming) {
        if (dates.add(record.date)) records.add(record);
      }
      return records;
    });
  }
}
