# 客户端 core 用 TypeScript 重写：设计方案（草案）

2026-10-03 用户定：「接着做 ts 化，把 rust core 换掉」。station 的 TS 化（docs/station-ts.md）之后，客户端的 core（`client/core`，约 3.4 万行 Rust、595 个测试）也换成 TS。做法和 station 一样：Rust 只留固定的壳（iroh），逻辑全部 TS。

## 目标与不做的事

- 一份 TS core，三端共用：web（SharedWorker）、桌面（Electron utilityProcess）、安卓（Hermes）。
- **UI 一行不改**：UI ↔ core 的 JSON 协议（docs/client-core.md「Protocol」）、所有 call 和 topic 的名字与形状原样保留；安卓的 `Engine` 接口（connect/receive/close）原样保留，只是换一个实现。
- **数据兼容**：core 的数据库（docs/core-db.md 的记录）、storage 里的键（账号、token、设备密钥、偏好）、kept 的条目，新旧 core 都能读；升级不丢登录、不丢缓存，也能退回 Rust core。
- 不做：改 UI、改协议、改 cloud/station 的接口。

## 进程结构（每端）

| 端 | core 跑在哪 | Host（网络、存储、时间） | iroh（连 station） |
|---|---|---|---|
| Web | 现在的 SharedWorker（缺 SharedWorker 时的专用 Worker），直接跑 TS | 浏览器 API：fetch、WebSocket、IndexedDB | 一个只含 iroh 的小 wasm 包（relay-only，浏览器没 UDP），从现在的 `client/wasm` 里拆出来 |
| 桌面 | Electron 的 utilityProcess（Node），直接跑 TS | Node API：fetch、ws、`node:sqlite`、文件 | napi 插件，复用 station 的 `mesh.node`（同一套 bind/connect/stream） |
| 安卓 | 一个专用线程上的 Hermes，跑预编译的 Hermes 字节码 | Kotlin 实现，经 JSI 交给 JS：OkHttp、SQLite、文件 | Rust（现在 `client/ffi` 里的 iroh 部分），经 JNI 暴露 |

为什么安卓选 Hermes：分支 `proto-rust-shell-ts` 的原型实测过，Hermes 跑 TS core 不比 Rust 慢、内存更省；QuickJS 慢 3–5 倍且没有 `Intl`。

## Host 与 Mesh 接口（TS）

- `Host`：照搬 `client/core/src/host.rs` 的 trait——`fetch`/`fetchStream`/`websocket`、`storage*`、`dbRead/dbWrite`、`nowMs`/`monotonicMs`/`utcOffsetMin`、`sleep`、`woken`、`resetConnections`、`randomBytes`、`emit`。异步一律 Effect（docs/station-ts.md「写法：Effect」），定时器走 Effect 的 Clock，测试用 TestClock；不在逻辑里直接用 setTimeout。
- `Mesh`：iroh 的最小面——建 endpoint、连某个 station（地址 + relay）、开双向流、读写、关；和 station 的 `mesh.node` 同一套形状，三端各自实现。凭证、续期、请求行格式这些协议逻辑在 TS 里（照 `client/core/src/mesh.rs`、`station/transport.rs`）。

## 类型

`client/shapes`（typeshare）现在从 Rust 生成 UI 用的 TS 和 Kotlin 类型。第一步不动它：TS core 直接 import 生成的 TS 类型，UI 那边什么都不变。等 Rust core 删掉后，再把类型的源头挪到 TS（从 TS 生成 Kotlin）。

## 怎么验证

- **测试照搬**：`client/core` 的 595 个测试逐个移植成 TS（同名同断言），核心规则不靠新写。
- **对照运行**：同一组 UI 消息脚本 + 同一个假 Host（假 cloud、假 station、固定时钟和随机数），分别喂给 Rust core（`client/node` 的 napi 插件）和 TS core，逐条比较发给 UI 的消息。能对上的才算搬完。
- **端到端**：dev cloud + 临时 station（docs 里已有的做法），web 用 TS core 跑一遍登录、看 chat、发消息、停止、归档；安卓在模拟器上跑同样的路径。
- 每期量：内存、首屏时间、包大小，和 Rust core 放一起对比。

## 分期

1. **地基**：`client/core-ts` 包；协议、Host/Mesh 接口、Core 骨架（连接、call 分发、订阅、topic store）；账号、cloud、workspace topic、cloud 的 `/v1/events`；Node host；对照运行的框架。完成标志：账号和 workspace 相关的 call/topic 与 Rust core 对照一致。
2. **station 链路**：mesh 连接与凭证、station transport、`/events` 订阅、侧栏/会话/线程/消息的 topic、数据库记录与同步、kept 条目、发消息/outbox。完成标志：对照运行里「看 chat、发消息」整条一致。
3. **其余**：决策、jobs、adb、用量、管理视图、present/状态、doing/changing、通知等全部模块；595 个测试全部移植并通过。
4. **桌面切换**：utilityProcess 换成 TS core + `mesh.node`；桌面 app 端到端。
5. **Web 切换**：拆出 iroh-only wasm；worker 换成 TS core；IndexedDB host；web 端到端（dev cloud）。
6. **安卓切换**：Hermes + JSI host + JNI 的 iroh；`Engine` 换实现；模拟器端到端、真机测内存和流畅度。
7. **删掉 Rust core**：`client/core`、`client/wasm`、`client/node`、`client/ffi` 里的逻辑部分；类型源头挪到 TS。

