import { FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import notification from '@ohos.notification';

interface TrainingReminderDiagnostics {
  stage: string;
  visible: number;
  owned: number;
  stored: number;
  api: number;
}

/** One finite, daily reminder instead of one reminder per training date.
 * API 12 supports daysOfWeek + endDateTime; no app process is needed at trigger time.
 * Only IDs reserved for training are replaced. Live running notifications are unrelated.
 */
export default class TrainingReminders {
  private context: common.UIAbilityContext;
  private pending: Promise<void> = Promise.resolve();
  private static readonly DAILY_ID: number = 2100;
  private static readonly GROUP: string = 'runtrail.marathon.daily.v3';
  private static readonly TITLE: string = '跑迹 · 每日训练提醒';
  private static readonly CONTENT: string = '打开跑迹查看今天的马拉松训练计划（含休息日）';
  private knownIds: Array<number> = [];
  private diagnostics: string = '';

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
    this.diagnostics = '';
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
          title: TrainingReminders.TITLE,
          content: TrainingReminders.CONTENT,
          groupId: TrainingReminders.GROUP,
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
      result.error(`reminder_${error.code ?? 'unknown'}`, error.message ?? '系统提醒操作失败', this.diagnostics);
    }
  }

  private async ensurePermission(): Promise<void> {
    if (await notificationManager.isNotificationEnabled()) return;
    await notificationManager.requestEnableNotification(this.context);
    if (!await notificationManager.isNotificationEnabled()) {
      const error: Error = new Error('通知未授权，请在系统设置中允许跑迹发送通知');
      (error as BusinessError).code = 1700001;
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
    const req = info.reminderReq;
    if (req.reminderType !== reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) return false;
    // Listing is app-scoped, but a numeric notification ID alone is not ownership.
    // Reject other feature groups/targets even when their notification IDs collide.
    if (req.groupId && req.groupId !== TrainingReminders.GROUP) return false;
    const target = req.wantAgent?.pkgName;
    if (target && target !== this.context.abilityInfo.bundleName) return false;
    const daily = req.title === TrainingReminders.TITLE && req.content === TrainingReminders.CONTENT &&
      req.expiredContent === '本期训练计划已结束';
    if (req.groupId === TrainingReminders.GROUP) return daily;
    const id = req.notificationId ?? -1;
    if (daily && (id === TrainingReminders.DAILY_ID || this.knownIds.indexOf(info.reminderId) >= 0)) return true;
    // Exact legacy signature written by 1.3.1: calendar + reserved ID + title + expiry text.
    // Unknown/missing IDs are NOT guessed away to resolve a quota error.
    return id >= 2000 && id < 2100 && (req.title ?? '').startsWith('跑迹 · ') &&
      req.expiredContent === '训练提醒已过期';
  }

  private recordSnapshot(stage: string, all: Array<reminderAgentManager.ReminderInfo>): void {
    const info: TrainingReminderDiagnostics = {
      stage: stage, visible: all.length,
      owned: all.filter((item: reminderAgentManager.ReminderInfo) => this.isOwned(item)).length,
      stored: this.knownIds.length, api: deviceInfo.sdkApiVersion
    };
    this.diagnostics = JSON.stringify(info);
    // Counts only. Do not log training text or other features' notification contents.
    console.info(`training reminder state ${this.diagnostics}`);
  }

  private async loadIds(): Promise<void> {
    try {
      const store = await preferences.getPreferences(this.context, { name: 'training_reminders_v3' });
      const empty: Array<number> = [];
      this.knownIds = await store.get('ownedIds', empty) as Array<number>;
    } catch (err) {
      this.knownIds = [];
      console.error(`training reminder ID read failed: ${(err as BusinessError).code}`);
    }
  }

  private async saveIds(all: Array<reminderAgentManager.ReminderInfo>): Promise<void> {
    this.knownIds = all.filter((item: reminderAgentManager.ReminderInfo) => this.isOwned(item))
      .map((item: reminderAgentManager.ReminderInfo) => item.reminderId);
    try {
      const store = await preferences.getPreferences(this.context, { name: 'training_reminders_v3' });
      await store.put('ownedIds', this.knownIds);
      await store.flush();
    } catch (err) {
      // The feature-specific group/signature still identifies the live reminder.
      // A bookkeeping failure must not report registration failure after it succeeded.
      console.error(`training reminder ID save failed: ${(err as BusinessError).code}`);
    }
  }

  private async ownedSnapshot(stage: string): Promise<Array<reminderAgentManager.ReminderInfo>> {
    const all = await reminderAgentManager.getAllValidReminders();
    this.recordSnapshot(stage, all);
    return all.filter((info: reminderAgentManager.ReminderInfo) => this.isOwned(info));
  }

  private async cancelExisting(id: number): Promise<void> {
    try {
      await reminderAgentManager.cancelReminder(id);
    } catch (err) {
      // Expiry or a concurrent OS dismissal can remove a listed reminder first.
      if ((err as BusinessError).code !== 1700003) throw err as Error;
    }
  }

  private async restore(
    before: Array<reminderAgentManager.ReminderInfo>, createdId: number, updatedId: number
  ): Promise<boolean> {
    let failed = false;
    if (createdId >= 0) {
      try { await this.cancelExisting(createdId); } catch (_) { failed = true; }
    }
    let current: Array<reminderAgentManager.ReminderInfo>;
    try {
      current = await reminderAgentManager.getAllValidReminders();
    } catch (_) {
      // Never blindly republish when current state cannot be established.
      return false;
    }
    for (const info of before) {
      try {
        const exists = current.some((item: reminderAgentManager.ReminderInfo) => item.reminderId === info.reminderId);
        if (exists && info.reminderId === updatedId) {
          await reminderAgentManager.updateReminder(info.reminderId, info.reminderReq);
        } else if (!exists) {
          await reminderAgentManager.publishReminder(info.reminderReq);
        }
      } catch (err) {
        failed = true;
        console.error(`training reminder restore failed: ${(err as BusinessError).code}`);
      }
    }
    return !failed;
  }

  private async publishWithOwnedRetry(
    next: reminderAgentManager.ReminderRequestCalendar,
    keepId: number,
    before: Array<reminderAgentManager.ReminderInfo>
  ): Promise<number> {
    try {
      return await reminderAgentManager.publishReminder(next);
    } catch (err) {
      if ((err as BusinessError).code !== 1700002) throw err as Error;
      // One re-list, one retry only if newly visible, provably owned duplicates can
      // actually free a slot. Never erase the last valid old reminder or unknown entries.
      const additional = (await this.ownedSnapshot('quota')).filter(
        (info: reminderAgentManager.ReminderInfo) => info.reminderId !== keepId);
      if (additional.length === 0) throw err as Error;
      for (const info of additional) {
        if (!before.some((item: reminderAgentManager.ReminderInfo) => item.reminderId === info.reminderId)) {
          before.push(info);
        }
        await this.cancelExisting(info.reminderId);
      }
      return await reminderAgentManager.publishReminder(next);
    }
  }

  private async replaceOwned(next: reminderAgentManager.ReminderRequestCalendar | undefined): Promise<void> {
    await this.loadIds();
    const before = await this.ownedSnapshot('before');
    // Prefer an existing daily reminder; otherwise migrate a known legacy calendar
    // in-place. API20 update does not allocate a new reminder/quota slot.
    before.sort((a: reminderAgentManager.ReminderInfo, b: reminderAgentManager.ReminderInfo) =>
      Number(b.reminderReq.notificationId === TrainingReminders.DAILY_ID) -
      Number(a.reminderReq.notificationId === TrainingReminders.DAILY_ID));
    let updatedId = -1;
    let createdId = -1;
    let keeperId = -1;
    try {
      if (next && deviceInfo.sdkApiVersion >= 20) {
        for (const info of before) {
          try {
            await reminderAgentManager.updateReminder(info.reminderId, next);
            updatedId = info.reminderId;
            keeperId = info.reminderId;
            break;
          } catch (err) {
            // A displayed/expired reminder cannot be updated. Try another known
            // candidate; permission/parameter/service errors are not blindly retried.
            if ((err as BusinessError).code !== 1700003) throw err as Error;
          }
        }
      }
      if (next && keeperId < 0) {
        const oldKeeper = before.length > 0 ? before[0].reminderId : -1;
        // Keep one valid old reminder while making room. On failure every removed
        // legacy task is restored from the verified snapshot, not recreated blindly.
        for (const info of before) {
          if (info.reminderId !== oldKeeper) await this.cancelExisting(info.reminderId);
        }
        createdId = await this.publishWithOwnedRetry(next, oldKeeper, before);
        keeperId = createdId;
      }
      const owned = await this.ownedSnapshot('cleanup');
      for (const info of owned) {
        if (info.reminderId !== keeperId) await this.cancelExisting(info.reminderId);
      }
      const all = await reminderAgentManager.getAllValidReminders();
      this.recordSnapshot('verified', all);
      const remaining = all.filter((info: reminderAgentManager.ReminderInfo) => this.isOwned(info));
      const valid = next
        ? remaining.length === 1 && remaining[0].reminderId === keeperId
        : remaining.length === 0;
      if (!valid) {
        const error: Error = new Error('系统提醒状态核验失败，请查看诊断日志');
        (error as BusinessError).code = -2;
        throw error;
      }
      await this.saveIds(all);
    } catch (err) {
      const restored = await this.restore(before, createdId, updatedId);
      try {
        const all = await reminderAgentManager.getAllValidReminders();
        this.recordSnapshot(restored ? 'failed-preserved' : 'failed-uncertain', all);
        await this.saveIds(all);
      } catch (_) {
        // Preserve the original API error and the most recent successful snapshot.
      }
      if (!restored) {
        const error: Error = new Error('原提醒未能完整恢复，当前状态不确定，请查看诊断日志');
        (error as BusinessError).code = -1;
        throw error;
      }
      throw err as Error;
    }
  }
}
