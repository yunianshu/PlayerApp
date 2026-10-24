# 鸿蒙开跑约 30 秒震动：排查与真机复测

## 已发现的问题与修复范围

没有发现「开跑满 30 秒必震」的显式定时器。旧代码每 10 秒（或距离推进后）用同一 ID 1001 发布实时成绩，使用 SOCIAL_COMMUNICATION 高提醒槽，且未设置 isAlertOnce。重复发布同 ID 不等于静默更新，这是可确认的通知策略缺陷，也是此次异常的候选来源；没有真机日志，不能断言这就是用户手机上那一次震动。

另有几个需要区分的来源：
- 目标配速偏离持续约 15 秒后会有正常重触觉，GPS 起步稳定需要时间，可能落在开跑约 30 秒。默认未配置目标时不触发。
- 自动暂停/恢复会有正常中触觉（设置默认关闭，通知防抖 45 秒）。
- 鸿蒙定位流 30 秒静默超时会记录 GPS 错误、重连及可选语音，没有直接震动调用。
- 热身课程部分动作 30 秒到期有正常触觉；常规跑步与热身计时不同。
- 系统 LOCATION 长时任务自带通知可能有平台行为，应用不能直接观测实际马达。

本次保留原有 SOCIAL_COMMUNICATION 槽以维持锁屏实时成绩，只设置 isAlertOnce=true，让同 ID 后续更新降低提醒级别，不修改系统/用户通知设置，不影响训练提醒、倒计时、配速和暂停/继续触觉。通知发布和取消串行，防止退出跑步后在途更新把通知重新显示。重新开始跑步时刷新节流状态也重置。

限制：首发通知仍可按系统槽设置提示；若首次授权/后台启动延迟，首次发布可能晚于开跑，此时 isAlertOnce 不能消除首次提醒。LOCATION 系统保活通知不受此变更影响。用户修改过通知槽设置时以日志中的实际槽属性和真机效果为准。没有为消除候选问题而改用可能丢失锁屏展示的低级别通知槽。没有使用 API 23 才可写的 notificationFlags 或不存在的 isSilent 字段；未在本环境完成 ArkTS 编译。

## 如何取日志

1. 安装包含本次修改的 HAP；打开「我的 → 诊断日志」，复制旧记录留存后清空。
2. 按下面场景跑一次；记下实际震动相对开跑的秒数、是否锁屏、手机系统版本、是否开启配速与自动暂停。
3. 回到「我的 → 诊断日志 → 复制」。日志保留上限 256 KiB，界面读取最近 60,000 字符；写入/清空串行，避免并发截断丢事件。无需上传到外部服务器。
4. 搜索 RUN_FEEDBACK。session 为独立诊断会话，不是运动记录 ID；elapsedMs 来自单调 Stopwatch，不受调时间影响；eventId/requestId 关联请求与结果，requestSession 关联迟到响应。定位每采样不新增此类日志。
5. 如果有 DevEco/hdc，可同时在系统日志中过滤 RUN_FEEDBACK，查看 notification_permission、running_notification 原生请求/接受/错误、系统槽属性和后台任务。日志只记录来源/状态/错误码，不记录新增的坐标、成绩正文或 API Key。

request 表示应用调用；accepted/api_result 只表示平台 API 返回成功。physicalVibrationObserved 或 vibrationObserved 始终 unknown，不能当成硬件震动/无震动的证明。没有 haptic request 而只有通知请求时，只能把通知列为待进一步核实的候选。

应用原有的 GPS/TTS 诊断可能含精度或播报文字；本次 RUN_FEEDBACK 不增加这些内容。分享日志前可只保留 RUN_FEEDBACK 与版本行，检查后再发送。

## 真机验收矩阵

- 前台连续跑 0–90 秒：先关闭目标配速/自动暂停，不操作按钮，尤其检查 20–40 秒是否震动；持续观察第 10/20/30/40/60/90 秒实时通知更新。首发提示允许，预期无重复通知提醒，正常记录继续。
- 锁屏/后台连续跑 0–90 秒：开跑 10 秒后锁屏，60 秒后回前台；查看 lifecycle 与通知 request/result。确认后台记录和系统保活通知正常；单独记录自定义成绩是否仍在锁屏显示。
- 目标配速开启：制造持续偏离，确认 pace_target 的请求/接受和真实触觉仍存在；不应被全局静音。
- 自动暂停开启：满足停止及恢复条件，核对 auto_pause/auto_resume，45 秒防抖不被改变。手动暂停/继续也应各有对应来源。
- 倒计时、热身动作边界、锁定/解锁、结束跑步：原有触觉保留，并有单独来源；确认课程不在后台意外继续。
- GPS 断流超过 30 秒：核对 gps_stream failed/retry，不能把 GPS 语音当成显式触觉。
- 快速停止并重开：旧通知不能在取消之后复活，新会话不继承旧节流或被记到旧 session。
- 已拒通知权限、关闭其他通知槽、用户自定义槽震动：确认失败码可查，不影响计时/保存；不偷偷恢复或覆盖用户设置。

## 自动验证与证据边界

`node app/tool/test_running_notification_ohos.mjs` 执行实际 ArkTS 源码（去类型后的宿主 mock），覆盖 0–90 秒重复更新策略、失败后恢复、停止竞态、恢复和 ID 隔离。这不替代 Harmony SDK 编译或真机测试。

Dart 新增 run_feedback_diagnostics_test.dart 与 background_feedback_test.dart，使用模拟平台/事件收集，检查触觉来源、请求结果配对、隐私、生命周期/时间场景。恢复环境已重新安装官方 Flutter 3.47.5 / Dart 3.13.4，当前源码静态分析无问题，完整测试 572/572 已重新通过；旧快照测试结果不替代本次验证。上述宿主通知策略测试已重新通过，仍不代表真机马达行为或 HAP 编译通过。

官方依据：
- https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-notification-kit/js-apis-inner-notification-notificationRequest.md
- https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-notification-kit/js-apis-notificationManager.md
