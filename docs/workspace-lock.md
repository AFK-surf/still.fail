# workspace 安全模式（锁）

> chat EMBER/1791993156.752000（2026-10-15 用户定：owner 自己开、默认关；passkey 也是自愿；不强制装客户端；角色取锁和 cloud 中较低的；网页版加进来的设备 30 天）。

没开的时候，谁能进 station 由 still.fail 的服务器（cloud）决定：它签成员凭证、发 station 名单、决定 station 属于哪个 workspace。cloud 被攻破，就能给自己发凭证、往名单里加 station、把 station 改绑走，从而在所有 station 上执行命令。

开了之后，workspace 有一条**锁**：一串带哈希链的签名记录，写明成员、设备、station。cloud 只负责存和转发（只收 station 会收的条目，见「同步」）；station 钉住锁之后只认锁里签过的东西。

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

- **签名者**不单独列：锁里某个成员的 app 设备的 `sign_key`，或他的 passkey。权限跟着锁里的角色走，而且只有**本人的**设备和 passkey 签的才算（下一条）。
- **本人的设备**（2026-11-04 用户定，chat EMBER/1793781166.844000）：owner、admin 可以往任何成员名下加设备和 passkey，以前这台设备签的条目就按那个人的角色算：admin 往 owner 名下加一台，签名钥匙在自己手里，就能以 owner 的身份换 cloud 公钥、关掉安全模式、提别人当 owner，在密钥库里也能以 owner 的名义签库的新版本、收封给 owner 的待存值。现在锁里每台设备、每把 passkey 都有 `own`（station `cloud/lock.ts` Device `own`、core `vault/lock-check.ts`，同一套规则）。算本人的有三种：genesis 里列着的；本人的设备或 passkey 签进来的；这个人在锁里还没有过能签名的本人设备或 passkey 时（他的第一台，面对面批准）由 owner、admin 签进来的。admin 把某台本人设备换成自己的 `sign_key`，这台就不再算本人的；签名钥匙不变（网页版续期）则照旧算本人的。不是本人的设备照样能连 station，但它签的条目留在链里、什么也不改（以前的锁里有这样的条目，链照样折得下去）；cloud 不再收新的这种条目（`lock_refused`），core 也不签（`lock_not_own`）。密钥库同样只认本人设备的签名、只封给本人设备（`docs/vault.md`）。
  - 第二台设备起只能本人批：面对面批准时，别人的设备只在这个人还没有能签名的本人设备时出码（`pair.ts placesFor`/`waitingIn`）。以前由 admin 批进来的第二台设备现在不算本人的：在「成员和设备」里移除，再用自己的设备重新批准。
  - 设备全丢了：admin 加的新设备不算本人的。admin 把这个人移出成员再加回来（`member.remove` 清掉记录），之后的第一台由 admin 面对面批准，库用恢复码找回。admin 想冒充谁，只能明着把他踢出去。
- **网页版不能签**：页面代码是 cloud 发的。`kind: web` 的设备不能有 `sign_key`，`exp` 最多 30 天（station 校验）。
- **设备身份**：`id` 是设备的基础 iroh 密钥（core 的 `DEVICE_KEY` 对应的公钥）。客户端按中继派生出多个 endpoint，所以连 station 时 hello 里带 `lock: {device: <基础公钥>, proof}`，`proof` 是基础密钥对 `"stillfail-lock-endpoint/1\0<ws>\0<endpoint>"` 的签名。老客户端没有这一步，开锁时按它用过的 endpoint 记进 `endpoints`。
- **passkey**：station 校验 `clientDataJSON` 的 `type` 是 `webauthn.get`、`origin` 在 genesis 的 `origins` 里、challenge 是条目哈希，`authenticatorData` 的 rpIdHash 是 `rp_id`、带 UP 标志，ES256。
- **分叉**：station 只接能延长自己链头的条目；和已有的冲突就拒。

## 同步

