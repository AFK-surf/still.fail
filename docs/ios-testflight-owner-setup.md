# still.fail mbui：GitHub 云端 TestFlight 安全配置

本指南不含凭据。流程仍在验证中；配置完成不等于已上传或可安装。

## 1. 创建受保护的发布环境

仓库：https://github.com/AFK-surf/still.fail

打开 Settings → Environments，创建 `ios-testflight`。Deployment branches and tags 只允许 `main`；开启可信维护者审批（若仓库套餐支持），不要让任意分支、标签、PR 或 fork 使用此环境。不要复用 `production` 中其他平台的密钥。

当前 AirBuild GitHub 连接能读取源代码和 Actions 结果，但不能管理发布密钥；这些值须由仓库管理员在 GitHub 填写。不要发到聊天，也不要提交到仓库。

## 2. Environment secrets：准确的七个名称

| 名称 | 值 |
|---|---|
| `MBUI_IOS_CERTIFICATE_P12_BASE64` | 专用于此 CI 的 Apple Distribution 证书及其私钥的 `.p12` 文件，整体 Base64 编码 |
| `MBUI_IOS_CERTIFICATE_PASSWORD` | 上述 `.p12` 的导出密码，原文，不做 Base64 |
| `MBUI_IOS_APP_PROFILE_BASE64` | App Store Connect 分发描述文件，精确匹配 `fail.still.mbui`，整体 Base64 编码 |
| `MBUI_IOS_SHARE_PROFILE_BASE64` | App Store Connect 分发描述文件，精确匹配 `fail.still.mbui.share`，整体 Base64 编码 |
| `MBUI_ASC_KEY_ID` | 专用 App Store Connect 团队 API 密钥的 Key ID，原文 |
| `MBUI_ASC_ISSUER_ID` | 该 API 密钥所属团队的 Issuer ID，原文 |
| `MBUI_ASC_PRIVATE_KEY_BASE64` | 对应 `AuthKey_<Key ID>.p8` 文件，整体 Base64 编码 |

签名证书、两个描述文件和 API 密钥必须属于 Apple 团队 `D9AAN3VJK8`。两个描述文件必须包含 `group.fail.still.mbui`，均使用上述同一张分发证书；不得使用开发、Ad Hoc、企业或通配符描述文件。

由凭据所有者在 Apple Developer 创建独立 CI 分发身份，并在 App Store Connect → Users and Access → Integrations → App Store Connect API 创建专用团队 API 密钥（需要能够上传该 App、读取构建状态、管理内部 TestFlight 组）。此流程使用带 Issuer ID 的团队密钥，不接受个人密钥。凭据所有者应按 Apple 当前角色要求赋予最小可用权限。只授权新 App；不要修改原版 App 的签名或分发。

只从所有者独立准备的文件取值，不得从 AirBuild 的运行环境、钥匙串或托管签名缓存提取凭据。Base64 只是编码，不是加密。

在文件所有者自己的 Mac 上，可将文件编码后直接复制到剪贴板再粘到对应的 GitHub secret：

```sh
base64 -i '/绝对路径/专用CI文件' | tr -d '\n' | pbcopy
```

这条命令不向终端输出值；完成后清空剪贴板，并妥善保存或删除本地私密文件。不要截取包含 secret 值的屏幕，不要把文件或编码结果附到聊天。证书导出密码、Key ID、Issuer ID 按上表直接填写。

## 3. Environment variable：内部组

另在该环境的 Variables 中设置：

`MBUI_TESTFLIGHT_GROUP_ID` = 所有者明确批准的新版 App 内部组 ID。

新版 App 为 `6826455869` / `fail.still.mbui`。目前已建的专用空组 ID 为 `5f3be0e4-d831-43e7-8abe-994a95575a70`；没有成员，没有公开链接，不自动接收全部构建。只有在所有者批准首轮名单并完成成员授权后，才能把它当作实际测试分发组。空组通过检查不等于有人能安装。

原版 App `6818750243` / `fail.still.iphone` 的 `Internal Testers` 组 ID 为 `b948be95-b47f-4cf6-9c67-5af32a52ee34`，实查 12 人，其中 3 人已安装原版、9 人待接受原版邀请。原版组属于原版 App，不能直接用于新版。可以在所有者授权后复用这些人的测试身份，但不会自动复制全部 12 人，也不会复制 `external default` 公开外部组。

首轮仅向已授权且不在法国的测试人员分发，不启用公开链接。这不是永久排除法国。Apple 此次返回的成员资料没有国家信息，安装状态也不能证明所在地；需由所有者确认首轮名单。

## 4. 验收与后续

配置准备好后，只需在聊天告知“GitHub 发布环境已配置”，不要附任何值。开发者会核对实际 Actions 触发，记录源码提交、签名 IPA 版本及 SHA256、Apple 构建处理结果、获批内部组，最后等待实际 TestFlight 安装证据。

真实云端失败会使任务失败；本地成功不能替代 Actions 发布成功。遇到上传状态不明时，不盲目重新上传相同版本。具体恢复步骤以最终校验后的工作流说明为准。

当前 App 没有 App Intents；此配置工作不改变业务动作，不需要新增评估。
