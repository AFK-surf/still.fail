# 远程登录（设计稿）

> chat EMBER/1792171443.604000（2026-10-17 用户定：不在 station 之间借用、复制登录；每台 station 自己登录、自己持有和续期凭据，人在客户端远程完成；登录是机器级的；通用，跑工具自己的登录命令；浏览器那一步在客户端设备上、用这个人自己的浏览器完成；station 的浏览器和远程屏幕只是兜底；能操作这台 station 的人就能在上面登录，不分是哪个 workspace 的；两种都支持的工具默认用设备码）。同一 chat 后来又定：不按服务一个一个支持，只有一种通用的登录方式；登录区不列没登录的服务。

状态：第一步已实现（PR #496：station `station/src/logins/`、core `client/core-ts/src/station/machine-logins.ts`、web `web/src/MachineLogins.tsx`）；下面写「实现」的地方是代码里实际的做法，和最初的设计不同处随文说明。

## 要解决的事

agent 在 station 上跑 `gh`、`gcloud`、`npm publish`、`docker push` 时常遇到「没登录」。现在只能有人 ssh 上去、或者坐到那台机器前面登录。agent 的订阅 Profile 已经能在页面上远程登录（`station/src/accounts/login.ts`：`claude auth login` 贴码、`codex login --device-auth` 设备码），但只管这两个 runtime。

这份设计把它推广到任意命令行工具：在目标 station 上跑工具自己的登录命令，人在客户端（桌面、安卓、网页）完成浏览器、验证码、密码这些步骤，凭据由那个工具自己存在 station 上、自己续期。

## 已定的规则

- **不借用、不复制**：不把一台机器的登录拷到另一台。各家的 refresh token 多是一次性的，拷过去的两份会有一份过一阵被挤掉（`station/src/agents/machine-logins.ts` 开头写的就是这个原因）。要在三台 station 上用 gh，就在三台上各登录一次。
- **机器级**：登录落在 station 的系统用户下（和 agent 跑命令用的是同一个 HOME、同一个钥匙串），这台 station 上所有 chat 的 agent、所有任务都用它，不分 chat、不分 workspace。界面上每个登录入口都写明这一点。
- **只有一种通用的登录方式**（用户定：不按服务一个一个支持，只有一种通用的登录方式；登录区不列没登录的服务）：不维护「支持哪些 CLI」的名单，没有服务描述，不查各服务登没登录。登录就是跑工具自己的登录命令（`gh auth login`、`gcloud auth login`、`az login --use-device-code`、`aws sso login`、`npm login`、`docker login`、`gh auth refresh -s workflow`……），要人做什么全从命令自己的行为看出来（见下面「怎么做到」「网址和端口的解析」）。station 页只列通过 still.fail 在这台上做过的登录。
- **浏览器那一步在客户端设备上**：用这个人自己的浏览器、密码管理器（1Password）、passkey。station 上什么都不用装。
- **station 的浏览器 + 远程屏幕只是兜底**：只用于回调地址不是本机回环、又没有设备码的登录，以及网页版接不住回调时。

## 不做的

- 不在 station 之间同步、转发凭据，不做「登录在 X，别的 station 借用」（Profile 的订阅分享是另一回事，见 station-share.md）。
- station 不读、不存各工具的凭据：凭据在哪、怎么续期是工具自己的事（钥匙串或它的配置文件）。station 只记「谁在什么时候通过 still.fail 登录了哪个服务」。
- 不按 chat、按 workspace 隔离登录，不给每个 chat 一套 HOME。
- 不做多账号切换的界面（gh、gcloud 自己支持多账号的，照工具的规矩：最后登录的那个生效）。
- 不改写登录地址里的 `redirect_uri`（换端口会让工具自己换 token 时对不上，见「端口被占」）。

## 怎么做到

一次远程登录 = station 上一个跑在伪终端（PTY）里的登录命令，加上客户端的一个面板。station 从三个地方看出这个命令要人做什么：

1. **它要打开的网址**：给登录进程设 `BROWSER`，并在 PATH 最前面放 `open`、`xdg-open`、`osascript` 三个替身（`osascript` 的网址从 stdin 里的 `open location "…"` 读）。它们都只是把网址交给 station、然后退出 0，station 机器上不会弹出浏览器（现在 Profile 登录的 `noBrowser()` 已经放了前两个，只是不记网址）。哪些 CLI 走哪一条见下面的实验；codex 哪条都不走，只能读它的输出。
2. **它打印的东西**：网址、设备码、提示语（`Paste code`、`Press Enter`、`? What account`）。
3. **它在不在等输入**：PTY 里有提示停住、没有网址也没有设备码，就是在等人敲字。

于是有四种情况，一次登录里可以先后出现几种：

