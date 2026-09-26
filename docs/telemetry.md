# 遥测：PostHog

ember 用 PostHog（美国区，`https://us.i.posthog.com`）做产品分析、错误追踪和会话回放。这是我们对自己用户的第一方分析：用 ember 的就是团队自己，所以没有同意弹窗。链路追踪另走 Axiom，不在这里。

**什么都不带内容**：聊天文字、引用、文件名、提示词、agent 的输出、对话标题，一样都不发。发出去的只有动作、计数、耗时和错误（带调用栈）。

## 网页版（ember.3720.org）和 station 自己的管理页

`web/src/telemetry.ts`，在 `web/src/main.tsx` 里启动。构建时没有 key 的话，这些函数什么都不做，bundle 里也没有 posthog-js。管理后台（`admin.ember.3720.org`）什么都不发。

- **身份**：看着哪个 workspace，就以那个 workspace 所用的已登录账号标识（ember 账号 id，即 Google `sub`），邮箱作为人的属性；退出这个账号时 reset。station 自己的管理页不标识人。
- **错误**：页面上未捕获的异常和 promise 拒绝；核心 worker（SharedWorker / Worker）里捕获到的错误由 worker 转给一个页面上报；worker 崩溃（`{fatal}`）或起不来也上报。每个事件都带 `release`（构建时的 git 提交）和 `app`（`cloud` / `station`）。
- **会话回放**：所有文字、所有输入框都打码；图片、视频、canvas 整块挡掉；`title`、`alt`、`aria-label`、`placeholder`、`href`、`src` 等可能带人名、文件名、对话名的属性打码。回放里只有布局和操作。控制台日志不录。登录回调页（URL 里有 Google 的 code）不录。是否录制还取决于 PostHog 项目设置里的 Session replay 开关。
- **事件**（不按键入发）：

  | 事件 | 属性 |
  |---|---|
  | `sign_in` | — |
  | `chat_opened` | `surface`（ember / slack）、`open`（本次页面加载打开的第一个对话为 cold，之后为 warm）、`ms`（从点击到消息出现；cold 且不是点进来的，从页面开始加载算） |
  | `message_sent` | `attachments`、`quotes`（个数）、`first`（是否新建对话的第一条）、`ok`、`ms`（到 station 收到为止） |
  | `chat_created` | `runtime`、`model`、`effort`、`ms` |
  | `workspace_created` | `first`（登录后自动建的第一个） |
  | `station_added` | `ms`（从生成命令到 station 出现在列表里） |
  | `$pageview` | 只在路由变化时发 |

- **URL**：所有事件里的 URL 都把 id 换成占位（`/w/:workspace/s/:station/chats/:thread`），去掉查询串和 `#` 之后的部分；别的域名只留域名。不开 autocapture（它会记元素里的文字），也不开热图、死点击、rage click。

## station（Node）

`src/telemetry.ts`，只做错误追踪，**默认关闭**。station 跑在用户自己的机器上，由它的管理者在 `config.json` 里打开：

```json
{ "telemetry": { "errors": true } }
```

打开后（改配置立即生效，关掉也立即停）上报：未捕获的异常（未处理的 promise 拒绝也会变成它）、每一条 `log.error`。每条带 station 的 id（有 mesh 登记时）和 `release`。`log.error` 的字段一律不发（可能带着人写的东西），只发其中的 Error 和日志的那句话；错误信息和调用栈里家目录下的路径换成 `~`，错误信息里引号括起来的内容换成 `"…"`（比如 JSON.parse 会把输入引出来）。

## key 从哪来

项目 key 是 PostHog 的公开 key（`phc_…`），本来就会出现在网页里，但和别的部署输入一样不进仓库：放在 studio 的 `~/ember-deploy/posthog.json`，内容 `{ "host": "https://us.i.posthog.com", "key": "phc_…" }`。

构建时由环境变量 `EMBER_POSTHOG` 指向这个文件，`web/vite.config.ts` 读它：

- `cloud/deploy.py` 构建网页版时自动设置（文件不存在就构建一个没有分析的版本，并提示）。
- station 的构建：`EMBER_POSTHOG=~/ember-deploy/posthog.json pnpm build`。key 除了进管理页，还写一份到 `dist/admin/posthog.json`，station 启动时从那里读，所以管理者只需打开配置，不需要别的设置。
- 不设 `EMBER_POSTHOG` 的构建（本地、开发）没有任何分析，station 也无从上报。
