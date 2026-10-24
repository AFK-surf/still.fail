# mbui iOS App Intents 机会评估

## 现有集成清单

本次源码检查发现 **0 个已声明的 App Intents 动作**；未发现面向 Shortcuts、App Shortcuts、Spotlight、Siri 的相关声明，也未发现 Apple Intelligence schema 声明。这是限定范围的源码清单，不是构建产物或系统运行验证。

| 业务动作 | Intent / Provider / Entity / Query | 当前接入 | 证据边界 |
| --- | --- | --- | --- |
| 无 | 在 `apps/mbui/src`、`apps/mbui/mbui/src` 搜索 `AppIntent`、`AppShortcut`、`AppShortcutsProvider`、`AppEntity`、`EntityQuery`、`@AssistantIntent`、`@AssistantEntity`，均无匹配 | 0 个 | 已另读主应用与 Share plist；Share extension 不等于 App Intents 集成。未检查所有其他产品目录、生成产物或运行时注册结果 |

## 项目与范围

- 分析日期：2026-10-24；导入项目 still.fail / mbui。当前源码 HEAD 为 `3220240b531d4cf4079a9560138c834699d91285`；`4f5a87096` 合并 upstream `b88dcde6f` 到本地审核/安全修改之上，合并相对第一父提交涉及 647 个路径。新增独立 CI 本身没有应用功能，但上游整合改变了 memory/skill 业务数据契约及桌面页面，必须重新评估，不能仅复用旧结论。原审核页无障碍、安全存储等背景保留；本次报告分析不改变权限、服务或部署目标。
- 目的：在上游业务整合与独立 GitHub 云 CI 工作之后重跑评估（具体差异见末节）。保留上一版 A1/A2 动作身份及首批零项结论；审核密码与原生输入接入不产生新的系统业务动作。原生 Apple 登录第二阶段未实现，不计入现有能力。
- 已读 find-intent 技能及报告模板、普通 App Intents 参考；参考中的 starter 配置和示例不作为本项目或具体 Apple API 可用性证据。
- 范围：mbui UI、C bridge 声明、Hermes 架构说明、构建入口及 plist，定向追踪“打开已有对话”“新建对话并发送首条消息”至 `client/core-ts`。未全量扫描大型仓库。

| Target / 配置 | 相关来源 | 最低系统 | 工具链证据与未知 |
| --- | --- | --- | --- |
| 主应用 `fail.still.mbui`（默认源码调试 ID 为 `fail.still.mbui.debug`） | `.airbuild/build-ios.sh`；`apps/mbui/scripts/ios.sh`；`apps/mbui/mbui/scripts/ios.sh`；`apps/mbui/ios/Info.plist` | plist 为 17.0；底层脚本分别使用 simulator/device 的 17.0 编译标志 | 自定义 MoonBit→C、ObjC/ObjC++ host、Hermes；脚本以 `xcrun` 选择 SDK。已独立读取 Xcode 27.1（27A9275）和 iphoneos SDK 27.1；它们是构建环境，不代表当前预览运行时。具体 App Intents SDK 符号仍未读取，不推导 API 可用性 |
| Share extension `fail.still.mbui.share` | `.airbuild/airbuild.yaml`；`apps/mbui/ios/Share-Info.plist`；底层 `ios.sh` 的 Share.appex 打包配置 | plist 为 17.0 | `MBShareController`，声明 `com.apple.share-services`，接收文字、URL、图片、视频、文件；与主应用通过 app group 交接。未验证签名、实际 extension 运行或生成工程源成员 |

`.airbuild/build-ios.sh` 先构建自定义应用，再生成包装 Xcode 工程并归档；不能把包装工程视为已具备 Swift App Intents 编译、链接和元数据提取链路。

## 决策摘要

**可直接进入实施的首批：0 项。** 保留 A1/A2，并新增一个有业务价值的记忆阅读待验证机会 A3；共三个待验证机会，优先验证“打开指定已有对话”，其次“打开指定站点的记忆 / 项目 skill 文档”，最后评估“新建并发送首条消息”。三者均为 **需验证**，不是已推荐可交付路径。

