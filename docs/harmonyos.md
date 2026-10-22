# HarmonyOS 构建与验收

鸿蒙端使用 OpenHarmony-SIG Flutter 3.22 / Dart 3.4，标准 Android/iOS 端使用主 Flutter 工具链。两套依赖和生成文件隔离，应用 `lib/` 共用。本次已在 Windows + DevEco Studio 6.0.2（SDK API 22、hvigor 6.22.3）构建出签名 release HAP；尚无连接设备进行后台定位验收。

## 本机配置

准备鸿蒙 Flutter SDK、DevEco Studio 6.0.2、Node.js（本次为 v24）和 Python 3.10+。命令行需能执行 `node`、`npm`、`python`。以下命令在 `app/` 运行：

```powershell
Copy-Item tool/ohos.local.example.json tool/ohos.local.json
```

编辑 `tool/ohos.local.json` 中的 `flutter_sdk` 和 `deveco_home` 为实际安装路径。也可通过 `OHOS_FLUTTER_SDK`、`DEVECO_HOME` 覆盖。该本机文件已加入忽略规则。

缓存默认使用仓库根目录下 `.pub-cache-ohos`；可在配置中增加 `pub_cache`，必须与项目同盘，以兼容上游插件的相对路径处理。脚本为子进程设置缓存，不依赖全局 `PUB_CACHE`。

## 构建

```powershell
python tool/ohos_build.py release --analyze
# 缓存完整时可离线解析 Dart 依赖（npm/ohpm/SDK 仍可能访问网络）
python tool/ohos_build.py debug --offline
# 只准备可在 DevEco 打开的工程
python tool/ohos_build.py --prepare-only
```

Git Bash 可继续使用 `bash tool/ohos_build.sh release`，该入口调用同一个 Python 脚本。

脚本在 `app/build/ohos-workspace` 创建工程副本，使用 `pubspec_ohos.yaml` 和独立锁文件，生成插件清单，再构建 HAP。主工程 `pubspec.yaml`、`pubspec.lock`、`.dart_tool` 与插件清单均不被切换。产物复制到 `app/build/ohos/hap/`。

不要在构建期间编辑隔离工程：每次重新运行脚本会重建该目录。源代码应编辑 `app/lib`、`app/ohos` 等源目录。脚本使用 `build/.ohos-build-lock` 防止并发；异常会释放锁。若进程被强制终止，确认无构建进程后仅移除这个空锁目录，再重试。

## 签名与 DevEco

公共 `app/ohos/build-profile.json5` 保留无个人信息的配置。需要签名时，把完整签名配置保存为 **`app/ohos/build-profile.local.json5`**，脚本会将其应用到隔离工程。这个文件包含证书路径和签名字段，已加入忽略规则；不要提交证书和口令。本次工作区原有签名配置已保留到该文件。

新电脑可这样配置：

1. 运行 `python tool/ohos_build.py --prepare-only`。
2. 在设置了相同 `PUB_CACHE` 和 `DEVECO_HOME` 的环境中启动 DevEco，打开 `app/build/ohos-workspace/ohos`，使用鸿蒙 Flutter SDK。不要打开主目录的 `app/ohos` 直接同步。
3. 通过 Project Structure → Signing Configs 完成账号授权和签名生成。
4. 将隔离工程生成的完整 `build-profile.json5` 复制为源目录的 `app/ohos/build-profile.local.json5`，之后重跑构建脚本。

有签名配置时产物为 `entry-default-signed.hap`；未配置时只能使用 unsigned 产物进行编译验证。安装示例：

```powershell
hdc list targets
hdc install build/ohos/hap/entry-default-signed.hap
```

`hdc` 可从 DevEco SDK 工具目录加入当前进程 PATH。

## 蒲公英网页安装

**release 编译模式与发布签名是两件事。** `entry-default-signed.hap` 这个文件名只表示经过签名；如果包内 Profile 的 `type` 是 `debug`，仍是调试包。它可以在授权设备上通过 HDC 安装，但不符合蒲公英网页安装的签名要求。