- cloud：`GET/POST /v1/workspaces/:ws/lock`（成员；只追加，检查 `seq`/`prev` 接得上，并用 station 的同一份规则（`station/src/cloud/lock.ts` 的 `genesis`/`apply`，cloud 直接 import）校验签名和权限，station 不会收的回 409 `lock_refused`：cloud 收下一条 station 拒收的，之后每一条都接在它后面，station 一条也接不上（2026-10-24 一个 workspace 因此卡了四天）。这之前存下的链，cloud 第一次读到时截到最后一条能通过的为止），`DELETE`（owner，签名者都丢了时清掉）。state 帧多一个 `lock: {seq, hash, genesis} | null`。station 落后就在 presence socket 上发 `{type: "lock.get", after}`，cloud 回 `{type: "lock", entries}`；cloud 落后（丢了、被清了）station 发 `{type: "lock.put", entries}` 补回去。
- station 之间：`stillfail/station/1` 上的 `lock.head` / `lock.get {after}` / `lock.put {entries}`，只和锁里的 station。锁变长、名单到了就互相拉平（`station/src/mesh/lock-sync.ts`）；和某台拉平失败（它离线、两台之间的线断了）就隔 5 秒、10 秒……最长 10 分钟再试，直到拉平：cloud 扣着条目不发时，只有这条路能把它们带过去。自己已不在锁里的 station 不再找别的 station（它们的 mesh 不收它）。
- 设备签了条目交给 cloud 时没收到回答（网关 502、线断了）：先再读一次 cloud 的链，条目已在就算成了，不报失败（以前报失败，面对面批准时新设备会说「没能批准此设备」，其实已批准）。
- 设备：`GET/POST /admin/api/lock`（station 自己的锁；POST 逐条校验）。hello 的回复多一个 `lock`（链头），设备发现 station 落后可以推。core 签任何条目前先用 `vault/lock-check.ts` 按 station 的规则把整条链加上新条目验一遍：此设备不是锁里的签名者（锁里有它但没有 `sign_key`，本机却有签名钥匙）、角色不够、cloud 上的链本身验不过，都不发，直接告诉用户原因。
- **关掉又重开时 station 不在**：cloud 换新链时把关掉的那条留在 `lock_turned_off`。station 发现 state 帧里的链头 genesis 跟自己钉的不同，就发 `{type: "lock.get", after, genesis}`，cloud 回那条旧链剩下的条目（含 `disable`），station 逐条验过后自己解除钉住，不用再到那台电脑上 `lock reset`；之后它跟没开过锁的 station 一样，在「安全」里重新加入。旧 cloud 不认 `genesis`，照旧回当前的链，station 照旧拒收。
- **station 钉着另一条锁**（重新开启时它没连上，或 cloud 收过它拒收的条目）：它拒绝设备时回的链头不在设备手里这条链上（genesis 不同，或同一序号哈希不同），core 不再当作「station 落后、稍后重试」，而是说这台 station 的记录和 workspace 不一致、要在那台电脑上 `stillfail lock reset` 后重新保护。打开「安全」时 core 问一遍锁里各 station 的 `GET /lock`：说自己没锁或钉着别的锁的不算受保护（可以重新加入）；开启时的核对页把钉着别的锁的 station 列为 `other`，不能勾选。
- cloud 扣着条目不发只能拖慢，伪造不了。

## 钉住

