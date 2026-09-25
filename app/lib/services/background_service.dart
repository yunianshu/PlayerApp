import 'package:flutter/services.dart';

/// 后台保活：Android 前台服务（location 类型）+ ohos 长时任务（LOCATION）。
/// iOS 由 geolocator 依据 Info.plist 的 UIBackgroundModes 自动开启，
/// 通道未实现时静默忽略（MissingPluginException）。
class BackgroundService {
  BackgroundService._();

  static const _channel = MethodChannel('runtrail/background');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // iOS 等未实现该通道的平台：后台定位由系统 UIBackgroundModes 处理。
    } on PlatformException {
      // 保活失败不阻塞跑步本身，仅失去锁屏续记能力。
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
}
