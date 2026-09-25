# iOS 构建指南

iOS 工程（`app/ios/`）已完成全部可配置项，因 iOS 编译强制要求 macOS + Xcode，
需在 Mac 上执行最终构建。本机（Windows）无法产出 .ipa，这是平台限制，不是项目缺陷。

## 已完成的配置

- `Info.plist`：
  - `CFBundleDisplayName` = 跑迹 RunTrail
  - `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription`
    / `NSLocationAlwaysUsageDescription`（定位权限文案）
  - `NSMotionUsageDescription`（运动传感器）
  - `UIBackgroundModes` 包含 `location`（跑步中后台持续定位）
- 应用图标：`ios/Runner/Assets.xcassets/AppIcon.appiconset/` 已由
  flutter_launcher_icons 生成全套（21 张 PNG + Contents.json），使用设计稿导出的
  1024×1024 主图标（靛蓝→青渐变 + 白色轨迹标记，无透明通道，符合 App Store 要求）。
- 代码无平台特定 API：geolocator / sqflite / share_plus / wakelock_plus /
  path_provider / shared_preferences 均原生支持 iOS。

## 在 macOS 上构建

```bash
# 1. 安装 Flutter（与主工程同版本），然后：
cd app
flutter pub get

# 2. 首次需安装 CocoaPods 依赖
cd ios && pod install --repo-update && cd ..

# 3. 打开 Xcode 配置签名
open ios/Runner.xcworkspace
#    Signing & Capabilities → 选择 Team（个人开发者账号即可真机调试）

# 4. 构建
flutter build ios --debug          # 模拟器/真机调试
flutter build ipa                  # 发布包（Archive，需有效签名）

# 5. 跑测试
flutter test
```

## 真机调试注意事项

- iOS 模拟器**没有 GPS 硬件**，跑步轨迹需用模拟器的
  Features → Location → City Run / Freeway Drive 模拟，或真机测试。
- 后台定位（锁屏继续记录）需要 Signing 里勾选 Background Modes → Location updates
  （Info.plist 已声明，Xcode 勾选后会自动写入 entitlements）。
- App Store 审核需要隐私清单（Privacy Manifest）：所用插件近期版本均已自带
  （geolocator 13+/shared_preferences 2.3+/sqflite 2.3.3+），无需额外处理。
