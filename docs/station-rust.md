# station 迁到 Rust

目标：station 最终是一个 Rust 程序（和 ember-mesh 合成一个），数据格式和 client core 共用 `client/shapes`，只装一个二进制，本机不再需要管理端口。

客户端也自带一个 station：桌面端打包同一个 `ember-station`，自己启动、自己看护，本机就是一台 station，不用另外安装。所以 `ember-station` 要能单独运行（launchd），也要能由桌面端作为子进程运行（数据目录、端口、生命周期都由启动它的一方决定）。

做法：逐块迁移，不做一次性重写。每一步结束时 station 都能完整工作、可以部署。

## 现在的结构

迁移已完成（第 8 步）：`ember-station`（mesh/station）一个进程运行整个 station，station 本身是 ember-app（mesh/app），在同一个进程里。它连着 ember cloud，接受 mesh 连接，在 127.0.0.1 提供本机管理页（端口被占时自动换），agent 的 MCP 端点也在它里面。发布包里只有 `bin/ember`、`dist/admin`（管理页和 posthog.json）、`mesh/target/release/ember-station` 和 `VERSION`（scripts/station-bundle.sh），不带 Node。

和 Node 版的兼容：数据目录照旧（ember.db 同一套表结构和 schema 版本，config.json、登录、agent 的家目录都一样），Node 版留下的 `run/admin.sock` 和数据目录里的 `rust` 文件（当年切到 Rust 的开关）都不再读。旧的启动方式传的 `--node` 照收不误：旧版桌面端、旧的 launchd/systemd 定义启动新的 `ember-station` 也能跑。

下面是迁移时的记录。

## 迁移期间的结构

一开始是 Node 的 station 启动 ember-mesh。第一步把主次倒过来：

- **Rust 进程（`ember-station`）是主进程**：由 launchd 启动。它连着 ember cloud，接受 mesh 连接，提供本机管理页，并负责启动、看护 Node 进程。
- **Node 进程是它的子进程**：只负责还没迁走的部分。它的管理接口不再监听 TCP 端口，改为监听数据目录里的 Unix socket（`run/admin.sock`），只有 Rust 进程会连它。
- **管理接口按路径分流**：Rust 收到一个 `/admin/api/...` 请求，已经迁到 Rust 的路径自己处理，其余转发给 Node。迁一块，就把一块路径改由 Rust 处理。
- **Agent 的 MCP 端点**：暂时留在 Node。Claude Code 和 Codex 只能连 HTTP 地址，所以仍用本机 TCP 端口，被占时自动换空闲端口（已实现）。

## 步骤

1. **倒转主次，去掉管理端口。**
   - Rust 的 `ember-station` 接替 Node 成为主进程，负责启动和重启 Node。
   - Node 的管理接口改走 Unix socket；mesh 转发和本机管理页都经 Rust 转到这个 socket。本机管理页仍由 Rust 在 127.0.0.1 提供，端口被占时自动换。
   - 在线状态以 Node 是否就绪为准，不会再出现"mesh 在线、station 已挂"。
   - 安装脚本、launchd、`ember` 命令都改成启动 Rust 程序。

   验证：本机管理页、mesh 访问、agent 会话都照常；Node 崩溃后会被拉起，期间对外显示离线。

1.5 **桌面端自带 station。** 桌面端打包 `ember-station`（和它需要的 Node 部分），登录后自动把本机加入当前 workspace，随应用启动和退出；已经装过独立 station 的机器用已有的那个，不重复运行。
   Node 部分照发布包原样带上（包括它自己的 Node），不做瘦身：第 8 步就去掉了。

2. **station 的类型也从 `client/shapes` 来。** Node 的 TypeScript 类型改由同一份定义生成，Rust 那边直接用。station 到 core 这一段也由契约管住。

3. **存储迁到 Rust。**
   - SQLite 的库、表结构和迁移由 Rust 负责。
   - 先让读接口（会话、线程、条目、侧栏行）由 Rust 直接回答；Node 暂时还写同一个库（WAL 支持多进程读写）。
   - 再把写入也搬过来，Node 改为通过 socket 调用 Rust 的存储接口。

4. **管理接口迁到 Rust**，按资源一组一组来：overview、profiles、connects、threads、sessions、slack apps、logins。

5. **运行时驱动迁到 Rust**：Codex（app-server JSON-RPC）、Claude Code（stream-json），以及会话、Hub、live 转写和执行历史的来源。

6. **MCP 端点迁到 Rust。**

7. **Slack 迁到 Rust**：Socket Mode 客户端、消息收发、App 的创建和安装。Rust 没有官方 SDK，这一块要自己写。

8. **去掉 Node。** 安装包里不再带 Node。（已完成）

## 每一步的要求

- 迁过去的部分行为不变：用现有 TypeScript 测试对应的场景，在 Rust 里写测试。
- 迁完一块，删掉 Node 里对应的代码，不留两份。
- 能在 studio 上完整跑通、部署后，才开始下一步。
