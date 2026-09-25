# ember cloud：账号、workspace 与 station

ember 的执行节点叫 **station**：就是现在这套东西（连接、会话、运行时账号、管理页）跑在一台机器上。一个人可以登录多个 Google 账号；一个账号可以建多个 **workspace**，也可以被邀请进别人的 workspace；一个 workspace 里可以有多台 station。网页版和以后的客户端通过 iroh 连到 station，不经过任何业务服务器。

```
浏览器 / 客户端 ──(iroh，只走 relay)──┐
                                       ├─ Cloudflare：ember cloud（账号、workspace、授权签发、relay、网页托管）
station ──(iroh：relay 或直连)─────────┘
```

参照 zork 的做法（`deploy/cloudflare`），代码从那里分出来，单独部署：Worker 名 `ember-cloud`，和 zork 同一个 Cloudflare 账号。

## 什么存在哪

- **控制面**：和人有关的一切——账号、workspace、成员与角色、邀请、station 名单、访问授权。
- **station**：station 自己的东西——连接、运行时账号、会话、对话、agent 的记忆和 skills。station 只用邮箱记"谁"（连接的添加人、对话的发送人、会话的发起人），名字和头像由网页版从控制面的成员名单里取。

## 对象

| 对象 | 是什么 | 标识 |
|---|---|---|
| 账号 | 一个 Google 身份 | Google `sub` |
| 客户端 | 一个浏览器或 App 安装，持有一把 iroh 设备密钥；可以同时登录多个账号 | 设备公钥 |
| workspace | 一组人和一组 station；账号在其中的角色是 owner / admin / member | ULID |
| station | 一台 ember 节点，属于一个 workspace | station 的 iroh 公钥 |

- 一个账号可以创建多个 workspace（成为 owner），也可以接受邀请加入别人的。
- owner / admin 可以邀请成员、登记 station、移除成员和 station；owner 还可以改角色、删除 workspace。workspace 至少保留一个 owner。
- 客户端里每个已登录的账号各自持有会话（access / refresh token），互不影响；切换账号不需要重新登录。

## 登录

Google OAuth（`openid email profile`），沿用 zork 的会话实现：access token 5 分钟，refresh token 轮换、闲置 7 天 / 最长 30 天过期，重放旧 refresh token 会吊销整个会话。

网页版在同一域名下走标准的授权码 + PKCE：页面生成 verifier，跳到 `/v1/auth/google/start`，回到 `/auth/callback?code=…`，再用 verifier 换 token。回调地址只允许本域的 `/auth/callback`（网页）和 `127.0.0.1` 回环地址（命令行）。token 不出现在 URL 里。

## station 登记

1. admin 在 workspace 里点「添加 station」，得到一条一次性、1 小时有效的登记命令。
2. 在要当 station 的机器上运行它。station 用自己的 iroh 密钥签名证明持有这把密钥，控制面把这个公钥记入 workspace。
3. station 保存控制面的授权公钥（Ed25519），之后校验授权不需要在线访问控制面。

## 连接 station 与授权

客户端连 station 之前，向控制面申请一张 **授权**：Ed25519 签名的 JWT，写明账号、workspace、角色、目标 station、客户端设备公钥，10 分钟有效。

- station 只接受：签名来自控制面、目标是自己、所属 workspace 是自己的、设备公钥等于这条 iroh 连接对端的公钥、没过期。
- 授权快到期时客户端在同一连接上换新的；过期不换，station 断开连接。所以成员被移除或 station 被移出 workspace，最迟 10 分钟生效。
- 控制面不能解密业务内容，relay 只转发加密帧。控制面下线时：已有连接照常，新连接拿不到授权（网页版本来也需要登录）；station 本机的管理页不受影响。

连接上用 ALPN `ember/admin/1`。第一个流交换授权；之后每个流承载一个管理 API 请求：请求头是一行 JSON（method、path、headers），随后是请求体；回应头是一行 JSON（status、headers），随后是回应体，流结束即回应结束（SSE 就是一直不结束的回应）。

station 端由 `ember-mesh`（Rust，iroh 1.0.3）负责：ember 启动并看护它，它把请求转给本机管理 API，带上已验证的用户身份；ember 据此记录「谁」做了操作、在管理页对话里说了话。

## 网页版

同一套 React 客户端，两种模式：

- **本机模式**：在 station 上打开 `http://127.0.0.1:4760/admin`，不登录，直接访问本机 API。
- **cloud 模式**：从 ember cloud 打开，先登录。左上角切换的是 workspace（标明属于哪个账号，账号的添加和退出也在这里）。一个 workspace 的页面同时连着它所有在线的 station：侧栏把各台 station 的会话按时间合在一起、每条标出 station，连接按 station 分组；打开的会话、对话、连接和运行时账号都直接和它所在的 station 通信。所有请求都经浏览器里的 iroh（wasm，只能走 relay）送到各自的 station。

  「设置」分两部分：**账号**（当前 workspace 所用的账号：资料、在哪些地方登录了、退出）和 **workspace**（通用、成员与邀请、Station、连接、各 station 的运行时账号）。连接不在侧栏里，在 workspace 设置下，按 station 标注。

  连接、会话、管理页对话都记录创建人：连接和对话是添加它的人（ember cloud 账号的邮箱，本机页面记为"本机管理页"）；Slack 发起的会话是发起的 Slack 用户，用 Slack 资料里的邮箱和 ember cloud 账号对应。会话列表和连接列表可以只看"我创建的"；打开会话时默认进入自己最近的对话。

浏览器的设备密钥存在 IndexedDB；清掉站点数据等于换了一个新客户端，重新申请授权即可，不需要任何人重新审批。

## relay 与发现

relay 沿用 zork 的做法：Cloudflare Container 里跑官方 `iroh-relay`，前面由 Worker 转发 WebSocket 帧并做总量限制。station 和客户端都用这个 relay 作为 home relay，所以客户端只凭 station 公钥和 relay 地址就能连上，不依赖额外的发现服务；签名发现（pkarr）保留给以后能直连的原生客户端。

## 部署

`cloud/deploy.py`（在 studio 上运行，需要 `wrangler login` 和 OrbStack 的 docker）：构建网页版（含 wasm）、部署 Worker 和 relay 容器、写入密钥、检查 `/healthz`。线上地址 `https://ember.3720.org`，和 zork 同一个 Cloudflare 账号，Google 登录用单独的 OAuth 客户端（`524783491799-bm55…`，和 zork 同一个 Google Cloud 项目），客户端 JSON 在 studio 的 `~/ember-deploy/google-oauth.json`。密钥在 studio 的 `~/ember-deploy/keys.json`，丢了会让所有人重新登录、所有 station 需要重新加入。

本地联调（不需要 Cloudflare）：`cloud/test/dev.ts` 起一个本地控制面（Google 用模拟），配合 `iroh-relay --dev`；`/tmp/mesh-e2e.sh`（studio）把 relay、控制面、`ember-mesh`、管理 API 和无头浏览器串起来跑一遍。
