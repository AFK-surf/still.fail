# 数据外流（设计稿）

> chat C0C5ZF5TQET/1793162070.551209（2026-10-28，左子健）。「类似其它 app 的第三方申请访问数据的功能」：同一台机器上的
> 程序经人同意读取 still.fail 的数据。still.fail 不知道、也不管使用者是谁、拿去做什么：它只给出数据，并让人看清是哪个程序在要。

## 结论先说

| | 做法 |
|---|---|
| 谁能申请 | 只有和 station 同一台机器上的程序：station 的本机 socket（`<data>/run/outflow.sock`，指向当前进程自己的 `outflow-<pid>-<n>.sock`：station 自更新时新旧进程并存，旧进程停下时只删自己的），网络、mesh、cloud 都到不了 |
| 申请方是谁 | station 自己核实，不信申请里自报的名字：socket 对端进程 → macOS 上是它的代码签名（Team ID 和签名标识）和可执行文件路径，Linux 上是可执行文件路径和它的 SHA-256 |
| 怎么批准 | 申请出现在 still.fail app 里这台 station 的设置页「数据外流」，只有 home workspace 的 owner / admin 能答：逐项勾掉不给的数据和「整个 workspace」，点允许后再出一次摘要确认 |
| 拿到什么 | 一个专用 token（`sfo_…`），不设有效期，只在这台机器的本机 socket 上有效；读数据只认 token，程序升级后照样能读 |
| 能读什么 | 授权里勾了的几类：`usage`（token 用量和按价目的金额）、`chats`（chat 的标题、状态、创建人、时间）、`messages`（chat 里的消息原文，单独一项，写明对方能读到对话内容）；范围是这台 station，或整个 workspace 的所有 station |
| 怎么收回 | 「数据外流」页列出每份授权、申请方、谁批准的、最近读了什么；取消后立即失效 |

申请方不必在批准的人旁边：给每个客户一台默认设备（可能是没人守着的虚拟机），上面的程序申请，管理员在自己的设备上批准；授权「整个
workspace」时，这台 station 经站间通道去读同一 workspace 的其他 station，员工的电脑上什么都不用装。

## 不知道使用者

still.fail 这边没有任何为某个使用者写的东西：谁来申请都走同一个批准页、同一个接口，页上写的是系统核实的程序身份，程序自述的
名字和用途只当它自己的话显示。拿到 token 之后怎么存、怎么用、数据拿去做什么，是使用者自己的事。

## 为什么是接口，不是读库

`stillfail.db` 的表结构随 station 的版本一直在变；外面的程序直接读库，station 一升级它就读错或读不到。外流的数据只经这个接口给，
格式是一份带版本的约定（`/v1/…`）：station 改自己的库时负责让 `/v1` 照旧回答，要变格式就加 `/v2`，`/v1` 继续留着。

## 防谁、不防谁

- 防的是：别的机器、cloud、mesh 上的成员和 agent 拿到这些数据；一个程序冒充另一个程序（批准页上写的是系统核实的签名，不是申请方自报
  的名字）；token 被抄到别的机器上用（它只在这台机器的本机 socket 上有效）。
- 不防的是：同一系统用户下存心要拿数据的程序，包括抄走了 token 的程序。它本来就能直接读 `stillfail.db`（agent 也是同一个用户，docs/vault.md 说过同样的事）。
  这里做的是一条经过人同意、看得见、能收回、格式稳定的正式通道，让外面的程序不用去读 station 的库。

## 申请

本机 socket 上是 HTTP（每个连接一次请求）：

