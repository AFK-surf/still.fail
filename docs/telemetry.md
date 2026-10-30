# 遥测：PostHog

still.fail 用 PostHog（美国区，`https://us.i.posthog.com`）做产品分析、错误追踪和会话回放。这是 still.fail 托管服务的第一方分析；自己构建时不配置 key 就不会上报（见下文）。链路追踪另走 Axiom，不在这里。

**什么都不带内容**：聊天文字、引用、文件名、提示词、agent 的输出、对话标题，一样都不发。发出去的只有动作、计数、耗时和错误（带调用栈）。

## 网页版（app.still.fail）

`web/src/telemetry.ts`，在 `web/src/main.tsx` 里启动。构建时没有 key 的话，这些函数什么都不做，bundle 里也没有 posthog-js。管理后台（`admin.still.fail`）什么都不发。

- **身份**：看着哪个 workspace，就以那个 workspace 所用的已登录账号标识，只用 still.fail 账号 id（即 Google `sub`），不发邮箱；退出或注销这个账号时 reset。station 自己的管理页不标识人。
- **开关**：设置里的「发送使用统计和错误报告」（宽屏在 设置 → 关于，窄屏在设置的「此设备」里），默认开。关掉用的是 PostHog 自己的 `opt_out_capturing()`，选择由 PostHog 存在这个浏览器里；关掉后事件、错误、会话回放都不再发（回放的录制也停掉）。reset 会清掉这个选择，所以 reset 后重新 opt out。构建时没有 key 的话不显示这个开关。
- **错误**：页面上未捕获的异常和 promise 拒绝；核心 worker（SharedWorker / Worker）里捕获到的错误由 worker 转给一个页面上报；worker 崩溃（`{fatal}`）或起不来也上报。核心照常运行但本机少存了东西时也报一条（data.ts `#report`，只带 SQLite 的报错，不带内容）：`LocalDbFailed`（账号的本机库打不开，这次只放在内存里）、`LocalDbBusy`（被另一个进程占着）、`LocalDbMadeAgain`（库文件坏了，删掉重建，消息里有原因和带过去几行本机做的改动）。每个事件都带 `release`（构建时的 git 提交）和 `app`（`cloud` / `station`）。
- **会话回放**：所有文字、所有输入框都打码；图片、视频、canvas 整块挡掉；`title`、`alt`、`aria-label`、`placeholder`、`href`、`src` 等可能带人名、文件名、对话名的属性打码。回放里只有布局和操作。控制台日志不录。登录回调页（URL 里有 Google 的 code）不录。是否录制还取决于 PostHog 项目设置里的 Session replay 开关。
- **事件**（不按键入发）：

  | 事件 | 属性 |
  |---|---|
  | `sign_in` | — |
  | `chat_opened` | `surface`（ember / slack）、`open`（本次页面加载打开的第一个对话为 cold，之后为 warm）、`ms`（从点击到消息出现；cold 且不是点进来的，从页面开始加载算） |
  | `message_sent` | `attachments`、`quotes`（个数）、`first`（是否新建对话的第一条）、`ok`、`ms`（到 station 收到为止） |
  | `chat_created` | `runtime`、`model`、`effort`、`ms` |
  | `workspace_created` | `first`（登录后自动建的第一个） |
  | `station_added` | `ms`（从生成命令到 station 出现在列表里） |
  | `workspace_opened` | 每次页面加载第一次显示出 workspace（不再是「正在打开 workspace」）时发一次：`ms`（从页面开始加载算）、`kept`（是不是靠本机存的数据打开的；false 是等 still.fail cloud 的 `/v1/me` 回来才打开）、`accounts`（登录的账号数） |
  | `page_loaded` | 每次页面加载发一次（`web/src/reloads.ts`）：`reason`（页面自己重新加载的原因：`pull` 下拉手机的聊天列表、`update` 点了「有新版本 · 刷新」、`retired` 同一浏览器里别的标签页开了新版、`button` 点了「重新加载」；`none` 不是页面自己重载的，比如浏览器的刷新按钮，或 iOS 回收了后台标签页、看它时重新加载）、`navigation`（浏览器给的 navigate / reload / back_forward）、`follows`（这个标签页里之前有没有页面）；有的话再带 `after_s`（上一个页面开了多久）、`hidden_s`（它已经在后台多久，-1 是还在前台） |
  | `$pageview` | 只在路由变化时发 |

