# 部署维护日志

线上 ember（ember cloud、各台 station）的部署、更新和出过的事，按时间倒序。时间是北京时间。怎么运行、服务怎么装见 docs/operations.md。

## 现在怎么上线

- **合并**：GitHub `zzj3720/ember` 的 main 是唯一的 main。commit / push 时 git hook 跑快速检查（`scripts/check.sh`，几秒）。
- **部署前 review**：部署的 agent 先把上次部署以来合进来的提交和 PR 过一遍（数据格式、新旧混跑的兼容、station 的启动和更新流程、删除数据或碰外部服务和密钥的改动），有风险先说；还没合的分支和开着的 PR 列出来给人决定。
- **部署**：在 studio 上 `~/bin/ember-job deploy "~/bin/ember-deploy"`（不直接 ssh 跑，ssh 会断）。它从 GitHub 拉 main，对上次部署以来改到的部分跑完整检查（测试、真实 wasm 核心、shapes、Rust、安卓），不过就不部署；再部署改到的 cloud Worker，重启 studio 的 station，后台上传 station 发布包（`/tmp/ember-release.log`）。上次部署到哪：studio `~/.ember/deployed-commit`。
- **更新 station**：不自动更新。发布包上传完后在那台机器上 `ember update`；支持交接的 station（`~/.ember/run/station.json` 里有 `"handoff"`）原地换版本，pid 不变，正在跑的轮次、agent 进程和 job 都接着跑。

## 卡住了怎么办

- **`ember update` 半天没动静、消息送不到**：多半是没能交接、退回了排空（`~/.ember/ember.log` 里有 `draining: no new turns`）。排空期间不开新轮次，新消息排队；最多等 10 分钟轮次结束，没人重启的话再过 5 分钟才自己恢复。处理：先结束卡住的 `ember update`（`ps` 找 `/bin/sh …/ember update` 和它的子进程），再给 station 发 `kill -USR2 <pid>`（pid 取 `run/station.json` 里的；`pgrep -f 'ember-station run'` 还会匹配到 agent 在工作区里起的测试 station，别用）。同一版本交接给自己，排空状态就没了。
- **部署时 `fetch failed`**：studio 出外网经过局域网的 Surge 旁路由（192.168.20.11），偶尔断。`ember-deploy` 的 cloud 部署遇到它会自己重试三次；拉 GitHub 断了就重跑部署。重复部署 Worker 没有副作用。
- **完整检查不过**：`/tmp/ember-check.log`。什么都没部署出去，线上还是上一版。

## 待部署

