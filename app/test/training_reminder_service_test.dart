import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/marathon_training_service.dart';
import 'package:runtrail/services/training_reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('runtrail/training_reminders');
  final calls = <MethodCall>[];
  late Future<Object?> Function(MethodCall) respond;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TrainingReminderService.debugOperatingSystem = 'ohos';
    TrainingReminderService.debugNow = () => DateTime(2026, 10, 23, 5);
    calls.clear();
    respond = (_) async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
  });

  tearDown(() {
    TrainingReminderService.debugOperatingSystem = null;
    TrainingReminderService.debugNow = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('80 days use one daily recurrence ending on the final plan day', () async {
    await TrainingReminderService.configure(enabled: true);
    expect(calls.length, 1);
    expect(calls.single.method, 'replaceDaily');
    final args = calls.single.arguments as Map;
    expect(args['start'], DateTime(2026, 10, 23, 6).millisecondsSinceEpoch);
    expect(args['end'], DateTime(2027, 1, 10, 23, 59, 59).millisecondsSinceEpoch);
    expect(args.containsKey('at'), isFalse);
    expect(await TrainingReminderService.enabled(), isTrue);
  });

  test('daily schedule skips a passed time and has no infinite post-plan recurrence', () async {
    final tasks = await MarathonTrainingService.load();
    final next = TrainingReminderService.dailySchedule(tasks, DateTime(2026, 10, 23, 7), 6, 0)!;
    expect(next['start'], DateTime(2026, 10, 24, 6).millisecondsSinceEpoch);
    expect(TrainingReminderService.dailySchedule(tasks, DateTime(2027, 1, 10, 7), 6, 0), isNull);
  });

  test('failed first enable leaves preference off and exposes native code', () async {
    respond = (_) async => throw PlatformException(code: 'reminder_201', message: 'Permission denied');
    await expectLater(TrainingReminderService.configure(enabled: true), throwsA(
      isA<TrainingReminderException>().having((e) => e.message, 'message', contains('AGC'))));
    expect(await TrainingReminderService.enabled(), isFalse);
    expect((await SharedPreferences.getInstance()).containsKey('training_reminder_settings_v2'), isFalse);
  });

  test('failed time change retains previous settings and next retry still works', () async {
    await TrainingReminderService.configure(enabled: true, hour: 7, minute: 15);
    respond = (_) async => throw PlatformException(code: 'reminder_1700001');
    await expectLater(TrainingReminderService.configure(enabled: true, hour: 8), throwsA(isA<TrainingReminderException>()));
    expect(await TrainingReminderService.time(), (7, 15));
    expect(await TrainingReminderService.enabled(), isTrue);
    respond = (_) async => true;
    await TrainingReminderService.configure(enabled: true, hour: 8);
    expect(await TrainingReminderService.time(), (8, 0));
  });

  test('explicit native false never saves enabled state', () async {
    respond = (_) async => false;
    await expectLater(TrainingReminderService.configure(enabled: true), throwsA(isA<TrainingReminderException>()));
    expect(await TrainingReminderService.enabled(), isFalse);
  });

  test('cancel works after plan expiry and does not schedule or load future dates', () async {
    TrainingReminderService.debugNow = () => DateTime(2027, 2, 1);
    await TrainingReminderService.configure(enabled: false);
    expect(calls.single.method, 'cancel');
    expect(await TrainingReminderService.enabled(), isFalse);
  });

  test('finite saved schedule is not reported as enabled after its end', () async {
    await TrainingReminderService.configure(enabled: true);
    TrainingReminderService.debugNow = () => DateTime(2027, 1, 11);
    expect(await TrainingReminderService.enabled(), isFalse);
  });

  test('enable after plan expiry fails without native mutation', () async {
    TrainingReminderService.debugNow = () => DateTime(2027, 1, 11);
    await expectLater(TrainingReminderService.configure(enabled: true), throwsA(isA<TrainingReminderException>()));
    expect(calls, isEmpty);
  });

  test('concurrent enable then disable preserves operation order', () async {
    final gate = Completer<Object?>();
    respond = (call) => call.method == 'replaceDaily' ? gate.future : Future.value(true);
    final enabling = TrainingReminderService.configure(enabled: true);
    final disabling = TrainingReminderService.configure(enabled: false);
    while (calls.isEmpty) { await Future<void>.delayed(Duration.zero); }
    expect(calls.length, 1);
    gate.complete(true);
    await Future.wait([enabling, disabling]);
    expect(calls.map((c) => c.method), ['replaceDaily', 'cancel']);
    expect(await TrainingReminderService.enabled(), isFalse);
  });

  test('immediate notification false can retry and only true marks today', () async {
    SharedPreferences.setMockInitialValues({'training_reminder_enabled': true});
    TrainingReminderService.debugNow = () => DateTime(2026, 10, 23, 8);
    respond = (_) async => false;
    await TrainingReminderService.notifyTodayIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('training_reminder_today_notified'), isFalse);
    respond = (_) async => true;
    await TrainingReminderService.notifyTodayIfNeeded();
    await TrainingReminderService.notifyTodayIfNeeded();
    expect(calls.length, 2);
    expect(prefs.getString('training_reminder_today_notified'), '2026-10-23');
  });

  test('failed foreground notification does not suppress a retry', () async {
    SharedPreferences.setMockInitialValues({'training_reminder_enabled': true});
    TrainingReminderService.debugNow = () => DateTime(2026, 10, 23, 8);
    respond = (_) async => throw PlatformException(code: 'reminder_1600004');
    await expectLater(TrainingReminderService.notifyTodayIfNeeded(), throwsA(isA<TrainingReminderException>()));
    respond = (_) async => true;
    await TrainingReminderService.notifyTodayIfNeeded();
    expect(calls.length, 2);
  });

  test('no foreground supplement before selected time or outside the plan', () async {
    SharedPreferences.setMockInitialValues({'training_reminder_enabled': true});
    await TrainingReminderService.notifyTodayIfNeeded();
    TrainingReminderService.debugNow = () => DateTime(2027, 1, 11, 8);
    await TrainingReminderService.notifyTodayIfNeeded();
    expect(calls, isEmpty);
  });

  test('Android keeps native entries protocol and skips unsupported publishNow', () async {
    TrainingReminderService.debugOperatingSystem = 'android';
    await TrainingReminderService.configure(enabled: true);
    expect(calls.single.method, 'replace');
    expect((calls.single.arguments as Map)['entries'], hasLength(80));
    await TrainingReminderService.notifyTodayIfNeeded();
    expect(calls.length, 1);
  });

  test('new settings are one atomic record and migrate legacy preferences', () async {
    SharedPreferences.setMockInitialValues({
      'training_reminder_enabled': true, 'training_reminder_hour': 9, 'training_reminder_minute': 30,
    });
    expect(await TrainingReminderService.time(), (9, 30));
    await TrainingReminderService.configure(enabled: true, hour: 10);
    final prefs = await SharedPreferences.getInstance();
    final settings = jsonDecode(prefs.getString('training_reminder_settings_v2')!) as Map;
    expect(settings['enabled'], isTrue);
    expect(settings['hour'], 10);
    expect(await TrainingReminderService.time(), (10, 0));
  });
  test('quota error includes validated counts and never claims to delete other reminders', () async {
    respond = (_) async => throw PlatformException(
      code: 'reminder_1700002',
      details: '{"visible":30,"owned":2,"stage":"failed-preserved","api":22}',
    );
    await expectLater(
      TrainingReminderService.configure(enabled: true),
      throwsA(
        isA<TrainingReminderException>()
            .having((e) => e.message, 'counts', contains('本应用可见30条，其中训练提醒2条'))
            .having((e) => e.message, 'safety', contains('不会清理其他功能')),
      ),
    );
    expect(await TrainingReminderService.enabled(), isFalse);
  });

  test('quota diagnostic malformed or inconsistent counts do not mask native failure', () {
    for (final details in [
      'not json',
      '{"visible":1,"owned":2}',
      '{"visible":-1,"owned":0}',
      '{"visible":"secret","owned":0}',
      '[]',
    ]) {
      final message = TrainingReminderService.describePlatformError(
        PlatformException(code: 'reminder_1700002', details: details),
      );
      expect(message, contains('1700002'));
      expect(message, isNot(contains('本应用可见')));
      expect(message, isNot(contains('secret')));
    }
  });

  test('quota failure preserves enabled setting and selected time', () async {
    await TrainingReminderService.configure(enabled: true, hour: 7, minute: 30);
    respond = (_) async => throw PlatformException(code: 'reminder_1700002');
    await expectLater(
      TrainingReminderService.configure(enabled: true, hour: 8),
      throwsA(isA<TrainingReminderException>()),
    );
    expect(await TrainingReminderService.enabled(), isTrue);
    expect(await TrainingReminderService.time(), (7, 30));
  });
}
