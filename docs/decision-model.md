# 自动决策

> 2026-10-03：「完成检查」改成「归档建议」：agent 标记 all_done 时不再等模型、不再拦截；之后在后台判断这个 chat 是否已没有后续事项，没有就推荐归档（见末尾）。下面讲拦截的几段是改之前的做法，模型选择、能力发现和连接部分仍然有效。

设置中有独立的「自动决策」页面，先按决策点列入口，进入某个决策点后分别配置各 station 的启用开关和模型；检查记录在独立页面查看，不铺在设置中。首个用途是「完成检查」：agent 请求 all_done（包括旧 final）前检查是否仍有工作或需人处理的事项。默认关闭，管理员打开开关、选择模型并保存后生效。

模型候选来自现有 Profile 的能力发现；不另填地址、key，不手工绑定 Profile。相同模型可由多个健康 Profile 提供，临时连接失败时自动换另一个支持该模型的 Profile，不擅自换成另一个模型。配置只保存 `automaticDecisions.completion.{enabled,model}`，凭据始终由 Profile 管理。

station 启动、Profile 修改/检查以及自动决策页「刷新模型」都会识别能力。合成探针验证原生 Jev 概率或关闭 thinking 的单 token logprobs。名称仅用于排序，不能作为可用证据：原生 Jev 优先，然后是不思考的小模型（qwen 的 flash、deepseek 的 flash，再是其他 flash/mini/nano/lite），其余模型靠后，GLM 这类无法关闭 thinking 的最后；最多探测八个候选、25 秒。普通模型用 Chat Completions；DeepSeek 发送 thinking disabled，其余发送 reasoning_effort none。OpenCode / OpenCode Go 的网关对每个请求都要求 `x-opencode-session: <任意 uuid>`，缺了所有模型都回 400 MissingSessionID，探测和真实决策请求都会带上。在 OpenCode Go 网关实测：qwen3.8-flash、qwen3.8-max、qwen3.7-max、qwen3.7-plus 直接可用；deepseek-flash、deepseek-v4.1-flash、deepseek-v4-pro 要 thinking disabled 才有 logprobs；glm-5.x 关不掉 thinking；gpt-6-luna、grok 等在 Chat Completions 上回 ModelProtocolUnsupported，探测不通过即不会被选中。不把生成的“置信度”当 logits。

连接来自 API 服务商 Profile（OpenCode Go 与「API 服务商」里的任何一个：取该服务商目录里的 chat_completions 接口和 Profile 保存的 key；只有 Responses / Anthropic 接口的服务商，如 OpenAI、xAI、Azure OpenAI，没有可用的 Chat Completions 接口，不能做自动决策），或 Codex Profile 的既有环境变量、config.toml provider、API-key 登录。Jev 复用 Profile 的 TYPESAFE_API_KEY / JEV_API_KEY 与可选 TYPESAFE_BASE_URL；普通 API 复用既有 base_url/env_key 或 OPENAI_BASE_URL/OPENAI_API_KEY。不把订阅 OAuth token 当 API key；当前没有已验证的 Codex app-server logprobs 通路，自定义 headers 和其它厂商协议尚未适配。

规则启用后，指定模型不可用、证据不足或判断尚未完成，都不会冒充完成；在发帖、上传附件和结束状态落库前返回工具错误。没有启用规则时保持既有行为。检查期间设置或会话改变会丢弃旧结果。每次结果进入 decision_checks，页面实时显示最近 30 次结果及对应会话链接；审计不存聊天正文或凭据。

检查覆盖 session 的全部会话、待决定卡片和拟发文字/done。每段历史超过 200 条或总请求超过 96 KB 不静默截断。模型概率不是校准后的正确率；模拟供应商只验证接线和拦截流程，不证明真实模型准确率。样例集位于 station/test/fixtures/completion-decisions.jsonl（拿它跑真实提供商评估的 decision_eval 是 Rust station 的工具，2026-10-04 随它删除，在 git 历史里）。

配置及 Overview 新字段可选，旧站/旧客户端兼容；设置权限在 station 校验，core 保存草稿并驱动具名操作，web/Android 只渲染。station 的 decision_checks 事件刷新 Overview，无客户端轮询。

Jev 也可以作为「API 服务商」Profile 添加（只填 key）：只用于自动决策，不接 Claude Code、Codex；它没有模型列表，key 在发现决策能力时才被试。

## 归档建议（现在的做法）

agent 的一轮以 `all_done`（旧 `final` 同）结束后，station 在后台问决策模型：这个 chat 里还有没有事情要做。agent 的结束状态、发帖和落库不等它，也不会被它拦下；规则没开、模型不可用、请求失败，都只是没有推荐。

- 传给模型的是这个 session 各会话里从最新往旧、尽可能多的消息（最多 400 条、约 80 KB，放不下的是更旧的，会写明「更旧的消息没有放进来」），按时间顺序排好，加上待决定的卡片。
- 问法是四选一：`complete`（没有后续事项）、`agent_work`、`human_needed`、`uncertain`；概率最大的是 `complete` 且 ≥ 0.85 才算「没有后续事项」。
- 通过：这个 chat 标为「推荐归档」：规则开着的 station 上，只有推荐过的 chat 才淡出、排到当天最后、可以一点归档（第二行照常写「做完了…」，不加字）；没推荐的照常显示。不通过或判断不了：不标。推荐记在 `archive_suggestions`，带着判断时 chat 的最后一条消息号；之后任何人在 chat 里再说话，推荐自动失效（不用清）。用户选「保留」的 chat 不显示推荐。
- 判断期间设置变了或 chat 又有新消息，这次结果作废。每次结果（含失败）写进 `decision_checks`，在自动决策页的「归档建议记录」里看。
