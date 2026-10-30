# TS station 的原生部分：启动器、runner、mesh 插件

方案见 `docs/station-ts.md`（文中 `mesh/…` 指 2026-10-04 删除的 Rust station，代码在 git 历史里）。这三件用 Rust 写，各有版本号，预编译发布；TS 那边只按这里的约定用它们。预编译怎么做（按源码算 key、本机共享缓存、GitHub release `native-artifacts`、CI 在 main 上补发）见 `docs/development.md` 的「Native parts」：测试、打包都经 `scripts/native.ts` 拿它们，只有它们自己的源码变了才编。

## 1. runner（`station/native/runner`，可执行文件 `stillfail-runner`）

一个 agent 进程（claude、codex app-server）一个 runner。station 重启或崩溃时 runner 和 agent 都不受影响，新 station 重新接上，从没读过的地方接着读。

启动：
```
stillfail-runner --dir <run/runners> --id <id> [--cwd <dir>] -- <program> <args…>
```
- 环境变量原样传给 agent（station 在启动 runner 时就把 agent 的环境配好）。
- station 用 `nice -n 10` 启动 runner（`STILLFAIL_AGENT_NICE` 可改，0 不降；Windows 不降），agent 和它起的子进程（构建、浏览器）都比 station 低一档 CPU 优先级：机器被 agent 的活占满时，station 自己回请求、推变化不被拖住（`station/src/ops/nice.ts`）；后台任务（jobs）同样。
- runner 先 `setsid()`（离开 station 的进程组和会话，launchd 结束 station 时不会带走它），再 fork 出 agent：agent 自己 `setpgid(0,0)` 成一个进程组（station 按 pgid 结束 agent 及其子进程，与现在一样）。
- 写 `<dir>/<id>.json`（0600，原子写）：`{"id","runner":pid,"pid":agent pid,"pgid","startedAt":ms,"program","args","socket":"<dir>/<id>.sock","out":"<dir>/<id>.out","err":"<dir>/<id>.err"}`。
- agent 的 stdout、stderr 原样追加到 `<id>.out`、`<id>.err`（不改内容）。stdin 由 runner 持有。文件只在 runner 退出时删，不截断：一个 profile 共用的 codex app-server 一周能写到几百 MB，所以 station 在它的 `.out` 超过 64 MB、又没有 turn 在跑时换一个新的（同 Codex 升级后的做法，`codex.ts` `OUTPUT_LIMIT`）；崩溃后接手时 `linesBefore` 按块逐行读，不整份读进内存。
- 在 `<dir>/<id>.sock`（0600）上听一个 Unix socket；启动成功（agent 已 fork、socket 已在听、json 已写）后才把 `{"ready":true,...同 json}` 一行写到自己的 stdout 并关掉 stdout，然后就不再碰启动它的人。启动失败则非 0 退出并把原因写到 stderr。

socket 协议：每条消息是一行 JSON（`\n` 结尾）。同时只服务一个连接；新连接一来，旧连接被关掉（旧 station 退出前、新 station 接手时）。

客户端 → runner：
- `{"op":"attach"}`：开始推送。runner 从「已确认」的位置起，把 out/err 的新内容推过来，之后有新内容就推（不轮询：读管道的线程写完文件就通知）。
- `{"op":"ack","out":n,"err":m}`：station 已经处理到 out 第 n 字节、err 第 m 字节。runner 只在内存里记（runner 活着就够用），下次 attach 从这里推。
- `{"op":"write","data":"<base64>"}`：写进 agent 的 stdin。`{"op":"close_stdin"}`。
- `{"op":"signal","signal":"TERM"|"KILL"|"INT","group":true}`：发给 agent（`group` 为真则发给整个进程组）。
- `{"op":"done"}`：station 读完了、不再需要：agent 若已退出，runner 删掉 sock/json/out/err 并退出；若还在跑，按 `signal` 的规矩处理，不自动结束。

