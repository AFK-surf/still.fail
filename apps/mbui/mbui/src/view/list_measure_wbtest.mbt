///|
test "filling a list measures its rows without placing the whole tree between them" {
  for count in [30, 3000] {
    let keys = Array::makei(count, fn(i) { i })
    let made : Array[(Int, Int)] = []
    let rows : Map[Int, View] = {}
    let tree = Tree::new(fn(root) {
      root.box(fn(list) {
        list.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
        list.scrolls_window(Scroll::list(), fn() { keys }, est=80.0,
          kept_keys=fn() { [] }, fn(row, key) {
            made.push((key, @flex.computes()))
            rows[key] = row
            row.owns(fn() { rows.remove(key) }) |> ignore
            row.height(Is(Some(40.0))) |> ignore
          }) |> ignore
      }) |> ignore
    })
    defer { tree.dispose() }
    tree.frame(390.0, 844.0, now=0.0) |> ignore
    assert_eq(made.map(fn(e) { e.0 }), Array::makei(10, fn(i) { i }))
    for i in 0..<10 {
      assert_eq(rows[i].rect(), (0.0, i.to_double() * 40.0, 300.0, 40.0))
      assert_eq(made[i].1, made[0].1,
        msg="the list must measure its own next row before another whole-tree layout")
    }
  }
}

///|
test "local row measurements follow content width and changed words and leave with their owner" {
  let width = @signals.signal(300.0)
  let words = @signals.signal("abcdef".repeat(10))
  let shown = @signals.signal(true)
  let keys = Array::makei(3000, fn(i) { i })
  let rows : Map[Int, View] = {}
  let tree = Tree::new(fn(root) {
    root.show(fn() { shown.get() }, fn(list) {
      list.width(By(fn() { Some(width.get()) })).height(Is(Some(160.0)))
      .padding(Is((10.0, 0.0, 20.0, 0.0))) |> ignore
      list.scrolls_window(Scroll::list(), fn() { keys }, est=80.0,
        kept_keys=fn() { [] }, fn(row, key) {
          rows[key] = row
          row.owns(fn() { rows.remove(key) }) |> ignore
          row.words(By(fn() { words.get() })) |> ignore
        }) |> ignore
    })
  }, measure=fn(s, _, width) {
    let natural = s.length().to_double() * 10.0
    if width <= 0.0 { (natural, 20.0) } else {
      (dmin(natural, width), (natural / width).ceil() * 20.0)
    }
  })
  defer { tree.dispose() }
  let check = fn(count, w, h) raise {
    tree.frame(500.0, 844.0, now=0.0) |> ignore
    assert_eq(rows.length(), count)
    for i in 0..<count { assert_eq(rows[i].rect(), (10.0, i.to_double() * h, w, h)) }
  }
  check(3, 270.0, 60.0)
  width.set(400.0)
  check(4, 370.0, 40.0)
  words.set("abcdef".repeat(20))
  check(2, 370.0, 80.0)
  shown.set(false)
  tree.frame(500.0, 844.0, now=0.0) |> ignore
  assert_eq(rows.length(), 0)
  assert_eq(tree.list_measures.length(), 0)
}
