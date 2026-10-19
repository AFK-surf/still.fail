# 飞书 connect

飞书（和国际版 Lark）的机器人作为 connect，和 Slack connect 并列：飞书群和私聊里的话交给 agent，agent 用 chat_post 回到原处。代码在 `station/src/feishu/`，是 station 的一个「部分」（`FeishuLive`，见 docs/station-modules.md），和 `SlackLive` 一样经 `Agents` 的 `surfaces`、`along` 挂上。

## 接法

- 收：飞书「长连接」（WebSocket，不要公网地址）。`POST <open>/callback/ws/endpoint {AppID, AppSecret}` 拿到连接地址，帧是 protobuf 的 `pbbp2.Frame`（`frame.ts` 手写编解码，不引飞书 SDK）。每 `PingInterval` 秒发一次 ping 帧；和 Slack 一样，连接 20 秒没任何动静就当它断了重连（他们的 bot 因为 SDK 的长连接静默断开加过看门狗）。事件处理完才回 ack 帧（`{code: 200}`），没处理成的不回，飞书会重发，库按 message_id 去重。
- 发：OpenAPI（`<open>/open-apis/…`），`tenant_access_token` 用 app_id/secret 换，过期前换新。`<open>` 是 `https://open.feishu.cn`，Lark 是 `https://open.larksuite.com`（connect 的 `feishu.domain`）。测试用 `$STILLFAIL_FEISHU_API` 指到假飞书。
- 订阅的事件：`im.message.receive_v1`；回调：`card.action.trigger`（卡片按钮，同样走长连接，按事件来）。

## 会话怎么分（群即会话）

- 线程地址 `CHANNEL/THREAD_TS`：CHANNEL 是飞书的 `chat_id`（`oc_…`）。
- 群里和私聊里不在话题里的话，算一个长期会话：THREAD_TS 是这段会话开头那条消息的 id（`om_…`），station 记在 `<data>/feishu-threads.json`。第一次 @ 机器人（私聊不用 @）开会话，之后这个群里的每条消息都交给它，不用再 @：hub 现有的「已有会话的线程，每条都投递」。
- 「新会话」：@机器人 说「新会话」（或 `/new`），这条消息成为新会话的开头，THREAD_TS 换成它的 id，旧会话留在 still.fail 里照常归档。
- 话题群（群设置里的「话题」模式）的每个话题：THREAD_TS 是 `thread_id`（`omt_…`），和 Slack 的 thread 一样，要 @ 才开会话，中途进来的读一遍之前的消息，回复发到话题里。普通群里「回复到话题」的消息仍算这个群的会话（他原来的 bot 就是按群分的），回复发在群里。
- 消息的 ts 是飞书的 `message_id`；卡片按钮的回答不是消息，ts 是 `card-<event_id>`。
- surface 是 `feishu:<connect id>`：两个机器人在同一个群里各是各的线程（飞书的 open_id 按应用分，人也对不上）。
- 人：`slack:<connect>:<open_id>`（这串的前缀本来就只是「connect 的人」，沿用，不改客户端的解析）；名字和邮箱从通讯录接口取，取不到时用群成员列表里的名字，记在 `<data>/feishu-names.json`；creator 的 `via` 是 `"feishu"`。

## 收到的内容

- text：`@_user_1` 这类占位换成 `@名字`。
- post（富文本）：转成 Markdown（加粗、链接、代码块、@），图片和视频当附件。
- image、file、audio、media：附件，`GET /im/v1/messages/:id/resources/:key` 下载到会话的 uploads（50 MB 以内）。
- 其他类型（表情包、卡片、合并转发、分享群名片……）：一个 `[类型]` 占位。
- 飞书没有「消息被编辑」的事件，改过的消息 station 不知道。

## 发出去的样子

- 文字一律发成卡片（JSON 2.0 的 markdown 组件）：飞书卡片的 Markdown 和 still.fail 的写法基本一样（标题、列表、表格、代码块），agent 照 still.fail chat 的写法写。太长的分成几张（每张 6000 字以内）。@人写 `<at id=ou_xxx></at>`。
- 文件跟在文字后面各发一条：图片 `im/v1/images` 上传后发图片消息，其他 `im/v1/files` 上传后发文件消息。
- 话题群的话题里就回到话题（`reply_in_thread`），否则直接发到群里。
- 选项卡片（`card.type` 为 options）：按钮，推荐的那个是主按钮，点了就当那个人说了这个选项（addressed），卡片换成「已选：…」不再能点；文字卡片（text）：一个输入框加提交按钮。login 卡片不在飞书里出，agent 只发链接。
- 「工作中」：一轮开始时发一张状态卡片（CardKit 卡片实体，不受消息编辑次数的限制），跟着 agent 当前在做的事更新（读文件、跑命令……，最多一秒一次），结束时变成一行「完成 · 用时」和执行历史的链接。
- 新会话开始时不另发「查看会话」链接：状态卡片上有。

