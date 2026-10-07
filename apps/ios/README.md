# 在 Xcode 中打开

双击仓库内的 `apps/ios/StillFail.xcodeproj`（本机路径：`/Users/catsjuice/workspace/afk/still.fail/apps/ios/StillFail.xcodeproj`）。在 Xcode 顶部选择共享 Scheme **StillFail**，选择 iOS 26 或更新版本的 iPhone / iPad 模拟器，然后点击 **Run**（⌘R）。需要已安装的 Xcode，以及 iOS 26+ 模拟器运行时；当前工程使用 arm64，仅面向 iOS 和 iPadOS。

会话列表使用 UIKit 复用单元格，iPad 宽屏采用列表与详情双栏。消息与执行历史共用原生 MarkdownView 4.6.5 / Litext 3.3.2 渲染器，依赖版本固定在 `project.yml`，首次打开工程时由 Swift Package Manager 解析。新建会话页与聊天页复用原生输入框，首次发送遵循核心的 `newChat.create` → `chat.send` 待发队列协议。界面支持系统语言、简体中文、繁体中文、英语、日语、韩语和西班牙语，可在设置中立即切换。

App 的构建前脚本会自动执行 `bootstrap-rust.sh` 和 `build-core.sh`，用 Node.js 24+ 和 pnpm 构建 `client/core-ts` 的 TypeScript 核心，并编译 `client/shell` 的原生 IO 静态库。逻辑由系统 JavaScriptCore 在后台串行队列执行，网络、SQLite 与 iroh 复用 main 的原生 shell，`storage.*` 仍全部通过本应用的 Keychain 存储。旧 Rust 客户端核心及 UniFFI 不再参与构建。Rust 工具链、依赖和构建缓存仅存放在仓库的 `.airbuild/` 下，不会修改全局 Rust 或 shell 配置；缺少缓存时，首次准备会下载所需依赖。后续构建复用缓存。生成的核心文件和资源位于 `.airbuild/`，不加入 Git，请勿删除它来“清理”工程。

工程定义仍为 `apps/ios/project.yml`。需要重新生成工程时，在仓库根目录运行（使用已有的 XcodeGen）：

```bash
/opt/homebrew/bin/xcodegen --spec apps/ios/project.yml --project apps/ios
```

重新生成会更新工程文件；工程设置应改在 `project.yml` 中，并先保留需要的手工修改。旧的 `.airbuild/xcode/StillFail.xcodeproj` 保留，但日常打开请使用上面的可见工程。
