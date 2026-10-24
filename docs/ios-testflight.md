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

## 已验证：AirBuild 本机托管签名

2026-10-24，用户确认本轮继续开发 **mbui 新客户端**；原版 `fail.still.iphone` / ASC app `6818750243` 的内测保持不变。本轮使用新 app `6826455869`、主应用 `fail.still.mbui`、分享扩展 `fail.still.mbui.share`，二者关联独立 App Group `group.fail.still.mbui`。不要把新包上传至原版 app。

已完成真实验证（不是 fixture 代替）：

- `runbuild 8de9d3df-0e4e-4f28-8718-06b6ff3bc771`：Xcode simulator archive 成功，安装并启动于 AirBuild iPhone 15 Pro / iOS 17.0；欢迎页正常，点击登录能进入系统认证及线上 Google / 邮箱验证码页面。登录后主流程尚待测试账号。
- `runbuild 8de9d3df-0e4e-4f28-8718-06b6ff3bc771 --sign`：Xcode device archive、托管签名和 distribution IPA 导出成功，实际版本 `0.1.4753 (4753)`。未上传 Apple，不代表 TestFlight 已可用。
- 最新签名构建 run `a5cf51b3-3264-4485-9b95-514a1c59b9a2`；普通构建 run `d87b524a-b1e8-4e33-8278-0fa45d06094d`。最新签名复验已消除底层依赖最低系统版本高于 iOS 17.0 的警告，未上传；本机产物位置由各次 runbuild 输出给出，后续脚本不可硬编码一次构建的路径。

可维护的打包桥保存在 `apps/mbui/scripts/ios-package/`，不依赖 Ruby gems，需要 Ruby、rsync 和 Python 3.9+。主程序与分享扩展各为一个 Xcode native target，原生二进制保持上游编译结果；Hermes 由 Embed Frameworks / CodeSignOnCopy 处理，Share 由依赖与 Embed App Extensions 处理，签名设置不覆盖 AirBuild 注入值。根目录 `core.hbc` 必须随 app 保留；输入签名、profile 和过期 DT 元数据不复制到新 app/extension。

安装步骤在 `DERIVED_FILE_DIR` 保存自己的资源清单：重复构建时只删除清单中已不存在于源包的文件，不用全目录 `rsync --delete`，不删除 Xcode 生成的元数据、嵌入扩展、框架和签名。清单不进入应用包。无签名依赖的回归测试覆盖主应用和分享扩展：

```bash
python3 apps/mbui/scripts/ios-package/test-install.py
```

从仓库根目录生成打包工程（先按现有脚本完成相应 SDK 编译）：

```bash
# apps/mbui/scripts/ios.sh build 仅构建；不要用其 run/device/shot 操作预览设备
ruby apps/mbui/scripts/ios-package/generate.rb \
  apps/mbui/out/ios-device/MBUI.app .airbuild/packaging/generated

airbuild-xcode archive \
  -project .airbuild/packaging/generated/MBUIPackaging.xcodeproj \
  -scheme MBUI \
  -archivePath .airbuild/artifacts/StillFail.xcarchive
```

iOS 构建入口显式导出 `IPHONEOS_DEPLOYMENT_TARGET=17.0`，与上游 clang 链接目标一致，防止 Rust 的 cc-rs 依赖采用已安装 SDK 的较新默认值。复制的 Rust 静态库旁保存部署版本戳；iOS 部署目标变化或缺戳时重新调用 Cargo，避免旧静态库绕过环境检查。Blake3 关闭了 cc-rs 环境变更跟踪，因此在该条件下只清理项目缓存中的 Blake3 目标产物后重编，不清空整个 Cargo / Xcode 缓存。构建和复制任何一步失败均不得发布新版本戳。此修复不提高应用最低系统版本；设备与模拟器中 SQLite、Blake3、Curve25519 对象的 Mach-O 最低版本均已逐个核实为 17.0。

该段应由 AirBuild 的 v3 `build.script` 调用；普通构建输入 `out/ios/MBUI.app`，签名构建输入 `out/ios-device/MBUI.app`，用 `AIRBUILD_SIGN` 区分，保持 `MBUI_IOS_ID=fail.still.mbui`，具体签名 bundles 声明主应用和分享扩展。不要在 GitHub runner 上假定存在 AirBuild 的托管签名环境。项目本机工具链和 `.airbuild/airbuild.yaml` 留在被忽略的 `.airbuild/`，不提交下载工具、缓存、签名材料或生成工程。

## 仍待完成：上传、分发和真正持续发布

1. 登录后验证；按产品合并交接实现审核密码入口与原生 Apple 登录，不做账号合并/迁移，不把本地 mock 当线上审核账号。
2. 复核原项目 `ITSAppUsesNonExemptEncryption=false` 与实际端到端加密实现的一致性，再确定本次上传的申报；不为跳过提示而改成 false。
3. 使用上面已导出的签名包上传新 app，等待 Apple 处理并验证内部测试组及成员。若 Xcode export 留下相同版本号的空 `AWAITING_UPLOAD` reservation，按平台文档确认无文件后删除该空记录，复用现有 IPA，不盲目改号重签。
4. 当前 GitHub workflow 仍只产生未签名 artifact；没有编造 GitHub→本机 AirBuild 托管签名的自动触发接口。完整端到端持续发布尚未实现，必须以一次真实触发、签名、上传、处理和分发记录验收，而不是仅以 YAML 或 IPA 导出成功验收。

无需为现有改动新增 GitHub secrets；不要提交或手动传递 Apple 私钥、证书、描述文件或账户凭据。认证与签名材料由平台托管连接提供。
