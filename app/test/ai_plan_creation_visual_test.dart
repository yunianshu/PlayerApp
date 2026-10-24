import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/pages/ai_plan_creation_page.dart';
import 'package:runtrail/services/ai_plan_generator.dart';

import 'ai_plan_creation_page_test.dart' as fixtures;

AiPlanDraft synthetic(GenericTrainingRequest r) => AiPlanGenerator.parse(
  jsonEncode({
    'schemaVersion': 1,
    'summary': '模拟 AI 预览：使用合成数据，经真实逐日格式与负荷规则校验。以轻松训练和恢复为主，不代表已具备全马能力。',
    'recommendedGoalMinutes': null,
    'warnings': ['仅演示界面，未调用真实 AI；备赛基础需持续评估。'],
    'tasks': List.generate(r.days + 1, (i) {
      final d = r.startDate.add(Duration(days: i));
      final remaining = r.days - i;
      final race = remaining == 0;
      final rest = !r.trainingWeekdays.contains(d.weekday) || remaining == 1;
      return {
        'date': d.toIso8601String().substring(0, 10),
        'type': race
            ? 'race'
            : rest
            ? 'rest'
            : 'easy',
        'title': race
            ? '比赛日'
            : rest
            ? '恢复休息'
            : '轻松跑',
        'km': race
            ? 42.195
            : rest
            ? 0
            : remaining < 7
            ? 1
            : remaining < 14
            ? 2
            : 4,
        'notes': race
            ? '按实际能力评估参赛，不承诺完赛'
            : rest
            ? '休息恢复，不补跑'
            : '保持可交谈的轻松体感',
        'easyPace': null,
        'slowPace': null,
      };
    }),
  }),
  request: r,
  model: '模拟模型 · 无网络请求',
);
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('render validated synthetic plan in three themes', (
    tester,
  ) async {
    // Widget tests have no operating-system CJK fallback. Register the bundled
    // CJK font for default and explicit families without changing production fonts.
    for (final family in ['Ahem', 'Roboto', 'Noto Sans SC', 'Inter']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf')))
          .load();
    }
    final output = Platform.environment['AI_PLAN_PREVIEW_DIR'];
    await (FontLoader(
          'Playfair Display',
        )..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Regular.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final style in AppThemeStyle.values) {
      final boundary = GlobalKey();
      final theme = buildTheme(style);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Noto Sans SC'),
            ),
            home: AiPlanCreationPage(
              key: ValueKey(style),
              now: DateTime(2026, 10, 23),
              loadSettings: () async => fixtures.settings,
              generate: (r, _) async => synthetic(r),
              saveDraft: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String screen) async {
        if (output == null) return;
        await tester.runAsync(() async {
          final img =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/ai-plan-${style.name}-$screen.png')
              .writeAsBytes(data!.buffer.asUint8List());
          img.dispose();
        });
      }

      await capture('race');
      await fixtures.fillRace(tester, name: '模拟 AI 示例赛事');
      await tester.enterText(find.byKey(const Key('plan-weekly')), '20');
      await tester.enterText(find.byKey(const Key('plan-longest')), '10');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture('form');
      await fixtures.fillAbility(tester);
      await capture('rhythm');
      await fixtures.tapKey(tester, 'plan-generate');
      await tester.tap(find.text('同意发送并生成'));
      await tester.pumpAndSettle();
      expect(find.textContaining('113 天逐日安排'), findsOneWidget);
      await capture('mock-review');
      await tester.ensureVisible(find.byKey(const Key('plan-week-0')));
      await tester.pumpAndSettle();
      await capture('mock-week');
      expect(tester.takeException(), isNull);
    }
  });
}
