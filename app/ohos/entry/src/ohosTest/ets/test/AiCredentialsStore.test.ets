import { describe, expect, it } from '@ohos/hypium';
import { asset } from '@kit.AssetStoreKit';
import AiCredentialsStore, { CredentialAssetBackend } from '../../../main/ets/security/AiCredentialsStore';

class FakeAssetFailure extends Error {
  code: number;

  constructor(code: number) {
    super('Synthetic backend failure');
    this.code = code;
  }
}

// Uses only synthetic in-memory credentials. Never queries the device's Asset Store.
class FakeAssetBackend implements CredentialAssetBackend {
  secret?: Uint8Array;
  attributes: asset.AssetMap = new Map();
  failureCode: number = 0;
  malformed: boolean = false;

  async add(attributes: asset.AssetMap): Promise<void> {
    this.checkFailure();
    this.attributes = attributes;
    this.secret = new Uint8Array(attributes.get(asset.Tag.SECRET) as Uint8Array);
  }

  async query(_query: asset.AssetMap): Promise<Array<asset.AssetMap>> {
    this.checkFailure();
    if (this.malformed) {
      return [new Map<asset.Tag, asset.Value>()];
    }
    if (this.secret === undefined) {
      throw new FakeAssetFailure(24000002);
    }
    const row: asset.AssetMap = new Map();
    row.set(asset.Tag.SECRET, new Uint8Array(this.secret));
    return [row];
  }

  async remove(_query: asset.AssetMap): Promise<void> {
    this.checkFailure();
    if (this.secret === undefined) {
      throw new FakeAssetFailure(24000002);
    }
    this.secret = undefined;
  }

  private checkFailure(): void {
    if (this.failureCode !== 0) {
      throw new FakeAssetFailure(this.failureCode);
    }
  }
}

export default function aiCredentialsStoreTest() {
  describe('AiCredentialsStore', () => {
    it('missing credential reads null and delete is idempotent', 0, async () => {
      const store = new AiCredentialsStore(new FakeAssetBackend());
      expect(await store.read()).assertEqual(null);
      await store.delete();
      await store.delete();
    });

    it('round trips and replaces the opaque envelope with device-only policy', 0, async () => {
      const backend = new FakeAssetBackend();
      const store = new AiCredentialsStore(backend);
      await store.write('synthetic-envelope-one');
      expect(await store.read()).assertEqual('synthetic-envelope-one');
      expect(backend.attributes.get(asset.Tag.ACCESSIBILITY)).assertEqual(asset.Accessibility.DEVICE_UNLOCKED);
      expect(backend.attributes.get(asset.Tag.SYNC_TYPE)).assertEqual(asset.SyncType.NEVER);
      expect(backend.attributes.get(asset.Tag.CONFLICT_RESOLUTION)).assertEqual(asset.ConflictResolution.OVERWRITE);
      expect(backend.attributes.has(asset.Tag.IS_PERSISTENT)).assertFalse();
      await store.write('synthetic-envelope-two');
      expect(await store.read()).assertEqual('synthetic-envelope-two');
      await store.delete();
      expect(await store.read()).assertEqual(null);
    });

    it('validates bytes rather than characters and leaves the previous value intact', 0, async () => {
      const store = new AiCredentialsStore(new FakeAssetBackend());
      await store.write('x'.repeat(1024));
      expect((await store.read())?.length).assertEqual(1024);
      let failed = false;
      try {
        await store.write('中'.repeat(342));
      } catch (_) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect((await store.read())?.length).assertEqual(1024);
    });

    it('rejects empty and malformed credentials', 0, async () => {
      const backend = new FakeAssetBackend();
      const store = new AiCredentialsStore(backend);
      let emptyFailed = false;
      try {
        await store.write('');
      } catch (_) {
        emptyFailed = true;
      }
      expect(emptyFailed).assertTrue();
      backend.malformed = true;
      let readFailed = false;
      try {
        await store.read();
      } catch (_) {
        readFailed = true;
      }
      expect(readFailed).assertTrue();
    });

    it('does not mistake backend failures for absent or deleted credentials', 0, async () => {
      const backend = new FakeAssetBackend();
      const store = new AiCredentialsStore(backend);
      backend.failureCode = 24000001;
      let failures = 0;
      try { await store.read(); } catch (_) { failures++; }
      try { await store.write('synthetic'); } catch (_) { failures++; }
      try { await store.delete(); } catch (_) { failures++; }
      expect(failures).assertEqual(3);
    });
  });
}