runner → 客户端：
- `{"op":"out","stream":"out"|"err","at":<这段起点的字节偏移>,"data":"<base64>"}`：按顺序推，偏移连续。
- `{"op":"exit","code":<int|null>,"signal":<string|null>}`：agent 退出且它的输出已全部推出之后才发。之后 runner 等 `done`（或下一个 attach 重放）。
- `{"op":"error","error":"..."}`：协议错误。

其它约定：
- agent 退出后、station 一直没来 `done`：runner 保留文件和 socket 24 小时后自行清理退出（station 也会在启动时清理找不到 agent 的 runner）。
- runner 自己被杀时，agent 的 stdin 关闭（与现在 station 崩溃时一样），agent 按自己的规矩退出；文件还在，station 能读到最后的输出。
- 不用 tokio，std 线程 + libc 就够；目标 macOS（arm64、x86_64）和 Linux（x86_64、aarch64）。
- `{"op":"leave"}`（客户端 → runner）：station 放手，runner 读到这里就关掉连接（之前的消息都已处理）。Unix 上等同于半关闭 socket 后读到底；Windows 的管道没有半关闭，station 在 Windows 上放手时先发它。

### Windows（PoC，`src/sys/windows.rs`；Unix 的在 `src/sys/unix.rs`，协议和文件不变）

- socket 换成命名管道 `\\.\pipe\stillfail-runner-<数据目录的 FNV-1a 哈希>-<id>`（json 的 `socket` 字段），ACL 只给当前用户、拒绝远程客户端、`FIRST_PIPE_INSTANCE` 防抢注。管道不是文件：**不能用 `existsSync`/stat 看它在不在——那本身就是一次连接**，会挤掉 station 的连接；TS 侧（`runner.ts` 的 `listening`）在 Windows 上以 info 文件在、runner 活着为准。
- 进程组换成 Job Object：agent 挂起启动、放进 job 后再恢复，它启动的东西都在 job 里；`signal` 没有信号可发，`group: true` 结束整个 job、否则只结束 agent（Node 在 Windows 上的 `process.kill` 也是结束），exit 的 `signal` 字段照样写 `TERM`/`KILL`/`INT`。agent 不开控制台窗口，能脱离外层 job 时就脱离。
- 启动时关掉从启动者继承来的、stdio 以外的句柄：Windows 把父进程所有可继承句柄都传给子进程（Unix 靠 close-on-exec），不关的话 runner 会一直占着 station 的 stdout，读它的一方（启动器、桌面端）等不到结束。
- 裸命令名按 PATH + PATHEXT 找（`codex` 是 npm 装的 `codex.cmd`），`.cmd`/`.bat` 由 Rust 的 Command 转义后交给 cmd。
- runner 从数据目录里的副本启动（`<data>/run/bin/stillfail-runner-<内容哈希>.exe`，`platform/processes.ts` 的 `keepRunnerIn`），不从发布目录。桌面端的 NSIS 安装器（electron-builder 的 `_CHECK_APP_RUNNING`）在换文件之前，会结束所有可执行文件在 app 目录下的进程：从那里启动的 runner 每次升级都被结束，留下的 agent 没人接管，新 station 又起了一个，同一个会话就有了两个 agent。只剩 1 个 runner 时它能活下来，只是因为安装器的计数在 Windows PowerShell 5.1 上数不出单个结果。副本按内容命名，同一个发布的 runner 只有一份；station 启动时删掉别的发布的副本，还在运行的删不掉（Windows 不让），就留着。复制失败时照旧从发布目录启动。
- `stillfail-runner --job -- <program> <args…>`：后台任务、设备命令在 Windows 上的“进程组”。把命令放进一个 `KILL_ON_JOB_CLOSE` 的 job，用自己的 stdio；等 job 里没有进程了才以命令的退出码退出；结束这个 runner 就结束整个 job。需要它是因为 Git Bash（MSYS）`exec` 出的进程在 Windows 看来父进程已经没了，按进程树（`taskkill /T`）找不到。

测试：`tests/windows.rs`（Windows 上的 `cargo test`），`station/test/runner-windows.test.ts`。

## 2. 启动器（`station/native/launcher`，可执行文件 `stillfail-station`）

