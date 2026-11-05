> **真实调用状态：尚无真实数据。** 下文为历史源码审计和推算，不是 API 实测或账单。可交接的真实调用脚本及运行说明见 [API-RUN.md](API-RUN.md)；本轮仅离线验证脚本，未发起 API 调用。

# still.fail 多人共享 coding agent：源码与成本基准

**结论：still.fail 在原理上能省去重复的仓库准备、上下文建立和冷缓存写入，但“多人共用 agent”本身没有推理折扣；当前源码也没有实现跨会话共享代码向量索引或自行共享模型 KV，收益取决于同一会话的连续使用、真正相同的前缀和服务商缓存域。**

审计仅涉及 `AFK-surf/still.fail`，固定提交 `c789e5c30f48998eac66b7c9654aff0e068178b1`，2026-11-05。没有采用 Cue 的源码、结论或数据。下文“事实”来自该提交；“推算”是条件成立时的数学结果。

## 1. 源码事实与可核查证据

下面路径均相对仓库根目录，行号对应固定提交。可用 `git show c789e5c:path` 或 `https://github.com/AFK-surf/still.fail/blob/c789e5c30f48998eac66b7c9654aff0e068178b1/<path>#L<line>` 核查。

|问题|源码证据与结论|
|---|---|
|仓库如何进入上下文|`station/src/agents/claude.ts:297–336` 启动真正的 `claude -p --input-format stream-json --output-format stream-json`，追加系统指令、配置 MCP；`:467–469` 把用户文字写进 Claude Code。仓库不是被 still.fail 整仓自动塞进请求。一般源码读取/grep/Bash 由外部 coding runtime 的工具完成，结果成为它的工具历史；其实现不在本仓，不能声称已审计 Claude Code 内部检索算法。`station/src/agents/live.ts:63–83,111–119` 处理工具调用和结果；`station/src/sessions/chat.ts:183` 将 read/grep/glob/search_files 等运行时工具归为读文件状态。|
|自动加载的项目材料|`station/src/sessions/presets.ts:239–266` 读取预设目录中的 `AGENTS.md`、`CLAUDE.md`、`.claude/CLAUDE.md`，每文件最多 16 KiB，长文件提示继续读；链接项目 skills。`:315–343` 将路径、预设、指南文字拼到 instructions。不是全仓内容索引。`station/src/agents/instructions.ts:10–23` 读取并追加 workspace 的 MEMORY.md。|
|向量/语义代码索引|**本仓自实现的 embedding 生成、向量数据库和代码内容/符号检索索引不存在**：下方给出搜索范围与计数。此结论仅覆盖本仓实现，不涵盖外部运行时或操作系统内部。|
|其他 index 确实存在|不能写“任何形式 index 均不存在”。`station/src/sessions/presets.ts:446–462,517–540` 的 `RepoIndex` 遍历 `.git`，保存仓库路径、origin、mtime、图标至 `repo-index.json`，10 分钟刷新，供预设选择；不是代码内容索引。`station/src/search/files.ts:1–5,76–82` 在 macOS 利用 Spotlight 的文件名/内容索引，其他平台实时遍历；`:173` 读取内容匹配。`station/src/search/search.ts:1–3,33–35` 明说 station 搜索不建索引并删除旧 search.db；`station/src/search/tool.ts:84` 描述按词检索。数据库会话索引、Git index 与这些用途也不能算语义代码索引。|
|提示词是否稳定|固定模板可复用，但 `station/src/agents/instructions.ts:10–25,81–89` 含 session workspace 路径、可选原项目 cwd、repos 路径、memory 路径及启动时 memory 内容；`station/src/sessions/actor.ts:1733–1763` 再追加 preset，传入 model/effort/context/fast、MCP token/URL、route。这些不全是模型可见文字（token 不能直接当上下文）；实际 API 字节排序由运行时决定。`instructions.ts:215–244` 的消息包装含 connect、you、thread、from、client、ts、before、卡片状态及正文。不同会话不能默认共享完整前缀。|
|同会话与不同会话|`station/src/sessions/hub.ts:1088–1124` 按 connect/scope 建会话及自己的 workspace；`:1129–1134` 每 session key 一个 actor。`instructions.ts:30` 允许同一会话听多个线程；多人若路由到同一个 session，可以接续同一历史，但 workspace 成员并非天然共用一条历史。|
|Claude 进程|`station/src/agents/claude.ts:1–2,303–314`：**每会话一个 Claude Code 进程**；新会话 UUID，已有会话 `--resume`。`own-process.ts:1–7` 也明确这个边界。因此产品上的“同一个 agent”不等于所有人一个 Claude 进程或一个上下文。|
|Codex 进程|`station/src/agents/codex.ts:1–7`：非沙箱模式按 profile 共用 app-server，每 session 独立 thread；`:549–553` 的 hostKey 在启用沙箱时改为 session；`:935–948` 各自 thread/start 或 thread/resume。共享 app-server 主要减少本机进程开销，不代表共享远端 KV。|
|沙箱与文件共享|`station/src/agents/sandbox.ts:1–8,31–38`：启用后每 session 自己的远端沙箱，不与 station 共享文件系统，通过同步获取指定材料；persist 可选。`hub.ts:749–758` 空闲时结束进程和沙箱。非沙箱模式可共用机器/磁盘；`instructions.ts:81–82` 要求共享 canonical repo cache、各 session 用 worktree。共享 clone 是 I/O/存储复用，不是模型免读。|
|模型调用及缓存标记|Claude 使用 CLI，Codex 使用 app-server 协议，非 still.fail 自己构造 Anthropic Messages 请求。全仓指定源码搜索 `cache_control`、`prompt_cache_key` **各 0 行**：**本仓不存在自行设置这些标记的实现，也不存在自建的 prompt/KV cache key 算法**。外部 CLI 仍可自行设置缓存，不能由零命中推出“Claude Code 没缓存”。|
|TTL 与账号切换|`station/src/read/usage.ts:141–166` 根据最近写入 usage 推断 5 分钟/1 小时 TTL，这是本地估算展示，不是控制服务商 TTL。`station/src/sessions/afresh.ts:1–5,20–27,38–46` 在换 profile/冷缓存时考虑开新 runtime session，让 agent 按需读回。这里“缓存属账号”是代码采用的保守策略，不可替代官方缓存域规则。|
|用量计量|**存在。** `station/src/usage/counter.ts:136–168` 从 Claude transcript 读 input、cache read、5m/1h write、output，按 response id 去重；`:169–185` 从 Codex token_count 读取 cached input。`station/src/read/usage.ts:80–115` 按模型价表估算美元；`:96` 公式包括读写缓存，fast 额外倍率。此数字是“API 标价等价成本”，不是订阅账号实际账单。|
|额外省费机制|`station/src/sessions/pool.ts:1–12,130–155` 优先消费已有订阅，再用按量账号，按剩余额度分配；换账号可能冷启动。`claude.ts:167–184` 减少无用内置 skills/connectors 上下文（注释中的旧版本 token 数不是本次实测，不当基准）。这些与“共享 KV”是不同机制。|