## 配置

config.json 的 connect：

```json
{
  "id": "codex-bot", "enabled": true, "kind": "feishu", "mode": "multi-session", "requireMention": true,
  "feishu": {
    "appId": "cli_xxx", "appSecret": "…", "domain": "feishu",
    "botName": "Codex 机器人", "botImage": "https://…", "botOpenId": "ou_…",
    "tenant": { "key": "…", "name": "某公司" }
  },
  "bind": { "runtime": "codex", "model": "…" }
}
```

`domain`：`feishu` 或 `lark`。`botName` 之后的是连上时从 `GET /open-apis/bot/v3/info` 记下的，不连也能显示。single-session 模式和 Slack 一样可用。

## 建机器人（扫码一键创建）

飞书开放平台的「一键创建应用」是 OAuth 设备码流程（RFC 8628），和飞书 Python SDK 的 `lark.register_app` 一样：

1. `POST https://accounts.feishu.cn/oauth/v1/app/registration`（表单）`action=init`，确认 `supported_auth_methods` 里有 `client_secret`。
2. `action=begin&archetype=PersonalAgent&auth_method=client_secret&request_user_info=open_id`，拿到 `device_code`、`verification_uri_complete`、`interval`、`expires_in`。给人看的链接是 `verification_uri_complete` 加上 `name`（应用名）和 `addons`（要的权限、事件、回调：JSON，gzip 后 base64url）。
3. 每 `interval` 秒 `action=poll&device_code=…`：`authorization_pending` 继续等，`slow_down` 间隔加 5 秒，`access_denied`、`expired_token` 结束；回来 `client_id`、`client_secret` 就是建好了。`user_info.tenant_brand` 是 `lark` 时改问 `accounts.larksuite.com`，connect 的 domain 记成 `lark`。

要的东西（`addons`）：

- 权限（tenant）：`im:message`、`im:message:send_as_bot`、`im:message.group_msg`（群里不 @ 的消息也收到，群即会话靠它）、`im:message.p2p_msg:readonly`、`im:message.group_at_msg:readonly`、`im:resource`、`im:chat:readonly`、`im:chat.members:read`、`contact:user.base:readonly`、`contact:user.email:readonly`、`cardkit:card:write`。
- 事件（tenant）：`im.message.receive_v1`。回调：`card.action.trigger`。

已有应用的，也可以填 App ID 和 App Secret 建 connect（station 先换一次 token、读一次机器人信息验证）。手建的应用要在开放平台自己开：机器人能力、长连接、上面的事件和回调、权限，然后发版。

## 管理 API

- `POST /feishu/registrations {domain?, name?}` → `{id, url, expiresAt, overview}`：开始扫码创建，station 自己轮询。进展在 overview 的 `feishuRegistrations`（只有发起的人看得到），`overviewChanged` 推给页面：`{id, url, expiresAt, state: "waiting" | "done" | "denied" | "expired" | "failed", error, appId, domain}`。`DELETE /feishu/registrations/:id` 取消。
- `POST /feishu/verify {appId, appSecret, domain?}` → `{identity: {botName, botImage, botOpenId, tenant: {key, name}} | null, errors: string[]}`。
- `POST /feishu/connects {feishu: {appId, appSecret, domain?} | {registration}, bind, mode?, owner?}` → `{id, overview}`：id 由机器人名字来。
- 改：`PUT /connects/:id`（启用、模式、bind 和 Slack 一样；`feishu: {appSecret}` 换密钥，空的不动）；换密钥并先验证：`PUT /feishu/connects/:id/secret {appSecret}`；删：`DELETE /connects/:id`。
- overview 的 `connects[]`：`kind: "feishu"`，`name` 是机器人名字，`team` 是企业名，`feishu: {appId, appSecret（遮住）, domain}`，`connection` 和 Slack 的一样（`workspace.teamId` 是 tenant key，`botUserId` 是机器人的 open_id）。

## agent 看到的

- 消息头 `via="feishu"`；格式表里飞书一栏和 still.fail chat 一样用 Markdown。
- 工具 `feishu_api`：以机器人身份调飞书 OpenAPI（`method` 写 `GET /open-apis/…`），读写文档、表格、日历都靠它；发消息（`/im/v1/messages`）不走它，用 chat_post。管应用和凭据的接口（`/open-apis/auth/`、`/open-apis/application/`）拒绝。

## 测试

`station/test/feishu-fake.ts` 是假飞书（OpenAPI 和长连接，protobuf 帧照真的编），`feishu.test.ts` 测解析和卡片，`feishu-e2e.test.ts` 起 station 的 hub 走一遍：@ 开会话、不 @ 续上、新会话、话题、附件、按钮回答。
