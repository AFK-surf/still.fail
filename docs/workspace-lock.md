# workspace 安全模式（锁）

> chat EMBER/1791993156.752000（2026-10-15 用户定：owner 自己开、默认关；passkey 也是自愿；不强制装客户端；角色取锁和 cloud 中较低的；网页版加进来的设备 30 天）。

没开的时候，谁能进 station 由 still.fail 的服务器（cloud）决定：它签成员凭证、发 station 名单、决定 station 属于哪个 workspace。cloud 被攻破，就能给自己发凭证、往名单里加 station、把 station 改绑走，从而在所有 station 上执行命令。

开了之后，workspace 有一条**锁**：一串带哈希链的签名记录，写明成员、设备、station。cloud 只负责存和转发；station 钉住锁之后只认锁里签过的东西。

## station 钉住锁之后

| 东西 | 以前 | 钉住锁之后 |
|---|---|---|
| 成员凭证 | cloud 的 grant key 签的就行 | 仍要 cloud 的凭证（过期、吊销照旧），但用锁里签过的 grant 公钥验（`cloud_keys`），state 帧换 key 不算；设备必须在锁里 |
| 角色 | 凭证里写的 | 锁里的角色和凭证里的取**较低**的：cloud 能降权、踢人，不能提权 |
| station 名单（`peers`） | state 帧给什么算什么 | 只认同时在锁里的 station：cloud 能少给，不能多给 |
| workspace、origin | state 帧能改 | 不变（日志里记一条） |
| `gateway_keys` | state 帧给什么算什么 | 只认同时在锁里的 |
| presence 上的 `tool` 帧 | 照做 | 拒绝（gateway 只能走 `comma/tools/1`，且要在锁里） |
| 吊销、移除（4004） | 照收 | 照收：只会缩小权限 |

没开锁的 station 行为完全不变。

## 记录格式

```
Entry = {v: 1, ws, seq, prev, at, kind, body, sig}
hash  = sha256("stillfail-lock/1\n" + canonical({v, ws, seq, prev, at, kind, body}))   // hex
sig   = {key: "ed25519:<hex>", alg: "Ed25519", sig: <hex>}          // 签的是 "stillfail-lock/1 sig\0" + hash 的字节
      | {key: "p256:<b64url>", alg: "ES256", sig: <b64url p1363>}    // 同上
      | {key: "p256:<b64url>", alg: "webauthn", authenticator_data, client_data, sig}  // passkey：challenge = hash 的字节
```

`canonical` 是键排好序、没有空白的 JSON，只允许整数。三处实现（`station/src/cloud/lock.ts`、`cloud/src/lock.ts`、`client/core-ts/src/lock.ts`）用同一组测试值。

| kind | body | 谁能签 |
|---|---|---|
| `genesis` | `{owner, origins, rp_id, cloud_keys, members[], devices[], passkeys[], stations[], gateways[]}` | owner 自己的设备或 passkey（必须在这条 genesis 里） |
| `member` / `member.remove` | `{sub, email, role}` / `{sub}` | owner、admin；涉及 owner 的只有 owner |
| `device` / `device.remove` | `{id, sub, kind: app\|web, label, sign_key?, endpoints?, exp?}` / `{id}` | owner、admin；成员只能给自己加、删 |
| `passkey` / `passkey.remove` | `{id, sub, key: "p256:…", label}` / `{key}` | 同上 |
| `station` / `station.remove` | `{key, name}` / `{key}` | owner、admin |
| `gateway` / `gateway.remove` | `{key}` | owner、admin |
| `cloud_keys` | `{keys}`（JWKS） | owner |
| `disable` | `{}` | owner |

- **签名者**不单独列：锁里某个成员的 app 设备的 `sign_key`，或他的 passkey。权限跟着锁里的角色走。
- **网页版不能签**：页面代码是 cloud 发的。`kind: web` 的设备不能有 `sign_key`，`exp` 最多 30 天（station 校验）。
- **设备身份**：`id` 是设备的基础 iroh 密钥（core 的 `DEVICE_KEY` 对应的公钥）。客户端按中继派生出多个 endpoint，所以连 station 时 hello 里带 `lock: {device: <基础公钥>, proof}`，`proof` 是基础密钥对 `"stillfail-lock-endpoint/1\0<ws>\0<endpoint>"` 的签名。老客户端没有这一步，开锁时按它用过的 endpoint 记进 `endpoints`。
- **passkey**：station 校验 `clientDataJSON` 的 `type` 是 `webauthn.get`、`origin` 在 genesis 的 `origins` 里、challenge 是条目哈希，`authenticatorData` 的 rpIdHash 是 `rp_id`、带 UP 标志，ES256。
- **分叉**：station 只接能延长自己链头的条目；和已有的冲突就拒。