替换现在的 `mesh/target/release/stillfail-station`，命令行与之相同（`bin/stillfail`、桌面 app、安装器都调它）：

- `run --app DIR [--port N] [--data DIR] [--with-parent] [--handoff FILE]`：启动器自己处理，见下。
- `enroll …`、`status`、`id`、`channel …`：直接 `exec` Node：`<app>/node/bin/node <app>/station/main.js <原参数>`（路径后续可调，用常量集中写）。
- `handoff-version`：打印 `2`（Rust 版是 `1`；见「从 Rust 版切过来」）。

`run` 时：
1. 解析 `--data`（缺省同 Rust：`$STILLFAIL_DATA`，否则 `$EMBER_DATA`，否则 `~/.stillfail`）。`flock` 住 `<data>/run/station.lock`；拿不到就退出码 3（桌面 app 靠它）。
2. 自己先 bind 两个 TCP 监听：MCP 端口（`config.json` 的端口或 4750，被占用时规则同 `mesh/app/src/ports.rs`）和本机回环口（`--port` 或 4760，规则同 `mesh/station/src/local.rs`），把它们作为继承的 fd 传给 Node（fd 3、4），这样新旧 Node 交接时端口不空档。MCP 端口记在 `<data>/run/mcp.json`，下次启动（stop 之后重启、崩溃后重启）先绑它：留着没重启的 agent 只认得这个地址；绑不上时，Node 打开工具入口后让拿着旧地址的 agent 进程重启并 resume。数据目录不是 `~/.stillfail` 的 station（测试、开发用）不占 4750/4760，没指定端口就用随机端口。
3. 起 Node：`node <app>/station/main.js run --app … --data … --launcher-fds 3,4,5 --launcher-carries`，fd 5 是控制管道（双向，一行一个 JSON）；`--launcher-carries` 说这个启动器会把交接时 Node 交出的内存转给新 Node（见下）。
4. 写 `<data>/run/station.json`（一行、字段与 Rust 版相同：`{"pid":<启动器 pid>,"startedAt":<ms>,"version":…,"handoff":1,"drain":1,"channel":1}`；version 由 Node 在控制管道上告诉启动器；安装器用 sed 读，格式不能变）。
5. 信号：
   - SIGUSR2（交接）：起一个新 Node（同样的 fd），等它在控制管道上说 `{"ready":true}`（超时 60 秒算失败：杀掉新的，写 `run/handoff-failed`，旧的照常）；然后告诉旧的 `{"op":"handover"}`，等它退出（最多 30 秒，超时 SIGKILL）；新的**接管之后**（见下）才更新 `station.json` 的 `startedAt`（pid 不变——安装器靠这个判断交接成功）。
   - station 页右上角 ⋯ 的「重启 station」（管理员，`POST /station/restart`，`station/src/ops/restart.ts`）就是请启动器做这次交接：`run/station.json` 里的 pid、`handoff: 1`，Unix 上发 SIGUSR2，Windows 上往管道写 `{"op":"handover"}`。新进程重新读 config.json（高级网络设置在这时生效），会话不中断；没有启动器（直接从源码跑）时回 409。
   - SIGUSR1（drain）、SIGHUP：转给当前 Node（在控制管道上发 `{"op":"drain"}` / `{"op":"hup"}`）。
   - SIGTERM / SIGINT：转给 Node（`{"op":"stop"}`），等它退出（最多 30 秒），然后自己退出。
6. Node 意外退出（不是启动器让它退的）：按 1s、2s、4s… 最多 60s 退避重启；连续 5 次起不来就退出（交给 launchd）。
7. `--with-parent`：每 2 秒看一次父进程，没了就按 SIGTERM 处理（同 Rust）。
8. 启动器 stderr 照常（launchd 会写日志）；Node 的 stdout/stderr 继承启动器的。

控制管道上 Node → 启动器：`{"ready":true,"version":"0.1.x"}`、`{"serving":"admin"|"mcp","port":N}`（回环口听好了；接手会话、agent 的门开好了）、`{"failed":"…"}`（没能接管：agent 那边没起来）、`{"drained":"idle"|"timeout"}`（启动器照 Rust 版写 `run/drained`）。

