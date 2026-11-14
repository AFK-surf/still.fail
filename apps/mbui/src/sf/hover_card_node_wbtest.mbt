// A hover card as nodes of the window's tree (hover_card_node): when it opens and closes, each at its cause's moment
// and so at every rate frames are drawn at (each turn's moment asserted, as the card's own reaction tells it): a
// mouse's pointer resting on its trigger hover_card_open_ms, on the card kept, off both closed hover_card_close_ms
// after, another trigger's card by its own; a finger's long press; a press outside both, Escape; its trigger taking no
// input, a modal layer over it; kept open by the app (`held`) through all of those but its own end.

///|
/// What a hover_rig made: its Tester, each card's hand by its trigger's name, each turn of a card (its trigger's name,
/// open or not, the moment of its cause), how many times each trigger was pressed.
struct HoverRig {
  t : @ui.Tester
  hands : Map[String, HoverHand]
  turns : Array[(String, Bool, Double)]
  pressed : Map[String, Int]
}

///|
/// Two triggers in a row, 甲 and 乙 (buttons 120 by 32, 40 apart, 40 in), each with its card holding its name's words
/// and its key, and after them 丙 (60 by 20, pressed for nothing) in 外 (a button 120 wide, 44 high, as a bar's name in
/// its bar; `cramped`, 32 high, a neighbour that takes presses right under 丙: less room than a press takes), in a
/// window 800 by 500 (`platform` 0 a mouse's, 1 a touch screen's): 甲's and 乙's holders taking input while `takes`
/// says, a modal layer over all of it while `modal`, 甲's card kept open while `held`; 甲's and 乙's cards
/// `along_offset` along and beside their `piece`.
fn hover_rig(
  platform? : Int = 0,
  along_offset? : Double = 0.0,
  piece? : (Double, Double) -> (Double, Double, Double, Double)?,
  takes? : @signals.Signal[Bool] = @signals.signal(true),
  modal? : @signals.Signal[Bool] = @signals.signal(false),
  held? : @signals.Signal[Bool] = @signals.signal(false),
  cramped? : Bool = false,
) -> HoverRig {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=500.0, platform~)
  t.check_looks(false)
  let hands : Map[String, HoverHand] = Map([])
  let turns : Array[(String, Bool, Double)] = []
  let pressed : Map[String, Int] = Map([])
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    for name in ["甲", "乙"] {
      root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
      root.box(fn(h) {
        h.width(Is(Some(120.0))).height(Is(Some(32.0))).presses(By(fn() { takes.get() })) |> ignore
        h.box(fn(k) {
          k
          .width(Is(Some(120.0)))
          .height(Is(Some(32.0)))
          .focusable(Is(true))
          .says(Is(Some(@view.said(Button, label=name))))
          |> ignore
          let hand = hover_card_node(
            tips,
            k,
            fn(b) { hover_card_body(b, name, pressed) },
            held=fn() { name == "甲" && held.get() },
            along_offset~,
            piece?,
            press=fn() { pressed[name] = pressed.get(name).unwrap_or(0) + 1 },
          )
          hands[name] = hand
          k.reacts(fn() { (hand.open)() }, at_start=false, fn(o) { turns.push((name, o, k.cause_at())) })
        })
        |> ignore
      })
      |> ignore
    }
    // (丙: 20 high, no press of its own, in 外, which is pressed: a bar's name in its bar)
    root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(o) {
      o
      .width(Is(Some(120.0)))
      .height(Is(Some(if cramped { 32.0 } else { 44.0 })))
      .says(Is(Some(@view.said(Button, label="外"))))
      |> ignore
      presses_node(o, fn() { pressed["外"] = pressed.get("外").unwrap_or(0) + 1 })
      o.box(fn(k) {
        k.width(Is(Some(60.0))).height(Is(Some(20.0))).says(Is(Some(@view.said(Text, label="丙")))) |> ignore
        let hand = hover_card_node(tips, k, fn(b) { hover_card_body(b, "丙", pressed) })
        hands["丙"] = hand
        k.reacts(fn() { (hand.open)() }, at_start=false, fn(o) { turns.push(("丙", o, k.cause_at())) })
      })
      |> ignore
    })
    |> ignore
    // (cramped: right under 丙, at 外's foot, a neighbour as wide as 丙 that takes presses, so that 丙's room ends there:
    // a hold reaches it from round it as a press does, and with nothing under 外 it would be reached from there. 外's
    // own room, down its middle past 丙's end, as it was)
    if cramped {
      root.box(fn(u) {
        u
        .over(Is(true))
        .offset(Is((360.0, 32.0)))
        .width(Is(Some(60.0)))
        .height(Is(Some(44.0)))
        .says(Is(Some(@view.said(Button, label="丙下"))))
        |> ignore
        presses_node(u, fn() {  })
      })
      |> ignore
    }
    // (丁: a finger's tap its own (`tapped` alone), in 拖, which a press drags (a bar dragging the window): how many
    // presses went down on 拖, in `pressed`)
    root.box(fn(g) { g.width(Is(Some(40.0))) |> ignore }) |> ignore
    root.box(fn(o) {
      o
      .width(Is(Some(120.0)))
      .height(Is(Some(44.0)))
      .says(Is(Some(@view.said(Group, label="拖"))))
      .on_drag(fn(d) { if d.kind == Down { pressed["拖"] = pressed.get("拖").unwrap_or(0) + 1 } })
      |> ignore
      o.box(fn(k) {
        k.width(Is(Some(60.0))).height(Is(Some(20.0))).says(Is(Some(@view.said(Text, label="丁")))) |> ignore
        let hand = hover_card_node(tips, k, fn(b) { hover_card_body(b, "丁", pressed) }, tapped=fn() {
          pressed["丁"] = pressed.get("丁").unwrap_or(0) + 1
        })
        hands["丁"] = hand
        k.reacts(fn() { (hand.open)() }, at_start=false, fn(o) { turns.push(("丁", o, k.cause_at())) })
      })
      |> ignore
    })
    |> ignore
    root.show(fn() { modal.get() }, fn(m) { m.over(Is(true)).modal(Is(true)) |> ignore })
    layer.val = Some(root.box(fn(l) { l.over(Is(true)).over_all(Is(true)) |> ignore }))
  })
  t.draw()
  { t, hands, turns, pressed }
}