| 情况 | 怎么认出来 | 客户端做什么 |
|---|---|---|
| 回环回调 | 网址里的 `redirect_uri`（或同类参数）是 `http://localhost:<端口>`、`http://127.0.0.1:<端口>`、`http://[::1]:<端口>` | 本机临时监听同一个端口，用默认浏览器打开网址，回调经 mesh 转给 station 上的命令 |
| 设备码 | 输出里有验证网址和一串码（`ABCD-1234` 之类，见「网址和端口的解析」） | 卡片上显示网址和码：复制码、打开网址 |
| 只要打开网址 | 有网址，但没有回环回调，也没有码（如 `npm login` 的网页登录：命令自己去轮询 npm） | 用默认浏览器打开网址，等命令自己结束 |
| 要输入 | PTY 停在提示上（用户名、密码、2FA、选项、贴码） | 面板里的小终端；贴码类的给一个输入框 |

浏览器那一步做完以后，命令自己写凭据、自己退出。退出码 0 就算完成（不再跑状态命令、不读账号）。

## 实验：各 CLI 怎么开浏览器

2026-10-17 在 studio（macOS 27）上做的：每个命令用临时 HOME 和各自的配置目录，只启动、观察、杀掉，没完成任何登录，没碰 studio 自己的登录。每个命令跑两次：一次设 `BROWSER` 为记录参数的脚本，一次不设、只在 PATH 前面放 `open`、`xdg-open`、`osascript` 替身。TTY 用 Python 写的伪终端，没 TTY 用 `</dev/null` 加管道。监听地址用 `lsof` 看。

| CLI 和版本 | 命令 | 认 `BROWSER` | 怎么开浏览器 | 流程 | 回调地址和监听 | 设备码 | 会问什么 | 没 TTY 时 |
|---|---|---|---|---|---|---|---|---|
| gh 2.92.0 | `auth login --web -h github.com` | 认（`GH_BROWSER` 优先） | `BROWSER`，否则 PATH 里的 `open` | 设备码（没有回环） | 无 | 只有设备码 | 「Authenticate Git…? (Y/n)」，再「Press Enter to open https://github.com/login/device in your browser...」 | 打印码和网址，不开浏览器，照样轮询 |
| gh | `auth login`（不带参数） | 同上 | 同上 | 设备码或贴 token | 无 | 同上 | GitHub.com/其他 → HTTPS/SSH → Y/n → 「浏览器登录 / 贴 token」→ 回车 | 同上 |
| gcloud 511.0.0 | `auth login`、`auth application-default login` | 认 | `BROWSER`，否则绝对路径的 `/usr/bin/osascript`（替身拦不到） | 回环 + PKCE | `localhost:8085/` 固定，被占就 8086…；听 127.0.0.1 | 无 | 无 | 照样开浏览器、监听 |
| gcloud | `auth login --no-launch-browser` | – | 只打印 | 贴码（回调到 sdk.cloud.google.com/authcode.html） | 无 | – | 「enter the verification code provided in your browser」 | – |
| gcloud | `auth login --no-browser` | – | 只打印 | 要在另一台装了 gcloud 的机器上跑一条命令再贴回来 | 无 | – | 「Enter the output of the above command」 | – |
| aws-cli 2.34.31 | `sso login` | 认 | `BROWSER`，否则绝对路径的 `osascript` | 回环 + PKCE | `127.0.0.1:随机/oauth/callback`；听所有 IPv4 | `--use-device-code` | 无 | 照样开浏览器、监听 |
| npm 11.4.2 | `login`（网页） | 不认（`--browser=路径` 也不认） | PATH 里的 `open` | 只要打开网址：命令自己轮询 npm，没有回环 | 无 | 无 | 「Login at: https://www.npmjs.com/login?next=/login/cli/…」「Press ENTER to open in the browser...」 | 打印网址，不问，轮询 |
| npm | `login --auth-type=legacy` | – | – | 用户名、密码 | – | – | 「Username:」… | – |
| Docker 29.7.2 | `login` | 不认 | PATH 里的 `open` | 设备码（Docker Hub） | 无 | 默认就是 | 「Your one-time device confirmation code is: XXXX-XXXX」「Press ENTER to open your browser…」 | 拒绝：「cannot perform an interactive login from a non-TTY device」 |
| codex-cli 0.160.0 | `login` | 不认 | 两个替身都没拦到（推测走系统接口） | 回环 + PKCE | `127.0.0.1:1455/auth/callback` 固定，被占换 1457；听 127.0.0.1 | `--device-auth` | 无 | 监听，打印网址 |
| Claude Code 2.1.107 | `auth login` | 认 | `BROWSER`，否则 `open` | 回环 + PKCE | `localhost:随机/callback`；**只听 [::1]** | 无 | 无 | 开浏览器、监听 |
| Vercel 64.4.0 | `login` | 不认 | 马上用 `open` | 设备码 | 无 | 默认就是 | 「Visit https://vercel.com/oauth/device?user_code=XXXX-XXXX」 | 用 `open` 开，轮询 |
| wrangler 4.151.1 | `login` | 不认 | `open` | 回环 + PKCE | `localhost:8976/oauth/callback` 固定，被占直接失败；**只听 [::1]**；可用 `--callback-port` | `--device`（8 位码，5 分钟） | 无 | 一样 |
| firebase-tools 15.34.0 | `login` | 不认 | `open` | 回环（state 是数字） | `localhost:9005`（没有路径），被占顺延；听所有地址（双栈） | 无；`--no-localhost` 是贴码 | 第一次跑先问两个 Y/n（Gemini、使用统计）才给网址 | 打印贴码说明，退出 0 |
| azure-cli 2.91.0 | `login` | 认 | `BROWSER`，否则 PATH 里的 `osascript`（网址从 stdin 给） | 回环 + PKCE，`response_mode=form_post`：**回调是 POST** | `localhost:随机`（没有路径）；听 127.0.0.1 | `--use-device-code` | 登录后选订阅（没走到） | 照样开浏览器 |

