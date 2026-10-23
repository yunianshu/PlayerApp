import 'dart:ui' show CheckedState, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/widgets/training_completion_toggle.dart';

Widget wrap(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('empty ring and filled checked circle toggle once each way', (
    tester,
  ) async {
    var value = false;
    var calls = 0;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => TrainingCompletionToggle(
            value: value,
            label: '训练完成状态',
            palette: AppPalette.editorial,
            onPressed: () => setState(() {
              value = !value;
              calls++;
            }),
          ),
        ),
      ),
    );
    final circle = find.byKey(const ValueKey('training-completion-circle'));
    BoxDecoration decoration() =>
        tester.widget<AnimatedContainer>(circle).decoration! as BoxDecoration;
    expect(decoration().shape, BoxShape.circle);
    expect(decoration().color, Colors.transparent);
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(decoration().shape, BoxShape.circle);
    expect(decoration().color, AppPalette.editorial.accent);
    expect(find.byKey(const ValueKey('checked')), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(decoration().color, Colors.transparent);
    expect(find.byKey(const ValueKey('checked')), findsNothing);
    expect(find.byKey(const ValueKey('unchecked')), findsOneWidget);
  });

  testWidgets(
    'checked semantics, keyboard focus and keyboard activation are preserved',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var value = false;
        var calls = 0;
        await tester.pumpWidget(
          wrap(
            StatefulBuilder(
              builder: (context, setState) => TrainingCompletionToggle(
                value: value,
                label: '周五轻松跑完成状态',
                palette: AppPalette.dark,
                focusNode: focus,
                onPressed: () => setState(() {
                  value = !value;
                  calls++;
                }),
              ),
            ),
          ),
        );
        final control = find.byType(TrainingCompletionToggle);
        var data = tester.getSemantics(control).getSemanticsData();
        expect(data.label, '周五轻松跑完成状态');
        expect(data.flagsCollection.isChecked, isNot(CheckedState.none));
        expect(data.flagsCollection.isChecked, CheckedState.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(calls, 1);
        data = tester.getSemantics(control).getSemanticsData();
        expect(data.flagsCollection.isChecked, CheckedState.isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(
          tester
              .getSemantics(control)
              .getSemanticsData()
              .flagsCollection
              .isChecked,
          CheckedState.isFalse,
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'busy disables actions and announces saving without an endless animation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var calls = 0;
        await tester.pumpWidget(
          wrap(
            TrainingCompletionToggle(
              value: false,
              label: '训练完成状态',
              palette: AppPalette.light,
              busy: true,
              onPressed: () => calls++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(button.onPressed, isNull);
        final data = tester
            .getSemantics(find.byType(TrainingCompletionToggle))
            .getSemanticsData();
        expect(data.label, contains('正在保存'));
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        await tester.tap(find.byType(IconButton));
        expect(calls, 0);
        expect(find.byKey(const ValueKey('saving')), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('reduced motion disables every transition in both states', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => TrainingCompletionToggle(
            value: value,
            label: '完成状态',
            palette: AppPalette.editorial,
            onPressed: () => setState(() => value = !value),
          ),
        ),
        reduceMotion: true,
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'light': AppPalette.light,
    'dark': AppPalette.dark,
    'editorial': AppPalette.editorial,
  }.entries) {
    testWidgets(
      '${entry.key} uses existing palette exactly and circular focus border',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            TrainingCompletionToggle(
              value: true,
              label: '完成状态',
              palette: entry.value,
              onPressed: () {},
            ),
          ),
        );
        final decoration =
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        expect(decoration.color, entry.value.accent);
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.border!.top.color, entry.value.accent);
        final button = tester.widget<IconButton>(find.byType(IconButton));
        expect(
          button.style!.shape!.resolve({WidgetState.focused}),
          isA<CircleBorder>(),
        );
        expect(
          button.style!.overlayColor!.resolve({WidgetState.focused}),
          entry.value.accentSoft,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