## 同步

- cloud：`GET/POST /v1/workspaces/:ws/lock`（成员；只追加，检查 `seq`/`prev` 接得上），`DELETE`（owner，签名者都丢了时清掉）。state 帧多一个 `lock: {seq, hash, genesis} | null`。station 落后就在 presence socket 上发 `{type: "lock.get", after}`，cloud 回 `{type: "lock", entries}`；cloud 落后（丢了、被清了）station 发 `{type: "lock.put", entries}` 补回去。
- station 之间：`stillfail/station/1` 上的 `lock.head` / `lock.get {after}` / `lock.put {entries}`，只和锁里的 station。锁变长、名单到了就互相拉平（`station/src/mesh/lock-sync.ts`）。
- 设备：`GET/POST /admin/api/lock`（station 自己的锁；POST 逐条校验）。hello 的回复多一个 `lock`（链头），设备发现 station 落后可以推。
- cloud 扣着条目不发只能拖慢，伪造不了。

## 钉住

- **开锁**（`lock.open`）：owner 的 app 生成签名钥匙，列出成员、最近 31 天领过凭证的设备（cloud 从这版起记 `devices`）、能回答 `GET /lock` 的 station，签 genesis，交给 cloud，再经 admin 连接直接交给每台 station。没钉住的 station 只接 owner（凭证角色）从 genesis 里自己那台设备送来的 genesis。
- **离线、旧版的 station** 不进 genesis：锁里的 station 能调别的 station 的 `task.*`，一台不认锁的 station 被 cloud 控制后就能借它进来。它们和受保护 station 之间的远程任务、分享会停，升级/上线后用 `lock.addStation` 加。
- **新 station**：锁住的 workspace 生成的登记命令带锁的哈希（`install.sh … <token> <hash>`、`stillfail station enroll … --lock <hash>`）。station 登记后打印一个短码，cloud 送来含这个哈希的链时钉住；管理员核对短码签 `station` 条目后它才进名单。
- **签名者都丢了**：在 station 本机运行 `stillfail lock reset`（锁文件改名留底），这台 station 回到信任 cloud。`stillfail lock status` 看现在钉的是什么。
- **关掉**：owner 签 `disable`，各 station 解除钉住。签之前要郑重确认（2026-10-17 用户要求）：确认框逐条列出关掉后失去什么，要输入 workspace 名称才能点；core 签名前再让系统验证本人（host `secureAsk`：Mac 上 Touch ID，安卓指纹或屏幕锁；没有可验证手段的机器——Windows、Linux、没有 Touch ID 的 Mac、没设屏幕锁的手机——直接通过），用户在系统弹窗里取消（`user_cancelled`）就什么都不签、不提示。

## 新设备

面对面批准（2026-10-19 用户定：受信任设备显示码、新设备输入；不经 cloud；不自动申请）。实现在 `client/core-ts/src/views/pair.ts`（协议）和 `src/pair.ts`（交换），设备间直连见 `src/iroh.ts` 的 `accept`（Node 的 mesh.node、安卓 shell 的 `iroh.accept`；网页版不接受连接，也不能批准别人）。