- **开锁**（`lock.open`）：owner 的 app 生成签名钥匙，列出成员、最近 31 天领过凭证的设备（cloud 从这版起记 `devices`）、能回答 `GET /lock` 的 station，签 genesis，交给 cloud，再经 admin 连接直接交给每台 station。没钉住的 station 只接 owner（凭证角色）从自己的设备送来的、从 genesis 起的整条链，这台设备要在这条链折完后的锁里、角色是 owner（以前只认 genesis 里的设备：owner 后来批准的手机在「安全」里点「加入」，cloud 上已记下这台 station，station 却回英文报错不钉）。
- **离线、旧版的 station** 不进 genesis：锁里的 station 能调别的 station 的 `task.*`，一台不认锁的 station 被 cloud 控制后就能借它进来。它们和受保护 station 之间的远程任务、分享会停，升级/上线后用 `lock.addStation` 加。
- **新 station**：锁住的 workspace 生成的登记命令带锁的哈希（`install.sh … <token> <hash>`、`stillfail station enroll … --lock <hash>`）。station 登记后打印一个短码，cloud 送来含这个哈希的链时钉住；管理员核对短码签 `station` 条目后它才进名单。
- **签名者都丢了**：在 station 本机运行 `stillfail lock reset`（锁文件改名留底），这台 station 回到信任 cloud。`stillfail lock status` 看现在钉的是什么（原生启动器 `stillfail-station` 把 `lock` 转给 Node，2026-10-29 之前它不认，只打印用法）。
- **关掉**：owner 签 `disable`，各 station 解除钉住，并在 lock.json 旁的 `lock.json.off` 记下这条锁的 genesis：关过的锁不再钉回。设备每改一次锁都把到那时为止的整条链送给各台 station，这一份比 cloud 的 `disable` 晚到时，以前会把 station 按旧链重新锁上（cloud 上已经关了，这台还在拦新设备）。签之前要郑重确认（2026-10-17 用户要求）：确认框逐条列出关掉后失去什么，要输入 workspace 名称才能点；core 签名前再让系统验证本人（host `secureAsk`：Mac 上 Touch ID，安卓指纹或屏幕锁；没有可验证手段的机器——Windows、Linux、没有 Touch ID 的 Mac、没设屏幕锁的手机——直接通过），用户在系统弹窗里取消（`user_cancelled`）就什么都不签、不提示。

## 新设备

面对面批准（2026-10-19 用户定：受信任设备显示码、新设备输入；不经 cloud；不自动申请）。实现在 `client/core-ts/src/views/pair.ts`（协议）和 `src/pair.ts`（交换），设备间直连见 `src/iroh.ts` 的 `accept`（Node 的 mesh.node、安卓 shell 的 `iroh.accept`；网页版不接受连接，也不能批准别人）。

