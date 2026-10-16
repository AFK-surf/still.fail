# 桌面版只更新网页（不用重启）

桌面版带着两样东西：**网页**（`dist/cloud-web`，就是 app.still.fail 那份构建）和**壳**（Electron 主进程和 preload、client 核心 `client/core-ts`、station 和它的原生部分，以及壳的 bundle 从 `web/`、`cloud/` 里引用到的几个文件）。以前随便改哪一样都要重发整个 app（mac zip 加 Windows 安装包，约 270 MB，签名、上传都要等），而 main 上七成多的提交只改了 `web/`。

现在测试版（youdid.wtf）的更新分两种：

| | 什么时候 | 用户看到 | 生效 |
|---|---|---|---|
| **整个 app** | 改到了壳 | 「更新」，下载完 app 会重启 | 重启后 |
| **只换网页** | 只改了网页 | 「刷新更新」，网页包已经在后台下载好了 | 点一下窗口重新加载；不点的话下次启动自动用上 |

正式版（still.fail）暂时不变，还是只有整个 app 的更新。

## 怎么判断哪种

`scripts/desktop-web.ts` 里的 `SHELL` 列出壳包含的路径，`WEB` 是网页的路径（`web/`）。根目录的 `package.json` 和 `pnpm-lock.yaml` 算壳：壳的 bundle 也用到根目录的包（页面标注用的 modern-screenshot），所以升级依赖还是发整个 app。CI 的 plan 用它算出：

- `desktop=true`：改到了壳，desktop job 照旧打整个 app（新 app 里也带着新网页）。
- `desktop_web=true` 且壳没改：desktop-web job 只打网页包。

壳的 bundle 引用了 `web/` 或 `cloud/` 里的哪些文件，是用 esbuild 的依赖图查出来的。`check.sh` 里的「desktop: its shell's files」会检查 `SHELL` 有没有覆盖全部这些文件：比如壳新 import 了一个 `web/` 里的文件却没加进 `SHELL`，检查就会失败。否则改这个文件只会发网页包，壳里的那份不会跟着更新。

## 兼容：网页包写明它要求的最低 app 版本

网页包的 feed 里带一个 `needs`，意思是这个网页只能在 0.1.`needs` 及以后的 app 里跑。它取的是**最近一个改动壳的提交**的 build 号（`desktop-web.ts needs`）。从那个提交起，壳没有再变过，所以 0.1.`needs` 及以后的 app 带的壳和这份网页构建时的壳完全一样，preload、IPC、client 核心的协议都对得上。更旧的 app 不会接收这个网页包，等装了整个 app 的更新之后再说。

所以不需要人去维护接口版本号。代价是保守：只要改了壳，哪怕只是一行和网页无关的代码，之后的网页包也只有新 app 才能接收。但改了壳本来就会同时发新 app，影响不大。

## 发布（CI）

desktop-web job（GitHub 的 ubuntu runner）：

1. `vp build --config web/vite.config.ts --mode cloud`，和 desktop job 的 `build:cloud` 是同一份构建，带 PostHog key。
2. `desktop-web.ts pack`：把 `dist/cloud-web` 打成 `desktop/web/stillfail-beta-web-0.1.N.tar.gz`（`apps/desktop/src/web-archive.mts`：只放普通文件，按路径排序，同样的文件得到同样的字节），然后用 `release-sign.ts desktop-web` 签出 feed `desktop/web/stillfail-beta-web.json`。
3. 压缩包带版本号，马上传到 bucket；feed 由 put job 在检查都过了之后再传（`release-put.sh` 把 `desktop/web/*.json` 当作 feed 处理）。

`release-prune.ts` 会保留 feed 当前指向的那个包、比它新的包，以及最新的 5 个，其余删掉。cloud 只放行这两类文件（`cloud/src/install.ts` 的 `APP_FILES`），压缩包可以长期缓存。

## 签名

和 station、Windows 安装包用同一把发布密钥（[release-signing.md](release-signing.md)）。签名的内容是：

```json
{"kind": "stillfail-desktop-web", "version": "0.1.N", "build": N, "needs": M, "file": "stillfail-beta-web-0.1.N.tar.gz", "sha256": "…", "size": 123}
```

app 端用 `verifyDesktopWeb`（`station/src/updates/signed.ts`）验证：签名必须是 `RELEASE_KEYS` 里的密钥、`needs` 不能超过 app 自己的 build、版本必须比当前在用的网页新、文件名里不能带路径。下载后再核对 sha256 和大小，解压时只接受普通文件、路径不能跑出目录（`readArchive`）。网页在 app 里能操作本机 station 和文件，所以这几步一步都不能省。

## app 端（`apps/desktop/src/web-update.mts`）

- 只有打包好的测试版才启用：从源码运行（dev.sh）不启用，正式版也不启用。
- 启动时检查一次，之后每 30 分钟检查一次 feed（只有几百字节）。有新包就下载（约 6 MB），解压到 `userData/web/0.1.N.part`，完整后再改名为 `0.1.N`，然后通过 `update:state` 告诉页面 `{phase: "available", kind: "web"}`。
- 点「刷新更新」：之后的新请求都从新目录提供，然后所有窗口重新加载，app 不重启。
- 已经打开的旧页面，晚些时候才加载的 chunk 按顺序去找：当前目录 → 本次运行里之前用过的目录（最多 2 个）→ app 内置的目录。所以切换网页时旧窗口不会 404。
- 下次启动时直接用已下载的最新包（前提是它比 app 内置的新，且 `needs` 符合），其余的删掉。`userData/web/state.json` 记录当前用的是哪个。
- 回退：如果新网页的页面找不到（`ERR_FILE_NOT_FOUND`），或者开始加载后 30 秒内渲染进程崩溃（`crashed`、`launch-failed`；被系统因内存杀掉的不算），就把这个页面开始加载时用的 build 删掉、标记为 `0.1.N.rejected`（之后不会再下载它），回到上一个版本（没有的话回到 app 内置的），然后重新加载。多个窗口同时报同一个 build 时只回退一次。
- 「整个 app」的更新优先：如果两种更新都有，页面只显示整个 app 的那个，因为新 app 本身就带着新网页。

## 还没做

- 正式版通道（需要一个 stable 的网页 feed，和 `release.sh promote` 一起发）。
- 页面启动时 JS 报错但没崩溃的情况，现在检测不到（只能检测到加载失败和渲染进程崩溃）。
