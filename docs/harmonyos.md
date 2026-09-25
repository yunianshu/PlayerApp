# 鸿蒙（HarmonyOS）构建指南

跑迹 RunTrail 的鸿蒙端基于 OpenHarmony-SIG 的 Flutter fork（`3.22.0-ohos` 分支，Flutter 3.22 / Dart 3.4）。
应用代码 `lib/` 已验证与该版本完全兼容（`flutter analyze` 通过，仅 6 条 share_plus 弃用提示）。

**当前状态（2026-09）**：`bash tool/ohos_build.sh release` 已能完整编译出
`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`（未签名）。
剩下唯一一步是配置签名（见「签名与安装」），需要华为账号在 DevEco Studio 里授权。

## 已完成的工作

- `ohos/` 平台工程已生成并配置：包名 `com.runtrail.runtrail`、应用名「跑迹 RunTrail」、
  定位权限（LOCATION / APPROXIMATELY_LOCATION / LOCATION_IN_BACKGROUND / KEEP_BACKGROUND_RUNNING）、
  应用图标（`AppScope/resources/base/media/app_icon.png`、`entry/.../media/icon.png`）。
- `pubspec_ohos.yaml`：鸿蒙专用依赖清单（见下表），全部指向社区适配的 git 仓库；
  另有 `dependency_overrides: web: 0.5.1`（见下文兼容性）。
- `tool/ohos_build.sh`：一键构建脚本（自动切换 pubspec → 构建 → 还原），
  并强制 `PUB_CACHE` 与项目同盘（见下文「工具链适配」）。
- 引擎产物（ohos-arm64 / ohos-x64 的 debug/profile/release）已通过工具下载验证。

## 环境准备（一次性，本机已完成）

1. **鸿蒙 Flutter 工具链**：`D:\soft\ohos-flutter-3.22`（3.22.0-ohos 分支，
   需拉取上游 tag 使 `git describe` 可用，否则 pub 校验失败）。
2. **DevEco Studio 6.0.2**：`D:\soft\DevEco Studio`，自带
   - 完整 HarmonyOS 6.0.2 SDK（API 22）：`DevEco Studio\sdk\default`
   - hvigor 6.22.3：`DevEco Studio\tools\hvigor`
   - ohpm：`DevEco Studio\tools\ohpm\bin`
3. **Node.js 18+**（本机 v24）。
4. **hvigor 包 junction**：`D:\hvigor-node\@ohos\{hvigor,hvigor-ohos-plugin}` →
   DevEco 自带同名包（见「工具链适配」）。重建方法：
   ```bat
   mklink /J "D:\hvigor-node\@ohos\hvigor" "D:\soft\DevEco Studio\tools\hvigor\hvigor"
   mklink /J "D:\hvigor-node\@ohos\hvigor-ohos-plugin" "D:\soft\DevEco Studio\tools\hvigor\hvigor-ohos-plugin"
   ```

## 构建

```bash
cd app
bash tool/ohos_build.sh release    # 或 debug
```

脚本做的事：
1. 备份 `pubspec.yaml` / `pubspec.lock`，用 `pubspec_ohos.yaml` 替换
2. 设置 `PUB_CACHE=D:/AiProject/PlayerApp/.pub-cache-ohos`（与项目同盘）与 `DEVECO_SDK_HOME`
3. 鸿蒙工具链执行 `flutter pub get` + `flutter build hap`
4. 还原主 pubspec

产物：`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`
（配置签名后重新构建即为已签名包）

## 工具链适配（踩坑记录，重要）

本机 DevEco 6 的 SDK/hvigor 与 ohos-flutter 3.22 自带工具存在多处版本错位，
已用以下方案打通（均已在仓库/本机落地，勿回退）：

1. **hvigor 双实例问题**：ohos-flutter 自带的 `hvigorw.bat` 用 hvigor 5.2.2（只认
   API 12 旧布局 SDK），而本机完整 SDK 是 DevEco 6 自带的 API 22 布局 —— 5.2.2 的
   SDK 扫描器不认识 6.0.2（`osVersionMapper` 无映射），报 `SDK component missing`；
   DevEco 的 hvigor 6.22.3 又与其不配套。最终方案：`ohos/hvigorw.bat` 直接调用
   DevEco 自带 `hvigor.js`，并设 `NODE_PATH=D:\hvigor-node`（junction 到 DevEco 的
   `@ohos/hvigor` + `@ohos/hvigor-ohos-plugin` 物理目录）。
   **关键**：`hvigorw.bat` 每次先删除 `ohos/node_modules/@ohos`——npm/IDE 同步会把
   5.2.2 旧版塞回项目 node_modules，包路径一旦与 CLI 不同（即使同版本）就是两个
   模块实例，hvigor 报 `The root node is not yet available for build`。
