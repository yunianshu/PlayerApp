# RunTrail 修复记录 · 2026-09-27

对应 [修复前审计的 30 项问题](project-audit-2026-09-27.md)。代码、配置和文档修复均已落地；设备行为的验收边界单列在末尾。保留了工作区原有 Android 服务 import 修改，未提交或推送代码。

## 修复对应关系

| 编号 | 修复 | 验证 |
| --- | --- | --- |
| 01 | 无定位点时暂停跳过空草稿，仍正常更新状态 | tracking A01 |
| 02 | 暂停/恢复建立新段，点记录活动时间，数据库 v2 保存段边界 | tracking A02、暂停分段测试、旧库迁移测试 |
| 03 | painter 保存构造时点数，路线按段绘制 | tracking A05 |
| 04 | iOS 使用 AppleSettings 显式启用后台定位 | 本地插件 API 和配置核对；待 iOS 构建及真机验证 |
| 05 | 鸿蒙补 location 后台模式，原生失败返回错误并在界面提示 | 签名 HAP 构建、后台失败测试；待真机验证 |
| 06 | 结束时保存最终草稿，数据库保存成功或确认放弃后才清理 | tracking A08、最终时长/快照测试 |
| 07 | 恢复草稿未处理前阻止新跑步，首页提示并刷新恢复卡 | tracking A12 |
| 08 | 保存按钮设置忙碌状态，SQLite 会话唯一键与事务保证幂等 | UI B03、5 次并发插入测试 |
| 09 | 实时配速在同一个窗口内插值距离和时间 | tracking A03 |
| 10 | 实时配速按当前时钟过期，停止移动后不保留旧值 | tracking A04 |
| 11 | 每公里分段保留跨界余量并插值用时，跳过暂停断点 | tracking A06、暂停分段和 splits 测试 |
| 12 | 草稿操作串行，临时文件原子替换，按会话清理 | tracking A13、替换失败保留旧快照、过期页面不能清新草稿测试 |
| 13 | 监听定位服务恢复，流错误/结束后定时重订阅，断开期间建立新段 | 定位服务恢复和自动重试测试 |
| 14 | 区分收到位置与获得可用精度，精度差时不显示记录正常 | tracking A09 |
| 15 | 用稳定海拔锚点累计缓坡，按垂直精度设置阈值 | tracking A11 |
| 16 | 倒计时按剩余时间显示 3→2→1 | tracking A07 |
| 17 | 页面入口及 tracker 在 await 前防重入，取消/释放后不迟启动 | tracking A10 |
| 18 | 回调使用不监听的 readColors，build 保留 select | UI B01、目标对话框点击测试 |
| 19 | 年度目标只统计当前自然年，日期变化触发刷新 | UI B02、日期刷新测试 |
| 20 | 半马成就改为单次距离达到 21.0975 km | 代码核对 |
| 21 | 数据库打开失败清理 Future，允许重试 | database_recovery C01 |
| 22 | 首页、历史、统计、我的、详情提供错误状态及重试 | 首页注入数据库读取失败后点击恢复测试 |
| 23 | 前台恢复与分钟定时器检查自然日，常驻页面重新加载 | 日期刷新、自然周统计测试 |
| 24 | 导航弹性分配；首页、历史卡片、徽章、趋势标签适配窄屏 | 320px 四个标签页 × 三套主题测试 |
| 25 | 鸿蒙使用隔离工程，不切换主 pubspec/lock | Python 构建失败隔离测试 |
| 26 | SDK 路径参数化，补丁只处理私有副本，签名移到本机配置 | Python 副本/签名隔离测试、实际 HAP 构建 |
| 27 | 年度剩余距离取下限 0 | 代码核对 |
| 28 | 目标校验有限值及 1–1000 范围，保留小数，错误就地显示 | calendar_prefs、目标对话框测试 |
| 29 | 双锁文件策略、Git 依赖固定提交、修正忽略规则 | 两套工具链依赖解析、分析与构建 |
| 30 | 重写 README、iOS SPM 流程、鸿蒙隔离构建和签名指南 | 与仓库配置及实际命令核对 |

额外补齐：无 GPS 更新时 ticker 仍按 15 秒间隔保存活动时长；日期运算改用自然日；旧 Share/PopScope API 的兼容说明集中保留；静态分析信息清零；Windows 鸿蒙超长缓存路径支持重复清理，并增加自动回归。

## 数据和兼容性

- 数据库版本从 1 升为 2，新增会话 ID、轨迹段边界及活动时间列，升级保留旧数据。
- 旧轨迹没有暂停分段信息，无法从旧数据还原此前被错误计入的暂停位移/时间；新记录按新模型处理。
- 草稿只会在显式放弃或对应记录保存成功后清理；写入失败仍显示错误并允许重试。
- 两套锁文件作为源码交付；本机签名、SDK 配置、缓存和构建产物继续忽略。原有鸿蒙签名配置保存在 `app/ohos/build-profile.local.json5`。

## 验证命令

在 `app/` 执行：

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
python -m unittest discover -s tool/tests -v
flutter build apk --release --no-pub
python tool/ohos_build.py release --offline --analyze
```

最终结果：

| 检查 | 结果 |
| --- | --- |
| 主 Flutter 静态分析 | 无 error、warning、info，退出码 0 |
| Flutter 全量回归 | 57 项通过；增强恢复断言后另跑相关 10 项通过 |
| Python 构建脚本回归 | 5 项通过 |
| Android release APK | 构建通过，约 51.8 MB |
| 鸿蒙 Flutter 3.22 静态分析 | No issues found，退出码 0 |
| 鸿蒙 release 签名 HAP | 构建通过，约 24.2 MB；重复隔离构建通过 |
| `git diff --check` | 通过 |

产物：`app/build/app/outputs/flutter-apk/app-release.apk`、`app/build/ohos/hap/entry-default-signed.hap`。

验证日志保存在忽略的 `app/.dart_tool/`：`fix-analyze.log`、`fix-tests.log`、`recovery-final-tests.log`、`android-fix-build.log`、`ohos-fix-build.log`。

## 尚需设备环境的验收

Windows 无法运行 Xcode，当前未连接 Android、鸿蒙或 iOS 设备。因此本次不能声称已经实测各平台锁屏后台续记。发布前需连接设备验证：权限申请/撤销、精确位置关闭、GPS 关闭/恢复、前后台切换、锁屏、长时任务状态、进程终止及草稿恢复。iOS 需在 Mac 按 [构建指南](ios.md) 完成编译和签名验证。

日历测试覆盖夏令时切换日期的自然日运算，但本机时区为 Asia/Shanghai，尚未在夏令时时区设备上完整验收。以上环境边界不影响已通过的自动化测试与本机构建结果。
