import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/data/database.dart';
import 'package:runtrail/models/run_record.dart';
import 'package:runtrail/pages/detail_page.dart';
import 'package:runtrail/pages/summary_page.dart';
import 'package:runtrail/widgets/run_poster.dart';

class _TestPaths extends PathProviderPlatform {
  final String path;
  _TestPaths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  final calls = <MethodCall>[];
  late Directory temp;
  final run = RunRecord(
    start: DateTime(2026, 10, 1, 7),
    end: DateTime(2026, 10, 1, 7, 30),
    distanceM: 5000,
    durationS: 1800,
    calories: 280,
    title: '晨跑',
  );
  final points = [
    RunPoint(lat: 30, lng: 120, altitude: 10, time: run.start),
    RunPoint(lat: 30.01, lng: 120.02, altitude: 12, time: run.end),
  ];

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await RunDatabase.instance.close();
    temp = await Directory.systemTemp.createTemp('runtrail-share-test-');
    PathProviderPlatform.instance = _TestPaths(temp.path);
    await databaseFactory.setDatabasesPath(temp.path);
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return ''; // User dismissed the native share sheet.
        });
  });

  tearDown(() async {
    await RunDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  for (final fromDetail in [false, true]) {
    testWidgets(
      '${fromDetail ? 'detail' : 'summary'} shares a rendered PNG, without text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var record = run;
        if (fromDetail) {
          final id = await tester.runAsync(
            () => RunDatabase.instance.insertRun(run, points),
          );
          record = run.copyWith(id: id);
        }
        await tester.pumpWidget(
          ChangeNotifierProvider(
            create: (_) => ThemeController(),
            child: MaterialApp(
              home: fromDetail
                  ? DetailPage(record: record)
                  : SummaryPage.fromTracker(run, points),
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        if (!fromDetail) {
          // 总结页现在会主动弹"跑后拉伸？"询问，先关闭再操作分享。
          final stretchPrompt = find.text('暂不');
          if (stretchPrompt.evaluate().isNotEmpty) {
            await tester.tap(stretchPrompt);
            await tester.pumpAndSettle();
          }
        }
        if (fromDetail) {
          await tester.tap(find.byIcon(Icons.ios_share));
        } else {
          await tester.dragUntilVisible(
            find.text('分享成绩海报'),
            find.byType(ListView),
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('分享成绩海报'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(RunPoster), findsOneWidget);
        expect(find.text('文字成绩单'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('分享图片'));
        await tester.pump();
        for (var i = 0; i < 50 && calls.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump();
        }
        expect(calls, hasLength(1));
        final args = calls.single.arguments as Map;
        expect(args['text'], isNull);
        expect(args['mimeTypes'], ['image/png']);
        final paths = (args['paths'] as List).cast<String>();
        expect(paths, hasLength(1));
        final bytes = await tester.runAsync(
          () => File(paths.single).readAsBytes(),
        );
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), 1020);
        expect(header.getUint32(20), 1920);
        expect(find.text('分享失败，请重试'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
