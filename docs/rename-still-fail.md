# 改名 still.fail：名字对照和迁移约定

产品从 ember 改名 still.fail（2026-09-29 定）。这份是各部分共用的约定：改代码时照这里的名字，新旧怎么并存也照这里做。

## 名字对照

| 旧 | 新 |
|---|---|
| `ember.3720.org`（app、API、relay） | `app.still.fail`，路径不变 |
| `admin.ember.3720.org` | `admin.still.fail` |
| `preview.ember.3720.org` | `preview.still.fail` |
| 命令 `ember` | `stillfail` |
| `ember-station` / `ember-mesh` / `ember-job` 等程序 | `stillfail-station` / `stillfail-mesh` / `stillfail-job` …（前缀 `ember-` → `stillfail-`） |
| 数据目录 `~/.ember` | `~/.stillfail` |
| 环境变量 `EMBER_*` | `STILLFAIL_*` |
| 请求头 `x-ember-*` | `x-stillfail-*` |
| 路径前缀 `/_ember` | `/_stillfail` |
| 链接 scheme `ember://` | `stillfail://` |
| 安卓包名 `dev.ember.android`（及 `dev.ember.*`） | `fail.still.android`（`fail.still.*`） |
| macOS / 桌面端 bundle id、launchd label `com.*.ember*` 之类 | `fail.still.*` |
| Rust crate / 模块 `ember_*`、`ember-*` | `stillfail_*`、`stillfail-*` |
| TS / Kotlin / Rust 类型名 `Ember*` | `StillFail*` |
| 标识符里的 `ember`（变量、CSS 类、存储 key 前缀 `ember.`） | `stillfail`（存储 key 前缀 `stillfail.`） |

名字里不能有点，所以程序、变量、标识符都写成 stillfail；给人看的产品名写 still.fail。

## 新旧并存（已经装好的不能断）

开源后的产品介绍、当前命令示例、包名与服务显示名称使用 still.fail / stillfail。仓库中仍存在的 `ember` 不都属于漏改：`app://ember` 关系到桌面端已有存储，`ember.db` 和会话/消息字段关系到已有数据，MCP 配置名、旧请求头与 ALPN 关系到混合版本客户端，Cloudflare Worker / bucket 名关系到现有云资源。这些兼容标识和历史迁移记录保留，不能做全仓字符串替换。

1. **cloud 先上、两边都认**：新旧域名都绑在同一个 Worker 上，旧域名长期保留；API 和 relay 的路径（`/v1`、`/relay`、`/ping`、`/healthz`、`/install.sh`、`/releases`、`/.well-known`）不跳转，网页从 2026-09-30 起 302 到新域名同一路径（`cloud/src/web.ts`，通知用的 `/sw.js` 除外）；请求头新旧都接受（先读 `x-stillfail-*`，没有再读 `x-ember-*`）；`/_ember` 和 `/_stillfail` 都响应。cloud 自己对外生成的链接用新域名。
2. **station 升级时自己搬家**：新版第一次启动，如果只有 `~/.ember` 没有 `~/.stillfail`，就把目录整个挪过去，在旧位置留一个指向新目录的软链接；两个都在就用新的，不动旧的。环境变量先读 `STILLFAIL_*`，没有再读 `EMBER_*`。launchd / systemd 服务换成新 label，装新的时卸掉旧的。钥匙串 / 凭据条目读不到新名字时从旧名字复制一份。旧命令名（`ember`、`ember-job` 等）留成指向新程序的软链接，给老脚本和 agent 的习惯用。
3. **客户端**：存储 key 先读新 key，没有再读旧 key 并写到新 key。桌面端 `productName` 改了以后，userData 目录也跟着变，第一次启动时把旧目录的内容搬过来。安卓换包名等于新 app，要重新安装、重新登录，这个躲不掉。`stillfail://` 为主，`ember://` 继续认。
4. 默认连接的 cloud 地址改成 `https://app.still.fail`。
5. 例外：预览的流式请求头客户端仍发旧名 `x-ember-stream`（两个名字都认）。它会经 station 转给本地服务，改名前的 station 只去掉 `x-ember-*`，发新名字会漏过去。

## 上线清单（按顺序）

