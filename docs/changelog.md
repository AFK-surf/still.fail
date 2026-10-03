# 更新日志（changelog）

用户在 app 里看到的「更新日志」，以及反馈（FB-n）修好、上线后回告提反馈的人。

## 写法：合并时在提交信息里写

合进 main 的提交，在末尾的 trailer 里加：

```
Changelog: 修复：很长的对话标题会把侧栏撑宽
Changelog: 新功能：会话可以置顶
Fixes: FB-12
Session: ember:c-…
```

- `Changelog:` 一行给用户看的中文，可以写多行（每行一个 `Changelog:`）。用「修复：」「新功能：」或「手机：」「安卓：」这类开头，说用户感受得到的变化，不写实现。CI、重构、文档、测试这类用户感觉不到的不写。
- `Fixes: FB-n` 说这个提交修的是哪条反馈（可以写多个）。只写 `Fixes` 不写 `Changelog`，反馈照样会被标成已修复，但日志里不显示。
- 版本是这个提交在 main 历史里的序号（`git rev-list --count`，各端的 `0.1.<n>` 就是它），不用手填。
- 归哪一端，看提交改了哪些目录（scripts/changelog.ts `PARTS`）：`station/src/`、`station/native/` 归 station（之前的提交里 `mesh/` 也是），`web/` 归网页版（桌面 app 带着网页，也算），`client/` 归网页和安卓，`apps/android/` 归安卓，`apps/desktop/` 归桌面，`cloud/src/` 归云端（一部署就上线）。其余（官网、文档、脚本）不需要发版。
- 写错了或漏写了：在 `docs/changelog-notes.json` 里按提交号（至少 7 位）补或改：`{ "<提交>": { "text": [...], "fixes": [...] } }`，它的 `text` 会替换提交里的那几行。

## 正式版的日志：每次正式发布写一份

上面那些逐个提交的条目是测试版的日志。正式版用户隔一阵才更新一次，看的是一次发布一条、重新写过的日志：`docs/releases/0.1.<n>.md`。

```
---
version: 1400          # 这次发布从哪个提交构建：各端都发到这个版本（或更新）
date: 2026-10-02
parts: [web, station, android, desktop, cloud]   # 这次发出去的端
---
- 新功能：……
- 改进：……
- 修复：……
```

- 正式发布时，agent 先跑 `node scripts/changelog.ts --draft`，拿到上次正式版之后测试版的所有条目（从旧到新，带版本、端和 FB 号），据此重写：按「新功能 / 改进 / 修复」分组，合并说同一件事的多条，去掉中间态（改了又改的只留最后的样子，修的是测试版里自己刚引入的问题就不写），用正式版用户看得懂的话写，不提测试版。只有 `- ` 开头的行会显示。
- 稿子发到 chat 里给人看，认可后和这次发布一起合进 main，再转正和发正式版 app。各端要从同一个提交发（`version` 就是它），app 才能准确说出「你的版本已包含」。
- 合进 main 后，CI 用 `node scripts/changelog.ts --stable` 把这些文件拼成 `changelog-stable.json` 放进 releases 桶。cloud 给正式通道（app.still.fail、不带测试版标记的 app）读它，给测试通道读 `changelog.json`。还没有任何一份正式版日志时，正式通道也读测试版的。每条的 `fixes` 是它和上一次正式发布之间测试版条目里的 FB 号，只用来展示：反馈标成已修复，仍然按测试版的逐提交记录来判断。
- `scripts/check.sh` 改到 `docs/releases/` 时会照 CI 的读法读一遍，格式不对就不让提交。

## 怎么到用户那里

- `node scripts/changelog.ts` 从 main 的历史生成 JSON（新的在前）。CI 的 pipeline 在 main 每次部署完（api 没失败）跑它，把结果放进 releases 桶的 `changelog.json`。
- cloud `GET /v1/changelog`（cloud/src/changelog.ts，谁都能读）给 `{ entries, released }`。`released` 是这个通道（按域名或 `x-stillfail-channel`）各端已经发出去的版本，来自更新器读的那些文件：`station(-beta).json`、`android/(beta/)latest.json`、`desktop/stillfail(-beta)-mac.yml`，以及 deploy.py 部署或转正网页时写的 `web(-beta).json`（取自构建出的 `build.json`）。
- core 的 `changelog` topic（client/core-ts/src/changelog.ts）显示时最多每小时读一次，存在本机。它按这个 app（`client.device` 说的 app 和 build）算出每条的 `has`/`note`：你的版本已包含、更新到 0.1.n 后就有、还没发布、已发布、已上线。`news` 是这次更新带来的、这个 app 的改动（上次看过的 build 之后、当前 build 之前），一直显示到 `changelog.seen`；第一次见到的 build 不算更新。
- 界面：PC 设置 →「更新日志」（web/src/pages/Changelog.tsx），侧栏底部的「已更新到 …」卡片；手机 web 和安卓在设置 →「更新日志」，首页列表顶上有卡片（web/src/mobile/Changelog.tsx、screens/Changelog.kt）。打开日志页或点 × 就算看过。

## 反馈修好了，告诉提的人

- cloud 读到 changelog 里的 `Fixes: FB-n` 后（station 来问时，或 admin 打开反馈列表时），把那条反馈记成 `fixed`，并记下 `fixed_in`（版本）和 `fixed_parts`。被标成 wontfix 的不动。
- 正式通道的 station 启动 5 分钟后、之后每小时 `POST /v1/feedback/fixed` 一次（station 签名，tag `stillfail-station-feedback-fixed-v1`）。cloud 只回这台 station 发的、已修复、修复在反馈所在通道上**都已发布**（每一端的 released ≥ fixed_in；云端的部署了就算）、还没告诉过的。
- station（station/src/tools/feedback.ts `tellFixed`）把每条作为 via="ember" 的消息交给当初发反馈的会话：FB 号、标题、修在哪些端的哪个版本，修在 station 上的还会说这台 station 是否已经是那个版本，让 agent 在当初那个 thread 里用对方的语言简短告诉提反馈的人。然后带上 `told` 再请求一次，cloud 记下 `told_at`，以后不再给。会话已经没了的，也算告诉过。
- 新旧混跑：旧 cloud 没有这两个接口，station 每小时打一行 warn，core 读不到日志页就显示「读不到更新日志」；旧 station 不来问，反馈照样会被标成已修复，只是不会回告；旧客户端没有这个页面。
