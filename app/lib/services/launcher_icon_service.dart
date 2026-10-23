import 'dart:async';

import 'package:flutter/services.dart';

class LauncherIconSupportState {
  final bool supported;
  final String reason;
  final int? deviceApi;
  final int? nativeError;
  const LauncherIconSupportState(
    this.supported,
    this.reason, {
    this.deviceApi,
    this.nativeError,
  });

  String get description {
    final api = deviceApi == null ? '' : '（设备 API $deviceApi）';
    return switch (reason) {
      'build_not_enabled' =>
        '本安装包未启用鸿蒙动态图标试验$api。需使用 --launcher-icons 重新打包，不代表手机不支持。',
      'device_api_low' => '设备 API $deviceApi 低于备用图标接口要求的 API 26，当前无法动态切换。',
      'missing_icons' => '已接入图标接口，但安装包缺少完整三主题备用图标资源$api，请检查试验构建。',
      'api_error' =>
        '系统图标接口查询失败$api${nativeError == null ? '' : '，错误码 $nativeError'}，尚不能判定是否支持。',
      'timeout' => '图标能力检测超时，尚不能判定是否支持，请重新检测。',
      'bridge_missing' => '当前安装包未注册桌面图标接口，请确认已安装最新构建。',
      'supported' => '桌面刷新可能稍有延迟；自动主题在应用运行或返回时同步',
      _ => '当前平台或安装包暂不支持，保留默认图标',
    };
  }
}

/// Platform bridge. Unsupported builds must say so, not simulate success.
class LauncherIconService {
  static const channel = MethodChannel('runtrail/launcher_icon');

  Future<bool> isSupported() async {
    try {
      return await channel
              .invokeMethod<bool>('getSupport')
              .timeout(const Duration(seconds: 2)) ??
          false;
    } on Object {
      return false;
    }
  }

  Future<LauncherIconSupportState> diagnose() async {
    try {
      final details = await channel
          .invokeMapMethod<String, dynamic>('getSupportDetails')
          .timeout(const Duration(seconds: 2));
      if (details != null &&
          details['supported'] is bool &&
          details['reason'] is String) {
        return LauncherIconSupportState(
          details['supported'] as bool,
          details['reason'] as String,
          deviceApi: details['deviceApi'] is int
              ? details['deviceApi'] as int
              : null,
          nativeError: details['nativeError'] is int
              ? details['nativeError'] as int
              : null,
        );
      }
    } on MissingPluginException {
      // Android and older bridges only implement getSupport; preserve compatibility.
    } on TimeoutException {
      return const LauncherIconSupportState(false, 'timeout');
    } on PlatformException {
      return const LauncherIconSupportState(false, 'api_error');
    } on Object {
      return const LauncherIconSupportState(false, 'unknown');
    }
    try {
      final supported =
          await channel
              .invokeMethod<bool>('getSupport')
              .timeout(const Duration(seconds: 2)) ??
          false;
      return LauncherIconSupportState(
        supported,
        supported ? 'supported' : 'unknown',
      );
    } on MissingPluginException {
      return const LauncherIconSupportState(false, 'bridge_missing');
    } on TimeoutException {
      return const LauncherIconSupportState(false, 'timeout');
    } on Object {
      return const LauncherIconSupportState(false, 'api_error');
    }
  }

  Future<void> setIcon(String style) =>
      channel.invokeMethod<void>('setIcon', {'style': style});
}
