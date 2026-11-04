///|
test "a retained list measures the same moving room before and after an old frame is rebuilt" {
  let items = @signals.signal([("a", 60.0, "1")])
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(x) { x.2 })
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, from_end=true,
      room=rows.room, fn(row, k) {
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).map(fn(x) { x.1 }) }))
        .ground(Is(0x3366CCFFL)) |> ignore
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  items.set([("a", 60.0, "1"), ("b", 38.0, "1")])
  t.draw()
  let start = t.time()
  let mut opening = false
  for ms in [7.25, 17.5, 73.75, row_size_ms] {
    t.frame_at(start + ms)
    match t.row(1) {
      Some((_, _, _, h)) if h > 0.0 && h < 38.0 => opening = true
      _ => ()
    }
  }
  assert_true(opening, msg="the new row opens on the frames being compared")
  assert_eq(t.row(1).map(fn(r) { r.3 }), Some(38.0))
}

///|
test "a row kept for a flight is measured outside the reading window without moving that window" {
  let needed : @signals.Signal[Int?] = @signals.signal(None)
  let nodes : Map[Int, @view.View] = {}
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(),
      fn() { Array::makei(20, fn(i) { i }) }, est=60.0,
      kept=fn(k) { needed.get() == Some(k) }, fn(row, k) {
        nodes[k] = row
        row.owns(fn() { nodes.remove(k) }) |> ignore
        row.height(Is(Some(60.0))) |> ignore
      }) |> ignore
  })
  t.draw()
  let before = t.visible()
  assert_false(nodes.contains(19))
  needed.set(Some(19))
  t.draw()
  assert_eq(nodes[19].laid_window_now(), (0.0, 1140.0, 300.0, 60.0))
  assert_eq(t.visible(), before)
  assert_false(nodes.contains(18))
  needed.set(None)
  t.draw()
  assert_false(nodes.contains(19))
  assert_eq(t.visible(), before)
}

///|
test "a retained page's row helpers drive its list with an old sidebar beside it" {
  let t = Tester::new(fn(c) {
    c.box(w=Px(80.0), h=Px(300.0), fn() {
      c.list("sidebar", 100, 30.0, fn(i) {
        c.box(h=Px(30.0), fn() { c.text("chat \{i}") |> ignore }) |> ignore
      }) |> ignore
    }) |> ignore
  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(300.0))).height(Is(Some(300.0))).offset(Is((100.0, 0.0)))
      .scrolls_window(@view.Scroll::list(), fn() { Array::makei(20, fn(i) { i }) }, est=60.0, from_end=true,
        fn(row, _) { row.height(Is(Some(60.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(t.at_end())
  assert_eq(t.visible(), (15, 19))
  t.scroll_to(4)
  t.draw()
  assert_eq(t.visible().0, 4)
  assert_eq(t.row(4), Some((100.0, 0.0, 300.0, 60.0)))
  assert_eq(t.rows()[0], (4, 0.0, 60.0))
  assert_false(t.at_end())
}

///|
test "a retained row changes its content in the cause that replaces it, keeping its identity" {
  let items = @signals.signal([("a", 60.0, "sending")])
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  let made = Ref(0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(x) { x.2 })
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, from_end=true,
      room=rows.room, fn(row, k) {
        made.val += 1
        let item = fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).unwrap() }
        row.height(By(fn() { Some(item().1) })).pick(fn() { item().2 }, fn(words, label) {
          words.words(Is(label)) |> ignore
        })
      }) |> ignore
  })
  t.draw()
  assert_true(t.find("sending") is Some(_))
  items.set([("a", 40.0, "delivered"), ("b", 70.0, "working")])
  t.draw()
  assert_true(t.find("sending") is None)
  assert_true(t.find("delivered") is Some(_))
  assert_eq(made.val, 2)
}

