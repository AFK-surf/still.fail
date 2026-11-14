// A sheet of the window's tree (sf's sheet_node; the chat's things on 小屏, 80% of the window, its heights 55% and 94%)
// let go under a finger going at a steady speed: it goes on from that speed wherever it goes then, to the height it
// settles at or away as it closes, not stopping dead as the finger leaves it nor setting out afresh from rest (as the
// old frame's sheet did: @kit.sheet hands the finger's speed to its height's spring); where it comes to rest is the
// same at any rate of frames. And what it says to a screen reader, a dialog, is the sheet as it is drawn in the window,
// not the room its foot reaches on under the window's.

///|
/// How many moves a frame apart the finger takes (a steady speed: as far each time).
let let_go_steps : Int = 10

// (the frame after it is let go goes the finger's way at least 0.6 as far as the finger's last move, as a way set out
// at its speed does, its own curve gaining on it a little where it goes far: 1.5 at most; from rest it goes a small
// part of that, stopped dead it goes back)

///|
/// Where the things' sheet is as a screen reader finds it (its dialog), if it is up.
fn let_go_dialog(t : @ui.Tester) -> (Double, Double, Double, Double) {
  match t.query(@ui.Role::Dialog) {
    Some(s) => s.rect
    None => (-1.0, -1.0, -1.0, -1.0)
  }
}

///|
/// The chat's things opened and at rest, its top (its grabber, 20 down it) held and drawn `dy` down in let_go_steps
/// moves, let go: how far its title (where it is drawn, closing or not) went at the finger's last move and over the
/// frame after it was let go (at a rate of frames, the finger's again: what walks its own frames returns at once
/// there), and the Tester.
fn sheet_let_go(dy : Double) -> (@ui.Tester, Double, Double) {
  let (t, src, r) = things_chat()
  open_things(src, r, 7.0)
  t.run_for(sheet_way_ms(t))
  let title = @sf.t("web-main.things.title")
  // (the lowest so named: the sheet's, over the page)
  let top = fn() { t.words().filter(fn(w) { w.0 == title }).fold(init=-1.0, fn(y, w) { dmax(y, w.2) }) }
  let (x, y0, w, _) = let_go_dialog(t)
  let (x, y) = (x + w / 2.0, y0 + 20.0)
  let step = dy / let_go_steps.to_double()
  t.hold_drag(x, y, x, y + dy - step, steps=let_go_steps - 1)
  let before = top()
  t.hold_move(x, y + dy)
  let held = top()
  t.release(x, y + dy)
  if @ui.test_at_a_rate() {
    return (t, held - before, held - before)
  }
  t.frame()
  (t, held - before, top() - held)
}

///|
test "a sheet of the tree's let go drawn up short of 94% of the window: on up at the finger's speed, at rest at 94%" {
  // (675.2 tall drawn 110 up: 785.2, nearer 94% (793.4) than 55%)
  let (t, held, after) = sheet_let_go(-110.0)
  assert_true((held + 11.0).abs() < 0.5, msg="the finger's last move: \{held}")
  assert_true(after / held >= 0.6 && after / held <= 1.5, msg="the frame after it was let go: \{after} (the finger's \{held})")
  t.run_for(sheet_way_ms(t))
  assert_true((let_go_dialog(t).3 - 844.0 * 0.94).abs() < 1.0, msg="\{Repr(let_go_dialog(t))}")
}

///|
test "a sheet of the tree's let go drawn down under 30% of the window: away at the finger's speed, closed" {
  // (675.2 tall drawn 450 down: 225.2, under 30% (253.2))
  let (t, held, after) = sheet_let_go(450.0)
  assert_true((held - 45.0).abs() < 0.5, msg="the finger's last move: \{held}")
  assert_true(after / held >= 0.6 && after / held <= 1.5, msg="the frame after it was let go: \{after} (the finger's \{held})")
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
}

