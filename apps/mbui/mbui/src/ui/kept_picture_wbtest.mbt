// A picture drawn at a rect of its own (Ctx::picture) in a part kept as its nodes (an old view's island): said again
// of its node where it is put back, wherever the nodes before it now stand; the part kept, not built every frame for it.

///|
/// The pictures drawn now (x, y, w, h), top to bottom.
fn pictures_drawn(t : Tester) -> Array[(Double, Double, Double, Double)] {
  let out = t.drawn_images().map(fn(i) { (i[0], i[1], i[2], i[3]) })
  out.sort_by(fn(a, b) { a.1.compare(b.1) })
  out
}

///|
test "pictures in kept parts: each where its own part says, as nodes before them come and go; the parts not changed not built again; the same as built whole" {
  let extra = @signals.signal(0, same=fn(a, b) { a == b })
  let builds = [0, 0]
  let t = Tester::new(fn(_c) {  }, images=[("a.png", 400, 400), ("b.png", 400, 400)])
  set_view_app(fn(root) {
    // (a part whose nodes grow and shrink: what comes after it stands elsewhere among the frame's nodes)
    old(root, fn(c) {
      for _ in 0..<extra.get() {
        c.box(w=Px(10.0), h=Px(10.0), bg=0x112233FFL, fn() {  }) |> ignore
      }
    })
    .height(Is(Some(40.0)))
    |> ignore
    old(root, fn(c) {
      builds[0] = builds[0] + 1
      c.picture("a.png", x=10.0, y=20.0, w=100.0, h=50.0) |> ignore
    })
    .height(Is(Some(200.0)))
    |> ignore
    old(root, fn(c) {
      builds[1] = builds[1] + 1
      c.picture("b.png", x=30.0, y=5.0, w=60.0, h=120.0) |> ignore
    })
    .height(Is(Some(200.0)))
    |> ignore
  })
  t.drawn_again(true)
  t.check_looks(false)
  t.draw()
  t.drawn_now()
  let at_first = pictures_drawn(t)
  assert_eq(at_first, [(10.0, 60.0, 100.0, 50.0), (30.0, 245.0, 60.0, 120.0)])
  let built = builds.copy()
  // nodes before them added, then taken away: the two kept, each its picture where it was
  for n in [3, 1, 0] {
    extra.set(n)
    t.frame_at(t.time() + frame_period_default)
    assert_eq(pictures_drawn(t), at_first, msg="\{n} before")
    assert_eq(builds, built, msg="\{n} before")
  }
  // built whole from the same state: the same
  t.drawn_again(false)
  extra.set(2)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(pictures_drawn(t), at_first)
}