- **只能手动发起**：新设备读到锁、发现自己不在里面，只显示等待页，不自己申请；用户点「发送批准请求」（`lock.pair`）才开始。
- **直连受信任设备**：新设备从锁里挑出能批准它的设备（自己账号下带 `sign_key` 的 app 设备，和 owner、admin 的），用 iroh 按 id 直连（ALPN `stillfail/pair/1`，relay 用账号和 workspace 的 relay 列表），每台连上的发 `hello {workspaces: [{ws, credential}], kind, label, sign_key}`。app 的主 endpoint 带这个 ALPN 接受连接（`mesh.ts` `takes`）。
- **受信任设备核对**：用自己核对过签名的锁（`vault/lock-check.ts` `checkLock`）里的 cloud 公钥验每个 workspace 的成员凭证（EdDSA，`device` 必须是连上来的那个 endpoint id），确认这台设备在那个 workspace 能为此人批准（owner/admin，或本人自己的设备），然后弹出码（`lockPrompts` 的 `pairing`，在哪个 workspace 都弹）：只有码和「拒绝」，没有批准按钮。码是 6 位数字（约 20 bit：每次连接最多试 3 次，每次都会在受信任设备上弹出），只显示不发送；新设备上是 6 个格子，弹数字键盘，输满自动提交，输错清空重来（2026-10-19 用户：「好输入一点」）。
- **CPace**：新设备输入码，两边各自用「码 + 双方 endpoint id（各自从连接上看到的）+ workspace 列表」生成 ristretto255 上的生成元，交换一次 share，算出同一把钥匙再互发 MAC。新设备先验受信任设备的 MAC 才回自己的；受信任设备验过新设备的 MAC 才在每个 workspace 签 `device` 条目（app 带 `sign_key`，网页版 30 天到期）。连错了对象（假的锁、中间人）时双方的 id 不一致，码对也算不出同一把钥匙。
- **次数和时限**：一次连接最多试 `PAIR_TRIES`（3）次，码 `PAIR_WAIT_MS`（5 分钟）内有效；受信任设备上点「拒绝」或关掉弹窗（`lockPrompt.deny`），码立即作废；新设备连每台 `PAIR_DIAL_MS`（20 秒）为限，一台都没连上时页面说明要在已获批的设备上打开 still.fail。
- **状态**：新设备的进度在 `lock` topic 的 `me.pair`（`finding` / `code` / `checking` / `wrong` / `none` / `failed` / `done`），等待页按它显示输入框、剩余次数或重试。
- 锁住的 station 拒绝不在锁里的设备时回 `{code: "lock_unconfirmed", lock}`，core 报 `lock_unconfirmed`，说明是哪个 workspace、去哪批和这台的安全码。
- **旧客户端**：旧版新设备仍经 cloud 申请（`lock.request`，`/v1/workspaces/:ws/lock/requests`），在各 workspace 的 设置 › 安全「待你批准」里核对短码后批（`lock.confirm`），不再弹窗。cloud 上的申请 7 天后作废；同一个人、同一类、同一个名字的设备只留最新一条。
- 批准、拒绝、续期、移除设备在 cloud 收下条目时就算完成（申请随即撤掉），再在后台把整条链送给锁里的各台 station；cloud 同时通知在线的 station，离线的上线后自己拉。以前要等每台都回话，一台离线的 station 能把一次批准拖上十几秒到几分钟（2026-10-19）。只有 `joinStation`、`addStation` 等那一台 station 的回答。
- 批准由被批准的设备自己带到 station：设备连 station 时，hello 的 `lock` 里多带 `entries`，即锁里把它加进来的那条起到链头的条目（加进来 7 天内，first line 最多 12 KiB）。station 按这台锁拒绝它时，先把带来的条目当普通条目逐条校验、接到自己钉住的链上（不钉新锁，最多 64 条），再判断一次放不放行。带来的条目里没有一条是加这台设备（hello 里证明过的基础公钥）的、或序号接不上 station 的链头时，station 直接不看，一条签名都不验。
- 带来的条目接不上（station 落后不止这几条）时 station 照样拒绝；锁里已有自己时，core 把它当作 station 落后，隔 `BEHIND_MS` 的 1、2、3… 倍再连，同一个链头最多 `BEHIND_TRIES`（5）次。
- 批准、拒绝这类由人发起的调用遇到 cloud 的「请求过多」（每个账号所有设备合计每分钟 120 个请求）时，每 10 秒重试一次，最多 6 次。
- 老客户端的新设备只看到 station 的拒绝文字。

## 数据

- station：`<data>/mesh/lock.json`（`{entries}`），`<data>/mesh/lock-pending.json`（登记时给的哈希）。cloud.json 不变。lock.json 坏了不回退到信任 cloud，而是谁都不让进，直到 `lock reset`。
- cloud：`lock_entries`、`devices`、`lock_requests` 三张新表（`CREATE TABLE IF NOT EXISTS`）。
- core：`lock-signer`（app 的签名钥匙，32 字节 Ed25519 种子；只有 app 的 host 有 `appKeys`）。host 能密封（`secureSet`）时存在系统钥匙串里（安卓 Keystore、桌面 `safeStorage`，`user: false`，见 `docs/vault.md`「设备上的钥匙」），老版本留下的普通文件第一次读到时封进去并删掉；不能密封的 host 照旧是 app 数据目录里的文件。

