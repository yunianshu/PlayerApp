# 完整训练计划分享

训练计划右上角“分享完整训练计划”打开独立预览页。导出数据来自当前启用计划的全部有效任务，而非屏幕截图、当前月份或已构建的日卡片。

- 包括赛事、目标、倒计时、全部日期、标题、距离、配速、完成状态和当天实际跑量。使用与训练页面相同的 `TrainingRunResults` 计算，保留距离达标与手动标记的区别。
- 分享时刷新实际跑量，再创建不可变快照。后续切换计划、旋转屏幕或日期选择不会改变预览内容。
- 不读取体重、身体反馈原始记录、GPS、API Key 或 AI 对话。训练说明可能是个性化 AI 文字，默认不附带；用户可开启“附带完整训练说明”，查看全部文字后分享。未附带说明时明确显示标记和细节缺失提醒，不声称完整训练说明已导出。
- 改变说明选项会清除旧预览并禁用分享，必须重新生成。
- 生成完成后才允许用户打开系统分享面板。应用不会自动选择收件人或发布。

## 输出与资源边界

布局固定为 900 像素宽，每次只渲染 900 × 1400 像素。每页 RGBA 扫描行增量送入 zlib，输出一个 PNG，无需创建整张长图的 GPU 纹理。所有日期均在独立导出布局中展开。超过长图安全高度时明确提示改为完整多页 PDF，不静默截断。PDF 嵌入与预览相同的像素，避免接收方缺少中文字体。

生成过程支持取消、禁止重复点击；失败和取消清理部分文件。未分享的预览离开页面后清理。已交给系统分享的文件保留，防止部分平台分享 API 返回后收件应用才读取；下一次导出时清理超过 24 小时的本功能临时目录。系统也可能清理其临时目录。不会删除其他应用临时文件。

复用 `ShareService.file` 与 OHOS 兼容静态 `share_plus` API，不新增依赖，不修改鸿蒙插件锁定版本。

## 验证

`test/training_plan_export_test.dart` 覆盖完整日期、跨月跨年、三种主题、PNG 实际解码、365 天完整 PDF 页数、取消清理、长 Unicode 说明和预览前无分享、重复点击保护。

可设置 `TRAINING_EXPORT_PREVIEW_DIR` 后运行此测试，保存三套主题的完整 PNG 及首尾页用于视觉检查。

2026-10-24 环境快照恢复后已重新执行本模块 10 项测试，全部通过。新生成三套主题 900 × 7000 完整长图，首尾像素与分块预览一致；新生成 365 天完整 PDF 共 60 页，通过交叉引用、解压检查和独立 PDF 阅读器解析，末页可正常渲染。上述结论来自本次重跑，不复用恢复前日志。实际系统分享、Android/HAP 构建与鸿蒙真机长图接收仍需独立验证；组件测试使用模拟分享面板，不代表真机验证。

## Integrated recovery verification — 2026-10-24

Current recovered source: Flutter 3.47.5 / Dart 3.13.4 analyzer passed with no issues; the full suite passed 572/572 tests. Native host-policy checks passed (Python: 19 passed, one existing skip). Android APK validation awaits the exact published commit’s CI run. Harmony HAP compilation, physical device vibration and native sharing are not verified by these tests.
