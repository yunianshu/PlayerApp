// Host tests execute actual ArkTS policy; no claim of SDK/device validation.
// Run: node app/tool/test_tts_playback_ohos.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
const source = readFileSync(new URL('../ohos/entry/src/main/ets/running/TtsPlayback.ets', import.meta.url), 'utf8');
const js = stripTypeScriptTypes(source.replace(/^import .*;\s*$/gm, '').replace('export default ', ''));
const events = [];
class MockRenderer {
  constructor(format) { this.format = format; events.push(['create', ...format]); }
  async start() { events.push(['start']); }
  async write(chunk) { events.push(['write', chunk.byteLength]); return chunk.byteLength; }
  async drain() { events.push(['drain']); }
  async stop() { events.push(['stop']); }
  async release() { events.push(['release']); }
}
const TtsPlayback = new Function('console', `${js}; return TtsPlayback;`)(
  { error() {}, info() {} });
const policy = new TtsPlayback({ create: async (rate, ch, bit) => new MockRenderer([rate, ch, bit]) });
const chunk = size => new ArrayBuffer(size);
const settle = async () => {
  for (let i = 0; i < 12; i++) await new Promise(r => setImmediate(r));
};
const playback = list => events.filter(e => e[0] !== 'create').map(e => e.join(':'));

// 1. 乱序到达按 sequence 排序播放，正常收尾 drain→stop→release。
policy.startUtterance('a', 24000, 1, 16);
policy.feed('a', 0, chunk(10));
policy.feed('a', 2, chunk(30));
await settle();
assert.deepEqual(events.filter(e => e[0] === 'write').map(e => e[1]), [10]);
policy.feed('a', 1, chunk(20));
policy.complete('a');
await settle();
assert.deepEqual(events.filter(e => e[0] === 'write').map(e => e[1]), [10, 20, 30]);
assert.deepEqual(events[0], ['create', 24000, 1, 16]);
assert.deepEqual(playback(events.slice(1)), ['start', 'write:10', 'write:20', 'write:30', 'drain', 'stop', 'release']);
assert.equal(JSON.parse(policy.describe()).active, 0);

// 2. onStart 缺席时按系统缺省格式 16k/单声道/16bit。
events.length = 0;
policy.feed('dflt', 0, chunk(8));
policy.complete('dflt');
await settle();
assert.deepEqual(events[0], ['create', 16000, 1, 16]);

// 3. 队列接续：B 的数据在 A 播放期间缓冲，A 释放后 B 才建渲染器。
events.length = 0;
policy.feed('q1', 0, chunk(12));
policy.feed('q2', 0, chunk(14));
policy.complete('q2');
policy.complete('q1');
await settle();
assert.deepEqual(events.filter(e => e[0] === 'create').map(e => e[1]), [16000, 16000]);
assert.deepEqual(events.filter(e => e[0] === 'write').map(e => e[1]), [12, 14]);
assert.deepEqual(events.filter(e => e[0] === 'release'), [['release'], ['release']]);

// 4. cancel 立即静音：已建渲染器 stop+release，迟到回调被 epoch 丢弃。
events.length = 0;
policy.feed('c1', 0, chunk(16));
await settle();
policy.cancel();
policy.feed('c1', 1, chunk(16));
policy.complete('c1');
await settle();
assert.deepEqual(playback(), ['start', 'write:16', 'stop', 'release']);
assert.equal(JSON.parse(policy.describe()).active, 0);

// 4b. 渲染器尚未创建时 cancel：排队数据直接丢弃，不建渲染器。
events.length = 0;
policy.feed('c2', 0, chunk(16));
policy.cancel();
policy.complete('c2');
await settle();
assert.deepEqual(events, []);

// 5. 引擎自播回退（playType 未生效，无音频流）：不建渲染器、不抛错。
policy.complete('engine-played');
await settle();
assert.equal(JSON.parse(policy.describe()).active, 0);

// 6. 乱序缺口未补齐即完成：已写数据正常，剩余截断，无 drain。
events.length = 0;
policy.feed('gap', 0, chunk(6));
await settle();
policy.feed('gap', 2, chunk(6)); // 序号 1 永远不会到
policy.complete('gap');
await settle();
assert.deepEqual(playback(), ['start', 'write:6', 'stop', 'release']);

// 7. 渲染器创建失败：丢弃该段，不影响后续播报。
events.length = 0;
const failing = new TtsPlayback({
  create: async () => { throw new Error('no device'); },
});
failing.feed('f1', 0, chunk(4));
failing.complete('f1');
await settle();
failing.feed('f2', 0, chunk(4));
failing.complete('f2');
await settle();
assert.equal(JSON.parse(failing.describe()).active, 0);

console.info('tts playback policy: all host assertions passed');
