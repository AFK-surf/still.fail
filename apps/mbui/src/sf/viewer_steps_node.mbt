// The ways to the picture before and after (FilePreview.css.ts fpStep) as nodes of the window's tree
// (the way there, docs/retained.md 4): each there as what is beside the picture says, in and out as the bars are (or
// the hand is on it) from the moment that changes, on a motion's way; pressed (its press let go on it), done then.

///|
/// The ways to the picture before and after in `parent` (a layer over the viewer's, all of its room), as the web's
/// fpStep has them: 40 discs of the canvas at 80% over a 12 blur, a shadow, 16 in from the sides (36 and 8 where `small`), in
/// the middle, a chevron in the words' ink; each while `before` and `after` say there is one. There while `awake` (or
/// the hand on it: a mouse's pointer over it, a press held on it), in over wake_ms and out over sleep_ms from where it
/// is at the moment that changes (at once with motion reduced), as far in as `shown` says of the node as it is drawn
/// (the viewer's fade); taking a press while any of it shows. Pressed (its press let go on it), `go` (-1 the one before,
/// 1 the one after) at that moment. Their tips in `tips`. The row's node.
pub fn viewer_steps_node(
  parent : @view.View,
  before : () -> Bool,
  after : () -> Bool,
  awake : () -> Bool,
  shown : (@view.View) -> Double,
  small : () -> Bool,
  go : (Int) -> Unit,
  tips : TipLayer,
) -> @view.View {
  parent.box(fn(row) {
    row
    .over(Is(true))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .padding(By(fn() {
      let px = @ui.Space::px(if small() { S2 } else { S4 })
      (px, 0.0, px, 0.0)
    }))
    |> ignore
    let disc = fn() { @ui.Space::px(if small() { S9 } else { S10 }) }
    for side in [(before, -1, "chevron-left", "web-main.preview.prevKey"), (after, 1, "chevron-right", "web-main.preview.nextKey")] {
      let (there, dir, icon, label) = side
      if dir > 0 {
        row.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
      }
      // (as wide where there is none, the other in its place)
      row.box(fn(slot) {
        slot.width(By(fn() { Some(disc()) })).height(By(fn() { Some(disc()) })) |> ignore
        slot.show(there, fn(b) { step_disc(b, dir, icon, label, awake, shown, disc, go, tips) })
      })
      |> ignore
    }
  })
}

///|
/// One way, in `b` (its slot, all of it): see viewer_steps_node.
fn step_disc(
  b : @view.View,
  dir : Int,
  icon : String,
  label : String,
  awake : () -> Bool,
  shown : (@view.View) -> Double,
  disc : () -> Double,
  go : (Int) -> Unit,
  tips : TipLayer,
) -> Unit {
  // (where the hand is on it, as a box's hovered look has it: its ground)
  let hot = fn() {
    match @ui.pointing() {
      Mouse => b.pointed()
      Finger => b.pressed()
    }
  }
  // (there while the bars are, or the hand is on it or holds it: a mouse's button held down on it and moved off it, it
  // stays, as one lit or pressed does)
  let woke = fn() { awake() || hot() || b.pressed() }
  let seen = EdgeWay::new(if @signals.untracked(woke) { 1.0 } else { 0.0 })
  b.reacts(woke, fn(on) { seen.go(b, if on { 1.0 } else { 0.0 }, if on { wake_ms } else { sleep_ms }) })
  b
  .width(By(fn() { Some(disc()) }))
  .height(By(fn() { Some(disc()) }))
  .radius(By(fn() { disc() / 2.0 }))
  .lines_up(Is(Some(Middle)))
  .glass(By(fn() {
    let p = theme().p
    Some(@ui.Glass::frosted(blur=viewer_step_blur, tint=alpha(p.canvas, viewer_step_share), solid=p.canvas))
  }))
  .shadow(By(fn() {
    let (blur, dy) = @ui.Shadow::blur_y(Base)
    (blur, dy, @ui.tree_theme().shadow)
  }))
  .ground(By(fn() { if hot() { @ui.tree_theme().color(Hover) } else { 0L } }))
  .alpha(By(fn() { seen.shown(b) * shown(b) }))
  // (taking a press while any of it shows: on its way in, there, or on its way out)
  .presses(By(fn() {
    seen.way.said()
    seen.ended.get() |> ignore
    seen.way.target() > 0.0 || seen.way.goes_at(b.logic_at())
  }))
  .says(By(fn() { Some(@view.said(Button, label=t(label))) }))
  .on_press(fn() { go(dir) })
  |> ignore
  // (its chevron in its middle)
  b.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  b.box(fn(i) {
    i
    .width(Is(Some(viewer_step_icon)))
    .height(Is(Some(viewer_step_icon)))
    .shapes(Is(
      match icon_numbers(icon) {
        Some(d) => icon_shapes(d, viewer_step_icon / 24.0, 0x000000FFL)
        None => []
      },
    ))
    .drawn_as(Is("/icon/" + icon + "/"))
    .tint(By(fn() { theme().p.text }))
    |> ignore
  })
  |> ignore
  b.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  tip_node(tips, b, fn() { t(label) }) |> ignore
}