交接时旧 Node 收到 `{"op":"handover"}` 先说 `{"carry":{…}}`：各部分只放在内存里、要带到新进程的东西（密钥库的授权，`StationParts.carry`），启动器原样转给新 Node `{"op":"carried","carried":{…}}`，内存到内存，不写盘、不写日志。只有带 `--launcher-carries` 起的 Node 才说这一行：更新只换 Node，启动器是旧的就不认它，会把整行写进日志。进程结束时启动器先读完它管道里剩下的行再处理退出，交出的东西不会因为先看到退出而丢。Windows 的启动器暂不传这个参数：它读管道和等进程退出在两个线程，退出可能先到，最后一行就丢了，要先让等退出的线程等读管道的线程读完。

**生命周期只有一份**（`src/lifecycle.rs`）：上面第 4–7 步（ready、退避重启、连续失败放弃、交接、drain、停止和超时强杀、跟随父进程）是一个与平台无关的状态机，它的测试在三个平台上都会跑。`run.rs`（Unix）和 `run_windows.rs` 只负责三件事：起进程、在控制通道上收发消息、把事件（某行消息、进程结束、停止）告诉状态机。改重启、取消或超时策略只改这一处。各平台不同的只有两点：端口怎么交给 Node（Unix 传 fd，Windows 由启动器转发，见下），判断父进程是否还在时 Unix 用 `getppid` 有没有变，Windows 等父进程的句柄。

交接时“热好了”和“接管了”是两回事：新 Node 说 ready 只表示它能接手；旧 Node 交出会话并退出、新 Node 接上之后，它才开始调度（同一时刻只有一个 Node 在调度）。**接管**＝ready、旧的已经不在、并且 `admin` 和 `mcp` 都说了 `serving`；`station.json` 只在这时写（普通启动也一样）。从开始服务起算 90 秒（`Times::take`）还没接管，或者它说了 `failed`，启动器就结束它，按没起来算（计入连续失败次数），再起一个。

交接失败分两种，启动器都写 `run/handoff-failed`：
- 新 Node 没 ready（起不来、60 秒超时）：旧的照常服务。
- 新 Node ready 了、旧的已经交出会话退出，但新的没接管：结束新的，**等 10 秒**（`Times::rollback`）再起一个。

安装器（两个平台一样）看到 `handoff-failed`、且 station 还是原来那次启动（启动器 pid 活着、`startedAt` 没变），就把旧发布挪回原位、报告失败退出：前一种旧 Node 继续跑，后一种启动器 10 秒后起的是旧发布。**不会重启进一个起不来的新版本**。安装器等交接最多 180 秒（60 秒 ready + 90 秒接管，再留余量）。

### Windows（`src/run_windows.rs`）

只有 `run` 的最小版本，其余命令照旧交给 Node（没有 exec，Node 作为子进程跑，退出码照传）：

