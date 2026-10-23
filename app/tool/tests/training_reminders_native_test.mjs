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

function legacy(notificationId) {
  return { notificationId, reminderType: 1, title: '跑迹 · 轻松跑',
    content: '今天 5 公里', expiredContent: '训练提醒已过期',
    dateTime: { year: 2026, month: 10, day: 24, hour: 6, minute: 0 } };
}
function daily(notificationId = 2100) {
  return { notificationId, reminderType: 1, title: '跑迹 · 每日训练提醒',
    content: '打开跑迹查看今天的马拉松训练计划（含休息日）', expiredContent: '本期训练计划已结束',
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
    wantAgent: { pkgName: 'com.runtrail.runtrail', abilityName: 'EntryAbility' },
    dateTime: { year: 2026, month: 10, day: 24, hour: 6, minute: 0 } };
}

function fixture({ enabled = true, old = [], api = 26, limit = 64, globalQuota = false, savedIds = [] } = {}) {
  const events = [];
  let clock = Date.now();
  let nextId = 1000;
  let onRequest = async () => { enabled = true; };
  let failPublish;
  let failUpdate;
  let updateResponses = [];
  let displayed = [];
  const saved = new Map([['ownedIds', savedIds]]);
  let failCancel;
  let failNotification;
  let handler;
  const active = new Map(old.map((item, i) => [i + 1, item]));
  const context = {
    console: { error() {}, info() {} },
    deviceInfo: { sdkApiVersion: api },
    preferences: { async getPreferences() { return {
      async get(key, fallback) { return saved.get(key) ?? fallback; },
      async put(key, value) { saved.set(key, Array.from(value)); },
      async flush() {},
    }; } },
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
      async updateReminder(id, request) {
        events.push(`update:${id}`);
        if (api < 20) throw error(801);
        const response = updateResponses.shift();
        if (response) throw response;
        if (failUpdate) throw failUpdate;
        if (!active.has(id) || displayed.includes(id)) throw error(1700003);
        active.set(id, request);
      },
      async publishReminder(request) {
        events.push(`publish:${request.notificationId}`);
        if (failPublish && request.notificationId === 2100) throw failPublish;
        if (active.size >= limit || globalQuota) throw error(1700002);
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
    error(code, message, details) { resolve({ ok: false, code, message, details }); },
    notImplemented() { resolve({ ok: false, code: 'unimplemented' }); },
  });
  return {
    events, active, saved,
    failUpdate(value) { failUpdate = value; },
    setUpdateResponses(value) { updateResponses = value; },
    setDisplayed(value) { displayed = value; },
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
  const f = fixture({ enabled: false, old: [legacy(2000)] });
  f.setRequest(async () => { throw error(1600004); });
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_1600004');
  assert.equal(f.active.size, 1);
  assert.equal(f.events.some(event => event.startsWith('cancel')), false);
});

test('replaces legacy quota-sized schedule with one bounded daily recurrence', async () => {
  const f = fixture({ old: Array.from({ length: 30 }, (_, i) => legacy(2000 + i)), limit: 30 });
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
  const f = fixture({ old: [legacy(2000), { notificationId: 777 }] });
  f.failUpdate(error(201));
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_201');
  assert.deepEqual([...f.active.values()].map(x => x.notificationId).sort((a, b) => a - b), [777, 2000]);
});

test('partial cancellation failure restores previously removed reminders', async () => {
  const f = fixture({ old: [legacy(2000), legacy(2001)] });
  f.failCancel(2);
  assert.equal((await f.call('cancel')).code, 'reminder_1700004');
  assert.deepEqual([...f.active.values()].map(x => x.notificationId).sort(), [2000, 2001]);
});

test('disable succeeds without requesting notification permission', async () => {
  const f = fixture({ enabled: false, old: [daily(), { notificationId: 777 }] });
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
  const f = fixture({ old: [legacy(2000), legacy(2001)] });
  f.setUpdateResponses([undefined, error(201)]);
  f.failCancel(2);
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
  const f = fixture({ enabled: false, old: [daily()] });
  f.setRequest(async () => { f.enable(); f.setClock(end + 60_000); });
  assert.equal((await f.call('replaceDaily', { start: future, end })).code, 'reminder_invalid_time');
  assert.equal(f.events.includes('list'), false);
  assert.equal(f.active.size, 1);
});


test('quota-full legacy migration updates an owned ID without allocating any new slot', async () => {
  const f = fixture({ old: Array.from({ length: 30 }, (_, i) => legacy(2000 + i)), limit: 30, globalQuota: true });
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.ok, true);
  assert.equal(f.active.size, 1);
  assert.equal(f.events.some(event => event.startsWith('publish:')), false);
  assert.equal([...f.active.values()][0].groupId, 'runtrail.marathon.daily.v3');
  assert.deepEqual(f.saved.get('ownedIds'), [...f.active.keys()]);
});

