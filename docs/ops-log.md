# 部署维护日志

线上 ember（ember cloud、各台 station）的部署、更新和出过的事，按时间倒序。时间是北京时间。怎么运行、服务怎么装见 docs/operations.md。

## 现在怎么上线

- **合并**：GitHub `zzj3720/ember` 的 main 是唯一的 main。commit / push 时 git hook 跑快速检查（`scripts/check.sh`，几秒）。分支一推上去，CI 就跑完整检查和打包（dry-run），结果当合并的证据。
- **部署（CI，自动）**：push 到 main 后，`.github/workflows/pipeline.yml` 在 mini1 的 runner 上检查上次部署（tag `deployed/beta`）以来的改动，过了就依次部署改到的 api、web-beta（app.youdid.wtf）、admin、preview、site-beta。合并就等于上线这些部分，所以合之前要想清楚新旧混跑。哪一步失败，后面都不发，tag 不动；修好再合一个提交，会连同上次没发出去的一起发。详见 docs/operations.md「CI」。
- **部署（studio，手动）**：CI 不做的 relay、station 发布包和 studio 的 station 更新，还是在 studio 上跑 `~/bin/ember-job deploy "~/bin/ember-deploy"`（不直接 ssh 跑，ssh 会断）。它从 GitHub 拉 main，对上次跑它以来的改动跑完整检查，过了才部署 relay（如果改了），并在后台上传 station 发布包（`/tmp/ember-release.log`），传完 studio 的 station 自己 `stillfail update`（`/tmp/ember-station-update.log`，原地交接）。studio 跑的是正式安装的 station（LaunchAgent `fail.still.station`，`~/.stillfail/app`）；`mesh/target` 里的 stillfail-station 只给测试 station 用。上次跑到哪：studio `~/.stillfail/deployed-commit`。
- **部署前 review**：合并前（不是部署前）把数据格式、新旧混跑的兼容、station 的启动和更新流程、删除数据或碰外部服务和密钥的改动过一遍，有风险先说。
- **测试版（beta）和转正**：测试版在自己的域名 youdid.wtf 上（still.fail 的对偶）。web 先上 app.youdid.wtf（Worker `ember-web-beta`，和 app 同一份 dist），管理后台「用户」里开了「测试版」的账号才能用（别的账号调 API 回 403 `not_beta`，页面跳回 app.still.fail 的同一路径；测试版 app「youdid.wtf」带 `x-stillfail-channel: beta` 也这样拦）。登录经 app.still.fail 走 Google，再回 app.youdid.wtf/auth/callback，不用在 Google 加回调。`python3 cloud/deploy.py` 不带参数时部署 `web-beta`、不部署 `web`，并把这次的构建存进 `<deploy>/builds/<commit>/cloud-web`（留最近 10 个）；在 beta 上试好后 `python3 cloud/deploy.py promote-web <commit 或目录>` 把同一份文件原样部署到 app.still.fail（不重新构建）。点名 `web` 仍然是直接构建并上 app。youdid.wtf 这个 zone 还没在 Cloudflare 上（active）时，deploy.py 跳过 `web-beta`、`site-beta`，api 去掉 app.youdid.wtf 的路由和 BETA_ORIGIN，不带参数的部署改上 `web`（`STILLFAIL_BETA=on|off` 可强制）。测试版官网 youdid.wtf：`python3 cloud/deploy.py site-beta`（不在默认部署里，`pnpm build:site-beta` 出 dist/site-beta，下载链接指向测试版 app）。station：`release.sh --beta` 发到 `beta/`、`station-beta.json`，`release.sh promote` 拷成正式名；装测试版 station 用 `install.sh?channel=beta` 或 `STILLFAIL_CHANNEL=beta`。测试版 app（`fail.still.*.beta`）是单独的 app：`release.sh --beta android|desktop` 发到 `android/beta/latest.json`、`desktop/stillfail-beta-mac.yml`，没有 promote，正式版照常 `release.sh android|desktop`。下载链接 `/releases/latest/android-beta`、`/releases/latest/mac-beta`。studio 的 `~/bin/ember-deploy` 目前写死 `parts+=(web admin)`，要走测试版流程得改成 `web-beta`。
- **更新 station**：不自动更新。发布包上传完后在那台机器上 `ember update`；支持交接的 station（`~/.ember/run/station.json` 里有 `"handoff"`）原地换版本，pid 不变，正在跑的轮次、agent 进程和 job 都接着跑。

## 卡住了怎么办

- **`ember update` 半天没动静、消息送不到**：多半是没能交接、退回了排空（`~/.ember/ember.log` 里有 `draining: no new turns`）。排空期间不开新轮次，新消息排队；最多等 10 分钟轮次结束，没人重启的话再过 5 分钟才自己恢复。处理：先结束卡住的 `ember update`（`ps` 找 `/bin/sh …/ember update` 和它的子进程），再给 station 发 `kill -USR2 <pid>`（pid 取 `run/station.json` 里的；`pgrep -f 'ember-station run'` 还会匹配到 agent 在工作区里起的测试 station，别用）。同一版本交接给自己，排空状态就没了。
- **部署时 `fetch failed`**：studio 出外网经过局域网的 Surge 旁路由（192.168.20.11），偶尔断。`ember-deploy` 的 cloud 部署遇到它会自己重试三次；拉 GitHub 断了就重跑部署。重复部署 Worker 没有副作用。
- **完整检查不过**：`/tmp/ember-check.log`。什么都没部署出去，线上还是上一版。

## 待部署

- Station 概览精简（station-summary-alerts）：发布 web 和桌面端（含同版本 core）；无需更新 station 或迁移数据。概览仅显示异常进度框（边框为已用比例、文字为剩余容量）、网络和可用更新，点击名字查看设备与软件详情。一键更新由 core 调旧版已有的单项更新接口，先运行时后 station；失败则停止后续项目。新 Meter.remaining 为可选字段，旧界面不受影响；移动端布局不变。上线后确认正常指标隐藏、详情可打开、更新失败留在原行。
- 决策「无需处理」（dismiss-human-decision）：新增 station `PUT /threads/:id/closed-card` 和 core `decision.close`，web/桌面、手机 web、Android 卡片提供静默结束入口；写入 `closed_cards`，只结束对应的 need human，不发送消息或唤醒 agent。先更新 station，再发 web/桌面/Android；新客户端连旧 station 时此入口会报不支持，卡片保留，普通回复和「不再提醒」仍可用。旧客户端连新 station 会从现有状态更新看到卡片结束。上线后验：点「无需处理」后两台设备上的卡片和等待标记都消失，聊天没有新消息、agent 没有新轮次；再提问仍可正常唤醒。老会话通过 migration 5 得知静默关闭行为。

- 建议等待用户决策（advice-needs-decision）：更新 station；agent 给出建议或备选方案后应询问用户决策，用 `need_human` 并附答复卡片，不直接 `all_done`。已授权工作继续执行，不重复索要决定。同时精简主 prompt 和四个内置 skill，保留行为规则及技术限制，不新增参考文件。迁移说明 3、4 会通知旧会话；无接口或数据格式变化。上线后在新旧会话分别请求建议，确认出现决策卡片且对话保持待用户处理。
- 网页更新提示（web-update-notice）：只需部署 web，build.json 新增可选 revision，旧客户端/旧 station 不受影响。用户需先刷新一次加载本功能，此后当前站点发布不同 revision 会出现「刷新更新 / 稍后」；后台标签页回前台后检查，当前页每分钟检查。按域名检查，beta 不会提示正式站的版本。旧元数据、离线和请求失败静默重试。上线验：保留已加载本功能的页面，再部署一个 web revision，一分钟内出现提示，稍后关闭，点击刷新保留当前 URL。

- 本机文件链接（fix/local-file-links）：只需更新 station，无客户端或数据库迁移。still.fail 聊天的 chat_post 自动将 Markdown 绝对路径链接/图片复制成现有附件，并将目标改成编码后的文件名；新 station 配旧客户端可用，旧 station 保持原行为。旧消息不回填。上线后在测试会话发一个仅含本机文件链接、不带 files 的消息，确认能打开附件；文件不存在时应在发出前报错。老 agent 会收到迁移说明。
- 本机订阅去重（hide-duplicate-local-account）：需更新 station（overview 提供订阅实际邮箱）和 web/桌面/Android 的共享 core。可任意顺序更新；新客户端连旧 station 缺邮箱时保留原显示，旧客户端忽略新增字段。无数据迁移。上线后检查同服务同邮箱本机项消失，不同账号仍显示；删除绑定订阅后本机项恢复。

- Claude 额度续期（claude-quota-refresh）：需发 station 包，无客户端/API/数据迁移依赖。额度读取和机器账号启动直接走 OAuth 续期，不再发 Haiku 对话；沿用文件/钥匙串原位置与 Claude Code 2.1.286 的新旧刷新锁。升级后在机器登录和独立登录两类账号上，token 到期后只打开账号额度页，确认恢复显示且不出现模型调用；模拟接口已覆盖到期、提前 401、并发、失败重试、钥匙串及遗留锁恢复。未来 Claude Code 调整锁或凭据格式时需同步核对。


- 模型勾选反馈：需发布 web（含新版 wasm core）和 Android；无需更新 station 或迁移数据。沿用 `profile.put`，core 给 Profile 增加可选 `modelsSaving`，旧 station 兼容。上线后在 Profile 勾选模型，确认立即勾选、保存中行内转圈、成功不退勾，失败回退并提示。

- Android New chat 首条发送闪动（fix/android-new-chat-flash）：随下次 Android 发版；仅视图修复，无接口、数据迁移或 station/cloud 顺序要求。浅色/深色点 New chat 发首条消息，输入框底色不应闪灰。Studio 完整 Android 检查和两项逐帧回归已通过，原版回归均能在第 2 帧捕获灰闪。

- 安卓菜单动效（android-menu-motion）：只改 Android 共用 MenuHost/SheetHost，需要发安卓包；无协议、core 或数据变化。修复首次展开跳过动画、底部菜单遮罩突变与滑入前空程；菜单缩放及底部菜单位移改为弹簧减速，连续开关承接当前速度。studio 完整检查通过，MenuMotionTest 浅深色展开/收起/快速重开录屏已获用户认可。发版后检查首页筛选、长按菜单和附件底部菜单进出动效。
- 安卓性能隔离：发布安卓时必须重新构建 `client/ffi` 的 `.so` 和 Kotlin 界面，不能只复用旧的 native 库；桌面的 `client/node` 也继承 native 队列隔离。协议、数据库和 station/cloud 接口不变，新旧客户端可混跑。上线后检查长代码打开时仍能点击/滑动、大附件上传下载时其他聊天继续更新、预览流的最后一个 chunk 不丢。`CoreListener` 的 API 与 topic 回调现在可能并发，同一流的进度与结束仍按序。

- 安卓分屏键盘动效（fix/android-ime-motion）：需发安卓包；仅视图变化，无 core/API 或数据迁移依赖。多窗口缺少系统 IME 中间帧时补升降过渡，有原生帧及全屏继续直通。studio 安卓完整检查和 KeyboardInsetsTest 两项通过，Android 16 双应用分屏浅/深色录屏已确认。发版后在厂商折叠屏实机验分屏升降、快速反向收放，以及退出分屏后的全屏键盘。
- 奏折输入框（memorial-composer）：奏折直接复用 chat 的输入组件（PC ComposerView、手机 web MobileComposer、Android HostComposer），带附件、引用、@ 对话与原有伸缩；草稿按奏折保存；发 web（含新 wasm core）、桌面和 Android 包，不能只换视图而继续用旧 core（旧 core 的 decision.reply 只接收问答类卡片且不接附件）。沿用 chat 消息和引用接口，兼容旧 station，无数据迁移。上线后验：有选项的奏折输入多行回复并发送、选项仍可点；加附件或引用后可发送，内容进入原 chat；左右滑动后回来保留草稿；失败保留文字；处理最后一件返回列表。

- 移动端执行历史全屏页（mobile-history-page）：手机 web 和安卓从半屏抽屉改为独立页面，顶部返回、系统返回及聊天链接回到聊天；沿用页面栈保存位置。只改视图，不改 core/station 接口，可与旧 station 混用。web 随部署更新，安卓需要发新版。上线后验：点击 agent 打开全屏历史，步骤/详情可切换，返回后聊天位置不变。
- 等待决定的对话读取失败（fix-decision-status-compat）：客户端 shapes 补齐旧 core 生成的 `decision` 状态；保留 main 将旧 `need_decision` 映射为 `block` 的逻辑。需更新 web core，并发 Android/桌面客户端；只更新 station 不能修复旧客户端。无需数据迁移。新版客户端打开旧 station 的等待决定对话，确认消息和输入框正常出现。
- 奏折清空自动返回（fix/edicts-empty-back）：发布 web 和 Android 包；沿用 core 的 decisions count/loading 字段，无接口或数据迁移，无部署顺序要求。上线后验最后一件处理完返回上一页、加载中不退、从奏折打开的其他页面不被误退。Studio 完整检查及 7 项安卓交互测试通过。

