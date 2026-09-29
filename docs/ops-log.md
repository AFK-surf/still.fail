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