- `POST /v1/request`：`{ name, purpose, scopes: ["usage", "chats"], workspace: true, key }`。`name`、`purpose` 只当说明显示，标明是申请方
  自己说的；`workspace: true` 申请整个 workspace（不写就是这台 station）；`key` 是申请方自己的键（比如它的 station id）：同一个程序
  在不同的键下各有各的申请和授权，同一个键下再申请就替换那一份。一次申请就是一个请求，挂到管理员答了为止：
  - 允许：`200 { token, grant, scopes, reach }`，`scopes` 是管理员最后留下的那几类，`reach` 是 `station` 或 `workspace`；
  - 不允许：`403 { error: "refused" }`，这份申请随之作废，再申请就是新的一份；
  - 申请方等着的时候断开了（比如它重启）：申请留着，它再发同样的申请就还是这一份，管理员在这期间答了的话立刻拿到结果。
  - 管理员一允许，授权就立即生成，在「数据外流」里列出、可以取消，标着「已允许，等程序来取」；token 在程序来取时才生成并交给它。
    程序来取之前就被取消的，它再来时得到 `403`。
  - 一份申请，没人答过一周，或答了允许、程序一周没来取，就作废。
  - 同一个申请方在同一个键下已有一份授权：照常申请，批准后旧的那份作废。
  - 申请的东西这个程序已经有了（它的某一份授权，不论在哪个键下，已经给了这几类、范围也够）：不再问管理员，立刻 `200`，还是那份授权，
    另给一个 token；它以前拿到的 token 照样能用（每份授权最多再记 8 个）。只有要的比已有的多，才是一份等管理员答的新申请。
- 申请方核实（station 一侧）：
  - 对端进程：macOS 用 `LOCAL_PEERTOKEN` 取审计令牌（防 PID 复用），Linux 用 `SO_PEERCRED`（mesh 插件 `peerProcess(fd)`）；
  - macOS：still.fail Helper 按审计令牌取 `SecCode`，查签名有效，取 Team ID、签名标识、可执行文件路径；没签名或签名无效的程序
    在页上标成「未签名的程序」；
  - Linux：`/proc/<pid>/exe` 的路径和这个文件的 SHA-256（Linux 没有代码签名可查），页上同样是「未签名的程序」；
  - 授权记在签名上（Team ID + 签名标识）；没签名的记在可执行文件路径和它的 SHA-256 上。
  - 说不出对端是谁（Windows，或 macOS 上没有 Helper）：`403`。

## 批准（still.fail app）

申请经 `outflow-grants` 事件和 `GET /outflow/grants` 的 `requests` 到达 app，显示在这台 station 设置页的「数据外流」里：

1. 第一步：程序名、系统核实的签名（未签名就标出来）、申请方自述的名字和用途（标明是它自己说的）、什么时候申请的；要的每一类数据
   各一个勾，带说明这类会给出什么；申请了整个 workspace 的再有一个「这个 workspace 的所有 station」的勾。按钮：不允许 / 允许。
2. 第二步：一句话摘要（「把这个 workspace 所有 station 上 chat 的「token 用量和金额」给 Comma（签名：…），直到在这里取消授权」），
   点允许才给。

只有 home workspace 的 owner / admin 能答（`POST /outflow/requests/:id`，`{ allow, scopes, workspace }`，别人 `403`）；其他成员看得到
这份申请，标着「等这个 workspace 的管理员批准」。管理员给的只会比申请的少，不会多。

## 读数据

带 `Authorization: Bearer sfo_…`，在同一个本机 socket 上；只认 token，不再核对读的是哪个程序（程序身份只在申请时核实，写在批准页上）。没有 token 或 token 不对：`401`。

- `GET /v1/stations`：能读的 station，`{ stations: [{ id, name, here }] }`，这台在最前（`here: true`）。授权只到这台 station 的，就只有
  这一台。
- 下面三个都可以带 `station=<id>`：读 workspace 里另一台 station 的（要授权到整个 workspace，否则 `403`；不在 workspace 里 `404`；
  那台连不上 `502`；那台 60 秒内没回答 `504`，请求不会一直挂着；workspace 的 station 名单此刻不可知 `503`）。不带就是这台。另一台的数据由这台 station 经站间通道
  （`outflow.read`，docs/station-peers.md）向它要，回答的格式和这台的一样；`thread` 是那台 station 自己的编号，和 `station` 一起才
  唯一。

- `GET /v1/usage?from&to&tz`（`usage`）：和用量页同一份明细，按天、chat、人、账号、模型相加：`calls`、`input`、`cacheRead`、
  `cacheWrite`、`output`、`cost`（按价目的美元，没价目为 null），以及各行的 `thread`；`people` 是各人的 email（知道的话）。
  一次最多 31 天。`person` 是那一轮由谁的消息开始的：多人在同一个 chat 里说话，这个 chat 就有每人一行，chat 的总量是它所有行相加。
