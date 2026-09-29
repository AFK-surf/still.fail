# 运行 ember

## 安装与启动

```sh
pnpm install --frozen-lockfile
pnpm build                                      # 先构建 wasm 的 client core（client/wasm/build.sh，需要 wasm-bindgen），再构建管理页（web/ → dist/admin）；带 PostHog key 构建见 docs/telemetry.md
(cd mesh && cargo build --release -p ember-station)
bin/ember start                                 # PATH 里需要 claude 和 codex
```

以上是从源码运行。正式安装走 ember cloud：在 workspace 里拿到安装命令（`curl -fsSL <origin>/install.sh | sh -s -- <token>`，cloud/src/install.ts），它把发布包放到 `~/.ember/app`、把 `ember` 链接进 `~/.local/bin`、加入 workspace，并注册成用户服务（macOS 用 launchd，Linux 用 systemd 用户服务），日志写到 `~/.ember/ember.log`。之后 `ember update` 更新到最新发布；`ember station enroll <origin> <token>` 手动加入 workspace。

更新不打断 agent：服务定义（plist / unit）没变时，`ember update` 把新版本放到原处后给运行中的 station 发 SIGUSR2，station 在自己的进程里 exec 新版本（pid 不变），把正在跑的 claude / codex 进程的管道、两个监听 socket 和每个会话的状态交接过去（mesh/app/src/handoff.rs），轮次、工具调用和 job 都接着跑。交接不了（服务定义变了、新版本读不了这一版的交接、交接失败）就退回重启：先发 SIGUSR1 排空（不再开新轮次，消息排队，等正在跑的轮次结束，最多 10 分钟，`run/drained` 说明排空了），再重启。job 不随 station 停止，重启后的 station 接着跟踪它们。station 在 `run/station.json` 里写着自己的 pid 和支持的这些能力。

部署、更新的做法和出过的事记在 docs/ops-log.md（部署维护日志）。

数据目录默认 `~/.ember`（`EMBER_DATA` 可改），配置文件是其中的 `config.json`（`EMBER_CONFIG` 可改）。

两个端口，都只监听本机：

| 端口 | 用途 |
|---|---|
| 4750 | agent 的 MCP 端点和 `/health`。不要对外暴露。 |
| 4760 | 管理页 `/admin`。要从外面访问时，只把 tunnel 指向这个端口。 |

station 由 `ember-station`（mesh/station）运行：station 本身（mesh/app）就在这个进程里，它在本机提供管理页（4760）。4760 被别的程序占了，管理页会改用空闲端口，实际端口写在 `~/.ember/run/ports.json`；`ember start --port N` 指定端口时，被占就报错退出。MCP 端点的 4750 同理（配置里的 `http.port` 指定时被占就报错）。

桌面端自带同一个 station（`scripts/station-bundle.sh` 的布局，放在应用的 Resources/station），随应用启动和退出，数据同样在 `~/.ember`。本机已经有 station 在运行（装过独立的），桌面端就不再启动自己的（ember-station 发现数据目录被占，以退出码 3 结束）。本机的 station 还没加入 workspace 时，打开一个 workspace 会自动加入它（要是 owner 或管理员）；只自动加入一次，之后从 workspace 移除就不会自己再加回来。桌面端用 `--with-parent` 启动 ember-station：父进程结束时它也结束，被强行杀掉的桌面端不会留下孤儿 station（launchd 或 nohup 启动的不这样）。

收到 SIGTERM 时会结束所有运行时进程组；正在进行的 turn 会在下次启动时自动恢复。

## 管理页

在运行 ember 的机器上直接打开 `http://127.0.0.1:4760/admin`，不需要登录。从公网访问时，把 Cloudflare tunnel 指向 4760，并在 Cloudflare 上为这个域名配置 Access；再把 Access 应用的团队域名和 AUD 写进配置：

```json
{ "admin": { "access": { "teamDomain": "<团队>", "aud": "<Access 应用的 AUD tag>" } } }
```

ember 会校验每个经过 tunnel 的请求所带的 Access JWT（签名、团队、AUD、有效期），页面上显示访问者的邮箱，配置改动也按邮箱记日志。没有配置 `admin.access` 时，经过 tunnel 的请求一律拒绝。

在管理页里可以：

