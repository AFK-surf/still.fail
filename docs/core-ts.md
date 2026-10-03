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

已完成：
1. 第 1 期（2026-10-03）：协议、Host、Store/delta、data center、accounts、cloud、status、workspace、wake、trace、ops、
   calls（全部 call 的解析）、prefs、doing、format、shapes 的 model/reasoning、i18n、Node host、假 Host。
   对照运行 44 步全部一致（账号登录登出、accounts/workspaces/workspace/loginSessions/status/prefs/doing 话题、
   cloud 写操作和 events socket 推送与断线重连、草稿、各种错误）。移植测试 79 个通过。

下一步（按顺序）：mesh（iroh 走 station 的 `mesh.node` 形状，见 `station/src/mesh/native.ts`）→ station 链路
（`station.rs`、`station/{wire,transport,events,threads}.rs`、`kept.rs`、`entries.rs`、`sync.rs`）→ views →
其余模块 → 桌面/web/安卓 host。