没测：gemini（登录在它的 TUI 里，没有登录子命令）、1Password `op`（走桌面 app 或 Secret Key，不开浏览器）、fly（跳过）、huggingface-cli（贴 token）。az 是临时用 `uvx` 跑的。浏览器之后的步骤（az 选订阅、gh 配 git 凭据）没观察到。

从表里得出的、会影响设计的几点：

- **截网址要三样一起上**：`BROWSER`（gh、gcloud、aws、az、Claude Code 认；Python 3.14 的 gcloud、aws 不设它就用绝对路径的 osascript，谁也拦不到）、PATH 上的 `open` 替身（npm、Docker、Vercel、wrangler、firebase 只用它）、PATH 上的 `osascript` 替身（Python 3.13 及以前，网址从 stdin 读）。codex 两样都不走，只能从它的输出里读网址。
- **以打开的网址为准**：打印的和打开的可能不一样（Claude Code 打印的是贴码用的 https 回调，打开的才是回环；codex 打印 `localhost:1455`，实际 `redirect_uri` 是 127.0.0.1）。都截到时用打开的那个。
- **回调要连到命令真正听的地址**：只听 `[::1]` 的有 Claude Code、wrangler（连 127.0.0.1 被拒），只听 127.0.0.1 的有 gcloud、codex、az，aws 和 firebase 听所有地址。station 转发时按 `lsof` 看到的地址连，看不到就 `[::1]`、127.0.0.1 都试（连接失败才换，不发两次请求）。
- **不能探回调路径**：一条 state 不对的请求就让 gcloud、aws、Claude Code、wrangler 直接失败退出，firebase 改成贴码。所以 station 核对端口只看 `lsof`，从不往回调路径发请求；客户端对不上的请求一律不转。没有一个命令检查 `Host` 头。
- **回调可能是 POST**：az 用 `form_post`，浏览器把 code 和 state 用表单 POST 到 `http://localhost:<端口>/`。客户端要接这一种 POST，并在表单正文里找 state。
- **常用的大多是设备码**：gh 只有设备码，Docker、Vercel 默认设备码，npm 只要打开网址。第一步就算只有设备码和打开网址，gh、Docker、Vercel、npm 都能在网页版和手机上做完；真正要回环转发的是 gcloud、aws（也有设备码）、az（也有设备码）、wrangler（也有设备码）、firebase、Claude Code、codex（也有设备码）。
- **要按回车才开浏览器**：gh、npm、Docker。光标停在「Press Enter/ENTER … open … browser」这类只要回车去开网页的提示上时，station 替人按（这里没有要选的东西，按了以后它们会调 `open`，正好被替身截到）；别的提示，问 Y/n 的也一样（gh 的「Authenticate Git with your GitHub credentials? (Y/n)」），都留给人在面板的终端里答。
- **要真 TTY**：Docker 没 TTY 直接拒绝。gh 在 TTY 里会问终端背景色（OSC 11）和光标位置，没人回答就卡住，所以 PTY 那头的终端模拟器要回答这些查询。
- **固定端口**：gcloud 8085、codex 1455、wrangler 8976、firebase 9005。gcloud、codex、firebase 被占会顺延（station 以实际网址里的端口为准），wrangler 被占直接失败。
- **超时**：回环的在 30 秒内都没说超时；codex 设备码 15 分钟，wrangler 设备码 5 分钟。

## 流程

### 回环回调（经客户端转发）

```
人/agent        客户端(core)                     station                       登录命令(PTY)
   |  登录 gh  ---->|  POST /machine-logins  -------->|  起 PTY，设 BROWSER/open 替身 -->|
   |                |                                 |<-- BROWSER <url> -----------------|
   |                |<-- 事件 machineLogins           |  解析 redirect_uri → 端口 P、state |
   |                |    {kind: loopback, host, P}    |                                   |  监听 127.0.0.1:P
   |  点「打开浏览器」>|  监听本机 127.0.0.1:P（localhost 时也听 [::1]:P）                  |
   |                |  默认浏览器打开 url                                                  |
   |  浏览器里登录、授权（密码管理器、passkey 都在这台设备上）                              |
   |  浏览器跳到 http://localhost:P/callback?code=…&state=… ---> 客户端监听               |
   |                |  核对：Host、路径、state（查询串或表单正文），第一条                  |
   |                |  POST /machine-logins/<id>/callback {method, path, headers, body} ->|
   |                |                                 |  lsof 确认 P 是这个命令在听，     |
   |                |                                 |  连它听的地址（::1 或 127.0.0.1）->|
   |                |                                 |<-- 命令的回应页（200 / 302）------|
   |                |<-- 原样带回 ----------------------|                                   |
   |  浏览器显示命令的「登录成功」页 <---|  回给浏览器，关监听                                 |
   |                |                                 |<-- 命令换 token、写凭据、退出 0 ---|
   |                |<-- 事件：done，账号 octocat     |  跑状态命令                        |
```

