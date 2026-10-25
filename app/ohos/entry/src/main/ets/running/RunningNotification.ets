import { notificationManager } from '@kit.NotificationKit';
import notification from '@ohos.notification';
import { BusinessError } from '@kit.BasicServicesKit';

// Only the optional live stats notification. Never changes training reminder slots.
// API 9/11 fields only: notificationFlags is NOT writable until API 23.
export default class RunningNotification {
  private epoch: number = 0;
  private active: boolean = false;
  private slotReady: boolean = false;
  private lastText: string = '';
  private pending: Promise<void> = Promise.resolve();

  begin(): void { this.epoch++; this.active = true; this.slotReady = false; this.lastText = ''; }
  async end(): Promise<void> {
    this.active = false;
    this.epoch++;
    const work = this.pending.then(() => notificationManager.cancel(1001));
    this.pending = work.catch(() => {});
    await work;
  }

  update(text: string, requestId: string, elapsedMs: number): Promise<string> {
    const epoch = this.epoch;
    const work = this.pending.then(() => this.publish(text, requestId, elapsedMs, epoch));
    this.pending = work.then(() => {}, () => {});
    return work;
  }

  private async publish(text: string, requestId: string, elapsedMs: number, epoch: number): Promise<string> {
    if (!this.active || epoch !== this.epoch || text.length === 0) return JSON.stringify({ outcome: 'inactive' });
    if (text === this.lastText) return JSON.stringify({ outcome: 'unchanged', isAlertOnce: true });
    // Keep the existing lock-screen-visible slot; only repeated updates are quiet.
    // Do not mutate the user's slot settings or repurpose training reminder slots.
    if (!this.slotReady) {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      if (!this.active || epoch !== this.epoch) return JSON.stringify({ outcome: 'stale' });
      this.slotReady = true;
    }
    let vibrationEnabled: boolean | undefined = undefined;
    let slotLevel: number | undefined = undefined;
    try {
      const slot = await notificationManager.getSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
      vibrationEnabled = slot.vibrationEnabled;
      slotLevel = slot.level;
    } catch (error) {
      const err = error as BusinessError;
      console.info(`RUN_FEEDBACK source=running_notification phase=slot_query_error requestId=${requestId} code=${err.code}`);
    }
    if (!this.active || epoch !== this.epoch) return JSON.stringify({ outcome: 'stale' });
    console.info(`RUN_FEEDBACK source=running_notification phase=request requestId=${requestId} elapsedMs=${elapsedMs} slot=SOCIAL_COMMUNICATION isAlertOnce=true vibrationObserved=unknown`);
    await notificationManager.publish({
      id: 1001,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      isAlertOnce: true,
      isOngoing: true,
      content: {
        contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: '跑步记录中', text: text, additionalText: '跑迹 RunTrail' }
      }
    });
    // Success means publication accepted, not evidence of a physical vibration.
    this.lastText = text;
    console.info(`RUN_FEEDBACK source=running_notification phase=accepted requestId=${requestId} vibrationObserved=unknown`);
    return JSON.stringify({ outcome: 'accepted', slot: 'SOCIAL_COMMUNICATION', isAlertOnce: true,
      vibrationEnabled: vibrationEnabled, slotLevel: slotLevel, vibrationObserved: 'unknown' });
  }
}
