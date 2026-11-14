// A list held at its end, grown: put there at once (its rows measured anew from that frame on, rows_steady.mbt) only
// where every row new to it is there at once (caught up on); where one comes on a way of its own (ListRows' Comes),
// wherever it comes in (before a row that stays at the end: an agent's working row), the list is held by that way.

///|
/// A list held at its end of the rows `ids()` gives, each 50 tall, keyed by their ids; a row new to it comes (opens
/// on its way) unless `caught(id)`.
fn put_rows(ids : () -> Array[Int], caught : (Int) -> Bool) -> (Ctx) -> Unit {
  let rows : ListRows[Int] = ListRows::new()
  fn(c) {
    let now = ids()
    let (items, _) = rows.rows(c, now.map(fn(i) { "r" + i.to_string() }), now, fn(_) { "" }, comes=fn(i) { !caught(i) })
    c.list("list", items.length(), 50.0, fn(k) {
        c.box(h=Px(50.0), fn() { c.text("Row \{items[k]}", wrap=false) |> ignore }) |> ignore
      }, stick_end=true, sized=rows.sized())
    |> ignore
  }
}

///|
/// When the one list was last put somewhere at once (ListState's put_at).
fn put_at_now() -> Double {
  let mut at = -1.0
  for _, st in g().lists {
    at = st.put_at
  }
  at
}

///|
test "a list held at its end: a row coming before the row kept at its end holds it by its way, not put at once; a row caught up on puts it there at once" {
  // (rows 0..18, then the working row 100 kept last; row 50 comes before it)
  let ids = @signals.signal(Array::makei(19, fn(i) { i }) + [100])
  let t = Tester::new(put_rows(fn() { ids.get() }, fn(i) { i == 60 }), w=300.0, h=400.0)
  t.run_for(row_size_ms * 2.0)
  let before = put_at_now()
  ids.set(Array::makei(19, fn(i) { i }) + [50, 100])
  t.draw()
  assert_eq(put_at_now(), before)
  t.run_for(row_size_ms * 2.0)
  let held = put_at_now()
  // caught up on, at the end: put there at once
  ids.set(Array::makei(19, fn(i) { i }) + [50, 100, 60])
  t.draw()
  assert_true(put_at_now() > held, msg="\{Repr((held, put_at_now()))}")
}
