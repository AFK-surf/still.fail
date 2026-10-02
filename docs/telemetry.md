# 遥测：PostHog

still.fail 用 PostHog（美国区，`https://us.i.posthog.com`）做产品分析、错误追踪和会话回放。这是我们对自己用户的第一方分析：用 still.fail 的就是团队自己，所以没有同意弹窗。链路追踪另走 Axiom，不在这里。

**什么都不带内容**：聊天文字、引用、文件名、提示词、agent 的输出、对话标题，一样都不发。发出去的只有动作、计数、耗时和错误（带调用栈）。

## 网页版（app.still.fail）

`web/src/telemetry.ts`，在 `web/src/main.tsx` 里启动。构建时没有 key 的话，这些函数什么都不做，bundle 里也没有 posthog-js。管理后台（`admin.still.fail`）什么都不发。

- **身份**：看着哪个 workspace，就以那个 workspace 所用的已登录账号标识（still.fail 账号 id，即 Google `sub`），邮箱作为人的属性；退出这个账号时 reset。station 自己的管理页不标识人。
- **错误**：页面上未捕获的异常和 promise 拒绝；核心 worker（SharedWorker / Worker）里捕获到的错误由 worker 转给一个页面上报；worker 崩溃（`{fatal}`）或起不来也上报。每个事件都带 `release`（构建时的 git 提交）和 `app`（`cloud` / `station`）。
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
  | `$pageview` | 只在路由变化时发 |

- **URL**：所有事件里的 URL 都把 id 换成占位（`/w/:workspace/s/:station/chats/:thread`），去掉查询串和 `#` 之后的部分；别的域名只留域名。不开 autocapture（它会记元素里的文字），也不开热图、死点击、rage click。

## station

`mesh/app/src/telemetry.rs`，只做错误追踪，**默认关闭**。station 跑在用户自己的机器上，由它的管理者在 `config.json` 里打开：

```json
{ "telemetry": { "errors": true } }
```

打开后（改配置立即生效，关掉也立即停）上报：error 级别的每一条日志。每条带 station 的 id（有 mesh 登记时）和 `release`。日志的字段一律不发（可能带着人写的东西），只发那句话和其中的错误信息；错误信息里家目录下的路径换成 `~`，引号括起来的内容换成 `"…"`（比如 JSON 解析错误会把输入引出来）。

## key 从哪来

项目 key 是 PostHog 的公开 key（`phc_…`），本来就会出现在网页里，但和别的部署输入一样不进仓库：放在 studio 的 `~/stillfail-deploy/posthog.json`，内容 `{ "host": "https://us.i.posthog.com", "key": "phc_…" }`。

构建时由环境变量 `STILLFAIL_POSTHOG`（改名前是 `EMBER_POSTHOG`，也认）指向这个文件，`web/vite.config.ts`（网页）和 `scripts/posthog-key.ts`（station）读它：

- `cloud/deploy.py` 构建网页版时自动设置（文件不存在就构建一个没有分析的版本，并提示）。
- station 的构建：`STILLFAIL_POSTHOG=~/stillfail-deploy/posthog.json pnpm build`。station 没有自己的页面了，`pnpm build` 只编 wasm core 并把 key 写到 `dist/admin/posthog.json`（scripts/posthog-key.ts），发布包带着它，station 启动时从那里读，所以管理者只需打开配置，不需要别的设置。
- 不设 `STILLFAIL_POSTHOG` 的构建（本地、开发）没有任何分析，station 也无从上报。

# Telemetry

## Tracing

When something is slow, one trace per user action shows where the time went,
hop by hop: the client core (the web's SharedWorker or a native app), still.fail
cloud, and ember-mesh on the station. Spans are
OpenTelemetry (OTLP JSON) and end up in Axiom, dataset `ember`.

### What is traced

A **trace** starts in the client core (`client/core/src/trace.rs`) for each
user-facing operation:

| Trace (root span) | When |
| --- | --- |
| `chat.open`, `chats.open`, `stations.open`, `connects.open` | a view's first subscriber, until its first value goes out (the requests that make it are read inside it; a chat's agents too, when the value that names them is computed while it is still opening) |
| the call's name: `chat.send`, `chat.older`, `chat.read`, `job.stop`, `workspace.rename`, … | every call, until it answers |
| `station.connect`, `station.reconnect` | a station's events stream opening (when a view asked for it, `station.connect` is part of that view's trace), and opening again after it was down, until everything it may have missed is read again |

Inside a trace:

- **core**: a span per station request (`GET /admin/api/threads/:id/messages`),
  ending when the whole answer is read — an event stream's when it is open
  (`ember.stream`); `station.connect` for the events stream a view asked for;
  `mesh.connect` when a request has to open the link first (credential, iroh
  connection), with the still.fail cloud requests it made; still.fail cloud requests
  made inside the trace (`/v1/me`, credentials, workspaces).
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
before it opened), `error.type`. Never message content, titles, file names or
emails. `service.name` says which hop: `ember-web`, `ember-native`,
`stillfail-cloud`, `ember-mesh` (historical cloud spans use `ember-cloud`); a station's spans also carry the
resource attribute `ember.station`.

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
One trace in order:

```kusto
['ember']
| where trace_id == "<trace id>"
| project _time, ['service.name'], name, duration, span_id, parent_span_id
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
| `stillfail.auth.outcome` | `rotated`, `retried` (the same credential again within the 120 s retry window), `reused` (an older credential outside it: the session is revoked and the device signed out), `no_session`, `invalid_token`, `limited` |
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
