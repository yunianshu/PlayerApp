import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/widgets/marathon_training_dashboard.dart';

const longNotes =
    '先进行十分钟动态热身，再以可以完整说话的强度慢跑。训练中如果出现持续疼痛，应立即停止并记录身体反馈。训练结束后步行放松十分钟，补充水分，不需要补跑前一天遗漏的公里数。';
const sampleTasks = [
  TrainingTask(
    '2026-10-26',
    'EASY',
    '轻松跑与跑后放松',
    5,
    longNotes,
    easyPace: 420,
    slowPace: 450,
  ),
  TrainingTask('2026-10-27', 'REST', '恢复与力量训练', 0, '休息或步行，并完成温和的髋部与核心力量练习。'),
  TrainingTask(
    '2026-10-28',
    'EASY',
    '轻松跑',
    6,
    '保持轻松呼吸。',
    easyPace: 420,
    slowPace: 450,
  ),
  TrainingTask(
    '2026-11-02',
    'LONG',
    '长距离训练',
    12,
    '放慢配速，控制强度。',
    easyPace: 430,
    slowPace: 470,
  ),
  TrainingTask('2027-01-10', 'RACE', '厦门马拉松', 42.195, '根据身体状态稳妥参赛。'),
];

class DashboardHarness extends StatefulWidget {
  const DashboardHarness({
    super.key,
    this.tasks = sampleTasks,
    this.now,
    this.onSettings,
    this.onFeedback,
    this.onComplete,
    this.reminderBusy = false,
  });
  final List<TrainingTask> tasks;
  final DateTime? now;
  final VoidCallback? onSettings;
  final ValueChanged<TrainingTask>? onFeedback;
  final Future<void> Function(TrainingTask, bool)? onComplete;
  final bool reminderBusy;
  @override
  State<DashboardHarness> createState() => _DashboardHarnessState();
}

class _DashboardHarnessState extends State<DashboardHarness> {
  final Set<String> done = {};
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('训练计划'),
      leading: const BackButton(),
      actions: [
        IconButton(
          onPressed: () {},
          tooltip: 'AI 服务设置',
          icon: const Icon(Icons.tune_rounded),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_outlined),
        ),
      ],
    ),
    body: MarathonTrainingDashboard(
      tasks: widget.tasks,
      now: widget.now ?? DateTime(2026, 10, 26),
      completed: done,
      runsByDate: const {},
      feedback: const {},
      reminderEnabled: true,
      reminderHour: 6,
      reminderMinute: 30,
      reminderBusy: widget.reminderBusy,
      usesDailySummary: true,
      onComplete: (task, value) async {
        await widget.onComplete?.call(task, value);
        if (mounted) {
          setState(() => value ? done.add(task.date) : done.remove(task.date));
        }
      },
      onFeedback: widget.onFeedback ?? (_) {},
      onAiReview: () {},
      onAiSettings: widget.onSettings ?? () {},
      onSuggestAdjustments: () {},
      onReminderChanged: (_) {},
      onReminderTime: () {},
    ),
  );
}

