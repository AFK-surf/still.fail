# station 的部分：进程内的模块（parts.ts）

和聊天、agent 绑得紧的功能（库、事件流、hub），不单独起进程，而是作为 station 进程里的一个「部分」：一个由组合根（`main.ts`）点名的 layer，在平台和 agents 之后构造，构造时经 `Parts` 服务说清自己往哪些面上加了什么：

- `routes`：管理 API 的路由，排在平台自己的之后；
- `viewerMay`：只读成员可以对它做的写（比如自己的标记）；
- `overview`：overview 里的字段，一个字段只能有一个部分说；
- `tools`：给 agent 的 MCP 工具。

这些都在被用到的时候才读（每个请求、agent 每次列工具），所以先构造好的管理 API 和 agents 也能拿到。没有全局注册表：一个部分在不在 station 里，只看 `main.ts` 有没有列它。

第一个搬过来的是 vault（`vault/module.ts`）：自带的表、两组路由、agent 的 secret 工具、`vault-request` 事件都由它自己挂上，agents 和管理 API 里不再有 vault 的代码。

agents 那一侧的部分（slack）还要跟着 agents 的节奏：`Agents` 给它们几个钩子。`surfaces` 说 connect 的聊天在哪里，hub 从那里收、往那里发；`slackView` 提供 overview 里 connect 的状态；`along` 注册几件事，agents 会按自己需要的顺序 await 它们：会话接管之后、恢复之前（`taken`），station 进入 workspace 时（`joined`），离开时、会话挂起之后（`left`），某个加入的 workspace 进出时（`changed`）。agents 要等 station 整个装好（所有部分都挂上了，`Up`）才接管会话。部分比 agents 后构造、先关闭，所以 Slack 会在会话交接之前断开，事件从这时起交给下一个进程。

聊天和 agent 的核心（hub、会话、jobs、远程任务、账号、共享）本身也是这样一个部分：平台（mesh、drive、services、管理 API）不 import 它，只经平台的服务和它打交道：`AgentsSide`（agents 构造好后放在这里，管理 API 的会话和聊天路由在请求进来时才去问）、`MeshSide`（mesh 和 agents 各自往里填：relay 状态、站间网页转发、端口转发、跨 workspace 的请求、设备工具看到的 runtime）、`Parts`（agents 自己的路由：更新、环境变量、跨 workspace 共享、账号、overview）。`station/test/platform-apart.test.ts` 守着这条：平台的文件只能 import agents 的类型。
