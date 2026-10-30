// A finger on a node of the window's tree held (View::on_drag), as a host hands it on: the node's from down to up, each
// event at its own moment, whatever old view lies under it and whatever frames come.

///|
test "window tree: a finger held on a node over an old view: down, moved off it, up, the node's at their own moments" {
  let seen : Array[(@view.DragIs, Double, Double, Double)] = []
  let old_taps = Ref(0)
  let t = Tester::new(fn(_c) {  })
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) {
      let id = c.id("under")
      if c.clicked(id) {
        old_taps.val = old_taps.val + 1
      }
      c.box(w=Fill(1.0), h=Fill(1.0), id~, fn() {  }) |> ignore
    })
    .over(Is(true))
    |> ignore
    root.box(fn(b) {
      b.over(Is(true)) |> ignore
      b.box(fn(h) {
        h.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push((d.kind, d.x, d.y, d.at)) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.drawn_now()
  let t0 = t.time()
  // (taken late, each said with its own moment)
  t.advance(30.0)
  t.touch_at(0, 10.0, 10.0, t0 + 5.0)
  t.touch_at(1, 200.0, 300.0, t0 + 15.0)
  t.touch_at(2, 210.0, 310.0, t0 + 25.0)
  t.drawn_now()
  assert_eq(seen, [(Down, 10.0, 10.0, t0 + 5.0), (Moved, 200.0, 300.0, t0 + 15.0), (Up, 210.0, 310.0, t0 + 25.0)])
  assert_eq(old_taps.val, 0)
}