共同阻塞：现有登录和业务 Store 位于 JS/Hermes core，原生仅有低层 JSON bridge；尚无原生 App Intents 服务层、实体查询、冷启动账户恢复、调用取消/结果关联及前台导航接入证据。具体 Apple API 与系统入口的声明/可用性也未核实。优先解决桥接与权限边界，不扩散研究 schema 或改变部署目标。

## 已评估动作

### A1 打开指定已有对话

- **业务状态：已实现（应用内导航及阅读状态链路）。** `apps/mbui/src/sfapp/home.mbt:707–708` 的列表点击分支，根据消息定位进入 `open_chat_at` 或 `app.nav.push(Chat(r))`；`sfapp/chat.mbt::open_chat_at`（当前约 406 行） 的 `open_chat_at` 调用 `go_to` 后 push 对话。搜索入口 `sfapp/search.mbt:618` 调用已迁至 `apps/mbui/src/sfbase/jump.mbt::open_chat_found`。
- **业务与数据链：** `apps/mbui/src/sfbase/chat_list.mbt::tell_focus` / `focus_chat`（当前约 955 行） 以 `station`、`session` 和可选 thread/seen 调用 `client.focus`；`client/core-ts/src/attend-parse.ts` 解析该请求；`src/attention.ts:113–119` 的 focus handler 调用 `prefs.chatOpened`，更新关注与订阅；`src/prefs.ts:184–191` 将最后打开对话按 workspace 写回 `data.set(PREFS, prefs)`。因此“打开”可能同时影响已读状态，不能描述为绝对无副作用查询。
- **方向（提案）：** 前台打开已有对话，不创建、不发送。必需参数为选定对话；拟议实体键应包含账户范围、workspace/station、session，不能用标题作唯一 ID。按标题搜索仅展示当前账户可访问候选，同名必须让用户选择；过期、删除或权限撤销后明确失败，不回退到其他同名对话。已有 session 标识与 prefs 持久化提供线索，但跨重启稳定性、跨账户冲突与实体查询仍待验证。
- **重复执行：** 不应创建内容；现有导航直接 push，不能认定已具备防重复页面逻辑。若要求重复调用复用当前页，需新增导航 guard（提案）。
- **访问与安全：** `tell_focus` 已检查 `Source.read_only`，但它不是账户授权证明。尚未追完整账号→workspace→会话 ACL 链路；新实体查询和执行必须同时检查当前账户及访问权。设备解锁不等于应用登录，也不等于数据授权。避免把对话标题、消息、站点信息默认暴露到锁屏、语音回复或全局搜索；不主动朗读正文。
- **普通路径 / schema：** 普通前台 App Intent 仅为设计方向，相关 Apple 符号、最低版本、所选 SDK 声明均未验证（E1）；schema 精确领域/member 未确定，不主张任何增强能力。
- **系统入口：** Shortcuts 动作及 App Shortcuts provider/短语待设计与核验；Spotlight 未见索引/实体接入证据；Siri 短语、账户选择和前台跳转未验证；Apple Intelligence 未验证，不能由普通 Intent 推导支持。
- **结论与优先级：需验证，P1，M–L。** 价值在于直接回到特定任务上下文，风险低于自动发送；成本主要是原生桥接、身份解析、权限过滤和冷启动导航，而非 Intent 声明本身。无使用统计，排序为定性判断。
- **下一步：** 先验证从原生冷启动恢复既有账户、按稳定 ID 查询授权会话并送达导航；测试注销、切换账户、离线、撤权、重复打开及已读副作用。未编译、未验证入口可见性、未跑模拟器/真机。

### A2 新建对话并发送首条消息

