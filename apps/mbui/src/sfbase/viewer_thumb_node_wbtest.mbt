///|
test "a retained thumbnail follows its moving, scaled, clipped node and leaves with its owner" {
  reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let off = @signals.signal(0.0)
  let scale = @signals.signal(1.0)
  let radius = @signals.signal(12.0)
  let shown = @signals.signal(true)
  let motion = @signals.signal((0.0, 0.0))
  @ui.set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(p) {
      p.width(Is(Some(160.0))).height(Is(Some(120.0))).offset(Is((20.0, 30.0))).clips(Is(true))
      .drawn_off(By(fn() { motion.get() })) |> ignore
      note_list_node(p, "messages", fn() { 10.0 }, fn() { 20.0 })
      p.box(fn(thumb) {
        thumb.width(Is(Some(80.0))).height(Is(Some(60.0))).ground(Is(0xFFFFFFFFL)).radius(By(fn() { radius.get() }))
        .offset(By(fn() { (off.get(), 0.0) })).scale(By(fn() { scale.get() })) |> ignore
        note_thumb_node(thumb, fn() { "test-picture" }, fn() { radius.get() }, fn() { "mem:test" }, list="messages")
      }) |> ignore
    })
  })
  t.draw()
  let first = thumb_of(t.ctx(), "test-picture").unwrap()
  assert_eq((first.x, first.y, first.w, first.h, first.clear), (20.0, 30.0, 80.0, 60.0, Some((40.0, 130.0))))
  off.set(120.0)
  radius.set(18.0)
  t.draw()
  let next = thumb_of(t.ctx(), "test-picture").unwrap()
  assert_eq((next.x, next.seen, next.corners.each()), (140.0, Some((140.0, 30.0, 40.0, 60.0)), (18.0, 18.0, 18.0, 18.0)))
  scale.set(0.5)
  t.draw()
  let small = thumb_of(t.ctx(), "test-picture").unwrap()
  assert_eq((small.w, small.h, small.corners.each()), (40.0, 30.0, (9.0, 9.0, 9.0, 9.0)))
  motion.set((-10.0, 20.0))
  t.draw()
  let moved = thumb_of(t.ctx(), "test-picture").unwrap()
  assert_eq((moved.x, moved.y), (small.x - 10.0, small.y + 20.0))
  assert_eq(moved.seen, small.seen.map(fn(s) { (s.0 - 10.0, s.1 + 20.0, s.2, s.3) }))
  shown.set(false)
  t.draw()
  assert_true(thumb_of(t.ctx(), "test-picture") is None)
  assert_true(!pv_thumbs.contains("test-picture") && !pv_tree_lists.contains("messages"))
}

///|
/// One picture shown three times on one place (a, b, c), the viewer open from a: a let go, it flies back into the one
/// left drawn on the window first as they read, it alone hidden; one left off the window is no place to fly back into,
/// whichever came first.
fn three_showings(b_first : Bool) -> String raise {
  reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let a_here = @signals.signal(true)
  let views : Map[String, @view.View] = {}
  let showing = fn(root : @view.View, name : String, at : (Double, Double)) {
    root.box(fn(thumb) {
      thumb.width(Is(Some(80.0))).height(Is(Some(60.0))).ground(Is(0xFFFFFFFFL)).offset(Is(at)) |> ignore
      views[name] = thumb
      note_thumb_node(thumb, fn() { "test-picture" }, fn() { 0.0 }, fn() { "mem:test" })
    })
    |> ignore
  }
  @ui.set_view_app(fn(root) {
    root.show(fn() { a_here.get() }, fn(p) { showing(p, "a", (20.0, 30.0)) }) |> ignore
    // (b above the window, c on it: laid out one after the other, c lower when after b)
    if b_first {
      showing(root, "b", (20.0, -400.0))
      showing(root, "c", (200.0, 130.0))
    } else {
      showing(root, "c", (200.0, 130.0))
      showing(root, "b", (20.0, -400.0))
    }
  })
  t.draw()
  thumb_pressed(views["a"], "test-picture")
  let pressed = thumb_of(t.ctx(), "test-picture").map(fn(th) { (th.x, th.y) })
  a_here.set(false)
  t.draw()
  thumb_settle(t.ctx(), "test-picture")
  let back = thumb_of(t.ctx(), "test-picture").map(fn(th) { (th.x, th.y) })
  pv_hidden.set("test-picture")
  let shows = ["b", "c"].map(fn(n) { thumb_node_shows(views[n], "test-picture") })
  pv_hidden.set("")
  "pressed at \{pressed}, back to \{back}, b and c show \{shows}"
}

///|
test "a showing pressed let go, another showing of it left: the viewer flies back into the one on the window" {
  inspect(
    [three_showings(true), three_showings(false)].join("\n"),
    content=(
      #|pressed at Some((20, 30)), back to Some((200, 190)), b and c show [1, 0]
      #|pressed at Some((20, 30)), back to Some((200, 130)), b and c show [1, 0]
    ),
  )
}
