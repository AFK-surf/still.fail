# iOS / TestFlight 工程交接

## 当前验收状态（2026-10-24）

尚未完成真实 GitHub Actions → 内部 TestFlight 闭环。不要把本机签名成功、离线脚本测试或工作流文件存在当作发布通过。

实查远端运行 [40069912469](https://github.com/AFK-surf/still.fail/actions/runs/40069912469)，源码 `3e151c371bc597041674ba282a4d96622241e160`，iOS 编译成功；由此确认该次 `xcode-27` / Xcode 27.1 runner 可用。原 `.github/workflows/mbui.yml` 只有编译、Payload 打包，未实现分发签名、Apple 上传、处理等待、内部组分配。不要覆盖该文件中正在独立演进的 Android/macOS/Windows 与原生下载逻辑。

用户明确选择 GitHub 云端发布，使用所有者独立准备的 Apple CI 身份；不安装自托管执行机，不复制 AirBuild 的运行时认证或托管签名材料，不借用个人登录。

## 发布边界

只操作新版 ASC app `6826455869` / `fail.still.mbui`，Share `fail.still.mbui.share`，App Group `group.fail.still.mbui`，Apple team `D9AAN3VJK8`。原版 app `6818750243` / `fail.still.iphone` 的签名、测试组和分发保持不变。

首轮只向所有者授权且不在法国的测试人员分发，不启用公开链接，不永久排除法国。Apple 返回的内部成员资料没有国家字段；不能用姓名、邮箱或原版安装状态推断所在地。

原版 `Internal Testers` 组 `b948be95-b47f-4cf6-9c67-5af32a52ee34` 实查 12 人（原版安装 3、原版邀请待接受 9）。可经所有者授权复用人员，不可直接跨 App 使用同一组。新版已建空组 `5f3be0e4-d831-43e7-8abe-994a95575a70`，无公开链接、无自动全部构建；尚未授权并添加成员。不要复制原版公开外部组，不要把空组当作实际可安装证明。

Ampo 已按所有者确认的实现和范围清除本次免文档加密门槛：最终包保留 `ITSAppUsesNonExemptEncryption=false`，不填不存在的出口代码。最终云端包仍须复验，而不是假定历史 IPA 的申报自动适用于新包。审核密码账号的真实聊天/站点权限与全流程 VoiceOver 仍未验收，原生 Apple 登录后排；本工作流不等于这些产品条件已通过。

## 新增独立云端工作流

`.github/workflows/mbui-testflight.yml` 是专用发布入口，仅上游仓库 main 的相关路径 push / main 手动触发。使用 `ios-testflight` 环境与串行发布，环境本身的 main 限制和审批必须由仓库管理员配置。仅在 YAML 中写环境名不构成保护措施。

安全配置准确名称、凭据来源和内部组变量见 [所有者配置指南](ios-testflight-owner-setup.md)。需要七项专用 Apple environment secrets 和显式 `MBUI_TESTFLIGHT_GROUP_ID` environment variable。现有 GitHub 连接能读源代码和 Actions 结果，但 runner 管理、发布密钥管理返回 403；仓库重新授权已重试一次，不能反复发送同一授权卡，也不能声称这些写权限已经具备。

脚本 `apps/mbui/scripts/ios-testflight.rb` 使用 Ruby 标准库，工作分 prepare / package / release：

- prepare 校验专用私有 P-256 API key、App/组归属、内部/无公开/非自动全部构建策略；校验证书私钥匹配及有效期、App Store 类型 profile、团队、两个精确 Bundle ID、App Group、profile 所含证书。XML plist reader 保留 DATE/DATA，不通过 JSON 转换真实 mobileprovision。只把专用材料装进临时云端 keychain/profile 位置。
- 首次运行读取 Apple 已有整数构建号、完整 git 历史和 Actions run number 分配新构建号，营销版本保持上游 `0.1.<build>`，上限 9999；不修改原版 App。源码 SHA、run、版本的不可变 reservation 在编译前保留。
- 现有脚本编译主 app、Share、Hermes 和 core.hbc。现有 Xcode 打包桥通过显式每 Bundle ID 的 profile 映射签名；拒绝覆盖 AirBuild 托管签名环境。设备归档和手动 App Store export 只在云端执行。
- package 私密导出后校验主 app/Share 版本、Bundle ID、team、entitlements、iOS 17 最低版本、Hermes 签名及 core.hbc；只将校验通过的 IPA 移入可保留目录。SHA256 identity receipt 必须上传成功后才允许执行上传步骤。
- release 使用当前 Xcode altool `--upload-package` 和专用 `API_PRIVATE_KEYS_DIR`，等待 Apple `VALID` 并确认只分配给明确批准的内部组。GET 瞬时错误有界重试；POST 不盲目重放。处理失败、身份不符、组分配失败都使任务失败，不回退到旧包。
- 重跑不重新编译或盲目重新上传；必须使用原 run 的 reservation 和 IPA identity，且 Apple 已可见唯一匹配构建。上传可能发生但 Apple 尚不可见时关闭自动恢复，需要先核对原 run。失败历史按实际持久化上传边界检查，缺凭据或编译失败不得永久污染后续发布；历史不完整时保守停止。
- `ios-testflight-cleanup.rb` 在成功/失败后清理临时 keychain、仅本次安装的 profiles、私钥及中间文件。Actions artifacts 只保留经过校验的 IPA 与无凭据清单，不上传原始证书、profile、keychain、私钥或 Xcode 分发日志。

真正跑过云端后才能确认当前 runner 的真实 profile、签名、Apple API 与上传行为。离线 fixture 不替代这些检查。

## 已验证与仍需验证

受管理的离线脚本测试 run `cb0cda04-b7bf-4970-8095-693f959ae0e4`：12 tests / 64 assertions 通过，Ruby syntax 与 workflow YAML 通过。此前 `cc860eb6-c88c-4f25-aed2-6a0de5cb2025` 为 12/59；本轮补充完整零 job 的排队取消恢复及字段、类型、数量不符拒绝。测试覆盖合成证书/API key、XML DATE/DATA、错误 profile、版本分配、失败阶段、GET 有界重试与 POST 不重放、处理与组分配 fixture，以及完整原始历史页、跨尝试的上传边界、过期或删除凭据清单后的保守停止。此前 10/46 为中间记录，最终补丁另经独立源码复核，无剩余具体阻断；不是云端上传证据。

本轮整合最终检查已通过：`mbui_checks` run `a9025102-a004-4f68-9af0-c4f6e7642f78`，1979 warnings / 0 errors，detlint 通过；样式基线仅将 app.mbt 的 style-literal 从 17 收紧为 16，未放宽规则。`reviewer_ui` run `3c0664b3-9680-441f-8d95-7735eaaca038`，695/695；账号安全 run `b0fdedcc-1259-46d9-9899-1e5a04dd0c12`，55/55；类型 run `2495d775-d4d8-4eb3-acbc-b60cb18c7667` 通过。桌面手机路由与同值命名样式另经独立源码复核，没有具体剩余阻断；不是渲染或实际 VoiceOver 验收。

最终本机签名 run `12092067-62c7-446e-9816-0c1c59ef78a6`：0.1.4866（4866），IPA SHA256 `0f0869a653cf68b98af85350f803a9882e41270f19067852814d68e1853c0db6`。导出后严格深层签名、主 app/Share 的 ID/team/App Group、最低 iOS 17、core.hbc 与免文档加密声明复验通过。此包未安装、未上传。当前预览仍是此前已验证最小键盘修复的版本，不把它的截图作为本次整合树证据。本地结果均不是本次云端发布的替代证据。

完整验收必须记录：最终源码 SHA、真实 Actions run/触发方式、签名 IPA 版本与 SHA256、Apple build ID/处理结果、批准的内部成员与组、实际 TestFlight 安装证据。当前无正向端到端发布记录。

## 本机打包与工具边界

项目 `.airbuild/airbuild.yaml` 使用 v3，签名声明精确覆盖主 app 与 Share；本机只用 `runbuild` / `runtest` / AirBuild-managed simulator。不得直接执行原生 build 脚本绕过管理器、操控其他预览模拟器或改动全局钥匙串。

打包桥 `apps/mbui/scripts/ios-package/` 仅生成包装工程，保留已编译二进制和 app-specific plist，Hermes 由 Embed Frameworks / CodeSignOnCopy 处理。输入签名、profile 与过期 DT 元数据不复制。资源安装清单只清理自己拥有且已消失的资源，不对目标 app 全目录删除。普通本机签名不启用 CI profile override。

`.airbuild/`、下载工具、缓存、签名材料、生成工程不入 Git。保持窄暂存，不清理已有未跟踪文件。远端 main 正在独立演进，发布前在隔离 worktree 合并验证，不 force-push，不以旧本地树覆盖远端。

发布配置本身没有改变业务动作，但本次整合引入了上游记忆/skill 业务契约变化，因此已重跑评估并更新 `intent-opportunities.md`。现有 App Intents 零项，可实施首批零项；新增“打开指定站点记忆/skill 文档”候选仍待真实授权、桥接和 API 证据。

## 参考

- Apple 添加组到构建及权限要求：https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds/
- Xcode altool 手册镜像：https://keith.github.io/xcode-man-pages/altool.7.html
- 当前本机 Xcode 27.1 实际 `altool --help`（Version 27.0.5）另确认 `--upload-package`、`--api-key`、`--api-issuer`、`API_PRIVATE_KEYS_DIR`。未使用真实凭据或执行上传。
