# still.fail cloud：账号、workspace 与 station

still.fail 的执行节点叫 **station**：就是现在这套东西（连接、会话、运行时账号、管理页）跑在一台机器上。一个人可以登录多个 Google 账号；一个账号可以建多个 **workspace**，也可以被邀请进别人的 workspace；一个 workspace 里可以有多台 station。网页版和以后的客户端通过 iroh 连到 station，不经过任何业务服务器。

```
浏览器 ──(iroh，只走 relay)───────────────┐
客户端（桌面、Android）──(iroh：局域网直连、   ├─ station
                        relay 或 n0 的 relay)┘
            │ 登录、workspace、成员凭证（30 天，缓存在设备上）
            ▼
Cloudflare：still.fail cloud（ember-cloud API、ember-relay、ember-web / ember-admin / ember-preview 静态站点，官网 still-fail-site）
```

still.fail 以 p2p 为主：设备直接连 station，看 station 在不在线也是设备自己连出来的（不靠 still.fail cloud 推送）。still.fail cloud 只管"人"：账号、workspace、成员，以及签发成员凭证；登录过一次之后，局域网里没有 still.fail cloud 也能用。代码参照 zork 的做法（`deploy/cloudflare`）分出来，和 zork 同一个 Cloudflare 账号。

## 什么存在哪

- **控制面**：和人有关的一切——账号、workspace、成员与角色、邀请、station 名单、成员凭证的签发与吊销。
- **station**：station 自己的东西——连接、运行时账号、会话、对话、agent 的记忆和 skills。station 只用邮箱记"谁"（连接的添加人、对话的发送人、会话的发起人），名字和头像由网页版从控制面的成员名单里取。

## 对象

| 对象 | 是什么 | 标识 |
|---|---|---|
| 账号 | 一个 Google 身份 | Google `sub` |
| 客户端 | 一个浏览器或 App 安装，持有一把 iroh 设备密钥；可以同时登录多个账号 | 设备公钥 |
| workspace | 一组人和一组 station；账号在其中的角色是 owner / admin / member | ULID |
| station | 一台 still.fail 节点，属于一个 workspace | station 的 iroh 公钥 |

- 一个账号可以创建多个 workspace（成为 owner），也可以接受邀请加入别人的。
- owner / admin 可以邀请成员、登记 station、移除成员和 station；owner 还可以改角色、删除 workspace。workspace 至少保留一个 owner。
- 邀请按邮箱发出：对方用这个邮箱登录 still.fail，就会在 workspace 切换菜单里看到邀请，点「加入」即可，不需要传链接。
- 没有 workspace 的账号登录后会自动得到一个自己的 workspace；没有单独的 workspace 列表页，切换都在左上角。
- 客户端里每个已登录的账号各自持有会话（access / refresh token），互不影响；切换账号不需要重新登录。

## 登录

Google OAuth（`openid email profile`），沿用 zork 的会话实现：access token 5 分钟，refresh token 轮换、闲置 7 天 / 最长 30 天过期，重放旧 refresh token 会吊销整个会话。

网页版在同一域名下走标准的授权码 + PKCE：页面生成 verifier，跳到 `/v1/auth/google/start`，回到 `/auth/callback?code=…`，再用 verifier 换 token。回调地址只允许本域的 `/auth/callback`（网页）和 `127.0.0.1` 回环地址（命令行）。token 不出现在 URL 里。

## station 登记

1. admin 在 workspace 里点「添加 station」，得到一条一次性、1 小时有效的登记命令。
2. 在要当 station 的机器上运行它。station 用自己的 iroh 密钥签名证明持有这把密钥，控制面把这个公钥记入 workspace。
3. station 保存控制面的签名公钥（Ed25519），之后校验成员凭证不需要在线访问控制面。

## 连接 station 与成员凭证

设备连 station 靠一张 **成员凭证**（`POST /v1/workspaces/:ws/credential {device}`）：still.fail cloud 用 Ed25519 签的 JWT（`typ: ember-member+jwt`），写明账号、邮箱、名字、workspace、角色、设备公钥和登录会话（`sid`），30 天有效。

- station 离线校验：签名来自登记时保存的公钥、workspace 是自己的、设备公钥等于这条 iroh 连接对端的公钥、没过期、没被吊销。同一张凭证进这个 workspace 的每一台 station。
- 设备把凭证存在本地（`credential/<账号>/<workspace>`，记着签给哪台设备），一天内直接用，过了一天向 still.fail cloud 换新的；still.fail cloud 连不上时，旧的一直用到过期。station 拒绝时（被吊销、过期）立刻换新的。退出账号时一并删掉。
- **吊销**：成员被移除或改角色（`sub`）、登录会话被注销（`sid`）时，still.fail cloud 通过 station 的控制通道推一条吊销（`revoke` 帧，`state` 帧里也带着最近 31 天的吊销）；station 拒绝签发时间不晚于吊销时间的凭证，已连着的最迟 5 秒内断开。station 不在线时错过的吊销，下次连上 still.fail cloud 时从 `state` 里补上。
- still.fail cloud 下线时：已登录过的设备凭缓存的凭证照常连 station（局域网直连或 relay）；只有新登录、新成员需要它。

