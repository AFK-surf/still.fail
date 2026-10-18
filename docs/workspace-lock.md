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

- 锁住的 station 拒绝不在锁里的设备时回 `{code: "lock_unconfirmed", lock}`，core 报 `lock_unconfirmed`，说明是哪个 workspace、去哪批（自己在那个 workspace 里的受信任设备或管理员的「设置 › 安全」）和这台的安全码：一台设备在一个 workspace 获批了、另一个还没批时，看得出是哪一个。
- `lock.request`：设备把基础公钥（app 还有签名公钥）交给 cloud（`/v1/workspaces/:ws/lock/requests`），显示 6 位短码（由基础公钥算出，两边各自算）。app 先要生成并存下签名钥匙（`Signer.make`）；存不下（宿主没有可用的 `secure.*`、钥匙串拒绝）就不发申请、不重试，等待页写明「此设备无法提交批准请求：……」（`lock` topic 的 `me.failed`），可以手动重发。cloud 上的申请 7 天后作废（重新申请就重新计时）；同一个人、同一类（app/web）、同一个名字的设备只留最新的一条（同一个浏览器清了存储、app 重装后会换一把钥匙）。
- `lock.confirm {device, code}`：这个人自己另一台锁里的 app 设备、或 owner/admin，核对短码后签 `device` 条目；网页版的设备 30 天到期。
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

## 测试

- 确定性的：`station/test/lock.test.ts`（谁能签什么、passkey、设备身份、锁住后 state 帧换 key/塞名单/改绑被拒、没锁的照旧、station 之间拉平）、`cloud/test/lock.test.ts`（存链、转发、补回、设备登记、待确认）、`client/core-ts/test/lock.test.ts`。三处用同一组哈希测试值。
- 端到端（真进程、真 relay，不进 CI）：`node station/side/lock-e2e.ts`。dev cloud 加 4 台临时 station 和两个真 core（owner 的桌面、新设备），演示 cloud 给自己的设备发凭证、往名单里塞 station、把 station 改绑到别的 workspace、换 grant key（重启 dev cloud 就是换 key），锁住的 station 都拒绝，没锁的照做。

## 界面（第二步）

- core：`lock`、`lockDraft` 两个 topic 和 `lock.*` 调用（`client/core-ts/src/views/lock.ts`），锁记录存在 workspace 的 `lock` 里；workspace 视图多了 `lock`、`lock_requests`，变了就重读。core 读到锁、发现这台设备不在里面（开启时没勾上，或之后才加的），就自己提交确认请求并显示等待页，不等 station 拒绝（还连着的 station 不会马上拒绝，没连过的也不会）；station 以 `lock_unconfirmed` 拒绝这台设备后同样会请求，锁没变前不再连那台 station；锁一变（有人确认了）立刻重试。被拒过的设备（申请没了、自己也没进锁：被拒绝，或被 cloud 作废）记在锁记录的 `declined` 里，之后锁再变、重启都不再自己申请，只能在它的等待页上手动「发送批准请求」。
- 桌面/网页：设置 › 安全（`web/src/cloud/Security.tsx`）；开启前核对页 `settings/security/open`；owner 在设置页顶上的一行提示（`lock.dismiss` 关掉，记在 prefs `lockNotice`）；等待确认的设备看到的整页。
- 等这台设备确认的新设备自己弹出来（`lockPrompts` topic，不带 workspace，2026-10-19 起）：这个人所有 workspace 里、这台是受信任设备的那些，在哪个 workspace 都能收到。同一台新设备（同一把基础公钥）在几个 workspace 都申请时合成一条，`workspaces` 逐个列出名字和图标，弹窗醒目写明「申请访问」哪几个；核对一次短码，`lockPrompt.confirm {device, code}` 在这几个 workspace 里各签一条 `device`（`lockPrompt.deny {device}` 同样全部拒绝），有的失败时报错列出没批成的 workspace。`prompt` 是第一个还有 workspace 没在这台弹过的。界面弹出核对短码的窗口（桌面对话框，手机网页和安卓底部面板），换页、换 workspace 都不关；用户手动关掉时调 `lockPrompt.shown {device}`，这次运行里同一台不再弹，仍在各 workspace 的 设置 › 安全 里（那里的「验证」只批这一个 workspace）。别的设备上确认或拒绝了，`waiting` 里没了它，弹窗跟着关。
- 手机网页（`web/src/mobile/Security.tsx`）和安卓（`screens/Security.kt`）同一套：设置里「安全」一行写现状（等你确认的件数标红），确认设备用底部面板。
- 网页版设备 30 天到期，快到期（5 天内）在「成员和设备」里标出、可续期（`lock.renew`）。

## 还没做

passkey 的注册和签名；新设备加入、快到期时用系统通知推送到这个人的其他设备（现在是 app 开着时弹窗，快到期只在页面里显示）。web 发版签名和多地比对哈希另开。
