import 'dart:io';

import 'package:flutter/services.dart';

/// 后台保活：Android 前台服务（location 类型）+ ohos 长时任务（LOCATION）。
/// iOS 由 AppleSettings + Info.plist 启用后台定位，不需要原生通道。
class BackgroundService {
  BackgroundService._();

  static const _channel = MethodChannel('runtrail/background');

  static Future<bool> start() async {
    if (Platform.isIOS || Platform.isMacOS) return true;
    try {
      await _channel.invokeMethod<void>('start');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // 同上。
    } on PlatformException {
      // 忽略。
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

  /// 刷新前台通知的实时成绩（息屏/锁屏可见，Keep 同款交互）。
  /// Android 刷新通知内容；ohos 的长时任务通知由系统生成、内容不可定制，
  /// 原生侧接收后直接成功返回；失败静默——通知文案是尽力而为的增强。
  static Future<void> updateStats(String text) async {
    if (Platform.isIOS || Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('update', {'text': text});
    } on MissingPluginException {
      // 平台未实现时忽略。
    } on PlatformException {
      // 忽略。
    }
  }
}