- **业务状态：已实现（应用内）。** `apps/mbui/src/sfapp/newchat.mbt` 的 `new_chat` / `new_chat_page` 为入口；`send_first`（当前约 504 行） 检查 `src.read_only`、`fresh.starting`，保存/清空草稿并处理失败恢复；已有待建 key 时复用，否则在当前约 599 行调用 `newChat.create`，再以该 key 调用 `chat.send`（当前约 576 行）。它不是单纯“打开新建页”。
- **core 链：** `client/core-ts/src/choose-calls.ts:48–54` 的 `newChat.create` → `Choose.create`（`src/choose.ts:349`，检查 runtime/model 可用）→ `handlers.chatCreate`（`src/views/calls.ts:250–259`）→ `local.pendingNew` 与 `makeChat`。`src/views/local.ts:142` 生成新的 pending key；`#savePending` 写入 `data.putLocal`。`chatSendTo` 根据 pending/bound session 排队或发送；`ViewCalls.resume` 可恢复未完成队列。**返回 pending key / 排队成功不等于远端已建好并发送完成。**
- **方向（提案）：** 若产品选择自动化，明确命名“新建对话并发送首条消息”；输入账户范围内的 workspace/station 与消息，runtime/model/profile 可选择或使用已明确展示的配置；不默默切换账号、站点或模型。同名站点先消歧；失效参数失败，不任意选择替代项。输出应区分已排队、已创建、已发送、失败。
- **重复执行：** `outgoing`（`src/views/calls.ts:43`）为每次新消息生成随机 idem key；持久队列恢复可沿用原操作，但不能据此认定两次独立系统调用会自动去重。`fresh.starting` 是当前 UI 内存态，不是系统动作幂等方案；跨调用幂等与部分完成恢复需要新设计。
- **访问与安全：** 既有 `read_only` 与模型检查有证据；`views/calls.ts` 的 `parse(station)` 只是 `StationAddr.parse`，不能当作 ACL。完整账户登录恢复、站点/会话授权与服务端拒绝路径未追完，需补验。消息可能触发远端代理、消耗额度或处理共享工作区数据；建议首期前台展示账户、站点、模型及消息并确认，不默认后台发送。生物认证、应用登录、数据权限、发送确认应独立处理。
- **普通路径 / schema / 系统入口：** 普通 Intent 方向需验证（E1）；不提出未经核实的 schema 名称。Shortcuts / Siri 若引入发送能力须明确确认与失败恢复；Spotlight 暂不索引消息正文；Apple Intelligence 未确定语义、依赖实体和可用条件。后台能力不能从 Hermes 线程或队列持久化推导。
- **结论与优先级：需验证，P2，L。** 有跨应用输入价值，但写操作、远端执行、去重和部分完成风险显著高于 A1。若产品只要打开新建页，应缩小为另一种明确的导航语义，不能混称“已开始对话”。
- **下一步：** 验证登录/ACL、远端建会话和发送完成事件、账户切换、离线后恢复、重复调用及取消；在产品批准确认策略前不进入首批。未进行任何发送或创建操作。

## 共享原生桥接与授权证据

`apps/mbui/src/host/core_api.h` 实际声明仅有 `mb_core_start` / `mb_core_send` / `mb_core_stop`：一个 core、一个 UI client；异步消息回调在 core 线程，宿主自行复制并切 UI 线程。`mb_core_start` 的 data_dir 保存账户、登录与数据库，返回时脚本仍可能加载，致命启动错误异步返回。已有低层通信基础不等于原生 Intent 可直接可靠调用。

`apps/mbui/core/README.md` 说明 `apple_core.mm` 承载 Hermes、Keychain secure 操作和 shell；该说明是架构证据，不是本次实际运行证明。`client/core-ts/src/core/execute.ts:45–54` 显示 `authBegin`、`authPassword`、`authComplete` 委托 `inner.accounts`。本次已追 Accounts.load 的错误传播、password prepare/accept/cancel 及持久化互斥；当前 iOS 主应用 accounts 操作经 apple_core.mm 路由至 mbui_ios_sessions.h/_apple.h 的系统 Keychain，稳定安装 UUID 区分重装/包身份。隔离状态机测试与设备/模拟器桥接编译通过；另已在独立 iOS 17 测试程序中使用生产适配器执行真实安全存储创建、读取、更新、删除及实际进程结束后重启恢复，数据限于独立合成测试条目。该证据不等于完整应用的真实账号迁移、卸载重装或权限验收。最终保存的不可取消边界已获产品确认；进度事件、核心和 UI 各自 15 秒预算、同一尝试重新核对与失败终态保留已实现并通过隔离回归，但仍未完成真实账号与原生安全存储的联动验收，不是可供原生系统动作直接复用的完成态服务。账户登录成功本身也不能证明工作区/站点/会话 ACL；完整数据所有权和站点 RPC 授权链仍待验证。

