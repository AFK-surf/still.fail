// A column's bar taken by the pointer as the host hands it on (on_pointer: the tree brought to the event's moment, what
// is pressed found there): the same place pressed at the same moment takes the same thumb and moves the column as far,
// whatever frames came between what changed and the press. Across, a bar in by what it holds is padded
// (View::scrolls' bar_in_held), that padding changed; down, the column's height changed. What each tree's last frame
// drew is said with it: where the thumb was drawn before the press, by each history.

///|
/// How long after a press its pointer is moved (and after that, moved again).
let hand_move_ms : Double = 10.0

///|
/// When a thumb is held, in the tests that hold it through a change.
let hand_held_at : Double = 316.0

///|
fn hand_bar() -> @view.ScrollBar {
  {
    drawn: fn() { true },
    ink: fn() { 0x00000042L },
    ink_held: fn() { 0x00000073L },
    ease: fn(t) { t },
    size: 3.0,
    inset: 2.0,
    least: 28.0,
    near: 12.0,
    grab: 4.0,
    hold_ms: 900.0,
    fade_ms: 200.0,
  }
}

///|
/// A window 400×300 with the pointer a mouse's: across (not `down`), a column 200×60 scrolling across what it holds,
/// 600 wide padded `pad()` at each side, its bar in by that; `down`, a column 60 wide `tall()` tall scrolling down what it
/// holds, 600 tall. `covered` a button over all of the window while set, `cover` its node and how often it was pressed; `said` what is done with the column as `host`
/// hands on what it has once (on_host_said). Its bar brought out by the wheel at 10, drawn at 0 and 300.
fn hand_window(
  pad : () -> Double,
  down? : Bool = false,
  tall? : () -> Double = fn() { 200.0 },
  covered? : @signals.Signal[Bool] = @signals.signal(false),
  cover? : Ref[(@view.NodeId?, Int)] = Ref((None, 0)),
  host? : OnceHad = OnceHad::new(),
  said? : (@view.View) -> Unit = fn(_) {  },
) -> (Tester, @view.Scroll) {
  let s = if down { @view.Scroll::new() } else { @view.Scroll::across() }
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  t.host_says_finger(Some(false))
  set_view_app(fn(root) {
    root.box(fn(c) {
      (if down {
        c.width(Is(Some(60.0))).height(By(fn() { Some(tall()) }))
      } else {
        c.width(Is(Some(200.0))).height(Is(Some(60.0)))
      })
      .scrolls(s, bar=hand_bar(), bar_in_held=!down, fn(held) {
        if down {
          held.width(Is(Some(60.0))).height(Is(Some(600.0))) |> ignore
        } else {
          held.width(Is(Some(600.0))).height(Is(Some(60.0))).padding(By(fn() { (pad(), 0.0, pad(), 0.0) })) |> ignore
        }
      })
      |> ignore
      on_host_said(root, kind="bar-test", fn() { host.said() }, fn(_) { said(c) })
    })
    |> ignore
    root.show(fn() { covered.get() }, fn(k) {
      cover.val = (Some(k.id()), cover.val.1)
      k.over(Is(true)).on_press(fn() { cover.val = (cover.val.0, cover.val.1 + 1) }) |> ignore
    })
  })
  t.frame_at(0.0)
  if down {
    t.wheel_told(30.0, 100.0, 0.0, 30.0, 0, 10.0)
  } else {
    t.wheel_told(100.0, 30.0, 30.0, 0.0, 0, 10.0)
  }
  t.frame_at(300.0)
  (t, s)
}

///|
/// Its one thumb as drawn last: its left, top, width and height.
fn hand_thumb() -> (Double, Double, Double, Double) {
  let tree = view_tree().unwrap()
  let ids = tree.thumbs_now()
  guard ids.length() == 1 else { abort("one thumb: \{ids.length()}") }
  let d = tree.drawn_of(ids[0]).unwrap()
  (d.x, d.y, d.w, d.h)
}

