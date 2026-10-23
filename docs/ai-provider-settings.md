# 国内 AI 平台设置

核验日期：2026-10-23。此功能是用户自带密钥（BYOK）的个人交互式训练助手，不是共享密钥网关。没有使用真实密钥或真实训练数据做线上调用。

## 操作顺序

选择国内平台 → 选择标准 API / Token Plan → 输入唯一的 API Key → 获取模型（或查看明确标注的官方预置目录）→ 选择模型 → 保存。地址由应用内核验目录提供，不要求用户手填地址或模型名。

模型列表调用和固定文本连接测试均需用户主动确认目的地址与密钥传输。获取模型不发送训练/健康数据，不保存配置。训练分析仍需原有独立的数据披露及确认。模型列表成功不等于账号拥有每个模型的调用权限。

## 当前平台

| 平台 | 标准 Chat Completions 地址 | 模型目录 | Token Plan |
| --- | --- | --- | --- |
| DeepSeek | https://api.deepseek.com/chat/completions | GET /models | 未核实适用方案，不启用 |
| 百炼（北京） | https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions | 官方预置；新模型列表接口需要 WorkspaceId，与仅填写 Key 的模式不兼容 | 官方排除自定义应用，不启用 |
| 智谱 GLM | https://open.bigmodel.cn/api/paas/v4/chat/completions | 官方预置，未核实公开的 Chat 模型列表 API | 官方限制指定工具，自建 App 应走标准 API |
| MiniMax | https://api.minimax.cn/v1/chat/completions | GET /v1/models | M Plan / Token Plan：仅个人自带订阅 Key 的主动交互；当前文字模型限 MiniMax-M3.1-Flash |
| Kimi | https://api.moonshot.cn/v1/chat/completions | GET /v1/models | Kimi Code 不是自建产品通用 API，不启用 |
| 小米 MiMo | https://api.xiaomimimo.com/v1/chat/completions | GET /v1/models，过滤语音等非聊天模型 | 官方排除明显非 Coding 场景，不启用 |

MiniMax 官方 FAQ 将 M Plan 定位于个人开发者交互场景，生产环境建议按量付费；官方通用工具页列出 Chatbox、Dify、LangChain 等。这为个人手动调用提供接入依据，但不是 MiniMax 对本健身 App 的专项认证，也不是共享服务、后台自动执行、多人共享 Key 的许可。中国区付费协议正文未能通过公开读取工具完整核验，用户仍须遵守其订阅条件。应用不自动从套餐切到标准 API，不更换 Key，不伪装客户端。套餐剩余额度可能与用户在官方购买的积分包有关，不能承诺所有调用仅消耗月套餐。

火山方舟 Coding Plan 也限制允许工具；本次不增加需要额外账户配置的火山标准接入，避免对未经完整核验的模型目录作承诺。

## 安全与兼容

- 原有自定义地址/模型配置保持可用，页面只读显示；选择新平台不会立即覆盖，只有用户保存才替换。
- 安全存储 envelope 同时绑定精确 endpoint、providerId、accessMode。旧 envelope 的缺省模式为 standard，旧记录可继续读取。恢复的元数据不匹配时不释放旧密钥。
- 切换平台或模式清空正在输入的密钥及模型列表；输入新 Key 会清空之前账号的模型选项。
- 模型发现只访问审核目录内的完整 HTTPS 地址，拒绝所有重定向，不将原始服务错误、Key、请求头写入日志或 UI。
- 所有表单在请求中锁定；页面退出不写状态，配置被其他页面改变时拒绝使用旧结果或覆盖新配置。
- Kimi 当前模型固定采样参数：HTTP 层对精确官方端点去除 temperature/top_p，保留生成器的结构化安全校验。
- MiMo 精确官方端点将 max_tokens 转为其文档要求的 max_completion_tokens，去除思考模式固定采样参数；预算不会丢失。
- MiniMax 精确官方端点的 content 可能带前置 think 块；只去除完整的前置块，不把截断思考当成成功计划，不修复非法 JSON。
- 推理模型连接测试不再只有 8 tokens，已核验官方服务使用 4096 上限；仍需显式确认可能产生的费用，输出截断或空内容不能视为连通成功。
- 已有安全后端继续使用 Android Keystore / 鸿蒙 Asset / iOS Keychain；安全保存失败不降级为明文。仅本次会话由用户明确选择。

## 官方依据

- DeepSeek 接口和当前模型：https://api-docs.deepseek.com/ ，https://api-docs.deepseek.com/api/list-models/
- 百炼兼容地址（明确旧域名仍可使用）：https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope
- 百炼新目录要求 WorkspaceId：https://help.aliyun.com/zh/model-studio/list-models
- 百炼 Coding / Token Plan 场景限制：https://help.aliyun.com/zh/model-studio/more-tools
- 百炼 Coding 无模型列表接口：https://help.aliyun.com/zh/model-studio/coding-plan-faq
- GLM 标准接口及模型：https://docs.bigmodel.cn/cn/guide/develop/openai/introduction
- GLM 订阅限制：https://docs.bigmodel.cn/cn/coding-plan/faq
- MiniMax OpenAI 兼容和模型：https://platform.minimax.cn/docs/api-reference/text-openai-api
- MiniMax 模型发现：https://platform.minimax.cn/docs/api-reference/models/openai/list-models
- MiniMax M Plan：https://platform.minimax.cn/docs/m-plan/faq ，https://platform.minimax.cn/docs/m-plan/other-tools
- Kimi 标准接口、模型发现和参数：https://platform.kimi.com/docs/api/overview ，https://platform.kimi.com/docs/api/list-models ，https://platform.kimi.com/docs/api/models-overview
- Kimi Code 限制：https://www.kimi.com/code/docs/
- MiMo 标准接口：https://mimo.mi.com/docs/zh-CN/quick-start/summary/first-api-call
- MiMo Chat 参数：https://mimo.mi.com/docs/en-US/api/chat/openai-api
- MiMo 模型目录：https://mimo.mi.com/docs/en-US/api/model/list-models ，https://mimo.mi.com/docs/zh-CN/quick-start/summary/model
- MiMo Token Plan 限制：https://mimo.mi.com/docs/zh-CN/tokenplan/Token%20Plan/subscription
- 火山方舟订阅限制：https://docs.volcengine.com/docs/ark/coding-plan-personal-faq?lang=zh