- 只在这次登录、只在点了「打开浏览器」之后监听；只听回环地址（`127.0.0.1`，`redirect_uri` 写的是 `localhost` 时同时听 `[::1]`，因为浏览器可能先试 IPv6），从不听 `0.0.0.0`。
- 只接一条：路径等于 `redirect_uri` 的路径，`state` 等于网址里的 `state`，`Host` 是 `localhost:P` / `127.0.0.1:P` / `[::1]:P`（挡 DNS rebinding；实验里没有一个 CLI 自己查 Host）。方法是 GET，`state` 在查询串里；网址里有 `response_mode=form_post` 的（az）是 POST，`state` 在表单正文里，正文原样转过去。别的请求一律 404，不转：一条 state 不对的请求就会让 gcloud、aws、Claude Code、wrangler 直接失败退出。实验里的回环登录都带 `state`，没有 `state` 的网址不做转发，走贴地址。
- 转完这一条就不再转：之后这个端口上的请求（favicon、成功页跳回本机的另一个路径）由客户端自己回一页「登录已完成，可以关掉这页」，10 秒后关监听。登录结束、取消、超时也立刻关。
- station 一侧只把这一条转给这次登录的端口 P，并且先确认 P 正被这个登录命令（或它的子进程）监听（macOS/Linux 用 `lsof -a -p`，Linux 也可读 `/proc/net/tcp`，Windows 用 `netstat -ano`）；命令已经退出、端口被别的程序占了，就拒绝，不会把授权码交给别的服务。确认只看进程和端口，**从不往回调路径发探测请求**（见上：一条错的请求就会弄死登录）。
- 连哪个地址：按 `lsof` 看到的监听地址连（Claude Code、wrangler 只听 `[::1]`，gcloud、codex、az 只听 127.0.0.1）；看不到时先 `[::1]` 再 127.0.0.1，只在连接被拒时换，请求只发一次。每次登录只转一次。
- 客户端就是这台 station（桌面 app 里的本机 station）时不转：命令自己就在听 P，直接用浏览器打开网址。

### 设备码

```
station: PTY 输出 "First copy your one-time code: ABCD-1234 … https://github.com/login/device"
      → 事件 {kind: device, url, code}（有 verification_uri_complete 的用带码的网址）
客户端: 卡片「打开 github.com/login/device，输入 ABCD-1234」[复制验证码] [打开]
人:     在自己的浏览器里输入码、授权
station: 命令轮询到结果，写凭据，退出 0 → done
```

有的命令显示设备码后还要按一次回车才去开浏览器（gh 的 `Press Enter to open github.com in your browser...`）。station 不等人按：只要回车去开网页的提示，它替人按；问问题的（Y/n、选项、用户名密码）留给人在终端里答。实现：输出停了 500 ms 才看光标所在行（和人一样等它把话说完），每一处提示只按一次；命令再说话就不算在等了。

能选的时候优先用设备码（人或 agent 给命令时带上设备码选项）（gh 只有设备码，Docker、Vercel 默认就是；`az login --use-device-code`、`aws sso login --use-device-code`、`wrangler login --device`、`codex login --device-auth` 也有）：设备码在网页版、手机、别人的电脑上都一样能完成，不依赖客户端能不能监听端口。只有设备码不可用、或者服务商把设备码关了（有的公司的 Entra ID 策略禁设备码）时才走回环。

### 要输入（PTY）

- station 给登录命令一个固定大小的 PTY（宽 200 列、高 40 行：宽一点是为了长网址不被折行，解析不出错），在 station 上用一个无界面的终端模拟器（`@xterm/headless`）维护屏幕。它要回答程序发来的终端查询（光标位置 `ESC[6n`、背景色 OSC 11）：gh 会问，没人答就一直卡住。网址和设备码从去掉控制序列的原始输出里读（长网址在屏幕上会折行，输出里是一整串）。
- 客户端打开面板时订阅这个终端：station 先推整屏，再推改了的行和光标位置；客户端按自己的宽度显示（行太长就折行），不做终端模拟，三端一样。实现：走 station 已有的事件流（`GET /events?login=<id>`，事件 `login-screen` `{id, rows, cursor, echo, live, full?}`，先整屏再只发改了的行），core 的 `machineLoginScreen` topic 被看着时才把它加进流的参数；输入是 `POST /machine-logins/<id>/input`。原来写的「`/term` 双向流、和 screens 的 view 同一种分帧」没有用：screens 的 view 流是给画面的（二进制帧、按帧率推），一块 200×40 的文字屏用已有的事件流（只发改了的行，断线续传照旧）加一个写接口就够，三端都不用新的流类型。
- 输入：文字（输入法、粘贴结果）、回车、退格、方向键、Tab、Ctrl-C。终端关了回显（输密码）时客户端的输入框换成密码框。实现：命令停在提示上时，station 对命令所在的终端跑 `stty -a`（`ps -o tty=` 找到它的 tty）看有没有 `-echo`；读不到时看提示里有没有 password、token、密码 这类字样。
- 卡片和面板不默认展开终端；命令停在提示上且没有网址、设备码时自动展开，并说「命令在等你输入」。
- 屏幕内容只在内存里：core 不写进数据库，station 不写日志。登录结束 10 分钟后丢掉。

