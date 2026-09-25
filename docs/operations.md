# 运行 ember

## 1. Slack app

用 [deploy/slack-app-manifest.yaml](../deploy/slack-app-manifest.yaml) 在 <https://api.slack.com/apps> 选 "From an app manifest" 新建 app，然后：

1. Basic Information → App-Level Tokens：生成一个带 `connections:write` 的 token（`xapp-…`）。
2. Install App：安装到 workspace，得到 Bot User OAuth Token（`xoxb-…`）。
3. 把 bot 拉进要用的频道。私聊不需要这一步。

## 2. 配置

数据目录默认 `~/.ember`，可以用 `EMBER_DATA` 改；配置文件是 `<数据目录>/config.json`，也可以用 `EMBER_CONFIG` 指定。Slack token 可以写在配置里，也可以用 `SLACK_APP_TOKEN` / `SLACK_BOT_TOKEN`。

```json
{
  "slack": { "appToken": "xapp-…", "botToken": "xoxb-…" },
  "defaults": { "runtime": "claude", "model": "deepseek-flash" },
  "channels": { "C0123456": { "runtime": "codex" } },
  "profiles": [
    {
      "id": "claude-main",
      "runtime": "claude",
      "home": "homes/claude-main",
      "env": {
        "ANTHROPIC_BASE_URL": "https://opencode.ai/zen/go",
        "ANTHROPIC_API_KEY": "…",
        "ANTHROPIC_CUSTOM_HEADERS": "x-opencode-session: {route}"
      }
    },
    { "id": "codex-main", "runtime": "codex", "home": "homes/codex-main", "env": { "OPENCODE_GO_KEY": "…", "OPENCODE_SESSION": "ember-{route}" } }
  ],
  "maxNudges": 2,
  "warmMinutes": 30,
  "maxWarmClaude": 4
}
```

- `profiles[].home` 是该账号的运行时配置目录（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`），相对路径以数据目录为基准。ember 不会读写用户自己的 `~/.claude`、`~/.codex`。
- `env` 里的 `{route}` 会替换成每个会话的路由 ID（Codex 的 app-server 是共享的，替换成账号 ID），用于 OpenCode Go 这类需要会话亲和头的服务。
- 用订阅账号时不需要 `env`：在对应的 `home` 下登录一次即可，例如 `CLAUDE_CONFIG_DIR=<home> claude` 或 `CODEX_HOME=<home> codex login`。
- Codex 的模型服务商在 `<home>/config.toml` 里配置，例如 OpenCode Go：

  ```toml
  model = "deepseek-flash"
  model_provider = "opencode-go"

  [model_providers.opencode-go]
  name = "OpenCode Go"
  base_url = "https://opencode.ai/zen/go/v1"
  env_key = "OPENCODE_GO_KEY"
  wire_api = "responses"
  env_http_headers = { "x-opencode-session" = "OPENCODE_SESSION" }
  ```

## 3. 启动

```sh
node src/main.ts        # 需要 Node 24，以及 PATH 里的 claude / codex
```

MCP 端点默认监听 `127.0.0.1:4750`，`/health` 用于存活检查。收到 SIGTERM 时会结束所有 runtime 进程组；正在进行的 turn 会在下次启动时自动恢复。

## 4. 在 Slack 里使用

- `@ember <任务>`：在频道里开一个会话；thread 里之后的回复都会转给它。
- `@ember [codex] <任务>` / `@ember [claude] <任务>`：为新会话指定 runtime。
- `-stop`：中断当前 turn。
- 私聊 bot：直接开会话。
