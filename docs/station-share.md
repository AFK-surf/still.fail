# Station 之间分享东西（设计稿）

> 状态：已实现（分支 station-share）。cloud 不参与分享（见「cloud：什么都不记」）；实现跟下面设计的其他出入见文末。chat EMBER/1791121239.467000。

## 要解决的事

现在每台 station 什么都是自己的：账号（`config.json` 的 `profiles`，订阅登录在 `homes/<profile>/`）、API key、自动决策设置、agent 的记忆和 skills（`agent/`）。新加一台机器要从头配一遍，几台 station 学到的教训互相看不到。

目标：

1. 每台 station 都可以把自己的一些东西**分享**出来，workspace 里别的 station 直接用，不用再配、不用再登录。
2. 分享出来的东西有一个 **host**，就是真正拿着它的那台。host 可以随时**换**到 workspace 里的另一台：东西整个搬过去，原来那台变成普通的使用方。
3. 数据只在 station 之间走（iroh，端到端加密）。cloud 只记一个名字：每样东西现在的 host 是谁，不碰 key 和 token。

已定的规则（2026-10-04）：

- **分享是一个开关**：每个 Profile、每个 skill 默认只在自己那台用（新加的和升级前已有的都一样，有些东西本来就有 station 限制）。打开「分享给其他 station」后，默认所有 station 都能用，可以再改成只勾几台。界面上不出现「host」；只有分享出去的订阅显示「登录在 X」，因为它离线时别处用不了。
- 自动决策的设置不做分享：现在的自动决策页本来就能在一处改所有 station。
- **订阅只能由 host 刷新**：refresh token 一刷就换，两处各刷一次就互相踢掉，所以只有 host 拿着它，使用方借短期 token，联系不上 host 就借不到。不留备用、不做接替；订阅换 host 只能在原 host 在线时由它交出去，host 那台机器没了就要重新登录。
- 其余的（API key、设置、skills）没有这个问题：使用方各存一份，host 不在线照常用；host 不在了，owner/admin 可以把 host 换到任意一台（它手上就有完整的一份）。不会自动换。
- Slack bot 先不做。

不做：cloud 存配置、多个 workspace 之间共享、自动换 host、Slack bot 分享和搬家。

## 概念

- **分享项（share）**：一样分享出来的东西，有 workspace 内唯一的 id（`sh_<ULID>`）、种类、名字、可用的 station（空 = 整个 workspace）。
- **host**：唯一拿着它的那台 station。订阅的 refresh token、API key、设置和 skills 的正本都只在 host 上。
- **使用方**：别的 station。订阅向 host 借短期 token；其余的在本地存一份，host 有变化就推过来。

| 种类 | 内容 | 使用方怎么用 | 联系不上 host 时 |
|---|---|---|---|
| `subscription` | Claude / Codex 订阅登录 | 向 host 借短期 access token 交给进程 | 不能开新轮次；手上那个 token 过期前，正在跑的那轮能跑完 |
| `key` | API key 类 profile（Anthropic、OpenCode、各 provider） | 完整的 profile 和 key 存在本地 `config.json` | 照常用，用最后一次拿到的 |
| `skills` | `agent/skills/` 里选定的几个 skill，可以带上 `MEMORY.md` | 镜像在本地，agent 可读可写，写入发给 host | 照常读写，修改攒着，重连后交给 host |

## cloud：什么都不记

除了账号系统，没有任何东西由 cloud 保证。cloud 只照旧给出 workspace 里有哪些 station（presence 的 `peers`），分享的事全在 station 之间：

- **host 记**：分享了什么、谁能用（`allow`，null 是整个 workspace）、告诉过谁、告诉的是第几版（state.json `hosted[id].told`），也就是谁有副本、谁在借用。
- **使用方记**：每个副本是从哪台来的（profile 的 `share.host`、state.json `borrowed[id].host`）、是第几版。
- **host 主动告诉**（`share.changed`）：分享了、内容变了、不再给这台了、搬到哪台了。没联系上的记着，过一阵再告诉（1 分钟起，越来越久，最多 30 分钟）。
- **使用方每次启动问一次**（`share.version`），补上自己离线期间的变化；对方说搬走了就转去问新的 host。
- **一台 station 被移出 workspace**：它分享的副本在各台被删掉，它作为使用方被各 host 忘掉。

## station 之间：`share.*` 方法

走现有的 `stillfail/station/1`（`station/src/mesh/peer.ts` → `jobs/remote.ts` 的 `handle`），加一组方法。跟 `session.message` 一样，只要求对方是当前 roster 里同 workspace 的 station，不需要 `remoteTasks.allow`。另外再检查一条：对方在这个分享项的 `allow` 名单里，或者名单为空；以 cloud 推来的为准。

