# X connect

X（Twitter）的一个账号作为 connect，和 Slack、飞书的 connect 并列：名单上的人发帖 @ 这个账号，就唤醒 agent，agent 用 chat_post 回到那条帖子下面。代码在 `station/src/x/`，是 station 的一个「部分」（`XLive`，见 docs/station-modules.md），和 `SlackLive`、`FeishuLive` 一样经 `connects/part.ts` 挂上。

## 接法

- 鉴权：OAuth 1.0a 用户上下文。connect 存开发者 app 的 Consumer Key、Consumer Secret，和 bot 账号的 Access Token、Access Token Secret。这四个都不过期，每次调用用 HMAC-SHA1 签名（`web.ts` 手写，不引 SDK）。在开发者后台里给 bot 账号自己的 app 生成 Access Token 时，权限要选 Read and write。
- 收：轮询 bot 的 mentions 时间线 `GET /2/users/:id/mentions`，默认每 20 秒一次，带上 `since_id`。X 的 Activity API 也能推 `post.mention.create`，但它的文档没写心跳，也没写断开后补不补发，webhook 还要公网地址，所以没用它。读到的最新一条 mention 的 id 记在 `<data>/x-threads.json`：station 不在的时候别人发的 mention，回来后照样能读到，同一条也不会读两次。connect 第一次开始读之前的 mention 不处理（第一次请求带 `start_time`）。一次轮询最多翻 5 页，每页 100 条，剩下的留给下一次。
- 发：`POST /2/tweets`，带 `reply.in_reply_to_tweet_id`；图片先用 `POST /2/media/upload` 上传（`media_category=tweet_image`）。
- X 的 API 文档已经把字段改叫 post（`post.fields`、`referenced_posts`、`note_post`、`includes.posts`），旧的叫法是 tweet。两种都认：带新名字的请求被 400 拒掉，就换旧名字重问，之后一直用旧名字。
- 撞到频率限制（429）时，等到 `x-rate-limit-reset` 再试，最多等一分钟；等更久就算这次轮询失败，按 connect 的退避重连（connects/surface.ts）。
- 测试用 `$STILLFAIL_X_API` 把请求指到假的 X。

## 白名单

- connect 的 `x.allow`：`[{id, username}]`。在页面上填 @handle（也可以填主页链接），保存时用 `GET /2/users/by/username/:username` 换成 user id，按 id 比对：handle 能改，也能被别人注册走。查不到的 handle 会报出来，整次保存不生效。
- 只处理名单上的人的 mention。名单外的人的帖子直接跳过：不建会话，不回复，记一行日志。bot 自己的帖子也跳过。名单是空的，就谁也唤醒不了。
- 每次轮询都重读名单，改名单不用重连。

## 会话怎么分

- 线程地址 `CHANNEL/THREAD_TS` 两段都是这个 X conversation 的 `conversation_id`，也就是最上面那条帖子的 id：同一条帖子下面的回复链算一个会话。
- 消息的 ts 是帖子 id。如果 mention 本身是一条回复，就沿 `replied_to` 往上最多读 10 条，作为 station 进来之前的内容（hub 的 `history`）。
- agent 的 chat_post 回复这个会话里最近一条 mention。内容超过一条帖子的长度就拆开，后一条回复前一条，连成一串。
- mentions 时间线里有什么就读什么。回复 bot 的帖子，X 会在正文开头加上 @bot，所以应该也在里面（还没用真账号确认过）。
- surface 是 `x:<connect id>`；人：`slack:<connect>:<user id>`，名字写成「显示名 (@handle)」，存在 `<data>/x-names.json`；creator 的 `via` 是 `"x"`。

## 收到的内容

- 正文：长帖读 `note_post` 里的全文，否则读 `text`；把 X 转义过的 `&lt; &gt; &amp;` 还原。开头连着的一串 @handle（X 加在回复前面的，和 @ bot 的那个）去掉，只剩这一串的帖子原样保留。
- 引用的帖子：附在正文后面，写成「[Quoting @handle]」加上被引用的内容（引用块）。
- 图片：附件，从 X 的图片地址下载到会话的 uploads。

## 发出去的样子

