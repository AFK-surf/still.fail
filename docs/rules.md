# 规则（rules/，MoonBit）

安全模式（和以后的密钥库）的判断规则写在一份 MoonBit 代码里，编成 JS（`rules/js/rules.js`，提交进仓库）。station 的锁（`station/src/cloud/lock.ts`，cloud 也用它）和设备上的锁检查（core 的 `vault/lock-check.ts`，交出密钥库的钥匙前用）都只调用它，所以设备拒绝的正是 station 拒绝的。其中能证明的部分用 `moon prove` 证明（2026-11-04 用户：「研究一下怎么给密钥库和安全模式搞证明」「拎出来用其它语言实现」）。

## 包
- `rules/src/form`：记录的规范化 JSON（键按 UTF-16 码元排序、无空白、只收安全整数，字符串照 `JSON.stringify` 写）和条目哈希的原文。和 `client/core-ts/src/lock-form.ts` 逐字节一致。
- `rules/src/role`：角色取低、谁能签哪类记录。`proof_enabled`：`role.mbtp` 写着要证的性质（取低不会提权；只有 owner/admin 管成员、名单；只有 owner 动 owner、cloud 的钥匙和关锁；成员只能动自己的设备和 passkey），`moon prove` 证明。
- `rules/src/lock`：`station/src/cloud/lock.ts` 的 `genesis`/`apply`/`fold`/`signer`/`admit`，同样的结果、同样的报错文字。哈希和签名由调用方给（`Crypto`：station 用 node 的，设备用 @noble 的）。
- `rules/src/vault`：`station/src/vault/crypto.ts` 的 `certOk`/`vaultOk`/`itemOk`/`browserListingOk`/`signerOf`：哪张 box 证书算锁里本人的 app 设备、密钥库和条目的新版本能不能接在已存的后面（含别的 station 带来的副本），同样的报错文字。锁只读成员、设备（谁的、哪类、签名钥匙、是不是本人的）和每台设备有过的签名钥匙；签名由调用方验。
- `rules/src/js`：给 JS 调用的入口（`canonical_of`、`entry_text_of`、`lower_role`、`fold_js`、`admit_js`；`genesis_js`、`apply_js`、`fold_held_js`、`signer_js`、`admit_one_js` 把规则自己的状态交给 JS 收着，下一条记录再交回来，JS 那边拿到的状态只是读的副本），直接读 JS 的值，不再自己解析 JSON（MoonBit 的 JSON 解析不收落单的代理对转义，`JSON.parse` 收）。

## 对照
- `station/test/rules-lock.test.ts`：对照的是换掉之前的 TypeScript 规则（`station/test/lock-oracle.ts`，证明覆盖全之前留着）。随机生成的链（每条随机种类、形状对或不对、签名者在不在锁里、接不接得上链头），每个前缀两边折出同样的状态或同样的报错，每台设备放行与否两边一样。
- `station/test/rules-vault.test.ts`：随机锁上随机的 box 证书、密钥库版本、条目版本（有的形状不对、签名者不该签、签名伪造），作为下一版和作为副本，两边答案和文字一样（对照 `station/test/vault-oracle.ts`）；证书、密钥库、条目各自收和拒都要够多。
- `client/core-ts/test/lock-rules.test.ts`：同样的随机链（`station/test/lock-chains.ts`）交给设备的检查（@noble 的签名校验），每个前缀收或拒、拒的文字、成员、设备、passkey、每把钥匙的签名者都和旧 TypeScript 规则一样。
- `client/core-ts/test/rules-moonbit.test.ts`：规范化 JSON 的测试值和 5000 个随机值逐字节一致；角色取低一致。
- `rules/hermes-check.sh`：照 core 给 Hermes 打包的做法（esbuild + Babel 的 class 转换，Hermes 0.81 不认 class）打包后在 Hermes 里跑，输出和 Node 一样。

## 构建和证明
- `sh rules/build.sh`（`MBUI_TOOLS` 同 mbui 的脚本）：编成 JS，复制到 `rules/js/rules.js`。改了 `rules/src` 要重编并提交 `rules/js`；CI 的 `rules` 工作流核对两者一致。
- `moon prove`（在 `rules/` 里）：要 Why3 1.7.2（opam 装）和一个求解器（z3 即可）。

## 写证明的坑
- MoonBit 翻成 WhyML 时**不加括号**：`a && (b || c)` 翻出来是 `a /\ b \/ c`，意思变了。每个公式只用一种连接词，其余拆成具名的 `predicate`。
- `by` 是 WhyML 的关键字，不能当参数名。
- 证明失败只说超时，不给反例。