- 侧栏头像显示参与的人（sidebar-people-avatars）：station（mesh）、core（wasm 和安卓的 core）、web、安卓都改了。station 的 `/chats` 每行多给 `creator` 和 `people`，core 给人配名字和头像，`chats` 视图多一个 `members`（workspace 人数，本机页算 1），都是可选字段。新旧混跑：旧 station 不给 people 时，行里就没有这个字段，页面照旧只画 agent；旧页面遇到新 station，多出来的字段直接忽略。要重新发 station 包，各台 station 更新后才看得到人；web 跟着部署生效；安卓要发新版。上线后验：在多人 workspace 里，侧栏左边显示的是参与的人，发起人带一圈描边，agent 缩到标题右边，同一家的 agent 只画一个图标；状态点在标题前面；设置 → 外观 →「侧栏头像」（手机在「我」→「列表头像」）切到 Agent 为主或人为主，列表跟着变。
- 固定 chat（pin-chats）：station（mesh）、core 的 wasm、web、安卓都改了。station 在打开 db 时建 `pins` 表（IF NOT EXISTS，不升 schema 版本，旧 station 照样能读），侧栏行多一个 `pinned` 字段（固定的时间或 null），新增 `PUT/DELETE /sessions/:key/pin`；有人固定的 chat 不会因为闲置被自动归档。新旧混跑：旧 station 不发 `pinned`，新页面就不显示固定的菜单项；旧页面忽略这个字段，列表照旧按时间排。安卓要发新版才有详情页的入口。先发 station 包或先发页面都可以。上线后验：PC 右键一个 chat 点「固定」，它进到列表顶部的「已固定」一组，换一台设备也在；别人登录看不到你的固定；手机详情页「固定到列表顶部」同样生效。
- 改权限后自动打开 Slack 同意页（slack-approve-opens）：只改客户端（web、安卓），station 和 cloud 不用动。web 在点「应用到 Slack」时如果权限有变，先同步开一个标签页，station 回来后跳到 Slack 的 install 页，失败就关掉；桌面端和安卓等结果回来后用系统浏览器打开。web 跟着 cloud / station 的页面上线，安卓要发新版。上线后验：在 Slack app 设置里勾一个新权限点应用，新标签页先显示「正在更新 Slack app…」，随后到 Slack 的同意页；只改名字不开标签页。
- CPU 显示真实占用率（cpu-usage-meter）：station（mesh）、core（wasm 和安卓的 core）、web 都改了。station 的 host 多给一个可选的 `cpuBusy`（0–1，所有核合起来；macOS 读 host_statistics，Linux 读 /proc/stat），core 有它时 CPU 表显示占用率、附注写「负载 x · 芯片」，没有时照旧按「load ÷ 核数」显示「CPU 负载」。新旧混跑：旧 station 不给 cpuBusy 就是旧显示；旧页面和旧 core 忽略这个字段。要重新发 station 包，各台 station 更新后才换成占用率；安卓要发新版（core 在里面）。上线后验：cloud 的 Station 列表里，没满的机器 CPU 圆环和 `top` 的占用率对得上，不再是 load ÷ 核数；悬停圆环看到「负载 …」。
- station 跟着 cloud 换域名（station-origin-follows-cloud）：cloud（api）和 station（mesh）都改了。cloud 推给 station 的 `state` 多带 `origin`（PUBLIC_ORIGIN）和 `relay_url`，station 收到就写回 `mesh/cloud.json`；Slack 里的会话链接、服务链接都从这里拼，改名前加入的 station 以前一直发 `ember.3720.org`。cloud 的签名校验新旧 origin 都认，换了不会断。新旧混跑：旧 station 忽略这两个字段；旧 cloud 不发时，新 station 保持原样。要部署 api，并重新发 station 包，各台 station 更新后才生效。上线后验：各台 station 的 `~/.stillfail/mesh/cloud.json` 里 `origin` 是 `https://app.still.fail`；Slack 里新发出的链接是 app.still.fail。

## 2026-09-30

### 22:40 部署 b862d34，发安卓 0.1.1172

- 部署：8652e08 → b862d34。包括安卓和 web 的动效（c8afea2），以及别的会话合进来的置顶对话、CPU 真实占用、桌面检查更新、Slack 权限批准、侧栏头像。部署了 web 和 admin，station 重新构建并重启，完整检查 9 项通过。
- 前两次部署被完整检查拦下：`host::tests::the_machine_is_described_and_kept_for_a_while` 报 `cpu_busy` 是 None（54bf344 起）。macOS 的 `host_statistics` 隔一阵才更新 ticks，真睡了 505ms 以后两次读数一模一样；单独跑这个测试时碰巧能过，整套一起跑时常挂。b862d34 改成睡半秒后每 100ms 再读一次，直到读数变了，最多等 2 秒。连跑 6 次整套都通过了。
- 安卓：`release.sh android` 在 c8afea2 上打包 0.1.1172，两个域名上的 `latest.json` 都已经是 1172。

### 20:20 桌面版 0.1.1169（586404e）

- 发了桌面版 0.1.1169：菜单栏 still.fail 菜单里的「检查更新…」、设置里的「版本」页（desktop-check-updates）。两个域名上的 `desktop/stillfail-mac.yml` 都是 1169，zip 用 GET 下载是 200。上一版是 0.1.1123，改名以后桌面版就没再发过。
- 签名不用非得在 studio 本机终端跑：`~/bin/ember-gui <名字> "<命令>"` 会在图形会话里跑命令（登录钥匙串在那里是解锁的），ssh 里 codesign 报的 errSecInternalComponent 就没了。这次的命令是 `~/bin/ember-gui desktop-release "export PATH=…; cd <新 worktree> && sh scripts/release.sh desktop"`，worktree 从 github/main 开，根目录、apps/desktop、cloud 三处都要 `pnpm install`。日志在 `/tmp/ember-gui-<名字>.log`，跑完退出码写进 `.done`。从头编译到上传完大约 50 分钟，其中签名占了大半。
- 上线后验：已经装好的 1123 会在启动时或 4 小时内查到新版，侧栏顶上出现「更新」。更新以后，菜单里点「检查更新…」应该弹出「已是最新版本」。

