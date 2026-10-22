**RunTrail 项目审计报告 · 2026-09-27**

> 本文保留修复前的审计快照，问题描述、行号和失败复现结果对应基线，不代表当前代码。后续修复及验证结果见 [修复记录](project-fixes-2026-09-27.md)。正式回归已迁移到 `app/test/`；下方 `.dart_tool` 脚本只作为历史复现证据保留。

审计对象：D:\AiProject\PlayerApp 当前工作区，基线提交 `4189552`，包含用户已有的 TrackingForegroundService.kt 修改。本次未修改业务代码、原有测试或用户的 pubspec.lock。

本次定位到 **30 项问题：8 项 P1、18 项 P2、4 项 P3**。其中 **18 项通过新增定向测试复现，1 项通过隔离构建脚本复现**；其余根据代码、已安装依赖实现和官方文档确认。优先级含义：P1 影响核心记录、数据完整性或后台续记；P2 影响计算、交互和可靠性；P3 为较低影响的显示、输入和工程维护问题。这不是“已证明不存在其他问题”的结论。

**验证结果与边界**

| 检查 | 结果 |
| --- | --- |
| 工具链 | Flutter 3.47.5 / Dart 3.13.4 / Windows |
| 原有 `flutter test --no-pub --reporter expanded` | 21 项全部通过 |
| `flutter analyze --no-pub` | 无 error/warning；12 条 info，命令退出码 1 |
| `flutter build apk --debug --no-pub` | 成功 |
| `flutter build apk --release --no-pub` | 成功，APK 约 51.5 MB |
| 新增审计复现 | A01–A13、B01–B04、C01 共 18 项，均因目标缺陷触发预期行为断言失败 |
| 鸿蒙构建脚本异常退出 | 在隔离副本使用失败的工具桩复现锁文件未恢复 |
| Android / 鸿蒙设备 | adb、hdc 均未发现连接设备 |
| iOS | Windows 无法执行 Xcode 构建；已检查工程、插件源码与后台配置 |
| 鸿蒙 | 已检查 ArkTS、manifest、构建脚本和依赖；未执行会切换主 pubspec 的完整构建 |

新增复现脚本和日志位于被 Git 忽略的 `app/.dart_tool/`，不会混入原有测试目录。它们断言“应有行为”，因此当前版本运行失败是缺陷证据，不代表原有 21 项测试失败：

- [定位、计算、草稿复现脚本](../app/.dart_tool/audit_regression_test.dart)，[日志](../app/.dart_tool/audit-regressions.log)
- [页面交互复现脚本](../app/.dart_tool/audit_ui_test.dart)，[日志](../app/.dart_tool/audit-ui.log)
- [数据库复现脚本](../app/.dart_tool/audit_database_test.dart)，[日志](../app/.dart_tool/audit-database.log)

在 `app` 目录可分别执行：
```powershell
D:\soft\flutter\bin\flutter.bat test --no-pub .dart_tool\audit_regression_test.dart --reporter expanded
D:\soft\flutter\bin\flutter.bat test --no-pub .dart_tool\audit_ui_test.dart --reporter expanded
D:\soft\flutter\bin\flutter.bat test --no-pub .dart_tool\audit_database_test.dart --reporter expanded
```

**P1：优先修复的 8 项**

**01. 首次 GPS 定位前暂停会抛异常。**  
位置：[run_tracker.dart:248](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:248)、[run_tracker.dart:225](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:225)。  
开始后尚未收到有效定位点时，`pause()` 无条件调用 `_snapshotDraft()`，后者读取空列表 `points.first`。状态已改为 paused，但异常发生在 `notifyListeners()` 之前，界面可能仍显示运行中。A01 实测：`StateError: Bad state: No element`。应只在有有效点时保存草稿，并保证状态通知不会被草稿生成打断。

**02. 暂停期间的位移和时间被计入恢复后的跑步。**  
位置：[run_tracker.dart:252](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:252)、[run_tracker.dart:171](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:171)。  
恢复时保留暂停前的 `_lastPoint`，下一点直接与其计算距离和时间差。A02：跑 50 米后暂停 60 秒，暂停时移动 300 米，恢复首点后距离变为 350 米；`movingMs` 同样包含暂停间隔，而 `elapsed` 已扣暂停，数据口径冲突。保存模型也没有暂停/轨迹分段标记，详情分段配速会把暂停时间算进去。应记录轨迹段边界及运动时间，恢复首点只建立新段起点。

