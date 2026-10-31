// How a column's edge looks as a node of the window's tree (edge_look's, its made-once form): its bar and its line in
// its middle, each moving between what it shows as its state changes, from the moment of what changed it (a pointer come
// onto it, a press of it, its end), each on its own way (@motion.Way), from where the one before had it then; drawn
// where it is at the moment it is drawn while it goes, where it went once it is there. Made as its state is then, still.

///|
/// One of what a look moves (a bar's height, how much it shows, its ink, the line's): its way, the end of the way it
/// goes now (a moment of the node's timeline: what reads it told as it is there), let go as another is said and as the
/// node is.
priv struct EdgeWay {
  way : @motion.Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
}

///|
fn EdgeWay::new(v : Double) -> EdgeWay {
  { way: @motion.Way::new(v), ended: @signals.signal(0), due: fn() {  } }
}

///|
/// Off to `to` over `ms` (eased out) from `n`'s cause's moment, from where it is then; its end a moment of `n`'s.
fn EdgeWay::go(self : EdgeWay, n : @view.View, to : Double, ms : Double) -> Unit {
  if self.way.target() == to {
    return
  }
  (self.due)()
  self.way.go(to, @motion.tween(ms, ease=Out), at=n.cause_at())
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(@signals.untracked(fn() { self.ended.get() }) + 1) })
  } else {
    fn() {  }
  }
}

///|
/// Where it is as `n` is drawn: at the moment it is drawn at while it goes, where it went once it is there.
fn EdgeWay::shown(self : EdgeWay, n : @view.View) -> Double {
  self.way.said()
  self.ended.get() |> ignore
  if self.way.goes_at(n.logic_at()) {
    self.way.value_at(n.drawn_at())
  } else {
    self.way.target()
  }
}

///|
/// A column's edge's look in a node of `parent`'s (as tall as it, `handle_w` across, its middle that of `parent`), as
/// edge_look draws it: its bar while `over()` its column, longer while `on()` it (pointed at, in hand), in the field's
/// edge grey while `active()` (pressed, dragged), else the strong line's grey; its line while on it (unless `line()` says
/// no, as that changes: a sidebar folded) or active. Its bar's height and showing move over edge_bar_ms, its grey over edge_ink_ms, its line over
/// edge_line_ms, each eased out, from the moment its state changed. Taking nothing. The node.
pub fn edge_look_node(
  parent : @view.View,
  over : () -> Bool,
  on : () -> Bool,
  active : () -> Bool,
  line? : () -> Bool = fn() { true },
) -> @view.View {
  parent.box(fn(v) {
    let theme = fn() { @ui.tree_theme() }
    let state = fn() { edge_state(over(), on(), active(), line()) }
    let now = @signals.untracked(state)
    // (each as the state is as it is made: still)
    let shows = EdgeWay::new(if (now & 1) != 0 { 1.0 } else { 0.0 })
    let long = EdgeWay::new(if (now & 2) != 0 { 1.0 } else { 0.0 })
    let ink = EdgeWay::new(if (now & 4) != 0 { 1.0 } else { 0.0 })
    let lit = EdgeWay::new(if (now & 8) != 0 { 1.0 } else { 0.0 })
    v.reacts(state, fn(s) {
      shows.go(v, if (s & 1) != 0 { 1.0 } else { 0.0 }, edge_bar_ms)
      long.go(v, if (s & 2) != 0 { 1.0 } else { 0.0 }, edge_bar_ms)
      ink.go(v, if (s & 4) != 0 { 1.0 } else { 0.0 }, edge_ink_ms)
      lit.go(v, if (s & 8) != 0 { 1.0 } else { 0.0 }, edge_line_ms)
    })
    v.owns(fn() {
      for w in [shows, long, ink, lit] {
        (w.due)()
      }
    })
    |> ignore
    v.width(Is(Some(handle_w))).grow(Is(1.0)).presses(Is(false)) |> ignore
    // its line, over all of it but S2 at each end, its grey whole at its middle, clear toward its ends
    v.box(fn(l) {
      let side = (handle_w - @ui.Space::px(SPx)) / 2.0
      l.over(Is(true)).padding(Is((side, @ui.Space::px(S2), side, @ui.Space::px(S2)))) |> ignore
      l.box(fn(h) {
        h
        .grow(Is(1.0))
        .alpha(By(fn() { lit.shown(v) }))
        |> ignore
        for i in 0..<edge_line_steps {
          let y = (i.to_double() + 0.5) / edge_line_steps.to_double()
          let a = if y <= 0.1 || y >= 0.9 { 0.0 } else if y < 0.5 { (y - 0.1) / 0.4 } else { (0.9 - y) / 0.4 }
          h.box(fn(s) {
            s.grow(Is(1.0)).alpha(Is(a)).ground(By(fn() { theme().color(FieldHover) })) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // its bar, in its middle (as much room above as below it, its sides as far in)
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    let side = (handle_w - edge_bar_w) / 2.0
    v.box(fn(p) {
      p.padding(Is((side, 0.0, side, 0.0))) |> ignore
      p.box(fn(b) {
      b
      .width(Is(Some(edge_bar_w)))
      .height(By(fn() {
        let (s6, s12) = (@ui.Space::px(S6), @ui.Space::px(S12))
        Some(s6 + (s12 - s6) * long.shown(v))
      }))
      .radius(Is(edge_bar_w / 2.0))
      .alpha(By(fn() { shows.shown(v) }))
      .ground(By(fn() { mix(theme().color(FieldHover), ink.shown(v), theme().color(Border)) }))
      .drawn_as(Is("/icon/edge-bar/"))
      |> ignore
      })
      |> ignore
    })
    |> ignore
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
  })
}

///|
/// Whether an edge's bar shows over its column as the hand has it now (edge_look's `over` where its column is not
/// lit by a pointer of its own: shown always to touch, which points at nothing; to a mouse, only as it is on the edge).
pub fn edge_over() -> Bool {
  @ui.pointing() is Finger
}