连接上优先用 ALPN `stillfail/admin/1`，兼容旧版 `ember/admin/1`。第一个流交换凭证；之后每个流承载一个管理 API 请求：请求头是一行 JSON（method、path、headers），随后是请求体；回应头是一行 JSON（status、headers），随后是回应体，流结束即回应结束（SSE 就是一直不结束的回应）。

station 端由 `stillfail-station`（Rust，iroh 1.0.3，mesh/station）负责：它运行整个 station（mesh/app，同一个进程），把 mesh 上来的请求交给 station 的管理 API，带上已验证的用户身份；station 据此记录「谁」做了操作、在管理页对话里说了话。

## 网页版

从 still.fail cloud 打开，先登录。以前的**本机模式**（station 上的 `http://127.0.0.1:4760/admin`，不登录）已经去掉：station 不再提供页面和本机管理 API，那个端口只把旧链接 302 到这里的同一页；每台 station 都必须加入一个 workspace 才干活。

- **cloud 模式**：左上角切换的是 workspace（标明属于哪个账号，账号的添加和退出也在这里）。一个 workspace 的页面同时连着它所有在线的 station：侧栏把各台 station 的会话按时间合在一起、每条标出 station，连接按 station 分组；打开的会话、对话、连接和运行时账号都直接和它所在的 station 通信。所有请求都经浏览器里的 iroh（wasm，只能走 relay）送到各自的 station。

  「设置」分两部分：**账号**（当前 workspace 所用的账号：资料、在哪些地方登录了、退出）和 **workspace**（通用、成员与邀请、Station、连接、各 station 的运行时账号）。连接不在侧栏里，在 workspace 设置下，按 station 标注。

  会话页：执行历史是主体；没有对话时历史下面就是输入框，发出第一条消息就建好这个会话唯一的对话，之后对话在中间、执行历史在右边。agent 没有名字，显示为「模型 · 思考深度」；思考深度是连接的一项设置（Claude Code 的 `--effort`、Codex 的 `model_reasoning_effort`），会话记下创建时的值。会话列表第二行叠放参与者的头像和所在 station。Profile（原来的"运行时账号"）按 station 分组，显示额度：OpenCode Go 的 5 小时 / 每周 / 每月用量、ChatGPT 订阅的限额窗口、Claude 订阅的 5 小时 / 每周用量。

  连接、会话、管理页对话都记录创建人：连接和对话是添加它的人（still.fail cloud 账号的邮箱；以前本机页面上建的记为"本机管理页"）；Slack 发起的会话是发起的 Slack 用户，用 Slack 资料里的邮箱和 still.fail cloud 账号对应。会话列表和连接列表可以只看"我创建的"；打开会话时默认进入自己最近的对话。

浏览器的设备密钥存在 IndexedDB；清掉站点数据等于换了一个新客户端，重新申请凭证即可，不需要任何人重新审批。

## relay 与发现

relay 沿用 zork 的做法：Cloudflare Container 里跑官方 `iroh-relay`，前面由 Worker（`ember-relay`，`cloud/src/relay-worker.ts`）转发 WebSocket。总量限制（RelayBudget）只在建连接时放行，不在帧的路径上：流量按 iroh-relay 自己的 metrics 每分钟读一次，当天超额就重启容器、拒绝新连接；单个客户端的速率由 iroh-relay 自己限。以前每一帧都经过 RelayBudget，它被连接一直占着、每条消息多算一次 DO 请求（2026-09-30 改掉）。它是单独的 Worker，部署 API 不会断开任何 relay 连接。station 平时只以 still.fail 的 relay 为家（浏览器只认它）；still.fail 的 relay 连不上时才临时加入 iroh 官方的公共 relay，恢复后撤掉（`relay_fallback`）。

station 在哪、怎么连，设备自己找，不经过 still.fail cloud：

- **局域网**：mDNS（服务名 `_ember._udp.local`，只有 station 广播，设备只查询）。每块网卡都收发；路由器在子网之间转发的 mDNS 也认。
- **公网**：station 把自己所在的 relay 发布到 Mainline DHT，设备查得到它换过的 relay。
- 浏览器（wasm）只能走 still.fail 的 relay。

