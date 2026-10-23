import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/run_start_confirmation.dart';

const preference = 'run_warmup_advice_acknowledged';

class _FailedWrite extends InMemorySharedPreferencesStore {
  _FailedWrite() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

Future<void> mount(
  WidgetTester tester,
  List<RunStartChoice?> results, {
  List<Object>? errors,
  AppThemeStyle style = AppThemeStyle.light,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(style),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  try {
                    results.add(await showRunStartConfirmation(context));
                  } catch (e) {
                    errors?.add(e);
                  }
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.load();
  });
  for (final choice in RunStartChoice.values) {
    testWidgets('$choice acknowledges once and persists after restart', (
      tester,
    ) async {
      final results = <RunStartChoice?>[];
      await mount(tester, results);
      await open(tester);
      expect(find.text('跑前热身？'), findsOneWidget);
      expect(
        tester.getCenter(find.text('热身')).dx,
        lessThan(tester.getCenter(find.text('开跑')).dx),
      );
      await tester.tap(
        find.text(choice == RunStartChoice.warmup ? '热身' : '开跑'),
      );
      await tester.pumpAndSettle();
      expect(results, [choice]);
      expect(
        (await SharedPreferences.getInstance()).getBool(preference),
        isTrue,
      );
      SharedPreferences.resetStatic();
      await tester.pumpWidget(const SizedBox());
      await mount(tester, results);
      await open(tester);
      expect(find.text('是否直接开跑？'), findsOneWidget);
      expect(find.textContaining('先活动关节'), findsNothing);
      expect(find.text('热身'), findsOneWidget);
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(results, [choice, null]);
    });
  }
  for (final dismiss in ['back', 'barrier', 'close']) {
    testWidgets('$dismiss does not start or acknowledge', (tester) async {
      final results = <RunStartChoice?>[];
      await mount(tester, results);
      await open(tester);
      if (dismiss == 'back') {
        await tester.binding.handlePopRoute();
      } else if (dismiss == 'barrier') {
        await tester.tapAt(const Offset(4, 4));
      } else {
        await tester.tap(find.byTooltip('取消'));
      }
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect((await SharedPreferences.getInstance()).get(preference), isNull);
      await open(tester);
      expect(find.text('跑前热身？'), findsOneWidget);
    });
  }
  testWidgets('later direct and warmup choices both remain usable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({preference: true});
    final results = <RunStartChoice?>[];
    await mount(tester, results);
    await open(tester);
    await tester.tap(find.text('开跑'));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.tap(find.text('热身'));
    await tester.pumpAndSettle();
    expect(results, [RunStartChoice.run, RunStartChoice.warmup]);
  });
  testWidgets(
    'rapid repeated choice only completes once and does not pop underlying route',
    (tester) async {
      final results = <RunStartChoice?>[];
      await mount(tester, results);
      await open(tester);
      final direct = tester
          .widget<FilledButton>(find.byKey(const ValueKey('run-start-direct')))
          .onPressed!;
      final warmup = tester
          .widget<TextButton>(find.byKey(const ValueKey('run-start-warmup')))
          .onPressed!;
      direct();
      direct();
      warmup();
      await tester.pumpAndSettle();
      expect(results, [RunStartChoice.run]);
      expect(find.text('open').hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'failed write returns no run choice and restores preference cache',
    (tester) async {
      SharedPreferencesStorePlatform.instance = _FailedWrite();
      SharedPreferences.resetStatic();
      final results = <RunStartChoice?>[];
      final errors = <Object>[];
      await mount(tester, results, errors: errors);
      await open(tester);
      await tester.tap(find.text('开跑'));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(errors.single, isA<StateError>());
      await open(tester);
      expect(find.text('跑前热身？'), findsOneWidget);
    },
  );
  for (final style in AppThemeStyle.values) {
    testWidgets('$style 320px 200% text actions stay visible and ordered', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, [], style: style, scale: 2);
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('热身').hitTestable(), findsOneWidget);
      expect(find.text('开跑').hitTestable(), findsOneWidget);
      expect(
        tester.getCenter(find.text('热身')).dx,
        lessThan(tester.getCenter(find.text('开跑')).dx),
      );
    });
  }
}
