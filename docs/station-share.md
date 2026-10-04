# Station 之间分享东西（设计稿）

> 状态：设计，未实现。chat EMBER/1791121239.467000。

## 要解决的事

现在每台 station 什么都是自己的：账号（`config.json` 的 `profiles`，订阅登录在 `homes/<profile>/`）、API key、自动决策设置、Slack bot、agent 的记忆和 skills（`agent/`）。新加一台机器要从头配一遍，一台机器关了它上面的东西就没了，几台 station 学到的教训互相看不到。

目标：

1. 每台 station 都可以把自己的一些东西**分享**出来，workspace 里别的 station 直接用，不用再配、不用再登录。
2. 分享出来的东西不属于哪台机器。它有一个 **host**，host 可以是 workspace 里的任意一台，**随时能换**；原来的 host 不在了，别的 station 也能接管。
3. 数据只在 station 之间走（iroh，端到端加密）。cloud 只记一个名字：每样东西现在的 host 是谁，不碰 key 和 token。

不做：cloud 存配置、多个 workspace 之间共享、跨 workspace 搬东西。

## 概念

- **分享项（share）**：一样可以分享的东西，有 workspace 内唯一的 id（`sh_<ULID>`）、种类、名字。种类见下表。
- **host**：分享项的权威副本在这台。它负责只能由一处做的事：刷新订阅 token、接收写入、给别人发最新版本。
- **使用方**：别的 station。本地有一份用得上的副本（或者借来的短期凭据），用的时候不必每次去问 host。
- **备用**：拿着一份能接管用的完整副本（包括订阅的 refresh token）的使用方。默认每个使用方都是备用。
- **代（epoch）**：每次换 host 加一。所有 `share.*` 的答复都带 epoch，旧 epoch 的 host 发来的东西不收；host 发现自己的 epoch 落后了，立刻退成使用方。

| 种类 | 内容 | 使用方本地有什么 | host 独有的工作 |
|---|---|---|---|
| `subscription` | Claude / Codex 订阅登录 | 借来的短期 access token；备用另有加密存的完整登录 | 刷新 token（refresh token 一刷就换，只能有一处刷）；读配额 |
| `key` | API key 类 profile（Anthropic、OpenCode、各 provider） | 完整的 profile 和 key | 无（改 key、改模型由它发出） |
| `settings` | 自动决策规则和模型（以后可加别的 workspace 级设置） | 最后一次拿到的值，加本地覆盖 | 接收修改、发新版本 |
| `skills` | agent 的 skills 目录，可选带 `MEMORY.md` | 一份镜像 | 接收各台的写入，排顺序，发新版本 |
| `slack` | 一个 Slack connect（bot） | bot token（用来发消息） | 唯一持有 Socket Mode 连接（app token），收事件再分给对应的 station |

## cloud：只记 host

`Directory` 加一张表（`CREATE TABLE IF NOT EXISTS`）：

```
shares (workspace TEXT, id TEXT, kind TEXT, name TEXT, host TEXT, epoch INTEGER,
        updated_by TEXT, updated_at INTEGER, PRIMARY KEY (workspace, id))
```

- presence 的 `state` 帧加可选字段 `shares: [{id, kind, name, host, epoch}]`，变了就推（跟 `peers` 一样）。station 在 `cloud.json` 里存一份，加 `sharesCurrent`，语义同 `peersCurrent`：socket 刚连上、还没收到这一帧时，不认为自己知道 host 是谁。
- 接口（成员凭据，owner/admin 才能改）：
  - `POST /v1/workspaces/:ws/shares {id, kind, name}`：登记，host 是发起的 station。由 station 用自己的密钥签名调用，跟 enroll 的签名方式一样；成员在客户端点「分享」时，客户端通过 station 的管理接口让 station 去登记。
  - `PATCH /v1/workspaces/:ws/shares/:id {host, epoch}`：换 host。按 epoch 做比较交换（带的 epoch 必须等于当前的），成功后 epoch+1。
  - `DELETE /v1/workspaces/:ws/shares/:id`：停止分享。
  - `GET /v1/workspaces/:ws` 的答复加 `shares`，客户端拿来显示。
- station 被移出 workspace 时，它 host 的分享项留在表里，状态显示「host 已不在 workspace」，由人选一台接管。

旧 cloud 不给 `shares`：分享功能整个关掉，station 照旧运行。部署顺序是先 cloud，再 station，再客户端。

## station 之间：`share.*` 方法