**03. 跑步中新增轨迹点不会触发路线重绘。**  
位置：[route_painter.dart:107](D:/AiProject/PlayerApp/app/lib/widgets/route_painter.dart:107)、[running_page.dart:102](D:/AiProject/PlayerApp/app/lib/pages/running_page.dart:102)。  
新旧 painter 持有同一个原地增长的 List，因此比较两者长度时长度永远相等。A05 实测：同一列表新增点后 `shouldRepaint` 仍返回 false。结合 RepaintBoundary，路线可一直停在旧画面，直到其他原因强制重绘。应在 painter 构造时保存版本/点数快照，或传入不可变列表。

**04. iOS 实际未启用后台位置更新开关。**  
位置：[run_tracker.dart:142](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:142)、[background_service.dart:3](D:/AiProject/PlayerApp/app/lib/services/background_service.dart:3)。  
当前只传通用 `LocationSettings`，序列化不包含 `allowBackgroundLocationUpdates`。本机 geolocator_apple 2.3.14 的 `PositionStreamHandler.m` 直接读取该键，缺失时转换为 false，再交给 CLLocationManager。Info.plist 声明 location 并不等同于打开这个运行时开关。应在 iOS 使用 `AppleSettings(allowBackgroundLocationUpdates: true, ...)`，然后真机锁屏验证。[Apple 官方说明](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)。此处确认的是配置缺陷，尚未在 iPhone 测量具体中断表现。

**05. 鸿蒙申请定位长时任务缺少必需模式声明，且失败被伪装为成功。**  
位置：[module.json5:14](D:/AiProject/PlayerApp/app/ohos/entry/src/main/module.json5:14)、[EntryAbility.ets:41](D:/AiProject/PlayerApp/app/ohos/entry/src/main/ets/entryability/EntryAbility.ets:41)。  
EntryAbility 未声明 `backgroundModes: ["location"]`，代码却申请 LOCATION 长时任务；catch 又执行 `result.success(null)`，Dart 无从知道后台保活失败。应补齐模式声明、返回可识别错误，并向界面反馈保活状态。[OpenHarmony 官方长时任务指南](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/task-management/continuous-task.md)。尚未进行鸿蒙真机续记验证。

**06. 结束跑步时提前删除草稿，保存前退出会丢整次记录。**  
位置：[run_tracker.dart:300](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:300)、[summary_page.dart:51](D:/AiProject/PlayerApp/app/lib/pages/summary_page.dart:51)。  
`stop()` 已清除草稿，真正的数据库插入要等用户在总结页点击保存。总结页停留期间进程被杀、系统回收，或保存持续失败，均无可恢复副本。A08：结束前草稿存在，stop 后数据库尚未保存，草稿已变成 null。应在数据库事务成功或明确放弃后删除，并在结束时保存最终快照。

**07. 开始新跑步会静默删除尚未处理的恢复草稿。**  
位置：[run_tracker.dart:131](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:131)、[home_page.dart:78](D:/AiProject/PlayerApp/app/lib/pages/home_page.dart:78)。  
首页展示恢复卡时仍可直接开始新跑步，而 start 无条件清掉旧草稿，没有“先恢复/放弃”的约束。A12 已复现。首页还缓存 `_draft`，该删除不发送 AppData 通知，可能继续展示过时恢复卡。应在新跑步入口处理旧草稿，或按独立会话存储草稿。

**08. 保存缺少进行中保护，会插入重复记录。**  
位置：[summary_page.dart:51](D:/AiProject/PlayerApp/app/lib/pages/summary_page.dart:51)、[home_page.dart:78](D:/AiProject/PlayerApp/app/lib/pages/home_page.dart:78)。  
`_saved` 只在插入结束后置 true；插入期间可重复触发。恢复草稿保存也没有互斥或数据库幂等标识。B03 对同一保存回调连续触发两次，数据库实际产生两条记录，累计统计翻倍。应在 await 前设置 saving 状态，并以会话 ID 保证插入幂等。

**P2：计算、交互和可靠性问题 18 项**

**09. 实时配速的距离和时间窗口不对应。**  
位置：[run_tracker.dart:79](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:79)。  
距离包含窗口内第一个完整段，时间却从该段的终点开始计，漏算一段用时。A03 输入每 10 秒 50 米：正确值 200 秒/公里，实际 133.33 秒/公里。应同时保存段起止时间，按同一窗口计算距离和时长。

**10. 停下后实时配速不会过期。**  
位置：[run_tracker.dart:81](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:81)。  
窗口以最后一段时间为“现在”，没有使用当前时钟；无新段时旧窗口永久有效。A04 停止移动 60 秒后仍显示原来的 133.33 秒/公里。应按当前时间淘汰过期段，静止或无有效窗口时显示无配速。

