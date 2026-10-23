import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';

/**
 * The current project targets HarmonyOS API 22 (compatible API 12).
 * The documented alternate-icon API starts at 26.0.0. Do not reference a newer
 * symbol or add an unsupported app.json5 field to this build. A future SDK
 * upgrade must add packaged alternateIcons and real-device validation together.
 */
export default class LauncherIconSupport {
  static register(engine: FlutterEngine): void {
    const channel = new MethodChannel(
      engine.dartExecutor.getBinaryMessenger(), 'runtrail/launcher_icon');
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'getSupport') {
          result.success(false);
        } else if (call.method === 'setIcon') {
          result.error('UNSUPPORTED', '当前鸿蒙安装包暂不支持切换桌面图标', null);
        } else {
          result.notImplemented();
        }
      }
    });
  }
}
