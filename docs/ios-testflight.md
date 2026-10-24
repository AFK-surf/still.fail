# iOS / TestFlight 工程交接

## 当前实际能力

`.github/workflows/mbui.yml` 的 `ios` job 使用现有 MoonBit / 原生构建脚本，为 `iphoneos` 编译 `APP=stillfail`，Bundle ID 为 `fail.still.mbui`，再将 `MBUI.app` 放入 `Payload/` 打包。它不是 Xcode archive / distribution export 流程。

- 沿用现有触发条件：仅 `AFK-surf/still.fail` 仓库运行；main 的 push 按 `what` 判断是否需要构建，手动运行也可构建 iOS；普通分支 push 不构建 iOS。
- Runner 为 `xcode-27`，指定 Xcode 27.1 并检查 iOS SDK；其可用性仍需真实 CI 运行确认。
- 成功打包后，以 Actions artifact `mbui-ios-UNSIGNED-<commit SHA>` 保存 `stillfail-mbui-unsigned.ipa`，可在该次运行的 Artifacts 下载，保存期限遵循 GitHub 的仓库设置。未生成文件时上传步骤报错。
- **这是未签名构建，不能直接安装到设备，也不能上传为可用的 TestFlight build。** artifact 用于检查打包内容及后续托管签名适配，不代表发布完成。

## 版本号

`apps/mbui/scripts/ios.sh` 默认以 `git rev-list --count HEAD` 设置 `MBUI_IOS_BUILD`（显式设置该变量可覆盖）。底层脚本将其写为 app 和分享扩展的 `CFBundleVersion`，同时将营销版本写为 `0.1.<构建号>`。iOS job 的 checkout 使用 `fetch-depth: 0`，避免浅克隆将构建号变成 `1`；未改动其他平台或版本策略。

完整历史计数不是独立的发布序号服务：重复构建同一 commit 会得到同一版本，分支或历史重写也不保证递增。正式上传前应检查 App Store Connect 已有版本和构建号，不能默认重跑即可再次上传。

## 仍待完成：托管签名与上传

1. 完成 AirBuild 的 Apple 账户连接与团队授权，确认 `fail.still.mbui` 及分享扩展的 Bundle ID、App Store Connect app 和所需能力。
2. 适配现有自定义 app / 扩展打包到 AirBuild 支持的托管签名、归档与导出流程，验证嵌入 framework、扩展、entitlements 和 provisioning profile；不能假设给当前 ZIP 加一个上传步骤就能发布。
3. 获得有效的 distribution 签名 IPA 后，使用已连接账户上传 App Store Connect，确认处理成功、版本信息和测试组分发结果，才可称为 TestFlight 发布完成。

本次仅提供 CI 基础修复和未签名产物留存，不实现签名或 Apple 上传，也不宣称 TestFlight CI 已完成。无需为本次改动新增 GitHub secrets；不要提交或手动传递 Apple 私钥、证书、描述文件或账户凭据。后续认证与签名材料由平台托管连接提供。
