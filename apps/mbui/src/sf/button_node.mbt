// The library's button (button's) as a node of the window's tree, made once: its ground the tone's, a step towards the
// page or the hover's where the hand is on it (dur_ms, eased out, from the moment that changed); faded while it cannot
// be pressed; at work, a spinner's room opening before its words (a Move as far as that room) and the spinner turning
// in it, coming in as it opens; its words changed, its ground and its words going together to where they are laid out
// (moves_together: the same cause, one length); read out a button, pressed where it is laid out.

///|
/// The button in `parent`: `label` its words, `tone` its look, `busy` while what it does is under way (not pressed
/// again, a spinner before its words), `disabled` while it cannot be pressed (faded), `across` as wide as what holds it
/// gives (its words in its middle); `press` done as it is pressed; `words_in`: how far its words are in over its ground
/// (what holds it coming in its ground first). Its words changing go to their place for that cause.
/// The node.
pub fn button_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  tone? : Tone = Plain,
  busy? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
  across? : Bool = false,
  words_in? : () -> Double = fn() { 1.0 },
) -> @view.View {
  let live = fn() { !disabled() && !busy() }
  let solid = tone == Primary || tone == DangerSolid
  let height = button_height()
  parent.box(fn(v) {
    // (the hand on it, or pressing it: how far its ground has gone towards its lit one; at work, how far its spinner is
    // in and how far its room is open; how faded it is)
    let lit = fn() {
      live() &&
      (v.focus_shown() ||
      (match @ui.pointing() {
        Mouse => v.pointed() || v.pressed()
        Finger => v.pressed()
      }))
    }
    let hand = EdgeWay::new(0.0)
    let turning = EdgeWay::new(if @signals.untracked(busy) { 1.0 } else { 0.0 })
    let open = EdgeWay::new(if @signals.untracked(busy) { 1.0 } else { 0.0 })
    let seen = EdgeWay::new(if @signals.untracked(disabled) { 0.45 } else { 1.0 })
    v.reacts(lit, fn(on) { hand.go(v, if on { 1.0 } else { 0.0 }, dur_ms) })
    v.reacts(busy, fn(on) {
      turning.go(v, if on { 1.0 } else { 0.0 }, dur_ms)
      open.go_by(v, if on { 1.0 } else { 0.0 }, button_reshape)
    })
    v.reacts(disabled, fn(off) { seen.go(v, if off { 0.45 } else { 1.0 }, dur_ms) })
    // (its ground, edge and words' ink as the tone has them, the hand's step as far as it has gone)
    let looks = fn() {
      let t = theme()
      let p = t.p
      let h = hand.shown(v)
      match tone {
        Primary => {
          let g = mix(p.primary_hover, h, p.primary)
          (g, g, p.bg)
        }
        DangerSolid => {
          let g = mix(mix(p.red, 0.85, p.canvas), h, p.red)
          (g, g, if t.dark { p.bg } else { 0xFFFFFFFFL })
        }
        Danger => {
          let g = over(p.chip, alpha(p.hover, h))
          (g, g, p.red)
        }
        Ghost => (alpha(p.hover, h), 0L, p.text)
        GhostDanger => (alpha(p.hover, h), 0L, p.red)
        Plain => {
          let g = over(p.chip, alpha(p.hover, h))
          (g, g, p.text)
        }
      }
    }
    let gap = fn() { if theme().touch { 8.0 } else { 6.0 } }
    v
    .row(Is(true))
    .height(Is(Some(height)))
    .padding(Is((button_padx, 0.0, button_padx, 0.0)))
    .lines_up(Is(Some(Middle)))
    .radius(Is(height / 2.0))
    .ground(By(fn() { looks().0 }))
    .alpha(By(fn() { seen.shown(v) }))
    .presses(By(live))
    // (the keyboard's focus too while it can be pressed, Enter and Space pressing it: button's c.focusable)
    .focusable(By(live))
    .says(By(fn() { Some(@view.said(Button, label=label())) }))
    .on_press(fn() {
      if @signals.untracked(live) {
        press()
      }
    })
    |> ignore
    if across {
      // (as wide as what holds it, whichever way that lays out: its own height kept)
      v.width_share(Is(1.0)) |> ignore
    }
    // (what it holds in its middle, however wide it is laid out (as wide as a column, stretched by what holds it): as
    // the old one's justify=JCenter)
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    // (the spinner's room before its words, while it is at work and till its room has closed after: as wide as it is
    // open, the spinner growing from its start as it opens; none of it, and nothing turning, at rest)
    v.show(fn() { busy() || open.shown(v) > 0.0 }, fn(room) {
      room
      .width(By(fn() { Some((button_icon + gap()) * dmax(open.shown(v), 0.0)) }))
      .height(Is(Some(button_icon)))
      |> ignore
      let s = spinner_node(
        room,
        size=button_icon,
        ring=fn() {
          let (_, _, ink) = looks()
          if solid { alpha(ink, 0.3) } else { theme().p.line_strong }
        },
        arc=fn() {
          let (_, _, ink) = looks()
          if solid { ink } else { theme().p.accent }
        },
      )
      s.alpha(By(fn() { turning.shown(v) })).scale(By(fn() { dmax(open.shown(v), 0.0) }), about=At(0.0, 0.5)) |> ignore
    })
    let words = v.box(fn(w) {
      w
      .words(By(label), look={ size: theme().t.ui, weight: if theme().touch { 600 } else { 500 }, line: theme().t.ui_line, wrap: false })
      .ink(By(fn() { looks().2 }))
      // (as far in as its words are where what holds it comes in its ground first: a panel's, motion's ground_first)
      .alpha(By(words_in))
      |> ignore
    })
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    // (its words changed: its ground from the shape it had, its words from where they were, together: reshape and
    // layout by its words)
    let g = @motion.moves_together(v, label, spec=button_reshape)
    g.add(v, reshapes=true)
    g.add(words)
  })
}
