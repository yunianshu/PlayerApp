import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'adaptive_training_service.dart';
import 'marathon_training_service.dart' show TrainingTask;

/// 训练提醒调度：Android 走 AlarmManager，鸿蒙走系统提醒代理
/// （reminderAgentManager，应用被杀后仍由系统触发）。其余平台不支持。
class TrainingReminderService {
  static const _channel = MethodChannel('runtrail/training_reminders');
  static const _enabled = 'training_reminder_enabled';
  static const _hour = 'training_reminder_hour';
  static const _minute = 'training_reminder_minute';
  static const _todayNotified = 'training_reminder_today_notified';

  /// 当前平台是否支持系统定时提醒。
  static bool get isSupported =>
      Platform.isAndroid || Platform.operatingSystem == 'ohos';

  static Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabled) ?? false;

  static Future<(int, int)> time() async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(_hour) ?? 6, p.getInt(_minute) ?? 0);
  }

  static Future<void> configure({required bool enabled, int hour = 6, int minute = 0}) async {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw ArgumentError('提醒时间无效');
    }
    if (!isSupported) {
      throw UnsupportedError('当前平台暂不支持系统定时训练提醒');
    }
    final tasks = await AdaptiveTrainingService.effectiveTasks();
    final now = DateTime.now();
    // 鸿蒙侧 ArkTS 不便解析嵌套结构，用平行数组协议（按下标配对）。
    final atMs = <int>[];
    final titles = <String>[];
    final bodies = <String>[];
    if (enabled) {
      for (final t in tasks) {
        final day = DateTime.parse(t.date);
        final atTime = DateTime(day.year, day.month, day.day, hour, minute);
        if (!atTime.isAfter(now)) continue;
        // 每日提醒含休息日；应用可以随时关闭或修改时间。
        atMs.add(atTime.millisecondsSinceEpoch);
        titles.add('跑迹 · ${t.title}');
        bodies.add(t.km > 0
            ? '今天 ${t.km.toStringAsFixed(t.km == t.km.roundToDouble() ? 0 : 1)} 公里。 ${t.notes}'
            : '今天：${t.title}。 ${t.notes}');
      }
    }
    try {
      if (enabled) {
        await _channel.invokeMethod<void>(
          'replace',
          {'at': atMs, 'title': titles, 'body': bodies},
        );
      } else {
        await _channel.invokeMethod<void>('cancel');
      }
    } on PlatformException catch (e) {
      if (e.code == 'reminder_failed') {
        throw StateError('系统未允许定时提醒（${e.message ?? e.code}），请在系统设置中检查通知与提醒权限');
      }
      rethrow;
    }
    final p = await SharedPreferences.getInstance();
    final ok = await p.setBool(_enabled, enabled) &&
        await p.setInt(_hour, hour) && await p.setInt(_minute, minute);
    if (!ok) throw StateError('训练提醒设置保存失败');
  }

  /// 当日兜底提醒：提醒代理在部分系统/签名组合下可能不可用，打开训练页时
  /// 把今天的任务直接发进通知中心（每天至多一次，锁屏也可见）。
  static Future<void> notifyTodayIfNeeded() async {
    if (!isSupported || !await enabled()) return;
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final key = '${today.year}-${today.month}-${today.day}';
    if (p.getString(_todayNotified) == key) return;
    final tasks = await AdaptiveTrainingService.effectiveTasks();
    TrainingTask? todayTask;
    for (final t in tasks) {
      if (t.date == today.toIso8601String().substring(0, 10)) {
        todayTask = t;
        break;
      }
    }
    final body = todayTask == null
        ? '今天休息恢复，为下一课储备体力'
        : todayTask.km > 0
            ? '今天 ${todayTask.km.toStringAsFixed(todayTask.km == todayTask.km.roundToDouble() ? 0 : 1)} 公里。 ${todayTask.notes}'
            : '今天：${todayTask.title}。 ${todayTask.notes}';
    final title = todayTask == null ? '跑迹 · 休息日' : '跑迹 · ${todayTask.title}';
    await _channel.invokeMethod<void>(
      'publishNow',
      {'title': title, 'body': body},
    );
    await p.setString(_todayNotified, key);
  }
}