蒲公英要求华为签发的发布证书、**指定设备发布** Profile，以及与 HAP 匹配的 P12。平台用 P12 签署下载所需的安装清单，不会替开发者重签 HAP。参考[蒲公英鸿蒙分发说明](https://www.pgyer.com/doc/view/harmonyos)。

首次准备（`app/` 目录）：

```powershell
python tool/ohos_distribution.py prepare
```

命令会在已忽略的 `signing/harmony-release/` 中生成发布密钥库、随机口令配置和 `runtrail-release.csr`，再次执行会复用现有密钥。**生成 CSR 还不等于取得发布证书。** P12 此时只含本地占位证书，不能直接拿去蒲公英分发。

在华为 AppGallery Connect 的“证书、APP ID 和 Profile”中完成：

1. 申请**发布证书**，上传 `runtrail-release.csr`；把华为返回的证书链保存为 `signing/harmony-release/runtrail-release.cer`。
2. 为 `com.runtrail.runtrail` 申请**指定设备发布 Profile**，关联上述发布证书，勾选要安装的设备（包括 P70 的 UDID）；下载为 `signing/harmony-release/runtrail-release.p7b`。
3. 不要用调试 Profile 或应用市场发布 Profile 代替指定设备发布 Profile；设备授权与权限申请以 AGC 当前要求为准。

随后构建、签名并上传：

```powershell
python tool/ohos_build.py release --offline
python tool/ohos_distribution.py sign
python tool/ohos_distribution.py check
& 'C:/Ruby33-x64/bin/fastlane.bat' runtrail pgyer_hap desc:"更新说明"
```

分发包单独输出到 `build/ohos/distribution/entry-default-signed.hap`。签名脚本会将华为签发的证书链导入发布 P12，并检查 Profile 的签名、`release` 与 `internaltesting` 类型、设备 UDID 列表、有效期、包名、私钥与证书是否匹配。可在本地 `signing.local.json` 的 `expectedDeviceIds` 数组中记录目标设备 UDID，检查时会确认这些设备均已授权。需要本机 Python 的 `cryptography` 库；缺失时按命令提示安装。

`pgyer_hap` 上传前会执行发布签名检查，上传 HAP 后同步同一 P12 供蒲公英生成安装清单。任一步失败都不应宣布网页安装已修复。`check` 能校验签名和已配置的设备授权，实际安装结果仍需真机确认。

只读检查原有 HAP：

```powershell
python tool/ohos_distribution.py inspect --hap build/ohos/hap/entry-default-signed.hap
```

`signing.local.json` 含口令，P12 含私钥，均不得提交到 Git。申请证书时只上传 CSR 到华为；完成发布签名后，Fastlane 才把匹配的 P12 发送到蒲公英官方证书接口。

### 扫码安装验收与旧版冲突

USB 安装成功只能证明安装包能被设备安装，不能代替蒲公英扫码验收。扫码验收应使用蒲公英鸿蒙下载页的二维码，在华为浏览器中点击安装，并通过手机安装结果与日志确认下载、验签和安装均成功。

若出现 `10021`，先读取手机实际 UDID 并与包内 Profile 比对，同时核对 HAP、Profile 和蒲公英安装清单的签名。不要仅凭 AGC 设备名称认定授权正确。

若重试日志显示包校验成功，随后报 `17700073`（已有同包名但签名不同的应用），应检查手机是否还装着调试签名版。调试版与发布版的签名或应用标识不同会阻止覆盖安装；先备份记录和设置，确认后卸载旧版，再通过蒲公英下载安装。后续发布持续复用同一发布身份，避免再次产生签名冲突。

## 固定依赖与兼容处理

`pubspec_ohos.yaml` 中所有直接 Git 依赖都固定到提交；构建脚本生成 overrides，确保 federated 插件内部的分支引用不会覆盖这些选择。`pubspec_ohos.lock` 与主 `pubspec.lock` 均应随源码提交。更新依赖时重新构建并审阅对应锁文件差异。

脚本自动完成以下兼容步骤：

- 在隔离目录 `vendor/geolocator` 的副本中移除不适用于鸿蒙的 Web 导出；共享 pub 缓存保持原样。
- 将 SDK 的 flutter-hvigor-plugin 复制到隔离目录后处理旧 hvigor 开发依赖；SDK 源文件保持原样。
- 使用 DevEco 自带的 hvigor，通过隔离工程中的 junction 统一 CLI 与插件的物理实例，避免双实例冲突。
- 固定 `web: 0.5.1` 以兼容 Dart 3.4，并将工程副本中的 JSON5 等文件统一为 LF 换行。
- 分享 API 与 PopScope 的 Flutter 3.22 兼容用法保留在明确标注的边界；静态检查无需全局禁用弃用提示。

### 语音播报无法压低其他应用音量

`@ohos.multimedia.audio` 没有应用侧申请音频焦点的 API（焦点由系统按音频流用途在渲染时自动分配），CoreSpeechKit `SpeakParams` 也不暴露音频属性，TTS 引擎内部自行渲染音频。因此播报期间其他应用（如音乐）的音量无法由本应用主动压低，只能依赖系统对 TTS 流的焦点策略。Android 端通过 `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` 实现、iOS 端通过 `AVAudioSession.duckOthers` 实现压低音量；鸿蒙端在系统提供相应 API 前不做处理。

## 测试与设备验收

```powershell
python -m unittest discover -s tool/tests -v
python tool/ohos_build.py release --analyze
```

Python 测试覆盖构建失败不修改主依赖、删除路径边界、签名隔离，以及兼容补丁不修改 SDK/共享缓存。

EntryAbility 已声明 `backgroundModes: ["location"]`；申请 LOCATION 长时任务失败会返回 Dart 错误，并在跑步页显示后台状态提示。真机需验证授权、锁屏续记、长时任务提示、前后台切换、GPS 关闭/恢复、暂停分段、进程终止及草稿恢复。编译成功不表示这些系统行为已经通过设备验收。

### 跑步后里程和配速不更新

固定提交 `d234260` 的 `geolocator_ohos` 在未收到 `timeInterval` 时，将 `ContinuousLocationRequest.interval` 设为 `10000`；这个字段的单位是**秒**，不是毫秒，见[OpenHarmony 位置服务接口](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-location-kit/js-apis-geoLocationManager.md#continuouslocationrequest12)。通用 `LocationSettings` 不包含该字段，会导致持续定位间隔约为 2 小时 47 分钟。

`tracking_location_settings.dart` 为鸿蒙明确传入 `timeInterval: 1000` 毫秒，由插件换算为 1 秒，并设置 30 秒无位置回调超时。超时后跑步页显示定位异常，5 秒后重连；断开前后的坐标不会直接累计为里程。Android/iOS 的定位设置保持原有行为。

在“我的 → 诊断日志”检查 `GPS subscribe`（应包含 `timeInterval: 1000`）、`GPS first fix` 和 `GPS stream` 错误记录。首个有效位置到达后，户外以正常跑步速度移动 50–100 米，确认轨迹、公里数和配速持续变化；再验证暂停恢复、锁屏及前后台切换。精度超过 25 米的点仍被过滤，不应以室内测试结果代替户外验收。
