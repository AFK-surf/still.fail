# mbui iOS App Intents 机会评估

## 现有集成清单

本次源码检查发现 **0 个已声明的 App Intents 动作**；未发现面向 Shortcuts、App Shortcuts、Spotlight、Siri 的相关声明，也未发现 Apple Intelligence schema 声明。这是限定范围的源码清单，不是构建产物或系统运行验证。

| 业务动作 | Intent / Provider / Entity / Query | 当前接入 | 证据边界 |
| --- | --- | --- | --- |
| 无 | 在 `apps/mbui/src`、`apps/mbui/mbui/src` 搜索 `AppIntent`、`AppShortcut`、`AppShortcutsProvider`、`AppEntity`、`EntityQuery`、`@AssistantIntent`、`@AssistantEntity`，均无匹配 | 0 个 | 已另读主应用与 Share plist；Share extension 不等于 App Intents 集成。未检查所有其他产品目录、生成产物或运行时注册结果 |

## 项目与范围

- 分析日期：2026-10-24；导入项目 still.fail / mbui。当前实现基于 `main` / `7cb11d1cabfb35a59b8f0391f91da39fe939c4bb`，并包含本轮审核登录、取消/保存协议、安全存储及原生输入修改；本报告按该实现快照复核，不代表已完成真实账号验收的版本。
- 目的：本次登录和会话存储契约改变后重跑评估。保留上一版 A1/A2 动作身份及首批零项结论；审核密码与原生输入接入不产生新的系统业务动作。原生 Apple 登录第二阶段未实现，不计入现有能力。
- 已读 find-intent 技能及报告模板、普通 App Intents 参考；参考中的 starter 配置和示例不作为本项目或具体 Apple API 可用性证据。
- 范围：mbui UI、C bridge 声明、Hermes 架构说明、构建入口及 plist，定向追踪“打开已有对话”“新建对话并发送首条消息”至 `client/core-ts`。未全量扫描大型仓库。

| Target / 配置 | 相关来源 | 最低系统 | 工具链证据与未知 |
| --- | --- | --- | --- |
| 主应用 `fail.still.mbui`（默认源码调试 ID 为 `fail.still.mbui.debug`） | `.airbuild/build-ios.sh`；`apps/mbui/scripts/ios.sh`；`apps/mbui/mbui/scripts/ios.sh`；`apps/mbui/ios/Info.plist` | plist 为 17.0；底层脚本分别使用 simulator/device 的 17.0 编译标志 | 自定义 MoonBit→C、ObjC/ObjC++ host、Hermes；脚本以 `xcrun` 选择 SDK。已独立读取 Xcode 27.1（27A9275）和 iphoneos SDK 27.1；它们是构建环境，不代表当前预览运行时。具体 App Intents SDK 符号仍未读取，不推导 API 可用性 |
| Share extension `fail.still.mbui.share` | `.airbuild/airbuild.yaml`；`apps/mbui/ios/Share-Info.plist`；底层 `ios.sh` 的 Share.appex 打包配置 | plist 为 17.0 | `MBShareController`，声明 `com.apple.share-services`，接收文字、URL、图片、视频、文件；与主应用通过 app group 交接。未验证签名、实际 extension 运行或生成工程源成员 |

`.airbuild/build-ios.sh` 先构建自定义应用，再生成包装 Xcode 工程并归档；不能把包装工程视为已具备 Swift App Intents 编译、链接和元数据提取链路。

## 决策摘要

**可直接进入实施的首批：0 项。** 保留两个有业务价值的待验证机会，优先验证“打开指定已有对话”，其次评估“新建并发送首条消息”。两者均为 **需验证**，不是已推荐可交付路径。

共同阻塞：现有登录和业务 Store 位于 JS/Hermes core，原生仅有低层 JSON bridge；尚无原生 App Intents 服务层、实体查询、冷启动账户恢复、调用取消/结果关联及前台导航接入证据。具体 Apple API 与系统入口的声明/可用性也未核实。优先解决桥接与权限边界，不扩散研究 schema 或改变部署目标。

## 已评估动作

### A1 打开指定已有对话

