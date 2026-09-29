# still.fail

团队聊天里的 coding agent 服务：在 Slack 或 still.fail 自己的网页对话里找它，每个对话落到一个持久的 agent 会话，由 Claude Code 或 Codex 驱动；会话在 hot / warm / cold / 归档之间流转，归档后有新消息就自动恢复。

- `mesh/`：station（Rust，`ember-station`），跑在执行 agent 的机器上
- `client/`：各客户端共用的 Rust client core；`web/`（网页版和管理页）、`apps/desktop`（Electron）、`apps/android`
- `cloud/`：still.fail cloud（账号、workspace、成员凭证、relay，部署在 Cloudflare）

设计见 [docs/design.md](docs/design.md)，运行见 [docs/operations.md](docs/operations.md)。
