import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  private backgroundChannel?: MethodChannel;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 跑步保活通道：申请/取消 LOCATION 长时任务（锁屏续记）。
    this.backgroundChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), 'runtrail/background')
    this.backgroundChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'start') {
          this.startContinuousTask(result)
        } else if (call.method === 'stop') {
          this.stopContinuousTask(result)
        } else {
          result.notImplemented()
        }
      }
    })
  }

  private startContinuousTask(result: MethodResult): void {
    const context = this.context
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
      }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
    }
    wantAgent.getWantAgent(wantAgentInfo).then((agent: WantAgent): Promise<void> => {
      return backgroundTaskManager.startBackgroundRunning(
        context, backgroundTaskManager.BackgroundMode.LOCATION, agent)
    }).then(() => {
      result.success(null)
    }).catch((err: BusinessError) => {
      // 申请失败不阻塞跑步本身，仅失去锁屏续记能力。
      console.error(`continuous task start failed: ${err.code} ${err.message}`)
      result.success(null)
    })
  }

  private stopContinuousTask(result: MethodResult): void {
    backgroundTaskManager.stopBackgroundRunning(this.context).then(() => {
      result.success(null)
    }).catch((err: BusinessError) => {
      console.error(`continuous task stop failed: ${err.code} ${err.message}`)
      result.success(null)
    })
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    // 沉浸式：内容铺满全屏，状态栏/导航栏透明（Flutter 侧 SafeArea 处理避让）。
    windowStage.getMainWindow((err: BusinessError, win) => {
      if (err.code) {
        console.error(`immersive: getMainWindow failed: ${JSON.stringify(err)}`)
        return
      }
      win.setWindowLayoutFullScreen(true)
      win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        // 浅色背景 → 深色图标（夜间主题由 Flutter SystemChrome 覆盖）
        isStatusBarLightIcon: false,
        navigationBarColor: '#00000000',
        isNavigationBarLightIcon: false,
      })
    })
  }
}