- **只能手动发起**：新设备读到锁、发现自己不在里面，只显示等待页，不自己申请；用户点「发送批准请求」（`lock.pair`）才开始。
- **直连受信任设备**：新设备从锁里挑出能批准它的设备（自己账号下带 `sign_key` 的 app 设备，和 owner、admin 的），用 iroh 按 id 直连（ALPN `stillfail/pair/1`，relay 用账号和 workspace 的 relay 列表），每台连上的发 `hello {workspaces: [{ws, credential}], kind, label, sign_key}`。app 的主 endpoint 带这个 ALPN 接受连接（`mesh.ts` `takes`）。
- **受信任设备核对**：用自己核对过签名的锁（`vault/lock-check.ts` `checkLock`）里的 cloud 公钥验每个 workspace 的成员凭证（EdDSA，`device` 必须是连上来的那个 endpoint id），确认这台设备在那个 workspace 能为此人批准（owner/admin，或本人自己的设备），然后弹出码（`lockPrompts` 的 `pairing`，在哪个 workspace 都弹）：只有码和「拒绝」，没有批准按钮。码是 6 位数字（约 20 bit：每次连接最多试 3 次，每次都会在受信任设备上弹出），只显示不发送；新设备上是 6 个格子，弹数字键盘，输满自动提交，输错清空重来（2026-10-19 用户：「好输入一点」）。
- **后来加的成员**（2026-11-06 用户：「他请求安全码根本跳不出来」）：开锁之后在 cloud 加的成员不在锁里。加人的那一刻签不了：加人的可能在网页版上，被加的人可能还没注册，还没有 `sub`；以前也没有别的地方给他们签 `member` 条目，受信任设备一查锁里没这个人就回 `not_here`，他的每台设备都等不到码，哪台也不弹。现在 owner、admin 的受信任设备照样给他的第一台设备出码：凭证是 cloud 说他是成员，真正放他进来的是把码告诉他的那个人。码输对后先签 `member`（`Lock.admit`，cloud 的链上已有这个人就不签），再签 `device`。角色一律写 `member`，cloud 说他是 admin 也一样：cloud 只能降权、不能提权，admin 在锁里能签 station 名单，不能只凭 cloud 的一句话就给。弹窗里设备名后面写明「还没加入这个 workspace 的安全模式，批准后以成员身份加入」，让给码的人知道这次是在放一个新人进来（`core-misc.lock.pairJoins`）。普通成员的设备不给不在锁里的人出码。
- **每 10 秒找一次，最多 6 次**：新设备每 `PAIR_REDIAL_MS`（10 秒，从上一次开始算）连一次还没连上的受信任设备，每次以 `PAIR_DIAL_MS`（同样 10 秒）为限，每台最多 `PAIR_DIAL_TRIES`（6）次，大约 1 分钟。人常常是先点「发送批准请求」，再去打开手机、电脑上的 still.fail：以前每台只在点的那一刻连一次 20 秒，之后才打开的设备什么也不弹，新设备说「未找到在线的受信任设备」（2026-11-05 用户：「开好几个自己已经进这个 workspace 的设备，根本就弹不出来」；「每 10 秒一次也可以，但是比如说最多找 6 次这样。并且如果已经弹出来了，就不要重复弹」「一直找 10 分钟也太夸张了吧」）。已经有一台弹了码，没连上的也照样接着连：码可能弹在不在手边的那台上，打开手边这台它也弹一个，两个码输哪个都行。连上了（把 `hello` 交给了它）的不再连，不管它回的是码、`no`（它在这些 workspace 都不能批准这台），还是什么也没回（回话丢了：它可能已经弹了码，再连一次它会换一个新码再弹）：一台设备一次请求只弹一次。每台都连上了或 6 次都没连上，又没有一台弹码，才是 `none`，页面说「未找到在线的受信任设备」，要再点一次才重新找。批准了、被拒绝、码过期了、再点一次（旧的这一轮作废）或取消（`lock.pairCancel`），都不再连。
- **CPace**：新设备输入码，两边各自用「码 + 双方 endpoint id（各自从连接上看到的）+ workspace 列表」生成 ristretto255 上的生成元，交换一次 share，算出同一把钥匙再互发 MAC。新设备先验受信任设备的 MAC 才回自己的；受信任设备验过新设备的 MAC 才在每个 workspace 签 `device` 条目（app 带 `sign_key`，网页版 30 天到期）。连错了对象（假的锁、中间人）时双方的 id 不一致，码对也算不出同一把钥匙。
- **次数和时限**：一次连接最多试 `PAIR_TRIES`（3）次，码 `PAIR_WAIT_MS`（5 分钟）内有效；受信任设备上点「拒绝」（`lockPrompt.deny`），码立即作废；关掉弹窗（点旁边、Esc、返回，`lockPrompt.hide`）只是不再显示，码照样有效（人看完码顺手关掉弹窗是常事，以前关掉就作废，新设备上输对了也报「错误次数过多」，2026-10-25）。
- **没批成时说原因**：受信任设备结束时回 `no {error}`（`tries` 次数用完、`denied` 被拒绝、`late` 码过期），新设备照它说（`core-misc.lock.pairTries` / `pairDenied` / `pairLate`），连接断了、对方没说原因就说连不上显示安全码的设备（`pairGone`），不再一律说错误次数过多。受信任设备核对通过、却一个 workspace 都没签进去（`approved` 的 `workspaces` 为空，原因在 `failed`）时，新设备不算获批，照 `failed` 说原因（`pairUnsigned`）；以前当成功，弹框一关回到等待页，什么也不说（2026-10-26）。
- **几台受信任设备同时显示码**：输的码每台都核对；没一台批准、却有一台在这之前或这时断开（线断了、app 收起），等待页说「安全码不对，或显示它的设备已断开」（`me.pair.error`），不只说码不对：码多半是那台的（以前只说「安全码不对」，用户照着那台的码再输也没用）。
- **只在一部分 workspace 获批**：新设备同时在几个 workspace 等，答应它的受信任设备只能在其中一些批准（它在别的 workspace 不签名、角色不够）。这次就算完成，其余 workspace 的等待页说「已在 X 获批，在这里还需要此 workspace 的管理员或你在这里的受信任设备批准」（`Trying.approvedIn`；以前那页停在输完码的样子，什么也不说，2026-11-04 网页版「输完不跳」）。
- **批准了、回话丢了**：受信任设备签完、回 `approved` 前线断了（批完切走 app），新设备说失败之前先重读各 workspace 的锁，自己已经在里面就算批准了（以前等 51 秒后说码不对，2026-11-04）。
- **状态**：新设备的进度在 `lock` topic 的 `me.pair`（`finding` / `code` / `checking` / `wrong` / `none` / `failed` / `done`），等待页按它显示输入框、剩余次数或重试。`me.pair.approvers` 是它在这个 workspace 正在连的受信任设备（`LockApprover`：机器和 app 的名字、最近什么时候用过、此刻是否正在显示它的码），正在显示码的在前，其余按最近使用排：等待页拿它告诉人去打开哪一台（2026-11-05 用户：「到底是哪个设备会弹出来呀？」：网页版、没批准过的客户端都不弹）。
- 锁住的 station 拒绝不在锁里的设备时回 `{code: "lock_unconfirmed", lock}`，core 报 `lock_unconfirmed`，说明是哪个 workspace、去哪批和这台的安全码。
- **没有点一下就批的路**（2026-11-02 用户：「为啥现在还能通过被申请设备之间点通过」）：以前留给旧客户端的经 cloud 申请、在 设置 › 安全「待你批准」里核对短码后点「批准」（`lock.request`/`lock.confirm`/`lock.deny`）已从 core 和各端界面删掉：受信任设备上看不到这类申请，也没有批准它们的调用，只能在新设备上输入受信任设备显示的码。cloud 的 `/v1/workspaces/:ws/lock/requests` 和 workspace 视图的 `lock_requests` 为兼容旧客户端还在，新客户端不读也不写。
- 批准、拒绝、续期、移除设备在 cloud 收下条目时就算完成（申请随即撤掉），再在后台把整条链送给锁里的各台 station；cloud 同时通知在线的 station，离线的上线后自己拉。以前要等每台都回话，一台离线的 station 能把一次批准拖上十几秒到几分钟（2026-10-19）。只有 `joinStation`、`addStation` 等那一台 station 的回答。
- 批准由被批准的设备自己带到 station：设备连 station 时，hello 的 `lock` 里多带 `entries`，即锁里把它加进来的那条起到链头的条目（加进来 7 天内，first line 最多 12 KiB；这个人也是 7 天内才成为锁里的成员时，从加他为成员的那条起：station 不收不认识的人的设备）。station 按这台锁拒绝它时，先把带来的条目当普通条目逐条校验、接到自己钉住的链上（不钉新锁，最多 64 条），再判断一次放不放行。带来的条目里没有一条是加这台设备（hello 里证明过的基础公钥）的、或序号接不上 station 的链头时，station 直接不看，一条签名都不验。
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
- 按性质的随机测试（带种子、可重放，失败时报出种子和缩到最短的步骤）：
  - `station/test/lock-world.test.ts`：一个 cloud（`cloud/src/lock.ts` 的 `extendLock`，和 cloud 收条目用的同一段）、三台真 station 代码（cloud.json/lock.json、presence 帧、`planeTeller`、mesh 的 `followLock`、设备 hello 带来的条目）和成员设备，两个 workspace 各有一把锁（三台的 home 一个，其中两台另加入一个），每步随机：签条目（加删设备、改角色、加删 station、关掉安全模式、再打开一条新锁）并送到 cloud 和 station、设备连 station、断开或接回某条线、停或起某台 station、cloud 扣着不发或伪造条目；线上的消息随机延迟、乱序（每条 socket 内保序）、随线断而丢。每步都查：各处的链不分叉、cloud 只存 station 会收的、伪造的条目谁都不收也放不进人、station 只放行它自己的链里有的设备。最后线都接回（cloud 对一部分 station 仍扣着不发，station 之间的线最后才接）再查：各 station 追平最长的链，有 station 连着 cloud 时 cloud 也追平，获批的设备每台都进得去、移除的哪台都进不去。`LOCK_WORLD_SEED=<种子>` 只跑那一个，`LOCK_WORLD_RUNS=<n>` 跑前 n 个。它找出过：station 之间那次拉平失败后，在锁或名单再变之前不再试，cloud 不给它发时被移除的设备一直进得去（现在 `followLock` 失败后 5 秒起翻倍、最长 10 分钟重试）；关掉安全模式前那次批准带的旧链晚到，把 station 重新锁上（现在关过的锁不再钉回）。
  - `client/core-ts/test/lock-pair-faults.test.ts`：面对面批准的两端都是真 core，连接上每条消息随机延迟、在某条之后断开，cloud 存下受信任设备的条目却把回答丢了，人随机输对、输错、输一半、在受信任设备上拒绝或关弹窗、等。查：只有码在时限内输对、没被拒绝、没用完次数时才签进去；输的每个码都有回答；码的时间过了以后新设备要么完成，要么说的原因跟发生的事对得上；受信任设备上不留弹窗；码输对、线没断就一定签进去。`PAIR_FAULT_SEED`、`PAIR_FAULT_RUNS` 同上。线在受信任设备签完、回话之前断了，新设备会先说连不上，等它重读锁（cloud 通知成员 workspace 变了）发现自己已在锁里，等待页就没了。
