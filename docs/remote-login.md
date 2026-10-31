# 远程登录（设计稿）

> chat EMBER/1792171443.604000（2026-10-17 用户定：不在 station 之间借用、复制登录；每台 station 自己登录、自己持有和续期凭据，人在客户端远程完成；登录是机器级的；通用，跑工具自己的登录命令；浏览器那一步在客户端设备上、用这个人自己的浏览器完成；station 的浏览器和远程屏幕只是兜底；能操作这台 station 的人就能在上面登录，不分是哪个 workspace 的；两种都支持的工具默认用设备码）。同一 chat 后来又定：不按服务一个一个支持，只有一种通用的登录方式；登录区不列没登录的服务；不让用户输入命令：登录只由 agent 用 login 发起，人只在面板里完成；CLI 的交互由 agent 操作；人只做要本人身份的那一步（在自己浏览器里登录、填码）；设备码不要两个按钮，一个「复制并打开」。

状态：第一步已实现（PR #496：station `station/src/logins/`、core `client/core-ts/src/station/machine-logins.ts`、web `web/src/MachineLogins.tsx`），安卓（卡片和回环转发）是第二步；下面写「实现」的地方是代码里实际的做法，和最初的设计不同处随文说明。

## 要解决的事

agent 在 station 上跑 `gh`、`gcloud`、`npm publish`、`docker push` 时常遇到「没登录」。现在只能有人 ssh 上去、或者坐到那台机器前面登录。agent 的订阅 Profile 已经能在页面上远程登录（`station/src/accounts/login.ts`：`claude auth login` 贴码、`codex login --device-auth` 设备码），但只管这两个 runtime。

这份设计把它推广到任意命令行工具：在目标 station 上跑工具自己的登录命令，人在客户端（桌面、安卓、网页）完成浏览器、验证码、密码这些步骤，凭据由那个工具自己存在 station 上、自己续期。

## 已定的规则

- **不借用、不复制**：不把一台机器的登录拷到另一台。各家的 refresh token 多是一次性的，拷过去的两份会有一份过一阵被挤掉（`station/src/agents/machine-logins.ts` 开头写的就是这个原因）。要在三台 station 上用 gh，就在三台上各登录一次。
- **机器级**：登录落在 station 的系统用户下（和 agent 跑命令用的是同一个 HOME、同一个钥匙串），这台 station 上所有 chat 的 agent、所有任务都用它，不分 chat、不分 workspace。界面上每个登录入口都写明这一点。
- **只有一种通用的登录方式**（用户定：不按服务一个一个支持，只有一种通用的登录方式；登录区不列没登录的服务）：不维护「支持哪些 CLI」的名单，没有服务描述，不查各服务登没登录。登录就是跑工具自己的登录命令（`gh auth login`、`gcloud auth login`、`az login --use-device-code`、`aws sso login`、`npm login`、`docker login`、`gh auth refresh -s workflow`……），要人做什么全从命令自己的行为看出来（见下面「怎么做到」「网址和端口的解析」）。station 页只列通过 still.fail 在这台上做过的登录。
- **不让用户输入命令**（用户定：登录只由 agent 用 login 发起，人只在面板里完成）：客户端里没有输入登录命令的地方。agent 自己发现命令缺登录，或者人在 chat 里说「在 studio 上登录 GitHub」，都由 agent 调 `login {command}`。
- **CLI 的交互由 agent 操作**（用户定：人只做要本人身份的那一步，在自己浏览器里登录、填码）：命令问的 Y/n、选项、选主机都由 agent 通过 `login` 工具看屏幕、替它答（取工具的默认或任务需要的）；实在定不了才在 chat 里像平常一样问人。卡片里没有终端输入。
- **不碰密码**：agent 不问、不输密码和 token。命令停在不回显的提示上（读密码）时，station 拒绝往里写任何东西；agent 改用这个工具的浏览器或设备码登录方式，没有就告诉人这个工具不能这样登录。
- **浏览器那一步在客户端设备上**：用这个人自己的浏览器、密码管理器（1Password）、passkey。station 上什么都不用装。
- **station 的浏览器 + 远程屏幕只是兜底**：只用于回调地址不是本机回环、又没有设备码的登录，以及网页版接不住回调时。

## 不做的

- 不在 station 之间同步、转发凭据，不做「登录在 X，别的 station 借用」（Profile 的订阅分享是另一回事，见 station-share.md）。
- station 不读、不存各工具的凭据：凭据在哪、怎么续期是工具自己的事（钥匙串或它的配置文件）。station 只记「谁在什么时候通过 still.fail 登录了哪个服务」。
- 不按 chat、按 workspace 隔离登录，不给每个 chat 一套 HOME。
- 不做多账号切换的界面（gh、gcloud 自己支持多账号的，照工具的规矩：最后登录的那个生效）。
- 不改写登录地址里的 `redirect_uri`（换端口会让工具自己换 token 时对不上，见「端口被占」）。

## 怎么做到

一次远程登录 = station 上一个跑在伪终端（PTY）里的登录命令，加上客户端的一个卡片。station 从三个地方看出这个命令要人做什么：

