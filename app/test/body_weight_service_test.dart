import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/services/body_weight_service.dart';
import 'package:runtrail/services/ai_plan_generator.dart';
import 'package:runtrail/pages/body_weight_page.dart';

void main() {
  final now = DateTime(2026, 10, 23);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'concurrent writes stay serialized and failed head does not poison queue',
    () async {
      final started = Completer<void>();
      final gate = Completer<bool>();
      var writes = 0;
      final store = BodyWeightService(
        write: (prefs, key, value) async {
          writes++;
          if (writes == 1) {
            started.complete();
            return gate.future;
          }
          return prefs.setString(key, value);
        },
      );
      final first = store.save(
        const BodyWeightRecord(date: '2026-10-20', kg: 65),
        now: now,
      );
      final failure = expectLater(first, throwsStateError);
      await started.future;
      final second = store.save(
        const BodyWeightRecord(date: '2026-10-21', kg: 64),
        now: now,
      );
      final third = store.save(
        const BodyWeightRecord(date: '2026-10-22', kg: 63),
        now: now,
      );
      expect(writes, 1);
      gate.complete(false);
      await failure;
      await Future.wait([second, third]);
      expect((await store.snapshot()).records.map((r) => r.date), [
        '2026-10-21',
        '2026-10-22',
      ]);
      await store.delete('2026-10-21');
      expect((await store.snapshot()).records.single.date, '2026-10-22');
    },
  );
  test(
    'create edit duplicate policy delete and stable date ordering',
    () async {
      final store = BodyWeightService();
      await store.save(
        const BodyWeightRecord(date: '2026-10-22', kg: 65),
        now: now,
      );
      await store.save(
        const BodyWeightRecord(date: '2026-10-01', kg: 66),
        now: now,
      );
      final before = await store.snapshot();
      expect(before.records.map((r) => r.date), ['2026-10-01', '2026-10-22']);
      await expectLater(
        store.save(
          const BodyWeightRecord(date: '2026-10-22', kg: 64),
          now: now,
        ),
        throwsStateError,
      );
      expect(await store.unchanged(before), true);
      await store.save(
        const BodyWeightRecord(date: '2026-10-22', kg: 64),
        replace: true,
        now: now,
      );
      expect(await store.unchanged(before), false);
      await store.delete('2026-10-01');
      expect((await store.snapshot()).records.single.kg, 64);
    },
  );
  test(
    'failed persistence does not publish new data; later writes recover',
    () async {
      final normal = BodyWeightService();
      await normal.save(const BodyWeightRecord(date: '2026-10-22', kg: 65));
      final before = await normal.snapshot();
      final failing = BodyWeightService(
        write: (prefs, key, value) async => false,
      );
      await expectLater(
        failing.save(const BodyWeightRecord(date: '2026-10-21', kg: 64)),
        throwsStateError,
      );
      expect(await normal.unchanged(before), true);
      await normal.save(const BodyWeightRecord(date: '2026-10-21', kg: 64));
      expect((await normal.snapshot()).records.length, 2);
    },
  );
  test(
    'guards invalid values and impossible/future dates without medical labels',
    () {
      for (final kg in [double.nan, double.infinity, -1.0, 0.0, 19.9, 500.1]) {
        expect(
          () => BodyWeightRecord(date: '2026-10-22', kg: kg).validate(now: now),
          throwsFormatException,
        );
      }
      for (final date in [
        '2026-02-30',
        '2026-10-24',
        '2026-1-2',
        '1899-01-01',
      ]) {
        expect(
          () => BodyWeightRecord(date: date, kg: 65).validate(now: now),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'summary only28days, no fabricated missing days or full history',
    () async {
      final store = BodyWeightService();
      for (final date in [
        '2026-08-01',
        '2026-09-26',
        '2026-10-01',
        '2026-10-22',
      ]) {
        await store.save(BodyWeightRecord(date: date, kg: 65), now: now);
      }
      final summary = (await store.snapshot()).summary(now)!;
      expect(summary.records.length, 3);
      expect(summary.toJson()['firstDate'], '2026-09-26');
      expect(summary.toJson().containsKey('records'), false);
      expect(jsonEncode(summary.toJson()), isNot(contains('2026-08-01')));
    },
  );
  test('optional AI context never persists into input profile by default', () {
    final request = GenericTrainingRequest(
      raceName: 'Test',
      startDate: now,
      raceDate: now.add(const Duration(days: 112)),
      weeklyKm: 30,
      longestRunKm: 12,
      trainingWeekdays: {2, 4, 7},
    );
    expect(
      request.toJson(includeWeight: true).containsKey('bodyWeightSummary'),
      false,
    );
    final withWeight = request.withWeightSummary(
      BodyWeightSummary([const BodyWeightRecord(date: '2026-10-22', kg: 65)]),
    );
    expect(withWeight.toJson().containsKey('bodyWeightSummary'), false);
    expect(
      withWeight.toJson(includeWeight: true).containsKey('bodyWeightSummary'),
      true,
    );
    expect(withWeight.baseKm, request.baseKm);
    expect(withWeight.longLimit(2), request.longLimit(2));
  });
  test(
    'backup merges, existing days win, invalid batch leaves weights intact',
    () async {
      final store = BodyWeightService();
      await store.save(const BodyWeightRecord(date: '2026-10-22', kg: 65));
      await store.mergeBackup([
        {'date': '2026-10-22', 'kg': 60},
        {'date': '2026-10-01', 'kg': 66},
      ]);
      expect((await store.snapshot()).records.last.kg, 65);
      final before = await store.snapshot();
      expect(
        () => store.mergeBackup([
          {'date': '2026-10-10', 'kg': 64},
          {'date': 'bad', 'kg': 60},
        ]),
        throwsFormatException,
      );
      expect(await store.unchanged(before), true);
    },
  );
  test(
    'invalid stored data fails closed instead of becoming a fake empty history',
    () async {
      SharedPreferences.setMockInitialValues({
        BodyWeightService.storageKey: 'broken',
      });
      await expectLater(BodyWeightService().snapshot(), throwsFormatException);
    },
  );
  test('real calendar spacing, not record index', () {
    const first = BodyWeightRecord(date: '2026-10-01', kg: 65);
    const middle = BodyWeightRecord(date: '2026-10-02', kg: 64);
    const last = BodyWeightRecord(date: '2026-10-11', kg: 63);
    expect(WeightTrendPainter.dayPosition(middle, first, last), .1);
    expect(WeightTrendPainter.dayPosition(first, first, first), .5);
  });
  test('smooth curve passes through measured points without overshoot', () {
    const points = [
      Offset(0, 100),
      Offset(20, 40),
      Offset(50, 90),
      Offset(80, 30),
      Offset(120, 70),
    ];
    final curve = WeightTrendPainter.smoothCurve(points);
    expect(curve.first, points.first);
    expect(curve.last, points.last);
    for (final point in points) {
      expect(curve, contains(point));
    }
    // Monotone interpolation must stay inside the measured value range, so
    // the chart never draws a weight that was not recorded.
    expect(
      curve.every((p) => p.dy >= 30 && p.dy <= 100),
      isTrue,
      reason: 'curve overshot the measured range: $curve',
    );
  });
}
