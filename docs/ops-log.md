# 部署维护日志

线上 ember（ember cloud、各台 station）的部署、更新和出过的事，按时间倒序。时间是北京时间。怎么运行、服务怎么装见 docs/operations.md。

## 现在怎么上线

- **合并**：GitHub `zzj3720/ember` 的 main 是唯一的 main。commit / push 时 git hook 跑快速检查（`scripts/check.sh`，几秒）。
- **部署前 review**：部署的 agent 先把上次部署以来合进来的提交和 PR 过一遍（数据格式、新旧混跑的兼容、station 的启动和更新流程、删除数据或碰外部服务和密钥的改动），有风险先说；还没合的分支和开着的 PR 列出来给人决定。
- **部署**：在 studio 上 `~/bin/ember-job deploy "~/bin/ember-deploy"`（不直接 ssh 跑，ssh 会断）。它从 GitHub 拉 main，对上次部署以来改到的部分跑完整检查（测试、真实 wasm 核心、shapes、Rust、安卓），不过就不部署；再部署改到的 cloud Worker，后台上传 station 发布包（`/tmp/ember-release.log`），传完 studio 的 station 自己 `stillfail update` 到它（`/tmp/ember-station-update.log`，原地交接）。2026-10-01 起 studio 跑的是正式安装的 station（LaunchAgent `fail.still.station`，程序在 `~/.stillfail/app`），不再从检出跑；`mesh/target` 里的 stillfail-station 只给测试 station 用。上次部署到哪：studio `~/.stillfail/deployed-commit`。
- **更新 station**：不自动更新。发布包上传完后在那台机器上 `ember update`；支持交接的 station（`~/.ember/run/station.json` 里有 `"handoff"`）原地换版本，pid 不变，正在跑的轮次、agent 进程和 job 都接着跑。

## 卡住了怎么办

- **`ember update` 半天没动静、消息送不到**：多半是没能交接、退回了排空（`~/.ember/ember.log` 里有 `draining: no new turns`）。排空期间不开新轮次，新消息排队；最多等 10 分钟轮次结束，没人重启的话再过 5 分钟才自己恢复。处理：先结束卡住的 `ember update`（`ps` 找 `/bin/sh …/ember update` 和它的子进程），再给 station 发 `kill -USR2 <pid>`（pid 取 `run/station.json` 里的；`pgrep -f 'ember-station run'` 还会匹配到 agent 在工作区里起的测试 station，别用）。同一版本交接给自己，排空状态就没了。
- **部署时 `fetch failed`**：studio 出外网经过局域网的 Surge 旁路由（192.168.20.11），偶尔断。`ember-deploy` 的 cloud 部署遇到它会自己重试三次；拉 GitHub 断了就重跑部署。重复部署 Worker 没有副作用。
- **完整检查不过**：`/tmp/ember-check.log`。什么都没部署出去，线上还是上一版。

## 待部署

## 2026-10-01

### 02:32 各台 station 更新到 0.1.1209，studio 和 mini 换成正式安装

- bft、claude-mac（macvm）：`stillfail update` 原地交接到 0.1.1209，pid 不变。claude-mac 是从这台机器上的会话里起的，更新放在后台等轮次结束后再跑。
- studio：原来是 `~/bin/stillfail-restart-station.sh` 从 `~/WebstormProjects/ember` 起的开发版（0.1.0）。先发 USR1 等轮次结束，停掉它，再跑 install.sh 装成正式版（LaunchAgent，0.1.1209），数据还是 `~/.stillfail`，之前的 ember.db 备份在 `ember.db.pre-official`。`~/bin/ember-deploy` 改成不重启 station、不重建 station 页面，改为发布包传完后执行 `stillfail update`（旧脚本备份在 `~/bin/ember-deploy.bak-1001`）。
- mini（mini1，zuozijian的Mac mini）：原来是很旧的开发版桌面 app（`~/ember-dev/Electron.app`，带着 node 的 station）用 `--with-parent` 起的。退出这个 app 之后跑 install.sh，数据从 `~/.ember` 搬到 `~/.stillfail`（旧位置留了链接），ember.db 备份在 `~/ember.db.pre-official-1001`。别再打开 `~/ember-dev` 的那个 app，它会自己再起一个 station。
- 四台都已经 online at still.fail cloud。更新后应该都会选北京 relay，station 卡片上的网络行能看到。

