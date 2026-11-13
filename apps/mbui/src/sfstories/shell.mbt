// The page round the parts: the list of them at the side (by group), a bar over the one chosen (its name, where it is
// in src/sf, light or dark, the width it is shown at), and its states under it, each in a card with
// what it shows said over it.

///|
/// A part, as the list names it and the page shows it: its key (?STORY=), its group, its name, the file it is in under
/// src/sf, what it is, and its states, each what it is said to show and how it is made in the card given.
struct Story {
  key : String
  group : String
  name : String
  file : String
  about : String
  cases : Array[(String, (@view.View) -> Unit)]
}

///|
/// The width the parts are shown at: 小屏's, a page's at 中屏, or all of what is left of the window.
let widths : Array[(String, Double?)] = [("390", Some(390.0)), ("768", Some(768.0)), ("全宽", None)]

///|
fn stories_tree(root : @view.View) -> Unit {
  // (the library's words, the app's catalog's: what its parts say themselves, 取消 and the like)
  @sf.set_words(@sfbase.fill)
  @ui.set_tree_theme(@sf.ui_theme_now)
  let all = stories(@sf.TipLayer::new(fn() { Some(root) }))
  let first = @ui.env("STORY")
  let chosen = @signals.signal(all.search_by(fn(s) { s.key == first }).unwrap_or(0))
  let width = @signals.signal(2)
  // (the list's width, narrower in a phone's window, the parts keeping most of it; what is left of the window the parts',
  // said as a width so that what shares its room by it (a filled segmented) is given that room, not what it holds)
  let side_w = fn() { @sf.dmin(240.0, @sf.dmax(150.0, root.window().0 * 0.3)) }
  let main_w = fn() { Some(@sf.dmax(0.0, root.window().0 - side_w())) }
  // (what is drawn under it all: the root's own ground is the host's)
  root.box(fn(page) {
  page.grow(Is(1.0)).row(Is(true)).ground(By(fn() { @sf.theme().p.bg })) |> ignore
  side_node(page, all, chosen, side_w)
  page.box(fn(main) {
    main.width(By(main_w)) |> ignore
    bar_node(main, all, chosen, width)
    main.box(fn(held) {
      held.grow(Is(1.0)).min_height(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      held.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(col) {
        col.width(By(main_w)) |> ignore
        col.pick(fn() { chosen.get() }, at_once=true, fn(page, i) {
          story_node(page, all[i], fn() { widths[width.get()].1 })
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
/// The list at the side: each group's name over its parts, the one chosen marked.
fn side_node(root : @view.View, all : Array[Story], chosen : @signals.Signal[Int], side_w : () -> Double) -> Unit {
  root.box(fn(side) {
    side
    .width(By(fn() { Some(side_w()) }))
    .ground(By(fn() { @sf.theme().p.sidebar }))
    .edge(By(fn() { (0.0, 0L) }))
    |> ignore
    side.box(fn(head) {
      head.padding(Is((20.0, 20.0, 20.0, 12.0))).gap(Is(4.0)) |> ignore
      @sf.words_node(head, fn() { "still.fail 组件" }, fn() { @sf.title }) |> ignore
      @sf.words_node(head, fn() { "apps/mbui/src/sf · \{all.length()} 个" }, fn() { @sf.meta }) |> ignore
    })
    |> ignore
    side.box(fn(held) {
      held.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      held.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(list) {
        list.padding(Is((8.0, 0.0, 8.0, 24.0))) |> ignore
        let mut group = ""
        for i, s in all {
          if s.group != group {
            group = s.group
            let named = group
            list.box(fn(h) {
              h.padding(Is((12.0, 14.0, 12.0, 4.0))) |> ignore
              @sf.words_node(h, fn() { named }, fn() { @sf.caption }) |> ignore
            })
            |> ignore
          }
          @sf.choice_row_node(
            list,
            fn() { s.name },
            fn() { chosen.get() == i },
            press=fn() { chosen.set(i) },
            compact=true,
          )
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The bar over the part chosen: its name and file, then light or dark and the width.
fn bar_node(
  main : @view.View,
  all : Array[Story],
  chosen : @signals.Signal[Int],
  width : @signals.Signal[Int],
) -> Unit {
  main.box(fn(bar) {
    bar
    .row(Is(true))
    .wraps(Is(Some(8.0)))
    .gap(Is(12.0))
    .padding(Is((24.0, 14.0, 24.0, 14.0)))
    .lines_up(Is(Some(Middle)))
    .edge(Is((0.0, 0L)))
    |> ignore
    bar.box(fn(name) {
      name.grow(Is(1.0)).min_width(Is(Some(160.0))).gap(Is(2.0)) |> ignore
      @sf.words_node(name, fn() { all[chosen.get()].name }, fn() { @sf.desk_strong }) |> ignore
      @sf.words_node(name, fn() { "src/sf/" + all[chosen.get()].file }, fn() { @sf.meta }) |> ignore
    })
    |> ignore
    @sf.seg_node(
      bar,
      fn() { ["浅色", "深色"] },
      fn() { if @sf.theme().dark { 1 } else { 0 } },
      fn(i) { @sf.set_dark(Some(i == 1)) },
      said="主题",
    )
    |> ignore
    @sf.seg_node(bar, fn() { widths.map(fn(w) { w.0 }) }, fn() { width.get() }, fn(i) { width.set(i) }, said="宽度") |> ignore
  })
  |> ignore
}

///|
/// A part's page: what it is, then each of its states in a card under what it shows, as wide as `width` says at most.
fn story_node(page : @view.View, s : Story, width : () -> Double?) -> Unit {
  page.padding(By(fn() { if page.window().0 < 700.0 { (16.0, 16.0, 16.0, 48.0) } else { (24.0, 20.0, 24.0, 48.0) } })).gap(Is(20.0)).min_width(Is(Some(0.0))) |> ignore
  @sf.words_node(page, fn() { s.about }, fn() { @sf.lead }) |> ignore
  for c in s.cases {
    let (label, make) = c
    page.box(fn(case) {
      case.gap(Is(8.0)).max_width(By(width)).min_width(Is(Some(0.0))) |> ignore
      @sf.words_node(case, fn() { label }, fn() { @sf.caption }) |> ignore
      case.box(fn(card) {
        card
        .ground(By(fn() { @sf.theme().p.paper }))
        .edge(By(fn() { (1.0, @sf.theme().p.line) }))
        .radius(Is(12.0))
        .pad(By(fn() { if card.window().0 < 700.0 { 14.0 } else { 20.0 } }))
        .gap(Is(12.0))
        .min_width(Is(Some(0.0)))
        |> ignore
        make(card)
      })
      |> ignore
    })
    |> ignore
  }
}
