// A tip as nodes of the window's tree (tip's, kit's tooltip's way): what a control is for, in a few words, shown by it
// as the mouse's pointer rests on it a while (at once where another tip of the same layer went a moment before), and
// while the keyboard's focus shows on it; shut by a press on it till the hand and the focus have left it; gone as either
// leaves, as its control takes input no more (said to take no press, it or what holds it; leaving; under a modal layer:
// View::takes_input, told at that cause), or goes. Each of these at its cause's moment: the rest's end a moment of the
// timeline, its control's state as it is then; drawn beside its control by where that is as the tree is placed
// (View::beside), in its layer (over all of the window), in the look tip_look draws (small words on the primary ink),
// set as the window's theme says as that changes.

///|
/// Where a window's tips are drawn (a node over all of it, as it is given when a tip is first shown) and when the last
/// of them went (another shown within tooltip_skip_ms of it at once: kit's tip_closed): one for the window's tree, made
/// and let go with what holds it.
pub struct TipLayer {
  layer : () -> @view.View?
  mut went_at : Double
}

///|
/// The tips' layer of a window, drawn in what `layer` gives (the node it is first shown in).
pub fn TipLayer::new(layer : () -> @view.View?) -> TipLayer {
  { layer, went_at: -1.0e18 }
}

///|
/// How a tip comes in (kit's tip_in: faded in, eased out, 120 ms); it goes as pop_out does (faded, eased to leave).
let tip_in_ms : Double = 120.0

///|
/// A tip saying `label` (as it changes; none said: no tip) of the control `anchor`, on its `side`, in `tips` (its
/// layer over all of the window). What shows it and what shuts it as the file's head says.
pub fn tip_node(tips : TipLayer, anchor : @view.View, label : () -> String, side? : @view.Side = Bottom) -> Unit {
  let open : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  let shut = Ref(false)
  let rest : Ref[(() -> Unit)?] = Ref(None)
  // (how it comes in, this time it is shown: from when, from how far in it was (shown again as it went: as far as it
  // had gone), whether it is in whole yet, and the moment that says so: this showing's own, let go as it goes)
  let fade : TipFade = { from_at: 0.0, from: 0.0, calm: @signals.signal(true, same=fn(a, b) { a == b }), due: None }
  let shown : Ref[@view.View?] = Ref(None)
  let anchor_id = anchor.id()
  // (made in its layer as it is first shown where there is one then (none yet: shown the next time it is, as there is
  // one), held there for its control, let go with it)
  let made = Ref(false)
  let make = fn() -> Bool {
    guard (tips.layer)() is Some(l) else { return false }
    let holder = l.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(anchor)
    holder.show(fn() { open.get() }, leave=@kit.pop_out_ms, fn(t) {
      shown.val = Some(t)
      tip_look_node(t, anchor_id, side, label, fade)
    })
    true
  }
  let stop_rest = fn() {
    match rest.val {
      Some(s) => s()
      None => ()
    }
    rest.val = None
  }
  let set_open = fn(on : Bool) {
    if on == @signals.untracked(fn() { open.get() }) {
      return
    }
    let at = anchor.cause_at()
    fade.stop()
    if on {
      if !made.val {
        made.val = make()
      }
      // (from where it is now: none of it, or as far as it had gone going)
      fade.from = match shown.val {
        Some(t) if t.alive() => 1.0 - @ui.Ease::at(Leave, @signals.untracked(fn() { t.going() }))
        _ => 0.0
      }
      fade.from_at = at
      fade.calm.set(false)
      fade.due = Some(anchor.at_moment(at + tip_in_ms, fn() { fade.calm.set(true) }))
    } else {
      fade.calm.set(true)
      tips.went_at = at
    }
    open.set(on)
  }
  // (what decides it, as of each cause: the pointer over it (a mouse's), a press on it, the keyboard's focus shown on it,
  // whether it takes input at all, whether there is anything to say)
  let state = fn() {
    (
      @ui.pointing() is Mouse && anchor.pointed(),
      anchor.pressed(),
      anchor.focus_shown(),
      anchor.takes_input(),
      label() != "",
    )
  }
  anchor.reacts(state, fn(s) {
    let (over, pressed, focused, takes, says) = s
    let at = anchor.cause_at()
    stop_rest()
    // (a press on it shuts it till the hand and the focus have left it: neither over it nor shown on it)
    if pressed {
      shut.val = true
    } else if !over && !focused {
      shut.val = false
    }
    if !says || !takes || shut.val || (!over && !focused) {
      set_open(false)
    } else if focused || @signals.untracked(fn() { open.get() }) {
      set_open(true)
    } else if at - tips.went_at <= @kit.tooltip_skip_ms {
      // (another of the layer's went a moment ago: at once)
      set_open(true)
    } else {
      // (rested on a while from now: shown then, as it is then, a pointer over it carrying no press, taking input)
      rest.val = Some(
        anchor.at_moment(at + tip_delay_ms, fn() {
          let (over, pressed, _, takes, says) = @signals.untracked(state)
          if over && !pressed && takes && says && !shut.val {
            set_open(true)
          }
        }),
      )
    }
  })
  // (its control let go: nothing of it left pending)
  anchor.owns(fn() {
    stop_rest()
    fade.stop()
  })
  |> ignore
}