- 锁用 `File::try_lock`（LockFileEx），拿不到退出码 3。
- 端口：Windows 上 Node 不支持 `listen({fd})`，所以启动器自己占着 MCP 端口和回环口（规则同 Unix），在中间转发（`src/proxy.rs`）。Node 以 `--launcher-ports <mcp>,<回环口>` 启动，自己听 `127.0.0.1:0`，对外（agent 的 MCP 地址、`run/ports.json`）仍说启动器的端口；门开好后在控制通道上说 `{"serving":"mcp"|"admin","port":N}`。启动器只把连接转给**已经接管**的那个 Node（交接中热好的新 Node 说了也先不转）。
- 转发只管自己的连接：已经建立的连接留在原来的 Node 上，不重放，旧 Node 退出时随之断开（要客户端重新连）；交接空档里新来的连接最多等 60 秒（`ENTRANCE_WAIT`），等到接管的 Node 就转过去，等不到就关掉。所以承诺的是“任务继续、入口不变”，不是“完全无感”。
- 控制通道是命名管道 `\\.\pipe\stillfail-launcher-<pid>-<n>`（只给当前用户），以 `--launcher-pipe` 交给 Node（`src/ops/launcher.ts`），两边的消息同 Unix。
- 没有信号，安装器、`stillfail channel` 改用启动器自己的管道 `\\.\pipe\stillfail-launcher-<pid>`（只给当前用户）发一行 `{"op":"handover"|"drain"|"hup"|"stop"}`，对应 Unix 的 SIGUSR2/SIGUSR1/SIGHUP/SIGTERM（TS 侧在 `platform.askLauncher`）。
- ^C / 控制台关闭 / `--with-parent` 的父进程没了：交给共用的状态机，和 Unix 的 SIGTERM 一样处理。Node 在自己的进程组里，^C 只到启动器。
- Node 意外退出、退避、放弃：同 Unix（共用的状态机）。
- Node 在发布目录里是 `node/node.exe`（Node 官方 Windows 包的布局）。
- `stillfail-station-w.exe`（GUI 子系统，没有窗口）：登录时的计划任务跑它，它再无窗口地跑同目录的 `stillfail-station.exe`，输出追加到数据目录的 `stillfail.log`。`--run <program> <args…>` 则无窗口地跑那个程序（station 自更新用）。

安装、自启动、更新（`cloud/src/install-windows.ts`，`/install.ps1`）：
- 发布包 `stillfail-station-win32-x64.zip`（`scripts/station-bundle.sh win32-x64`），native 部分由 `scripts/native.ts` 在 Mac 上用 cargo-zigbuild 交叉编译（`x86_64-pc-windows-gnu`），和 macOS/Linux 一样走缓存/CI。
- 自启动是当前用户的计划任务（登录时、不需要管理员），结束后 1 分钟再起。`STILLFAIL_TASK`/`STILLFAIL_BIN` 让一台测试 station 用自己的任务名和命令目录，记在 `<data>/windows.json` 里，之后的更新（包括 station 自己发起的）沿用。
- 以管理员运行（可选）：装的时候加 `-Admin`（`irm .../install.ps1 | …` 后传 `-Admin`，或设 `STILLFAIL_ADMIN=1`），计划任务以 `RunLevel Highest` 注册，之后每次登录 station 都直接以管理员起，不再弹 UAC；它起的 agent 子进程继承管理员，多数需要提权的命令（错误 740）不再需要人确认，远程桌面也能操作以管理员运行的窗口。注册 Highest 任务需要这一次装是在管理员权限下跑（弹一次 UAC），用户不在管理员组则退回 Limited。设置记在 `windows.json` 的 `admin:true`，station 自更新沿用（更新计划任务也随之以 Highest 注册，`platform/windows.ts`）。代价：agent 的每条命令都是管理员权限、没有逐条批准，且 station 是 workspace 共享的——个人机、机主自担风险的场景用；共享机的逐条批准方案（SYSTEM 服务）另做。安全桌面上的 UAC 仍点不了，只是 agent 自己基本不会再触发。
- 从 station 页面切换（`elevation/elevation.ts`，overview 的 `elevation`，`PUT /elevation {on}`，workspace 管理员可改）：设置页「管理员」里的「以管理员身份运行」。切换全程旧 station 一直在跑，确认之前什么都不动。① station 起一个自己的 PowerShell，用 `Start-Process -Verb RunAs` 请求 UAC；2 分钟（`ASK_MS`）没人确认就结束它，记为 `unanswered`；被拒绝记为 `declined`。远程画面看不到安全桌面上的 UAC，所以没人点也不会失联。已经以管理员运行时（比如关掉这个开关）不请求 UAC。② 提权后跑 `run/elevation-apply.ps1`：先看截止时间（过了截止时间才点「是」就什么都不做），再改登录计划任务的 RunLevel 和 `windows.json` 的 `admin`，然后注册并启动自己的提权任务「<任务名> elevation」（不是 station 的子进程）。③ 这个任务跑 `run/elevation-restart.ps1`：像更新一样先 drain（最多 10 分钟），停掉 station，再按新的 RunLevel 启动；180 秒内 `run/station.json` 没有出现新的启动，就把 RunLevel 和 `windows.json` 改回去、按原样重新启动，记为 `notStarted`。进行中的步骤和上次失败的原因记在 `run/elevation.json`，station 重启后也能读到。运行 station 的 Windows 账号不在 Administrators 组时不能切换（UAC 会改成要别人的账号密码，任务会注册到别的用户名下）。
- 更新同 install.sh：station 在跑、计划任务没变、`station.json` 说 `handoff:1` 时，旧发布挪到 `app.old-<时间>`（还在跑的启动器、runner 让目录删不掉，挪可以），新发布放到原位，请启动器交接；`startedAt` 变了、pid 没变就是交接成功，启动器不重启。交接失败且旧的还在服务：挪回旧发布、报告失败。其余情况（第一次装、任务变了、交接失败且旧的已经不在）先 drain，再停（停任务、结束 launcher，按命令行里含 `<app>` 等 Node 退出）、换发布、重启。
- 安装器在 PowerShell 里作为脚本块运行（`& ([scriptblock]::Create(...))`），那里的 `$script:` 是调用者的作用域：函数要改的状态放在一个哈希表里（`cloud/test/install-windows.test.ts` 守着不出现 `$script:`/`$global:`）。
- `.cmd` 文件里只写 ASCII：cmd 按控制台代码页（中文系统 936、英文 437）读 .cmd，不是 UTF-8，所以 `C:\Users\张三\…` 写成 ASCII 会变成 `??`，写成 UTF-8 会读乱。含非 ASCII 的路径写成它所在的环境变量（`%USERPROFILE%\.stillfail\…`），cmd 运行时按 Unicode 展开。安装器的 `stillfail.cmd`（`CmdPath`/`WriteCmd`）和 station 的 `.cmd` 外壳（`platform/windows.ts` 的 `cmdPath`）用同一条规则；不在任何这类目录下时，安装器退而用系统 OEM 代码页写（能表示才写，否则报错），station 报错不写。
- station 从页面上自更新（`updates.ts` 的 `startInstaller`）：把这个版本自带的 `bin/install.<lang>.ps1` 复制成 `run/install.ps1`（签名校验见 [release-signing.md](release-signing.md)），写 `run/update.ps1`，复制 `stillfail-station-w.exe` 到 `run/`，注册一次性计划任务「<station 的任务名> update」去跑它，跑完自己删掉任务；`update.step`/`update.log`/`update.exit` 同 Unix。不用 WMI 的 `Win32_Process.Create`：那样起 PowerShell 会被安全软件拒（实测“Access is denied”）。