- `GET /v1/chats?since&limit&before`（`chats`）：在 `since` 之后有动静的 chat，最近活动的在前：`thread`、标题、状态（`all_done` /
  `need_human` / `waiting` / 进行中）、创建人、创建时间、最后活动时间、runtime 和模型。用 `thread` 和用量对上。不带 `limit` 一次给全部；
  带 `limit`（最多 1000）就分页：`more` 说后面还有，下一页带上这页的 `next` 作 `before`。只为 `since` 之后有动静的 chat 汇总，
  `since` 越近越省。
- `GET /v1/messages?thread&after&limit`（`messages`）：chat 用 `thread` 指定，也可以用 `session`（用量行里的会话 key）或 `channel` 加
  `ts`（Slack 频道和线程首条消息的 ts）指定；一个 chat 在第 `after` 条之后的消息，按顺序，一次最多 `limit` 条（默认 100，
  最多 500）：每条的 `n`、`kind`（`message`，或 `edit`：对第 `target` 条的改写）、`authorKind`（`person` / `agent`）、`author`、
  `text`、`at`；`last` 是这个 chat 最新的一条，`more` 说后面还有。`thread` 不是 home workspace 的 chat：`404`。
  消息不加工：chat 是干什么的（标签、摘要），由使用者自己从消息里算，still.fail 不为此多花 token。
- 授权在这台 station 上被撤销：`401 { error: "revoked", grant, revokedAt }`（撤销的授权记得最近 200 个 token）。
- token 不是这台 station 发的（别的 station 的、早已换掉的）或没带：`401 { error: "unknown token", station: { id, name } }`，
  说的是回答的这台，程序据此知道自己问错了地方，该去发它的那台读，或在这台重新申请。

授权覆盖这台 station（或 workspace 的每台 station）上这个 workspace 的全部 chat，不按 chat、不按人分（station 不做按 chat、按人的权限：同一 workspace 里所有 chat 本来就对所有成员和 agent 可见；workspace 之间的软隔离照 docs/multi-workspace.md）。

## 怎么传

不是文件：每个读取是本机 socket 上的一次 HTTP 请求，回答是一个完整的 JSON。读另一台 station 时，这台经站间通道向它要，收齐它的
回答（最多 64 MiB，再多就是 `502`）、解析好了才回给程序，程序拿不到半份数据：途中断了是 `502`，那台不回答是 `504`。大的东西分页拿：
`messages` 每页最多 500 条，`chats` 带 `limit` 分页，`usage` 每次最多 31 天。程序自己断开了就再读一次，消息从 `after` 接着读。

## 收回和记录

- 管理 API（成员可用）：`GET /outflow/grants` 列出授权（申请方身份、范围、批准时间和批准人、最近一次读取）和等着答的申请；
  `DELETE /outflow/grants/:id` 取消；`POST /outflow/requests/:id` 答申请（管理员）。core 的 `outflowGrants` 话题和
  `outflow.revoke`、`outflow.answer` 调用，各客户端设置里的「数据外流」页都用它。
- 每次读取记一笔（哪份授权、什么时候、读了哪类、多少行、读的哪台 station），每份授权留最近 100 笔，在「数据外流」页能看到。
- station 只存 token 的 SHA-256。

## 做了什么、还没做的

做了（still.fail）：本机 socket、申请方核实（mesh 插件 `peerProcess` 取对端进程；macOS 由 Helper 查签名，macOS 自己的程序没有
Team ID，按 Apple 的锚点记作 `Apple`；Linux 按可执行文件）、申请和授权的存储（`<data>/outflow.json`）、app 里 station 设置页「数据外流」
一节（申请：逐项勾选、两步确认，只有管理员能答；授权：列出、取消前先问）、整个 workspace 的范围（`/v1/stations`、`station=`，经
`outflow.read` 读其他 station）、管理 API、core 的 `outflowGrants` 话题和 `outflow.revoke`、`outflow.answer`。

还没做：

- 网页版的「数据外流」页（申请和授权先在 app 里看、答、取消）。
- 有新申请时推送给管理员：现在要管理员自己打开那台 station 的设置页才看得到。
- Windows 上核实申请方（那里申请回 `403`）。
