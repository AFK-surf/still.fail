# station 的模块：旁边的独立进程

2026-10-19。模块是跑在 station 旁边的独立程序（第一个是媒体库：照片、视频、电子书），给成员多一块能用的东西，但不进 station 的代码。station 只多一层通用的：启动和看着它们、把 admin API 的一段路径转给它们、给它们一个本机接口读 drive。代码在 `station/src/modules/`，组合根（`main.ts`）里是 `Modules`（有哪些模块、各自现在怎样）、`StationDrive`（drive，admin API 和本机接口共用一个）、`ModulePackages`（station 自己装的模块包，`modules/packages.ts`：agents 那边把它加进自己的 updates，一起读、一起显示）和 `ModulesLive`（生命周期）。

## 配置与生命周期（modules/live.ts）

config.json：

```json
"modules": [
  { "id": "media", "package": "media" },
  { "id": "mine", "command": "/path/to/mine", "args": [], "env": {}, "enabled": true }
]
```

- `id`：`^[a-z][a-z0-9]{0,31}$`（和客户端 core 的模块名一样，没有连字符），不能重复。不合规的那一条记一行日志、跳过，其余照常。`enabled: false` 的不启动。
- `command` 和 `package` 必须有且只有一个：`command` 是已经装在机器上的程序；`package` 是 station 自己去下载、校验、安装、更新的模块包（下面「包」），名字的规则同 `id`。`args`、`env` 两种都可以有（包的 `args` 跟在入口文件后面）。
- 启动时机：上一个 station 进程已经退出之后（交接时两份同时跑会抢模块的数据）。config.json 改了（页面上改、或文件被别人改后读到）会重新对一遍：不再列出的停掉，改了的按新的重启，新加的启动。
- 每个模块是一个独立进程组（它启动的东西随它一起结束），工作目录和自己的目录都是 `<data>/modules/<id>`（0700）。它拿到的环境变量（在 station 自己的环境和 `env` 之上）：

| 变量 | 是什么 |
|---|---|
| `STILLFAIL_MODULE_ID` | 它的 id |
| `STILLFAIL_MODULE_DIR` | `<data>/modules/<id>`，它的数据放这里 |
| `STILLFAIL_MODULE_SOCKET` | 它要监听的 unix socket（`<dir>/module.sock`），HTTP/1.1 |
| `STILLFAIL_STATION_SOCKET` | station 给它的本机接口（`<dir>/station.sock`，0600） |
| `STILLFAIL_STATION_TOKEN` | 调本机接口用的令牌，每次启动都换 |

- 输出（stdout、stderr）追加到 `<dir>/log`，超过 10 MB 时启动前挪到 `log.1`。
- stdin 是 station 持有的管道：读到 EOF 说明 station 没了（比如崩了），模块应自己退出。正常停止时 station 先发 SIGTERM，5 秒后 SIGKILL。
- 退出了就重启：1 秒、2 秒、4 秒……最多隔 1 分钟（`Schedule`）。
- 启动后 station 反复 `GET /manifest`（先密后疏，最多 2 秒一次），答了（200，或 404 = 没有 manifest）才算在跑；在跑之前转发一律 503。
- 只在 macOS 和 Linux 上跑（靠 unix socket）；Windows 上配了也不启动，记一行日志。

## 包（modules/packages.ts）

`package: "<p>"` 的模块由 station 自己装：和 station 自更新同一个发布地址（控制面的 release base：still.fail cloud 的 origin，Comma 的 `<origin>/stations`）、同一个渠道、同一把签名 key（[release-signing.md](release-signing.md)）。