| 方法 | 谁问谁 | 做什么 |
|---|---|---|
| `share.changed {id, version}` | host → 使用方 | 内容变了；使用方再 `share.get` |
| `share.version {id}` | 使用方 → host | 现在是第几版（每次启动问一次） |
| `share.lend {id}` | 使用方 → host | 借订阅的 access token：`{token, expiresAt}` |
| `share.key {id}` | 使用方 → host | 拿 `key` 分享项的 profile 内容和 key |
| `share.read {id, since}` | 使用方 → host | 拿 `skills` 的当前版本（按文件给差异） |
| `share.put {id, base, change}` | 使用方 → host | 写 `skills`；`base` 对不上就拒绝 |
| `share.spent {id, until}` | 使用方 → host | 用这个订阅的某轮撞到额度了，host 去重读配额，再推给所有人 |
| `share.handover {id}` | 原 host → 新 host | 换 host：把正本整个交过去（见下） |

「联系得上」以 `share.watch` 的流是否连着为准：流断了就按退避重连，连上后先推当前值。只有订阅在断开时不可用；其余的只是暂时收不到更新。

## 订阅：只有 host 刷新

Claude Code 已经有现成的路子。`machine` profile 就是靠 `CLAUDE_CODE_OAUTH_TOKEN` 把 access token 交给进程，进程自己不刷新，token 快过期时 station 带着新 token 重启这个进程（resume）。见 `agents/machine-logins.ts`，以及 `agents/claude.ts` 里的 `machineToken` / `machineExpires`。

- `agents/claude.ts`：`isMachine(profile)` 那一支扩成「profile 的 token 由别处给」：本机登录给 `machineToken`，分享来的给 `share.lend`。过期前重启的逻辑不变；借不到就跟本机登录读不到一样，开不了这一轮。
- `agents/codex.ts`：Codex 用 `auth.json`，会自己用 refresh token 刷新。**要先在 studio 上验证**：给 Codex 一个只有 access token、没有可用 refresh token 的 `auth.json`，它会不会一直用到过期，过期时是不是干净地报错（station 再借一个、写回、重启）。如果不行，备选方案是让借用方的 Codex 走 station 本地的一个转发：用 `codexOverrides` 把 ChatGPT 后端的地址指到本机，由 station 换上借来的 token。
- host 一侧：`accounts/oauth.ts` 照旧在本机的锁下刷新。整个 workspace 只有 host 拿着 refresh token，所以刷新时不需要再问 cloud。
- 配额：只有 host 读（`accounts/quota.ts`），通过 `share.watch` 推给使用方。使用方的 `sessions/accounts.ts`（`setHealth`、`spent`）用推来的值；本地撞到额度时发 `share.spent`。
- 检查（`profile.check`）：使用方不去直接调 provider，而是问 host；联系不上 host 时，状态显示「host 不在线」，pool 不选它。

## 换 host

客户端的分享项页面有「换到…」。

**订阅**：原 host 在线时才能点，流程如下。

1. 客户端请求原 host（station 的管理接口）把分享项交给 Y。
2. 原 host 先停用：不再刷新、不再借出，正在跑的借用方继续用手上的 token。然后通过 `share.handover` 把正本发给 Y：订阅的完整登录、key、设置、skills 的文件和版本。
3. Y 写好本地文件，回答「收到」。原 host 签名 `PATCH host=Y`。cloud 改好后推新的 `state` 帧，使用方看到 host 变了，就把 `share.watch` 重新连到 Y。
4. 原 host 删掉本地正本（订阅的 refresh token 一定删掉），把本地那条 profile 改成使用方的样子。

任何一步失败都退回到第 1 步之前：原 host 恢复正常，Y 删掉收到的东西。第 3 步 cloud 改成了、但原 host 没收到答复：原 host 去读 cloud 状态，按 cloud 说的为准，继续或者回退。这样同一时刻只有一台拿着 refresh token，两台之间的这一次交接是唯一的空档，这期间谁都不刷新。

**其余种类**：原 host 在线时走同一个流程（它先把还没推出去的东西交给新 host）。原 host 不在线时，owner/admin 直接改 cloud 里的 host，新 host 用自己本地那份当正本；原 host 回来后看到 host 不是自己了，就退成使用方，离线期间攒下的 skills 修改用 `share.put` 交给新 host，base 对不上按冲突处理。

换 host 时，使用方的 `config.json` 不用改：它认的是 `share.id`。

## 使用方的 `config.json`

