// 分享海报跟随当前主题（曾硬编码编辑风，用户反馈分享图不随主题）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/theme.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/widgets/run_poster.dart';

RunRecord _run() => RunRecord(
  start: DateTime(2026, 10, 1, 7),
  end: DateTime(2026, 10, 1, 7, 30),
  distanceM: 5000,
  durationS: 1800,
  calories: 280,
);

Future<Color> _pumpAndGetBg(
  WidgetTester tester,
  AppThemeMode mode,
) async {
  final controller = ThemeController();
  await controller.setMode(mode);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: Scaffold(body: RunPoster(record: _run(), points: const []))),
    ),
  );
  await tester.pump();
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(RunPoster), matching: find.byType(Container))
        .first,
  );
  return container.color!;
}

void main() {
  setUp(() {
    // setMode 会持久化偏好，测试环境必须 mock，否则平台通道挂起超时。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('海报背景色随主题切换', (tester) async {
    final lightBg = await _pumpAndGetBg(tester, AppThemeMode.light);
    expect(lightBg, AppPalette.light.bg);

    final darkBg = await _pumpAndGetBg(tester, AppThemeMode.dark);
    expect(darkBg, AppPalette.dark.bg);

    final editorialBg = await _pumpAndGetBg(tester, AppThemeMode.editorial);
    expect(editorialBg, AppPalette.editorial.bg);

    // 三主题确实互不相同（避免"看起来换了其实没换"）。
    expect(lightBg, isNot(darkBg));
    expect(darkBg, isNot(editorialBg));
  });
}
