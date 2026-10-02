# station 用 TypeScript 重写：设计方案（草案）

2026-10-03。依据：现有 Rust station（main d5a4dd72，去掉测试约 3.2 万行）的完整梳理，以及分支 proto-rust-shell-ts 上的原型实测（`proto/ts-station`：同库 53 个请求与 Rust 逐字段一致；4.1 万行 TS 的类型检查 165ms、esbuild 38ms；Node 单线程会被重请求堵住）。

## 目标与不做的事

- 目标：日常开发不再编译 Rust（改一行到能跑在 1 秒内、没有几十 G 的 target）；结构比现在清楚；对外行为不变。
- 不变的东西（兼容约束，见文末清单）：`stillfail.db` 的结构和数据、数据目录里的文件、给客户端的 admin API 与 mesh 线协议、给 agent 的 MCP 工具、给安装器和桌面 app 的命令行与 `run/*` 文件、与 cloud 的签名接口。新旧 station 要能来回切（出问题能退回 Rust 版而不丢数据）。
- 这一版不做的：改客户端协议（只做向后兼容的追加）、权限模型的重新设计（现状：除更新和自动决策外，成员都能改设置，见「待定」）、去掉 `ember` 旧名。

## 进程结构

```
launchd / 桌面 app
  └─ stillfail-station        原生启动器（Rust，预编译，几百行）：pid 不变，持有锁、端口、信号
       └─ node station.js      全部逻辑（TS 打包成一个文件，带自己的 Node）
            ├─ mesh.node        iroh 插件（Rust，预编译）：endpoint、连接、流
            └─ worker 线程       SQLite 读、归档解压、重计算
  stillfail-runner × N          每个 agent 进程一个看守（Rust，预编译，很小）：
       └─ claude / codex       持有 agent 的 stdin/stdout，station 重启后重新接上
```

为什么这样分：

- **启动器**解决 Node 不能 exec 的问题。安装器和桌面 app 认的是「`station.json` 里 pid 不变、startedAt 变了 = 交接成功」、SIGUSR2/SIGUSR1/SIGHUP、退出码 3。启动器 pid 不变，收到 SIGUSR2 就起新的 Node、等它说准备好了再让旧的退出，契约原样保留。它还持有 `run/station.lock`、`--with-parent` 的父进程检查。
- **runner** 取代现在的「交接时复制 fd、带上半行字节、新进程 adopt」那一整套（process.rs 的 hand_off/adopt、Handed* 结构、两次 settle）。agent 进程本来就挂在 runner 下面，station 怎么重启、崩溃都不影响正在跑的轮次；新 station 起来后按 `run/runners/<pgid>.sock` 重新接上，从 runner 的缓冲里接着读。这比现在更稳：现在 station 崩溃（不是交接）时 agent 进程会被清掉，只能靠续写提示从转录接着做。
- **原生部分只有三个**（启动器、runner、iroh 插件），按自己的版本号预编译发布，平时开发不碰；改了才在 CI 编。

## 写法：Effect（2026-10-03 定）

- 异步和编排一律用 Effect 4（`effect` 包）：服务是 `Context.Service`，各部分是 `Layer`，在组合根（`station/src/main.ts`）拼起来；长任务是 fiber，挂在所属部分的 scope 里（`Effect.forkScoped`、`FiberSet`），部分停了它们一起停，资源用 `acquireRelease` 保证释放；退避和定时用 `Schedule`；推送用 `PubSub`/`Stream`；计时相关的规则用 `TestClock` 测。
- 纯计算（读视图的拼装、格式化、协议解析）保持普通函数，不进 Effect；热路径同理。
- 回调式的 API（ws、子进程、原生插件的事件）用 `Effect.callback` 包一层，取消时要能清理。
- 不用全局状态；需要什么，在服务里声明依赖。

## 模块划分（Node 进程内）

一个组合根（`main.ts`）把下面这些用参数传进去，不再有全局注册表（现在的 OnceLock：feedback、adb、notify outbox、errors、lang）。

