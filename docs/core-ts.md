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
7. **数据按增量订阅来定义**：话题的数据是按稳定 id 分的集合（rows、sessions、threads、entries、jobs…）加少量标量。
   记录变了只重算受影响视图里受影响的那几项（每项按它依赖的记录和版本记忆化，没变的项是同一个对象），集合从不「整个
   重算再 diff」；发给 UI 的是按 key 的增量：插入/更新（patch）/删除/移动，日志类（entries、transcript）用 append，
   一行变了就是一个小 op，不管它在第几行。协议扩展见下面「按 key 的增量」，老 op 继续有效；没声明支持的客户端照旧收老式
   delta。web 和安卓的 delta 应用器都支持新 op，并按 key 保持解码出来的对象稳定，UI 只重绘变了的项。
8. **workspace 互相隔离**（docs/client-core.md、client/core/src/workspace.rs 的意图）；本地先建的东西和 station 的对应项只靠
   确切的 clientKey 对上，绝不猜。

对照运行因此只比两件事：协议形状，和同一个脚本下 UI 最终看到的结果。下面「刻意不同」一节列出 TS core 因为 Rust 违反
上面某条规则而故意做得不一样的每一处。

## 按 key 的增量（协议扩展）

订阅消息可以带 `"keyed": true`（`{ "id": 8, "subscribe": {…}, "keyed": true }`；Rust core 忽略多余字段，照旧发老式 delta）。
声明了的订阅，话题里按 key 的集合（每个话题在 `src/collections.ts` 里声明哪些路径是集合、key 是哪个字段）变了时收到：

```jsonc
{ "path": ["days"], "key": ["daysAgo"], "patch": 0, "ops": [ … ] }                          // 只改 key 为 0 的那一项：ops 相对那一项（可以再是按 key 的）
{ "path": ["days", 0, "items"], "key": ["station", "id"], "put": { … }, "before": ["ws/a", "k2"] } // 插到 key 为 k2 的项前面；before 为 null 放最后；没有 before：原地整项替换
{ "path": ["days", 0, "items"], "key": ["station", "id"], "drop": ["ws/a", "k1"] }           // 删掉
{ "path": ["days", 0, "items"], "key": ["station", "id"], "move": ["ws/a", "k1"], "before": null } // 只挪位置
```

`key` 是组成 key 的字段名列表；key 的值是那个字段的值（一个字段时），或各字段的值按顺序组成的数组（缺的字段算 null）。
同一列表里 key 重复（或缺）时，这个列表照老式 op 发。老式 op（`set`、`append`、`remove`）照旧可用；集合以外的部分照旧用它们。
没声明 `keyed` 的订阅收到同一变化的老式表达（按下标 diff，比整值大就发整值），和 Rust 一样。

集合（`src/collections.ts` 的 `SPECS`）：`chats`（days 按 `daysAgo`，每天的 items 按 `station`+`id`）、`chatSearch`、`chat`
（messages 按 `seq`+`outgoing`，outbox 按 `id`）、`decisions`（items 按 `station`+`session`+`seq`）、`archive`、`chatRows`、
`archivedRows`、`threads`、`sessions`（`key`）、`jobs`。

应用器：web `web/src/core/delta.ts`（页面和桌面主进程共用）、安卓 `apps/android/core/.../Delta.kt`；两边只复制路径上的
数组/对象，没动的项是原来的对象。安卓的 `ChatsDecoder`（和原有的 `ChatDecoder`）按 JSON 对象的同一性复用解码好的
`ChatItem`，所以 Compose 只重组变了的行。web 的 client 和安卓的 bridge 订阅时都带 `keyed: true`（Rust core 忽略它）。

core 这边怎么做到「一行变只算一行」：
- 记录在 `Data` 里冻结（只会被整条替换），`store` 读持有的话题用 `data.shared()`，不复制；没变的记录每次读都是同一个对象。
- 视图按记录做行（`views.ts` 的 `#rowsMade`：记录对象 + 这行用到的其余东西的签名 → 做好的行，冻结），没变的行不再做。
- 输出（`src/output.ts`）按集合逐项装饰（时间文字）和过 shape，项和上次是同一个对象（或相等）且在同一分钟内，就直接用上次
  发出去的那个对象；diff 遇到同一对象直接跳过。

测量（studio，`node bench/keyed.ts`，2000 个 chat 分在 3 台 station，30 次取中位数；「整算」= 本分支 rule 7 之前的 TS core，
即 Rust 的做法：整个视图重算、整值装饰和过 shape、按下标 diff）：

| 变化 | 方式 | 发出字节 | core 耗时 | UI 解析+应用 | UI 拿到的新行对象 |
|---|---|---|---|---|---|
| 一行 unread 变了（原地） | 整算 + 老式 op | 122 | 101 ms | 0.10 ms | 1 |
| | 按 key | 208 | 5.1 ms | 0.09 ms | 1 |
| 一行来了新消息、挪到最上面 | 整算 + 老式 op | 110 682 | 100 ms | 0.43 ms | 136 |
| | 按 key | 1 109 | 5.4 ms | 0.10 ms | 1 |

