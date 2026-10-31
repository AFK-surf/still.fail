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
/// How big a tip is drawn as it has gone (pop_out's scale).
let tip_out_scale : Double = 0.97

///|
/// A tip saying `label` (as it changes; none said: no tip) of the control `anchor`, on its `side`, in `tips` (its
/// layer over all of the window). What shows it and what shuts it as the file's head says. `delay`: how long the
/// pointer rests on it before it shows; `skip`: shown at once where another of the layer went a moment before; `gap`:
/// how far from what it is beside; `at_pointer`: beside the pointer as it moves along the control, its middle level with
/// it (a tall thin thing's: an edge, usePointerTip), not the control's middle. `within`: shown by the pointer within
/// `anchor` as it is placed (View::pointer_within), where it is no control and takes no press (a bar's name, what is
/// pressed there the bar's), not by its being pointed at.
pub fn tip_node(
  tips : TipLayer,
  anchor : @view.View,
  label : () -> String,
  side? : @view.Side = Bottom,
  delay? : Double = tip_delay_ms,
  skip? : Bool = true,
  gap? : Double = tip_gap,
  at_pointer? : Bool = false,
  within? : Bool = false,
) -> TipHand {
  let open : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  // (a finger held on its control: Held while it is down, Lifted a while once it is let go, till then or the next
  // press, wherever it lands; Free otherwise)
  let hand : @signals.Signal[TipHeld] = @signals.signal(Free, same=fn(a, b) { a == b })
  let lifted_end : Ref[() -> Unit] = Ref(fn() {  })
  let shut = Ref(false)
  let rest : Ref[(() -> Unit)?] = Ref(None)
  // (how it comes in, this time it is shown: from when, from how far in it was (shown again as it went: as far as it
  // had gone), whether it is in whole yet, and the moment that says so: this showing's own, let go as it goes)
  let fade = TipFade::new()
  let anchor_id = anchor.id()
  // (made in its layer as it is first shown where there is one then (none yet: shown the next time it is, as there is
  // one), held there for its control, let go with it)
  let made = Ref(false)
  // (Escape while it shows: its, before what is under it (a viewer it is over) is asked; gone, shut as a press shuts it)
  let escaped : Ref[() -> Unit] = Ref(fn() {  })
  let make = fn() -> Bool {
    guard (tips.layer)() is Some(l) else { return false }
    let holder = l.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(anchor)
    holder.on_key(fn(k) {
      if k.code == @ui.key_escape && @signals.untracked(fn() { open.get() }) {
        (escaped.val)()
        true
      } else {
        false
      }
    })
    |> ignore
    holder.show(fn() { open.get() }, leave=@kit.pop_out_ms, fn(t) {
      tip_look_node(t, anchor_id, side, label, fade, gap, at_pointer)
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
    if on {
      if !made.val {
        made.val = make()
      }
      // (in, as kit's tip_in: from where it is at this moment, eased out)
      fade.go(anchor, 1.0, at, tip_in_ms, Out)
    } else {
      // (out, as pop_out: from where it is at this moment, eased to leave, over as long as it is kept going)
      fade.go(anchor, 0.0, at, @kit.pop_out_ms, Leave)
      tips.went_at = at
    }
    open.set(on)
  }
  // (what decides it, as of each cause: the pointer over it (a mouse's), a press on it, the keyboard's focus shown on it,
  // whether it takes input at all, whether there is anything to say)
  let state = fn() {
    (
      @ui.pointing() is Mouse && (if within { anchor.pointer_within() } else { anchor.pointed() }),
      anchor.pressed(),
      anchor.focus_shown(),
      anchor.takes_input(),
      label() != "",
      hand.get(),
    )
  }
  anchor.reacts(state, fn(s) {
    let (over, pressed, focused, takes, says, held) = s
    let at = anchor.cause_at()
    stop_rest()
    // (held open by a finger: shown at once, as long as there is something to say and it takes input; taking none, this
    // holding over, not shown again as it takes input again)
    if held != Free {
      if says && takes {
        set_open(true)
      } else {
        (lifted_end.val)()
        hand.set(Free)
        set_open(false)
      }
      return
    }
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
    } else if skip && at - tips.went_at <= @kit.tooltip_skip_ms {
      // (another of the layer's went a moment ago: at once)
      set_open(true)
    } else {
      // (rested on a while from now: shown then, as it is then, a pointer over it carrying no press, taking input)
      rest.val = Some(
        anchor.at_moment(at + delay, fn() {
          let (over, pressed, _, takes, says, _) = @signals.untracked(state)
          if over && !pressed && takes && says && !shut.val {
            set_open(true)
          }
        }),
      )
    }
  })
  escaped.val = fn() {
    shut.val = true
    (lifted_end.val)()
    hand.set(Free)
    set_open(false)
  }
  // (let go by a finger that held it open: shown on a while, gone at the next press wherever it lands, or then)
  anchor.reacts(fn() { anchor.window_downs() }, fn(_) {
    if @signals.untracked(fn() { hand.get() }) == Lifted {
      (lifted_end.val)()
      hand.set(Free)
    }
  })
  // (its control let go: nothing of it left pending)
  anchor.owns(fn() {
    stop_rest()
    fade.stop()
    (lifted_end.val)()
  })
  |> ignore
  {
    hold: fn() {
      (lifted_end.val)()
      hand.set(Held)
    },
    cancel: fn() {
      (lifted_end.val)()
      hand.set(Free)
    },
    lift: fn() {
      if @signals.untracked(fn() { hand.get() }) == Held {
        hand.set(Lifted)
        lifted_end.val = anchor.at_moment(anchor.cause_at() + @kit.tooltip_lifted_ms, fn() { hand.set(Free) })
      }
    },
  }
}

///|
/// How a finger holds a tip open (tip_node): not at all, held down on its control, let go of it a moment ago.
enum TipHeld {
  Free
  Held
  Lifted
} derive(Eq)

///|
/// What a control tells its tip of a finger (tip_node's): held on it long enough (`hold`: shown at once, as long as it
/// stays down), let go after (`lift`: shown on tooltip_lifted_ms more, or till the next press, wherever it lands),
/// called off instead (`cancel`: the system took the touch, its control was taken from the hand: gone, none of it
/// kept).
pub struct TipHand {
  hold : () -> Unit
  lift : () -> Unit
  cancel : () -> Unit
}

///|
/// How far a tip is in (0 none of it, 1 all of it) as it comes and goes (tip_node): one way at a time, from where the
/// one before had it at the moment it was turned (`from`, worked out of that one as of then: the same however far it had
/// got), to `to` over `ms` from `start` as `ease` has it; while it goes (`moving`, till the moment it ends: the clock
/// read no longer than that), the moment it ends its own, let go as another way is set out.
struct TipFade {
  mut from : Double
  mut to : Double
  mut start : Double
  mut ms : Double
  mut ease : @ui.Ease
  moving : @signals.Signal[Bool]
  mut due : (() -> Unit)?
}

///|
/// A tip none of which is in, going nowhere.
fn TipFade::new() -> TipFade {
  { from: 0.0, to: 0.0, start: 0.0, ms: 0.0, ease: Out, moving: @signals.signal(false, same=fn(a, b) { a == b }), due: None }
}

///|
/// How far in it is at `t`, by the way it goes now.
fn TipFade::at(self : TipFade, t : Double) -> Double {
  if self.ms <= 0.0 || t >= self.start + self.ms {
    return self.to
  }
  let p = (t - self.start) / self.ms
  self.from + (self.to - self.from) * self.ease.at(if p < 0.0 { 0.0 } else { p })
}

///|
/// It set going to `to` from `at` over `ms` as `ease` has it, from where it is at `at`; its end, the moment `node` says
/// it is (its own, the way before's let go).
fn TipFade::go(self : TipFade, node : @view.View, to : Double, at : Double, ms : Double, ease : @ui.Ease) -> Unit {
  self.from = self.at(at)
  self.to = to
  self.start = at
  self.ms = ms
  self.ease = ease
  self.stop()
  self.moving.set(true)
  self.due = Some(node.at_moment(at + ms, fn() { self.moving.set(false) }))
}

///|
/// Its end's moment let go of (another way set out, its control gone).
fn TipFade::stop(self : TipFade) -> Unit {
  match self.due {
    Some(s) => s()
    None => ()
  }
  self.due = None
}

///|
/// How far in it is as drawn now: by the clock while it goes, where it went once it is there.
fn TipFade::shown(self : TipFade, t : @view.View) -> Double {
  if self.moving.get() {
    self.at(t.drawn_at())
  } else {
    self.to
  }
}

///|
/// A tip's node `t` as tip_look draws it (tip_box, tip_words), beside `anchor` on `side`, saying `label`: its look and
/// its words set as the window's theme says, as that changes; in and out as `fade` says.
fn tip_look_node(
  t : @view.View,
  anchor : @view.NodeId,
  side : @view.Side,
  label : () -> String,
  fade : TipFade,
  gap : Double,
  at_pointer : Bool,
) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  let px = @ui.Space::px(S2_5)
  let py = @ui.Space::px(S1_25)
  t
  .beside(anchor, side~, along=Middle, offset=gap, at_pointer~)
  .padding(Is((px, py, px, py)))
  .max_width(Is(Some(tip_widest)))
  .radius(By(fn() { theme().corner(Lg) }))
  .ground(By(fn() { theme().color(Primary) }))
  .shadow(By(fn() {
    let (blur, dy) = @ui.Shadow::blur_y(Md)
    (blur, dy, theme().shadow)
  }))
  // (its ground in first, its words after, as kit's tip_in and pop_out have them (ground_first): the ground the first
  // half of the way in, the words the second; going, the other way round)
  .alpha(By(fn() {
    let a = fade.shown(t)
    if a * 2.0 < 1.0 {
      a * 2.0
    } else {
      1.0
    }
  }))
  // (going, drawn smaller as it fades, to 0.97 of itself, about its edge toward its control (kit's pop_out, grown_from):
  // coming, whole, as tip_in has it, from wherever it was turned back)
  .scale(
    By(fn() {
      let a = fade.shown(t)
      if fade.to > 0.5 {
        1.0
      } else {
        tip_out_scale + (1.0 - tip_out_scale) * a
      }
    }),
    about=@view.FromBeside,
  )
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
    .alpha(By(fn() {
      // (of its ground's: what of the words shows over as much of the ground as there is)
      let a = fade.shown(t)
      let ground = if a * 2.0 < 1.0 { a * 2.0 } else { 1.0 }
      let words = if a * 2.0 - 1.0 > 0.0 { a * 2.0 - 1.0 } else { 0.0 }
      if ground > 0.0 {
        words / ground
      } else {
        0.0
      }
    }))
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