**11. 每公里分段丢弃跨界余量，也不插值公里边界。**  
位置：[summary_page.dart:20](D:/AiProject/PlayerApp/app/lib/pages/summary_page.dart:20)。  
达到 1000 米就 `seg = 0`，超出的米数和对应时间全部丢弃；一个段跨多个公里时也只生成一个分段。A06 用 5 段 600.1 米组成 3000.5 米路线，只得到两个公里分段。应保留余量，并对边界时间插值。

**12. 草稿写入/删除存在竞态，落盘也不是原子替换。**  
位置：[run_draft.dart:70](D:/AiProject/PlayerApp/app/lib/services/run_draft.dart:70)、[run_draft.dart:92](D:/AiProject/PlayerApp/app/lib/services/run_draft.dart:92)。  
定位回调、pause、stop 发起的 save/clear 未串行化。A13 将先发起的 save 延迟到 clear 之后完成，已清除的草稿重新出现，导致已保存或已放弃记录再次被恢复。直接覆盖同一个 JSON 文件，在进程中止时也可能留下截断文件，而 load 会静默丢弃。应按会话串行操作并采用临时文件原子替换。

**13. 定位流停止后缺少自动恢复机制。**  
位置：[run_tracker.dart:140](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:140)。  
onError 只设标志，没有重订阅、服务状态监听或恢复入口，onDone 也未处理。已检查安装版本 geolocator_android 的 LocationManagerClient：关闭提供器时会 removeUpdates；重新打开后应用并未重新申请定位。系统定位中途关闭/恢复后，可能一直计时却不记轨迹，直到用户手动暂停再恢复。应监听服务恢复并安全重建流。具体设备/定位提供器行为仍需真机覆盖。

**14. 无效精度的位置仍显示“GPS 记录中”。**  
位置：[run_tracker.dart:155](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:155)。  
更新 `_lastFixAt` 和清理错误标志发生在精度过滤之前。A09 输入精度 500 米的位置：points 为空，但 hasFix 为 true。用户只给大致位置时尤其容易出现一直显示记录中、最终距离为零。应区分接收到定位与获得可用定位，并在精度不足时给出明确状态和权限引导。

**15. 缓坡爬升被完全忽略。**  
位置：[run_tracker.dart:187](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:187)。  
每一段必须比上一点高超过 1 米才累加，但上一点每段都会更新。A11 连续 10 段各上升 0.5 米，真实累计 5 米，实际 climbM 为 0。算法同时直接累加较大的正向海拔噪声。应使用平滑/海拔精度和累计滞回阈值，保留缓慢上升。

**16. 倒计时数字实际按 1→2→3 变化。**  
位置：[countdown_page.dart:40](D:/AiProject/PlayerApp/app/lib/pages/countdown_page.dart:40)。  
controller 从 0 增至 1，而 `ceil(value * 3)` 从 1 增到 3；初始 3 只短暂出现。A07 在 100 毫秒时已出现数字 1。应按剩余时间计算，并与完成回调统一边界。

**17. 开始操作可并发，状态检查不能阻止重复启动。**  
位置：[run_tracker.dart:113](D:/AiProject/PlayerApp/app/lib/services/run_tracker.dart:113)、[main.dart:117](D:/AiProject/PlayerApp/app/lib/main.dart:117)。  
idle 检查在权限与服务查询的 await 之前，没有 starting 状态或互斥；首页按钮也没有忙碌保护。A10 同时调用两次 start，两个都返回 true。界面快速触发还可能重复推入倒计时页面。应在异步操作前锁定流程，并在失败时释放。

**18. 多个按钮在调试模式下触发 Provider 断言。**  
位置：[theme.dart:210](D:/AiProject/PlayerApp/app/lib/core/theme.dart:210)、[profile_page.dart:236](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:236)、[running_page.dart:330](D:/AiProject/PlayerApp/app/lib/pages/running_page.dart:330)。  
`context.colors` 封装的是 `context.select`，却在结束跑步、删除记录、放弃总结、编辑目标、切换主题、关于等事件回调中调用。B01 实际点击“关于跑迹”，得到 `Tried to use context.select outside of the build method`。该断言属于 debug/test，不据此声称 release 必然崩溃。应在事件回调使用 `context.read<ThemeController>()` 读取，监听只放在 build 中。

**19. 年度目标使用所有年份的累计里程。**  
位置：[profile_page.dart:280](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:280)。  
传给年度卡的是 totals 的全历史 totalKm，没有筛选年份。B02：去年 100 公里，今年 10 公里，年度进度显示 110 公里。应按当前自然年求和，并在跨年后刷新。