### 从 Rust 版切过来

Rust 版 station 交接前会先问新二进制 `handoff-version`，只有回答 `1` 才 exec 它并传 fd。启动器回答 `2`，Rust 版就不走 exec 交接（会写 `run/handoff-failed`），安装器再走普通重启：正在跑的轮次照现在的规则在新 station 上续写。这只在从 Rust 换到 TS 的那一次发生。具体在第 5 期（切换）里验证和调整。

### station 的 TS 代码：平台差异只在 `src/platform/`

station 的逻辑在 macOS、Linux、Windows 上是同一份。各平台不同的地方都在 `src/platform/` 里：`index.ts` 是接口，`unix.ts`（macOS 和 Linux，两者的差异也只在这里）和 `windows.ts` 是实现。业务代码只问 `platform` 要它想做的事，比如结束一个任务的进程组、让一个脚本能被别的程序按名字运行、按 Rust `Path::join` 的规则拼路径；只有某个平台才有的功能，用一个能力开关表示（`hasKeychain`、`hasQuickLook`）。

`station/test/platform.test.ts` 守着这条规则：`src/platform/` 以外的代码一出现 `process.platform`、`win32`、`WINDOWS`，测试就失败。它也在每台机器上测两个平台的路径规则（都是纯函数），所以 Windows 的路径规则在 macOS 和 Linux 的 CI 上也会被测到。

## 3. mesh 插件（`station/native/mesh`，Node 插件 `mesh.node`）

