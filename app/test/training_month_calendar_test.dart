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
    body: TrainingMonthCalendar(
      tasks: tasks,
      completed: completed,
      selectedDate: selected,
      today: '2024-01-01',
      onSelect: onSelect ?? (_) {},
    ),
  ),
);

void main() {
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
      expect(cell.properties.label, contains('未记录完成'));
      expect(cell.properties.label, isNot(contains('漏练')));
      await pumpCalendar(tester, selected: '2024-01-01');
      cell = tester.widget<Semantics>(
        find.byKey(const ValueKey('training-calendar-semantics-2024-01-01')),
      );
      expect(cell.properties.label, contains('今天 休息'));
      expect(cell.properties.selected, true);
      await pumpCalendar(
        tester,
        selected: '2024-01-01',
        completed: {'2024-01-01'},
      );
      cell = tester.widget<Semantics>(
        find.byKey(const ValueKey('training-calendar-semantics-2024-01-01')),
      );
      expect(cell.properties.label, contains('已完成'));
      expect(find.text('计划 0 km · 已完成 1/1 天'), findsOneWidget);
    },
  );
}