- **URL**：所有事件里的 URL 都把 id 换成占位（`/w/:workspace/s/:station/chats/:thread`），路由里固定的词以外的段一律换成 `:id`（Profile 的 key 带着邮箱，skill 的名字可能是客户名；`pathTemplate`，`test/telemetry-paths.test.ts`），去掉查询串和 `#` 之后的部分；别的域名只留域名。不开 autocapture（它会记元素里的文字），也不开热图、死点击、rage click。

## station

`station/src/ops/telemetry.ts`，只做错误追踪，**默认关闭**。station 跑在用户自己的机器上，由它的管理者在 `config.json` 里打开：

```json
{ "telemetry": { "errors": true } }
```

打开后（改配置立即生效，关掉也立即停）上报：error 级别的每一条日志。每条带 station 的 id（有 mesh 登记时）和 `release`。日志的字段一律不发（可能带着人写的东西），只发那句话和其中的错误信息；错误信息里家目录下的路径换成 `~`，引号括起来的内容换成 `"…"`（比如 JSON 解析错误会把输入引出来）。

### station 的日志

`station/src/ops/log-export.ts`，**默认开**（2026-10-29 用户定：「应该脱敏默认发，然后用户可以关闭，不然 debug 都没法搞」）。起因是用户 station 之间共享 skill 不同步，要看的是两台连 still.fail cloud 的记录（`presence` 那几行），我们这边一条都没有，只能找用户要日志文件。workspace 的管理员在 app 和网页的 station 设置 →「诊断」→「发送运行日志给 still.fail」关掉（`diagnostics.setLogs`，station 的 `PUT /diagnostics/settings {logs}`，概览的 `diagnostics.logs`），或者在 `config.json` 里关掉（改配置立即生效）：

```json
{ "telemetry": { "logs": false } }
```

- 发什么：`stillfail.log` 里的每一行（INFO、WARN、ERROR），作为 OpenTelemetry 日志，每 5 秒一批（至多 500 行）发到 control plane 的 `/v1/telemetry/logs`（和 station 的 span 一样用 station 的 key 签名），still.fail cloud 转给 Axiom 的 `/v1/logs`，同一个数据集。资源属性 `service.name: stillfail-station`、`service.version`、`stillfail.station`；每行 `log.target`（`presence`、`share`…）和各字段 `log.<名字>`。
- 脱敏：家目录下的路径换成 `~`；邮箱和用邮箱拼成的 profile id（`zzj3720-gmail-com`）换成 `<email>`；JWT、常见前缀的 API key/token、AWS access key 换成 `<secret>`；引号括起来的内容换成 `"…"`；可能是人写的字段（`text`、`name`、`title`、`command`、`args`、`prompt`、`body`、`question`、`content`）整个换成 `…`；`workspace` 字段不是 workspace id（是名字）时也换成 `…`；每个值最多 2000 字。
- 发不出去（还没登记、mesh 还没起来）的先攒着，最多 5000 行，再多就丢最老的、下一批里说丢了几行；一批发失败就丢掉，不重发；失败每 10 分钟在 stderr 说一次。Comma 不收（`telemetry: null`）。
- 查：Axiom 里 `['ember'] | where ['service.name'] == "stillfail-station" and ['resource.stillfail.station'] startswith "<station id 前几位>"`，按 `_time` 看 `body` 和 `attributes.log.*`。
- 设备的连接（`mesh` 那几行，src/mesh/serve.ts）：`client connected` 在凭据通过时写，`a device's connection ended` 在连接断开时写。两行都带 `device`（设备这个端点 id 的前 12 位）和 `trace`（设备拨号那次 `mesh.connect` 的 trace id，客户端随凭据那行发来的 `traceparent`；后台重拨的没有）；前一行带 `via`（握手走的中继，或 `direct`）和 `ways`，后一行带 `why`（断开的原因，iroh 的原话）、`lasted`（连了多少毫秒）、`ways`（断开时的各条路，没了就用最后一次收到请求时的）、`rx`/`tx`（字节）。`ways` 的写法和慢回复行一样：`*` 是选定的那条，中继或地址、来回、发出/丢掉的包数。把设备那边和 station 这边对起来：`attributes.log.trace == <mesh.connect 的 trace_id>`。

### 中继

