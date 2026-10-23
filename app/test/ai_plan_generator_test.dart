import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/ai_plan_generator.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_training_coach.dart';

GenericTrainingRequest request({String recovery = 'good', DateTime? race}) =>
    GenericTrainingRequest(
      raceName: '示例马拉松',
      startDate: DateTime(2027, 1, 1),
      raceDate: race ?? DateTime(2027, 1, 29),
      goalMinutes: 300,
      weeklyKm: 30,
      longestRunKm: 10,
      recent10kMinutes: 60,
      trainingWeekdays: {1, 2, 3, 4, 5, 6},
      recovery: recovery,
    );
Map<String, dynamic> valid() => {
  'schemaVersion': 1,
  'summary': '根据近期跑量安排恢复与减量，目标待评估。',
  'recommendedGoalMinutes': 320,
  'warnings': <String>[],
  'tasks': List.generate(29, (i) {
    final date = DateTime(2027, 1, 1).add(Duration(days: i));
    final rest = date.weekday == 7 || i == 27;
    final km = i == 28
        ? 42.195
        : rest
        ? 0
        : i < 14
        ? 3
        : i < 21
        ? 2
        : 1;
    return <String, dynamic>{
      'date': date.toIso8601String().substring(0, 10),
      'type': i == 28
          ? 'RACE'
          : rest
          ? 'REST'
          : 'EASY',
      'title': rest ? '休息' : '轻松训练',
      'km': km,
      'notes': rest ? '恢复休息' : '轻松体感，不补跑',
      'easyPace': rest ? null : 420,
      'slowPace': rest ? null : 480,
    };
  }),
};

class FakeTransport implements AiCoachTransport {
  String response;
  int calls = 0;
  Map<String, Object>? body;
  FakeTransport(this.response);
  @override
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  }) async {
    calls++;
    this.body = body;
    return response;
  }
}

class PendingTransport implements AiCoachTransport {
  @override
  Future<String> complete({
    required Uri endpoint,
    required String apiKey,
    required Map<String, Object> body,
  }) => Completer<String>().future;
}