///|
/// What card `name` holds: its words, and under them its key, a button named `name` + "的键" (80 by 24), pressed into
/// `pressed`.
fn hover_card_body(b : @view.View, name : String, pressed : Map[String, Int]) -> Unit {
  b.box(fn(w) { w.words(Is(name + "的卡")) |> ignore }) |> ignore
  b.box(fn(x) {
    let key = name + "的键"
    x.width(Is(Some(80.0))).height(Is(Some(24.0))).says(Is(Some(@view.said(Button, label=key)))) |> ignore
    presses_node(x, fn() { pressed[key] = pressed.get(key).unwrap_or(0) + 1 })
  })
  |> ignore
}

///|
/// What is read out as `name`, shown: its rect.
fn HoverRig::trigger(self : HoverRig, name : String) -> (Double, Double, Double, Double) raise {
  match self.t.semantics().filter(fn(s) { s.label == name && !s.hidden }) {
    [s, ..] => s.rect
    [] => fail("none read out as \{name}")
  }
}

///|
/// The middle of what is read out as `name`.
fn HoverRig::middle(self : HoverRig, name : String) -> (Double, Double) raise {
  let r = self.trigger(name)
  (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
}

///|
/// The label of what has the keyboard's focus ("" none).
fn HoverRig::focus(self : HoverRig) -> String {
  match self.t.focused() {
    Some(s) => s.label
    None => ""
  }
}

///|
/// A point well inside trigger `name`.
fn HoverRig::on(self : HoverRig, name : String) -> (Double, Double) raise {
  let r = self.trigger(name)
  (r.0 + 20.0, r.1 + 16.0)
}

///|
/// A point well inside trigger `name`'s card, where it stands at rest: under it, at its start, 6 off.
fn HoverRig::on_card(self : HoverRig, name : String) -> (Double, Double) raise {
  let r = self.trigger(name)
  (r.0 + 40.0, r.1 + r.3 + hover_card_offset + 14.0)
}

///|
/// The card drawn and read out under trigger `name` (its rect), if one is.
fn HoverRig::card(self : HoverRig, name : String) -> (Double, Double, Double, Double)? raise {
  let r = self.trigger(name)
  let cards = self.t
    .semantics()
    .filter(fn(s) { s.role == Group && !s.hidden && s.rect.1 >= r.1 + r.3 && (s.rect.0 - r.0).abs() < 1.0 })
  match cards {
    [c, ..] => Some(c.rect)
    [] => None
  }
}

///|
/// Whether trigger `name`'s card is open.
fn HoverRig::open(self : HoverRig, name : String) -> Bool {
  match self.hands.get(name) {
    Some(h) => @signals.untracked(h.open)
    None => false
  }
}

///|
/// The pointer moved to `at`.
fn HoverRig::move_to(self : HoverRig, at : (Double, Double)) -> Unit {
  self.t.move_to(at.0, at.1)
}

///|
/// Far from both triggers and their cards.
let hover_away : (Double, Double) = (760.0, 480.0)

///|
/// A short while, and a while long enough for a card to have come in whole or gone.
let hover_short_ms : Double = 20.0

///|
let hover_settled_ms : Double = 200.0

///|
test "a card opens as the mouse's pointer has rested on its trigger hover_card_open_ms, not before; under its trigger, at its start, 6 off, 320 wide; the moment it opened its cause's" {
  let h = hover_rig()
  h.move_to(h.on("甲"))
  let t0 = h.t.time()
  h.t.run_for(hover_card_open_ms - hover_short_ms)
  assert_false(h.open("甲"), msg="a moment before its time: not open")
  assert_eq(h.card("甲"), None, msg="a moment before its time: none drawn")
  h.t.run_for(hover_short_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="at its time: open")
  assert_eq(h.turns, [("甲", true, t0 + hover_card_open_ms)], msg="opened at the rest's end")
  let r = h.trigger("甲")
  match h.card("甲") {
    Some(c) => {
      assert_eq((c.0, c.1, c.2), (r.0, r.1 + r.3 + hover_card_offset, hover_card_px), msg="where: \{Repr(c)}, its trigger \{Repr(r)}")
    }
    None => fail("open, none drawn")
  }
  assert_false(h.open("乙"), msg="the other's not")
  assert_eq(h.t.audit(), [])
}

///|
test "a card stays open as the pointer goes from its trigger onto it, across the gap between them; closes hover_card_close_ms after it has left both, at that moment" {
  let h = hover_rig()
  h.move_to(h.on("甲"))
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="open")
  // (into the gap between them a moment, then onto it)
  let r = h.trigger("甲")
  h.t.move_to(r.0 + 40.0, r.1 + r.3 + hover_card_offset / 2.0)
  h.t.run_for(hover_short_ms)
  h.move_to(h.on_card("甲"))
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="on the card, past its close's time: open")
  // (off both: closed its time after)
  h.move_to(hover_away)
  let left = h.t.time()
  h.t.run_for(hover_card_close_ms - hover_short_ms)
  assert_true(h.open("甲"), msg="a moment before its time: open")
  h.t.run_for(hover_short_ms + hover_settled_ms)
  assert_false(h.open("甲"), msg="at its time: closed")
  assert_eq(h.card("甲"), None, msg="gone")
  assert_eq(h.turns.length(), 2, msg="\{Repr(h.turns)}")
  assert_eq(h.turns[1], ("甲", false, left + hover_card_close_ms), msg="closed at the leave's end")
  assert_eq(h.t.audit(), [])
}

