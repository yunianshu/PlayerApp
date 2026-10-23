// Real API26 ArkTS bridge control flow with mocked OS calls. Not a HAP compile.
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../launcher_icons_api26/LauncherIconSupport.ets', import.meta.url), 'utf8')
  .replace(/^import .*;\n/gm, '').replace('export default class', 'class');
const javascript = stripTypeScriptTypes(source) + '\nglobalThis.Subject = LauncherIconSupport;';
function fixture({ version = 26, missing = false, current = '' } = {}) {
  let handler;
  let failSet = false;
  let failQuery = false;
  let ignoreNext = false;
  let gate;
  const calls = [];
  const context = {
    deviceInfo: { sdkApiVersion: version },
    bundleManager: {
      async getAlternateIcons() {
        calls.push('get');
        if (failQuery) throw Object.assign(new Error('query'), { code: 17700311 });
        return (missing ? ['light'] : ['light', 'dark', 'editorial']).map((style, i) =>
          ({ iconName: 'runtrail_' + style, iconId: i + 1, enabled: current === 'runtrail_' + style }));
      },
      async setAlternateIcon(name) {
        calls.push(name);
        if (gate) await gate;
        if (failSet) throw Object.assign(new Error('set'), { code: 17700310 });
        if (ignoreNext) { ignoreNext = false; return; }
        current = name;
      },
    },
    MethodChannel: class { setMethodCallHandler(value) { handler = value; } },
  };
  vm.runInNewContext(javascript, context);
  context.Subject.register({ dartExecutor: { getBinaryMessenger() {} } });
  return {
    calls, get current() { return current; },
    failSet() { failSet = true; }, failQuery() { failQuery = true; },
    ignoreNext() { ignoreNext = true; }, hold(value) { gate = value; },
    call(method, style) {
      return new Promise(resolve => handler.onMethodCall({ method, argument: () => style }, {
        success(value) { resolve({ ok: true, value }); },
        error(code, message) { resolve({ ok: false, code, message }); },
        notImplemented() { resolve({ ok: false, code: 'unimplemented' }); },
      }));
    },
  };
}

test('old system never calls API26 methods', async () => {
  const f = fixture({ version: 22 });
  assert.equal((await f.call('getSupport')).value, false);
  assert.equal((await f.call('setIcon', 'light')).code, 'UNSUPPORTED');
  assert.deepEqual(f.calls, []);
});
test('support requires all three installed alternate icon resources', async () => {
  assert.equal((await fixture().call('getSupport')).value, true);
  const f = fixture({ missing: true });
  assert.equal((await f.call('getSupport')).value, false);
  assert.equal((await f.call('setIcon', 'light')).code, 'MISSING_ICONS');
});
test('API query failure does not claim supported', async () => {
  const f = fixture(); f.failQuery();
  assert.equal((await f.call('getSupport')).value, false);
});
test('switch themes and restore default with readback', async () => {
  const f = fixture();
  for (const style of ['light', 'dark', 'editorial', 'default']) {
    assert.equal((await f.call('setIcon', style)).ok, true);
    assert.equal(f.current, style === 'default' ? '' : 'runtrail_' + style);
  }
});
test('already-default reset is idempotent, avoids native17700309', async () => {
  const f = fixture();
  assert.equal((await f.call('setIcon', 'default')).ok, true);
  assert.ok(!f.calls.includes(''));
});
test('invalid style never mutates OS state', async () => {
  const f = fixture();
  assert.equal((await f.call('setIcon', 'surprise')).code, 'INVALID_STYLE');
  assert.deepEqual(f.calls, []);
});
test('native set failure remains failure and previous icon remains', async () => {
  const f = fixture({ current: 'runtrail_dark' }); f.failSet();
  assert.equal((await f.call('setIcon', 'light')).code, 'ICON_CHANGE_FAILED');
  assert.equal(f.current, 'runtrail_dark');
});
test('nonchanging successful API response fails readback instead of fake success', async () => {
  const f = fixture({ current: 'runtrail_dark' }); f.ignoreNext();
  assert.equal((await f.call('setIcon', 'light')).code, 'ICON_CHANGE_FAILED');
  assert.equal(f.current, 'runtrail_dark');
});
test('native concurrent change rejected, pending operation remains consistent', async () => {
  const f = fixture(); let release;
  f.hold(new Promise(resolve => { release = resolve; }));
  const first = f.call('setIcon', 'light');
  assert.equal((await f.call('setIcon', 'dark')).code, 'BUSY');
  release();
  assert.equal((await first).ok, true);
  assert.equal(f.current, 'runtrail_light');
});

// Diagnostics must not collapse build configuration and device capability.
test('diagnostics distinguish API version, resources and native query error', async () => {
  assert.equal((await fixture({ version: 22 }).call('getSupportDetails')).value.reason, 'device_api_low');
  assert.equal((await fixture({ missing: true }).call('getSupportDetails')).value.reason, 'missing_icons');
  const f = fixture(); f.failQuery();
  const detail = (await f.call('getSupportDetails')).value;
  assert.equal(detail.reason, 'api_error');
  assert.equal(detail.nativeError, 17700311);
  assert.equal(detail.deviceApi, 26);
});
test('normal HAP diagnoses build mode rather than blaming the device', async () => {
  const stub = readFileSync(new URL('../../ohos/entry/src/main/ets/appearance/LauncherIconSupport.ets', import.meta.url), 'utf8')
    .replace(/^import .*;\n/gm, '').replace('export default class', 'class');
  let handler;
  const context = { deviceInfo: { sdkApiVersion: 26 },
    MethodChannel: class { setMethodCallHandler(value) { handler = value; } } };
  vm.runInNewContext(stripTypeScriptTypes(stub) + '\nglobalThis.Subject = LauncherIconSupport;', context);
  context.Subject.register({ dartExecutor: { getBinaryMessenger() {} } });
  let detail;
  handler.onMethodCall({ method: 'getSupportDetails' }, { success(value) { detail = value; } });
  assert.equal(detail.supported, false);
  assert.equal(detail.reason, 'build_not_enabled');
  assert.equal(detail.deviceApi, 26);
});
