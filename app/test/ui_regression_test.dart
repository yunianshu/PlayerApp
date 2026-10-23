import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/core/launcher_icon_controller.dart';
import 'package:runtrail/data/database.dart';
import 'package:runtrail/main.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/pages/profile_page.dart';
import 'package:runtrail/pages/home_page.dart';
import 'package:runtrail/pages/summary_page.dart';
import 'package:runtrail/widgets/common.dart';
import 'package:runtrail/widgets/goal_dialog.dart';
import 'package:runtrail/services/run_draft.dart';

class TestDocuments extends PathProviderPlatform {
  TestDocuments(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

RunRecord record(double km, DateTime time) => RunRecord(
  start: time,
  end: time.add(const Duration(hours: 1)),
  distanceM: km * 1000,
  durationS: 3600,
  calories: 100,
);
Widget wrap(Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeController()),
    ChangeNotifierProvider(
      create: (context) =>
          LauncherIconController(context.read<ThemeController>())..load(),
    ),
    ChangeNotifierProvider.value(value: LocaleController.instance),
  ],
  child: MaterialApp(home: child),
);
Future<void> load(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await RunDatabase.instance.close();
    final dir = await Directory.systemTemp.createTemp('runtrail-ui-audit-');
    PathProviderPlatform.instance = TestDocuments(dir.path);
    await databaseFactory.setDatabasesPath(dir.path);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => RunDatabase.instance.close());
  testWidgets(
    'launcher follow-theme setting is explicit and disabled on unsupported builds',
    (tester) async {
      await tester.pumpWidget(wrap(const ProfilePage()));
      await load(tester);
      await tester.dragUntilVisible(
        find.text('桌面图标跟随主题'),
        find.byType(ListView).first,
        const Offset(0, -280),
      );
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '桌面图标跟随主题'),
      );
      expect(tile.value, isFalse);
      expect(tile.onChanged, isNull);
      expect(find.text('当前安装包未注册桌面图标接口，请确认已安装最新构建。'), findsOneWidget);
    },
  );
  testWidgets('B01 about button must work without provider assertion', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const ProfilePage()));
    await load(tester);
    // 设置卡片增多后"关于跑迹"超出懒加载缓存区，先滚动到可见再点击。
    await tester.dragUntilVisible(
      find.text('关于跑迹'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于跑迹'));
    await tester.pump();
    final error = tester.takeException();
    await tester.pumpWidget(const SizedBox());
    expect(error, isNull);
  });
  testWidgets('B02 yearly goal must exclude previous years', (tester) async {
    await tester.runAsync(() async {
      final now = DateTime.now();
      await RunDatabase.instance.insertRun(
        record(100, DateTime(now.year - 1, 6)),
        [],
      );
      await RunDatabase.instance.insertRun(
        record(10, DateTime(now.year, 6)),
        [],
      );
    });
    await tester.pumpWidget(wrap(const ProfilePage()));
    await load(tester);
    final goalText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s.contains('/ 500'))
        .toList();
    await tester.pumpWidget(const SizedBox());
    expect(goalText, contains(startsWith('10.0 / 500')));
  });
  testWidgets('B03 repeated save must insert only one record', (tester) async {
    await tester.pumpWidget(
      wrap(SummaryPage.fromTracker(record(5, DateTime.now()), const [])),
    );
    final save = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    await tester.runAsync(() async {
      final saveRun = save.onTap! as Future<void> Function();
      await Future.wait([saveRun(), saveRun()]);
    });
    final records = await tester.runAsync(
      () => RunDatabase.instance.listRuns(),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(records!.length, 1);
  });
  testWidgets('B04 320 logical pixel screen must not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeController();
    await tester.pumpWidget(RunTrailApp(themeController: theme));
    await load(tester);
    final error = tester.takeException();
    await tester.runAsync(() async {
      await RunDraft.load();
    });
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    expect(error, isNull);
  });

  testWidgets(
    'home data failure offers retry and recovers after storage is repaired',
    (tester) async {
      late String runsSchema;
      await tester.runAsync(() async {
        final db = await RunDatabase.instance.db;
        runsSchema =
            (await db.rawQuery(
                  "SELECT sql FROM sqlite_master WHERE name = 'runs'",
                )).single['sql']
                as String;
        await db.execute('DROP TABLE runs');
        await expectLater(RunDatabase.instance.listRuns(), throwsA(anything));
      });
      await tester.pumpWidget(wrap(const HomePage()));
      await load(tester);
      expect(find.text('数据加载失败，请重试'), findsOneWidget);
      await tester.runAsync(() async {
        await (await RunDatabase.instance.db).execute(runsSchema);
      });
      await tester.tap(find.text('重试'));
      await load(tester);
      expect(find.text('数据加载失败，请重试'), findsNothing);
      expect(find.text('本周里程'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('goal editor keeps decimals and displays invalid input inline', (
    tester,
  ) async {
    double? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => GoalDialog(
                  title: '目标',
                  current: 12.75,
                  onSave: (value) async => saved = value,
                ),
              ),
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12.75',
    );
    await tester.enterText(find.byType(TextField), 'NaN');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入 1–1000 之间的有效公里数'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byType(TextField), '12.75');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(saved, 12.75);
    expect(find.byType(GoalDialog), findsNothing);
  });

  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.editorial,
  ]) {
    testWidgets('320px navigation works in ${mode.name} theme', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final theme = ThemeController();
      await tester.runAsync(() => theme.setMode(mode));
      await tester.pumpWidget(RunTrailApp(themeController: theme));
      await load(tester);
      for (final tab in ['课程', '统计', '我的', '首页']) {
        await tester.tap(find.text(tab).last);
        await load(tester);
        expect(tester.takeException(), isNull, reason: '${mode.name}/$tab');
      }
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    });
  }
}
