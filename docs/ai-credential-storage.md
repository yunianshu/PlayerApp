# AI credential storage

The `runtrail/ai_credentials` MethodChannel stores one opaque string envelope. Dart
binds the API key to its configured endpoint inside that envelope. The native layer
does not interpret, log, sync, or place that envelope in normal preferences,
diagnostic logs, exported training data, or app backup files.

## 管理与使用

- 入口为「我的 → AI 服务设置」，也可从马拉松训练页的「AI 服务设置」进入。
- 填写兼容 OpenAI Chat Completions 协议的完整 HTTPS 请求地址和服务商提供的
  模型名称，不是只填网站域名。地址不能夹带账号、查询参数或片段。
- 已保存的密钥不会回填到输入框，也不能通过显示密码按钮重新展示；显示按钮
  只作用于本次手动输入的内容。更换接口地址后必须重新输入密钥，不会把原密钥
  自动发送给新地址。
- 「保存」只修改本机配置，不调用远程模型。安全保存失败不会转为明文保存；
  仅本次运行使用的密钥保存在内存中，重启应用后需重新输入。
- 「测试连接」会先显示目标地址、模型、固定测试文本的发送说明及可能产生的
  调用费用，确认后才发送密钥与测试请求，不发送跑步记录、恢复评分或 GPS。
  测试本身不会保存配置。
- 训练分析是独立的确认步骤：用户审核将发送的训练摘要与目标服务后才发送。
  不把连接测试的同意视为训练数据分享的同意。
- AI 分析不直接修改训练计划。原有本地保守调整提案、逐项审核和确认应用的
  流程保持不变；联网分析不是自动执行计划变更的授权。

## Contract

- `read`: returns the saved string, or `null` only when no record exists.
- `write`: receives `{apiKey: String}`. The complete UTF-8 envelope must contain
  1–1024 bytes. A successful call means the secure backend accepted the write.
- `delete`: deletes the credential and succeeds if already absent.
- Failure: returns a sanitized `secure_storage_unavailable` PlatformException.
  Invalid method arguments can return `invalid_credentials`. The bridge never
  echoes the key, endpoint, or underlying platform error. There is no plaintext
  fallback. The UI must obtain an explicit choice before session-only use.

## Platform behavior

### HarmonyOS native HAP

`AiCredentialsStore.ets` uses Asset Store with `SECRET`, `DEVICE_UNLOCKED`, and
`SyncType.NEVER`. The alias is constant and contains no secret information.
Overwrite uses the same asset, while writes/deletes are serialized. The
`IS_PERSISTENT` attribute is omitted, keeping its default false without requesting
the persistent-data permission; the asset is not retained after uninstall.

Asset Store APIs require API 11. This implementation's UTF-8 decoder requires API
12, matching this project's existing minimum. A locked device, missing system
capability, corrupted asset, or service failure is a storage error, not an empty
credential. No lock-screen password means `DEVICE_UNLOCKED` provides no additional
lock-state protection. This is app-local encrypted storage, not remote key custody.

### Android

API 23+ Android Keystore holds a non-exportable 256-bit AES key. AES-GCM encrypts
the credential using a fresh provider-generated 12-byte IV and 128-bit tag for each
write. The fixed key alias is authenticated as AAD. The versioned ciphertext file
is written atomically under `noBackupFilesDir` and read back before success is
reported. Reads never generate a replacement key if the original key is missing.
Delete removes the Keystore key and ciphertext. No new dependency is added.

Keystore hardware backing depends on the device; this implementation does not
claim StrongBox support or biometric authentication. Unlike the HarmonyOS/iOS
backends, it does not impose a device-unlocked-only Keystore policy. Below API 23,
or if Keystore/filesystem access fails, durable storage fails explicitly.

### iOS

The existing AppDelegate registers a generic-password Keychain item with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and synchronization disabled.
Updates use `SecItemUpdate`, and missing records use `SecItemAdd`; there is no
delete-then-write gap. Keychain operations use a serial background queue. The item
does not migrate to a different device or synchronize through iCloud. Keychain
items can survive app uninstall on the same device, so users who want to remove
the credential should use the app's clear-key action before uninstalling.

## Validation and release checks

No real API keys or external AI calls are needed for these checks.

1. `python3 -m unittest discover -s app/tool/tests -p test_ai_credentials_native.py -v`
   validates source-policy guardrails and registrations. These are not runtime
   encryption tests.
2. `node app/tool/test_ai_credentials_ohos.mjs` (Node 22.13+) type-strips the actual
   ArkTS source and runs the in-memory Hypium cases plus channel serialization,
   redacted failures, malformed UTF-8, and argument checks with mocked APIs. It is
   not an ArkTS compiler or native Asset Store integration test.
3. On DevEco, run the registered `AiCredentialsStore.test.ets` Hypium suite and
   build the native HAP. Android requires a Gradle/Flutter Android build; iOS
   requires macOS/Xcode. These SDK builds and device checks were not run in the
   editing environment.
4. On each supported device, save a synthetic credential, force-stop/relaunch,
   replace, clear, and relaunch again. Confirm the UI never reports failed storage
   as saved. Cover locked-device reads, unavailable/corrupt storage, rapid
   save/clear, no configured lock screen, and app backup/restore to another device.
5. Verify exported training JSON and diagnostic logs contain no credential. Test
   explicit session-only mode separately and confirm it is empty after restart.

Managed strings cannot be reliably zeroized; native mutable byte buffers are
cleared where possible. Secrets necessarily exist briefly in application memory
to make an authorized request. Rooted/jailbroken devices and hostile code running
inside this application are outside the storage protection boundary.

## Official API references

- [OpenHarmony Asset Store API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-asset-store-kit/js-apis-asset.md)
- [OpenHarmony TextDecoder API](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-arkts/js-apis-util.md)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Android cryptography guidance](https://developer.android.com/privacy-and-security/cryptography)
- [Android no-backup directory](https://developer.android.com/reference/android/content/Context#getNoBackupFilesDir())
- [Apple device-only Keychain accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Apple Keychain synchronization](https://developer.apple.com/documentation/security/ksecattrsynchronizable)