| 模块 | 职责 | 取代 |
|---|---|---|
| `store` | SQLite（WAL）。一个写连接在主线程；读走 worker 池。按领域分仓库：sessions、threads/entries、deliveries、turns、jobs、usage、ui-state | store.rs 3000 行、单连接加锁 |
| `views` | 侧栏、会话、概览等读模型；读模型的汇总表由 SQLite 触发器维护（见数据层） | 每次请求全量重算 /chats |
| `cloud` | 登记、presence 套接字、签名（一个函数）、relay 列表、通知/反馈/trace 上报、吊销 | main.rs 里分散的 4 种签名、三处解析 cloud.json |
| `mesh` | iroh 插件之上：成员 credential、请求流、预览 WebSocket、adb 隧道、站间 peer | main.rs、peer.rs、adb.rs、keep.rs |
| `api` | admin API：带类型的路由表（参数校验统一）、幂等、语言、事件流 | admin/mod.rs 560 行手写匹配 |
| `sessions` | 每个会话一个显式状态机：cold → starting → running → waiting → idle（+ held）；轮次、送达、等待、催办、限额切换、认证重试 | hub.rs + session.rs 里分散在三处的「是否在跑」 |
| `runtimes` | claude、codex 适配器（命令行、环境、输出解析、失败分类），对上只给统一事件 | runtime/* |
| `tools` | MCP 服务（HTTP，Bearer 令牌）；所有工具在边界统一做参数归一（旧写法 final/block、JSON 字符串参数）；工具的副作用经会话队列，不再绕过 | hub.rs 里的工具实现、state_arg 等 250 行 |
| `surfaces` | Slack、站内聊天各是一个注册的 surface（同一接口：收、发、名字、状态） | 站内聊天在 hub 里按字符串特判 |
| `slack` | 一个 HTTP 客户端（统一 429 重试）、Socket Mode、应用和配置令牌、名字缓存（一个，有过期） | slack.rs 与 slack_apps.rs 各一套 |
| `accounts` | 凭据仓库（文件/钥匙串、机器/Profile 统一）、OAuth 续期（与 Claude Code 共用锁）、检查、额度、登录 | claude_oauth、no_keychain、machine_logins、quota 四处 |
| `jobs` | 后台任务、服务、预览、站间任务（回执改进库，不再是 JSON 文件） | jobs.rs、remote.rs 的 JSON 文件和三个轮询 |
| `updates` | 拆成「运行时安装」和「station 自更新」两块 | updates.rs 1100 行 |
| `ops` | 配置/设置（原子写、保留未知字段）、`run/*` 文件、端口、日志、错误上报、遥测 | config/settings/ports/telemetry |

## 数据层

- **库还是同一个 `stillfail.db`，`user_version` 仍是 12**：Rust 版拒绝打开别的版本，要能退回就不能动它。新增的东西只用 `IF NOT EXISTS` 的新表、新索引和触发器；TS 版自己的迁移记在新表 `ts_migrations` 里。
- **侧栏变成查表**：用触发器在 `entries`、`deliveries`、`reads`、`turns` 写入时维护一张 `thread_rows` 汇总表（最后一条消息、第一句话、参与者、未读、待回答的卡片）。Rust 版写库时触发器同样生效，所以来回切也不会不一致。`/chats` 从「每个 thread 6 次以上查询、还要解压归档文件」（现在 115ms）变成一两次查询。
- **不再把消息归档进文件**：新归档的 chat 消息留在库里（消息很小）；已有的 `archive/threads/*.jsonl.zst` 照读，并在后台慢慢搬回库里。Rust 版本来就会把有新消息的归档 chat 读回库里，所以兼容。会话工作区和转录的冷存（`workspace.tar.zst`）保留，那个确实省空间。
- **读不堵主线程**：读查询和解压在 worker 线程里跑（原型里一个 115ms 的请求能把别的请求堵到 250ms，就是因为没这样做）。写只有一个连接，按事务排队。
- 死表 `items` 不再写，也不删（Rust 版还会删它里面的行）。

## 推送优先（原则）

能推送的就不让客户端请求（2026-10-03 定）。station 自己知道什么变了，就由它推给关心的人；客户端只在第一次需要、或者真的要做一件事（写操作）时发请求。

- **订阅代替拉取**：客户端在一条长连接上说「我要看什么」（侧栏、某个 chat 的消息、会话、概览、jobs、日志……），station 先推一份当前值，之后只推变化。读接口（`GET /chats` 等）保留给老客户端和首次加载，新客户端不再轮询、不再「收到 usage 事件去重拉」。
- **变化从源头出**：所有写都经过 store 的写入口，写完发领域事件（消息追加、送达、轮次开始/结束、卡片、job 状态、配置变化……）；读模型（`thread_rows` 等）由这些事件或触发器更新，订阅按变了的行推，不再「每次变化给每个人重算整个侧栏再按字符串比较」。
- **带序号、可续传**：每条推送带递增序号，station 保留最近一段；断线重连带上次的序号，只补缺的，超出范围才给全量快照。
- **内部也一样**：现在十几个轮询（cloud.json 每 2 秒、转录 250ms、job 日志 1 秒、站间任务 5 秒、settle 50ms……）都改成事件：文件用 watch、子进程用退出事件、站间用推送。只有对外部系统（Slack、模型额度、更新源）才保留必要的定时。
- **兼容**：现有 `GET /events`（SSE）的事件名和数据形状不变，只追加 `id:` 行；新的订阅协议是追加的（客户端在握手里声明支持才用），老客户端照旧。客户端 core 那边改用订阅是另一件事，跟 station 分开做、分开上线。

## agent 运行

- 会话状态机 + 一个串行队列：MCP 工具的副作用（声明结束状态、need、about、等待）也进这个队列，晚到的工具调用不会再被悄悄丢掉。
- 轮次规则照旧：首次失败不重放原请求，认证失败只重试一次（换续写提示），限额切换到别的 Profile，催办次数、等待计时、停止，都按现在的规则。
- claude/codex 的命令行、环境变量、MCP 配置原样保留（`CLAUDE_CODE_CERT_STORE=bundled`、钥匙串替身、`--dangerously-skip-permissions`、codex 的 `-c` 覆盖等）。
- 失败分类集中在适配器里，有单测；Claude 的文本猜测保留，但集中一处。

## 兼容约束清单（每一条都要有对照测试）

- 命令行：`run --app --port --data --with-parent --handoff`、`enroll`、`status`、`id`、`handoff-version`、`channel`；退出码 3、2；`bin/stillfail` 的用法。
- 信号与文件：SIGTERM/USR1/USR2/HUP；`run/station.json`（单行，安装器用 sed 读）、`presence.json`、`ports.json`、`drained`、`handoff-failed`、`channel-ask/answer`、`update.*`。
- 数据目录：`mesh/secret.key`、`mesh/cloud.json`（字段和权限）、`config.json`（保留未知字段，0600）、`stillfail.db`、`slack-names.json`、`sessions/`、`jobs/`、`thumbs/`、`uploads/`、`archive/`、`remote/`。
- mesh：ALPN（含 `ember/admin/1`）、首个流的 credential/续期、请求头行格式、关闭码 1–4、头 16K、mDNS 两个名字、DHT、keeper、peer 协议。
- cloud：`/v1/stations/enroll|connect|notify|feedback|feedback/fixed`、`/v1/telemetry/traces` 的签名和头。
- admin API：全部路由与字段（含给老客户端留的 `decision`、`declared` 旧词、`footprint`、`follows`）、幂等、语言头。
- MCP：全部工具名和参数、旧写法。
- 原样不改的已知小问题会单列，改的要说明（例：重复的 Set-Cookie 头现在被逗号拼接，是 bug，改；trace 开关不认 `$STILLFAIL_CONFIG`，改）。

## 怎么验证

- **对照运行**：同一份库拷贝，Rust 版和 TS 版各起一台（原型里已经跑通：自签 credential 的压测客户端），对每个读接口比返回；写接口在两份拷贝上做同样的操作，比库的结果。
- **假 agent**：一个假的 `claude`/`codex` 命令（按脚本吐 stream-json / JSON-RPC），把轮次、失败、等待、限额切换、停止这些规则做成测试，两边都跑。
- **重启不断轮次**：轮次进行中重启 station（交接和崩溃各一次），轮次照常结束。
- 内存、延迟、构建时间每期都量，和 Rust 版放在一起。

## 分期

1. **地基**：三个原生件（启动器、runner、iroh 插件）、组合根、store（读写分离、触发器、`thread_rows`）、配置、cloud（登记、presence、签名）、mesh 服务、对照测试框架。完成标志：TS station 能登记、上线、被客户端连上，侧栏和消息读接口与 Rust 一致。
2. **读接口全量 + 事件流**：所有 GET、`/events`（带序号）。完成标志：客户端只读地用 TS station 一切正常，对照测试全过。
3. **agent**：会话状态机、claude/codex 适配器、MCP 工具、站内聊天、jobs、预览。完成标志：在测试 workspace 里网页 chat 完整可用，假 agent 规则测试全过，重启不断轮次。
4. **其余**：Slack、账号（Profile、登录、额度、续期）、更新、adb、站间任务、遥测、反馈。
5. **切换**：安装器和桌面 app 改为装 TS 版（带 Node）；先在一台测试 station 上跑，再到 studio、bft；保留退回 Rust 版的路径一段时间。

规模估计：3.2 万行 Rust → 约 2 万多行 TS；每期都在分支上做完、给证据、你认可再合。

## 已定（2026-10-03）

1. 重启不断轮次：做启动器 + runner。
2. 随 station 发固定版本的 Node。
3. 权限照旧；mesh 上的成员互信（凭 credential 进来的成员都可信，不按角色细分）。
