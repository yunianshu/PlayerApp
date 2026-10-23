import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_training_service.dart';
import 'diagnostics.dart';
import 'marathon_training_service.dart' show TrainingTask;

class TrainingReminderException implements Exception {
  const TrainingReminderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Android uses dated alarms. HarmonyOS uses one daily calendar reminder with a
/// finite end date, so an 80-day plan does not exceed the system's reminder quota.
class TrainingReminderService {
  static const _channel = MethodChannel('runtrail/training_reminders');
  static const _settings = 'training_reminder_settings_v2';
  static const _enabled = 'training_reminder_enabled';
  static const _hour = 'training_reminder_hour';
  static const _minute = 'training_reminder_minute';
  static const _todayNotified = 'training_reminder_today_notified';
  static Future<void> _configurationWork = Future<void>.value();
  static bool _publishingToday = false;

  @visibleForTesting
  static String? debugOperatingSystem;
  @visibleForTesting
  static DateTime Function()? debugNow;

  static String get _platform =>
      debugOperatingSystem ?? Platform.operatingSystem;
  static DateTime get _now => debugNow?.call() ?? DateTime.now();
  static bool get isSupported => _platform == 'android' || _platform == 'ohos';
  static bool get usesDailySummary => _platform == 'ohos';

  static Map<String, dynamic>? _saved(SharedPreferences prefs) {
    final raw = prefs.getString(_settings);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = _saved(prefs);
    final until = saved?['until'] as int?;
    if (until != null && _now.millisecondsSinceEpoch > until) return false;
    return saved?['enabled'] as bool? ?? prefs.getBool(_enabled) ?? false;
  }

  static Future<(int, int)> time() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = _saved(prefs);
    return (
      saved?['hour'] as int? ?? prefs.getInt(_hour) ?? 6,
      saved?['minute'] as int? ?? prefs.getInt(_minute) ?? 0,
    );
  }

  /// A daily recurrence is bounded by the plan's last local calendar day.
  @visibleForTesting
  static Map<String, int>? dailySchedule(
    List<TrainingTask> tasks,
    DateTime now,
    int hour,
    int minute,
  ) {
    final future =
        tasks
            .map((task) {
              final day = DateTime.parse(task.date);
              return DateTime(day.year, day.month, day.day, hour, minute);
            })
            .where((at) => at.isAfter(now))
            .toList()
          ..sort();
    if (future.isEmpty) return null;
    final last = future.last;
    return {
      'start': future.first.millisecondsSinceEpoch,
      'end': DateTime(
        last.year,
        last.month,
        last.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch,
    };
  }

  static Future<void> configure({
    required bool enabled,
    int hour = 6,
    int minute = 0,
  }) {
    final next = _configurationWork.then(
      (_) => _configure(enabled, hour, minute),
    );
    // A rejected operation must not poison later retries or disable requests.
    _configurationWork = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  static Future<void> _configure(bool enabled, int hour, int minute) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const TrainingReminderException('提醒时间无效');
    }
    if (!isSupported) {
      throw const TrainingReminderException('当前平台暂不支持系统定时训练提醒');
    }
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = await TrainingReminderService.enabled();
    final oldTime = await time();
    // Disabling never needs to load a plan, or request notification permission.
    final tasks = enabled
        ? await AdaptiveTrainingService.effectiveTasks()
        : <TrainingTask>[];
    final schedule = enabled ? dailySchedule(tasks, _now, hour, minute) : null;
    if (enabled && schedule == null) {
      throw const TrainingReminderException('本期训练计划已结束，没有可设置的未来提醒');
    }
    try {
      await _applyNative(enabled, hour, minute, tasks);
    } on PlatformException catch (error) {
      await Diagnostics.log(
        'TRAINING_REMINDER code=${error.code} details=${error.details ?? 'none'}',
      );
      throw TrainingReminderException(describePlatformError(error));
    } on MissingPluginException {
      throw const TrainingReminderException('当前安装包未包含训练提醒实现，请更新安装包');
    }
    // Persist a single record only after native confirmation: no partial three-key writes.
    final saved = await prefs.setString(
      _settings,
      jsonEncode({
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        if (schedule != null) 'until': schedule['end'],
      }),
    );
    if (!saved) {
      try {
        final oldTasks = wasEnabled
            ? await AdaptiveTrainingService.effectiveTasks()
            : <TrainingTask>[];
        await _applyNative(wasEnabled, oldTime.$1, oldTime.$2, oldTasks);
      } catch (_) {
        throw const TrainingReminderException('设置保存失败，系统提醒状态未能恢复，请关闭提醒后重新开启');
      }
      throw const TrainingReminderException('设置保存失败，已保留原提醒设置，请重试');
    }
  }