## 兼容

- 旧 station：不认锁，照旧信 cloud；`GET /admin/api/lock` 回 404，开锁时列为「需要升级」。
- 旧 cloud：state 帧没有 `lock`，station 不向它要也不推给它；没钉锁的 station 不受影响。
- 旧客户端：hello 不带 `lock`，按 `endpoints` 认；领凭证不带 `base`，cloud 照记 endpoint。
- 新客户端 + 旧 station：hello 多出的 `lock` 字段旧 station 不读。
- hello 的 `lock.entries`：旧 station 不读，照旧等 cloud 或批准方送来；旧客户端不带，新 station 照旧拒绝。

## 测试

- 确定性的：`station/test/lock.test.ts`（谁能签什么、passkey、设备身份、锁住后 state 帧换 key/塞名单/改绑被拒、没锁的照旧、station 之间拉平）、`cloud/test/lock.test.ts`（存链、转发、补回、设备登记、待确认）、`client/core-ts/test/lock.test.ts`。三处用同一组哈希测试值。
- 端到端（真进程、真 relay，不进 CI）：`node station/side/lock-e2e.ts`。dev cloud 加 4 台临时 station 和两个真 core（owner 的桌面、新设备），演示 cloud 给自己的设备发凭证、往名单里塞 station、把 station 改绑到别的 workspace、换 grant key（重启 dev cloud 就是换 key），锁住的 station 都拒绝，没锁的照做。

## 界面（第二步）

- core：`lock`、`lockDraft` 两个 topic 和 `lock.*` 调用（`client/core-ts/src/views/lock.ts`），锁记录存在 workspace 的 `lock` 里；workspace 视图多了 `lock`、`lock_requests`，变了就重读。core 读到锁、发现这台设备不在里面（开启时没勾上，或之后才加的），就显示等待页，不等 station 拒绝；**不会自己提交申请**（2026-10-19 用户定：要让用户知道，并由要核对安全码的本人发起），只有用户在等待页点「发送批准请求」（`lock.request`）才发出。station 以 `lock_unconfirmed` 拒绝这台设备后，锁没变前不再连那台 station；锁一变（有人确认了）立刻重试。被安全模式拒绝时凭证本身没问题，重连不再每次向 cloud 领新凭证。
- 桌面/网页：设置 › 安全（`web/src/cloud/Security.tsx`）；开启前核对页 `settings/security/open`；owner 在设置页顶上的一行提示（`lock.dismiss` 关掉，记在 prefs `lockNotice`）；等待确认的设备看到的整页。
- 等待页在首页的位置，顶上仍是首页的顶栏：设置，和 workspace 名称（点开切换 workspace）。手机上没有底栏，以前进了待批准的 workspace 就回不去（2026-10-23）。
- 被安全模式拦下的 station（这台设备未获批 `lock_unconfirmed`，或 station 不接受这个 workspace 的成员 `lock_station`）不显示成离线：link 的 `cause` 是 `lock`，station 列表写「安全模式未放行」，station 页（`blocked`）和对话里写原因。
- 受信任设备上，面对面批准的新设备自己弹出来（`lockPrompts` 的 `pairing`，见「新设备」）：在哪个 workspace 都弹，写明申请访问哪几个 workspace，只显示码和「拒绝」（桌面对话框，手机网页和安卓底部面板），关掉就是拒绝；新设备那边输对码、或被拒绝，弹窗跟着关。被拒绝（或手动关掉）的只是那一次请求（设备加它当时的码）：同一台新设备再发请求，弹窗照样弹（以前要重启 app，2026-10-23）。
- 手机网页（`web/src/mobile/Security.tsx`）和安卓（`screens/Security.kt`）同一套：设置里「安全」一行写现状（等你确认的件数标红），确认设备用底部面板。
- 网页版设备 30 天到期，快到期（5 天内）在「成员和设备」里标出、可续期（`lock.renew`）。

## 还没做

passkey 的注册和签名；新设备加入、快到期时用系统通知推送到这个人的其他设备（现在是 app 开着时弹窗，快到期只在页面里显示）。web 发版签名和多地比对哈希另开。
