// A retained list across its first reading, a change of source, and changes while earlier rows are still going.

///|
test "a retained moving row keeps its focused control through its zero-height first frame" {
  let items = @signals.signal(["a", "b", "c"])
  let buttons : Map[String, @view.View] = {}
  let position : @view.AnchoredPosition[String] = @view.AnchoredPosition::new()
  let scroll = @view.Scroll::list()
  let presses = Ref(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(k) { k }, fn(_) { "" },
      moves=fn(_) { true })
    root.height(Is(Some(300.0))).scrolls_window(scroll, fn() { [..(rows.read)().1, "footer"] }, position~,
      rooms=fn() {
        let room = (rows.room_now)()
        fn(k, natural, width) {
          if k == "footer" { @view.list_room(natural) } else { room(k, natural, width) }
        }
      }, fn(row, k) {
        row.height(Is(Some(50.0))) |> ignore
        if k != "footer" {
          row.box(fn(button) {
            buttons[k] = button
            button.height(Is(Some(50.0))).focusable(Is(true)).says(Is(Some(@view.said(Button, label=k))))
            .on_press(fn() { presses.val += 1 }) |> ignore
          }) |> ignore
        }
      }) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="b")
  let focused = buttons["b"].id()
  // A new zero-height row between the moved row and the old anchor must not hide the moved row either.
  items.set(["b", "new", "a", "c"])
  t.draw()
  let laid = position.geometry().unwrap().rows
  assert_eq(laid[0], ("b", 0.0, 0.0))
  assert_eq(laid[1], ("new", 0.0, 0.0))
  assert_eq(view_tree().unwrap().focused_now().0, Some(focused), msg="laid rows: \{laid}")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("b"))
  assert_eq(scroll.at(view_tree().unwrap()), 0.0)
  assert_eq(scroll.most(), 0.0)
  t.key(key_space)
  assert_eq(presses.val, 1)
  items.set(["a", "c"])
  t.draw()
  assert_true(t.all(Button, label="b").is_empty())
  t.key(key_space)
  assert_eq(presses.val, 1)
}

///|
test "retained rows show a first reading and another source at once, then animate changes to that source" {
  let source : @signals.Signal[(String?, Array[(String, Double)])] = @signals.signal((None, []))
  let out : Ref[NodeRows[(String, Double)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { source.get().1 }, fn(x) { x.0 }, fn(_) { "" },
      continuity=fn() { source.get().0 })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      rooms=rows.room_now, fn(row, k) {
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).map(fn(x) { x.1 }) })) |> ignore
      }) |> ignore
  })
  t.draw()
  source.set((Some("one"), [("a", 60.0)]))
  t.draw()
  let rows = out.val.unwrap()
  assert_eq((rows.read)().1, ["a"])
  assert_eq((rows.room)("a", 60.0).height, 60.0)
  source.set((Some("one"), [("a", 60.0), ("b", 60.0)]))
  t.draw()
  t.run_for(row_size_ms / 4.0)
  let opening = (rows.room)("b", 60.0).height
  assert_true(opening > 0.0 && opening < 60.0, msg="\{opening}")
  let laid = t.row(1).map(fn(r) { r.3 }).unwrap_or(-1.0)
  assert_true(laid > 0.0 && laid < 60.0, msg="the windowed row opens in layout: \{laid}")
  source.set((Some("two"), [("c", 70.0)]))
  t.draw()
  assert_eq((rows.read)().1, ["c"])
  assert_eq((rows.room)("c", 70.0).height, 70.0)
  assert_eq((rows.moving)(), [])
}

///|
test "retained rows open in a top-aligned following window with a separate ground" {
  let items = @signals.signal(["a"])
  let t = Tester::new(fn(_) { }, w=200.0, h=150.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(k) { k }, fn(_) { "" })
    root.height(Is(Some(150.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      from_end=true, align_end=false, rooms=rows.room_now, room_transforms=false, fn(row, k) {
        (rows.lend)(row, k)
        row.height(Is(Some(60.0))) |> ignore
        row.box(fn(g) { g.over(Is(true)).ground(Is(0xFFFFFFFFL)).list_room_ground() |> ignore }) |> ignore
        row.box(fn(body) { body.height(Is(Some(60.0))).list_room_content() |> ignore }) |> ignore
      }) |> ignore
  })
  t.draw()
  assert_eq(t.row(0).map(fn(r) { r.1 }), Some(0.0))
  items.set(["a", "b"])
  t.draw()
  t.run_for(row_size_ms / 2.0)
  let open = t.row(1).map(fn(r) { r.3 }).unwrap_or(-1.0)
  assert_true(open > 0.0 && open < 60.0, msg="the new room opens: \{open}")
  t.run_for(row_size_ms)
  assert_eq(t.row(1).map(fn(r) { r.3 }), Some(60.0))
}