在原型（分支 proto-rust-shell-ts 的 `proto/ts-station/native`）基础上补齐 station 的 iroh 用法（`mesh/station/src/main.rs` `serve_mesh`、`keep.rs`、`peer.rs`）：
- `bind({secretKey, alpns, relayUrls, discovery})`：同原型；另加 `online()`（等到连上家 relay）、`setRelays(urls)`（cloud 推来新的 relay 列表）、`home()`（当前家 relay）。
- 同时挂在所有 relay 上：`bind` 时给的每个 relay 各有一条到 relay 的连接，地址里写着全部（vendored iroh 的 `home_on_every_relay`），一条连接到它就有经每个 relay 的路径；每条路径每秒保活一次，3 秒收不到就放弃（`PATH_KEEP_ALIVE`、`PATH_IDLE`），包改走别的路径，relay 回来后路径重开。
- keeper：`keep(urls)` 只给 bind 之后才加进来的 relay 起一个只挂这个 relay 的附属 endpoint（ALPN `stillfail/keep/1`），bind 时就有的不再要。
- 连接：`connect(addr, alpn)`（站间 peer 用），`Connection.paths()`（relay 还是直连，给 trace 用）、`closed()`、`close(code, reason)`、`acceptBi/openBi`。
- 流：`read()`、`write()`、`finish()`、`reset()`、`stopped()`。
- 所有异步操作不阻塞 Node 主线程（napi async，tokio 多线程运行时）。
- 缩略图（`src/thumbs.rs`，就是当时 Rust station 的 `thumbs.rs`，`image`/`thumbhash` 及其编解码 crate 钉在它当时的版本上（station/native/mesh/Cargo.lock），产出与 Rust 版逐字节相同）：`thumbnail(image, dir)` → `{path, type}` 或 null；`thumbhash(image, dir?)` → `{hash, width, height}` 或 null，给了 `dir` 且图大于 24 KiB 时用同一次解码在后台线程做缩略图。哪些文件、何时做由 TS（`src/drive/thumbs.ts`）决定。

## 4. still.fail Helper（`station/native/helper`，`still.fail Helper.app`，只有 macOS）

station 在 macOS 上要系统授权的事都放在这个 app 里：本机屏幕（[remote-screens.md](remote-screens.md)）和「文件」里 macOS 保护的文件夹（文稿、桌面、下载、外接和网络磁盘，[drive.md](drive.md)），以后摄像头这类也加在这里，共用一个授权身份（bundle id `fail.still.helper`）。本机启动的 iOS 模拟器的画面和操作（`simulator.view`，不需要授权，用 `vendor/serve-sim` 的采集和注入）也在这里，和本机屏幕共用编码和消息格式。为什么是单独的 app：屏幕录制、辅助功能这类授权要进程重启才生效，授权给 station 的启动器就得重启 station；给 helper，只重启 helper。