///|
/// Whether a press held is the thumb's (on_pointer took it as a drag of it, and holds it).
fn hand_holds_thumb() -> Bool {
  let tree = view_tree().unwrap()
  match view_held.val {
    Some(Dragging(id)) => tree.thumbs_now().contains(id)
    _ => false
  }
}

///|
/// What a press at `p` at `at`, moved 10 along (across or down) 10 later and let go there, did: whether the thumb took
/// the press, kept it as it moved, and let it go; how far the column scrolled; where the thumb is drawn at `at` + 40.
priv struct HandPress {
  took : Bool
  kept : Bool
  let_go : Bool
  moved : Double
  drawn : (Double, Double, Double, Double)
} derive(Show, Eq)

///|
fn hand_press(t : Tester, s : @view.Scroll, p : (Double, Double), at : Double, down? : Bool = false) -> HandPress {
  let tree = view_tree().unwrap()
  let (dx, dy) = if down { (0.0, 10.0) } else { (10.0, 0.0) }
  let from = s.at(tree)
  t.advance(at - t.time())
  t.touch_at(0, p.0, p.1, at)
  let took = hand_holds_thumb()
  t.advance(hand_move_ms)
  t.touch_at(1, p.0 + dx, p.1 + dy, at + 10.0)
  let kept = hand_holds_thumb()
  let moved = s.at(tree) - from
  t.touch_at(2, p.0 + dx, p.1 + dy, at + 10.0)
  let let_go = !hand_holds_thumb()
  t.frame_at(at + 40.0)
  { took, kept, let_go, moved, drawn: hand_thumb() }
}

///|
fn hand_alike(a : HandPress, b : HandPress) -> Bool {
  a.took == b.took &&
  a.kept == b.kept &&
  a.let_go == b.let_go &&
  (a.moved - b.moved).abs() < 1.0e-9 &&
  (a.drawn.0 - b.drawn.0).abs() < 1.0e-9 &&
  (a.drawn.1 - b.drawn.1).abs() < 1.0e-9 &&
  (a.drawn.2 - b.drawn.2).abs() < 1.0e-9 &&
  (a.drawn.3 - b.drawn.3).abs() < 1.0e-9
}

///|
/// The middle of the thumb a window drawn by `history` and at `at` draws: one place, the same for each history pressed.
fn hand_middle(
  make : () -> (Tester, @view.Scroll),
  at : Double,
) -> (Double, Double) {
  let (t, _) = make()
  t.frame_at(at)
  let (x, y, w, h) = hand_thumb()
  (x + w / 2.0, y + h / 2.0)
}

///|
test "across, in by its padding: that padding changed alone, one place pressed at one moment takes the thumb and moves the column alike, with a frame between or none" {
  let at = 316.0
  // (the place: the thumb's middle, padded 40 from the start, at the press's moment)
  let p = hand_middle(fn() { hand_window(fn() { 40.0 }) }, at)
  let fresh = {
    let (t, s) = hand_window(fn() { 40.0 })
    hand_press(t, s, p, at)
  }
  let pad_framed = @signals.signal(10.0, same=fn(a, b) { a == b })
  let (framed, framed_before) = {
    let (t, s) = hand_window(fn() { pad_framed.get() })
    pad_framed.set(40.0)
    t.frame_at(308.0)
    let before = hand_thumb()
    (hand_press(t, s, p, at), before)
  }
  let pad_unframed = @signals.signal(10.0, same=fn(a, b) { a == b })
  let (unframed, unframed_before) = {
    let (t, s) = hand_window(fn() { pad_unframed.get() })
    pad_unframed.set(40.0)
    // (as its last frame drew it: padded 10)
    let before = hand_thumb()
    (hand_press(t, s, p, at), before)
  }
  println(
    "across: pressed at \{p}; drawn before it with a frame \{framed_before}, with none \{unframed_before}; fresh \{fresh}",
  )
  assert_true(fresh.took && fresh.kept && fresh.let_go && fresh.moved > 0.0, msg="taken, kept, let go, moving: \{fresh}")
  assert_true(hand_alike(framed, fresh), msg="a frame between: \{framed}")
  assert_true(hand_alike(unframed, fresh), msg="no frame between: \{unframed}")
}

