# iOS CI 与 TestFlight

流程参考 Cue 的 Apple CI；这里构建 still.fail 的 App 与 Widget，逻辑使用共享 TypeScript 核心及 Rust IO shell。

## 构建检查

`.github/workflows/ios.yml` 在仓库分支 push 且 iOS、共享核心、原生 shell、工具链或对应 CI 文件变化时运行，也支持手动运行。

- Linux：验证 workflow、发布重跑逻辑、配置打包与凭据隔离、签名 profile 校验。
- Apple Silicon Mac：运行全部 `StillFailTests`，再构建 App 和 Widget 的无签名 Release 真机版本。
- 保存构建日志和 XCTest `.xcresult`，保留 14 天。

与本仓库现有自托管流程一致，只接收本仓库的 push 和手动运行；不将外部 PR 代码送到自托管 runner。

Mac runner 必须安装 Xcode 27 和至少一个 iOS 26+ 模拟器运行时。Node 版本取 `.node-version`，pnpm 版本取根 `package.json`；CI 安装 XcodeGen 2.44.1，项目自身准备 Rust 1.95.0。下载和编译缓存只包含 pnpm、Rust 和 Swift Package 依赖，签名材料不进入缓存。

仓库变量 `IOS_RUNNER_LABELS` 是 JSON 数组。默认使用现有 `mini1`：

```json
["self-hosted", "mini1"]
```

要复用 Cue 当前成功发布所用的 Tartelet Mac，先在组织 runner group 中为 **AFK-surf/still.fail** 开通访问，再将该变量设为：

```json
["self-hosted", "tartelet"]
```

`IOS_XCODE_PATH` 可指定 Xcode 的 `Contents/Developer` 路径。未填写时按顺序查找 `/Applications/Xcode_27.0.0.app`、`/Applications/Xcode-27.0.0.app`、`/Applications/Xcode.app`，并核实其版本为 27。

在本机运行相同检查：

```sh
bash apps/ios/scripts/build-ci.sh all
```

脚本默认创建专用 iPhone 模拟器，结束后删除。可设置 `IOS_SIMULATOR_UDID` 复用已有模拟器；复用的设备不会被删除。`test` 只运行测试，`build` 只做无签名真机构建。日志默认写入 `.airbuild/ci/results.*`。

## 发布前需要准备

在 GitHub 创建 **ios-testflight** Environment，并在其中保存一个 Secret：**IOS_TESTFLIGHT_CONFIG**。它是 Base64 编码的 gzip JSON，由下面的脚本生成。无需把各份签名文件分别存成 GitHub Secret。

需要以下信息和文件：

| 项目 | 要求 |
| --- | --- |
| App Store Connect App ID | `fail.still.iphone` 对应应用的数字 ID；没有应用记录时需要先创建 |
| API Key ID、Issuer ID、`api.p8` | 可上传构建并分发内部 TestFlight 的团队 API Key；建议 App Manager 角色 |
| Apple Team ID | 工程当前为 `D9AAN3VJK8`，可通过打包参数覆盖 |
| `distribution.p12` | 同一团队的 Apple Distribution 证书及私钥，附导出密码 |
| `app.mobileprovision` | `fail.still.iphone` 的 App Store Connect distribution profile；包含 Sign in with Apple 和 App Group `group.fail.still.iphone` |
| `widget.mobileprovision` | `fail.still.iphone.widgets` 的 App Store Connect distribution profile；包含同一 App Group |
| 内部测试组 | App Store Connect 中已存在的内部组；默认名称 `Internal Testers`，也接受组 ID |
| Mac runner | Apple Silicon、Xcode 27、iOS 26+ 模拟器，且该仓库有 runner group 使用权限 |

Apple 的[上传构建权限说明](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)和[向构建添加测试者的权限说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-testers-to-builds/)分别说明所需权限。发布流程只分发到已有内部组，不邀请新测试者、不提交 App Store 审核。

