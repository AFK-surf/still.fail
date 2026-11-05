///|
/// The old box, without or with a child filling it: its ground and edge instances in order.
fn old_edge_with_child(child : Bool) -> Array[Array[Double]] {
  let t = Tester::new(fn(c) {
    c.box(w=Px(40.0), h=Px(24.0), radius=6.0, bg=0xFFFFFF99L, border=1.0, border_color=0x7676764DL, fn() {
      if child {
        c.box(w=Fill(1.0), h=Fill(1.0), bg=0x2050A0FFL, fn() {  }) |> ignore
      }
    }) |> ignore
  }, w=200.0, h=100.0)
  t.draw()
  rects_sized(40.0, 24.0)
}

///|
test "an edge around a conditional child is drawn as the old box as the child comes and goes" {
  let empty = old_edge_with_child(false)
  let full = old_edge_with_child(true)
  let shown = @signals.signal(false)
  let t = Tester::new(fn(_) {  }, w=200.0, h=100.0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card.width(Is(Some(40.0))).height(Is(Some(24.0))).radius(Is(6.0))
      .ground(Is(0xFFFFFF99L)).edge(Is((1.0, 0x7676764DL))) |> ignore
      card.show(fn() { shown.get() }, fn(child) {
        child.width(Is(Some(40.0))).height(Is(Some(24.0))).ground(Is(0x2050A0FFL)) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  assert_eq(rects_sized(40.0, 24.0), empty, msg="nothing shown: the ground and edge are one")
  shown.set(true)
  t.draw()
  assert_eq(rects_sized(40.0, 24.0), full, msg="a child shown: the edge follows it")
  shown.set(false)
  t.draw()
  assert_eq(rects_sized(40.0, 24.0), empty, msg="nothing shown again: the ground and edge are one")
}

///|
test "a conditional child comes and goes beside another layer: the scene's own frames match drawing every layer" {
  let shown = @signals.signal(false)
  let other = @signals.signal(0xAA5533FFL)
  let t = Tester::new(fn(_) {  }, w=200.0, h=100.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(card) {
      card.width(Is(Some(40.0))).height(Is(Some(24.0))).radius(Is(6.0))
      .ground(Is(0xFFFFFF99L)).edge(Is((1.0, 0x7676764DL))) |> ignore
      card.show(fn() { shown.get() }, fn(child) {
        child.width(Is(Some(40.0))).height(Is(Some(24.0))).ground(Is(0x2050A0FFL)) |> ignore
      })
    }) |> ignore
    root.box(fn(sibling) {
      sibling.width(Is(Some(20.0))).height(Is(Some(24.0))).ground(By(fn() { other.get() })) |> ignore
    }) |> ignore
  })
  t.draw()
  let light = Ref(false)
  for on in [false, true, false] {
    shown.set(on)
    t.clock_frame()
    // A following paint-only change lets the scene splice this layer beside the conditional one.
    let was = scene_done().alone
    light.val = !light.val
    other.set(if light.val { 0x339955FFL } else { 0xAA5533FFL })
    t.clock_frame()
    let alone = scene_done().alone > was
    let kept = t.drawn_instances_keyed()
    g().scene_check(-1)
    assert_true(alone, msg="a scene frame after shown=\{on}: \{scene_alone_why()}")
    assert_eq(t.drawn_instances_keyed(), kept, msg="shown=\{on}: a scene frame matches every layer drawn")
  }
}