///|
test "the pointer going from one trigger to the next: the first's card closes hover_card_close_ms after, the next's opens hover_card_open_ms after, each at its cause's moment" {
  let h = hover_rig()
  h.move_to(h.on("甲"))
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="甲 open")
  h.move_to(h.on("乙"))
  let moved = h.t.time()
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_false(h.open("甲"), msg="甲 closed")
  assert_true(h.open("乙"), msg="乙 open")
  assert_eq(h.turns.length(), 3, msg="\{Repr(h.turns)}")
  assert_eq(h.turns[1], ("甲", false, moved + hover_card_close_ms), msg="甲 closed at its leave's end")
  assert_eq(h.turns[2], ("乙", true, moved + hover_card_open_ms), msg="乙 opened at its rest's end")
  assert_eq(h.t.audit(), [])
}

///|
test "the pointer resting on a trigger held down rests on nothing: its card opens hover_card_open_ms after it is let go there, not before; a click on it its press" {
  let h = hover_rig()
  let (x, y) = h.on("甲")
  h.t.move_to(x, y)
  h.t.touch(0, x, y)
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_false(h.open("甲"), msg="held down past its time: not open")
  h.t.touch(2, x, y)
  let up = h.t.time()
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="let go, rested its time: open")
  assert_eq(h.turns, [("甲", true, up + hover_card_open_ms)], msg="from its letting go")
  assert_eq(h.pressed.get("甲").unwrap_or(0), 1, msg="the click its press")
  assert_eq(h.t.audit(), [])
}

