# 公开分享 chat

> chat EMBER/1791983430.527000（2026-10-15 用户定：只做 p2p，我们只承担中继和极少量控制面的成本；内容不进 cloud）。

把一个 chat 的消息冻结成一份快照，存在 chat 所在的 station 上，生成一条链接。拿到链接的人在浏览器里打开，页面直接经 iroh 连到那台 station 读这份快照，cloud 不存、不转任何内容。station 离线时打不开。

第一步只做「公开」（拿到链接就能看）。「需申请」（访客申请、发布人批准）以后在同一条访客通道上加。

## 规矩

- **只由人发布**：没有给 agent 的工具。客户端里 chat 的「…」→「公开分享」。只读成员（`viewer`）不能发布；撤销：发布人，或 workspace 的 owner/admin。
- **只含消息**：chat 里的消息（最新一次编辑后的样子），不含执行历史、卡片的选项、notice。附件逐个勾，默认全勾。
- **发布前预览、打码**：station 按一组特征（各家的 API key、token、私钥块、`password=…` 一类）把疑似机密换成 `[已隐藏]`，预览里标出每条消息隐藏了几处。
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
id TEXT PRIMARY KEY, thread INTEGER, key TEXT, title TEXT, created_by TEXT, created_at INTEGER, upto INTEGER, size INTEGER
```

快照在 `<data>/published/<id>/snapshot.json`，附件在 `<data>/published/<id>/f/<k>`。chat 被删除时它的快照一起删。

**admin API**（成员，经现有 mesh 连接）：

| 请求 | 回答 |
|---|---|
| `POST /threads/:thread/publish/preview {names}` | `{upto, snapshot, redacted: [{n, count}], files: [{k, name, size, type, n}]}`：照现在的样子拼一份，不存 |
| `POST /threads/:thread/publish {upto, files: [k], names}` | `{published: Published}`：按 `upto` 再拼一次，只带勾上的附件，存下 |
| `DELETE /published/:id` | `{ok: true}` |

- `names`：`{email: 名字}`，客户端从 workspace 成员名单给。快照里人的名字按它换，不在里面的用邮箱 @ 前面那段；快照里不出现邮箱。agent 用它在 chat 里的名字。
- `Published = {id, station, key, at, by, byName, size, upto}`；thread 视图（`GET /threads/:id`、`/threads`、`changed/threads`）多一个可选字段 `published: Published[]`（没有时不给）。发布、撤销后 thread 照常推变化。
- 上限：快照（含附件）20 MB，单个附件 10 MB，超了的附件在预览里标出、不能勾。

**快照**（`snapshot.json`，也是预览里的 `snapshot`）：

```
{v: 1, title, station: <station 名>, at: <发布时间 ms>, by: <发布人名字>,
 entries: [{n, at, authorKind, author: <名字>, text, files: [{k, name, size, type, width?, height?, thumbhash?}]}],
 redacted: <总共隐藏了几处>}
```

`k` 是附件在快照里的编号（`f0`、`f1`…）。消息里按文件名放的图（`![](shot.png)`）照旧按名字对上（`placed.ts`）。

**访客通道** `stillfail/guest/1`：每个双向流一问一答。

```
→ {"get": "<id>", "key": "<key>"}                 ← {"ok": true, "size": N} + N 字节的 snapshot.json
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
3. 读快照，再读图片附件，读完关连接。其他附件点了才再连一次去读。
4. 用 web 的 Markdown 渲染（`Prose.tsx`）画消息；消息里的 HTML 照 `Viz.tsx` 放进 `sandbox="allow-scripts"` 的 iframe。
5. station 离线、链接失效、忙，各给一句话。

## 兼容

- 旧 station 没有这些路由：客户端的预览请求回 404，说「这台 station 还没更新」。
- 旧客户端：thread 视图多出的 `published` 不读。
- 新表、新目录、新 ALPN，旧版本都不碰。
