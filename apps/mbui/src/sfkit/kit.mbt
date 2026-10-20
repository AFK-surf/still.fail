// The framework's parts for still.fail's pages (MBUI_SCREEN=kit; in a
// browser ?MBUI_SCREEN=kit): a paragraph of rich text, a message in
// Markdown as still.fail shows one, and a stack of pages pushed, popped and
// swiped back, each keeping where its list was scrolled.

///|
struct Kit {
  nav : @ui.Nav[Int]
  /// the link tapped last
  mut went : String
}

///|
let kit : Kit = { nav: @ui.Nav::new(0), went: "" }

///|
let kit_message : String =
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
  #|```sh
  #|scripts/test.sh && scripts/shots.sh kit
  #|```
  #|
  #|详情见 [设计文档](https://example.com/design)，或者直接打开 https://example.com/kit。

///|
fn kit_view(c : @ui.Ctx) -> Unit {
  let t = @sf.begin(c)
  c.nav(kit.nav, fn(page) { kit_page(c, page) }, bg=t.p.bg) |> ignore
}

///|
/// A page's bar: back (but on the first), its title, the next page.
fn kit_bar(c : @ui.Ctx, page : Int) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, h=Px(52.0), padx=12.0, gap=8.0, align=ACenter, fn() {
    if page > 0 {
      if @sf.icon_button(c, "chevron-left", key="back", icon_size=20.0) {
        kit.nav.pop() |> ignore
      }
    }
    c.text(
      if page == 0 { "富文本与页面" } else { "第 \{page + 1} 页" },
      size=t.t.title,
      weight=600,
      color=t.p.text,
      wrap=false,
      w=Fill(1.0),
    )
    |> ignore
    if @sf.button(c, "下一页", key="next", icon="arrow-right") {
      kit.nav.push(page + 1)
    }
  })
  |> ignore
  c.box(h=Px(1.0), bg=t.p.line, fn() {  }) |> ignore
}

///|
fn kit_page(c : @ui.Ctx, page : Int) -> Unit {
  c.column(w=Fill(1.0), h=Fill(1.0), fn() {
    kit_bar(c, page)
    if page == 0 {
      c.list("kit", 3 + 30, 120.0, fn(i) { kit_row(c, i) }) |> ignore
    } else {
      c.list("rows", 60, 56.0, fn(i) { page_row(c, page, i) }) |> ignore
    }
  })
  |> ignore
}

///|
fn section(c : @ui.Ctx, title : String) -> Unit {
  let t = @sf.theme()
  c.box(pl=20.0, pt=20.0, pb=8.0, fn() {
    c.text(title, size=t.t.meta, weight=600, color=t.p.muted, wrap=false) |> ignore
  })
  |> ignore
}

///|
fn kit_row(c : @ui.Ctx, i : Int) -> Unit {
  let t = @sf.theme()
  let p = t.p
  if i == 0 {
    section(c, "一段富文本")
    c.box(padx=16.0, fn() {
      @sf.card(c, gap=10.0, fn() {
        c.rich(
          [
            @ui.plain("这一段把几种样式放进同一段里："),
            @ui.bold("粗体"),
            @ui.plain("、"),
            @ui.italic("斜体 italic"),
            @ui.plain("、"),
            @ui.code("inline code"),
            @ui.plain("、"),
            @ui.strike("删掉的字"),
            @ui.plain("，还有一个"),
            @ui.link("可以点的链接", "https://example.com/kit"),
            @ui.plain("。中文和 English words 混在一起时，在 runs 之间也按 UAX #14 换行，标点不落在行首。"),
          ],
          size=t.t.body,
          line=t.t.body * 1.65,
          color=p.text,
          link_color=p.blue,
          pressed_bg=@sf.alpha(p.blue, 0.14),
          code_color=p.code_ink,
          code_bg=@sf.alpha(p.text, 0.07),
          on_link=fn(href) { kit.went = href },
        )
        |> ignore
        c.text(
          if kit.went == "" { "点一下链接试试" } else { "点过：" + kit.went },
          size=t.t.meta,
          color=p.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
  } else if i == 1 {
    section(c, "一条 Markdown 消息")
    c.box(padx=20.0, gap=6.0, fn() {
      c.row(gap=8.0, fn() {
        c.box(
          w=Px(24.0),
          h=Px(24.0),
          radius=8.0,
          bg=p.accent_bg,
          align=ACenter,
          justify=JCenter,
          fn() {
            c.text("令", size=12.0, weight=600, color=p.accent_text, wrap=false)
            |> ignore
          },
        )
        |> ignore
        c.text("助手", size=t.t.ui, weight=600, color=p.text, wrap=false) |> ignore
        c.text("刚刚", size=t.t.caption, color=p.muted, wrap=false) |> ignore
      })
      |> ignore
      @sf.markdown(c, kit_message, on_link=fn(href) { kit.went = href }) |> ignore
    })
    |> ignore
  } else if i == 2 {
    section(c, "下面的行用来试滚动：推一页再回来，还在这里")
  } else {
    c.box(padx=20.0, pady=12.0, fn() {
      c.rich(
        [@ui.bold("第 \{i - 2} 行"), @ui.plain(" · 一行普通的字，用来把列表撑长。")],
        size=t.t.ui,
        color=p.text,
        wrap=false,
      )
      |> ignore
    })
    |> ignore
  }
}

///|
fn page_row(c : @ui.Ctx, page : Int, i : Int) -> Unit {
  let t = @sf.theme()
  c.box(padx=16.0, pady=4.0, fn() {
    c.box(padx=16.0, pady=12.0, bg=t.p.card, radius=@sf.row_corner, fn() {
      c.rich(
        [
          @ui.bold("第 \{page + 1} 页"),
          @ui.plain("的第 \{i + 1} 行，"),
          @ui.italic("从左边缘向右滑"),
          @ui.plain("可以回到上一页。"),
        ],
        size=t.t.ui,
        color=t.p.text,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}