- station 自更新下载进度（station-update-progress）：发 station 包；从现有安装脚本的 curl 进度输出上报已有 `percent` 字段，Android/web 无需更新，旧 cloud 安装脚本也兼容。本次从旧 station 升级仍只有阶段文字，运行新 station 后的下一次更新才会显示下载百分比；上线后验下载期间百分比递增，交接/重启后清除进度条。

- 安卓正文视频附件点按（fix-android-video）：仅安卓 UI 改动，需要发布安卓包；兼容现有 core/station，无部署顺序要求。上线后验：同段两个 `![](视频.mp4)` 和 Markdown 表格中的视频卡片均可点开播放。Studio 独立模拟器已复现修复前失败、修复后通过，完整 Android 检查通过。

- 剩余客户端精简（complete-client-simplification）：core 接管完整 Slack 接入向导（草稿、步骤、配置 token、建 app、校验、绑定和提交），三端只保留视图与本地输入回显；表单按 client/form 隔离，关闭后丢弃迟到结果。普通 HTTP 操作参数从 ops.rs 生成 TS/Kotlin 包装，保留缺省与显式 null 的区别；操作反馈统一观察 doing，系统权限、图片导出和动效仍在端上。core/station 按执行、账号、路由、传输、事件、线程拆文件，无数据迁移、无新增 station/cloud 接口。需要发 web、桌面 core、Android；web 遇到旧桌面 core 的 unknown_call 时保留旧向导，新客户端配旧 station 仍用原接口。上线后验：三端分别走配置 token/OAuth 和手填 token 路径；切换模型、返回上一步、校验失败、关闭后重开；连续点创建只出现一个连接；两个窗口的草稿互不串。

- 卡片和结束状态分开（pinned-long-term 分支，cards）：结束状态只剩 all_done（done 必填）/ need_help（need 必填）/ waiting（for 必填），每种都可带 `about`（本对话里某条消息的 ts）；need_decision 照收，等于「带 options 卡片的帖子 + need_help」，need 默认取消息第一行。卡片是消息的属性：chat_post `card` = `{type:"options",options}` 或 `{type:"text",placeholder?}`，旧的顶层 `options` 照收（= options 卡片），任何帖子（带不带 kind）都能带，Slack 里拒绝。station：entries 加 `card` 列、turns 加 `about_thread/about_n/about_ts` 列（旧库打开时自动补）；options 卡片仍同时写 `options` 列，旧 station 回滚也读得到；chat 行新增 `card`（任何类型），options 卡片仍给 `decision`（1388 等旧客户端照旧显示和点选，text 卡片它们看不到）；`PUT /threads/:id/dismissed` 接受任何卡片；lastTurn 加 `about`；ending 把旧的 need_decision 读成 need_help。core：行的 `stateText` 先看状态（要你帮忙/出问题），再看卡片（奏 · …，agent 在干活时也显示），再在等/做完了；新字段 `stateAbout`（seq）；need_help 的 tone 改成 wait（蓝圈），只有失败是 alert；workspace 计数 wait 含 need_help，文案「N 个在等你」；通知 need_help 为「要你帮忙 · <need>」；新调用 `decision.reply`；消息和 `decisions` 条目带 `card`。界面要改（见分支说明）：text 卡片只在奏页面画输入框（调 `decision.reply`），消息流里 options 卡片照旧；行可用 `stateAbout` 跳到消息。all_done 的 done 现在是理由：少于 6 个字或只是「做完了/已完成/done/ok」会被拒；agent 指令同时写明等人（确认、验证、给 key、选择）一律 need_help，waiting 只给自己起的、会自己回来的工作。station 要发包，web 跟部署走，安卓要发一版。上线后验：agent 发 text 卡片并 need_help，行显示「要你帮忙：…」蓝圈，奏页有输入框，填写后卡片消失、agent 收到引用该消息的回复。
- 决定和新的结束状态（block-options）：chat 里的「事」（items）整套去掉，换成 agent 的 `need_decision` 帖子带 `options`；结束状态改名 all_done / need_decision / need_help（带 `need`）/ waiting，旧的 final/block 照收。station：entries 加 `options` 列、turns 加 `need` 列（旧库打开时自动补），新表 `dismissed`；chat 行带可选的 `decision`，新路由 `PUT /threads/:id/dismissed {n}`；turns/entries 里存新词，但接口里的 `declared` 仍给旧词（final/block），另加 `ending` 给新词，旧客户端照常显示；agent 指令和 nudge 改了（session.txt 快照同步）。core：行的 `decision`/`stateText`/`settled`/`archivable`，消息的 `options`/`decision`，新 topic `decisions`，调用 `decision.answer`/`decision.defer`/`decision.dismiss`，workspace 计数 `decisions`；旧的 `item.*` 调用没了。界面：web/手机 web/安卓只留了行上的「奏 · …」，卡片删了，决定页和消息下的选项按钮等界面会话来做。station 要发包，web 跟部署走，安卓要发一版。新 station + 旧客户端：看不到选项，agent 照常说话，行状态照旧；旧 station + 新客户端：没有 decision，状态文字按 declared 推。items 表留在库里不再用。上线后验：让 agent 用 need_decision 问一个问题，chat 行显示「奏 · …」和蓝圈，`decisions` 里有它；另一个人回一句后它消失；agent 以 all_done 结束的 chat 变淡沉到当天底部。
- Station 互联远程任务（station-remote-jobs）：先发 cloud（presence state 新增 peers 名单），再发参与互联的 station；旧客户端无改动，旧 station 忽略新字段，旧 cloud 下互联不启用。接收端管理员明确设置 `remoteTasks.allow` 为允许的来源 station 公钥，默认关闭。详见 docs/station-peers.md；上线后在获准测试目录走 prepare → 上传 → start → 日志 → 下载，同 key 重试仍为同一任务。
- 模型思考档位：需要同时更新 station、web core 和 Android。新 station 从 Codex `model/list` 保存每账号/模型档位；新客户端读可选 `check.modelEfforts`，旧 station 缺此字段时保留旧列表，旧客户端仍能连接新 station。上线后在 Profile 的「刷新模型」更新能力，再确认 Astra 可选/保存 max、ultra（含已有会话与连接）；Android 和手机 web 的模型区新增刷新入口。无需数据迁移。
- GPT 用量费用修复（fix-gpt-usage）：补 GPT-6 Astra / Sol / Luna、GPT-6.1 Sol、GPT-5.6 Sol 标准 API 单价；已有 token 记录查询时直接折算，无需重扫或修改数据库。core 对无价目显示「未计价」，混合统计标出 ≥。点击折合费用可进入各台 station 的实际价目表（输入、缓存读取/写入、输出），三端都有入口，旧 station 显示尚未提供价目表。station 要更新才能补 GPT 费用；web、桌面、安卓更新 core 后有新的文案，接口字段不变，新旧混跑兼容。费用是标准短上下文单价估算，不含服务等级及长上下文加价。上线验：用量页 GPT 已有调用费用不再为零，未知模型显示未计价，调用数和 token 不变。

- core 与多端精简（simplify-core-operations）：发布 web（含 WASM）、桌面 core、Android；station/cloud API 无变更，无部署顺序要求。新版 web 配旧桌面 core 的 Slack token 表单会退回原校验逻辑；旧页面配新 core 的 `slack.verify` 保留。token 草稿只在内存中，关闭表单/断开客户端清除。上线后验：三端新增连接与更换 token，修改输入后原校验失效、旧校验结果不推进下一步；旧 station 的归档 404 回退仍正常。

- Slack 会话自动标题（slack-auto-title）：station 允许 agent 用 chat_post.title 为 Slack 线程设置 still.fail 列表标题，沿用手动标题保护和改名频率限制；同步 agent 指令。只需发 station，新旧客户端均沿用现有 title 字段。上线后验：Slack 线程首个最终回复后，still.fail 列表显示概括标题；手动命名后不会被覆盖。已有会话在 agent 下次提供标题时生效，不批量回填。

- Claude 额度报错识别（fix-quota-failover）：更新 station；无需更新客户端。`You've hit your session limit` 等额度提示现在归为 rate_limit，自动账号会话可进入切换并继续链路；固定账号仍遵守原有固定设置。新旧数据和接口不变。上线后核对自然发生的额度失败记录为 rate_limit，且有可用同模型账号时自动继续。
- 中继检测口径（relay-measure-consistent）：更新 web/wasm、桌面 core 和安卓；station、cloud API 无需更新，仍兼容旧 station。后台探测只走指定中继，3 次预热后取 5 次 QUIC RTT 估算的中位数；选路优先比较同轮检测。三端移除手动检测入口和各中继检测结果，仅保留当前连接网络信息；旧客户端的检测调用仍兼容。上线后验：安卓同局域网仍可直连，检测值不被直连冒充；无需打开 station 页面或点击检测，后台会自动切换到明显更快的中继。

- 事项卡片说清在问什么、等待说清在等什么（ask-question）：station 要求 waiting 的事项带 `ask.question`（没有就报错让 agent 补），`chat_state waiting` 必须带 `for`（turns 表补 `wait_for` 列，旧库自动补，行和会话的 `lastTurn` 带 `waitFor`）；指令同步。core：`WorkItem` 加 `question`、`head`（「奏 · 标题 · 时间」，不再带分支），agent 状态「在等：…」。web 和安卓卡片改成问题做主文字、点空白跳到提问的消息；安卓卡片的滑动改挂在外层（加了 23 个真实触摸的 androidTest：`AskCardSwipeTest`）。新字段可选：旧 station 没有 question 时卡片用标题、没有 waitFor 时显示「等待中」。web 跟部署走，station 要发包，安卓要发一版。上线后验：让 agent 声明一件 waiting 的事，卡片主文字是一句问题；agent 用 waiting 结束时，名字下面显示「在等：…」；安卓上横着拖卡片能滑走。
- 用量页未知人员解析修复（usage-unknown-person）：core 仍把无法识别人员的历史用量计入总额和「说不清是谁」，但不再把缺少来源字段的占位对象当作 `Creator` 发送，避免安卓整页解析失败。接口字段不变，`person` 本来可空；新旧 station 都兼容。需发布安卓和桌面客户端，web 随部署更新；station 无需更新。上线后用含未知人员历史记录的 workspace 打开用量页，确认 7 天/30 天能显示且未知人员的用量仍计入。

