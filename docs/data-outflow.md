# 数据外流（设计稿）

> chat C0C5ZF5TQET/1793162070.551209（2026-10-28，左子健）。Comma for Teams（CFT）要按各团队自己的规则算 token 的 ROI，
> 需要 still.fail 用户的 token 总用量、各任务的用量和是否完成。still.fail 只提供数据，怎么算是对方的事。
> 「类似其它 app 的第三方申请访问数据的功能」。

## 结论先说

| | 做法 |
|---|---|
| 谁能申请 | 只有和 station 同一台机器上的程序：station 的本机 socket（`<data>/run/outflow.sock`），网络、mesh、cloud 都到不了 |
| 申请方是谁 | station 自己核实，不信申请里自报的名字：socket 对端进程的审计令牌 → 它的代码签名（macOS 的 Team ID 和签名标识）和可执行文件路径 |
| 怎么批准 | still.fail 直接弹出授权窗口：申请方是谁、要哪几类数据（可逐项去掉）；点允许后再出一次摘要，用 Touch ID 或系统密码二次确认 |
| 拿到什么 | 一个专用 token（`sfo_…`），不设有效期，只在这台机器的本机 socket 上、由同一个签名的程序拿来用才有效 |
| 能读什么 | 授权里勾了的几类：`usage`（token 用量和按价目的金额）、`chats`（chat 的标题、状态、创建人、时间）。不含消息内容 |
| 怎么收回 | still.fail 的「数据外流」页列出每份授权、申请方、最近读了什么；取消后立即失效 |

## 第一个用的：Comma

同一台机器上的 Comma station（Comma 桌面 app 带的那个）来申请。批准后它把 token 交给 Comma 云端（Salix）加密存着，按
「这台机器的 Comma station × still.fail station」一份；要数据时从 Salix 取 token，在本机 socket 上读，再经它和 Salix
已有的连接交给 CFT。token 离开这台机器就用不了，所以云端存着也读不到别处的数据。读的时候被拒（授权取消了），Comma 就删掉
token，等下次再申请。

## 为什么是接口，不是读库

`stillfail.db` 的表结构随 station 的版本一直在变；外面的程序直接读库，station 一升级它就读错或读不到。外流的数据只经这个接口给，
格式是一份带版本的约定（`/v1/…`）：station 改自己的库时负责让 `/v1` 照旧回答，要变格式就加 `/v2`，`/v1` 继续留着。

## 防谁、不防谁

- 防的是：别的机器、cloud、mesh 上的成员和 agent 拿到这些数据；一个程序冒充另一个程序（窗口里写的是系统核实的签名，不是申请方自报
  的名字）；token 被抄走后换个程序或换台机器来用。
- 不防的是：同一系统用户下存心要拿数据的程序。它本来就能直接读 `stillfail.db`（agent 也是同一个用户，docs/vault.md 说过同样的事）。
  这里做的是一条经过人同意、看得见、能收回、格式稳定的正式通道，让 Comma 这样的程序不用去读 station 的库。

## 申请

本机 socket 上是 HTTP（每个连接一次请求）：

- `POST /v1/request`：`{ name, purpose, scopes: ["usage", "chats"] }`。`name`、`purpose` 只当说明显示，标明是申请方自己说的。
  请求一直挂着，直到人在窗口里答了（或关了窗口、或 10 分钟没答）：
  - 允许：`200 { token, grant, scopes }`，`scopes` 是人最后留下的那几类；
  - 不允许、关了窗口、超时：`403 { error: "refused" }`；
  - 同一个申请方已有一份还在的授权：照常弹窗（可能要改范围），批准后旧的那份作废。
- 申请方核实（station 一侧）：
  - 对端进程：macOS 用 `LOCAL_PEERTOKEN` 取审计令牌（防 PID 复用），Linux 用 `SO_PEERCRED`（mesh 插件 `peerProcess(fd)`）；
  - 签名：macOS 由 still.fail Helper 按审计令牌取 `SecCode`，查签名有效，取 Team ID、签名标识、可执行文件路径。
    没签名或签名无效的程序在窗口里明确标成「未签名」；
  - 授权记在签名上（Team ID + 签名标识）；没签名的记在可执行文件路径和它的 SHA-256 上。

## 授权窗口（macOS：still.fail Helper）

station 让 Helper 弹出原生窗口（`outflow.ask`），和它申请系统权限的窗口同一套：

1. 第一步：「〈签名的名字〉想读取你在 still.fail 的数据」。写明系统核实的身份（Team ID、签名标识、路径；未签名就标红）、申请方自己
   写的名字和用途（标明「对方自述」），以及要的每一类数据，各带一个勾，可以去掉。按钮：不允许 / 允许。
2. 第二步：一句话摘要（「把这台 station 上所有 chat 的 token 用量和金额给 AFK Inc. (D9AAN3VJK8) 的 surf.comma.station，
   直到你取消」），用 Touch ID 或系统密码确认（LocalAuthentication）。

窗口只在这台机器上出现：申请来自这台机器，批准的人也得在这台机器前。

## 读数据

带 `Authorization: Bearer sfo_…`，在同一个本机 socket 上，对端必须和授权记的签名一样，否则 `401`（token 对、程序不对也是 `401`）：

- `GET /v1/usage?from&to&tz`（`usage`）：和用量页同一份明细，按天、chat、人、账号、模型相加：`calls`、`input`、`cacheRead`、
  `cacheWrite`、`output`、`cost`（按价目的美元，没价目为 null），以及各行的 `thread`；`people` 是各人的 email（知道的话）。
  一次最多 31 天。
- `GET /v1/chats?since`（`chats`）：在 `since` 之后有动静的 chat：`thread`、标题、状态（`all_done` / `need_human` /
  `waiting` / 进行中）、创建人、创建时间、最后活动时间、runtime 和模型。用 `thread` 和用量对上。
- 授权取消或换过：`401 { error: "revoked" }`。

授权覆盖这台 station 上 home workspace 的全部 chat，不按 chat、不按人分（station 不做按 chat、按人的权限：同一 workspace 里所有 chat 本来就对所有成员和 agent 可见；workspace 之间的软隔离照 docs/multi-workspace.md）。

## 收回和记录

- 管理 API（成员可用）：`GET /outflow/grants` 列出授权（申请方身份、范围、批准时间和批准人、最近一次读取）；
  `DELETE /outflow/grants/:id` 取消。core 的 `outflowGrants` 话题和 `outflow.revoke` 调用，各客户端设置里的「数据外流」页都用它。
- 每次读取记一笔（哪份授权、什么时候、读了哪类、多少行），每份授权留最近 100 笔，在「数据外流」页能看到。
- station 只存 token 的 SHA-256。

## 还没做的

本稿描述的全部。分两步：

1. still.fail：本机 socket、申请方核实（mesh 插件取对端、Helper 查签名）、Helper 的授权窗口、授权和 token 的存储、两个读取接口、
   管理 API、core 话题、客户端的「数据外流」页。
2. Comma（AFK-surf/Cue）：Comma station 的申请、token 交给 Salix 加密保存、按 token 读取并交给 CFT。

Windows 和 Linux 上的授权窗口没有设计（Helper 只有 macOS）：那里先回 `unsupported`。