北京、香港、深圳三台每分钟由 `cloud/relay-load.sh` 把计数发给 still.fail cloud，Cloudflare 那台由 cloud 的 cron 每分钟读（`cloud/src/relay-load.ts`）。cloud 存一份给后台的中继页，同时把这一分钟（跟上一次相比）做了什么作为一行日志发到 Axiom：`service.name` 是 `stillfail-relay`，资源属性 `stillfail.relay` 是中继的 host，`body` 是 `relay minute`，字段 `log.secs`（离上一次多少秒）、`log.open`（这时连着几个）、`log.accepts`、`log.disconnects`、`log.sent`/`log.recv`（字节）、`log.packets`（转出去的包）、`log.dropped`（丢掉的包：对方不在、队列满，或在队列里等了超过 200 ms，zzj3720/iroh#1）、`log.load1`（机器负载，Cloudflare 那台没有）。两次隔太久（超过 10 分钟）或中继刚开始报的第一次不写。Cloudflare 那台每分钟都写一行（进程没在跑时也写，预算用完它就被停掉），另带它的预算（`cloud/src/relay.ts`、`limits.ts`）离各上限多远：`log.running`（进程在不在跑）、`log.today_bytes`/`log.today_frames`（UTC 零点起转过的，按样本算，和预算的算法一样）、`log.open`、`log.limit_bytes`/`log.limit_frames`/`log.limit_connections`/`log.limit_connects`，`log.full` 是已经撞上的那几项（`bytes`、`frames`、`connections`、`connects`，没有是 `none`）：撞上任何一项，新连接都回 429。每台中继每个连接排队多久不在里面（iroh-relay 不数）。

三台自己机器上的中继还把每个客户端连接在内核里的样子一起报上来（`relay-load.sh` 的 `node_conn` 行，`ss -ti`）：一分钟里发过东西的每条连接一行 `relay conn`，跟这一分钟的 `relay minute` 同一批，字段 `log.peer`（对方地址只留到 /24，IPv6 到 /48）、`log.port`、`log.rtt`/`log.minrtt`（毫秒）、`log.sent`（这条连接开起来以后发出的字节）、`log.again`（其中重发的）、`log.rate`（最近的实际送出速度，bit/s）、`log.limited`（那会儿中继没有更多要发的：速度是没东西可发，不是线路慢）。中继自己的计数看不到最后一段：2026-10-30 衡阳移动的手机经北京只有 8–19 KB/s，北京的计数一切正常，`ss` 上才看得出那段 TCP 的来回和重发。

每台中继（still.fail 的四台）每半小时还从国内各运营商的探针各测一遍（`cloud/src/probes.ts`，Globalping 的免费探针：移动、电信、联通各 5 个，国内机房 3 个，香港 2 个；后几台用第一台那次挑中的同一批探针，好比较）：对中继 443 的 TCP 握手 16 次，每个探针一行 `relay probe`，字段 `log.probe_country`/`log.probe_region`/`log.probe_city`/`log.probe_asn`/`log.probe_network`（探针在哪、哪家运营商）、`log.rtt_avg`/`log.rtt_min`/`log.rtt_max`（毫秒）、`log.loss`（没回的占比，%）、`log.status`。只测来回和丢包，不测能跑多快（那个看设备的 `mesh.speed`）。只在 `RELAY_PROBES` 是 `globalping` 时测（wrangler.jsonc）。各中继在各运营商的来回：

```kusto
['ember']
| where _time > ago(1d) and ['service.name'] == "stillfail-relay" and body == "relay probe"
| summarize rtt = percentile(toreal(['attributes.log.rtt_avg']), 50), loss = avg(toreal(['attributes.log.loss'])), probes = count()
    by relay = ['resource.stillfail.relay'], network = tostring(['attributes.log.probe_network']), city = tostring(['attributes.log.probe_city'])
| order by network asc, city asc, rtt asc
```

## 安卓

安卓 app（`apps/mbui`）的上报在 `apps/mbui/android/app/src/main/java/dev/mbui/`：`Crashes.java`（`Tombstone.java`）报闪退，`MemoryWatch.java` 报原生堆失控，`BarTiming.java` 报下方栏切换的耗时，`CoreProfileReceiver.java` 按需采样核心。MoonBit 那边只告诉宿主它自己才知道的事（`src/stillfail/reports.mbt`：登录的账号、核心死掉重启、下方栏切换、页面新订阅的 topic），时间都由 Java 取。和网页版的错误进同一个项目（`$exception`，`release` 是版本号 `0.1.<n>`，`distinct_id` 是登录账号的 id，和网页版标识的人一样）。

