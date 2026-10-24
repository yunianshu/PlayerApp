import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runtrail/services/run_feedback_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final records = <Map<String, Object?>>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    RunFeedbackDiagnostics.resetForTest();
    records.clear();
    RunFeedbackDiagnostics.recordForTest = records.add;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    RunFeedbackDiagnostics.resetForTest();
  });

  test(
    'preserves real haptic type and correlates request with accepted',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      RunFeedbackDiagnostics.beginSession();
      await RunFeedbackDiagnostics.haptic(
        'manual_pause',
        HapticFeedback.mediumImpact,
      );
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.mediumImpact');
      final request = records[1];
      final accepted = records[2];
      expect(request['phase'], 'request');
      expect(accepted['phase'], 'accepted');
      expect(accepted['eventId'], request['eventId']);
      expect(accepted['session'], request['session']);
      expect(accepted['physicalVibrationObserved'], 'unknown');
      expect(
        accepted['elapsedMs'] as int,
        greaterThanOrEqualTo(request['elapsedMs'] as int),
      );
    },
  );

  test(
    'late haptic completion remains attached to the previous session',
    () async {
      final done = Completer<void>();
      RunFeedbackDiagnostics.beginSession();
      final feedback = RunFeedbackDiagnostics.haptic(
        'auto_pause',
        () => done.future,
      );
      final first = records[1];
      RunFeedbackDiagnostics.endSession();
      RunFeedbackDiagnostics.beginSession();
      done.complete();
      await feedback;
      expect(records.last['session'], first['session']);
      expect(records.last['eventId'], first['eventId']);
      expect(records[3]['session'], isNot(first['session']));
    },
  );

  test(
    'platform errors contain code only, not private native details',
    () async {
      await RunFeedbackDiagnostics.haptic('pace_target', () async {
        throw PlatformException(
          code: 'denied',
          message: 'private text',
          details: 'secret',
        );
      });
      expect(records.last['errorCode'], 'denied');
      expect(records.last.toString(), isNot(contains('private')));
      expect(records.last.toString(), isNot(contains('secret')));
      expect(records.last['phase'], 'error');
    },
  );

  test('missing plugin and unexpected errors do not break recording', () async {
    await RunFeedbackDiagnostics.haptic('course_complete', () async {
      throw MissingPluginException('private');
    });
    expect(records.last['errorCode'], 'missing_plugin');
    await RunFeedbackDiagnostics.haptic('countdown_complete', () async {
      throw StateError('private');
    });
    expect(records.last['errorCode'], 'haptic_failed');
  });

  test('broken diagnostic sink never blocks intended haptic', () async {
    var invoked = false;
    RunFeedbackDiagnostics.recordForTest = (_) =>
        throw StateError('sink failed');
    await RunFeedbackDiagnostics.haptic('manual_resume', () async {
      invoked = true;
    });
    expect(invoked, true);
  });

  test('events carry safe flags and externally supplied correlation ID', () {
    RunFeedbackDiagnostics.beginSession();
    final request = RunFeedbackDiagnostics.event(
      'live_notification',
      'request',
      {'autoPauseEnabled': false, 'targetPaceEnabled': true},
    );
    RunFeedbackDiagnostics.event('live_notification', 'accepted', {
      'requestId': request,
    });
    expect(records.last['requestId'], request);
    expect(records[1]['targetPaceEnabled'], true);
    RunFeedbackDiagnostics.endSession();
    expect(records.last['phase'], 'end');
  });
}
