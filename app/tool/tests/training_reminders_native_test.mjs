// Runs the real ArkTS reminder control flow against fake OS APIs.
// This is NOT a HarmonyOS SDK compile or a substitute for HAP/device validation.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../../ohos/entry/src/main/ets/reminders/TrainingReminders.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default class', 'class');
const javascript = stripTypeScriptTypes(source) + '\nglobalThis.Subject = TrainingReminders;';
const future = Date.now() + 60_000;
const end = Date.now() + 80 * 86400_000;
const error = code => Object.assign(new Error(`native ${code}`), { code });

function fixture({ enabled = true, old = [] } = {}) {
  const events = [];
  let clock = Date.now();
  let nextId = 1000;
  let onRequest = async () => { enabled = true; };
  let failPublish;
  let failCancel;
  let failNotification;
  let handler;
  const active = new Map(old.map((item, i) => [i + 1, item]));
  const context = {
    console: { error() {} },
    Date: class extends Date { static now() { return clock; } }, Error, Number,
    notification: { ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 } },
    notificationManager: {
      SlotType: { CONTENT_INFORMATION: 3 },
      async isNotificationEnabled() { events.push('check'); return enabled; },
      async requestEnableNotification() { events.push('request'); await onRequest(); },
      async publish(request) { events.push('notify'); if (failNotification) throw failNotification; },
    },
    reminderAgentManager: {
      ReminderType: { REMINDER_TYPE_CALENDAR: 1 },
      ActionButtonType: { ACTION_BUTTON_TYPE_CLOSE: 0 },
      async getAllValidReminders() {
        events.push('list');
        return [...active].map(([reminderId, reminderReq]) => ({ reminderId, reminderReq }));
      },
      async cancelReminder(id) {
        events.push(`cancel:${id}`);
        if (failCancel === id) { failCancel = undefined; throw error(1700004); }
        active.delete(id);
      },
      async publishReminder(request) {
        events.push(`publish:${request.notificationId}`);
        if (failPublish && request.notificationId === 2100) throw failPublish;
        const id = nextId++;
        active.set(id, request);
        return id;
      },
    },
    MethodChannel: class {
      setMethodCallHandler(value) { handler = value; }
    },
  };
  vm.runInNewContext(javascript, context);
  const appContext = { abilityInfo: { bundleName: 'com.runtrail.runtrail', name: 'EntryAbility' } };
  const subject = new context.Subject(appContext);
  const resultFor = resolve => ({
    success(value) { resolve({ ok: true, value }); },
    error(code, message) { resolve({ ok: false, code, message }); },
    notImplemented() { resolve({ ok: false, code: 'unimplemented' }); },
  });
  return {
    events, active,
    setClock(value) { clock = value; },
    setRequest(fn) { onRequest = fn; },
    enable() { enabled = true; },
    failPublish(value) { failPublish = value; },
    failCancel(value) { failCancel = value; },
    failNotification(value) { failNotification = value; },
    call(method, args = {}) {
      return new Promise(resolve => subject.handle({ method, argument: name => args[name] }, resultFor(resolve)));
    },
    queued(method, args = {}) {
      if (!handler) context.Subject.register({ dartExecutor: { getBinaryMessenger() {} } }, appContext);
      return new Promise(resolve => handler.onMethodCall({ method, argument: name => args[name] }, resultFor(resolve)));
    },
  };
}

test('awaits notification authorization before listing or changing reminders', async () => {
  const f = fixture({ enabled: false });
  let accept;
  f.setRequest(() => new Promise(resolve => { accept = () => { f.enable(); resolve(); }; }));
  const work = f.call('replaceDaily', { start: future, end });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.events, ['check', 'request']);
  accept();
  assert.equal((await work).ok, true);
  assert.deepEqual(f.events.slice(0, 4), ['check', 'request', 'check', 'list']);
});

test('permission rejection preserves old schedule and original code', async () => {
  const f = fixture({ enabled: false, old: [{ notificationId: 2000 }] });
  f.setRequest(async () => { throw error(1600004); });
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_1600004');
  assert.equal(f.active.size, 1);
  assert.equal(f.events.some(event => event.startsWith('cancel')), false);
});

