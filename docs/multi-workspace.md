# 一台 station 在多个 workspace 里（设计稿）

> 状态：在做（分支 multi-workspace-station）。chat EMBER/1792163874.844000，2026-10-17 用户定了「账号可共用、其余分开（软隔离）」和「station 级设置归主 workspace」。

## 要解决的事

现在一台 station 只属于一个 workspace：cloud 的 `stations` 表以公钥为主键，再登记到别的 workspace 会把它**搬走**；station 的 `cloud.json` 只记一个 workspace，凭证只认这个 workspace 的。想让同一台机器（同一份订阅、同一套 runtime）同时给两个团队用，只能再装一台。

目标：一台 station（一把 iroh 密钥）可以**加入**多个 workspace。每个 workspace 的成员只看到、只用到这个 workspace 的东西；机器本身的东西共用一份。

## 已定的规则

- **主 workspace**：station 第一个加入的 workspace（`cloud.json` 顶层那个）。之后加入的叫**加入的 workspace**。主 workspace 被移走时，加入最早的那个接任。
- **station 级的东西只归主 workspace 的 owner/admin 管**：账号（profiles、订阅登录、API key）、更新和通道、`tools.access`、加入和退出 workspace、自动决策、station 分享（share）、继续本机的 Claude Code/Codex 会话。其他 workspace 的 admin 不能改，可以看到自己能用到的部分。
- **按 workspace 分开的**：chat（会话、thread、奏、归档和归档策略）、Slack connect、agent 的记忆和 skills（`agent/`）、文件根目录（`drive.roots`）、chat 分享（xshare）、station 之间的调用（session_send、chat_list、station_list、任务）都只在同一个 workspace 的 station 之间。
- **账号可以共用**：每个 profile 默认只给主 workspace 用；主 workspace 的管理员可以给它勾上加入的 workspace（`profiles[].workspaces`）。加入的 workspace 一个能用的 profile 都没有时，那里的 chat 开不了轮次，界面说明原因。
- **软隔离**：所有 agent 用同一个系统用户跑，A 的 agent 想读 B 的会话目录，物理上拦不住。这里隔离的是数据、列表和 agent 的工具，不是沙盒。界面上加入 workspace 时写明这一点。
- **workspace 锁（安全模式）先只支持主 workspace**：station 钉了锁就不能再加入别的 workspace；开了锁的 workspace 也不能被已在别处的 station 加入（cloud 和 station 都拒绝，说明原因）。以后再做每个 workspace 一把锁。

## cloud

### 数据

`stations` 表拆成两张：

- `stations (id PRIMARY KEY, last_seen, version)`：机器本身。
- `station_members (workspace, station, name, emoji, icon, enrolled_at, enrolled_by, PRIMARY KEY (workspace, station))`：membership。名字、图标按 workspace 各起各的。

打开时迁移：现有每行拆成一条 station 和一条 membership。所有按 workspace 列 station、数 station（套餐上限）的地方改查 `station_members`；按 id 找「station 在哪个 workspace」的地方（feedback、notify、锁）改成按请求说的 workspace 查 membership。

一台 station 的主 workspace = 它 `enrolled_at` 最早的 membership。

### 登记

`POST /v1/stations/enroll` 不变：照旧**搬家**，删掉它所有的 membership，再加这一条。

新增 `POST /v1/stations/join`（Comma 是 `/v1/comma/stations/join`），请求体和签名都和 enroll 一样（token 已经决定了去哪个 workspace，签名证明持有密钥）。用新路径而不是在 enroll 上加参数：旧 cloud 会忽略不认识的参数，结果是搬家；新路径在旧 cloud 上是 404，什么都不会变。

- 已经在这个 workspace 就只更新名字；否则**加一条** membership，套餐上限按目标 workspace 算。
- station 钉了锁，或目标 workspace 开了锁、而 station 已经在别的 workspace，就拒绝（`409 locked_workspace`）。
- 回应和 enroll 一样带 `workspace`、`workspace_name`、`name`，另外带 `home`（主 workspace 的 id）。

### presence socket

