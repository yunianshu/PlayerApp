import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/pages/ai_plan_adjustment_page.dart';
import 'package:runtrail/services/ai_plan_generator.dart';

List<Map<String, dynamic>> original() => List.generate(
  15,
  (i) => {
    'date': DateTime(
      2026,
      10,
      23,
    ).add(Duration(days: i)).toIso8601String().substring(0, 10),
    'type': i == 3
        ? 'EASY'
        : i == 14
        ? 'RACE'
        : 'REST',
    'title': i == 3
        ? '轻松跑'
        : i == 14
        ? '比赛'
        : '恢复休息',
    'km': i == 3
        ? 8.0
        : i == 14
        ? 42.195
        : 0.0,
    'notes': i == 3 ? '保持轻松谈话强度，不追求速度。' : '休息恢复，不补跑。',
    'easyPace': i == 3 ? 420 : null,
    'slowPace': i == 3 ? 480 : null,
  },
);
AiPlanDraft proposal() => AiPlanGenerator.parseAdjustment(
  jsonEncode({
    'schemaVersion': 1,
    'summary': '模拟 AI 预览，未调用真实服务。近期反馈偏疲劳，将下次轻松跑减至 5 公里，保留恢复日。',
    'warnings': ['训练建议不保证成绩；疼痛时停止相关训练并寻求专业评估。'],
    'changes': [
      {
        'date': '2026-10-26',
        'type': 'EASY',
        'km': 5.0,
        'easyPace': 450,
        'slowPace': 480,
        'notes': '以舒适体感完成，若疲劳持续则休息，不补跑。',
      },
    ],
  }),
  existingPlan: {
    'name': '秋日马拉松 · 模拟方案',
    'raceDate': '2026-11-06',
    'tasks': original(),
  },
  now: DateTime(2026, 10, 23),
  completed: {},
);

// Screenshot-only simulated example: unchanged runs are included in week totals.
List<Map<String, dynamic>> screenshotOriginal() => List.generate(31, (i) {
  final date = DateTime(
    2026,
    10,
    23,
  ).add(Duration(days: i)).toIso8601String().substring(0, 10);
  final km =
      {
        '2026-10-26': 6.0,
        '2026-10-28': 4.0,
        '2026-10-29': 8.0,
        '2026-11-01': 18.0,
      }[date] ??
      0.0;
  return {
    'date': date,
    'type': km == 18
        ? 'LONG'
        : km > 0
        ? 'EASY'
        : 'REST',
    'title': km == 18
        ? '长距离'
        : km > 0
        ? '轻松跑'
        : '恢复休息',
    'km': km,
    'notes': km > 0 ? '维持轻松体感，避免追求速度。' : '休息恢复，不补跑。',
    'easyPace': km > 0 ? 420 : null,
    'slowPace': km > 0 ? 480 : null,
  };
});
AiPlanDraft screenshotProposal() => AiPlanDraft(
  plan: {
    'name': '秋日马拉松 · 模拟方案',
    'raceDate': '2026-11-22',
    'tasks': screenshotOriginal()
        .map(
          (t) => {
            ...t,
            if (t['date'] == '2026-10-29') ...{
              'km': 6.0,
              'notes': '缩短距离，维持轻松强度；疲劳持续则休息。',
            },
            if (t['date'] == '2026-11-01') ...{
              'km': 12.0,
              'notes': '保留长跑安排，减少单次负荷，不补跑遗漏公里。',
            },
          },
        )
        .toList(),
  },
  summary: '模拟 AI 预览，未调用真实服务。示例反馈为疲劳偏高，建议缩短两次训练，不把遗漏跑量补回来。',
  warnings: ['示例数据不是训练处方。建议不保证成绩；疼痛时停止相关训练并寻求专业评估。'],
);

