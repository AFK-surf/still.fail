// The hand as what is built reads it (docs/incremental.md, the way there's 3): what the pointer is over, what is
// pressed and what the press went down on, what was clicked or clicked twice since the frame before, what was held
// long, what has the focus, the current input, where the pointer is and whether it is down, the discrete events of the
// hand (a key, words typed, a press going down or up, a menu, what a reader asked). Each is said as each frame
// begins, before it is decided what it does again (frame_watch.mbt), as what the next build would see of it: a key of
// a set read by member (signals' Keyed: "is this row pointed at" changes as the pointer crosses its edge, not as it
// moves), a value read whole otherwise. What reads them (Ctx::hovered, lit, pressed, clicked, the focus's, Ctx::press)
// follows them, and is built again as they change for it: a pointer moved over what lights nothing builds nothing.

///|
/// What the frames read of the hand, as the frame being drawn began.
priv struct Hand {
  /// what the pointer is over and what holds that, as the last frame drew them (Ctx::hovered)
  over : @signals.Keyed[Int]
  /// what is pressed (Ctx::pressed), and what the press went down on and what holds it (Ctx::press_within)
  pressed : @signals.Keyed[Int]
  press_on : @signals.Keyed[Int]
  /// what was clicked, and clicked twice, since the frame before (Ctx::clicked, double_clicked); what a press held long
  /// was on (Ctx::long_press)
  clicked : @signals.Keyed[Int]
  double : @signals.Keyed[Int]
  held : @signals.Keyed[Int]
  /// what has the focus, as a member and as what it is (Ctx::has_focus, focused_id)
  focus : @signals.Keyed[Int]
  focus_id : @signals.Signal[Int]
  /// what has the focus where it shows (it came by the keyboard: Ctx::focus_shown), by member: told as that alone
  /// changes too, what has it not told
  shown : @signals.Keyed[Int]
  /// where the pointer is, whether it is down, the current input (Ctx::pointer, Ctx::press, pointing)
  pointer : @signals.Signal[(Double, Double)]
  down : @signals.Signal[Bool]
  pointing : @signals.Signal[Pointing]
  /// whether a finger or a button held down is past the slop of where the press was seen going down (Ctx::press's
  /// `moved`): what reads the press is built again as it goes past, not as it moves
  beyond : @signals.Signal[Bool]
  /// the hand's discrete events so far, counted (hand_event): what reads what came (a key, a menu asked for, words
  /// dropped) is built again as one comes
  events : @signals.Signal[Int]
  /// the pointer's presses going down or up so far, counted (hand_pressed): what reads how a press goes (Ctx::press, an
  /// editor's caret, a second finger) is built again as one does, nothing else
  presses : @signals.Signal[Int]
  /// what a reader asked something of (Ctx::ask_action), by member (Ctx::action_asked): what asked of none, not built
  asked : @signals.Keyed[Int]
}

///|
// kept across runs: said anew as each frame begins (hand_arrive), from the Ctx of the run
let hand : Hand = {
  over: @signals.keyed(),
  pressed: @signals.keyed(),
  press_on: @signals.keyed(),
  clicked: @signals.keyed(),
  double: @signals.keyed(),
  held: @signals.keyed(),
  focus: @signals.keyed(),
  focus_id: @signals.signal(0),
  shown: @signals.keyed(),
  pointer: @signals.signal((0.0, 0.0), same=fn(a, b) { a.0 == b.0 && a.1 == b.1 }),
  down: @signals.signal(false),
  pointing: @signals.signal(Finger),
  beyond: @signals.signal(false),
  events: @signals.signal(0),
  presses: @signals.signal(0),
  asked: @signals.keyed(),
}

///|
/// The hand as the frame about to be drawn sees it, said (frame_drawn, before what it does again is decided): what of
/// it changed since the frame before tells what read it.
fn hand_arrive(c : Ctx) -> Unit {
  @signals.start_batch()
  let over = c.hover_in.copy()
  if c.hover != 0 {
    over.push(c.hover)
  }
  hand.over.set(over)
  hand.pressed.set(if c.down && c.active != 0 { [c.active] } else { [] })
  hand.press_on.set(c.press_on)
  hand.clicked.set(c.clicked)
  hand.double.set(c.double_clicked)
  hand.held.set(if c.held_on != 0 { [c.held_on] } else { [] })
  hand.focus.set(if c.focus != 0 { [c.focus] } else { [] })
  hand.focus_id.set(c.focus)
  hand.shown.set(if c.focus != 0 && c.focus_visible { [c.focus] } else { [] })
  hand.pointer.set((c.px, c.py))
  hand.down.set(c.down)
  let p = c.press_seen
  hand.beyond.set(c.down && ((c.px - p.x).abs() > press_slop || (c.py - p.y).abs() > press_slop))
  hand.pointing.set(pointing())
  hand.asked.set(c.asked_actions.map(fn(a) { a.0 }))
  @signals.end_batch()
}

///|
/// A discrete event of the hand came (a key, words typed, a press going down or up, a back, a menu, a reader's action):
/// what reads what comes (Ctx::keys, menu_asked, action_asked, tapped_anywhere) is built again.
fn hand_event() -> Unit {
  hand.events.set(@signals.untracked(fn() { hand.events.get() }) + 1)
}

///|
/// What the hand's discrete events are, read (Ctx::keys and the rest of what reads what came): followed.
fn hand_events_read() -> Unit {
  hand.events.get() |> ignore
}

///|
/// A press of the pointer went down or up (or was called off, or a second finger came): what reads how a press goes
/// built again (hand_presses_read), what reads the clicks by its own (Ctx::clicked: hand's `clicked`) as it is one.
fn hand_pressed() -> Unit {
  hand.presses.set(@signals.untracked(fn() { hand.presses.get() }) + 1)
}

///|
/// How the pointer's presses go, read (Ctx::press and what follows a press as it goes): followed, with the discrete
/// events.
fn hand_presses_read() -> Unit {
  hand.events.get() |> ignore
  hand.presses.get() |> ignore
}

///|
/// Put back as a run begins (reset_globals): nothing over, pressed, clicked, held or focused.
fn hand_reset() -> Unit {
  for k in [hand.over, hand.pressed, hand.press_on, hand.clicked, hand.double, hand.held, hand.focus, hand.shown] {
    k.set([])
  }
}

///|
/// The focus as a pass of the frame's build left it (the layers' focus moved in, a field asked for it): said at once,
/// what read it told, so a build again of the frame sees it as this one left it.
fn hand_focus_said(c : Ctx) -> Unit {
  @signals.start_batch()
  if @signals.untracked(fn() { hand.focus_id.get() }) != c.focus {
    hand.focus.set(if c.focus != 0 { [c.focus] } else { [] })
    hand.focus_id.set(c.focus)
  }
  // (whether it shows, as that alone changes: a press letting a field keep it, unshown)
  hand.shown.set(if c.focus != 0 && c.focus_visible { [c.focus] } else { [] })
  @signals.end_batch()
}
