# 小面板

菜单、下拉、右键菜单、popover、悬停卡片、station 卡片、通知气泡、⌘K 之外的一切「浮起来的小东西」都是小面板。规范在代码里：`web/src/styles/align.ts`（数）、`web/src/styles/controls.css.ts` 的 `popover` / `panelCard` / `panelEdge`（底）、`web/src/ui.tsx` 的 `Panel*`（部件）。这里只写规则。

## 底

- 一个小面板只有一种底：`controlsCss.popover`（白底或深色 raised 灰、一圈细线、阴影），不自己写底色、内边距、圆角。要改宽度、层级、动画，就用 `style([popover, {...}])` 组合。
- 内边距统一 `PANEL_PAD` = 6。它只管有自己底色的东西（行、按钮、一组行）离面板边多远。
- 面板圆角 = 内圆角 `--panel-in` + 6，内圆角默认 `--r-menu − 6`。贴着内边距的行，圆角就用 `inner`（`var(--panel-in)`），所以跟面板同心。

## 文字

- 文字自己留空间，不靠加大面板的内边距：缩进一个行的内边距 `TEXT_IN` = 10。菜单行里的字和卡片里的字，都在离面板边 6 + 10 = 16 的同一条线上。
- 一段段文字组成的面板（卡片）加 `panelCard`：它的每个直接子元素左右缩进 10，第一个上面留 6，最后一个下面留 6。贴着内边距的东西（一行、一组行、带按钮的头和脚）标上 `panelEdge`，不缩进。
- 行（`menuItem`、`PanelRow`、各列表的行）左右内边距是 `TEXT_IN`；小标题、空状态的提示也一样。

## 按钮

- 小面板里只有两种按钮：文字按钮 `PanelButton`（`panelButton`），24 高的小胶囊；图标按钮 `PanelIconButton`（`panelIcon`），24 的圆。不用 28 高的按钮、方块或带别的圆角的按钮。
- `tone`：`accent` 是唯一要做的事，`quiet` 是次要的，`filled` 是必须一直被看到的（底色常驻）。
- 放在面板角落时，离两条边一样远（都是 6）。

## 检查

- `scripts/check.sh`：
  - 「no hand-written negative margins」：样式里不能手写负 margin。
  - 「small panels on one ground」：`surface()` 只允许出现在 popover、通知气泡、⌘K、composer 引用列表四处，其它小面板必须组合 `popover`。
- `test/browser/align.mjs`（在 studio 上手动跑，CI 没有浏览器）：在 demo 里打开各个小面板，量四件事：
  - 小面板的内边距是不是 6；
  - 角落元素横竖距离是否相等、圆角是否同心；
  - `panelCard` 里文字是否在 16 那条线上；
  - 行的左内边距是不是 10。