- 归档时清理可重建的文件（archive-clean-rebuild）：chat 归档（手动或自动）后，station 结束空闲进程，再在后台删掉它工作区里可重建的目录（判断同 footprint::rebuildable）；agent 在跑、已恢复、和没归档的 session 共用目录、或不在 station 的 sessions 目录下时不动。只改 station，要发包；客户端不用动。占用页的数字等下次统计才变。上线后验：归档一个工作区里有 node_modules 的 chat，一两秒后那个 node_modules 没了，station 日志有 `rebuildable files of an archived session cleaned`。
- 新对话怎么来就怎么走（android-new-chat-back）：新对话变成正式 chat 后，点返回不再往右横着出去，而是和升上来时一样往下沉；安卓侧滑返回新对话（或它变成的 chat）时跟着手指往下沉。手机 web 的 `mobile/app.tsx` 也改了点返回（页面记下自己是怎么进来的），侧滑没改。改了安卓 App.kt 和手机 web，web 跟部署走，安卓要发一版。上线后验：点新对话 → 发一条消息 → 点返回，往下沉；再来一次换成侧滑，同样往下沉。motion 测试 `OverMotionTest#newChatInAndOut`。
- chat 里漏新回复（chat-stale-messages）：app 在后台时事件流静默断掉，回前台恰好被新流顶替，漏掉的不会补；点进 chat 又只从本地打开不问 station，所以列表看得到、chat 里没有。改成：顶替一个超过 30 秒没动静的旧流时，新流连上后重读一遍；chat 只靠本地打开到末尾时，后台再问一次 `entries?after=`。只改了 core，web 跟部署走，安卓、桌面要各发一版。上线后验：app 切后台一两分钟，期间让 agent 回一条，切回来点进去应该有；Axiom 里回前台有一次 `GET /threads`，打开 chat 有一次 `entries?after=`。
- station 卡片流量按天算（net-total-by-day）：卡片上 ↑↓ 后面的「共 …」从「这次连接以来」改成「这台设备今天连这台 station 的总量」。只改了 core（mesh.rs 每分钟、以及连接断开或被换掉时把各连接的字节记进当天的账，存在设备存储 `net-day`，过了本地零点重新算）和 shapes 的注释，station、cloud、界面代码都没动。新旧混跑：旧 core 不给 `todayRxBytes`，照旧显示这次连接的量。web 跟部署走，安卓、桌面要各发一版。上线后验：开着卡片重连一次或换个中继，「共」的数字不会回到 0；重启 app 后还在。
- 安卓页面栈过渡（android-stack-transition）：页面层级按栈深度定（原来按前进/后退定，点返回回来的页再侧滑会被下面那页盖住），侧滑返回改成两页并排平移（去掉 -30% 视差和阴影），状态栏底色跟着各自的页走。只改了安卓 App.kt，要发一版。上线后验：打开 chat → 进一个设置页 → 点返回 → 侧滑返回列表，chat 全程在上面、和列表贴着平移；在不是 chat/列表的页上切页时状态栏那条不闪。motion 测试 `OverMotionTest#swipedBackAfterBack` 能复现原来的问题。
- 连接按整条路最快的中继走，可手动重新测量（relay-by-station-rtt）：只改了客户端（core、shapes、web、手机 web、安卓），station 和 cloud 不用动。core 在连上 3 秒后测一次，之后只要还走中继，每 4 分钟测一次：每个中继起一个只挂这个中继的小端点（密钥从设备密钥派生），各握一次手，量出到 station 的整条往返；有一个明显更快的（快 30ms 以上且快 20% 以上），就换过去（`switch`）。卡片上的网络行下面列出各中继的实测往返，旁边是「重新测量」（`station.measure`）。新旧混跑：station 会把这台设备的每个中继端点当成不同的设备 id（凭证用的还是同一个账号和会话，撤销照常）；探测连接没有凭证，station 日志会记一行 info `connection ended`。中继端点的凭证存在 `credential/<account>/<workspace>/others`，设备密钥那份位置不变，旧 core 照读。web 和 wasm 跟部署走，安卓、桌面要各发一版。上线后验：手机连 bft，Axiom 里看 `mesh.measure`（`stillfail.rtt.<中继 host>` 是各中继的往返，`stillfail.moved` 是换到了哪个），station 卡片的延时从秒级降到一两百毫秒以内；点「重新测量」，各中继的数字会刷新。
- 手机 web 切换 workspace（fix-mobile-workspace-switch）：触屏上从 workspace 弹层点另一个 workspace 会退回原来的那个（弹层关闭的 back 和带淡入淡出的 replace 抢先后），现在 `app.replace` 在淡入淡出里等弹层的 back 落地再跳。只改了手机 web 的 `mobile/app.tsx`，web 跟部署走。上线后验：手机浏览器里点左上 workspace 名 → 选另一个，停在新 workspace；按返回不会落到弹层的空记录上。
- station 自动更新（station-auto-update）：版本区加「自动更新」开关（默认关，owner/管理员能拨），存在 station 的 config.json `autoUpdate`；开着时每 10 分钟读一次所在渠道的最新版，有更新的就自己跑安装脚本（和点「更新」同一条路，交接不中断 agent），不自己降级，同一个版本失败了不重试。新接口 `POST /admin/api/updates/auto {on}`、core 调用 `software.auto`，`SoftwareVersion` 加可选 `auto`。改了 station、core、shapes、web、手机 web、安卓。新页面配旧 station：不给 `auto`，开关不显示；旧页面配新 station：看不到开关，station 默认不自动更新。station 要发包，web 跟部署走，安卓要发一版。上线后验：在一台测试版 station 上打开开关，发一个新的测试版 station 包，10 分钟内它自己升上去，版本行显示「已更新到 0.1.x，agent 没有中断」；station 日志有 `a newer release out: the station updates itself`。
- 用量统计（usage-stats）：station 从 agent 的 transcript 里记每一次模型调用（新表 `usage`、`usage_files`，`turns` 补 `profile`/`person`/`thread` 三列，旧库打开时自动补；旧 station 打开新库不受影响），第一次启动会把以前的 transcript 全读一遍补历史（本机 1.3G、2.9 万次调用，release 下 2.4 秒），之后每分钟读一次跑过的会话；新接口 `GET /admin/api/usage`、新事件 `usage`。core 加 `stationUsage` topic 和 `usage` 视图，PC、手机 web 和安卓（7096d93f）在设置里加「用量」页，安卓要发一版。新页面配旧 station：那台 station 写「还没更新到记用量的版本」；旧页面配新 station：不认识 `usage` 事件，忽略。station 要发包，web 跟部署走。上线后验：station 日志有一行 `usage read from every transcript`；设置 → 用量能看到最近 7 天的费用、按人/对话/账号/模型的排行，数字和 `sqlite3 ember.db "select count(*) from usage"` 对得上。
- 写请求断线不再误报失败（op-ack）：写请求的连接在回答前断了，core 用同一个幂等 key 等 station 回来再问（最多 5 分钟，station 留结果 10 分钟），期间 `doing` 的 stage 是 `rechecking`；还问不到、或是不认幂等 key 的旧 station，提示「X：不确定做没做成：…」，不再说「没能X」。只改了 core（station.rs、mesh.rs、status.rs、doing.rs）、shapes 和三端的 toast 改写；station、cloud 不用动。web 跟部署走，安卓要发一版。上线后验：把一台 station 的网断掉（或暂停进程）后在网页上固定一个 chat，30 秒后那一行还在转圈、悬停写「station 没有回应，等它回来确认做没做成」；恢复后 chat 进了「已固定」，没有弹失败。
- chat 里的「事」（chat-items）：agent 用 `chat_post` 的 `items` 声明一个 chat 里的几件事（在做/等人/完成/不要了，等谁，`ask.options`），station 新表 `items`（IF NOT EXISTS，旧库自动建），chat 行带可选的 `items`（答过的带 `answered`）；agent 指令加了两条（session.txt 快照同步）。core 按人算：行的 `waiting`（第二行「奏 · …」）、`tone`（等你蓝空心圈、只等别人灰圈）、`settled`（全结束变淡）、`asks`（卡片顺序），调用 `item.answer`（`answer` 或 `reply`）、`item.defer`（只记本机 prefs）；workspace 计数加 `wait`，通知加「等你决定」。PC/手机 web/安卓：列表第二行和圈、composer 上方一次一张卡片（准/agent 的选项/随便/待定 + 输入框；手机右滑随便、左滑待定）。新字段都可选：新客户端配旧 station 跟以前一样；旧客户端配新 station 看不到事项，agent 照常说话。web 跟部署走，station 要发包，安卓要发一版。上线后验：在测试版 app 的 chat 里让 agent 改点东西并按指令声明事项，列表出现「奏 · …」和蓝圈，chat 里出现卡片；点「准」后另一台设备上卡片也消失；agent 标完成后整行变淡。
- chat 行上的重连标记（reconnect-mark）：station 在重连时，chat 行上从转圈改成断开图标（同离线），转圈只表示用户点的操作在进行。只改了 web、手机 web、安卓 Home.kt；web 跟部署走，安卓要发一版。上线后验：断网再连时，侧栏 chat 行显示断开图标，悬停是「正在重连…」。
- 失败原地标出（op-stages）：core 的 `doing` 里失败的调用多留 6 秒（`stage: failed`、`error`），三端原来转圈的地方变成红色「!」带原因（桌面悬停、手机/安卓点一下看）。改了 core、shapes、web、手机 web、安卓；新字段可选，旧 core 没有 stage 时按进行中处理。web 跟部署走，安卓要发一版。上线后验：停掉 station 后在网页上固定一个 chat，约 30 秒后那一行变成红色「!」，悬停显示「连不上这台 station：没有回应」，6 秒后消失。
- 操作的即时反馈（op-feedback）：core 加 `doing` topic（client/core/src/doing.rs：用户发起的写调用从发出到回答都列在里面），三端按它在对应的行或按钮上转圈、禁止重复点，吞掉的错误都改成提示。改了 core、shapes、web、手机 web、安卓；station 和 cloud 不用动。web 跟部署走，安卓要发一版（安卓的 core 和界面在同一个包里，一起发）。上线后验：网页上右键一个 chat 选「固定」，那一行立刻转圈；把 station 停掉再固定，约 30 秒后提示「没能固定：…」，转圈消失；安卓上长按 chat 选固定，那一行转圈。
- 移除占用统计（remove-usage-stats）：web、安卓删除占用入口及页面；station 停止后台扫描，overview.footprint 返回 null；旧 GET /footprint 仅返回空的只读兼容响应，旧清理/扫描接口返回 410，不执行操作。需更新 web、station、安卓；旧 station + 新客户端不显示入口，新 station + 旧客户端隐藏入口。归档自动清理不变。上线后确认 station 页没有占用入口、无 footprint scanned 日志。
- 安卓列表从 chat 返回时离底部不远会往上偏（android-chatlist-scroll）：只改了安卓 Home.kt（上下两条栏的高度跟页面状态一起存），要发一版。上线后验：列表滚到靠近底部，进一个 chat 再返回，停在原来的行上；新加的 motion 测试 `ListPlaceTest` 在 studio 上 `sh apps/android/app/src/androidTest/motion.sh fail.still.android.motion.ListPlaceTest` 能跑。
- agent 不再在 chat 里逐步播报（quieter-progress）：只改了 station。station 启动 claude 时设 `CLAUDE_CODE_SILENT_TURN_REMINDER=0`（关掉 Claude Code「用户很久没听到你的消息」的提醒，profile 里自己设了的优先）；指令里讲进度的那句收紧。station 包跟 CI 走；已在跑的 claude 进程要重启（新会话或 station 更新后新起的进程）才生效。上线后验：新开 chat 让 agent 做一件十几轮工具的活，中途只在计划变了、要人看或拍板、卡住、要等很久时才发消息；`ps` 看 claude 进程的环境（`ps eww <pid>`）里有 `CLAUDE_CODE_SILENT_TURN_REMINDER=0`。
- station 更新进度看得见（station-update-progress）：安装脚本（cloud/src/install.ts）每一步写 `run/update.step`（download/handoff/drain/restart），station 把它转成一句话放进 `SoftwareVersion.progress`；从页面点的更新会写 `run/update.started`，交接或重启后起来的新进程接着盯完，结果放进 `done`，显示 10 分钟。页面不再一律写「等 agent 这一轮跑完」；「查不到最新版本」改成「检查更新失败，点「检查更新」重试」。改了 cloud（安装脚本）、station、shapes、web、手机 web、安卓，新字段都可选。顺序：api 上线后安装脚本才写步骤（只发 station 时进度只显示「正在更新…」，结果照样有）；station 要发包，从旧 station 升到这一版的那一次没有结果提示（旧进程不写 update.started），之后每次都有；安卓要发一版。上线后验：在一台正式安装的 station 上从页面点更新，依次看到「正在下载新版本…」「正在交接给新版本（agent 不中断）…」，结束后显示「已更新到 0.1.x，agent 没有中断」，10 分钟后消失；`run/` 里不留 update.started、update.step。
- 监控型 chat（watch-chats）：`job_start` 加 `watch`。开着 watch job 的 chat 就是监控 chat，列表上看起来和普通 chat 一样（不另加标记），筛选菜单多「监控中」；不会被自动归档（顺带：任何 job 还在跑的 chat 都不自动归档）；手动归档它时先弹确认（监控照常运行，有新消息会回到列表）；agent 以 waiting 结束回合后，等待到点不再叫醒它，只有 job 的 notify、job 结束、有人说话才会；监控中的 agent 在界面上算空闲（不转圈、无黄圈），状态文字写「监控中」；侧栏「一直在跑的后台任务」不收 watch job；起了监控的 chat，agent 可以立刻改一次名（不受「人说够 5 句才能改」限制），工具说明让它把监控写进标题。改了 station（jobs 表补 `watch` 列，旧库打开时自动补；会话摘要和 chat 行的 agent 带 `watch`）、core（`chats` 的 `watching`、prefs `onlyWatching`、行和对话视图的 `watch`）、shapes、web、手机 web、安卓。新字段都是可选的：新客户端配旧 station，「监控中」是空的、归档不提醒；旧客户端配新 station，watch job 还会出现在「一直在跑」里，监控中的 agent 还显示等待中。web 跟部署走，station 要发包（`stillfail update`），安卓要发一版。上线后验：在一个 chat 里让 agent「每分钟查一次 X，有变化告诉我」，它用 watch 起 job 并把标题改成带「监控」的；筛选「监控中」能看到它，左下角「一直在跑」里没有它；手动归档它会先问；过一小时 agent 没有被叫醒（执行历史里没有新的 nudge 回合）。
- 安卓页面回来时不再先空一下（android-chatlist-services-no-anim）：只改了安卓（data/Topics.kt 的 `PageTopics`、App.kt），要发一版；core、cloud、station 都不用动。页面在栈里时一直订阅它的 topic，出栈才放；出栈的页面同时清掉保存的状态。上线后验：列表顶上有「开了很久的网页服务」时，把列表滚到中间，进一个 chat 再返回，列表还在原位置，服务区不再出现、下面的行也不往下滑；关掉一个 chat 再打开它，chat 自己记的位置（`chat.place`）照旧。
- 更新日志和反馈回告（changelog，docs/changelog.md）：合并时提交信息里加 `Changelog:`（给用户看的中文）和 `Fixes: FB-n`。pipeline 新加 `changelog` job（main 每次部署后把 `node scripts/changelog.ts` 的结果放进 releases 桶的 `changelog.json`），static job 改成拉全部历史（以前 CI 构建的 web 是浅克隆，`__BUILD__` 可能算错）；deploy.py 部署 web/web-beta、promote-web 时写 `web.json`/`web-beta.json`（构建里新增 `build.json`）。cloud 加 `GET /v1/changelog`、`POST /v1/feedback/fixed`，feedback 表补 `fixed_in`、`fixed_parts`、`told_at` 三列（旧库自动补），admin 反馈列表带 `fixed_in`。core 加 `changelog` topic 和 `changelog.seen`；PC/手机 web/安卓加「更新日志」页和更新后的卡片。station（正式通道）每小时问一次修好的反馈，交给当初的会话去告诉提的人。顺序：api 先上（合并即上），再 web-beta、station 测试包、安卓测试版（CI 自动）；正式版的 `web.json` 要等下一次 `~/bin/ember-promote web`（promote-web 会写），在那之前正式版网页的条目显示「还没发布」，网页版修复的反馈也不会回告。上线后验：`curl https://app.youdid.wtf/v1/changelog` 有条目、`released.web` 是刚部署的版本；测试版 app 设置 →「更新日志」能看到；挑一条反馈，在某个合并的提交里写 `Fixes: FB-n`，等修复到了正式通道，提反馈的 thread 里 agent 会说修好了，admin 里那条显示已修复。
- 安卓 chat 停在底部离开、再进又回到上面（android-chat-scroll-restore）：只改了安卓（Chat.kt、Calls.kt），要发一版；core 不用动（`chat.place` 的 `offset` 和视图的 `atOffset` 已在 514492cf 上线）。上线后验：安卓上打开一个曾停在中间的 chat，滚到最底下，返回再进，应该还在底部；再滚到中间，从最近任务里划掉 app，重开进这个 chat，应该回到原位置。
- 手机账号页顺序、去掉 chat 顶上的连接胶囊（mobile-me-order-chat-conn）：只改了手机 web 和安卓，web 跟部署走，安卓要发一版；core 的 `connection` topic 保留给旧 app。上线后验：手机上 设置 → 账号，「登录的地方」在「这台设备上的账号」下面；断网再连时 chat 顶上不再出现胶囊。
- 桌面测试版进 CI、签名提速（desktop-sign-fast）：`apps/desktop/package.json` 加 `signIgnore`，只单独签 Mach-O（以前 .pak、图片、字体也逐个带时间戳签，签名要 4～5 分钟，现在 19 秒；`codesign --verify --deep --strict` 通过，Designated Requirement 不变，本地网络授权认的就是它，按理不受影响）。pipeline 加 desktop job：main 改到桌面带的东西（apps/desktop、client、web、station）就在 studio 上发桌面测试版。正式版桌面照常手动 `release.sh desktop`，也一样变快。上线后验：合进去后改到 web 的那次 pipeline 里 desktop job 绿，`desktop/stillfail-beta-mac.yml` 的版本是那个提交的；桌面测试版「检查更新」能更新上去，更新后打开局域网里的 station 不再弹本地网络授权。
- station 包和安卓测试版进 CI（ci-station-android）：main 改到 station 或安卓时，pipeline 自动发测试通道的 station 包（并让 studio 的 station 更新）和安卓测试版。合并的同时把 studio 的 `~/bin/ember-deploy` 改成只管 relay 和 mesh（备份 `.bak-1001-station`）。上线后验：合进去的那次 pipeline 里 station、android 两个 job 绿，android 的日志里证书 SHA-256 是 `a01a48b5…b56a`；`/releases/latest/android-beta` 指向新的 apk。
- CI 流水线（ci-pipeline）：`.github/workflows/web-beta.yml` 换成 `pipeline.yml`（分支：完整检查 + dry-run 打包；main：检查 → api → web-beta/admin/preview/site-beta，tag `deployed/beta` 记到哪）。`deploy.py` 加了 `--dry-run`。合并时已经把 tag `deployed/beta` 打在 studio 上次部署的 514492cf，所以合并后的第一次运行会把 bug 反馈（6f54db91）的 api 和 admin 一起发出去；studio 的 `~/bin/ember-deploy` 同时改成只管 relay、station 包和 mesh（旧的备份成 `.bak-1001-pipeline`）。密钥都在 GitHub Environment `production`，包括 `CLOUDFLARE_API_TOKEN`；第一次运行就能验它的权限够不够。上线后验：合进去的那次 pipeline 全绿，`deployed/beta` 指向它；推一个分支，Actions 里有 check 和 bundle。
- bug 反馈（feedback-report，docs/feedback.md）：station 内置 skill `stillfail-feedback` 和工具 `feedback_send`，agent 碰到 still.fail 本身的问题先问用户、给用户看过再发；测试版渠道的 station 没有 skill 也没有工具（启动时按更新渠道定）。cloud 加 `POST /v1/feedback`（station 签名或账号 token，两个域名都收，记 channel；Directory 新表 `feedback`，IF NOT EXISTS），admin 加 `GET /v1/admin/feedback`、`POST /v1/admin/feedback/:id/status`；core 加 admin 列表 `feedback` 和 op `admin.feedbackStatus`，console 加「反馈」页和概览的「N 个新反馈」。顺序：先 api，再 admin，再发 station 包（新 station 配旧 cloud 会 404，agent 把报告交给用户；新 admin 配旧 api 显示「还不收反馈」）。上线后验：用一台正式渠道的 station 在 chat 里让 agent 走一遍反馈（会问、给看、发出后回 FB 号），admin.still.fail「反馈」里能看到并改状态；studio 的 station（测试版）`~/.stillfail/agent/skills` 里不应有 stillfail-feedback。
- 预览小窗拖边缩放跟手（preview-resize-no-transition）：只改了 web 的 Previews.tsx，web 跟部署走，station、cloud 和安卓都不用动。拖动期间小窗直接跳到位，不再被悬停展开时启动的弹簧拖着走。上线后验：鼠标移到小窗上，马上拖左上角缩放，小窗要紧跟鼠标。
- activity 动效（android-activity-motion，接 main 上已有的 web 部分 b815859..7950bbc）：只改了客户端（web、手机 web、安卓），station 和 cloud 不用动。web 跟部署走，安卓要发一版。内容：web 的 scroll.ts 跟随到底部时会滑过去，不再走一步就一次到位；activity 离场时列表不再被拉上去；同一个 agent 连续回复时，头像直接落到下一条；排队的 agent 一直收成头像；飞的头像和真头像的转圈同步。安卓移植了 web 的这些，另外修了几处只闪一两帧的交接问题，activity 按 agent 各自停留、淡出。上线后验：让两个 agent 在同一个 chat 里交错回复，PC 和手机上都看一遍：消息从头像里吐出来，activity 不瞬移，没有一闪。
- 管理后台改成能管很多人（admin-console-scale）：新加概览页（总数、每周新用户、「需要看一眼」）；用户、Workspace、邀请码三张列表有搜索、筛选（带数量）、排序和「再显示」，点一行在右边打开详情（手机上列表和详情轮流显示），筛选和打开的是哪条都写在 URL 里。用户详情里「可以新建 workspace」开关直接给资格（准入记为新值 `granted`），还能封禁/解封；workspace 详情能删除。改了 cloud（`/v1/admin/users/:sub/may-create`、`/block`，`/v1/admin/workspaces/:id/delete`；users 表补 `blocked` 列，旧库自动补；`adminWorkspaces` 一共查 3 次，不再每个 workspace 查 3 次；新字段都可选）和 core（`adminList`/`adminItem`/`adminOverview` 三个 view，`admin.setMayCreate`/`admin.block`/`admin.deleteWorkspace`）。顺序：先部署 api，再部署 admin（新页面配旧 api 会读不到 `may_create` 等字段，开关不显示，列表照常能用）。只有 admin.still.fail 用到，app、station 和安卓都不用动。上线后验：admin.still.fail 打开就是概览，数字和用户页的总数对得上；挑一个「还没进来」的人打开「可以新建 workspace」，计数减 1，准入显示「管理员开通」，再关掉恢复原样。
- 消息里的表格换新样式（table-style）：外面一圈卡片的平滑圆角框（web 用 `--r-card` + `corner-shape`，安卓用 20dp 普通圆角），去掉竖线，只在行之间画线，表头浅底灰字。只改客户端样式（web、手机 web、安卓 `ui/Markdown.kt`），web 跟部署走，安卓要发一版，cloud 和 station 不用动。上线后验：让 agent 回一个 Markdown 表格，PC 和手机上都是圆角框加浅底表头；表格很宽时在框里横向滚动。