- 端到端（真进程、真 relay，不进 CI）：`node station/side/lock-e2e.ts`。dev cloud 加 4 台临时 station 和两个真 core（owner 的桌面、新设备），演示 cloud 给自己的设备发凭证、往名单里塞 station、把 station 改绑到别的 workspace、换 grant key（重启 dev cloud 就是换 key），锁住的 station 都拒绝，没锁的照做。

## 界面（第二步）

- core：`lock`、`lockDraft` 两个 topic 和 `lock.*` 调用（`client/core-ts/src/views/lock.ts`），锁记录存在 workspace 的 `lock` 里；workspace 视图多了 `lock`、`lock_requests`，`lock` 变了就重读。core 读到锁、发现这台设备不在里面（开启时没勾上，或之后才加的），就显示等待页，不等 station 拒绝；**不会自己提交申请**（2026-10-19 用户定：要让用户知道，并由要核对安全码的本人发起），只有用户在等待页点「发送批准请求」（`lock.pair`）才发出。station 以 `lock_unconfirmed` 拒绝这台设备后，锁没变前不再连那台 station；锁一变（有人确认了）立刻重试。被安全模式拒绝时凭证本身没问题，重连不再每次向 cloud 领新凭证。
- 桌面/网页：设置 › 安全（`web/src/cloud/Security.tsx`）；开启前核对页 `settings/security/open`；owner 在设置页顶上的一行提示（`lock.dismiss` 关掉，记在 prefs `lockNotice`）；等待确认的设备看到的整页。
- 等待页在首页的位置，顶上仍是首页的顶栏：设置，和 workspace 名称（点开切换 workspace）。手机上没有底栏，以前进了待批准的 workspace 就回不去（2026-10-23）。
- 被安全模式拦下的 station（这台设备未获批 `lock_unconfirmed`，或 station 不接受这个 workspace 的成员 `lock_station`）不显示成离线：link 的 `cause` 是 `lock`，station 列表写「安全模式未放行」，station 页（`blocked`）和对话里写原因。
- 受信任设备上，面对面批准的新设备自己弹出来（`lockPrompts` 的 `pairing`，见「新设备」）：在哪个 workspace 都弹，写明申请访问哪几个 workspace，只显示码和「拒绝」（桌面对话框，手机网页和安卓底部面板），关掉只是收起、码仍有效，点「拒绝」才作废；新设备那边输对码、或被拒绝，弹窗跟着关。被拒绝（或手动关掉）的只是那一次请求（设备加它当时的码）：同一台新设备再发请求，弹窗照样弹（以前要重启 app，2026-10-23）。
- 手机网页（`web/src/mobile/Security.tsx`）和安卓（`screens/Security.kt`）同一套：设置里「安全」一行写现状（等你确认的件数标红），确认设备用底部面板。
- 网页版设备 30 天到期，快到期（5 天内）在「成员和设备」里标出、可续期（`lock.renew`）。过期了的（station 一律拒绝）在 core 里按不在锁里算（`views/lock.ts` `live`）：显示等待页、可以面对面重新批准，station 拒绝时说「尚未获准」并给安全码，不再说「station 尚未收到批准，即将重试」（以前因为锁里还有它，既没有等待页，受信任设备也不肯再批准它）。
- 「成员和设备」要让人认得出哪台是哪台（2026-10-27 用户：「根本看不出哪个是哪个」）：每台的名字是它最近一次向 cloud 领凭证时自己报的（cloud `devices` 的 `label`；桌面写电脑名、手机写系统设置里的名字，宿主经 `client.device` 的 `machine` 告诉 core；网页版只有浏览器和系统），没报过才用批准时记进锁里的；下面一行先说此设备或什么时候用过（`last_seen`：领凭证最多一天一次、在连 station 的路上，所以按天说；31 天里没领过的说超过一个月未使用），不再写客户端/网页版（图标和名字已经说了）。每人的设备按 app 分组（2026-10-27 用户：「应该先显示设备名而不是网页版啥的，不同版直接分组」）：组名是 app（still.fail 桌面版、still.fail 网页版、youdid.wtf Android…，用中文还是英文起的名都算同一个 app，按看的人的语言说），行名只写哪台机器（电脑名、手机名、浏览器 · 系统）；名字是 core 拼的「{品牌} {app} · {机器}」，`prefs.ts` 的 `deviceParts` 照同一套模板拆回去，拆不出 app 的（批准时起的名、没报过名的旧设备）归「其他」。只有一行地方说一台设备时（移除的确认、待批准的请求、开启时的清单）先说机器再说 app。含此设备的组在最前，其余组按组里最近一次使用排；组内此设备在最前，其余按最近使用排。owner、admin 看得到所有人的使用时间，成员只看自己的（cloud 只给成员他自己的设备）。名字和时间来自 cloud，只用来认设备，谁在锁里仍只看签过的条目。
- 此设备是受信任设备时可以移除别的设备（`lock.removeDevice`，owner、admin 任何人的，成员自己的；先确认，说明移除后它要重新批准才能用）。窄排法下「续期」「移除」在名字和说明下面单独一行，不跟名字并排：名字是认设备用的，不能被按钮挤得截断。

## 还没做

passkey 的注册和签名；新设备加入、快到期时用系统通知推送到这个人的其他设备（现在是 app 开着时弹窗，快到期只在页面里显示）。web 发版签名和多地比对哈希另开。在 cloud 改角色（`workspace.setRole`）不签 `member` 条目：锁里的角色不变，提成 admin 的人到 station 上还是原来的角色，也签不了 admin 才能签的条目。
