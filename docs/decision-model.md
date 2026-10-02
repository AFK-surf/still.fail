# 自动决策

设置中有独立的「自动决策」页面，按 station 配置要启用的事项及每项使用的模型。首个用途是「完成检查」：agent 请求 all_done（包括旧 final）前检查是否仍有工作或需人处理的事项。默认关闭，管理员打开开关、选择模型并保存后生效。

模型候选来自现有 Profile 的能力发现；不另填地址、key，不手工绑定 Profile。相同模型可由多个健康 Profile 提供，临时连接失败时自动换另一个支持该模型的 Profile，不擅自换成另一个模型。配置只保存 `automaticDecisions.completion.{enabled,model}`，凭据始终由 Profile 管理。

station 启动、Profile 修改/检查以及自动决策页「刷新模型」都会识别能力。合成探针验证原生 Jev 概率或关闭 thinking 的单 token logprobs。名称与模型目录仅用于排序（Jev、Luna、小模型优先），不能作为可用证据；最多探测八个候选、25 秒。普通模型用 Chat Completions；DeepSeek 发送 thinking disabled，OpenAI 发送 reasoning_effort none。不把生成的“置信度”当 logits。

连接来自 OpenCode Go Profile，或 Codex Profile 的既有环境变量、config.toml provider、API-key 登录。Jev 复用 Profile 的 TYPESAFE_API_KEY / JEV_API_KEY 与可选 TYPESAFE_BASE_URL；普通 API 复用既有 base_url/env_key 或 OPENAI_BASE_URL/OPENAI_API_KEY。不把订阅 OAuth token 当 API key；当前没有已验证的 Codex app-server logprobs 通路，自定义 headers 和其它厂商协议尚未适配。

规则启用后，指定模型不可用、证据不足或判断尚未完成，都不会冒充完成；在发帖、上传附件和结束状态落库前返回工具错误。没有启用规则时保持既有行为。检查期间设置或会话改变会丢弃旧结果。每次结果进入 decision_checks，页面实时显示最近 30 次结果及对应会话链接；审计不存聊天正文或凭据。

检查覆盖 session 的全部会话、待决定卡片和拟发文字/done。每段历史超过 200 条或总请求超过 96 KB 不静默截断。模型概率不是校准后的正确率；模拟供应商只验证接线和拦截流程，不证明真实模型准确率。样例集位于 tests/fixtures/completion-decisions.jsonl，decision_eval 可使用测试 station 配置中的 Profile 跑真实提供商评估。

配置及 Overview 新字段可选，旧站/旧客户端兼容；设置权限在 station 校验，core 保存草稿并驱动具名操作，web/Android 只渲染。station 的 decision_checks 事件刷新 Overview，无客户端轮询。
