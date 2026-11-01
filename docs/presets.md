# 预设

2026-11-01 用户定：别的 agent harness 的「project」在 still.fail 做成**预设**：开对话时选一个，提前给 agent 上下文（要用的目录、人写的要求），但不把 agent 关进某个目录，它照旧在自己的会话工作区里跑、哪里都能去。开对话时选定，之后不能换（换了也撤不掉已经读进去的东西）；要换就开新对话。建预设时最要紧的是加目录方便。

## 存在哪

- 一个 workspace 的预设是它 agent home 里的 `presets.json`（主 workspace 在 agent home 根上，加入的 workspace 在 `workspaces/<ws>/`，`sessions/agent-home.ts` `workspaceAgentHome`）：`{presets: [{id, name, dirs: [{path, repo}], instructions, createdBy, createdAt, updatedAt}]}`。目录是这台 station 上的路径；`repo` 是它是哪个仓库的克隆（origin，写成 `github.com/owner/name`），不是仓库就没有。
- 对话用预设开时，station 把那一刻的预设抄一份放进会话工作区的 `.stillfail-preset.json`：之后预设改了、删了，已经开的对话都照旧。

## 接口（`api/routes/presets.ts`）

| 请求 | 做什么 |
|---|---|
| `GET /presets` | `{presets, candidates}`：本 workspace 的预设，和新建时给人挑的目录 |
| `POST /presets {name, dirs, instructions?}` | 新建；`dirs` 每个是这台机器上的目录（`~` 是家目录），不是目录就 400 |
| `PUT /presets/:id {name, dirs, instructions?}` | 改 |
| `DELETE /presets/:id` | 删 |
| `POST /sessions {…, preset}` | 用它开对话；不是本 workspace 的预设就不开 |

`candidates`：给人挑的目录，不用打字。两部分合起来：
- station 仓库缓存（`<data>/repos`）里的每个克隆，带「有多少个对话在里面建过 worktree」（从 `.git/worktrees/*/gitdir` 读出是哪个会话工作区）；
- 这台机器上可能是仓库的目录（`RepoIndex`，2026-11-01 用户：「应该先索引出可能是仓库的目录，用来提供选择」）：从家目录往下最多 4 层找有 `.git` 的目录，找到就不再往里走；跳过隐藏目录、`node_modules` 这类依赖和构建目录、`Library` 等，以及 macOS 读之前要弹框问人的 `Desktop`、`Documents`、`Downloads`（会在那台机器屏幕上弹授权框），也跳过 station 自己的数据目录；一次最多看 2 万个目录。结果存在 `<data>/repo-index.json`，超过 10 分钟再被问到时在后台重扫，先答存着的；第一次没有就等第一遍扫完。

排序：对话用过的在前（多的在前），其余按最近改动（`.git/index` 的修改时间）。再加上别的预设用到的目录。全程异步读，不卡主线程。

## agent 拿到什么

- 预设的开场说明（`presetInstructions`）接在 station 自己的说明后面：预设名、各目录（是克隆的说明在自己的 worktree 里改）、先读各目录的 AGENTS.md、CLAUDE.md 和 `.claude/skills`、`.agents/skills`，人写的要求放在 `<preset-instructions>` 里（人的，不是 agent 改的）。
- Claude 另外用 `--add-dir` 加上这些目录（`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`：目录里的 CLAUDE.md 也读）；工作目录仍是会话工作区。
- 从终端接过来的会话（`cwd`）不用预设。

## 客户端

- core：station topic `presets`（页面显示时读一次，建、改、删后再读：`preset.add`、`preset.put`、`preset.delete`）；`newChat` 视图的 `preset`、`presetName`（新对话页自己不订 `presets`，名字由 core 跟着新对话的数据一起给，选预设的面板打开时才订）是这台设备上这个 workspace 在这台 station 新开对话用的预设（`newChat.pick {preset}`，`""` 不用），`newChat.create` 把它带进 `POST /sessions`。station 已经没有的预设不再算选中。
- App 新对话页：station、模型旁边一个「预设」胶囊，点开是这台 station 的预设（不用预设、各预设和它的目录、编辑），最后是「新预设…」。新建/编辑的对话框以目录为主：上面是选中的目录（点 × 去掉），一行搜索（也能直接粘贴路径），下面是这台 station 上的仓库，按对话用过多少排，点一下加上；名字默认取第一个目录的名字；指令可选。建好就选中它。

## 还没做

- 对话里显示用的是哪个预设、「用另一个预设开新对话」。
- 飞书群、Slack 频道的默认预设。
- 把预设和项目记忆 skill 连上（选了仓库自动带上它的记忆）。
- 预设在 workspace 的各台 station 之间同步（现在每台 station 自己的）。
- 索引还不看 `Documents` 这些受保护的目录（要经 still.fail Helper 读，不弹框）。
