// Host tests execute actual ArkTS policy; no claim of SDK/device validation.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../ohos/entry/src/main/ets/running/RunningNotification.ets', import.meta.url), 'utf8');
const js = stripTypeScriptTypes(source.replace(/^import .*;\s*$/gm, '').replace('export default ', ''));
let calls = [], fail = false, gate;
const manager = {
  SlotType: { SOCIAL_COMMUNICATION: 1 },
  async addSlot(type) { calls.push(['slot', type]); },
  async getSlot() { return { vibrationEnabled: true, level: 4 }; },
  async publish(req) { if (gate) await gate; if (fail) throw { code: 1600004 }; calls.push(['publish', req]); },
  async cancel(id) { calls.push(['cancel', id]); },
};
const policy = new Function('notificationManager', 'notification', 'console', `${js}; return RunningNotification;`)(manager,
  { ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 } }, { info() {} });
const run = new policy();
assert.equal(JSON.parse(await run.update('stats', 'before', 0)).outcome, 'inactive');
run.begin();
for (const ms of [0, 10000, 20000, 30000, 40000, 90000]) {
  const summary = JSON.parse(await run.update('private distance', `id-${ms}`, ms));
  assert.equal(summary.outcome, 'accepted');
  assert.equal(summary.vibrationObserved, 'unknown');
  assert.equal(summary.vibrationEnabled, true);
  assert.ok(!JSON.stringify(summary).includes('private'));
}
assert.equal(calls.filter(c => c[0] === 'slot').length, 1);
assert.equal(calls.filter(c => c[0] === 'publish').length, 6);
for (const [, req] of calls.filter(c => c[0] === 'publish')) {
  assert.equal(req.id, 1001); assert.equal(req.isAlertOnce, true);
  assert.equal(req.notificationSlotType, 1);
  assert.ok(!('notificationFlags' in req)); // API23-only writable field prohibited.
}
fail = true;
await assert.rejects(run.update('stats', 'failed', 100000));
fail = false;
assert.equal(JSON.parse(await run.update('stats', 'retry', 110000)).outcome, 'accepted');
// Stop waits for in-flight publish, then cancels. Late queued work cannot resurrect it.
let release;
gate = new Promise(r => { release = r; });
const pending = run.update('stats', 'inflight', 120000);
await new Promise(r => setImmediate(r));
const late = run.update('stats', 'queued', 120001);
const stopped = run.end();
release(); await pending; await stopped;
assert.equal(JSON.parse(await late).outcome, 'inactive');
assert.equal(calls.at(-1)[0], 'cancel');
gate = undefined;
assert.equal(JSON.parse(await run.update('stats', 'after', 130000)).outcome, 'inactive');
run.begin();
assert.equal(JSON.parse(await run.update('stats', 'resume', 140000)).outcome, 'accepted');
assert.equal(calls.filter(c => c[0] === 'slot').length, 2);
await run.end();
assert.ok(calls.filter(c => c[0] === 'cancel').every(c => c[1] === 1001));
assert.ok(!source.includes('cancelAll'));
console.log('PASS: running notification 0–90s, silent policy, errors, stop race, resume, isolation');
