# 在 Xcode 中打开

双击仓库内的 `apps/ios/StillFail.xcodeproj`（本机路径：`/Users/catsjuice/workspace/afk/still.fail/apps/ios/StillFail.xcodeproj`）。在 Xcode 顶部选择共享 Scheme **StillFail**，选择 iOS 26 或更新版本的 iPhone / iPad 模拟器，然后点击 **Run**（⌘R）。需要已安装的 Xcode，以及 iOS 26+ 模拟器运行时；当前工程使用 arm64，仅面向 iOS 和 iPadOS。

会话列表使用 UIKit 复用单元格，iPad 宽屏采用列表与详情双栏。消息与执行历史共用原生 MarkdownView 4.6.5 / Litext 3.3.2 渲染器，依赖版本固定在 `project.yml`，首次打开工程时由 Swift Package Manager 解析。新建会话页与聊天页复用原生输入框，首次发送遵循核心的 `newChat.create` → `chat.send` 待发队列协议。界面支持系统语言、简体中文、繁体中文、英语、日语、韩语和西班牙语，可在设置中立即切换。

App 的构建前脚本会自动执行 `bootstrap-rust.sh` 和 `build-core.sh`，用 Node.js 24+ 和 pnpm 构建 `client/core-ts` 的 TypeScript 核心，并编译 `client/shell` 的原生 IO 静态库。逻辑由系统 JavaScriptCore 在后台串行队列执行，网络、SQLite 与 iroh 复用 main 的原生 shell，`storage.*` 仍全部通过本应用的 Keychain 存储。旧 Rust 客户端核心及 UniFFI 不再参与构建。Rust 工具链、依赖和构建缓存仅存放在仓库的 `.airbuild/` 下，不会修改全局 Rust 或 shell 配置；缺少缓存时，首次准备会下载所需依赖。后续构建复用缓存。生成的核心文件和资源位于 `.airbuild/`，不加入 Git，请勿删除它来“清理”工程。

工程定义仍为 `apps/ios/project.yml`。需要重新生成工程时，在仓库根目录运行（使用已有的 XcodeGen）：

```bash
/opt/homebrew/bin/xcodegen --spec apps/ios/project.yml --project apps/ios
```

重新生成会更新工程文件；工程设置应改在 `project.yml` 中，并先保留需要的手工修改。旧的 `.airbuild/xcode/StillFail.xcodeproj` 保留，但日常打开请使用上面的可见工程。

自动构建检查、TestFlight 发布以及所需 runner / 签名配置见 [iOS CI 与 TestFlight](CI.md)。普通 push 会运行无签名测试和真机构建；TestFlight 由 main 上的手动 workflow 发起。

## 小组件独立更新

`SnapshotProvider.getTimeline` 在 **Widget 扩展自己的进程** 中调用 `WidgetSync`：
从 App Group 的 Keychain 读取登录会话和已确认设备密钥，自行刷新过期令牌，
通过临时 iroh endpoint 和现有加密节点协议读取 `/chats` 与 `/chats?archived=1`，
然后生成统计、热力图、待决策和最近任务。主应用被结束后仍可执行这条链路，
不依赖 BGAppRefreshTask 或前台页面。

扩展使用单独打包的 `stillfail-widget.js`，只包含一次性读取器，不启动完整应用核心、
数据库、历史记录或事件订阅。临时 endpoint 由应用已确认的设备密钥签署，
因此不绕过工作区锁。账号和工作区切换带有 generation，旧的在途结果不能覆盖新账号的快照；
Widget 只能续期当前仍存在的账号，不能重新添加已退出的账号。

App Group 文件只保存工作区路由和展示快照，令牌/私钥仅保存在 Keychain。
升级后首次运行应用会迁移原来的私有凭据并记住所选工作区。此后无需保持主应用存活。
读取失败、设备尚未首次解锁或节点不可达时保留上次完整快照。

Timeline 请求最早 30 分钟后再次刷新，实际执行时机由 WidgetKit 决定，不保证固定间隔或实时更新。
应用的“后台 App 刷新”不再是取数入口。

`WidgetExtensionE2E` 是独立的模拟器 UI 测试 scheme：结束主应用，通过 SpringBoard 添加
统计小组件，修改真实本地 QUIC 测试节点的任务数，再点击小组件自己的刷新按钮请求新 timeline，检查屏幕统计更新且
主应用仍是 `.notRunning`。`WIDGET_E2E` 编译条件只将地址发现/账号 API 指向隔离合成服务；
读取器、原生 QUIC、WidgetKit Provider 和共享 Keychain 均使用正式路径，Release 不包含测试入口。

在英文模拟器环境重现（Node 24+、Xcode 27、已安装模拟器运行时；脚本自行创建并清理测试设备）：

```sh
STILLFAIL_MESH_NATIVE="$(node scripts/native.ts file mesh)" python3 apps/ios/scripts/widget-e2e.py
```

`.airbuild/widget-e2e-results/` 保存 XCTest 截图、日志及扩展进程读取到的新任务数。
测试构建使用 `.e2e` bundle ID，不安装或操作正式 App。
