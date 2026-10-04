# Station 之间分享东西（设计稿）

> 状态：设计，未实现。chat EMBER/1791121239.467000。

## 要解决的事

现在每台 station 什么都是自己的：账号（`config.json` 的 `profiles`，订阅登录在 `homes/<profile>/`）、API key、自动决策设置、agent 的记忆和 skills（`agent/`）。新加一台机器要从头配一遍，几台 station 学到的教训互相看不到。

目标：

1. 每台 station 都可以把自己的一些东西**分享**出来，workspace 里别的 station 直接用，不用再配、不用再登录。
2. 分享出来的东西有一个 **host**，就是真正拿着它的那台。host 可以随时**换**到 workspace 里的另一台：东西整个搬过去，原来那台变成普通的使用方。
3. 数据只在 station 之间走（iroh，端到端加密）。cloud 只记一个名字：每样东西现在的 host 是谁，不碰 key 和 token。

已定的规则（2026-10-04）：

- 分享出去默认整个 workspace 都能用，也可以只选某几台。
- **使用方联系不上 host，这样东西就用不了**：使用方不留副本，没有备用，不做接替。换 host 只能在原 host 在线时由它交出去；host 那台机器没了，它 host 的东西就跟着没了，要重新添加。
- Slack bot 先不做。

不做：cloud 存配置、多个 workspace 之间共享、自动接替、Slack bot 分享和搬家。

## 概念

- **分享项（share）**：一样分享出来的东西，有 workspace 内唯一的 id（`sh_<ULID>`）、种类、名字、可用的 station（空 = 整个 workspace）。
- **host**：唯一拿着它的那台 station。订阅的 refresh token、API key、设置和 skills 的正本都只在 host 上。
- **使用方**：别的 station。用的时候实时向 host 要，只放在内存里，不落盘。

| 种类 | 内容 | 使用方怎么用 | 联系不上 host 时 |
|---|---|---|---|
| `subscription` | Claude / Codex 订阅登录 | 向 host 借短期 access token 交给进程 | 不能开新轮次；手上那个 token 过期前，正在跑的那轮能跑完 |
| `key` | API key 类 profile（Anthropic、OpenCode、各 provider） | 进程启动时向 host 要 key，只放在内存和进程的环境变量里 | 不能开新的进程 |
| `settings` | 自动决策的规则和模型 | 跟随 host 的设置 | 用本台自己的设置 |
| `skills` | `agent/skills/` 里选定的几个 skill，可以带上 `MEMORY.md` | 在 agent home 里出现、可读可写，写入实时发给 host | 从 agent home 里拿掉，agent 看不到 |

## cloud：只记 host

`Directory` 加一张表（`CREATE TABLE IF NOT EXISTS`）：

```
shares (workspace TEXT, id TEXT, kind TEXT, name TEXT, host TEXT, allow TEXT,
        updated_by TEXT, updated_at INTEGER, PRIMARY KEY (workspace, id))
```

- `allow`：可用 station 的 JSON 数组，空表示整个 workspace。
- presence 的 `state` 帧加可选字段 `shares: [{id, kind, name, host, allow}]`，变了就推（跟 `peers` 一样）。station 存在 `cloud.json` 里。
- 接口：
  - `POST /v1/workspaces/:ws/shares {id, kind, name, allow}`：由 host station 用自己的密钥签名登记（签名方式同 enroll）。成员在客户端点「分享」时，是客户端通过 station 的管理接口让它去登记的。
  - `PATCH /v1/workspaces/:ws/shares/:id {allow}`：改可用名单（成员凭据，owner/admin）。
  - `PATCH /v1/workspaces/:ws/shares/:id {host}`：只接受**当前 host** 签名的请求，也就是只能由原 host 交出去（见「换 host」）。
  - `DELETE /v1/workspaces/:ws/shares/:id`：host 签名，或者 owner/admin。后者用来清掉 host 已经不在的分享项。
  - `GET /v1/workspaces/:ws` 的答复加上 `shares`。
- host 被移出 workspace，或者机器没了：这些分享项显示「host 不在」，只能删掉。

旧 cloud 不给 `shares`：分享功能整个关掉，station 照旧运行。部署顺序是先 cloud，再 station，再客户端。

## station 之间：`share.*` 方法