1. **合进 main**：`rename-still-fail` rebase 到最新 main，冲突解掉，studio 上重跑 `sh scripts/check.sh full origin/main..HEAD`，再 fast-forward 推 main。
2. **Google 登录**：studio 上 `~/ember-deploy/google-oauth.json` 备份成 `google-oauth.ember.json`，把 `google-oauth.still-fail.json` 换上去（新 OAuth 客户端，只登记了 `https://app.still.fail/v1/auth/google/callback`；旧域名上的 Google 登录会先跳到新域名）。
3. **先发 station 安装包**：`scripts/release.sh station`（出 `stillfail-station-*.tar.gz`；旧的 `ember-station-*.tar.gz` 冻结在改名前最后一版，老安装脚本照样能用）。
4. **再发 cloud 全部**：`python3 cloud/deploy.py`（relay → api → web / admin / preview / site）。新增自定义域名 `app.still.fail`、`admin.still.fail`、`preview.still.fail`，证书要等几分钟。验：`https://app.still.fail/healthz`、`/ping`、首页，旧的 `ember.3720.org` 同样能用。
5. **web**：在 `https://app.still.fail` 登录一次（新域名，浏览器里的登录带不过去）。
6. **station**：每台跑一次更新（`ember update` 或 `stillfail update`），升级时自己把 `~/.ember` 搬到 `~/.stillfail` 并留软链接。验：新服务在跑、旧服务已卸、会话和历史都在、`stillfail-job` / `ember-job` 都能用。
7. **桌面端**：在 studio 本机终端（ssh 里签不了名）跑 `scripts/release.sh desktop`；MBA 上装新的 still.fail.app，删掉旧 ember.app（登录状态从旧数据目录自动搬过来）。旧 app 不再有更新。
8. **安卓**：`scripts/release.sh android`；手机上装新 app（包名 `fail.still.android`），登录，删掉旧 app。确认 `assetlinks.json` 里的签名指纹对得上。
9. **以后**：youdid.wtf 买了、接到 Cloudflare 后加进 `cloud/wrangler.site.jsonc` 重发官网。

## 现在的状态

已上线（2026-09-30）。以后新写的代码直接用新名字，上面「新旧并存」的兼容长期保留。

## 上线经过（2026-09-30）

- main `d9b03e1`；station 安装包 `stillfail-station-*` 已上传；cloud 全部部署，`app` / `admin` / `preview.still.fail` 都已生效；Google 登录换成新的 OAuth 客户端。
- station：claude-mac（mini2 虚拟机）、Studio（从检出目录跑，`~/bin/ember-deploy` 改用 `~/bin/stillfail-restart-station.sh` 重启）、bft/Office-VM-1 都已搬到 `~/.stillfail`。
- 安卓 0.1.1123 已发（包名 `fail.still.android`）。
- 桌面端 0.1.1123 在 studio 本机终端签名发布：约 957 个文件带时间戳签名，要 15 分钟左右；那个终端里的上传没进 bucket，后来从 ssh 重新上传。
- MBA 和 mini1 装上新的 still.fail.app 后切换。

## Removing the remaining deployment names (2026-10-02)

Production resources are migrated separately from wire compatibility. Never change a
Worker name and replay its `new_sqlite_classes` on an existing installation: that
creates empty namespaces. `cloud/migrate-workers.py` prepares the new API/relay,
seeds existing secrets, transfers the classes, and verifies every namespace ID.
It changes no routes. `cloud/cutover-worker.py` then updates the existing route IDs,
records them, and supports `--rollback` to the preserved former Worker. Both tools
are read-only unless `--apply` is specified. Their `--report` files are private
operator state outside the repository. The grant signing key must match production.

`cloud/migrate-releases.py --copy --report <private-file>` copies the entire release
bucket, including private feedback attachments, using a temporary authenticated
edge preview. It checks SHA-256, size and metadata on every object and never deletes
the source. Default mode inventories; `--verify-only` checks without writing.
A final delta pass and uploader cutover are required before retiring the source.
Keep reports and rollback resources until all callers have switched and the final
verification passes; an initial successful copy alone is not a completed cutover.

Protocol aliases have a different retirement condition: all supported clients and
stations must read the new identifiers first, all new writes must use them, then
wait for old credentials (up to 30 days), active jobs and handed-over agent processes
to expire or restart. Historical transcripts, exported links and migration readers
remain readable. They are archival compatibility, not permission to keep issuing
old identifiers in new data. Old deployment resource names do not need to remain
forever once their live bindings, uploaders and rollback window have ended.
