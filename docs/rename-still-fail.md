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