void main() {
  test(
    'cross-year coverage is continuous and malformed February is rejected',
    () {
      final r = GenericTrainingRequest(
        raceName: '跨年赛',
        startDate: DateTime(2026, 12, 4),
        raceDate: DateTime(2027, 1, 1),
        weeklyKm: 30,
        longestRunKm: 10,
        trainingWeekdays: {1, 2, 3, 4, 5, 6},
      );
      final payload = valid();
      for (var i = 0; i < 29; i++) {
        payload['tasks'][i]['date'] = DateTime(
          2026,
          12,
          4,
        ).add(Duration(days: i)).toIso8601String().substring(0, 10);
      }
      final draft = AiPlanGenerator.parse(jsonEncode(payload), request: r);
      expect(draft.plan['raceDate'], '2027-01-01');
      payload['tasks'][0]['date'] = '2026-02-30';
      expect(
        () => AiPlanGenerator.parse(jsonEncode(payload), request: r),
        throwsA(isA<AiCoachException>()),
      );
    },
  );
  testWidgets('deadline rejects without fallback or saving', (tester) async {
    Object? failure;
    AiPlanGenerator.generate(
      request: request(),
      config: const AiCoachConfig(
        endpoint: 'https://example.test/chat',
        model: 'fake',
      ),
      apiKey: 'fixture',
      transport: PendingTransport(),
      now: DateTime(2027, 1, 1),
    ).then<void>(
      (_) => fail('must not return draft'),
      onError: (Object e) {
        failure = e;
      },
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 91));
    expect(failure, isA<AiCoachException>());
    expect(failure.toString(), contains('超时'));
  });
  test('adjustment payload uses only bounded profile fields', () async {
    final fake = FakeTransport(
      jsonEncode({
        'schemaVersion': 1,
        'summary': '保留安排',
        'warnings': [],
        'changes': [],
      }),
    );
    await AiPlanGenerator.generateAdjustment(
      existingPlan: {
        ...valid(),
        'name': '示例赛',
        'goalMinutes': 300,
        'inputProfile': {
          'weeklyKm': 30,
          'recovery': 'good',
          'apiKey': 'never-forward',
          'unknown': 'private',
        },
      },
      now: DateTime(2027, 1, 2),
      completed: {},
      actualKm: {},
      feedback: {},
      config: const AiCoachConfig(
        endpoint: 'https://example.test/chat',
        model: 'fake',
      ),
      apiKey: 'fixture',
      transport: fake,
    );
    final body = jsonEncode(fake.body);
    expect(body, contains('weeklyKm'));
    expect(body, contains('goalMinutes'));
    expect(body, isNot(contains('never-forward')));
    expect(body, isNot(contains('private')));
  });
  test('rejects invented fast easy pace and empty training', () {
    final fast = valid();
    fast['tasks'][0]['easyPace'] = 200;
    expect(
      () => AiPlanGenerator.parse(jsonEncode(fast), request: request()),
      throwsA(isA<AiCoachException>()),
    );
    final empty = valid();
    for (final t in (empty['tasks'] as List).take(28)) {
      t['type'] = 'REST';
      t['km'] = 0;
      t['easyPace'] = null;
      t['slowPace'] = null;
    }
    expect(
      () => AiPlanGenerator.parse(jsonEncode(empty), request: request()),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('creation normalizes canonical fields and owns identity locally', () {
    final draft = AiPlanGenerator.parse(
      jsonEncode({...valid(), 'id': 'malicious', 'endpoint': 'evil'}),
      request: request(),
    );
    expect(draft.plan['id'], startsWith('ai-marathon-'));
    expect(draft.plan.containsKey('endpoint'), false);
    expect(draft.plan['name'], '示例马拉松');
    expect((draft.plan['tasks'] as List).first['type'], 'EASY');
    expect(draft.plan['inputProfile']['weeklyKm'], 30);
    expect(draft.warnings, isNotEmpty);
  });
  test('creation rejects malformed and fenced JSON', () {
    for (final input in ['no', '```json\n{}\n```', '[]', '{}']) {
      expect(
        () => AiPlanGenerator.parse(input, request: request()),
        throwsA(isA<AiCoachException>()),
      );
    }
  });
  test('rejects missing duplicate rolled-over and out of order dates', () {
    for (final date in ['2027-01-02', '2027-02-30', '2027-1-1']) {
      final data = valid();
      (data['tasks'] as List).first['date'] = date;
      expect(
        () => AiPlanGenerator.parse(jsonEncode(data), request: request()),
        throwsA(isA<AiCoachException>()),
      );
    }
    final data = valid();
    (data['tasks'] as List).removeLast();
    expect(
      () => AiPlanGenerator.parse(jsonEncode(data), request: request()),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('rejects unknown type inconsistent rest race and pace', () {
    for (final change in [
      {'type': 'UNKNOWN'},
      {'km': -1},
      {'easyPace': 500, 'slowPace': 400},
      {'type': 'REST'},
      {'easyPace': null},
      {'type': 'RACE'},
      {'notes': '<script>alert(1)</script>'},
    ]) {
      final data = valid();
      (data['tasks'] as List).first.addAll(change);
      expect(
        () => AiPlanGenerator.parse(jsonEncode(data), request: request()),
        throwsA(isA<AiCoachException>()),
      );
    }
  });
  test('rejects per-session and weekly excess', () {
    final session = valid();
    session['tasks'][0]['km'] = 11;
    expect(
      () => AiPlanGenerator.parse(jsonEncode(session), request: request()),
      throwsA(isA<AiCoachException>()),
    );
    final weekly = valid();
    for (var i = 0; i < 7; i++) {
      if (weekly['tasks'][i]['type'] == 'EASY') weekly['tasks'][i]['km'] = 6;
    }
    expect(
      () => AiPlanGenerator.parse(jsonEncode(weekly), request: request()),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('rejects consecutive hard sessions and absent taper', () {
    final data = valid();
    data['tasks'][0]['type'] = 'LONG';
    data['tasks'][1]['type'] = 'TEMPO';
    expect(
      () => AiPlanGenerator.parse(jsonEncode(data), request: request()),
      throwsA(isA<AiCoachException>()),
    );
    final taper = valid();
    taper['tasks'][25]['km'] = 10;
    expect(
      () => AiPlanGenerator.parse(jsonEncode(taper), request: request()),
      throwsA(isA<AiCoachException>()),
    );
  });
  test('rejects unavailable training day and aggressive recommended goal', () {
    final data = valid();
    data['tasks'][2].addAll({'type': 'EASY', 'km': 1});
    expect(
      () => AiPlanGenerator.parse(jsonEncode(data), request: request()),
      throwsA(isA<AiCoachException>()),
    );
    final goal = valid();
    goal['recommendedGoalMinutes'] = 250;
    expect(
      () => AiPlanGenerator.parse(jsonEncode(goal), request: request()),
      throwsA(isA<AiCoachException>()),
    );
  });
  test(
    'input guards horizon pain nonfinite and availability before network',
    () async {
      final fake = FakeTransport(jsonEncode(valid()));
      await expectLater(
        AiPlanGenerator.generate(
          request: request(recovery: 'pain'),
          config: const AiCoachConfig(
            endpoint: 'https://example.test/chat',
            model: 'fake',
          ),
          apiKey: 'fake',
          transport: fake,
          now: DateTime(2027, 1, 1),
        ),
        throwsA(isA<AiCoachException>()),
      );
      expect(fake.calls, 0);
      expect(
        () => request(race: DateTime(2027, 1, 20)).validate(),
        throwsA(isA<AiCoachException>()),
      );
      expect(
        () => request().validate(now: DateTime(2027, 1, 2)),
        throwsA(isA<AiCoachException>()),
      );
    },
  );
  test(
    'mock generation sends structured inputs and never credential in body',
    () async {
      final fake = FakeTransport(jsonEncode(valid()));
      await AiPlanGenerator.generate(
        request: request(),
        config: const AiCoachConfig(
          endpoint: 'https://example.test/chat',
          model: 'fake',
        ),
        apiKey: 'secret-fixture',
        transport: fake,
        now: DateTime(2027, 1, 1),
      );
      expect(fake.calls, 1);
      expect(jsonEncode(fake.body), isNot(contains('secret-fixture')));
      expect(jsonEncode(fake.body), contains('weekKmMaximum'));
    },
  );

  Map<String, dynamic> adjustment(List<Map<String, dynamic>> changes) => {
    'schemaVersion': 1,
    'summary': '依据训练记录降低负荷，保留比赛信息。',
    'warnings': [],
    'changes': changes,
  };
  Map<String, dynamic> change(int day, {double km = 1, String type = 'EASY'}) =>
      {
        'date': '2027-01-${day.toString().padLeft(2, '0')}',
        'type': type,
        'km': km,
        'easyPace': type == 'REST' ? null : 420,
        'slowPace': type == 'REST' ? null : 480,
        'notes': '减少负荷，观察恢复',
      };
  test('adjustment preserves all immutable tasks and source metadata', () {
    final original = {...valid(), 'id': 'plan1', 'name': '赛事'};
    final draft = AiPlanGenerator.parseAdjustment(
      jsonEncode(adjustment([change(4)])),
      existingPlan: original,
      now: DateTime(2027, 1, 2),
      completed: {'2027-01-05'},
    );
    expect(draft.plan['id'], 'plan1');
    expect(draft.plan['tasks'][0], original['tasks'][0]);
    expect(draft.plan['tasks'][1], original['tasks'][1]);
    expect(draft.plan['tasks'][3]['km'], 1);
    expect(draft.plan['tasks'][4], original['tasks'][4]);
    expect(draft.plan['tasks'][28], original['tasks'][28]);
    expect(original['tasks'][3]['km'], 3);
  });
  test('adjustment rejects past today completed race duplicates increases', () {
    for (final changes in [
      [change(1)],
      [change(2)],
      [change(5)],
      [change(29)],
      [change(4), change(4)],
      [change(4, km: 4)],
      [change(4, type: 'TEMPO')],
      [
        {...change(4), 'easyPace': 300},
      ],
      [
        {...change(4, km: 3), 'slowPace': 500},
      ],
    ]) {
      expect(
        () => AiPlanGenerator.parseAdjustment(
          jsonEncode(adjustment(changes)),
          existingPlan: valid(),
          now: DateTime(2027, 1, 2),
          completed: {'2027-01-05'},
        ),
        throwsA(isA<AiCoachException>()),
      );
    }
  });
  Map<String, dynamic> restChange(int day) => {
    'date': '2027-01-${day.toString().padLeft(2, '0')}',
    'type': 'REST',
    'km': 0,
    'easyPace': null,
    'slowPace': null,
    'notes': '移期保留恢复',
  };
  Map<String, dynamic> movable() {
    final p = valid();
    p['inputProfile'] = {
      'trainingWeekdays': [1, 2, 3, 4, 5, 6],
    };
    (p['tasks'] as List)[3] = <String, dynamic>{
      ...(p['tasks'] as List)[3],
      ...restChange(4),
    };
    return p;
  }

  Map<String, dynamic> moved(int from, int to) => {
    ...change(to, km: 3),
    'sourceDate': '2027-01-${from.toString().padLeft(2, '0')}',
  };
  AiPlanDraft moveParse(
    Map<String, dynamic> p,
    List<Map<String, dynamic>> edits,
  ) => AiPlanGenerator.parseAdjustment(
    jsonEncode(adjustment(edits)),
    existingPlan: p,
    now: DateTime(2027, 1, 2),
    completed: {},
  );
  test(
    'reschedule moves future session into an available same-week rest day',
    () {
      final p = movable();
      final draft = moveParse(p, [restChange(5), moved(5, 4)]);
      expect(draft.plan['tasks'][3]['km'], 3);
      expect(draft.plan['tasks'][4]['type'], 'REST');
      expect(draft.plan['tasks'][0], p['tasks'][0]);
      expect(draft.plan['tasks'][28], p['tasks'][28]);
      expect(draft.plan['tasks'][3].containsKey('sourceDate'), false);
    },
  );
  test('reschedule rejects copy stacking cross-week and forbidden weekday', () {
    for (final edits in [
      [moved(5, 4)],
      [restChange(5), moved(5, 6)],
      [restChange(12), moved(12, 4)],
      [restChange(5), moved(5, 3)],
      [
        restChange(5),
        {...moved(5, 4), 'km': 4},
      ],
    ]) {
      expect(
        () => moveParse(movable(), edits),
        throwsA(isA<AiCoachException>()),
      );
    }
  });
  test('reschedule rejects adjacent hard sessions', () {
    final p = valid();
    p['tasks'][3]['type'] = 'LONG';
    p['tasks'][4] = <String, dynamic>{...p['tasks'][4], ...restChange(5)};
    p['tasks'][5]['type'] = 'TEMPO';
    expect(
      () => moveParse(p, [
        restChange(4),
        {...moved(4, 5), 'type': 'LONG'},
      ]),
      throwsA(isA<AiCoachException>()),
    );
  });
  test(
    'adjustment sends only recent metrics and blocks reported pain',
    () async {
      final fake = FakeTransport(jsonEncode(adjustment([])));
      final args = {...valid(), 'raceDate': '2027-01-29'};
      await AiPlanGenerator.generateAdjustment(
        existingPlan: args,
        now: DateTime(2027, 1, 2),
        completed: {},
        actualKm: {'2025-01-01': 10, '2027-01-01': 3},
        feedback: {},
        config: const AiCoachConfig(
          endpoint: 'https://example.test/chat',
          model: 'fake',
        ),
        apiKey: 'fixture',
        transport: fake,
      );
      expect(jsonEncode(fake.body), isNot(contains('2025-01-01')));
      await expectLater(
        AiPlanGenerator.generateAdjustment(
          existingPlan: args,
          now: DateTime(2027, 1, 2),
          completed: {},
          actualKm: {},
          feedback: {
            '2027-01-01': {'pain': 1, 'fatigue': 3},
          },
          config: const AiCoachConfig(
            endpoint: 'https://example.test/chat',
            model: 'fake',
          ),
          apiKey: 'fixture',
          transport: fake,
        ),
        throwsA(isA<AiCoachException>()),
      );
      expect(fake.calls, 1);
    },
  );
}
