// What the app's host lights and how it shapes the pointer where a node of the tree that is pointed at alone
// (View::points) is over an old view (view_host.mbt view_point_tell): it alone lit and shaping the pointer, the old
// view under it not, a click still the old view's; the pointer gone from it, or it pointed at no longer, or a node of
// the tree's taking presses over it, the old view as before.

///|
let ph_old_lit : Int64 = 0x33AA55FFL

///|
let ph_points_lit : Int64 = 0xCC3333FFL

///|
let ph_cover_lit : Int64 = 0x3355CCFFL

///|
let ph_off : Int64 = 0x777777FFL

///|
priv struct PointsHost {
  t : Tester
  /// whether the node over the old button says it is pointed at alone, whether a node taking presses is over both
  points : @signals.Signal[Bool]
  covered : @signals.Signal[Bool]
  /// the old button's clicks
  clicks : Ref[Int]
}

///|
/// An old view's button at the window's top left, 80 by 40 (lit as hovered, counting its clicks, its pointer a hand), under a node of the
/// tree's as big over it that says it is pointed at alone while `points` holds (lit as pointed, its pointer a beam);
/// over both while `covered` holds, one that takes presses (lit as pointed); on a mouse.
fn points_host() -> PointsHost {
  let points = @signals.signal(true, same=fn(a, b) { a == b })
  let covered = @signals.signal(false, same=fn(a, b) { a == b })
  let clicks = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.over(Is(true)).width(Is(Some(150.0))).height(Is(Some(200.0))) |> ignore
      old(b, fn(c) {
        let id = c.id("old-button")
        c.on_press(id, fn() {
          clicks.val = clicks.val + 1
        })
        c.box(w=Px(80.0), h=Px(40.0), id~, bg=if c.hovered(id) { ph_old_lit } else { ph_off }, fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(n) {
      n
      .over(Is(true))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .points(By(fn() { points.get() }))
      .cursor(Is(Some(IBeam)))
      .ground(By(fn() { if n.pointed() { ph_points_lit } else { ph_off } }))
      |> ignore
    })
    |> ignore
    root.show(fn() { covered.get() }, fn(m) {
      m
      .over(Is(true))
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() {  })
      .ground(By(fn() { if m.pointed() { ph_cover_lit } else { ph_off } }))
      |> ignore
    })
  })
  t.draw()
  { t, points, covered, clicks }
}

///|
/// What is lit in the next frame: the old button, the node pointed at alone, the one over both; and the pointer's shape.
fn PointsHost::lit(self : PointsHost) -> (Bool, Bool, Bool, Cursor) {
  self.t.frame_at(self.t.time() + frame_period_default)
  let rects = self.t.drawn_rects()
  let has = fn(k : Int64) { rects.iter().any(fn(r) { r.4 == k }) }
  (has(ph_old_lit), has(ph_points_lit), has(ph_cover_lit), self.t.cursor())
}

///|
test "a node pointed at alone over an old view's button: it alone lit, its pointer's shape; a click still the old button's; the pointer gone, nothing lit" {
  let h = points_host()
  let away = h.lit()
  h.t.move_to(40.0, 20.0)
  let over = h.lit()
  h.t.tap(40.0, 20.0)
  h.t.draw()
  let clicked = h.clicks.val
  h.t.move_to(300.0, 150.0)
  let gone = h.lit()
  assert_eq(
    (away, over, clicked, gone),
    ((false, false, false, Arrow), (false, true, false, IBeam), 1, (false, false, false, Arrow)),
  )
}

///|
test "a still mouse over a node pointed at alone over an old view's button: it pointed at no longer, the old one lit; a node taking presses over both, that one; each gone, as before" {
  let h = points_host()
  h.t.move_to(40.0, 20.0)
  let first = h.lit()
  h.points.set(false)
  let old_lit = h.lit()
  h.points.set(true)
  let again = h.lit()
  h.covered.set(true)
  let covered = h.lit()
  h.covered.set(false)
  let uncovered = h.lit()
  assert_eq(
    (first, old_lit, again, covered, uncovered),
    (
      (false, true, false, IBeam),
      (true, false, false, Hand),
      (false, true, false, IBeam),
      (false, false, true, Hand),
      (false, true, false, IBeam),
    ),
  )
}
