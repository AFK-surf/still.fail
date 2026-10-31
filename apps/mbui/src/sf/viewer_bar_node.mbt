// The bar across the top of a file opened over a wide window (viewer_bar's, ViewerBar.tsx) as nodes of the window's
// tree (the way there, docs/retained.md 4): what it says bound to what says it as that changes (the way back's words,
// the name, the line about it, where the file is, the window's width, the ink), its tools nodes of their own
// (tool_node), its way back and each tool done at the press's moment. Gone up out of the way (hidden: a picture left
// alone) from the moment it is told so, as far as that way has it by the moment each frame is drawn, whatever frames
// come between; taking no press while it goes or is gone.

///|
/// The bar across the top in `parent` (a layer over the viewer's, all of its room): the file's ground (`ink`) at 82%
/// over a 20 blur, saturated, 45 high under the room's top (`top`: a tablet's status bar, its ground on under it); the
/// way back first (`back`'s words after the chevron, `went` as it is pressed), clear of the window's buttons where they
/// are the system's at its left; `name` and `meta` under it in the middle, as wide as they are (the window's `width`
/// less 320 at most), where the file is (`title`, none: "") its tip while the pointer is over them; what `tools` makes in
/// the row at its end (the corner each is round at given: the window's followed at its corner, a bar's buttons'), the
/// last as far in from the window's side as a page's bar's last. There while `hidden` holds not (gone up its height and
/// faded over 240 ms, eased out, from where it is at the moment it is told, and back so; at once with motion
/// reduced), as far in as `shown` says of the node as it is drawn (the viewer's fade). A press on it where nothing of it
/// takes one is its own, moving the window while it has none of the system's title bar (the app's own top row). Its
/// tips in `tips`. The bar's node.
pub fn viewer_bar_node(
  parent : @view.View,
  back : () -> String,
  name : () -> String,
  meta : () -> String,
  title : () -> String,
  hidden : () -> Bool,
  shown : (@view.View) -> Double,
  top : () -> Double,
  width : () -> Double,
  ink : () -> ViewerInk,
  tools : (@view.View, @view.Live[Double]) -> Unit,
  went : () -> Unit,
  tips : TipLayer,
) -> @view.View {
  // (hidden as it is made: gone whole, not gone up; its way a motion's, there at once with motion reduced)
  let gone = EdgeWay::new(if @signals.untracked(hidden) { 1.0 } else { 0.0 })
  let mut bar : @view.View? = None
  parent.box(fn(room) {
    room.over(Is(true)) |> ignore
    room.reacts(hidden, fn(off) { gone.go(room, if off { 1.0 } else { 0.0 }, viewer_bar_ms) })
    let b = room.box(fn(b) {
      b
      .glass(By(fn() {
        let k = ink()
        Some(
          @ui.Glass::frosted(
            blur=viewer_bar_blur,
            tint=alpha(k.ground, viewer_bar_share),
            solid=k.ground,
            saturation=viewer_bar_saturation,
          ),
        )
      }))
      .alpha(By(fn() { (1.0 - gone.shown(b)) * shown(b) }))
      .offset(By(fn() { (0.0, -(viewer_bar_h + top()) * gone.shown(b)) }))
      // (gone or going, it takes no press: what is under it does)
      .presses(By(fn() { !hidden() }))
      |> ignore
      // (the app's own top row while the window has none of the system's: not full screen)
      b.moves_window(By(@ui.window_inset_now)) |> ignore
      // (its ground on under the status bar where the system's bars are over the window: a tablet's)
      b.box(fn(s) { s.height(By(fn() { Some(top()) })) |> ignore }) |> ignore
      b.box(fn(row) {
        row
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .height(Is(Some(viewer_bar_h)))
        .gap(Is(@ui.Space::px(S4)))
        .padding(By(fn() { (bar_start_in(), 0.0, bar_end_in(width()), hairline_h) }))
        |> ignore
        // clear of the window's buttons at its left, the system's (ViewerBar.css.ts: 84 in, not in full screen)
        row.show(@ui.window_keys_left_now, fn(k) { k.width(Is(Some(viewer_buttons_w))) |> ignore })
        // the way back, at its start; short of room, its words give way, the chevron stays
        row.box(fn(start) {
          // (as wide as the tools' side, whatever each holds: the middle in the window's middle, viewer_bar's grow)
          start
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .basis(Is(Some(0.0)))
          .grow(Is(1.0))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          |> ignore
          back_node(start, back, ink, went) |> ignore
        })
        |> ignore
        // the middle, as wide as what it says, the sides kept for the way back and the tools
        let middle = row.box(fn(m) {
          m
          .lines_up(Is(Some(Middle)))
          .max_width(By(fn() { Some(dmax(viewer_none, width() - viewer_bar_sides)) }))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          |> ignore
          m.box(fn(n) {
            n
            .words(By(name))
            .words_look(By(fn() { bar_words(Ui, L6, 600) }))
            .ink(By(fn() { ink().ink }))
            .says(By(fn() { Some(@view.said(Text, label=name())) }))
            |> ignore
          })
          |> ignore
          m.show(fn() { meta() != "" }, fn(l) {
            l
            .words(By(meta))
            .words_look(By(fn() { bar_words(Caption, L4, 400) }))
            .ink(By(fn() { ink().muted }))
            .says(By(fn() { Some(@view.said(Text, label=meta())) }))
            |> ignore
          })
        })
        // (where the file is, over its name while the pointer is there)
        tip_node(tips, middle, title, within=true) |> ignore
        // (short of room, the tools kept whole: the way back and the name give way)
        row.box(fn(end) {
          // (its tools kept whole, the way back and the name giving way first: viewer_bar's keep)
          end.row(Is(true)).lines_up(Is(Some(Middle))).basis(Is(Some(0.0))).grow(Is(1.0)).keeps_held(Is(true)) |> ignore
          // (at its end, nothing before them but what is left: viewer_bar_end's justify end, no gap of their own)
          end.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
          end.box(fn(r) {
            r.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(keys_apart())) |> ignore
            tools(r, bar_tool_corner())
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    bar = Some(b)
  })
  |> ignore
  bar.unwrap()
}

///|
/// How far in from the window's side the bar's last tool stands, the window `w` wide (viewer_bar's end): clear of the
/// window's buttons where they are the app's; else at the window's corner as a page's bar's last is (window_end_in), as
/// the window's corner is now for the window's tree, followed.
fn bar_end_in(w : Double) -> Double {
  let roots = @ui.tree_corner_roots_now()
  if @ui.window_keys_own_now() {
    window_keys_room_at(w) + viewer_bar_in
  } else {
    window_end_in(viewer_bar_in, roots~)
  }
}

///|
/// How far in from the window's left the bar's way back stands (viewer_bar's start): at the window's corner where nothing
/// of the system's is there (viewer_bar_start_in, the theme's Xl where it cannot follow it), as the window's corner is now
/// for the window's tree, followed; 12 after the system's buttons.
fn bar_start_in() -> Double {
  if @ui.window_keys_left_now() {
    viewer_bar_in
  } else {
    viewer_bar_start_in(@ui.tree_theme().corner(Xl), @ui.tree_corner_roots_now())
  }
}

///|
/// The corner of the bar's way back (viewer_bar's): the window's followed at its top left corner (viewer_back_corner) as
/// the window's corner is now for the window's tree; the theme's Xl after the system's buttons, or where it cannot.
fn bar_back_corner() -> Double {
  let alone = @ui.tree_theme().corner(Xl)
  if @ui.window_keys_left_now() {
    alone
  } else {
    viewer_back_corner(alone).radius(@ui.tree_corner_roots_now())
  }
}

///|
/// The corner of the bar's tools (viewer_tool_corner's, for the bar across the top): the one a page's bar's buttons
/// share at the window's corner (bar_keys_link: window_corner_key), followed as the window's corner changes and as its
/// own buttons come to be the app's or not (full screen); round where they are the app's.
fn bar_tool_corner() -> @view.Live[Double] {
  By(fn() {
    if @ui.window_keys_own_now() {
      tool_side / 2.0
    } else {
      window_corner_key().radius(@ui.tree_corner_roots_now())
    }
  })
}

///|
/// Words in the bar as viewer_bar sets them: the theme's `size`, `line` a line, `weight`, on one line.
fn bar_words(size : @ui.TextSize, line : @ui.Leading, weight : Int) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  { size: px, weight, line: th.leading(line).unwrap_or(own), wrap: false }
}

///|
/// The way back (viewer_bar's: ViewerBar.css.ts back) in `parent`: 32 high, 4 before the chevron and 10 after the words,
/// at the window's corner following it (bar_back_corner); the chevron and `words` in the ink's own, its hover ground
/// where the hand is on it (or the keyboard's focus shows); `went` as it is pressed, at the press's moment. Read out a
/// button, by its words.
fn back_node(parent : @view.View, words : () -> String, ink : () -> ViewerInk, went : () -> Unit) -> @view.View {
  parent.box(fn(v) {
    let lit = fn() {
      v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed()
        Finger => v.pressed()
      })
    }
    v
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .height(Is(Some(@ui.Space::px(S8))))
    .padding(Is((@ui.Space::px(S1), 0.0, @ui.Space::px(S2_5), 0.0)))
    .gap(Is(@ui.Space::px(S0_5)))
    .radius(By(bar_back_corner))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    .presses(Is(true))
    .focusable(Is(true))
    .ground(By(fn() { if lit() { ink().hover } else { 0L } }))
    .says(By(fn() { Some(@view.said(Button, label=words())) }))
    .on_press(went)
    |> ignore
    v.box(fn(i) {
      i
      .width(Is(Some(viewer_back_icon)))
      .height(Is(Some(viewer_back_icon)))
      .shapes(Is(back_shapes()))
      .drawn_as(Is("/icon/chevron-left/"))
      .tint(By(fn() { ink().ink }))
      |> ignore
    })
    |> ignore
    v.box(fn(w) {
      w
      .words(By(words))
      .words_look(By(fn() { bar_words(Ui, L6, 400) }))
      .ink(By(fn() { ink().ink }))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
  })
}

///|
/// The chevron of the way back, viewer_back_icon across, in no colour of its own (the node's tint).
fn back_shapes() -> Array[@ui.Shape] {
  match icon_numbers("chevron-left") {
    Some(d) => icon_shapes(d, viewer_back_icon / 24.0, 0x000000FFL)
    None => []
  }
}

///|
/// How much of a file opened has come, in the bar across the top beside its tools, as nodes (viewer_coming's,
/// FilePreview.tsx FileComing inBar): "正在读取 **1.2 MB** / 3.4 MB" in the meta's size in the ink's quieter colour, the
/// size so far in bold in its own, then a progress bar 120 wide (progress_node); before the core has said how much and
/// with no size it was sent with, 正在打开 over a bar that sweeps. `got`: what has come and its whole size; `size`: the
/// size it was sent with. Each as it changes. The row's node.
pub fn viewer_coming_node(
  parent : @view.View,
  got : () -> (Double, Double?)?,
  size : () -> Double,
  ink : () -> ViewerInk,
) -> @view.View {
  let total = fn() -> Double? {
    match got() {
      Some((_, Some(n))) if n > 0.0 => Some(n)
      _ => if size() > 0.0 { Some(size()) } else { None }
    }
  }
  parent.box(fn(row) {
    row
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(@ui.Space::px(S2_5)))
    .padding(Is((@ui.Space::px(S2), 0.0, @ui.Space::px(S2), 0.0)))
    |> ignore
    row.box(fn(w) {
      w
      .words_runs(By(fn() {
        match (got(), total()) {
          (Some((loaded, _)), Some(n)) =>
            [
              @view.words_run(t("web-main.preview.loadingLabel") + " "),
              @view.words_run(file_size(loaded), weight=600, ink=ink().ink),
              @view.words_run(" / " + file_size(n)),
            ]
          _ => [@view.words_run(t("common.opening"))]
        }
      }))
      .words_look(By(fn() {
        let (size, line) = @ui.tree_theme().text_size(Meta)
        { size, weight: 400, line, wrap: false }
      }))
      .ink(By(fn() { ink().muted }))
      |> ignore
    })
    |> ignore
    progress_node(
      row,
      fn() {
        match (got(), total()) {
          (Some((loaded, _)), Some(n)) => Some(if loaded >= n { 1.0 } else { loaded / n })
          _ => None
        }
      },
      fn() { @ui.tree_theme().line },
      fn() { theme().p.accent },
    )
    .width(Is(Some(vfr_coming_track)))
    |> ignore
  })
}