- 切换 workspace 时的标记和「回到上次的 chat」挪进 core（workspace-attention）：core 加了 `workspaceMarks` topic（views/marks.rs），按 workspace 算你参与的 chat 里有几个需要处理（被 block 或出错）、几个未读，还有上次打开的 chat（core 从 `client.focus` 记进 prefs 的 `openChat`，设置页不改它；旧的 `lastChat` 路径也会读）。PC 切换菜单、手机 web 和安卓的 workspace sheet 里，名字后面是红点加数字、蓝点加数字，切换按钮和手机首页名字旁边是一个点。只改了客户端（core、shapes、web、手机 web、安卓），cloud 和 station 不用动。web 和 wasm 跟部署走；桌面 app 自带的 core 是旧版时没有这个 topic，页面退回原来自己记路径的做法，不显示标记、不会卡住；安卓要发一版。上线后验：有两个 workspace，在 W2 里让一个自己参与的 chat 出新消息，在 W1 打开左下角切换菜单，W2 后面应该有蓝点和 1；进 W1 的设置再切到 W2、再切回 W1，应该回到 W1 原来那个 chat。

- chat 改成窗口、双向加载（chat-window）：只改了客户端（core、web、手机 web、安卓），station 和 cloud 不用动。core 的 `thread` topic 是最多 150 条的窗口，打开锚在第一条未读（或 `chat.place` 记的位置），第一个值就是完整的；新调用 `chat.newer`/`chat.latest`/`chat.place`；窗口不在底部时新消息只进本地，不标已读；后台把最近 200 个 chat 和本地对齐。走测试通道：部署只上 app.youdid.wtf，安卓/桌面发测试版（`release.sh --beta android desktop`）；用一阵没问题再 `~/bin/ember-promote web`，正式版安卓/桌面照常发。验证：在测试版打开一个有很多未读的 chat，直接落在未读线；上下翻页不跳、一次一页；翻到上面时来新消息只有「↓ N 条新消息」，点了直接到底；快速往下甩不会提前标已读。
- 测试通道 youdid.wtf（beta-channel）：cloud（Directory 的 users 加 `beta` 列，旧库自动补；`/v1/me` 带 `user.beta`；管理后台用户页开关；app.youdid.wtf 和带 `x-stillfail-channel: beta` 的请求，对没开通的账号回 403 `not_beta`，`/v1/auth/*` 不拦；`stillfail-beta://auth/callback`；测试版发布文件和下载链接）、web（测试版标记、`not_beta` 跳回正式版）、core（测试版 app 带通道头、按通道取更新、`software.channel`、`betaOffered`）、安卓/桌面测试版 app（`fail.still.*.beta`，叫 youdid.wtf）、station（`updateChannel`、`station-beta.json`、`stillfail update --beta|--stable`、SIGHUP 改通道）。顺序：先部署 api（新字段都可选，旧客户端不受影响），再 `web-beta` 和 `site-beta`（第一次部署建 app.youdid.wtf、youdid.wtf 的 DNS），这次 `web` 也要部署一次（正式版页面里有测试版开关和标记的代码）。然后改 studio 的 `~/bin/ember-deploy` 默认部署 `web-beta`。发测试版：`release.sh --beta android desktop`，以及测试版 station。验证：`curl -sI https://app.youdid.wtf/robots.txt` 有 `x-robots-tag: noindex`；没开通的账号打开 app.youdid.wtf 被转回 app.still.fail；管理后台给账号开测试版后能进；`/releases/latest/android-beta` 302 到测试版 apk。
- station 常驻 still.fail 的每个中继，不只「家」那个（station-multi-relay）：只改了 station（新文件 `mesh/station/src/keep.rs`），客户端、cloud 和接口都没动，新旧混跑没问题。要发一版 station 包（`release.sh station`），各台用 `stillfail update` 原地交接。修的是：海外的 station（如 bft，在东京）家中继是 Cloudflare，国内手机经北京或香港中继拨号到不了它。每个中继多一条只有 keep-alive 的连接，Cloudflare 上每台 station 约多 $0.02/月。验证：bft 的 `~/.stillfail/stillfail.log` 里每个中继各有一行 `held on this relay`；`lsof` 能看到 station 连着 39.105.157.122 和 47.76.247.168；Axiom 里安卓连 `d70ccd…` 的 `mesh.connect` 基本都是 OK。
- workspace 的收尾（workspace-followups）：station 启动时已经被移出 workspace，会结束上次留下的 job（随 station 包发）；官网 demo 不再报 `reading 'length'`（要 `python3 deploy.py site` 才上线）；`test/perf/chat.mjs` 改成测 cloud 网页。被移出（或没加入）时结束 agent 的运行时进程，不再只打断轮次（以前打断后运行时还会处理已收下的消息并发出回复），重新被接纳后续上被打断的轮次、补发它没来得及读的消息；这期间 MCP 拒绝 `chat_post`、`slack_api`、`job_start`（随 station 包发，只改 station）。新加的 `STILLFAIL_REMOVED_RETRY_SECS`（station）、`STILLFAIL_USER_DATA` / `STILLFAIL_DATA`（桌面）只给测试用，线上不设，不用改任何配置。验证：官网 demo 播完，控制台没有报错；被移出的 station 上 `ps` 里没有它起的 claude/codex 进程。

