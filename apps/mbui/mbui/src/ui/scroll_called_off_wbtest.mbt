// A list pulled past its top and the press called off (the host's word, or a modal layer of the window's tree come
// over the old view the list is in), or let go flicked back into what it pulled: what was pulled goes back from that
// moment, not from the next frame (docs/retained.md: a press called off sets going what it sets going at its cause).
// Two ways, the same moment: the next frame drawn at once, or late; where it is at a moment after both is the same, and
// both are at rest at the end said for its way back. A fling still sets out at its first frame (Compose's playtime 0).

///|
/// What one way came to: whether the list was held pulled past its top as it was called off or let go, and let go
/// as that was told (before any frame); where what it pulled is and whether it moves at `at` + `then`; the end said
/// for its way back; and where it is, whether it moves, at that end.
struct OffWay {
  pulled : Bool
  let_go : Bool
  then : (Double, Bool)
  rest : Double
  at_rest : (Double, Bool)
} derive(Eq, Show, Debug)

///|
/// A finger down on the list at (200, 300) and 10 moves down to 400, then held still: pulled 100 past its top.
fn pull_down(t : Tester) -> Unit {
  t.touch(0, 200.0, 300.0)
  for k in 1..=10 {
    t.advance(drag_step_ms)
    t.touch(1, 200.0, 300.0 + 10.0 * k.to_double())
    t.draw()
  }
  t.advance(tracker_horizon_ms)
  t.draw()
}

///|
/// Whether the list is held by a finger, pulled past an end.
fn held_pulled(t : Tester) -> Bool {
  let st = t.list_state()
  st.held && st.over_state == 1 && st.over > 0.0
}

///|
/// After `off` has called the list off or let it go at `at` (`told`: whether the list was let go as that was told,
/// read before any frame), the next frame drawn `late` after it: the way it went (OffWay), its end that of `rest`
/// where given (the other way's), else its own.
fn off_way(t : Tester, pulled : Bool, told : () -> Bool, at : Double, late : Double, then : Double, rest? : Double) -> OffWay {
  let let_go = told()
  t.frame_at(at + late)
  t.frame_at(at + then)
  let now = (t.list_overscroll(), t.list_moving())
  let end = match rest {
    Some(r) => r
    None => t.list_state().back_rest()
  }
  t.frame_at(end)
  { pulled, let_go, then: now, rest: end, at_rest: (t.list_overscroll(), t.list_moving()) }
}

///|
/// Pulled on `platform`, then called off by the host at the moment it is held so.
fn host_off_way(platform : Int, late : Double, then : Double, rest? : Double) -> OffWay {
  let t = Tester::new(rows_view(100), platform~)
  pull_down(t)
  let pulled = held_pulled(t)
  let at = t.time()
  t.touch_at(3, 200.0, 400.0, at)
  off_way(t, pulled, fn() { !t.list_state().held }, at, late, then, rest?)
}

///|
/// The same list an old view of the window's tree, which shows a modal layer over all of it from a moment it is told
/// (its cause, View::at_moment): pulled, the layer come at the moment it is held so.
fn modal_off_way(platform : Int, late : Double, then : Double, rest? : Double) -> OffWay {
  let t = Tester::new(fn(_c) {  }, platform~)
  let layer = @signals.signal(false, same=fn(a, b) { a == b })
  let root_at : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root_at.val = Some(root)
    old(root, rows_view(100)).grow(Is(1.0)) |> ignore
    root.show(fn() { layer.get() }, fn(m) { m.over(Is(true)).modal(Is(true)).ground(Is(0x00000040L)) |> ignore })
  })
  t.draw()
  pull_down(t)
  let pulled = held_pulled(t)
  let at = t.time()
  root_at.val.unwrap().at_moment(at, fn() { layer.set(true) }) |> ignore
  // (the layer come as the tree is brought to its moment, before any frame: the list let go then)
  let told = fn() {
    view_tree().unwrap().bring_to(at)
    !t.list_state().held
  }
  off_way(t, pulled, told, at, late, then, rest?)
}

///|
/// Both ways (the next frame at once, `late` later), compared at `then` after the moment, the second held to the
/// first's end.
fn both_ways(way : (Double, Double, Double?) -> OffWay, late? : Double = 50.0, then? : Double = 80.0) -> (OffWay, OffWay) {
  let now = way(0.0, then, None)
  (now, way(late, then, Some(now.rest)))
}

///|
/// What a way must have come to: held pulled, let go, going back still at the moment compared, at rest at its end.
fn assert_off(now : OffWay, late : OffWay) -> Unit raise {
  assert_eq(late, now)
  assert_true(
    now.pulled && now.let_go && now.then.0 > 0.0 && now.then.1 && now.at_rest == (0.0, false),
    msg="\{now}",
  )
}

///|
test "Android: a pull past the top called off by the host goes back from that moment, the next frame drawn at once or 50 later" {
  let (now, late) = both_ways(fn(l, th, r) { host_off_way(2, l, th, rest?=r) })
  assert_off(now, late)
}

///|
test "iOS: a pull past the top called off by the host goes back from that moment, the next frame drawn at once or 50 later" {
  let (now, late) = both_ways(fn(l, th, r) { host_off_way(1, l, th, rest?=r) })
  assert_off(now, late)
}

///|
test "Android: a pull past the top under a modal layer come over it goes back from the moment it came, the next frame drawn at once or 50 later" {
  let (now, late) = both_ways(fn(l, th, r) { modal_off_way(2, l, th, rest?=r) })
  assert_off(now, late)
}

///|
test "iOS: a pull past the top under a modal layer come over it goes back from the moment it came, the next frame drawn at once or 50 later" {
  let (now, late) = both_ways(fn(l, th, r) { modal_off_way(1, l, th, rest?=r) })
  assert_off(now, late)
}

///|
/// Android: pulled past the top, then flicked a little back up and let go at the moment it leaves the glass: a fling
/// no further than the stretch, all of it taken by the stretch (Compose's applyToFling), no fling set going.
fn flicked_back_way(late : Double, then : Double, rest? : Double) -> OffWay {
  let t = Tester::new(rows_view(100), platform=2)
  pull_down(t)
  for k in 1..=3 {
    t.advance(drag_step_ms)
    t.touch(1, 200.0, 400.0 - 4.0 * k.to_double())
    t.draw()
  }
  let pulled = held_pulled(t)
  let at = t.time()
  t.touch_at(2, 200.0, 388.0, at)
  // (taken by the stretch: going back already, no fling)
  let taken = fn() {
    let st = t.list_state()
    !st.held && st.over_state == 2 && st.fling == 0
  }
  off_way(t, pulled, taken, at, late, then, rest?)
}

///|
test "Android: a pull past the top flicked back and let go, the flick taken by the stretch, goes back from that moment, the next frame drawn at once or 16 later" {
  // (back fast, the flick's speed with it: compared 24 after, while it is still on its way)
  let (now, late) = both_ways(fn(l, th, r) { flicked_back_way(l, th, rest?=r) }, late=16.0, then=24.0)
  assert_off(now, late)
}
