import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/widgets/training_month_calendar.dart';

import 'marathon_dashboard_test.dart' show pumpDashboard;

const tasks = [
  TrainingTask('2023-12-31', 'EASY', '年末轻松跑', 5, ''),
  TrainingTask('2024-01-01', 'REST', '恢复日', 0, ''),
  TrainingTask('2024-02-29', 'LONG', '闰日长跑', 10, ''),
];

Future<void> pumpCalendar(
  WidgetTester tester, {
  String selected = '2023-12-31',
  Set<String> completed = const {},
  ValueChanged<TrainingTask>? onSelect,
}) => pumpDashboard(
  tester,
  height: 1100,
  child: Scaffold(
    body: SingleChildScrollView(
      child: TrainingMonthCalendar(
        tasks: tasks,
        completed: completed,
        selectedDate: selected,
        today: '2024-01-01',
        onSelect: onSelect ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'one horizontal board keeps weeks aligned and preserves manual scroll',
    (tester) async {
      final checkins = ValueNotifier<Set<String>>({});
      addTearDown(checkins.dispose);
      final plan = List.generate(
        14,
        (i) => TrainingTask(
          '2024-01-${(i + 1).toString().padLeft(2, '0')}',
          'EASY',
          '轻松跑',
          5,
          '轻松完成训练。',
          easyPace: 420,
          slowPace: 450,
        ),
      );
      String? selected;
      await pumpDashboard(
        tester,
        height: 1100,
        child: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<Set<String>>(
              valueListenable: checkins,
              builder: (context, completed, _) => TrainingMonthCalendar(
                tasks: plan,
                completed: completed,
                selectedDate: '2024-01-05',
                today: '2024-01-05',
                onSelect: (task) => selected = task.date,
              ),
            ),
          ),
        ),
      );
      final board = find.byKey(const ValueKey('training-calendar-board'));
      final scroll = tester.widget<SingleChildScrollView>(board).controller!;
      expect(
        scroll.offset,
        greaterThan(0),
        reason: 'Initially expose today column.',
      );
      expect(
        find.byKey(const ValueKey('training-calendar-scroll-hint')),
        findsOneWidget,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('training-day-2024-01-05')))
            .dx,
        tester
            .getTopLeft(find.byKey(const ValueKey('training-day-2024-01-12')))
            .dx,
      );
      await tester.drag(board, const Offset(220, 0));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      checkins.value = {'2024-01-01'};
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        offset,
        reason: 'Completion rebuild must not undo a manual swipe.',
      );
      final target = find.byKey(const ValueKey('training-day-2024-01-03'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      expect(selected, '2024-01-03');
      expect(find.text('5 km'), findsWidgets);
      expect(find.text('7:00–7:30 /km'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'seven readable card columns fit a wide screen without scrolling',
    (tester) async {
      await pumpDashboard(
        tester,
        width: 1600,
        height: 1800,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TrainingMonthCalendar(
              tasks: tasks,
              completed: const {},
              selectedDate: '2023-12-31',
              today: '2024-01-01',
              onSelect: (_) {},
            ),
          ),
        ),
      );
      final board = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('training-calendar-board')),
      );
      expect(board.controller!.position.maxScrollExtent, 0);
      expect(
        find.byKey(const ValueKey('training-calendar-scroll-hint')),
        findsNothing,
      );
      final first = tester.getTopLeft(
        find.byKey(const ValueKey('training-day-2023-12-04')),
      );
      final last = tester.getTopRight(
        find.byKey(const ValueKey('training-day-2023-12-10')),
      );
      expect(first.dx, greaterThanOrEqualTo(0));
      expect(last.dx, lessThanOrEqualTo(1600));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('natural months handle December, January and leap February', (
    tester,
  ) async {
    await pumpCalendar(tester);
    expect(find.text('2023年12月'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('training-month-previous')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('training-month-next')));
    await tester.pumpAndSettle();
    expect(find.text('2024年1月'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('training-month-next')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('training-day-2024-02-29')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('training-day-2024-02-30')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('training-month-next')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('outside-plan dates are disabled and do not invent training', (
    tester,
  ) async {
    var calls = 0;
    await pumpCalendar(
      tester,
      selected: '2024-01-01',
      onSelect: (_) => calls++,
    );
    final noTask = find.byKey(const ValueKey('training-day-2024-01-02'));
    expect(tester.widget<InkWell>(noTask).onTap, isNull);
    await tester.tap(noTask);
    expect(calls, 0);
    final semantics = tester.widget<Semantics>(
      find.byKey(const ValueKey('training-calendar-semantics-2024-01-02')),
    );
    expect(semantics.properties.label, '2024-01-02 无训练安排');
    expect(semantics.properties.enabled, false);
    await tester.tap(find.byKey(const ValueKey('training-day-2024-01-01')));
    expect(calls, 1);
  });

  testWidgets(
    'past pending, rest, today and completed have explicit semantics',
    (tester) async {
      await pumpCalendar(tester);
      var cell = tester.widget<Semantics>(
        find.byKey(const ValueKey('training-calendar-semantics-2023-12-31')),
      );
      expect(cell.properties.label, contains('暂无跑步记录'));
      expect(cell.properties.label, isNot(contains('漏练')));
      await pumpCalendar(tester, selected: '2024-01-01');
      cell = tester.widget<Semantics>(
        find.byKey(const ValueKey('training-calendar-semantics-2024-01-01')),
      );
      expect(cell.properties.label, contains('今天 非跑步任务'));
      expect(cell.properties.selected, true);
      await pumpCalendar(
        tester,
        selected: '2024-01-01',
        completed: {'2024-01-01'},
      );
      cell = tester.widget<Semantics>(
        find.byKey(const ValueKey('training-calendar-semantics-2024-01-01')),
      );
      expect(cell.properties.label, contains('已手动完成'));
      expect(find.text('计划 0 km · 已完成 1/1 天'), findsOneWidget);
    },
  );
}
