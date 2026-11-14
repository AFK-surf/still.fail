// The library's button (button's) as a node of the window's tree, made once: its ground the tone's, a step towards the
// page or the hover's where the hand is on it (dur_ms, eased out, from the moment that changed); faded while it cannot
// be pressed; at work, a spinner's room opening before its words (a Move as far as that room) and the spinner turning
// in it, coming in as it opens; its words changed, its ground and its words going together to where they are laid out
// (moves_for: the same cause, one length). All of that is its look, over mbui's headless button (@headless.button),
// whose it is that it is read out a button, pressed where it is laid out and by the keyboard, and when it is neither.

///|
/// The button in `parent`: `label` its words, `tone` its look, `busy` while what it does is under way (not pressed
/// again, a spinner before its words), `disabled` while it cannot be pressed (faded), `across` as wide as what holds it
/// gives (its words in its middle); `press` done as it is pressed. In a panel coming in its surface first, all of it
/// (its ground, its icon, its spinner, its words) with the rest of what the panel holds: the panel's content's. Its
/// words changing go to their place for that cause. `card_words`: in a card's foot corner, its words where the card's
/// begin (card_foot_words's: its padding as far in as that corner leaves them; one with an icon keeps its ends).
/// The node.
#callsite(autofill(loc))
pub fn button_node(
  parent : @view.View,
  label : () -> String,
  press : () -> Unit,
  tone? : Tone = Plain,
  busy? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
  across? : Bool = false,
  icon? : String = "",
  card_words? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  button_by(loc~, parent, label, fn(_) { press() }, tone, busy, disabled, across, icon, card_words)
}

///|
/// button_node's button that opens what goes beside it (a menu under it): `open` given the button itself as it is
/// pressed, where it is placed then.
#callsite(autofill(loc))
pub fn button_opens_node(
  parent : @view.View,
  label : () -> String,
  open : (@view.View) -> Unit,
  tone? : Tone = Plain,
  icon? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  button_by(loc~, parent, label, open, tone, fn() { false }, fn() { false }, false, icon, false)
}

///|
/// button_node's button, `press` given the button itself as it is pressed.
#callsite(autofill(loc))
fn button_by(
  parent : @view.View,
  label : () -> String,
  press : (@view.View) -> Unit,
  tone : Tone,
  busy : () -> Bool,
  disabled : () -> Bool,
  across : Bool,
  icon : String,
  card_words : Bool,
  loc~ : SourceLoc,
) -> @view.View {
  let live = fn() { !disabled() && !busy() }
  let solid = tone == Primary || tone == DangerSolid
  let height = button_height()
  // (what it is to the hand, the keyboard and a screen reader is mbui's headless button's: read out a button called by
  // its label, pressed and focused only while not disabled, Enter and Space pressing it. At work is disabled to all of
  // those, and told apart by the eye alone: said to the component as disabled, its spinner this look's. Here, its look)
  @headless.button(made_for=loc, parent, label, press, disabled=fn() { !live() }, fn(v, b) {
    // (the hand on it, or pressing it (the keyboard's focus shown on it, a pointer over it, a finger or the pointer
    // held on it: which of the button's states light it is this look's): how far its ground has gone towards its lit
    // one; at work, how far its spinner is in and how far its room is open; how faded it is)
    let lit = fn() {
      (busy() && (tone == Ghost || tone == GhostDanger)) || (live() && (b.focus_shown() || b.hovered() || b.pressed()))
    }
    let hand = EdgeWay::new(if @signals.untracked(lit) { 1.0 } else { 0.0 })
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
    let padx = if card_words && icon == "" && !across { card_foot_words_in(height) } else { button_padx }
    v
    .row(Is(true))
    .height(Is(Some(height)))
    .padding(Is((padx, 0.0, padx, 0.0)))
    .lines_up(Is(Some(Middle)))
    .radius(Is(height / 2.0))
    .ground(By(fn() { looks().0 }))
    .alpha(By(fn() { seen.shown(v) }))
    |> ignore
    if across {
      // (as wide as what holds it, whichever way that lays out: its own height kept)
      v.width_share(Is(1.0)) |> ignore
    } else if v.lent(foot_fills_lent).unwrap_or(false) {
      // (at a sheet's foot, in a thumb's reach: its share of the foot's width, as the old button's there, foot_fills;
      // never narrower than its words and its ends need, what is beside it giving way first, as the old one's `keep`)
      v.grow(Is(1.0)).basis(Is(Some(0.0))).keeps_held(Is(true)) |> ignore
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
      s.alpha(By(fn() { turning.shown(v) * seen_at(open.shown(v)) })).scale(By(fn() { dmax(open.shown(v), 0.0) }), about=At(0.0, 0.5)) |> ignore
    })
    // (its icon before its words where it has one: button's `icon`. At work the spinner takes its place: its room
    // closing as the spinner's opens, the icon going as the spinner comes, never the two side by side (the user,
    // 2026-11-14: 「这个怪怪的」, a spinner and the refresh mark before 刷新 together))
    if icon != "" {
      // (by its ink: as far in from the end as the words are from the other, the grid's room round its strokes taking
      // none, so the two ends look alike: button's draw_icon by_ink)
      let (ink_l, ink_r) = match icon_numbers(icon) {
        Some(d) => @ui.shapes_ink_in(icon_shapes(d, button_icon / 24.0, 0x000000FFL), button_icon)
        None => (0.0, 0.0)
      }
      let rest = fn() { dmax(1.0 - open.shown(v), 0.0) }
      v.show(fn() { rest() > 0.0 }, fn(room) {
        room
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .width(By(fn() { Some((button_icon - ink_l - ink_r + gap()) * rest()) }))
        |> ignore
        icon_node(room, icon, button_icon, By(fn() { looks().2 }))
        .margin(Is((-ink_l, 0.0, -ink_r, 0.0)))
        .alpha(By(fn() { seen_at(rest()) }))
        .scale(By(rest), about=At(0.0, 0.5))
        |> ignore
        room.box(fn(g) { g.width(By(fn() { Some(gap()) })) |> ignore }) |> ignore
      })
    }
    let words = v.box(fn(w) {
      w
      .words(By(label), look={ size: theme().t.ui, weight: if theme().touch { 600 } else { 500 }, line: theme().t.ui_line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
      .ink(By(fn() { looks().2 }))
      |> ignore
    })
    v.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    // (its words changed: its ground from the shape it had, its words from where they were, together: reshape and
    // layout by its words)
    let m = @motion.moves_for(v, label, spec=button_reshape)
    m.reshapes(v)
    m.moves_with(words)
  })
}