一台 station 仍然只有一个 socket，签名不变。`state` 帧：

- 顶层字段照旧，说的是**主 workspace**：`workspace`、`workspace_name`、`name`、`peers`、`revocations`、`lock`。旧 station 只认这些，它也只会有一个 membership。
- `relay_urls`：still.fail 的 relay 加上**所有** membership 的 workspace 自带 relay（去重）。endpoint 只有一个，relay 合在一起。
- 新增 `workspaces: [{workspace, workspace_name, name, peers, revocations}]`：主 workspace 之外的每个 membership。没有也要带上空数组，station 靠它判断 cloud 支不支持多个 workspace。

其他帧：

- `revoke`：加 `workspace` 字段，说是哪个 workspace 的吊销。
- `lock.get` / `lock.put` / `lock`：只针对主 workspace，不变。
- 移除 station（`DELETE …/stations/:id`）：只删这个 workspace 的 membership。这是最后一条就像以前那样以 4004 断开；否则给 station 重发 `state`（被移走的那个不在里面了；被移走的是主 workspace，接任的那个就到了顶层）。删除 workspace 同理。

### notify 和 feedback

- `POST …/stations/notify` 的请求体多一个可选的 `workspace`（缺省为主 workspace）。cloud 检查 station 在不在那个 workspace，再推给那个 workspace 的成员。推送的 tag 和链接本来就是 `<workspace>/<station>`。
- feedback 同样带 `workspace`，缺省为主 workspace。

### 加入的入口

在 workspace B 里「添加 station」时，可以选一台**已有的** station：列出调用者在它的主 workspace 里是 owner/admin 的 station。选中后客户端：

1. 在 B 里建一个登记 token（已有的 `createEnrollment`）；
2. 通过主 workspace 的连接让 station 去 `join`（station 的 `POST /workspaces/join {token}`，只有主 workspace 的 owner/admin 能调）。

在机器上跑 `stillfail station enroll <origin> <token> --join` 效果一样。

## station

### cloud.json

顶层照旧，是主 workspace。新增 `joined: [{workspace, workspace_name, name, peers, revocations}]`，来自 `state` 帧的 `workspaces`；旧文件没有它，就当只有主 workspace。桌面 app 和 `bin/stillfail` 读顶层，不受影响。

`Cloud` 给出：

- `memberships()`：主 workspace 加上每个加入的 workspace，各带 peers 和 revocations。
- `inWorkspace(ws)`、`home()`。
- `removed()` 只在一个 membership 都不剩时为真。

### 鉴权

- 凭证校验（`mesh/credential.ts` `verifyMember`）接受任一 membership 的 workspace，用那个 workspace 的吊销。`Viewer.workspace` 就是请求者所在的 workspace，之后所有过滤都按它。
- 「station 级设置」的路由（accounts、updates、tools、share、join，以及自动决策）除了要求 owner/admin，还要求 `viewer.workspace === home`。
- station 之间的调用（`mesh/peer.ts`）本来就带 `{workspace, request}`：按那个 workspace 的 roster 检查对方。主动去调别的 station 时，用发起这次调用的会话所在的 workspace。

### 数据按 workspace 分开

