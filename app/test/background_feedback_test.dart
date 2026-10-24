import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/background_service.dart';
import 'package:runtrail/services/run_feedback_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('runtrail/background');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final records = <Map<String, Object?>>[];

  setUp(() {
    records.clear();
    RunFeedbackDiagnostics.resetForTest();
    RunFeedbackDiagnostics.recordForTest = records.add;
    RunFeedbackDiagnostics.beginSession();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    RunFeedbackDiagnostics.resetForTest();
  });

  test(
    'native publication evidence is whitelisted without workout text',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'update');
        expect((call.arguments as Map)['requestId'], isA<String>());
        expect((call.arguments as Map)['elapsedMs'], isA<int>());
        return jsonEncode({
          'outcome': 'accepted',
          'slot': 'SOCIAL_COMMUNICATION',
          'isAlertOnce': true,
          'vibrationEnabled': false,
          'slotLevel': 1,
          'text': 'private workout text',
          'location': 'private location',
        });
      });
      await BackgroundService.updateStats('private workout text');
      final result = records.last;
      expect(result['source'], 'running_notification');
      expect(result['phase'], 'api_result');
      expect(result['requestId'], records[1]['eventId']);
      expect(result['vibrationEnabled'], false);
      expect(result['physicalVibrationObserved'], 'unknown');
      expect(records.toString(), isNot(contains('private')));
    },
  );

  test(
    'unexpected native text and malformed response cannot leak or throw',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            jsonEncode({'outcome': 'private text', 'slot': 'private text'}),
      );
      await BackgroundService.updateStats('private workout');
      expect(records.last.containsKey('outcome'), false);
      expect(records.last.containsKey('slot'), false);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => 'private malformed',
      );
      await BackgroundService.updateStats('private workout');
      expect(records.last['errorCode'], 'invalid_diagnostic_response');
      expect(records.toString(), isNot(contains('private')));
    },
  );

  test('native failure is correlated and logs only its code', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'publish_failed', message: 'private');
    });
    await BackgroundService.updateStats('private workout');
    expect(records.last['errorCode'], 'publish_failed');
    expect(records.last['requestId'], records[1]['eventId']);
    expect(records.toString(), isNot(contains('private')));
    expect(await BackgroundService.start(), false);
    expect(records.last['source'], 'background_task');
  });

  testWidgets('0–90s periodic updates never invoke explicit Dart haptics', (
    tester,
  ) async {
    var updates = 0;
    final hapticCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'update') updates++;
      return null; // Android/legacy bridge without native diagnostic response.
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call);
      return null;
    });
    for (var second = 0; second <= 90; second += 10) {
      if (second > 0) await tester.pump(const Duration(seconds: 10));
      await BackgroundService.updateStats('workout text at $second');
    }
    expect(updates, 10);
    expect(hapticCalls, isEmpty);
    expect(records.where((r) => r['phase'] == 'api_result').length, 10);
    // This only proves Dart behavior. Native publication silence is separately
    // covered by native mocks and still requires physical device verification.
  });
}