test('repeated enables update the same persisted system ID, not duplicate reminders', async () => {
  const f = fixture();
  assert.equal((await f.call('replaceDaily', { start: future, end })).ok, true);
  const id = [...f.active.keys()][0];
  assert.equal((await f.call('replaceDaily', { start: future + 60_000, end })).ok, true);
  assert.deepEqual([...f.active.keys()], [id]);
  assert.equal(f.events.filter(event => event.startsWith('publish:')).length, 1);
});

test('numeric ID collisions or a stale saved ID never authorize deletion', async () => {
  const unrelated = { notificationId: 2100, reminderType: 1, title: 'Other feature', content: 'keep me' };
  const f = fixture({ old: [unrelated], savedIds: [1], limit: 1 });
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.code, 'reminder_1700002');
  assert.equal(f.active.get(1), unrelated);
  assert.equal(f.events.some(event => /^(update|cancel):/.test(event)), false);
  const details = JSON.parse(result.details);
  assert.equal(details.visible, 1);
  assert.equal(details.owned, 0);
  assert.equal(f.events.filter(event => event.startsWith('publish:')).length, 1);
});

test('full system quota with no owned entries reports counts and does not guess a cleanup target', async () => {
  const f = fixture({ globalQuota: true });
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.code, 'reminder_1700002');
  assert.equal(JSON.parse(result.details).visible, 0);
  assert.equal(f.events.filter(event => event.startsWith('publish:')).length, 1);
  assert.equal(f.active.size, 0);
});

test('displayed daily reminder is preserved when no replacement slot is available', async () => {
  const original = daily();
  const f = fixture({ old: [original], limit: 1 });
  f.setDisplayed([1]);
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.code, 'reminder_1700002');
  assert.equal(f.active.get(1), original);
  assert.equal(f.events.some(event => event.startsWith('cancel:')), false);
});

test('displayed first legacy reminder does not prevent updating a second owned candidate', async () => {
  const f = fixture({ old: [legacy(2000), legacy(2001)], limit: 2, globalQuota: true });
  f.setDisplayed([1]);
  assert.equal((await f.call('replaceDaily', { start: future, end })).ok, true);
  assert.deepEqual([...f.active.keys()], [2]);
  assert.equal(f.events.some(event => event.startsWith('publish:')), false);
});

test('API12 fallback frees only duplicate training slots and preserves unknown entries', async () => {
  const unknown = { notificationId: 888 };
  const f = fixture({ old: [legacy(2000), legacy(2001), unknown], api: 12, limit: 3 });
  assert.equal((await f.call('replaceDaily', { start: future, end })).ok, true);
  assert.equal(f.active.size, 2);
  assert.equal([...f.active.values()].includes(unknown), true);
  assert.equal(f.events.some(event => event.startsWith('update:')), false);
});

test('API12 quota failure restores deleted legacy tasks while retaining the last old reminder', async () => {
  const originals = [legacy(2000), legacy(2001)];
  const f = fixture({ old: originals, api: 12, limit: 2 });
  f.failPublish(error(1700002));
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.code, 'reminder_1700002');
  assert.equal(f.active.get(1), originals[0]);
  assert.deepEqual([...f.active.values()].map(x => x.notificationId).sort(), [2000, 2001]);
});

test('other feature groups and other target bundles are left alone even with a legacy signature', async () => {
  const first = { ...legacy(2000), groupId: 'another.feature' };
  const second = { ...daily(), wantAgent: { pkgName: 'another.bundle' } };
  const f = fixture({ old: [first, second] });
  assert.equal((await f.call('cancel')).ok, true);
  assert.equal(f.active.size, 2);
});

test('source never falls back to broad cancelAll or a fabricated delay for quota errors', () => {
  assert.equal(source.includes('cancelAllReminders'), false);
  assert.equal(source.includes('setTimeout'), false);
});

test('cleanup failure rolls the in-place update back to the original schedule', async () => {
  const original = legacy(2000);
  const f = fixture({ old: [original, legacy(2001)] });
  f.failCancel(2);
  const result = await f.call('replaceDaily', { start: future, end });
  assert.equal(result.code, 'reminder_1700004');
  assert.equal(f.active.get(1), original);
  assert.equal(f.active.size, 2);
  assert.equal(f.events.filter(event => event === 'update:1').length, 2);
});

test('a later permission error cannot reuse stale quota diagnostic details', async () => {
  const f = fixture({ globalQuota: true });
  const first = await f.call('replaceDaily', { start: future, end });
  assert.equal(first.code, 'reminder_1700002');
  f.failNotification(error(1600004));
  const second = await f.call('publishNow', { title: 'today' });
  assert.equal(second.code, 'reminder_1600004');
  assert.equal(second.details, '');
});
