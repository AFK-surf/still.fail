// The retained row's shared motion is also the height the natural window asks of its holder in that layout.

///|
test "a natural retained list sizes to entering and leaving rooms" {
  let items = @signals.signal(["a"])
  let list : Ref[@view.View?] = Ref(None)
  let retained : Ref[NodeRows[String]?] = Ref(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).max_height(Is(Some(120.0))) |> ignore
      list.val = Some(body.box(fn(v) {
        let rows = ListRows::new().in_node(v, fn() { items.get() }, fn(k) { k }, fn(_) { "" })
        retained.val = Some(rows)
        v.scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, natural=true, from_end=true,
          align_end=false, rooms=rows.room_now, room_transforms=false, fn(row, k) {
            (rows.lend)(row, k)
            row.height(Is(Some(40.0))) |> ignore
          }) |> ignore
      }))
    }) |> ignore
  })
  t.draw()
  assert_eq(list.val.unwrap().rect().3, 40.0)
  items.set(["a", "b"])
  t.draw()
  t.run_for(row_size_ms / 2.0)
  let entering = list.val.unwrap().rect().3
  assert_true(entering > 40.0 && entering < 80.0, msg="entering: \{entering}")
  t.run_for(row_size_ms)
  assert_eq(list.val.unwrap().rect().3, 80.0)
  items.set(["a"])
  t.draw()
  t.run_for(row_size_ms / 2.0)
  let leaving = list.val.unwrap().rect().3
  assert_true(leaving > 40.0 && leaving < 80.0, msg="leaving: \{leaving}")
  assert_true((retained.val.unwrap().read)().1.contains("b"))
  t.run_for(row_size_ms)
  assert_eq(list.val.unwrap().rect().3, 40.0)
  assert_false((retained.val.unwrap().read)().1.contains("b"))
}

///|
test "a natural retained list keeps a zero-height arrival and releases its last departure" {
  let items = @signals.signal(["a"])
  let made : Map[String, @view.View] = {}
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(body) {
      body.max_height(Is(Some(120.0))) |> ignore
      body.box(fn(v) {
        let rows = ListRows::new().in_node(v, fn() { items.get() }, fn(k) { k }, fn(_) { "" })
        v.scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, natural=true,
          rooms=rows.room_now, fn(row, k) {
            made[k] = row
            row.owns(fn() { made.remove(k) }) |> ignore
            row.height(Is(Some(40.0))) |> ignore
          }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(made.contains("a"), msg="initial row was built")
  let first = made["a"]
  items.set([])
  t.draw()
  t.run_for(row_size_ms)
  assert_false(first.alive())
  assert_false(made.contains("a"))
  items.set(["b"])
  t.draw()
  assert_true(made.contains("b"), msg="zero-height arrival was built")
  let arrival = made["b"]
  t.run_for(row_size_ms / 2.0)
  assert_true(arrival.alive())
  assert_true(made.contains("b"), msg="arrival still exists while opening")
  assert_eq(made["b"].id(), arrival.id())
}