///|
test "a finger, resting on nothing, opens a card by holding its trigger long_press_ms (that press no tap); it stays after it is let go, till a press elsewhere, at that moment; a tap its trigger's press, no card" {
  let h = hover_rig(platform=1)
  let (x, y) = h.on("甲")
  h.t.touch(0, x, y)
  h.t.touch(2, x, y)
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_eq(h.pressed.get("甲").unwrap_or(0), 1, msg="a tap: its press")
  assert_false(h.open("甲"), msg="a tap: no card")
  h.t.touch(0, x, y)
  let down = h.t.time()
  h.t.run_for(@ui.long_press_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="held: open")
  h.t.touch(2, x, y)
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="let go, past a mouse's close: still open")
  assert_eq(h.pressed.get("甲").unwrap_or(0), 1, msg="the hold no press")
  // (a press on the card: its own, still open)
  let (cx, cy) = h.on_card("甲")
  h.t.touch(0, cx, cy)
  h.t.touch(2, cx, cy)
  h.t.run_for(hover_settled_ms)
  assert_true(h.open("甲"), msg="a press on it: open")
  // (elsewhere: closed as it goes down)
  h.t.touch(0, hover_away.0, hover_away.1)
  let off = h.t.time()
  h.t.touch(2, hover_away.0, hover_away.1)
  h.t.run_for(hover_settled_ms)
  assert_false(h.open("甲"), msg="a press elsewhere: closed")
  assert_eq(h.turns, [("甲", true, down + @ui.long_press_ms), ("甲", false, off)], msg="\{Repr(h.turns)}")
  assert_eq(h.t.audit(), [])
}

///|
test "a card closes at once at a press outside it and its trigger, and at Escape; the pointer resting on its trigger still, it opens again only once it has left and rested anew" {
  for case in ["press", "escape"] {
    let h = hover_rig()
    h.move_to(h.on("甲"))
    h.t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_true(h.open("甲"), msg="\{case}: open")
    let at = h.t.time()
    if case == "press" {
      // (a mouse's press elsewhere, the pointer there)
      h.t.move_to(hover_away.0, hover_away.1)
      h.t.touch(0, hover_away.0, hover_away.1)
      h.t.touch(2, hover_away.0, hover_away.1)
    } else {
      h.t.key(@ui.key_escape)
    }
    h.t.run_for(hover_settled_ms)
    assert_false(h.open("甲"), msg="\{case}: closed")
    assert_eq(h.turns[1], ("甲", false, at), msg="\{case}: at once: \{Repr(h.turns)}")
    if case == "escape" {
      h.t.run_for(hover_card_open_ms + hover_settled_ms)
      assert_false(h.open("甲"), msg="escape: resting on still: not again")
      h.move_to(hover_away)
      h.t.run_for(hover_short_ms)
      h.move_to(h.on("甲"))
      h.t.run_for(hover_card_open_ms + hover_settled_ms)
      assert_true(h.open("甲"), msg="escape: left and rested anew: open")
    }
    assert_eq(h.t.audit(), [], msg=case)
  }
}