  static Future<void> _applyNative(
    bool enabled,
    int hour,
    int minute,
    List<TrainingTask> tasks,
  ) async {
    String method = 'cancel';
    Map<String, Object>? arguments;
    if (enabled) {
      if (usesDailySummary) {
        final schedule = dailySchedule(tasks, _now, hour, minute);
        if (schedule == null) {
          throw const TrainingReminderException('没有可设置的未来提醒');
        }
        method = 'replaceDaily';
        arguments = schedule;
      } else {
        method = 'replace';
        final entries = <Map<String, Object>>[];
        final now = _now;
        for (final task in tasks) {
          final day = DateTime.parse(task.date);
          final at = DateTime(day.year, day.month, day.day, hour, minute);
          if (!at.isAfter(now)) continue;
          entries.add({
            'at': at.millisecondsSinceEpoch,
            'title': '跑迹 · ${task.title}',
            'body': _body(task),
          });
        }
        // Android's existing native bridge expects entries, not HarmonyOS arrays.
        arguments = {'entries': entries};
      }
    }
    final ok = await _channel.invokeMethod<bool>(method, arguments);
    if (ok != true) {
      throw const TrainingReminderException('系统没有确认提醒设置成功，请重试');
    }
  }

  @visibleForTesting
  static String describePlatformError(PlatformException error) {
    switch (error.code) {
      case 'reminder_1700001':
      case 'reminder_1600004':
        return '通知未授权，请在系统设置中允许跑迹发送通知后重试（${error.code}）';
      case 'reminder_201':
        return '应用缺少代理提醒权限，请检查AGC开放能力及HAP签名Profile，手机通知开关不能解决（201）';
      case 'reminder_1700002':
        final counts = _quotaCounts(error.details);
        return '系统未提供可用提醒配额（1700002）。$counts'
            '未能启用新设置，请发送诊断日志排查；不会清理其他功能的提醒';
      case 'reminder_-1':
        return '原提醒未能完整恢复，当前状态不确定，请发送诊断日志排查';
      default:
        return '系统提醒操作失败（${error.code}）：${error.message ?? '请稍后重试'}';
    }
  }

  static String _quotaCounts(Object? details) {
    if (details is! String || details.isEmpty) return '';
    try {
      final parsed = jsonDecode(details);
      if (parsed is! Map<String, dynamic>) return '';
      final visible = parsed['visible'];
      final owned = parsed['owned'];
      if (visible is! int ||
          owned is! int ||
          visible < 0 ||
          owned < 0 ||
          owned > visible) {
        return '';
      }
      return '本应用可见$visible条，其中训练提醒$owned条。';
    } on FormatException {
      return '';
    }
  }

  static String _body(TrainingTask task) => task.km > 0
      ? '今天 ${task.km.toStringAsFixed(task.km == task.km.roundToDouble() ? 0 : 1)} 公里。 ${task.notes}'
      : '今天：${task.title}。 ${task.notes}';

  /// Foreground-only supplement; never advertised as a replacement for scheduling.
  /// Android has no publishNow method. Do not mark failures as notified, and do not
  /// notify outside this plan's dates or before today's configured reminder time.
  static Future<void> notifyTodayIfNeeded() async {
    if (_platform != 'ohos' || _publishingToday) return;
    _publishingToday = true;
    try {
      if (!await enabled()) return;
      final prefs = await SharedPreferences.getInstance();
      final today = _now;
      final selectedTime = await time();
      if (today.isBefore(
        DateTime(
          today.year,
          today.month,
          today.day,
          selectedTime.$1,
          selectedTime.$2,
        ),
      )) {
        return;
      }
      final key = today.toIso8601String().substring(0, 10);
      if (prefs.getString(_todayNotified) == key) return;
      final tasks = await AdaptiveTrainingService.effectiveTasks();
      final matches = tasks.where((task) => task.date == key);
      if (matches.isEmpty) return;
      final task = matches.first;
      final sent = await _channel.invokeMethod<bool>('publishNow', {
        'title': '跑迹 · ${task.title}',
        'body': _body(task),
      });
      if (sent == true) await prefs.setString(_todayNotified, key);
    } on PlatformException catch (error) {
      throw TrainingReminderException(describePlatformError(error));
    } finally {
      _publishingToday = false;
    }
  }
}
