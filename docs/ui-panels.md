# 小面板

菜单、下拉、右键菜单、popover、悬停卡片、station 卡片、通知气泡、⌘K 之外的一切「浮起来的小东西」都是小面板。规范在代码里：`web/ui/src/styles/align.ts`（数）、`web/ui/src/styles/controls.css.ts` 的 `popover` / `panelCard` / `panelEdge`（底）、`web/ui/src/parts.tsx` 的 `Panel*`（部件）。这里只写规则。

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

## 页面卡片

页面里的卡片（设置页、密钥、权限、决策选项这类，`web/src/styles/pages.css.ts`）也按「圆角从里面的东西算」，分两类：

- **内容卡**（`pagesCss.card`：标题、说明、按钮）：四边都是 `CARD_PAD`（20）。文字和**有常驻底色的按钮**（实心按钮）站在同一条线上，对齐的是按钮底色的边，不是按钮里的字，因为底色很显眼，字对字反而看着没对齐。实心按钮在角上时（按钮那排 `pagesCss.cardFoot` 在最下面，或者最后一行以实心按钮结尾），卡片圆角 = 20 + 按钮半高 18 = 38，和按钮同心；角上没有带底色的东西时，圆角照旧 22。卡片里不是实心的按钮是文字按钮，悬停时底色往外伸，和行一样（`pageControls.css.ts`）。
- **列表卡**（`pagesCss.listCard`，以及决策选项 `Decisions.css.ts`）：每一行都能点，平时没有底色，悬停才有。底色伸到离卡片边 `LIST_PAD`（8），行圆角 `ROW_CORNER`（18），卡片圆角 = 行圆角 + 8，同心；行里的字离卡片边还是 20，和内容卡对齐。决策选项的编号圆圈离行边 8，和行的角同心。
- 卡片标题前不放圆点：状态由标题的文字说（圆点放在线内会把标题往右推，挂到线外又贴着卡片边，都不对）。

## 等待

只有三种等待，各一个组件，PC web、手机 web、安卓画法一样（`web/ui/src/waiting.tsx`，安卓 `ui/Waiting.kt`）：

- **页面或列表第一次读取**：`Waiting`。只在内容区画将要出现的东西的形状（`rows` 列表行、`messages` 消息、`cards` 设置页卡片），透明度 1→0.5→1 呼吸（1.4s，减少动效时静止；试过亮光扫过，嫌乱），不写字：「正在读取 X」只给读屏（core 的 note `ListNote` 的 text，没有就用页面自己的，再没有用 `common.reading`）。顶栏、标题、返回、tabs、composer 照常画，不再整页灰字或整页转圈。读不到的 station 在形状上方各一个红色胶囊 `WaitPill error`，立刻出现，形状停住并变淡（0.6）。已有几行、还在等别的 station 时，行下面用 `WaitMore`（一行形状，失败的红字）。
- **内容区里的一小块**（卡片里的一行、一节还没到）：`WaitLine`，12 的转圈 + 灰字，同样 400ms 后出现，出错红字无转圈。
- **某一行或某个按钮在做事**：`Spinner`，只有两种尺寸：`inline` 12（行尾、胶囊、小字行里），默认 14（按钮、图标按钮里替换图标）；线宽 2，底圈 lineStrong + 主题色弧，实心按钮里跟按钮文字颜色。core 的调用一律走 `DoingMark` / `DoingShown`（转圈，失败后红「!」）。不手写转圈，各处只改颜色和位置，不改尺寸。
- **有大小的传输**（上传、下载、更新、读文件）：`Progress`，3 高的胶囊条，底是主题色 18%；不知道总量时 40% 的一段 1.4s 来回扫（减少动效时整条 35% 透明）。
- 播放器缓冲、远程屏幕连接中：浮在画面上的磨砂胶囊（`WaitPill over`），不用大号转圈。
- 文案：「正在读取 X」/「Loading X」，不带省略号；通用词用 `common.*`（reading、readingStations、connecting、reconnecting、opening、saving、uploading、downloading）。

## 减少动效

减少动效只是同一个时钟走得快：页面走同一条路，每个动效的时长都是 0，结束时的样子和结束后要做的事（移除、回调、焦点）跟不减少时完全一样。不给某一处另写一份「减少版」。