### 兜底

- **网页版**接不住回调（浏览器里的页面不能监听端口）。面板改成两步：先「打开浏览器」，登录完浏览器会跳到一个 `http://localhost:…` 开头、打不开的地址；把地址栏里的整个地址粘贴回面板，core 把它当成回调交给 station（`/callback`，和转发的那条一样核对路径和 state）。
- **客户端端口被占**（本机也在跑 gcloud 之类）：同上，改成贴地址。面板说清是哪个端口被占。
- **回调不是本机回环、又没有设备码**（少数 CLI 回调到服务商自己的页面再让命令去取），或者上面两条都不行：面板给「在 station 的浏览器里登录」，打开远程屏幕（remote-screens.md 的 station 浏览器）。这时 `BROWSER` 换成 station 浏览器开新标签页，回调在 station 本机完成。

### 几台 station 一起登录

面板里「也在其他 station 上登录」勾几台，每台各起一次同样的命令。面板按台排成一列，一次做一台：

- 设备码的可以同时做（每台的码不同，挨个输入）。
- 回环的一次只转一台：端口常常是固定的（gcloud 8085、wrangler 8976、firebase 9005 每台都一样），客户端同一时间只为一台监听，这台完成或取消了再给下一台「打开浏览器」。
- 每台各自成功或失败，失败的可以单独重来。

## station

### 模块

- `station/src/logins/`（新）：
  - `run.ts`：起 PTY、设 `BROWSER` 和 `open`/`xdg-open` 替身、读输出、解析网址/端口/设备码、超时、取消。
  - `index.ts`：进行中和刚结束的登录（在内存里），以及在这台上做过的登录的记录（`<data>/logins/history.json`：命令、谁、什么时候、怎么结束的，不记网址、码和输出）。
  - `parse.ts`：从网址和输出里认出回环、设备码、只要回车的提示（通用规则，不按工具）。
  - `relay.ts`：把回调转给登录命令的端口，核对端口归属。
- 路由 `station/src/api/routes/logins.ts`，工具 `station/src/tools/login.ts`。
- 现有 Profile 登录（`accounts/login.ts`）先不动；以后可以改成用同一套跑（`codex login` 不加 `--device-auth` 就是回环 1455 端口）。

### PTY

- macOS、Linux 第一步用系统自带的 `script` 包一层（macOS `script -q /dev/null <命令>`，Linux `script -qfec <命令> /dev/null`），开头 `stty cols 200 rows 40`。在 studio 上试过：stdin 是管道也能拿到 PTY、能交互；stdin 关掉会给命令送 EOF，所以登录期间一直开着。不加原生代码。实现时发现：macOS 的 `script` 对 stdin 做 `tcgetattr`，遇到 socket 就报「Operation not supported on socket」退出，而 Node 的 `stdio: "pipe"` 和 macOS 的 fifo 都是 socket；所以 macOS 上是 `cat <&3 | script …`（中间是真管道），`script` 结束后 `pkill -P $$ -x cat` 收掉 `cat`，不然整条命令要等 station 关 stdin 才算结束（`station/src/platform/unix.ts` `terminal`）。
- Windows 没有 `script`，先用普通管道跑（多数 CLI 没有 TTY 时会改成打印网址、设备码，见上面的表），之后在原生插件里加 ConPTY。
- 登录进程是 station 的子进程，station 重启就结束（登录本来就几分钟内做完，不像 agent 那样要跨重启）；重启后这次登录记为「station 重启了」。实现：登录只在 station 进程的内存里（结束的留 10 分钟），重启后列表里就没有它了，面板和卡片说「没有这个登录」，卡片随 agent 下一次发言或撤回处理；没有另记「station 重启了」。

### 网址和端口的解析

- 网址先看 `BROWSER`/替身拿到的，再看输出里的 `https://…`；两样都有时以打开的为准（Claude Code 打印的网址回调到它自己的 https 贴码页，打开的才是回环）。
- 回环：取网址查询参数里的 `redirect_uri`（也看 `redirect_url`、`redirect`、`callback`，以及这些参数里再套一层的网址），host 是 `localhost`、`127.0.0.1`、`[::1]` 的，取端口和路径；再看 `state`、`response_mode=form_post`。端口为 0 或没写的不算回环。
- 设备码：通用规则，不按工具：网址里的 `user_code=`（RFC 8628 的 verification_uri_complete，Vercel 这样给）；`ABCD-1234` 这类（四位大写字母数字、横线、四到六位：gh、Docker、AWS、Cloudflare）；「code」字样同一行里紧跟在 code 后面、或带数字的 6–10 位大写字母数字（az）。验证网址取路径里有 device、activate、verify 的那个。
- 认不出来的网址也照样给客户端「打开」，由人判断。

