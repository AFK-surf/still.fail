# ember

团队聊天里的 coding agent 服务：一个 thread 对应一个持久的 agent 会话，由 Claude Code 或 Codex 驱动；会话在 hot / warm / cold / 归档之间流转，归档后仍可唤醒。

设计见 [docs/design.md](docs/design.md)。