## API 与可用性证据

| ID | 精确符号 / 范围 | 最低 OS / SDK | 已读来源及日期 | 缺口与下一步 |
| --- | --- | --- | --- | --- |
| E1 | 拟依赖 `AppIntent`、参数/结果、`AppEntity` / `EntityQuery`；若暴露快捷方式还需 provider、shortcut 和短语相关符号 | **均未核实，不填写推测版本** | 2026-10-24 已读技能及普通参考，未读 Apple 官方符号文档或本机 SDK 对应声明 | 后续按选定最小路径逐一读取自身声明与 availability，并核对当前 SDK、iOS 17 覆盖及元数据提取链路；参考示例不是 symbol 验证 |
| E2 | 可选 Apple Intelligence schema 的精确 domain.member 与实体依赖 | 未确定 | 未开展 schema 专项核验 | 普通路径与桥接可行后再核对语义、依赖动作/实体、SDK 与实际 runtime；不承诺 Siri/Apple Intelligence 支持 |

以上没有“已验证 Apple API”项。并非断言网络或 SDK 不可用，而是本次受限只读评估未读取其声明；不得把缺口降格为实施后的附加测试。

## 延后与排除

| 功能 | 业务证据 | 处理 |
| --- | --- | --- |
| Share 接收内容 | `Share-Info.plist` 声明系统分享接收，提示打开 app 后选择对话；底层打包脚本描述 app group 交接 | 现有 Share 集成，不计作现有 Intent；未追完整发送链，不另列即用候选 |
| 单纯打开新建页 / 装饰性切换 | `newchat.mbt::new_chat` 是 UI 路由，真正建会话及发送另有函数 | 不包装为已创建/已发送；除非有明确任务场景，不为凑数量纳入首批 |
| 删除、管理、密钥库等高风险操作 | 超出本次两条链路，无完整实现/授权评估 | 不推荐本轮纳入；并非断言未实现 |
| 审核登录、密码/恢复凭据与保存状态 | `sfapp/reviewer.mbt`、`accounts.ts` 的 prepare/accept/cancel、iOS accounts Keychain 路由；提交/取消 UI 契约已实现并通过隔离回归，真实账号和原生安全存储验收待完成 | 不将输入凭据或身份管理暴露为 Shortcut/Siri 动作；不通过系统入口绕开登录确认、安全存储可用性或数据 ACL |
| schema 增强 | 无已读具体声明及语义映射 | 待验证，不进入 ready batch |

## 产品交接

**首批 0 项；待验证优先级 A1 → A3 → A2。** 先决定是否仅做对话/记忆的前台导航，以及是否接受任何自动发送。关键依赖：原生 Intent 构建/元数据链路、Hermes 服务桥接与冷启动、账户隔离和 ACL、稳定实体 ID、写操作确认及幂等/恢复、精确 Apple API 声明证据。随后分别验证编译、入口可见、执行结果、签名模拟器/真机及 Siri；这些证据不能互相替代。

本报告完成于仓库根目录 `intent-opportunities.md`；本次仅更新报告和读取源码/版本，没有新增 App Intents、启动业务操作或改变系统权限。整体开发任务另外执行了文中明确标注的隔离测试及桥接编译；它们不等于 App Intents 编译、运行、入口可见性或真实账号访问验证。

## 2026-10-24 上游整合后的精确重评差异

### 当前快照与复核边界