- `sessions` 加 `ws TEXT` 列（`NULL` = 主 workspace，旧行不动）。新会话的 `ws`：网页 chat 取发起人的 `viewer.workspace`；Slack 会话取它那个 connect 的 workspace；`chat_create` 开的取开它的会话的 workspace；station 内部会话取主 workspace。
- 所有列会话、thread、奏、归档、通知、执行历史的路由和事件流都按 `viewer.workspace` 过滤；按 key 读写单个会话时，会话不在 viewer 的 workspace 就当它不存在（404）。
- `archive_policy` 加 `ws` 列，一个 workspace 一份策略。
- Slack connect：config 的 connect 多一个可选的 `workspace`（缺省主 workspace）。在哪个 workspace 里加的就归哪个，列表只给那个 workspace 的人看。
- 文件：各 workspace pin 自己的文件夹列表：主 workspace 仍是 `drive.roots`，加入的 workspace 是 `drive.workspaces[<ws>]`。能写的成员不论哪个 workspace 都能浏览整台机器（能用 agent 就能让它读，拦文件浏览没有意义，2026-10-17 用户定），只读成员只看自己 workspace pin 的。
- agent 的记忆和 skills：主 workspace 仍是 `<data>/agent/`，加入的 workspace 用 `<data>/agent/workspaces/<ws>/`（`MEMORY.md`、`skills/`）。会话按自己的 `ws` 拿对应的那份。
- profile：`profiles[].workspaces?: string[]`，缺省只给主 workspace。选 profile、自动挑 profile 时只看会话所在 workspace 能用的。
- agent 的工具：`chat_list`、`chat_read`、`session_send`、`station_list`、`chat_create`、`station_task` 等都只看会话所在 workspace 的 chat 和 station；chat 链接里的 workspace 不是会话自己的，就按 xshare 的规则走（没被分享就拒绝）。
- xshare：host 一方按 chat 所在的 workspace 记；借用一方按会话所在的 workspace 记。

### 退出

workspace 的 admin 在 B 里移除这台 station：cloud 删掉 membership，重发 `state`。station 发现某个加入的 workspace 不在了，就停掉那个 workspace 的会话（像现在整台被移走时那样挂起），数据留着；再加入时恢复。

## 客户端 core

- `mesh.ts` 的连接池和它旁边的各个表（`#links`、`#ways`、`#hedges`、`#theirs`、`#moved`、`#speeds`、`#days`，以及 `MeshWire` 的幂等集合）改成按地址（`<workspace>/<station>`）记：一个 workspace 一条连接，各自出示自己 workspace 的凭证。请求协议不变。
- `dropLink`、凭证被拒后重连只影响那个地址。
- `status`、`notices` 这类不分 workspace 的 topic，条目上标出 workspace。
- station 设置里：主 workspace 的管理员看到「加入另一个 workspace」（流程见上面「加入的入口」）；station 列表里标出它也在哪些 workspace。加入时写明软隔离。
- 已做的（docs/client-core.md）：`joinable {workspace}` 列出可以加进来的 station（只读已有的 workspace 数据）；`station.join {workspace, station}` 在目标 workspace 建登记 token，再经主 workspace 的连接让 station `POST /workspaces/join`，拒绝原因（旧 station 404、旧 cloud、锁、套餐上限）用中文说；`memberships {station}` 是 station 的 `GET /workspaces` 加每个加入的 workspace 开放的文件夹，只给主 workspace 的管理员；`stations` 视图里加入的 station 带 `joined` 和主 workspace 的名字 `home`；`drive.setRoots` 可带 `workspace`。界面：「添加 station」里选「已有的 station」（web、手机 web、安卓），station 页的 Workspace 一节，列表里「来自 X」，电脑上文件夹右键「在 X 里开放」；Profile 页给主 workspace 的管理员每个加入的 workspace 一个「也给 X 用」开关（`profile.put` 的 `input.workspaces`，`Profile.workspaces`）；加入的 station 没有开放给这个 workspace 的 Profile 时，新建对话（core `newChat` 的 `blocked: shared`）说明该找谁打开，不再提示添加 Profile。station 设置里从主 workspace 这边「加入另一个 workspace」还没做；手机 web 和安卓上给加入的 workspace 开放文件夹也还没做。

## 兼容

- 旧 station + 新 cloud：旧 station 只会调 enroll，照旧搬家；`state` 顶层字段照旧，它只有一个 membership，`workspaces` 是空的。
- 新 station + 旧 cloud：`state` 没有 `workspaces`，`joined` 保持为空；`/v1/stations/join` 是 404，station 说明「这个控制面还不支持」，什么都没变。
- 旧客户端 + 新 station：旧 core 按 station id 复用连接，同一个人在两个 workspace 里都能看到这台 station 时，另一个 workspace 里显示的会是先连上的那个 workspace 的内容（都是他有权看的，不会漏给别人）。加入第二个 workspace 的入口只在新客户端里有，可以接受。
- 数据：`sessions.ws`、`archive_policy.ws` 用加列迁移，旧行为主 workspace。