每期都在分支 `core-ts` 上做完、给证据，用户认可再往下；合并时机由用户定。

## 待定

- 安卓的 Hermes 是自己编（不带 React Native）还是用 RN 发布的预编译库：倾向后者，第 6 期再定。
- iOS：现在没有，将来也走 Hermes（同安卓）。

## 设计规则（2026-10-03 用户定：照设计做，不照 Rust 逐行搬）

Rust core 有不少地方不符合设计，TS core 不以「和 Rust 一样」为目标。只有两样必须和 Rust 完全一样：UI 协议（call/topic
的名字和 JSON 形状）和设备上的存储（storage 的键和格式、`core.db` 的表和记录），这样老 UI 不用改、登录和缓存升级不丢、
也能退回 Rust core。其余一律按下面的规则：

1. **异步全是 Effect**：call、订阅、station 链路、cloud socket、同步，都是挂在 scope 里的 fiber；取消就是 interrupt；
   重试和退避用 Schedule；计时走 Clock（测试用 TestClock）。Host 的接口也返回 Effect。
2. **推送，不轮询**：订阅先给当前值，再给变化；station 和 cloud 的状态靠事件来，任何数据都不定时重读。只有显示在屏幕上的
   测量值（链路速率、RTT、「已等 3 秒」）可以在被看着的时候采样。
3. **docs/core-db.md 全做完**：所有业务数据都是记录，包括 Rust 还放在 kept.rs 里的消息 entries 和 transcript、已读位置、
   outbox；视图从记录算出来，推 delta；启动先从数据库出值，再联网；每条记录带最后一次被来源确认的时间。
4. **用户操作不等网络**：操作在 core 里立刻生效（outbox、待建的 chat、改名/置顶/归档的覆盖层、已回答），`doing` 跟踪，
   失败回滚并说明原因；跨 station 的话题是流式的：到了多少显示多少，station 陆续补进来，不用 loading 挡住已有的内容。
5. **UI 不发请求**：一切都是 core 的具名 call；数据和逻辑（草稿、选择、状态、PC 和手机的差别）都在 core 里。
6. **core 把一切缓存在数据库里，UI 读几乎总是命中缓存**：core 和 station/cloud 之间的同步一直自己跑，不看 UI 显示什么、
   订阅什么；UI 最多改同步任务的**优先级**（比如打开的 chat 的消息先同步），不能开始或停止同步。所以订阅只读记录，从不
   触发网络请求；所有 station/cloud 的流量归一个同步调度器（Effect）管，优先级由 UI 的 focus/订阅调整；数据还没同步到的
   视图显示已有的，记录到了再补上。
7. **workspace 互相隔离**（docs/client-core.md、client/core/src/workspace.rs 的意图）；本地先建的东西和 station 的对应项只靠
   确切的 clientKey 对上，绝不猜。

对照运行因此只比两件事：协议形状，和同一个脚本下 UI 最终看到的结果。下面「刻意不同」一节列出 TS core 因为 Rust 违反
上面某条规则而故意做得不一样的每一处。

## 刻意和 Rust core 不同的地方

（随做随补；每条写明违反了哪条规则。）

- 规则 6：Rust 的话题在被订阅时才去读（`Stations::start` → `refetch`，`start_topic` → `spawn_refresh`，chat 打开时
  `open_thread` 读窗口，`job`/`jobLog`/`slackApp`/`footprint`/`stationUsage`/`loginSessions`/`admin` 都是订阅时读）；TS 的订阅
  只读记录，读请求都由同步调度器发起，订阅和 `client.focus` 只调高相关任务的优先级。
- 规则 6：Rust 的 `sync.rs` 只同步 workspace、station 的 rows/sessions/threads/overview 和在跑的 agent 的 live；消息由
  `warm` 顺带拉。TS 的同步调度器同步全部业务数据（含每个 chat 的 entries），按优先级排队。
- 规则 6：cloud 的 `/v1/events` socket 在账号登录期间一直开着（Rust 只在有 account 话题时开）；账号的 workspace 列表一变，
  它能到的每个 workspace 都重读（Rust 只重读列表，workspace 要等 socket 重连或该话题被订阅才读）；登录设备列表、运营
  列表也由同步维护，不靠订阅触发。
