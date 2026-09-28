# ember 设计

ember 是一个团队聊天里的 coding agent 服务：一个聊天 thread 对应一个持久的 agent 会话，agent 由 Claude Code 或 Codex 驱动。它面向内存和磁盘都紧张的机器，会话在 hot / warm / cold / 归档之间流转，归档后仍可唤醒。

本文记录已确定的设计和约束。实现细节以源码为准，不在这里重复。

## 1. 边界

- **宿主（ember）负责**：聊天接入、会话身份与状态、入站消息持久化、结束状态约定、后台任务、账号池、进程与内存预算、workspace 与磁盘生命周期、可观测性。
- **运行时驱动负责**：启动 / 恢复 / 结束一个 agent 进程，把输入送进去，把事件流读出来。
- 运行时的 agent loop、上下文压缩、内置工具都属于 Claude Code / Codex 本身，ember 不改写。

## 2. 进程结构

单进程，launchd 托管。

```
Chat 适配层 ── Inbox(SQLite) ── SessionActor(每个 thread 一个，串行)
                                     │
                               AgentDriver(claude / codex)
                                     │
                          Tool Bridge(HTTP MCP) ◄── agent 调用
JobRunner   ProfilePool   ResourceGovernor(内存)   StorageLifecycle(磁盘)
```

## 3. 聊天接入

- 平台无关的接口：入站消息（thread 坐标、作者、文本、附件）和出站操作（发消息、上传文件、读历史、状态提示）。第一个实现是 Slack Socket Mode。
- 入站事件**先写库再 ack**，按平台事件 ID 去重。
- 每 5 分钟对活跃 thread 补查一次漏掉的消息。
- thread 中的每条新消息都转给 agent，由 agent 判断是否与它相关。

## 4. 会话

- 一个 thread 对应一个会话：`key`、`runtime`、`model`、`profile`、`runtimeSessionId`、`workspace`、`state`、最近声明的结束状态。
- runtime 在会话创建时确定，之后不能换。换 runtime 就开新会话并交接摘要。
- 选择顺序：首条消息里的显式指定 > 频道默认 > 用户默认 > 全局默认。
- 会话的所有状态变更都在它的 actor 里串行执行。
- 输入投递：
  - 空闲时 `prompt`
  - turn 进行中 `steer`
  - 不能 steer 时进入 ember 自己的**持久队列**，turn 结束后逐条投递

## 5. 运行时驱动

ember 定义自己的接口，其余部分只依赖这层接口：

```ts
interface AgentDriver {
  open(opts: OpenOptions): Promise<AgentSession>;   // profile, cwd, resume?, instructions, env
  usage(profile: Profile): Promise<UsageSnapshot>;
  models(profile: Profile): Promise<ModelInfo[]>;
  migrateSession?(id: string, from: Profile, to: Profile): Promise<void>;
}
interface AgentSession {
  id: string;
  prompt(text: string): Promise<Ack>;
  steer(text: string): Promise<Ack>;
  abort(): Promise<Ack>;
  on(event: "turn_end" | "rate_limited" | "auth_failed" | "exited" | "record", fn: Listener): void;
  dispose(): Promise<void>;
}
```

- 两个驱动都自己实现，共用一套进程管理（进程组、stdin、内存采样）。不依赖 `@botiverse/oar`：它只结束直接子进程、不解析 `api_retry` / `rate_limit_event`，也没有按账号的 env。它的 Claude / Codex 文档和实验脚本作为需求清单和参考，升级 CLI 版本时对照其上游。
- **账号相关全部自己实现**。
- 限流、认证失败的信号由驱动层归一，这是账号切换的触发条件。
  - Claude 的 turn 成败看 `result.is_error`，不看 `subtype`（认证失败时是 `subtype: "success"` + `is_error: true`）。
  - Claude 遇到 401 会静默重试约 3 分钟，只发 `system/api_retry` 帧；驱动在第一个 401 的 `api_retry` 就判定认证失败并中止 turn。
- **Codex：每个账号共享一个 app-server**，多个会话按 thread 复用同一个进程。这部分自己实现，不用 oar 的"每个会话一个 app-server"。实测每个 thread 的内存增量 <1MB（spike 2）。
  - 与会话相关的配置（MCP token 等）通过 `thread/start` / `thread/resume` 的 `config` 按 thread 传入，不放进进程环境变量。
  - thread 以 `approvalPolicy: "never"` + `sandbox: "danger-full-access"` 启动；否则 MCP 调用会被拒绝。
- **Claude：每个会话一个 `claude -p` 进程**，因为会话在进程启动时就绑定了，无法复用。
- 子进程的 stdin 必须由驱动持有或显式关闭：两个 CLI 都会读 stdin。

## 6. 给 agent 的工具（MCP）

ember 直接提供 HTTP MCP，不为每个会话额外起进程：

| 工具 | 作用 |
|---|---|
| `chat_post(text, kind?)` | 发到 thread；`kind` 可以是 final / block / wait |
| `chat_state(kind, reason?)` | 静默声明结束状态 |
| `chat_upload(path, comment?)` | 上传文件 |
| `chat_history(before?, limit?)` | 读更早的 thread 历史 |
| `job_register` / `job_list` / `job_cancel` | 后台任务管理 |