Future<void> pumpDashboard(
  WidgetTester tester, {
  Widget child = const DashboardHarness(),
  double width = 390,
  double height = 844,
  double scale = 1,
  bool reduceMotion = false,
  AppThemeMode mode = AppThemeMode.light,
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
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('training-capture'),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get dashboardScroll =>
    find.byKey(const ValueKey('training-dashboard-scroll'));

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: find
        .descendant(of: dashboardScroll, matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final path = Platform.environment['TRAINING_SCREENSHOT_DIR'];
  if (path == null) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('training-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(path).create(recursive: true);
    await File('$path/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'full daily text is visible without truncation; selection changes session',
    (tester) async {
      await pumpDashboard(tester);
      final notes = tester.widget<Text>(
        find.byKey(const ValueKey('training-full-notes-2026-10-26')),
      );
      expect(notes.data, longNotes);
      expect(notes.maxLines, isNull);
      expect(notes.overflow, isNull);
      await tester.tap(find.byKey(const ValueKey('training-day-2026-10-27')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AnimatedSwitcher), findsWidgets);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('training-session-2026-10-27')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('training-full-notes-2026-10-27')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion updates progress, is reversible and keeps notes readable',
    (tester) async {
      await pumpDashboard(tester);
      final complete = find.byKey(
        const ValueKey('training-complete-2026-10-26'),
      );
      await reveal(tester, complete);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.text('已完成 · 点击撤销'), findsOneWidget);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.text('标记为已完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekly overview expands full notes and AI settings remains accessible',
    (tester) async {
      var openedSettings = 0;
      await pumpDashboard(
        tester,
        child: DashboardHarness(onSettings: () => openedSettings++),
      );
      await reveal(tester, find.byKey(const ValueKey('training-ai-settings')));
      await tester.tap(find.byKey(const ValueKey('training-ai-settings')));
      expect(openedSettings, 1);
      final row = find.byKey(const ValueKey('training-week-row-2026-10-27'));
      await reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('休息或步行，并完成温和的髋部与核心力量练习。'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('week navigation and today reset select a real task', (
    tester,
  ) async {
    await pumpDashboard(tester);
    await tester.tap(find.text('第 2 周'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('training-session-2026-11-02')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('training-return-today')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('training-session-2026-10-26')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320px, 200 percent text, reduced motion: no overflow throughout page',
    (tester) async {
      await pumpDashboard(tester, width: 320, scale: 2, reduceMotion: true);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 18; i++) {
        await tester.drag(dashboardScroll, const Offset(0, -450));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'scroll step $i');
      }
      final animations = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animations.every((widget) => widget.duration == Duration.zero),
        isTrue,
      );
    },
  );

  testWidgets('weekly circular toggle does not also expand its parent row', (
    tester,
  ) async {
    var calls = 0;
    await pumpDashboard(
      tester,
      child: DashboardHarness(
        onComplete: (task, value) async {
          calls++;
        },
      ),
    );
    final toggle = find.byKey(
      const ValueKey('training-week-complete-2026-10-27'),
    );
    await reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('恢复 / 力量 · 已完成'), findsOneWidget);
    expect(find.text('休息或步行，并完成温和的髋部与核心力量练习。'), findsNothing);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('恢复 / 力量 · 已完成'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending reminders disable controls and explain finite daily summary',
    (tester) async {
      await pumpDashboard(
        tester,
        child: const DashboardHarness(reminderBusy: true),
      );
      await reveal(tester, find.byType(Switch));
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(find.text('每日提醒打开今日计划，至本期计划结束'), findsOneWidget);
      final time = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('06:30  更改时间'),
          matching: find.byType(TextButton),
        ),
      );
      expect(time.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    testWidgets('real plan ${mode.name} native rendering', (tester) async {
      if (Platform.environment['TRAINING_SCREENSHOT_DIR'] != null) {
        await tester.runAsync(() async {
          final regular = await rootBundle.load(
            'assets/fonts/NotoSansSC-Regular.ttf',
          );
          for (final family in ['Roboto', 'Noto Sans SC']) {
            final font = FontLoader(family)..addFont(Future.value(regular));
            await font.load();
          }
          final display = FontLoader('Barlow Condensed')
            ..addFont(rootBundle.load('assets/fonts/BarlowCondensed-Bold.ttf'));
          final serif = FontLoader('Playfair Display')
            ..addFont(rootBundle.load('assets/fonts/PlayfairDisplay-Bold.ttf'));
          await display.load();
          await serif.load();
          final icons = FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
          await icons.load();
        });
      }
      final tasks = (await tester.runAsync(
        () => MarathonTrainingService.load(),
      ))!;
      await pumpDashboard(
        tester,
        child: DashboardHarness(tasks: tasks, now: DateTime(2026, 10, 23)),
        mode: mode,
      );
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'training-${mode.name}-top');
      await tester.drag(dashboardScroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'training-${mode.name}-details');
      final toggle = find.byKey(
        const ValueKey('training-week-complete-2026-10-23'),
      );
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await screenshot(tester, 'training-${mode.name}-checked-details');
      expect(tester.takeException(), isNull);
    });
  }
}