///|
test "a sheet of the tree's said to a screen reader as a dialog as tall as it is drawn in the window, its foot at the window's" {
  let (t, src, r) = things_chat()
  open_things(src, r, 7.0)
  t.run_for(sheet_way_ms(t))
  let (x, y, w, h) = let_go_dialog(t)
  assert_eq((x, w), (0.0, 390.0))
  assert_true((h - 844.0 * things_share).abs() < 0.5 && (y + h - 844.0).abs() < 0.5, msg="\{Repr((x, y, w, h))}")
}

///|
/// The chat's things opened and at rest (675.2 tall), its top drawn `dy` down in `steps` moves a frame apart and let
/// go: whether it is open once it has had its way, and how tall it is then.
fn things_let_go(dy : Double, steps : Int) -> (Bool, Double) {
  let (t, src, r) = things_chat()
  open_things(src, r, 7.0)
  t.run_for(sheet_way_ms(t))
  let (x, y0, w, _) = let_go_dialog(t)
  let (x, y) = (x + w / 2.0, y0 + 20.0)
  t.drag(x, y, x, y + dy, steps~)
  t.run_for(sheet_way_ms(t))
  (@sf.presenting(), let_go_dialog(t).3)
}

///|
test "a sheet of the tree's that grows let go above 30% of the window: closed flicked down, at 55% let go slowly" {
  // (drawn 380 down: 295.2, 35%; in 4 moves a frame apart, 5.7 points a ms: flicked, no detent under it, closed)
  let (open, _) = things_let_go(380.0, 4)
  assert_false(open, msg="flicked down to 35%: closed")
  // (in 60, 0.38 points a ms: landing at 34%, the nearest detent 55%)
  let (open, tall) = things_let_go(380.0, 60)
  assert_true(open && (tall - 844.0 * 0.55).abs() < 1.0, msg="let go slowly at 35%: at 55% (\{open}, \{tall})")
  // (either side of 30% slowly: 400 and 460 down in 80 moves, landing at 32% and 25%)
  let (open, _) = things_let_go(400.0, 80)
  assert_true(open, msg="let go slowly at 33%: open")
  let (open, _) = things_let_go(460.0, 80)
  assert_false(open, msg="let go slowly at 25%: closed")
}

///|
/// A sheet held at its top, drawn `dy` down in `steps` moves (a frame apart: as fast as that), let go short of where it
/// would close or go to its next height; from the finger's last move, a frame each `ms` till it is back where it stood:
/// where its top was at each (the chat's things, as tall as it can grow, or a panel of nodes).
fn let_go_back(grows : Bool, dy : Double, steps : Int, ms : Double) -> Array[Double] {
  let t = if grows {
    let (t, src, r) = things_chat()
    open_things(src, r, 7.0)
    t
  } else {
    let t = phone_tester()
    @sf.panel_nodes("面板", from=Unanchored, foot=fn(v, _) { ink_node(v, 60.0, 36.0, foot_ink) }, fn(v, _) {
      ink_node(v, 40.0, 36.0, body_ink)
    })
    t
  }
  t.run_for(sheet_way_ms(t))
  let (x, y0, w, _) = let_go_dialog(t)
  let (x, y) = (x + w / 2.0, y0 + 20.0)
  t.press_at(x, y)
  for i in 1..=steps {
    t.hold_move(x, y + dy * i.to_double() / steps.to_double())
  }
  let tops = [let_go_dialog(t).1]
  t.release(x, y + dy)
  let end = t.time() + sheet_way_ms(t)
  while t.time() < end {
    t.frame(ms~)
    tops.push(let_go_dialog(t).1)
  }
  tops
}

///|
test "a sheet let go going down, short of closing or its next height: back where it stood never hanging near still at its turn, at 60 and 120 a second" {
  // (what walks its own frames returns at once at a rate)
  if @ui.test_at_a_rate() {
    return
  }
  for ms in [1000.0 / 60.0, 1000.0 / 120.0] {
    // (a panel drawn 40 down at 0.3 points a ms; the things' sheet, at its tallest, 380 down at 0.38)
    assert_not_hung(let_go_back(false, 40.0, 8, ms), ms, "a panel, frames \{ms} ms apart")
    assert_not_hung(let_go_back(true, 380.0, 60, ms), ms, "the things' sheet, frames \{ms} ms apart")
  }
}
