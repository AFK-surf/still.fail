// The settings' wide button as a node of the window's tree. Its colours and its spinner are the wide button's,
// rather than the library button's; each follows the page's state without rebuilding the button.

///|
/// A 46-high capsule across `parent`, with `label` in its middle. `primary`, `busy`, `enabled` and `danger` are
/// read as they change. While busy or disabled it cannot be pressed; otherwise a tap, click, keyboard or screen-reader
/// activation calls `press`. The node.
pub fn wide_button_node(
  parent : @view.View,
  label : () -> String,
  primary : () -> Bool,
  press : () -> Unit,
  busy? : () -> Bool = fn() { false },
  enabled? : () -> Bool = fn() { true },
  danger? : () -> Bool = fn() { false },
) -> @view.View {
  parent.box(fn(v) {
    let live = fn() { enabled() && !busy() }
    let ground = fn() {
      let p = theme().p
      if !primary() {
        alpha(p.text, 0.08)
      } else if danger() {
        if enabled() { p.red } else { alpha(p.red, 0.4) }
      } else if !enabled() {
        p.line
      } else {
        p.text
      }
    }
    let ink = fn() {
      let p = theme().p
      if primary() && danger() { 0xFFFFFFFFL } else if primary() { p.bg } else { p.text }
    }
    v
    .row(Is(true))
    .width_share(Is(1.0))
    .height(Is(Some(wide_button_node_h)))
    .padding(Is((20.0, 0.0, 20.0, 0.0)))
    .lines_up(Is(Some(Middle)))
    .radius(Is(wide_button_node_h / 2.0))
    .ground(By(ground))
    .presses(By(live))
    .focusable(By(live))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    .on_press(fn() { if @signals.untracked(live) { press() } })
    |> ignore
    // Equal flexible room on each side keeps the spinner and the words together in the capsule's middle.
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    v.box(fn(line) {
      line.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      line.show(busy, fn(at) {
        spinner_node(at, size=14.0, ring=fn() { alpha(ink(), 0.3) }, arc=ink) |> ignore
      })
      line.box(fn(w) {
        w
        .words(By(label))
        .words_look(By(fn() { @ui.style_words(body.then(strong).then(one_line)) }))
        .ink(By(ink))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    // The old button's ripple starts at the press; a solid ground sinks beneath the hand as it does there.
    let ripple = press_look(v, Is(wide_button_node_h / 2.0), fn() { @ui.stands_alone(ground()) })
    let on_it = fn(d : @view.Drag) { v.finger_target(d.wx, d.wy) }
    v.gesture(
      @ui.touch_slop(),
      press=fn(d) { if @signals.untracked(live) { ripple(d) } },
      tap=fn(d) { if on_it(d) && @signals.untracked(live) { press() } },
      drag=fn(d) {
        if d.kind == Up && @ui.pointing() is Mouse && on_it(d) && @signals.untracked(live) { press() }
      },
    )
    |> ignore
  })
}

///|
/// A wide button at the foot of a page, 12 below what precedes it. `radii` are the current panel's four corners in
/// `foot_capsule_of` order, or None for the window's whole. The sides and foot follow those corners as they change.
/// `body` builds the button in the room left; the page's frame supplies any window safe area separately.
pub fn wide_button_foot_node(
  parent : @view.View,
  radii : () -> FixedArray[Double]?,
  body : (@view.View) -> Unit,
) -> @view.View {
  parent.box(fn(foot) {
    foot
    .width_share(Is(1.0))
    .padding(By(fn() {
      let (left, right, bottom) = foot_capsule_of(radii(), wide_button_node_h, 12.0, 12.0)
      (left, 12.0, right, bottom)
    }))
    |> ignore
    body(foot)
  })
}

///|
let wide_button_node_h : Double = 46.0
