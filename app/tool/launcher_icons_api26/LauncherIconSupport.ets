import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';

interface IconSupportDetails {
  supported: boolean;
  reason: string;
  deviceApi: number;
  nativeError: number;
}

// This file is overlaid ONLY by --launcher-icons after SDK/schema checks.
// It must never be compiled by the legacy SDK22 source build.
export default class LauncherIconSupport {
  private static busy: boolean = false;
  private static names: string[] = ['runtrail_light', 'runtrail_dark', 'runtrail_editorial'];

  static register(engine: FlutterEngine): void {
    const channel = new MethodChannel(
      engine.dartExecutor.getBinaryMessenger(), 'runtrail/launcher_icon');
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'getSupportDetails') {
          LauncherIconSupport.details().then((value: IconSupportDetails) => result.success(value));
        } else if (call.method === 'getSupport') {
          LauncherIconSupport.details().then((value: IconSupportDetails) => result.success(value.supported));
        } else if (call.method === 'setIcon') {
          const style: string = call.argument('style') ?? '';
          LauncherIconSupport.setIcon(style, result);
        } else {
          result.notImplemented();
        }
      }
    });
  }

  private static configured(icons: bundleManager.AlternateIconInfo[]): boolean {
    return LauncherIconSupport.names.every((name: string) =>
      icons.some((icon: bundleManager.AlternateIconInfo) => icon.iconName === name && icon.iconId > 0));
  }

  private static async details(): Promise<IconSupportDetails> {
    const api: number = deviceInfo.sdkApiVersion;
    if (api < 26) return { supported: false, reason: 'device_api_low', deviceApi: api, nativeError: 0 };
    try {
      const icons = await bundleManager.getAlternateIcons();
      const supported: boolean = LauncherIconSupport.configured(icons);
      return { supported: supported, reason: supported ? 'supported' : 'missing_icons', deviceApi: api, nativeError: 0 };
    } catch (err) {
      const failure = err as BusinessError;
      return { supported: false, reason: 'api_error', deviceApi: api, nativeError: failure.code ?? -1 };
    }
  }

  private static async setIcon(style: string, result: MethodResult): Promise<void> {
    if (deviceInfo.sdkApiVersion < 26) {
      result.error('UNSUPPORTED', '桌面图标切换需要 API 26.0.0 或更新系统', null);
      return;
    }
    if (style !== 'default' && style !== 'light' && style !== 'dark' && style !== 'editorial') {
      result.error('INVALID_STYLE', '未知桌面图标主题', null);
      return;
    }
    if (LauncherIconSupport.busy) {
      result.error('BUSY', '桌面图标正在更新', null);
      return;
    }
    LauncherIconSupport.busy = true;
    let previous: string = '';
    let previousKnown: boolean = false;
    try {
      const icons = await bundleManager.getAlternateIcons();
      if (!LauncherIconSupport.configured(icons)) {
        result.error('MISSING_ICONS', '安装包未包含完整的三主题备用图标', null);
        return;
      }
      for (const icon of icons) {
        if (icon.enabled) previous = icon.iconName;
      }
      previousKnown = true;
      const next: string = style === 'default' ? '' : 'runtrail_' + style;
      if (previous !== next) await bundleManager.setAlternateIcon(next);
      const after = await bundleManager.getAlternateIcons();
      const enabled = after.filter((icon: bundleManager.AlternateIconInfo) => icon.enabled);
      const verified: boolean = next === '' ? enabled.length === 0 :
        enabled.length === 1 && enabled[0].iconName === next;
      if (!verified) throw new Error('系统未确认桌面图标切换');
      result.success(null);
    } catch (err) {
      let restored: boolean = false;
      if (previousKnown) {
        try {
          const now = await bundleManager.getAlternateIcons();
          let current: string = '';
          for (const icon of now) {
            if (icon.enabled) current = icon.iconName;
          }
          if (current !== previous) await bundleManager.setAlternateIcon(previous);
          const restoredIcons = await bundleManager.getAlternateIcons();
          const restoredEnabled = restoredIcons.filter((icon: bundleManager.AlternateIconInfo) => icon.enabled);
          restored = previous === '' ? restoredEnabled.length === 0 :
            restoredEnabled.length === 1 && restoredEnabled[0].iconName === previous;
        } catch (_) {}
      }
      const failure = err as BusinessError;
      result.error('ICON_CHANGE_FAILED',
        '桌面图标设置失败 (' + String(failure.code ?? -1) + ')' +
        (restored ? '，已恢复原图标' : '，请返回应用后核对图标'), null);
    } finally {
      LauncherIconSupport.busy = false;
    }
  }
}
