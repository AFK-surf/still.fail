# 小面板

菜单、下拉、右键菜单、popover、悬停卡片、station 卡片、通知气泡、⌘K 之外的一切「浮起来的小东西」都是小面板。规范在代码里：`web/src/styles/align.ts`（数）、`web/src/styles/controls.css.ts` 的 `popover` / `panelCard` / `panelEdge`（底）、`web/src/ui.tsx` 的 `Panel*`（部件）。这里只写规则。

## 底

- 一个小面板只有一种底：`controlsCss.popover`（白底或深色 raised 灰、一圈细线、阴影），不自己写底色、内边距、圆角。要改宽度、层级、动画，就用 `style([popover, {...}])` 组合。
- 内边距统一 `PANEL_PAD` = 6。它只管有自己底色的东西（行、按钮、一组行）离面板边多远。
- 面板圆角 = 内圆角 `--panel-in` + 6，内圆角默认 `--r-menu − 6`。贴着内边距的行，圆角就用 `inner`（`var(--panel-in)`），所以跟面板同心。

## 文字

- 文字自己留空间，不靠加大面板的内边距：缩进一个行的内边距 `TEXT_IN` = 10。菜单行里的字和卡片里的字，都在离面板边 6 + 10 = 16 的同一条线上。
- 一段段文字组成的面板（卡片）加 `panelCard`：它的每个直接子元素左右缩进 10，第一个上面、最后一个下面也各留 10：文字离面板四边都是 16。贴着内边距的东西（一行、一组行、带按钮的头和脚）标上 `panelEdge`，不缩进。
- 行（`menuItem`、`PanelRow`、各列表的行）左右内边距是 `TEXT_IN`；小标题、空状态的提示也一样。

## 按钮

- 小面板里只有两种按钮：文字按钮 `PanelButton`（`panelButton`），24 高的小胶囊；图标按钮 `PanelIconButton`（`panelIcon`），24 的圆。不用 28 高的按钮、方块或带别的圆角的按钮。
- `tone`：`accent` 是唯一要做的事，`quiet` 是次要的，`filled` 是必须一直被看到的（底色常驻）。
- 放在面板角落时，离两条边一样远（都是 6）。

## 所有带圆角的东西

不止小面板：侧栏（包括收起后临时展开时浮起来的那条）、卡片、composer、工具条、弹窗，凡是带圆角的容器都守同一条规则。

- 放在容器角落里的东西（容器圆角范围内、离两条边都很近的按钮、行、输入框、带底色的块），离那两条边一样远，自己的圆角 = 容器圆角 − 这段距离（同心）。
- 容器用 `surface()` / `popover` 声明内边距和内圆角的，角落里的东西直接用 `inner`；容器圆角是别处算出来的（比如侧栏浮起时的 9 + 6），角落里的东西照同一个式子算，不另写一个数。

## 检查

- `scripts/check.sh`：
  - 「no hand-written negative margins」：样式里不能手写负 margin。
  - 「small panels on one ground」：`surface()` 只允许出现在 popover、通知气泡、⌘K、composer 引用列表四处，其它小面板必须组合 `popover`。
- `test/browser/corners.mjs`：在 demo 里打开各种页面和状态（宽屏、手机，侧栏展开、收起、临时展开，各个弹层），对每个有自己底色、或者可以按的带圆角元素，找它外面最近的带圆角容器；落在容器角落里的，量两条边的距离是否相等、圆角是否同心。不按面板列清单，新加的东西也会被量到。
- `test/browser/align.mjs`：在 demo 里打开各个小面板，量四件事：
  - 小面板的内边距是不是 6；
  - 角落元素横竖距离是否相等、圆角是否同心；
  - `panelCard` 里文字是否在 16 那条线上；
  - 行的左内边距是不是 10。
- 这两个测试在完整检查里跑（`scripts/check.sh` 的「web: corners and panels measured」，CI 的 Linux runner 用它自带的 Chrome）；本机要跑就设 `PLAYWRIGHT_MODULE` 指向 Playwright。
