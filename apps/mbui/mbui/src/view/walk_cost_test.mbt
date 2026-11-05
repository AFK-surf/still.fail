// What finding what a point is on and what takes a key costs (retained.md rules 13 and 14): what shows and what holds
// the focus, never the whole tree. The same scene with 30 and with 3000 rows does the same work.

///|
/// A long column held by its rows in sight (View::scrolls_window), each taking a press and keys, under a field with the
/// focus; then a press on a row, a key, and a row come at its end: what each cost (Work's hit_visited, keys_asked, and
/// the nodes a frame visited).
fn walk_cost(rows : Int) -> (Int, Int, Int, Int) raise {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(rows, fn(i) { i }), same=fn(a, b) { a == b })
  let pressed = Ref(-1)
  let keyed : Array[String] = []
  let field : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
        o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end=true, fn(b, k) {
          b
          .height(Is(Some(40.0)))
          .on_press(fn() { pressed.val = k })
          .on_key(fn(_) {
            keyed.push("row")
            false
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      root.box(fn(p) {
        p
        .width(Is(Some(300.0)))
        .height(Is(Some(60.0)))
        .on_key(fn(_) {
          keyed.push("holder")
          false
        })
        |> ignore
        p.box(fn(f) {
          field.val = Some(f)
          f
          .width(Is(Some(100.0)))
          .height(Is(Some(40.0)))
          .focusable(Is(true))
          .on_key(fn(_) {
            keyed.push("field")
            false
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      // (drawn over the field: a tip's, a menu's layer, asked before what has the focus)
      root.box(fn(o) {
        o
        .width(Is(Some(10.0)))
        .height(Is(Some(10.0)))
        .on_key(fn(_) {
          keyed.push("over")
          false
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  assert_true(field.val.unwrap().ask_focus())
  tree.frame(390.0, 844.0) |> ignore
  // (a press on the row at the column's foot)
  let hit0 = tree.work().hit_visited
  assert_true(tree.press(150.0, 380.0))
  let hit = tree.work().hit_visited - hit0
  assert_eq(pressed.val, rows - 1)
  // (a key: what is drawn over what has the focus first, then it, then what holds it, then the rows under it)
  let keys0 = tree.work().keys_asked
  assert_false(tree.key_at(65, 0, 0.0))
  let asked = tree.work().keys_asked - keys0
  assert_eq(keyed[0:3].to_array(), ["over", "field", "holder"])
  assert_true(keyed[3:].iter().all(fn(k) { k == "row" }) && keyed.length() > 3)
  // (a row come at its end)
  let w0 = tree.work()
  keys.set(Array::makei(rows + 1, fn(i) { i }))
  tree.frame(390.0, 844.0) |> ignore
  let w1 = tree.work()
  (hit, asked, w1.visited - w0.visited, w1.orders - w0.orders)
}

///|
test "walk cost: a press, a key and a row come cost the same with 30 rows and with 3000" {
  let short = walk_cost(30)
  let long = walk_cost(3000)
  assert_true(short.0 > 0 && short.1 > 0, msg="counted: \{short}")
  assert_eq(long, short)
}