- 从单台 station 页进连接/Profile 只列这台（station-scoped-lists）：web 用 `?station=<id>`，安卓 Screen.Connects/Profiles 带 station；连接列表某台没连接时按它自己的 overview 显示「还没有连接」，不再等所有 station 回话。只改手机 web 和安卓，安卓要发一版。验证：手机设置 → Station → 某台 → 连接，标题上写「<名字> 上的」，只列这台。
- 去掉「侧栏头像 / 会话列表的头像」设置（remove-row-picture-setting）：web 外观页、手机 web 和安卓的外观里都没了；手机 web 和安卓的主题从三行列表改成三段 switch。core 的 chats 视图 `leading` 固定为 `agents`（字段和 `rowPicture` 偏好都留着，旧客户端的这项设置不再起作用，不报错）。只改客户端，web 和 wasm 一起跟部署走，安卓要发一版，cloud 和 station 不用动。上线后验：web 设置 → 外观只剩主题；有别人参与的 chat，行尾先是 agent 标志、后是人的头像；手机外观页主题是三段 switch，点深色立刻变深色。
- 手机上在官网 demo 里划也能滚页面（site-demo-scroll-chain）：只改官网（`web/src/demo/demo.css.ts`），部署 `site` 即可，App 和 cloud 不动。上线后验：手机打开 still.fail，手指放在 demo 里往上划，列表到底后页面接着往下走。
- 安卓从设置手势返回时往左退（android-settings-back-left）：设置从左边进来，点返回本来就往左退，但系统返回手势把它往右推了出去。只改了安卓 app（`App.kt`），要发一版安卓才能用上，cloud、station、web 都不动。验证：首页左上角齿轮进设置，从屏幕边缘划返回，设置跟着手指往左走，首页从右边露出来，阴影在设置的右边。
- 官网手机版 demo 的框改成大圆角（site-demo-phone-radius）：宽 ≤747px 时框 36px、光边 37px（输入框胶囊 26px + 10px 间距，同心），手机 App 顶上留 24px 状态栏的位置。只改官网，部署 `site` 即可。上线后验：手机打开 still.fail，demo 四角是大圆角，和底部输入框同心，标题栏不贴顶。
- 图片预览左右切换（image-viewer-swipe）：PC 和安卓切换时前后两张像胶片一样滑动，拖动跟手（拖动时旁边那张也露出来），松手翻页或弹回；修了安卓切图后画面一直停在第一张（`produceState` 留着上一张的数据）。只改客户端：web 跟部署走，安卓要发一版，cloud、station 不动。验证：打开一个有几张图的 chat，点开一张，PC 按 ← → 或用鼠标拖、手机左右滑，图跟着走，松手滑到下一张，标题的「2 / 3」和画面一致。
- 图片标注带编号和评论（image-marks-comments）：PC/手机 web 的图片标注里，框和箭头带编号圆点和评论气泡；放进对话时除了画好的图，每处编号一张引用卡片（quote 的 role 新加 `image`）。改了 web 和 station（`admin/files.rs` 收下 role `image`，`instructions.rs` 告诉 agent 这是图片上的第 N 处）。新页面配旧 station：role 被丢掉，卡片当普通引用显示，agent 读到「a message from 图片 … 标注 N」，位置和评论都还在；旧页面配新 station 不受影响。web 跟部署走，station 要发包（`stillfail update`）。验证：在 chat 里点开一张图 → 标注 → 画个框写句评论 → 放进对话 → 发送，消息里的卡片带橙色编号，agent 收到的引用是「From an image marked in the chat (…)」。
- 安卓图片标注带编号和评论（android-image-marks-comments）：框和箭头带编号圆点；评论用批注页同一套底部输入框和卡片（Annotate.kt 的 NoteBox/Card）；放进对话时除了画好编号的图，每处一张 role `image` 的引用卡片。只改了 app，要发一版安卓；station 认 `image` 要随上面「图片标注带编号和评论」那条发的 station 包，旧 station 下卡片当普通引用。验证：安卓上点开图片 → 标注 → 画框，底部弹出批注输入框，写完 ✓ 后工具栏上方出现卡片；放进对话后 composer 里有图和每处一张引用。
- 手机 web 图片标注用批注页的输入框和卡片（mobile-web-image-marks-notes）：手机 web 上框和箭头的评论改成和批注页同一套底部输入框 + 卡片（抽成 `web/src/mobile/Notes.tsx`，批注页也用它），PC 不变；批注卡片里长评论显示省略号。只改 web，跟部署走。上线后验：手机浏览器打开图片 → 标注 → 画框，底部输入框浮在键盘上方没被挡住（visualViewport 算的，harness 里没键盘没验到）；写完工具栏上方出现卡片。

下面各条的 cloud、web、admin 部分已经随 1bf61c4 上线（2026-10-01 11:13），剩下的是要发版的安卓和桌面部分。

- 手机设置重构（mobile-settings-workspace-redesign）：首页左上角头像换成设置齿轮，进一个设置总页（账号、Workspace、Station、连接、Profile、记忆、外观、通知；安卓还有版本）；连接、Profile、记忆改成跨 station 的一张表，单台 station 页只留机器和版本；Workspace 页成员、未登录、邀请合成一张表，点名字改名；切换面板不再带设置入口。只改了手机 web 和安卓的界面，core、cloud、station 都没动，旧地址（`settings/general`、`s/…/overview` 等）照样能开。手机 web 跟部署走；安卓要发一版才有。验证：手机上点首页左上角齿轮进设置，行尾显示在线台数、出错的连接；设置 → 连接，按 station 分组列出所有连接。
- 安卓「我」页的版本行点一下就马上检查更新（android-check-update）：只改了 app，不用部署 cloud 或 station。要发一版安卓（`release.sh android`）才能用上。发了以后，在旧版上点版本行，应该出现「正在检查…」，然后显示「更新到 …」。
- 安卓 chat 停在底部离开、没有新消息时再进，直接开在底部（android-back-at-bottom）：只改了 app，要发一版安卓才能用上。发了以后，停在一个有图片或活动行的 chat 底部，退出再进，应该还在底部。
- 离线 station 不在左下角给重试，改在 station 页给（offline-station-no-retry）：改了 core（wasm 和安卓 ffi 都要带上）、web 和安卓。新页面接旧 core 时，左下角也不会出重试。安卓要发一版才会在单台 station 页上有重试。验证：停掉一台 station，左下角只显示「xx 离线」；设置里的 Station 页，那张卡片上有「重试」。
- 中继带名字、station 卡片网络行重排（relay-names）：改了 cloud（`wrangler.jsonc` 的 `RELAY_NAMES`，`/v1/me`、credential 和推给 station 的 state 多带一个 `relay_names`）、core（wasm 和安卓 ffi 都要带上）、web、手机 web 和安卓。要部署 api 这个 Worker，名字才会下发。旧客户端会忽略这个字段；新客户端碰到旧 cloud 没有名字，就显示「中继 host」。安卓要发一版才会用上。验证：设置 → Station 的卡片上，经北京 relay 连的显示「北京中继」，右边 ↑↓ 速度后面跟着「共 …」，没有走势线。
- station 的 CPU、内存、磁盘改成和额度一样的圆角框（meter-chips），额度框的线也加粗了、灰色淡了一些：只改了 web、手机 web 和安卓的界面，不用部署 cloud 或 station，core 也没动。安卓要发一版才有。验证：设置 → Station 的卡片右上角是「CPU 34%」这样的框，边线画到用了多少；模型选择器里的额度框也是粗一点的线。
- core 按 workspace 分开（workspace-scoped-core）：只改了客户端（core、web、手机 web、桌面主进程、安卓），station 和 cloud 的接口、存储的键都没动，新 core 接旧 station 没问题，不用部署 cloud 或 station。UI↔core 的协议变了（`status`/`notices`/`notify` 带 `workspace`，新 topic `connection`，shapes 加了 `ConnectionView`），所以 web、admin、桌面、安卓要各自带上同一版 core 一起发：web 和 admin 跟部署走；桌面（主进程改成读 core 的 `notify` 并 claim）和安卓要各发一版，旧 app 里带的是旧 core，不受影响。行为变化：通知（页面里的、桌面和安卓的系统通知、安卓 FCM 推送）只报当前所在 workspace 的；一个 workspace 的 chat 里 `@[标题]` 只会展开成同 workspace 的链接；「新对话」记住的 station 按 workspace 分开（旧记录还会读）；聊天顶上的连接胶囊只看本 workspace，重连不满 1.5 秒不显示，没显示过就不出「已连上」。验证：有两个 workspace 的账号，在 W1 里让 W2 的 chat 出一条消息，W1 页面和系统通知都不该提示；切到 W2 再来一条，应当提示；W2 的 station 断开时，W1 的 chat 顶上不出胶囊，左下角也不提 W2 的 station。
- 建 workspace 的资格按账号给（account-invites）：cloud 和 web 已上线；安卓显示中文的上限提示要发一版，旧版显示错误码。
- 安卓新对话的模型选择改成和 PC 一样的一个胶囊加级联面板（android-model-cascade）：只改了 app，用 core 已有的 `pick`（of "new"），不用部署 cloud 或 station。要发一版安卓才能用上。验证：新对话底下只有 station 和「模型 · 深度」两个胶囊，一行放得下；点开是左边模型、右边深度，底栏「账号 自动 ›」点进去是账号列表；改了按「确定」，胶囊跟着变。
- 安卓 Markdown 表格里的图片（android-md-table-images）：格子里只有消息自己的图片时直接画出来；交给系统打开的链接没有应用能开时提示「打不开这个链接」，不再崩（以前点表格里退成链接的图片会崩）。只改了 app，要发一版安卓。验证：在安卓上看一条用 `| ![](a.png) | ![](b.png) |` 放附件截图的消息，图片在表格里显示。
- 进 chat 时哪些消息要动由 core 定（core-said-while-shown）：core 给 chat 显示期间实时推来的消息标 `said`、看着开始干活的 agent 标 `started`，web（含官网 demo 的假 core）和安卓只看这两个字段，不再各自比 `caught`。只改了客户端（core、web、安卓），不用部署 cloud 或 station；web 和 admin 跟部署走，安卓要发一版（旧 app 带的是旧 core 和旧界面，互不影响）。验证：安卓上打开一个 agent 正在干活、有一阵没看的 chat，补上来的消息直接就位，不从头像里一条条吐出来；chat 开着时 agent 新发的回复照样从头像里出来。
- 列表在底部时，点开的东西不再被拉到底（android-history-scroll）：web 的 `scroll.ts`（聊天、执行历史，跟部署走）在点击后一帧内内容变高、又没来新消息时，就停在原位不吸底；安卓 `Follow.kt` 改成和 web 一样，不是列表自己滚的都算读者在滚，停下时在最底部才吸底，展开步骤不吸底。只改了客户端，不用部署 cloud 或 station，安卓要发一版。验证：执行历史停在底部时点开最后一个工具，页面不动；在工具输出框里上下滑，不会被拉回底部；滚回最底部后，新步骤照旧吸底。
- 发出的消息飞进列表改成先往右、再往上的弧线（send-float-arc）：曲线 (.6, 0, .2, 1)，520ms，不回弹；web（`madeChat.ts` sendingHere，PC 和手机 web 都用）跟部署走，安卓（`ChatHost.kt` Flight）要发一版。新对话第一条消息的飞入没动。只改了客户端，不用部署 cloud 或 station。验证：在打开的 chat 里发一条，消息从输入框先横着往右、再往上落到位，轻轻停住。
- 安卓发出的消息落地时不再闪一下（send-land-flicker）：飞进来的那一行落地后不再重新做入场（以前会从透明重新升上来一遍）。只改了 app，要发一版安卓。验证：在打开的 chat 里发一条，消息落到位后直接停住，不会消失再淡入。
- 手机首页去掉底部的「全部 / 我参与的」大开关（mobile-mine-switch）：底部只留新建对话的圆按钮；顶栏的「已归档」按钮换成筛选按钮，点开菜单有全部、我参与的、已归档，筛选中图标变橙色。改了手机 web（跟部署走）和安卓（ui/Sheet.kt 的 MenuItem.icon 改成可空）。要发一版安卓。不用部署 cloud 或 station。验证：手机首页底部只有右下角的圆按钮；点顶栏的筛选图标，选「我参与的」，列表变少，图标变橙色；点「已归档」进归档页。
- station 必须在 workspace 里、去掉本机页面（station-requires-workspace）：改了 station、core（wasm 和安卓 ffi 都要带上）、web、桌面、安卓（一行）和 install.sh 的提示，cloud 的接口没动。行为变化：没加入 workspace（没有 `mesh/cloud.json`）或被移出的 station 不连 Slack、不开新轮次、不拉起 job；被移出时打断正在跑的轮次、停掉 job 和服务、断开 Slack，并在 cloud.json 里记 `removed_at`（文件保留）；127.0.0.1:4760 不再有管理页和 `/admin/api`，旧的 `/admin/...` 链接 302 到 `{cloud}/w/<ws>/...` 的同一页；Cloudflare Access 隧道那条路删了（config 里的 `admin.access` 照读照留，只是不再用）；新命令 `stillfail status`。
  - 部署前先查有没有从没加入 workspace 的 station：在每台机器上 `stillfail status`（旧版没有这个命令就看 `ls ~/.stillfail/mesh/cloud.json`），没有 cloud.json 的，这一版一上去就不再接 Slack，要先 `stillfail station enroll <cloud> <token>`（token 在 still.fail 的「添加 station」里生成）或在桌面端点「添加这台 Mac」。新 station 启动时日志里也有一行 `this station is in no workspace` 的警告。
  - 顺序：web/admin 先随部署上（新页面接旧 station 没问题：只是不再有本机页面这条路），再发 station 包（`release.sh station`，studio 的 station 由 ember-deploy 用 `stillfail update` 交接），再发桌面和安卓。`pnpm build` 现在只编 wasm core 和写 `dist/admin/posthog.json`（scripts/posthog-key.ts），不再出本机页面；station-bundle.sh 打包前自己重写 dist/admin（用 ember-deploy 已 export 的 `STILLFAIL_POSTHOG`），部署检出里旧的页面文件不会再进发布包。
  - 新旧混跑：旧 station 照旧有本机页面、不认 `removed_at`（被移出后仍会每隔一阵重连 cloud，和以前一样）；新 station 读得了旧的 cloud.json（没有新字段）。旧桌面端只看 cloud.json 在不在，所以被移出的新 station 留着文件，旧桌面端也不会自动再加入。旧 core 里存的 `local` 站点地址（草稿、上次打开的 chat、`/admin/chats/…` 的引用）新 core 读到会当成「已经没有」，不会崩。
  - 上线后验：`curl -sI http://127.0.0.1:4760/admin/chats/<key>` 返回 302，location 是 `https://app.still.fail/w/<ws>/s/<station>/chats/<key>`（cloud.json 里是旧域名的就是 ember.3720.org，那边再 302 到新域名）；`curl -s http://127.0.0.1:4760/admin/api/overview` 是 404；`stillfail status` 显示 workspace、cloud、在线。