走现有的 `stillfail/station/1`（`station/src/mesh/peer.ts` → `jobs/remote.ts` 的 `handle`），加一组方法。跟 `session.message` 一样，只要求对方是当前 roster 里同 workspace 的 station，不需要 `remoteTasks.allow`。另外再检查一条：对方在这个分享项的 `allow` 名单里，或者名单为空；以 cloud 推来的为准。

| 方法 | 谁问谁 | 做什么 |
|---|---|---|
| `share.list` | 任意 → 任意 | 对方 host 着哪些分享项、各自的状态、版本、配额（客户端也读这个） |
| `share.watch {id}` | 使用方 → host | 长连的流：先推当前值，之后有变化就推（状态、配额、设置、skills 的新版本） |
| `share.lend {id}` | 使用方 → host | 借订阅的 access token：`{token, expiresAt}` |
| `share.key {id}` | 使用方 → host | 拿 `key` 分享项的 profile 内容和 key |
| `share.read {id, since}` | 使用方 → host | 拿 `settings` / `skills` 的当前版本（skills 按文件给差异） |
| `share.put {id, base, change}` | 使用方 → host | 写 `skills`（以后也可以写 `settings`）；`base` 对不上就拒绝 |
| `share.spent {id, until}` | 使用方 → host | 用这个订阅的某轮撞到额度了，host 去重读配额，再推给所有人 |
| `share.handover {id}` | 原 host → 新 host | 换 host：把正本整个交过去（见下） |

「联系得上」以 `share.watch` 的流是否连着为准：流断了就当联系不上，同时按退避重连，连上后先推当前值。

## 订阅：只有 host 刷新

Claude Code 已经有现成的路子。`machine` profile 就是靠 `CLAUDE_CODE_OAUTH_TOKEN` 把 access token 交给进程，进程自己不刷新，token 快过期时 station 带着新 token 重启这个进程（resume）。见 `agents/machine-logins.ts`，以及 `agents/claude.ts` 里的 `machineToken` / `machineExpires`。

- `agents/claude.ts`：`isMachine(profile)` 那一支扩成「profile 的 token 由别处给」：本机登录给 `machineToken`，分享来的给 `share.lend`。过期前重启的逻辑不变；借不到就跟本机登录读不到一样，开不了这一轮。
- `agents/codex.ts`：Codex 用 `auth.json`，会自己用 refresh token 刷新。**要先在 studio 上验证**：给 Codex 一个只有 access token、没有可用 refresh token 的 `auth.json`，它会不会一直用到过期，过期时是不是干净地报错（station 再借一个、写回、重启）。如果不行，备选方案是让借用方的 Codex 走 station 本地的一个转发：用 `codexOverrides` 把 ChatGPT 后端的地址指到本机，由 station 换上借来的 token。
- host 一侧：`accounts/oauth.ts` 照旧在本机的锁下刷新。整个 workspace 只有 host 拿着 refresh token，所以刷新时不需要再问 cloud。
- 配额：只有 host 读（`accounts/quota.ts`），通过 `share.watch` 推给使用方。使用方的 `sessions/accounts.ts`（`setHealth`、`spent`）用推来的值；本地撞到额度时发 `share.spent`。
- 检查（`profile.check`）：使用方不去直接调 provider，而是问 host；联系不上 host 时，状态显示「host 不在线」，pool 不选它。

## 换 host

客户端的分享项页面有「换到…」，原 host 在线时才能点：

1. 客户端请求原 host（station 的管理接口）把分享项交给 Y。
2. 原 host 先停用：不再刷新、不再借出，正在跑的借用方继续用手上的 token。然后通过 `share.handover` 把正本发给 Y：订阅的完整登录、key、设置、skills 的文件和版本。
3. Y 写好本地文件，回答「收到」。原 host 签名 `PATCH host=Y`。cloud 改好后推新的 `state` 帧，使用方看到 host 变了，就把 `share.watch` 重新连到 Y。
4. 原 host 删掉本地正本（订阅的 refresh token 一定删掉），把本地那条 profile 改成使用方的样子。

任何一步失败都退回到第 1 步之前：原 host 恢复正常，Y 删掉收到的东西。第 3 步 cloud 改成了、但原 host 没收到答复：原 host 去读 cloud 状态，按 cloud 说的为准，继续或者回退。这样同一时刻只有一台拿着 refresh token，两台之间的这一次交接是唯一的空档，这期间谁都不刷新。

