import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/pages/body_weight_page.dart';
import 'package:runtrail/services/body_weight_service.dart';
import 'package:runtrail/widgets/weight_ai_consent.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final palette in [
    AppPalette.light,
    AppPalette.dark,
    AppPalette.editorial,
  ]) {
    testWidgets('weight CRUD uses theme ${palette.bg}', (tester) async {
      final service = BodyWeightService();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: palette.isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: palette.bg,
          ),
          home: BodyWeightPage(service: service, now: DateTime(2026, 10, 23)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weight-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weight-kg')), '65.3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect((await service.snapshot()).records.single.kg, 65.3);
      final row = find.widgetWithText(ListTile, '65.3 kg');
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('weight-kg')), '65.1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect((await service.snapshot()).records.single.kg, 65.1);
      final remove = find.byTooltip('删除 2026-10-23 的体重记录');
      await tester.scrollUntilVisible(remove, 200);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect((await service.snapshot()).records, hasLength(1));
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect((await service.snapshot()).records, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('AI consent is explicit optional and discloses minimized data', (
    tester,
  ) async {
    var selected = false;
    final summary = BodyWeightSummary([
      const BodyWeightRecord(date: '2026-10-23', kg: 65),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => WeightAiConsent(
              summary: summary,
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    expect(find.textContaining('不发送逐日明细'), findsOneWidget);
    await tester.tap(find.byKey(const Key('weight-ai-consent')));
    await tester.pump();
    expect(selected, true);
  });
}