- web：样式由 `styles/global.css.ts` 把所有动画压到 1ms、只播一遍，过渡直接到位（不是 1ms：每个元素的 `transition-property` 默认是 `all`，1ms 会让所有属性都过渡一帧，重新显示的东西会空一帧）；`motion` 库由 `MotionGlobalConfig.instantAnimations`（`followMotion` 设）；`el.animate` 一律走 `play`，等动效的计时走 `motionMs`，跟着列表滑的走 `glideShare`（都在 `web/ui/src/motion.ts`）。`check.sh` 的「reduced motion as one clock」拦脚本里直接读 `reducedMotion()` 或调 `.animate(`。
- 安卓：`ui/Motion.kt` 的 `Motion` 把这台设备的设置（prefs `motion`，没设就跟系统的动画时长缩放，变了就跟着变）做成整个 app 的 `MotionDurationScale`，减少时为 0；底栏自己的逐帧弹簧读同一个时钟，减少时直接到目标。页面里不写「减少时」分支。
- 只有两种东西要自己的静止样子，各用一个共用写法：
  - 一直循环的（转圈、呼吸）：给一个静止的样子（转圈慢到 2.4s，呼吸停在平静时，不知道总量的进度条整条 35% 透明）。web 是 `styles/still.ts` 的 `stillLoop`，安卓是 `rememberLoop`；
  - 亮一下就消失的（跳到某条消息、引用段落的高亮）：不渐变地亮同样久再消失，不能因为时长是 0 就看不见。web 是 `stillFlash`，安卓是 `flash`。
- `test/browser/stories.mjs` 每个 story 再在减少动效下走一遍，跟不减少时逐个元素比位置、大小、透明度、颜色，不一样就挂（循环的除外）。

## 组件画廊（stories）

`web/stories`：app 的每个部分、每种状态各是一个 story（`web/stories/stories.tsx`），用的是官网 demo 的假 core，再加上 `web/stories/data.ts` 里补的数据（小说、Markdown、视频、图片、更新说明），不进任何发布的包。

- `pnpm stories` 打开画廊：左边列出所有 story，右边按选的设备和主题（浅色/深色）显示，打开时自己点到那个状态。`?story=<id>&theme=light|dark&device=<id>` 单独打开一个。
- 设备（`web/stories/devices.ts`）：Mac 窗口（红绿灯在 app 让 macOS 放的位置）、Mac 全屏，几款 iPhone（灵动岛、刘海、Home 键）和 Android（挖孔，手势或三键导航），各有自己的安全区域，状态栏、Home 条、导航键画在屏幕上面。
- 安全区域只通过 `--safe-top` / `--safe-bottom` / `--safe-left` / `--safe-right`（`styles/global.css.ts`）读，不直接写 `env(safe-area-inset-*)`，画廊靠设这几个变量把页面放到各个手机上（`scripts/check.sh` 检查）。
- story 有两种：
  - 整个 app（`app: true`），用 `steps` 点到对应状态；
  - 单独画一个部件（`render`）。
- 加新界面就加一个 story：测试会自动打开它、量它，不用另写测试。

## 检查

- `scripts/check.sh`：
  - 「no hand-written negative margins」：样式里不能手写负 margin。
  - 「no corner of its own (in what this adds)」：这次改动新增的样式行里不能写死圆角（5px 及以上），用 tokens（`vars.r*`）或 `align.ts` 的 `surface`/`inner` 算出来；圆、胶囊（`999px`）和 4px 以内的小记号除外，确实要自定的在同一行注释 `own corner: <为什么>`。已有的不追究，改到哪行就顺手改掉。
  - 「small panels on one ground」：`surface()` 只允许出现在 popover、通知气泡、⌘K、composer 引用列表四处，其它小面板必须组合 `popover`。
  - 「web: stories measured, the message list's motion watched」（完整检查，CI 的 Linux runner 用自带 Chrome）：`test/browser/stories.mjs` 打开每个 story，走完它的 `steps`，用 `test/browser/measure.mjs` 量两件事，有一处不对就挂：
    - 所有圆角（`corners`）：圆的东西（胶囊）放在 superellipse 的角里时，按圆的等效圆角算（角的半径 ÷ corner-scale）；一个可点的行（比如决策选项）里面的东西，按那一行悬停时的底色算角；每个有底色或能按的圆角元素，落在外面圆角容器的角落里时，离两边一样远，圆角同心，而且它够高、圆得到外圆角要的那么大（胶囊太矮就会在角上空出月牙：这时外圆角从它算，`align.ts` `pillInner`）；
    - 所有小面板（`panels`）：内边距 6，卡片文字四边 16，行的文字缩进 10，角落元素同心。
    - 量完再把每个滚动区滚到底量一遍：列表最后一行（⌘K 的最后一项）只有滚到底才在角落里。
- 开发版（`pnpm dev:web`、`pnpm stories`）一边用一边量（`web/src/dev/offs.ts`，量法同上）：不对的地方画红框，指上去说哪里不对，控制台打一行 `off (docs/ui-panels.md): …`。写界面时第一眼就看得到，不用等 CI，也不只限于 story 走得到的状态。
- 本机跑：`PLAYWRIGHT_MODULE=<playwright> node test/browser/stories.mjs`；`ONLY=<id,…>` 只跑几个，`REPORT=1` 列出全部问题而不是直接失败，`SHOTS=<目录>` 每个 story 存一张图。
