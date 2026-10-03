# still.fail 设计

still.fail 是一个团队聊天里的 coding agent 服务：人在 Slack 或 still.fail 自己的网页对话里找它，每个对话落到一个持久的 agent 会话，agent 由 Claude Code 或 Codex 驱动。它面向内存和磁盘都紧张的机器，会话在 hot / warm / cold / 归档之间流转，归档后有新消息就自动恢复。

本文记录已确定的设计和约束。实现细节以源码为准，不在这里重复。

## 1. 边界

- **station（宿主）负责**：聊天接入、会话身份与状态、入站消息持久化、结束状态约定、后台任务、账号池、进程数量、会话 workspace 与归档、可观测性。
- **运行时驱动负责**：启动 / 恢复 / 结束一个 agent 进程，把输入送进去，把事件流读出来。
- 运行时的 agent loop、上下文压缩、内置工具都属于 Claude Code / Codex 本身，still.fail 不改写。
- **still.fail cloud 只管人**：账号、workspace、成员和成员凭证；客户端（网页、桌面、Android）通过 iroh 直接连 station，不经过业务服务器。见 [cloud.md](cloud.md)、[client-core.md](client-core.md)。

## 2. 进程结构

station 是 TypeScript（station/，跑在发布包自带的 Node 上），原生的只有三件预编译的：启动器 `stillfail-station`（station/native/launcher：持有数据目录的锁和端口，pid 不变，更新时在旁边起新的 Node 进程再放掉旧的）、每个 agent 一个 runner（station/native/runner：station 重启或崩溃时轮次不断）、iroh 和图片编解码的 Node 插件（station/native/mesh）。由 launchd（macOS）或 systemd 用户服务（Linux）托管；桌面端自带一份，作为子进程用 `--with-parent` 启动。方案见 [station-ts.md](station-ts.md)；之前的 Rust station（2026-10-04 删除）见 [station-rust.md](station-rust.md)。

```
Chat 接入(Slack / 网页对话) ── Store(SQLite) ── SessionActor(每个会话一个，串行)
                                                    │
                                              AgentDriver(claude / codex)
                                                    │
                                    MCP 端点(HTTP, 127.0.0.1) ◄── agent 调用
Jobs   账号池   空闲进程回收   自动归档
管理 API ◄── iroh(客户端，带 still.fail cloud 签发的成员凭证)
```

## 3. 聊天接入

- 平台无关的接口：入站消息（thread 坐标、作者、文本、附件）和出站操作（发消息、读历史、状态提示）。实现有两个：Slack Socket Mode，以及 station 自己的网页对话（固定连接 `ember`，thread 为 `EMBER/…`）。
- 入站事件**先写库再 ack**；写库失败就不 ack，让 Slack 重投，按 thread + 消息 ts 去重。
- 在一个 thread 中途加入时，先把之前的消息补记下来（不投递），thread 的记录保持完整。
- 哪些消息进哪个会话由连接的会话方式决定（多会话 / 单会话，见 [operations.md](operations.md)）；进来的每条消息都转给 agent，由 agent 判断是否与它相关。

## 4. 会话

- 会话记录：`key`、所属连接、`runtime`、`model`、`effort`、`profile`、`runtime_session_id`、`workspace`、MCP token、是否在跑、归档状态。一个会话可以在多个 thread 里（单会话连接、网页对话把会话拉进来），一个 thread 里也可以有多个会话。
- runtime 在会话创建时确定，之后不能换；model、effort、profile 可以在两个 turn 之间改。
- 选择：Slack 会话用连接绑定的 runtime / model / effort（绑定了 profile 就用它，否则由账号池挑）；网页对话由发起人选。
- 会话的所有状态变更都在它的 actor 里串行执行。
- 输入投递：
  - 空闲时 `prompt`
  - turn 进行中 `steer`（Claude 的 profile 默认先把 turn 正在等的命令和子 agent 挪到后台，让消息立刻被读到）
  - 不能 steer 时留在库里的待投递队列，turn 结束后投递

## 5. 运行时驱动

