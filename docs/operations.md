# 运行 ember

## 安装与启动

```sh
pnpm install --frozen-lockfile
pnpm build              # 构建管理页（web/ → dist/admin）
node src/main.ts        # Node 24；PATH 里需要 claude 和 codex
```

数据目录默认 `~/.ember`（`EMBER_DATA` 可改），配置文件是其中的 `config.json`（`EMBER_CONFIG` 可改）。

两个端口，都只监听本机：

| 端口 | 用途 |
|---|---|
| 4750 | agent 的 MCP 端点和 `/health`。不要对外暴露。 |
| 4760 | 管理页 `/admin`。要从外面访问时，只把 tunnel 指向这个端口。 |

收到 SIGTERM 时会结束所有运行时进程组；正在进行的 turn 会在下次启动时自动恢复。

## 管理页

在运行 ember 的机器上直接打开 `http://127.0.0.1:4760/admin`，不需要登录。从公网访问时，把 Cloudflare tunnel 指向 4760，并在 Cloudflare 上为这个域名配置 Access；再把 Access 应用的团队域名和 AUD 写进配置：

```json
{ "admin": { "access": { "teamDomain": "<团队>", "aud": "<Access 应用的 AUD tag>" } } }
```

ember 会校验每个经过 tunnel 的请求所带的 Access JWT（签名、团队、AUD、有效期），页面上显示访问者的邮箱，配置改动也按邮箱记日志。没有配置 `admin.access` 时，经过 tunnel 的请求一律拒绝。

在管理页里可以：

- 实时看所有会话的状态和对话过程，停止正在运行的任务，释放空闲的运行时进程；
- 增删改 **bot**：一个 bot 对应一个 Slack app，绑定一种运行时（Claude Code / Codex）、一组账号和一个模型。页面上的「在 Slack 创建 app」会打开预填好 manifest 的 Slack 新建页；
- 增删改 **账号**：运行时的配置目录（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）和启动时注入的环境变量。

改动立即写回 `config.json`（权限 600）并生效：新增或换了 token 的 bot 会重新连接，停用或删除的 bot 会断开。token 和密钥类环境变量在页面上只显示打码后的值，留空即保持不变。

## config.json

也可以直接编辑，格式如下（改完需要重启 ember）：

```json
{
  "admin": { "port": 4760, "access": { "teamDomain": "…", "aud": "…" } },
  "bots": [
    { "id": "ds", "name": "ember", "runtime": "claude", "profiles": ["claude-ocg"], "model": "deepseek-flash",
      "slack": { "appToken": "xapp-…", "botToken": "xoxb-…" } },
    { "id": "gpt", "name": "ember-gpt", "runtime": "codex", "profiles": ["codex-main"], "enabled": false }
  ],
  "profiles": [
    { "id": "claude-ocg", "runtime": "claude", "home": "homes/claude-ocg",
      "env": { "ANTHROPIC_BASE_URL": "https://opencode.ai/zen/go", "ANTHROPIC_API_KEY": "…",
               "ANTHROPIC_CUSTOM_HEADERS": "x-opencode-session: {route}" } },
    { "id": "codex-main", "runtime": "codex", "home": "homes/codex-main" }
  ],
  "maxNudges": 2,
  "warmMinutes": 30,
  "maxWarmClaude": 4
}
```

- bot 的 `id` 是会话记录的一部分，创建后不要改。
- 账号的 `home` 相对数据目录。用订阅登录时，对这个目录登录一次：`CLAUDE_CONFIG_DIR=<home> claude`，或 `CODEX_HOME=<home> codex login`。
- `env` 里的 `{route}` 会替换成每个会话的路由 ID（Codex 的 app-server 按账号共享，替换成账号 ID），用于 OpenCode Go 这类需要会话亲和头的服务。
- Codex 的模型服务商写在 `<home>/config.toml`，例如 OpenCode Go：

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

- 共享的记忆和 skills 在 `<数据目录>/agent/`（`MEMORY.md` 和 `skills/`），启动时链接进每个账号的配置目录。

## 在 Slack 里使用

- `@bot名 <任务>`：在频道里开一个会话，之后这个 thread 里的回复都会转给它。私聊 bot 直接开会话。
- 同一个 thread 里可以 @ 多个 bot，它们各自有独立的会话。
- `-stop`：中断当前 turn。

## 开发

- `pnpm test`、`pnpm typecheck`（前后端都检查）。
- `pnpm dev:web`：管理页的热更新开发服务器，API 代理到本机 4760。
- `node scripts/admin-demo.ts`：用一份临时数据（各种状态的会话）起一个管理页。
- `node scripts/e2e.ts`：用真实的 Claude Code 和 Codex 跑一遍端到端，需要 `~/.config/ember-spike/opencode-go.env`。