（同样的改动下老式订阅者的 core 耗时也降到 17–19 ms：行和输出的复用对两种订阅都有效，差的是按下标 diff 和整值称重。）

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
- 规则 7：Rust 每次把话题整个重算再和上次发的整值做 JSON diff（数组按下标比，开头插一行后面全部 set）；TS 按记录变化
  只重算受影响的项，集合按 key 发增量（声明 `keyed` 的订阅）。没变的项在同一分钟内直接用上次发出的对象，所以它的
  时间文字（「3 分钟前」）跟着每分钟的整体刷新走，不会因为别的行变了而顺带刷新（Rust 每次发都重算全部时间文字）。
- 规则 2：老 station 不跟随 job 日志时，Rust 每 2 秒起退避重读 `/jobs/:id/log`；TS 不重读，只在事件里更新（老 station 上
  日志面板不再自动增长，打开时读一次）。
- 规则 2：`job` 话题 Rust 每半分钟（老 station 每 4 秒）重读 `/jobs/:id`；TS 只靠 `job` 事件。
- 规则 3：消息 entries、transcript、已读位置、outbox 在 TS 里是 `core.db` 的记录（新表），不再用 kept.rs 的 storage 分块；
  第一次启动时把 Rust 留下的 kept 分块导入成记录（老数据不丢），之后不再写 kept 分块（退回 Rust 时它会从 station 重新读）。
- 规则 3：每条记录带「最后确认时间」（新表 `confirmed`，键 `<表>␁<键>`），Rust 没有。
- 规则 3、4：发送中的消息（outbox）、在这里建的 chat（pending）、发给还没有 chat 的 agent 的消息（first）、改名/置顶/
  保留/归档的覆盖层（changing）都是 `core.db` 的记录（表 `outbox`、`pending`、`first`、`changing`），重启后还在；没回答的
  发送用同一个 idempotency key 重发、没建完的 chat 重新请求（Rust 这些都只在内存里，重启就丢）。没回答的覆盖层在重启时
  按「被拒」撤掉（它的回答不会再来），station 的行随后会说明到底改没改。
- 规则 6：一个 profile 自 station 启动后没检查过时，Rust 在算「新 chat」页面时顺手发 `profile.check`；TS 在 overview 记录
  进来时由同步发（每次运行每个 profile 一次），和页面开没开无关。
- 规则 6：更新日志（`changelog`）Rust 在页面打开时读（一小时最多一次）；TS 在 core 启动和每次账号的 events socket 打开时
  由同步读，页面只读记录。

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
  `entry`、`transcript`、`outbox`、`pending`、`first`、`changing` 等）、Accounts（刷新用 Deferred 单飞）、Cloud、Status、
  Trace、wake（hedge/drop 用 race）、call 的执行（可取消的 call 是可 interrupt 的 fiber）。
- 同步调度器 `src/sync/scheduler.ts`（按 lane 限并发、按 key 去重、按优先级取，UI 只能 `prioritize`）和 cloud 同步
  `src/sync/cloud.ts`（socket、/v1/me、workspace、登录设备、运营列表）。订阅只读记录（`core/routing.ts`）。
- station 同步 `src/station/sync.ts`：workspace 能到就建链路，events 流每次打开都把 station 整个读一遍（交给调度器），
  事件更新记录；thread 的 entries 和 transcript 是日志记录（按需从库里懒加载），整段从最新页往前补全；写操作用
  `afterWrite` 只读它影响的记录。station 话题 `src/station/topics.ts` 只读记录（thread 窗口、live、net 采样、place）。
- 文字和显示：`present.ts`、`decisions.ts`、`jobs.ts`、`footprint.ts`、`looks.ts`、`history.ts`、`refs.ts`、`notices.ts`、
  `attend.ts`、`pill.ts`、`changelog.ts`、`asks.ts`、`preview-load.ts`、`format.ts`。
- 视图 `src/views/`：chats/chatSearch/chat/stations/connects/decisions/history/archive/workspaceMarks/chatJobs/longJobs/
  usage/admin*，覆盖层 `views/local.ts`（outbox、pending、first、changing、archiving 全是记录），改 chat 的 call
  `views/calls.ts`（发送、建 chat、回答卡片、改名置顶归档，启动时把没做完的接着做）。
- 选择（newChat/pick，`choose.ts`）、表单（自动决策、Slack token、连接向导、加 profile，`forms.ts`）、注意力和通知
  （`attention.ts`）、推送注册。
