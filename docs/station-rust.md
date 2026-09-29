# station：Rust

station 是一个 Rust 程序：`ember-station`（mesh/station）一个进程运行整个 station，station 本身是 ember-app（mesh/app），在同一个进程里。数据格式和 client core 共用 `client/shapes`。只装一个二进制，不带 Node。

## 现在的结构

- **`ember-station`（mesh/station）**：连着 still.fail cloud，接受 mesh 连接，在 127.0.0.1 提供本机管理页（默认 4760，被占时自动换），也负责 `enroll`（加入 workspace）和 `id`。
- **ember-app（mesh/app）**：station 自己的活——SQLite 存储（`store`）、管理 API（`admin`）、运行时驱动（`runtime`：Codex app-server、Claude Code stream-json）、会话 / Hub / live 转写、agent 的 MCP 端点（`mcp`）、Slack（`chat`）。
- **发布包**：只有 `bin/ember`、`dist/admin`（管理页和 posthog.json）、`mesh/target/release/ember-station` 和 `VERSION`（scripts/station-bundle.sh）。

`ember-station` 能单独运行（launchd / systemd），也能由桌面端作为子进程运行：桌面端打包同一个 `ember-station`，用 `run --app … --data … --with-parent` 启动（apps/desktop/src/station.ts），随应用退出；数据目录已经有别的 station 在跑时它以 HELD 退出，桌面端就用已有的那个，不重复运行。登录后桌面端把本机加入当前 workspace（只自动做一次，apps/desktop/src/main.ts）。

## 历史与兼容

station 原来是 Node/TypeScript，由它启动 ember-mesh。迁移逐块进行，不做一次性重写，每一步结束时 station 都能完整工作、可以部署；最后去掉 Node（d7232dd）。

迁移期间的结构：Rust 的 `ember-station` 是主进程（launchd 启动），连着 still.fail cloud、接受 mesh 连接、提供本机管理页，并启动、看护 Node 子进程；Node 只负责还没迁走的部分，管理接口不再监听 TCP，改听数据目录里的 Unix socket（`run/admin.sock`）；Rust 收到 `/admin/api/...` 请求，已迁的路径自己处理，其余转给 Node；在线状态以 Node 是否就绪为准。

步骤（都已完成）：

1. 倒转主次，去掉管理端口：Rust 接替 Node 做主进程，安装脚本、launchd、`ember` 命令都改成启动 Rust 程序。
1.5 桌面端自带 station：打包 `ember-station`，登录后自动把本机加入当前 workspace，随应用启动和退出；已经装过独立 station 的机器用已有的那个。
2. station 的类型也从 `client/shapes` 来，station 到 core 这一段由契约管住。
3. 存储迁到 Rust：先读后写，期间 Node 和 Rust 共用同一个库（WAL）。
4. 管理接口迁到 Rust，按资源一组一组来：overview、profiles、connects、threads、sessions、slack apps、logins。
5. 运行时驱动迁到 Rust：Codex（app-server JSON-RPC）、Claude Code（stream-json），以及会话、Hub、live 转写和执行历史的来源。
6. MCP 端点迁到 Rust。
7. Slack 迁到 Rust：Socket Mode 客户端、消息收发、App 的创建和安装（Rust 没有官方 SDK，自己写）。
8. 去掉 Node：安装包里不再带 Node。

每一步的要求：迁过去的部分行为不变（按现有 TypeScript 测试的场景在 Rust 里写测试）；迁完一块就删掉 Node 里对应的代码，不留两份；在 studio 上完整跑通、部署后才开始下一步。

和 Node 版的兼容：

- 数据目录照旧：ember.db 同一套表结构和 schema 版本，config.json、登录、agent 的家目录都一样。
- Node 版留下的 `run/admin.sock` 和数据目录里的 `rust` 文件（当年切到 Rust 的开关）都不再读。
- 旧的启动方式传的 `--node` 照收不误（mesh/station/src/main.rs）：旧版桌面端、旧的 launchd/systemd 定义启动新的 `ember-station` 也能跑。