### 搜索范围、词与命中数（实测）

脚本通过 `git ls-tree` 固定提交枚举已跟踪 `.ts/.tsx/.js/.mjs/.rs/.py/.swift/.kt/.c/.h`，逐文件大小写不敏感 regex 搜索；计**匹配行数**，含测试/注释，不含文档、锁文件、依赖包。全仓 2,438 文件；其中 station/src 467 文件。完整命中材料在 results/search-*.txt。

|regex|全仓源码匹配行|station/src 匹配行|
|---|---:|---:|
|`embedding`|10|1|
|`vector`|78|1|
|`\bindex\b`|1432|488|
|`cache`|1423|319|
|`cache_control`|0|0|
|`prompt_cache_key`|0|0|
|`code[_ -]?index\|codeIndex`（两个分支的 regex）|0|0|
|`RepoIndex`|13|7|
|`\bFAISS\b\|\bHNSW\b\|\bLanceDB\b\|\bChromaDB\b\|\bPinecone\b`|0|0|

station/src 唯一 embedding 命中是 `browser/chrome.ts:12` 的“embedding Chromium”；唯一 vector 命中是 `vault/crypto.ts:4` 的加密 test vectors。全仓 embedding 其余为宿主嵌入 app、EPUB DRM 等文字，vector 多为图形/测试。零命中与调用链一起支撑“不存在本仓语义代码索引”，不是把单次关键词搜索当绝对证明。

## 2. 两笔钱分别算（原理及估算）

### (a) 仓库准备 / 建索引 / 建上下文

设一次可重复使用的准备成本为 S。N 人分别做是 N×S，共做一次是 S，理论最多省 `(N−1)S`，比例 `1−1/N`：N=1/5/20 时为 0%/80%/95%。这是**完全重复、产物完全适用**的上界；如果每人本来用各自已有 clone、或所需文件不同，收益更小。

