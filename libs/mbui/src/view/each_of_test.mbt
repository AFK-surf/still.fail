// View::each_of: a list whose items are the rows themselves, a row for each object (physical_equal), with nothing of
// theirs to key them by: made once as an object comes, kept while it stays (set again, moved), let go as it goes; two
// objects alike in what they hold are two rows.

///|
priv struct EachOfRow {
  name : String
}

///|
test "each_of: a row for each object, made once, kept across a set and a move, gone as it goes; two blank ones two rows" {
  let a : EachOfRow = { name: "" }
  let b : EachOfRow = { name: "" }
  let c : EachOfRow = { name: "c" }
  let items = @signals.signal([a, b], same=fn(x, y) { physical_equal(x, y) })
  let made : Array[String] = []
  let gone : Array[String] = []
  let t = @view.Tree::new(fn(root) {
    root.each_of(at_once=true, fn() { items.get() }, fn(v, r) {
      made.push(r.name)
      v.owns(fn() { gone.push(r.name) }) |> ignore
    })
  })
  t.frame(390.0, 844.0) |> ignore
  // two blank rows, alike: two rows
  assert_eq(made, ["", ""])
  // the same two set again, one more after them: it alone made
  items.set([a, b, c])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(made, ["", "", "c"])
  assert_eq(gone, [])
  // moved: none made, none let go
  items.set([c, b, a])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(made.length(), 3)
  assert_eq(gone, [])
  // one of the blank ones taken out: it alone let go, the other blank one kept
  items.set([c, b])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(made.length(), 3)
  assert_eq(gone, [""])
  // the one taken out put back: a row made for it anew
  items.set([c, b, a])
  t.frame(390.0, 844.0) |> ignore
  assert_eq(made, ["", "", "c", ""])
  assert_eq(gone, [""])
}