still.fail 定义自己的接口（station/src/agents/runtime.ts），其余部分只依赖这层：`AgentDriver` 按 profile、cwd、要 resume 的 id、model、effort、附加指令和 MCP 地址 / token 打开一个 `AgentSession`；会话提供 `prompt` / `steer` / `abort` / `dispose`（Claude 另有把工具调用挪到后台），运行时发生的事按顺序作为事件（turn 开始 / 结束及结果、进程关闭、实时步骤）送回会话自己的任务，而不是回调。

- 两个驱动都自己实现，共用一套进程管理（进程组、stdin）。不依赖 `@botiverse/oar`：它只结束直接子进程、不解析 `api_retry` / `rate_limit_event`，也没有按账号的 env。它的 Claude / Codex 文档和实验脚本作为需求清单和参考，升级 CLI 版本时对照其上游。
- **账号相关全部自己实现**。
- turn 失败由驱动层归一分类：认证失败、限流、模型错误、进程退出、其他。
  - Claude 的 turn 成败看 `result.is_error`，不看 `subtype`（认证失败时是 `subtype: "success"` + `is_error: true`）。
  - Claude 遇到 401/403 会静默重试数分钟，只发 `system/api_retry` 帧；驱动在第一个 401/403 的 `api_retry` 就判定认证失败并中止 turn。
- **Codex：每个账号共享一个 app-server**，多个会话按 thread 复用同一个进程。这部分自己实现，不用 oar 的"每个会话一个 app-server"。实测每个 thread 的内存增量 <1MB（spike 2）。
  - 与会话相关的配置（MCP token 等）通过 `thread/start` / `thread/resume` 的 `config` 按 thread 传入，不放进进程环境变量。
  - thread 以 `approvalPolicy: "never"` + `sandbox: "danger-full-access"` 启动；否则 MCP 调用会被拒绝。
- **Claude：每个会话一个 `claude -p` 进程**（stream-json 输入输出），因为会话在进程启动时就绑定了，无法复用。
- 子进程的 stdin 必须由驱动持有或显式关闭：两个 CLI 都会读 stdin。

## 6. 给 agent 的工具（MCP）

still.fail 直接提供 HTTP MCP，不为每个会话额外起进程：

| 工具 | 作用 |
|---|---|
| `chat_post(to, text, kind?, files?)` | 发到自己的某个对话；`kind` 为 final / block，省略即进度消息；`files` 附本机文件（仅网页对话） |
| `chat_state(kind, seconds?)` | 静默声明结束状态：final / block / waiting（waiting 带预计秒数） |
| `chat_history(to, before?, limit?)` | 读自己某个对话更早的消息 |
| `chat_list` / `chat_read` | 列出 / 读这台 station 上的任意对话（按链接、thread 地址或会话 key） |
| `session_history` | 读某个会话的执行历史 |
| `slack_api(method, params, to?)` | 以连接的 Slack bot 身份调任意 Web API；别的会话所在的 thread 不能写 |
| `job_start` / `job_list` / `job_log` / `job_stop` | 后台任务和 web 服务 |

- 每个会话有自己的 token，MCP 服务按 token 识别会话。agent 无法冒充其他会话。
- Claude：启动时用 `--mcp-config` 传入 MCP 服务，header 为 `Authorization: Bearer ${STILLFAIL_MCP_TOKEN}`；token 作为该会话进程的环境变量注入。
- Codex：MCP 服务不写进账号配置，而是在 `thread/start` / `thread/resume` 的 `config` 里按 thread 传 `mcp_servers.stillfail.url` 和 `mcp_servers.stillfail.http_headers`，因为同一个 app-server 进程承载多个会话。

## 7. 结束状态约定

- agent 的最终回答**不自动转发**，由 agent 通过 `chat_post` 发送；回复必须用 `to` 指明发到哪个 thread。
- 每个 turn 结束时要声明 final / block / waiting 之一（`chat_post` 的 `kind` 或 `chat_state`）。
- turn 结束时如果没有声明：提醒 agent 补上，最多 `maxNudges` 次（默认 2）；超过后在 thread 里说明"停下来了但没有明确结果"。
- 声明了 `waiting` 的，到预计时间还没有东西把它唤醒（任务结束、有人回复），就再问它一次。
- 失败的 turn（认证失败、限流、模型错误、进程退出）分类后在 thread 里说明，不自动重试；下一个 turn 开始时，原账号已不可用就由账号池换一个。