- **业务状态：已实现（应用内导航及阅读状态链路）。** `apps/mbui/src/sfapp/home.mbt:703–708` 的列表点击分支，根据消息定位进入 `open_chat_at` 或 `app.nav.push(Chat(r))`；`sfapp/chat.mbt:1620` 的 `open_chat_at` 调用 `go_to` 后 push 对话。搜索入口 `sfapp/search.mbt:627` 调用 `open_chat_found`。
- **业务与数据链：** `sfapp/chat.mbt:1716–1739` 的 `tell_focus` 以 `station`、`session` 和可选 thread/seen 调用 `client.focus`；`client/core-ts/src/attend-parse.ts` 解析该请求；`src/attention.ts:113–119` 的 focus handler 调用 `prefs.chatOpened`，更新关注与订阅；`src/prefs.ts:184–191` 将最后打开对话按 workspace 写回 `data.set(PREFS, prefs)`。因此“打开”可能同时影响已读状态，不能描述为绝对无副作用查询。
- **方向（提案）：** 前台打开已有对话，不创建、不发送。必需参数为选定对话；拟议实体键应包含账户范围、workspace/station、session，不能用标题作唯一 ID。按标题搜索仅展示当前账户可访问候选，同名必须让用户选择；过期、删除或权限撤销后明确失败，不回退到其他同名对话。已有 session 标识与 prefs 持久化提供线索，但跨重启稳定性、跨账户冲突与实体查询仍待验证。
- **重复执行：** 不应创建内容；现有导航直接 push，不能认定已具备防重复页面逻辑。若要求重复调用复用当前页，需新增导航 guard（提案）。
- **访问与安全：** `tell_focus` 已检查 `Source.read_only`，但它不是账户授权证明。尚未追完整账号→workspace→会话 ACL 链路；新实体查询和执行必须同时检查当前账户及访问权。设备解锁不等于应用登录，也不等于数据授权。避免把对话标题、消息、站点信息默认暴露到锁屏、语音回复或全局搜索；不主动朗读正文。
- **普通路径 / schema：** 普通前台 App Intent 仅为设计方向，相关 Apple 符号、最低版本、所选 SDK 声明均未验证（E1）；schema 精确领域/member 未确定，不主张任何增强能力。
- **系统入口：** Shortcuts 动作及 App Shortcuts provider/短语待设计与核验；Spotlight 未见索引/实体接入证据；Siri 短语、账户选择和前台跳转未验证；Apple Intelligence 未验证，不能由普通 Intent 推导支持。
- **结论与优先级：需验证，P1，M–L。** 价值在于直接回到特定任务上下文，风险低于自动发送；成本主要是原生桥接、身份解析、权限过滤和冷启动导航，而非 Intent 声明本身。无使用统计，排序为定性判断。
- **下一步：** 先验证从原生冷启动恢复既有账户、按稳定 ID 查询授权会话并送达导航；测试注销、切换账户、离线、撤权、重复打开及已读副作用。未编译、未验证入口可见性、未跑模拟器/真机。

### A2 新建对话并发送首条消息

