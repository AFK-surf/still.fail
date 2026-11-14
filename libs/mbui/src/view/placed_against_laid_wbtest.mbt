// A node as placed against as laid out (Tree::placed_against_laid), what the Tester's placed rule reads.

///|
test "placed_against_laid: placed as laid out by a frame; laid out again and not placed, or never placed, it says so" {
  let node : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.box(fn(b) {
      node.val = Some(b)
      b.width(Is(Some(40.0))).height(Is(Some(30.0))).ground(Is(1L)) |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  let b = node.val.unwrap()
  assert_eq(tree.placed_against_laid(b.id()), Some((true, 40.0, 30.0, 40.0, 30.0)))
  // (laid out again by a layout no frame placed by: what a layout begun inside another left, Tree::measured_now)
  tree.nodes[b.at].flex.width = 302.0
  assert_eq(tree.placed_against_laid(b.id()), Some((true, 40.0, 30.0, 302.0, 30.0)))
  // (laid out, never placed)
  tree.nodes[b.at].placed = false
  assert_eq(tree.placed_against_laid(b.id()), Some((false, 40.0, 30.0, 302.0, 30.0)))
  // (one let go: none)
  assert_eq(tree.placed_against_laid({ at: b.at, gen: b.id().gen + 1 }), None)
}