- mesh（`src/mesh.ts`，对应 mesh.rs + station/wire.rs 的 MeshWire）：凭据握手和续期、共享 opening、UI 回来时 race/hedge、
  relay 测速和换路、当日流量；iroh 由 host 给（`src/iroh.ts`）。Node 用 station 的 napi 插件（`station/native/mesh`，
  已为客户端加了：不广播的 lookup、只走 relay 的 endpoint、附加 ALPN、paths/rtt/stats、单向流、关闭原因、网络变化、
  relay 状态、已知地址）。`test/mesh.test.ts` 在 studio 上起本机 station 端点实测（10 个）。
- 移植的 Rust 测试：present、decisions、jobs、footprint、looks、refs、history、views（43）、usage、admin、notices、attend、
  pill、choose、changelog、asks、forms、preview_load、mesh 的大部分；合计 252 个测试通过（`node --test --test-force-exit`）。
- adb 共享（`src/adb.ts`，host 给 TCP：Node 用 `net`）；Rust kept 分块的一次性导入（`src/kept.ts`，存储标记 `kept-read`，
  原分块不删，退回 Rust 仍可用）。
- 桌面：`apps/desktop` 的 utilityProcess 跑 TS core（`build.sh` 把 `src/hosts/node.ts` 打成 `build/app/core-ts.js`，iroh 用
  `station/native/mesh` 的插件，作 `mesh.node` 放进 Resources；`core.ts` 只换了加载方式，fatal/重启照旧）。Node host 的
  storage 改成异步、按顺序的文件操作；一个 fiber 出 bug 等同 Rust 的 panic：每个 client 收到 `{"fatal": …}`，桌面起新的。
  验证（studio）：`DEV=1 SKIP_WEB=1 SKIP_STATION=1 sh apps/desktop/build.sh` 通过；Electron 44.4.5（Node 24.21）里
  utilityProcess + MessagePort 跑通订阅和调用、`core.db` 写入；`node harness/handover.ts <Rust addon>`：Rust 写的目录 TS
  打开、TS 写的目录 Rust 打开，账号/workspace/偏好/草稿都一样。
- 网页：worker（`web/src/core/worker.ts`）跑 TS core（`src/hosts/web.ts`：fetch、WebSocket、IndexedDB 同库同表
  `stillfail-core` v2 的 `values`/`records`，第一次打开照旧从 `ember-core` 搬），iroh 来自新的 `client/iroh-wasm`
  （只有 iroh，2.7 MB；原来整个 Rust core 的 wasm 6.2 MB），在 mesh 第一次 bind 时才加载。web 的 tsconfig 更严，所以 worker
  经 `@stillfail/core-ts/web` 引用（vite alias 指到源码，类型见 `web/src/core/core-ts.d.ts`），core-ts 用自己的 tsconfig 检查。
  `pnpm build`/`build:cloud` 改编 iroh-wasm 并装 core-ts 的依赖；`scripts/check.sh` 的替身和测试步骤跟着换，加了 core-ts 的
  typecheck 和测试。验证（studio）：`build:cloud`、`build:site` 通过；dev cloud（`cloud/test/dev.ts`）+ 本地 relay + 临时 station，
  Chrome 打开登录 → 页面经 iroh-wasm 读到 station（「给 studio 添加一个 Profile」）→ 发新对话，消息立刻出现、station 建出
  chat 并回 agent 的错误；刷新后 82 ms 内从 IndexedDB 出来。
- 规则 7：按 key 的增量（`src/collections.ts`、`src/output.ts`、Data 冻结记录 + `shared()`、视图按记录复用行）、web 和安卓
  应用器、安卓 `ChatsDecoder`、2000 行测量（见上面「按 key 的增量」）。

还没做（接手从这里开始）：
- 剩下的 Rust 测试：`core/tests.rs`（56）、`station/tests.rs`（45）、`kept.rs`、`data.rs`、`sync.rs`、`account_state`、
  mesh 里要 relay 服务器的几个。
- host：安卓 Hermes + JNI iroh。
- 对照运行加上 station（假 station 走 HostWire）的步骤，更新刻意不同的清单。

此前（第一版，照 Rust 写的，已被上面取代）：
1. 第 1 期（2026-10-03）：协议、Host、Store/delta、data center、accounts、cloud、status、workspace、wake、trace、ops、
   calls（全部 call 的解析）、prefs、doing、format、shapes 的 model/reasoning、i18n、Node host、假 Host。
   对照运行 44 步全部一致（账号登录登出、accounts/workspaces/workspace/loginSessions/status/prefs/doing 话题、
   cloud 写操作和 events socket 推送与断线重连、草稿、各种错误）。移植测试 79 个通过。

下一步（按顺序）：mesh（iroh 走 station 的 `mesh.node` 形状，见 `station/src/mesh/native.ts`）→ station 链路
（`station.rs`、`station/{wire,transport,events,threads}.rs`、`kept.rs`、`entries.rs`、`sync.rs`）→ views →
其余模块 → 桌面/web/安卓 host。