///|
test "a card closes at once as its trigger takes input no more (its holder said to take no press, a modal layer over it); one waiting to open never opens past its time" {
  for case in ["holder", "modal"] {
    let takes = @signals.signal(true)
    let modal = @signals.signal(false)
    let cover = fn(on : Bool) { if case == "holder" { takes.set(!on) } else { modal.set(on) } }
    let h = hover_rig(takes~, modal~)
    h.move_to(h.on("甲"))
    h.t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_true(h.open("甲"), msg="\{case}: open")
    cover(true)
    let at = h.t.time()
    h.t.run_for(hover_settled_ms)
    assert_false(h.open("甲"), msg="\{case}: closed")
    assert_eq(h.turns[1], ("甲", false, at), msg="\{case}: at once: \{Repr(h.turns)}")
    // (waiting: never)
    cover(false)
    h.move_to(hover_away)
    h.t.run_for(hover_short_ms)
    h.move_to(h.on("甲"))
    h.t.run_for(hover_short_ms)
    cover(true)
    h.t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_false(h.open("甲"), msg="\{case}: while it waited: never")
    assert_eq(h.turns.length(), 2, msg="\{case}: \{Repr(h.turns)}")
    cover(false)
    assert_eq(h.t.audit(), [], msg=case)
  }
}

///|
test "a card kept open by the app (held) stays as the pointer leaves both, as a press lands outside, at Escape and under a modal layer; let go, it closes hover_card_close_ms after, the pointer off both" {
  let held = @signals.signal(false)
  let modal = @signals.signal(false)
  let h = hover_rig(held~, modal~)
  h.move_to(h.on("甲"))
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="open")
  held.set(true)
  h.move_to(hover_away)
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="held, off both: open")
  h.t.touch(0, hover_away.0, hover_away.1)
  h.t.touch(2, hover_away.0, hover_away.1)
  h.t.run_for(hover_settled_ms)
  assert_true(h.open("甲"), msg="held, a press outside: open")
  h.t.key(@ui.key_escape)
  h.t.run_for(hover_settled_ms)
  assert_true(h.open("甲"), msg="held, Escape: open")
  modal.set(true)
  h.t.run_for(hover_settled_ms)
  assert_true(h.open("甲"), msg="held, under a modal layer: open")
  modal.set(false)
  h.t.run_for(hover_short_ms)
  held.set(false)
  let let_go = h.t.time()
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_false(h.open("甲"), msg="let go: closed")
  assert_eq(h.turns.length(), 2, msg="\{Repr(h.turns)}")
  assert_eq(h.turns[1], ("甲", false, let_go + hover_card_close_ms), msg="its close's time after it was let go")
  assert_eq(h.t.audit(), [])
}

///|
test "the focus taken into a card by Tab: Escape closes it at once, the focus back on its trigger; the pointer gone off both meanwhile, it closes hover_card_close_ms after and the focus goes back the same" {
  for case in ["escape", "leave"] {
    let h = hover_rig()
    h.move_to(h.on("甲"))
    h.t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_true(h.open("甲"), msg="\{case}: open")
    for _ in 0..<8 {
      if h.focus() == "甲的键" {
        break
      }
      h.t.tab()
    }
    assert_eq(h.focus(), "甲的键", msg="\{case}: Tab into it")
    let at = h.t.time()
    if case == "escape" {
      h.t.key(@ui.key_escape)
      h.t.run_for(hover_settled_ms)
      assert_eq(h.turns[1], ("甲", false, at), msg="escape: at once: \{Repr(h.turns)}")
    } else {
      h.move_to(hover_away)
      h.t.run_for(hover_card_close_ms + hover_settled_ms)
      assert_eq(h.turns[1], ("甲", false, at + hover_card_close_ms), msg="leave: its close's time after: \{Repr(h.turns)}")
    }
    assert_false(h.open("甲"), msg="\{case}: closed")
    assert_eq(h.focus(), "甲", msg="\{case}: the focus back on its trigger")
    assert_eq(h.t.audit(), [], msg=case)
  }
}

