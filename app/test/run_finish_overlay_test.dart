import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/widgets/run_finish_overlay.dart';

Widget wrap(Widget child) => ChangeNotifierProvider(
  create: (_) => ThemeController(),
  child: MaterialApp(home: Scaffold(body: Stack(children: [child]))),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('结束动画完整播放后定格在完成态，期间拦截点击', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () => tapped = true,
                child: const Text('页'),
              ),
            ),
            const RunFinishOverlay(),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('跑步结束'), findsOneWidget);
    expect(find.text('正在生成运动记录…'), findsOneWidget);

    // 动画未播完时文案还在浮现途中，点击被全屏手势拦截。
    await tester.tap(find.text('页'), warnIfMissed: false);
    expect(tapped, isFalse);

    await tester.pump(const Duration(milliseconds: 1600));
    // 播完定格：文案保持可见，等待总结页接管。
    expect(find.text('跑步结束'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三套主题都能渲染，换肤不重建动画状态', (tester) async {
    final controller = ThemeController();
    Widget wrapWith(ThemeController tc) => ChangeNotifierProvider.value(
      value: tc,
      child: MaterialApp(
        home: Scaffold(body: Stack(children: const [RunFinishOverlay()])),
      ),
    );
    await tester.pumpWidget(wrapWith(controller));
    await tester.pump(const Duration(milliseconds: 100));
    await controller.setMode(AppThemeMode.dark);
    await tester.pump(const Duration(milliseconds: 100));
    await controller.setMode(AppThemeMode.editorial);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
