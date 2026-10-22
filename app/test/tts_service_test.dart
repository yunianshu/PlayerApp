import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/core/i18n.dart';
import 'package:runtrail/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('runtrail/tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    TtsService.resetForTest();
    LocaleController.instance.pref = AppLanguage.zh;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    TtsService.resetForTest();
    LocaleController.instance.pref = AppLanguage.system;
  });

  test('concurrent initialization shares one native request', () async {
    final init = Completer<bool>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) {
      calls++;
      return init.future;
    });
    final first = TtsService.ensureInitialized();
    final second = TtsService.ensureInitialized();
    init.complete(true);
    expect(await Future.wait([first, second]), [true, true]);
    expect(calls, 1);
  });

  test('failed initialization can be retried', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async => ++calls > 1);
    expect(await TtsService.ensureInitialized(), isFalse);
    expect(await TtsService.ensureInitialized(), isTrue);
  });

  test('changing language reconfigures the native engine', () async {
    final languages = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      languages.add((call.arguments as Map)['lang'] as String);
      return true;
    });
    await TtsService.ensureInitialized();
    LocaleController.instance.pref = AppLanguage.en;
    expect(TtsService.isReady, isFalse);
    expect(await TtsService.ensureInitialized(), isTrue);
    expect(languages, ['zh-CN', 'en-US']);
  });

  test('rejected speech invalidates readiness for a later retry', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'init',
    );
    await TtsService.ensureInitialized();
    await TtsService.speak('3', flush: true);
    expect(TtsService.isReady, isFalse);
  });

  test('a missing speech handler never escapes as an async error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'init') return true;
      throw MissingPluginException();
    });
    await TtsService.ensureInitialized();
    await TtsService.speak('3');
    expect(TtsService.isReady, isFalse);
  });

  test('a missing stop handler never escapes as an async error', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'init') return true;
      throw MissingPluginException();
    });
    await TtsService.ensureInitialized();
    await TtsService.stop();
  });

  test('stop cancels speech waiting for engine initialization', () async {
    final init = Completer<bool>();
    final speaks = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'init') return init.future;
      if (call.method == 'speak') {
        speaks.add((call.arguments as Map)['text'] as String);
      }
      return true;
    });
    final speech = TtsService.speak('3');
    await TtsService.stop();
    init.complete(true);
    expect(await speech, isFalse);
    expect(speaks, isEmpty);
  });

  testWidgets('initialization timeout ignores a late native reply', (
    tester,
  ) async {
    final init = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (_) => init.future);
    final ready = TtsService.ensureInitialized();
    await tester.pump(const Duration(seconds: 12));
    expect(await ready, isFalse);
    init.complete(true);
    await tester.pump();
    expect(TtsService.isReady, isFalse);
  });
}
