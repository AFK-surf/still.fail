# 决策模型

决策能力属于现有 Profile，没有独立的地址、key、模型选择表单。station 启动、Profile 修改或重新检查时，使用 Profile 已有的连接、凭据和模型目录自动识别决策模型。Profile 页显示识别结果，旧客户端忽略可选的 `check.decision` 字段。

识别使用合成题，不发送聊天内容。原生 Jev 调用 `systemone`；普通模型使用关闭 reasoning 的单 token Chat Completions logprobs。模型目录和名称仅用于候选排序（Jev、Luna、小模型优先），必须通过完整概率分布验证才进入决策池。探测最多八个候选、25 秒，失败显示未验证，可用现有的 Profile 重新检查按钮重试。

连接来自 OpenCode Go Profile，或 Codex Profile 的已有环境变量、`config.toml` provider 和 API-key 登录。Jev 使用 Profile 内的 `TYPESAFE_API_KEY` / `JEV_API_KEY` 与可选 `TYPESAFE_BASE_URL`。普通 API 使用既有 provider 的 `base_url`、`env_key`，或 `OPENAI_BASE_URL` / `OPENAI_API_KEY`。不把 ChatGPT/Claude 的订阅 OAuth token 当作 API key；没有概率接口的账号明确显示未支持，不假称可用。未实现的自定义 headers / 独立供应商协议也不会仅凭模型名启用。

每次 `chat_post` 或 `chat_state` 请求 all_done（包括旧 final），自动选通过验证且账号健康的 Profile。连接临时失败时换下一个候选。任何一次有效判断指出仍需工作、等人或证据不足，均在发帖、上传附件、修改结束状态之前拒绝。无任何已验证 Profile 时保持既有行为，不要求人另配一套账号。

检查覆盖该 session 的所有会话、现有待决定卡片及拟发文字和 done 理由。超过 200 条消息或 96 KB 不静默截断；等待期间会话有新消息时拒绝过期结果。概率分布是模型分数，不是校准后的正确率。结果和所用 Profile/model 写入 decision_checks，密钥及聊天正文不写入审计。

验证：studio 上 `cargo test -p stillfail-app decision` 与 `cargo test -p stillfail-app completion_review`。合成集在 `tests/fixtures/completion-decisions.jsonl`，`cargo run -p stillfail-app --example decision_eval -- <station-config.json> <cases.jsonl>` 自动从该测试 station 的 Profile 发现模型；失败不宣称语义准确率已验证。
