// 合成模式播报的播放策略：CoreSpeechKit 以 playType=0 只回 PCM 音频流，
// 由本类按 sequence 排序后写入注入的渲染器（STREAM_USAGE_NAVIGATION，
// 导航语义 → 系统对音乐压低音量而非暂停）。不 import 鸿蒙 kit，
// 渲染器经工厂注入，宿主 Node 测试直接执行（同 RunningNotification）。

export interface TtsRenderer {
  start(): Promise<void>;
  write(chunk: ArrayBuffer): Promise<number>;
  drain(): Promise<void>;
  stop(): Promise<void>;
  release(): Promise<void>;
}

export interface TtsRendererFactory {
  create(sampleRate: number, channels: number, sampleBit: number): Promise<TtsRenderer>;
}

interface TtsUtterance {
  requestId: string;
  sampleRate: number; // 0 = onStart 未回报，建渲染器时落默认值
  channels: number;
  sampleBit: number;
  nextSequence: number;
  pending: Map<number, ArrayBuffer>;
  synthesisDone: boolean;
  renderer?: TtsRenderer;
}

export default class TtsPlayback {
  private factory: TtsRendererFactory;
  private epoch: number = 0;
  private queue: TtsUtterance[] = [];
  private chain: Promise<void> = Promise.resolve();
  // cancel 后引擎仍会回调在途 requestId（engine.stop 异步生效），
  // 拉黑防止迟到数据重建出幽灵播报。requestId 每次播报唯一。
  private discarded: Set<string> = new Set<string>();

  constructor(factory: TtsRendererFactory) {
    this.factory = factory;
  }

  /** 新一段播报开始（onStart 的格式回报；晚于首包数据时格式为 0）。 */
  startUtterance(requestId: string, sampleRate: number, channels: number, sampleBit: number): void {
    if (this.discarded.has(requestId)) return;
    const epoch = this.epoch;
    this.enqueue(() => {
      this.upsert(requestId, sampleRate, channels, sampleBit);
    }, epoch);
  }

  /** 收到一段 PCM（可能乱序、可能分多次回调）。 */
  feed(requestId: string, sequence: number, chunk: ArrayBuffer): void {
    if (this.discarded.has(requestId)) return;
    const epoch = this.epoch;
    this.enqueue(() => {
      const utterance = this.upsert(requestId, 0, 0, 0);
      if (!utterance.pending.has(sequence)) {
        utterance.pending.set(sequence, chunk);
      }
    }, epoch);
  }

  /** 该段合成结束（onComplete）：写完剩余数据后收尾渲染器。 */
  complete(requestId: string): void {
    if (this.discarded.has(requestId)) return;
    const epoch = this.epoch;
    this.enqueue(() => {
      const utterance = this.find(requestId);
      if (utterance !== undefined) {
        utterance.synthesisDone = true;
      }
    }, epoch);
  }

  /** 打断/停止：丢弃全部排队音频，立即静音当前渲染器。 */
  cancel(): void {
    this.epoch++;
    const dropped = this.queue;
    this.queue = [];
    for (const utterance of dropped) {
      this.discarded.add(utterance.requestId);
      const renderer = utterance.renderer;
      if (renderer !== undefined) {
        renderer.stop().then((): Promise<void> => renderer.release()).catch(() => {});
      }
    }
  }

  /** 测试与诊断快照：当前排队/播放中的播报状态。 */
  describe(): string {
    const items: string[] = [];
    for (const utterance of this.queue) {
      items.push(JSON.stringify({
        requestId: utterance.requestId,
        buffered: utterance.pending.size,
        nextSequence: utterance.nextSequence,
        synthesisDone: utterance.synthesisDone,
        playing: utterance.renderer !== undefined,
      }));
    }
    return JSON.stringify({ active: items.length, utterances: items });
  }

  private find(requestId: string): TtsUtterance | undefined {
    for (const utterance of this.queue) {
      if (utterance.requestId === requestId) {
        return utterance;
      }
    }
    return undefined;
  }

  private upsert(requestId: string, sampleRate: number, channels: number, sampleBit: number): TtsUtterance {
    let utterance = this.find(requestId);
    if (utterance === undefined) {
      utterance = {
        requestId: requestId,
        sampleRate: 0,
        channels: 0,
        sampleBit: 0,
        nextSequence: 0,
        pending: new Map<number, ArrayBuffer>(),
        synthesisDone: false,
      };
      this.queue.push(utterance);
    }
    if (sampleRate > 0 && utterance.sampleRate === 0) {
      utterance.sampleRate = sampleRate;
      utterance.channels = channels;
      utterance.sampleBit = sampleBit;
    }
    return utterance;
  }

  // 单链串行：所有状态变更排队执行，数据在写入期间到达只进缓冲，
  // 下一轮 pump 按序写出——乱序回调与并发写入都不会破坏播放顺序。
  private enqueue(work: () => void, epoch: number): void {
    const step = this.chain.then(() => {
      if (epoch !== this.epoch) return;
      work();
      return this.pump(epoch);
    });
    this.chain = step.then(() => {}, () => {});
  }

  private async pump(epoch: number): Promise<void> {
    while (this.queue.length > 0) {
      if (epoch !== this.epoch) return; // cancel 后不再碰旧数据
      const utterance = this.queue[0];
      if (utterance.renderer === undefined) {
        if (utterance.pending.size === 0) {
          // 无数据即完成：引擎自播（playType 未生效）或空文本，无需渲染器。
          if (utterance.synthesisDone) {
            this.queue.shift();
            continue;
          }
          return; // 等首包数据。
        }
        // 没有 onStart 格式回报时按系统 TTS 缺省（16k/单声道/16bit）。
        const sampleRate = utterance.sampleRate > 0 ? utterance.sampleRate : 16000;
        const channels = utterance.channels > 0 ? utterance.channels : 1;
        const sampleBit = utterance.sampleBit > 0 ? utterance.sampleBit : 16;
        try {
          const renderer = await this.factory.create(sampleRate, channels, sampleBit);
          if (epoch !== this.epoch) {
            renderer.release().catch(() => {});
            return;
          }
          utterance.renderer = renderer;
          await renderer.start();
        } catch (error) {
          console.error(`tts renderer create failed: ${JSON.stringify(error)}`);
          this.queue.shift();
          continue;
        }
      }
      while (utterance.pending.has(utterance.nextSequence)) {
        const chunk = utterance.pending.get(utterance.nextSequence) as ArrayBuffer;
        utterance.pending.delete(utterance.nextSequence);
        utterance.nextSequence++;
        try {
          await utterance.renderer?.write(chunk);
        } catch (error) {
          console.error(`tts renderer write failed: ${JSON.stringify(error)}`);
          utterance.pending.clear();
          break;
        }
      }
      if (!utterance.synthesisDone) return; // 还有数据在路上，等下一次 feed。
      const renderer = utterance.renderer;
      const dropped = utterance.pending.size > 0; // 乱序缺口未补齐：截断收尾
      this.queue.shift();
      if (renderer === undefined || dropped) {
        if (renderer !== undefined) {
          renderer.stop().then((): Promise<void> => renderer.release()).catch(() => {});
        }
        continue;
      }
      try {
        await renderer.drain();
        await renderer.stop();
      } catch (error) {
        console.error(`tts renderer stop failed: ${JSON.stringify(error)}`);
      }
      await renderer.release().catch(() => {});
    }
  }
}