///|
/// How a tip comes in, the time it is shown (tip_node): from when (`from_at`), from how far in (`from`: 0, or as far as
/// it had gone going, shown again), whether it is in whole (`calm`: the clock read no more), the moment that says so.
struct TipFade {
  mut from_at : Double
  mut from : Double
  calm : @signals.Signal[Bool]
  mut due : (() -> Unit)?
}

///|
/// The moment this showing comes in whole by let go (another showing, or its going, its own).
fn TipFade::stop(self : TipFade) -> Unit {
  match self.due {
    Some(s) => s()
    None => ()
  }
  self.due = None
}

///|
/// A tip's node `t` as tip_look draws it (tip_box, tip_words), beside `anchor` on `side`, saying `label`: its look and
/// its words set as the window's theme says, as that changes; coming in as `fade` says, going as it leaves.
fn tip_look_node(t : @view.View, anchor : @view.NodeId, side : @view.Side, label : () -> String, fade : TipFade) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  let px = @ui.Space::px(S2_5)
  let py = @ui.Space::px(S1_25)
  t
  .beside(anchor, side~, along=Middle, offset=tip_gap)
  .padding(Is((px, py, px, py)))
  .max_width(Is(Some(tip_widest)))
  .radius(By(fn() { theme().corner(Lg) }))
  .ground(By(fn() { theme().color(Primary) }))
  .shadow(By(fn() {
    let (blur, dy) = @ui.Shadow::blur_y(Md)
    (blur, dy, theme().shadow)
  }))
  .alpha(By(fn() {
    // (coming in from when it was said to, eased out; going, faded as it leaves; else whole, the clock not read)
    let gone = t.going()
    if gone > 0.0 {
      1.0 - @ui.Ease::at(Leave, gone)
    } else if fade.calm.get() {
      1.0
    } else {
      let p = (t.drawn_at() - fade.from_at) / tip_in_ms
      fade.from + (1.0 - fade.from) * @ui.Ease::at(Out, if p < 0.0 { 0.0 } else if p > 1.0 { 1.0 } else { p })
    }
  }))
  .says(By(fn() { Some(@view.said(Tooltip, label=label())) }))
  |> ignore
  t.box(fn(w) {
    w
    .words(By(fn() { label() }))
    .words_look(By(fn() {
      let (size, line) = theme().text_size(Meta)
      { size, weight: 400, line, wrap: true }
    }))
    .ink(By(fn() { theme().color(OnPrimary) }))
    |> ignore
  })
  |> ignore
}

///|
/// How far a tip is from its control (kit's tooltip `offset`), and how wide it may grow (tip_max).
let tip_gap : Double = 6.0

///|
let tip_widest : Double = match tip_max {
  Fixed(v) => v
  _ => 0.0
}