- Swift 写（ScreenCaptureKit、VideoToolbox、CGEvent、SwiftUI 授权窗口），授权窗口照搬 Cue 的 Computer Use，用 `vendor/PermissionFlow`（改动见 vendor/README.md）。`scripts/native.ts` 的 part `helper`（darwin-arm64）用这台 Mac 的 Xcode 编，装进 `still.fail Helper.app`（`Info.plist` 在包目录里，LSUIElement；图标由 `apps/desktop/icon.png` 生成 `AppIcon.icns`，授权窗口和系统设置里显示它）并 ad hoc 签名；发布时 `station-bundle.sh` 放在 `station/` 里 `mesh.node` 旁边，用 `fail.still.helper` 重签。TCC 按 bundle id 加签名要求记授权，同一证书签的新版本沿用授权。
- station（`src/helper/app.ts`）先把它拷到 `<data>/helper/`（不在别的 app 里面：桌面 app 里 station 在 still.fail.app 内部；代码变了才重拷，并让旧的退出），再用 `open -n -g --env …` 交给 LaunchServices 启动，这样它自己就是 TCC 的“负责进程”。之后在 `<data>/helper/helper.sock` 上一个连接一个请求：先一行 `{token, op, …}`（token 在 `<data>/helper/token`，0600，station 交接后的新进程照样连得上），op 有 `hello`、`status`、`permissions.show`（`grants` 指定窗口里的几行）、`screen.view`（之后这个连接收发画面消息）、`files.*`（保护文件夹的列表、读写等，字节在连接上流式传，`Files.swift` 开头写协议）、`restart`、`quit`，协议写在 `main.swift` 开头。没人连 30 分钟它自己退出，station 停止时让它退出，要用时再起。
- 授权后：窗口关闭时如果期间有新授权，它用同一个 socket 和 token 重新启动自己；打开画面时发现“授权了但本进程还没生效”也会先重启，station 等它回来再开一次。文件夹的授权（文件与文件夹）只能由 macOS 自己的弹框给：窗口里点「允许」时 helper 去打开那个文件夹，macOS 就问一次，允许后立刻生效、不用重启；helper 没授权时从不碰那个文件夹（否则弹框没人点会一直卡住调用）。窗口看到授权变化会在 `watch` 连接上告诉 station（`{event: "grants"}`）。
- macOS 授权后自己的「退出并重新打开」会不带参数启动它：它从 app 旁边（`<data>/helper/`）读 `helper.sock` 和 `token`，照样服务。一个目录只跑一个（旁边的 `helper.lock`，自己重启时新进程等旧的放锁）。station 用一条一直开着的 `watch` 连接盯着它：它不是被要求退出却结束了（macOS 没重新打开、崩溃），station 等 3 秒看它自己回不回来，不回来就再启动；回来后如果还缺授权，再弹授权窗口（只剩缺的那几行）。

## 5. stillfail-screen（`station/native/screen`，可执行文件 `stillfail-screen.exe`，只有 Windows）

Windows 上本机屏幕（[remote-screens.md](remote-screens.md) 的 `desktop`）由它采集和操控，相当于 macOS 上的 still.fail Helper，但不需要授权：station 作为登录时的计划任务跑在用户自己的会话里，那里的屏幕本来就能采集、能输入。

- Rust 写（`windows` crate）：Windows.Graphics.Capture 采主显示器（带鼠标指针，Windows 11 上不显示黄框；Windows 11 24H2 起用 DirtyRegions 跳过没变化的帧），D3D11 视频处理器在 GPU 上缩放并转成 NV12，Media Foundation 编 H.264（优先用接受 D3D11 纹理的硬件编码器，比如 NVIDIA、Intel、AMD 的 MFT，异步模式；没有就用微软的软件编码器），低延迟、没有 B 帧，优先 constrained baseline；不收 H.264 的画面（agent 的截图）用 WIC 编 JPEG。输入用 `SendInput`：键盘按扫描码发（与键盘布局无关，键码表在 `src/screens/win-input.ts`），文字按 Unicode 发。剪贴板支持文本和 PNG（另放一份 DIB，给不认 PNG 的程序用）；其他程序占着剪贴板时会重试一会儿。
- `scripts/native.ts` 的 part `screen`（win32-x64），和 runner 一样在 Mac 上用 cargo-zigbuild 交叉编译成 MinGW 的 exe；`station-bundle.sh` 把它放在 `station/` 里 `mesh.node` 旁边，桌面 app 跟着带上。
- station（`src/screens/win-desktop.ts`）每开一个画面就起一个 `stillfail-screen view` 进程：stdin 先写一行请求 `{codec, maxWidth, maxHeight}`，之后双向传的消息和 helper 的 `screen.view` 连接上的一样（`desktop.ts` 的 `HelperView` 两边共用；消息格式写在 `src/main.rs` 开头），stdin 关掉进程就退出。显示器尺寸由 `stillfail-screen status` 给出。进程自己退出时（显示器拔掉或主显示器换了、显卡驱动重启、崩溃），station 会再起一个，画面从关键帧和 config 接着放，用户无感；一分钟内超过三次就结束这个画面。编码器 2 秒没吐回一帧就重建。
- 采不到的：登录界面和 UAC 的安全桌面（Windows 不让任何程序采）；以管理员身份运行的窗口收不到输入（UIPI）。
