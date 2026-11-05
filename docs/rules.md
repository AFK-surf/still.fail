# 规则（rules/，MoonBit）

安全模式（和以后的密钥库）的判断规则写在一份 MoonBit 代码里，编成 JS（`rules/js/rules.js`，提交进仓库）。station 的锁（`station/src/cloud/lock.ts`，cloud 也用它）和设备上的锁检查（core 的 `vault/lock-check.ts`，交出密钥库的钥匙前用）都只调用它，所以设备拒绝的正是 station 拒绝的。设备信不信一个密钥库版本、一张 box 证书、一个条目（core 的 `views/vault.ts`）也按 station 的规则：密钥库版本照 `vaultOk` 检查别的 station 带来的副本那样查（2026-11-04 用户选「换成 station 的规则」），不合的不显示、不用。其中能证明的部分用 `moon prove` 证明（2026-11-04 用户：「研究一下怎么给密钥库和安全模式搞证明」「拎出来用其它语言实现」）。

## 包
- `rules/src/form`：记录的规范化 JSON（键按 UTF-16 码元排序、无空白、只收安全整数，字符串照 `JSON.stringify` 写）和条目哈希的原文。和 `client/core-ts/src/lock-form.ts` 逐字节一致。
- `rules/src/role`：角色取低、谁能签哪类记录。`proof_enabled`：`role.mbtp` 写着要证的性质（取低不会提权；只有 owner/admin 管成员、名单；只有 owner 动 owner、cloud 的钥匙和关锁；成员只能动自己的设备和 passkey；别人替你加的设备什么时候算「本人的」，以及你已经有本人设备时 owner/admin 加的不算；锁里一直留着 owner：改角色、移人恰好在还剩一个 owner 时才收；别人替你加的设备签的记录不改锁；同一把钥匙先算本人设备的，过期的、不是成员的设备不签；连接放行恰好在设备找得到、是这个人的、没过期、人还在锁里时；密钥库只认锁里成员本人的 app 设备签的版本，主人的签密钥库、成员的签条目；别人替加的设备拿不到新的密钥库钥匙，证书用设备现在的钥匙签（读已存的旧版本时可以是它用过的）；每台设备一把钥匙、只给成员的设备），`moon prove` 证明。每条都证了两个方向。
- `rules/src/history`：记录的版本怎么接（锁的条目、密钥库和条目的版本都用它）。`proof_enabled`：`history.mbtp` 证明下一版正好是已存的加一，别的 station 带来的副本只收更晚的；去掉成员或设备一定换新的密钥（epoch 变大），epoch 不倒退；删掉的密钥库一直是删掉的；条目写在密钥库当前的 epoch 下（删除和副本除外）；删掉的条目不能再接着写；过期的设备不放行；同号的两版（两台 station 同时各写了一版）大家留同一版：删除的优先，其次 epoch 大的，最后全文大的。每条都证了「检查通过 ⇔ 规则成立」两个方向；故意改错一条（去成员不换钥匙）证明就失败。
- `rules/src/lock`：`station/src/cloud/lock.ts` 的 `genesis`/`apply`/`fold`/`signer`/`admit`，同样的结果、同样的报错文字。哈希和签名由调用方给（`Crypto`：station 用 node 的，设备用 @noble 的）。
- `rules/src/vault`：`station/src/vault/crypto.ts` 的 `certOk`/`vaultOk`/`itemOk`/`browserListingOk`/`signerOf`：哪张 box 证书算锁里本人的 app 设备、密钥库和条目的新版本能不能接在已存的后面（含别的 station 带来的副本），同样的报错文字。锁只读成员、设备（谁的、哪类、签名钥匙、是不是本人的）和每台设备有过的签名钥匙；签名由调用方验。
- `rules/src/js`：给 JS 调用的入口（`canonical_of`、`entry_text_of`、`lower_role`、`fold_js`、`admit_js`；`genesis_js`、`apply_js`、`fold_held_js`、`signer_js`、`admit_one_js` 把规则自己的状态交给 JS 收着，下一条记录再交回来，JS 那边拿到的状态只是读的副本），直接读 JS 的值，不再自己解析 JSON（MoonBit 的 JSON 解析不收落单的代理对转义，`JSON.parse` 收）。