- 旧报告基线 `b7f495c45` → 当前 HEAD `3220240b5` 的只读 `git diff --name-only` 共 660 路径；其中合并提交 `4f5a87096` 相对第一父提交为 647 路径。前者是报告跨度，后者是上游整合范围，不混称本次修改。
- 本次读取时已存在未提交修改：`apps/mbui/src/sfapp/app.mbt`、`home_wbtest.mbt`、`style_ref_wbtest.mbt`、`apps/mbui/scripts/ios-testflight.rb`、`ios-testflight-test.rb`；另有未跟踪 `apps/mbui/src/sf/math_fixture_wbtest.mbt`、`math_text_wbtest.mbt` 及 `client/core-ts/node_modules`。不触碰这些文件。已读 app diff：窄桌面不再触发手机审核登录，改以 `touch_system()` 分流；已读 CI helper diff：完整零 job 响应可证明排队阶段取消、未执行，不等于上传成功。测试文件只记录快照，不以其名称或存在声称测试通过。
- 重新搜索主应用/Share 相关源码 `apps/mbui/src`（包括 `sfbase`、`sfdesk`）、`apps/mbui/mbui/src`、`apps/mbui/ios`、`apps/mbui/core`：`AppIntent`、`AppShortcut`、`AppShortcutsProvider`、`AppEntity`、`EntityQuery`、`@AssistantIntent`、`@AssistantEntity` 均无匹配。仍为 **0 个声明**；生成包装工程/元数据未检查，不推断系统注册。阅读了两层 mbui `AGENTS.md`；本任务不进入其代码/PR实施流程。
- 重新读取 `Info.plist` / `Share-Info.plist`：两者最低系统仍 17.0，Share 仍为 `com.apple.share-services`；应用 `ios.sh` 明确设置 `IPHONEOS_DEPLOYMENT_TARGET=17.0`，构建包装脚本主 ID 仍 `fail.still.mbui`，Share 身份保留 `fail.still.mbui.share`。未变更 target、权限、服务、签名或 Apple 登录范围。
- 只读工具查询实得 Xcode **27.1 / 27A9275**，`xcrun --sdk iphoneos --show-sdk-path` 实得 `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.1.sdk`。这是实际安装/选择的设备 SDK，不是已运行 iOS 27.1 的证明。已完整重读 find-intent 技能、模板及 iOS 技能，并读普通 App Intents 参考。旧 E1 没有任何精确 SDK symbol 证据可沿用；本次未宣称任何普通 API 已验证，E1/E2 保持待验证，不编造最低版本，不把参考中的 iOS 26 starter 路线套到本项目。

### A1/A2 当前函数复核

- A1 的 UI → core 链仍成立，但共享业务函数迁入 `sfbase`，上文已修正实际路径。已读 `open_chat_at`、`open_chat_found`、`tell_focus` / `focus_chat` 函数体以及 `attention.ts` focus handler、`prefs.ts::chatOpened`：前台 push、消息定位、已读/关注及 workspace 最近对话持久化语义仍成立；没有新增实体授权查询或防重复导航证据。
- A2 已重新读 `newchat.mbt::send_first`、`choose-calls.ts` 的 `newChat.create`、`Choose.create`、`views/calls.ts` 的 create/send handler 与 `outgoing`、`views/local.ts::pendingNew` / `#savePending`。read-only/start guard、草稿恢复、pending key 复用、排队与远端完成分离仍成立；当前 `pendingNew` 使用 `localId("chat")`，不是时钟生成的远端 session ID；每个独立 outgoing 仍取随机 idem bytes。不能以“可重放的本地 ID”推断系统重复调用已幂等。A1/A2 均维持 **需验证 / ready 0**。
- 重新读取 `apps/mbui/src/host/core_api.h`：仍是单 core / 单 UI client 的 start/send/stop JSON 回调，启动返回不保证脚本已加载。新增上游业务并没有自动补齐原生 headless 服务、冷启动恢复、实体查询或调用取消桥接。

### A3 打开指定站点的记忆 / 项目 skill 文档 — 新增待验证候选

