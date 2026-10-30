# 公开分享 chat

> chat EMBER/1791983430.527000（2026-10-15 用户定：只做 p2p，我们只承担中继和极少量控制面的成本；内容不进 cloud）。

> 2026-10-26 用户：「静态分享功能改成分享图片吧，把内容直接渲染成一张长图」。客户端不再新建链接：chat 的「…」里是「分享图片」，打开的还是下面的预览（`chat.publishPreview`：打码、附件逐个勾），按下就把这一列（chat 的名字、消息、末尾 still.fail 的标志）整个画成一张长 PNG，键鼠是「复制图片」，手机 app 是「保存到相册」，手机网页交给系统的分享（没有就下载）。图里不带勾选框、没勾的附件和「已隐藏 N 处」的说明，时间写成日期。app 由 mbui 的 shot（`apps/mbui/mbui/src/ui/shot.mbt`）离屏画、按窗口高度分段读回、边读边压成 PNG（`@pixels.PngRows`），网页由 `web/src/longPicture.ts` 分段画进 canvas、用浏览器的 CompressionStream 压：都不受屏幕高度和单张画布大小的限制。下面的链接、station 的快照和访客通道照旧：已发出的链接继续能打开，chat 的「…」里仍列出它们（前面是链接的地球图标，后面时间、谁发的），能复制、撤销。

> 2026-10-28 用户：「增加分享单个 agent 会话 turn 的输出」「完整 chat 分享图片这里，是不是也可以选择哪些内容不分享」。同一个预览多了两样：
>
> - **分享这一轮**：消息上选中文字后的操作里（手指长按后的条、鼠标选中后的「引用」旁边；app 原生操控是键鼠时悬停在消息上，名字行末尾出现一个「⋯」，菜单里是「复制消息链接」（定位到这条消息的会话链接）和「分享这一轮」，跟右键消息的菜单末尾那两项一样（2026-10-30 用户：名字行两个光秃秃的图标「放这怪怪的」，图片图标读起来像「图片」不像「分享」）；触控时名字行不放（每条都摆着太抢眼，2026-10-29 用户），这两个图标放在长按后那条的末尾，跟引用、复制隔一条竖线。右键消息的菜单末尾有复制消息链接、分享这一轮）点「分享这一轮」，打开的还是「分享图片」，只是 `chat.publishPreview` 带上这条消息的 `turn`（它的 n），core 从 station 照旧给的整份预览里截出这一轮（`views/publish.ts` 的 `turnOf`）：开头是发起这一轮的人的消息（连着说的几条一起），到下一条人的消息之前为止的所有消息（agent 的回复、通知）。在 core 里截，旧 station 也能用。
> - **每条消息都能勾**：预览里每条消息在它头一行的另一侧（别人的在行尾，自己的在行首）有个勾选框，默认全勾；取消的消息在页面上变淡，不画进图里。一条都不勾时按钮不可用。

消息定位链接沿用会话权限，使用 `?message=<seq>`；App 和网页打开后跳到该消息。它不会发布公开快照。

把一个 chat 的消息冻结成一份快照，存在 chat 所在的 station 上，生成一条链接。拿到链接的人在浏览器里打开，页面直接经 iroh 连到那台 station 读这份快照，cloud 不存、不转任何内容。station 离线时打不开。

第一步只做「公开」（拿到链接就能看）。「需申请」（访客申请、发布人批准）以后在同一条访客通道上加。

## 规矩

- **只由人发布**：没有给 agent 的工具。客户端里 chat 的「…」→「公开分享」。只读成员（`viewer`）不能发布；撤销：发布人，或 workspace 的 owner/admin。
- **只含消息**：chat 里的消息（最新一次编辑后的样子），不含执行历史、卡片的选项、notice。附件逐个勾，默认全勾。
- **发布前预览、打码**：station 按一组特征（各家的 API key、token、私钥块、`password=…` 一类，`publish/redact.ts`）把疑似机密换成 `[已隐藏]`，标题（没人起名时就是第一句话）也一样；预览里标出每条消息隐藏了几处。
- **冻结**：快照停在预览时看到的最后一条消息（`upto`），附件拷一份进快照目录，之后 chat 怎么变都不影响它。
- **只读、单独的通道**：访客走 ALPN `stillfail/guest/1`，只能凭口令读一份快照和它的附件；不经过成员的 admin API，碰不到 `session.*`、`task.*`。
- **一次读完就断**：中继是所有人共用一份额度（cloud `limits.ts`：同时 160 个连接、每天 5GB），查看页拿到快照和图片就关掉连接；station 限制访客的并发和频率。

## 链接

```
https://share.still.fail/#<station>.<id>.<key>
```

- `station`：station 的 iroh 公钥，base64url（43 字符）。
- `id`：快照 id，12 个随机字节的 base64url（16 字符）。
- `key`：口令，32 个随机字节的 base64url（43 字符）。

全部在 `#` 后面：浏览器不会发给 share.still.fail，CF 的访问日志里也没有。station 存明文口令（成员本来就能读这个 chat，链接可以在「公开分享」里再复制），比较时用定长比较。

## station

**数据**：stillfail.db 新表 `published`（`CREATE TABLE IF NOT EXISTS`）：

```
id TEXT PRIMARY KEY, thread INTEGER, key TEXT, title TEXT, created_by TEXT, by_name TEXT, created_at INTEGER, upto INTEGER, size INTEGER
```