- `app` 是 `android`（正式版和测试版，`beta` 分开二者，`$lib` 是 `stillfail-android`）；每次推送出的 still.fail mbui（`fail.still.mbui`，apps/mbui/README.md）是 `android-mbui`（`$lib` 是 `stillfail-mbui-android`），不算进发布的 app。看的是 manifest 里 `dev.mbui.env` 的 `MBUI_OWN`、`MBUI_BETA`（`android/apk.json` 的各个 variant）。`in_app` 看 `dev.mbui.` 开头的类。
- Java 层未捕获的异常：崩溃时把异常（PostHog 的 `$exception_list` 格式，带 java 帧）写到 app 目录 `files/crashes/<ms>.json`，系统自己不留。
- 每次启动、有账号登录后：读系统的进程退出记录（ApplicationExitInfo，Android 11 起），从上次报到的地方（`crashes.since`；第一次往回看 7 天）起，把闪退、native 崩溃（Hermes、JNI 的 abort）和 ANR 一批发到 `/batch/`。native 崩溃带系统给的 tombstone 解成的文字（崩溃线程的堆栈、abort message、进程最后 50 条 warning/error 日志），ANR 带线程 dump，都放在 `trace` 属性里；native 崩溃另带 `webview`（系统 WebView 的包名和版本，崩在 WebView 里时看是哪个 Chromium）和 `logcat`（报告时从系统日志里读到的那个进程最后 80 条 warning 及以上，有的手机 tombstone 里不带日志）；这两种没有 PostHog 认的帧，用 `$exception_fingerprint`（信号或 ANR 加栈顶几帧）归 issue。每条的 `uuid` 由时间和 pid 定，重发不会重复。在前台或可见时被系统杀掉（内存不足、信号、资源超用、OEM 的管控等，`reason` 是 `killed_low_memory`、`killed_signaled`…）也报一条 `Killed`：用户看到的是闪退回桌面，App 自己没机会报；值是原因、系统给的说明和当时的 PSS/RSS，带 `logcat`，按原因归 issue。在后台被杀是 Android 的常态，不报。
- 原生堆超过 1.5 GB（`MemoryWatch.java`，每 30 秒看一次 `Debug.getNativeHeapAllocatedSize`）：每个进程报一次 `MemoryRunaway`（`$exception_level: error`，`reason: memory_runaway`）。报之前看 15 秒：Rust shell 这段时间里各操作被调了多少次（`shell_calls`，来自 client/shell 的 `sf_shell_stats`；核心和 shell 之间的死循环会是一个操作远远多于其他），进程启动以来各操作的总次数（`shell_calls_total`），没回的调用（`shell_unanswered`），shell 手里各类 handle 的数量（`shell_handles`；`gone` 是已关、已放掉的 iroh 连接），各线程占的 CPU（`threads`，百分之一核），核心 JS 的采样（`js`：不空闲的比例，最热的函数和调用栈，函数写成 `名字@行:列`，对照那个版本的 core.js），以及原生堆的大小和每分钟涨多少。起因是 2026-10 一台 OPPO PLP110 上原生堆每分钟涨约 300 MB，shell 线程在 app 空闲时一直转，模拟器复现不出来。
- 核心死掉重启也当场报一条 `CoreFailed`（`$exception_level: error`，`reason: core_failed`，值是核心给的原因），和网页版的 CoreFailed 一样；用的是最近一次上报时的账号，还没有就是 `android-anonymous`。
- 下方栏切换一次地方发一条 `bar_switch`（`BarTiming.java`；攒 20 条或一分钟一批发到 `/batch/`，`distinct_id` 同上，没有账号就不发）。设备上同时写一行 `adb logcat -s StillfailTiming`，没有 key 的构建也写。时间都从手指抬起算（`touched: false` 是不是点出来的，比如返回手势）：

  | 属性 | |
  |---|---|
  | `from`、`to` | 地方的名字（`chats`、`files`…） |
  | `first` | 这次启动后第一次到这个地方；`away_ms` 离开它多久了 |
  | `place_ms` | 到页面放进栈 |
  | `composed_ms`、`frame_ms` | 到第一次建出新页面的那一帧建完、其后主线程的下一帧（交给屏幕了） |
  | `frames`、`longest_frame_ms`、`frame_gaps_ms` | 从点到 `frame_ms` 之间的帧和间隔：主线程卡没卡 |
  | `cut` | 3 秒内没走完，或被下一次切换打断 |
  | `topics` | 页面新订阅的每个 topic：`topic`（名字，不带参数）、`core_ms`（订阅到第一条消息在 UI 线程解完）、`tap_shown_ms`、`bytes`（第一个值的 JSON 大小）、`failed` |