1. **它要打开的网址**：给登录进程设 `BROWSER`，并在 PATH 最前面放 `open`、`xdg-open`、`osascript` 三个替身（`osascript` 的网址从 stdin 里的 `open location "…"` 读）。它们都只是把网址交给 station、然后退出 0，station 机器上不会弹出浏览器（现在 Profile 登录的 `noBrowser()` 已经放了前两个，只是不记网址）。哪些 CLI 走哪一条见下面的实验；codex 哪条都不走，只能读它的输出。
2. **它打印的东西**：网址、设备码、提示语（`Paste code`、`Press Enter`、`? What account`）。
3. **它在不在等输入**：PTY 里有提示停住、没有网址也没有设备码，就是在等人敲字。

于是有五种情况，一次登录里可以先后出现几种：

| 情况 | 怎么认出来 | 客户端做什么 |
|---|---|---|
| 回环回调 | 网址里的 `redirect_uri`（或同类参数）是 `http://localhost:<端口>`、`http://127.0.0.1:<端口>`、`http://[::1]:<端口>` | 本机临时监听同一个端口，用默认浏览器打开网址，回调经 mesh 转给 station 上的命令 |
| 设备码 | 输出里有验证网址和一串码（`ABCD-1234` 之类，见「网址和端口的解析」） | 卡片上显示网址和码：复制码、打开网址 |
| 只要打开网址 | 有网址，但没有回环回调，也没有码（如 `npm login` 的网页登录：命令自己去轮询 npm） | 用默认浏览器打开网址，等命令自己结束 |
| 贴回网页给的码 | station 不自己判断（用户定：不应该自动判断，agent 自己发）：给了要打开的网址（没有回环、没有设备码）之后，agent 从屏幕上看出它要的是网页给的码（gcloud `--no-launch-browser` 的「enter the verification code」、Devin 的「copy the code and paste it below」），调 `login {id, paste: true}` | 卡片上「在浏览器里登录」，下面一个输入框：人把网页给的码贴进来，客户端交给 station（`POST /machine-logins/<id>/answer`），station 打进命令再按回车，输入框随之收起。agent 不答这个提示。原来按「给了网址、接着停在回显的提示上」自动认，Devin 的输入框（`❭` 开头、不以冒号结尾）认不出来，卡片就没有输入框 |
| 要输入 | PTY 停在提示上（Y/n、选项、主机、用户名） | 由 agent 通过 `login` 工具答；卡片只说「等 agent 回答命令的问题」。不回显的提示（密码）谁也不写，agent 换浏览器或设备码方式 |

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
- **要按回车才开浏览器**：gh、npm、Docker。光标停在「Press Enter/ENTER … open … browser」这类只要回车去开网页的提示上时，station 替人按（这里没有要选的东西，按了以后它们会调 `open`，正好被替身截到）；别的提示，问 Y/n 的也一样（gh 的「Authenticate Git with your GitHub credentials? (Y/n)」），都留给人在卡片的终端里答。
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
客户端: 卡片「打开 github.com/login/device，输入 ABCD-1234」[复制并打开]
人:     在自己的浏览器里输入码、授权
station: 命令轮询到结果，写凭据，退出 0 → done
```

有的命令显示设备码后还要按一次回车才去开浏览器（gh 的 `Press Enter to open github.com in your browser...`）。station 不等人按：只要回车去开网页的提示，它直接按；问问题的（Y/n、选项）由 agent 答，不回显的（密码）谁也不答。实现：输出停了 500 ms 才看光标所在行（和人一样等它把话说完），每一处提示只按一次；命令再说话就不算在等了。光标所在行是空的时候看它上面最近的一行：gh 的这句后面带换行，光标停在下一行（真机上 gh 因此一直停在这句上，授权完了也不退；已修）。

不让命令卡住（真机 gh 登录时遇到的）：
- **钥匙串不进来**：登录命令和它起的进程里，git 的凭据助手被清空（环境变量 `GIT_CONFIG_COUNT/KEY/VALUE` 给一个空的 `credential.helper`，git 最后读它，前面配置文件里的助手都作废；只对这个进程，不写任何文件，用户的 ~/.gitconfig 不动）。原因：Homebrew 和 Apple 的 git 在系统配置里设了 `osxkeychain`，gh 答了「Authenticate Git」Yes 以后会 `git credential approve` 把令牌存进去；launchd 下的 station 没人能点钥匙串的对话框，`git-credential-osxkeychain store` 就一直等着。清空以后 gh 发现没有助手，就照 `gh auth setup-git` 那样在 ~/.gitconfig 里加它自己的 `!gh auth git-credential`。
- **兜底**：不需要人了（浏览器回来了；它说了已登录，如「✓ Authentication complete」「Logged in as」；或者它起的进程是钥匙串、凭据助手、pinentry、askpass 这类）却 3 分钟没有任何输出、也不停在提示上，就结束，算超时，错误里写原因和它最后的屏幕，发起的 agent 收到通知。人在浏览器里慢慢登录时的安静不算。15 分钟的总时限照旧。
- agent 的说明里写：命令问要不要顺便设 git 凭据、要不要存进钥匙串（或有这样的参数）时，选不碰系统钥匙串的（gh 用 `--insecure-storage`）。

能选的时候优先用设备码（人或 agent 给命令时带上设备码选项）（gh 只有设备码，Docker、Vercel 默认就是；`az login --use-device-code`、`aws sso login --use-device-code`、`wrangler login --device`、`codex login --device-auth` 也有）：设备码在网页版、手机、别人的电脑上都一样能完成，不依赖客户端能不能监听端口。只有设备码不可用、或者服务商把设备码关了（有的公司的 Entra ID 策略禁设备码）时才走回环。

### 要输入（PTY）

- station 给登录命令一个固定大小的 PTY（宽 200 列、高 40 行：宽一点是为了长网址不被折行，解析不出错），在 station 上用一个无界面的终端模拟器（`@xterm/headless`）维护屏幕。它要回答程序发来的终端查询（光标位置 `ESC[6n`、背景色 OSC 11）：gh 会问，没人答就一直卡住。网址和设备码从去掉控制序列的原始输出里读（长网址在屏幕上会折行，输出里是一整串）。
- 客户端不显示这个终端（卡片里没有命令输出，agent 用 `login` 工具看屏幕）；`machineLoginScreen` topic 和 `login=<id>` 流还在，给以后要看的地方用：station 先推整屏，再推改了的行和光标位置；客户端按自己的宽度显示（行太长就折行），不做终端模拟，三端一样。实现：走 station 已有的事件流（`GET /events?login=<id>`，事件 `login-screen` `{id, rows, cursor, echo, live, full?}`，先整屏再只发改了的行），core 的 `machineLoginScreen` topic 被看着时才把它加进流的参数；输入是 `POST /machine-logins/<id>/input`。原来写的「`/term` 双向流、和 screens 的 view 同一种分帧」没有用：screens 的 view 流是给画面的（二进制帧、按帧率推），一块 200×40 的文字屏用已有的事件流（只发改了的行，断线续传照旧）加一个写接口就够，三端都不用新的流类型。
- 输入只来自 agent 的 `login` 工具（文字，或 enter、up、down、left、right、tab、backspace、ctrl-c）；客户端没有输入。命令在读不回显的一行（密码）时 station 拒绝输入。实现：命令停在提示上时，station 对命令所在的终端跑 `stty -a`（`ps -o tty=` 找到它的 tty）看有没有 `-echo`，并且是按行读（`icanon`）：逐键读（gh 的 Y/n、菜单）也会关回显，那不是密码；读不到时看提示里有没有 password、token、密码 这类字样。
- 卡片上命令停在提示上时说「等 agent 回答命令的问题」，agent 的 `login` 工具回的就是屏幕和它在等什么。
- 屏幕内容只在内存里：core 不写进数据库，station 不写日志。登录结束 10 分钟后丢掉。

### 兜底

- **网页版**接不住回调（浏览器里的页面不能监听端口）。卡片改成两步：先「打开浏览器」，登录完浏览器会跳到一个 `http://localhost:…` 开头、打不开的地址；把地址栏里的整个地址粘贴回卡片，core 把它当成回调交给 station（`/callback`，和转发的那条一样核对路径和 state）。
- **客户端端口被占**（本机也在跑 gcloud 之类）：同上，改成贴地址。卡片说清是哪个端口被占。
- **回调不是本机回环、又没有设备码**（少数 CLI 回调到服务商自己的页面再让命令去取），或者上面两条都不行：卡片给「在 station 的浏览器里登录」，打开远程屏幕（remote-screens.md 的 station 浏览器）。这时 `BROWSER` 换成 station 浏览器开新标签页，回调在 station 本机完成。

### 在 station 的浏览器中登录（2026-10-25，chat EMBER/1792894388.635000）

凡是要人在浏览器里做一步的登录，都可以改在 station 自己的浏览器（remote-screens.md「The station's browser」，agent 用的那个 Chrome）里做，人在 app 里看着那个标签页的画面操作：

- **入口**（2026-10-25 用户：「这个功能应该是不常用的，入口不应该这么放」）：登录卡片（命令行登录）和 Profile 的登录（「连接 Anthropic / OpenAI…」、Profile 页的重新登录，手机、桌面、网页都有）在这一步自己的按钮行末放一个「⋯」（其他方式），菜单里是「在 dev-prod 的浏览器中打开」，不单独占一行按钮：它是同一步的另一个去处，平时用不到（docs/ui-panels.md：用得少的收进行末的「⋯」）。主按钮还是用自己设备的浏览器（手机上有密码管理器、passkey、已经登录的 Google；10-17 定过 station 浏览器只是兜底）。只有它走得通时它才是这一步的按钮，本机的方式反过来收进「⋯」：网页版接不住回环登录的回调（原来只说「这一步要在桌面或安卓 app 里完成」），或者本机端口刚被占用。station 没有 Chrome、或者是旧 station（不说 `browser`）时没有这一项。只读成员没有。
- **打开的是哪一页**：命令本来要打开的那一页。命令行登录：回环的是它打开的那页（回调到本机端口），设备码的是带码的那页（`codeUrl`，没有就验证页），只要打开网址的就是那个网址。Profile 的登录：`claude auth login` 的 `BROWSER`/`open` 替身原来什么都不做，现在把要打开的网址写进这次登录的文件（`STILLFAIL_LOGIN_OPENED`），station 浏览器打开其中回调到本机端口的那一页；这样授权完浏览器直接回到命令，**不用贴授权码**。别的（Codex、Grok、OpenCode、Kimi、Cursor 的设备码页，Devin 要贴回来的页）打开它给的那一页；设备码在画面里粘贴（这台设备的剪贴板经画面的粘贴过去），Devin 的码在画面里复制，回到登录页粘贴。
- **标签页跟着这次登录走**（`station/src/logins/pages.ts`）：每次登录最多一个，不属于任何会话（不挂在 chat 下，chat 归档也不关）。再点一次（别的设备也一样）是同一个标签页，拿到前面来。中途退出不关，这时「⋯」里那一项变成「回到 dev-prod 的浏览器」（登录带 `screen`）。登录完成、失败、取消、超时或重新开始时 station 关掉它；人自己关了，登录再告诉一遍（没有 `screen` 了）。
- **画面**：按钮的回答是标签页的屏幕 id，客户端打开那个屏幕的页面，并记下「只到它消失为止」（mbui 的 `ScreenAt.until_gone`、网页的 `?until-gone`）：标签页一关（view 以 `ended: gone` 结束，core 说 `phase: gone`），页面自己退回登录页，登录页这时已经是「已登录，正在添加」或已连接。在手机和平板上，station 浏览器的标签页按这台设备显示画面的区域排版（remote-screens.md 的 `fit`），手指点哪就是哪（不用触控板方式）。
- **用的就是 agent 那个 Chrome**：在里面登录过的 claude.ai 等会留着，下次只要点「授权」。agent 本来就能拿到这台机器上的登录，不会多暴露什么。

接口（都不给只读成员，回 `{screen}`：标签页的屏幕 id）：

| 方法和路径 | 作用 |
|---|---|
| `POST /machine-logins/<id>/browser` | 命令行登录的这一页在 station 浏览器里打开；记下是谁（`doneBy`） |
| `POST /profiles/<id>/login-browser` | Profile 的登录（重新登录）的这一页 |
| `POST /logins/<id>/browser` | 新 Profile 的登录的这一页 |

`Login`（命令行登录）和 `LoginJob`（Profile 的登录）各加两个可选字段：`browser`（现在能在 station 浏览器里做，进行中、有页可开、station 有 Chrome）、`screen`（标签页开着时它的屏幕 id）。core 的调用：`machineLogin.browser`、`profile.loginBrowser`、`login.browser`；卡片上按钮的字是 core 给的 `browserText`。旧 station 没有这些路由（404），也不说 `browser`，按钮不出现。

### 几台 station 一起登录

卡片里「也在其他 station 上登录」勾几台，每台各起一次同样的命令。卡片按台排成一列，一次做一台：

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
- 路由 `station/src/api/routes/logins.ts`，工具 `station/src/logins/tool.ts`。
- 现有 Profile 登录（`accounts/login.ts`）先不动；以后可以改成用同一套跑（`codex login` 不加 `--device-auth` 就是回环 1455 端口）。

### PTY

- macOS、Linux 第一步用系统自带的 `script` 包一层（macOS `script -q /dev/null <命令>`，Linux `script -qfec <命令> /dev/null`），开头 `stty cols 200 rows 40`。在 studio 上试过：stdin 是管道也能拿到 PTY、能交互；stdin 关掉会给命令送 EOF，所以登录期间一直开着。不加原生代码。实现时发现：macOS 的 `script` 对 stdin 做 `tcgetattr`，遇到 socket 就报「Operation not supported on socket」退出，而 Node 的 `stdio: "pipe"` 和 macOS 的 fifo 都是 socket；所以 macOS 上是 `cat <&3 | script …`（中间是真管道），`script` 结束后 `pkill -P $$ -x cat` 收掉 `cat`，不然整条命令要等 station 关 stdin 才算结束（`station/src/platform/unix.ts` `terminal`）。
- Windows 没有 `script`，先用普通管道跑（多数 CLI 没有 TTY 时会改成打印网址、设备码，见上面的表），之后在原生插件里加 ConPTY。
- 登录进程是 station 的子进程，station 重启就结束（登录本来就几分钟内做完，不像 agent 那样要跨重启）；重启后这次登录记为「station 重启了」。实现：登录只在 station 进程的内存里（结束的留 10 分钟），重启后列表里就没有它了，卡片和卡片说「没有这个登录」，卡片随 agent 下一次发言或撤回处理；没有另记「station 重启了」。

### 网址和端口的解析

- 网址先看 `BROWSER`/替身拿到的，再看输出里的 `https://…`；两样都有时以打开的为准（Claude Code 打印的网址回调到它自己的 https 贴码页，打开的才是回环）。
- 回环：取网址查询参数里的 `redirect_uri`（也看 `redirect_url`、`redirect`、`callback`，以及这些参数里再套一层的网址），host 是 `localhost`、`127.0.0.1`、`[::1]` 的，取端口和路径；再看 `state`、`response_mode=form_post`。端口为 0 或没写的不算回环。
- 设备码：通用规则，不按工具：网址里的 `user_code=`（RFC 8628 的 verification_uri_complete，Vercel 这样给）；`ABCD-1234` 这类（四位大写字母数字、横线、四到六位：gh、Docker、AWS、Cloudflare）；「code」字样同一行里紧跟在 code 后面、或带数字的 6–10 位大写字母数字（az）。验证网址取路径里有 device、activate、verify 的那个。
- 程序自己按终端宽度（200 列）折行时，比 200 列还长的网址会断成两行（Devin 的登录网址约 230 字符，丢了后半截，网页给的码换不了 token）：一行几乎占满整行宽、以网址结尾时，下一行开头那个词接回去再认。
- 设备码只在网址以外的文字里找（`user_code=` 除外）：网址里的 PKCE challenge、state 是随机串，偶尔会像一个码。
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
| `GET /machine-logins/<id>` | 一次登录 |
| `DELETE /machine-logins/<id>` | 取消（结束命令）；记下是谁取消的 |
| `POST /machine-logins/<id>/answer` | `{text}`：网页给的码（只在 `paste` 时收，一行），打进命令再按回车；记下是谁贴的。只读成员不行 |

客户端没有「起登录」的接口，往终端写也只有贴回网页给的码这一条：起登录和答命令的问题都是 agent 的（`login` 工具在 station 里直接调）。转发回调时记下是谁的浏览器回来的（`doneBy`）。
| `POST /machine-logins/<id>/callback` | `{method, path, headers, body?}`（body 是 base64）→ 命令的回应 `{status, headers, body}`（body 是 base64，整份；回调页很小，不做流式） |
| `POST /machine-logins/<id>/browser` | 它的页在 station 自己的浏览器里打开 → `{screen}`（见「在 station 的浏览器中登录」） |
| `GET /events?login=<id>` | 这次登录的终端（事件 `login-screen`），见上面「要输入」 |

```
Login   = {id, name, command, state, step?, url?, domain?, callback?: {host, port, path, state, post},
           code?, codeUrl?, waiting, paste?, by, workspace?, chat?, chatTitle?, doneBy?, startedAt, expiresAt, endedAt?, error?, timedOut?,
           browser?, screen?}
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

agent 要在另一台 station 上登录（它在 A 上，命令要在 B 上跑，比如它用 station_task 在 B 上跑的命令要登录）：`login {station: "B", …}`（名字或 id，和 station_task 一样认）。A 把这次调用原样经 `stillfail/station/1` 的 `login.call` 交给 B（带上 A 上的会话、chat 的发起人和标题），B 在自己的 `Logins` 上做（`logins/tool.ts` 的 `act`：起、看、答、取消），把给 agent 的那段话回给 A：话里说登录在 B 上（「on <B 的名字>」），卡片要带 `"station": "<B 的 key>"`，链接是 B 的。B 记下发起它的是 A 的哪个会话（`Starter.peer`），只让 A 动它自己起的登录；B 上没有这次登录的 chat。登录再问问题、结束时，B 经 `login.told` 告诉 A：A 关掉这个 id 的卡片（结束时），给那个会话发 station 通知。权限和远程任务一样（同 workspace 的 station 就能调，见 station-peers.md）。旧 station 不认 `login.call`，A 告诉 agent 那台要更新。

## agent 的 `login` 工具

```
login {command, station?}           // 跑工具自己的登录命令（station：在另一台上）；等它停下，回状态、屏幕（网址和码遮掉）、它在等什么
login {id}                          // 现在怎样了，同上
login {id, input?, key?}            // 答它的提示：文字和/或一个键（enter、up、down、tab、ctrl-c…），等它再停下
login {id, paste: true|false}       // 它在等网页给的码：卡片上出输入框，由人贴（只在给了要打开的网址之后；不回显的提示不行）
login {id, cancel: true}            // 结束它
```

- 工具回的屏幕里网址写成 `<link>`、设备码写成 `<code>`：agent 用不着，也就不会把它们贴进 Slack 或 chat。
- 用法（写进 instructions 和工具说明）：命令失败、输出说没登录（not logged in、401、token 过期），或者人在 chat 里要登录时，用工具自己的登录命令调 `login`（有浏览器或设备码选项的带上）。命令问问题就自己答（工具的默认，或任务需要的），实在定不了在 chat 里问人。从不叫人去跑命令。
- 卡片只在有浏览器那一步（设备码或要打开的网页）之后发：`chat_post` 带 `card: {"type": "login", "login": "<id>"}`，正文一句话说要谁在哪台登录什么、为什么，加登录链接，`kind: "need_human"` 结束这一轮。工具回的话会说「人那一步好了，现在发卡片」。
- 密码：不问、不输；不回显的提示 station 拒绝输入，工具回的话会说换浏览器或设备码方式，或者告诉人不能这样登录。
- 登录结束（完成、失败、超时、取消）时，station 给发起它和发过它卡片的会话各一条通知，卡片自动算答了（从待处理里撤掉）。人那一步之后命令又问问题（az 选订阅这类）时，也给发起它的会话一条通知，agent 接着答；agent 正在用 `login` 等它停下时不发，那次调用的回答里已经有了。
- 同一条命令已有进行中的登录，回那一个，不起第二个。
- 改了工具和规则，按惯例在 `station/src/agents/migrations.ts` 的 `NOTES` 末尾加一条（38）。

### `login` 卡片

- 新卡片类型 `{"type": "login", "login": "<id>", "station"?: "<id>", "assignee"?}`（`station/src/sessions/args.ts` 的 `cardArg` 加一种；`station` 是登录在别的 station 上时）。登录结束时 station 把带这个 id 的卡片记进 `closed_cards`（像 agent 自己撤回，不算谁答了，也不叫醒谁：叫醒它的是那条 station 通知）。
- 卡片里只有登录的 id。网址、设备码由客户端打开卡片时经 mesh 向 station 要，所以消息、推送、待处理都不会带它们走 still.fail cloud 或 Slack。
- 推送通知只说「需要在 studio 上登录 gh」这类话（agent 写的正文）。
- Slack 里的 chat 没有卡片：agent 只贴登录链接，链接在客户端里打开。

## 界面（web、桌面、安卓，文字）

### station 页的「登录」区

- 只列通过 still.fail 在这台上做过的登录，一条都没有时整个区不显示（旧 station 也不显示）。标题「登录」，小字「agent 在这台 station 上做的登录，所有 chat 的 agent 都会用。」
- 进行中的就是它的登录卡片（和 chat 里同一张，见下面），排在前面。结束了的按工具（`name`，和卡片标题里的同一个，如 devin）合成一行（2026-10-31 用户看着一次尝试一行、gcloud 刷了十几行大半是「已取消」说「就这么列着不太对」：人要知道的是这台登过哪些工具、最近是谁登上去的），按每个工具最近一次尝试排，越近越前：
  - 标题是工具名，不显示命令（2026-10-26 用户看着整条带变量和路径的命令说「很难看明白」：命令是 agent 的做法，人要知道的是登录了哪个工具）。
  - 第二行说最近一次登录成功的那次：「张三 登录 · 10/30 16:04 · 『<chat 标题>』」（标题链到那个 chat；不知道是谁就「登录完成 · …」），之后又试过没成也不改；一次都没成过就说「没有登录成功过 · 最近一次已取消 · 03:12 · 『…』」，最近一次失败或超时时这一行是红的。
  - 行尾是一共试了几次（「11 次」）和一个箭头，点这一行展开每一次：什么时候、怎么结束的（知道是谁就写谁：「张三 完成」「张三 取消」，不知道就写结果：登录完成 / 登录失败 / 已取消 / 超时了；失败和超时红字）、哪个 chat 的 agent 发起。默认收着。
  - 分组是 core 做的（`machineLogins` 的 `tools`，`station/machine-logins.ts` `toolsShown`），网页宽窄两种排法和 app 用同一份。station 读记录时按命令重新取名，在有这个取名规则之前记下的（名字是 env）也一样。
- 没有输入框、没有「登录」「运行」按钮：登录由 agent 发起（人在 chat 里说一声就行）。只读成员看到的一样，只是卡片上没有按钮。
- agent 贴的登录链接（`/w/<ws>/s/<station>/login/<id>`）打开 station 页，把那张卡片（结束了的：展开它的工具，那一次）滚到眼前并用浅色底标出来，不弹任何东西。

### 登录卡片（用户定：卡片就是全部界面，点开不再有弹窗）

chat 里 agent 的消息下面、station 页「登录」区里进行中的，都是同一张卡片；点卡片本身什么也不打开，没有卡片、没有底部弹层。卡片里依次是：
- 标题「在 studio 上登录 gh」（命令的程序名：跳过 `env` 和它的选项、`VAR=value`，以及 sudo、npx、uvx、`pnpm dlx` 这类只是用来跑它的命令，取文件名、去掉包的版本；`env HOME=… /x/bin/devin auth login` 是 devin）。
- 现在要人做的：
  - 设备码：「打开 github.com，输入」+ 大字的码，一个按钮 [复制并打开]（用户定：不要两个按钮）：先把码写进剪贴板，再打开验证网址（网址里已经带码的就用那个）；剪贴板写不进去照样打开，码一直显示在卡片上。码本身也能点（用户后来加的）：点了只复制、不打开什么，底部 toast「验证码已复制」（复制不了就说为什么）；它是个按钮（键盘 Enter/空格也行，读屏念「复制验证码 <码>」），手指形光标，没有底色，悬停也没有。
  - 回环（桌面 app）：「登录页在 accounts.google.com」+ [在浏览器里登录]；点了以后「等浏览器回来…」。网页版说一句「这一步要在桌面 app 里完成」，也写出域名。
  - 只要打开网址：「登录页在 www.npmjs.com」+ [在浏览器里登录]。
  - 还没到人的那一步（启动中，或 agent 在答命令的问题）：转圈 +「等 agent 回答命令的问题」，没有这一步的按钮。
- 结束了：卡片收成一行（用户定：结束的大灰卡片太丑），和 chat 里答过的决策那行一样（`settledLine`：小字、淡色、没有底色和框）：「已在 studio 上登录 gh」；「张三 取消了在 studio 上登录 gh」（不知道谁就「已取消在 studio 上登录 gh」）；「在 studio 上登录 gh 失败：<错误里说原因的那行>」用红色；「在 studio 上登录 gh 超时了」。没有「重试」：要再来让 agent 再起一次。
- 进行中时按钮在一排（用户定：不要两排）：先是这一步自己的按钮（[复制并打开] / [在浏览器里登录]），旁边是 [取消]：主按钮是强调色实底的药丸，[取消] 是不带底色的普通面板按钮（指针放上去才有底色）。按钮的底色贴着卡片的内边距（离左边和底边 8，和卡片圆角同心），按钮里的字再进 10，和标题对齐（docs/ui-panels.md 的规则）。还没到人的那一步时这一排只有 [取消]。手机宽度也是一排。
- 不显示命令输出（agent 用 `login` 工具看）；不显示多台的切换（之后几台一起登录时再加）。
- 在待处理里和别的卡片一样排；登录结束后从待处理里消失（station 关掉了它的卡片）。

### 安卓

安卓 app（`apps/mbui`）的卡片是 `apps/mbui/src/sfpages/login_card.mbt`（每种屏幕同一张，测试 `sfapp/login_card_wbtest.mbt`、`login_link_wbtest.mbt`），和网页同一套状态、同一套文字（`web-main.logins.*`），用在 chat 里 agent 消息下面、station 页「登录」区；agent 贴的登录链接（`/w/<ws>/s/<station>/login/<id>`，core `link.parse` 的 `login`）打开 station 页并把那张卡片滚到眼前、浅色底标出来。

- 网页都在 Chrome Custom Tab 里打开（`BrowserLogin.java`；没有支持 Custom Tab 的浏览器就交给系统浏览器）。设备码「复制并打开」、点码只复制（toast「验证码已复制」）、只要打开网址，和网页一样。
- 回环：core 的 `Host.listen` 在安卓上是 app 的（bridge 的 `listen.open/next/respond/close`，引擎把 `listen.*` 和 `secure.*` 一样交给宿主的 Java：`Loopback.java`，`ServerSocket` 只绑 127.0.0.1 / ::1），所以 `canRelay` 为真，核对 Host、路径、state、只转一次、10 秒后关，全是 core 里桌面那一套（`Relays`）。没有改 Rust shell。
- 后台：Custom Tab 在前面时 app 在后台；Android 14 起默认开着「缓存应用冻结」，进了后台的进程几秒后就被冻住，冻住的进程接不了浏览器的回调。所以监听开着的时候（只在那时）起一个前台服务（`LoginService.java`，`specialUse`，通知「在 studio 上登录 gcloud · 正在等待浏览器」）：第一个监听打开时起（app 在前台，Android 只允许这时起），最后一个监听关掉就自己停，最多 16 分钟。
- 本机端口被占：core 记下原因（`MachineLoginShown.relayText`「本机 8085 端口被占用」），卡片上红字说，按钮还在、可以再试；不弹 toast、什么都不打开（网页桌面同样改成说在卡片上）。

### 跨机器实测（2026-10-18）

第一步的回环转发只有同机的确定性测试，这次第一次真的跨机器走通。studio 上起 dev cloud 和临时 station（临时 HOME），登录命令是一个假的回环登录（只听 127.0.0.1 的 `<端口>`，经 `BROWSER` 交出一个 https 登录页：httpbin 的 `redirect-to`，当作立刻跳回 `redirect_uri` 的服务商；state 对的回调到了就退出 0，别的请求退出 1）。登录都由 agent 用 station 的 `login` 工具起、再发卡片，studio 上没有人碰。

| 客户端 | 怎么做 | 结果 |
|---|---|---|
| Mini1 上的 node host（桌面 app 的 core，`hosts/node.ts`），经局域网连 studio 的 dev cloud 和 relay | `machineLogin.open` → Mini1 本机监听 → 照浏览器那样请求登录页、跟着跳到 `http://localhost:18085/callback` | 回调经 mesh 转到 studio 上的命令，2.8 秒里卡片变成「已在 studio 上登录 fake-loopback」；之后那个端口只回「登录已完成」页 |
| studio 上的安卓模拟器（自己的网络栈：它的 127.0.0.1 不是 studio 的，算「另一台机器」），adb reverse 只给 dev cloud 和 relay | 在 chat 的卡片上点「在浏览器里登录」→ Custom Tab → 跳回模拟器的 `localhost:18086` | 前台服务起来（`fg-service`），Custom Tab 显示命令自己的「signed in」页，登录完成；10 秒后监听关、服务结束 |
| 同上，真的 `gcloud auth login`（studio 上，临时配置目录） | 打开 agent 贴的登录链接（station 页，卡片标出来）→「在浏览器里登录」| Custom Tab 停在 Google 的「登录 · 继续前往 Google Cloud SDK」，没有真的登录；在卡片上取消，命令结束，服务跟着结束 |

这次实测查出一个只在手机上出的问题：core 核对回调时用了 `URLSearchParams`，安卓的 Hermes 没有它，浏览器的第一个请求一来 core 就崩、监听跟着没了（Chrome 显示连接被拒）。已改成手写解析，`hermes-safe.test.ts` 也拦 `URLSearchParams`。同一次里也看到了冻结：core 崩掉、服务结束以后，Custom Tab 还在前面，约 70 秒后系统日志 `freezing … fail.still.android.motion`。

## 安全

- **谁能起登录、转回调、往终端里打字**：能操作这台 station 的人，即能在上面让东西跑起来的人（能开 chat、让 agent 跑命令），主 workspace 和加入的 workspace（multi-workspace.md）一样（用户定）。登录命令本身就是任意命令，所以不另设更低的门槛，也不需要更高：这些人的 agent 本来就能跑 `gh auth login`。只读成员（`viewer`）只能看状态。登录是机器级的，谁登的账号，这台 station 上所有 workspace 的 agent 都会用；登录列表里记下是谁、从哪个 workspace 登的。
- **agent 起登录**：等同于 agent 跑命令，不另要权限；完成它的人要满足上一条。
- **workspace 锁**：这些接口都在 member link 上，开了锁的 station 只放锁里的设备，角色取锁和凭证里较低的。cloud 起不了登录、也转不了回调。
- **不经 cloud**：登录网址、设备码、回调（里面有授权码）、终端内容只走 iroh（member link 和 station 之间的 transport，端到端加密，relay 只看到密文）。消息、卡片、推送、待处理只带登录 id。station 日志只记服务名、谁、结果，不记网址的查询串和终端内容。
- **转发的范围**：客户端只听回环、只在这次登录点了「打开」之后、只接路径和 state 对得上的第一条；station 只转给这次登录的端口，并核对端口确实是这个命令在听；每次登录只转一次。
- **打开什么网址**：客户端只打开 `https://` 的网址，打开前在卡片上显示域名。一个被人操纵的 agent 可以起一个「登录」把人引到钓鱼页，显示域名、要人点一下才打开，是能做到的最多的。
- **终端里的密码**：不进 core 的数据库、不进 station 日志，回显关着时客户端不显示。

## 失败的情况

| 情况 | 怎么办 |
|---|---|
| 客户端端口被占 | 监听失败就不打开浏览器，卡片说「本机 8085 端口被占用」，改成贴地址或 station 浏览器。不能换端口：`redirect_uri` 的端口要和命令换 token 时用的一致 |
| station 上端口被占 | gcloud、codex、firebase 自己顺延到下一个端口（以截到的网址为准）；wrangler 直接失败，命令里加 `--callback-port`，或者改用 `--device` |
| 客户端中途断线、关了 | station 上的命令照等，直到它自己或 station 的 15 分钟超时。人可以在别的设备上打开同一个登录接着做（状态是推的）。回环的浏览器跳回来时原来那台的监听没了，就贴地址 |
| 客户端就是这台 station | 不监听，直接打开网址 |
| 命令超时或退出 | 记为失败，显示最后几行；agent 收到通知，要的话再起一次 |
| 设备码过期 | 同上（命令自己会报错退出） |
| 几个客户端同时开着 | 都看到同一个状态；谁先把回调转回来算谁的，之后的回调 station 拒绝；终端输入谁打都进同一个 PTY，卡片显示还有谁开着 |
| 同一服务同时起两次 | 回已有的那个；要换就先取消 |
| station 重启 | 登录命令跟着结束，记为「station 重启了」 |
| 凭据存不进去（钥匙串锁着，station 不在图形会话里） | 是命令自己的报错，照样显示在失败信息和终端里；状态命令也会说没登录 |
| 登录成功但 agent 还是没权限（scope 不够） | agent 用 `command` 起 `gh auth refresh -s <scope>` 这类命令，同样走一遍 |

## 分步

**第一步**

- station：`logins/` 模块（`script` 包的 PTY、`BROWSER` 和替身截网址、回环端口和设备码解析、回调转发和端口核对、超时取消）、接口和事件。实现：没有内置描述，任何登录命令走同一条路（用户后来定的）。
- core：`machineLogins` topic、`machineLogin.start/cancel/paste/open/term/input` 调用（实现：只剩 `cancel` 和 `open`，起登录、答问题是 agent 的）；node host（桌面）加只听回环的监听，打开网址走现有的 `openExternal`。实现：topic 是 `machineLogins`（一台的全部）、`machineLogin`（一次）、`machineLoginScreen`（终端，代替 `term` 调用）；调用是 `machineLogin.start/cancel/input/paste`（station 操作）和 `machineLogin.open`（core 自己的：回环的先在本机听，再回要打开的网址；`here` 是这台 station 就在本机时不听）；监听是 `Host.listen`（只有 node host 有，`canRelay`），打开网址由页面 `window.open`，桌面 app 里会交给系统浏览器（`openExternal`）。登录列表随 station 的其他文档记在 core 的数据库里（station/memory.ts：重开 app 先显示上次的，连上后再读），终端画面只在内存里。
- 桌面和网页：station 页「登录」区（只有做过的登录，没有就不显示）、登录卡片（回环转发只桌面有，网页先只有设备码、打开网址）。
- agent：`login` 工具、`login` 卡片、登录结束的通知、instructions 和 migrations NOTE。
- 验证：studio 上 dev cloud + 临时 station，临时 HOME，用 gh（设备码）、gcloud（回环 8085）、npm（只打开网址）各走通一次；回环转发（GET 和 form_post 的 POST、只听 `[::1]` 和只听 127.0.0.1 的两种）、端口被占、state 不对、命令已退出时的拒绝写确定性测试（假的登录命令 + 本机 HTTP 服务）。

**第二步（安卓，已实现）**

- 安卓卡片和回环转发，见上面「安卓」。

**之后**

- 网页的贴地址兜底、station 浏览器兜底（要 remote-screens 先合）。
- 几台 station 一起登录。
- `login {station}` 跨 station。
- Windows 的 ConPTY。
- Profile 的订阅登录改用同一套。