test('replaces legacy quota-sized schedule with one bounded daily recurrence', async () => {
  const f = fixture({ old: Array.from({ length: 30 }, (_, i) => ({ notificationId: 2000 + i })) });
  assert.equal((await f.call('replaceDaily', { start: future, end })).ok, true);
  assert.equal(f.active.size, 1);
  const request = [...f.active.values()][0];
  assert.deepEqual(Array.from(request.daysOfWeek), [1, 2, 3, 4, 5, 6, 7]);
  assert.equal(request.notificationId, 2100);
  assert.equal(request.endDateTime.year, new Date(end).getFullYear());
  assert.equal(request.endDateTime.day, new Date(end).getDate());
  assert.equal(request.wantAgent.pkgName, 'com.runtrail.runtrail');
  assert.equal(f.events.includes('request'), false);
});

test('failed replacement restores prior reminders and does not touch unrelated IDs', async () => {
  const f = fixture({ old: [{ notificationId: 2000 }, { notificationId: 777 }] });
  f.failPublish(error(201));
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_201');
  assert.deepEqual([...f.active.values()].map(x => x.notificationId).sort((a, b) => a - b), [777, 2000]);
});

test('partial cancellation failure restores previously removed reminders', async () => {
  const f = fixture({ old: [{ notificationId: 2000 }, { notificationId: 2001 }] });
  f.failCancel(2);
  assert.equal((await f.call('cancel')).code, 'reminder_1700004');
  assert.deepEqual([...f.active.values()].map(x => x.notificationId).sort(), [2000, 2001]);
});

test('disable succeeds without requesting notification permission', async () => {
  const f = fixture({ enabled: false, old: [{ notificationId: 2100 }, { notificationId: 777 }] });
  assert.equal((await f.call('cancel')).ok, true);
  assert.equal(f.events.includes('check'), false);
  assert.deepEqual([...f.active.values()].map(x => x.notificationId), [777]);
});

test('immediate notification failure is an error, not success(false)', async () => {
  const f = fixture();
  f.failNotification(error(1600004));
  assert.equal((await f.call('publishNow', { title: 'today', body: 'plan' })).code, 'reminder_1600004');
  f.failNotification(undefined);
  assert.equal((await f.call('publishNow', { title: 'today', body: 'plan' })).ok, true);
});

test('expired or unbounded time is rejected before permission and mutation', async () => {
  const f = fixture();
  for (const args of [{ start: 1, end }, { start: future, end: Infinity }, { start: future, end: 1 }]) {
    assert.equal((await f.call('replaceDaily', args)).code, 'reminder_invalid_time');
  }
  assert.deepEqual(f.events, []);
});

test('queued disable waits for in-flight permission and leaves no reminder', async () => {
  const f = fixture({ enabled: false });
  let accept;
  f.setRequest(() => new Promise(resolve => { accept = () => { f.enable(); resolve(); }; }));
  const first = f.queued('replaceDaily', { start: future, end });
  const second = f.queued('cancel');
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(f.events, ['check', 'request']);
  accept();
  assert.equal((await first).ok, true);
  assert.equal((await second).ok, true);
  assert.equal(f.active.size, 0);
});

test('permission dialog resolving without a grant still prevents registration', async () => {
  const f = fixture({ enabled: false });
  f.setRequest(async () => {});
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_1700001');
  assert.equal(f.events.includes('list'), false);
});

test('rollback failure is explicit instead of falsely preserving enabled status', async () => {
  const f = fixture({ old: [{ notificationId: 2100 }] });
  f.failPublish(error(201));
  const outcome = await f.call('replaceDaily', { start: future, end });
  assert.equal(outcome.code, 'reminder_-1');
  assert.match(outcome.message, /当前状态不确定/);
});


test('slow authorization advances a passed reminder minute to the next day', async () => {
  const f = fixture({ enabled: false });
  f.setRequest(async () => { f.enable(); f.setClock(future + 60_000); });
  assert.equal((await f.call('replaceDaily', { start: future, end })).ok, true);
  const request = [...f.active.values()][0];
  const next = new Date(future);
  next.setDate(next.getDate() + 1);
  assert.equal(request.dateTime.day, next.getDate());
  assert.equal(request.dateTime.hour, next.getHours());
});

test('authorization completing after the plan ends preserves old reminder state', async () => {
  const f = fixture({ enabled: false, old: [{ notificationId: 2100 }] });
  f.setRequest(async () => { f.enable(); f.setClock(end + 60_000); });
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_invalid_time');
  assert.equal(f.events.includes('list'), false);
  assert.equal(f.active.size, 1);
});
