# iOS 构建与验收

工程位于 `app/ios/`，最低部署版本为 iOS 15。当前 Xcode 工程通过 `FlutterGeneratedPluginSwiftPackage` 集成 Flutter 插件；仓库没有 Podfile。Windows 无法完成 Xcode 构建，以下步骤需在 Mac 执行。

## 使用当前工程构建

安装与主工程一致的 Flutter 3.47.5 工具链，以及其支持的 Xcode 版本，然后执行：

```sh
cd app
flutter doctor -v
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --simulator --debug
open ios/Runner.xcworkspace
```

在 Xcode 的 Runner → Signing & Capabilities 中选择自己的 Team，检查 Bundle Identifier、证书和设备授权。确认 Background Modes 包含 Location updates。签名准备完成后：

```sh
flutter build ios --debug
flutter build ipa --release
```

IPA 位于 `build/ios/ipa/`。本次修复未在 Mac 执行以上构建，实际 Xcode/插件兼容性需以该环境的结果为准。

## Swift Package Manager 与 CocoaPods

先使用仓库现有的 Swift Package Manager 集成。`flutter pub get` 和 Flutter 的 iOS 构建步骤负责生成临时包引用，不需要预先执行 `pod install`。

如果插件明确要求回退 CocoaPods，应在独立分支或备份后处理：在该 Flutter SDK 通过 `flutter config --help` 确认 `--no-enable-swift-package-manager` 选项并关闭 SPM，使用 `flutter create --platforms=ios .` 生成匹配的工程/Podfile，再检查并恢复应用标识、权限文案、图标和签名配置，最后按生成的 Podfile 执行 `pod install`。不要无审阅覆盖平台文件。

## 定位配置与验收

- `Info.plist` 已包含定位授权文案和 `UIBackgroundModes: location`。
- `RunTracker` 在 iOS 使用 `AppleSettings`，启用 `allowBackgroundLocationUpdates`、后台位置指示器及 fitness 模式，并关闭自动暂停位置更新。
- 模拟器可用模拟路线检查界面与基本流程；真实定位精度、锁屏续记、权限变化和电量消耗必须真机验证。
- 对“使用期间”授权、精确位置关闭、权限撤销、锁屏、前后台切换、定位断开恢复逐项测试，确认后台指示器、距离、暂停分段及草稿恢复符合预期。
- 上架前依据最终依赖与实际数据使用核对归档中的隐私清单、用途文案和隐私申报；插件自带清单不等于应用已自动完成全部上架要求。