- 纯文本：去掉 Markdown 记号；链接写成「文字 (地址)」；列表项写成「• 」开头的行；表格每行写成用「 · 」分隔的一行。
- 长度按 twitter-text 的权重计：大部分拉丁字母、标点和空格算 1，其他字符（包括中日韩文字）算 2，一个链接固定算 23。每条最多 280（`x.maxLength`，开了 X Premium 的账号最多可设到 25000）。超长时依次在段落、换行、空格处断开。
- 链接：X 的按量价目里，带 URL 的帖子 $0.20 一条，不带的 $0.010。所以默认把链接里的点写成 `[.]`，X 就不会把它识别成链接。`x.links: true` 时原样保留链接。
- 新会话开始时不发「查看会话」的链接，工作中也不发状态：发出去的帖子收不回，每条还要花钱。
- 没有卡片：带选项卡或文字卡的 chat_post 会被拒，agent 要把选项写在正文里。
- 文件只能发图片（png、jpg、gif、webp，每张最多 5 MB）。每条帖子最多带 4 张，第一张帖子先带上，多出来的另发几条。只要有一个文件不是图片，整条就不发并返回错误。

## 费用（X 的按量价目，2026-04 起）

| 动作 | 价格 |
|---|---|
| 读一条 mention（含被引用、被回复的帖子） | $0.005 |
| 回复一条 @ 了我们的帖子 | $0.010 |
| 发一条帖子 | $0.015 |
| 帖子里带链接 | $0.20 |
| 读一个用户 | $0.010 |

同一个资源在一个 UTC 自然日里只计一次费。空的轮询不读到任何资源，不花钱。

## 配置

config.json 的 connect：

```json
{
  "id": "commabot", "enabled": true, "kind": "x", "mode": "multi-session",
  "x": {
    "consumerKey": "…", "consumerSecret": "…", "accessToken": "…", "accessSecret": "…",
    "allow": [{ "id": "200", "username": "ada" }],
    "links": false, "maxLength": 280,
    "botName": "Comma Bot", "botUsername": "commabot", "botUserId": "100", "botImage": "https://…"
  },
  "bind": { "runtime": "claude" }
}
```

`botName` 及后面几项是连上时从 `GET /2/users/me` 记下的，没连上时页面也能显示。

## 管理 API

- `POST /x/verify {consumerKey, consumerSecret, accessToken, accessSecret}` → `{identity: {botName, botImage, botUserId, username} | null, errors: string[]}`。
- `POST /x/connects {x: {四个 key, allow: ["@ada", …] | "ada, bob", links?}, bind, mode?, owner?}` → `{id, overview}`：先验证 key，再逐个查名单里的 handle；id 用 bot 的 handle。
- `PUT /x/connects/:id/allow {allow}`：整份替换名单（逐个查 handle）。
- `PUT /x/connects/:id/keys {四个 key，空的不动}`：先验证，必须还是同一个账号；换成别的账号要另建 connect。
- 其他（启用、模式、bind、`x.links`、`x.maxLength`）走 `PUT /connects/:id`，删除走 `DELETE /connects/:id`，和其他 connect 一样。
- overview：有 `xConnects: true` 的 station 才支持建 X connect。`connects[]` 里 `kind: "x"`，`name` 是账号的显示名，`team` 是 `@handle`，`x: {consumerKey…（都遮住）, username, allow, links, maxLength}`。

## agent 看到的

- 消息头 `via="x"`。说明里写了：内容是纯文本，越短越好，不要带链接，每条帖子都要花钱。
- 工具 `x_api`：以 bot 账号身份调 X API v2，只能 GET（读帖子、查用户、搜索）。发帖走 chat_post。

## 客户端

- core 的新建 connect 向导（`client/core-ts/src/forms.ts`）：station 的 overview 里有 `xConnects: true` 才出现 X 这个平台。步骤是「平台 → 模型和会话方式（xBind）→ 四个 key 和名单（xApp）」：先验证 key，名单不能为空，然后建 connect（`x.createConnect`）。
- connect 页面（web 两种宽度、mbui）：账号、名单（`x.putAllow` 整份替换）、key（`x.putKeys`，留空的不改）、回复里是否保留链接（`PUT /connects/:id` 的 `x.links`）。
- 对话：X 来的会话标 X 的标志，地点写「X 帖子」，信息里有「在 X 中打开」（`xUrl`，打开会话最上面那条帖子）。
- Kotlin 的 apps/android 已冻结，没有改。

## 测试

`station/test/x-fake.ts` 是假的 X，会按同样的四个 key 校验每次请求的签名；`x.test.ts` 测签名（对上 X 文档里的示例）、纯文本转换和拆条、轮询（白名单、重连后补读、翻页、旧字段名）、回复成串和附图，hub 里一个 X 会话的完整流程，以及管理路由。