Future<void> pumpReview(
  WidgetTester tester,
  AppThemeMode mode, {
  double width = 430,
  double height = 932,
  double scale = 1,
  ValueChanged<bool?>? onResult,
  bool screenshotFixture = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = ThemeController()..mode = mode;
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        theme: buildTheme(controller.effectiveStyle),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const Key('adjust-capture'),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AiPlanAdjustmentPage(
                      draft: screenshotFixture
                          ? screenshotProposal()
                          : proposal(),
                      before: screenshotFixture
                          ? screenshotOriginal()
                          : original(),
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('review'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('review'));
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    testWidgets('${mode.name}: real adjustment rendering', (tester) async {
      final output = Platform.environment['AI_PLAN_SCREENSHOT_DIR'];
      if (output != null) {
        await tester.runAsync(() async {
          final regular = await rootBundle.load(
            'assets/fonts/NotoSansSC-Regular.ttf',
          );
          for (final family in ['Roboto', 'Noto Sans SC', 'Inter']) {
            await (FontLoader(family)..addFont(Future.value(regular))).load();
          }
          await (FontLoader('Barlow Condensed')..addFont(
                rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'),
              ))
              .load();
          await (FontLoader('Playfair Display')..addFont(
                rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf'),
              ))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      await pumpReview(
        tester,
        mode,
        height: output == null ? 932 : 1400,
        screenshotFixture: output != null,
      );
      expect(find.text('把调整，看清楚再决定。'), findsOneWidget);
      expect(find.text(output == null ? '1 个日期变化' : '2 个日期变化'), findsOneWidget);
      if (output != null) {
        expect(find.text('36 → 28 km', findRichText: true), findsOneWidget);
        expect(find.text('-8 km'), findsOneWidget);
      }
      expect(find.byKey(const Key('adjustment-change-count')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (output != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('adjust-capture')),
        );
        await tester.runAsync(() async {
          final capture = await boundary.toImage(pixelRatio: 1);
          final bytes = await capture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(output).create(recursive: true);
          await File('$output/ai-plan-${mode.name}-adjustment.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          capture.dispose();
        });
      }
    });
  }
  testWidgets(
    '320px doubled text scrolls without overflow and cancellation returns false',
    (tester) async {
      bool? result;
      await pumpReview(
        tester,
        AppThemeMode.editorial,
        width: 320,
        height: 640,
        scale: 2,
        onResult: (v) => result = v,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('adjustment-cancel')),
        400,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('adjustment-cancel')));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
  testWidgets('confirm returns true only after explicit tap', (tester) async {
    bool? result;
    await pumpReview(tester, AppThemeMode.dark, onResult: (v) => result = v);
    expect(result, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('adjustment-confirm')),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('adjustment-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets(
    'week totals include unchanged days and preserve cross-year labels',
    (tester) async {
      final before = [
        {
          'date': '2026-12-28',
          'type': 'EASY',
          'title': '轻松跑',
          'notes': '不变',
          'km': 10.0,
        },
        {
          'date': '2026-12-30',
          'type': 'EASY',
          'title': '轻松跑',
          'notes': '原说明',
          'km': 8.0,
        },
        {
          'date': '2027-01-03',
          'type': 'REST',
          'title': '恢复',
          'notes': '休息',
          'km': 0.0,
        },
      ];
      final after = [
        before[0],
        {...before[1], 'km': 6.0, 'notes': '建议说明'},
        before[2],
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: AiPlanAdjustmentPage(
            before: before,
            draft: AiPlanDraft(
              plan: {'name': '跨年比赛', 'tasks': after},
              summary: '仅缩短一次训练',
              warnings: ['完整警示'],
            ),
          ),
        ),
      );
      expect(find.text('周计划跑量 · 2026.12.28—2027.01.03'), findsOneWidget);
      expect(find.text('18 → 16 km', findRichText: true), findsOneWidget);
      expect(find.text('1 个日期变化'), findsOneWidget);
      expect(find.text('-2 km'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('配速与完整对比'), 200);
      await tester.tap(find.text('配速与完整对比'));
      await tester.pumpAndSettle();
      expect(find.text('原说明'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('system back does not apply', (tester) async {
    bool? result;
    await pumpReview(tester, AppThemeMode.light, onResult: (v) => result = v);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('review'), findsOneWidget);
  });
}
