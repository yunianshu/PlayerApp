import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'run_feedback_diagnostics.dart';

/// 后台保活：Android 前台服务（location 类型）+ ohos 长时任务（LOCATION）。
/// iOS 由 AppleSettings + Info.plist 启用后台定位，不需要原生通道。
class BackgroundService {
  BackgroundService._();

  static const _channel = MethodChannel('runtrail/background');

  static Future<bool> start() async {
    if (Platform.isIOS || Platform.isMacOS) return true;
    final requestSession = RunFeedbackDiagnostics.session;
    final requestId = RunFeedbackDiagnostics.event(
      'background_task',
      'request',
      {'operation': 'start', 'systemNotificationPossible': true},
    );
    try {
      await _channel.invokeMethod<void>('start');
      RunFeedbackDiagnostics.event('background_task', 'accepted', {
        'requestId': requestId,
        'requestSession': requestSession,
        'physicalVibrationObserved': 'unknown',
      });
      return true;
    } on MissingPluginException {
      RunFeedbackDiagnostics.event('background_task', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': 'missing_plugin',
      });
      return false;
    } on PlatformException catch (error) {
      RunFeedbackDiagnostics.event('background_task', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': error.code,
      });
      return false;
    }
  }

  static Future<void> stop() async {
    final requestSession = RunFeedbackDiagnostics.session;
    final requestId = RunFeedbackDiagnostics.event(
      'background_task',
      'request',
      {'operation': 'stop'},
    );
    try {
      await _channel.invokeMethod<void>('stop');
      RunFeedbackDiagnostics.event('background_task', 'accepted', {
        'requestId': requestId,
        'requestSession': requestSession,
      });
    } on MissingPluginException {
      RunFeedbackDiagnostics.event('background_task', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': 'missing_plugin',
      });
    } on PlatformException catch (error) {
      RunFeedbackDiagnostics.event('background_task', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': error.code,
      });
    }
  }

  /// 通知权限是否已授予（Android 13+ 需 POST_NOTIFICATIONS）。
  /// 未授予时锁屏/通知栏都看不到实时成绩。
  static Future<bool> hasNotificationPermission() async {
    if (Platform.isIOS || Platform.isMacOS) return true;
    try {
      return await _channel.invokeMethod<bool>('notiPermission') ?? true;
    } on MissingPluginException {
      return true; // 平台未实现（ohos）视为可用。
    } on PlatformException {
      return true;
    }
  }

  /// 跳到系统通知设置页（权限被拒后引导用户手动开启）。
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotiSettings');
    } on MissingPluginException {
      // 平台未实现时忽略。
    } on PlatformException {
      // 忽略。
    }
  }

  /// Best-effort live stats; Harmony returns privacy-safe publication evidence.
  /// API success is not proof that the operating system did/did not vibrate.
  static Future<void> updateStats(String text) async {
    if (Platform.isIOS || Platform.isMacOS) return;
    final requestSession = RunFeedbackDiagnostics.session;
    final requestId = RunFeedbackDiagnostics.event(
      'running_notification',
      'request',
      {'systemNotificationPossible': true},
    );
    try {
      final response = await _channel.invokeMethod<Object?>('update', {
        'text': text,
        'requestId': requestId,
        'requestSession': requestSession,
        'elapsedMs': RunFeedbackDiagnostics.elapsedMilliseconds,
      });
      final fields = <String, Object?>{
        'requestId': requestId,
        'requestSession': requestSession,
        'physicalVibrationObserved': 'unknown',
      };
      if (response is String) {
        // Whitelist small flags only; never copy native content or arbitrary text.
        final decoded = jsonDecode(response);
        if (decoded is Map) {
          for (final key in [
            'outcome',
            'slot',
            'isAlertOnce',
            'vibrationEnabled',
            'slotLevel',
          ]) {
            final value = decoded[key];
            if (value is bool ||
                value is num ||
                (value is String &&
                    [
                      'accepted',
                      'inactive',
                      'stale',
                      'SOCIAL_COMMUNICATION',
                    ].contains(value))) {
              fields[key] = value;
            }
          }
        }
      }
      RunFeedbackDiagnostics.event(
        'running_notification',
        'api_result',
        fields,
      );
    } on MissingPluginException {
      RunFeedbackDiagnostics.event('running_notification', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': 'missing_plugin',
      });
    } on PlatformException catch (error) {
      RunFeedbackDiagnostics.event('running_notification', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': error.code,
      });
    } on FormatException {
      RunFeedbackDiagnostics.event('running_notification', 'error', {
        'requestId': requestId,
        'requestSession': requestSession,
        'errorCode': 'invalid_diagnostic_response',
      });
    }
  }
}