///|
fn node_rows_test(
  items : @signals.Signal[Array[(String, Double, String)]],
  nodes : Map[String, @view.View],
  made : Ref[Int],
) -> (Tester, NodeRows[(String, Double, String)]) {
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  let out : Ref[NodeRows[(String, Double, String)]?] = Ref(None)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(x) { x.2 }, middle=fn(_) { false })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, from_end=true,
      room=rows.room, fn(row, k) {
        made.val += 1
        nodes[k] = row
        row.owns(fn() { nodes.remove(k) }) |> ignore
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).map(fn(x) { x.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  t.run_for(row_size_ms)
  (t, out.val.unwrap())
}

///|
test "a retained list opens and closes the row's room, keeping its contents until it is gone" {
  let items = @signals.signal([("a", 80.0, "1")])
  let nodes : Map[String, @view.View] = {}
  let made = Ref(0)
  let (t, rows) = node_rows_test(items, nodes, made)
  let y = fn() { nodes["a"].rect().1 }
  assert_eq(y(), 220.0)
  assert_eq(t.rows(), [(0, 220.0, 80.0)])
  items.set([("a", 80.0, "1"), ("b", 60.0, "1")])
  t.draw()
  assert_true((y() - 220.0).abs() < 1.0, msg="the old row jumps as the new one arrives: \{y()}")
  let mut before = y()
  let mut saw_opening = false
  let start = t.time()
  while t.time() < start + row_size_ms {
    t.run_for(first_frame_ms)
    match t.row(1) {
      Some((_, _, _, h)) if h > 0.0 && h < 60.0 => saw_opening = true
      _ => ()
    }
    let now = y()
    assert_true(now <= before + 0.5)
    before = now
  }
  assert_eq(y(), 160.0)
  assert_true(saw_opening, msg="the row reports its opening room, not just its natural height")
  assert_eq(made.val, 2)
  items.set([("a", 80.0, "1")])
  t.draw()
  assert_true((rows.read)().1.contains("b"), msg="a departing row remains while its room closes")
  let closing = nodes["b"].rect()
  assert_true((y() - 160.0).abs() < 1.0, msg="closing starts from where it was: y=\{y()}, b=\{closing}, at=\{t.time()}")
  t.run_for(row_size_ms)
  assert_eq(y(), 220.0)
  assert_false((rows.read)().1.contains("b"))
  assert_eq(made.val, 2)
}

///|
test "a row shrinking and another arriving share one height curve, with no reversal of their sum" {
  let items = @signals.signal([("a", 80.0, "1"), ("b", 80.0, "1")])
  let nodes : Map[String, @view.View] = {}
  let made = Ref(0)
  let (t, _) = node_rows_test(items, nodes, made)
  assert_eq(nodes["a"].rect().1, 140.0)
  items.set([("a", 20.0, "2"), ("b", 80.0, "1"), ("c", 60.0, "1")])
  t.draw()
  let start = t.time()
  while t.time() < start + row_size_ms {
    let y = nodes["a"].rect().1
    assert_true((y - 140.0).abs() <= 0.5, msg="the total height changed while equal rooms traded places: \{y}")
    t.run_for(first_frame_ms)
  }
  assert_eq(made.val, 3)
}

///|
test "a glide to a retained list's end follows the room that opens on its way" {
  let items = @signals.signal(Array::makei(10, fn(i) { (i, 80.0) }))
  let follows = @signals.signal(false)
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0.to_string() }, fn(_) { "1" }, middle=fn(_) { false })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { (rows.read)().1 }, from_end=true, follows~,
      room=rows.room, fn(row, k) {
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0.to_string() == k }).map(fn(x) { x.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  assert_eq(scroll.drawn(view_tree().unwrap()), 0.0)
  let old_end = scroll.most()
  follows.set(true)
  scroll.glide_to(old_end)
  t.frame()
  items.set(items.get() + [(10, 160.0)])
  t.draw()
  // The room opens over Move; even a glide over the whole new list takes only its declared easing duration.
  t.run_for(move_most_ms + @view.ease_end(660.0, 0.0))
  assert_eq(scroll.most(), 660.0)
  assert_true((scroll.drawn(view_tree().unwrap()) - scroll.most()).abs() < 0.5,
    msg="the list stopped at the old end: \{scroll.drawn(view_tree().unwrap())}, now \{scroll.most()}")
  assert_true(follows.get())
}

///|
test "a retained list being wheeled away from its end keeps the hand's destination as rows are measured" {
  let follows = @signals.signal(true)
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let items = Array::makei(10, fn(i) { i })
    let rows = ListRows::new().in_node(root, fn() { items }, fn(i) { i.to_string() }, fn(_) { "1" })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { (rows.read)().1 }, from_end=true, follows~,
      room=rows.room, fn(row, k) {
        row.height(Is(Some(if k == "4" { 160.0 } else { 80.0 }))) |> ignore
      }) |> ignore
  })
  t.draw()
  assert_eq(scroll.most(), 500.0)
  t.wheel_phase(150.0, 150.0, -400.0, 4)
  t.run_for(@view.ease_end(-400.0, 0.0))
  assert_eq(scroll.most(), 580.0)
  assert_true(scroll.drawn(view_tree().unwrap()) < scroll.most() - 300.0,
    msg="the wheel was sent back to the end: \{scroll.drawn(view_tree().unwrap())}, end \{scroll.most()}")
  assert_false(follows.get())
}

