// A natural old view can be measured between frames. Its decorative covers belong to its next real build.

///|
let cover_input_after_frame_ms : Double = 4.0

///|
test "a cover asked during old-view measurement does not outlive the measured nodes" {
  let active = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, natural=true, fn(c) {
      c.box(w=Px(140.0), h=Px(40.0), fn() {
        let holder = c.layer(fn() { })
        let item = c.box(w=Px(60.0), h=Px(20.0), fn() { })
        if active.get() {
          c.cover("measured cover", holder, [item], 0, fn(c, w, h) {
            c.box(w=Px(w), h=Px(h), bg=0x13579bffL, fn() { }) |> ignore
          })
        }
      }) |> ignore
    }) |> ignore
  })
  t.frame()
  let tree = view_tree().unwrap()
  tree.event(t.time(), fn() { active.set(true) })
  tree.bring_to(t.time())
  assert_true(g().cover_asks.is_empty(), msg="a measurement's nodes cannot be used by a later frame")
  t.frame()
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x13579bffL }), msg="the real build still draws its cover")
}

///|
test "an old-view input build cannot leave its covers for the next frame" {
  let active = @signals.signal(false)
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, stable=false)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, natural=true, fn(c) {
      let id = c.id("trigger")
      if c.clicked(id) { active.set(true) }
      c.box(w=Px(140.0), h=Px(40.0), fn() {
        let holder = c.layer(fn() { })
        let item = c.box(id~, w=Px(60.0), h=Px(20.0), fn() { })
        if active.get() {
          c.cover("input cover", holder, [item], 0, fn(c, w, h) {
            c.box(w=Px(w), h=Px(h), bg=0x13579bffL, fn() { }) |> ignore
          })
        }
      }) |> ignore
    }) |> ignore
  })
  t.frame_at(16.0)
  t.advance(cover_input_after_frame_ms)
  finger(0, 20.0, 10.0)
  finger(2, 20.0, 10.0)
  assert_true(active.get(), msg="the click was handled before the next frame")
  assert_true(g().cover_asks.is_empty(), msg="an input build's covers do not belong to the next frame")
  t.frame_at(40.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x13579bffL }), msg="the real build still draws its cover")
}