///|
test "retained rows keep successive departures in their old order and keep their old values" {
  let items = @signals.signal([("a", "A"), ("b", "B"), ("c", "C"), ("d", "D")])
  let out : Ref[NodeRows[(String, String)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(x) { x.1 })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      rooms=rows.room_now, fn(row, _) { row.height(Is(Some(50.0))) |> ignore }) |> ignore
  })
  t.draw()
  let rows = out.val.unwrap()
  items.set([("a", "A"), ("c", "C changed"), ("d", "D")])
  t.draw()
  t.run_for(row_size_ms / 4.0)
  items.set([("a", "A"), ("d", "D")])
  t.draw()
  let (shown, keys) = (rows.read)()
  assert_eq(keys, ["a", "b", "c", "d"])
  assert_eq(shown, [("a", "A"), ("b", "B"), ("c", "C changed"), ("d", "D")])
  assert_false((rows.room)("b", 50.0).presses)
  assert_false((rows.room)("c", 50.0).presses)
  t.run_for(row_size_ms)
  assert_eq((rows.read)().1, ["a", "d"])
}

///|
test "a retained row returning while it closes goes on from the height it reached" {
  let items = @signals.signal([("a", 60.0), ("b", 60.0)])
  let out : Ref[NodeRows[(String, Double)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(_) { "" })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      rooms=rows.room_now, fn(row, _) { row.height(Is(Some(60.0))) |> ignore }) |> ignore
  })
  t.draw()
  let rows = out.val.unwrap()
  items.set([("a", 60.0)])
  t.draw()
  t.run_for(row_size_ms / 4.0)
  let closing = (rows.room)("b", 60.0).height
  assert_true(closing > 0.0 && closing < 60.0, msg="\{closing}")
  items.set([("a", 60.0), ("b", 60.0)])
  t.draw()
  let returning = (rows.room)("b", 60.0)
  assert_true((returning.height - closing).abs() < 0.5, msg="\{closing} to \{returning.height}")
  assert_true(returning.presses)
  t.run_for(row_size_ms)
  assert_eq((rows.room)("b", 60.0).height, 60.0)
}

///|
test "a retained row first built after its cause is already part way open" {
  let items = @signals.signal(Array::makei(12, fn(i) { i.to_string() }))
  let nodes : Map[String, @view.View] = {}
  let out : Ref[NodeRows[String]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=150.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(k) { k }, fn(_) { "" })
    out.val = Some(rows)
    root.height(Is(Some(150.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      est=60.0, rooms=rows.room_now, fn(row, k) {
        nodes[k] = row
        row.owns(fn() { nodes.remove(k) }) |> ignore
        row.height(Is(Some(60.0))) |> ignore
      }) |> ignore
  })
  t.draw()
  assert_false(nodes.contains("new"))
  let at = t.time()
  view_tree().unwrap().event(at, fn() { items.set(items.get() + ["new"]) })
  t.advance(row_size_ms / 2.0)
  t.scroll_to(12)
  t.draw()
  assert_true(nodes.contains("new"))
  let rows = out.val.unwrap()
  let open = (rows.room)("new", 60.0).height
  assert_true(open > 0.0 && open < 60.0, msg="\{open}")
  t.scroll_to(0)
  t.draw()
  t.run_for(row_size_ms)
  t.scroll_to(12)
  t.draw()
  assert_eq((rows.room)("new", 60.0).height, 60.0)
}

///|
test "retained rows keep both old-position copies when the same row moves again before it finishes" {
  let items = @signals.signal([("a", "old"), ("b", "B"), ("c", "C")])
  let out : Ref[NodeRows[(String, String)]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(x) { x.1 },
      moves=fn(_) { true })
    out.val = Some(rows)
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 },
      rooms=rows.room_now, fn(row, _) { row.height(Is(Some(50.0))) |> ignore }) |> ignore
  })
  t.draw()
  let rows = out.val.unwrap()
  items.set([("b", "B"), ("c", "C"), ("a", "first")])
  t.draw()
  t.run_for(row_size_ms / 4.0)
  items.set([("a", "second"), ("b", "B"), ("c", "C")])
  t.draw()
  let (shown, keys) = (rows.read)()
  assert_eq(keys, ["a" + row_moved_mark, "a", "b", "c", "a" + row_moved_mark + "1"])
  assert_eq(shown, [("a", "old"), ("a", "second"), ("b", "B"), ("c", "C"), ("a", "first")])
  assert_false((rows.room)(keys[0], 50.0).presses)
  assert_false((rows.room)(keys[4], 50.0).presses)
  t.run_for(row_size_ms)
  assert_eq((rows.read)().1, ["a", "b", "c"])
}
