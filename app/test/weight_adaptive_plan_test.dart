import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_plan_generator.dart';
import 'package:runtrail/services/body_weight_service.dart';
import 'package:runtrail/services/training_run_results.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/services/ai_training_coach.dart';

import 'ai_plan_generator_test.dart' as fixtures;

void main() {
  final now = DateTime(2027, 1, 15);
  BodyWeightSummary sufficient({double latestKg = 65}) => BodyWeightSummary([
    for (final day in [3, 5, 7, 10, 12, 14])
      BodyWeightRecord(
        date: '2027-01-${day.toString().padLeft(2, '0')}',
        kg: day < 9 ? 66 : latestKg,
      ),
  ], asOf: now);
  Map<String, Object?> response({
    bool used = false,
    List<String> signals = const [],
  }) => {
    'schemaVersion': 1,
    'summary': '保持训练，结合反馈观察恢复。',
    'warnings': <String>[],
    'changes': <Object>[],
    'weightAssessment': {
      'used': used,
      'reason': '均值仅作背景，与训练和恢复共同评估，不以体重换算跑量。',
      'supportingSignals': signals,
    },
  };
  Future<AiPlanDraft> generate(
    fixtures.FakeTransport fake, {
    BodyWeightSummary? weight,
    TrainingRunSummary? runs,
    Map<String, double> actual = const {},
    Map<String, Map<String, int>> feedback = const {},
  }) => AiPlanGenerator.generateAdjustment(
    existingPlan: fixtures.valid(),
    now: now,
    completed: {},
    actualKm: actual,
    feedback: feedback,
    weightSummary: weight,
    runSummary: runs,
    config: const AiCoachConfig(
      endpoint: 'https://example.test/chat',
      model: 'fake',
    ),
    apiKey: 'fixture',
    transport: fake,
  );
  test('four selected weekdays reject a fifth running day', () {
    final request = GenericTrainingRequest(
      raceName: '测试',
      startDate: DateTime(2027, 1, 1),
      raceDate: DateTime(2027, 1, 29),
      weeklyKm: 30,
      longestRunKm: 10,
      trainingWeekdays: {1, 2, 4, 6},
    );
    expect(
      () =>
          AiPlanGenerator.parse(jsonEncode(fixtures.valid()), request: request),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('actual pace summary remains distinct from goal prediction', () async {
    final runs = TrainingRunSummary([
      RunRecord(
        start: DateTime(2027, 1, 14, 8),
        end: DateTime(2027, 1, 14, 9),
        distanceM: 10000,
        durationS: 3600,
        calories: 0,
      ),
    ], now);
    final fake = fixtures.FakeTransport(jsonEncode(response()));
    final result = await generate(fake, runs: runs);
    final input = jsonDecode(
      (fake.body!['messages'] as List).last['content'] as String,
    ) as Map;
    expect(
      input['actualTrainingSummary']['weightedAveragePaceSecondsPerKm'],
      360,
    );
    expect(input['actualTrainingSummary']['heartRate'], null);
    expect(result.adaptationEvidence.join(), contains('目标仍待'));
  });
  test(
    'adjacent calendar weeks use observed means not first-last readings',
    () {
      final value = sufficient();
      expect(value.trendUsable, true);
      expect(value.toJson()['previous7DaysCount'], 3);
      expect(value.toJson()['latest7DaysCount'], 3);
      expect(value.changeInWeeklyMeanKg, -1);
      expect(value.toJson()['latestMeasurementAgeDays'], 1);
      expect(value.toJson().containsKey('records'), false);
    },
  );
  test('one reading sparse and old readings never form usable trend', () {
    for (final records in [
      [const BodyWeightRecord(date: '2027-01-14', kg: 65)],
      [
        const BodyWeightRecord(date: '2027-01-03', kg: 66),
        const BodyWeightRecord(date: '2027-01-14', kg: 60),
      ],
      [
        for (final day in [20, 21, 22, 23, 24, 25])
          BodyWeightRecord(date: '2026-12-$day', kg: 65),
      ],
    ]) {
      final value = BodyWeightSummary(records, asOf: now);
      expect(value.trendUsable, false);
      expect(value.changeInWeeklyMeanKg, null);
    }
  });
  test(
    'unsorted input sorts and duplicates cannot manufacture sample size',
    () {
      final rows = sufficient().records.reversed.toList();
      expect(BodyWeightSummary(rows, asOf: now).changeInWeeklyMeanKg, -1);
      expect(
        () => BodyWeightSummary([...rows, rows.first], asOf: now),
        throwsFormatException,
      );
    },
  );
  test('window boundaries do not overlap and future samples are rejected', () {
    final records = [
      for (final day in [2, 5, 8, 9, 12, 15])
        BodyWeightRecord(
          date: '2027-01-${day.toString().padLeft(2, '0')}',
          kg: 65,
        ),
    ];
    final value = BodyWeightSummary(records, asOf: now);
    expect(value.trendUsable, true);
    expect(value.changeInWeeklyMeanKg, 0);
    expect(
      () => BodyWeightSummary([
        ...records,
        const BodyWeightRecord(date: '2027-01-16', kg: 65),
      ], asOf: now),
      throwsFormatException,
    );
  });
  test(
    'consented trend and actual evidence reach model not persisted plan',
    () async {
      final fake = fixtures.FakeTransport(
        jsonEncode(
          response(used: true, signals: ['training_results', 'fatigue']),
        ),
      );
      final result = await generate(
        fake,
        weight: sufficient(),
        actual: {'2027-01-14': 2},
        feedback: {
          '2027-01-14': {'pain': 0, 'fatigue': 6},
        },
      );
      final input = jsonDecode(
        (fake.body!['messages'] as List).last['content'] as String,
      ) as Map;
      expect(input['bodyWeightSummary']['changeInWeeklyMeanKg'], -1);
      expect(result.adaptationEvidence.join(), contains('前 7 天均值'));
      expect(result.adaptationEvidence.join(), contains('AI 已结合'));
      expect(jsonEncode(result.plan), isNot(contains('bodyWeightSummary')));
      expect(jsonEncode(result.plan), isNot(contains('weightAssessment')));
      expect(result.plan['tasks'], fixtures.valid()['tasks']);
    },
  );
  test('declined weight has no payload or assessment requirement', () async {
    final data = response()..remove('weightAssessment');
    final fake = fixtures.FakeTransport(jsonEncode(data));
    final draft = await generate(fake);
    final input = jsonDecode(
      (fake.body!['messages'] as List).last['content'] as String,
    ) as Map;
    expect(input.containsKey('bodyWeightSummary'), false);
    expect(draft.adaptationEvidence.join(), isNot(contains('体重')));
    expect(draft.adaptationEvidence.join(), contains('睡眠未记录'));
  });
  test(
    'sparse trend cannot be claimed used even with training evidence',
    () async {
      final fake = fixtures.FakeTransport(
        jsonEncode(response(used: true, signals: ['training_results'])),
      );
      await expectLater(
        generate(
          fake,
          weight: BodyWeightSummary([
            const BodyWeightRecord(date: '2027-01-14', kg: 65),
          ], asOf: now),
          actual: {'2027-01-14': 2},
        ),
        throwsA(isA<AiCoachException>()),
      );
    },
  );
  test('weight alone or fabricated support cannot justify changes', () async {
    for (final signals in [
      <String>[],
      ['training_results'],
      ['fatigue'],
      ['body_mass'],
    ]) {
      await expectLater(
        generate(
          fixtures.FakeTransport(
            jsonEncode(response(used: true, signals: signals)),
          ),
          weight: sufficient(),
        ),
        throwsA(isA<AiCoachException>()),
      );
    }
  });
  test(
    'past-window training does not count as current supporting evidence',
    () async {
      await expectLater(
        generate(
          fixtures.FakeTransport(
            jsonEncode(response(used: true, signals: ['training_results'])),
          ),
          weight: sufficient(),
          actual: {'2026-10-01': 8},
        ),
        throwsA(isA<AiCoachException>()),
      );
    },
  );
  test('days15to28 cannot support fourteen-day weight trend', () async {
    await expectLater(
      generate(
        fixtures.FakeTransport(
          jsonEncode(response(used: true, signals: ['training_results'])),
        ),
        weight: sufficient(),
        actual: {'2026-12-31': 8},
      ),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('pain-only feedback cannot invent fatigue signal', () async {
    await expectLater(
      generate(
        fixtures.FakeTransport(
          jsonEncode(response(used: true, signals: ['fatigue'])),
        ),
        weight: sufficient(),
        feedback: {
          '2027-01-14': {'pain': 0},
        },
      ),
      throwsA(isA<AiCoachException>()),
    );
  });
  test(
    'missing assessment rejected and insufficient unused input works',
    () async {
      final data = response()..remove('weightAssessment');
      await expectLater(
        generate(
          fixtures.FakeTransport(jsonEncode(data)),
          weight: sufficient(),
        ),
        throwsA(isA<AiCoachException>()),
      );
      final result = await generate(
        fixtures.FakeTransport(jsonEncode(response())),
        weight: BodyWeightSummary([
          const BodyWeightRecord(date: '2027-01-14', kg: 65),
        ], asOf: now),
      );
      expect(result.adaptationEvidence.join(), contains('证据不足'));
      expect(result.adaptationEvidence.join(), contains('AI 未将体重'));
    },
  );
  test('unchanged26km is not verified after20km recorded activity', () async {
    final plan = fixtures.valid();
    plan['tasks'][15]['type'] = 'LONG';
    plan['tasks'][15]['km'] = 26;
    final runs = TrainingRunSummary([
      RunRecord(
        start: DateTime(2027, 1, 14, 8),
        end: DateTime(2027, 1, 14, 11),
        distanceM: 20000,
        durationS: 9000,
        calories: 0,
      ),
    ], now);
    final result = await AiPlanGenerator.generateAdjustment(
      existingPlan: plan,
      now: now,
      completed: {},
      actualKm: {'2027-01-14': 20},
      feedback: {},
      runSummary: runs,
      config: const AiCoachConfig(
        endpoint: 'https://example.test/chat',
        model: 'fake',
      ),
      apiKey: 'fixture',
      transport: fixtures.FakeTransport(jsonEncode(response())),
    );
    expect(result.adaptationEvidence.join(), contains('长跑加量尚未验证'));
    expect(result.adaptationEvidence.join(), contains('26'));
  });
  test('no faster or larger training even when weight decreased', () async {
    final data = response(used: true, signals: ['training_results']);
    data['changes'] = [
      {
        'date': '2027-01-16',
        'type': 'EASY',
        'km': 50,
        'easyPace': 200,
        'slowPace': 240,
        'notes': '体重减轻所以加量',
      },
    ];
    await expectLater(
      generate(
        fixtures.FakeTransport(jsonEncode(data)),
        weight: sufficient(),
        actual: {'2027-01-14': 2},
      ),
      throwsA(isA<AiCoachException>()),
    );
  });
}
