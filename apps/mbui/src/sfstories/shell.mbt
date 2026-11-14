// The page round the parts, as component libraries' sites are (Storybook, shadcn/ui, Ant Design, Primer): the list of
// them at the side (by group, with a search over it), an overview of all of them as cards, and a part's page: what it
// is, its Playground (its arguments changed by controls, the call they make written under it), each of its states in a
// card with the lines that make it, and its functions as the library declares them. Light or dark and the width the
// parts are shown at over it. In a narrow window the list is a sheet a button in the bar opens.

///|
/// A part, as the list names it and the page shows it: its key (?STORY=), its group, its name, the file it is in under
/// src/sf, what it is, its functions (their file under src/sf, their name), its Playground, and its states, each what
/// it is said to show and how it is made in the card given.
struct Story {
  key : String
  group : String
  name : String
  file : String
  about : String
  api : Array[(String, String)]
  play : (() -> Play)?
  cases : Array[(String, (@view.View) -> Unit)]
}

///|
/// The width the parts are shown at: 小屏's, a page's at 中屏, or all of what is left of the window.
let widths : Array[(String, Double?)] = [("390", Some(390.0)), ("768", Some(768.0)), ("全宽", None)]

///|
/// Whether a window this wide shows the list at its side (else a sheet the bar's button opens).
fn side_shown(w : Double) -> Bool {
  w >= 720.0
}

