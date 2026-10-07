# station 托管组件

2026-10-07 定（左子健）：嵌入 station 的 app 可以把自己的常驻程序交给本机的 station 运行，station 负责启动、重启、替换和结束它。第一个用户是 Comma 桌面版：它把自己的 connector（`salix-connect`）交给 station，不再自己装 launchd 服务。托管组件和 station 是否加入 workspace 无关：没有加入任何 control plane 的 station 也照样运行它们。

代码：`station/src/components/components.ts`，测试：`station/test/components.test.ts`。

## 声明

app 在 `<data>/components/<name>.json` 写一个声明（`<name>` 是小写字母、数字和 `-`，最长 64）：

```json
{
  "command": "/Applications/Comma.app/Contents/Resources/native/darwin/arm64/salix-connect",
  "args": ["--config", "/Users/me/Library/Application Support/Comma Staging/connector/config.json"],
  "env": {},
  "cwd": "/Users/me",
  "version": "1.0.8-staging.749"
}
```

- `command` 必须是绝对路径；`args`、`env`、`cwd`、`version` 可省。`env` 加在 station 自己的环境之上；`cwd` 不给时是数据目录。
- 声明的内容就是组件的身份：内容变了就替换（先结束旧的，确认退出后再起新的）。app 原地换了程序文件（升级）时，改 `version` 让 station 换上新的。
- 删掉声明就结束组件，`run/components/<name>.json` 也一起删掉。
- 写声明时先写临时文件再改名，避免 station 读到半个文件。以 `.` 开头的文件不算声明。

## station 怎么运行

- 每个组件在自己的进程组里运行（和后台 job 一样），日志在 `<data>/logs/components/<name>.log`，超过 10 MB 时在下次启动前挪到 `.1`。
- 结束了就再启动：稳定运行超过 60 秒后结束的立刻重启，否则等待 1、2、4……秒，最长 60 秒（与 job 的服务同一规则）。
- 结束组件时先给进程组发 SIGTERM，5 秒后还在就 SIGKILL。
- 组件比 station 活得长：station 更新、交接或崩溃时组件继续运行，下一个 station 启动时按记录的进程组（pid 复用的检查同 job）接管，不会重启它。station 停下时不结束组件。

## app 读状态

`<data>/run/components/<name>.json`（整文件替换写入）：

| 字段 | 含义 |
|---|---|
| `state` | `running`：进程组在运行；`waiting`：结束了，等待重启；`invalid`：声明无法运行，见 `error` |
| `version` | 正在运行的声明的 `version` |
| `spec` | 声明内容的哈希 |
| `pgid`、`startedAt` | 进程组和它的启动时间（机器时间，毫秒） |
| `restarts` | 上次稳定运行以来重启了几次 |
| `lastExit` | 上次结束：`code`（被信号结束时为 null）和时间 |
| `error` | `invalid` 时的原因 |
