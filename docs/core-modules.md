# core 的模块

client core（`client/core-ts`）是各个 app 共用的平台：账号、still.fail cloud、和 station 的连接、本机库、call 和 topic。app 自己的东西做成**模块**，启动 core 时传进去：

```ts
Core.create(host, { modules: [media] });
startBridged(native, cloudOrigin, beta, os, onFatal, { modules: [media] }); // 原生宿主
startWeb(emit, testChannel, loadIroh, onFatal, loadSqlite, [media]);        // web 的 worker
start(dataDir, cloudOrigin, listener, channel, { modules: [media] });       // Node（桌面）
```

still.fail 自己现在不传模块（`hosts/hermes.ts`、web、桌面照旧）。聊天这些还写在 core 里，以后再一块块搬成模块。

## 一个模块有什么（`src/module.ts`）

`CoreModule = { name, install(env) }`。`install` 在平台装好之后调用一次，返回：

- `calls`：按名字列出的 call，UI 用 `<模块>.<名字>` 来调。每个 call 都有：
  - `parse(params, bytes)`：检查参数，不对就抛 `CoreError.invalid`；
  - `run(p, at)`：执行，返回 Effect；`at.progress` 用来报进度、发字节；
  - 可选的 `station`（这个 call 涉及哪台 station，写进 trace）、`counts`（是不是人在等的操作，会出现在 `doing` 里）、`cancellable`（UI 能不能取消，页面走了也会停）。
- `topics`：一个 `Owner`（`core/routing.ts`），负责名为 `<模块>.…` 的 topic：`start`/`stop` 时开始和停止同步，`compute` 从本机已有的数据算出值。它只会被问到自己名下的 topic。
- `keyed`：自己 topic 里按 key 增量的列表（`collections.ts` 的 `Spec`）。

`env`（`ModuleEnv`）是模块能用到的 core：

- `request` / `exchange` / `stream`：请求这个模块在 station 上的部分，路径都在 `/admin/api/m/<模块>/…` 下（station 那边见 docs/station-modules.md）。走的是平台的连接、凭证、压缩和状态，和 drive 的请求一样。
- `kept` / `keep`：模块在本机按 station 存的值，放在能到达这台 station 的那个账号的库里（`station` 表，kind 是 `/m/<模块>/<名字>`）。`keep` 会让对应的 topic 重新计算。
- `changed`：让一个 topic 重新计算；`fork`：后台跑的活，core 关闭时停掉；`nowMs`。

## 规则

- 名字：小写字母开头，只有小写字母和数字，最长 32 位，不能和别的模块重名（重名或不合规，`Core.create` 失败）。
- core 自己的 call 先匹配：模块里和平台同名的 call 永远不会被调到。topic 用 `<模块>.` 开头，平台的 topic 名里不带点，所以不会撞。
- 模块不 import 聊天的代码（views、attention、composer……）：它只经 `env` 和平台打交道，这样以后聊天搬出去，模块不受影响。
- 原生宿主的 bundle：app 自己写一个入口，调用 `startHermes([模块…])`（`hosts/hermes-start.ts`），然后用 `node scripts/hermes-bundle.ts --entry <入口> <out.js> [<out.hbc>]` 打包。引擎这一侧不变（`__stillfail.start(cloudOrigin, beta[, os])`，多了一个可选的 `os`，默认是 `android`）。

测试：`client/core-ts/test/modules.test.ts`。
