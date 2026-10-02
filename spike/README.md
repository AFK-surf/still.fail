# Spike

验证设计里依赖、但尚未实测的假设。每项留下脚本和结论，结论写明日期与运行时版本。

运行环境：一台 macOS 机器（64GB），claude 2.1.282，codex-cli 0.155.1，模型 OpenCode Go `deepseek-flash`。
凭证放在仓库外的私有 env 文件里；两家运行时都用单独的隔离配置目录，不碰用户自己的 `~/.claude`、`~/.codex`。

| # | 问题 | 脚本 | 结论（2026-09-26） |
|---|---|---|---|
| 1 | `claude -p` 的真实内存占用 | `claude-memory.ts` | 启动后未输入 ≈74MB footprint；一个调用 4 次工具的 turn 后稳定在 ≈125MB（峰值 130MB，RSS ≈290MB）。上下文很小时的数值，长会话会更高。 |
| 2 | 一个 codex app-server 承载 N 个 thread 的内存增量 | `codex-multithread.ts` | 空载 ≈27–41MB；每多一个 thread（跑过一次带命令的 turn）增加 <1MB，8 个 thread 共 48MB；4 个 turn 同时跑峰值 55MB。共享 app-server 的方案成立。 |
| 3 | HTTP MCP 通过环境变量传 token | `mcp-token.ts` | 两家都通过。Claude：user 级配置的 header 写 `Bearer ${EMBER_SESSION_TOKEN}`，按进程环境变量展开。Codex：`bearer_token_env_var`。 |
| 3b | 共享 codex app-server 里按 thread 区分 token | `codex-thread-mcp.ts` | 通过。`thread/start` 的 `config` 传 `mcp_servers.ember.url` 和 `mcp_servers.ember.http_headers`，每个 thread 建自己的 MCP 连接，3 个并发 thread 互不串。必须同时传 `sandbox: "danger-full-access"`，否则 MCP 调用被拒（"requires approval, but approval policy is never"）。 |
| 4 | 归档后解压回原路径能否 resume | `archive-resume.ts` | 两家都通过，且对照组（不恢复直接 resume）都失败，说明会话记录文件就是 resume 的全部依赖。Claude：`$CLAUDE_CONFIG_DIR/projects/<cwd 编码>/<id>.jsonl`；Codex：`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`。zstd 压缩到 23–31%。 |

辅助脚本：`tool-check.ts`（确认模型真的调用了工具）、`claude-trace.ts`（打印一次 `claude -p` 的事件流）。

## 过程中发现的坑

- **OpenCode Go 的请求必须带 `x-opencode-session` 头**，否则 400 `MissingSessionID`。值是任意的会话路由 ID。Claude 用 `ANTHROPIC_CUSTOM_HEADERS`，Codex 用 `env_http_headers`。
- **Claude 要用 `ANTHROPIC_API_KEY`（x-api-key）**。`ANTHROPIC_AUTH_TOKEN`（Bearer）会 401。
- **401 会被 claude 静默重试 10 次、约 3 分钟**，期间只有 `system/api_retry` 帧（带 `error_status`），最后的结果是 `subtype: "success"` 且 `is_error: true`。判断 turn 成败必须看 `is_error`，并且应在第一个 401 的 `api_retry` 就判定为认证失败。
- **两个 CLI 都会读 stdin**：stdin 不关，`claude -p` 等 3 秒后警告，`codex exec` 则一直等待。启动子进程时 stdin 要显式关闭。
- Codex 不认识的型号会报一条 `error` item（"Model metadata … not found"），不影响运行；可以在配置里补型号元数据来消除。
