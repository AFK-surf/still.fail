# 运行 still.fail

## 安装与启动

从源码搭建隔离开发环境见 [development.md](development.md)。正式使用时，在 [still.fail web](https://app.still.fail) 的 workspace 设置里添加 station，按页面生成的一次性命令安装并加入 workspace。安装器把发布包放到 `~/.stillfail/app`，把 `stillfail` 链接进 `~/.local/bin`，并注册用户服务（macOS 用 launchd，Linux 用 systemd）。`stillfail update` 更新发布包，`stillfail status` 查看绑定与连接状态。

station 必须加入 workspace 才接 Slack、运行 agent。数据默认在 `~/.stillfail`（`STILLFAIL_DATA` 可改，兼容 `EMBER_DATA`）；旧版 `~/.ember` 在首次启动时迁移。开发测试使用独立数据目录，不使用已有真实会话的 station。

更新支持原地交接；不支持交接时，安装器会先排空再重启。运行细节见 `mesh/app/src/handoff.rs`。部署与历史维护记录见 [ops-log.md](ops-log.md)。

## 管理界面

管理 station 从 workspace 内进入，通过客户端 core 与 station 建立带成员凭证的连接。本机旧管理端口 4760 仅重定向到 cloud，已经不再提供独立管理页；4750 是 agent MCP 端点，不要对公网暴露。这两个端口都默认只监听本机，实际端口以 station 的运行记录为准。

下面的配置与会话说明包含旧版本兼容字段。新安装使用 workspace 设置管理连接、账号和 station，控制面设计见 [cloud.md](cloud.md)。

## config.json

也可以直接编辑，格式如下（改完需要重启 still.fail）：

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
- 账号的 `access` 决定运行时怎么接模型：`subscription`（订阅登录）、`opencode-go`、`anthropic-api`（后两种要 `key`），或 `env`（只用 `env` 里手写的变量）。still.fail 据此生成环境变量；Codex 的服务商配置在启动 app-server 时用 `-c` 传入，不改 `config.toml`。
- `telemetry.errors` 打开后，这台 station 的错误（不带内容）上报到 still.fail 的 PostHog 项目，默认关闭，见 [telemetry.md](telemetry.md)。
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
- client core：在 client/ 里 `cargo test --workspace --exclude stillfail-core-wasm`。
- `pnpm test`（web 里的 TypeScript 部分，需要先构建 wasm core）、`pnpm typecheck`。
- `pnpm check`：跑全部检查（scripts/check.sh all）。
- `pnpm dev:web`：still.fail cloud 网页版（`--mode cloud`）的热更新开发服务器。

## CI

`.github/workflows/pipeline.yml` 使用 AFK-surf 的 CI 资源：计划/API/changelog/标签在 ubuntu-24.04，完整检查、网页构建和 Android 发布在 Blacksmith Linux；station 与桌面打包签名在现有 `[self-hosted, mini1]` Mac。Linux 工具链由 `.github/actions/setup` 安装并缓存；Mac 使用 `.github/actions/setup-mac` 接入 mini1 既有工具链。只有 Studio 自更新经 mini1 执行；构建签名不再 SSH 到 Studio。桌面必须使用原签名身份，可通过 production 的 MACOS_SIGNING_CERTIFICATE_B64 / MACOS_SIGNING_CERTIFICATE_PASSWORD 注入一次性钥匙串，结束后删除；身份缺失则拒绝发包。

- **分支**：每次 push 跑完整检查（`scripts/check.sh full <merge-base>..HEAD`），并把改到的部分构建、打包一遍（`deploy.py --dry-run`，不部署、不读密钥）。结果当合并的证据，不卡合并。
- **main**：检查上次部署（tag `deployed/beta`）以来改到的部分，过了就按顺序部署改到的：先 api（stillfail-cloud，正式环境，只有一份），再 web-beta（app.youdid.wtf）、admin、preview、site-beta（youdid.wtf），以及测试通道的 station 发布包（`.github/release.sh station`：三个平台，传完让 studio 的 station `stillfail update`，经 mini1 到 studio 的 ssh）、桌面测试版（`.github/release-desktop.py`：在组织 Mac runner 上直接构建，用原签名身份签名、验证后上传）和安卓测试版（`.github/release.sh android`，用 secret `ANDROID_DEBUG_KEYSTORE_B64` 里 studio 的那把 key 签，不能换）。哪一步不过，后面的都不发；全部发完才把 `deployed/beta` 挪到这个提交，所以被取消或失败的那次，改动会算进下一次。relay 改了只在 Actions 里给个警告，不自动部署（会断所有连接）。
- **正式版手动一键发布**：在 GitHub Actions 的 **Publish stable → Run workflow**，选择 main，revision 留空即可。它选择最新已审核的 `docs/releases/0.1.<n>.md` 对应提交；也可填写完整 main SHA。该提交必须包含本版本日志、已通过 main pipeline 且保留网页 artifact（90 天），否则在发布前停止。先由 Blacksmith / mini1 构建签名正式 Android / 桌面，再将同一提交的原网页 artifact 转正，最后从该提交构建三个平台的正式 station。各端全部成功才移动 `deployed/stable`；不自动更新用户的 station。测试版继续随 main 自动发布，正式版没有 push 触发器。失败后可用相同 SHA 重跑；已发布到更新正式版后不能借此回退旧版。
- **仍手动处理**：relay 用 studio 的部署入口（会断开连接）；正式官网 `deploy.py site`。旧 `ember-promote` 仅为运维入口，日常正式发布使用上述 workflow。
- **密钥**：GitHub 的 Environment `production`（只有 main 能用），secret 是部署目录各文件的内容：`DEPLOY_KEYS_JSON`（keys.json）、`GOOGLE_OAUTH_JSON`、`AXIOM_JSON`、`FCM_SERVICE_ACCOUNT_JSON`、`POSTHOG_JSON`、`VAPID_JSON`（还没有）、`CLOUDFLARE_API_TOKEN`（GitHub-hosted 部署必须配置）。`.github/deploy.sh` 每次把它们写进临时部署目录，用完就删。换密钥：改 studio `~/ember-deploy` 里的文件，再 `gh secret set <名字> --env production < 文件`。
- **本地收尾**：mini1 runner 只负责通过 SSH 让 Studio 更新到刚发布的 station 包。普通 CI 不再排这些 runner 的队；自托管任务仍限 main 和 production 环境。
- **加 runner / 重新注册**：在 mini1 上 `gh api -X POST repos/AFK-surf/still.fail/actions/runners/registration-token --jq .token` 拿 token，在新目录里解开 actions-runner-osx-arm64，`./config.sh --unattended --url https://github.com/AFK-surf/still.fail --token <token> --name mini1-<n> --labels mini1`，`./svc.sh install && ./svc.sh start`。
- 看结果：`gh run list -R AFK-surf/still.fail -w pipeline`（mini1 上有 gh 登录）。