### 不按工具的知识

一个服务一个服务的描述（原来的 `builtin.ts`：状态命令、登录参数、设备码正则、替人回答的提示）全部去掉了。还留着的工具相关的东西只有解析时认不出来就不行的那几条通用规则，都写在 `parse.ts`，不对应哪一个工具：
- 设备码的三种样子（见上），验证网址看路径里的 device/activate/verify；
- 回调参数的名字（`redirect_uri`、`redirect_url`、`redirect`、`callback`、`return_to`）和 `response_mode=form_post`；
- 「只要回车去开网页」的提示：`press enter|return … open|browser`，且不是 Y/n。

登录成没成，只看命令的退出码（0 是完成）；不再跑状态命令、不读账号。

做过的登录：`<data>/logins/history.json` 记最近 50 次 `{id, name, command, state, by, workspace?, chat?, startedAt, endedAt, timedOut?}`。通过 still.fail 之外登录的（有人 ssh 上去敲的）不出现。

### 接口（member link，`stillfail/admin/1`）

都在 `/admin/api/machine-logins` 下（`/logins/<id>` 已经被「新 Profile 的登录」占了，不复用）。

| 方法和路径 | 作用 |
|---|---|
| `GET /machine-logins` | `{logins: [Login]}`：进行中的，然后结束了的（内存里的，再接历史记录里的） |
| `POST /machine-logins` | `{command}`（一行，或词的数组）；要幂等 key。同一条命令已有进行中的登录就回那一个 |
| `GET /machine-logins/<id>` | 一次登录 |
| `DELETE /machine-logins/<id>` | 取消（结束命令） |
| `POST /machine-logins/<id>/callback` | `{method, path, headers, body?}`（body 是 base64）→ 命令的回应 `{status, headers, body}`（body 是 base64，整份；回调页很小，不做流式） |
| `POST /machine-logins/<id>/paste` | `{text}`：贴回来的 `http://localhost…` 地址当回调；别的文字写进 PTY 加回车 |
| `POST /machine-logins/<id>/input` | `{text}` 或 `{key: "Enter" \| "Backspace" \| "Up" \| "Down" \| "Left" \| "Right" \| "Tab" \| "Ctrl-C"}`：写进终端 |
| `GET /events?login=<id>` | 这次登录的终端（事件 `login-screen`），见上面「要输入」 |

```
Login   = {id, name, command, state, step?, url?, domain?, callback?: {host, port, path, state, post},
           code?, codeUrl?, waiting, by, workspace?, chat?, startedAt, expiresAt, endedAt?, error?, timedOut?}
state   = starting | browser | code | input | verifying | done | failed | cancelled
step    = loopback | device | open | terminal          // 现在要人做的那一步
```

`callback.state` 给客户端核对浏览器回来的那一条；只读成员拿到的 `Login` 没有 `url`、`callback`、`code`、`codeUrl`、`error`，只看得到状态（`Logins.limited`）。

事件：station 的事件流加 `machine-logins`（和别的事件一样用连字符），带变了的 `{login}`；只读成员收到去掉网址和码的那份。流开时 core 先 `GET /machine-logins` 读一遍，之后靠事件。

能力和兼容：

- 旧 station 对 `GET /machine-logins` 回 404：core 记这台不支持，station 页不显示「登录」区（或显示「需要更新 station」），卡片里的登录链接说这台要更新。不另加版本号字段，和 screens 一样靠 404 判断。
- 旧客户端 + 新 station：不认识 `login` 卡片（下面），只显示消息正文；正文里一定有登录链接 `<cloud>/w/<ws>/s/<station>/login/<id>`，点开走网页版（网页总是最新的）。
- 字段都按「可选」处理：新 station 以后加的 `step` 种类，老 core 当成「打开网址 + 终端」显示。
- 不升数据库版本：`<data>/logins/` 是新目录，没有就建。

### station 之间

agent 要在另一台 station 上登录（它在 A 上，命令要在 B 上跑）：`login {station: "B"}` 走 `stillfail/station/1` 的新方法 `login.start` / `login.get` / `login.cancel`，B 起登录，回登录链接，卡片照样由 A 上的 agent 发。权限和远程任务一样（同 workspace 的 station 就能调，见 station-peers.md）。旧 station 不认这些方法，回「需要更新」。放在第二步。

## agent 的 `login` 工具

```
login {command, station?}      // 跑工具自己的登录命令，回 {id, state, step, link}
login {id}                     // 现在怎样了
login {id, cancel: true}       // 结束它
```

