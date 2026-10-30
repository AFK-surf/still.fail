// The bar told what it shows at the moment of what changed it (a page put on the stack, a place come in), whatever
// frames are drawn after: where it is at a moment a function of that moment and what was done, at 60 Hz, 120 Hz or in
// one jump; built again with nothing changed, its ways the same.

///|
/// Where the bar is at `t0 + 160` (the frames' clock) with a page put on the stack at `t0 + 10`, frames drawn at
/// `t0 +` each of `frames` between: when it set out going (from t0), how far shown and to where, the notch, the ball across, how far shown and its size.
fn bar_after_push(frames : Array[Double]) -> (Double, Double, Double, Double, Double, Double, Double) {
  let t = tester("home")
  let rest = bar_rest()
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  let t0 = t.time()
  t.advance(10.0)
  app.nav.push(Settings)
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 160.0)
  (bar.vis.start - t0, bar.vis.value, bar.vis.target, bar.k.x, bar.ball_x.x, bar.ball_alpha.value, bar.ball_scale.value)
}

///|
test "bar: a page put on the stack between frames, the bar going from that moment: the same at a moment, whichever frames came between" {
  let one = bar_after_push([])
  let late = bar_after_push([40.0])
  let many = bar_after_push([11.0, 13.0, 16.0, 24.0, 33.0, 80.0])
  assert_eq((late, many), (one, one))
  // (going from the moment the page was put on: hidden by then, not there yet)
  assert_true((one.0 - 10.0).abs() < 0.000001 && one.1 > 0.0 && one.1 < 1.0 && one.2 == 0.0, msg="\{one}")
}

///|
test "bar: told the same again, at another moment, by a build or as the state is read again: its ways as they were" {
  let t = tester("home")
  let t0 = t.time()
  t.advance(10.0)
  app.nav.push(Settings)
  t.frame_at(t0 + 16.0)
  let ways = fn() {
    (bar.vis.start, bar.vis.from, bar.vis.target, bar.vis.dur, bar.k.to, bar.ball_x.to, bar.ball_alpha.start)
  }
  let first = ways()
  // (the same told again later, as a reaction or a build would)
  bar_tell(bar.told.unwrap(), t0 + 30.0)
  let again = ways()
  // (frames built on at other moments)
  t.frame_at(t0 + 40.0)
  t.frame_at(t0 + 41.0)
  assert_eq((again, ways()), (first, first))
  assert_eq(first.0, t0 + 10.0)
}

///|
/// The tester at rest on the chats, and where it is from then (t0).
fn bar_at_rest() -> (@ui.Tester, Double) {
  let t = tester("home")
  let rest = bar_rest()
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
  (t, t.time())
}

///|
/// How lit place `key` of the bar is (1 lit, 0 not; -1 never drawn).
fn bar_lit(key : String) -> Double {
  match bar.tints.get("bar:" + key) {
    Some(g) => g.value
    None => -1.0
  }
}

///|
/// A place of the bar in the fixture whose notch offers `action` ("plus": ＋, another action than the chats' 令; "":
/// none, the notch closed).
fn bar_place_with(action : String) -> String {
  let src = fixture("home")
  let ws = workspace_in_view(src).0.unwrap()
  let (sets, cur) = bars_in(src, ws.id)
  // (the bar shown's first, then the others')
  let places = sets[cur].copy()
  for set in sets {
    for p in set {
      if !places.contains(p) {
        places.push(p)
      }
    }
  }
  match places.iter().find_first(fn(p) { bar_action(src, ws, Some(p), bar_place_add(src, ws, Some(p))) == action }) {
    Some(p) => p
    None => abort("no place of the bar offers \"\{action}\"")
  }
}

///|
/// Where the bar is at `t0 + 160` with another place come in at `t0 + 10` (its notch's action another), frames drawn at
/// `t0 +` each of `frames` between: the notch's icon and how far its swap is and since when, how lit the place come in
/// and the chats, the ball across.
fn bar_after_place(place : String, frames : Array[Double]) -> (String, Double, Double, Double, Double, Double) {
  let (t, t0) = bar_at_rest()
  t.advance(10.0)
  if !@sfbase.go_place(place) {
    abort("not gone to \{place}")
  }
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 160.0)
  (m_face.val, bar.icon_swap.start - t0, bar.icon_swap.value, bar_lit(place), bar_lit("chats"), bar.ball_x.x)
}

///|
test "bar: another place come in between frames, its notch's action another: the icon's swap, the places lit and the ball from that moment, whichever frames came between" {
  let place = bar_place_with("plus")
  let one = bar_after_place(place, [])
  let late = bar_after_place(place, [40.0])
  let many = bar_after_place(place, [11.0, 13.0, 16.0, 24.0, 33.0, 80.0])
  assert_eq((late, many), (one, one))
  assert_eq(one.0, "plus")
}

///|
/// Where the ball is at `t0 + 160` with the bar's places put in another order at `t0 + 10` (the place shown the same,
/// elsewhere in it), frames drawn at `t0 +` each of `frames` between: across, and since when it goes there.
fn bar_after_order(frames : Array[Double]) -> (Double, Double, Double) {
  let (t, t0) = bar_at_rest()
  let src = fixture("home")
  let ws = workspace_in_view(src).0.unwrap()
  let (sets, cur) = bars_in(src, ws.id)
  let turned = sets.copy()
  turned[cur] = sets[cur].rev()
  t.advance(10.0)
  bars_picked.set(Some((turned, cur)))
  for f in frames {
    t.frame_at(t0 + f)
  }
  t.frame_at(t0 + 160.0)
  (bar.ball_x.x, bar.ball_x.to, bar.ball_x.set_at - t0)
}