///|
test "an unmeasured row entering above the words being read does not push those words away from the wheel" {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let items = Array::makei(10, fn(i) { i })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { items }, from_end=true, fn(row, k) {
      row.height(Is(Some(if k == 4 { 800.0 } else { 80.0 }))) |> ignore
    }) |> ignore
  })
  t.draw()
  let before = t.row(6).unwrap().1
  t.wheel(150.0, 150.0, -200.0)
  let after = t.row(6).unwrap().1
  assert_eq(after, before + 200.0, msg="the new height moved the words past the hand: \{before} to \{after}")
}

///|
test "a newly revealed row keeps the reading position through its island's first measurement" {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let items = Array::makei(10, fn(i) { i })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { items }, from_end=true, fn(row, k) {
      if k == 4 {
        row.box(fn(head) { head.height(Is(Some(20.0))) |> ignore }) |> ignore
        old(row, natural=true, fn(c) {
          c.box(w=Fill(1.0), h=Px(780.0), fn() { c.text("上方的图片说明") |> ignore }) |> ignore
        }) |> ignore
      } else {
        row.height(Is(Some(80.0))) |> ignore
      }
    }) |> ignore
  })
  t.draw()
  let before = t.row(6).unwrap().1
  t.wheel(150.0, 150.0, -200.0)
  assert_eq(t.row(6).map(fn(r) { r.1 }), Some(before + 200.0))
}

///|
test "jumping to a retained row replaces the previous reading anchor before its island is measured" {
  let scroll = @view.Scroll::list()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let items = Array::makei(10, fn(i) { i })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { items }, from_end=true, fn(row, k) {
      if k == 4 {
        row.box(fn(head) { head.height(Is(Some(20.0))) |> ignore }) |> ignore
        old(row, natural=true, fn(c) {
          c.box(w=Fill(1.0), h=Px(780.0), fn() { c.text("跳到图片这行的开头") |> ignore }) |> ignore
        }) |> ignore
      } else {
        row.height(Is(Some(80.0))) |> ignore
      }
    }) |> ignore
  })
  t.draw()
  t.scroll_to(4)
  t.draw()
  assert_eq(t.row(4).map(fn(r) { (r.1, r.3) }), Some((0.0, 800.0)))
}

///|
test "a saved position inside an island's row is restored after that row is measured in full" {
  let scroll = @view.Scroll::list()
  let put = @signals.signal(Some((4, -35.5)))
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let items = Array::makei(10, fn(i) { i })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { items }, from_end=true, put~, fn(row, k) {
      if k == 4 {
        row.box(fn(head) { head.height(Is(Some(20.0))) |> ignore }) |> ignore
        old(row, natural=true, fn(c) {
          c.box(w=Fill(1.0), h=Px(780.0), fn() { c.text("保留图片里的阅读位置") |> ignore }) |> ignore
        }) |> ignore
      } else {
        row.height(Is(Some(80.0))) |> ignore
      }
    }) |> ignore
  })
  t.draw()
  assert_eq(t.row(4).map(fn(r) { (r.1, r.3) }), Some((-35.5, 800.0)))
  t.wheel(150.0, 150.0, 100.0)
  assert_eq(t.row(4).map(fn(r) { r.1 }), Some(-135.5))
}

///|
test "a tall retained row opening at the end is read from its top under the cover" {
  let items = @signals.signal([("first", 80.0)])
  let scroll = @view.Scroll::list()
  let follows = @signals.signal(true)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(_) { "1" }, middle=fn(_) { false })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { (rows.read)().1 }, from_end=true, follows~,
      fresh=fn(k) { k == "new" }, cover=fn() { 50.0 }, room=rows.room, fn(row, k) {
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).map(fn(x) { x.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  items.set([("first", 80.0), ("new", 800.0)])
  t.draw()
  t.run_for(move_most_ms + @view.ease_end(800.0, 0.0))
  assert_eq(t.row(1).map(fn(r) { r.1 }), Some(50.0))
  assert_false(follows.get())
}