换 host 时，使用方的 `config.json` 不用改：它认的是 `share.id`。

## 使用方的 `config.json`

agent 和 hub 的代码继续读 `config.json`。分享来的东西写成一条带 `share` 字段的 profile，**不带 key、不带登录**：

```json
{"id": "sh_01J…", "name": "Claude Max（左）", "runtime": "claude",
 "access": {"kind": "subscription"}, "home": "homes/sh_01J…",
 "share": {"id": "sh_01J…"}}
```

- 这条记录只是一个占位：有了它，chat 和 connect 的 `bind.profile` 能指着这个分享项，pool 也知道有这么个 profile。真正的凭据在启动进程时现取：`agents/profiles.ts` 的 `accessEnv` / `profileEnv` 对带 `share` 的 profile，从分享模块拿内存里的 key，或者借 token。
- host 一侧原来的 profile 保留原 id（chat、connect 都还指着它），只是加上 `"share": {"id": …}`。换 host 后，新 host 建的那条用 share id 当 id。
- 停止分享，或者这台不在 `allow` 里了：使用方删掉这条记录。正在用它的 chat 按现在「profile 不可用」的路子换到别的 profile。
- `accounts/check.ts`（`parse_config` 的检查）要接受 `share` 字段、允许分享来的 profile 没有 key，并防止 share id 跟本地 profile 的 id 撞车。
- 退回 Rust station 的话，这些占位 profile 用不了：显示要登录或者缺 key，不会用错别人的东西。

`settings`：使用方选「跟随」某个设置分享项后，`config.json` 里只记 `"automaticDecisionsShare": "sh_…"`。生效的值来自 host 推来的内容，联系不上 host 时退回本台自己的 `automaticDecisions`。

## skills 和记忆

现在所有 profile 共用 `agent/`（`sessions/agent-home.ts`），里面是 `MEMORY.md` 和 `skills/`，每个 profile 的 home 用链接指过去。

- host 选 `agent/skills/` 下的几个 skill 目录分享，可以带上 `MEMORY.md`。
- 使用方把分享来的内容放在 `<data>/share/<id>/`（只在跟 host 连着时有效），`agent-home.ts` 把这些 skill 目录链接进 agent home 的 `skills/`。分享来的 `MEMORY.md` 以「来自 X 的记忆」接在本台 `MEMORY.md` 后面，作为单独的一个文件链接进去。联系不上 host 时把这些链接拿掉，重新连上后先读到最新版本，再链接回来。
  - 这里留了一份文件，因为 agent 只能读文件。但它只在连着 host 时才可见、可写，断开后拿掉；它是一份缓存，不算副本。
- 写入：使用方的 station 盯着这些文件，agent 改了就立刻用 `share.put {base}` 发给 host。host 按顺序接收，加版本号，推给所有人。发的时候 host 不在线，就把这次修改留着，重连时再交；base 对不上就按冲突处理。
- 冲突：host 不覆盖，而是把后到的那份存成 `SKILL.conflict-<station>.md`，通过 `session.message` 告诉写的那个 session 的 agent，让它去合并。
- 内置 skills（`stillfail-*`）由各台 station 自己写，不参与分享。
- 在 `agents/migrations.ts` 加一条：agent 的 skills 和记忆可能是别的 station 分享来的，写了会同步过去。

## 客户端

core（`client/core-ts`）：

- 新 topic `shares`（按 workspace）：cloud 的 host 表（`GET /v1/workspaces/:ws` 的 `shares`），加上每台 station 的 `share.list` / overview 里的状态。哪台先到先显示哪台，其他的后补进来，不用 loading 挡住整个页面。
- 新的具名调用（都走 `doing`）：`share.publish {station, profile|kind, allow}`、`share.unpublish {id}`、`share.allow {id, stations}`、`share.move {id, station}`、`share.use {station, id, on}`（这台不用某个分享项）、`share.follow {station, id}`（跟随设置）。
- station 的 overview 里每个 profile 加可选的 `share: {id, role: "host"|"user", host, state}`。`state` 可以是 `ok` / `host_offline` / `not_allowed`。旧 station 不给这个字段，页面就按「只在这台」显示。

界面（web 的 `pages/Accounts.tsx`、`cloud/settings.tsx` 里的 `RuntimeSettings`、`ProfileCard.tsx`、`mobile/Profiles.tsx`，安卓的 `screens/Profiles.kt`、`data/Accounts.kt`）：

