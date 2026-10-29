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

1. 在那里发第一条：谁、从哪个对话（带它在 still.fail 的链接）接力过来，附言。「谁」和抄送一样，用这个人的邮箱在那个平台上找到账号就 @ 这个账号，找不到才写 still.fail 上的名字（Peng Xiao，2026-10-28）。这一条是站点自己发的，不经过 agent。
2. 那里的会话成为这个对话的 agent 的会话（通过那个连接发言），第一条记成站点的话。
3. 原来的对话里记一条「↗ 某人把对话接力到了 #频道」，带那里的链接（Slack 的消息链接；飞书打开那个群）。
4. 告诉 agent（站点通知）：新的会话地址，请它用 `chat_post` 发一段摘要（在聊什么、定了什么、还有什么没定），让那里的人不用翻记录就能接上；接到已有 thread 时先读那里之前的消息。
5. agent 在那里的第一条 `chat_post`（不带文件和卡片）不另发回复，由站点接在第 1 条后面（Slack `chat.update`，飞书改卡片），频道里那条顶层消息就带着摘要，不用点开 thread 也能看到。接上去超出一条消息的长度（Slack 3500 字，飞书一张卡片）、改不成功，或站点在 agent 发之前重启过，就照常作为回复发。之后的都是回复。

## 抄送

接力过的对话（或者 agent 本来就在 Slack、飞书的会话里），之后人在 still.fail 里接着发的话，Slack、飞书那边的人看不到：still.fail 的对话和那边的会话是两个对话，agent 在哪边被问就在哪边答。要让那边的人也看到，就在输入框里勾「抄送」（`chat.cc`）。

- 能抄送到哪：对话的 agent 所在的每个 Slack、飞书会话，最近有人说话的在前，最多 20 个（`CC_THREADS_SQL`，`station/src/store/rows.ts`）。一个都没有，就没有抄送。
- 勾上的每个会话，发出去的每条消息站点照常记进 still.fail 的对话、交给 agent，同时让那个会话的 bot 在那边发一条「某人 在 still.fail 说：」加原话，带上附件（`station/src/sessions/cc.ts`）。「某人」是用这个人的邮箱在那个平台上找到的账号，@ 这个账号（Slack 用 `users.lookupByEmail`，飞书用 `contact/v3/users/batch_get_id`，要 `contact:user.id:readonly`）；找不到就写 still.fail 上的名字和账号（`Peng Xiao (pengxiao@cue.surf)`；Peng Xiao，2026-10-28）。bot 不冒充人：Slack 的 `chat:write.customize` 能换名字和头像，但不用（左子健，2026-10-25）。
- 那边那条记成站点的话，不交给 agent：它已经从 still.fail 的对话里收到了。agent 的回答还是在 still.fail 的对话里。
- 没发出去（bot 不在频道里、权限不够），站点在 still.fail 的对话里说一句为什么，消息本身照常发出。
- 默认都不勾。勾了就一直勾着（这个对话、这台设备、这次运行里：core 的 `Views.ccOn`），不用每条都勾。Slack 自己的「同时发送到 #频道」是每发一条就复位的，这里不这样，因为在这里接着聊是连续的。
- 样子（左子健，2026-10-25：没输入时只显示状态，展开了才能操作）：
  - 输入框收起（一行，没写字）：勾了的会话以「平台 logo + #频道」灰字显示在发送按钮旁边，不能点；一个没勾就什么都不显示。
  - 展开写字：勾了的会话还在发送按钮旁边原处（跟着发送按钮走，输入框收起、展开时不挪；2026-10-29 之前展开后挪到那排开头，展开收起时来回跳，左子健：「乱飞」），它前面是一个胶囊「抄送」，hover 有底色，点开浮窗菜单（右端对齐「抄送」）列出能抄送到的会话（logo + #频道，勾选），多选：不止一个时浮窗留着可以接着勾，只有一个时勾完就关。
  - 网页和桌面版：`web/src/Chat.tsx` CcChooser；mbui：`apps/mbui/src/sfpages/composer.mbt` cc_chooser；手机网页：＋ 菜单里每个会话一项「抄送到 #频道」，勾了时输入框提示「发消息，抄送 #频道」。

## 接口

- `GET /threads/:id/relay`：`{connects: [{id, kind: slack|feishu|lark, name, team, botImage, preferred, places: [{id, name, kind: channel|topics|group, private?, used?}], error?}]}`，`used` 是最近一次接力到那里的时间（毫秒），每个连接的 places 按上面的顺序排。读不出某个连接的频道时，那一组带 `error`，其余照给。
- `POST /threads/:id/relay`：`{connect, channel, note?}` 或 `{link, connect?, note?}`，答 `{thread, to, place, link}`。
- `GET /threads/:id` 里 still.fail 对话的 `cc`：`[{thread, surface, channel, threadTs, channelName}]`，可以抄送到的会话；没有就不给。`POST /threads/:id/messages` 带 `cc: [thread id…]`：发出后抄送到其中属于这个对话的那些（不等它）。
- core 的操作：`chat.relayPlaces {thread}`、`chat.relay {thread, connect?, channel?, link?, note?}`、`chat.cc {thread, to, on}`（chat 视图的 `cc: [{thread, place, via, on}]`）；挑选框列什么、怎么排（上面的规则）由 core 的 `chat.relayView` 算（`client/core-ts/src/relay-pick.ts`），网页、手机、桌面都用它。
- 平台的部分在 `ChatSurface` 上：`places()`、`begin(channel, message)`、`edit(thread, ts, message)`、`threadOf(link)`、`permalink(thread)`；Slack 和飞书各自实现，再加平台只要实现这几个。
