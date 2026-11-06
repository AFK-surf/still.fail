///|
test "making a keyed list does not walk all earlier siblings for each row" {
  let rows = @signals.signal([], same=fn(a : Array[Int], b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.each(fn() { rows.get() }, fn(n) { n }, fn(row, _) {
        row.box(fn(body) { body.height(Is(Some(10.0))) |> ignore }) |> ignore
      })
    }) |> ignore
  })
  t.frame(300.0, 600.0, now=0.0) |> ignore
  let before = t.work().boxes_walked
  let n = 500
  t.event(1.0, fn() { rows.set(Array::makei(n, fn(i) { i })) })
  let walked = t.work().boxes_walked - before
  assert_true(walked < n * 4, msg="\{n} rows: \{walked} boxes walked")
  t.dispose()
}

///|
test "making a keyed list with something after it walks each row a few times, not all earlier ones for each" {
  let rows = @signals.signal([], same=fn(a : Array[Int], b) { a == b })
  let t = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.each(fn() { rows.get() }, fn(n) { n }, fn(row, _) {
        row.box(fn(body) { body.height(Is(Some(10.0))) |> ignore }) |> ignore
      })
      // (after the list's slot: a row made last in it is not its holder's last box)
      list.box(fn(foot) { foot.height(Is(Some(10.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.frame(300.0, 600.0, now=0.0) |> ignore
  let before = t.work().boxes_walked
  let n = 500
  t.event(1.0, fn() { rows.set(Array::makei(n, fn(i) { i })) })
  let walked = t.work().boxes_walked - before
  assert_true(walked < n * 4, msg="\{n} rows: \{walked} boxes walked")
  t.frame(300.0, 600.0, now=1.0) |> ignore
  t.dispose()
}
