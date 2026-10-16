# 组件库 `@stillfail/ui`

web 的设计系统单独成包，在 `web/ui`（`web/ui/package.json`）。app（`web/src`）、share 页、官网和 stories 都从这里拿 tokens、对齐、图标、动效、文案和共用部件。

## 边界

- 包里不 import `web/src` 的任何东西，也不碰 core、station、cloud。`scripts/check.sh` 里的「the design system on its own」会拦。
- 包需要的、只有宿主才知道的东西，由宿主在启动时注入：
  - 文案：`i18n.ts` 的 `addWords` 加词表，`setLang` 设语言来源。app 用偏好设置（`web/src/i18n.ts`），share 页用浏览器语言（`web/src/share/stand-ins/i18n.ts`）。没注入时就是浏览器语言。
  - 快捷键：`shortcuts.ts` 的 `setShortcuts` 注入；动作名由宿主声明进 `Shortcuts` 接口（app 在 `web/src/keymap.ts`）。没注入时 tip 不显示按键。
  - 查看器：`viewer/host.ts` 的 `setViewerHost`（app 在 `web/src/viewer/whole.ts`：手机弹层、主题、聊天的 Markdown、偏好里的排版）。打开的文件由调用方给：station 上的文件用 app 的 `web/src/drive/viewerFile.ts`，附件预览用 `blobFile`。
- 引用写 `@stillfail/ui/<文件>`，例如 `@stillfail/ui/styles/tokens.css.ts`、`@stillfail/ui/parts.tsx`。根 `package.json` 用 `link:./web/ui` 把它链进 `node_modules`（Node 的测试和类型检查从这里找），各个 vite 配置另用 `web/ui/alias.ts` 直接指到源码。

## 里面有什么

| 文件 | 内容 |
|---|---|
| `styles/tokens.css.ts` | 颜色、字号、圆角、时长等 tokens（`vars`） |
| `styles/align.ts` | 对齐和同心圆角的算法（`surface`、`inner`、`bleedX`…） |
| `styles/glass.ts`、`styles/keyframes.css.ts`、`styles/busyRing.ts` | 毛玻璃底、关键帧、转圈环 |
| `styles/controls.css.ts` | 按钮、输入框、小面板底（`popover`）、菜单、`Chooser` |
| `styles/page.css.ts`、`styles/spinner.css.ts` | 图标按钮和 section；spinner |
| `parts.tsx`、`parts.css.ts` | 共用部件：Button、IconButton、Tip、Field、Segmented、Choices、Switch、Select、Dialog、Confirm、Menu、Panel*、Chooser、Loading、FirstOne、ResizeHandle… |
| `toast.tsx`、`Avatar.tsx`、`backClose.ts` | toast、字母头像、返回键关闭浮层 |
| `viewer/Reader.tsx`、`viewer/Player.tsx`、`viewer/ViewerBar.tsx` | 阅读器、播放器和它们共用的顶栏；`viewer/media.css.ts` 是浮在画面上的媒体控件 |
| `viewer/file.ts` | 查看器打开的「文件」接口：读全部、流地址、旁边的文件、上次的位置、保存；`blobFile` 包一个已经在手里的 Blob |
| `viewer/host.ts` | 查看器向页面要的东西：窄屏、深色、Markdown 怎么画、手机的弹层、阅读排版存在哪（`setViewerHost`） |
| `strokes.ts` | 找到的字下面的手画线 |
| `icons.tsx` | 图标（由 `scripts/icons.py` 从 `design/icons` 生成） |
| `motion.ts`、`fileSize.ts`、`i18n.ts`、`shortcuts.ts` | 动效规律、文件大小、文案、快捷键接口 |

app 自己的部件（模型和 connect 的标记、时间、返回链接、splash、页面切换）留在 `web/src/ui.tsx`，它同时转出包里的全部部件，所以 app 里照旧 `from "./ui.tsx"` 也行。

## 层叠顺序

样式的先后由 `web/src/styles/index.ts` 决定，包里的样式文件都放在它们拆出来之前的位置：

- `page.css.ts` 在 app 的 `pages.css.ts` 前；
- `parts.css.ts` 在 app 的 `ui.css.ts` 前；
- `controls.css.ts` 在 `pageControls.css.ts` 前；
- `toast.css.ts` 在 `later.css.ts` 前；
- `own.css.ts` 在 `later.css.ts` 后：FirstOne、About、ResizeHandle 自己的尺寸要压过 app 栏的 `> *` 规则（比如窄页面的列宽）。

app 把包的部件放进自己的版面时，规则写在 app 那边（`pageControls.css.ts`、`ui.css.ts`、`later.css.ts`），排在包的后面。

拆包时对过一遍：95 个 story 拆前拆后的每个元素的计算样式都一样。另外把这些部件放进 app 的各个栏里（窄页面、聊天列表、composer 外框、对话框正文等）逐一比过，也都一样。只有几种实际不会出现的摆法有差别：对话框的标题、tip 直接放进窄页面（它们都 portal 到 body），spinner 或菜单的勾直接放进聊天列表。