///|
test "the pointer over a card where nothing in it is pressed is the arrow; over what in it is pressed, the hand; over its trigger, the hand" {
  let h = hover_rig()
  h.move_to(h.on("甲"))
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("甲"), msg="open")
  h.move_to(h.on_card("甲"))
  h.t.run_for(hover_short_ms)
  assert_eq(h.t.cursor(), Arrow, msg="its ground")
  h.move_to(h.middle("甲的键"))
  h.t.run_for(hover_short_ms)
  assert_eq(h.t.cursor(), Hand, msg="its key")
  h.move_to(h.on("甲"))
  h.t.run_for(hover_short_ms)
  assert_eq(h.t.cursor(), Hand, msg="its trigger")
  assert_eq(h.t.audit(), [])
}

///|
test "a finger's long press opens the card of a trigger that is pressed for nothing (a name in a bar), at long_press_ms, what holds it not pressed; a press elsewhere closes it" {
  let h = hover_rig(platform=1)
  let (x, y) = h.middle("丙")
  h.t.touch(0, x, y)
  let down = h.t.time()
  h.t.run_for(@ui.long_press_ms + hover_settled_ms)
  assert_true(h.open("丙"), msg="held: open")
  h.t.touch(2, x, y)
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_true(h.open("丙"), msg="let go: still open")
  assert_eq(h.pressed.get("外").unwrap_or(0), 0, msg="held: what holds it not pressed")
  assert_eq(h.t.audit(), [], msg="open")
  h.t.touch(0, hover_away.0, hover_away.1)
  let off = h.t.time()
  h.t.touch(2, hover_away.0, hover_away.1)
  h.t.run_for(hover_settled_ms)
  assert_false(h.open("丙"), msg="a press elsewhere: closed")
  assert_eq(h.turns, [("丙", true, down + @ui.long_press_ms), ("丙", false, off)], msg="\{Repr(h.turns)}")
  assert_eq(h.t.audit(), [], msg="at rest")
}

///|
test "a trigger pressed for nothing (a name in a bar): a tap or a click on it is what holds it's (the row pressed), and opens no card; the mouse's pointer resting on it hover_card_open_ms opens its card" {
  for platform in [0, 1] {
    let h = hover_rig(platform~)
    let (x, y) = h.middle("丙")
    if platform == 0 {
      h.t.move_to(x, y)
    }
    h.t.touch(0, x, y)
    h.t.touch(2, x, y)
    // (a mouse's let go there: resting from then)
    let up = h.t.time()
    h.t.run_for(hover_short_ms)
    assert_false(h.open("丙"), msg="\{platform}: tapped: none")
    assert_eq(h.pressed.get("外").unwrap_or(0), 1, msg="\{platform}: tapped: what holds it pressed")
    if platform == 0 {
      h.t.run_for(hover_card_open_ms + hover_settled_ms)
      assert_true(h.open("丙"), msg="rested: open")
      assert_eq(h.turns, [("丙", true, up + hover_card_open_ms)], msg="\{Repr(h.turns)}")
    }
    assert_eq(h.t.audit(), [], msg="\{platform}")
  }
}

///|
test "a trigger pressed for nothing still takes a finger's long press, so it is held to the room a press takes: laid out with less (60 by 32 to be pressed in), t.audit() says so" {
  for platform in [0, 1] {
    let h = hover_rig(platform~, cramped=true)
    let faults = h.t.audit()
    let least = if platform == 0 { "36" } else { "44" }
    assert_eq(faults.length(), 1, msg="\{platform}: \{Repr(faults)}")
    assert_true(
      faults[0].has_prefix("room: ") && faults[0].contains("60×20") && faults[0].contains("has 60×32 to be pressed in, under \{least}"),
      msg="\{platform}: \{Repr(faults)}",
    )
  }
}