Cue 的 Distribution 证书和团队 API Key 在同一 Apple 团队且权限匹配时可以复用；它的应用 ID、App/Watch/Activity profiles 不适用于这里。仍需 still.fail 自己的 App 和 Widget profiles。脚本会在归档前验证 profile 的 bundle ID、团队、证书、有效期与 capabilities；API 也会核对 App ID 指向 `fail.still.iphone`。

将文件放在 Git 仓库之外的私有目录，文件名为 `api.p8`、`distribution.p12`、`p12-password`、`app.mobileprovision`、`widget.mobileprovision`。`p12-password` 中保存 P12 的导出密码。

```sh
python3 apps/ios/scripts/testflight-config.py pack \
  --signing-dir /path/to/private-signing-files \
  --app-id YOUR_STILL_FAIL_APP_ID \
  --key-id YOUR_API_KEY_ID \
  --issuer-id YOUR_ISSUER_ID \
  --team-id D9AAN3VJK8 \
  --group 'Internal Testers' \
  --output /path/to/private-signing-files/stillfail-testflight.b64

gh secret set IOS_TESTFLIGHT_CONFIG \
  --repo AFK-surf/still.fail --env ios-testflight \
  < /path/to/private-signing-files/stillfail-testflight.b64
```

输出文件以 0600 权限创建，不能覆盖已有文件；打包脚本会检查 GitHub Secret 的 48 KiB 上限。环境配置可单独验证：

```sh
IOS_TESTFLIGHT_CONFIG="$(cat /path/to/private-signing-files/stillfail-testflight.b64)" \
  GITHUB_ENV=/tmp/stillfail-public-config \
  python3 apps/ios/scripts/testflight-config.py env
```

该命令只导出 App ID、团队等公开配置。密钥应通过私有文件和 GitHub Secret 配置。

## 手动发布

先将 CI 和 iOS 实现合入 main，然后在 GitHub Actions 选择 **iOS TestFlight → Run workflow**。Workflow 必须从 main 运行，`source_ref` 可以是 main 或 main 上的 tag。

- `version_bump=none`：保留 Apple 与所选工程中较高的 marketing version，仅递增 build number。
- `patch`、`minor`、`major`：按语义版本递增；构建号同时读取 Apple 已处理的构建和待处理上传，避免重复。
- `test_notes`：内部测试的 What to Test 内容。
- `resume_build_id`：分发已有 Apple build，不再构建或上传；此时 `version_bump` 必须为 `none`。

still.fail 当前只有一个 cloud API：`https://app.still.fail`，因此没有 Cue 的 staging/production 后端选择。App 和 Widget 的版本、构建号在临时生成的发布工程中覆盖，发布不会向仓库提交版本号变化。

新发布先运行全部 iOS 测试，再使用 ASC 2.6.0 归档和导出，上传、等待 Apple 处理，最后加入内部测试组。签名使用临时 Keychain，并与现有桌面签名流程共用 Mac 的签名锁；P12 在导入后即删除，签名文件、临时 profile 和 Keychain 在结束时清理。已有且完全一致的 runner profile 可以复用，清理只删除本次创建的文件。

## 失败重跑

版本、构建号、source SHA、测试组在第一次解析后冻结。上传前再保存一份不可变的上传记录；这两份 artifact 保留 90 天。

使用 **Re-run jobs** 时恢复相同配置。上传记录存在时只查找 Apple 中相同 App/platform/version/build 的构建，避免超时后再次上传。不假设超时代表 Apple 未收到：尚未发现构建时，流程报告上传结果待确认，可稍后重跑或填写 `resume_build_id`。如果前一次保存了上传记录却尚未真正上传就中断，应启动新的发布。

分发已有 build 或重跑时仅能确认 Apple 的版本和构建号，摘要会标记源代码来源未独立验证。IPA、dSYMs、日志和发布摘要保留 14 天。失败时归档停止；普通 CI 与签名发布的日志均可在 Actions artifact 中查看。
