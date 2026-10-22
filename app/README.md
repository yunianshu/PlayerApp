# 跑迹 RunTrail

Flutter 本地跑步记录应用，支持 Android、iOS 和 HarmonyOS。记录 GPS 轨迹、距离、配速、时长和爬升，提供历史记录、统计、目标、分享与多套主题；数据保存在设备本地。

第二期新增：语音播报（TTS）、低速自动暂停、手动补录（跑步机）、目标配速提醒、GPX 导出、JSON 备份/恢复、记录标题与备注、16 枚成就徽章与连续打卡、个人纪录（最快 1/5/10 km）、月度对比、轨迹抽稀绘制、分享成绩海报、中英双语、诊断日志。实现细节见 [第二期记录](../docs/roadmap-2026-09-30.md)。

## 开发与验证

标准工具链：Flutter 3.47.5 / Dart 3.13.4。以下命令在 `app/` 执行：

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter run
```

应用依赖锁文件 `pubspec.lock` 与鸿蒙专用 `pubspec_ohos.lock` 均应纳入版本管理。普通开发使用主 `pubspec.yaml`；鸿蒙脚本会在隔离目录使用另一套依赖，不需要手动切换文件。

## 平台构建

- Android：`flutter build apk --debug`；release 使用 `flutter build apk --release`，签名读取本机 `android/key.properties`（`storeFile`、`storePassword`、`keyAlias`、`keyPassword`）。证书和口令文件不要提交。产物在 `build/app/outputs/flutter-apk/`。
- iOS：需要 macOS、Xcode 和有效签名，工程使用 Swift Package Manager，参见 [iOS 指南](../docs/ios.md)。
- HarmonyOS：独立的 Flutter 3.22 / Dart 3.4 工具链、DevEco Studio、Node.js 和 Python 3.10+；配置路径后执行 `python tool/ohos_build.py release --analyze`，参见 [鸿蒙指南](../docs/harmonyos.md)。产物在 `build/ohos/hap/`。

鸿蒙脚本测试：`python -m unittest discover -s tool/tests -v`。

## 数据可靠性

- 暂停、定位中断后恢复会建立新轨迹段；暂停期间的位移与用时不计入跑步。低速自动暂停（默认关闭）触发时保持定位流，恢复移动自动续跑并新建分段。
- 有效轨迹每 15 秒保存一次恢复草稿，暂停与结束时另存快照；结束后直到保存成功或明确放弃才清理。
- 草稿通过串行队列和临时文件替换写入。数据库使用会话 ID 避免重复保存；v1/v2 数据库自动迁移到 v3（新增记录来源、标题、备注列），保留历史记录。备份恢复按会话 ID 幂等。
- 未处理的恢复记录会显示在首页；先保存或放弃它，再开始新跑步。存储、后台服务和定位异常会在界面反馈。未捕获异常写入本地诊断日志（我的页可查看），无网络上报。

## 回归与设备验收

正式回归测试位于 `test/`，涵盖定位状态、暂停/恢复与自动暂停、实时和分段配速、目标配速判定、草稿持久化、旧库迁移（v1→v2→v3）、幂等保存、目标输入、日历边界、徽章与打卡、GPX/备份往返、轨迹抽稀、个人纪录滑窗、双语字典、页面重试及小屏布局。审计与修复对应关系见 [修复记录](../docs/project-fixes-2026-09-27.md)，第二期实现与验收边界见 [第二期记录](../docs/roadmap-2026-09-30.md)。

单元测试和构建不能替代真机验收。发布前在各平台覆盖锁屏续记、切换前后台、定位关闭/恢复、精度不足、撤销权限，以及进程终止后的草稿恢复；第二期另需覆盖语音播报、自动暂停、手动补录、GPX/备份恢复与语言切换（清单见第二期记录）。iOS 还需在 Mac 完成构建验证；CI（`.github/workflows/ci.yml`）在每次推送时自动执行分析与测试。