///|
test "a trigger only a finger's tap is said for (a station's name in a bar that drags the window): a mouse's press on it is what holds it's, its drag begun, none of its own; the mouse resting on it opens its card; a finger's tap on it its own, not what holds it's" {
  let modal = @signals.signal(false)
  let h = hover_rig(modal~)
  let (x, y) = h.middle("丁")
  h.t.move_to(x, y)
  h.t.touch(0, x, y)
  h.t.touch(1, x + 30.0, y)
  h.t.touch(2, x + 30.0, y)
  h.t.run_for(hover_short_ms)
  assert_eq(h.pressed.get("拖").unwrap_or(0), 1, msg="a mouse: what holds it dragged")
  assert_eq(h.pressed.get("丁").unwrap_or(0), 0, msg="a mouse: not its tap")
  h.move_to(hover_away)
  h.t.run_for(hover_short_ms)
  h.move_to((x, y))
  let at = h.t.time()
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("丁"), msg="a mouse resting on it: its card")
  assert_eq(h.turns.filter(fn(tn) { tn.0 == "丁" && tn.1 }).last(), Some(("丁", true, at + hover_card_open_ms)), msg="\{Repr(h.turns)}")
  // (what holds it under a modal layer: taking no input, closed at once)
  modal.set(true)
  h.t.run_for(hover_settled_ms)
  assert_false(h.open("丁"), msg="a mouse: under a modal layer, closed")
  modal.set(false)
  h.t.run_for(hover_settled_ms)
  assert_eq(h.t.audit(), [], msg="a mouse")
  let f = hover_rig(platform=1)
  let (fx, fy) = f.middle("丁")
  f.t.touch(0, fx, fy)
  f.t.touch(2, fx, fy)
  f.t.run_for(hover_short_ms)
  assert_eq(f.pressed.get("丁").unwrap_or(0), 1, msg="a finger: its tap")
  assert_eq(f.pressed.get("拖").unwrap_or(0), 0, msg="a finger: not what holds it's")
  assert_false(f.open("丁"), msg="a finger's tap: no card")
  assert_eq(f.t.audit(), [], msg="a finger")
}

///|
/// The card drawn and read out as wide as a card is, below trigger `name`'s top (its rect), wherever along it, if one is.
fn HoverRig::card_along(self : HoverRig, name : String) -> (Double, Double, Double, Double)? raise {
  let r = self.trigger(name)
  let cards = self.t
    .semantics()
    .filter(fn(s) { s.role == Group && !s.hidden && s.rect.1 > r.1 && (s.rect.2 - hover_card_px).abs() < 0.5 })
  match cards {
    [c, ..] => Some(c.rect)
    [] => None
  }
}

///|
test "a card said along_offset stands that much further along its trigger's side: back by it, its words starting where the trigger's do (sfpages' words_along); on the mouse's rest, as ever" {
  for off in [-16.0, 24.0] {
    let h = hover_rig(along_offset=off)
    h.move_to(h.on("甲"))
    h.t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_true(h.open("甲"), msg="\{off}: open")
    let r = h.trigger("甲")
    match h.card_along("甲") {
      Some(c) => assert_eq((c.0, c.1), (r.0 + off, r.1 + r.3 + hover_card_offset), msg="\{off}: \{Repr(c)}, its trigger \{Repr(r)}")
      None => fail("\{off}: open, none drawn")
    }
    assert_eq(h.t.audit(), [], msg="\{off}")
  }
}

///|
test "a card said a piece of its trigger stands beside that piece (a link in its words), not all of it; along_offset from the piece's start; its hand says the card while it is made" {
  let h = hover_rig(piece=fn(_w, _h) { Some((30.0, 4.0, 40.0, 12.0)) }, along_offset=-5.0)
  h.move_to(h.on("乙"))
  h.t.run_for(hover_card_open_ms + hover_settled_ms)
  assert_true(h.open("乙"), msg="open")
  let r = h.trigger("乙")
  match h.card_along("乙") {
    Some(c) => assert_eq((c.0, c.1), (r.0 + 30.0 - 5.0, r.1 + 4.0 + 12.0 + hover_card_offset), msg="\{Repr(c)}, its trigger \{Repr(r)}")
    None => fail("open, none drawn")
  }
  // (its hand says the card while it is made: what is opened from what it holds stands beside it)
  let card = fn() { @signals.untracked(h.hands["乙"].card) }
  assert_true(card() is Some(_), msg="open: its card said")
  assert_true(@signals.untracked(h.hands["甲"].card) is None, msg="the other's none")
  assert_eq(h.t.audit(), [])
  h.move_to(hover_away)
  h.t.run_for(hover_card_close_ms + hover_settled_ms)
  assert_false(h.open("乙"), msg="left: closed")
  assert_true(card() is None, msg="gone: none said")
}

