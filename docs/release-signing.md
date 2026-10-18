# 发布包签名

目标：still.fail 的服务（Cloudflare 上的 cloud、R2 上的发布包）就算被攻破，也没法批量往用户的 station 推恶意代码。cloud 只负责存和发，签名用的私钥不在 cloud 上，station 只装签名验得过的版本。

## 签什么

`scripts/release.sh` 发 station 时，用 `scripts/release-sign.ts` 把 feed（`releases/station.json`、`station-beta.json`）签成：

```json
{"version": "0.1.N", "build": N, "commit": "…", "release": "<签名内容的 base64>", "signature": "<Ed25519 签名的 base64>", "key": "<key id>"}
```

`version/build/commit` 照旧，给旧 station 看。签名内容（`release` 解码后）是：

```json
{"kind": "stillfail-station-release", "version": "0.1.N", "build": N, "commit": "…", "node": "24.x.y",
 "builds": {"darwin-arm64": {"sha256": "…", "size": 123, "nodeSha256": "…"}, "linux-x64": {…}, "linux-arm64": {…}, "win32-x64": {…}}}
```

- `sha256`/`size` 是各平台发布包（`stillfail-station-<平台>.tar.gz`、`.zip`）本身。
- `nodeSha256` 是 Node 二进制本身（`bin/node`、`node.exe`）的哈希，不是 `node-dist.sh` 重新打的 tar（那个 tar 不确定）。nodejs.org 的二进制是确定的，机器上已有的同版本 Node 只有哈希完全一样才用。
- 不绑定渠道：`release.sh promote` 原样把 beta 拷成 stable 也能用。
- key id 是公钥原始字节 sha256 的前 16 位十六进制（`keyId`）。

Windows 桌面版（NSIS 安装包，没有代码签名）同样签：`desktop/<安装包>.exe.sig`，内容 `{kind: "stillfail-desktop-win", version, build, file, sha256, size}`。mac 桌面版由 Squirrel 验代码签名，安卓由系统验 APK 签名，不另外签。测试版桌面 app 单独更新的网页包也签：feed `desktop/web/stillfail-beta-web.json`，内容 `{kind: "stillfail-desktop-web", version, build, needs, file, sha256, size}`（[desktop-web-updates.md](desktop-web-updates.md)）。

station 自己装的模块包（[station-modules.md](station-modules.md)「包」）也签：`scripts/module-bundle.ts pack` 打出 `releases/modules/<id>/<id>-0.1.N.tar.gz`，再用 `release-sign.ts module` 签 feed `modules/<id>/<id>.json`（测试渠道 `<id>-beta.json`）：

```json
{"id": "media", "version": "0.1.N", "build": N, "needsStation": M, "release": "…", "signature": "…", "key": "…"}
```

签名内容是 `{kind: "stillfail-module-release", id, version, build, needsStation, builds: {"any": {sha256, size}}}`：`any` 是不分平台的包（以后有分平台的就是 `darwin-arm64` 这些，文件名后面加平台），`needsStation` 是它要求的最旧 station 的 build。key 和流程与 station 完全一样（同一个 `RELEASE_SIGNING_KEY`，CI 里没有就失败）。

## 谁验、怎么验

