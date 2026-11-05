// A row's head that sticks (View::sticks): a column 200 tall that scrolls two rows of 300, the first's head 40 tall at
// its top, kept 10 under the column's top as the row passes under it, then going on up with the row's foot.

///|
priv struct StickCase {
  tree : @view.Tree
  head : Ref[@view.NodeId?]
}

///|
fn stick_case() -> StickCase {
  let head : Ref[@view.NodeId?] = Ref(None)
  let scroll = @view.Scroll::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(v) {
        v
        .width(Is(Some(300.0)))
        .height(Is(Some(200.0)))
        .scrolls(scroll, fn(held) {
          for r in 0..<2 {
            held.box(fn(row) {
              row.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
              if r == 0 {
                row.box(fn(h) {
                  head.val = Some(h.id())
                  h.width(Is(Some(300.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)).sticks(Is(10.0)) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(300.0, 200.0) |> ignore
  { tree, head }
}

///|
/// Where its head is drawn (its top), scrolled `by` more, and how many times the tree was laid out for that.
fn StickCase::scrolled(self : StickCase, by : Double, at : Double) -> (Double, Int) {
  let computes = self.tree.work.computes
  self.tree.wheel_at(150.0, 100.0, 0.0, by, 0, at) |> ignore
  self.tree.frame(300.0, 200.0) |> ignore
  let y = self.tree.drawn_of(self.head.val.unwrap()).map(fn(d) { d.y }).unwrap_or(-1.0e9)
  (y, self.tree.work.computes - computes)
}

///|
test "a row's head that sticks: where it is laid out, scrolled into its row 10 under the column's top, then up with its row's foot" {
  let k = stick_case()
  let at_rest = k.tree.drawn_of(k.head.val.unwrap()).map(fn(d) { d.y }).unwrap_or(-1.0e9)
  // (as laid out, its row at the column's top: 10 under it)
  assert_eq(at_rest, 10.0)
  // (scrolled 150 into its row: 10 under the column's top still)
  let (mid, _) = k.scrolled(150.0, 10.0)
  assert_eq(mid, 10.0)
  // (scrolled 280: its row's foot 20 under the column's top, it above that, going on up with it)
  let (leaving, _) = k.scrolled(130.0, 20.0)
  assert_eq(leaving, -20.0)
  // (turned back: down with its row's foot as it comes back in, then held 10 under the top again, no jump between)
  let (coming, _) = k.scrolled(-20.0, 30.0)
  assert_eq(coming, 0.0)
  let (held, _) = k.scrolled(-10.0, 40.0)
  assert_eq(held, 10.0)
  let (still, _) = k.scrolled(-100.0, 50.0)
  assert_eq(still, 10.0)
  let (home, _) = k.scrolled(-150.0, 60.0)
  assert_eq(home, 10.0)
}

///|
test "a row's head that sticks: a layer of its own, scrolled only placed anew, nothing laid out again for it" {
  let k = stick_case()
  let head = k.head.val.unwrap()
  assert_true(k.tree.starts_layer(head))
  k.tree.take_placed() |> ignore
  let (_, laid) = k.scrolled(150.0, 10.0)
  assert_eq(laid, 0)
  // (what scrolls placed anew, and it: nothing else of the rows, their layers copied as they were)
  let placed = k.tree.take_placed()
  assert_true(placed.contains(head), msg="\{placed.length()} placed")
  let row = k.tree.holder_of(head).unwrap()
  assert_true(!placed.contains(row), msg="\{placed.length()} placed")
}
