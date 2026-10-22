import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runtrail/core/prefs.dart';
import 'package:runtrail/core/theme_controller.dart';
import 'package:runtrail/pages/countdown_page.dart';
import 'package:runtrail/pages/running_page.dart';
import 'package:runtrail/services/run_tracker.dart';
import 'package:runtrail/services/tts_service.dart';

Widget wrap(Widget child) => ChangeNotifierProvider(
  create: (_) => ThemeController(),
  child: MaterialApp(home: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TtsService.resetForTest();
    SharedPreferences.setMockInitialValues({});
    Prefs.instance.voiceEnabled = true;
    Prefs.instance.paceTargetSecPerKm = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('runtrail/tts'),
          (_) async => true,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('runtrail/tts'), null);
    TtsService.resetForTest();
    Prefs.instance.paceTargetSecPerKm = 0;
  });

  testWidgets('离开倒计时后初始化完成不能补播数字', (tester) async {
    final init = Completer<bool>();
    final speaks = <String>[];
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'init') return init.future;
          if (call.method == 'speak') {
            speaks.add((call.arguments as Map)['text'] as String);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(wrap(CountdownPage(onComplete: () {})));
    await tester.pumpWidget(const SizedBox());
    init.complete(true);
    await tester.pump();
    expect(speaks, isEmpty);
  });

  testWidgets('退出跑步页清理语音回调和配速定时器', (tester) async {
    Prefs.instance.paceTargetSecPerKm = 360;
    final tracker = RunTracker();
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: wrap(const RunningPage()),
      ),
    );
    await tester.pump();
    expect(tracker.onInterval, isNotNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(tracker.onInterval, isNull);
    expect(tracker.onAutoPause, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('GPS 丢失/恢复播报并防抖', (tester) async {
    final speaks = <String>[];
    var fakeNow = DateTime(2026, 1, 1, 8);
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            speaks.add((call.arguments as Map)['text'] as String);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final tracker = RunTracker(now: () => fakeNow);
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: wrap(const RunningPage()),
      ),
    );
    await tester.pump();
    expect(tracker.onGpsStatus, isNotNull);

    // 丢失 → 播报一次。
    tracker.onGpsStatus!(true);
    await tester.pump();
    expect(speaks, contains('GPS信号丢失'));

    // 60 秒内恢复再丢失 → 防抖，不播报。
    tracker.onGpsStatus!(false);
    await tester.pump();
    tracker.onGpsStatus!(true);
    await tester.pump();
    expect(speaks.where((s) => s == 'GPS信号恢复'), isEmpty);
    expect(speaks.where((s) => s == 'GPS信号丢失'), hasLength(1));

    // 超过 60 秒后恢复 → 正常播报。
    fakeNow = fakeNow.add(const Duration(seconds: 61));
    tracker.onGpsStatus!(false);
    await tester.pump();
    expect(speaks, contains('GPS信号恢复'));
  });

  testWidgets('半马里程碑：播报 + 奖杯横幅 + 4 秒后消失', (tester) async {
    final speaks = <String>[];
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            speaks.add((call.arguments as Map)['text'] as String);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final tracker = RunTracker();
    tracker.distanceM = 21500;
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: wrap(const RunningPage()),
      ),
    );
    await tester.pump();
    expect(tracker.onInterval, isNotNull);

    tracker.onInterval!(22, 1000, 400, 8800, 22, 400);
    await tester.pump();
    // 里程碑既口播也出横幅。
    expect(speaks.any((s) => s.contains('完成半马距离')), isTrue);
    expect(find.text('完成半马距离！'), findsOneWidget);

    // 4 秒后横幅自动消失。
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('完成半马距离！'), findsNothing);
  });

  testWidgets('语音关闭时里程碑横幅仍显示', (tester) async {
    Prefs.instance.voiceEnabled = false;
    final tracker = RunTracker();
    tracker.distanceM = 21500;
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: wrap(const RunningPage()),
      ),
    );
    await tester.pump();
    tracker.onInterval!(22, 1000, 400, 8800, 22, 400);
    await tester.pump();
    expect(find.text('完成半马距离！'), findsOneWidget);
  });

  testWidgets('倒计时逐字播报 3、2、1 并语音开始', (tester) async {
    final speaks = <String>[];
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            speaks.add((call.arguments as Map)['text'] as String);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(wrap(CountdownPage(onComplete: () {})));
    // TTS init 异步完成后应立刻补播当前数字 3。
    await tester.pump(const Duration(milliseconds: 100));
    // 倒计时共 3 秒：逐秒推进触发 2、1 与完成播报。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(speaks, contains('3'));
    expect(speaks, contains('2'));
    expect(speaks, contains('1'));
    expect(speaks, contains('开始跑步！'));
    // 播报顺序：3 → 2 → 1 → 开始跑步。
    expect(speaks.indexOf('3'), lessThan(speaks.indexOf('2')));
    expect(speaks.indexOf('2'), lessThan(speaks.indexOf('1')));
    expect(speaks.indexOf('1'), lessThan(speaks.indexOf('开始跑步！')));
  });

  testWidgets('关闭语音总开关后倒计时不播报', (tester) async {
    final speaks = <String>[];
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            speaks.add((call.arguments as Map)['text'] as String);
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    Prefs.instance.voiceEnabled = false;

    await tester.pumpWidget(wrap(CountdownPage(onComplete: () {})));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(speaks, isEmpty);
  });
  testWidgets('手动暂停/继续立即播报（flush 不排队）', (tester) async {
    final speaks = <(String, bool)>[];
    const channel = MethodChannel('runtrail/tts');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'speak') {
            speaks.add((
              (call.arguments as Map)['text'] as String,
              (call.arguments as Map)['flush'] as bool? ?? false,
            ));
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final tracker = RunTracker();
    addTearDown(tracker.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: wrap(const RunningPage()),
      ),
    );
    await tester.pump();

    // 点暂停按钮：立即播报且 flush=true。
    await tester.tap(find.byIcon(Icons.pause_rounded).first);
    await tester.pump();
    final paused = speaks.where((s) => s.$1 == '已暂停').toList();
    expect(paused, isNotEmpty);
    expect(paused.last.$2, isTrue, reason: '暂停播报必须 flush 立即播');
  });

}
