// Several changes may be settled at one moment while a retained list is being measured.

///|
test "a retained row delayed and removed at one moment stays closed until it is due" {
  let items = @signals.signal([("base", 60.0), ("state", 46.0)])
  let from : @signals.Signal[Double?] = @signals.signal(None)
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0, stable=false)
  set_view_app(fn(root) {
    let rows = ListRows::new().in_node(root, fn() { items.get() }, fn(x) { x.0 }, fn(_) { "1" },
      from=fn(k) { if k == "state" { from.get() } else { None } })
    root.height(Is(Some(300.0))).scrolls_window_rooms(@view.Scroll::list(), fn() { (rows.read)().1 },
      est=90.0, from_end=true, room=rows.room, fn(row, k) {
        row.height(By(fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).map(fn(x) { x.1 }) })) |> ignore
      }) |> ignore
  })
  // Start without the state, then add it as a newly arriving row.
  items.set([("base", 60.0)])
  t.draw()
  t.run_for(row_size_ms)
  let now = t.time()
  items.set([("base", 60.0), ("state", 46.0)])
  t.draw()
  from.set(Some(now + 120.0))
  t.draw()
  items.set([("base", 60.0)])
  t.draw()
  t.frame_at(now + 50.0)
  assert_eq(t.row(1).map(fn(r) { r.3 }), Some(0.0), msg="the delayed row opened before it was due")
  t.run_for(row_size_ms * 2.0)
  assert_eq(t.rows().length(), 1, msg="the row eventually leaves")
}
