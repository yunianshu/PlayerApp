import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import notification from '@ohos.notification';

/** One finite, daily reminder instead of one reminder per training date.
 * API 12 supports daysOfWeek + endDateTime; no app process is needed at trigger time.
 * Only IDs reserved for training are replaced. Live running notifications are unrelated.
 */
export default class TrainingReminders {
  private context: common.UIAbilityContext;
  private pending: Promise<void> = Promise.resolve();
  private static readonly DAILY_ID: number = 2100;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  static register(engine: FlutterEngine, context: common.UIAbilityContext): void {
    const reminders = new TrainingReminders(context);
    const channel = new MethodChannel(engine.dartExecutor.getBinaryMessenger(), 'runtrail/training_reminders');
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        // Serialize replacement/cancellation, including while the permission dialog is open.
        reminders.pending = reminders.pending.then(() => reminders.handle(call, result));
      }
    });
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'replaceDaily') {
        const start: number = call.argument('start') ?? 0;
        const end: number = call.argument('end') ?? 0;
        if (!Number.isFinite(start) || !Number.isFinite(end) || start <= Date.now() || end < start) {
          result.error('reminder_invalid_time', '训练提醒时间已过期，请重新设置', null);
          return;
        }
        await this.ensurePermission();
        // A user may leave the permission dialog open past today's reminder minute.
        const first = new Date(start);
        while (first.getTime() <= Date.now()) first.setDate(first.getDate() + 1);
        if (first.getTime() > end) {
          result.error('reminder_invalid_time', '本期训练计划已结束，没有可设置的未来提醒', null);
          return;
        }
        const request: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: this.localTime(first.getTime()),
          endDateTime: this.localTime(end),
          daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
          title: '跑迹 · 每日训练提醒',
          content: '打开跑迹查看今天的马拉松训练计划（含休息日）',
          expiredContent: '本期训练计划已结束',
          notificationId: TrainingReminders.DAILY_ID,
          slotType: notificationManager.SlotType.CONTENT_INFORMATION,
          wantAgent: {
            pkgName: this.context.abilityInfo.bundleName,
            abilityName: this.context.abilityInfo.name
          },
          actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }]
        };
        await this.replaceOwned(request);
        result.success(true);
      } else if (call.method === 'cancel') {
        // Turning reminders off never requires requesting notification permission.
        await this.replaceOwned(undefined);
        result.success(true);
      } else if (call.method === 'publishNow') {
        const title: string = call.argument('title') ?? '';
        const body: string = call.argument('body') ?? '';
        if (title.length === 0) {
          result.error('reminder_invalid_content', '提醒内容为空', null);
          return;
        }
        await this.ensurePermission();
        await notificationManager.publish({
          id: 2101,
          notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
          content: {
            contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: { title: title, text: body, additionalText: '跑迹 RunTrail' }
          }
        });
        result.success(true);
      } else {
        result.notImplemented();
      }
    } catch (err) {
      const error = err as BusinessError;
      console.error(`training reminder ${call.method} failed: ${error.code} ${error.message}`);
      result.error(`reminder_${error.code ?? 'unknown'}`, error.message ?? '系统提醒操作失败', null);
    }
  }

  private async ensurePermission(): Promise<void> {
    if (await notificationManager.isNotificationEnabled()) return;
    await notificationManager.requestEnableNotification(this.context);
    if (!await notificationManager.isNotificationEnabled()) {
      const error = new Error('通知未授权，请在系统设置中允许跑迹发送通知') as BusinessError;
      error.code = 1700001;
      throw error;
    }
  }

  private localTime(at: number): reminderAgentManager.LocalDateTime {
    const date = new Date(at);
    return {
      year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(),
      hour: date.getHours(), minute: date.getMinutes(), second: date.getSeconds()
    };
  }

  private isOwned(info: reminderAgentManager.ReminderInfo): boolean {
    const id = info.reminderReq.notificationId ?? -1;
    // Includes legacy per-day training IDs, so upgrading clears partial old schedules.
    return id === TrainingReminders.DAILY_ID || (id >= 2000 && id < 2100);
  }

  private async replaceOwned(next: reminderAgentManager.ReminderRequestCalendar | undefined): Promise<void> {
    // Snapshot before mutation. This also checks the agent-reminder entitlement first.
    const previous = (await reminderAgentManager.getAllValidReminders()).filter(
      (info: reminderAgentManager.ReminderInfo) => this.isOwned(info));
    const removed: Array<reminderAgentManager.ReminderInfo> = [];
    try {
      for (const info of previous) {
        await reminderAgentManager.cancelReminder(info.reminderId);
        removed.push(info);
      }
      if (next) await reminderAgentManager.publishReminder(next);
    } catch (err) {
      // Keep the prior enabled/time setting truthful on a failed replace or cancel.
      // One reminder is created only after all old training reminders are removed.
      let restoreFailed = false;
      for (const info of removed) {
        try {
          await reminderAgentManager.publishReminder(info.reminderReq);
        } catch (restoreError) {
          restoreFailed = true;
          console.error(`training reminder restore failed: ${JSON.stringify(restoreError)}`);
        }
      }
      if (restoreFailed) {
        const error = new Error('原提醒恢复失败，当前状态不确定，请关闭提醒后重新开启') as BusinessError;
        error.code = -1;
        throw error;
      }
      throw err;
    }
  }
}