但当前 still.fail 没有代码向量索引，因此“少建 N−1 份向量索引”这项在当前实现中没有可验证金额，不能虚构成产品节约。可省的是 clone/安装/磁盘、共享指南/经验，以及同一会话中已经做过的搜索、理解与总结。磁盘文件共享并不免除模型输入费用：文件内容每次进入独立请求仍需付费或命中 provider cache。S 若包含推理准备，应与下节的 prefix prefill 选择一种口径，不能重复记省钱。

### (b) 推理与 prefix/KV cache

必须同时满足：同模型、同服务商缓存域、直到断点的 tools/system/messages 内容完全相同、超过最小长度、TTL 内已有可用写入、运行时的缓存断点可匹配。仅“代码文件相同”不够：它之前若出现不同 cwd/系统指令/技能清单/用户消息，后面的相同源码也不能复用那一整段前缀。独立 CLI 若满足同样条件也有同样折扣；共享进程既非必要也非充分条件。

官方 Claude API 文档（核查日 2026-11-05）当前明确按**provider workspace** 隔离缓存（Google managed/Bedrock 为 organization 级）；provider workspace 与 still.fail workspace 是两种概念。不同组织不共享。缓存 key 是截至 cache breakpoint 的前缀加密哈希，任意前置变化会改变哈希；本仓没有实现/掌控此哈希。5m 默认，另有付费 1h，每次命中刷新；首个响应开始后并发请求才可命中。Sonnet 4.5 最小 1,024 token。Claude Code 订阅缓存域和 CLI 精确分块本次未实测，不能假定等同 API workspace。

设公共前缀 P、任务新增输入 U、输出 O；每 token 普通输入价 b、写入价 w、读取价 r、输出价 q（下列式子按单 token 单位）：

- N 个独立冷缓存域：`C_ind = N(wP+bU+qO)`。
- 理想共享缓存，先预热一次再做余下任务：`C_share = [w+(N−1)r]P + N(bU+qO)`。
- 因此节省 `Δ=(N−1)(w−r)P`，只省公共前缀；输出完全不打折。
- 独立 CLI 已在同缓存域且具有相同前缀：`C_ind=C_share`，产品带来的额外缓存节约是 **0**。
- 各自已有热缓存：两边均付 `N(rP+bU+qO)`；不能把独立客户端强行当成每次全价冷读。

Sonnet 4.5 的 5m 写价 1.25b、读价 0.1b：仅公共前缀相对 N 次冷写最多省 `0.92(1−1/N)`，N=5/20 为 73.6%/87.4%，N→∞ 为 92%；相对 N 次无缓存普通输入则为 `1−[1.25+0.1(N−1)]/N`，N=1 为 **−25%**、5 为 67%、20 为 84.25%，极限 90%。这些都不是整单节省率。含输出和工具回合后，整单更低。1h 写价 2b、读价 0.1b，相对独立 1h 冷写的前缀极限为 95%，相对不缓存仍为 90%；其他模型需用各自 w/r。

对话分叉后，设最早分叉前还可命中的前缀为 K≤P。只对 K 使用上述公式，分叉后的历史各自付费；不能跳过分叉点去匹配后面相同的代码。若分叉早于源码且没有更早可用断点，仓库材料的共享缓存收益可能降为 0。相同会话连续使用能复用更多既有历史，但每次仍需支付读缓存价，后续各人的输出、工具结果也会累积。

### 共享反而更贵的情形

1. 把无关任务全塞进一条长历史。每个后续任务多带 H 个无关 token，即使热缓存也多付约 rH，冷缓存更贵；另有摘要/压缩、上下文污染、重试成本。
2. 为共享而整仓预载，本来各人只需要少量相关文件。共同大前缀和缓存写入溢价可超过省下的重复读取。
3. 首轮并发尚未预热、间隔超过 TTL、切账号/模型/路由/预设、技能和系统提示变化，导致不断重写缓存。
4. N=1 或只有一次读取：5m 写入比无缓存贵 25%，1h 贵 100%；没有后续复用无法回本。
5. 共享会话串行排队、文件冲突、返工、持续运行的主机和沙箱费，可能超过 token 节约。
6. “每人自己装 Claude Code”若付固定订阅且在额度内，多用一点 token 未必增加当月账单；共享只能在合法账号/席位/许可与额度约束下比较实际购买成本。本仓的订阅池不能据此证明少买 N−1 个席位或共享账号被服务条款许可。

## 3. 可重跑基准

### 测量设计与前提

**实测**：从固定提交取四个真实完整源码文件，按稳定 path 顺序和 `<source>` 包装组成公共前缀：instructions.ts、claude.ts、presets.ts、counter.ts。共 **134,652 UTF-8 bytes、34,040 proxy tokens**。任务问题 27 proxy tokens。文件清单/逐文件 SHA-256 与前缀 SHA-256 在 measurement.json，prefix.txt 直接附上。

