import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { backgroundTaskManager, reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import notification from '@ohos.notification';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { textToSpeech } from '@kit.CoreSpeechKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  private backgroundChannel?: MethodChannel;
  private ttsEngine?: textToSpeech.TextToSpeechEngine;
  private ttsLang: string = 'zh-CN';
  private ttsReady: boolean = false;
  private ttsCreating: boolean = false;
  private ttsInitResults: MethodResult[] = [];

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 跑步保活通道：申请/取消 LOCATION 长时任务（锁屏续记）。
    this.backgroundChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), 'runtrail/background')
    this.backgroundChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'start') {
          // 请求通知授权（未授权时自定义实时成绩通知无法显示）。
          notificationManager.requestEnableNotification(this.context).catch(() => {})
          this.startContinuousTask(result)
        } else if (call.method === 'stop') {
          notificationManager.cancel(1001).catch(() => {})
          this.stopContinuousTask(result)
        } else if (call.method === 'update') {
          // 系统长时任务通知内容不可定制；另发一条自定义通知显示实时成绩，
          // 同 id 重复 publish 即为更新。
          const text: string = call.argument('text') ?? ''
          if (text.length > 0) {
            notificationManager.publish({
              id: 1001,
              // SOCIAL_COMMUNICATION 槽位：锁屏可见（Keep 同款行为）；
              // 默认槽位的通知在部分系统版本锁屏不展示。
              notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
              content: {
                // 新旧模块 ContentType 枚举类型不兼容，publish 入参需要旧枚举。
                contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
                normal: {
                  title: '跑步记录中',
                  text: text,
                  additionalText: '跑迹 RunTrail'
                }
              }
            }).then(() => result.success(null))
              .catch((err: BusinessError) => {
                console.error(`live notification publish failed: ${err.code} ${err.message}`)
                result.success(null)
              })
          } else {
            result.success(null)
          }
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
    // 训练提醒通道：系统级日历提醒（应用被杀后仍由系统提醒代理触发）。
    const reminderChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), 'runtrail/training_reminders')
    reminderChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        if (call.method === 'replace') {
          // 平行数组协议：entries 里是 Map，ArkTS 侧动态取值会踩 ESObject 限制，
          // 改传三个全类型化数组按下标配对。
          const ats: Array<number> = call.argument('at') ?? []
          const titles: Array<string> = call.argument('title') ?? []
          const bodies: Array<string> = call.argument('body') ?? []
          this.replaceReminders(ats, titles, bodies, result)
        } else if (call.method === 'cancel') {
          this.cancelReminders(result)
        } else if (call.method === 'publishNow') {
          const title: string = call.argument('title') ?? ''
          const body: string = call.argument('body') ?? ''
          this.publishTodayNotification(title, body, result)
        } else {
          result.notImplemented()
        }
      }
    })
  }

  /// 清空本应用全部待触发提醒。
  private async cancelReminders(result: MethodResult): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders()
      result.success(true)
    } catch (err) {
      console.error(`reminders cancel failed: ${JSON.stringify(err)}`)
      result.error('reminder_failed', 'cancel', JSON.stringify(err))
    }
  }

  /// 整表替换训练提醒：先清空，再按条目逐个发布日历提醒。
  private async replaceReminders(
    ats: Array<number>, titles: Array<string>, bodies: Array<string>,
    result: MethodResult): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders()
      let published = 0
      for (let i = 0; i < ats.length; i++) {
        const at = new Date(ats[i])
        const req: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: {
            year: at.getFullYear(),
            month: at.getMonth() + 1,
            day: at.getDate(),
            hour: at.getHours(),
            minute: at.getMinutes(),
            second: 0
          },
          title: i < titles.length ? titles[i] : '跑迹 · 训练提醒',
          content: i < bodies.length ? bodies[i] : '',
          notificationId: 2000 + i,
          expiredContent: '训练提醒已过期'
        }
        await reminderAgentManager.publishReminder(req)
        published++
      }
      console.info(`reminders replaced: ${published}`)
      result.success(true)
    } catch (err) {
      console.error(`reminders replace failed: ${JSON.stringify(err)}`)
      result.error('reminder_failed', 'replace', JSON.stringify(err))
    }
  }

  /// 立即发一条本地通知（打开训练页时的当日任务兜底提醒，当天去重由 Dart 侧控制）。
  private publishTodayNotification(title: string, body: string, result: MethodResult): void {
    if (title.length === 0) {
      result.success(null)
      return
    }
    notificationManager.requestEnableNotification(this.context).catch(() => {})
    notificationManager.publish({
      id: 2001,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: body,
          additionalText: '跑迹 RunTrail'
        }
      }
    }).then(() => result.success(true))
      .catch((err: BusinessError) => {
        console.error(`today notification publish failed: ${err.code} ${err.message}`)
        result.success(false)
      })
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
      console.error(`continuous task start failed: ${err.code} ${err.message}`)
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