- 打开一个会话默认看它的执行历史；停止正在运行的任务、释放空闲进程都在历史底部。点「新建对话」会在旁边开一个 ember 自己的对话：它和 Slack 一样是一种连接，消息以 `via="web"`、`thread="EMBER/…"` 送给 agent，agent 用 `chat_post` 回到这个对话；
- 增删改 **连接**（connect）：人找到 ember 的地方。目前只有 Slack 连接（一个 Slack app），以后会有微信。每个连接绑定运行时（Claude Code / Codex）、模型和思考深度，可以固定一个账号，不固定时由账号池为每个会话挑，并选一种会话方式（见下文）。页面上的「在 Slack 创建 app」会打开预填好 manifest 的 Slack 新建页；
- 单会话连接可以在连接页「当前会话」里换成任意一个同运行时的已有会话，或新建一个（可以起名）；更改会话方式要在弹窗里确认，弹窗会说明对进行中的对话有什么影响；
- 订阅账号可以直接在账号页登录：ember 在自己的机器上运行 `claude auth login` / `codex login --device-auth`，页面给出授权链接（Claude 需要把浏览器里显示的授权码粘贴回来，Codex 输入页面给的一次性代码后自动完成）；
- 这台机器自己的 Claude Code / Codex 已经登录时，可以直接用这份登录（`"machine": true` 的 Profile，只能选模型，不能改名或在 ember 里登录；停用就是移除这个 Profile，本机的登录不受影响）。Claude Code 的登录按 claude 自己的顺序读：macOS 上先读钥匙串（`Claude Code-credentials`，station 在图形会话里能读到），再读 `~/.claude/.credentials.json`；Codex 只支持文件里的 `~/.codex/auth.json`。station 读不到的（Codex 只存在钥匙串里的，或钥匙串没解锁）要单独登录一次。Codex 的 home 里 `auth.json` 链接到本机那份，两边共用、各自刷新都写回同一个文件；Claude Code 换新令牌时会把链接替换成新文件，所以改为把本机当前的 access token 通过 `CLAUDE_CODE_OAUTH_TOKEN` 交给 ember 的进程，ember 自己从不刷新：令牌快过期时让本机的 claude 用 haiku 回一个字（不留会话记录），由它在自己存登录的地方刷新，ember 再从同一个地方读。
- 连接页的「Slack app」可以改 app 的名字、简介、背景色、图标和权限，点「应用到 Slack」写进 app 的 manifest；权限有变化时，按提示去 Slack 同意一次。这需要一次性填入工作区的 App 配置 token（api.slack.com/apps 页面底部生成，填 Refresh Token），ember 会自动续期。Slack 只允许给用 API 创建的 app 换图标；
- 用配置 token 建好的 Slack app 在连上之前一直存在 station 的 config.json（`slackApps`，含 client secret 和装好后拿到的 bot token），重启不丢；「连接」页列出你建的、还没连上的 app，随时点「继续」安装或补 App-Level Token，也可以从 ember 里移除（Slack 里的 app 要自己删）；
- 增删改 **账号**：运行时的配置目录（`CLAUDE_CONFIG_DIR` / `CODEX_HOME`）和启动时注入的环境变量。

改动立即写回 `config.json`（权限 600）并生效：新增或换了 token 的连接会重新连接，停用或删除的连接会断开。token 和密钥类环境变量在页面上只显示打码后的值，留空即保持不变。

## config.json

也可以直接编辑，格式如下（改完需要重启 ember）：

```json
{
  "admin": { "access": { "teamDomain": "…", "aud": "…" } },
  "connects": [
    { "id": "ds", "kind": "slack", "mode": "multi-session",
      "bind": { "runtime": "claude", "profile": "claude-ocg", "model": "deepseek-flash" },
      "slack": { "appToken": "xapp-…", "botToken": "xoxb-…" } },
    { "id": "ops", "kind": "slack", "mode": "single-session", "requireMention": false,
      "bind": { "runtime": "codex" }, "enabled": false }
  ],
  "profiles": [
    { "id": "claude-ocg", "name": "OpenCode Go（Claude Code）", "runtime": "claude", "home": "homes/claude-ocg",
      "access": { "kind": "opencode-go", "key": "…" } },
    { "id": "codex-main", "runtime": "codex", "home": "homes/codex-main", "access": { "kind": "subscription" } }
  ],
  "maxNudges": 2,
  "warmMinutes": 30,
  "maxWarmClaude": 4,
  "autoArchiveDays": 1,
  "telemetry": { "errors": false }
}
```

- 连接的 `id` 是会话记录的一部分，创建后不要改。`bind.profile` 可省略：省略时由账号池在该运行时的账号里挑（只挑启用了这个模型的）。
- `autoArchiveDays`：空闲且已结束的会话和对话多少天后自动归档，0 为不自动归档。
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

- station：在 mesh/ 里 `cargo test --workspace`。
- client core：在 client/ 里 `cargo test --workspace --exclude ember-core-wasm`。
- `pnpm test`（web 里的 TypeScript 部分，需要先构建 wasm core）、`pnpm typecheck`。
- `pnpm check`：跑全部检查（scripts/check.sh all）。
- `pnpm dev:web`：管理页的热更新开发服务器，API 代理到本机 4760。