## 8. 后台任务

- agent 用 `job_start` 让 station 执行 shell 命令，agent 不自己跑 sleep 循环。每个任务在独立进程组里跑，输出写日志文件。
- 任务结束时通知 agent；任务里可以用 `stillfail-job notify <文字>` 随时给 agent 发消息。通知作为输入注入会话，唤醒 agent。
- 带 `port` 的是 web 服务：一直保持运行（退出后按递增间隔重启），workspace 成员经 still.fail cloud 的链接打开。
- station 重启后，原来在跑的任务重新启动，并告诉 agent。

## 9. 账号池

- profile = 运行时配置目录 + 接入方式（订阅 / API key / 自定义 env）+ 启用的模型 + 登录检查和额度缓存。
- 新会话只在启用了所选模型的 profile 里挑：跳过登录失效、key 被拒或额度用尽的；其余选余量最多的，再比进行中的会话数，再比最久没被选中。
- 已有会话尽量留在原账号（运行时缓存在那个账号上）；不可用时换一个。运行时会话记录按 runtime 放在所有 profile 共享的目录里，换账号 resume 不需要迁移。

## 10. 内存

进程是最贵的资源。

- **hot**（turn 进行中）：绝不驱逐、绝不暂停。
- **warm**（turn 结束后）：进程保留，默认 30 分钟（`warmMinutes`）。
- 空闲的 Claude 进程超过 `maxWarmClaude`（默认 4）个时，超过 warm 时长的按最久空闲先结束；机器空闲时可以一直保留。Codex 的 thread 共用 app-server，不回收。
- 实测起点（spike 1、2）：一个 `claude -p` 会话 ≈75–130MB footprint，且随上下文增长；一个共享 codex app-server ≈40–55MB，每个 thread <1MB。
- **防泄漏**：
  - 每个 runtime 进程放进独立进程组，dispose 时整组结束
  - 进程组 ID 和启动时间记进 SQLite，启动时先清理上一轮遗留（按启动时间确认是自己的，防 pid 复用）

## 11. 磁盘

**少写**
- 不重复存储运行时的原始事件；运行时自己已经存了完整会话记录。still.fail 只存 thread 里的消息和精简的 turn 记录（起止时间、结果、声明的状态）。
- 仓库共享：规范 clone 放在 `<数据目录>/repos`，会话在自己的 workspace 里从它建 git worktree。

**归档**
- 空闲超过 `autoArchiveDays`（默认 1 天）且已结束的会话和对话自动归档（没有在跑、没有待投递、没有停在 block、发起人没有未读、没有单会话连接绑着）；也可以手动归档。
- 归档的会话从列表隐藏，空闲进程结束，运行时会话记录另存一份 zstd 压缩副本（`archive/transcripts/<key>.jsonl.zst`）；运行时自己目录里的原文件不动。
- thread 的会话全部归档后，它的消息写成 `archive/threads/<id>.jsonl.zst` 并从库里删除；读时从文件读。
- 有人在 thread 里说话，或手动恢复，就恢复成活跃状态。细节见 [station-storage.md](station-storage.md)。
- 原计划归档为 `archive/<月份>/<key>.tar.zst`（会话记录 + 元数据一起打包，删除原文件，唤醒时解压回原路径），已改为上面的做法。
- 删除会话时，删掉它的 workspace 目录和压缩副本；运行时的会话记录留在原处。
- spike 4 确认会话记录文件是 resume 的全部依赖：
  - Claude：`$CLAUDE_CONFIG_DIR/projects/<cwd 编码>/<id>.jsonl`。路径里编码了 cwd，所以 workspace 路径必须保持不变。
  - Codex：`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`。
  - zstd 压缩后是原大小的 23–31%。

**稳健性**
- 全程只用一个用户运行。

## 12. 存储

