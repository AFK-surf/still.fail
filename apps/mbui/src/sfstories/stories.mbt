// Each part of the library and its states, as the page shows them (shell.mbt): grouped as a page is made of them,
// what can be pressed answering as it does in the app.

///|
/// A row of parts side by side, going on in another line where it has not the room.
fn side_by_side(card : @view.View, make : (@view.View) -> Unit) -> Unit {
  card.box(fn(r) {
    r.row(Is(true)).wraps(Is(Some(12.0))).gap(Is(12.0)).lines_up(Is(Some(Middle))) |> ignore
    make(r)
  })
  |> ignore
}

///|
/// A story's state: a part's own state kept with it, from its first making.
fn[T] kept(v : T) -> @signals.Signal[T] {
  @signals.signal(v)
}

///|
let markdown_sample : String =
  #|### 发版前的检查
  #|
  #|已经跑完 **48 个测试**，*全部通过*。还剩两件事：
  #|
  #|1. 在 Windows 上看一眼 `DirectWrite` 的斜体
  #|2. 补上 ~~旧的~~ 新的截图
  #|
  #|- [x] 富文本的换行
  #|- [ ] 页面的左滑返回
  #|
  #|> 小提示：长按链接以后的菜单，这一版还没有做。
  #|
  #|详情见 [设计文档](https://example.com/design)。

///|
let table_sample : String =
  #|| 平台 | 宿主 | 状态 |
  #||:--|:--|--:|
  #|| Android | mbui | 已发布 |
  #|| macOS | mbui | 已发布 |
  #|| Web | canvas | 测试中 |

///|
let code_sample : String =
  #|cd apps/mbui && . scripts/env.sh
  #|bash scripts/kit-web.sh dist/kit