- 发送时先跳到底（send-scrolls-to-bottom）：只改了客户端（web、手机 web、安卓），station 和 cloud 不用动。web 跟部署走，安卓要发一版。往上翻着发消息，列表先一下到底，接着跟新消息；由 composer 发送时通知（web 列表上的 `sent` 事件，安卓 `Host.sends`），不看 outbox。上线后验：PC 和手机上往上翻一大段再发消息，要直接到底、气泡落在最下面。

## 2026-10-01

### 11:45 发安卓 0.1.1256

- 从 main 371e6a4 打包（`~/ember-wt/rel-android` 新 worktree，`~/bin/ember-gui rel-1256` 跑 `release.sh android`）。带上了 1212 之后所有安卓的改动：「待部署」里写着「安卓要发一版」的那些，现在安卓这边都已经发出去了。两个域名上的 `android/latest.json` 都是 1256，apk 用 Range GET 返回 206，整包 sha256 和 latest.json 一致；`/releases/latest/android` 302 到 stillfail-1256.apk。

### 11:13 部署 1bf61c4（香港 relay、官网下载、建 workspace 资格按账号）

- 部署：76afc23 → 1bf61c4，共 40 个提交。完整检查 9 项通过，部署了 api、web 和 admin，另外单独发了官网（`python3 deploy.py site`）。station 发布包传完后，studio 的 station 原地交接到了 0.1.1249。
- 第一次跑在 api 的 `wrangler secret bulk` 失败（code 10215）：api 部署时同一秒多出一个 version_upload（29b20bf0），它比当时在线的版本（1ba7b1f0）新却没有部署，Cloudflare 不允许在最新版本没部署时改密钥。api 的代码那时已经上线了，只是脚本停在了这一步，web、admin 和发布包都没发。重跑 ember-deploy 后正常完成。再遇到同样的错就直接重跑。
- 验证：`/releases/latest/mac` 302 到 `stillfail-0.1.1212-arm64-mac.zip`，`/releases/latest/android` 302 到 `stillfail-1212.apk`；线上官网顶栏悬停「下载」能弹出卡片，从截图解出的二维码是 Android 下载地址；studio station 的 `mesh/cloud.json` 里 `relay_urls` 有三个（cloud、北京、香港）。建 workspace 的新规则没有在线上用真账号试，靠的是 cloud 测试。

### 03:45 发安卓和桌面 0.1.1212

- 从 main 91ab09f 打包 0.1.1212（含 76afc23 station 卡片的网络行、86b8edb 多 relay），在 studio 的图形会话里用 `~/bin/ember-gui rel-1212` 跑 `release.sh android` 和 `release.sh desktop`。两个域名上的 `android/latest.json` 和 `desktop/stillfail-mac.yml` 都是 1212，apk 和 zip 用 Range GET 都返回 206。
- 另外：claude-mac（ccvm）原来连不上北京 relay。mini2 的 Surge 把 ccvm 发往真实 IP 的流量挡掉了，用户在 mini2 上打通了；我之前在 Surge profile 里加的那条 DIRECT 规则，备份是 `…bak-before-ccvm-bjrelay-20261001-013613`。

### 02:32 各台 station 更新到 0.1.1209，studio 和 mini 换成正式安装

- bft、claude-mac（macvm）：`stillfail update` 原地交接到 0.1.1209，pid 不变。claude-mac 是从这台机器上的会话里起的，更新放在后台等轮次结束后再跑。
- studio：原来是 `~/bin/stillfail-restart-station.sh` 从 `~/WebstormProjects/ember` 起的开发版（0.1.0）。先发 USR1 等轮次结束，停掉它，再跑 install.sh 装成正式版（LaunchAgent，0.1.1209），数据还是 `~/.stillfail`，之前的 ember.db 备份在 `ember.db.pre-official`。`~/bin/ember-deploy` 改成不重启 station、不重建 station 页面，改为发布包传完后执行 `stillfail update`（旧脚本备份在 `~/bin/ember-deploy.bak-1001`）。
- mini（mini1，zuozijian的Mac mini）：原来是很旧的开发版桌面 app（`~/ember-dev/Electron.app`，带着 node 的 station）用 `--with-parent` 起的。退出这个 app 之后跑 install.sh，数据从 `~/.ember` 搬到 `~/.stillfail`（旧位置留了链接），ember.db 备份在 `~/ember.db.pre-official-1001`。别再打开 `~/ember-dev` 的那个 app，它会自己再起一个 station。
- 四台都已经 online at still.fail cloud。更新后应该都会选北京 relay，station 卡片上的网络行能看到。

### 02:20 部署 76afc23（station 卡片的网络行）

- 部署：86b8edb → 76afc23，这之间只有 76afc23（station 卡片显示客户端到 station 的路径、延时、速度、丢包）和一个只改 ops-log 的提交。完整检查 6 项通过；发了 web、admin，studio 的 station 只重建了页面没重启，station 发布包在后台上传。
- 只改了客户端（core + web + 手机 web + 安卓），station 和 cloud 的接口没动。安卓要等下一版 app 才有。
- 验证：app.still.fail 上的 CloudApp 和 core wasm 都是新构建（200，含网络行的文字）。还没在登录后的页面上实际看过：打开设置 → Station，远端 station 卡片上应该有「经 relay（…）/直连 · 延时 · ↓ ↑」这一行，每 2 秒刷新一次。
- 没合的分支：preview-dock-edge、search-list-layout，这次没带。

### 01:40 部署 e407171（新图标），发安卓和桌面 0.1.1204

- 部署：a99cfc8 → e407171（新图标）。发了 web 和 admin；admin.ember.3720.org 的部署检查偶发 SSL EOF，手动 curl 返回 200。
- 发版：从 main e407171 打包 0.1.1204，安卓和桌面端都发了，用 `~/bin/ember-gui rel-1204` 在 studio 的图形会话里跑。两个域名上的 `android/latest.json` 和 `desktop/stillfail-mac.yml` 都是 1204，zip 和 apk 用 Range GET 都返回 206。之前还发过一版安卓 0.1.1203（a99cfc8 之后，旧图标）。
- 00:35 那条记录里说要等安卓和桌面端新包才生效的改动（草稿、未读线、`@`、任务、prefs、原生端重连、新图标），到这里都已经发出去了。上线后照 00:35 那条里各项的验法，在安卓和桌面端上各看一遍。

### 00:38 部署 86b8edb（多 relay，北京 relay 上线）

- 部署：e407171 → 86b8edb。包括 5d3898a（登录失败的提示链到对应 profile 页，`entries` 表原地加了 `profile` 一列）和 86b8edb（多 relay）。完整检查 9 项通过；这次发了 relay、api、web、admin 四个 Worker，studio 的 station 重新构建并重启，station 发布包在后台上传。
- 验证：`https://app.still.fail/ping` 已经带 `access-control-allow-origin: *`。studio station 的 `mesh/cloud.json` 里 `relay_urls` 是 `[app.still.fail, 39.105.157.122]`。重启后约 1 分钟，北京 relay 上多了一条来自 studio 出口 IP（120.207.93.144，山西移动）的连接，说明 studio 的 station 已经把北京当成 home relay。
- 别的 station 要各自 `stillfail update` 以后才会切过去。下面是这次改动部署时要注意的，原文保留：

  - 多 relay（multi-relay）：cloud 多发一个 `relay_urls`（still.fail 自己的在前，`RELAY_URLS` 里的在后；wrangler.jsonc 里写的是北京那台 `https://39.105.157.122`），`relay_url` 照旧只给第一个；relay Worker 的 `/ping` 加了 `access-control-allow-origin: *`，浏览器靠它测延迟选 relay。所以 relay 和 api 两个 Worker 都要部署。新 station 把所有 relay 放进 map，就近选一个作为 home（国内的会选北京）；cloud 以后增删 relay，station 运行中就会跟着改。新 core 拨 station 时所有 relay 都走一遍。
    - 新旧混跑：旧 station 只认 `relay_url`，新客户端照样能连上。新 station 如果选了北京做 home，旧的原生客户端（桌面、安卓）只拨 Cloudflare，要靠 DHT 查到北京才连得上（在 studio 实测第一次连约 3 秒，之后正常）。旧网页（wasm 没有 DHT）连不上北京上的 station，要刷新成新页面才行：web 要和 cloud 一起发，部署后开着的旧标签页要刷新一下。客户端的 relay 列表是第一次 `/v1/me` 时定下的，设备上存着旧 `me` 记录的，要到下次打开 app 才用上新列表。
    - 限制：一台 station 只能从它的 home relay 收到连接。北京那台从海外基本连不上（海外出口的本机也连不上），所以人在海外、station 在国内时，会连不上这台 station。
    - 北京 relay 本身的情况：阿里云轻量北京，iroh-relay 1.1.0，证书是 Let's Encrypt 的 IP 证书（6 天有效，lego 自动续签后热加载），只能从 studio ssh 上去。具体见 ember skill。
    - 上线后验：studio 的 station 日志里 home relay 是 `39.105.157.122`；在国内打开 web 连 studio 的 station，mesh.connect 的耗时明显下降。改之前在 studio 实测：全走 Cloudflare 时建连 2.6 秒、每个来回 540ms；走北京时建连 0.2 秒、每个来回 41ms。

### 00:35 部署 a99cfc8（逻辑挪进 core）