- **业务状态：已实现（应用内阅读）。** 实读 `apps/mbui/src/sfapp/settings/memory.mbt` 全部函数体：`memories_page` 只让在线站点进入 `Memory(address)`；`memory_page` 按全局 sections、project skills、其他/内置 skills 展示，选择后进入 `MemoryDoc(address, name, at)`；`memory_doc_page` 渲染全局分节或 skill 的 `pages`，缺失 skill 显示 gone。`memory_of` 在页面 after-build 发 `core.call("memory.get", {station})`，按站点内存缓存，错误可见。不是“保存新记忆”功能。
- **core / 数据链：** `client/core-ts/src/ops.ts` 的 `memory.get` 映射 `GET /memory`；`looks.ts` 的 memory 响应处理及 `memorySections` 将全局文本按 Markdown 二级标题分节，并为 skills 生成 `kindText`、`whenText`、`line`、`pages`（总览加文件）。这次上游的项目记忆/skill 展示契约确有业务意义。站点 RPC 传输、服务端 ACL、跨账户缓存清理及完整路由接入尚未逐段验证；普通 URL/path 不是 Apple API 或授权证据。另读 `sfdesk/memory.mbt`，桌面有对应阅读呈现，不把桌面专属布局当作 iOS 系统入口。
- **方向（提案）：** 前台打开所选授权站点的全局记忆或具体项目 skill 文档；必需站点，skill 可选，全局为显式选项；文件页可作为后续可选参数。拟议身份必须包含账户、workspace、完整站点地址、skill 名及文件 key。`at` 是当前排序索引，不能作为跨更新稳定全局章节 ID；稳定章节定位/重命名规则是新增设计，不是现有能力。同名先让用户选择；删除、撤权、离线或文档失效明确失败，不静默转入其他站点/同名 skill。
- **重复执行 / 前后台：** 提案仅打开阅读，不修改或分享；现有缓存不证明后台数据源可用，也没有原生冷启动导航证明。若要重复打开复用页面，需新增 guard。缓存 keyed by station 不等于已证明账户隔离；查询和执行须各自重新核权。设备解锁、应用登录、数据授权是不同检查。记忆可能包含敏感项目上下文，不在锁屏、语音结果或 Spotlight 默认输出正文；暂不索引内容。
- **普通路径 / schema：** 普通前台 Intent、实体/query/结果和入口全部 **需验证（E1）**；未提出具体 API 可用版本。可选 schema 未确定（E2），不强行套用笔记/文档 schema，不宣称 Apple Intelligence 支持。Shortcuts 尚无实现；App Shortcuts/Siri provider、短语及精确声明待查；Spotlight 无已验证索引；Apple Intelligence 未评估。源代码、编译、入口可见、执行与真机五层证据均不能替代。
- **结论：需验证，P2（先于写入型 A2），M–L。** 直接回到项目记忆有任务价值，风险小于自动发送；无使用频率数据，价值排序仅定性。成本包含稳定实体与文档失效策略、权限过滤、桥接/冷启动、E1 符号证据及入口验证，不计为现成服务。先用真实授权账户核验在线/离线、账户切换、撤权、skill 删除/重命名和全局章节变序；本次没有调用 `memory.get` 或执行导航业务。

### 新增排除与交接修正

| 功能 | 实读证据 / 当前语义 | 本轮决定 |
| --- | --- | --- |
| 分享 / 停止分享 skill | `settings/memory.mbt::skill_share_row` 点击提交 `skill.share`，`on = !当前 host role`；成功后重读。内置或 role=user 隐藏开关；`ops.ts` 映射 POST `/skills/{name}/share`，可带 `on` / `allow`，UI 未提供 allow 时不是仅向单个指定站点分享 | 有真实共享写入，不是装饰开关；会影响工作区其他站点，权限/收件范围与重复语义尚不完整，不另纳自动化候选。不把 UI toggle 冒称幂等“设为已分享” |
| 内置 skill 展开、文档页签切换与桌面布局 | `builtin_open`、`doc_picked` 为 UI 内存选择；桌面 memory 页面读取同类业务内容 | 无独立系统任务价值，A3 已覆盖有用阅读，不拆分凑数 |

**最终首批仍为 0；待验证 3 项，顺序 A1 → A3 → A2。** 最关键缺口仍是实际账户及 workspace/station/session ACL、原生/Hermes 冷启动及 headless 桥接、稳定实体身份，以及 E1 每个必要 Apple symbol/availability 的精确声明证据。A3 另外需要文档变更/失效策略；A2 另外需要确认、幂等与部分成功恢复。

真实 reviewer chat / station 账号仍待密码卡 **105** 提供；不扩大 Apple 登录，不把隔离安全存储实验视为真实账户完成。VoiceOver 运行体验仍未验证。用户选择的主任务是 **GitHub 云 CI**，专用 owner 凭据仍待提供；本报告不执行 CI、不查凭据、不上传、不安装，也不声称签名/分发完成。旧报告列出的历史隔离测试仅为历史背景，本次未复跑或新增构建、测试、业务操作、网络请求、提交。**本次唯一写入为现有 `intent-opportunities.md`；窄提交及附件由主任务负责人处理。**
