import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // ignore: depend_on_referenced_packages

import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/pages/home_page.dart';

/// 冒烟测试直接构建首页而非 RunTrailApp：
/// 完整应用会经 main.dart → run_tracker → geolocator 拉入 web 互操作实现，
/// ohos fork 的 Dart 3.4 VM 无法编译（主工具链 Dart 3.13 下无此问题）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('首页启动冒烟测试', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider.value(value: LocaleController.instance),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    // 首帧 → 用 runAsync 让 FFI 数据库等真实异步完成 → 再 pump 重建帧。
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(find.text('跑迹 RunTrail'), findsOneWidget);
    expect(find.text('本周活动'), findsOneWidget);
    // 空库时显示最近跑步空态文案。
    expect(find.textContaining('还没有跑步记录'), findsOneWidget);
  });
}
