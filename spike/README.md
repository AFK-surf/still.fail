# Spike

验证设计里依赖、但尚未实测的假设。每项留下脚本和结论，结论写明日期与运行时版本。

| # | 问题 | 影响的设计 |
|---|---|---|
| 1 | `claude -p` 在空闲和活跃时的真实内存占用（整个进程树） | 内存估值、warm 时长 |
| 2 | 一个 codex app-server 承载 N 个 thread 时，每个 thread 的内存增量 | Codex 进程复用 |
| 3 | HTTP MCP 通过环境变量传 token，Claude 与 Codex 都能鉴权 | Tool Bridge |
| 4 | 会话记录归档后解压回原路径，两家都能 resume | 磁盘归档与唤醒 |
