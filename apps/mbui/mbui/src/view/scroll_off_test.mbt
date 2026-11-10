// A page's list (View::scrolls with Scroll::list) drawn off by how far it is scrolled by its offset alone (Node's
// scroll_off): 100 tall under 100 of the window's, ten rows of 40, each counting its presses; found, pressed and placed
// where it is drawn as it scrolls, nothing of it placed again, and what hosts the tree told which column moved.

///|
priv struct OffCase {
  tree : @view.Tree
  scroll : @view.Scroll
  pressed : Array[Int]
  rows : Array[@view.View]
  told : Array[@view.NodeId]
  column : Ref[@view.NodeId?]
}

///|
fn off_case() -> OffCase {
  let now = Ref(0.0)
  let scroll = @view.Scroll::list()
  let pressed = []
  let rows = []
  let column : Ref[@view.NodeId?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
        o.box(fn(gap) { gap.height(Is(Some(100.0))) |> ignore }) |> ignore
        o.box(fn(v) {
          column.val = Some(v.id())
          v
          .height(Is(Some(100.0)))
          .scrolls(scroll, fn(held) {
            for i in 0..<10 {
              held.box(fn(r) {
                r.width(Is(Some(300.0))).height(Is(Some(40.0))).on_press(fn() { pressed.push(i) }) |> ignore
                rows.push(r)
              })
              |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  let told = []
  tree.on_offset(fn(id) { told.push(id) })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, pressed, rows, told, column }
}

///|
test "a page's list scrolled by its offset alone: pressed, found and placed where it is drawn, nothing of it placed again, its column told" {
  let k = off_case()
  k.tree.wheel_at(150.0, 150.0, 0.0, 70.0, 0, 10.0) |> ignore
  k.tree.frame(390.0, 844.0) |> ignore
  // (nothing placed again for it: the frame composed none of it)
  let composed = k.tree.composed().length()
  // (105 in the window: 5 into the column, 75 into what it holds, the second row's)
  let found = k.tree.target_at(150.0, 105.0) is Pressed(_)
  k.tree.press(150.0, 105.0) |> ignore
  let (_, y1, _, _) = k.rows[1].rect()
  let y2 = match k.tree.drawn_place(k.rows[2].id()) {
    Some((_, y, _, _)) => y
    None => -1.0
  }
  let (_, laid, _, _) = k.rows[3].laid_window_now()
  let (_, was, _, _) = k.rows[3].placed_window_now()
  assert_eq(
    (k.scroll.at(k.tree), composed, found, k.pressed, y1, y2, laid, was, k.told.contains(k.column.val.unwrap())),
    (70.0, 0, true, [1], 70.0, 110.0, 150.0, 150.0, true),
  )
}