- 部署：b24e8b2 → a99cfc8。包括 core-read-notices、core-chat-refs、core-archive、core-new-chat-choice、core-jobs、core-prefs、core-labels-net、job-log-topic、android-reconnect，还有 activity 进场。完整检查 9 项通过；station 重新构建并重启，cloud 发了 web 和 admin（新旧两个域名都返回 200），station 安装包在后台上传。
- 验证：app.still.fail 线上的构建里已经有 `chatSearch`、`longJobs`、`prefs.set`、`client.focus`；`~/.stillfail/deployed-commit` 是 a99cfc8。
- 还没发：安卓新包（`release.sh android`）和桌面端新版。发之前，旧的安卓和桌面端会缺这些：草稿、未读线、`@` 菜单、任务按钮，以及原生端重连。下面是各条改动部署时要注意的，原文保留，发安卓和桌面端时照着做：

  - activity 进场和不裁剪（android-chat-edge-clip）：只改客户端。web 随页面上线：activity 进场时位置展开、渐入、从头像放大，内容贴顶不被压；聊天列表底下的垫底不再取整（以前底部有东西按小数像素长高时，整个列表会上下抖 1px）。安卓要发新包：activity 一行和 agent 消息长按高亮、发送失败变淡都不再裁剪内容（转圈的环左边不再被切）；另外修了新来的行从来不播进场动画的 bug（activity 进场、新消息升起）。新旧混跑没问题，station 和 cloud 不用动。上线后验：发一句让 agent 开始干活，activity 从头像处渐入放大，环左边完整，上面的消息平滑让位、不抖；安卓同样看一遍。
  - 草稿挪进 core（android-new-chat-draft）的安卓部分：web 和 wasm 已随 b24e8b2 上线，安卓要发新包（`release.sh android`）才生效。上线后验：安卓在 new chat 写一句，杀掉进程重开后还在；返回手势松手后不会停一下。
  - android-reconnect（原生端重连）：改的是 client/core，web 部署会带上 wasm 那份（重试时胶囊立刻变「正在重连」，span 带 `os.type`）；安卓要 `release.sh android` 发新版，桌面端要发新版，原生端才会只用自己的 relay、在拨号没回应时重建端点。另外：重试改成 `client.wake {retry}`（不作废进行中的请求，老 core 收到的仍是 network）；web 在 Chrome 安卓上按 `navigator.connection.type` 发现换网；桌面端主进程每 3 秒看一次网卡地址，变了告诉页面（要发桌面新版）；原生端 sleep 按墙钟算，设备睡眠期间也计时。新旧混跑没问题：station 和 cloud 都不用动，老桌面端没有 `onNetwork` 就不报。上线后在 Axiom 里验：`name == "mesh.connect"` 按 `['resource.os.type']`（或 `resource.custom`）分组看失败率，失败的看 `stillfail.relay`（home relay 当时是 up 还是 down），`stillfail.rebound`/`mesh.hedge` 说明重建端点、第二路拨号有没有起作用。改之前（9-28 到 9-30）原生端连本机 station 是 43/69 失败，web 是 9/71。
  - 任务输出改成 core 的 `jobLog` topic（job-log-topic）：界面不再自己轮询 `job.log`。要发 station（`/events` 多认 `job=<id>&lines=<n>`，推 `job-log` 事件；`GET /jobs/:id/log` 多给 `follows: true`）、web/admin（带 wasm 的 core）、安卓新包、桌面端。不用排顺序：旧 station 不认 `job=`，新 core 看它的日志回答里没有 `follows`，就由 core 自己隔一阵再读（2 秒起，没变化就加倍，最多 1 分钟）；旧页面和旧安卓照旧调 `job.log`，接口没删。安卓服务页去掉了「station 太旧、job 里没有 session 就每 4 秒重读」这段：Rust station 从有任务起 job 就带 `session`。上线后验：打开一个在跑的任务看「输出」，内容一秒左右跟着长；浏览器开发者工具里看不到每隔几秒一次的 `/jobs/<id>/log` 请求，事件流的地址里带 `job=`。
  - 未读线、已读、通知判断挪进 core（core-read-notices）：core 加了 `notify` topic 和 `client.focus`、`notify.set`、`notice.claim`、`notice.pushed`（attend.rs）；聊天的 `chat` 多了 `unreadLine`/`unreadAbove`。通知开关和「问过系统」存在 core 的本机存储（键 `notify`，不改库结构），默认开。web 和 wasm 一起发布；web 旧的 `stillfail.notify=off` 首次打开时搬进 core，`stillfail.noticesShown` 删掉。安卓要发新包，旧 SharedPreferences 的 `notify`/`notifyAsked` 首次打开时搬进 core。桌面端 core 比页面旧时不认识 `client.focus`：页面自己标已读（和以前一样），但没有未读线，桌面更新后恢复。上线后验：web 打开有未读的 chat 出现未读线、滚到底后侧栏未读消失；另开一个 tab 停在别的页面，别人发消息只弹一次通知，正看着那个 chat 时不弹；设置里关掉通知刷新后还是关；安卓同样验未读线/已读/通知，关掉通知杀进程重开仍是关。
  - 引用对话和对话搜索挪进 core（core-chat-refs）：core 加了 `chatSearch` topic（`@` 菜单和 ⌘K 切换器共用）、`chat.ref`（选中的对话 → 标记，链接存在 core 的数据库里，新表名 `chat_ref`，不改库结构）、`chat.refs`（旧客户端存的链接搬进来），`chat.send` 发出时由 core 把 `@[标题]` 换成链接；草稿按页面的 key 存取（`draft.put {key}`、`draft.get`），每次改动都交给 core，core 自己合并成 300ms 后写一次库。web 和 wasm 一起发布；web localStorage `stillfail.chatRefs` 和安卓 SharedPreferences `chatRefs` 首次打开时搬进 core。桌面端 core 如果比页面旧：`@` 菜单和 ⌘K 显示「更新 still.fail 后才能…」，草稿只留在内存里，不会报错——所以桌面端最好跟着发一版。上线后验：web 在对话里 `@` 选一个对话发出去，消息里是能点的引用；⌘K 搜标题；刷新后草稿还在；安卓同样 `@` 引用一次。
  - 归档挪进 core（core-archive）：core 加了 `archive { scope }` 视图和 `archivedRows { station }` topic（不存库），`chat.archive` 归档时 core 立刻把那一行从 `chats` 里拿掉，失败再放回；恢复/删除后 core 重读归档列表。station 不用改，旧 station（不给 `archived` 的）归档页照样是空的。web 和 wasm/桌面端 core 一起打包，不用排顺序；只有开着旧 SharedWorker 的旧标签页配新页面时归档页会显示错误，刷新即好。安卓要发新包。上线后验：侧栏右键归档一个对话，行立刻消失；归档页能看到它（今天、手动归档），点恢复后行从归档页消失、回到侧栏；安卓归档页同样。
  - 新对话的选择和换模型挪进 core（core-new-chat-choice）：core 加了 `newChat`（新对话页：station 列表、选中的 station 和解析好的模型/运行时/深度/账号、提示文案）和 `pick`（模型控件：当前值、面板里的草稿、账号让位的说明、手机全屏页的前后对照）两个 topic，调用 `newChat.pick`/`newChat.create`/`newChat.migrate`/`pick.set`/`pick.save`；选择存在 core 的数据库（新表名 `choice`，不改库结构），没检查过的 profile 由 core 自己去检查；`machineSessions.list/read` 的回答多了 `meta` 一行字。web 和 wasm 一起发布，页面和 core 同版本，不用排顺序。web 旧页面存在 localStorage `stillfail.newChat` 的选择、安卓旧版存在 SharedPreferences `newChat/*` 的选择，首次打开时各搬进 core 一次。安卓要发新包。上线后验：web 新对话选一个模型/深度，刷新后还在；换 station 后再开新对话还在那台；聊天页换模型（桌面面板、手机全屏页）改完生效；安卓旧版选过的模型升级后还在。
  - 任务列表挪进 core（core-jobs）：core 加了 `chatJobs`、`longJobs`、`job` 三个 topic（jobs.rs），`jobLog`（job-log-topic 加的，station 跟着推）多了 `last`、`said`（「最后输出 · 3 分钟前」，core 按秒刷新）；页面和安卓不再自己算圆点、排序、「x 个在线」这些字，也不再自己轮询任务本身（`job` 由 core 跟事件，旧 station 每 4 秒读一次）。station 的 `GET /jobs/:id/log` 除了 `follows` 还多回一个 `state`（现在没人用，留着无害）。web 和 wasm 一起发，不用排顺序；安卓要发新包。桌面 core 比页面旧时不认识 `chatJobs`/`longJobs`/`job`：任务按钮不出现、侧栏不显示「开了很久的」、单独打开的服务页报找不到，不会崩。上线后验：一个 chat 里起一个 `job_start` 的服务和一个后台任务，标题栏按钮、弹层、任务侧栏、手机的任务表单、左下角「开了很久」（等一小时）都和以前一样；任务输出跟着长，「最后输出 · x 秒前」逐秒走。
  - 偏好挪进 core（core-prefs）：core 加了 `prefs` topic、`prefs.set` 和 `client.device`，存在 core 数据库的 `prefs` 表（逻辑表，不改库结构）。里面有：只看我的、外观、列表头像、绝对时间、快捷键、上次的 workspace/chat、每个 chat 的执行历史 tab、安卓 new connect 的 resume、邀请码。chats 视图新加了 `leading` 字段，行上新加了 `peopleText` 字段。设备名和消息的「从哪个 app 发的」改由 core 按 `client.device` 生成。web 和 wasm 一起发布，不用排顺序。web 旧的 localStorage 值（`stillfail.onlyMine/appearance/rowPicture/absoluteTime/keys/lastChat/chatTabs`）首次启动时搬进 core 一次（只补 core 里还没有的），旧 key 留着不删；`stillfail.appearance` 和 `stillfail.prefs` 以后是 core 值的同步副本，给 index.html 首帧上主题用，不能删。邀请码从 sessionStorage 挪到了 core，建好 workspace 后由 core 自己清掉。安卓要发新包：SharedPreferences 里的 workspace/theme/rowPicture/onlyMine/newConnect.resume 会在首次启动时搬进 core，搬完就删。上线后验：web 切「只看我的」和深色后刷新，首帧就是深色，列表也已经筛好；侧栏头像跟「列表头像」设置走；从 Slack 点会话链接，PC 浏览器先问桌面端，手机直接打开；安卓升级后主题、workspace、只看我的都还在。
  - 标签/状态和界面里的请求挪进 core（core-labels-net）：chats 视图多了 `glyph`、`note`、`trouble.retry`，chat 视图多了 `connection`，stations 视图多了 `face`、`line`，overview 里 profile 多了 `available`、machineLogins 多了 `offered`，`memory.get` 的 skill 多了 `body`、`about`；新调用 `link.parse`、`app.update`、`picture`、`buddies`、`dev.signIn`（client/core/src/asks.rs、looks.rs，不改库）。web 和 wasm 一起发布，不用排顺序。桌面端 core 比页面旧时这些字段没有：侧栏 station 图标画成空圈、行旁的字为空、没有重试按钮，Slack app 头像只剩厂商标志，「这台机器上已经登录了」不出现，直到桌面端更新；不会报错。安卓要发新包（检查更新、头像、链接都走 core 了）。上线后验：侧栏 station 行和手机首页右上角图标与之前一样；聊天里断开 station 时顶上的胶囊文字不变；安卓点 still.fail 链接仍在 app 里打开；安卓「我」里检查更新正常；安卓头像照常显示。

## 2026-09-30

### 22:50 部署 b24e8b2：ember.3720.org 的网页跳到 app.still.fail，官网

- 部署：d00630c → b24e8b2。包括 732dc78（ember.3720.org 的网页 302 到 app.still.fail 同路径和查询；ember-web 从纯静态改成前面有 `cloud/src/web.ts`，`run_worker_first`），以及已合未部署的草稿进 core、滚动条变细、作者名去下划线、可视化高度不设上限、打开 agent 历史这几个。部署了 api、web、admin，station 重建并重启，发布包后台上传。relay 没动。ad980b7（android-reconnect）是之后合的，没在这次里。
- 前两次被完整检查拦下：`login::tests::a_subscription_sign_in_relays_the_link_the_code_and_the_result` 等 NeedsCode 超过 10 秒。当时 studio 负载 35～47（几个编译、Android 构建，trustd 占满一核），假登录命令启动很慢；单独跑 2～4 秒就过。b24e8b2 把等待上限放宽到 30 秒。
- 线上验（curl）：ember.3720.org 的 `/`、`/w/…/chats/…?service=…`、`/assets/…` 都是 302 到 app.still.fail 同路径；`/sw.js`、`/healthz`、`/ping`、`/install.sh`、`/.well-known/assetlinks.json` 是 200，`/v1/me` 是 401（照旧由 API 回答）。旧域名的 API 和 relay 不跳，已装的 station 和旧 app 照旧能连。
- 官网 `python3 cloud/deploy.py site`：链接和安装命令改成 app.still.fail。
- 另外（不在仓库里）：manus.rip 的跳转 Worker（studio `~/ember-deploy/redirect-manus-rip`）改成跳到 still.fail。
- 草稿进 core：web 部分已上线，没在浏览器里实际验；安卓部分留在「待部署」。

### 21:13 部署 d00630c（relay 预算不再逐帧转发）