### 18:19 部署 7fb7463 → 6614ba8 → 8652e08，官网

- 部署：`ember-deploy` 从 6b6782f 起分三次上线。7fb7463：cloud api/web/admin、studio 的 station 重启、station 发布包上传。第一次跑在完整检查的「Rust: station」挂了，报 `iroh-mainline-address-lookup` 里 `iroh_dns` 有两个版本，Cargo.lock 其实只有一份。原因是在 studio 上给别的 worktree 跑测试时用了 `CARGO_TARGET_DIR=~/WebstormProjects/ember/mesh/target`，缓存被弄乱了；重跑就过了。以后在 worktree 里测试别共用主检出的 target。6614ba8、8652e08 只有 web/admin 变化。部署时 `ember.3720.org/healthz` 报过一次 SSL EOF，本机和 studio 重查都是 200。
- 官网 `python3 cloud/deploy.py site`：`build:site` 的预渲染（SSR）连着被两处挡住：fe6f7ab 的 StationGlyph 用了 `CSS.escape`（6614ba8 修），6436a34 的侧栏 `useSyncExternalStore` 没给 getServerSnapshot（8652e08 修）。完整检查不跑 `build:site`，这类问题只有部署官网时才暴露；共用组件里别在渲染时用浏览器才有的 API，`useSyncExternalStore` 要给第三个参数。上线后 still.fail 的 title 和 og:image 已是新的。
- 这次上线的（原「待部署」各条照做了）：history-no-arrive-anim、auto-chat-title、og-image-still-fail、slack-duplicate-session-race、slack-file-upload、slack-scopes、chat-open-no-flicker。push 用的 VAPID / FCM 密钥还没有，推送没开。
- 没做的：别的 station（mini2 等）要在各自机器上 `stillfail update`；安卓没发新版，新权限表单、切 chat 不闪等客户端改动要等下次 `release.sh android`。

### 13:10 部署 6b6782f，发安卓 0.1.1141

- 部署：`ember-deploy` 从 98aad7f 到 6b6782f，共 3 个提交：安卓和 web 手机版互补、b050b46 消息性能、82135e2 ops-log。完整检查 7 项通过，部署了 web 和 admin；这次没改 cloud 的 api，也没改 mesh，所以 station 只重建了页面。
- 安卓：`release.sh android`，事先在 `cloud/` 里装好了依赖，这次正常上传。两个域名的 `latest.json` 都是 1141，apk 返回 200。

### 05:00 部署 98aad7f，发安卓 0.1.1138

- 部署：`ember-deploy` 从 d9b03e1 到 98aad7f（15 个提交：安卓补齐到 web 手机版，chat 列表动效、系统消息胶囊、整页 HTML 16:9、预览流式请求头改回旧名、Slack app 默认名、cloud 提供 `android/stillfail-<n>.apk` 等）。完整检查 10 项通过；部署了 api、web、admin，重启 studio 的 station，station 发布包在后台上传。
- 安卓：必须先部署 cloud 再传包。改名后的包叫 `android/stillfail-<n>.apk`（b9226f9），之前线上 cloud 的白名单只认 `android/ember-<n>.apk`，先传的话旧 app 更新会拿到 404。
- 在新开的 worktree 里跑 `scripts/release.sh android` 时，包打好了，上传却以 254 退出。原因是 `cloud/` 没装依赖，找不到 wrangler，而 `put` 把 wrangler 的输出吞掉了，看不到报错。处理：在 `cloud/` 里 `pnpm install`，再手动 `wrangler r2 object put` 传 apk 和 `latest.json`（格式同 release.sh）。两个域名上的 `latest.json` 都已是 1138，apk 返回 200。

## 2026-09-29

### 21:50 agent 自己跑 `ember update`，卡住 + 消息送不到

