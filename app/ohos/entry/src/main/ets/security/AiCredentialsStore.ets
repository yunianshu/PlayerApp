import { FlutterEngine, MethodCall, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// The native bridge stores an opaque endpoint/key envelope, never preferences.
// Asset Store SECRET has a 1024-byte limit; the Dart layer validates the same limit.
const MAX_CREDENTIAL_BYTES: number = 1024;
const ASSET_NOT_FOUND: number = 24000002;
const CREDENTIAL_ALIAS: string = 'runtrail.ai_credentials.v1';

export interface CredentialAssetBackend {
  add(attributes: asset.AssetMap): Promise<void>;
  query(query: asset.AssetMap): Promise<Array<asset.AssetMap>>;
  remove(query: asset.AssetMap): Promise<void>;
}

class SystemCredentialAssetBackend implements CredentialAssetBackend {
  add(attributes: asset.AssetMap): Promise<void> {
    return asset.add(attributes);
  }

  query(query: asset.AssetMap): Promise<Array<asset.AssetMap>> {
    return asset.query(query);
  }

  remove(query: asset.AssetMap): Promise<void> {
    return asset.remove(query);
  }
}

export default class AiCredentialsStore {
  private backend: CredentialAssetBackend;
  private pending: Promise<void> = Promise.resolve();

  constructor(backend: CredentialAssetBackend = new SystemCredentialAssetBackend()) {
    this.backend = backend;
  }

  static register(engine: FlutterEngine): void {
    const store = new AiCredentialsStore();
    const channel = new MethodChannel(
      engine.dartExecutor.getBinaryMessenger(), 'runtrail/ai_credentials');
    channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        // Serialize writes/deletes so an older save cannot resurrect a removed key.
        store.pending = store.pending.then(() => store.handle(call, result));
      }
    });
  }

  async read(): Promise<string | null> {
    const query = this.aliasQuery();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    query.set(asset.Tag.RETURN_LIMIT, 1);
    let rows: Array<asset.AssetMap>;
    try {
      rows = await this.backend.query(query);
    } catch (error) {
      if ((error as BusinessError).code === ASSET_NOT_FOUND) {
        return null;
      }
      throw error;
    }
    // A successful but malformed response is not treated as a missing key.
    if (rows.length !== 1) {
      throw new Error('Invalid credential record');
    }
    const secret = rows[0].get(asset.Tag.SECRET);
    if (!(secret instanceof Uint8Array) || secret.length === 0 ||
      secret.length > MAX_CREDENTIAL_BYTES) {
      throw new Error('Invalid credential record');
    }
    try {
      return util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(secret);
    } finally {
      secret.fill(0);
    }
  }

  async write(value: string): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(value);
    try {
      if (bytes.length === 0 || bytes.length > MAX_CREDENTIAL_BYTES) {
        throw new Error('Invalid credential size');
      }
      const attributes = this.aliasQuery();
      attributes.set(asset.Tag.SECRET, bytes);
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
      attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
      attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      // IS_PERSISTENT is deliberately omitted: default false, no persistent-data
      // permission, and the OS removes this asset when the application is uninstalled.
      await this.backend.add(attributes);
    } finally {
      bytes.fill(0);
    }
  }

  async delete(): Promise<void> {
    try {
      await this.backend.remove(this.aliasQuery());
    } catch (error) {
      if ((error as BusinessError).code !== ASSET_NOT_FOUND) {
        throw error;
      }
    }
  }

  private aliasQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(CREDENTIAL_ALIAS));
    return query;
  }

  private async handle(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (call.method === 'read') {
        result.success(await this.read());
      } else if (call.method === 'write') {
        const value: string | null = call.argument('apiKey');
        if (typeof value !== 'string' || value.length === 0) {
          result.error('invalid_credentials', 'Invalid credential data', null);
          return;
        }
        await this.write(value);
        result.success(null);
      } else if (call.method === 'delete') {
        await this.delete();
        result.success(null);
      } else {
        result.notImplemented();
      }
    } catch (_) {
      // Never expose platform error messages, record contents, URLs or key data.
      // Dart must ask for explicit session-only use; there is no plaintext fallback.
      result.error('secure_storage_unavailable', 'Secure credential storage is unavailable', null);
    }
  }
}