- 工具回的东西里**没有**登录网址、设备码：agent 用不着，也就不会把它们贴进 Slack 或 chat。
- 用法（写进 instructions 和工具说明）：命令失败、输出说没登录（not logged in、401、token 过期）时，用工具自己的登录命令调 `login`（有设备码选项的优先用它）；然后 `chat_post` 带 `card: {"type": "login", "login": "<id>"}`，正文一句话说要谁在哪台登录什么、为什么，加登录链接，`kind: "need_human"` 结束这一轮。
- 登录结束（完成、失败、超时、取消）时，station 给发起它和发过它卡片的会话各一条通知（和远程 chat 结束时的 station notice 一样），卡片自动算答了（从奏里撤掉）。agent 被叫醒后继续原来的事。
- 同一条命令已有进行中的登录，回那一个，不起第二个。
- 改了工具和规则，按惯例在 `station/src/agents/migrations.ts` 的 `NOTES` 末尾加一条（38）。

### `login` 卡片

- 新卡片类型 `{"type": "login", "login": "<id>", "station"?: "<id>", "assignee"?}`（`station/src/sessions/args.ts` 的 `cardArg` 加一种；`station` 是登录在别的 station 上时）。登录结束时 station 把带这个 id 的卡片记进 `closed_cards`（像 agent 自己撤回，不算谁答了，也不叫醒谁：叫醒它的是那条 station 通知）。
- 卡片里只有登录的 id。网址、设备码由客户端打开卡片时经 mesh 向 station 要，所以消息、推送、奏都不会带它们走 still.fail cloud 或 Slack。
- 推送通知只说「需要在 studio 上登录 gh」这类话（agent 写的正文）。
- Slack 里的 chat 没有卡片：agent 只贴登录链接，链接在客户端里打开。

## 界面（web、桌面、安卓，文字）

### station 页的「登录」区

- 标题「登录」，下面一行小字：「运行工具自己的登录命令，在你自己的浏览器里完成；登录在这台 station 上，所有 chat 的 agent 都会用。」
- 主操作是一个输入框加「运行」：输入工具自己的登录命令（`gh auth login`），按下面的面板走。
- 下面只列通过 still.fail 在这台上做过的登录：进行中的在前，然后结束了的，新的在前；每行是命令、谁、什么时候、现状或结果（验证码 ABCD-1234 / 命令在等你输入 / 登录完成 / 登录失败 / 已取消 / 超时了）。点一行打开它的面板（结束了的可以「重试」）。一条都没有时只有输入框和那行小字，不列任何服务。
- 只读成员只看得到列表，没有输入框和按钮。

### 登录面板（桌面对话框，手机网页和安卓底部面板）

- 标题「在 studio 上登录 gh」（命令的程序名），下面一行等宽小字是整条命令。
- 回环：「要在浏览器里登录 accounts.google.com。」[打开浏览器]。点了以后「等浏览器回来…」。网址的域名总是显示出来，人能看清要去哪里登录。
- 设备码：「打开 github.com/login/device，输入」+ 大字的码 [复制] [打开]；「输完后这里会自己更新。」
- 只要打开网址：「在浏览器里完成登录。」[打开浏览器]
- 网页版或端口被占：「这个页面接不住登录回调。登录完浏览器会跳到一个 localhost 开头、打不开的地址，把地址栏里的整个地址粘贴到这里。」输入框 [提交]；下面小字「或者 在 station 的浏览器里登录」。第一步网页版先只说一句「要在 still.fail 桌面 app 里打开这个登录」并显示域名；`paste` 接口已经有，面板上的贴地址放在之后。
- 终端：一个可展开的「终端」，展开后是等宽字体的屏幕和一个输入框（密码时是密码框），一排按键：回车、↑、↓、Tab、Ctrl-C。
- 结束：「登录完成」（命令退出码 0）；失败时显示命令最后几行和 [重试]；超时「超时了，没等到浏览器回来」[重试]。
- 多台：面板上方一排 station 名字，每个带状态（等你、进行中、完成、失败），当前那台高亮；「也在其他 station 上登录」可再勾。
- 底部固定一行：「这个登录在 studio 上，所有 chat 的 agent 都会用这个账号。」

### chat 里的卡片

- 「在 studio 上登录 GitHub」+ 一行现状（等你打开浏览器 / 验证码 ABCD-1234 / 命令在等你输入 / 已登录 octocat）。
- 按钮按现状给：[打开浏览器]、[复制验证码] [打开]、[打开终端]。点卡片打开同一个登录面板。
- 在奏里和别的卡片一样排；登录完成后自己消失。

### 安卓

- 打开网址用 Chrome Custom Tab；回环回调由 app 自己听 `127.0.0.1:<端口>`（core 的 host 经 `client/shell` 加一个只听回环的监听），Custom Tab 在前台时 app 的进程还在。要实测：系统把 app 放后台后监听会不会被停，必要时登录期间起一个前台服务（通知栏「正在 studio 上登录 GitHub」）。
- 第一步安卓只有设备码、打开网址、终端和贴地址兜底；回环转发放第二步。

## 安全