- 每个会话有自己的 token，MCP 服务按 token 识别会话。agent 无法冒充其他会话。
- Claude：MCP 服务写在账号配置目录的 user 级配置里，header 为 `Authorization: Bearer ${EMBER_SESSION_TOKEN}`；token 作为该会话进程的环境变量注入。
- Codex：MCP 服务不写进账号配置，而是在 `thread/start` / `thread/resume` 的 `config` 里按 thread 传 `mcp_servers.ember.url` 和 `mcp_servers.ember.http_headers`，因为同一个 app-server 进程承载多个会话。

## 7. 结束状态约定

- agent 的最终回答**不自动转发**，由 agent 通过 `chat_post` 发送。
- 每个 turn 结束时必须声明 final / block / wait 之一。
- turn 结束时如果没有声明：提醒 agent 补上，最多 N 次；超过后在 thread 里说明"意外停止"。
- 声明了 `wait` 但没有正在运行的后台任务，同样提醒。
- 失败的 turn（限流、认证失败、模型错误）先分类，在 thread 里说明；限流和认证失败交给 ProfilePool 换账号重试。

## 8. 后台任务

- 由 ember 执行 agent 登记的脚本，agent 不自己跑 sleep 循环。
- 脚本通过 helper CLI 上报 event / complete / fail。ember 收到后把结果作为输入注入会话，唤醒 agent。
- 有心跳超时；ember 重启后重新接管，或把任务标记为失败。

## 9. 账号池

- profile = runtime 类型 + 配置目录 + 登录状态 + 额度缓存。
- 新会话选余量最多的账号。已有会话尽量留在原账号，因为 resume 依赖该账号目录下的会话记录。
- 换账号 resume 时，先把会话记录迁移到新账号目录。

## 10. 内存

进程是最贵的资源。

- **hot**（turn 进行中）：绝不驱逐、绝不暂停。
- **warm**（turn 结束后）：进程保留，默认 30 分钟，可配置。
- 超过 warm 时长的进程**只在超出内存预算时**才按 LRU 回收；机器空闲时可以一直保留。
- 预算是**软上限**：超出只触发回收空闲进程，新 turn 照常启动。
- **硬上限**（swap 或内存压力超过阈值）才让新 turn 排队，并在 thread 里说明原因；一有余量马上启动。
- 每个进程的占用按 runtime 给初始估值，之后每 30 秒采样整个进程树的真实占用来修正。实测起点（spike 1、2）：一个 `claude -p` 会话 ≈75–130MB footprint，且随上下文增长；一个共享 codex app-server ≈40–55MB，每个 thread <1MB。
- **防泄漏**：
  - 每个 runtime 进程放进独立进程组，dispose 时整组结束
  - 进程组 ID 和启动时间记进 SQLite，启动时先清理上一轮遗留
  - 每分钟对账：带 ember 实例标记但在会话表里找不到主人的进程，直接结束

## 11. 磁盘

**少写**
- 不重复存储运行时的原始事件；运行时自己已经存了完整会话记录。ember 只存精简的 turn 摘要（起止时间、状态、工具、usage）。原始记录只在调试开关打开时写。
- 共享可复用的缓存：pnpm store、npm / cargo 缓存共享；`CARGO_TARGET_DIR` 按仓库共享。

**生命周期**

```
active ──(空闲 >1 天)──► slim ──(空闲 >3 天)──► archived ──(>60 天或超预算)──► purged
```

- **slim**：删除 workspace 里可重新生成的目录（`node_modules`、`dist`、`build`、`target`、`.next`、缓存）；已推送且无改动的 worktree 直接移除。
- **archived**：未提交的改动存成 patch，未跟踪文件打包；与运行时会话记录、会话元数据一起压成 `archive/<月份>/<key>.tar.zst`，然后删除原文件。
- **唤醒**：把会话记录解压回原账号目录的原路径，resume 后告诉 agent 归档情况和 patch 位置。spike 4 确认会话记录文件是 resume 的全部依赖：
  - Claude：`$CLAUDE_CONFIG_DIR/projects/<cwd 编码>/<id>.jsonl`。路径里编码了 cwd，所以 workspace 路径必须保持不变。
  - Codex：`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-…-<id>.jsonl`。
  - zstd 压缩后是原大小的 23–31%。
- **purged**：删除归档。之后该 thread 再有消息就开新会话，从聊天历史回填上下文。

**按预算驱动**：数据目录有总预算和最低空闲空间。超出时按以下顺序回收：
1. 调试日志
2. 空闲会话 slim
3. 最久未用的会话归档
4. 最老的归档删除
5. 共享仓库 `git gc`，删除长期不用的仓库

**稳健性**
- 全程只用一个用户运行。
- 单个文件清理失败只记告警，不阻塞其他清理。
- 日志按大小轮转。

## 12. 存储

- SQLite，一个库：sessions、inbound、jobs、profiles、turns、processes。
- 运行时会话记录留在运行时自己的目录，ember 只记录路径。

## 13. 可观测性

- 第一版：`ember status`、`ember session <key>` 这样的 CLI，外加一个只读的本地 HTTP 页面。
- 以后需要时再加外网访问和 thread 里的会话链接。