走现有的 `stillfail/station/1`（`station/src/mesh/peer.ts` → `jobs/remote.ts` 的 `handle`），加一组方法。跟 `session.message` 一样，只要求对方是当前 roster 里的同 workspace station，不需要 `remoteTasks.allow`。再加一条检查：分享项的「可用 station」名单里有对方（默认整个 workspace）。

| 方法 | 谁问谁 | 做什么 |
|---|---|---|
| `share.list` | 任意 → 任意 | 对方 host 着哪些分享项、各自的 epoch、版本、状态（客户端也读这个） |
| `share.get {id, since}` | 使用方 → host | 拿 `key` / `settings` / `skills` 的当前版本（`skills` 按文件给差异），`since` 是本地已有的版本 |
| `share.watch {id}` | 使用方 → host | 长连的流，host 有新版本、状态或配额变化就推过来；先推当前值（「推送优先」） |
| `share.lend {id}` | 使用方 → host | 借一个订阅的 access token：`{token, expiresAt, epoch}` |
| `share.standby {id}` | host → 备用 | host 每次刷新完，把完整登录（含新的 refresh token）推给备用 |
| `share.put {id, base, change}` | 使用方 → host | 写 `settings` / `skills`；`base` 对不上就拒绝，由写的一方重做 |
| `share.handover {id, epoch}` | 新 host → 旧 host | 换 host 时向旧 host 要最新的完整内容；旧 host 先停掉刷新再给 |
| `share.spent {id, until}` | 使用方 → host | 用这个订阅的某轮撞到额度了，host 去重读配额并推给所有人 |
| `slack.event {connect, event}` | Slack host → 线程所在的 station | 把 Slack 事件转给真正拥有这个线程的 station |

所有答复都带 `epoch`。收到更旧的 epoch 一律不收；发现对方的 epoch 更新，就先去读 cloud 状态再说。

## 订阅：只有 host 刷新

Claude Code 已经有现成的路子。`machine` profile 就是靠 `CLAUDE_CODE_OAUTH_TOKEN` 把 access token 交给进程，进程自己不刷新，token 快过期时 station 带着新 token 重启这个进程（resume）。见 `agents/machine-logins.ts`、`agents/claude.ts` 里的 `machineToken` / `machineExpires`。使用方的订阅照这个做：

- `agents/claude.ts`：`isMachine(profile)` 那一支扩成「profile 的 token 由别处给」：本机登录给 `machineToken`，借来的给 `shares.lend(id)`。过期前重启的逻辑不用变。
- `agents/codex.ts`：Codex 用 `auth.json`，会自己用 refresh token 刷新。**要先在 studio 上验证**：把只有 access token、没有可用 refresh token 的 `auth.json` 给 Codex，它会不会一直用到过期，过期时是不是干净地报错（station 再借一个、写回、重启）。如果不行，备选方案是让借用方的 Codex 走 station 本地的一个转发：用 `codexOverrides` 把 ChatGPT 后端地址指到本机，由 station 换上借来的 token。
- host 一侧：`accounts/oauth.ts` 已经在本机锁下刷新 Claude 的登录。改动是刷新前先确认自己现在是 host：`sharesCurrent` 为真，cloud 里的 host 是自己，epoch 也一致。三条有一条不满足就不刷，宁可让 token 过期，也不能让两台各刷一次、把同一个登录互相踢掉。刷新成功后，先写本地，再 `share.standby` 推给备用。
- 配额：只有 host 读（`accounts/quota.ts`），通过 `share.watch` 推给使用方。使用方的 `sessions/accounts.ts` 里的 `setHealth` 和 `spent` 用 host 推来的值；本地撞到额度时发 `share.spent`。
- 检查（`profile.check`）：使用方这边不去直接调 provider，而是问 host。

已知限制：cloud 连不上时，host 不刷新，使用方手里的 token 用完就停。Claude 的 access token 有几个小时，平常的断线不会碰到；真碰到了会显示「host 连不上 cloud，等它回来」。

## 换 host、接管

客户端的分享项页面有「换到…」：

1. **原 host 在线（移交）**：客户端调 cloud 的 `PATCH`，epoch+1，host 改成新的。原 host 收到新的 `state` 帧后停止刷新、退成使用方。新 host 先用 `share.handover` 向原 host 要最新内容，拿到后才开始干 host 的活；要不到的话，就用自己作为备用存的那份。
2. **原 host 不在线（接管）**：一样是 `PATCH`。只能选「备用」名单里的 station，页面会说明原 host 最后在线的时间。新 host 用备用副本；订阅的 refresh token 如果被 provider 拒了（原 host 失联前刚刷过、还没推出来），这个订阅就要重新登录一次，页面会直说。
3. 原 host 回来以后，看到 cloud 里 host 已经不是自己，就把本地那份变成使用方的形式。它离线期间如果有没推出去的写入（settings / skills），用 `share.put` 交给新 host，base 对不上就按冲突处理（见下）。

