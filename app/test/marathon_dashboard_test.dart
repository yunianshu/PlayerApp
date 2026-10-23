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
    this.planName = '厦门马拉松',
    this.goalSummary = '目标先按 5 小时 15 分评估',
  });
  final List<TrainingTask> tasks;
  final DateTime? now;
  final VoidCallback? onSettings;
  final ValueChanged<TrainingTask>? onFeedback;
  final Future<void> Function(TrainingTask, bool)? onComplete;
  final bool reminderBusy;
  final String planName, goalSummary;
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
      planName: widget.planName,
      goalSummary: widget.goalSummary,
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

Future<void> returnToTop(WidgetTester tester) async {
  final scrollable = find
      .descendant(of: dashboardScroll, matching: find.byType(Scrollable))
      .first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
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
    'custom race and goal replace Xiamen branding in both orientations',
    (tester) async {
      const custom = DashboardHarness(
        planName: '杭州马拉松',
        goalSummary: '目标：健康完赛',
      );
      await pumpDashboard(tester, child: custom);
      expect(find.text('杭州马拉松'), findsOneWidget);
      expect(find.text('目标：健康完赛'), findsOneWidget);
      expect(find.text('厦门马拉松'), findsNothing);
      await pumpDashboard(tester, child: custom, width: 1000, height: 600);
      expect(find.text('杭州马拉松'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('training-month-calendar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'portrait swipes dates, handles gaps, picker and rotation stay synced',
    (tester) async {
      await pumpDashboard(tester);
      expect(
        find.byKey(const ValueKey('training-month-calendar')),
        findsNothing,
      );
      final pages = find.byKey(const ValueKey('training-day-pages'));
      await tester.drag(pages, const Offset(330, 0));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-26 周一'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.drag(pages, const Offset(-330, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('2026-10-29 周四'), findsOneWidget);
      expect(find.text('2026-10-29 无训练安排'), findsOneWidget);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('2026-10-29 无训练安排'));
      expect(find.text('2026-10-29 无训练安排'), findsOneWidget);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await returnToTop(tester);
      await tester.tap(find.byKey(const ValueKey('training-date-picker')));
      await tester.pumpAndSettle();
      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(picker.firstDate, DateTime(2026, 10, 26));
      expect(picker.lastDate, DateTime(2027, 1, 10));
      await tester.tap(find.text('27').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-27 周二'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('training-session-2026-10-27')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('training-return-today')));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-26 周一'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('daily pages include leap day and stop at both plan boundaries', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      child: DashboardHarness(
        now: DateTime(2024, 2, 28),
        tasks: const [
          TrainingTask('2024-02-28', 'EASY', '轻松跑', 5, ''),
          TrainingTask('2024-03-01', 'REST', '休息', 0, ''),
        ],
      ),
    );
    final pages = find.byKey(const ValueKey('training-day-pages'));
    await tester.drag(pages, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('2024-02-29 周四'), findsOneWidget);
    expect(find.text('2024-02-29 无训练安排'), findsOneWidget);
    await tester.drag(pages, const Offset(-330, 0));
    await tester.pumpAndSettle();
    await tester.drag(pages, const Offset(-330, 0));
    await tester.pumpAndSettle();
    expect(find.text('2024-03-01 周五'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('training-date-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2024-03-01 周五'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'small landscape at double text keeps seven columns without overflow',
    (tester) async {
      await pumpDashboard(
        tester,
        width: 640,
        height: 360,
        scale: 2,
        reduceMotion: true,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('training-month-calendar')),
      );
      final board = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('training-calendar-board')),
      );
      expect(board.controller!.position.maxScrollExtent, 0);
      for (var i = 0; i < 8; i++) {
        await tester.drag(dashboardScroll, const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('landscape countdown precedes calendar and selected detail', (
    tester,
  ) async {
    await pumpDashboard(tester, width: 1800, height: 1600);
    final session = find.byKey(const ValueKey('training-primary-session'));
    final navigation = find.byKey(
      const ValueKey('training-schedule-navigation'),
    );
    expect(
      find.byKey(const ValueKey('training-session-2026-10-26')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(session).dy,
      greaterThan(tester.getBottomLeft(navigation).dy),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('training-countdown-header')))
          .dy,
      lessThan(100),
    );
    expect(find.text('76 天后出发'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'today alone expands by default; collapse survives save and navigation',
    (tester) async {
      await pumpDashboard(tester, width: 1000, height: 700);
      final row = find.byKey(const ValueKey('training-week-row-2026-10-26'));
      final details = find.byKey(
        const ValueKey('training-week-details-2026-10-26'),
      );
      await reveal(tester, row);
      expect(details, findsOneWidget);
      expect(
        find.byKey(const ValueKey('training-week-details-2026-10-27')),
        findsNothing,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(details, findsNothing);
      final toggle = find.byKey(
        const ValueKey('training-week-complete-2026-10-26'),
      );
      await reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        details,
        findsNothing,
        reason: 'Saving must not reapply the expansion default.',
      );
      await returnToTop(tester);
      await reveal(tester, find.byKey(const ValueKey('training-month-next')));
      await tester.tap(find.byKey(const ValueKey('training-month-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('training-day-2026-11-02')));
      await tester.pumpAndSettle();
      await returnToTop(tester);
      await reveal(tester, find.byKey(const ValueKey('training-return-today')));
      await tester.tap(find.byKey(const ValueKey('training-return-today')));
      await tester.pumpAndSettle();
      await reveal(tester, row);
      expect(
        details,
        findsNothing,
        reason: 'Returning to today must preserve manual collapse.',
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        details,
        findsOneWidget,
        reason: 'Manual expansion must remain available.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offscreen month calendar initially shows the selected month', (
    tester,
  ) async {
    final tasks = List.generate(84, (index) {
      final date = DateTime(2026, 8, 3).add(Duration(days: index));
      return TrainingTask(
        date.toIso8601String().split('T').first,
        'EASY',
        '轻松跑',
        5,
        longNotes,
      );
    });
    await pumpDashboard(
      tester,
      child: DashboardHarness(tasks: tasks, now: DateTime(2026, 10, 19)),
      width: 1000,
      height: 600,
    );
    await reveal(tester, find.byKey(const ValueKey('training-calendar-month')));
    expect(find.text('2026年10月').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'return today resets a browsed month without changing selected date',
    (tester) async {
      await pumpDashboard(tester, width: 1000, height: 700);
      await reveal(tester, find.byKey(const ValueKey('training-month-next')));
      await tester.tap(find.byKey(const ValueKey('training-month-next')));
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);
      await returnToTop(tester);
      await reveal(tester, find.byKey(const ValueKey('training-return-today')));
      await tester.tap(find.byKey(const ValueKey('training-return-today')));
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('training-calendar-month')),
      );
      expect(find.text('2026年10月'), findsOneWidget);
    },
  );

  testWidgets('today expansion initializes after asynchronous task arrival', (
    tester,
  ) async {
    final tasks = ValueNotifier<List<TrainingTask>>([]);
    addTearDown(tasks.dispose);
    await pumpDashboard(
      tester,
      child: ValueListenableBuilder<List<TrainingTask>>(
        valueListenable: tasks,
        builder: (context, value, child) => DashboardHarness(tasks: value),
      ),
    );
    expect(find.text('暂无训练任务，请先选择或导入训练计划。'), findsOneWidget);
    tasks.value = sampleTasks;
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.byKey(const ValueKey('training-week-row-2026-10-26')),
    );
    expect(
      find.byKey(const ValueKey('training-week-details-2026-10-26')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plan without today does not expand another day as today', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      child: DashboardHarness(now: DateTime(2026, 10, 25)),
    );
    expect(
      find.byKey(const ValueKey('training-session-2026-10-26')),
      findsOneWidget,
    );
    await reveal(
      tester,
      find.byKey(const ValueKey('training-week-row-2026-10-26')),
    );
    expect(
      find.byKey(const ValueKey('training-week-details-2026-10-26')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

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
      await tester.drag(
        find.byKey(const ValueKey('training-day-pages')),
        const Offset(-330, 0),
      );
      await tester.pumpAndSettle();
      await returnToTop(tester);
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

  testWidgets('month navigation and today reset select a real task', (
    tester,
  ) async {
    await pumpDashboard(tester, width: 1000, height: 700);
    await reveal(tester, find.byKey(const ValueKey('training-month-next')));
    await tester.tap(find.byKey(const ValueKey('training-month-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('training-day-2026-11-02')));
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.byKey(const ValueKey('training-primary-session')),
    );
    expect(
      find.byKey(const ValueKey('training-session-2026-11-02')),
      findsOneWidget,
    );
    await returnToTop(tester);
    await reveal(tester, find.byKey(const ValueKey('training-return-today')));
    await tester.tap(find.byKey(const ValueKey('training-return-today')));
    await tester.pumpAndSettle();
    await reveal(
      tester,
      find.byKey(const ValueKey('training-primary-session')),
    );
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
      await returnToTop(tester);
      await tester.drag(
        find.byKey(const ValueKey('training-day-pages')),
        const Offset(-330, 0),
      );
      await tester.pumpAndSettle();
      await screenshot(tester, 'training-${mode.name}-portrait-swiped');
      // Rotation changes the presentation without recreating dashboard state.
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('training-month-calendar')),
      );
      await screenshot(tester, 'training-${mode.name}-landscape');
      await tester.tap(find.byKey(const ValueKey('training-month-next')));
      await tester.pumpAndSettle();
      await returnToTop(tester);
      await screenshot(tester, 'training-${mode.name}-landscape-november');
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('training-month-calendar')),
      );
      await screenshot(tester, 'training-${mode.name}-wide-calendar');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      await returnToTop(tester);
      expect(find.text('2026-10-24 周六'), findsOneWidget);
      await screenshot(tester, 'training-${mode.name}-portrait-return');

      expect(tester.takeException(), isNull);
    });
  }
}
