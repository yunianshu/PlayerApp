import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/training_month_calendar.dart';

import 'marathon_dashboard_test.dart';

void main() {
  for (final mode in AppThemeMode.values) {
    testWidgets('run results are automatic, readable and theme aware: $mode', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        mode: mode,
        width: 320,
        scale: 1.5,
        child: const DashboardHarness(runsByDate: {'2026-10-26': 6.2}),
      );
      final complete = find.byKey(
        const ValueKey('training-complete-2026-10-26'),
      );
      await reveal(tester, complete);
      expect(find.textContaining('实际 6.20 km · 多跑 1.20 km'), findsWidgets);
      expect(find.text('跑步距离已自动达标'), findsOneWidget);
      expect(tester.widget<FilledButton>(complete).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('partial and no record snapshots do not claim completion', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      child: const DashboardHarness(runsByDate: {'2026-10-26': 3}),
    );
    final complete = find.byKey(const ValueKey('training-complete-2026-10-26'));
    await reveal(tester, complete);
    expect(find.textContaining('实际 3.00 km · 少跑 2.00 km'), findsWidgets);
    expect(tester.widget<FilledButton>(complete).onPressed, isNotNull);
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(find.text('已手动完成 · 点击撤销'), findsOneWidget);
    expect(find.textContaining('手动完成已保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar semantic output includes actual, planned and delta', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      width: 1000,
      height: 700,
      child: Scaffold(
        body: SingleChildScrollView(
          child: TrainingMonthCalendar(
            tasks: sampleTasks,
            completed: const {},
            runsByDate: const {'2026-10-26': 6.2, '2026-10-27': 4},
            selectedDate: '2026-10-26',
            today: '2026-10-26',
            onSelect: (_) {},
          ),
        ),
      ),
    );
    final runCell = tester.widget<Semantics>(
      find.byKey(const ValueKey('training-calendar-semantics-2026-10-26')),
    );
    expect(runCell.properties.label, contains('距离已达标'));
    expect(runCell.properties.label, contains('计划 5.00 km'));
    expect(runCell.properties.label, contains('实际 6.20 km · 多跑 1.20 km'));
    final restCell = tester.widget<Semantics>(
      find.byKey(const ValueKey('training-calendar-semantics-2026-10-27')),
    );
    expect(restCell.properties.label, contains('非跑步任务'));
    expect(restCell.properties.label, isNot(contains('距离已达标')));
    expect(tester.takeException(), isNull);
  });
}