2. **pub 缓存同盘**：`flutter-hvigor-plugin` 用 `path.relative` 把插件路径写成
   相对路径；项目在 D: 而默认 pub 缓存在 C:，跨盘符回退成绝对路径，hvigor 6 报
   `The srcPath is not a relative path`。构建脚本因此强制 `PUB_CACHE` 在 D:。
3. **web 包版本**：Dart 3.4（ohos fork）的 AOT 目标无法编译 web 1.x 的
   `implements JSObject` 扩展类型写法，`pubspec_ohos.yaml` 中
   `dependency_overrides: web: 0.5.1`（与 Flutter 3.22 同期）。
4. **geolocator 补丁**：geolocator v13 鸿蒙分支的 `lib/geolocator.dart` 无条件
   `export geolocator_web`（引入 package:web，鸿蒙 AOT 编译失败）。应用未用
   `WebSettings`，已在 pub 缓存副本中移除该导出（`.pub-cache-ohos/git/fluttertpc_geolocator-*/geolocator/lib/geolocator.dart`）。
   若 pub 缓存清空重拉，需要重新打这个补丁。
5. `flutter-hvigor-plugin`（SDK 内 `packages/flutter_tools/hvigor`）的
   `devDependencies.@ohos/hvigor: 5.2.2` 已移除，避免 npm 每次构建把它装进项目。
6. **`.flutter-plugins-dependencies` 被主工具链覆盖**：在 `app/` 下用标准 Flutter（或
   主 pubspec）跑一次 `flutter pub get`，该文件会被重写、丢失 `plugins.ohos` 段。
   之后再在 DevEco 里同步 `ohos/` 工程，`hvigorfile.ts` → `injectNativeModules` →
   `findFlutterPlugins` 对 `plugins.ohos`（此时为 undefined）调 `.filter`，
   报 `hvigor ERROR: 00305010 TypeError Cannot read properties of undefined
   (reading 'filter')`。修法：重跑一次鸿蒙侧 pub get 恢复清单
   （切 `pubspec_ohos.yaml` + `PUB_CACHE=D:/AiProject/PlayerApp/.pub-cache-ohos`，
   见 `tool/ohos_build.sh`），再同步即可。DevEco 打开鸿蒙工程期间，
   保持最后一次 pub get 是鸿蒙工具链执行的。

## 鸿蒙插件源对照表（pubspec_ohos.yaml 已配好）

| 插件 | 鸿蒙来源 |
|------|---------|
| geolocator | `gitcode.com/openharmony-sig/fluttertpc_geolocator.git` 分支 `br_geolocator_v13.0.0_ohos` |
| flutter_geolocator_ohos | 同上仓库，path `geolocator_ohos`（geolocator 的 ohos 实现包，**必须显式依赖**，否则 ohos 端无 GPS 原生模块） |
| sqflite | `gitcode.com/openharmony-sig/flutter_sqflite.git` path `sqflite` |
| path_provider | `gitcode.com/openharmony-sig/flutter_packages.git`（ref master）path `packages/path_provider/path_provider` |
| shared_preferences | 同上，path `packages/shared_preferences/shared_preferences` |
| share_plus | `gitcode.com/openharmony-sig/flutter_plus_plugins.git` path `packages/share_plus/share_plus` |
| wakelock_plus | `gitcode.com/openharmony-sig/fluttertpc_wakelock_plus.git` 分支 `br_wakelock_plus_1.2.8_ohos`（3.22 对应分支）path `wakelock_plus` |
| wakelock_plus_ohos | 同上仓库，path `wakelock_plus/ohos`（防息屏 ohos 实现包，同上必须显式依赖） |

> - geolocator 的 `br_v14.x_ohos` 分支要求 Dart ≥3.5，与 3.22 工具链不匹配，故用 v13。
> - OpenHarmony-SIG 约定：主包 pubspec 不声明 `platforms.ohos` 时（geolocator / wakelock_plus 即如此），
>   需在应用里显式依赖对应 `*_ohos` 实现包，pub 才会把原生模块写进 `plugins.ohos`。
>   验证方法：`.flutter-plugins-dependencies` 的 `plugins.ohos` 应含
>   `flutter_geolocator_ohos` / `wakelock_plus_ohos` 等 6 项。

