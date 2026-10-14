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
- **关掉**：owner 签 `disable`，各 station 解除钉住。

## 新设备

- 锁住的 station 拒绝不在锁里的设备时回 `{code: "lock_unconfirmed", lock}`，core 报 `lock_unconfirmed`。
- `lock.request`：设备把基础公钥（app 还有签名公钥）交给 cloud（`/v1/workspaces/:ws/lock/requests`），显示 6 位短码（由基础公钥算出，两边各自算）。
- `lock.confirm {device, code}`：这个人自己另一台锁里的 app 设备、或 owner/admin，核对短码后签 `device` 条目；网页版的设备 30 天到期。
- 老客户端的新设备只看到 station 的拒绝文字。

## 数据

- station：`<data>/mesh/lock.json`（`{entries}`），`<data>/mesh/lock-pending.json`（登记时给的哈希）。cloud.json 不变。lock.json 坏了不回退到信任 cloud，而是谁都不让进，直到 `lock reset`。
- cloud：`lock_entries`、`devices`、`lock_requests` 三张新表（`CREATE TABLE IF NOT EXISTS`）。
- core：`lock-signer`（app 的签名钥匙，32 字节 Ed25519 种子；只有 app 的 host 有 `appKeys`）。

## 兼容

- 旧 station：不认锁，照旧信 cloud；`GET /admin/api/lock` 回 404，开锁时列为「需要升级」。
- 旧 cloud：state 帧没有 `lock`，station 不向它要也不推给它；没钉锁的 station 不受影响。
- 旧客户端：hello 不带 `lock`，按 `endpoints` 认；领凭证不带 `base`，cloud 照记 endpoint。
- 新客户端 + 旧 station：hello 多出的 `lock` 字段旧 station 不读。

## 还没做（第二步）

三端界面（设置里的「安全」、开锁核对页、等待确认、横幅）；签名钥匙放进系统钥匙串；passkey 的注册和签名。web 发版签名和多地比对哈希另开。