### 02:20 部署 76afc23（station 卡片的网络行）

- 部署：86b8edb → 76afc23，这之间只有 76afc23（station 卡片显示客户端到 station 的路径、延时、速度、丢包）和一个只改 ops-log 的提交。完整检查 6 项通过；发了 web、admin，studio 的 station 只重建了页面没重启，station 发布包在后台上传。
- 只改了客户端（core + web + 手机 web + 安卓），station 和 cloud 的接口没动。安卓要等下一版 app 才有。
- 验证：app.still.fail 上的 CloudApp 和 core wasm 都是新构建（200，含网络行的文字）。还没在登录后的页面上实际看过：打开设置 → Station，远端 station 卡片上应该有「经 relay（…）/直连 · 延时 · ↓ ↑」这一行，每 2 秒刷新一次。
- 没合的分支：preview-dock-edge、search-list-layout，这次没带。

### 01:40 部署 e407171（新图标），发安卓和桌面 0.1.1204

- 部署：a99cfc8 → e407171（新图标）。发了 web 和 admin；admin.ember.3720.org 的部署检查偶发 SSL EOF，手动 curl 返回 200。
- 发版：从 main e407171 打包 0.1.1204，安卓和桌面端都发了，用 `~/bin/ember-gui rel-1204` 在 studio 的图形会话里跑。两个域名上的 `android/latest.json` 和 `desktop/stillfail-mac.yml` 都是 1204，zip 和 apk 用 Range GET 都返回 206。之前还发过一版安卓 0.1.1203（a99cfc8 之后，旧图标）。
- 00:35 那条记录里说要等安卓和桌面端新包才生效的改动（草稿、未读线、`@`、任务、prefs、原生端重连、新图标），到这里都已经发出去了。上线后照 00:35 那条里各项的验法，在安卓和桌面端上各看一遍。

### 00:38 部署 86b8edb（多 relay，北京 relay 上线）

- 部署：e407171 → 86b8edb。包括 5d3898a（登录失败的提示链到对应 profile 页，`entries` 表原地加了 `profile` 一列）和 86b8edb（多 relay）。完整检查 9 项通过；这次发了 relay、api、web、admin 四个 Worker，studio 的 station 重新构建并重启，station 发布包在后台上传。
- 验证：`https://app.still.fail/ping` 已经带 `access-control-allow-origin: *`。studio station 的 `mesh/cloud.json` 里 `relay_urls` 是 `[app.still.fail, 39.105.157.122]`。重启后约 1 分钟，北京 relay 上多了一条来自 studio 出口 IP（120.207.93.144，山西移动）的连接，说明 studio 的 station 已经把北京当成 home relay。
- 别的 station 要各自 `stillfail update` 以后才会切过去。下面是这次改动部署时要注意的，原文保留：

  - 多 relay（multi-relay）：cloud 多发一个 `relay_urls`（still.fail 自己的在前，`RELAY_URLS` 里的在后；wrangler.jsonc 里写的是北京那台 `https://39.105.157.122`），`relay_url` 照旧只给第一个；relay Worker 的 `/ping` 加了 `access-control-allow-origin: *`，浏览器靠它测延迟选 relay。所以 relay 和 api 两个 Worker 都要部署。新 station 把所有 relay 放进 map，就近选一个作为 home（国内的会选北京）；cloud 以后增删 relay，station 运行中就会跟着改。新 core 拨 station 时所有 relay 都走一遍。
    - 新旧混跑：旧 station 只认 `relay_url`，新客户端照样能连上。新 station 如果选了北京做 home，旧的原生客户端（桌面、安卓）只拨 Cloudflare，要靠 DHT 查到北京才连得上（在 studio 实测第一次连约 3 秒，之后正常）。旧网页（wasm 没有 DHT）连不上北京上的 station，要刷新成新页面才行：web 要和 cloud 一起发，部署后开着的旧标签页要刷新一下。客户端的 relay 列表是第一次 `/v1/me` 时定下的，设备上存着旧 `me` 记录的，要到下次打开 app 才用上新列表。
    - 限制：一台 station 只能从它的 home relay 收到连接。北京那台从海外基本连不上（海外出口的本机也连不上），所以人在海外、station 在国内时，会连不上这台 station。
    - 北京 relay 本身的情况：阿里云轻量北京，iroh-relay 1.1.0，证书是 Let's Encrypt 的 IP 证书（6 天有效，lego 自动续签后热加载），只能从 studio ssh 上去。具体见 ember skill。
    - 上线后验：studio 的 station 日志里 home relay 是 `39.105.157.122`；在国内打开 web 连 studio 的 station，mesh.connect 的耗时明显下降。改之前在 studio 实测：全走 Cloudflare 时建连 2.6 秒、每个来回 540ms；走北京时建连 0.2 秒、每个来回 41ms。