///|
test "bar: its places put in another order between frames, the place shown the same: the ball off to it from that moment, whichever frames came between" {
  let one = bar_after_order([])
  let late = bar_after_order([40.0])
  let many = bar_after_order([11.0, 13.0, 16.0, 24.0, 33.0, 80.0])
  assert_eq((late, many), (one, one))
  assert_true((one.2 - 10.0).abs() < 0.000001, msg="\{one}")
}

///|
/// The ball across riding toward 100 from 0, set out at the tester's moment; read at `ahead` first (a frame drawn
/// ahead of the logic) where given, then sent to 50 at 5 ms before the ride's end: where it is then and its way's start.
fn ride_then_sent(ahead : Bool) -> (Double, Double, Double) {
  bar_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=844.0)
  t.draw()
  let s = spr(0.0, 300.0, ball_damping(300.0), "test/ride")
  let at0 = t.time()
  let swap : Swap = { i: 0, n: 0, from: 1.0, key: None, sets: [[]], cur: 0, alpha: 1.0, drop: 0.0, lit: {}, ends: 0.0 }
  let from : RideFrom = { swap, j: 0, w: 346.0, row_top: 0.0, o_to: 0.0, o_end: 0.0, k_to: 0.0, k_end: 0.0 }
  s.ride_on(300.0, fn(_t) { 100.0 }, at0, from, at=at0)
  let end = s.end()
  if ahead {
    s.sample(end + 5.0)
  }
  let then = s.value_at(end - 5.0)
  s.go(50.0, 300.0, ball_damping(300.0), at=end - 5.0)
  (then, s.x, s.set_at - (end - 5.0))
}

///|
test "bar: a ride read ahead past its end, then sent elsewhere at an earlier moment: from where the ride was then, as unread" {
  let unread = ride_then_sent(false)
  let ahead = ride_then_sent(true)
  assert_eq(ahead, unread)
  assert_eq(unread.0, unread.1)
}

///|
/// The bar told, on the chats in a window 466 wide, the system's bars `right` wide down its right side.
fn bar_width_beside(t : @ui.Tester, right : Int) -> Double {
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{right}}}")
  t.run_for(@ui.move_most_ms)
  bar.told.unwrap().width
}

///|
test "bar: told the width of the box it is laid out in, the system's bar down the side taken off it; the window the same, that bar gone: wider" {
  reset()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=466.0, h=678.0, platform=1)
  let beside = bar_width_beside(t, 84)
  let none = bar_width_beside(t, 0)
  assert_eq((beside, none), (466.0 - 84.0 - 44.0, 466.0 - 44.0))
  // (and laid out so: where the ball is, the place shown's, by that width)
  assert_eq(bar.width, none)
}

///|
/// The bar's panel drawn up by a finger from its first place, each event of the host's at its own time from `t0` (down
/// at 10, moving up 64 by 160, let go at 170), frames drawn at each of `frames` (none at all between some) and at 400:
/// where the panel is and whether it is open, the ball, and what the bars are.
fn bar_drawn_up(frames : Array[Double]) -> (Double, Double, Bool, Double, Double) {
  let (t, t0) = bar_at_rest()
  let (xs, y) = bar_places_at()
  let events = [(0, 10.0, 0.0)]
  for i in 1..=15 {
    events.push((1, 10.0 + i.to_double() * 10.0, -64.0 * i.to_double() / 15.0))
  }
  events.push((2, 170.0, -64.0))
  let mut f = 0
  for e in events {
    let (kind, at, dy) = e
    while f < frames.length() && frames[f] <= at {
      t.frame_at(t0 + frames[f])
      f = f + 1
    }
    t.advance(t0 + at - t.time())
    t.touch_at(kind, xs[0], y + dy, t0 + at)
  }
  t.frame_at(t0 + 400.0)
  (bar.o.value_at(t0 + 400.0), bar.o.to, bar.mode.get(), bar.ball_x.x, bar.ball_y.x)
}

///|
test "bar: drawn up by a finger, each event at its own moment: the same at a moment whichever frames came between, or none" {
  let none = bar_drawn_up([])
  let each = bar_drawn_up([15.0, 35.0, 55.0, 75.0, 95.0, 115.0, 135.0, 155.0, 175.0, 250.0])
  let few = bar_drawn_up([100.0])
  assert_eq((each, few), (none, none))
  // (drawn up: open)
  assert_true(none.2, msg="\{none}")
}

///|
/// A finger down on the bar's first place at 10, the window let go of in front at `lost` (or not), let go at 600 with no
/// move: whether the place under it was gone to (a tap) and the lens (held still) ever shown.
fn bar_held_then(lost : Double?) -> (Bool, Bool) {
  let (t, t0) = bar_at_rest()
  let (xs, y) = bar_places_at()
  let start = app.nav.top()
  let lens = Ref(false)
  t.app_state(true, true)
  t.advance(10.0)
  t.touch_at(0, xs[1], y, t0 + 10.0)
  match lost {
    Some(at) => {
      t.advance(t0 + at - t.time())
      t.app_state(true, false)
    }
    None => ()
  }
  for at in [200.0, 300.0, 500.0] {
    t.frame_at(t0 + at)
    if bar.drag >= 0.0 {
      lens.val = true
    }
  }
  t.advance(t0 + 600.0 - t.time())
  t.touch_at(2, xs[1], y, t0 + 600.0)
  t.frame_at(t0 + 700.0)
  (app.nav.top() != start, lens.val)
}

///|
test "bar: held still on a place, let go without moving: the lens while held, then that place as a tap; called off first, nothing" {
  assert_eq(bar_held_then(None), (true, true))
  assert_eq(bar_held_then(Some(50.0)), (false, false))
}