**20. 半马成就的阈值和统计口径错误。**  
位置：[profile_page.dart:487](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:487)。  
`半马挑战` 使用累计里程 `km >= 210.975`，既把 21.0975 公里扩大了 10 倍，也不是检查单次跑步。一次完成半马不解锁，多次短跑累计超过 210.975 公里却解锁。应以单次记录达到半马距离判定；若产品本意是累计成就，需要改名和阈值说明。

**21. 数据库首次打开失败会永久缓存失败 Future。**  
位置：[database.dart:24](D:/AiProject/PlayerApp/app/lib/data/database.dart:24)。  
`_opening` 只在成功的 then 中清空，失败时后续 db 请求始终返回同一个失败 Future。C01 先用无效父目录制造打开失败，修复路径并验证新实例能打开后，原实例仍返回原失败对象。应在失败时清理打开状态，使用户重试能够重新连接。

**22. 数据读取失败没有错误状态和重试入口。**  
位置：[home_page.dart:53](D:/AiProject/PlayerApp/app/lib/pages/home_page.dart:53)、[history_page.dart:39](D:/AiProject/PlayerApp/app/lib/pages/history_page.dart:39)、[stats_page.dart:37](D:/AiProject/PlayerApp/app/lib/pages/stats_page.dart:37)、[detail_page.dart:35](D:/AiProject/PlayerApp/app/lib/pages/detail_page.dart:35)。  
这些异步加载没有捕获数据库读取异常，也未在失败后结束 loading。读取失败时出现未处理异步异常、持续转圈或不完整页面。与第 21 项不同，即使数据库可恢复，用户也没有显式重试操作。应提供 loading/error/data 状态及重试按钮。

**23. 跨周后首页仍显示旧周的缓存统计。**  
位置：[home_page.dart:32](D:/AiProject/PlayerApp/app/lib/pages/home_page.dart:32)、[main.dart:298](D:/AiProject/PlayerApp/app/lib/main.dart:298)。  
首页只在 initState 和 AppData.bump 时 load，标签页保持存活，没有日期边界或应用恢复前台的刷新。周日打开、后台保留到周一后返回，本周里程和柱图仍是上一周；切换标签通常也不会重新查库。应在恢复前台时比较日期/周边界并刷新。

**24. 小屏幕底部导航确定溢出。**  
位置：[main.dart:220](D:/AiProject/PlayerApp/app/lib/main.dart:220)、[main.dart:253](D:/AiProject/PlayerApp/app/lib/main.dart:248)。  
4 个标签各固定 52 像素，加 58 像素开始按钮、左右 padding/margin 和边框，总宽度超过 320 逻辑像素。B04 测到导航 Row 向右溢出 16 像素。其他文本行也在无真实字体的 widget 测试中溢出，但这里只将不依赖字体的导航宽度作为确认依据。应使用弹性布局并覆盖小屏/大字号。

**25. 鸿蒙构建失败后没有恢复主依赖锁文件。**  
位置：[ohos_build.sh:25](D:/AiProject/PlayerApp/app/tool/ohos_build.sh:25)、[ohos_build.sh:28](D:/AiProject/PlayerApp/app/tool/ohos_build.sh:28)。  
脚本先把主 lock 移到 .bak，但 EXIT trap 只恢复 yaml，并删除一个流程中没有生成的 `pubspec.lock.ohos`。pub get/build 任一步失败，主 lock 留在 .bak，当前 lock 缺失或仍是鸿蒙版本。在隔离副本使工具失败后实测：yaml 恢复=true，lock 恢复=false，遗留 .bak=true。应让统一 cleanup 无论成功失败均恢复两个文件，并处理原本无 lock 的情况。

**26. 鸿蒙构建依赖仓库之外的手工补丁及特定机器路径。**  
位置：[hvigorw.bat:7](D:/AiProject/PlayerApp/app/ohos/hvigorw.bat:7)、[ohos_build.sh:18](D:/AiProject/PlayerApp/app/tool/ohos_build.sh:18)、[harmonyos.md:73](D:/AiProject/PlayerApp/docs/harmonyos.md:73)、[build-profile.json5:1](D:/AiProject/PlayerApp/app/ohos/build-profile.json5:1)。  
脚本硬编码 D 盘的 DevEco/hvigor 路径，签名配置指向本机用户证书；同时需要手动修改 pub 缓存的 geolocator 导出及 SDK 内 hvigor 依赖。缓存重建、SDK 重装或换电脑后，单靠仓库脚本无法复现当前构建。应参数化路径、把补丁纳入可重复执行且可校验的准备步骤，并隔离个人签名配置。本报告不输出任何签名口令内容，也未认定这些字段一定是可用明文凭据。