- **打包**（`scripts/module-bundle.ts`）：模块的目录里放一个 `module.json`：`{id, entry, files, needsStation}`，媒体服务的是 `media/service/module.json`：`{"id": "media", "entry": "src/main.ts", "files": [], "needsStation": …}`。打包时用 esbuild（station 自己构建用的那个，`station/package.json`）把 `entry` 和它 import 的一切打成一个普通的 ES module `main.mjs`（`platform: "node"`、`format: "esm"`、`target: "node22"`，Node 自带的模块留给运行时，`legalComments: "none"`，没有时间戳，路径都是相对的）：运行时不需要会去掉 TypeScript 类型（桌面版的 Electron、老一点的 Node 都能跑），也不带 node_modules。`files`（文件，或整个目录，隐藏文件除外，不能叫 `main.mjs`、`module.json`）原样放在旁边。包里的 `module.json` 形状不变，写成 `{id, entry: "main.mjs", files: ["main.mjs", …files], needsStation}`。这些打成一个只含普通文件的 tar.gz（`station/src/updates/archive.ts`，和桌面版的网页包同一个格式：按路径排序，同样的文件得到同样的字节），不分平台。版本是 `0.1.<build>`，build 取最近一次改动了打进去的东西（`module.json`、entry 所在的目录、`files`）或打包方式（`module-bundle.ts`、`archive.ts`、`station/pnpm-lock.yaml` 里的 esbuild）的提交，所以之后的提交、正式渠道再打一次，都是同一个版本、同样的字节。
- **发布**：`modules/<p>/<p>-0.1.<build>.tar.gz`（按版本命名，cloud 永久缓存）和 feed `modules/<p>/<p>.json`（正式）、`<p>-beta.json`（测试），都在 `/releases/` 下。CI：main 上改了某个模块打进去的东西（`module-bundle.ts plan`）时 `pipeline.yml` 的 `modules` job 打包、签 beta feed（包先传，feed 由 `put` 在检查通过后传）；「Publish stable」的 `modules` job 在 station 之后签正式 feed。已经发过的版本（另一个渠道的）只核对字节相同，不覆盖。
- **安装**：config 里出现一个还没装的包，station（上一个 station 进程退出后）马上去取；之后每次 station 读自己的更新时（`updates.ts`，每几个小时，页面上「检查更新」时）一起读。读 feed → `verifyModule` 验签（kind `stillfail-module-release`、id 是这个包、版本一致）→ 比已装的新才装，`needsStation` 比这台 station 的 build 新就不装（overview 上的 note 说要先更新 station，这一行这时不算可更新，免得客户端的「全部更新」在 station 之前卡在它上面；不是正式发布的 station，比如源码目录跑的，不查这一条）→ 下载 `builds[本机平台] ?? builds.any`，边下边核大小，下完核 sha256 → 解到 `<data>/modules/<id>/app/.<build>-<随机>`（只接受普通文件、不越出目录，`module.json` 要指明一个包里有的 `entry`）再整个改名成 `app/<build>` → 整个写 `app/state.json`（`{package, current, previous, ran, failed}`）切过去 → 模块按新的重启。新版自动装，不看 `autoUpdate`（模块重启不打断 agent）。
- **运行**：命令是 station 自己的 Node（`process.execPath`；桌面版里是 Electron，带 `ELECTRON_RUN_AS_NODE=1`），参数是 `[<app>/<build>/main.mjs, ...args]`（包里 `module.json` 的 `entry`），其余同上。`app/` 是 station 的，模块自己的数据别放那里。
- **回退**：保留上一个 build。新 build 连续 3 次在答 manifest 之前就退出（从没起来过），退回上一个（记进 `failed`，这个 build 以后不再装；目录删掉），页面上显示「没能启动，已退回」。
- **数据比代码新的不跑**：`ran` 记着起来过（答了 manifest）的最新 build。比 `ran` 旧的 build 永远不会再跑，不管是 feed 给的（比如从 beta 切回正式渠道，正式的更旧：不装，和 station 自己不同）还是回退：模块可能已经把数据迁到了新版（媒体库 `media.db` 的 `user_version`），旧代码读不了。所以只能往前；要旧代码就得发一个更新的 build。
- **概览**：每个用包的模块在 overview 的 `updates` 里一行 `module:<id>`（`SoftwareVersion`：已装的版本、最新、是否在装、失败的原因），客户端照通用的一行显示；`POST /updates {id: "module:<id>"}` 立刻读一次并安装更新的。
- 只读 `releases/modules/…`：Comma 那边要在 `<origin>/stations/releases/modules/…` 原样提供同样的文件，station 才能从 Comma 装包。

## 转发（modules/forward.ts）

`/admin/api/m/<id>/<rest>?<query>` 原样转给模块：`<method> /<rest>?<query>`。转发在 admin API 里（`Admin.answer`），经 mesh 来的和别处进到 admin API 的都一样；只读门、幂等键照常先过。

- 请求体边来边转（mesh 那边不先收全，也不受 64 MB 的上限），响应的状态、头、体也边来边回：视频分段、缩略图、长时间的 SSE 都行。调用方走了（流断了），给模块的请求随之结束。
- 加头 `stillfail-viewer`：station 验过的成员 `{sub, email, name, role, workspace, home}`，JSON，非 ASCII 字符转成 `\uXXXX`。客户端自己带的 `stillfail-viewer` 被丢掉；hop 头和 `accept-encoding` 也不转（压缩是 station 对客户端做的，mesh/compress.ts）。
- 没有这个模块：404 `{error}`；没在跑或没答：503 `{error}`。
- 凭证、吊销、workspace 锁都还是 station 管，模块只看身份，不碰 iroh。按 workspace 隔离数据是模块的事，依据就是 `workspace` 和 `home`。

## 只读成员（viewer）的写

viewer 照旧只能读（GET/HEAD）。模块可以在 manifest 里声明 viewer 也能做的写（比如存自己的阅读进度）：

```json
{ "viewerWrites": ["/progress/[^/]+", "/notes(/[^/]+)?"] }
```