使用 `tiktoken==0.12.0 / cl100k_base` 真 tokenizer，**这是 Claude token 数的代理，不是 Claude 官方 tokenizer**；没有校准误差界。字节及此 encoding 的 token 数为实测；以它代替 Claude 计费 token 后的美元数全部是推算。这个源码材料包是人为构造的缓存上界测试，不是对线上 still.fail 自动预载行为的描述，也不是抓取到的完整 CLI 请求。

按官方 Sonnet 4.5（`claude-sonnet-4-5-20250929`）标准 API 价：输入 $3/M、5m 写 $3.75/M、1h 写 $6/M、读 $0.30/M、输出 $15/M。固定这个仍可用但已 deprecated 的型号用于稳定比较，并非推荐生产选型；官方说明计划 2026-11-30 退役。每任务**假设输出 1,000 token**，不是生成实测。N 是一批 N 个任务/请求，每人一次；“单任务”金额是批次总成本除 N，包含首个预热任务。可用 `--output-tokens 0` 看纯输入场景。

**未做 API 调用，api_calls=0**。本任务环境没有 ANTHROPIC_API_KEY / ANTHROPIC_AUTH_TOKEN，未取得可用于本基准的 Claude API 凭证；没有用订阅代替付费 API 测试。未测真实缓存命中率、模型输出质量、延迟、吞吐、工具轮数和真实账单。忽略 CLI system/tools 的额外 token、消息 framing、其他推理输出、主机/订阅费；两边给予相同的额外开销假设，不把它包装成完整 coding task 的花费。

### 基准表（tokenizer 实测，费用全为推算；USD/任务）

|N|独立，各自冷 5m 域|共享，理想 5m|对独立冷写节省|独立 CLI，同域相同前缀|两边各自已热|独立，不缓存|
|---:|---:|---:|---:|---:|---:|---:|
|1|0.142731|0.142731|0%|0.142731|0.025293|0.117201|
|5|0.142731|0.048781|65.82%|0.048781|0.025293|0.117201|
|20|0.142731|0.031165|78.17%|0.031165|0.025293|0.117201|

5m 的每批总成本（独立冷域 → 理想共享）分别为 $0.142731→$0.142731、$0.713655→$0.243903、$2.854620→$0.623298。相对无缓存独立，理想共享的整单节省为 N=1 **−21.78%**、5 **58.38%**、20 **73.41%**。不能把基准的 78.17% 宣称为 still.fail 线上已经实现的节省。

|N|独立各自冷 1h（$/任务）|共享理想 1h（$/任务）|
|---:|---:|---:|
|1|0.219321|0.219321|
|5|0.219321|0.064099|
|20|0.219321|0.034994|

完整 21 行场景在 costs.csv（同时有批次 input-only、批次总费用、摊销单任务费用）。同域独立 CLI 对照行与理想共享行完全相同，是此比较最重要的控制组。

### 一键重跑

在包含固定提交对象的 still.fail checkout 内：

```bash
python3 reports/stillfail-shared-agent-cost/benchmark.py --repo . --out /tmp/stillfail-cost-results
```

或把附件脚本放在任意位置，指定 `--repo /path/to/still.fail`。首次运行自动在临时目录建立 venv 并安装固定版本 tiktoken，需要 Python3 venv、pip、网络与 git；不需要 API key。默认读取固定提交，不受当前工作区修改影响；`--rev` 可选其他提交，但结果应重新标注。输出 prefix、measurement.json、costs.csv、search-counts.csv 和逐项搜索命中材料。

## 4. 官方依据与决策含义

- 定价：https://platform.claude.com/docs/en/about-claude/pricing
- 缓存及缓存域：https://platform.claude.com/docs/en/build-with-claude/prompt-caching （原始 Markdown 可取同 URL 加 `.md`；关键节 How prompt caching works / Cache limitations / Cache storage and sharing / Frequently asked questions）
- 固定型号与退役说明：https://platform.claude.com/docs/en/models/sonnet-4-5/overview

对 owner 的判断：可以把“共享工作成果、减少重复启动、优先利用已有额度、可观测 token 成本”作为已有机制；不能把“自动共建代码向量索引”“所有人的模型 KV 合并”“多人天然获得更低推理单价”作为源码支持的事实。若要形成实际节省承诺，应在相同任务/模型/账号计费方式下，以本仓已有 usage 数据记录冷写、热读、输出、工具调用和压缩成本，并与同域独立 Claude Code 控制组比较。本次已经交付可复跑的 token 与价格基准，实际命中率仍需有凭证的 API/CLI 实验才能回答。