快照在 `<data>/published/<id>/snapshot.json`，附件在 `<data>/published/<id>/f/<k>`。chat 被删除时它的快照一起删。

**admin API**（成员，经现有 mesh 连接）：

| 请求 | 回答 |
|---|---|
| `POST /threads/:thread/publish/preview {names}` | `{upto, title, entries, redacted: [{n, count}], files: [{k, name, size, type, n, width?, height?, thumbhash?, path, owner}]}`：照现在的样子拼一份，不存；`entries` 和快照里的一样，只是 `files` 是 `k` 的列表；`path`、`owner`（附件现在在哪、哪个会话的）只给成员的预览，让它照 chat 的样子画 |
| `POST /threads/:thread/publish {upto, files: [k], names}` | `{published: Published}`：按 `upto` 再拼一次，只带勾上的附件，存下 |
| `DELETE /published/:id` | `{ok: true}` |

- `names`：`{email: 名字}`，客户端从 workspace 成员名单给。快照里人的名字按它换，不在里面的用邮箱 @ 前面那段；快照里不出现邮箱。agent 用它在 chat 里的名字。
- `Published = {id, key, title, at, by, byName, size, upto}`（`by` 是邮箱，只给成员看）；thread 视图（`GET /threads/:id`、`/threads`、`changed/threads`）多一个可选字段 `published: Published[]`（没有时不给）。发布、撤销后 thread 照常推变化。
- 没有大小上限（2026-10-15 用户定）：快照和附件多大都能发布，查看页也照单全收。

**快照**（`snapshot.json`，也是预览里的 `snapshot`）：

```
{v: 1, title, station: <station 名>, at: <发布时间 ms>, by: <发布人名字>,
 entries: [{n, at, authorKind, author: <名字>, text, files: [{k, name, size, type, width?, height?, thumbhash?}]}],
 redacted: <总共隐藏了几处>}
```

`k` 是附件在快照里的编号（`f0`、`f1`…）。消息里按文件名放的图（`![](shot.png)`）照旧按名字对上（`placed.ts`）。

**访客通道** `stillfail/guest/1`：每个双向流一问一答。

```
→ {"get": "<id>", "key": "<key>"}                 ← {"ok": true, "size": N, "type": "application/json"} + N 字节的 snapshot.json
→ {"get": "<id>", "key": "<key>", "file": "<k>"}  ← {"ok": true, "size": N, "type": "<mime>"} + N 字节
                                                   ← {"error": "…", "code": "gone" | "busy"}
```

- id 不存在和口令不对一样回 `gone`，不区分。
- 一个连接最多 4 个流同时在读，30 秒没有新流就关；同时最多 16 个访客连接、每分钟最多 240 个请求（整台 station），超了回 `busy`。

## cloud

- `GET /v1/relays`：不用登录，回 `{relay_urls}`（`relays.ts`），带 CORS，查看页靠它找中继。这是这个功能唯一用到的控制面。
- share.still.fail：静态 Worker（`wrangler.share.jsonc`，`build-static.ts` 写 `dist/cloud-share`），和 preview 一样与 app 不同源，碰不到登录态；`X-Robots-Tag: noindex`、严格的 CSP。

## 查看页

1. 从 `#` 读出 station、id、口令；问 `/v1/relays`。
2. 用一把随机的临时密钥起只走中继的 iroh endpoint（`client/iroh-wasm`），连 station 的 `stillfail/guest/1`。
3. 读快照，再读图片附件（和消息里放的 HTML），读完关连接。
4. 用 web 的 Markdown 渲染（`Prose.tsx`）画消息；消息里的 HTML 照 `Viz.tsx` 放进 `sandbox="allow-scripts"` 的 iframe。
5. 附件点开和 chat 里一样，用 chat 自己的预览（`FilePreview.tsx`：文本、代码、Markdown、CSV、PDF、图片、视频、音频、HTML），图片可以左右翻快照里的其他图。预览经 `FileSource`（`guest.ts` 的 `guestFiles`）读文件：页面已经读到的（图片、放进消息的 HTML）直接用，别的再连一次 station 读完就关。下载只在预览里（它自己的下载按钮，或者预览显示不了的类型给的下载）。`vite.share.config.ts` 把预览用到的 core 部分换成 `web/src/share/stand-ins/` 里的替身（`station.tsx`、`core/react.ts`、`annotate/ImageMarks.tsx` 等），页面里没有账号或 station core；替身只开放本地 `markdown` 和 `code.ink`，按需加载 core 同一份解析器（含公式布局和代码着色），正文和附件预览共用，其他调用仍拒绝。
6. station 离线、链接失效、忙，各给一句话。

station 给的东西都不会在 share 的源上当页面打开：HTML 只进 share host 自己的 `/frame`（`sandbox="allow-scripts"`，没有 allow-same-origin；srcdoc 的 frame 会继承页面的 CSP，所以不用），SVG 只放进 `<img>`，下载存成 `application/octet-stream` 的文件，预览里没有指向 blob 的链接。页面的 CSP 为预览只加了 `media-src blob:`（视频、音频）；pdf.js 的 worker 和代码分片都是 share host 自己的脚本，已在 `script-src 'self'` 里。

## 兼容

- 旧 station 没有这些路由：客户端的预览请求回 404，说「这台 station 还没更新」。
- 旧客户端：thread 视图多出的 `published` 不读。
- 新表、新目录、新 ALPN，旧版本都不碰。
