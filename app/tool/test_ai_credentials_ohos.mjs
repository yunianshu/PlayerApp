// Host-side logic tests of the actual ArkTS source with mocked platform APIs.
// Requires Node 22.13+; does NOT replace ArkTS compilation or device tests.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const sourceUrl = new URL('../ohos/entry/src/main/ets/security/AiCredentialsStore.ets', import.meta.url);
const testUrl = new URL('../ohos/entry/src/ohosTest/ets/test/AiCredentialsStore.test.ets', import.meta.url);
const prepare = (url) => stripTypeScriptTypes(readFileSync(url, 'utf8')
  .replace(/^import .*;\s*$/gm, '')
  .replace(/export default /g, '')
  .replace(/export interface /g, 'interface '));

let handler;
let stored;
let failure;
let holdWrite;
const asset = {
  Tag: Object.fromEntries(['SECRET', 'ALIAS', 'ACCESSIBILITY', 'SYNC_TYPE', 'CONFLICT_RESOLUTION',
    'IS_PERSISTENT', 'RETURN_TYPE', 'RETURN_LIMIT'].map((name) => [name, name])),
  Accessibility: { DEVICE_UNLOCKED: 2 },
  SyncType: { NEVER: 0 },
  ConflictResolution: { OVERWRITE: 0 },
  ReturnType: { ALL: 0 },
  async add(attributes) {
    if (failure) throw failure;
    if (holdWrite) await holdWrite;
    stored = new Uint8Array(attributes.get('SECRET'));
  },
  async query() {
    if (failure) throw failure;
    if (!stored) throw Object.assign(new Error('missing'), { code: 24000002 });
    return [new Map([['SECRET', new Uint8Array(stored)]])];
  },
  async remove() {
    if (failure) throw failure;
    if (!stored) throw Object.assign(new Error('missing'), { code: 24000002 });
    stored = undefined;
  },
};
const util = {
  TextEncoder: class {
    encodeInto(value) { return new TextEncoder().encode(value); }
  },
  TextDecoder: {
    create(encoding, options) {
      const decoder = new TextDecoder(encoding, options);
      return { decodeToString: (bytes) => decoder.decode(bytes) };
    },
  },
};
class MethodChannel {
  constructor(_messenger, name) { assert.equal(name, 'runtrail/ai_credentials'); }
  setMethodCallHandler(value) { handler = value; }
}
const cases = [];
const describe = (_name, body) => body();
const it = (name, _flag, body) => cases.push({ name, body });
const expect = (actual) => ({
  assertEqual: (expected) => assert.equal(actual, expected),
  assertTrue: () => assert.equal(actual, true),
  assertFalse: () => assert.equal(actual, false),
});
const Store = new Function('asset', 'util', 'MethodChannel', 'describe', 'it', 'expect',
  `${prepare(sourceUrl)}\n${prepare(testUrl)}\naiCredentialsStoreTest(); return AiCredentialsStore;`)(
  asset, util, MethodChannel, describe, it, expect);

function invoke(method, value) {
  return new Promise((resolve) => handler.onMethodCall(
    { method, argument: () => value },
    {
      success: (value) => resolve({ value }),
      error: (code, message, details) => resolve({ error: { code, message, details } }),
      notImplemented: () => resolve({ unimplemented: true }),
    },
  ));
}
Store.register({ dartExecutor: { getBinaryMessenger: () => ({}) } });
cases.push({ name: 'channel returns null for missing reads and idempotent deletes', body: async () => {
  assert.deepEqual(await invoke('read'), { value: null });
  assert.deepEqual(await invoke('delete'), { value: null });
} });
cases.push({ name: 'channel serializes an in-flight save before delete', body: async () => {
  let release;
  holdWrite = new Promise((resolve) => { release = resolve; });
  const save = invoke('write', 'synthetic-enqueued');
  const remove = invoke('delete');
  await Promise.resolve();
  release();
  assert.deepEqual(await save, { value: null });
  assert.deepEqual(await remove, { value: null });
  holdWrite = undefined;
  assert.deepEqual(await invoke('read'), { value: null });
} });
cases.push({ name: 'channel sanitizes backend failures without poisoning the queue', body: async () => {
  failure = Object.assign(new Error('DO_NOT_LEAK_SYNTHETIC_CREDENTIAL'), { code: 24000001 });
  for (const method of ['read', 'write', 'delete']) {
    const response = await invoke(method, 'synthetic');
    assert.deepEqual(response, { error: {
      code: 'secure_storage_unavailable', message: 'Secure credential storage is unavailable', details: null,
    } });
  }
  failure = undefined;
  assert.deepEqual(await invoke('write', 'synthetic-recovered'), { value: null });
  assert.deepEqual(await invoke('read'), { value: 'synthetic-recovered' });
} });
cases.push({ name: 'channel rejects invalid arguments and supports unknown methods', body: async () => {
  for (const value of [null, undefined, 10, '', {}]) {
    assert.equal((await invoke('write', value)).error?.code, 'invalid_credentials');
  }
  assert.deepEqual(await invoke('futureMethod'), { unimplemented: true });
} });
cases.push({ name: 'malformed UTF-8 is a storage failure, not a replacement credential', body: async () => {
  stored = new Uint8Array([0xff]);
  assert.equal((await invoke('read')).error?.code, 'secure_storage_unavailable');
  await invoke('delete');
} });

for (const { name, body } of cases) {
  await body();
  process.stdout.write(`PASS ${name}\n`);
}
process.stdout.write(`${cases.length} mocked Harmony logic tests passed; native SDK/device validation remains required.\n`);
