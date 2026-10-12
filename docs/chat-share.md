# 把 chat 分享给其他 workspace

> chat EMBER/1791811670.593000（2026-10-12 用户定：「类似做分享的思路」「可以不用经过 cloud」）。

一个 workspace 里的 chat，可以分享给同一个人所在的另一个 workspace。另一个 workspace 的 agent 用 `chat_read` / `session_history` 读它、用 `chat_list` 找到它；打开了「可以发消息」的，还能用 `session_send` 往里说话。人这一侧不变：workspace 之间的数据在客户端里仍然完全隔离，要在页面上看 B 的 chat 就加入 B。

做法照 station 之间的分享（[station-share.md](station-share.md)）：东西放在哪台 station 上，就由那台记谁能用、告诉过谁；用的一方记从哪借的。**cloud 不参与**，它只照旧给每个 workspace 自己的 station 名单。

下面 B 是 chat 所在的 workspace，X 是 chat 所在的那台 station（host），A 是被分享到的 workspace。

## 开关

- chat 的「…」里有「分享给其他 workspace」：勾选给哪几个 workspace（只列自己也在的），再加一个「可以发消息」，默认关（只能看）。全部取消就是停止分享。
- 能改的人：chat 的发起人，或 B 的 owner/admin。
- 分享的单位是一个 chat：它的消息、附件，和它的 agent 的执行历史。

## 谁记什么

**X（host）**，stillfail.db 的 `chat_shares` 表（按 chat 的 session key）：分享给哪些 workspace、能不能发消息、谁、什么时候改的；`<data>/xshare/state.json`：

- `guests[A]`：A 有哪几台 station（`{id, name}`）。第一次由打开分享的人的客户端交给 X（他是 A 的成员，客户端本来就有 A 的 station 名单）；之后由 A 自己的 station 更新（`xshare.roster`）。
- `told[chat][A 的 station]`：告诉到第几版。

**A 的 station**，`<data>/xshare/state.json`：

- `borrowed[chat]`：从哪台 station（X）、哪个 workspace（B，名字）、标题、链接、能不能发消息、第几版。
- `hosts[X]`：信任 X 是 B 的 station（由 A 的成员在打开分享时告诉 A 的一台 station，A 的其他 station 需要时问它，见下）。
- `replies[session]`：这个 session 发过消息的外部 station。只有它们能用 `session.message` 回到这个 session。
- `roster`：上次告诉各个 host 的 A 名单是哪一版。

## 站间方法

都走 `stillfail/station/1`。请求包里的 `workspace` 是**接收方**的 workspace。同 workspace 的请求照旧；不在本 workspace 名单里的对端，按下表放行：

| 方法 | 谁问谁 | 接收方怎么判 |
|---|---|---|
| `xshare.changed {chat, version, title, link, write, workspace, workspaceName}` / `{chat, gone: true}` | X → A | X 在 `hosts` 里；不在就问 A 的其他 station（`xshare.trusts`），有一台信就记下 |
| `xshare.trusts {station}` | A → A | 同 workspace 才能问；答 `{trusted, workspace, name}` |
| `xshare.list {workspace: A}` | A → X | 对端在 `guests[A]` 里；答分享给 A 的所有 chat 和版本（A 每次启动问一次） |
| `xshare.roster {workspace: A, stations}` | A → X | 对端在 `guests[A]` 里；整份替换 A 的名单，新加的 station 随后被告知 |
| `session.read` / `session.file` | A → X | 对端在某个 `guests[A]` 里，且读的 chat（或它的 agent）分享给了 A |
| `session.put` / `session.message` | A → X | 同上，且这个 chat 打开了「可以发消息」 |
| `session.message` | X → A | 发往的 session 在 `replies` 里记着 X（A 先给它发过消息） |

`session.create`、`session.notice` 和任务（`task.*`、`file.*`）不对外部 station 开放：跨 workspace 不能开 chat。按 chat 分享，还没有 chat 可分享，开出来的 chat 的决策人也不一定在 B 里。

## 流程

**打开分享**（客户端 core 的 `chat.xshare`）：

1. 调 X 的 `PUT /sessions/:key/xshare {to: [{workspace, name, stations: [{id, name}]}], write}`。X 写好 `chat_shares` 和 `guests`，版本加一，然后去告诉每个 A station（`xshare.changed`）。没告诉到的，按 1 分钟起、翻倍、最多 30 分钟的间隔再试（和 share 一样）。
2. 对每个新加的 A，调 A 的一台在线 station 的 `PUT /xshare/hosts {workspace: B, name, station: X, stationName}`，让它信任 X。A 的其他 station 收到 X 的通知时，问 A 的同伴（`xshare.trusts`）就知道了。
3. 两步顺序无所谓：A 还不信任 X 时就拒绝通知，X 稍后再试。

**A 的 station 名单变了**：A 的每台 station 盯着自己 workspace 的名单（cloud 的 `peers`），名单是最新的、又和上次告诉 X 的不同，就把整份名单发给自己借用的每个 host（`xshare.roster`）。X 用新名单替换旧的：新来的 station 被告知分享，移走的 station 从此被拒绝。A 的 station 都连不上 X 时，被移走的 station 在 X 上会多留一阵，直到 A 的某台通知到 X 为止。

**停止分享 / 不再给 A**：X 告诉 A 的各台 `gone`，A 删掉记录。chat 被删除时同样处理。

**A 的 agent 读写**：chat 链接里有 workspace 和 station（`…/o/<B>/<X>/<key>`）。workspace 不是自己的，就按 `borrowed` 或 `hosts` 找到 X，带上 `workspace: B` 去问。附件照常拉到 `uploads/<X>/`。发出的消息在 B 的 chat 里以「来自 A 的 chat 链接」开头；A 记下 `replies`，B 的 agent 用 `session_send` 回复时就能回到 A。

**chat_list**：在本 station 的 chat 后面列出「分享给本 workspace 的」chat（标明来自哪个 workspace、能不能发消息），链接直接可用于 `chat_read` / `session_send`。

## 界面

- PC：chat 页右上「…」菜单多一项「分享给其他 workspace」，后面写现状（如「A、C · 只读」）；点了弹窗，列出自己所在的其他 workspace 勾选，下面一个「可以发消息」开关。
- 手机 web 和安卓：chat 的「…」页多一行，同样内容，点开底部面板。
- 只有自己在不止一个 workspace 时才出现。不是发起人也不是 admin 时只显示现状、不能改。
- thread 视图多一个可选字段 `xshare: {to: [{workspace, name}], write, by, at} | null`。旧 station 不给，界面当没有分享。

## 兼容和部署

- 新表 `chat_shares` 用 `CREATE TABLE IF NOT EXISTS`；`xshare/` 下是新文件，旧 station 不读。
- 旧 station 收到 `xshare.*` 会当成任务拒绝。X 是旧版时客户端的 PUT 返回 404，界面说「这台 station 还没更新」。A 是旧版时，X 的通知被拒、按退避再试，A 更新后就收到了。
- cloud 不用改、不用先部署。station 先上，客户端后上。
- agent 能感知的变化（`chat_list` 多了分享来的 chat、可以读写别的 workspace 的链接）写进 `agents/migrations.ts`。
