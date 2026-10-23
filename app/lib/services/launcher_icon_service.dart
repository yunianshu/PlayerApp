import 'package:flutter/services.dart';

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

  Future<void> setIcon(String style) =>
      channel.invokeMethod<void>('setIcon', {'style': style});
}
