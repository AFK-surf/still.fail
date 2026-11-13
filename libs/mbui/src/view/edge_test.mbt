// A node's edge round its ground (View::edge): what it draws, as its ground is, wherever what draws is asked for (a
// scale about the middle of what is drawn: Tree::drawn_box_of).

///|
test "a node with an edge alone draws: scaled about the middle of what is drawn, its edge counted as it comes and goes" {
  let edge = @signals.signal((0.0, 0L), same=fn(a, b) { a == b })
  let kid : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        // (200 wide, no ground; scaled to half about the middle of what it and what it holds draw)
        p.width(Is(Some(200.0))).height(Is(Some(40.0))).edge(By(fn() { edge.get() })).scale(Is(0.5), about=@view.Drawn)
        |> ignore
        // (40 wide at its left, drawn)
        p.box(fn(k) {
          kid.val = Some(k.id())
          k.width(Is(Some(40.0))).height(Is(Some(40.0))).ground(Is(0x336699FFL)) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let left = fn() {
    t.frame(500.0, 300.0) |> ignore
    t.drawn_of(kid.val.unwrap()).map(fn(d) { d.x })
  }
  assert_eq(left(), Some(10.0), msg="no edge: about the middle of what it holds draws")
  edge.set((2.0, 0xFF0000FFL))
  assert_eq(left(), Some(50.0), msg="edged: about its own middle")
  edge.set((2.0, 0xFF000000L))
  assert_eq(left(), Some(10.0), msg="an edge of no opacity: none")
}
