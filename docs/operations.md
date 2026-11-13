# 运行 still.fail

## 安装与启动

从源码搭建隔离开发环境见 [development.md](development.md)。正式使用时，在 [still.fail web](https://app.still.fail) 的 workspace 设置里添加 station，按页面生成的一次性命令安装并加入 workspace。安装器把发布包放到 `~/.stillfail/app`，把 `stillfail` 链接进 `~/.local/bin`，并注册用户服务（macOS 用 launchd，Linux 用 systemd）。`stillfail update` 更新发布包，`stillfail status` 查看绑定与连接状态。

station 必须加入 workspace 才接 Slack、运行 agent。数据默认在 `~/.stillfail`（`STILLFAIL_DATA` 可改）。开发测试使用独立数据目录，不使用已有真实会话的 station。

查内存：station 每 10 分钟在日志里记一行 `memory: now`（主线程的 heap、external，各读取线程的 heap）。`stillfail heap` 让运行中的 station 把主线程的堆快照写到 `<数据目录>/run/heap-*.heapsnapshot`（只留最新一份，0600：里面有 station 持有的 token），用 Chrome DevTools 的 Memory 打开；写的几秒里 station 不响应（station/src/ops/heap.ts）。macOS 上看进程占用以 footprint 为准（`footprint -p <pid>`），RSS 含共享库。

更新支持原地交接：启动器（station/native/launcher，pid 不变）收到 SIGUSR2，在旁边起新版本的 Node 进程，新的就绪后放掉旧的，轮次、运行时和 job 不断（station/native/launcher/src/run.rs、station/src/ops/launcher.ts）；不支持交接的旧版本（Rust station），安装器会先排空再重启。

## 管理界面

管理 station 从 workspace 内进入，通过客户端 core 与 station 建立带成员凭证的连接。本机旧管理端口 4760 仅重定向到 cloud，已经不再提供独立管理页；4750 是 agent MCP 端点，不要对公网暴露。这两个端口都默认只监听本机，实际端口以 station 的运行记录为准。

下面的配置与会话说明包含旧版本兼容字段。新安装使用 workspace 设置管理连接、账号和 station。

## config.json

也可以直接编辑，格式如下（改完需要重启 still.fail）：

```json
{
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
- `sandboxes`：托管重任务的沙箱，`[{ "name": "l4es-large", "target": "{name}.team@l4es.afk.surf", "size": "large" }]`。每一项是 `station_list` 里一个可排任务的目标，`station_task` 的 station 填它的 `name`，任务在这个对话自己的沙箱里跑（第一次用时建，闲置后由沙箱服务删除），沙箱里不用装任何东西，有 node 就行。`target` 是沙箱服务的入口，`{name}` 处会换成每台沙箱的名字；`size` 是服务方提供的规格，省略用默认；`identity` 是登录用的私钥路径，省略时用 station 自己生成的 `<数据目录>/run/sandbox/id_ed25519`（第一次用时沙箱服务若要求绑定这把 key，绑定链接会出现在任务日志里）。
- `telemetry.errors` 打开后，这台 station 的错误（不带内容）上报到 still.fail 的 PostHog 项目，默认关闭。
- 共享的记忆和 skills 在 `<数据目录>/agent/`（`MEMORY.md` 和 `skills/`），启动时链接进每个账号的配置目录。

## 会话方式

- **多会话**（`multi-session`）：每个 thread 一个会话。在 thread 里 @ 它开始，之后这个 thread 的回复都进这个会话；私聊直接开会话。
- **单会话**（`single-session`）：这个连接看到的所有 thread 进同一个会话。`requireMention: true`（默认）时，被 @ 的 thread 才会进来，进来之后的回复不用再 @；`false` 时它能看到的每条消息都进来。

两种方式下，agent 收到的每条消息都带着来源（`thread="频道/thread_ts"`），回复时必须用 `to=` 指明发到哪个 thread，没有默认位置。这样一个会话以后换绑到别的连接，行为也不变。

## 在 Slack 里使用

- `@名字 <任务>`：开始一个会话（单会话连接则把这个 thread 带进它的会话）。
- 同一个 thread 里可以 @ 多个连接，它们各自有独立的会话。
- Slack 的运行状态条可点停止：只中断点中的 bot 在这个 thread 的当前 turn；真正结束后 station 说「已停止当前任务」。新 Slack app 自带此事件订阅；已有 app 在连接拥有者配置了可管理该 app 的 Slack 配置 token 后由 station 自动加上。也可以在连接页保存 app 设置时加上。
- 让 agent 别再跟某个 thread（例如说「别跟了」）：它回一句，然后调 `chat_leave` 离开这个 thread。之后这里的消息照样记下，但不再交给它；有人再 @ 它，它就回来，之后的回复又都能收到。它仍能读这个 thread、在里面发消息。离开后，Slack thread 末尾那行灰色小字会写「🔕 已退出这个 thread，@ 我即可回来」（下面讲 thread 末尾状态的那条），一看就知道它不再跟；被 @ 回来开始干活时这行就去掉。飞书没有这行。still.fail 自己的对话不能这样离开。
- `-stop`：中断当前 turn；同一 thread 有多个代理时，它们都会收到停止请求。
- `-compact`：在两轮之间压缩 agent 的上下文（Claude Code 的 `/compact`、Codex 的 `thread/compact/start`），完成后 station 在 thread 里说一声。
- `-clear`：在两轮之间清空上下文：进程结束，下一条消息开始新的 runtime 会话；之前的会话仍在执行历史里。
- 这两件事在 still.fail 的 app 里也能点。
- agent 的消息以 `markdown` 块发出：Slack 照 still.fail chat 的 Markdown 画（粗体、链接、多级列表、标题、表格、带语言的代码块），agent 不再写 mrkdwn；@人仍是 `<@USER_ID>`。消息的 `text` 是同一段原文，通知和读回历史用它。
- 问题卡片（chat_post 的 `card`，`options` 或 `text`）：一条消息，正文下面是单选（推荐的排最后、默认选中，`detail` 是选项下的灰字；有一项超过 75 字时，全部选项连同说明列在正文后，单选里只留标题）加「确定」；文字卡片（`text`）不放输入框，正文上面是标题「✍️ 需要你回答」，下面一行「在这个线程里回复作答」（有 placeholder 时跟在后面），在 thread 里回复就是回答。按下后经 Socket Mode 的 `interactive` 信封送来（不需要公网地址），当作这个人在 thread 里说了选中的标签（addressed，ts 是这次操作的 `action_ts`），卡片改成「✓ 谁 回答：什么」不再能点；没选就按、或卡片已答过，只回一条他自己看得到的消息。app 要打开 interactivity：新建的 app 自带，旧 app 在连接页保存一次设置就会加上。login 卡片只在 Slack 里出一种：这台 station 上、等着填登录页给的码的登录（login 工具的 `paste`；2026-11-03 Peng Xiao 定：原来让人把码贴进 thread，链接打开的卡片又不在了，看起来像没发起登录）。消息是正文（登录链接）、一个直接打开登录页的按钮「打开 <域名> 登录」、一个输入框「登录页给的码」和「提交」按钮；按下提交后码只交给这个登录的命令（核对这条消息确实是这个登录的卡片），不作为 thread 里的消息记下，卡片改成「✓ 谁 已填码，正在校验」；没填、或登录已结束，只回一条他自己看得到的消息。设备码登录（gh、docker）也出卡片：正文、码和打开验证页的按钮，没有输入框（2026-11-06 Peng Xiao 定：原来要先打开整个 still.fail 网页版才拿到登录页，太慢；station 对 workspace 公开，频道里的人就是同一团队，码放在 thread 里不比放在 station 页上更公开）。卡片结束时按钮和码一起去掉，只留正文。频道和别的组织共享（Slack Connect，`conversations.info` 的 `is_ext_shared`，查不到也按共享算）时不放登录页和码：贴码型只有输入框，设备码型只有正文的链接。回环登录和别的 station 的登录在 Slack 里仍只发链接；飞书只发链接。
- agent 一轮结束在 all_done 或 need_human 时，thread 末尾用一行灰色小字（`context` 块）说它现在的状态，和 still.fail 对话末尾那行一样：「✓ 已完成：…」或「🔔 需要你处理：…」；它在这一轮离开了这个 thread（`chat_leave`）时，不管这一轮怎么结束，都写「🔕 已退出这个 thread，@ 我即可回来」。最后一条是 bot 自己的消息时，用 `chat.update` 加在那条下面，不发新消息，跟这个 thread 的人不会再收到一次通知；最后一条是别人的（agent 这轮没说话）时，单独发一条只有这行字的消息。thread 里最多留一行：agent 再开始干活，或者一轮以等待、出错、停下结束，这行就去掉（改回原消息，或删掉那条单独的消息）。最后一条是还没回答的问题卡片时，need_human 不再加这行。station 重启后不记得上一行加在哪，旧的那行会留着。

## 开发

- station：在 station/ 里 `pnpm test`、`pnpm exec tsgo --noEmit`；它的原生部分（station/native/*）在各自目录里 `cargo test`。
- client core（TypeScript）：在 client/core-ts 里 `pnpm test`、`pnpm exec tsgo --noEmit`；core 的原生壳（client/shell、client/iroh-wasm）：在 client/ 里 `cargo test --workspace`。
- `pnpm test`（根目录 `test/` 里的测试，需要先构建 iroh wasm）、`pnpm typecheck`。
- `pnpm check`：跑全部检查（scripts/check.sh all）。
- `pnpm dev:web`：still.fail cloud 网页版（`--mode cloud`）的热更新开发服务器。

## CI

`.github/workflows/pipeline.yml` 使用 AFK-surf 的 CI 资源：计划/API/put/changelog/计时和 Linux 检查（check-linux）在 GitHub 自带的 ubuntu-24.04（公开仓库免费），不用 Blacksmith（2026-10-15 用户定）；网页构建部署、分支的打包演练和 Mac 测试版打包签名在 GitHub 的 Linux 和 macos-26 runner；Android 发布、完整检查和 station 打包签名在自托管 Mac runner。station 的测试（`station/test`）不在自托管 Mac 上跑：分 6 片，各在一台 GitHub 的 ubuntu-24.04 上跑（`check-station`，2026-11-10 起；那台 Mac 上四个 runner 共用一台机器，三个检查同时跑就超过 5 分钟），Mac 上只留只有 Mac 能跑的那几条（Rust station 的归档命令）。Mac 上的完整检查是一个 job，`scripts/check.sh` 在里面让各步并排跑（要编译的 Rust、安卓两类步骤等其余步骤跑完再开始，免得按真实时间跑的测试被挤得超时），Rust 每一步用自己的临时 Cargo target（`$RUNNER_TEMP/target` 下），经 sccache 编译，跨 job 保留的只有 sccache 的缓存（`~/stillfail-ci/sccache`，上限 25G）。不要再在 runner 之间共享 target：三个 runner 的检出路径不同，vendor 里的 iroh（lib + cdylib，.dylib 不带 hash）每个路径编一份，加上不同分支、不同特性的构建堆在一起，rustc 会拿错（E0308「multiple different versions of crate iroh_relay」，2026-10-02、03 反复出现，去掉 kache、按依赖指纹分目录都没根治）。上传 R2 遇到 Cloudflare 的 502、fetch failed 会自己重试两次。Linux 工具链由 `.github/actions/setup` 安装并缓存；Mac 使用 `.github/actions/setup-mac` 接入 runner 既有工具链。原生部分（station 的 mesh 插件/启动器/runner、网页的 iroh wasm、安卓的 shell 和引擎）预编译（`scripts/native.ts`）：`natives` job 按源码算 key，GitHub release `native-artifacts` 里没有的才编，main 上传上去、分支只作本次运行的 artifact 传给后面的 job；检查、网页构建、Android 和桌面都不再编 Rust（只有 Rust 自己的测试在它的源码变了时才编）。构建签名在 CI 中进行。macOS 的签名身份写在 `.github/mac_signing.py`（`identity`），桌面 app 和 station 原生部分共用它：production 的 MACOS_DEVELOPER_ID_KEYCHAIN_B64_1 / _2（AFK 的 keychain 文件分两半，从 Cue 仓库拷来）用 KEYCHAIN_PASSWORD_AFK 打开，复制一份放进搜索列表，结束后删除；里面有 `Developer ID Application: AFK AI, Inc. (D9AAN3VJK8)` 和 notarytool 的凭据。Cue 那边换了凭据要重新拷。身份是 Developer ID 时，桌面 app 在打 zip 前公证（票据不装订进 app），下载后 Gatekeeper 可在线验证。已装的 app 只接受满足它自己 designated requirement 的更新：认的是 AFK 的 team（D9AAN3VJK8，当初 Electron 版定下的，mbui 的 app 照样签），证书续期不影响更新。身份缺失则拒绝发包。

安卓、Mac、Windows 的正式版和测试版都是 `apps/mbui` 构建的（apps/mbui/README.md「Which app is built」）。此外 main 上每次推送都出一个 still.fail preview（`fail.still.mbui`，和正式版、测试版并排装的预览版），只有 Windows 和 Linux（Linux 只有这个通道；安卓和 Mac 的预览版 2026-11-03 起不再构建，测试版就是它们的测试通道），不在 pipeline 里：`.github/workflows/preview.yml` 在 GitHub 的 runner 上自己跑（`apps/mbui/scripts/beta.sh`），main 每次改到它的来源（`apps/mbui/`、`client/`、`vendor/`、`scripts/native.ts` 等，见 workflow 的 `paths`）就构建、签名、放进 R2（`win/stillfail-mbui-<n>-x64-win.exe`、`linux/stillfail-mbui-<n>-<arch>-linux.tar.gz`），从线上地址取回核对大小和 SHA-256 之后才写 feed `win/mbui/latest.json`、`linux/mbui/latest.json`；下载 `/releases/latest/win-mbui`、`linux-mbui`、`linux-arm64-mbui`。feed 和 app id 还叫 mbui：装着的预览版靠它们更新。它不等 pipeline 的检查（用户定：测试 app 不被测试挡），pipeline 也不等它、不因它失败；分支只构建不发。mbui 框架本身在本仓库的 `apps/mbui/mbui`（2026-10-21 从 zzj3720/mbui 连历史并进来，不再钉提交）。

- **分支**：每次 push 跑完整检查（`scripts/check.sh full <merge-base>..HEAD`），并把改到的部分构建、打包一遍（`deploy.py --dry-run`，不部署、不读密钥）。PR 要其中的 `gate` 通过才能合（见下面「main 有保护」）。
- **main**：检查上次部署（tag `deployed/beta`）以来改到的部分，过了就按顺序部署改到的：先 api（stillfail-cloud，正式环境，只有一份），再 web-beta（app.youdid.wtf）、admin、preview、site-beta（youdid.wtf），以及测试通道的 station 发布包（`.github/release.sh station`：TypeScript station 加它的 Node 和原生部分，三个平台，传完按配置更新测试 station）、Mac 测试版（2026-10-26 起是 mbui 的 app 顶替 Electron 的：`.github/release-desktop.sh` 跑 `scripts/release.sh --beta desktop`，在 GitHub 的 macos-26 runner 上构建、用原签名身份签名并公证、验证是 Electron 那个 app 的 id 和我们的 team 后上传；改了 mbui 的 app 就发，同一个 zip 写进 mbui 自己的更新源 `mac/beta/latest.json` 和 Electron 的 `desktop/stillfail-beta-mac.yml`，已装的 Electron 版点「更新」就换成它，数据、登录、密钥照旧）、Windows 测试版（同日起也是 mbui 的：desktop-win job 在 GitHub 的 Windows runner 上跑 `scripts/release.sh --beta desktop-win`，安装包签 `.sig`，写进 `win/beta/latest.json` 和 Electron 的 `desktop/stillfail-beta.yml`）和安卓测试版（`.github/release.sh android`，用 secret `ANDROID_DEBUG_KEYSTORE_B64` 里的 key 签，不能换）。哪一步不过，后面的都不发（api 和网页只等跟它们有关的检查，不等安卓的，2026-10-17 起）；全部发完才把 `deployed/beta` 挪到这个提交，所以被取消或失败的那次，改动会算进下一次。relay 改了只在 Actions 里给个警告，不自动部署（会断所有连接）。
- **正式版手动一键发布**：在 GitHub Actions 的 **Publish stable → Run workflow**，选择 main，revision 留空即可。它按 main 上最新已审核的 `docs/releases/0.1.<n>.md` 选提交（`.github/stable-plan.py`）。正式版发的是前一天的 main（在测试版上跑满一天）加当天提交里写了 `Stable: yes` 的严重修复（用户定，2026-11-09）：
  - 没有严重修复：n 是 main 上那个基础提交的提交数，日志之后再合进 main，不在那个提交里。它得有跑通的 main pipeline；这次 pipeline 留了网页 artifact（90 天）就原样转正，没有（那次没改网页）就在本 workflow 里从该提交构建网页。
  - 有严重修复：从基础提交拉 `release/<日期>` 分支，cherry-pick 修复，日志提交在分支上（抬头加 `base: <基础的提交数>`、`branch: release/<日期>`），n 是分支的提交数，可以和 main 上某个提交同号（用户定，2026-11-09）；同一份日志也合进 main。分支的 pipeline 跑通后发它的最新提交，网页在本 workflow 里构建（它没上过测试版）。cherry-pick 改到原生部分的话，正式版构建拿不到它的预编译件，会失败。
  - 也可以填完整 SHA（main 上的基础提交，或日志指定分支的最新提交）。版本号必须比上一个正式版大（不然 station 和 app 不会更新），基础不能比上一个正式版的基础旧。
  先构建签名正式 Android、Mac（自托管 runner 上）和 Windows（GitHub 的 Windows runner 上），都是 mbui 的，同测试版；再发网页，最后从该提交构建三个平台的正式 station。各端全部成功才移动 `deployed/stable`；不自动更新用户的 station。测试版继续随 main 自动发布，正式版没有 push 触发器。失败后可用相同 SHA 重跑；已发布到更新正式版后不能借此回退旧版。
- **增量更新（delta）**：各平台的 app 和 station 更新时，若 feed 里有从它正在跑的版本出发的 delta，就只下载 delta，在本机用已装的文件拼出新包（核对的还是 feed 或签名里写的哈希）；没有或出任何错都照旧下载整包，所以 delta 是可有可无的，生成失败从不挡发布（只记一条 warning）。delta 由 `scripts/release-deltas.ts` 在发布时生成：以发布时线上那个 feed 的版本、以及它的 delta 来自的更早版本为底（最多 10 个，被清掉的跳过），不到整包 80% 的才留下。main 上是 pipeline 的 `deltas` job（每个部分一台 Linux runner，在检查旁边跑，做好的 delta 先上传，改过的 feed 交给 `put`）；正式版和 preview 由各自直接写 feed 的地方顺带生成（`scripts/release.sh` 的 `put_feed`、`.github/release-desktop.sh`、`beta.sh publish`，Windows 正式版在 `desktop-win-feeds` job）。Windows 安装包旁边会多一个 `<exe>.raw.zst`（`--raw` 出的未压缩安装包，签名里写着它的哈希），station 的每个发布包另存一份 `station/archive/<通道>/<build>-<sha256>-<平台>`，供以后的版本做底；`scripts/release-prune.ts` 留下每个 feed 自己的包和它的 delta 来自的包，其余的删掉。看生成了什么：job 的 summary 里每个 feed 一行（`deltas: mac/beta 8147: from 8146 1.8 MB, …; package 24.9 MB`），或直接看 feed 里的 `deltas`。
- **安卓崩溃的符号**：PostHog 里安卓 app 的原生崩溃（`$exception`，一段 tombstone 文本）只给出 `libmbui.so` 里的地址（APK 里的库去了符号）。每次 still.fail 自己的安卓发布（测试版和正式版，monoid 的不存）在构建时从链接出来、还没去符号的库写出它的函数符号，存进发布桶的 `symbols/android/<APK 名去掉 .apk>.syms.xz`（如 `symbols/android/stillfail-beta-8300.syms.xz`、正式版 `symbols/android/stillfail-8300.syms.xz`），不对外提供下载，放满 30 天由 `scripts/release-prune.ts` 删掉；写不出或传不上只记一条 warning，不挡发布。崩溃报告里的版本号 0.1.<n> 就是 APK 名里的 n。在登录了 Cloudflare 的机器上：`node scripts/crash-symbols.ts --fetch stillfail-beta-8300 tombstone.txt`（tombstone 省略则读标准输入），每个 `libmbui.so` 帧后面补上 `函数名+0x偏移`；已有符号文件时把 `--fetch <名>` 换成文件路径。
- **仍手动处理**：relay 用部署脚本（会断开连接）。正式官网随上述正式版 workflow 一起发布。
- **密钥**：GitHub 的 Environment `production`（只有 main 能用），secret 是部署目录各文件的内容：`DEPLOY_KEYS_JSON`（keys.json）、`GOOGLE_OAUTH_JSON`、`GCP_TELEMETRY_JSON`（Google Cloud 项目 `cueboard-gamma-prod` 里写 traces 和日志的 service account 的 JSON key，角色 `roles/telemetry.writer`；traces 在 Cloud Trace，日志在 Cloud Logging）、`FCM_SERVICE_ACCOUNT_JSON`、`APNS_JSON`（apns.json）、`POSTHOG_JSON`、`VAPID_JSON`（还没有）、`CLOUDFLARE_API_TOKEN`（GitHub-hosted 部署必须配置）。`.github/deploy.sh` 每次把它们写进临时部署目录，用完就删。换密钥：将新的值写入对应的 GitHub Environment secret。
- **monoid 的 cloud**（2026-11-04 起）：同一份代码在公司的 Cloudflare 账号（AFK.Surf）里另部署一套，正式地址 monoid.build，测试通道 monoid.zone（同 youdid.wtf 之于 still.fail：同一个 API、同一套账号）。账号和 still.fail 不通、不迁移。`STILLFAIL_CLOUD=monoid` 时 `deploy.py` 把各部分的 still.fail 域名换成 monoid 的、去掉 3720.org 的旧路由，部署目录默认 `~/monoid-deploy`。main 的 pipeline 在 still.fail 的 api、static 之后跑 `monoid-api`、`monoid-static`（不发官网）；正式版的网页转正同时转 monoid 自己那份构建。中继和第一次部署手动跑 Actions 的 **monoid** workflow。密钥：production 里的 `MONOID_CLOUDFLARE_API_TOKEN`、`MONOID_DEPLOY_KEYS_JSON`（备份在用户密钥库「monoid cloud 部署密钥」），Google 登录用 `MONOID_GOOGLE_OAUTH_JSON`（缺省回退 still.fail 的）；Android 推送用公司 Firebase 项目 `monoid-build`，正式版和测试版分别注册应用，发送凭据为 `MONOID_FCM_SERVICE_ACCOUNT_JSON`。iOS 推送用 `MONOID_APNS_JSON`（`{keyId, teamId, key, topic:"build.monoid.iphone"}`），APNs key 必须允许该 topic 和 production 环境；PostHog 和 Google Cloud 的 telemetry 仍用 still.fail 的。
- **iOS TestFlight**：手动运行 `mbui-testflight.yml` 默认 `product=both`，一次测试后分别发布 still.fail 和 monoid，使用同一个 main SHA、版本和新 build number；也可以选择 `stillfail` 或 `monoid` 单独发布。每款 App 使用自己的描述文件和发布核对开关，并有独立的上传锁；一款失败不取消另一款，上传成功的各自触发分发，默认都进入内部组和外部组并提交 Beta App Review。发布前分别核对两款的迁移、能力和加密声明，再将 environment `ios-testflight` 的 `IOS_RELEASE_REVIEWED`、`MONOID_IOS_RELEASE_REVIEWED` 设为 true；结束后复原。build number 必须高于以往所有发布任务用过的号，包括失败和取消的。上传成功但分发失败时，只为该产品运行 `mbui-testflight-distribute.yml`，沿用已上传的版本和 build number。
- **monoid iOS**：一个应用身份 `build.monoid.iphone`（App Store Connect ID `6832495462`）从 TestFlight 沿用到 App Store，分享扩展 `build.monoid.iphone.share`，共享组 `group.build.monoid.iphone`。在公司 Apple 团队注册这三项、给主 App 启用 Push Notifications，并给两个 App ID 关联共享组后，用 CI 现有 Apple Distribution 证书创建两份 App Store 描述文件。在 GitHub Environment `ios-testflight` 设置 `MONOID_IOS_APP_PROFILE_B64`／`MONOID_IOS_SHARE_PROFILE_B64` secrets，及 `MONOID_IOS_APP_GROUP`、`MONOID_IOS_RELEASE_REVIEWED` vars；最后一项只在应用身份、能力和加密声明已审核后设为 true。共用公司的 CI 签名证书和 ASC 上传凭据，描述文件分开。上传与分发都会校验 App Store Connect 记录的 Bundle ID，后续分发轮次保留产品选择。App 内的名称、云地址和分享扩展说明来自签名的 monoid 配置。
- **自托管 runner 跑什么**：完整检查（分支和 main）、station 和正式版桌面的打包签名、更新测试 station 到刚发布的包。pipeline 只由仓库成员的 push 触发（`plan` 只认本仓库的 push 和手动触发，不接 pull_request），外部贡献的代码不会在自托管 runner 上跑；带密钥的发布任务仍只在 main 的 production 环境里。
- **main 有保护**（2026-10-20 起）：谁都不能直接推 main，改动一律走 PR；PR 要 pipeline 的 `gate` 通过才能合；管理员可以越过（`gh pr merge --admin`，2026-10-22 起），只在要紧的时候用。`gate` 汇总分支上跑的每个 job，跳过的算过，失败或取消的算挂；给分支加了新 job，要同时加进 `gate` 的 `needs`。
- 看结果：`gh run list -R AFK-surf/monoid -w pipeline`。