agent 和 hub 的代码继续读 `config.json`。分享来的东西写成一条带 `share` 字段的 profile。`key` 类的 `access.key` 照常写进去（权限 600，跟本地 profile 一样），退回 Rust station 也能用；订阅的**不带登录**：

```json
{"id": "sh_01J…", "name": "Claude Max（左）", "runtime": "claude",
 "access": {"kind": "subscription"}, "home": "homes/sh_01J…",
 "share": {"id": "sh_01J…"}}
```

- 订阅的这条记录是个占位：chat 和 connect 的 `bind.profile` 能指着它，pool 也知道有这么个 profile；token 在启动进程时向 host 借（见上）。home 里不放登录文件，免得 Claude Code / Codex 自己去刷新。
- `key` 类：host 改了 key、模型等，通过 `share.watch` 推过来，使用方改写本地这条。
- host 一侧原来的 profile 保留原 id（chat、connect 都还指着它），只是加上 `"share": {"id": …}`。换 host 后，新 host 建的那条用 share id 当 id。
- 停止分享，或者这台不在 `allow` 里了：使用方删掉这条记录。正在用它的 chat 按现在「profile 不可用」的路子换到别的 profile。
- `accounts/check.ts`（`parse_config` 的检查）要接受 `share` 字段、允许分享来的 profile 没有 key，并防止 share id 跟本地 profile 的 id 撞车。
- 退回 Rust station 的话：`key` 类照常能用；订阅的占位显示要登录，不会刷坏 host 的登录。


## skills 和记忆

现在所有 profile 共用 `agent/`（`sessions/agent-home.ts`），里面是 `MEMORY.md` 和 `skills/`，每个 profile 的 home 用链接指过去。

- host 选 `agent/skills/` 下的几个 skill 目录分享，可以带上 `MEMORY.md`。
- 使用方把分享来的内容镜像在 `<data>/share/<id>/`，`agent-home.ts` 把这些 skill 目录链接进 agent home 的 `skills/`。分享来的 `MEMORY.md` 作为单独的「来自 X 的记忆」文件链接进去，跟本台的 `MEMORY.md` 并排。
- 写入：使用方的 station 盯着这些文件，agent 改了就立刻用 `share.put {base}` 发给 host。host 按顺序接收，加版本号，推给所有人。发的时候 host 不在线，就把这次修改留着，重连时再交；base 对不上就按冲突处理。
- 冲突：host 不覆盖，而是把后到的那份存成 `SKILL.conflict-<station>.md`，通过 `session.message` 告诉写的那个 session 的 agent，让它去合并。
- 内置 skills（`stillfail-*`）由各台 station 自己写，不参与分享。
- 在 `agents/migrations.ts` 加一条：agent 的 skills 和记忆可能是别的 station 分享来的，写了会同步过去。

## 客户端

原型：`share-prototype-v2.html`（chat EMBER/1791121239.467000）。

core（`client/core-ts`）：

- Profile 列表改成 workspace 级的 topic：cloud 的 `shares` 表，加上每台 station 的 overview（其中带 `share` 字段的 profile）。同一个分享项在各台上的占位只算一条；还没分享出去的 profile 按「可用的 station 只有这台」算，也是一条。哪台先到先显示哪台，其他的后补进来。
- 具名调用（都走 `doing`）：`profile.share {id, on}`（打开时登记分享项，可用的 station 为全部；关掉时撤销）、`profile.allow {id, stations|"all"}`（改可用的 station）、`profile.moveLogin {id, station}`（订阅换登录的 station）、`skill.share {name, on}`、`skill.allow {name, stations|"all"}`。
- overview 里每个 profile 加可选的 `share: {id, host, allow, state}`。旧 station 不给这个字段，就按「只在这台」显示。

界面（web 的 `cloud/settings.tsx` 里的 `RuntimeSettings`、`pages/Accounts.tsx`、`ProfileCard.tsx`、记忆页、`mobile/Profiles.tsx`，安卓的 `screens/Profiles.kt`、`data/Accounts.kt`）：

- **Profile 列表**：一条平的列表，不再按 station 分组。副标题：没分享的写「只在 ● office-linux」；分享出去的订阅写「登录在 ● studio」；可用范围不是全部时写「只给 studio、mac-mini」。只在出问题时上色：订阅登录的那台离线时，整行变淡，标红「macbook 离线」。
- **详情页**多一个开关「分享给其他 station」（关着时副标题「现在只在 office-linux 上用」）。打开后再出现两行：
  - 「登录在」（只有订阅才有）+「换」。那台离线时按钮不可用，并写明「macbook 上线后才能换」。点「换」弹出 station 列表，点一台就开始交接，那一行转圈，离线的灰掉。
  - 「可用的 station：全部 / studio、mac-mini」+「改」。弹出勾选列表；订阅登录的那台锁定勾着。下面一行小字说明以后新加的 station 会不会自动加进来。