- 「Profile」页从「按 station 分组」改成「workspace 的账号」：每个分享项一张卡片，写明 host、哪几台在用、状态（host 不在线时整张卡片是灰的）。只在某台上的 profile 放在下面「只在 X」一组，卡片上有「分享」按钮。
- 分享项详情：host 和「换到…」（原 host 不在线时不能点，并说明原因）、可用的 station（默认整个 workspace，可以改成只选几台）、各台的用量、停止分享。
- 设置页的自动决策：「跟随 X 的设置」/「X 不在线，正在用本台的设置」。
- 新加一台 station 后，它的 profile 列表里直接就有已经分享出来的东西。

## 兼容和部署

- 新字段全是可选的：`config.json` 的 `share` 和 `automaticDecisionsShare`、overview 的 `share`、state 帧的 `shares`。旧 station、旧客户端、旧 cloud 都当没有。
- `stillfail.db` 不改。分享相关的状态放在 `<data>/share/` 下的文件里，写法跟 `remote/` 一样（原子写，权限 600）。
- 部署顺序：cloud → station → 客户端。新客户端配旧 station：显示「只在这台」，不能分享；旧客户端配新 station：只看到普通的 profile，分享来的那些显示成一条条 profile。
- 改了 agent 能感知的东西（skills 会同步），所以要在 `migrations.ts` 加说明。

## 要改的地方一览

| 范围 | 文件 | 改什么 |
|---|---|---|
| cloud | `cloud/src/directory.ts`、`api.ts` | `shares` 表，登记、改名单、交出、删除的接口，`state` 帧和 workspace 的答复里带上 `shares` |
| station 状态 | `station/src/cloud/state.ts`、`presence.ts` | 存 `shares`，变了就通知 |
| station 新模块 | `station/src/share/`（新） | 登记、`share.*` 的服务端和调用端、`share.watch` 连接的管理、内存里的凭据、交接流程、`<data>/share/` 的存储、往 `config.json` 写占位 profile |
| 站间传输 | `station/src/mesh/peer.ts`、`jobs/remote.ts` | `handle` 把 `share.*` 交给新模块；`share.watch` 要做成长流（现在一个请求一个 QUIC 流，`servePeer` 60 秒没新请求就断，要改成按流保活） |
| 订阅和 key | `agents/claude.ts`、`agents/codex.ts`、`agents/profiles.ts`、`agents/machine-logins.ts`、`accounts/quota.ts` | 借来的 token、启动时现取的 key、配额由 host 推送 |
| 账号 | `accounts/index.ts`、`accounts/check.ts`、`accounts/profiles.ts`、`sessions/accounts.ts`、`sessions/config.ts`、`api/routes/accounts.ts`、`api/overview.ts` | profile 的 `share` 字段，分享/停止/改名单/交出的管理接口，overview 带分享状态，使用方的检查和额度，跟随设置 |
| skills | `sessions/agent-home.ts`、`agents/migrations.ts` | 连着 host 时链接进来、断开时拿掉，盯文件变化，冲突文件，迁移说明 |
| core | `client/core-ts/src/ops.ts`、`station/sync.ts`、新 `shares.ts` | `shares` topic、具名调用、`doing` |
| web | `cloud/settings.tsx`、`pages/Accounts.tsx`、`ProfileCard.tsx`、`mobile/Profiles.tsx`、`AutomaticDecisions.tsx` | workspace 账号列表、分享项详情、换 host、可用名单、跟随设置 |
| 安卓 | `screens/Profiles.kt`、`data/Accounts.kt` | 同 web |
| 文档 | 本文、`docs/station-peers.md` | 把新方法写进站间协议 |

## 先验证的事

1. Codex 在 `auth.json` 里只有 access token 时的表现，决定 Codex 订阅走「写 auth.json」还是「本地转发」。
2. Claude 订阅的 access token 实际能用多久，决定多久借一次。
3. 在现有传输上做 `share.watch` 长流：保活、断开的检测、重连。

测试照 `docs/station-peers.md` 的做法：在 studio 上起本地控制面，加两三台临时 station，验证这些：分享、借 token 跑一轮、按名单拒绝、host 下线后使用方马上不能用、重新上线后恢复、换 host（包括中途失败回退）、skills 的写入、冲突。