///|
test "across, in by its padding: held, the padding changed, the next move as one held padded so from the start, with a frame between or none" {
  let p10 = hand_middle(fn() { hand_window(fn() { 10.0 }) }, 316.0)
  let p40 = hand_middle(fn() { hand_window(fn() { 40.0 }) }, 316.0)
  // (held at 316, moved 10 at 326, the padding set at 330, moved 10 more at 336; or padded 40 throughout from p40)
  let second = fn(pad0 : Double, p : (Double, Double), frame : Bool) {
    let pad = @signals.signal(pad0, same=fn(a, b) { a == b })
    let (t, s) = hand_window(fn() { pad.get() })
    let tree = view_tree().unwrap()
    t.advance(hand_held_at - t.time())
    t.touch_at(0, p.0, p.1, 316.0)
    let took = hand_holds_thumb()
    t.advance(hand_move_ms)
    t.touch_at(1, p.0 + 10.0, p.1, 326.0)
    pad.set(40.0)
    if frame {
      t.frame_at(330.0)
    }
    let from = s.at(tree)
    t.advance(hand_held_at + 2.0 * hand_move_ms - t.time())
    t.touch_at(1, p.0 + 20.0, p.1, 336.0)
    let kept = hand_holds_thumb()
    let moved = s.at(tree) - from
    t.touch_at(2, p.0 + 20.0, p.1, 336.0)
    (took, kept, moved)
  }
  let base = second(40.0, p40, false)
  let framed = second(10.0, p10, true)
  let unframed = second(10.0, p10, false)
  println("held through a change: as padded 40 throughout \{base}; a frame between \{framed}; none \{unframed}")
  assert_true(base.0 && base.1 && base.2 > 0.0, msg="\{base}")
  assert_true(framed.0 && framed.1 && (framed.2 - base.2).abs() < 1.0e-9, msg="a frame between: \{framed}, \{base}")
  assert_true(unframed.0 && unframed.1 && (unframed.2 - base.2).abs() < 1.0e-9, msg="no frame between: \{unframed}, \{base}")
}

///|
test "across, in by its padding changed with no frame between: a press half a point inside the thumb's end takes it, half a point past it does not, as on one made so" {
  let at = 316.0
  let (x, y, w, _) = {
    let (t, _) = hand_window(fn() { 40.0 })
    t.frame_at(at)
    hand_thumb()
  }
  let mid = y + 2.0 + 4.0
  let each = fn(px : Double) {
    let fresh = {
      let (t, s) = hand_window(fn() { 40.0 })
      hand_press(t, s, (px, mid), at)
    }
    let unframed = {
      let pad = @signals.signal(10.0, same=fn(a, b) { a == b })
      let (t, s) = hand_window(fn() { pad.get() })
      pad.set(40.0)
      hand_press(t, s, (px, mid), at)
    }
    (fresh, unframed)
  }
  for px in [x + 0.5, x - 0.5, x + w - 0.5, x + w + 0.5] {
    let (fresh, unframed) = each(px)
    println("edge at \{px}: fresh \{fresh.took}, none between \{unframed.took}")
    assert_true(hand_alike(unframed, fresh), msg="at \{px}: \{unframed} as \{fresh}")
  }
  assert_true(each(x + 0.5).0.took && !each(x - 0.5).0.took && each(x + w - 0.5).0.took && !each(x + w + 0.5).0.took)
}