- 经过：这台 station（macvm）上一个 agent 先在 studio 上直接跑了 `~/bin/ember-deploy`（21:45，部署 ff8d4be，完整检查通过；没经过 `ember-job`，所以 `/tmp/ember-deploy.log` 里没有这次），发布包 21:49 传完，然后在自己的轮次里跑 `ember update`。安装脚本发现服务定义（launchd plist）和它新生成的不一样，没有交接，改发 SIGUSR1 排空，等正在跑的轮次结束——其中就有发起更新的这个轮次，互相等。排空期间新消息全在排队。
- 原因：`cloud/src/install.ts` 把**调用者 shell 的 PATH** 写进 plist。上次是从 Claude Code 的 shell 更新的，这次是 agent 的 shell，PATH 不同，plist 就"变了"。这台当时还是 1920ea2，发布包已经是 ff8d4be（darwin-arm64 也传了），这次更新本该交接到新版本，结果卡住后没更新成（~/.ember/app/VERSION 仍是 1920ea2）。
- 处理：21:53 结束卡住的安装脚本（在 10 分钟超时、强制重启打断轮次之前）；21:56 给 station 发 SIGUSR2，同一版本交接给自己，1 秒完成，pid 69946 不变，agent 进程和 job 都在，排队的消息开始处理，7 秒后重新连上 ember cloud。
- 顺带验证了：交接时会话 c-11c65e11b9 正在跑（`busy=true`），交接后接着写 transcript——**轮次跑着的时候交接是成立的**。
- 待修（安装脚本）：
  1. 不把调用者的 PATH 写进服务定义（或比较服务定义时不看 PATH），否则换个 shell 更新就交接不了。
  2. 从某个轮次里发起的更新，排空不该等这个轮次本身，否则必然互相等到超时、被强制重启打断。
  3. 已经是最新版时 `ember update` 直接说一声就结束，不走交接或重启。
- 修好之前：agent 别自己跑 `ember update`，从外面更新。
- 22:08 测修复时又把这台排空了一次：agent 的环境里有 `EMBER_DATA=~/.ember`，沙箱里跑安装脚本没清掉，对准了真 station。13 秒内结束脚本、SIGUSR2 交接给自己恢复，app 没动。测安装脚本一律 `env -i`。
- 三处修复在分支 `installer-update-fixes`：比较服务定义时不看 PATH（PATH 也去重，不再随每次更新变长；页面上的「更新」原来因此永远交接不了）；在 station 里面（agent 轮次、job）发起、又得重启时，重启放到后台、独立进程组里等，调用方立刻返回；已经是这个版本就直接说一声结束。

### 19:16 第一次交接更新

1920ea2 上线后更新 bft 和 macvm，两台都是第一次走交接：pid 不变（bft 22182、macvm 69946），常驻的 agent 进程和一个 job 都接了过去。两台当时都没有轮次在跑。

### 18:55 部署时 Cloudflare 连不上

studio 上 `wrangler deploy` 在第一个请求就 `fetch failed`，什么都没部署出去。当天第三次（另两次是更早的部署里：studio 从 GitHub 拉代码、上传网页到 Cloudflare）。连测 20 次都通，是偶发断线，出口经过 Surge 旁路由。`~/bin/ember-deploy` 的 cloud 部署加了遇到 `fetch failed` 自动重试三次（旧脚本备份 `~/bin/ember-deploy.bak-0929`）。

### 13:30 完整检查拦下部署（桌面端依赖）

桌面端 typecheck 报找不到 `electron-updater`：`scripts/check.sh` 只在没有 node_modules 时才装依赖，studio 的旧 node_modules 少了后来加的包。改成每次都 `pnpm install`（01ec190）后重新部署通过。

## 2026-09-28

### 检查挪到本地和部署前（8727607、a3a37c4）

先试过 GitHub Actions（studio 自托管 runner，后改 GitHub 的 Linux 机器），因为分钟数（一次完整检查二十多分钟，发布包还要 Mac 机器按 10 倍计）和合并变慢，改成：git hook 只跑快速检查，完整检查放进 `ember-deploy`，不用 GitHub Actions。`Cargo.lock` 从这时起进仓库。

### agent 合并时撤掉了别人的提交

一个 agent 合并时用 `git reset --soft origin/main` 再提交来压成一个提交；origin/main 在它干活期间往前走了，结果把 99278aa（样式改用 TypeScript）整个撤掉、把 945 行旧 CSS 带回 app.css。另一个会话发现后补了 f5a847c、e2bbdb2、597036f 修回来。项目记忆里已禁止这种合并方式（ember skill 的「开发流程」）。

### GitHub 和 studio 两个 main 分叉

agent 有的推 GitHub、有的推 studio，两个 main 各多了提交，部署（从 studio）漏了 GitHub 上的自动更新。合并成 9fefdb0；之后只认 GitHub 的 main，studio 的检出拒收推送、只用来构建。