### 00:35 部署 a99cfc8（逻辑挪进 core）

- 部署：b24e8b2 → a99cfc8。包括 core-read-notices、core-chat-refs、core-archive、core-new-chat-choice、core-jobs、core-prefs、core-labels-net、job-log-topic、android-reconnect，还有 activity 进场。完整检查 9 项通过；station 重新构建并重启，cloud 发了 web 和 admin（新旧两个域名都返回 200），station 安装包在后台上传。
- 验证：app.still.fail 线上的构建里已经有 `chatSearch`、`longJobs`、`prefs.set`、`client.focus`；`~/.stillfail/deployed-commit` 是 a99cfc8。
- 还没发：安卓新包（`release.sh android`）和桌面端新版。发之前，旧的安卓和桌面端会缺这些：草稿、未读线、`@` 菜单、任务按钮，以及原生端重连。下面是各条改动部署时要注意的，原文保留，发安卓和桌面端时照着做：

  - activity 进场和不裁剪（android-chat-edge-clip）：只改客户端。web 随页面上线：activity 进场时位置展开、渐入、从头像放大，内容贴顶不被压；聊天列表底下的垫底不再取整（以前底部有东西按小数像素长高时，整个列表会上下抖 1px）。安卓要发新包：activity 一行和 agent 消息长按高亮、发送失败变淡都不再裁剪内容（转圈的环左边不再被切）；另外修了新来的行从来不播进场动画的 bug（activity 进场、新消息升起）。新旧混跑没问题，station 和 cloud 不用动。上线后验：发一句让 agent 开始干活，activity 从头像处渐入放大，环左边完整，上面的消息平滑让位、不抖；安卓同样看一遍。
  - 草稿挪进 core（android-new-chat-draft）的安卓部分：web 和 wasm 已随 b24e8b2 上线，安卓要发新包（`release.sh android`）才生效。上线后验：安卓在 new chat 写一句，杀掉进程重开后还在；返回手势松手后不会停一下。
  - android-reconnect（原生端重连）：改的是 client/core，web 部署会带上 wasm 那份（重试时胶囊立刻变「正在重连」，span 带 `os.type`）；安卓要 `release.sh android` 发新版，桌面端要发新版，原生端才会只用自己的 relay、在拨号没回应时重建端点。另外：重试改成 `client.wake {retry}`（不作废进行中的请求，老 core 收到的仍是 network）；web 在 Chrome 安卓上按 `navigator.connection.type` 发现换网；桌面端主进程每 3 秒看一次网卡地址，变了告诉页面（要发桌面新版）；原生端 sleep 按墙钟算，设备睡眠期间也计时。新旧混跑没问题：station 和 cloud 都不用动，老桌面端没有 `onNetwork` 就不报。上线后在 Axiom 里验：`name == "mesh.connect"` 按 `['resource.os.type']`（或 `resource.custom`）分组看失败率，失败的看 `stillfail.relay`（home relay 当时是 up 还是 down），`stillfail.rebound`/`mesh.hedge` 说明重建端点、第二路拨号有没有起作用。改之前（9-28 到 9-30）原生端连本机 station 是 43/69 失败，web 是 9/71。
  - 任务输出改成 core 的 `jobLog` topic（job-log-topic）：界面不再自己轮询 `job.log`。要发 station（`/events` 多认 `job=<id>&lines=<n>`，推 `job-log` 事件；`GET /jobs/:id/log` 多给 `follows: true`）、web/admin（带 wasm 的 core）、安卓新包、桌面端。不用排顺序：旧 station 不认 `job=`，新 core 看它的日志回答里没有 `follows`，就由 core 自己隔一阵再读（2 秒起，没变化就加倍，最多 1 分钟）；旧页面和旧安卓照旧调 `job.log`，接口没删。安卓服务页去掉了「station 太旧、job 里没有 session 就每 4 秒重读」这段：Rust station 从有任务起 job 就带 `session`。上线后验：打开一个在跑的任务看「输出」，内容一秒左右跟着长；浏览器开发者工具里看不到每隔几秒一次的 `/jobs/<id>/log` 请求，事件流的地址里带 `job=`。
  - 未读线、已读、通知判断挪进 core（core-read-notices）：core 加了 `notify` topic 和 `client.focus`、`notify.set`、`notice.claim`、`notice.pushed`（attend.rs）；聊天的 `chat` 多了 `unreadLine`/`unreadAbove`。通知开关和「问过系统」存在 core 的本机存储（键 `notify`，不改库结构），默认开。web 和 wasm 一起发布；web 旧的 `stillfail.notify=off` 首次打开时搬进 core，`stillfail.noticesShown` 删掉。安卓要发新包，旧 SharedPreferences 的 `notify`/`notifyAsked` 首次打开时搬进 core。桌面端 core 比页面旧时不认识 `client.focus`：页面自己标已读（和以前一样），但没有未读线，桌面更新后恢复。上线后验：web 打开有未读的 chat 出现未读线、滚到底后侧栏未读消失；另开一个 tab 停在别的页面，别人发消息只弹一次通知，正看着那个 chat 时不弹；设置里关掉通知刷新后还是关；安卓同样验未读线/已读/通知，关掉通知杀进程重开仍是关。
  - 引用对话和对话搜索挪进 core（core-chat-refs）：core 加了 `chatSearch` topic（`@` 菜单和 ⌘K 切换器共用）、`chat.ref`（选中的对话 → 标记，链接存在 core 的数据库里，新表名 `chat_ref`，不改库结构）、`chat.refs`（旧客户端存的链接搬进来），`chat.send` 发出时由 core 把 `@[标题]` 换成链接；草稿按页面的 key 存取（`draft.put {key}`、`draft.get`），每次改动都交给 core，core 自己合并成 300ms 后写一次库。web 和 wasm 一起发布；web localStorage `stillfail.chatRefs` 和安卓 SharedPreferences `chatRefs` 首次打开时搬进 core。桌面端 core 如果比页面旧：`@` 菜单和 ⌘K 显示「更新 still.fail 后才能…」，草稿只留在内存里，不会报错——所以桌面端最好跟着发一版。上线后验：web 在对话里 `@` 选一个对话发出去，消息里是能点的引用；⌘K 搜标题；刷新后草稿还在；安卓同样 `@` 引用一次。
  - 归档挪进 core（core-archive）：core 加了 `archive { scope }` 视图和 `archivedRows { station }` topic（不存库），`chat.archive` 归档时 core 立刻把那一行从 `chats` 里拿掉，失败再放回；恢复/删除后 core 重读归档列表。station 不用改，旧 station（不给 `archived` 的）归档页照样是空的。web 和 wasm/桌面端 core 一起打包，不用排顺序；只有开着旧 SharedWorker 的旧标签页配新页面时归档页会显示错误，刷新即好。安卓要发新包。上线后验：侧栏右键归档一个对话，行立刻消失；归档页能看到它（今天、手动归档），点恢复后行从归档页消失、回到侧栏；安卓归档页同样。
  - 新对话的选择和换模型挪进 core（core-new-chat-choice）：core 加了 `newChat`（新对话页：station 列表、选中的 station 和解析好的模型/运行时/深度/账号、提示文案）和 `pick`（模型控件：当前值、面板里的草稿、账号让位的说明、手机全屏页的前后对照）两个 topic，调用 `newChat.pick`/`newChat.create`/`newChat.migrate`/`pick.set`/`pick.save`；选择存在 core 的数据库（新表名 `choice`，不改库结构），没检查过的 profile 由 core 自己去检查；`machineSessions.list/read` 的回答多了 `meta` 一行字。web 和 wasm 一起发布，页面和 core 同版本，不用排顺序。web 旧页面存在 localStorage `stillfail.newChat` 的选择、安卓旧版存在 SharedPreferences `newChat/*` 的选择，首次打开时各搬进 core 一次。安卓要发新包。上线后验：web 新对话选一个模型/深度，刷新后还在；换 station 后再开新对话还在那台；聊天页换模型（桌面面板、手机全屏页）改完生效；安卓旧版选过的模型升级后还在。
  - 任务列表挪进 core（core-jobs）：core 加了 `chatJobs`、`longJobs`、`job` 三个 topic（jobs.rs），`jobLog`（job-log-topic 加的，station 跟着推）多了 `last`、`said`（「最后输出 · 3 分钟前」，core 按秒刷新）；页面和安卓不再自己算圆点、排序、「x 个在线」这些字，也不再自己轮询任务本身（`job` 由 core 跟事件，旧 station 每 4 秒读一次）。station 的 `GET /jobs/:id/log` 除了 `follows` 还多回一个 `state`（现在没人用，留着无害）。web 和 wasm 一起发，不用排顺序；安卓要发新包。桌面 core 比页面旧时不认识 `chatJobs`/`longJobs`/`job`：任务按钮不出现、侧栏不显示「开了很久的」、单独打开的服务页报找不到，不会崩。上线后验：一个 chat 里起一个 `job_start` 的服务和一个后台任务，标题栏按钮、弹层、任务侧栏、手机的任务表单、左下角「开了很久」（等一小时）都和以前一样；任务输出跟着长，「最后输出 · x 秒前」逐秒走。
  - 偏好挪进 core（core-prefs）：core 加了 `prefs` topic、`prefs.set` 和 `client.device`，存在 core 数据库的 `prefs` 表（逻辑表，不改库结构）。里面有：只看我的、外观、列表头像、绝对时间、快捷键、上次的 workspace/chat、每个 chat 的执行历史 tab、安卓 new connect 的 resume、邀请码。chats 视图新加了 `leading` 字段，行上新加了 `peopleText` 字段。设备名和消息的「从哪个 app 发的」改由 core 按 `client.device` 生成。web 和 wasm 一起发布，不用排顺序。web 旧的 localStorage 值（`stillfail.onlyMine/appearance/rowPicture/absoluteTime/keys/lastChat/chatTabs`）首次启动时搬进 core 一次（只补 core 里还没有的），旧 key 留着不删；`stillfail.appearance` 和 `stillfail.prefs` 以后是 core 值的同步副本，给 index.html 首帧上主题用，不能删。邀请码从 sessionStorage 挪到了 core，建好 workspace 后由 core 自己清掉。安卓要发新包：SharedPreferences 里的 workspace/theme/rowPicture/onlyMine/newConnect.resume 会在首次启动时搬进 core，搬完就删。上线后验：web 切「只看我的」和深色后刷新，首帧就是深色，列表也已经筛好；侧栏头像跟「列表头像」设置走；从 Slack 点会话链接，PC 浏览器先问桌面端，手机直接打开；安卓升级后主题、workspace、只看我的都还在。
  - 标签/状态和界面里的请求挪进 core（core-labels-net）：chats 视图多了 `glyph`、`note`、`trouble.retry`，chat 视图多了 `connection`，stations 视图多了 `face`、`line`，overview 里 profile 多了 `available`、machineLogins 多了 `offered`，`memory.get` 的 skill 多了 `body`、`about`；新调用 `link.parse`、`app.update`、`picture`、`buddies`、`dev.signIn`（client/core/src/asks.rs、looks.rs，不改库）。web 和 wasm 一起发布，不用排顺序。桌面端 core 比页面旧时这些字段没有：侧栏 station 图标画成空圈、行旁的字为空、没有重试按钮，Slack app 头像只剩厂商标志，「这台机器上已经登录了」不出现，直到桌面端更新；不会报错。安卓要发新包（检查更新、头像、链接都走 core 了）。上线后验：侧栏 station 行和手机首页右上角图标与之前一样；聊天里断开 station 时顶上的胶囊文字不变；安卓点 still.fail 链接仍在 app 里打开；安卓「我」里检查更新正常；安卓头像照常显示。

