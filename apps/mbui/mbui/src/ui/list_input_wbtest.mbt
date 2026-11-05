///|
test "finishing a retained list's motion does not read its model or replace its unchanged keys" {
  for count in [30, 3000] {
    let items = @signals.signal(Array::makei(count, fn(i) { i }))
    let reads = Ref(0)
    let versions = Ref(0)
    let sizes = ListRows::new()
    let result : Ref[NodeRows[Int]?] = Ref(None)
    let nodes : Map[String, @view.View] = {}
    let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
    set_view_app(fn(root) {
      let rows = sizes.in_node(root, fn() {
        reads.val += 1
        items.get().map(fn(i) { i })
      }, fn(i) { i.to_string() }, fn(_) {
        versions.val += 1
        "1"
      })
      result.val = Some(rows)
      root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(),
        fn() { (rows.read)().1 }, from_end=true, room=rows.room, moving=rows.moving,
        fn(row, k) {
          nodes[k] = row
          row.height(Is(Some(40.0))) |> ignore
        }) |> ignore
    })
    t.draw()
    items.set(items.get() + [count])
    t.draw()
    let keys = (result.val.unwrap().read)().1
    let before = (reads.val, versions.val)
    let end = sizes.causes.end
    assert_true(end > t.time())
    t.frame_at(end)
    assert_eq(nodes[count.to_string()].rect().3, 40.0)
    assert_eq((reads.val, versions.val), before,
      msg="ending a motion must not reread the unchanged model")
    assert_true(physical_equal((result.val.unwrap().read)().1, keys),
      msg="the same ordered keys must keep the list's position index")
  }
}

///|
test "a retained list still tracks content versions after its preceding motion ends" {
  let items = ["a"]
  let version = @signals.signal("one")
  let sizes = ListRows::new()
  let t = Tester::new(fn(_) { }, w=300.0, h=300.0)
  set_view_app(fn(root) {
    let rows = sizes.in_node(root, fn() { items }, fn(k) { k }, fn(_) { version.get() })
    root.height(Is(Some(300.0))).scrolls_window(@view.Scroll::list(),
      fn() { (rows.read)().1 }, room=rows.room, moving=rows.moving,
      fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
  })
  t.draw()
  version.set("two")
  t.draw()
  assert_true(sizes.causes.by.get("a") is Some((Changed(_), _)))
  t.frame_at(sizes.causes.end)
  assert_true(sizes.causes.by.is_empty())
  version.set("three")
  t.draw()
  assert_true(sizes.causes.by.get("a") is Some((Changed(_), _)),
    msg="keeping the model between frames must keep its version dependencies too")
}