///|
test "triggers without a mouse press (丙 and 丁) do not light lit_within_node or open their hover card when covered by a non-modal layer above them" {
  let covered = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=500.0, platform=0)
  t.check_looks(false)
  let hands : Map[String, HoverHand] = Map([])
  let k_bing : Ref[@view.View?] = Ref(None)
  let k_ding : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(row) {
      row.row(Is(true)) |> ignore
      row.box(fn(o) {
        o.width(Is(Some(120.0))).height(Is(Some(44.0))).says(Is(Some(@view.said(Button, label="外")))) |> ignore
        presses_node(o, fn() {  })
        o.box(fn(k) {
          k_bing.val = Some(k)
          k.width(Is(Some(60.0))).height(Is(Some(20.0))).says(Is(Some(@view.said(Text, label="丙")))) |> ignore
          hands["丙"] = hover_card_node(tips, k, fn(b) { hover_card_body(b, "丙", Map([])) })
        })
        |> ignore
      })
      |> ignore
      row.box(fn(o) {
        o
        .width(Is(Some(120.0)))
        .height(Is(Some(44.0)))
        .says(Is(Some(@view.said(Group, label="拖"))))
        .on_drag(fn(_d) {  })
        |> ignore
        o.box(fn(k) {
          k_ding.val = Some(k)
          k.width(Is(Some(60.0))).height(Is(Some(20.0))).says(Is(Some(@view.said(Text, label="丁")))) |> ignore
          hands["丁"] = hover_card_node(tips, k, fn(b) { hover_card_body(b, "丁", Map([])) }, tapped=fn() {  })
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // Non-modal covering bar over the triggers
    root.show(fn() { covered.get() }, fn(bar) {
      bar
      .over(Is(true))
      .width(Is(Some(400.0)))
      .height(Is(Some(60.0)))
      .ground(Is(0xFFFFFFFFL))
      |> ground_node
      |> ignore
    })
    layer.val = Some(root.box(fn(l) { l.over(Is(true)).over_all(Is(true)) |> ignore }))
  })
  t.draw()
  for item in [("丙", k_bing), ("丁", k_ding)] {
    let (name, vref) = item
    let r = match t.semantics().filter(fn(s) { s.label == name && !s.hidden }) {
      [s, ..] => s.rect
      [] => fail("none read out as \{name}")
    }
    let (x, y) = (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.move_to(x, y)
    t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_false(@signals.untracked(fn() { lit_within_node(vref.val.unwrap()) }), msg="\{name} covered: not lit")
    assert_false(@signals.untracked(hands[name].open), msg="\{name} covered: card closed")
  }
  covered.set(false)
  t.run_for(hover_short_ms)
  for item in [("丙", k_bing), ("丁", k_ding)] {
    let (name, vref) = item
    let r = match t.semantics().filter(fn(s) { s.label == name && !s.hidden }) {
      [s, ..] => s.rect
      [] => fail("none read out as \{name}")
    }
    let (x, y) = (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    t.move_to(hover_away.0, hover_away.1)
    t.run_for(hover_short_ms)
    t.move_to(x, y)
    t.run_for(hover_card_open_ms + hover_settled_ms)
    assert_true(@signals.untracked(fn() { lit_within_node(vref.val.unwrap()) }), msg="\{name} uncovered: lit")
    assert_true(@signals.untracked(hands[name].open), msg="\{name} uncovered: card open")
  }
}
