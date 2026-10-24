import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import AiCredentialsStore from '../security/AiCredentialsStore';
import TrainingReminders from '../reminders/TrainingReminders';
import LauncherIconSupport from '../appearance/LauncherIconSupport';
import RunningNotification from '../running/RunningNotification';

export default class EntryAbility extends FlutterAbility {
  private backgroundChannel?: MethodChannel;
  private runningNotification: RunningNotification = new RunningNotification();
  private ttsEngine?: textToSpeech.TextToSpeechEngine;
  private ttsLang: string = 'zh-CN';
  private ttsReady: boolean = false;
  private ttsCreating: boolean = false;
  private ttsInitResults: MethodResult[] = [];

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    AiCredentialsStore.register(flutterEngine)
    LauncherIconSupport.register(flutterEngine)
    // 跑步保活通道：申请/取消 LOCATION 长时任务（锁屏续记）。
    this.backgroundChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), 'runtrail/background')
    this.backgroundChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'start') {
          this.runningNotification.begin();
          // 请求通知授权（未授权时自定义实时成绩通知无法显示）。
          notificationManager.requestEnableNotification(this.context)
            .then(() => console.info('RUN_FEEDBACK source=notification_permission phase=accepted'))
            .catch((err: BusinessError) => console.info(`RUN_FEEDBACK source=notification_permission phase=error code=${err.code}`))
          this.startContinuousTask(result)
        } else if (call.method === 'stop') {
          this.runningNotification.end().catch((err: BusinessError) => {
            console.info(`RUN_FEEDBACK source=running_notification phase=cancel_error code=${err.code}`)
          })
          this.stopContinuousTask(result)
        } else if (call.method === 'update') {
          const text: string = call.argument('text') ?? ''
          const requestId: string = call.argument('requestId') ?? 'unknown'
          const elapsedMs: number = call.argument('elapsedMs') ?? 0
          this.runningNotification.update(text, requestId, elapsedMs)
            .then((summary: string) => result.success(summary))
            .catch((err: BusinessError) => {
              console.info(`RUN_FEEDBACK source=running_notification phase=error requestId=${requestId} code=${err.code}`)
              result.error('NOTIFICATION_UPDATE_FAILED', '实时通知更新失败', err.code)
            })
        } else {
          result.notImplemented()
        }
      }
    })
    // 语音播报通道：CoreSpeechKit 文本转语音（每公里/自动暂停/配速提醒）。
    const ttsChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), 'runtrail/tts')
    ttsChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'init') {
          const lang: string = call.argument('lang') ?? 'zh-CN'
          this.initTts(lang, result)
        } else if (call.method === 'speak') {
          const text: string = call.argument('text') ?? ''
          const flush: boolean = call.argument('flush') ?? false
          this.speakTts(text, flush, result)
        } else if (call.method === 'stop') {
          this.stopTts(result)
        } else {
          result.notImplemented()
        }
      }
    })
    TrainingReminders.register(flutterEngine, this.context)
  }

  private initTts(lang: string, result: MethodResult): void {
    if (this.ttsReady && this.ttsLang === lang && this.ttsEngine) {
      result.success(true)
      return
    }
    if (this.ttsCreating) {
      // 引擎创建中：排队等待完成回调统一答复。
      this.ttsInitResults.push(result)
      return
    }
    this.ttsCreating = true
    this.ttsInitResults.push(result)
    if (this.ttsEngine) {
      try {
        this.ttsEngine.shutdown()
      } catch (err) {
        console.error(`tts shutdown old engine failed: ${JSON.stringify(err)}`)
      }
      this.ttsEngine = undefined
      this.ttsReady = false
    }
    const params: textToSpeech.CreateEngineParams = {
      language: lang,
      person: 0,
      online: 1,
    }
    textToSpeech.createEngine(params,
      (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
        if (err || !engine) {
          this.ttsReady = false
          this.ttsCreating = false
          console.error(`tts createEngine failed: ${err?.code} ${err?.message}`)
          this.replyTtsInit(false)
          return
        }
        engine.setListener({
          onStart: (requestId: string, response: textToSpeech.StartResponse) => {
          },
          onComplete: (requestId: string,
            response: textToSpeech.CompleteResponse) => {
          },
          onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          },
          onError: (requestId: string, errorCode: number,
            errorMessage: string) => {
            console.error(`tts speak failed: ${errorCode} ${errorMessage}`)
          }
        })
        this.ttsEngine = engine
        this.ttsLang = lang
        this.ttsReady = true
        this.ttsCreating = false
        this.replyTtsInit(true)
      })
  }

  private replyTtsInit(ready: boolean): void {
    const pending = this.ttsInitResults
    this.ttsInitResults = []
    for (const result of pending) {
      result.success(ready)
    }
  }

  private speakTts(text: string, flush: boolean, result: MethodResult): void {
    if (!this.ttsReady || !this.ttsEngine || text.length === 0) {
      result.success(false)
      return
    }
    if (flush) {
      // 打断上一条未播完的内容（倒计时逐字播报）。
      try {
        this.ttsEngine.stop()
      } catch (err) {
        console.error(`tts flush stop failed: ${JSON.stringify(err)}`)
      }
    }
    const speakParams: textToSpeech.SpeakParams = {
      requestId: `runtrail-${Date.now()}`
    }
    this.ttsEngine.speak(text, speakParams)
    result.success(true)
  }

  private stopTts(result: MethodResult): void {
    if (this.ttsEngine) {
      try {
        this.ttsEngine.stop()
      } catch (err) {
        console.error(`tts stop failed: ${JSON.stringify(err)}`)
      }
    }
    result.success(null)
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
      this.runningNotification.end().catch(() => {})
      console.info(`RUN_FEEDBACK source=background_task phase=error code=${err.code}`)
      result.error('BACKGROUND_START_FAILED', '后台定位启动失败', null)
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

  onDestroy(): void {
    if (this.ttsEngine) {
      try {
        this.ttsEngine.shutdown()
      } catch (err) {
        console.error(`tts shutdown failed: ${JSON.stringify(err)}`)
      }
      this.ttsEngine = undefined
      this.ttsReady = false
    }
    super.onDestroy()
  }
}