- **谁能起登录、转回调、往终端里打字**：能操作这台 station 的人，即能在上面让东西跑起来的人（能开 chat、让 agent 跑命令），主 workspace 和加入的 workspace（multi-workspace.md）一样（用户定）。登录命令本身就是任意命令，所以不另设更低的门槛，也不需要更高：这些人的 agent 本来就能跑 `gh auth login`。只读成员（`viewer`）只能看状态。登录是机器级的，谁登的账号，这台 station 上所有 workspace 的 agent 都会用；登录列表里记下是谁、从哪个 workspace 登的。
- **agent 起登录**：等同于 agent 跑命令，不另要权限；完成它的人要满足上一条。
- **workspace 锁**：这些接口都在 member link 上，开了锁的 station 只放锁里的设备，角色取锁和凭证里较低的。cloud 起不了登录、也转不了回调。
- **不经 cloud**：登录网址、设备码、回调（里面有授权码）、终端内容只走 iroh（member link 和 station 之间的 transport，端到端加密，relay 只看到密文）。消息、卡片、推送、奏只带登录 id。station 日志只记服务名、谁、结果，不记网址的查询串和终端内容。
- **转发的范围**：客户端只听回环、只在这次登录点了「打开」之后、只接路径和 state 对得上的第一条；station 只转给这次登录的端口，并核对端口确实是这个命令在听；每次登录只转一次。
- **打开什么网址**：客户端只打开 `https://` 的网址，打开前在面板上显示域名。一个被人操纵的 agent 可以起一个「登录」把人引到钓鱼页，显示域名、要人点一下才打开，是能做到的最多的。
- **终端里的密码**：不进 core 的数据库、不进 station 日志，回显关着时客户端不显示。

## 失败的情况

| 情况 | 怎么办 |
|---|---|
| 客户端端口被占 | 监听失败就不打开浏览器，面板说「本机 8085 端口被占用」，改成贴地址或 station 浏览器。不能换端口：`redirect_uri` 的端口要和命令换 token 时用的一致 |
| station 上端口被占 | gcloud、codex、firebase 自己顺延到下一个端口（以截到的网址为准）；wrangler 直接失败，命令里加 `--callback-port`，或者改用 `--device` |
| 客户端中途断线、关了 | station 上的命令照等，直到它自己或 station 的 15 分钟超时。人可以在别的设备上打开同一个登录接着做（状态是推的）。回环的浏览器跳回来时原来那台的监听没了，就贴地址 |
| 客户端就是这台 station | 不监听，直接打开网址 |
| 命令超时或退出 | 记为失败，显示最后几行，[重试] 重新起 |
| 设备码过期 | 同上（命令自己会报错退出） |
| 几个客户端同时开着 | 都看到同一个状态；谁先把回调转回来算谁的，之后的回调 station 拒绝；终端输入谁打都进同一个 PTY，面板显示还有谁开着 |
| 同一服务同时起两次 | 回已有的那个；要换就先取消 |
| station 重启 | 登录命令跟着结束，记为「station 重启了」 |
| 凭据存不进去（钥匙串锁着，station 不在图形会话里） | 是命令自己的报错，照样显示在失败信息和终端里；状态命令也会说没登录 |
| 登录成功但 agent 还是没权限（scope 不够） | agent 用 `command` 起 `gh auth refresh -s <scope>` 这类命令，同样走一遍 |

## 分步

**第一步**

- station：`logins/` 模块（`script` 包的 PTY、`BROWSER` 和替身截网址、回环端口和设备码解析、回调转发和端口核对、超时取消）、接口和事件。实现：没有内置描述，任何登录命令走同一条路（用户后来定的）。
- core：`machineLogins` topic、`machineLogin.start/cancel/paste/open/term/input` 调用；node host（桌面）加只听回环的监听，打开网址走现有的 `openExternal`。实现：topic 是 `machineLogins`（一台的全部）、`machineLogin`（一次）、`machineLoginScreen`（终端，代替 `term` 调用）；调用是 `machineLogin.start/cancel/input/paste`（station 操作）和 `machineLogin.open`（core 自己的：回环的先在本机听，再回要打开的网址；`here` 是这台 station 就在本机时不听）；监听是 `Host.listen`（只有 node host 有，`canRelay`），打开网址由页面 `window.open`，桌面 app 里会交给系统浏览器（`openExternal`）。全部只在内存里，不进 core 的数据库。
- 桌面和网页：station 页「登录」区（输入登录命令，下面是做过的登录）、登录面板（回环转发只桌面有，网页先只有设备码、打开网址、终端）。
- agent：`login` 工具、`login` 卡片、登录结束的通知、instructions 和 migrations NOTE。
- 验证：studio 上 dev cloud + 临时 station，临时 HOME，用 gh（设备码）、gcloud（回环 8085）、npm（只打开网址）各走通一次；回环转发（GET 和 form_post 的 POST、只听 `[::1]` 和只听 127.0.0.1 的两种）、端口被占、state 不对、命令已退出时的拒绝写确定性测试（假的登录命令 + 本机 HTTP 服务）。

**之后**

- 安卓：回环转发（shell 加监听、Custom Tab、必要时前台服务）。
- 网页的贴地址兜底、station 浏览器兜底（要 remote-screens 先合）。
- 几台 station 一起登录。
- `login {station}` 跨 station。
- Windows 的 ConPTY。
- Profile 的订阅登录改用同一套。
