# 个人锁

> 2026-11-05 左子健定：「不再有 workspace 锁，只有个人锁，所谓的 workspace 锁其实就是管理员的个人锁」。

## 目标

只有个人锁一种锁，它是唯一的信任根。

- **个人锁**：一个人有哪些设备。一条带哈希链的签名记录，跟着账号走，只有这个人已有的设备能改。owner、admin 和 cloud 都改不了。
- **workspace 名单**：谁是成员（角色、他的个人锁 ID）、哪些 station 和 gateway 算数、cloud 公钥。由 owner 和 admin 用个人钥匙签，保留哈希链，防回滚和分叉。名单里不再有设备。
- **设备连 station**：出示自己的个人锁，station 按「名单钉的个人锁 → 这台设备在锁里」验证。
- **不开名单的 workspace**：成员和 station 信 cloud，手机授权和个人密钥库仍受个人锁保护。

## 现在做到哪

| | 状态 |
|---|---|
| 个人锁本身、面对面加设备 | 已做 |
| 手机授权签名、手机验签 | 已做 |
| 名单钉个人锁、station 按个人锁验设备、迁移已开锁的 workspace | 没做，现有 workspace 锁（`docs/workspace-lock.md`）不变 |
| 密钥库迁到个人锁 | 没做，密钥库仍依赖 workspace 锁 |

## 记录

条目和 workspace 锁同形（`lock-form.ts` 的哈希、Ed25519 签名），`ws` 是 `person:<sub>`，所以签名挪不到别的锁上。

| kind | body | 谁能签 |
|---|---|---|
| `genesis` | `{sub, device: {key, id, label}}` | 这台设备自己 |
| `device` | `{key, id, label}` | 锁里的设备 |
| `device.remove` | `{key}` | 锁里的设备，不能移除最后一台 |

`key` 是设备的个人钥匙，`id` 是它的 iroh 基础密钥（面对面批准时拨它）。

- **钥匙**：`personal-signer`，每台 app 设备一把，`user: true` 封存：每次用都要过生物识别或屏幕锁。这和 `lock-signer` 不同，后者不问人。网页版没有：页面代码是 cloud 发的。
- **cloud**：`GET/POST /v1/me/personal-lock`，存在账号自己的对象里（`cloud/src/personal-lock.ts`）。只收接得上、且由锁里的设备签名的条目，所以只偷到登录态写不进已有的锁；但从 `genesis` 开始的新链它会收（设备全丢时要用）。
- **钉住**：设备只信自己钉住的那条链。cloud 给的链只有在延长钉住的链时才接受；不一样就是 `replaced`，手机继续按原来钉住的验，这台设备不再签任何东西，直到人确认。

## 开启和加设备

1. 第一次批准手机调试时，这台设备生成钥匙，签 `genesis`，交给 cloud，自己钉住。
2. 别的设备在共享调试页点「加入个人锁」：读 cloud 上的锁，拨上面每台设备（沿用 `views/pair.ts`，`hello` 带 `personal: {sub, key}`，`workspaces` 为空）。
3. 锁里的设备显示安全码，新设备输入，CPace 证明（`pair.ts`）。对方过一次生物识别，签 `device`，把整条链经这条已证明的连接交给新设备钉住。
4. 新设备不能只凭 cloud 的话把自己钉上：cloud 可以塞一条假链，但它拿不到人眼看到的安全码。

**设备全丢**：新设备点「新建个人锁」，签新的 `genesis`。别的设备显示 `replaced`，人确认后才改用；手机上的授权都要重新批。

## 手机授权

- **批准**：`adb.decide` 允许时，core 签 `{v, sub, station, request, session, chat, scope, exp}`（标签 `stillfail-phone-grant/1`），随决定交给 station。station 只带着，不读。
- **手机验**：`adb.ts` 的 `#holds`：签名的钥匙在钉住的锁里、内容和 station 说的这条授权一一对得上、没过期、没在这台手机上收回过，才算数。`wanted()` 只看算数的。
- **到期**：手机按签名里的 `exp` 自己停止出借，不需要 station 说。
- **收回**：在这台手机上收回的授权记在设备上（`adb-revoked`），station 再说它还在也不出借。在别的设备上收回要靠 station 转告，改成签名的收回之前，不老实的 station 能拖到它到期。

## 挡得住什么

| 攻击 | 结果 |
|---|---|
| 账号或网页登录态被盗，点批准 | 批不了：没有钥匙 |
| 被盗的账号登录新设备 | 加不进锁：要已有设备显示的安全码 |
| cloud 被攻破，改锁或给假链 | 钉住的设备不跟 |
| station 数据库被改、station 被攻破，说「有授权」 | 手机验签不过，不出借 |
| workspace admin 冒充你批准 | 他的设备不在你的锁里 |

挡不住：

- **活跃授权期间的同机 agent**：手机分不清连接来自哪个对话，这一层只有 `station/src/adb/door.ts` 按进程区分，同一系统用户下存心绕过的 agent 能绕开。要彻底隔离得每个 session 独立系统用户或沙箱。
- **扣着不发**：cloud 可以不把 `device.remove` 发给手机，已丢的设备在手机收到前还能批。
- **第一台设备**：手机第一次开启或加入之前没有东西可钉。

## 兼容

- 旧 station：不带 `signed`，新手机不出借，等 station 更新后重新批。
- 旧 app：批准不带签名；旧手机照旧按 station 的话出借，升级后就不再认这些授权。
- 升级之前批的授权都没有签名，都要重新批。