- 规则 1：Host 的接口是 Effect（Rust 是 future），流式的 body 和 WebSocket 是在 scope 里的 pull 句柄，scope 关了就关。
- 规则 2：老 station 不跟随 job 日志时，Rust 每 2 秒起退避重读 `/jobs/:id/log`；TS 不重读，只在事件里更新（老 station 上
  日志面板不再自动增长，打开时读一次）。
- 规则 2：`job` 话题 Rust 每半分钟（老 station 每 4 秒）重读 `/jobs/:id`；TS 只靠 `job` 事件。
- 规则 3：消息 entries、transcript、已读位置、outbox 在 TS 里是 `core.db` 的记录（新表），不再用 kept.rs 的 storage 分块；
  第一次启动时把 Rust 留下的 kept 分块导入成记录（老数据不丢），之后不再写 kept 分块（退回 Rust 时它会从 station 重新读）。
- 规则 3：每条记录带「最后确认时间」（新表 `confirmed`，键 `<表>␁<键>`），Rust 没有。

## 进度与交接（随做随更新）

代码在 `client/core-ts/`（pnpm 包，`node --test test/*.test.ts`，`npx tsgo --noEmit`），文件按 Rust 模块一一对应
（`src/core.ts` + `src/core/{calls,execute,routing,account_state}.ts` 对应 `core.rs` + `core/*.rs`，其余同名）。
在 studio 上跑：`rsync` 到 `~/ember-wt/core-ts/`，`cd client/core-ts && pnpm install && node --test test/*.test.ts`。

写法：
- 异步 IO 是 Promise；定时一律走 `Runner`（`src/runtime.ts`，Effect 的 Clock），长活（cloud 的 events socket）是 Effect fiber；
  测试用 `TestTime`（`src/testing.ts`，TestClock 外包一层记下每次 sleep），`host.time.pass(ms)` 推时间。
- 发给 UI 的值经过 `conform`（`src/conform.ts`）：形状表 `src/shapes-schema.ts` 由 `scripts/shapes-schema.ts` 从
  `client/shapes` 的 Rust 源生成（`--check` 检查是否过期），报错文字照 serde 的写法。
- trace 的上下文在 JS 里没法跨 await 自动带，所以显式传（`ctx` 参数）。
- 参数校验的错误文字照 serde（`src/core/params.ts`），UI 看到的和 Rust core 一样。
- JSON 的对象键按 serde_json 的顺序（排序）写盘和算 delta（`util.ts` 的 `toJson`/`compareKeys`）。

对照运行：`client/core-ts/harness/`（假 cloud `cloud.ts`、脚本 `script.ts`、`run.ts`）。Rust 一侧是 studio 上
`cd client && cargo build --release -p stillfail-core-node` 出的 `target/release/libstillfail_core_node.dylib`（拷成 `.node`）。
`node harness/run.ts <addon>`：每一步比较两边发给 UI 的全部消息（同一订阅/调用内的顺序必须一样；不同订阅之间的先后
按各自 core 的调度，Rust 那边本来就随 HashMap 顺序变）和每个订阅应用 delta 后的值。只抹掉 PKCE 的 state/challenge、
cloud 的端口、`doing` 的 `since`。

已完成（2026-10-03 按设计规则重写后）：
- 地基全换成 Effect：Host、Runner（scope + FiberSet）、Store 的发送窗口和回收、Data 的单写 fiber 和新表（`confirmed`、
  `entry`、`transcript`、`outbox` 等）、Accounts（刷新用 Deferred 单飞）、Cloud、Status、Trace、wake（hedge/drop 用
  race）、call 的执行（可取消的 call 是可 interrupt 的 fiber）。
- 同步调度器 `src/sync/scheduler.ts`（按 lane 限并发、按 key 去重、按优先级取，UI 只能 `prioritize`）和 cloud 同步
  `src/sync/cloud.ts`（socket、/v1/me、workspace、登录设备、运营列表）。订阅只读记录（`core/routing.ts`）。
- 对照运行：44 步里 42 步一致，2 步是规则 6 带来的刻意不同（见上），最终 UI 状态完全一致。测试 79 个通过。

此前（第一版，照 Rust 写的，已被上面取代）：
1. 第 1 期（2026-10-03）：协议、Host、Store/delta、data center、accounts、cloud、status、workspace、wake、trace、ops、
   calls（全部 call 的解析）、prefs、doing、format、shapes 的 model/reasoning、i18n、Node host、假 Host。
   对照运行 44 步全部一致（账号登录登出、accounts/workspaces/workspace/loginSessions/status/prefs/doing 话题、
   cloud 写操作和 events socket 推送与断线重连、草稿、各种错误）。移植测试 79 个通过。

下一步（按顺序）：mesh（iroh 走 station 的 `mesh.node` 形状，见 `station/src/mesh/native.ts`）→ station 链路
（`station.rs`、`station/{wire,transport,events,threads}.rs`、`kept.rs`、`entries.rs`、`sync.rs`）→ views →
其余模块 → 桌面/web/安卓 host。
