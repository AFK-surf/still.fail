# 客户端插件

> chat EMBER/1792344944.386000（2026-10-19）。用户想在抖音里「分享 → 直接下载」，而且要通用：自己的 agent 写一个专用分享，
> 写完马上能用，不改别人的功能。

## 是什么

插件是**一个人自己的一份声明**：在客户端长出什么入口，入口被用到时把东西交给谁。它是数据不是代码，客户端照着画，干活的是
station 上的 agent（或以后的 station 模块）。所以 agent 写好插件，这个人的各台设备同步到就能用，不用发版；也只有他自己看得到，
别人的 app 一点不变。

为什么不带代码：客户端有安卓、web、桌面、浏览器扩展四端，跑别人写的代码要每端各做沙箱和权限；要真代码的部分放进 station
模块（docs/station-modules.md），那里已有安装、更新、回退。

```json
{
  "id": "douyin",
  "name": "抖音下载",
  "entries": [{ "kind": "share", "match": "v\\.douyin\\.com|douyin\\.com/(video|note)/" }],
  "action": { "kind": "chat", "session": "<station 上的 session key>", "send": "auto" }
}
```

- `id`：`^[a-z][a-z0-9-]{0,31}$`，同一个人在同一台 station 上不重复（再存一次就是改）。
- `name`：给人看的名字，最长 40 个字符。
- `entries`：入口。第一期只有 `share`（别的 app 分享过来的东西）：`match` 是 JS 正则（不区分大小写，最长 500 字符），对分享的
  整段文字测；不写就什么都接。
- `action`：入口被用到时做什么。第一期只有 `chat`：把分享的整段文字作为这个人的一条消息发进那个对话（`send: "auto"`，默认），
  或像普通分享那样只放进它的输入框（`send: "composer"`）。对话就在存插件的那台 station 上。

以后：动作 `module`（直接调 station 模块 `/m/<id>/…`，不经 agent、不花 token），入口 `shortcut`（桌面快捷方式）、`composer`
（输入框的按钮）、通知上的操作。

## station：存和给（`station/src/plugins/`）

- 表 `plugins (ws, owner, id, body, at)`，主键 `(ws, owner, id)`；`owner` 是邮箱（小写），`ws` 是 workspace（session 没有自己的
  ws 时取 station 的 home）。
- admin API（都只看请求者自己的、在请求者的 workspace 里）：`GET /plugins` → `{plugins: [Plugin & {at}]}`；
  `DELETE /plugins/<id>`（只读成员也能删自己的）。
- 事件：`plugin`（存了或改了，整份）、`plugin-gone`（`{id}`），只告诉它的主人。
- agent 的工具（MCP）：`plugin_list`、`plugin_save`、`plugin_delete`。插件的主人是这个对话的发起人（`starterOf`：thread
  的创建者，否则 session 的），不是 agent 自己能挑的；`action.session` 不写就是调用工具的这个对话，写了必须是这台 station 上、
  同一个人发起的对话。存之前检查形状和正则能编译。

## core：合起来、匹配、执行（`client/core-ts/src/views/plugins.ts`）

- 每台 station 连上时读 `GET /plugins`（`stations.also`），听 `plugin` / `plugin-gone`；记在 workspace 的 `plugins` 记录里，
  按 `<station>/<id>`。读到 404（还没有插件的旧 station）就当没有。
- topic `plugins {workspace, source?}` → `{items: [{station, id, name, entries, action, chat}]}`：`chat` 是动作那个对话现在的
  标题（没有就 null）。给了 `source` 只列 `share` 入口匹配它的。按名字排序。
- call `plugins.run {workspace, station, id, source}`：`send: "auto"` 用 `chat.send`（按 session）发出 `source`，
  `"composer"` 放进那个对话的输入框；答 `{station, session, key, title, sent}`，页面拿去打开对话或报一声已发。
- call `plugins.delete {workspace, station, id}`。

## 安卓

- 普通的「still.fail」分享入口不变（docs/share-in.md：只放进输入框，不放快捷操作）。
- 另一个入口「快捷分享」（manifest 里 `ShareActivity` 的 `activity-alias`，默认关）：app 看到当前 workspace 有带
  `share` 入口的插件就打开它（`setComponentEnabledSetting`），一个都没有就关掉。没有插件的人在分享列表里看不到它。
- 从「快捷分享」进来：只有一个插件匹配就直接 `plugins.run`，面板显示「已发到 <对话>」和「打开对话」，几秒后自己关；
  几个匹配就列出来挑；一个都不匹配就回到普通的分享面板。
- 以后再加：把每个插件发布成系统的「分享直达」（sharing shortcuts）。有的国产系统不显示那一排，所以固定入口是主路。

## web、浏览器扩展

第一期不做。`/share` 和扩展以后同样用 `plugins` topic：匹配的插件列在分享面板最上面，或扩展的右键菜单里每个插件一项。