## 2026-09-30

### 22:50 部署 b24e8b2：ember.3720.org 的网页跳到 app.still.fail，官网

- 部署：d00630c → b24e8b2。包括 732dc78（ember.3720.org 的网页 302 到 app.still.fail 同路径和查询；ember-web 从纯静态改成前面有 `cloud/src/web.ts`，`run_worker_first`），以及已合未部署的草稿进 core、滚动条变细、作者名去下划线、可视化高度不设上限、打开 agent 历史这几个。部署了 api、web、admin，station 重建并重启，发布包后台上传。relay 没动。ad980b7（android-reconnect）是之后合的，没在这次里。
- 前两次被完整检查拦下：`login::tests::a_subscription_sign_in_relays_the_link_the_code_and_the_result` 等 NeedsCode 超过 10 秒。当时 studio 负载 35～47（几个编译、Android 构建，trustd 占满一核），假登录命令启动很慢；单独跑 2～4 秒就过。b24e8b2 把等待上限放宽到 30 秒。
- 线上验（curl）：ember.3720.org 的 `/`、`/w/…/chats/…?service=…`、`/assets/…` 都是 302 到 app.still.fail 同路径；`/sw.js`、`/healthz`、`/ping`、`/install.sh`、`/.well-known/assetlinks.json` 是 200，`/v1/me` 是 401（照旧由 API 回答）。旧域名的 API 和 relay 不跳，已装的 station 和旧 app 照旧能连。
- 官网 `python3 cloud/deploy.py site`：链接和安装命令改成 app.still.fail。
- 另外（不在仓库里）：manus.rip 的跳转 Worker（studio `~/ember-deploy/redirect-manus-rip`）改成跳到 still.fail。
- 草稿进 core：web 部分已上线，没在浏览器里实际验；安卓部分留在「待部署」。