///|
/// What is shown: the overview of all the parts (-1), or a part, by its place in the list.
fn stories_tree(root : @view.View) -> Unit {
  // (the library's words, the app's catalog's: what its parts say themselves, 取消 and the like)
  @sf.set_words(@sfbase.fill)
  @ui.set_tree_theme(@sf.ui_theme_now)
  let all = stories(@sf.TipLayer::new(fn() { Some(root) }))
  let first = @ui.env("STORY")
  let chosen = @signals.signal(all.search_by(fn(s) { s.key == first }).unwrap_or(-1))
  let width = @signals.signal(2)
  let query = @signals.signal("")
  let wide = fn() { side_shown(root.window().0) }
  // (the list's width; what is left of the window the parts', said as a width so that what shares its room by it (a
  // filled segmented) is given that room, not what it holds)
  let side_w = fn() { if wide() { 248.0 } else { 0.0 } }
  let main_w = fn() { Some(@sf.dmax(0.0, root.window().0 - side_w())) }
  // (what is drawn under it all: the root's own ground is the host's)
  root.box(fn(page) {
    page.grow(Is(1.0)).row(Is(true)).ground(By(fn() { @sf.theme().p.bg })) |> ignore
    page.show(wide, at_once=true, fn(side) { side_node(side, all, chosen, query) })
    page.box(fn(main) {
      main.width(By(main_w)) |> ignore
      bar_node(main, all, chosen, width, query, wide)
      main.box(fn(held) {
        held.grow(Is(1.0)).min_height(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        held.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(col) {
          col.width(By(main_w)) |> ignore
          col.pick(fn() { chosen.get() }, at_once=true, fn(at, i) {
            if i < 0 {
              overview_node(at, all, chosen)
            } else {
              story_node(at, all[i], fn() { widths[width.get()].1 })
            }
          })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  @sf.presented_nodes(root)
  @sfbase.toasts_node(root, fn() { 24.0 }) |> ignore
}

///|
/// Whether part `s` is one `query` finds: its name, key, group or file holding it, case aside.
fn found(s : Story, query : String) -> Bool {
  let q = query.trim(chars=" ").to_lower()
  q == "" || [s.name, s.key, s.group, s.file].iter().any(fn(w) { w.to_lower().contains(q) })
}

///|
/// The rows of the list: 总览, then each group's name over its parts `query` finds; `picked` told the one pressed.
fn list_rows(
  list : @view.View,
  all : Array[Story],
  chosen : @signals.Signal[Int],
  query : @signals.Signal[String],
  picked : () -> Unit,
) -> Unit {
  // (a row a key: -1 the overview, a part its place in the list, a group's name -2 less the place of its first part)
  let keys = fn() {
    let q = query.get()
    let out = [-1]
    let mut group = ""
    for i, s in all {
      if found(s, q) {
        if s.group != group {
          group = s.group
          out.push(-2 - i)
        }
        out.push(i)
      }
    }
    out
  }
  list.each(keys, fn(k) { k }, at_once=true, fn(row, k) {
    let key = k.untracked()
    if key == -1 {
      @sf.choice_row_node(
        row,
        fn() { "总览" },
        fn() { chosen.get() < 0 },
        press=fn() {
          chosen.set(-1)
          picked()
        },
        compact=true,
      )
    } else if key < -1 {
      let named = all[-2 - key].group
      row.box(fn(h) {
        h.padding(Is((12.0, 14.0, 12.0, 4.0))) |> ignore
        @sf.words_node(h, fn() { named }, fn() { @sf.caption }) |> ignore
      })
      |> ignore
    } else {
      let i = key
      @sf.choice_row_node(
        row,
        fn() { all[i].name },
        fn() { chosen.get() == i },
        press=fn() {
          chosen.set(i)
          picked()
        },
        compact=true,
      )
    }
  })
}

///|
/// The search over the list.
fn search_node(v : @view.View, query : @signals.Signal[String]) -> Unit {
  @sf.input_node(
    v,
    @ui.Field::new(text=@signals.untracked(fn() { query.get() })),
    placeholder="搜索组件",
    small=true,
    edited=fn(t) { query.set(t) },
  )
  |> ignore
}

///|
/// The list at the side: the library's name, the search, the rows.
fn side_node(side : @view.View, all : Array[Story], chosen : @signals.Signal[Int], query : @signals.Signal[String]) -> Unit {
  side.width(Is(Some(248.0))).ground(By(fn() { @sf.theme().p.sidebar })) |> ignore
  side.box(fn(head) {
    head.padding(Is((20.0, 20.0, 20.0, 8.0))).gap(Is(4.0)) |> ignore
    @sf.words_node(head, fn() { "still.fail 组件" }, fn() { @sf.title }) |> ignore
    @sf.words_node(head, fn() { "apps/mbui/src/sf · \{all.length()} 个" }, fn() { @sf.meta }) |> ignore
  })
  |> ignore
  side.box(fn(s) {
    s.padding(Is((16.0, 4.0, 16.0, 8.0))) |> ignore
    search_node(s, query)
  })
  |> ignore
  side.box(fn(held) {
    held.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    held.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(list) {
      list.padding(Is((8.0, 0.0, 8.0, 24.0))) |> ignore
      list_rows(list, all, chosen, query, fn() {  })
    })
    |> ignore
  })
  |> ignore
}

///|
/// The bar over what is shown: in a narrow window the button that opens the list; its name and file; the width the
/// parts are shown at (where the window has the room for it to mean anything); light or dark.
fn bar_node(
  main : @view.View,
  all : Array[Story],
  chosen : @signals.Signal[Int],
  width : @signals.Signal[Int],
  query : @signals.Signal[String],
  wide : () -> Bool,
) -> Unit {
  main.box(fn(bar) {
    bar
    .row(Is(true))
    .gap(Is(12.0))
    .padding(By(fn() { if wide() { (24.0, 14.0, 24.0, 14.0) } else { (8.0, 8.0, 12.0, 8.0) } }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    bar.show(fn() { !wide() }, at_once=true, fn(b) {
      @sf.icon_button_opens_node(b, "list", fn() { "组件" }, fn(opener) {
        @sf.panel_nodes(
          "组件",
          fn(body, close) {
            search_node(body, query)
            body.box(fn(list) { list_rows(list, all, chosen, query, close) }) |> ignore
          },
          from=@sf.Anchor::Node(opener),
        )
      })
      |> ignore
    })
    bar.box(fn(name) {
      name.grow(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
      @sf.words_node(
        name,
        fn() {
          let i = chosen.get()
          if i < 0 {
            "总览"
          } else {
            all[i].name
          }
        },
        fn() { @sf.desk_strong },
      )
      |> ignore
      @sf.words_node(
        name,
        fn() {
          let i = chosen.get()
          if i < 0 {
            "\{all.length()} 个部件"
          } else {
            "src/sf/" + all[i].file
          }
        },
        fn() { @sf.meta },
      )
      |> ignore
    })
    |> ignore
    bar.show(wide, at_once=true, fn(w) {
      @sf.seg_node(w, fn() { widths.map(fn(w) { w.0 }) }, fn() { width.get() }, fn(i) { width.set(i) }, said="宽度") |> ignore
    })
    @sf.icon_button_node(
      bar,
      "moon",
      fn() { if @sf.theme().dark { "浅色" } else { "深色" } },
      fn() { @sf.set_dark(Some(!@signals.untracked(fn() { @sf.theme().dark }))) },
      icon_now=fn() { if @sf.theme().dark { "sun" } else { "moon" } },
    )
    |> ignore
  })
  |> ignore
  main.box(fn(rule) { rule.height(Is(Some(1.0))).ground(By(fn() { @sf.theme().p.line })) |> ignore }) |> ignore
}

///|
/// A box in which what is made shows and takes nothing (a thumbnail of a part).
fn still_box(v : @view.View, make : (@view.View) -> Unit) -> Unit {
  v.box(fn(b) {
    b.in_use(Is(false)) |> ignore
    make(b)
  })
  |> ignore
}

///|
/// All the parts as cards, each its name, its group and its first state drawn small; pressed, its page.
fn overview_node(page : @view.View, all : Array[Story], chosen : @signals.Signal[Int]) -> Unit {
  let narrow = fn() { page.window().0 < 720.0 }
  page.padding(By(fn() { if narrow() { (16.0, 16.0, 16.0, 48.0) } else { (24.0, 24.0, 24.0, 48.0) } })).gap(Is(16.0))
  |> ignore
  @sf.words_node(
    page,
    fn() { "still.fail 的界面都由这些部件拼成（apps/mbui/src/sf）。每个部件一页：它的各种状态、可调参数的 Playground、示例代码和 API。" },
    fn() { @sf.lead },
  )
  |> ignore
  page.box(fn(grid) {
    grid.row(Is(true)).wraps(Is(Some(16.0))).gap(Is(16.0)) |> ignore
    for i, s in all {
      grid.box(fn(card) {
        card
        .basis(Is(Some(260.0)))
        .grow(Is(1.0))
        .min_width(Is(Some(0.0)))
        .ground(By(fn() { @sf.theme().p.paper }))
        .edge(By(fn() { (1.0, @sf.theme().p.line) }))
        .radius(Is(12.0))
        .clips(Is(true))
        .cursor(Is(Some(Hand)))
        .says(Is(Some(@view.said(Button, label=s.name))))
        .on_press(fn() { chosen.set(i) })
        |> ignore
        card.box(fn(thumb) {
          thumb.height(Is(Some(132.0))).pad(Is(16.0)).clips(Is(true)) |> ignore
          match s.cases.get(0) {
            Some((_, make)) => still_box(thumb, make)
            None => ()
          }
        })
        |> ignore
        card.box(fn(r) { r.height(Is(Some(1.0))).ground(By(fn() { @sf.theme().p.line })) |> ignore }) |> ignore
        card.box(fn(foot) {
          foot.padding(Is((16.0, 10.0, 16.0, 12.0))).gap(Is(2.0)) |> ignore
          @sf.words_node(foot, fn() { s.name }, fn() { @sf.desk_strong }) |> ignore
          @sf.words_node(foot, fn() { s.group + " · " + s.file }, fn() { @sf.meta }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A card on the page's ground: `make` in it.
fn card_node(v : @view.View, make : (@view.View) -> Unit) -> Unit {
  v.box(fn(card) {
    card
    .ground(By(fn() { @sf.theme().p.paper }))
    .edge(By(fn() { (1.0, @sf.theme().p.line) }))
    .radius(Is(12.0))
    .pad(By(fn() { if card.window().0 < 720.0 { 14.0 } else { 20.0 } }))
    .gap(Is(12.0))
    .min_width(Is(Some(0.0)))
    |> ignore
    make(card)
  })
  |> ignore
}

///|
/// A heading of a part's page.
fn heading_node(v : @view.View, words : String) -> Unit {
  v.box(fn(h) {
    h.padding(Is((0.0, 12.0, 0.0, 0.0))) |> ignore
    @sf.words_node(h, fn() { words }, fn() { @sf.wide_heading }) |> ignore
  })
  |> ignore
}

///|
/// Code as a block with its copy key.
fn code_node(v : @view.View, code : () -> String) -> Unit {
  @sf.code_block_node(v, code, fn() { "moonbit" }, fn() { None })
}

///|
/// A part's page: what it is; its Playground; each of its states in a card under what it shows, the lines that make it
/// a press away; its functions. As wide as `width` says at most.
fn story_node(page : @view.View, s : Story, width : () -> Double?) -> Unit {
  page
  .padding(By(fn() { if page.window().0 < 720.0 { (16.0, 16.0, 16.0, 48.0) } else { (24.0, 20.0, 24.0, 48.0) } }))
  .gap(Is(16.0))
  .min_width(Is(Some(0.0)))
  |> ignore
  @sf.words_node(page, fn() { s.about }, fn() { @sf.lead }) |> ignore
  match s.play {
    Some(make) => {
      let play = make()
      heading_node(page, "Playground")
      page.box(fn(at) {
        at.max_width(By(width)).min_width(Is(Some(0.0))).gap(Is(8.0)) |> ignore
        card_node(at, fn(card) {
          card.box(fn(shown) {
            shown.min_height(Is(Some(64.0))).lines_up(Is(Some(Start))).padding(Is((0.0, 4.0, 0.0, 12.0))) |> ignore
            (play.preview)(shown)
          })
          |> ignore
          card.box(fn(r) { r.height(Is(Some(1.0))).ground(By(fn() { @sf.theme().p.line })) |> ignore }) |> ignore
          (play.controls)(card)
        })
        code_node(at, play.code)
      })
      |> ignore
    }
    None => ()
  }
  heading_node(page, "示例")
  for c in s.cases {
    let (label, make) = c
    let code = case_code(label)
    let open = @signals.signal(false)
    page.box(fn(case) {
      case.gap(Is(8.0)).max_width(By(width)).min_width(Is(Some(0.0))) |> ignore
      case.box(fn(head) {
        head.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(8.0)) |> ignore
        head.box(fn(l) {
          l.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          @sf.words_node(l, fn() { label }, fn() { @sf.caption }) |> ignore
        })
        |> ignore
        if code != "" {
          @sf.link_node(head, fn() { if open.get() { "收起代码" } else { "代码" } }, fn() { open.set(!open.get()) }, icon="file-code")
          |> ignore
        }
      })
      |> ignore
      card_node(case, make)
      case.show(fn() { open.get() }, fn(c) { code_node(c, fn() { code }) })
    })
    |> ignore
  }
  let apis = s.api.map(fn(a) { api_of(a.0, a.1) }).filter(fn(a) { a != "" })
  if !apis.is_empty() {
    heading_node(page, "API")
    page.box(fn(at) {
      at.max_width(By(width)).min_width(Is(Some(0.0))).gap(Is(12.0)) |> ignore
      for a in apis {
        code_node(at, fn() { a })
      }
    })
    |> ignore
  }
}
