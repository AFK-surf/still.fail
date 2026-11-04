// What a message places that draws itself (viz_page.mbt's viz_file_of, viz_mermaid.mbt's viz_mermaid_block) as nodes of
// the window's tree, made once: its place breathing while it comes, the ways under it to open it on its own; a
// visualization's page itself the host's (a web view: an old view hosting it, the island its page is drawn in), a
// mermaid chart a picture of its SVG.

///|
/// A way under what a message places (viz_icon's) in `parent`: `icon` 14 in a 22 square, `subtle`'s ink, round as the
/// theme's Md; read out a button named `label`, `press` told it pressed.
pub fn viz_way_node(parent : @view.View, icon : String, label : () -> String, subtle : () -> Int64, press : () -> Unit) -> @view.View {
  parent.box(fn(b) {
    b
    .width(Is(Some(viz_way_px)))
    .height(Is(Some(viz_way_px)))
    .radius(By(fn() { @ui.tree_theme().corner(Md) }))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() { if b.pressed() { @ui.tree_theme().color(Hover) } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    |> ignore
    @sf.presses_node(b, press)
    @sf.icon_node(b, icon, 14.0, By(subtle)) |> ignore
  })
}

///|
/// viz_way's side, 22.
let viz_way_px : Double = 22.0

///|
/// The ways under what a message places (viz_ways'): 2 under it, 22 high, at its end, 2 apart; `ways` makes them.
pub fn viz_ways_node(parent : @view.View, ways : (@view.View) -> Unit) -> Unit {
  parent.box(fn(w) {
    w.row(Is(true)).gap(Is(2.0)).padding(Is((0.0, 2.0, 0.0, 0.0))).lies_along(Is(End)) |> ignore
    ways(w)
  })
  |> ignore
}

///|
/// The place of what draws itself while it comes (viz_wait's) in `parent`: as wide as it is given, `h` high, round as
/// the theme's Xl, in the line's grey, breathing.
pub fn viz_wait_node(parent : @view.View, h : Double) -> Unit {
  parent.box(fn(w) {
    w
    .height(Is(Some(h)))
    .radius(By(fn() { @ui.tree_theme().corner(Xl) }))
    .ground(By(fn() { @ui.tree_theme().color(Line) }))
    |> ignore
    @sf.breathe_node(w) |> ignore
  })
  |> ignore
}

///|
/// The visualization a message of chat `session` on `station` places (viz_file_of's), kept by session `key`, in
/// `parent`: its place breathing while it comes, 8 under it; one that cannot be read as `failed` draws it; come, its
/// page (the host's, an island: viz_frame) and under it the ways to open it over the whole screen or aside, in
/// `subtle`, 4 under them.
pub fn viz_file_node(
  parent : @view.View,
  src : Source,
  station : () -> String,
  session : () -> String,
  key : () -> String,
  ts : () -> String,
  a : () -> Attachment,
  failed : (@view.View) -> Unit,
  subtle : () -> Int64,
) -> Unit {
  let l = @signals.untracked(fn() { viz_asked(src, station(), key(), a().path, size=a().size) })
  parent.pick(fn() {
    match l.result() {
      None => 0
      Some(Err(_)) => 1
      Some(Ok(_)) => 2
    }
  }, fn(v, which) {
    match which {
      0 => {
        v.padding(Is((0.0, 0.0, 0.0, 8.0))) |> ignore
        viz_wait_node(v, @sf.viz_wait_h_px)
      }
      1 => failed(v)
      _ => {
        v.padding(Is((0.0, 0.0, 0.0, 4.0))) |> ignore
        let place = fn() { "chat/" + station() + ":" + session() + "/" + ts() + "/" + a().path }
        // (the page the host's: drawn by viz_frame in an island of its own, as wide as the column)
        @ui.old(v, fn(c) {
          match l.result() {
            Some(Ok((html, state))) => {
              let st = station()
              let ses = session()
              let k = key()
              let path = a().path
              viz_frame(c, place(), html, state, {
                keep: Some(fn(s) { viz_keep(src, st, k, path, s) }),
                failed: None,
                follow_up: Some(viz_follow_up(st, ses)),
              })
            }
            _ => ()
          }
        }, natural=true)
        |> ignore
        viz_ways_node(v, fn(w) {
          viz_way_node(w, "expand", fn() { viz_tr("android-misc.viz.fullscreen") }, subtle, fn() {
            viz_open_full(a().name, station(), key(), a().path, session())
          })
          |> ignore
          viz_way_node(w, "panel-open", fn() { viz_tr("android-misc.viz.openAside") }, subtle, fn() {
            open_page(PreviewFile(station(), key(), a().path, a().name))
          })
          |> ignore
        })
      }
    }
  })
}

///|
/// A ```mermaid block (viz_mermaid_block's) in `parent`, its `code` as it is: its chart a picture of the SVG the core
/// makes, as wide as it is written or the column's where that is less, in its proportions, the way under it to open it
/// over the whole screen in `subtle`; while the core makes it, its place breathing as a page's; refused, its code.
pub fn viz_mermaid_node(
  parent : @view.View,
  src : Source,
  station : () -> String,
  code : () -> String,
  subtle : () -> Int64,
) -> Unit {
  let ask = fn() { mermaid_ask(code(), mermaid_filling) }
  let chart = fn() {
    mermaid_made.get() |> ignore
    mermaid_charts.get(ask().stringify())
  }
  // (asked of the core as it is made and as its code changes: once for each chart)
  parent.reacts(fn() { ask() }, fn(now) {
    let key = now.stringify()
    if mermaid_charts.get(key) is None {
      mermaid_charts[key] = ChartComing
      mermaid_asked(src, key, now)
    }
  })
  parent.pick(fn() {
    match chart() {
      Some(ChartRefused) => 1
      Some(ChartMade(_, _, _, _)) => 2
      _ => 0
    }
  }, fn(v, which) {
    match which {
      1 => @sf.code_block_node(v, code, fn() { "mermaid" }, fn() { None })
      2 => {
        let made = fn() {
          match chart() {
            Some(ChartMade(svg, picture, w, h)) => (svg, picture, w, h)
            _ => (b"", "", 1.0, 1.0)
          }
        }
        v.box(fn(p) {
          p
          .max_width(By(fn() { Some(made().2) }))
          .aspect(By(fn() { made().2 / made().3 }))
          .image(By(fn() { Some((made().1, "", 8192)) }))
          |> ignore
        })
        |> ignore
        viz_ways_node(v, fn(w) {
          viz_way_node(w, "expand", fn() { viz_tr("android-misc.viz.fullscreen") }, subtle, fn() {
            let (svg, _, cw, ch) = made()
            mermaid_open(station(), svg, cw, ch)
          })
          |> ignore
        })
      }
      _ => viz_wait_node(v, viz_first_height.to_double())
    }
  })
}