几处 iroh 相关库的修补（多网卡、mDNS 反射、macOS 回包源地址、晚到的地址立即补发握手包）在 `vendor/`，原因见 `vendor/README.md`。

## 推送通知

设备（浏览器的 Web Push 订阅、安卓的 FCM token）登记在登录的账号和会话下（`POST/DELETE /v1/push`，会话退出时一起删掉）；station 把自己 chat 的通知签名后发到 `POST /v1/stations/notify`，still.fail cloud 只推给通知里点名、并且是这台 station 所在 workspace 成员的人。接口、签名和推送内容见 [notifications.md](notifications.md)，代码在 `cloud/src/push.ts`、`webpush.ts`、`fcm.ts`。

API Worker 的密钥（都可以不设：没有 VAPID 就没有 Web Push，`/v1/push/key` 回 404；没有服务账号就不推安卓）：

- `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` / `VAPID_SUBJECT`：`deploy.py` 从 studio 的 `~/stillfail-deploy/vapid.json`（`{public, private, subject}`）读。生成一次，之后别换（换了浏览器的订阅全部作废，要重新订阅）：

  ```sh
  node -e 'const j=require("crypto").generateKeyPairSync("ec",{namedCurve:"P-256"}).privateKey.export({format:"jwk"});console.log(JSON.stringify({public:Buffer.concat([Buffer.from([4]),Buffer.from(j.x,"base64url"),Buffer.from(j.y,"base64url")]).toString("base64url"),private:j.d,subject:"mailto:<运维邮箱>"}))' > ~/stillfail-deploy/vapid.json
  ```

- `FCM_SERVICE_ACCOUNT`：Firebase 项目的服务账号 JSON（Firebase 控制台 → 项目设置 → 服务账号 → 生成新的私钥），原样放在 `~/stillfail-deploy/fcm-service-account.json`。

## 部署

still.fail cloud 由以下 Worker 组成（`cloud/wrangler*.jsonc`）：

| Worker | 是什么 | 在哪 |
|---|---|---|
| `ember-cloud` | API（`cloud/src/index.ts`） | `app.still.fail/v1/*`、`admin.still.fail/v1/*`、`/healthz`、`/install.sh`、`/releases/*`、`/.well-known/*` |
| `ember-relay` | relay 及其容器 | `app.still.fail/relay`、`/ping`、`/generate_204`、`/v1/admin/relay/*` |
| `ember-web` | 网页版，纯静态 | `app.still.fail`（Custom Domain） |
| `ember-admin` | 管理后台，纯静态 | `admin.still.fail`（Custom Domain） |
| `ember-preview` | 预览页，纯静态 | `preview.still.fail`（Custom Domain） |
| `still-fail-site` | 官网，纯静态（`pnpm build:site`，`python3 cloud/deploy.py site`） | `still.fail`（Custom Domain）；youdid.wtf 买了、接到 Cloudflare 后加进 `cloud/wrangler.site.jsonc` |

同一个域名上，路由优先于 Custom Domain，所以 API 和 relay 的路径到各自的 Worker，其余都是静态站点。域名没变，客户端不用改。

`cloud/deploy.py [api relay web admin preview]`（在 studio 上运行，需要 `wrangler login` 和 OrbStack 的 docker）逐个部署，不写就是全部；studio 的 `ember-deploy` 只部署改动涉及的那几个，只有 relay 改了才会断开 relay 连接。线上地址 `https://app.still.fail`，Google 登录用单独的 OAuth 客户端（`524783491799-bm55…`，和 zork 同一个 Google Cloud 项目），客户端 JSON 在 studio 的 `~/stillfail-deploy/google-oauth.json`。默认部署目录是 `~/stillfail-deploy`（`STILLFAIL_DEPLOY_DIR` 可覆盖；只有旧 `~/ember-deploy` 存在时仍沿用它）。密钥在 `keys.json`，丢了会让所有人重新登录、所有 station 需要重新加入。PostHog 的项目 key 在 `~/stillfail-deploy/posthog.json`，构建网页版时带进去（见 [telemetry.md](telemetry.md)）。Axiom 的写入令牌和数据集在 `~/stillfail-deploy/axiom.json`（`{dataset, token}`），部署时写成 API Worker 的 `AXIOM_TOKEN` / `AXIOM_DATASET`；客户端和 station 的 trace 发到 `POST /v1/telemetry/traces`，由 Worker 转给 Axiom，令牌不出 Worker（见 `docs/telemetry.md`）。

本地联调（不需要 Cloudflare）：`cloud/test/dev.ts` 在 miniflare 里按线上的路由起全部 Worker（Google 用模拟），配合 `iroh-relay --dev`；`/tmp/mesh-e2e.sh`（studio）把 relay、控制面、`stillfail-station`、管理 API 和无头浏览器串起来跑一遍。
