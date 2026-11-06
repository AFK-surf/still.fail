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
/// left seen on the window first as they read, it alone hidden; b, left off the window ("off"), on it but all cut off
/// by what holds it ("cut"), across its top edge with only what is off the window left as it is cut ("edge") or on it
/// in a box drawn see-through ("clear"), is no place to fly back into, whichever came first.
fn three_showings(b_first : Bool, b_is? : String = "off") -> String raise {
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
    // (b above the window, or above c on it in a box cutting it all off; c on it: laid out one after the other, c lower
    // when after b)
    let b = fn() {
      if b_is == "cut" {
        root.box(fn(p) {
          p.width(Is(Some(80.0))).height(Is(Some(20.0))).clips(Is(true)) |> ignore
          showing(p, "b", (0.0, 40.0))
        })
        |> ignore
      } else if b_is == "edge" {
        // (the box from 50 to 10 above the window, b from 30 above it to 30 on it)
        root.box(fn(p) {
          p.width(Is(Some(80.0))).height(Is(Some(40.0))).clips(Is(true))
          .offset(Is((0.0, if b_first { -50.0 } else { -110.0 }))) |> ignore
          showing(p, "b", (0.0, 20.0))
        })
        |> ignore
      } else if b_is == "clear" {
        root.box(fn(p) {
          p.width(Is(Some(80.0))).height(Is(Some(60.0))).alpha(Is(0.0)) |> ignore
          showing(p, "b", (0.0, 0.0))
        })
        |> ignore
      } else {
        showing(root, "b", (20.0, -400.0))
      }
    }
    if b_first {
      b()
      showing(root, "c", (200.0, 130.0))
    } else {
      showing(root, "c", (200.0, 130.0))
      b()
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
  let b_at = views["b"].rect()
  "pressed at \{pressed}, b at \{(b_at.0, b_at.1)}, back to \{back}, b and c show \{shows}"
}

///|
test "a showing pressed let go, another showing of it left: the viewer flies back into the one on the window" {
  inspect(
    [three_showings(true), three_showings(false), three_showings(true, b_is="cut"), three_showings(false, b_is="cut"),
      three_showings(true, b_is="edge"), three_showings(false, b_is="edge"), three_showings(true, b_is="clear"),
      three_showings(false, b_is="clear"),
    ].join(
      "\n",
    ),
    content=(
      #|pressed at Some((20, 30)), b at (20, -400), back to Some((200, 190)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (20, -340), back to Some((200, 130)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, 40), back to Some((200, 150)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, 100), back to Some((200, 130)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, -30), back to Some((200, 170)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, -30), back to Some((200, 130)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, 0), back to Some((200, 190)), b and c show [1, 0]
      #|pressed at Some((20, 30)), b at (0, 60), back to Some((200, 130)), b and c show [1, 0]
    ),
  )
}

///|
/// One picture shown twice on one place, the viewer opened from the first: both let go, in either order: what it looked
/// like, and its place, gone with the last.
fn two_let_go(first_first : Bool) -> String raise {
  reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let here = [@signals.signal(true), @signals.signal(true)]
  let views : Array[@view.View] = []
  @ui.set_view_app(fn(root) {
    for i in 0..<2 {
      root.show(fn() { here[i].get() }, fn(thumb) {
        thumb.width(Is(Some(80.0))).height(Is(Some(60.0))).ground(Is(0xFFFFFFFFL)) |> ignore
        views.push(thumb)
        note_thumb_node(thumb, fn() { "test-picture" }, fn() { 0.0 }, fn() { "mem:test" })
      })
      |> ignore
    }
  })
  t.draw()
  thumb_pressed(views[0], "test-picture")
  let order = if first_first { [0, 1] } else { [1, 0] }
  let after : Array[String] = []
  for i in order {
    here[i].set(false)
    t.draw()
    after.push("\{i} gone: kept \{pv_thumbs.contains("test-picture")}, placed \{pv_tree_thumbs.contains("test-picture")}")
  }
  after.join("; ")
}

///|
test "one picture shown twice, the showing pressed and the other let go in either order: gone with the last" {
  inspect(
    [two_let_go(true), two_let_go(false)].join("\n"),
    content=(
      #|0 gone: kept true, placed true; 1 gone: kept false, placed false
      #|1 gone: kept true, placed true; 0 gone: kept false, placed false
    ),
  )
}

///|
/// One picture shown twice on one place (a, b), the viewer open from a: a let go, then another showing of it, d, come
/// at `d_at`, the viewer shut: where it flies back to, d and b showing how much
/// as it does.
fn came_while_open(d_at : (Double, Double)) -> String raise {
  reset()
  let t = @ui.Tester::new(fn(_) {  }, w=400.0, h=300.0)
  let a_here = @signals.signal(true)
  let d_here = @signals.signal(false)
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
    root.show(fn() { a_here.get() }, fn(p) { showing(p, "a", (20.0, 0.0)) }) |> ignore
    root.show(fn() { d_here.get() }, fn(p) { showing(p, "d", d_at) }) |> ignore
    showing(root, "b", (200.0, 100.0))
  })
  t.draw()
  thumb_pressed(views["a"], "test-picture")
  // (the viewer has the picture: open from a)
  pv_hidden.set("test-picture")
  a_here.set(false)
  t.draw()
  d_here.set(true)
  t.draw()
  pv_hidden.set("")
  t.draw()
  thumb_settle(t.ctx(), "test-picture")
  let back = thumb_of(t.ctx(), "test-picture").map(fn(th) { (th.x, th.y) })
  pv_hidden.set("test-picture")
  let shows = ["d", "b"].map(fn(n) { thumb_node_shows(views[n], "test-picture") })
  pv_hidden.set("")
  let (bx, by, _, _) = views["b"].rect()
  let (dx, dy, _, _) = views["d"].rect()
  "d at \{(dx, dy)}, b at \{(bx, by)}: back to \{back}, d and b show \{shows}"
}

///|
test "the showing pressed let go, the viewer open, another showing come: it flies back into the one seen first" {
  inspect(
    [came_while_open((20.0, -400.0)), came_while_open((20.0, 0.0))].join("\n"),
    content=(
      #|d at (20, -400), b at (200, 160): back to Some((200, 160)), d and b show [1, 0]
      #|d at (20, 0), b at (200, 160): back to Some((20, 0)), d and b show [0, 1]
    ),
  )
}