- 部署：c4f4561 → d00630c，包括 18f45dd（内嵌 HTML 记住高度）和 d00630c（relay-direct-websocket）。完整检查 4 项通过；部署了 relay、api、web、admin，studio 的 station 只重建了页面。所有 relay 连接断了一次，之后自动重连。
- 起因：CF 出了按量账单。查 9 月用量发现，RelayBudget 的 DO（namespace `d73f80fb…`）被每条 relay 连接占着，每天 active 86,300 秒，每天约 465 万条入站消息；容器的 DO（`2bb98e53…`）也收同样多的消息。现在 RelayBudget 只在建连接时放行，每分钟读一次 iroh-relay 的 metrics 来统计流量。
- 验证：`/relay` 的 WebSocket 升级请求返回 101。GraphQL 按分钟查：部署后 RelayBudget 每分钟 active 0.2–0.8 秒（每分钟一次的 alarm），入站消息 0；容器的 DO 照常每分钟收几千条。alarm 一直在续，说明从容器 9090 端口读到了打开的连接。
- 容器的 DO 仍然全天在线，并逐帧转发（@cloudflare/containers 的 containerFetch 就是这么转发的），这部分省不掉。按 9 月底的流量，relay 每月从约 $8–9 降到约 $4–5。
- 别的按量开销（R2 `zork-kache` 50 GB、sokoban/benchmark 等旧资源）没动，等人决定要不要删。

### 21:03 部署 c4f4561（桌面端差量更新）

- 部署：b862d34 → c4f4561，包括 aec4d4b（station 跟着 cloud 换域名）和 c4f4561（`/releases/` 支持 Range 和多段 multipart/byteranges，白名单加上桌面 zip 的 blockmap）。完整检查 3 项通过；部署了 api，studio 的 station 重启，station 发布包在后台上传。别的 station 要各自 `stillfail update`，才会用 cloud 推过来的 origin。
- 补传了 1169 的 blockmap，文件在 studio 的 `~/ember-deploy/blockmaps/`，是照线上 zip 算的。验证：两个域名上 `curl -r 0-9` 都返回 206 和 `content-range: bytes 0-9/159912673`；三段 Range 返回 multipart/byteranges；blockmap 用 GET 返回 200，sha256 和本地文件一致。在 studio 的 miniflare 里用 electron-updater 6.8.9 的差量下载器实测，从 1123 更新到 1169 只下 31 MB（整包 156 MB），拼出来的文件和原包逐字节相同。
- 原来「待部署」里侧栏头像、固定 chat、Slack 同意页、CPU 占用率这四条，其实在 b862d34 那次已经上线了，只是没从这里清掉；station 跟着 cloud 换域名、桌面端差量更新这两条是这次上线的。这一节现在清空。
- 桌面端差量更新的前提是 app 本地缓存了上次自己更新时下的 update.zip。手动安装的 1169 下一次更新还是整包，再往后才会差量。下次发桌面版时，`release.sh desktop` 会自动把 blockmap 一起传上去。

### 22:40 部署 b862d34，发安卓 0.1.1172

- 部署：8652e08 → b862d34。包括安卓和 web 的动效（c8afea2），以及别的会话合进来的置顶对话、CPU 真实占用、桌面检查更新、Slack 权限批准、侧栏头像。部署了 web 和 admin，station 重新构建并重启，完整检查 9 项通过。
- 前两次部署被完整检查拦下：`host::tests::the_machine_is_described_and_kept_for_a_while` 报 `cpu_busy` 是 None（54bf344 起）。macOS 的 `host_statistics` 隔一阵才更新 ticks，真睡了 505ms 以后两次读数一模一样；单独跑这个测试时碰巧能过，整套一起跑时常挂。b862d34 改成睡半秒后每 100ms 再读一次，直到读数变了，最多等 2 秒。连跑 6 次整套都通过了。
- 安卓：`release.sh android` 在 c8afea2 上打包 0.1.1172，两个域名上的 `latest.json` 都已经是 1172。

### 20:20 桌面版 0.1.1169（586404e）

- 发了桌面版 0.1.1169：菜单栏 still.fail 菜单里的「检查更新…」、设置里的「版本」页（desktop-check-updates）。两个域名上的 `desktop/stillfail-mac.yml` 都是 1169，zip 用 GET 下载是 200。上一版是 0.1.1123，改名以后桌面版就没再发过。
- 签名不用非得在 studio 本机终端跑：`~/bin/ember-gui <名字> "<命令>"` 会在图形会话里跑命令（登录钥匙串在那里是解锁的），ssh 里 codesign 报的 errSecInternalComponent 就没了。这次的命令是 `~/bin/ember-gui desktop-release "export PATH=…; cd <新 worktree> && sh scripts/release.sh desktop"`，worktree 从 github/main 开，根目录、apps/desktop、cloud 三处都要 `pnpm install`。日志在 `/tmp/ember-gui-<名字>.log`，跑完退出码写进 `.done`。从头编译到上传完大约 50 分钟，其中签名占了大半。
- 上线后验：已经装好的 1123 会在启动时或 4 小时内查到新版，侧栏顶上出现「更新」。更新以后，菜单里点「检查更新…」应该弹出「已是最新版本」。

### 18:19 部署 7fb7463 → 6614ba8 → 8652e08，官网

- 部署：`ember-deploy` 从 6b6782f 起分三次上线。7fb7463：cloud api/web/admin、studio 的 station 重启、station 发布包上传。第一次跑在完整检查的「Rust: station」挂了，报 `iroh-mainline-address-lookup` 里 `iroh_dns` 有两个版本，Cargo.lock 其实只有一份。原因是在 studio 上给别的 worktree 跑测试时用了 `CARGO_TARGET_DIR=~/WebstormProjects/ember/mesh/target`，缓存被弄乱了；重跑就过了。以后在 worktree 里测试别共用主检出的 target。6614ba8、8652e08 只有 web/admin 变化。部署时 `ember.3720.org/healthz` 报过一次 SSL EOF，本机和 studio 重查都是 200。
- 官网 `python3 cloud/deploy.py site`：`build:site` 的预渲染（SSR）连着被两处挡住：fe6f7ab 的 StationGlyph 用了 `CSS.escape`（6614ba8 修），6436a34 的侧栏 `useSyncExternalStore` 没给 getServerSnapshot（8652e08 修）。完整检查不跑 `build:site`，这类问题只有部署官网时才暴露；共用组件里别在渲染时用浏览器才有的 API，`useSyncExternalStore` 要给第三个参数。上线后 still.fail 的 title 和 og:image 已是新的。
- 这次上线的（原「待部署」各条照做了）：history-no-arrive-anim、auto-chat-title、og-image-still-fail、slack-duplicate-session-race、slack-file-upload、slack-scopes、chat-open-no-flicker。push 用的 VAPID / FCM 密钥还没有，推送没开。
- 没做的：别的 station（mini2 等）要在各自机器上 `stillfail update`；安卓没发新版，新权限表单、切 chat 不闪等客户端改动要等下次 `release.sh android`。

### 13:10 部署 6b6782f，发安卓 0.1.1141

- 部署：`ember-deploy` 从 98aad7f 到 6b6782f，共 3 个提交：安卓和 web 手机版互补、b050b46 消息性能、82135e2 ops-log。完整检查 7 项通过，部署了 web 和 admin；这次没改 cloud 的 api，也没改 mesh，所以 station 只重建了页面。
- 安卓：`release.sh android`，事先在 `cloud/` 里装好了依赖，这次正常上传。两个域名的 `latest.json` 都是 1141，apk 返回 200。

### 05:00 部署 98aad7f，发安卓 0.1.1138

- 部署：`ember-deploy` 从 d9b03e1 到 98aad7f（15 个提交：安卓补齐到 web 手机版，chat 列表动效、系统消息胶囊、整页 HTML 16:9、预览流式请求头改回旧名、Slack app 默认名、cloud 提供 `android/stillfail-<n>.apk` 等）。完整检查 10 项通过；部署了 api、web、admin，重启 studio 的 station，station 发布包在后台上传。
- 安卓：必须先部署 cloud 再传包。改名后的包叫 `android/stillfail-<n>.apk`（b9226f9），之前线上 cloud 的白名单只认 `android/ember-<n>.apk`，先传的话旧 app 更新会拿到 404。
- 在新开的 worktree 里跑 `scripts/release.sh android` 时，包打好了，上传却以 254 退出。原因是 `cloud/` 没装依赖，找不到 wrangler，而 `put` 把 wrangler 的输出吞掉了，看不到报错。处理：在 `cloud/` 里 `pnpm install`，再手动 `wrangler r2 object put` 传 apk 和 `latest.json`（格式同 release.sh）。两个域名上的 `latest.json` 都已是 1138，apk 返回 200。

## 2026-09-29

### 21:50 agent 自己跑 `ember update`，卡住 + 消息送不到

- 经过：这台 station（macvm）上一个 agent 先在 studio 上直接跑了 `~/bin/ember-deploy`（21:45，部署 ff8d4be，完整检查通过；没经过 `ember-job`，所以 `/tmp/ember-deploy.log` 里没有这次），发布包 21:49 传完，然后在自己的轮次里跑 `ember update`。安装脚本发现服务定义（launchd plist）和它新生成的不一样，没有交接，改发 SIGUSR1 排空，等正在跑的轮次结束——其中就有发起更新的这个轮次，互相等。排空期间新消息全在排队。
- 原因：`cloud/src/install.ts` 把**调用者 shell 的 PATH** 写进 plist。上次是从 Claude Code 的 shell 更新的，这次是 agent 的 shell，PATH 不同，plist 就"变了"。这台当时还是 1920ea2，发布包已经是 ff8d4be（darwin-arm64 也传了），这次更新本该交接到新版本，结果卡住后没更新成（~/.ember/app/VERSION 仍是 1920ea2）。
- 处理：21:53 结束卡住的安装脚本（在 10 分钟超时、强制重启打断轮次之前）；21:56 给 station 发 SIGUSR2，同一版本交接给自己，1 秒完成，pid 69946 不变，agent 进程和 job 都在，排队的消息开始处理，7 秒后重新连上 ember cloud。
- 顺带验证了：交接时会话 c-11c65e11b9 正在跑（`busy=true`），交接后接着写 transcript——**轮次跑着的时候交接是成立的**。
- 待修（安装脚本）：
  1. 不把调用者的 PATH 写进服务定义（或比较服务定义时不看 PATH），否则换个 shell 更新就交接不了。
  2. 从某个轮次里发起的更新，排空不该等这个轮次本身，否则必然互相等到超时、被强制重启打断。
  3. 已经是最新版时 `ember update` 直接说一声就结束，不走交接或重启。
- 修好之前：agent 别自己跑 `ember update`，从外面更新。
- 22:08 测修复时又把这台排空了一次：agent 的环境里有 `EMBER_DATA=~/.ember`，沙箱里跑安装脚本没清掉，对准了真 station。13 秒内结束脚本、SIGUSR2 交接给自己恢复，app 没动。测安装脚本一律 `env -i`。
- 三处修复在分支 `installer-update-fixes`：比较服务定义时不看 PATH（PATH 也去重，不再随每次更新变长；页面上的「更新」原来因此永远交接不了）；在 station 里面（agent 轮次、job）发起、又得重启时，重启放到后台、独立进程组里等，调用方立刻返回；已经是这个版本就直接说一声结束。

### 19:16 第一次交接更新

1920ea2 上线后更新 bft 和 macvm，两台都是第一次走交接：pid 不变（bft 22182、macvm 69946），常驻的 agent 进程和一个 job 都接了过去。两台当时都没有轮次在跑。

### 18:55 部署时 Cloudflare 连不上

studio 上 `wrangler deploy` 在第一个请求就 `fetch failed`，什么都没部署出去。当天第三次（另两次是更早的部署里：studio 从 GitHub 拉代码、上传网页到 Cloudflare）。连测 20 次都通，是偶发断线，出口经过 Surge 旁路由。`~/bin/ember-deploy` 的 cloud 部署加了遇到 `fetch failed` 自动重试三次（旧脚本备份 `~/bin/ember-deploy.bak-0929`）。

### 13:30 完整检查拦下部署（桌面端依赖）

桌面端 typecheck 报找不到 `electron-updater`：`scripts/check.sh` 只在没有 node_modules 时才装依赖，studio 的旧 node_modules 少了后来加的包。改成每次都 `pnpm install`（01ec190）后重新部署通过。

## 2026-09-28

### 检查挪到本地和部署前（8727607、a3a37c4）

先试过 GitHub Actions（studio 自托管 runner，后改 GitHub 的 Linux 机器），因为分钟数（一次完整检查二十多分钟，发布包还要 Mac 机器按 10 倍计）和合并变慢，改成：git hook 只跑快速检查，完整检查放进 `ember-deploy`，不用 GitHub Actions。`Cargo.lock` 从这时起进仓库。

### agent 合并时撤掉了别人的提交

一个 agent 合并时用 `git reset --soft origin/main` 再提交来压成一个提交；origin/main 在它干活期间往前走了，结果把 99278aa（样式改用 TypeScript）整个撤掉、把 945 行旧 CSS 带回 app.css。另一个会话发现后补了 f5a847c、e2bbdb2、597036f 修回来。项目记忆里已禁止这种合并方式（ember skill 的「开发流程」）。

### GitHub 和 studio 两个 main 分叉

agent 有的推 GitHub、有的推 studio，两个 main 各多了提交，部署（从 studio）漏了 GitHub 上的自动更新。合并成 9fefdb0；之后只认 GitHub 的 main，studio 的检出拒收推送、只用来构建。