## 代码兼容性说明

`lib/` 与 Flutter 3.22 的兼容点（已处理）：

- `Color.withValues()` 是 Flutter 3.27+ API → 已统一换成 `theme.dart` 的 `scaleAlpha()`
- 分享用 `Share.share()` 静态 API（share_plus v7 鸿蒙版支持）
- 其余语法（records / patterns / switch 表达式）Dart 3.4 均支持
- 字体已在 `pubspec_ohos.yaml` 声明（Playfair Display / Noto Sans SC / Inter /
  Barlow Condensed），三套主题的数字字体在鸿蒙端可正常渲染

## 签名与安装（唯一剩余步骤，需华为账号）

当前产物为**未签名** hap，真机安装需要调试签名：

1. 用 DevEco Studio 打开 `app/ohos` 工程
2. File → Project Structure → Signing Configs → 勾选 **Automatically generate signature**
   （需登录华为账号；DevEco 会生成调试证书并写入 `build-profile.json5` 的
   `signingConfigs`）
3. 之后运行 `bash tool/ohos_build.sh debug`（或 release）即可得到**已签名** hap；
   或直接在 DevEco 里 Run
4. 命令行安装：`hdc install entry-default-signed.hap`
   （hdc 在 `hos-sdk-placeholder\12\toolchains\` 或 DevEco SDK `default\openharmony\toolchains\`）

## DevEco 同步与命令行的缓存统一（2026-09-25）

DevEco Studio 同步时用自己的环境跑 `flutter pub get`，默认 pub 缓存在 **C 盘**，而命令行构建用
`PUB_CACHE=D:\AiProject\PlayerApp\.pub-cache-ohos`——两边交替运行会把
`.flutter-plugins-dependencies` / `.dart_tool/package_config.json` 的插件路径在 C:/D 盘之间来回改写，
C 盘路径跨盘符无法转相对路径 → hvigor 报 `The srcPath is not a relative path`。

**永久修复**：已 `setx PUB_CACHE D:\AiProject\PlayerApp\.pub-cache-ohos`（Windows 用户级环境变量）。
**改完必须重启 DevEco Studio 才生效**；改前已启动的进程仍用旧环境。

## JSON5 换行符陷阱（2026-09-25）

ohos-flutter 的 JSON5 解析器不接受 CR 字符（CRLF 换行）。DevEco Studio 保存配置时会把
`build-profile.json5`、`oh-package.json5`、`module.json5` 等写成 CRLF，导致
`flutter pub get` / DevEco 同步报 `Parse ohos module.json5 error: JSON5: invalid character`。
注意报错文案会张冠李戴——`build-profile.json5` 的解析错误也报成 module.json5。

修法：把 ohos 工程及 pub 缓存里所有 .json5/.json 的 CR 字节删掉（
 归一为 
），
可参考如下思路（os.walk 遍历 + 二进制替换，跳过 node_modules/build/.hvigor）。
pub 缓存里的插件 module.json5 同理（git autocrlf=true 检出时会转 CRLF）。
另：DevEco 保存与脚本批处理并发写同一文件可能造成文件截断损坏
（build-profile.json5 曾被写坏成 storeFile 半行），损坏时按仓库里的模板手工重建。

## ArkTS 兼容要点

- Kit 名是 `@kit.BackgroundTasksKit`（复数，没有 BackgroundTaskKit）
- 长时任务模式枚举是 `backgroundTaskManager.BackgroundMode.LOCATION`（无 TaskType）
- ArkTS 严格模式：私有方法要显式 `: void` 返回类型；`.then()` 回调加返回类型注解
- Flutter 侧 `PopScope` 用 `onPopInvoked`（3.22 fork 无 onPopInvokedWithResult；主线已弃用但保留）

## 已知边界

- DevEco Studio 打开工程时会按 modelVersion 5.0.0 往 `ohos/package.json` 同步写入
  `@ohos/hvigor: 5.2.2` 依赖——`hvigorw.bat` 已在构建前自动清理，无需手动处理。
- `.pub-cache-ohos` 中的 geolocator 补丁在缓存重建后会丢失（见「工具链适配」第 4 条）。
