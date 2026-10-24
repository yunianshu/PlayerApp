import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostics.dart';

/// Source-level evidence, not a sensor for physical vibration. Never log workout
/// metrics, speech text, coordinates, credentials or arbitrary native messages.
class RunFeedbackDiagnostics {
  RunFeedbackDiagnostics._();

  static Stopwatch _clock = Stopwatch();
  static int _sessionNumber = 0;
  static int _eventNumber = 0;
  static String _session = 'outside-run';

  static int get elapsedMilliseconds => _clock.elapsedMilliseconds;
  static String get session => _session;

  @visibleForTesting
  static void Function(Map<String, Object?>)? recordForTest;

  static void beginSession() {
    _session =
        'feedback-${DateTime.now().millisecondsSinceEpoch}-${++_sessionNumber}';
    _clock = Stopwatch()..start();
    event('session', 'begin');
  }

  static void endSession() {
    event('session', 'end');
    _clock.stop();
    _clock = Stopwatch();
    _session = 'outside-run';
  }

  /// Fields must be bounded diagnostic flags/codes only. To relate an external
  /// asynchronous outcome, pass the returned event ID as `requestId`.
  static String event(
    String source,
    String phase, [
    Map<String, Object?> fields = const {},
  ]) {
    final id = 'feedback-event-${++_eventNumber}';
    _record(source, phase, id, _session, _clock, fields);
    return id;
  }

  static void _record(
    String source,
    String phase,
    String id,
    String session,
    Stopwatch clock,
    Map<String, Object?> fields,
  ) {
    final record = <String, Object?>{
      ...fields,
      'session': session,
      'eventId': id,
      'elapsedMs': clock.elapsedMilliseconds,
      'source': source,
      'phase': phase,
    };
    try {
      recordForTest?.call(Map<String, Object?>.unmodifiable(record));
      unawaited(Diagnostics.log('RUN_FEEDBACK ${jsonEncode(record)}'));
    } on Object {
      // Logging must never prevent feedback or recording.
    }
  }

  /// Accepted means the platform call completed, NOT that hardware vibrated.
  /// Capturing session/clock keeps late responses associated with their request.
  static Future<void> haptic(
    String source,
    Future<void> Function() invoke, {
    Map<String, Object?> fields = const {},
  }) async {
    final session = _session;
    final clock = _clock;
    final id = 'feedback-event-${++_eventNumber}';
    _record(source, 'request', id, session, clock, fields);
    try {
      await invoke();
      _record(source, 'accepted', id, session, clock, const {
        'physicalVibrationObserved': 'unknown',
      });
    } on PlatformException catch (error) {
      final code = RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(error.code)
          ? error.code
          : 'platform_error';
      _record(source, 'error', id, session, clock, {'errorCode': code});
    } on MissingPluginException {
      _record(source, 'error', id, session, clock, const {
        'errorCode': 'missing_plugin',
      });
    } on Object {
      _record(source, 'error', id, session, clock, const {
        'errorCode': 'haptic_failed',
      });
    }
  }

  @visibleForTesting
  static void resetForTest() {
    recordForTest = null;
    _clock = Stopwatch();
    _session = 'outside-run';
    _sessionNumber = 0;
    _eventNumber = 0;
  }
}
