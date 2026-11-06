///|
priv struct ProjectedSurfaceCase {
  t : Tester
  extent : @signals.Signal[Double]
  surface_taps : Ref[Int]
  scrim_taps : Ref[Int]
  builds : Ref[Int]
}

///|
fn projected_surface_case() -> ProjectedSurfaceCase {
  let extent = @signals.signal(20.0)
  let surface_taps = Ref(0)
  let scrim_taps = Ref(0)
  let builds = Ref(0)
  let t = Tester::new(fn(_) {  }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let measured = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(By(fn() { Some(extent.get()) })) |> ignore
    })
    let projection = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(Is(Some(1.0)))
        .offset(Painted(fn(laid) { (0.0, -laid.size(measured).unwrap_or((0.0, 0.0)).1) })) |> ignore
    })
    old(root, fn(c) {
      builds.val += 1
      let layer = c.overlay("projected", modal=true, scrim=0x40000000L, fn() {
        let id = c.id("moving surface")
        if c.clicked(id) { surface_taps.val += 1 }
        let surface = c.box(left=40.0, top=160.0, w=Px(100.0), h=Px(40.0), bg=0x3366CCFFL, id~, fn() {  })
        c.moved_with_node(surface, projection)
        c.box(left=180.0, top=100.0, w=Px(40.0), h=Px(40.0), bg=0x884422FFL, fn() {  }) |> ignore
      })
      if layer.dismissed is Some(_) { scrim_taps.val += 1 }
    }).over(Is(true)) |> ignore
  })
  t.draw()
  t.drawn_now()
  { t, extent, surface_taps, scrim_taps, builds }
}

///|
test "old projected surface follows retained layout without moving its scrim or sibling" {
  let c = projected_surface_case()
  // Count only the actual build here, not the Tester's separately rebuilt comparison frame.
  c.t.check_looks(false)
  let before = c.builds.val
  let moving = fn() { c.t.drawn_rects().iter().find_first(fn(r) { r.4 == 0x3366CCFFL }).unwrap() }
  let stationary = fn() { c.t.drawn_rects().iter().find_first(fn(r) { r.4 == 0x884422FFL }).unwrap() }
  assert_eq(moving().1, 140.0)
  let fixed = stationary()
  c.extent.set(100.0)
  c.t.drawn_now()
  assert_eq(moving().1, 60.0)
  assert_eq(stationary(), fixed)
  assert_eq(c.builds.val, before)
  // Also compare a projection-only paint with a frame built whole by the Tester's normal scene check.
  c.t.check_looks(true)
  c.extent.set(70.0)
  c.t.drawn_now()
  assert_eq(moving().1, 90.0)
}

///|
test "old projected surface receives an input at its new place before any intermediate frame" {
  let c = projected_surface_case()
  c.extent.set(100.0)
  finger(0, 70.0, 80.0)
  finger(2, 70.0, 80.0)
  c.t.drawn_now()
  assert_eq(c.surface_taps.val, 1)
  assert_eq(c.scrim_taps.val, 0)
}

///|
test "a projected surface becomes hittable after entering from offscreen before a frame" {
  let c = projected_surface_case()
  c.extent.set(250.0)
  c.t.drawn_now()
  c.extent.set(100.0)
  finger(0, 70.0, 80.0)
  finger(2, 70.0, 80.0)
  c.t.drawn_now()
  assert_eq(c.surface_taps.val, 1)
  assert_eq(c.scrim_taps.val, 0)
}

///|
test "a projected old surface leaves the scrim at the previous place" {
  let c = projected_surface_case()
  c.extent.set(100.0)
  finger(0, 70.0, 150.0)
  finger(2, 70.0, 150.0)
  c.t.drawn_now()
  assert_eq(c.surface_taps.val, 0)
  assert_eq(c.scrim_taps.val, 1)
}

///|
test "a projected old surface moves its focused editor's IME at an input before a frame" {
  let height = @signals.signal(20.0)
  let field = Field::new()
  let t = Tester::new(fn(_) {  }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let extent = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(By(fn() { Some(height.get()) })) |> ignore
    })
    let projection = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(Is(Some(1.0)))
        .offset(Painted(fn(laid) { (0.0, -laid.size(extent).unwrap_or((0.0, 0.0)).1) })) |> ignore
    })
    old(root, fn(c) {
      c.overlay("editor projection", modal=true, fn() {
        let surface = c.box(left=40.0, top=160.0, w=Px(200.0), h=Px(60.0), fn() {
          c.editor("projected field", field~, placeholder="Projected field") |> ignore
        })
        c.moved_with_node(surface, projection)
      }) |> ignore
    }).over(Is(true)) |> ignore
  })
  t.draw()
  t.tap_text("Projected field")
  assert_true(t.ime().0)
  let before = t.ime_rect()
  height.set(100.0)
  finger(1, 5.0, 5.0)
  assert_eq(t.ime_rect().1, before.1 - 80.0)
}

///|
test "a passive hold and an old projected surface share the input's current placement" {
  let extent = @signals.signal(20.0)
  let pressed = Ref(0)
  let held = Ref(0)
  let lifted = Ref(0)
  let t = Tester::new(fn(_) {  }, w=300.0, h=300.0, platform=1)
  set_view_app(fn(root) {
    let measured = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(By(fn() { Some(extent.get()) })) |> ignore
    })
    let projection = root.box(fn(v) {
      v.over(Is(true)).width(Is(Some(1.0))).height(Is(Some(1.0)))
        .offset(Painted(fn(laid) { (0.0, -laid.size(measured).unwrap_or((0.0, 0.0)).1) })) |> ignore
    })
    old(root, fn(c) {
      let id = c.id("moving hold surface")
      let surface = c.box(left=40.0, top=160.0, w=Px(100.0), h=Px(40.0), id~, fn() {  })
      c.moved_with_node(surface, projection)
      c.on_press(id, fn() { pressed.val += 1 })
    }).over(Is(true)) |> ignore
    let anchor = root.box(fn(v) {
      v.over(Is(true)).offset(Is((40.0, 60.0))).width(Is(Some(100.0))).height(Is(Some(40.0))) |> ignore
    })
    observe_finger_hold(anchor, fn() { true }, fn() { held.val += 1 }, fn() { lifted.val += 1 }, fn() {  })
  })
  t.draw()
  extent.set(100.0)
  t.touch(0, 70.0, 80.0)
  t.touch(2, 70.0, 80.0)
  assert_eq((pressed.val, held.val, lifted.val), (1, 0, 0))
  t.touch(0, 70.0, 80.0)
  t.advance(long_press_ms)
  t.touch(2, 70.0, 80.0)
  assert_eq((pressed.val, held.val, lifted.val), (1, 1, 1))
}