- **station**（`station/src/updates/signed.ts`、`release.ts`）：公钥写死在 `RELEASE_KEYS`。读 feed 时验签，验不过就当没有新版（页面不显示「有新版」，自动更新也不动）。更新时（页面、自动更新、`stillfail update` 都走 `planUpdate`）再取一次 feed 验签，拒绝降级（只有人把渠道从 beta 切回 stable 时可以回到旧版），然后运行**自己这个版本里带的安装脚本** `<app>/bin/install.<zh|en>.<sh|ps1>`，环境变量告诉它 `STILLFAIL_ORIGIN`（发布包在哪）、`STILLFAIL_RELEASE_SHA256`、`STILLFAIL_NODE_SHA256`、`STILLFAIL_INSTALL_LANG`。cloud 上的 `install.sh` 不再参与更新。
- **安装脚本**（`cloud/src/install.ts`、`install-windows.ts`，`scripts/installers.ts` 渲染进发布包）：下载后核对发布包哈希，不对就不装；对了就把控制权交给**新包里带的安装脚本**继续装（`STILLFAIL_ARCHIVE` 指向已下载的包，`STILLFAIL_INSTALLER_HANDED=1` 防止再交），所以安装逻辑的修改照样立刻生效。新脚本会再核一次哈希；Node 按 `nodeSha256` 核二进制。
- **`stillfail update`**（`bin/stillfail`、`bin/stillfail.ps1`）：用本版本的 Node 跑 `station/main.js update [--beta|--stable] --app … --data …`（`station/src/updates/command.ts`），它验签后只输出要运行的脚本和环境变量，由 shell 去运行（Windows 上安装脚本会结束从 `<app>` 跑的进程，包括这个 Node）。原生 launcher 不转发 `update`。
- **Comma**：station 读的是 `<origin>/stations/releases/…`，一样要 still.fail 的 key 签过，Comma 只能原样转发我们签好的 feed。
- **Windows 桌面版**（`apps/desktop/src/main.ts` `verifyWindowsUpdates`）：electron-updater 下载完安装包后调 `verifyUpdateCodeSignature`，取同目录的 `.sig` 验签、核版本（等于 feed 说的、比自己新）和字节；不过就丢掉不装。electron-updater 只在 app-update.yml 有 `publisherName` 时才调这个钩子，`build.sh --win` 给 publish 配置写了一个。
- **模块包**（`station/src/modules/packages.ts`）：读 feed 用 `verifyModule` 验签（`verifySigned` 再加 kind、id、版本的检查），只装比已装的新、`needsStation` 不超过自己 build 的版本，而且永远不装比起来过的最新 build 更旧的（模块的数据可能已经迁到新版）；下载时核大小和 sha256，解压只接受目录里的普通文件。
- **桌面版的网页包**（`apps/desktop/src/web-update.mts`）：下载前用 `verifyDesktopWeb` 验 feed（签名、`needs` 不超过 app 自己的 build、比当前网页新），下载后核对字节，解压时只接受目录里的普通文件。

`STILLFAIL_RELEASE_KEYS`（逗号分隔的公钥）可以在 station 的环境里多加几把 key，只用于测试（dev cloud 上用测试 key 发的版本）。只有机器的用户能设这个环境变量。

## 密钥

- 私钥（Ed25519，PKCS#8 PEM）放在 GitHub Environment `production` 的 secret `RELEASE_SIGNING_KEY`，备份在左子健的 1Password（个人账号的 Personal vault，「still.fail release signing key (release-1 …)」）。恢复 key 只在同一个 vault 里（「still.fail release recovery key …」），不进 CI。两把都是 2026-10-15 在 mba 上用 openssl 生成的，生成完本地文件已删。用到它的 job：`pipeline.yml` 的 `station`、`desktop`、`desktop-win`、`desktop-web`、`modules`，`stable.yml` 的 `station`、`desktop`、`modules`。CI 里没有 key、或者 key 不在 `RELEASE_KEYS` 里，`release-sign.ts` 直接失败，不发未签名的版本。
- 本地用 `RELEASE_DIR` 发到 dev cloud 时没有 key 只警告，产出未签名的 feed（station 不会更新到它）；要测签名就自己生成一把测试 key（下面），station 用 `STILLFAIL_RELEASE_KEYS` 认它。
- 生成：`node scripts/release-sign.ts keygen <私钥文件>`，打印公钥和 key id。公钥加进 `signed.ts` 的 `RELEASE_KEYS`。
- 恢复 key：`RELEASE_KEYS` 里再放一把离线保管的公钥。CI 的 key 泄露或丢失时，用恢复 key 签一个把 `RELEASE_KEYS` 换成新 key 的版本，station 就能继续更新。
- 换 key：先发一个 `RELEASE_KEYS` 同时含新旧 key 的版本（用旧 key 签），等 station 都升上去，再把 secret 换成新 key。

## 部署顺序和过渡

1. 先生成 key，公钥写进 `RELEASE_KEYS`，私钥写进 secret，再合这个改动：合进去的那次 CI 就要签名，没有 secret 会失败。
2. 旧 station 升到第一个签名版本的那一次，用的还是旧版本自己的方式（cloud 上的 `install.sh`，没有校验），这一次接受。之后的每次更新都验签。
3. 正式渠道的 feed 要等下一次「Publish stable」才是签过的；在那之前，新版本的 beta station 切回 stable 看不到可更新的版本。
4. 第一次装（`curl … /install.sh | sh`）没有之前的版本可以依靠，仍然信任 cloud。
