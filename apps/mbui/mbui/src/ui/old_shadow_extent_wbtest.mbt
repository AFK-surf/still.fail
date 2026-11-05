// An old view's layout box is not a clip: its drawing can extend into the tree around it.

///|
fn old_shadow_extent(cut : Bool) -> (Tester, @signals.Signal[Bool], Ref[@view.NodeId?]) {
  let shown = @signals.signal(false, same=fn(a, b) { a == b })
  let host : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.over(Is(true)).offset(Is((80.0, 60.0))).width(Is(Some(100.0))).height(Is(Some(80.0))).clips(Is(cut)) |> ignore
      p.show(fn() { shown.get() }, fn(slot) {
        slot.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
        let h = old(slot, fn(c) {
          c.box(w=Px(100.0), h=Px(80.0), bg=0xFFFFFFFFL, radius=12.0, shadow=16.0, shadow_y=12.0,
            shadow_color=0x00000033L, fn() {  }) |> ignore
        })
        h.width(Is(Some(100.0))).height(Is(Some(80.0))) |> ignore
        host.val = Some(h.id())
      })
    }) |> ignore
  })
  t.draw()
  shown.set(true)
  t.draw()
  (t, shown, host)
}

///|
test "an old view without a clipping ancestor draws and damages outside its layout box" {
  let (t, shown, host) = old_shadow_extent(false)
  let shadows = t.drawn_cut().filter(fn(d) { d.0 == 2 && d.3 == 100.0 && d.4 == 80.0 })
  assert_eq(shadows.length(), 1, msg="the old view's shadow")
  let s = shadows[0]
  let (left, top, right, bottom) = s.5
  assert_true(left <= 72.0 && top <= 52.0 && right >= 188.0 && bottom >= 148.0,
    msg="the shadow can draw eight points outside the box: \{s}")
  let reach = scene.reach.get(host.val.unwrap())
  assert_true(reach is Some((l, u, r, d)) && l <= 72.0 && u <= 52.0 && r >= 188.0 && d >= 148.0,
    msg="the hosted layer reaches its shadow: \{reach}")
  shown.set(false)
  t.draw()
  let parts = scene_parts()
  assert_true(parts.iter().any(fn(p) {
    p.2 < 0.0 || (p.0 <= 72.0 && p.1 <= 52.0 && p.0 + p.2 >= 188.0 && p.1 + p.3 >= 148.0)
  }), msg="removing the view redraws the whole shadow: \{parts}")
}

///|
test "an old view is still cut by a tree ancestor that says clips" {
  let (t, _, _) = old_shadow_extent(true)
  let shadows = t.drawn_cut().filter(fn(d) { d.0 == 2 && d.3 == 100.0 && d.4 == 80.0 })
  assert_eq(shadows.length(), 1, msg="the old view's shadow")
  assert_eq(shadows[0].5, (80.0, 60.0, 180.0, 140.0), msg="the ancestor cuts the shadow")
}
