# 接力到频道

一个对话（still.fail 里的 chat，或者 Slack、飞书里的会话）聊到一半，要拉团队一起：选一个 Slack 频道或飞书/Lark 群，这个对话的 agent 就在那里接着做。原来的对话照常可用，两边是同一个会话。

## 入口

- 网页和桌面版：chat 标题栏的「接力到频道」按钮，⌘K 里的「接力到频道…」，侧栏右键菜单里的同一项。都打开同一个选择框（`web/src/Relay.tsx`）。
- 手机（网页和安卓）：对话的「…」里「接力到频道…」，打开底部的选择列表，和桌面版一样选（`web/src/mobile/Chat.tsx` RelaySheet，安卓 `screens/Relay.kt`）。

## 选择框

- 先选 bot，再选它加入的频道和群。这个 chat 所在 workspace 里开着并连上的连接（Slack、飞书、Lark：Lark 是 `domain: lark` 的飞书连接）多于一个时，最上面一排 bot 按钮（头像和名字；连接在几个 Slack workspace / 飞书租户时名字后面带上 workspace），点哪个就列哪个 bot 的频道；只有一个时不出现。
- 打开时选中这个对话自己的 bot（站点给的 `preferred`）：对话本来就在其中一个连接上的，用它；否则是绑定和对话的 agent 同一个 runtime、同一个 profile 的，再是同一个模型的，再是同一个 runtime 的第一个；都没有就是第一个。
- 列表里只有选中的 bot 已经加入的频道和群，每行前面是平台的图标；bot 没加入的不列：在那里开不了会话。
- 站点记得每个频道和群最近一次被接力过去的时间（`relayed_to` 表），接力过的排在前面（最近的在前），其余按名字排。打开时一共超过 8 个、又有接力过的，先只列最近接力过的 5 个，下面「显示全部 N 个」；一输入就在全部里搜，名字以输入开头的在前。
- 每一项说接力过去会怎样：Slack 频道是「新 thread」（最常见，选中后才写）；飞书话题群是「新话题」；飞书普通群是「接管群会话」：普通群本来就是一个会话（docs/feishu.md「会话怎么分」），接力等于在群里开新会话，群里之后的话都归这个对话，原来的会话照常留着。
- 搜索框里粘一条 Slack 消息的链接（频道里的消息，或 thread 里的回复，带 `thread_ts` 的那种），列表换成「接力到这个 Slack thread」：接到那条消息所在的 thread。用选中的 bot，它不在链接的工作区时站点按工作区找别的连接；bot 不在那个频道、那个 thread 已经有别的对话的 agent 在（和 `slack_api` 的规则一样），都拒绝。
- 选中一个后列表收起，只剩选中的那一行（「更换」回到列表），下面一行「那里由 [头像] bot 名 回复」写明在那边发言的 bot，再下面才出现可选的「开头附一句」，跟着第一条消息发出去（比如 @ 某人）；按钮写明去向（「接力到 #频道」）。

## 接力时站点做什么（`station/src/sessions/relay.ts`）

1. 在那里发第一条：谁、从哪个对话（带它在 still.fail 的链接）接力过来，附言。这一条是站点自己发的，不经过 agent。
2. 那里的会话成为这个对话的 agent 的会话（通过那个连接发言），第一条记成站点的话。
3. 原来的对话里记一条「↗ 某人把对话接力到了 #频道」，带那里的链接（Slack 的消息链接；飞书打开那个群）。
4. 告诉 agent（站点通知）：新的会话地址，请它用 `chat_post` 发一段摘要（在聊什么、定了什么、还有什么没定），让那里的人不用翻记录就能接上；接到已有 thread 时先读那里之前的消息。

## 接口

- `GET /threads/:id/relay`：`{connects: [{id, kind: slack|feishu|lark, name, team, botImage, preferred, places: [{id, name, kind: channel|topics|group, private?, used?}], error?}]}`，`used` 是最近一次接力到那里的时间（毫秒），每个连接的 places 按上面的顺序排。读不出某个连接的频道时，那一组带 `error`，其余照给。
- `POST /threads/:id/relay`：`{connect, channel, note?}` 或 `{link, connect?, note?}`，答 `{thread, to, place, link}`。
- core 的操作：`chat.relayPlaces {thread}`、`chat.relay {thread, connect?, channel?, link?, note?}`；挑选框列什么、怎么排（上面的规则）由 core 的 `chat.relayView` 算（`client/core-ts/src/relay-pick.ts`），网页、手机、桌面都用它。
- 平台的部分在 `ChatSurface` 上：`places()`、`begin(channel, message)`、`threadOf(link)`、`permalink(thread)`；Slack 和飞书各自实现，再加平台只要实现这几个。