## 对照
- `station/test/rules-lock.test.ts`：对照的是换掉之前的 TypeScript 规则（`station/test/lock-oracle.ts`）。证明只管上面那些判断；记录的形状怎么读、报错怎么写、判断按什么先后，证明管不到，靠这些对照测试，所以旧规则一直留着。随机生成的链（每条随机种类、形状对或不对、签名者在不在锁里、接不接得上链头），每个前缀两边折出同样的状态或同样的报错，每台设备放行与否两边一样。
- `station/test/rules-vault.test.ts`：随机锁上随机的 box 证书、密钥库版本、条目版本（有的形状不对、签名者不该签、签名伪造），作为下一版和作为副本，两边答案和文字一样（对照 `station/test/vault-oracle.ts`）；证书、密钥库、条目各自收和拒都要够多。
- `client/core-ts/test/lock-rules.test.ts`：同样的随机链（`station/test/lock-chains.ts`）交给设备的检查（@noble 的签名校验），每个前缀收或拒、拒的文字、成员、设备、passkey、每把钥匙的签名者都和旧 TypeScript 规则一样。
- `client/core-ts/test/rules-moonbit.test.ts`：规范化 JSON 的测试值和 5000 个随机值逐字节一致；角色取低一致。
- `rules/hermes-check.sh`：照 core 给 Hermes 打包的做法（esbuild + Babel 的 class 转换，Hermes 0.81 不认 class）打包后在 Hermes 里跑，输出和 Node 一样。

## 构建和证明
- `sh rules/build.sh`（`MBUI_TOOLS` 同 mbui 的脚本）：编成 JS，复制到 `rules/js/rules.js`。改了 `rules/src` 要重编并提交 `rules/js`；CI 的 `rules` 工作流核对两者一致。
- `moon prove`（在 `rules/` 里）：要 Why3 1.7.2（opam 装）和一个求解器（z3 即可）。CI 的 `rules` 工作流每次改到 `rules/` 都跑一遍，证不出来就红：`tools` 每个 MoonBit 版本做一次证明工具（moonc-prove 和 opam 装的 Why3 1.7.2，放进 Actions 缓存；各 job 共用的 MoonBit 里删掉了 moonc-prove），`proved` 取出来跑；`planted` 同时跑 `rules/planted.sh`：把证过的规则逐条故意改错（最后一个 owner 能被移走、过期设备能签、别人替加的设备拿到钥匙……），各在一份副本里依次证（并排跑时 why3server 偶尔卡住不动），外加一份原样的副本必须证得出，每一处都要证不出来，有一处还证得出来就红（说明那条证明没管住它该管的）。改了被改错的那几行要跟着改脚本。

## 协议（Tamarin，2026-11-05）
`rules/protocol/lock.spthy` 把锁、面对面批准和库钥匙的封装写成消息往来，攻击者握着整个网络（cloud 和问的那台以外的所有 station：读、扣、重放、伪造任何消息），还能拿下任意设备的钥匙（Reveal）。rules/src 证的是每个判断，这里证的是这些判断在恶意网络上拼起来仍然管用：station 收的每把钥匙，签它的若是设备自己的钥匙，就是那台设备批准的（或它被拿下）；批准的只会是亮过码的那台新设备的钥匙；库钥匙封给设备自己的钥匙时，封的是它自己认证过的箱钥匙，它没被拿下就没人学得到。整条链由每一步归纳得出（Tamarin 自己顺着链找停不下来，所以只让它证每一步，归纳写在模型开头）。没建模的：角色和谁能签哪类记录（rules/src/role 证了）、移除、版本和 epoch（rules/src/history）、passkey、密码学本身（这里当完美的）。

`sh rules/protocol/check.sh`（PATH 上要有 tamarin-prover 和 maude，`MAUDE_LIB` 指到 Maude 的目录）：每条引理各证一遍，再把三处判断各改错一份（station 收没签名的记录、没看码就批准、封给没人认证的箱钥匙），每份都要被 Tamarin 找出攻击。CI 的 `rules` 工作流 `protocol` 跑它，约 15 秒，Tamarin 1.12.0 和 Maude 3.5.1 从各自的 GitHub release 取、进缓存。

## 写证明的坑
- MoonBit 翻成 WhyML 时**不加括号**：`a && (b || c)` 翻出来是 `a /\ b \/ c`，意思变了。每个公式只用一种连接词，其余拆成具名的 `predicate`。
- `by` 是 WhyML 的关键字，不能当参数名。
- 证明失败只说超时，不给反例。
- `.mbtp` 里没有 `↔`：写成「通过 → 规则」和「规则 → 通过」两个谓词再用 `&&` 连起来。