换 host 时，使用方的 `config.json` 不变：它用的一直是 `share.id`，host 只是在后台换了。

## 使用方的 `config.json`

agent 和 hub 的代码继续只读 `config.json`。分享来的东西写成带 `share` 字段的 profile：

```json
{"id": "sh_01J…", "name": "Claude Max（左）", "runtime": "claude",
 "access": {"kind": "subscription"}, "home": "homes/sh_01J…",
 "share": {"id": "sh_01J…", "epoch": 3}}
```

- host 一侧原来的 profile 保留原 id（chat、connect 的 `bind.profile` 都还指着它），只是加上 `"share": {"id": …}`。使用方新建的 profile 直接用 share id 当 id。
- `key`：`access.key` 照原样写进去，这样退回 Rust station 也能直接用。
- `subscription`：使用方的 home 里不放登录文件（交给进程的 token 在内存里）。备用的完整登录存在 `<data>/share/<id>/standby.json`（权限 600，不放在 home 里，免得 Claude Code 自己拿去刷新）。退回 Rust station 时，这个 profile 会显示「要登录」，不会刷坏 host 的登录。
- 停止分享，或者这台不再在可用名单里：使用方删掉这条 profile，以及 standby。正在用它的 chat 按现在「profile 不可用」的路子换到别的 profile。
- `accounts/check.ts`（`parse_config` 的检查）要接受 `share` 字段，并防止 id 跟本地 profile 撞车。

`settings`：使用方「跟随」某个设置分享项后，`config.json` 里写入 `automaticDecisions` 和 `"automaticDecisionsShare": {"id": …, "version": …, "override": {…}}`。本地改其中某一项就记成覆盖，页面上能「恢复跟随」。

## skills 和记忆

现在所有 profile 共用 `agent/`（`sessions/agent-home.ts`），里面是 `MEMORY.md` 和 `skills/`。

- 一个 `skills` 分享项对应 `agent/skills/` 下的一组 skill 目录（host 选哪些），可以带上 `MEMORY.md`。使用方镜像到同一个位置，agent 照常读写，不需要知道哪个 skill 是分享来的。
- 写入：使用方的 station 盯着这些文件，agent 改了就用 `share.put {base}` 发给 host。host 按顺序接收，加版本号，再推给所有人。
- 冲突：同一个文件两边同时改，后到的那份 base 对不上。host 不覆盖，而是把后到的那份存成 `SKILL.conflict-<station>.md`，并通过迁移说明那条通道告诉写的那个 session 的 agent，让它去合并。记忆文件是 agent 自己写的短文字，冲突很少，按这个办法处理够用。
- 内置 skills（`stillfail-*`）由各台 station 自己写，不参与分享。
- 要在 `agents/migrations.ts` 加一条：agent 的 skills 和记忆可能是分享来的，写了会同步给别的 station。

## Slack bot

一个 Slack app 的 Socket Mode 连接，Slack 会把事件随机分给其中一条连接，所以一个 bot 只能有一处连着。这正好就是「host」：

- host 持有 app token 并保持连接；bot token 发给使用方，这样每台都能用 bot 身份发消息、读历史（`slack_api`、`chat_post` 照旧）。
- 每个线程归一台 station（就是它的 session 在的那台）。host 收到事件后查 `thread → station`。是自己的就自己处理；是别人的，就用 `slack.event` 转过去。新线程由 host 自己接。
- 换 host 时，旧 host 把自己知道的 `thread → station` 交给新 host（`share.handover`）；旧线程的 session 不搬，留在原来那台，事件转过去继续。
- 这块改动最大（`slack/` 收事件的入口、`connects` 的配置），可以放在最后做；不做也不影响其余部分。

## 客户端

core（`client/core-ts`）：

- 新 topic `shares`（按 workspace）：cloud 的 host 表（`GET /v1/workspaces/:ws` 的 `shares`），加上每台 station `share.list` / overview 里的状态。哪台先到先显示哪台，其他的后补进来，不用 loading 挡住整个页面。
- 新的具名调用（都走 `doing`）：`share.publish {station, profile|kind}`、`share.unpublish {id}`、`share.move {id, station}`、`share.allow {id, stations}`、`share.use {station, id, on}`（这台不用某个分享项）、`share.follow {station, id}`（设置跟随）。
- station 的 overview 里每个 profile 加可选的 `share: {id, role: "host"|"user"|"standby", host, epoch, state}`；旧 station 不给这个字段，页面就按「只在这台」显示。