### 21:13 部署 d00630c（relay 预算不再逐帧转发）

- 部署：c4f4561 → d00630c，包括 18f45dd（内嵌 HTML 记住高度）和 d00630c（relay-direct-websocket）。完整检查 4 项通过；部署了 relay、api、web、admin，studio 的 station 只重建了页面。所有 relay 连接断了一次，之后自动重连。
- 起因：CF 出了按量账单。查 9 月用量发现，RelayBudget 的 DO（namespace `d73f80fb…`）被每条 relay 连接占着，每天 active 86,300 秒，每天约 465 万条入站消息；容器的 DO（`2bb98e53…`）也收同样多的消息。现在 RelayBudget 只在建连接时放行，每分钟读一次 iroh-relay 的 metrics 来统计流量。
- 验证：`/relay` 的 WebSocket 升级请求返回 101。GraphQL 按分钟查：部署后 RelayBudget 每分钟 active 0.2–0.8 秒（每分钟一次的 alarm），入站消息 0；容器的 DO 照常每分钟收几千条。alarm 一直在续，说明从容器 9090 端口读到了打开的连接。
- 容器的 DO 仍然全天在线，并逐帧转发（@cloudflare/containers 的 containerFetch 就是这么转发的），这部分省不掉。按 9 月底的流量，relay 每月从约 $8–9 降到约 $4–5。
- 别的按量开销（R2 `zork-kache` 50 GB、sokoban/benchmark 等旧资源）没动，等人决定要不要删。