- release 包关了 R8 的混淆（`android/app/proguard-rules.pro` 的 `-dontobfuscate`，保留行号），堆栈里是原名，不用上传 mapping。
- 构建时由 `STILLFAIL_POSTHOG` 指向的文件给 key（`android/apk.json` 的 `strings`：`posthog_host`、`posthog_key`）；CI 的安卓构建从 `POSTHOG_JSON` 写这个文件（`.github/release.sh android`、`.github/workflows/mbui.yml` → `apps/mbui/scripts/beta.sh build`）。没有 key 的构建（本地、开发）什么都不发。
- 设置 → 此设备里的「发送使用统计和错误报告」（默认开，只存在这台设备上，app prefs `stillfail` 的 `telemetry`，`Crashes.reporting`；没有 key 的构建不显示）关掉后，以上都不发：都经 `Crashes.send` 发出，它先看这个开关；关着时的闪退也不留到以后再报。
- 采样 core：`adb shell am broadcast -n <包名>/dev.mbui.CoreProfileReceiver --ei seconds 60`（正式版 `fail.still.android`）。

## key 从哪来

项目 key 是 PostHog 的公开 key（`phc_…`），本来就会出现在网页里，但和别的部署输入一样不进仓库：放在部署目录（`STILLFAIL_DEPLOY_DIR`，默认 `~/stillfail-deploy`）的 `posthog.json`，内容 `{ "host": "https://us.i.posthog.com", "key": "phc_…" }`。

构建时由环境变量 `STILLFAIL_POSTHOG`（改名前是 `EMBER_POSTHOG`，也认）指向这个文件，`web/vite.config.ts`（网页）和 `scripts/posthog-key.ts`（station）读它：

- `cloud/deploy.py` 构建网页版时自动设置（文件不存在就构建一个没有分析的版本，并提示）。
- station 的构建：`STILLFAIL_POSTHOG=~/stillfail-deploy/posthog.json pnpm build`。station 没有自己的页面了，`pnpm build` 只编 iroh 的 wasm 并把 key 写到 `dist/admin/posthog.json`（scripts/posthog-key.ts），发布包带着它，station 启动时从那里读，所以管理者只需打开配置，不需要别的设置。
- 不设 `STILLFAIL_POSTHOG` 的构建（本地、开发）没有任何分析，station 也无从上报。

# Telemetry

## Tracing

When something is slow, one trace per user action shows where the time went,
hop by hop: the client core (the web's SharedWorker or a native app), still.fail
cloud, and ember-mesh on the station. Spans are
OpenTelemetry (OTLP JSON) and end up in Axiom, dataset `ember`.

### What is traced

A **trace** starts in the client core (`client/core-ts/src/trace.ts`) for each
user-facing operation:

| Trace (root span) | When |
| --- | --- |
| `chat.open` | a chat's page's first subscriber, until its first value goes out (store.ts `OPENED`): `stillfail.work_ms` what the core spent making it (computing it, and putting it through its shape), the rest of its time waited (for what it is made from, or for the core busy with something else); `stillfail.computes` how many times it was made before it had a value; `stillfail.anew` whether the core made its view anew rather than keeping it from a page shown a moment ago; cancelled when the page was left first |
| `core.flush` | a round of topics going out that held the core 50 ms or more (`FLUSH_HELD_MS`): `stillfail.held_ms`, `stillfail.topics` how many, `stillfail.slowest` the topic that took longest and `stillfail.slowest_ms` |
| the call's name: `chat.send`, `chat.older`, `chat.read`, `job.stop`, `workspace.rename`, … | every call, until it answers; one that asked nothing of the network and answered well within 100 ms is not recorded (`QUIET_MS`: a scroll position kept, the focus moving, a draft saved were 41% of a phone's spans) |
| `station.connect`, `station.reconnect` | a station's events stream opening (when a view asked for it, `station.connect` is part of that view's trace), and opening again after it was down, until everything it may have missed is read again. `stillfail.resumed`: the station told what came since the last event heard (nothing is read again); a reconnect says how the stream before it went: `stillfail.previous.end` (why it ended), `stillfail.previous.lasted_ms`, and what came on it, `stillfail.previous.bytes` (over the link, compressed), `stillfail.previous.read_bytes` (as read) and `stillfail.previous.events` |
| `client.wake` | every time the UI says it is back on screen or the network changed (`client.wake`), always recorded: `stillfail.away_ms` how long it was off screen, `stillfail.network` / `stillfail.retry` when that is why, `stillfail.reset` whether the connections under the core were taken for gone. Several stations' links ending in the same second just before one says the app was frozen off screen |
| `ignored` | a failure the core let go of on purpose, which nothing waited on (`Effect.ignore(…, { log: "Unhandled", message })`: a file kept in the background, a read nobody asked for, a native handle closed): `stillfail.ignored` the `message` (what was let go of: `speeds kept`, `me read`, `socket closed`), `error.type` and `stillfail.cause` as any failed span's. A failure someone does wait on (a `Deferred` another fiber answers) is said where it is waited on, not here |

