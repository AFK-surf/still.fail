# 运行 ember

## 安装与启动

```sh
pnpm install --frozen-lockfile
pnpm build              # 构建管理页（web/ → dist/admin）；带 PostHog key 构建见 docs/telemetry.md
node src/main.ts        # Node 24；PATH 里需要 claude 和 codex
```

数据目录默认 `~/.ember`（`EMBER_DATA` 可改），配置文件是其中的 `config.json`（`EMBER_CONFIG` 可改）。

两个端口，都只监听本机：

| 端口 | 用途 |
|---|---|
| 4750 | agent 的 MCP 端点和 `/health`。不要对外暴露。 |
| 4760 | 管理页 `/admin`。要从外面访问时，只把 tunnel 指向这个端口。 |

station 由 `ember-station`（mesh/station）运行：它在本机提供管理页（4760），并把 Node 部分（src/main.ts）作为子进程启动和看护；Node 部分的管理接口只监听数据目录里的 `run/admin.sock`。4760 被别的程序占了，管理页会改用空闲端口，实际端口写在 `~/.ember/run/ports.json`；`ember start --port N` 指定端口时，被占就报错退出。MCP 端点的 4750 同理（配置里的 `http.port` 指定时被占就报错）。

收到 SIGTERM 时会结束所有运行时进程组；正在进行的 turn 会在下次启动时自动恢复。

## 管理页

在运行 ember 的机器上直接打开 `http://127.0.0.1:4760/admin`，不需要登录。从公网访问时，把 Cloudflare tunnel 指向 4760，并在 Cloudflare 上为这个域名配置 Access；再把 Access 应用的团队域名和 AUD 写进配置：

```json
{ "admin": { "access": { "teamDomain": "<团队>", "aud": "<Access 应用的 AUD tag>" } } }
```

ember 会校验每个经过 tunnel 的请求所带的 Access JWT（签名、团队、AUD、有效期），页面上显示访问者的邮箱，配置改动也按邮箱记日志。没有配置 `admin.access` 时，经过 tunnel 的请求一律拒绝。

在管理页里可以：

- 打开一个会话默认看它的执行历史；停止正在运行的任务、释放空闲进程都在历史底部。点「新建对话」会在旁边开一个 ember 自己的对话：它和 Slack 一样是一种连接，消息以 `via="web"`、`thread="EMBER/…"` 送给 agent，agent 用 `chat_post` 回到这个对话；
- 增删改 **连接**（connect）：人找到 ember 的地方。目前只有 Slack 连接（一个 Slack app），以后会有微信。每个连接绑定一个模型（运行时 Claude Code / Codex、一组账号和一个模型），并选一种会话方式（见下文）。页面上的「在 Slack 创建 app」会打开预填好 manifest 的 Slack 新建页；
- 单会话连接可以在连接页「当前会话」里换成任意一个同运行时的已有会话，或新建一个（可以起名）；更改会话方式要在弹窗里确认，弹窗会说明对进行中的对话有什么影响；
- 订阅账号可以直接在账号页登录：ember 在自己的机器上运行 `claude auth login` / `codex login --device-auth`，页面给出授权链接（Claude 需要把浏览器里显示的授权码粘贴回来，Codex 输入页面给的一次性代码后自动完成）；
- 连接页的「Slack app」可以改 app 的名字、简介、背景色、图标和权限，点「应用到 Slack」写进 app 的 manifest；权限有变化时，按提示去 Slack 同意一次。这需要一次性填入工作区的 App 配置 token（api.slack.com/apps 页面底部生成，填 Refresh Token），ember 会自动续期。Slack 只允许给用 API 创建的 app 换图标；
- 增删改 **账号**：运行时的配置目录（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）和启动时注入的环境变量。

改动立即写回 `config.json`（权限 600）并生效：新增或换了 token 的连接会重新连接，停用或删除的连接会断开。token 和密钥类环境变量在页面上只显示打码后的值，留空即保持不变。

## config.json

也可以直接编辑，格式如下（改完需要重启 ember）：

```json
{
  "admin": { "access": { "teamDomain": "…", "aud": "…" } },
  "connects": [
    { "id": "ds", "name": "ember", "kind": "slack", "mode": "multi-session",
      "bind": { "runtime": "claude", "profiles": ["claude-ocg"], "model": "deepseek-flash" },
      "slack": { "appToken": "xapp-…", "botToken": "xoxb-…" } },
    { "id": "ops", "name": "ember-ops", "kind": "slack", "mode": "single-session", "requireMention": false,
      "bind": { "runtime": "codex", "profiles": ["codex-main"] }, "enabled": false }
  ],
  "profiles": [
    { "id": "claude-ocg", "name": "OpenCode Go（Claude Code）", "runtime": "claude", "home": "homes/claude-ocg",
      "access": { "kind": "opencode-go", "key": "…" } },
    { "id": "codex-main", "runtime": "codex", "home": "homes/codex-main", "access": { "kind": "subscription" } }
  ],
  "maxNudges": 2,
  "warmMinutes": 30,
  "maxWarmClaude": 4,
  "telemetry": { "errors": false }
}
```

- 连接的 `id` 是会话记录的一部分，创建后不要改。旧版的 `bots` 配置在启动时会自动改写成 `connects`（多会话）。
- 账号的 `home` 相对数据目录。用订阅登录时，对这个目录登录一次：`CLAUDE_CONFIG_DIR=<home> claude`，或 `CODEX_HOME=<home> codex login`。
- `env` 里的 `{route}` 会替换成每个会话的路由 ID（Codex 的 app-server 按账号共享，替换成账号 ID），用于 OpenCode Go 这类需要会话亲和头的服务。
- 账号的 `access` 决定运行时怎么接模型：`subscription`（订阅登录）、`opencode-go`、`anthropic-api`（后两种要 `key`），或 `env`（只用 `env` 里手写的变量）。ember 据此生成环境变量；Codex 的服务商配置在启动 app-server 时用 `-c` 传入，不改 `config.toml`。
- `telemetry.errors` 打开后，这台 station 的错误（不带内容）上报到 ember 的 PostHog 项目，默认关闭，见 [telemetry.md](telemetry.md)。
- 共享的记忆和 skills 在 `<数据目录>/agent/`（`MEMORY.md` 和 `skills/`），启动时链接进每个账号的配置目录。

## 会话方式

- **多会话**（`multi-session`）：每个 thread 一个会话。在 thread 里 @ 它开始，之后这个 thread 的回复都进这个会话；私聊直接开会话。
- **单会话**（`single-session`）：这个连接看到的所有 thread 进同一个会话。`requireMention: true`（默认）时，被 @ 的 thread 才会进来，进来之后的回复不用再 @；`false` 时它能看到的每条消息都进来。

两种方式下，agent 收到的每条消息都带着来源（`thread="频道/thread_ts"`），回复时必须用 `to=` 指明发到哪个 thread，没有默认位置。这样一个会话以后换绑到别的连接，行为也不变。

## 在 Slack 里使用

- `@名字 <任务>`：开始一个会话（单会话连接则把这个 thread 带进它的会话）。
- 同一个 thread 里可以 @ 多个连接，它们各自有独立的会话。
- `-stop`：中断当前 turn。

## 开发

- `pnpm test`、`pnpm typecheck`（前后端都检查）。
- `pnpm dev:web`：管理页的热更新开发服务器，API 代理到本机 4760。
- `node scripts/admin-demo.ts`：用一份临时数据（各种状态的会话）起一个管理页。
- `node scripts/e2e.ts`：用真实的 Claude Code 和 Codex 跑一遍端到端，需要 `~/.config/ember-spike/opencode-go.env`。