- **业务状态：已实现（应用内）。** `apps/mbui/src/sfapp/newchat.mbt` 的 `new_chat` / `new_chat_page` 为入口；`send_first:603` 检查 `src.read_only`、`fresh.starting`，保存/清空草稿并处理失败恢复；已有待建 key 时复用，否则在 `:697` 调用 `newChat.create`，再以该 key 调用 `chat.send`（`:664`）。它不是单纯“打开新建页”。
- **core 链：** `client/core-ts/src/choose-calls.ts:48–54` 的 `newChat.create` → `Choose.create`（`src/choose.ts:349`，检查 runtime/model 可用）→ `handlers.chatCreate`（`src/views/calls.ts:250–259`）→ `local.pendingNew` 与 `makeChat`。`src/views/local.ts:142` 生成新的 pending key；`#savePending` 写入 `data.putLocal`。`chatSendTo` 根据 pending/bound session 排队或发送；`ViewCalls.resume` 可恢复未完成队列。**返回 pending key / 排队成功不等于远端已建好并发送完成。**
- **方向（提案）：** 若产品选择自动化，明确命名“新建对话并发送首条消息”；输入账户范围内的 workspace/station 与消息，runtime/model/profile 可选择或使用已明确展示的配置；不默默切换账号、站点或模型。同名站点先消歧；失效参数失败，不任意选择替代项。输出应区分已排队、已创建、已发送、失败。
- **重复执行：** `outgoing`（`src/views/calls.ts:43`）为每次新消息生成随机 idem key；持久队列恢复可沿用原操作，但不能据此认定两次独立系统调用会自动去重。`fresh.starting` 是当前 UI 内存态，不是系统动作幂等方案；跨调用幂等与部分完成恢复需要新设计。
- **访问与安全：** 既有 `read_only` 与模型检查有证据；`views/calls.ts` 的 `parse(station)` 只是 `StationAddr.parse`，不能当作 ACL。完整账户登录恢复、站点/会话授权与服务端拒绝路径未追完，需补验。消息可能触发远端代理、消耗额度或处理共享工作区数据；建议首期前台展示账户、站点、模型及消息并确认，不默认后台发送。生物认证、应用登录、数据权限、发送确认应独立处理。
- **普通路径 / schema / 系统入口：** 普通 Intent 方向需验证（E1）；不提出未经核实的 schema 名称。Shortcuts / Siri 若引入发送能力须明确确认与失败恢复；Spotlight 暂不索引消息正文；Apple Intelligence 未确定语义、依赖实体和可用条件。后台能力不能从 Hermes 线程或队列持久化推导。
- **结论与优先级：需验证，P2，L。** 有跨应用输入价值，但写操作、远端执行、去重和部分完成风险显著高于 A1。若产品只要打开新建页，应缩小为另一种明确的导航语义，不能混称“已开始对话”。
- **下一步：** 验证登录/ACL、远端建会话和发送完成事件、账户切换、离线后恢复、重复调用及取消；在产品批准确认策略前不进入首批。未进行任何发送或创建操作。

## 共享原生桥接与授权证据

`apps/mbui/src/host/core_api.h` 实际声明仅有 `mb_core_start` / `mb_core_send` / `mb_core_stop`：一个 core、一个 UI client；异步消息回调在 core 线程，宿主自行复制并切 UI 线程。`mb_core_start` 的 data_dir 保存账户、登录与数据库，返回时脚本仍可能加载，致命启动错误异步返回。已有低层通信基础不等于原生 Intent 可直接可靠调用。

`apps/mbui/core/README.md` 说明 `apple_core.mm` 承载 Hermes、Keychain secure 操作和 shell；该说明是架构证据，不是本次实际运行证明。`client/core-ts/src/core/execute.ts:45–54` 显示 `authBegin`、`authPassword`、`authComplete` 委托 `inner.accounts`。本次已追 Accounts.load 的错误传播、password prepare/accept/cancel 及持久化互斥；当前 iOS 主应用 accounts 操作经 apple_core.mm 路由至 mbui_ios_sessions.h/_apple.h 的系统 Keychain，稳定安装 UUID 区分重装/包身份。隔离状态机测试与设备/模拟器桥接编译通过，但未验证真实系统安全存储行为。最终保存的不可取消边界已获产品确认；进度事件、核心和 UI 各自 15 秒预算、同一尝试重新核对与失败终态保留已实现并通过隔离回归，但仍未完成真实账号与原生安全存储的联动验收，不是可供原生系统动作直接复用的完成态服务。账户登录成功本身也不能证明工作区/站点/会话 ACL；完整数据所有权和站点 RPC 授权链仍待验证。

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

**首批 0 项；待验证顺序 A1 → A2。** 先决定是否仅做前台导航，以及是否接受任何自动发送。关键依赖：原生 Intent 构建/元数据链路、Hermes 服务桥接与冷启动、账户隔离和 ACL、稳定实体 ID、写操作确认及幂等/恢复、精确 Apple API 声明证据。随后分别验证编译、入口可见、执行结果、签名模拟器/真机及 Siri；这些证据不能互相替代。

本报告完成于仓库根目录 `intent-opportunities.md`；本次仅更新报告和读取源码/版本，没有新增 App Intents、启动业务操作或改变系统权限。整体开发任务另外执行了文中明确标注的隔离测试及桥接编译；它们不等于 App Intents 编译、运行、入口可见性或真实账号访问验证。