**P3：显示、输入和工程维护问题 4 项**

**27. 完成年度目标后仍显示“还差”。**  
位置：[profile_page.dart:466](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:466)。  
剩余公里数使用绝对值：目标 500、完成 600，会显示“还差 100.0 公里”。应取 max(目标-已完成, 0)，或显示已超额完成。

**28. 目标输入的校验和展示不一致。**  
位置：[profile_page.dart:103](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:103)、[profile_page.dart:143](D:/AiProject/PlayerApp/app/lib/pages/profile_page.dart:143)。  
键盘允许小数、存储也保存 double，但编辑初始值和标签用 toStringAsFixed(0)，再次打开保存会悄悄改变已有小数目标；提示要求 1–1000，实际允许 0 到 1 之间的值；`double.tryParse('NaN')` 返回 NaN，现有大小比较不能拒绝它；不可解析文本又被当作取消静默处理。应统一整数/小数规则，校验 isFinite，保留有效精度，并在对话框内提示无效输入。

**29. 应用依赖缺少可提交的稳定锁定策略，ignore 规则也写错层级。**  
位置：[app/.gitignore:61](D:/AiProject/PlayerApp/app/.gitignore:61)、[pubspec_ohos.yaml:46](D:/AiProject/PlayerApp/app/pubspec_ohos.yaml:46)。  
app/.gitignore 中的 `app/pubspec.lock` 实际匹配 app/app/pubspec.lock，当前主 lock 因此仍显示未跟踪。主 lock 未入库，鸿蒙多个 Git 依赖指向 master/移动分支或省略 ref，构建又反复生成 lock，同一源码在不同时间解析到的版本可能不同。应采用分别保存两套 lock 或隔离构建目录的方案，Git 依赖锁定提交；同时修正与实际策略相符的 ignore 路径。

**30. 构建文档与工程现状不符。**  
位置：[ios.md:28](D:/AiProject/PlayerApp/docs/ios.md:28)、[harmonyos.md:118](D:/AiProject/PlayerApp/docs/harmonyos.md:118)、[README.md:1](D:/AiProject/PlayerApp/app/README.md:1)。  
iOS 指导直接执行 pod install，但仓库没有 Podfile，Xcode 工程已经使用 FlutterGeneratedPluginSwiftPackage；应说明当前 Swift Package Manager 流程，以及确有 CocoaPods 回退需要时的生成步骤。鸿蒙文档仍写“唯一剩余步骤是签名”，而工程已有 default 签名配置，且本文发现了后台声明等未完成项。主 README 还是模板，缺少双工具链、测试和签名准备说明。应据实际验证状态更新文档；iOS 具体构建流程仍需在 Mac 上最终核对。

**还需补齐的验证与工程检查**

- 原有 `run_tracker_test.dart` 实际只测 RunMath，没有实例化 RunTracker；原有分段测试只覆盖接近整公里的点，所以无法发现这次的定位状态和余量问题。应将修复后的审计用例转成正式回归测试，并加入插件流、保存/恢复和生命周期测试。
- 12 条分析信息包括 6 条 Share API 弃用、1 条 onPopInvoked 弃用、5 条多下划线命名提示。当前分析命令退出码非零；但部分旧 API 是兼容鸿蒙 Flutter 3.22 的选择，不能直接全部替换成新 API 而不验证鸿蒙兼容。
- Android/iOS/鸿蒙需要真机验证：前后台切换、锁屏、GPS 关闭再打开、仅大致位置权限、权限撤销、暂停后恢复、进程回收与草稿恢复。
- 夏令时地区需要补日期分桶测试：weeklyKm 仍使用本地 DateTime 的 Duration/inDays，不保证等同于自然日边界；本机为 Asia/Shanghai，未把此项计入已复现问题。
- 草稿保存目前由定位回调触发，ticker 只刷新界面；长时间无 GPS 或精度不合格时，草稿中的 elapsedMs 会长期不更新，恢复时长会落后。应补持久化时间间隔和最后保存时间的验证。
- 本次没有把 Windows 无法构建 iOS、未接真机、未接地图底图、没有服务器，以及“固定 65 kg 的卡路里估算”本身当作缺陷；这些属于环境限制或当前产品范围。

建议先处理 01–08，再统一修正定位状态、运动时间和分段计算，之后完善恢复、重试与跨平台验证。