### 21:03 部署 c4f4561（桌面端差量更新）

- 部署：b862d34 → c4f4561，包括 aec4d4b（station 跟着 cloud 换域名）和 c4f4561（`/releases/` 支持 Range 和多段 multipart/byteranges，白名单加上桌面 zip 的 blockmap）。完整检查 3 项通过；部署了 api，studio 的 station 重启，station 发布包在后台上传。别的 station 要各自 `stillfail update`，才会用 cloud 推过来的 origin。
- 补传了 1169 的 blockmap，文件在 studio 的 `~/ember-deploy/blockmaps/`，是照线上 zip 算的。验证：两个域名上 `curl -r 0-9` 都返回 206 和 `content-range: bytes 0-9/159912673`；三段 Range 返回 multipart/byteranges；blockmap 用 GET 返回 200，sha256 和本地文件一致。在 studio 的 miniflare 里用 electron-updater 6.8.9 的差量下载器实测，从 1123 更新到 1169 只下 31 MB（整包 156 MB），拼出来的文件和原包逐字节相同。
- 原来「待部署」里侧栏头像、固定 chat、Slack 同意页、CPU 占用率这四条，其实在 b862d34 那次已经上线了，只是没从这里清掉；station 跟着 cloud 换域名、桌面端差量更新这两条是这次上线的。这一节现在清空。
- 桌面端差量更新的前提是 app 本地缓存了上次自己更新时下的 update.zip。手动安装的 1169 下一次更新还是整包，再往后才会差量。下次发桌面版时，`release.sh desktop` 会自动把 blockmap 一起传上去。

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