每一条是正则，匹配 `/m/<id>` 之后的**整条**路径（station 自己加 `^(?:…)$`），任何方法。只对这个模块、只在它在跑时生效；不在其中的写照旧 403。

## 本机接口（modules/local.ts）

模块经 `STILLFAIL_STATION_SOCKET` 调 station，每个请求要带：

- `authorization: Bearer <STILLFAIL_STATION_TOKEN>`，不对 401；
- `stillfail-viewer`：它在替谁做事，就是转发时给它的那个原样带回来，缺了 400。

station 按这个成员套用 drive 的规则（docs/drive.md）：viewer 只能到自己 workspace 钉住的文件夹，能写的成员哪里都能到，station 自己的数据永远不可达，macOS 受保护的文件夹经 still.fail Helper。只读，只有 GET：

| 接口 | 答 |
|---|---|
| `GET /drive/list?root&path` | 同 admin API |
| `GET /drive/stat?root&path` | 同 admin API |
| `GET /drive/read?root&path&offset&length` | 同 admin API：一次最多 8 MB，`stillfail-total`、`stillfail-mtime` |
| `GET /drive/watch?root&path&id` | 同 admin API 的长轮询：有变化就答 `{changed: true}`，否则约 25 秒后 `false` |
| `GET /thumb?root&path` | 图片（png/jpg/jpeg/webp）的缩略图（长边最多 720×600，原生 thumbs.rs 做的）；图片本身很小（≤24 KB）就给原图。头里带 `stillfail-thumbhash`（base64）、`stillfail-width`、`stillfail-height`，是给出去的这张的。不是图片 404 |
| `GET /poster?root&path` | 视频的封面（JPEG，QuickLook 或 ffmpeg）。做不出来 404 |

拒绝和 admin API 的 drive 一样：`{error, code}`，状态码按 code。缩略图和封面放在 `<data>/thumbs/drive`，按文件的路径命名，文件比它新就重做。Helper 后面的文件 station 自己不打开：先由 Helper 拷一份到 station 自己的目录，做完就删。

写 drive 的事模块不经本机接口做：它要以成员的身份写，就让客户端调 admin API 的 drive。

## 概览

至少配了一个模块时，overview 多一个 `modules: [{id, running}]`，客户端据此显示入口；变了照常推 `overview` 事件。没配模块时 overview 和以前一样。

## 还没做的

- 旧的模块包不会从发布桶里清掉（`release-prune.ts` 不碰 `modules/`）。
- 缩略图只有一个尺寸（原生件里写死的 720×600），要别的尺寸得改 thumbs.rs、重新发原生件。HEIC 不在原生支持的格式里。
- `<data>/thumbs/drive` 不会自动清理。

## 进程内的部分（parts.ts）

和聊天、agent 绑得紧的功能（库、事件流、hub），不单独起进程，而是作为 station 进程里的一个「部分」：一个由组合根（`main.ts`）点名的 layer，在平台和 agents 之后构造，构造时经 `Parts` 服务说清自己往哪些面上加了什么：

- `routes`：管理 API 的路由，排在平台自己的之后；
- `viewerMay`：只读成员可以对它做的写（比如自己的标记）；
- `overview`：overview 里的字段，一个字段只能有一个部分说；
- `tools`：给 agent 的 MCP 工具。

这些都在被用到的时候才读（每个请求、agent 每次列工具），所以先构造好的管理 API 和 agents 也能拿到。没有全局注册表：一个部分在不在 station 里，只看 `main.ts` 有没有列它。

第一个搬过来的是 vault（`vault/module.ts`）：自带的表、两组路由、agent 的 secret 工具、`vault-request` 事件都由它自己挂上，agents 和管理 API 里不再有 vault 的代码。

## 用到就装上，也能在 app 里开关（api/routes/modules.ts）

still.fail 做的模块（`modules/catalog.ts`）不用任何人去开：`/m/<id>/…` 第一次被请求而 config.json 里还没有它时，station 自己写上 `{id, package: id}`，照常下载、验签、启动，这期间请求答 503 `{code: "module_starting"}`，客户端过一会儿再问（媒体模块的事件流本来就每 5 秒重连，连上就把显示着的 topic 重读一遍）。owner 和 admin 关掉过的（`enabled: false`）不会这样被装回来。

开关也不用人去改 config.json：`GET /modules` 列出 still.fail 做的模块（`modules/catalog.ts`，目前只有 media）和 config.json 里配了的，每个带 `{id, offered, enabled, installed, running, version}`；`PUT /modules/<id> {enabled}`（只有 owner 和 admin）由 station 自己改 config.json：清单里的模块第一次打开就写成 `{id, package: id}`，关掉就是 `enabled: false`，再打开去掉它。之后照常按 config 的变化下载、验签、启动或停止。core 的 op 是 `station.modules` 和 `station.module.set {id, enabled}`。

