# 三主题启动动画

启动过场现在由 Flutter 矢量绘制，不再播放固定白底的 `assets/splash.mp4`。保留原有约两秒的品牌顺序：路径图标、轨迹划入和简笔跑者、跑迹 / RunTrail 字标、淡出进入首页。

## 主题来源

- `main` 在首帧前恢复 `ThemeController` 的保存选择，过场和首页直接共用 `AppPalette`。
- 白天使用原有雾白、靛紫与薄荷青；夜间使用炭黑与珊瑚橙；编辑风使用米纸、墨色与荧光绿。没有修改现有主题色。
- 编辑风文字保持墨色，荧光绿用于轨迹和图形，避免低对比度正文。
- `StartupAnimationFrame` 是实际过场和预览截帧的共同实现，预览不是另外制作的效果图。

## 启动与中断行为

- 动画不依赖视频解码、平台视频控制器或外部资产下载，因而没有等待视频的白色占位层。
- 首页在固定子树中预热，动画移除后不重新创建首页。过场期间阻断隐藏按钮的点击、焦点和语义。
- 系统启用“减少动态效果”时直接显示首页。进入后台后结束过场，回到前台不重播。
- 父节点重建或切换主题不会重播；切换主题时当前帧使用新调色板。
- 动画正常时长为 2 秒，计时兜底为 2.6 秒。偏好读取失败、格式损坏或超过 2 秒无响应时保留自动主题，启动不会无限等待。

## 原生启动窗口的边界

Android、iOS 与 HarmonyOS 在 Flutter 绘制之前的系统启动窗口不读取 Dart 的已保存主题。其底色现在按系统浅色 / 深色资源分别使用 `#EDEFF8` / `#101014`，不再无条件白底。

如果用户手动选择的主题与系统外观不同，或选择编辑风，系统窗口与 Flutter 首帧之间仍可能有一次颜色切换。这不应描述为“所有平台最早一帧都跟随应用内设置”。Android 12 及以上还可能显示系统强制的启动图标。需要各平台真机冷启动验收，单元测试和资源解析不能证明系统启动窗口的真实表现。

## 回归与预览

在 `app/` 执行：

```sh
flutter analyze --no-pub
flutter test --no-pub test/startup_animation_test.dart
flutter test --no-pub --dart-define=STARTUP_PREVIEWS=true test/startup_animation_test.dart --plain-name 'export actual Flutter startup previews'
```

最后一条会在 `app/build/startup-previews/{light,dark,editorial}/` 输出各 60 张 Flutter 实际画面，可按每秒 30 帧组合成视频。生成物不纳入版本库。

测试覆盖保存选择与重新加载、缺失 / 非法 / 损坏 / 失败 / 超时偏好、首帧颜色、禁止误触、首页不重建、减少动态效果、背景返回、提前卸载、小屏与横屏。原生资源仅做 XML / JSON 结构验证，未替代 Android、iOS 或 HarmonyOS 构建及真机验证。