///|
test "across, in by its padding changed with no frame between: a button over it takes the press, not the thumb, the column not moved" {
  let at = 316.0
  let p = hand_middle(fn() { hand_window(fn() { 40.0 }) }, at)
  let covered = @signals.signal(false, same=fn(a, b) { a == b })
  let cover : Ref[(@view.NodeId?, Int)] = Ref((None, 0))
  let pad = @signals.signal(10.0, same=fn(a, b) { a == b })
  let (t, s) = hand_window(fn() { pad.get() }, covered~, cover~)
  pad.set(40.0)
  covered.set(true)
  let tree = view_tree().unwrap()
  let from = s.at(tree)
  t.advance(at - t.time())
  t.touch_at(0, p.0, p.1, at)
  // (the press the button's, as the host took it: held by it, over the thumb there at that moment)
  let held = match view_held.val {
    Some(Node(id)) => Some(id)
    _ => None
  }
  let target = tree.target_at(p.0, p.1)
  t.touch_at(2, p.0, p.1, at)
  t.frame_at(at + 40.0)
  assert_true(cover.val.0 is Some(_), msg="the button made")
  assert_eq(held, cover.val.0, msg="the press held by the button")
  assert_true(target == @view.Target::Pressed(cover.val.0.unwrap()), msg="the button over all at the press")
  assert_eq(cover.val.1, 1, msg="pressed once")
  assert_true(!hand_holds_thumb() && s.at(tree) == from, msg="the thumb not taken, the column not moved")
}

///|
test "down: the column's height changed alone, one place pressed at one moment takes the thumb and moves the column alike, with a frame between or none" {
  let at = 316.0
  let p = hand_middle(fn() { hand_window(fn() { 0.0 }, down=true, tall=fn() { 150.0 }) }, at)
  let fresh = {
    let (t, s) = hand_window(fn() { 0.0 }, down=true, tall=fn() { 150.0 })
    hand_press(t, s, p, at, down=true)
  }
  let tall_framed = @signals.signal(200.0, same=fn(a, b) { a == b })
  let (framed, framed_before) = {
    let (t, s) = hand_window(fn() { 0.0 }, down=true, tall=fn() { tall_framed.get() })
    tall_framed.set(150.0)
    t.frame_at(308.0)
    let before = hand_thumb()
    (hand_press(t, s, p, at, down=true), before)
  }
  let tall_unframed = @signals.signal(200.0, same=fn(a, b) { a == b })
  let (unframed, unframed_before) = {
    let (t, s) = hand_window(fn() { 0.0 }, down=true, tall=fn() { tall_unframed.get() })
    tall_unframed.set(150.0)
    let before = hand_thumb()
    (hand_press(t, s, p, at, down=true), before)
  }
  println(
    "down: pressed at \{p}; drawn before it with a frame \{framed_before}, with none \{unframed_before}; fresh \{fresh}",
  )
  assert_true(fresh.took && fresh.kept && fresh.let_go && fresh.moved > 0.0, msg="taken, kept, let go, moving: \{fresh}")
  assert_true(hand_alike(framed, fresh), msg="a frame between: \{framed}")
  assert_true(hand_alike(unframed, fresh), msg="no frame between: \{unframed}")
}

///|
test "across, in by its padding: the padding changed as the host hands something on, the column laid out there (laid_size): the bar painted, pressed and moved as one made so, handed on in a frame before the press or in the frame at its moment" {
  let at = 316.0
  let p = hand_middle(fn() { hand_window(fn() { 40.0 }) }, at)
  let fresh = {
    let (t, s) = hand_window(fn() { 40.0 })
    hand_press(t, s, p, at)
  }
  // (handed on as the frame at 308 begins, drawn by it; or as the frame at the press's own moment begins, drawn then,
  // the press after it at that moment)
  let each = fn(frame : Bool) {
    let host = OnceHad::new()
    let pad = @signals.signal(10.0, same=fn(a, b) { a == b })
    let (t, s) = hand_window(fn() { pad.get() }, host~, said=fn(c) {
      pad.set(40.0)
      c.laid_size() |> ignore
    })
    host.had.val = Some("padded")
    if frame {
      t.frame_at(308.0)
    } else {
      // (the host's hand-off is asked as a frame begins: at the press's own moment, that frame the one it is drawn by)
      t.frame_at(at)
    }
    hand_press(t, s, p, at)
  }
  let framed = each(true)
  let at_press = each(false)
  println("handed on: fresh \{fresh}; in a frame before \{framed}; in the frame at the press \{at_press}")
  assert_true(hand_alike(framed, fresh), msg="a frame before: \{framed}")
  assert_true(hand_alike(at_press, fresh), msg="at the press's frame: \{at_press}")
}