- **添加 Profile**：流程不变，加好后只在那台用，要分享就去详情页打开开关。
- **记忆**：一个列表，每个 skill 跟 Profile 一样有分享开关和「可用的 station」。两台同时改了同一个文件时，标黄「两台同时改了，agent 在合并」。

## 兼容和部署

- 新字段全是可选的：`config.json` 的 `share`、overview 的 `share`、state 帧的 `shares`。旧 station、旧客户端、旧 cloud 都当没有。
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
| 订阅和 key | `agents/claude.ts`、`agents/codex.ts`、`agents/profiles.ts`、`agents/machine-logins.ts`、`accounts/quota.ts` | 借来的 token（只有订阅）、配额由 host 推送 |
| 账号 | `accounts/index.ts`、`accounts/check.ts`、`accounts/profiles.ts`、`sessions/accounts.ts`、`sessions/config.ts`、`api/routes/accounts.ts`、`api/overview.ts` | profile 的 `share` 字段，改可用名单（含第一次登记）、交出的管理接口，overview 带分享状态，使用方的检查和额度 |
| skills | `sessions/agent-home.ts`、`agents/migrations.ts` | 镜像链接进 agent home，盯文件变化，离线攒写入，冲突文件，迁移说明 |
| core | `client/core-ts/src/ops.ts`、`station/sync.ts`、新 `shares.ts` | `shares` topic、具名调用、`doing` |
| web | `cloud/settings.tsx`、`pages/Accounts.tsx`、`ProfileCard.tsx`、`mobile/Profiles.tsx`、记忆页 | workspace 级 Profile 列表、详情页的「登录在」「可用的 station」、记忆页的可用范围 |
| 安卓 | `screens/Profiles.kt`、`data/Accounts.kt` | 同 web |
| 文档 | 本文、`docs/station-peers.md` | 把新方法写进站间协议 |

## 实现跟设计的出入

- **cloud 不参与**（2026-10-04 用户定：「没有任何东西由 cloud 保证，除了账号系统」；「租借方记一下找谁借的，host 记一下谁借了」）：上面 cloud 一节已按此重写，前面各节里提到 cloud 记 host、`PATCH`、`state` 帧带 shares 的地方都作废。同一个订阅只有一台在续登录，由交接本身保证：只有 host 能交出去，交出去以后它删掉自己的登录。
- **没有 `share.watch` 长流**：变化由 host 用 `share.changed` 推，内容由使用方 `share.get` 取；配额和状态由使用方需要时问 host（`share.status`）：检查、额度轮询（有人看着时每 5 分钟）、借 token 时。
- **使用方怎么知道 host 不在**：借 token、问状态失败就记下联系不上（overview 的 `share.reachable`），之后按上面的退避再试，通了就把借来的订阅重新检查一遍。客户端把「cloud 说它离线」和「借用方联系不上它」都当作 host 不在。
- **换 host 只能由原 host 交出**（订阅和 key 一样），没有做「原 host 不在时把 key、skill 交给别台」。
- **`MEMORY.md` 不分享**，只分享 skills；记忆页仍按 station 分组，每个 skill 展开后有分享开关，分享来的标「来自 X」。同名时本台自己的 skill 优先，分享来的不链接进去。
- **Codex 订阅**：在 studio 上验证过（codex-cli 0.160.0），`auth.json` 里只有 access token、refresh token 是假的、`last_refresh` 是现在时，Codex 照常用到过期，不会自己去刷新；token 坏了干净地报 401 退出。ChatGPT 的 access token 约 10 天有效，借用方的 app-server 在离过期 6 小时内、没有会话在跑时重启并重新借。host 只在自己没有 Codex 进程用这个登录时才替它续期（续期会换掉 refresh token，正在跑的 Codex 手里还是旧的）。

## 测试

- `station/test/share.test.ts`：两台 station、一个只给成员名单的假 cloud，验证 key 的复制与同步、host 离线时副本还在、停止分享后删掉、按名单拒绝、借订阅 token（host 不在时借不到）、交出订阅（登录搬过去，原 host 留副本、id 不变）、skill 的复制、链接、改动回传、旧版本上的改动存成冲突文件。
- `client/core-ts/test/profiles-view.test.ts`：workspace 的 Profile 列表去重、「登录在 / 只给 / 只在」、host 不在时不可用且排在前面。
- 端到端：studio 上 dev cloud 加两台临时 TS station，在网页上分享订阅和 key、改可用的 station、分享 skill、把订阅换到另一台、关掉 host 后列表变灰，都是真的走 iroh 的站间请求。
