# TS station 的原生部分：启动器、runner、mesh 插件

方案见 `docs/station-ts.md`。这三件用 Rust 写，各有版本号，预编译发布；TS 那边只按这里的约定用它们。

## 1. runner（`station/native/runner`，可执行文件 `stillfail-runner`）

一个 agent 进程（claude、codex app-server）一个 runner。station 重启或崩溃时 runner 和 agent 都不受影响，新 station 重新接上，从没读过的地方接着读。

启动：
```
stillfail-runner --dir <run/runners> --id <id> [--cwd <dir>] -- <program> <args…>
```
- 环境变量原样传给 agent（station 在启动 runner 时就把 agent 的环境配好）。
- runner 先 `setsid()`（离开 station 的进程组和会话，launchd 结束 station 时不会带走它），再 fork 出 agent：agent 自己 `setpgid(0,0)` 成一个进程组（station 按 pgid 结束 agent 及其子进程，与现在一样）。
- 写 `<dir>/<id>.json`（0600，原子写）：`{"id","runner":pid,"pid":agent pid,"pgid","startedAt":ms,"program","args","socket":"<dir>/<id>.sock","out":"<dir>/<id>.out","err":"<dir>/<id>.err"}`。
- agent 的 stdout、stderr 原样追加到 `<id>.out`、`<id>.err`（不改内容）。stdin 由 runner 持有。
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

## 2. 启动器（`station/native/launcher`，可执行文件 `stillfail-station`）

替换现在的 `mesh/target/release/stillfail-station`，命令行与之相同（`bin/stillfail`、桌面 app、安装器都调它）：

- `run --app DIR [--port N] [--data DIR] [--with-parent] [--handoff FILE]`：启动器自己处理，见下。
- `enroll …`、`status`、`id`、`channel …`：直接 `exec` Node：`<app>/node/bin/node <app>/station/main.js <原参数>`（路径后续可调，用常量集中写）。
- `handoff-version`：打印 `2`（Rust 版是 `1`；见「从 Rust 版切过来」）。

`run` 时：
1. 解析 `--data`（缺省同 Rust：`$STILLFAIL_DATA`，否则 `$EMBER_DATA`，否则 `~/.stillfail`）。`flock` 住 `<data>/run/station.lock`；拿不到就退出码 3（桌面 app 靠它）。
2. 自己先 bind 两个 TCP 监听：MCP 端口（`config.json` 的端口或 4750，被占用时规则同 `mesh/app/src/ports.rs`）和本机回环口（`--port` 或 4760，规则同 `mesh/station/src/local.rs`），把它们作为继承的 fd 传给 Node（fd 3、4），这样新旧 Node 交接时端口不空档。
3. 起 Node：`node <app>/station/main.js run --app … --data … --launcher-fds 3,4,5`，fd 5 是控制管道（双向，一行一个 JSON）。
4. 写 `<data>/run/station.json`（一行、字段与 Rust 版相同：`{"pid":<启动器 pid>,"startedAt":<ms>,"version":…,"handoff":1,"drain":1,"channel":1}`；version 由 Node 在控制管道上告诉启动器；安装器用 sed 读，格式不能变）。
5. 信号：
   - SIGUSR2（交接）：起一个新 Node（同样的 fd），等它在控制管道上说 `{"ready":true}`（超时 60 秒算失败：杀掉新的，写 `run/handoff-failed`，旧的照常）；然后告诉旧的 `{"op":"handover"}`，等它退出（最多 30 秒，超时 SIGKILL）；更新 `station.json` 的 `startedAt`（pid 不变——安装器靠这个判断交接成功）。
   - SIGUSR1（drain）、SIGHUP：转给当前 Node（在控制管道上发 `{"op":"drain"}` / `{"op":"hup"}`）。
   - SIGTERM / SIGINT：转给 Node（`{"op":"stop"}`），等它退出（最多 30 秒），然后自己退出。
6. Node 意外退出（不是启动器让它退的）：按 1s、2s、4s… 最多 60s 退避重启；连续 5 次起不来就退出（交给 launchd）。
7. `--with-parent`：每 2 秒看一次父进程，没了就按 SIGTERM 处理（同 Rust）。
8. 启动器 stderr 照常（launchd 会写日志）；Node 的 stdout/stderr 继承启动器的。

控制管道上 Node → 启动器：`{"ready":true,"version":"0.1.x"}`、`{"drained":"idle"|"timeout"}`（启动器照 Rust 版写 `run/drained`）。

### 从 Rust 版切过来

Rust 版 station 交接前会先问新二进制 `handoff-version`，只有回答 `1` 才 exec 它并传 fd。启动器回答 `2`，Rust 版就不走 exec 交接（会写 `run/handoff-failed`），安装器再走普通重启：正在跑的轮次照现在的规则在新 station 上续写。这只在从 Rust 换到 TS 的那一次发生。具体在第 5 期（切换）里验证和调整。

## 3. mesh 插件（`station/native/mesh`，Node 插件 `mesh.node`）

在原型（分支 proto-rust-shell-ts 的 `proto/ts-station/native`）基础上补齐 station 的 iroh 用法（`mesh/station/src/main.rs` `serve_mesh`、`keep.rs`、`peer.rs`）：
- `bind({secretKey, alpns, relayUrls, discovery})`：同原型；另加 `online()`（等到连上家 relay）、`setRelays(urls)`（cloud 推来新的 relay 列表）、`home()`（当前家 relay）。
- keeper：`keep(relayUrl)` 起一个只挂这个 relay 的附属 endpoint（ALPN `stillfail/keep/1`），`unkeep(relayUrl)`。
- 连接：`connect(addr, alpn)`（站间 peer 用），`Connection.paths()`（relay 还是直连，给 trace 用）、`closed()`、`close(code, reason)`、`acceptBi/openBi`。
- 流：`read()`、`write()`、`finish()`、`reset()`、`stopped()`。
- 所有异步操作不阻塞 Node 主线程（napi async，tokio 多线程运行时）。
- 缩略图（`src/thumbs.rs`，就是 `mesh/app/src/thumbs.rs` 的代码，`image`/`thumbhash` 及其编解码 crate 钉在 `mesh/Cargo.lock` 的版本上，产出与 Rust 版逐字节相同）：`thumbnail(image, dir)` → `{path, type}` 或 null；`thumbhash(image, dir?)` → `{hash, width, height}` 或 null，给了 `dir` 且图大于 24 KiB 时用同一次解码在后台线程做缩略图。哪些文件、何时做由 TS（`src/sessions/thumbs.ts`）决定。