界面（web 的 `pages/Accounts.tsx`、`cloud/settings.tsx` 里的 `RuntimeSettings`、`mobile/Profiles.tsx`，安卓的 `screens/Profiles.kt`）：

- 「Profile」页从「按 station 分组」改成「workspace 的账号」：分享项一张卡片，写明 host、哪几台在用、状态。只在某台上的 profile 放在下面「只在 X」一组，卡片上有「分享」按钮。
- 分享项详情：host（「换到…」）、可用的 station（默认全部）、备用、各台的用量。原 host 离线时，按钮变成「让 X 接管」。
- 设置页的自动决策显示「跟随 X 的设置」/「本台覆盖了 2 项」。
- 新加一台 station 后，它的 profile 列表里直接就有已经分享的东西，不需要额外操作。

## 兼容和部署

- 新字段全是可选的：`config.json` 的 `share`、overview 的 `share`、state 帧的 `shares`。旧 station、旧客户端、旧 cloud 都当没有。
- `stillfail.db` 不改。分享的状态放在 `<data>/share/` 下的文件里，写法跟 `remote/` 一样（原子写，权限 600）。退回 Rust station 照常能跑：key 类的分享能用，借来的订阅显示要登录。
- 部署顺序：cloud → station → 客户端。新客户端配旧 station：显示「只在这台」，不能分享；旧客户端配新 station：只看到普通的 profile。
- 改了 agent 能感知的东西（skills 会同步），所以要在 `migrations.ts` 加说明。

## 要改的地方一览

| 范围 | 文件 | 改什么 |
|---|---|---|
| cloud | `cloud/src/directory.ts`、`api.ts` | `shares` 表、登记/换 host/删除接口、`state` 帧和 workspace 答复里带上 `shares` |
| station 状态 | `station/src/cloud/state.ts`、`presence.ts` | 存 `shares` 和 `sharesCurrent`，变化通知 |
| station 新模块 | `station/src/share/`（新） | 分享项登记、host/使用方角色切换、epoch 检查、`share.*` 的服务端和客户端、`<data>/share/` 的存储、把分享内容写进 `config.json` |
| 站间传输 | `station/src/mesh/peer.ts`、`jobs/remote.ts` | `handle` 把 `share.*`、`slack.event` 交给新模块；`share.watch` 要做成流（现在一个请求一个流，要加长连的推送） |
| 订阅 | `agents/claude.ts`、`agents/codex.ts`、`agents/machine-logins.ts`、`accounts/oauth.ts`、`accounts/quota.ts` | 借来的 token、只有 host 才刷新、配额由 host 推送 |
| 账号 | `accounts/index.ts`、`accounts/check.ts`、`accounts/profiles.ts`、`sessions/accounts.ts`、`api/routes/accounts.ts`、`api/overview.ts` | profile 的 `share` 字段、分享/停止/换 host 的管理接口、overview 带分享状态、使用方的检查和额度 |
| skills | `sessions/agent-home.ts`、`agents/migrations.ts` | 盯文件变化、同步、冲突文件、迁移说明 |
| Slack | `station/src/slack/`、`api/routes/slack.ts` | 只有 host 连 Socket Mode、事件按线程转发、移交线程表 |
| core | `client/core-ts/src/ops.ts`、`station/sync.ts`、新 `shares.ts` | `shares` topic、具名调用、`doing` |
| web | `cloud/settings.tsx`、`pages/Accounts.tsx`、`ProfileCard.tsx`、`mobile/Profiles.tsx`、`AutomaticDecisions.tsx` | workspace 账号列表、分享项详情、换 host、设置跟随 |
| 安卓 | `screens/Profiles.kt`、`data/Accounts.kt` | 同 web |
| 文档 | 本文、`docs/station-peers.md` | 新方法写进站间协议 |

## 先验证的事

1. Codex 在 `auth.json` 里只有 access token 时的表现（决定 Codex 订阅走「写 auth.json」还是「本地转发」）。
2. Claude 订阅的 access token 实际能用多久（决定使用方多久借一次、cloud 断线能撑多久）。
3. `share.watch` 的长流放在现有一个请求一个 QUIC 流的传输上，空闲超时（`servePeer` 现在 60 秒没请求就断）要改成按流保活。

测试照 `docs/station-peers.md` 的做法：在 studio 上起本地控制面加两三台临时 station，验证分享、借 token、移交、接管、旧 host 回来退成使用方、两台同时被设成 host 时只有一台刷新，以及冲突写入。
