// What waits breathing as a node (breathe_node) as the old view's breathe: the same opacity at each moment of its
// breath; stopped, back to whole over dur_ms from the moment it stopped, then nothing of the clock read (no frame
// asked of it); waiting again, breathing again; failed, still and whole.

///|
let breathe_test_side : Double = 40.0

///|
/// The square's colour: wholly opaque, so its opacity is its colour's last byte.
let breathe_test_ink : Int64 = 0x336699FFL

///|
/// How far the node is from the old one, along the row.
let breathe_test_apart : Double = 300.0

///|
/// A moment just after another (a hair).
let breathe_test_hair : Double = 1.0

///|
/// How long it is watched once whole (two breaths: any while).
let breathe_test_after : Double = 2800.0

///|
/// A square breathing as an old view draws it at (0, 0) and as a node 300 in, both while `waits` says so.
fn breathe_pair(waits : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=600.0, h=100.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(breathe_test_side))).height(Is(Some(breathe_test_side))) |> ignore
      @ui.old(h, fn(c) {
        let share = @motion.told(c, "breathe-test", if waits.get() { 1.0 } else { 0.0 }, spec=@motion.tween(dur_ms, ease=Out))
        let b = c.box(w=Px(breathe_test_side), h=Px(breathe_test_side), bg=breathe_test_ink, fn() {  })
        breathe(c, b, share~)
      })
      .grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(breathe_test_apart - breathe_test_side))) |> ignore }) |> ignore
    breathe_square(root, waits, fn() { false })
  })
  t.draw()
  t
}

///|
/// The square that breathes, as a node in `parent`.
fn breathe_square(parent : @view.View, waits : @signals.Signal[Bool], failed : () -> Bool) -> Unit {
  parent.box(fn(b) {
    b
    .width(Is(Some(breathe_test_side)))
    .height(Is(Some(breathe_test_side)))
    .ground(Is(breathe_test_ink))
    |> ignore
    breathe_node(b, waits=fn() { waits.get() }, failed~)
  })
  |> ignore
}

///|
/// The opacity of the square drawn on either side (the old view's, the node's: its colour's last byte), -1 for none.
fn breathe_alphas(t : @ui.Tester) -> (Int64, Int64) {
  let mut old = -1L
  let mut new = -1L
  for r in t.drawn_rects() {
    if r.2 == breathe_test_side && r.3 == breathe_test_side {
      if r.0 < breathe_test_apart / 2.0 {
        old = r.4 & 0xFFL
      } else {
        new = r.4 & 0xFFL
      }
    }
  }
  (old, new)
}

///|
/// The opacity of the one square drawn (its colour's last byte), -1 for none.
fn breathe_alone(t : @ui.Tester) -> Int64 {
  match t.drawn_rects().iter().find_first(fn(r) { r.2 == breathe_test_side && r.3 == breathe_test_side }) {
    Some(r) => r.4 & 0xFFL
    None => -1L
  }
}

///|
/// Whether anything of the window's tree reads the clock's cycle (View::cycle): what has frames drawn for it.
fn breathe_reads_clock() -> Bool {
  @ui.view_tree().unwrap().cycle_read()
}

///|
/// Its opacity at moment `at` taking `share` of its breath (breathe's), as a colour's byte.
fn breathe_want(at : Double, share : Double) -> Double {
  let p = at / breath_ms
  let f = p - p.floor()
  let way = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
  (1.0 - 0.5 * share * @ui.Ease::InOut.at(way)) * 255.0
}

///|
test "breathing as a node as the old view's breathe: the same opacity at each moment of its breath" {
  let waits = @signals.signal(true)
  let t = breathe_pair(waits)
  let t0 = t.time()
  let seen = []
  for dt in [0.0, breath_ms / 8.0, breath_ms / 4.0, breath_ms / 2.0, breath_ms * 3.0 / 4.0, breath_ms * 5.0 / 4.0] {
    if dt > 0.0 {
      t.frame_at(t0 + dt)
    }
    let (old, new) = breathe_alphas(t)
    assert_true(old >= 0L && new == old, msg="at \{dt}: old \{old}, node \{new}")
    seen.push(new)
  }
  // (it breathes: not as opaque at every moment)
  assert_true(seen.iter().any(fn(a) { a != seen[0] }), msg="\{Repr(seen)}")
}

///|
test "stopped, back to whole over dur_ms from the moment it stopped, then no frame asked of it; waiting again, breathing again; failed, whole" {
  let waits = @signals.signal(true)
  let failed = @signals.signal(false)
  let root : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) { @ui.old_views_here(c) },
    tree=fn(r) {
      root.val = Some(r)
      breathe_square(r, waits, fn() { failed.get() })
    },
    w=300.0,
    h=300.0,
    platform=0,
  )
  t.run_for(breath_ms / 4.0)
  assert_true(breathe_reads_clock(), msg="breathing: the clock read")
  // (stopped at a moment said, a breath and a quarter in: its cause's moment)
  let stop = t.time() + breath_ms
  root.val.unwrap().at_moment(stop, fn() { waits.set(false) }) |> ignore
  for at in [breathe_test_hair, dur_ms / 2.0] {
    t.run_for(stop + at - t.time())
    let share = 1.0 - @ui.Out.at(at / dur_ms)
    let want = breathe_want(t.time(), share)
    let got = breathe_alone(t)
    assert_true((got.to_double() - want).abs() <= 1.0, msg="at \{at}: \{got} wanted \{want}")
  }
  t.run_for(stop + dur_ms - t.time())
  assert_eq(breathe_alone(t), 0xFFL)
  // (whole: nothing of the clock read, no frame asked of it as the time goes)
  t.run_for(breathe_test_after)
  assert_eq(breathe_alone(t), 0xFFL)
  assert_true(!breathe_reads_clock())
  assert_eq(t.idle_said(), None)
  // (waiting again: breathing again)
  waits.set(true)
  t.run_for(breath_ms / 2.0)
  assert_true(breathe_alone(t) < 0xFFL, msg="\{breathe_alone(t)}")
  assert_true(breathe_reads_clock())
  // (failed: still and whole)
  failed.set(true)
  t.run_for(breath_ms / 4.0)
  assert_eq(breathe_alone(t), 0xFFL)
  assert_eq(t.audit(), [])
}
