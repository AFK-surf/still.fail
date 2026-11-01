# 运行 still.fail

## 安装与启动

从源码搭建隔离开发环境见 [development.md](development.md)。正式使用时，在 [still.fail web](https://app.still.fail) 的 workspace 设置里添加 station，按页面生成的一次性命令安装并加入 workspace。安装器把发布包放到 `~/.stillfail/app`，把 `stillfail` 链接进 `~/.local/bin`，并注册用户服务（macOS 用 launchd，Linux 用 systemd）。`stillfail update` 更新发布包（只装签名验得过的版本，见 [release-signing.md](release-signing.md)），`stillfail status` 查看绑定与连接状态。

station 必须加入 workspace 才接 Slack、运行 agent。数据默认在 `~/.stillfail`（`STILLFAIL_DATA` 可改，兼容 `EMBER_DATA`）；旧版 `~/.ember` 在首次启动时迁移。开发测试使用独立数据目录，不使用已有真实会话的 station。

查内存：station 每 10 分钟在日志里记一行 `memory: now`（主线程的 heap、external，各读取线程的 heap）。`stillfail heap` 让运行中的 station 把主线程的堆快照写到 `<数据目录>/run/heap-*.heapsnapshot`（只留最新一份，0600：里面有 station 持有的 token），用 Chrome DevTools 的 Memory 打开；写的几秒里 station 不响应（station/src/ops/heap.ts）。macOS 上看进程占用以 footprint 为准（`footprint -p <pid>`），RSS 含共享库。

更新支持原地交接：启动器（station/native/launcher，pid 不变）收到 SIGUSR2，在旁边起新版本的 Node 进程，新的就绪后放掉旧的，轮次、运行时和 job 不断（station/native/launcher/src/run.rs、station/src/ops/launcher.ts）；不支持交接的旧版本（Rust station），安装器会先排空再重启。

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
  "slackArchiveDays": 3,
  "archivedWorkspaceDays": 7,
  "telemetry": { "errors": false }
}
```

- 连接的 `id` 是会话记录的一部分，创建后不要改。`bind.profile` 可省略：省略时由账号池在该运行时的账号里挑（只挑启用了这个模型的）。
- `autoArchiveDays`：空闲且已结束的会话和对话多少天后自动归档，0 为不自动归档。
- `slackArchiveDays`：只在 Slack 里说话的会话空闲多少天后自动归档，停在 block（等人）的也归档（默认 3，0 为不按这条归档）；在跑、有 job、被固定或保留的照旧不动，Slack 里有人再说话就回来。
- `archivedWorkspaceDays`：会话归档多少天后清掉它的工作区（默认 7，0 为一直保留）：只留聊天里发过的文件（`uploads/`），其余的连同归档压缩包一起删掉，执行历史和聊天记录不动；再打开的会话从空工作区接着做。按归档时间算，再次归档重新计时；在跑、有 job 或别的会话还在用这个目录的不动。station 数据所在的盘剩不到 20G 时不等满天数：先删别的 station 的任务留下的、不在用的目录副本，还不够就按归档时间从早到晚提前清，直到剩够 20G；设成 0 的不清。
- 账号的 `home` 相对数据目录。用订阅登录时，对这个目录登录一次：`CLAUDE_CONFIG_DIR=<home> claude`，或 `CODEX_HOME=<home> codex login`。
- `env` 里的 `{route}` 会替换成每个会话的路由 ID（Codex 的 app-server 按账号共享，替换成账号 ID），用于 OpenCode Go 这类需要会话亲和头的服务。
- 账号的 `access` 决定运行时怎么接模型：`subscription`（订阅登录）、`opencode-go`、`anthropic-api`（后两种要 `key`）、`api-provider`（用 `provider` 指定服务商，如 `openai`、`deepseek`、`openrouter`、`azure-openai`、`custom`，再加 `key`；Azure OpenAI、Cloudflare、`custom` 还要 `endpoint`，`custom` 的 key 可省），或 `env`（只用 `env` 里手写的变量）。`api-provider` 按服务商目录里的协议决定能跑什么：有 Anthropic 接口的跑 Claude Code，有 Responses 接口的跑 Codex，有 Chat Completions 接口的可用于自动决策；只有 Chat Completions 的服务商不跑任何运行时，`runtimes` 为空。旧版 still.fail 读到 `api-provider` 的账号会显示成 `env`。still.fail 据此生成环境变量；Codex 的服务商配置在启动 app-server 时用 `-c` 传入，不改 `config.toml`。
- `telemetry.errors` 打开后，这台 station 的错误（不带内容）上报到 still.fail 的 PostHog 项目，默认关闭，见 [telemetry.md](telemetry.md)。
- 共享的记忆和 skills 在 `<数据目录>/agent/`（`MEMORY.md` 和 `skills/`），启动时链接进每个账号的配置目录。

## 会话方式

- **多会话**（`multi-session`）：每个 thread 一个会话。在 thread 里 @ 它开始，之后这个 thread 的回复都进这个会话；私聊直接开会话。
- **单会话**（`single-session`）：这个连接看到的所有 thread 进同一个会话。`requireMention: true`（默认）时，被 @ 的 thread 才会进来，进来之后的回复不用再 @；`false` 时它能看到的每条消息都进来。

两种方式下，agent 收到的每条消息都带着来源（`thread="频道/thread_ts"`），回复时必须用 `to=` 指明发到哪个 thread，没有默认位置。这样一个会话以后换绑到别的连接，行为也不变。

## 在 Slack 里使用

- `@名字 <任务>`：开始一个会话（单会话连接则把这个 thread 带进它的会话）。
- 同一个 thread 里可以 @ 多个连接，它们各自有独立的会话。
- Slack 的运行状态条可点停止：只中断点中的 bot 在这个 thread 的当前 turn；真正结束后 station 说「已停止当前任务」。新 Slack app 自带此事件订阅；已有 app 在连接拥有者配置了可管理该 app 的 Slack 配置 token 后由 station 自动加上。也可以在连接页保存 app 设置时加上。
- `-stop`：中断当前 turn；同一 thread 有多个代理时，它们都会收到停止请求。
- `-compact`：在两轮之间压缩 agent 的上下文（Claude Code 的 `/compact`、Codex 的 `thread/compact/start`），完成后 station 在 thread 里说一声。
- `-clear`：在两轮之间清空上下文：进程结束，下一条消息开始新的 runtime 会话；之前的会话仍在执行历史里。
- 这两件事在 still.fail 的 agent 卡片（手机）和会话详情（桌面）里也能点。
- agent 的消息以 `markdown` 块发出：Slack 照 still.fail chat 的 Markdown 画（粗体、链接、多级列表、标题、表格、带语言的代码块），agent 不再写 mrkdwn；@人仍是 `<@USER_ID>`。消息的 `text` 是同一段原文，通知和读回历史用它。
- 问题卡片（chat_post 的 `card`，`options` 或 `text`）：一条消息，正文下面是单选（推荐的排最后、默认选中，`detail` 是选项下的灰字；有一项超过 75 字时，全部选项连同说明列在正文后，单选里只留标题）加「确定」；文字卡片（`text`）不放输入框，正文上面是标题「✍️ 需要你回答」，下面一行「在这个线程里回复作答」（有 placeholder 时跟在后面），在 thread 里回复就是回答。按下后经 Socket Mode 的 `interactive` 信封送来（不需要公网地址），当作这个人在 thread 里说了选中的标签（addressed，ts 是这次操作的 `action_ts`），卡片改成「✓ 谁 回答：什么」不再能点；没选就按、或卡片已答过，只回一条他自己看得到的消息。app 要打开 interactivity：新建的 app 自带，旧 app 在连接页保存一次设置就会加上。login 卡片不在 Slack 里出。
- agent 一轮结束在 all_done 或 need_human 时，thread 末尾用一行灰色小字（`context` 块）说它现在的状态，和 still.fail 对话末尾那行一样：「✓ 已完成：…」或「🔔 需要你处理：…」。最后一条是 bot 自己的消息时，用 `chat.update` 加在那条下面，不发新消息，跟这个 thread 的人不会再收到一次通知；最后一条是别人的（agent 这轮没说话）时，单独发一条只有这行字的消息。thread 里最多留一行：agent 再开始干活，或者一轮以等待、出错、停下结束，这行就去掉（改回原消息，或删掉那条单独的消息）。最后一条是还没回答的问题卡片时，need_human 不再加这行。station 重启后不记得上一行加在哪，旧的那行会留着。

## 开发

- station：在 station/ 里 `pnpm test`、`pnpm exec tsgo --noEmit`；它的原生部分（station/native/*）在各自目录里 `cargo test`。
- client core（TypeScript）：在 client/core-ts 里 `pnpm test`、`pnpm exec tsgo --noEmit`；core 的原生壳（client/shell、client/iroh-wasm）：在 client/ 里 `cargo test --workspace`。
- `pnpm test`（web 里的 TypeScript 部分，需要先构建 iroh wasm）、`pnpm typecheck`。
- `pnpm check`：跑全部检查（scripts/check.sh all）。
- `pnpm dev:web`：still.fail cloud 网页版（`--mode cloud`）的热更新开发服务器。

## CI

`.github/workflows/pipeline.yml` 使用 AFK-surf 的 CI 资源：计划/API/put/changelog/计时和 Linux 检查（check-linux）在 GitHub 自带的 ubuntu-24.04（公开仓库免费），不用 Blacksmith（2026-10-15 用户定）；网页构建部署、分支的打包演练和 Mac 测试版打包签名在 GitHub 的 Linux 和 macos-26 runner；Android 发布在 mini1；完整检查（2026-10-03 起）和 station 打包签名在 `[self-hosted, mini1]` Mac（M4 10 核，编译缓存在本机：4 核的 Blacksmith 上一次要 9 分钟）。完整检查是一个 job（2026-10-04 起；之前按 `STILLFAIL_CHECK_PART` 拆成 ts、station、core、android 四个 job，三个 runner 不够分、每个还要 ~10 秒准备），`scripts/check.sh` 在里面让各步并排跑（要编译的 Rust、安卓两类步骤等其余步骤跑完再开始，免得按真实时间跑的测试被挤得超时），Rust 每一步用自己的临时 Cargo target（`$RUNNER_TEMP/target` 下），经 sccache 编译，跨 job 保留的只有 sccache 的缓存（`~/stillfail-ci/sccache`，上限 25G）。不要再在 runner 之间共享 target：三个 runner 的检出路径不同，vendor 里的 iroh（lib + cdylib，.dylib 不带 hash）每个路径编一份，加上不同分支、不同特性的构建堆在一起，rustc 会拿错（E0308「multiple different versions of crate iroh_relay」，2026-10-02、03 反复出现，去掉 kache、按依赖指纹分目录都没根治）。上传 R2 遇到 Cloudflare 的 502、fetch failed 会自己重试两次。Linux 工具链由 `.github/actions/setup` 安装并缓存；Mac 使用 `.github/actions/setup-mac` 接入 mini1 既有工具链。原生部分（station 的 mesh 插件/启动器/runner、网页的 iroh wasm、安卓的 shell 和引擎）预编译（`scripts/native.ts`，见 development.md「Native parts」）：`natives` job 在 mini1 上按源码算 key，GitHub release `native-artifacts` 里没有的才编，main 上传上去、分支只作本次运行的 artifact 传给后面的 job；检查、网页构建、Android 和桌面都不再编 Rust（只有 Rust 自己的测试在它的源码变了时才编）。只有 Studio 自更新经 mini1 执行；构建签名不再 SSH 到 Studio。macOS 的签名身份写在 `.github/mac_signing.py`（`identity`），桌面 app 和 station 原生部分共用它：production 的 MACOS_DEVELOPER_ID_KEYCHAIN_B64_1 / _2（AFK 的 keychain 文件分两半，从 Cue 仓库拷来）用 KEYCHAIN_PASSWORD_AFK 打开，复制一份放进搜索列表，结束后删除；里面有 `Developer ID Application: AFK AI, Inc. (D9AAN3VJK8)` 和 notarytool 的凭据。Cue 那边换了凭据要重新拷。身份是 Developer ID 时，桌面 app 在打 zip 前公证（票据不装订进 app），下载后 Gatekeeper 可在线验证。已装的 app 只接受满足它自己 designated requirement 的更新：认的是 AFK 的 team（D9AAN3VJK8，当初 Electron 版定下的，mbui 的 app 照样签），证书续期不影响更新。2026-10-20 到 10-21 用旧 Apple Development 证书签、requirement 同时认两者的过渡版把已装的 app 带了过来；更早的版本要手动重装一次。身份缺失则拒绝发包。

安卓、Mac、Windows 的正式版和测试版都是 `apps/mbui` 构建的（apps/mbui/README.md「Which app is built」）。此外 main 上每次推送都出一个 still.fail mbui（`fail.still.mbui`，和正式版、测试版并排装的开发版），不在 pipeline 里：`.github/workflows/mbui.yml` 在 GitHub 的 runner 上自己跑（`apps/mbui/scripts/beta.sh`），main 每次改到它的来源（`apps/mbui/`、`client/`、`media/`、`vendor/`、`scripts/native.ts`）就构建、用安卓的发布 key（`ANDROID_DEBUG_KEYSTORE_B64`）签名、放进 R2（`android/stillfail-mbui-<n>.apk`），从线上地址取回核对大小和 SHA-256 之后才写 feed `android/mbui/latest.json`；下载 `/releases/latest/android-mbui`（Mac、Windows、Linux 是 `mac-mbui`、`win-mbui`、`linux-mbui`）。它不等 pipeline 的检查（用户定：测试 app 不被测试挡），pipeline 也不等它、不因它失败；分支只构建不发。mbui 框架本身在本仓库的 `apps/mbui/mbui`（2026-10-21 从 zzj3720/mbui 连历史并进来，不再钉提交）。

- **分支**：每次 push 跑完整检查（`scripts/check.sh full <merge-base>..HEAD`），并把改到的部分构建、打包一遍（`deploy.py --dry-run`，不部署、不读密钥）。结果当合并的证据，不卡合并。
- **main**：检查上次部署（tag `deployed/beta`）以来改到的部分，过了就按顺序部署改到的：先 api（stillfail-cloud，正式环境，只有一份），再 web-beta（app.youdid.wtf）、admin、preview、site-beta（youdid.wtf），以及测试通道的 station 发布包（`.github/release.sh station`：TypeScript station 加它的 Node 和原生部分，三个平台，传完让 studio 的 station `stillfail update`，经 mini1 到 studio 的 ssh）、Mac 测试版（2026-10-26 起是 mbui 的 app 顶替 Electron 的：`.github/release-desktop.py` 跑 `scripts/release.sh --beta desktop`，在 GitHub 的 macos-26 runner 上构建、用原签名身份签名并公证、验证是 Electron 那个 app 的 id 和我们的 team 后上传；改了 mbui 的 app 就发，同一个 zip 写进 mbui 自己的更新源 `mac/beta/latest.json` 和 Electron 的 `desktop/stillfail-beta-mac.yml`，已装的 Electron 版点「更新」就换成它，数据、登录、密钥照旧）、Windows 测试版（同日起也是 mbui 的：desktop-win job 在 GitHub 的 Windows runner 上跑 `scripts/release.sh --beta desktop-win`，安装包签 `.sig`，写进 `win/beta/latest.json` 和 Electron 的 `desktop/stillfail-beta.yml`）和安卓测试版（`.github/release.sh android`，用 secret `ANDROID_DEBUG_KEYSTORE_B64` 里 studio 的那把 key 签，不能换）。哪一步不过，后面的都不发（api 和网页只等跟它们有关的检查，不等安卓的，2026-10-17 起）；全部发完才把 `deployed/beta` 挪到这个提交，所以被取消或失败的那次，改动会算进下一次。relay 改了只在 Actions 里给个警告，不自动部署（会断所有连接）。
- **正式版手动一键发布**：在 GitHub Actions 的 **Publish stable → Run workflow**，选择 main，revision 留空即可。它选择最新已审核的 `docs/releases/0.1.<n>.md` 对应提交；也可填写完整 main SHA。该提交必须包含本版本日志、已通过 main pipeline 且保留网页 artifact（90 天），否则在发布前停止。先构建签名正式 Android、Mac（mini1 上）和 Windows（GitHub 的 Windows runner 上），都是 mbui 的，同测试版；再将同一提交的原网页 artifact 转正，最后从该提交构建三个平台的正式 station。各端全部成功才移动 `deployed/stable`；不自动更新用户的 station。测试版继续随 main 自动发布，正式版没有 push 触发器。失败后可用相同 SHA 重跑；已发布到更新正式版后不能借此回退旧版。
- **仍手动处理**：relay 用 studio 的部署入口（会断开连接）；正式官网 `deploy.py site`。旧 `ember-promote` 仅为运维入口，日常正式发布使用上述 workflow。
- **密钥**：GitHub 的 Environment `production`（只有 main 能用），secret 是部署目录各文件的内容：`DEPLOY_KEYS_JSON`（keys.json）、`GOOGLE_OAUTH_JSON`、`AXIOM_JSON`、`FCM_SERVICE_ACCOUNT_JSON`、`APNS_JSON`（apns.json）、`POSTHOG_JSON`、`VAPID_JSON`（还没有）、`CLOUDFLARE_API_TOKEN`（GitHub-hosted 部署必须配置）。`.github/deploy.sh` 每次把它们写进临时部署目录，用完就删。换密钥：改 studio `~/ember-deploy` 里的文件，再 `gh secret set <名字> --env production < 文件`。
- **自托管 runner 跑什么**：完整检查（分支和 main）、station 和正式版桌面的打包签名、经 SSH 让 Studio 更新到刚发布的 station 包。pipeline 只由仓库成员的 push 触发（`plan` 只认本仓库的 push 和手动触发，不接 pull_request），外部贡献的代码不会在 mini1 上跑；带密钥的发布任务仍只在 main 的 production 环境里。
- **main 有保护**（2026-10-20 起）：谁都不能直接推 main，改动一律走 PR；PR 要 pipeline 的 `gate` 通过才能合；管理员可以越过（`gh pr merge --admin`，2026-10-22 起），只在要紧的时候用。`gate` 汇总分支上跑的每个 job，跳过的算过，失败或取消的算挂；给分支加了新 job，要同时加进 `gate` 的 `needs`。
- **加 runner / 重新注册**：在 mini1 上 `gh api -X POST repos/AFK-surf/still.fail/actions/runners/registration-token --jq .token` 拿 token，在新目录里解开 actions-runner-osx-arm64，`./config.sh --unattended --url https://github.com/AFK-surf/still.fail --token <token> --name mini1-<n> --labels mini1`，`./svc.sh install && ./svc.sh start`。每个 runner 的 `.env` 里加 `ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE=$HOME/stillfail-ci/action-archives`（写展开后的路径，改完 `./svc.sh stop && ./svc.sh start`）：job 用到的 action 从这里拷，不再每个 job 经代理下载一遍；`.github/actions/setup-mac` 每小时最多补一次新提交的包（`.github/action-archives.sh`）。
- 看结果：`gh run list -R AFK-surf/still.fail -w pipeline`（mini1 上有 gh 登录）。
