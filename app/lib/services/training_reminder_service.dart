import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'marathon_training_service.dart';

/// Android reminder scheduler. Other platforms explicitly report unsupported.
class TrainingReminderService {
  static const _channel = MethodChannel('runtrail/training_reminders');
  static const _enabled = 'training_reminder_enabled';
  static const _hour = 'training_reminder_hour';
  static const _minute = 'training_reminder_minute';
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
    if (!Platform.isAndroid) {
      throw UnsupportedError('当前仅 Android 支持系统定时训练提醒');
    }
    final tasks = await MarathonTrainingService.load();
    final now = DateTime.now();
    final entries = <Map<String, Object>>[];
    if (enabled) {
      for (final t in tasks) {
        final day = DateTime.parse(t.date);
        final at = DateTime(day.year, day.month, day.day, hour, minute);
        if (!at.isAfter(now)) continue;
        // 每日提醒含休息日；应用可以随时关闭或修改时间。
        entries.add({
          'at': at.millisecondsSinceEpoch,
          'title': '跑迹 · ${t.title}',
          'body': t.km > 0
              ? '今天 ${t.km.toStringAsFixed(t.km == t.km.roundToDouble() ? 0 : 1)} 公里。 ${t.notes}'
              : '今天：${t.title}。 ${t.notes}',
        });
      }
    }
    if (enabled) {
      await _channel.invokeMethod<void>('replace', {'entries': entries});
    } else {
      await _channel.invokeMethod<void>('cancel');
    }
    final p = await SharedPreferences.getInstance();
    final ok = await p.setBool(_enabled, enabled) &&
        await p.setInt(_hour, hour) && await p.setInt(_minute, minute);
    if (!ok) throw StateError('训练提醒设置保存失败');
  }
}