- SQLite，一个库（`stillfail.db`，旧版的 `ember.db` 启动时自动迁移）：sessions、threads、thread_sessions、entries、deliveries、reads、turns、processes、jobs、job_notices、bindings、profile_status、identities。表结构和变更通知见 [station-storage.md](station-storage.md)。
- 运行时会话记录按 runtime 放在 `<数据目录>/transcripts/<runtime>`，每个 profile 目录里的 `projects/`（Claude）/ `sessions/`（Codex）链接到那里。

## 13. 可观测性

- 管理页：网页版 / 桌面端 / Android 经 iroh 连到 station（station 本机不再有页面；不在 workspace 里的 station 不干活，`stillfail status` 说明它在哪、为什么停着）。能看会话、执行历史（运行时会话记录 + 进行中 turn 的实时步骤）、进程和后台任务，并做管理操作。
- 多会话连接在 Slack 里新开的会话，先在 thread 里贴一个"在 still.fail 里查看这个会话"的链接（station 加入 workspace 之后）。
- 错误上报（PostHog）和链路追踪（经 still.fail cloud 转到 Axiom）都可选，默认关闭，见 [telemetry.md](telemetry.md)。
- 原计划第一版做 `ember status`、`ember session <key>` 这样的 CLI 加一个只读本地页面，已改为上面的管理页和客户端。

## 14. 计划中、尚未实现

原设计里有、目前还没做的部分。保留原意，实现时再细化。

- **内存预算**：软上限超出时回收空闲进程，新 turn 照常启动；硬上限（swap 或内存压力超过阈值）才让新 turn 排队，并在 thread 里说明原因，一有余量马上启动。每个进程按 runtime 给初始估值，之后每 30 秒采样整个进程树的真实占用修正。现在：只按 `maxWarmClaude` / `warmMinutes` 回收空闲的 Claude 进程，不看内存。
- **孤儿进程对账**：每分钟检查一次，带 still.fail 实例标记但在会话表里找不到主人的进程直接结束。现在：只在启动时清理上一轮遗留。
- **Slack 漏消息补查**：每 5 分钟对活跃 thread 补查一次漏掉的消息。现在：靠先写库再 ack、Slack 重投。
- **后台任务心跳超时**：任务超时没有心跳就判定失败。现在：只看进程是否结束。
- **按磁盘预算回收**：数据目录有总预算和最低空闲空间，超出时依次回收：调试日志 → 空闲会话 slim → 最久未用的会话归档 → 删除最老的归档 → 共享仓库 `git gc`、删除长期不用的仓库。单个文件清理失败只记告警，不阻塞其他清理。现在：只有按空闲天数的自动归档。
- **slim 阶段**：空闲超过 1 天，删除 workspace 里可重新生成的目录（`node_modules`、`dist`、`build`、`target`、`.next`、缓存）；已推送且无改动的 worktree 直接移除。现在：没有，workspace 原样保留。
- **归档时保存未提交改动**：未提交的改动存成 patch、未跟踪文件打包，唤醒后告诉 agent 归档情况和 patch 位置。现在：归档不动 workspace。
- **purge**：归档超过 60 天（或超预算）后删除；之后该 thread 再有消息就开新会话，从聊天历史回填上下文。现在：归档一直保留，只有手动删除会话。
- **共享缓存**：pnpm store、npm / cargo 缓存共享，`CARGO_TARGET_DIR` 按仓库共享。现在：只共享规范 clone（`<数据目录>/repos`）。
- **调试用原始记录**：运行时原始事件只在调试开关打开时写。现在：不写。
- **日志按大小轮转**。现在：不轮转。
- **换 runtime 交接**：换 runtime 就开新会话，并把旧会话的摘要交给新会话。现在：runtime 不能换，也没有交接。
- **选择顺序**：首条消息里的显式指定 > 频道默认 > 用户默认 > 全局默认。现在：Slack 只用连接绑定的设置，网页对话由发起人选。
- **限流 / 认证失败自动换账号重试**：驱动归一的限流、认证失败信号触发账号池换账号，并重试这个 turn。现在：只在 thread 里说明、不重试，下一个 turn 开始时原账号不可用才换一个。