Inside a trace:

- **core**: a span per station request (`GET /admin/api/threads/:id/messages`),
  ending when the whole answer is read — an event stream's when it is open
  (`ember.stream`); `station.connect` for the events stream a view asked for;
  `mesh.connect` when a request has to open the link first (credential, iroh
  connection; every way dialled at once, `stillfail.via` the relay of the one
  that came through first), with the still.fail cloud requests it made. Where
  its time went, in ms from the dial's start: `stillfail.onto_ms` (the endpoint
  on a relay; 0 at once, or not before the connection was made),
  `stillfail.dialled_ms` (the connection made), `stillfail.credential_ms` (the
  credential had: about 0 kept on the device); and `stillfail.paths`, each way's
  round trip and packets sent/lost as it ended (as `mesh.route`'s);
  `stillfail.asker`, what first waited on it (a request's method and route,
  `screen`, or `again`: the mesh opening it anew itself, nobody waiting). One that
  failed says what it was given and had beside it: `stillfail.ips` (the addresses
  the station said it is reached straight at, given to the dial) and
  `stillfail.beside` (this device's other open links to the same station, in
  another workspace: each one's workspace and paths, as `mesh.route`'s). Its
  `traceparent` goes to the station with the credential, which says its trace
  on its log lines of the connection (`client connected`, `a device's
  connection ended`, above). The
  station says a connection whose handshake failed on its log (`mesh: a
  connection's handshake failed from …`: a relay's or an address, and how long
  it took); none said means none came. still.fail
  cloud requests made inside the trace (`/v1/me`, credentials, workspaces).
- **core, on its own**: `mesh.route` when a station's requests move to another
  way (`stillfail.why`: `better` by its pings, `asked`, `lost`, `direct` as a
  way gone direct answers clearly quicker, `lan` to the way dialled at the
  station's LAN addresses, docs/mesh-lan.md), with
  `stillfail.from`/`stillfail.to` (the relay, or `direct`) and their scores in
  ms (`.score`: round trip, a typical reply at the speed seen, twice the
  deviation); `.paths`: every way iroh has for that connection (`*` the one
  chosen; a relay's host or a direct way's `ip:port`, round trip, packets
  sent/lost); `stillfail.from.missed`: its pings missed in a row.
- **core, on its own**: `mesh.path` when a way's paths change at a tick (one
  opened or gone, another chosen; a way first seen already direct) or it misses
  its first ping in a row (`stillfail.why`: `paths`, `missed`, or both), with
  `stillfail.way` (its key now), `stillfail.current` (whether the requests go
  on it), `stillfail.paths` and `stillfail.before.paths` as the tick before saw
  them (the same form as `mesh.route`'s), docs/mesh-lan.md.
- **core, on its own**: `mesh.speed` when a reply of `SPEED_MIN_BYTES` or more
  told how fast a relay brings a station's replies (mesh.ts `timed`): at most
  once a minute for each station and relay. `stillfail.via` (the relay's host),
  `stillfail.bytes`, `stillfail.ms`, `stillfail.bps`, `stillfail.current`
  (whether the requests go on that way), `stillfail.paths` (as `mesh.route`'s).
  Every one seen, the slower too, not only the fastest the device keeps for
  choosing its way: how the relays bring replies to devices, network by network.
- **still.fail cloud, on every client's and station's spans and on stations' log
  lines**: the network the batch came from, as Cloudflare saw it, as resource
  attributes (in Axiom under `['resource.custom']` on spans)
  `stillfail.net.asn`, `stillfail.net.org` (the carrier: China Mobile, Chinanet…),
  `stillfail.net.country`, `stillfail.net.region` (the province), `stillfail.net.city`;
  never the address (tracing.ts `networkOf`). A device behind a VPN shows the
  VPN's.
- **still.fail cloud**: a span of each `/v1/*` call that carries a recorded
  `traceparent`.
- **ember-mesh**: a span per request stream, from the stream accepted to the
  answer's last byte written (an event stream's: to its head). The station's
  admin API runs in the same process (`stillfail-station`) and has no span of its
  own.

A request without a trace (one an event caused, a stream's later reads) is a
trace of its own, one span per hop.

Every station request carries a W3C `traceparent`; ember-mesh records its span
under it, so the hops nest. Requests to
still.fail cloud carry one only inside a trace.

Attributes: `http.request.method`, `url.path` (the route with ids as `:id`,
no query), `http.response.status_code`, sizes (`http.request.body.size`,
`http.response.body.size`), `ember.station` (the station's id), `ember.path`
(`relay`, `direct`, or `local` for a station's own page), `ember.stream`,
`ember.cancelled` (the span's task ended before it did: the chat was closed
before it opened), `error.type`, `stillfail.cause` (what the transport said where a connection failed under it:
people are told only 无法连接此 station or 连接中断). Never message content, titles, file names or
emails. `service.name` says which hop: `ember-web`, `ember-native`,
`stillfail-cloud`, `ember-mesh` (historical cloud spans use `ember-cloud`); a station's spans also carry the
resource attribute `ember.station`, and a client's `service.version`, its app's build (`0.1.2420`) once its UI has
said it (`client.device`).

Times: the web core times with `performance.now()`, native with a monotonic
clock (`Host::monotonic_ms`), converted to Unix nanoseconds from the wall
clock read once when the trace started. ember-mesh does the same with its
own clock, so hops on different machines are only as aligned
as their clocks; durations are exact.

### Where spans go

Nothing ships Axiom's token: it lives only in still.fail cloud (`AXIOM_TOKEN`,
`AXIOM_DATASET`, which `cloud/deploy.py` uploads from
`~/stillfail-deploy/axiom.json`). Clients and stations send their spans to still.fail
cloud's `POST /v1/telemetry/traces` (OTLP JSON, at most 512 KB and 1000 spans a
batch), which forwards them to `https://api.axiom.co/v1/traces`:

- a client core batches for 3 s (`EXPORT_MS`) after a span ends and sends as
  its first signed-in account (`Authorization: Bearer`); with nobody signed in
  the batch is dropped.
- ember-mesh batches the same way and signs each batch with the
  station's key: headers `x-ember-station`, `x-ember-ts` (unix seconds, within
  5 minutes) and `x-ember-signature` over
  `ember-station-telemetry-v1:<origin>:<station>:<ts>:<sha256 of the body, hex>`;
  the station must be enrolled.
- still.fail cloud sends its own spans to Axiom directly, after answering
  (`ctx.waitUntil`).

A batch that cannot be sent is dropped, never retried. still.fail cloud allows each
sender (an account, a station) 60 batches a minute (`429` beyond), answers
`503` while it has no Axiom token and `502` when Axiom refuses.

### Sampling and opt-in

- Client cores record every trace (`trace::SAMPLE = 1.0`; lower it as use
  grows). A trace not sampled still sends its `traceparent`, with flags `00`,
  so no hop records it.
- Stations send spans only when their config says so:

  ```json
  { "telemetry": { "traces": true } }
  ```

  in `config.json` (off by default; read when `stillfail-station` starts, so
  restart the station after changing it). Off, ember-mesh records nothing but
  still passes the `traceparent` on.
- still.fail cloud records a span only for a call whose `traceparent` is sampled.

### Looking in Axiom

Dataset `ember`. The slowest chat opens today, with the longest span of each
hop in them:

```kusto
['ember']
| where _time > startofday(now())
| summarize
    open_ms = maxif(duration / 1ms, name == "chat.open"),
    link_ms = maxif(duration / 1ms, name == "mesh.connect"),
    cloud_ms = maxif(duration / 1ms, ['service.name'] in ("stillfail-cloud", "ember-cloud")),
    mesh_ms = maxif(duration / 1ms, ['service.name'] == "ember-mesh")
    by trace_id
| where open_ms > 0
| top 10 by open_ms desc
```

Read it as: `open_ms` is what the user waited; `link_ms` opening the link to
the station (credential plus iroh connection); `mesh_ms` a request's time on the
station (the admin API's included); what a core request span
took beyond its mesh span was the network (the relay, or the direct path).
How each relay does for each network over the last day: how fast replies came (`mesh.speed`), how long a link took and
how many failed (`mesh.connect`), by relay, carrier and province:

```kusto
['ember']
| where _time > ago(1d) and name in ("mesh.speed", "mesh.connect")
| extend relay = tostring(['attributes.custom']['stillfail.via']), carrier = tostring(['resource.custom']['stillfail.net.org']), province = tostring(['resource.custom']['stillfail.net.region'])
| summarize
    speeds = countif(name == "mesh.speed"),
    kbps_p50 = percentileif(toreal(['attributes.custom']['stillfail.bps']) / 1024, 50, name == "mesh.speed"),
    kbps_p10 = percentileif(toreal(['attributes.custom']['stillfail.bps']) / 1024, 10, name == "mesh.speed"),
    connects = countif(name == "mesh.connect"),
    connect_ms_p50 = percentileif(duration / 1ms, 50, name == "mesh.connect" and error != true),
    failed = countif(name == "mesh.connect" and error == true)
    by relay, carrier, province
| order by carrier asc, province asc, kbps_p50 desc
```

(A failed `mesh.connect` has no `stillfail.via`: its row is the one with no relay.) The last stretch from each relay to
its clients, the worst first (`relay conn`, above): the share sent again and the delivery rate, by the client's /24:

```kusto
['ember']
| where _time > ago(1h) and ['service.name'] == "stillfail-relay" and body == "relay conn"
| extend relay = ['resource.stillfail.relay'], peer = tostring(['attributes.log.peer'])
| summarize sent = max(toreal(['attributes.log.sent'])), again = max(toreal(['attributes.log.again'])),
    rtt = avg(toreal(['attributes.log.rtt'])), kbps = percentile(toreal(['attributes.log.rate']) / 8192, 50)
    by relay, peer, port = tostring(['attributes.log.port'])
| summarize sent = sum(sent), again_pct = 100 * sum(again) / sum(sent), rtt = avg(rtt), kbps = avg(kbps) by relay, peer
| where sent > 1000000
| order by again_pct desc
```

One trace in order:

```kusto
['ember']
| where trace_id == "<trace id>"
| project _time, ['service.name'], name, duration, span_id, parent_span_id
| order by _time asc
```

An error people see said with a time (`无法连接此 station（10月28日 00:40:14）`: the network, a host or a station's own fault,
CoreError `stamped`) failed at that second, the device's local time; its failed spans, the transport's words in
`stillfail.cause` (the zone from the reporter, the version from the feedback):

```kusto
['ember']
| where _time between (datetime(2026-10-27T16:40:09Z) .. datetime(2026-10-27T16:40:19Z)) and error == true
| where ['service.version'] == "0.1.5779"
| project _time, ['service.name'], name, duration, trace_id, ['attributes.custom']['stillfail.cause']
| order by _time asc
```

The attributes above are under `attributes` (Axiom puts those OpenTelemetry
does not define under `attributes.custom`, e.g.
`['attributes.custom']['ember.path']`).

### Signing out

A device that keeps being signed out is explained by its refreshes. Every
refresh of an account's credentials is a trace of its own (`auth.refresh`,
recorded whatever the sampling), and still.fail cloud's span of it
(`POST /v1/auth/refresh`) says what became of the session:

| attribute (`attributes.custom`) | |
|---|---|
| `stillfail.account`, `stillfail.session` | whose session (the Google `sub`, the session id) |
| `stillfail.auth.outcome` | `rotated`, `retried` (the credential that last rotated again, within the 120 s retry window), `retried_late` (the same past the window, while what it rotated to is unused: the same credentials, a new access one), `reused` (any other older credential: the session is revoked and the device signed out), `no_session`, `invalid_token`, `limited` |
| `stillfail.auth.presented_generation`, `stillfail.auth.generation` | the credential's generation, and the session's |
| `stillfail.auth.rotated_ago` | seconds since the session last rotated (sessions rotated since this was kept) |
| `stillfail.auth.gone` | for `no_session`: `reused`, `logout`, `logout_all`, `removed` (from another device's session list), `blocked`, `expired`, `idle`, `no_account`, `unknown` (pruned, or ended before endings were kept); `stillfail.auth.ended_ago` seconds since |

The core's own span adds `error.type` (the cloud's code, or the network error)
and `stillfail.auth.unanswered_ago_ms`: how long ago a refresh got no answer,
after which the cloud may have rotated the credential all the same. A device
signed out by its refresh cannot send its own span any more (nobody is signed
in to send it until it signs in again); the cloud's is always there.

```kusto
['ember']
| where _time > ago(7d) and name == "POST /v1/auth/refresh"
| extend outcome = tostring(['attributes.custom']['stillfail.auth.outcome'])
| where outcome != "rotated"
| project _time, account = ['attributes.custom']['stillfail.account'], outcome,
    gone = ['attributes.custom']['stillfail.auth.gone'],
    rotated_ago = ['attributes.custom']['stillfail.auth.rotated_ago'], trace_id
| order by _time desc
```
