// The bar floating at the top of a file opened in the Small tier (viewer_head's, fpHead) as nodes of the window's tree
// (the way there, docs/retained.md 4): what it shows bound to what says it as that changes (the file's name, its kind
// and size, the window's width, its theme, how far the viewer is in), its tools nodes of their own (tool_node), never
// narrower once open: how wide it was laid out is kept as what it holds changes (another tool, another name, another
// width), at that change.

///|
/// The floating bar in `parent` (a layer over the viewer's, all of its room): page glass (`glass`, as the theme says),
/// round, 44 high, the room's top (`top`) or 8 down (16 over 640: `width`, the window's), 16 in from the window's sides
/// at most (32 over 640) and 1080 wide at most; `name` first (`meta` after it over 640), cut short before the tools give
/// way, then what `tools` makes in the row of tools it is given (`holds`: which they are, as
/// that changes), then × (`close` as it is pressed). There while `awake`
/// (in over wake_ms, out over sleep_ms, from where it is at that moment), as far in as `shown` says of the node as it is
/// drawn (the viewer's fade). Its tools' tips in `tips`. The bar's node.
pub fn viewer_head_node(
  parent : @view.View,
  name : () -> String,
  meta : () -> String,
  awake : () -> Bool,
  shown : (@view.View) -> Double,
  top : () -> Double,
  width : () -> Double,
  ink : () -> ViewerInk,
  glass : () -> @ui.Glass,
  tools : (@view.View) -> Unit,
  holds : () -> String,
  close : () -> Unit,
  tips? : TipLayer,
) -> @view.View {
  let small = fn() { width() <= viewer_small_w }
  let fade = TipFade::new()
  let mut head : @view.View? = None
  parent.box(fn(room) {
    room.over(Is(true)).lines_up(Is(Some(Middle))) |> ignore
    // (awake as it is made: in whole, not come in)
    let woke = @signals.untracked(awake)
    fade.from = if woke { 1.0 } else { 0.0 }
    fade.to = fade.from
    room.reacts(awake, fn(on) {
      let at = room.cause_at()
      if on != (fade.to > 0.5) {
        fade.go(room, if on { 1.0 } else { 0.0 }, at, if on { wake_ms } else { sleep_ms }, Out)
      }
    })
    room.alpha(By(fn() { fade.shown(room) * shown(room) })) |> ignore
    room.box(fn(down) {
      down.height(By(fn() { Some(dmax(top(), if small() { vfr_head_top_small } else { vfr_head_top })) })) |> ignore
    })
    |> ignore
    // (the widest it was laid out at, as what it holds last changed: it grows to what it holds, never back)
    let widest : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
    let most = fn() { dmin(width() - (if small() { vfr_head_side_small } else { vfr_head_side }), vfr_head_most) }
    let h = room.box(fn(h) {
      h
      .row(Is(true))
      .lines_up(Is(Some(Middle)))
      .height(Is(Some(@ui.Space::px(S11))))
      .gap(By(fn() { @ui.Space::px(if small() { S1 } else { S3 }) }))
      .padding(By(fn() {
        let start = @ui.Space::px(if small() { S3 } else { S4 })
        (start, 0.0, @ui.Space::px(S1_5), 0.0)
      }))
      .radius(Is(@ui.Space::px(S11) / 2.0))
      .glass(By(fn() { Some(glass()) }))
      .max_width(By(fn() { Some(most()) }))
      .min_width(By(fn() { Some(dmin(widest.get(), most())) }))
      |> ignore
      // its name and meta (fpTitle): the name first, its line's meta 10 after it; what gives way short of room
      h.box(fn(title) {
        title
        .row(Is(true))
        .lines_up(Is(Some(End)))
        .gap(Is(@ui.Space::px(S2_5)))
        .padding(Is((0.0, 0.0, @ui.Space::px(S3), 0.0)))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
        title.box(fn(n) {
          n
          .words(By(name))
          .words_look(By(fn() {
            let (size, line) = @ui.tree_theme().text_size(Body)
            { size, weight: 600, line, wrap: false }
          }))
          .ink(By(fn() { @ui.tree_theme().color(Fg) }))
          // (read out whole, however much of it is drawn)
          .says(By(fn() { Some(@view.said(Text, label=name())) }))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          |> ignore
        })
        |> ignore
        title.show(fn() { !small() && meta() != "" }, fn(m) {
          m
          .words(By(meta))
          .words_look(By(fn() {
            let (size, line) = @ui.tree_theme().text_size(Meta)
            { size, weight: 400, line, wrap: false }
          }))
          .ink(By(fn() { @ui.tree_theme().color(Muted) }))
          .says(By(fn() { Some(@view.said(Text, label=meta())) }))
          |> ignore
        })
      })
      |> ignore
      h.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
      // (short of room, the tools kept whole: the name gives way)
      h.box(fn(row) {
        row.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(keys_apart())) |> ignore
        tools(row)
        tool_node(
          row,
          fn() { { icon: "close", label: t("web-main.preview.closeKey"), on: false, disabled: false } },
          ink,
          Is(tool_side / 2.0),
          close,
          tip?=tips,
        )
        |> ignore
      })
      |> ignore
    })
    head = Some(h)
    // (what it holds changed, how its words are set, or the room it is given (the window's, its first frame's too): as
    // wide as it is laid out then, kept)
    room.reacts(
      fn() {
        @ui.tree_theme() |> ignore
        (name(), meta(), holds(), small(), width(), room.window())
      },
      fn(_) {
        let (w, _) = h.laid_size()
        if w > @signals.untracked(fn() { widest.get() }) {
          widest.set(w)
        }
      },
    )
  })
  |> ignore
  head.unwrap()
}