///|
/// Every part shown, in the order of the list: `tips` the layer an icon button's name is shown in.
fn stories(tips : @sf.TipLayer) -> Array[Story] {
  [
    {
      key: "button",
      group: "按钮",
      name: "按钮 Button",
      file: "button_node.mbt",
      about: "页面和弹层里的按钮：六种语气，可带图标；忙时转圈，不可用时变淡。",
      cases: [
        (
          "语气 Tone",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.button_node(r, fn() { "取消" }, fn() {  }) |> ignore
              @sf.button_node(r, fn() { "保存" }, fn() {  }, tone=Primary) |> ignore
              @sf.button_node(r, fn() { "更多" }, fn() {  }, tone=Ghost) |> ignore
              @sf.button_node(r, fn() { "删除" }, fn() {  }, tone=Danger) |> ignore
              @sf.button_node(r, fn() { "永久删除" }, fn() {  }, tone=DangerSolid) |> ignore
              @sf.button_node(r, fn() { "移除" }, fn() {  }, tone=GhostDanger) |> ignore
            })
          },
        ),
        (
          "带图标 icon",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.button_node(r, fn() { "新对话" }, fn() {  }, icon="plus", tone=Primary) |> ignore
              @sf.button_node(r, fn() { "重试" }, fn() {  }, icon="refresh") |> ignore
              @sf.button_node(r, fn() { "分享" }, fn() {  }, icon="share", tone=Ghost) |> ignore
            })
          },
        ),
        (
          "忙 busy（按一下切换）· 不可用 disabled",
          fn(card) {
            let busy = kept(false)
            side_by_side(card, fn(r) {
              @sf.button_node(r, fn() { if busy.get() { "保存中" } else { "保存" } }, fn() { busy.set(!busy.get()) }, tone=Primary, busy=fn() {
                busy.get()
              })
              |> ignore
              @sf.button_node(r, fn() { "不可用" }, fn() {  }, disabled=fn() { true }) |> ignore
            })
          },
        ),
        (
          "撑满一栏 across",
          fn(card) { @sf.button_node(card, fn() { "继续" }, fn() {  }, tone=Primary, across=true) |> ignore },
        ),
      ],
    },
    {
      key: "wide-button",
      group: "按钮",
      name: "宽按钮 WideButton",
      file: "wide_button_node.mbt",
      about: "登录、引导这类页面底部的一整行按钮。",
      cases: [
        (
          "主要 · 次要 · 危险",
          fn(card) {
            @sf.wide_button_node(card, fn() { "继续" }, fn() {  }, true) |> ignore
            @sf.wide_button_node(card, fn() { "稍后再说" }, fn() {  }, false) |> ignore
            @sf.wide_button_node(card, fn() { "退出登录" }, fn() {  }, false, danger=true) |> ignore
          },
        ),
        (
          "忙 · 不可用",
          fn(card) {
            @sf.wide_button_node(card, fn() { "正在登录" }, fn() {  }, true, busy=fn() { true }) |> ignore
            @sf.wide_button_node(card, fn() { "继续" }, fn() {  }, true, enabled=fn() { false }) |> ignore
          },
        ),
      ],
    },
    {
      key: "icon-button",
      group: "按钮",
      name: "图标按钮 IconButton",
      file: "icon_button_node.mbt",
      about: "只有图标的按钮，指针停在上面时显示名字。按的范围至少 44×44。",
      cases: [
        (
          "常用图标",
          fn(card) {
            side_by_side(card, fn(r) {
              for ic in [("copy", "复制"), ("share", "分享"), ("more", "更多"), ("settings", "设置"), ("trash", "删除"), ("search", "搜索")] {
                let (icon, name) = ic
                @sf.icon_button_node(r, icon, fn() { name }, fn() {  }, tips~) |> ignore
              }
            })
          },
        ),
        (
          "不可用 · 大号",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.icon_button_node(r, "send", fn() { "发送" }, fn() {  }, tips~, disabled=fn() { true }) |> ignore
              @sf.icon_button_node(r, "plus", fn() { "新建" }, fn() {  }, tips~, size=44.0, icon_size=22.0) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "float-button",
      group: "按钮",
      name: "浮动按钮 FloatButton",
      file: "float_button_node.mbt",
      about: "浮在列表上的圆形按钮，可带计数。",
      cases: [
        (
          "无计数 · 有计数",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.float_button_node(r, "compose", fn() { "新对话" }, fn() {  }, tips~) |> ignore
              @sf.float_button_node(r, "arrow-down", fn() { "到最新" }, fn() {  }, count=fn() { "3" }, tips~) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "link",
      group: "按钮",
      name: "链接 Link",
      file: "link_node.mbt",
      about: "文字链接，可带图标或箭头。",
      cases: [
        (
          "文字 · 图标 · 箭头",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.link_node(r, fn() { "查看详情" }, fn() {  }) |> ignore
              @sf.link_node(r, fn() { "打开网页" }, fn() {  }, icon="external") |> ignore
              @sf.link_node(r, fn() { "全部设置" }, fn() {  }, chevron=true) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "chip",
      group: "按钮",
      name: "标签与胶囊 Chip · Pill · Badge",
      file: "chip_node.mbt",
      about: "可按的小标签（Chip、可切换的 ToggleChip），以及只用来显示状态的胶囊（Pill）和角标（Badge）。",
      cases: [
        (
          "Chip · ToggleChip（按一下切换）",
          fn(card) {
            let on = kept(true)
            side_by_side(card, fn(r) {
              @sf.chip_node(r, fn() { "Claude" }, fn() {  }, icon="agent", tips~) |> ignore
              @sf.toggle_chip_node(r, fn() { "只看未读" }, fn() { on.get() }, fn() { on.set(!on.get()) }) |> ignore
              @sf.toggle_chip_node(r, fn() { "全部 station" }, fn() { false }, fn() {  }, chevron=true) |> ignore
            })
          },
        ),
        (
          "Pill 的语气",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.pill_node(r, fn() { "普通" }) |> ignore
              @sf.pill_node(r, fn() { "在线" }, tone=Green) |> ignore
              @sf.pill_node(r, fn() { "测试版" }, tone=Blue) |> ignore
              @sf.pill_node(r, fn() { "等待中" }, tone=Amber) |> ignore
              @sf.pill_node(r, fn() { "失败" }, tone=Red) |> ignore
              @sf.pill_node(r, fn() { "推荐" }, tone=Accented, icon="star") |> ignore
            })
          },
        ),
        (
          "Badge",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.badge_node(r, fn() { "3" }) |> ignore
              @sf.badge_node(r, fn() { "12" }, tone=Red) |> ignore
              @sf.badge_node(r, fn() { "新" }, tone=Accented) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "switch",
      group: "选择",
      name: "开关 Switch",
      file: "page_node.mbt",
      about: "开和关两种状态，按一下切换；拖动的手感随操控方式变。",
      cases: [
        (
          "开 · 关 · 小号 · 不可用",
          fn(card) {
            let a = kept(true)
            let b = kept(false)
            let c = kept(true)
            side_by_side(card, fn(r) {
              @sf.switch_node(r, fn() { a.get() }, fn(v) { a.set(v) }, fn() { "通知" })
              @sf.switch_node(r, fn() { b.get() }, fn(v) { b.set(v) }, fn() { "震动" })
              @sf.switch_node(r, fn() { c.get() }, fn(v) { c.set(v) }, fn() { "小号" }, small=true)
              @sf.switch_node(r, fn() { true }, fn(_) {  }, fn() { "不可用" }, disabled=fn() { true })
            })
          },
        ),
        (
          "一行设置 switch_row_node",
          fn(card) {
            let on = kept(true)
            @sf.switch_row_node(card, fn() { "新消息通知" }, fn() { on.get() }, fn(v) { on.set(v) }, note=fn() {
              "有人回复你时推送到这台设备"
            })
          },
        ),
      ],
    },
    {
      key: "check",
      group: "选择",
      name: "勾选 Check",
      file: "check_row_node.mbt",
      about: "多选：单个勾选框（check_node）和带说明的一行（check_row_node）。",
      cases: [
        (
          "勾选框",
          fn(card) {
            let a = kept(true)
            let b = kept(false)
            side_by_side(card, fn(r) {
              @sf.check_node(r, fn() { a.get() }, fn(v) { a.set(v) }, fn() { "记住我" })
              @sf.check_node(r, fn() { b.get() }, fn(v) { b.set(v) }, fn() { "同意条款" })
              @sf.check_node(r, fn() { true }, fn(_) {  }, fn() { "不可用" }, disabled=fn() { true })
            })
          },
        ),
        (
          "勾选行",
          fn(card) {
            let a = kept(true)
            let b = kept(false)
            @sf.check_row_node(card, fn() { "Claude Code" }, fn() { a.get() }, fn(v) { a.set(v) }, note=fn() {
              "在这台 station 上可用"
            })
            @sf.check_row_node(card, fn() { "Codex" }, fn() { b.get() }, fn(v) { b.set(v) })
          },
        ),
      ],
    },
    {
      key: "choice-row",
      group: "选择",
      name: "单选行 ChoiceRow",
      file: "choice_row_node.mbt",
      about: "几个里选一个，每个一行，可带说明。",
      cases: [
        (
          "按一行选中它",
          fn(card) {
            let chosen = kept(1)
            for i, o in [("跟随系统", "按设备的设置"), ("浅色", ""), ("深色", "夜里看更舒服")] {
              let (label, note) = o
              @sf.choice_row_node(card, fn() { label }, fn() { chosen.get() == i }, press=fn() { chosen.set(i) }, note=fn() {
                note
              })
            }
          },
        ),
      ],
    },
    {
      key: "seg",
      group: "选择",
      name: "分段 Segmented",
      file: "seg_node.mbt",
      about: "几个并列的选项，同时只选中一个。",
      cases: [
        (
          "按内容宽 seg_node",
          fn(card) {
            let chosen = kept(0)
            @sf.seg_node(card, fn() { ["今天", "7 天", "30 天"] }, fn() { chosen.get() }, fn(i) { chosen.set(i) }, said="时间")
            |> ignore
          },
        ),
        (
          "撑满 seg_fill_node",
          fn(card) {
            let chosen = kept(2)
            @sf.seg_fill_node(card, fn() { ["系统", "浅色", "深色"] }, fn() { chosen.get() }, fn(i) { chosen.set(i) }, said="主题")
            |> ignore
          },
        ),
      ],
    },
    {
      key: "select",
      group: "选择",
      name: "下拉选择 Select",
      file: "select_node.mbt",
      about: "按下后从列表里选一个：小屏从底部弹出，中屏和大屏在它旁边展开。",
      cases: [
        (
          "选模型",
          fn(card) {
            let value = kept("sonnet")
            @sf.select_node(
              card,
              fn() { value.get() },
              fn() { [("opus", "Opus 5.5"), ("sonnet", "Sonnet 5.5"), ("haiku", "Haiku 5.5")] },
              fn(v) { value.set(v) },
              label=fn() { "模型" },
            )
          },
        ),
      ],
    },
    {
      key: "options-card",
      group: "选择",
      name: "选项卡片 OptionsCard",
      file: "options_card_node.mbt",
      about: "agent 提问时给出的几个选项：按下一个，它转圈直到答完，选中的打勾。",
      cases: [
        (
          "可选（按一个试试）",
          fn(card) {
            let chosen : @signals.Signal[Int?] = kept(None)
            @sf.options_card_node(
              card,
              fn() { [("先合并", "CI 已全绿", true), ("再等等", "等 review", false), ("关掉这个 PR", "", false)] },
              fn() { chosen.get() is None },
              fn() { None },
              chosen=fn() { chosen.get() },
              on_pick=fn(i) { chosen.set(Some(i)) },
            )
            |> ignore
          },
        ),
        (
          "正在答第二个",
          fn(card) {
            @sf.options_card_node(card, fn() { [("是", "", false), ("否", "", false)] }, fn() { true }, fn() { Some(1) })
            |> ignore
          },
        ),
      ],
    },
    {
      key: "input",
      group: "输入",
      name: "输入框 Input",
      file: "field_node.mbt",
      about: "一行文字的输入框：可带标签、占位、密码，或不可用。",
      cases: [
        (
          "占位 · 有字 · 密码 · 不可用",
          fn(card) {
            @sf.input_node(card, @ui.Field::new(), placeholder="搜索对话") |> ignore
            @sf.input_node(card, @ui.Field::new(text="still.fail"), label="名字") |> ignore
            @sf.input_node(card, @ui.Field::new(text="hunter2"), label="密码", secret=true) |> ignore
            @sf.input_node(card, @ui.Field::new(text="不能改"), disabled=fn() { true }) |> ignore
          },
        ),
        (
          "小号 small",
          fn(card) { @sf.input_node(card, @ui.Field::new(), placeholder="筛选", small=true) |> ignore },
        ),
      ],
    },
    {
      key: "textarea",
      group: "输入",
      name: "多行输入 Textarea",
      file: "field_node.mbt",
      about: "多行文字，随内容长高，到 most 行为止。",
      cases: [
        (
          "三行起",
          fn(card) {
            @sf.textarea_node(card, @ui.Field::new(), placeholder="写点什么……", label="说明") |> ignore
          },
        ),
      ],
    },
    {
      key: "field",
      group: "输入",
      name: "表单项 Field",
      file: "field_node.mbt",
      about: "表单里的一项：标签、控件，下面是提示或错误。",
      cases: [
        (
          "提示 hint",
          fn(card) {
            @sf.field_node(card, fn() { "station 名字" }, fn(b) { @sf.input_node(b, @ui.Field::new(text="mac-mini")) |> ignore }, hint=fn() {
              "别人在列表里看到的名字"
            })
          },
        ),
        (
          "错误 error",
          fn(card) {
            @sf.field_node(card, fn() { "邮箱" }, fn(b) { @sf.input_node(b, @ui.Field::new(text="not-an-email")) |> ignore }, error=fn() {
              "邮箱格式不对"
            })
          },
        ),
      ],
    },
    {
      key: "setting",
      group: "设置",
      name: "设置项 Setting",
      file: "setting_node.mbt",
      about: "设置页的一项：标题和说明，控件在旁边（宽排法）或下面（窄排法）。",
      cases: [
        (
          "宽排法：控件在旁边，一组在一张卡片里",
          fn(card) {
            let on = kept(true)
            let theme = kept(0)
            @sf.look_lent(card, Wide)
            @sf.group_node(card, fn(g) {
              @sf.setting_switch_node(g, fn() { "震动" }, fn() { on.get() }, fn(v) { on.set(v) }, note=fn() {
                "按下和拖动时轻震一下"
              })
              @sf.setting_choice_node(g, fn() { "主题" }, fn() { ["系统", "浅色", "深色"] }, fn() { theme.get() }, fn(i) {
                theme.set(i)
              })
              @sf.setting_link_node(g, fn() { "字体" }, fn() { "Inter · JetBrains Mono" }, fn() {  })
            })
          },
        ),
        (
          "窄排法：开关 · 选择 · 链接 · 自定控件",
          fn(card) {
            let on = kept(true)
            let theme = kept(0)
            @sf.setting_switch_node(card, fn() { "震动" }, fn() { on.get() }, fn(v) { on.set(v) }, note=fn() {
              "按下和拖动时轻震一下"
            })
            @sf.setting_choice_node(card, fn() { "主题" }, fn() { ["系统", "浅色", "深色"] }, fn() { theme.get() }, fn(i) {
              theme.set(i)
            })
            @sf.setting_link_node(card, fn() { "字体" }, fn() { "Inter · JetBrains Mono" }, fn() {  })
            @sf.setting_node(card, fn() { "侧栏" }, note=fn() { "调整侧栏里显示的东西" }, fn(r) {
              @sf.button_node(r, fn() { "自定义" }, fn() {  }) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "progress",
      group: "进度",
      name: "进度 Progress",
      file: "progress_node.mbt",
      about: "进度条（已知多少，或一直扫动）、圆环和转圈。",
      cases: [
        (
          "进度条：40% · 不知道多少",
          fn(card) {
            let t = @sf.theme
            @sf.progress_node(card, fn() { Some(0.4) }, fn() { t().p.line }, fn() { t().p.accent }) |> ignore
            @sf.progress_node(card, fn() { None }, fn() { t().p.line }, fn() { t().p.accent }) |> ignore
          },
        ),
        (
          "圆环 · 转圈",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.progress_ring_node(r, 24.0, fn() { 0.25 }, fn() { @sf.theme().p.accent }) |> ignore
              @sf.progress_ring_node(r, 24.0, fn() { 0.75 }, fn() { @sf.theme().p.green }) |> ignore
              @sf.progress_spinner_node(r, fn() { None }) |> ignore
              @sf.progress_spinner_node(r, fn() { None }, size=24.0) |> ignore
            })
          },
        ),
      ],
    },
    {
      key: "marks",
      group: "标记",
      name: "头像与标记 Avatar · Mark",
      file: "mark_node.mbt",
      about: "人的头像（没有图时是名字的首字）、station 和 workspace 的标记。",
      cases: [
        (
          "头像：圆 · 方",
          fn(card) {
            side_by_side(card, fn(r) {
              for p in [("u1", "左子健"), ("u2", "Ada"), ("u3", "Bob")] {
                let (id, name) = p
                @sf.avatar_node(r, fn() { id }, fn() { name }, fn() { "" }, 32.0)
              }
              @sf.tile_avatar_node(r, fn() { "u4" }, fn() { "Claude" }, fn() { "" }, 32.0)
            })
          },
        ),
        (
          "station · workspace",
          fn(card) {
            side_by_side(card, fn(r) {
              @sf.station_mark_node(r, fn() { "🗼" }, fn() { "" }, 32.0, fn() { 0L }, fn() { 0 })
              @sf.station_mark_node(r, fn() { "🖥️" }, fn() { "" }, 32.0, fn() { 0L }, fn() { 0 })
              @sf.workspace_badge_node(r, fn() { "AFK" }, fn() { "" }, fn() { "" }, 32.0)
              @sf.workspace_badge_node(r, fn() { "Monoid" }, fn() { "🌊" }, fn() { "" }, 32.0)
            })
          },
        ),
      ],
    },
    {
      key: "type",
      group: "文字",
      name: "文字样式 Type",
      file: "styles.mbt",
      about: "页面里用的文字样式，都跟着系统的字号变大。",
      cases: [
        (
          "title · lead · body · paragraph · caption · note · meta · code",
          fn(card) {
            for st in [
              ("标题 title", @sf.title),
              ("引导 lead：这一页是做什么的", @sf.lead),
              ("正文 body", @sf.body),
              ("段落 paragraph：较长的一段文字，行距更宽，读起来不累。", @sf.paragraph),
              ("说明 caption", @sf.caption),
              ("注 note", @sf.note),
              ("附注 meta · 3 分钟前", @sf.meta),
              ("let code = \"JetBrains Mono\"", @sf.code),
            ] {
              let (words, style) = st
              @sf.words_node(card, fn() { words }, fn() { style }) |> ignore
            }
          },
        ),
      ],
    },
    {
      key: "markdown",
      group: "文字",
      name: "Markdown",
      file: "markdown_node.mbt",
      about: "消息里的 Markdown：标题、强调、列表、待办、引用、行内代码和链接。",
      cases: [("一条消息", fn(card) { @sf.markdown_node(card, fn() { markdown_sample }) |> ignore })],
    },
    {
      key: "code-block",
      group: "文字",
      name: "代码块 CodeBlock",
      file: "markdown_node.mbt",
      about: "Markdown 里的代码块，按语言着色，可复制。",
      cases: [
        ("sh", fn(card) { @sf.code_block_node(card, fn() { code_sample }, fn() { "sh" }, fn() { None }) }),
      ],
    },
    {
      key: "table",
      group: "文字",
      name: "表格 Table",
      file: "table_node.mbt",
      about: "Markdown 表格：太宽时横向滚动。",
      cases: [("三列", fn(card) { @sf.table_node(card, fn() { table_sample }) })],
    },
    {
      key: "file-card",
      group: "卡片",
      name: "文件卡片 FileCard",
      file: "file_card_node.mbt",
      about: "消息里附带的文件：名字、大小，失败时可重试。",
      cases: [
        (
          "正常 · 失败",
          fn(card) {
            @sf.file_card_node(
              card,
              tips,
              fn() { "design.pdf" },
              fn() { "PDF · 2.4 MB" },
              fn() { false },
              fn() { false },
              fn() { true },
              fn() { "重试" },
              fn() { "移除" },
              fn(_) {  },
            )
            |> ignore
            @sf.file_card_node(
              card,
              tips,
              fn() { "screen-recording.mp4" },
              fn() { "上传失败" },
              fn() { true },
              fn() { true },
              fn() { true },
              fn() { "重试" },
              fn() { "移除" },
              fn(_) {  },
            )
            |> ignore
          },
        ),
      ],
    },
    {
      key: "quote-card",
      group: "卡片",
      name: "引用卡片 QuoteCard",
      file: "quote_card_node.mbt",
      about: "回复时引用的那条消息。",
      cases: [
        (
          "引用一条消息",
          fn(card) {
            @sf.quote_card_node(
              card,
              tips,
              fn() { "Claude" },
              fn() { "已经把组件库做成了网页，部署在 kit.monoid.zone。" },
              fn() { "agent" },
              fn() { "看着不错" },
              fn() { true },
              fn() {  },
            )
            |> ignore
          },
        ),
      ],
    },
    {
      key: "presenters",
      group: "弹层",
      name: "菜单与弹层 Menu · Pick · Panel",
      file: "presenters.mbt",
      about: "菜单、选择、确认、提问和面板：小屏从底部弹出，中屏和大屏在打开它的东西旁边。",
      cases: [
        (
          "按下打开",
          fn(card) {
            let model = kept("sonnet")
            side_by_side(card, fn(r) {
              @sf.button_opens_node(r, fn() { "菜单" }, fn(b) {
                @sf.menu(
                  [
                    Some(@sf.menu_item_of("复制", fn() { @sfbase.toast_later("已复制") }, icon="copy")),
                    Some(@sf.menu_item_of("分享…", fn() {  }, icon="share")),
                    None,
                    Some(@sf.menu_item_of("删除", fn() {  }, icon="trash", danger=true)),
                  ],
                  from=@sf.Beside::Node(b),
                )
              })
              |> ignore
              @sf.button_opens_node(r, fn() { "选择" }, fn(b) {
                @sf.pick(
                  "模型",
                  [
                    @sf.choice("opus", "Opus 5.5", note="最强"),
                    @sf.choice("sonnet", "Sonnet 5.5", note="又快又好"),
                    @sf.choice("haiku", "Haiku 5.5", note="最快"),
                  ],
                  model.get(),
                  fn(k) { model.set(k) },
                  from=@sf.Beside::Node(b),
                  search=false,
                )
              })
              |> ignore
              @sf.button_opens_node(r, fn() { "确认" }, fn(b) {
                @sf.confirm(
                  "删除这个对话？",
                  "删除后，对话里的消息都找不回来。",
                  "删除",
                  fn() { @sfbase.toast_later("已删除") },
                  danger=true,
                  from=@sf.Anchor::Node(b),
                )
              })
              |> ignore
              @sf.button_opens_node(r, fn() { "提问" }, fn(b) {
                @sf.ask("重命名", "保存", fn(name) { @sfbase.toast_later("已改名为「\{name}」") }, value="新对话", from=@sf.Anchor::Node(
                  b,
                ))
              })
              |> ignore
              @sf.button_opens_node(r, fn() { "面板" }, fn(b) {
                @sf.panel_nodes(
                  "关于 still.fail",
                  fn(body, close) {
                    @sf.words_node(body, fn() { "面板的内容由节点做成，小屏时是从底部弹出的一页。" }, fn() { @sf.paragraph })
                    |> ignore
                    @sf.button_node(body, fn() { "好" }, close, tone=Primary) |> ignore
                  },
                  from=@sf.Anchor::Node(b),
                )
              })
              |> ignore
              @sf.button_node(r, fn() { "提示 Toast" }, fn() { @sfbase.toast_later("已复制链接") }) |> ignore
            })
          },
        ),
      ],
    },
  ]
}
