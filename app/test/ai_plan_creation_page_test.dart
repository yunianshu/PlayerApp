import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/pages/ai_plan_creation_page.dart';
import 'package:runtrail/services/ai_coach_settings.dart';
import 'package:runtrail/services/ai_plan_generator.dart';

const settings = AiCoachSettings(
  config: AiCoachConfig(
    endpoint: 'https://example.invalid/v1/chat/completions',
    model: 'fake-model',
  ),
  apiKey: 'fake-widget-key',
  secureStorageAvailable: true,
  sessionOnly: false,
);
const draft = AiPlanDraft(
  plan: {
    'id': 'fake-plan',
    'name': '测试马拉松',
    'raceDate': '2027-02-12',
    'tasks': [
      {
        'date': '2026-10-23',
        'type': 'EASY',
        'title': '轻松跑',
        'km': 4.0,
        'notes': '测试安排，不是真实生成结果',
        'easyPace': 480,
        'slowPace': 540,
      },
    ],
  },
  warnings: ['测试警告'],
  summary: '测试生成概要',
);

Future<void> showPage(
  WidgetTester tester, {
  PlanGenerationAction? generate,
  Future<void> Function(Map<String, dynamic>)? save,
  AiCoachSettings config = settings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiPlanCreationPage(
                  now: DateTime(2026, 10, 23),
                  loadSettings: () async => config,
                  generate: generate ?? (request, settings) async => draft,
                  saveDraft: save ?? (_) async {},
                ),
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  if (key == 'plan-generate') {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> fillRace(WidgetTester tester, {String name = '测试马拉松'}) async {
  await tester.enterText(find.byKey(const Key('plan-name')), name);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tapKey(tester, 'plan-race-date');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tapKey(tester, 'plan-next');
}

Future<void> fillAbility(WidgetTester tester) async {
  for (final pair in [('plan-weekly', '20'), ('plan-longest', '10')]) {
    await tester.ensureVisible(find.byKey(Key(pair.$1)));
    await tester.enterText(find.byKey(Key(pair.$1)), pair.$2);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tapKey(tester, 'plan-next');
}

Future<void> fill(WidgetTester tester, {String name = '测试马拉松'}) async {
  await fillRace(tester, name: name);
  await fillAbility(tester);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('invalid input never loads generation or asks consent', (
    tester,
  ) async {
    var calls = 0;
    await showPage(
      tester,
      generate: (request, settings) async {
        calls++;
        return draft;
      },
    );
    await tapKey(tester, 'plan-next');
    expect(calls, 0);
    expect(find.text('请输入赛事名称'), findsOneWidget);
  });
  testWidgets(
    'consent names provider and health fields; cancel sends nothing',
    (tester) async {
      var calls = 0;
      await showPage(
        tester,
        generate: (request, settings) async {
          calls++;
          return draft;
        },
      );
      await fill(tester);
      await tapKey(tester, 'plan-generate');
      expect(find.text('确认发送并生成计划'), findsOneWidget);
      expect(find.textContaining('example.invalid'), findsOneWidget);
      expect(find.textContaining('恢复状态属于健康相关信息'), findsOneWidget);
      expect(calls, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const Key('plan-generate')), findsOneWidget);
    },
  );
  testWidgets(
    'generation preview requires separate save and can return without saving',
    (tester) async {
      var calls = 0;
      var saves = 0;
      await showPage(
        tester,
        generate: (request, settings) async {
          calls++;
          return draft;
        },
        save: (_) async {
          saves++;
        },
      );
      await fill(tester);
      await tapKey(tester, 'plan-generate');
      await tester.tap(find.text('同意发送并生成'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(saves, 0);
      expect(find.text('AI 计划预览 · 尚未保存'), findsOneWidget);
      await tester.ensureVisible(find.text('返回修改，不保存'));
      await tester.tap(find.text('返回修改，不保存'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('已选 3 天 / 周 · 比赛日单独安排'), findsOneWidget);
    },
  );
  testWidgets(
    'confirm saves once and leaves page; no activation action exists',
    (tester) async {
      var saves = 0;
      await showPage(
        tester,
        save: (plan) async {
          saves++;
          expect(plan['id'], 'fake-plan');
        },
      );
      await fill(tester);
      await tapKey(tester, 'plan-generate');
      await tester.tap(find.text('同意发送并生成'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'plan-save');
      expect(saves, 1);
      expect(find.text('打开'), findsOneWidget);
    },
  );
  testWidgets('cancel pending request ignores late result and never saves', (
    tester,
  ) async {
    final completer = Completer<AiPlanDraft>();
    var calls = 0;
    var saves = 0;
    await showPage(
      tester,
      generate: (request, settings) {
        calls++;
        return completer.future;
      },
      save: (_) async {
        saves++;
      },
    );
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    await tester.tap(find.text('同意发送并生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, 1);
    await tester.tap(find.text('取消等待'));
    await tester.pumpAndSettle();
    completer.complete(draft);
    await tester.pumpAndSettle();
    expect(find.text('AI 计划预览 · 尚未保存'), findsNothing);
    expect(saves, 0);
  });
  testWidgets('missing credentials offers setup without generation', (
    tester,
  ) async {
    var calls = 0;
    await showPage(
      tester,
      config: const AiCoachSettings(
        config: null,
        apiKey: null,
        secureStorageAvailable: false,
        sessionOnly: false,
      ),
      generate: (request, settings) async {
        calls++;
        return draft;
      },
    );
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    expect(find.text('先配置 AI 服务'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
  testWidgets('leaving generation ignores late result without saving', (
    tester,
  ) async {
    final completer = Completer<AiPlanDraft>();
    var saves = 0;
    await showPage(
      tester,
      generate: (_, _) => completer.future,
      save: (_) async {
        saves++;
      },
    );
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    await tester.tap(find.text('同意发送并生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pageBack();
    await tester.pumpAndSettle();
    completer.complete(draft);
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid model result shows error without a fallback or save', (
    tester,
  ) async {
    var saves = 0;
    await showPage(
      tester,
      generate: (_, _) async {
        throw const FormatException('invalid structured plan');
      },
      save: (_) async {
        saves++;
      },
    );
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    await tester.tap(find.text('同意发送并生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('未保存或更改原计划'), findsOneWidget);
    expect(find.text('AI 计划预览 · 尚未保存'), findsNothing);
    expect(saves, 0);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
  testWidgets('provider changes during request invalidate generated draft', (
    tester,
  ) async {
    final response = Completer<AiPlanDraft>();
    var current = settings;
    await tester.pumpWidget(
      MaterialApp(
        home: AiPlanCreationPage(
          now: DateTime(2026, 10, 23),
          loadSettings: () async => current,
          generate: (_, _) => response.future,
          saveDraft: (_) async {},
        ),
      ),
    );
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    await tester.tap(find.text('同意发送并生成'));
    await tester.pump();
    current = const AiCoachSettings(
      config: AiCoachConfig(
        endpoint: 'https://changed.invalid/v1/chat/completions',
        model: 'other',
      ),
      apiKey: 'synthetic',
      secureStorageAvailable: true,
      sessionOnly: false,
    );
    response.complete(draft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('AI 服务配置已变化'), findsOneWidget);
    expect(find.text('AI 计划预览 · 尚未保存'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
  testWidgets(
    '320px large text ability remains scrollable with keyboard and reduced motion',
    (tester) async {
      await showPage(tester);
      await fillRace(tester);
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('plan-weekly')));
      await tester.enterText(find.byKey(const Key('plan-weekly')), '20');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('plan-next')).hitTestable(), findsOneWidget);
    },
  );
  testWidgets('320px large text review keeps confirm and cancel reachable', (
    tester,
  ) async {
    await showPage(tester);
    await fill(tester);
    await tapKey(tester, 'plan-generate');
    await tester.tap(find.text('同意发送并生成'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-save')).hitTestable(), findsOneWidget);
    expect(find.text('返回修改，不保存').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'changing settings theme preserves in-progress form and weekdays',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.setMode(AppThemeMode.light);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: AnimatedBuilder(
            animation: controller,
            builder: (_, _) => MaterialApp(
              theme: buildTheme(controller.effectiveStyle),
              home: AiPlanCreationPage(
                now: DateTime(2026, 10, 23),
                loadSettings: () async => settings,
              ),
            ),
          ),
        ),
      );
      await fill(tester, name: '主题切换测试');
      await tester.ensureVisible(find.text('周一'));
      await tester.tap(find.text('周一'));
      await tester.pumpAndSettle();
      for (final mode in [
        AppThemeMode.dark,
        AppThemeMode.editorial,
        AppThemeMode.light,
      ]) {
        await controller.setMode(mode);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, '周一'))
              .selected,
          isTrue,
        );
        expect(find.text('已选 4 天 / 周 · 比赛日单独安排'), findsOneWidget);
        await tapKey(tester, 'plan-back');
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('plan-weekly')))
              .controller!
              .text,
          '20',
        );
        await tapKey(tester, 'plan-back');
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('plan-name')))
              .controller!
              .text,
          '主题切换测试',
        );
        await tapKey(tester, 'plan-next');
        await tapKey(tester, 'plan-next');
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'wizard validates each step and preserves optional goal and ability fields',
    (tester) async {
      GenericTrainingRequest? sent;
      await showPage(
        tester,
        generate: (request, _) async {
          sent = request;
          return draft;
        },
      );
      await tester.enterText(find.byKey(const Key('plan-name')), '完整字段测试');
      await tapKey(tester, 'plan-next');
      expect(find.byKey(const Key('plan-name')), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await tester.tap(find.text('设置目标成绩'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('plan-goal-hours')), '5');
      await tester.enterText(find.byKey(const Key('plan-goal-minutes')), '30');
      await tapKey(tester, 'plan-race-date');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'plan-next');
      await tapKey(tester, 'plan-next');
      expect(find.byKey(const Key('plan-weekly')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('plan-ten-km')), '65');
      await fillAbility(tester);
      await tapKey(tester, 'plan-back');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('plan-ten-km')))
            .controller!
            .text,
        '65',
      );
      await tapKey(tester, 'plan-next');
      await tapKey(tester, 'plan-generate');
      await tester.tap(find.text('同意发送并生成'));
      await tester.pumpAndSettle();
      expect(sent!.raceName, '完整字段测试');
      expect(sent!.goalMinutes, 330);
      expect(sent!.recent10kMinutes, 65);
      expect(sent!.weeklyKm, 20);
      expect(sent!.longestRunKm, 10);
      expect(sent!.trainingWeekdays, {2, 4, 7});
    },
  );
  testWidgets(
    'review uses actual weekly totals excluding race and expands later weeks',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final many = AiPlanDraft(
        plan: {
          ...draft.plan,
          'tasks': List.generate(
            8,
            (i) => {
              'date': '2026-10-${23 + i}',
              'type': i == 7 ? 'RACE' : 'EASY',
              'km': i == 7 ? 42.195 : 4.0,
              'title': i == 7 ? '赛事当天' : '轻松跑',
              'notes': i == 7 ? '后续周详情' : '逐日训练',
              'easyPace': null,
              'slowPace': null,
            },
          ),
        },
        warnings: ['风险仍需完整阅读'],
        summary: '真实条目求和的测试',
      );
      await showPage(tester, generate: (_, _) async => many);
      await fill(tester);
      await tapKey(tester, 'plan-generate');
      await tester.tap(find.text('同意发送并生成'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('第 1 周，28.0 公里'), findsOneWidget);
      expect(find.bySemanticsLabel('第 2 周，0.0 公里'), findsOneWidget);
      expect(find.text('后续周详情'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('plan-week-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-week-1')));
      await tester.pumpAndSettle();
      expect(find.text('后续周详情'), findsOneWidget);
      expect(find.textContaining('风险仍需完整阅读'), findsOneWidget);
      semantics.dispose();
    },
  );
}
