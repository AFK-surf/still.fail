// The corner rule held of the window's tree's nodes too (corners.mbt, Ctx::with_tree_nodes): a ground in a rounded
// node's corner, a node's or an old view's in it, concentric with it or said; one shown only under the hand said as
// all is lit (Tester::lit_all_faults); the frame as it was after.

///|
/// A card of the tree, 200×120, its ground 20 round, 6 in all round, holding what `inside` makes there, 188×108; drawn
/// `scale` as big.
fn tree_card(inside : (@view.View) -> Unit, scale? : Double = 1.0) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .pad(Is(6.0))
      .ground(Is(0x333333FFL))
      .radius(Is(20.0))
      .scale(Is(scale))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(188.0))).height(Is(Some(108.0))) |> ignore
        inside(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// A node's ground in the card's corners, `r` round.
fn tree_ground(r : Double) -> (@view.View) -> Unit {
  fn(v) { v.ground(Is(0xEEEEEEFFL)).radius(Is(r)) |> ignore }
}

///|
/// An old view's box in the card's corners, filling the old view, `r` round.
fn tree_old(r : Double) -> (@view.View) -> Unit {
  fn(v) {
    old(v, fn(c) { c.box(w=Fill(1.0), h=Fill(1.0), radius=r, bg=0xEEEEEEFFL, fn() {  }) |> ignore }).grow(Is(1.0))
    |> ignore
  }
}

///|
/// Whether one of `faults` says a corner wants to be `r` round.
fn wants(faults : Array[String], r : Double) -> Bool {
  faults.iter().any(fn(f) { f.contains("wants corner \{r}") })
}

///|
test "corners of the window's tree: a node's ground 20 round in a node's 20, 6 in, said (it wants 15.2); one concentric with it, nothing" {
  let follow = concentric(20.0, 6.0)
  let wrong = tree_card(tree_ground(20.0)).corner_faults()
  let right = tree_card(tree_ground(follow)).corner_faults()
  assert_eq((wants(wrong, follow), right), (true, []), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: the card drawn half as big (10 round, 3 in), a ground 20 round in it said (it wants 7.6), one concentric with it as laid out (7.6 drawn) nothing" {
  let wrong = tree_card(tree_ground(20.0), scale=0.5).corner_faults()
  let right = tree_card(tree_ground(concentric(20.0, 6.0)), scale=0.5).corner_faults()
  assert_eq((wants(wrong, concentric(10.0, 3.0)), right), (true, []), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: an old view's box 20 round in a node's 20, 6 in, said; one concentric with it, nothing" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(tree_old(20.0))
  // (the frame's nodes as they were after: how many, what holds each, what takes a press)
  let c = g()
  let nodes = fn() { (c.count, Array::makei(c.count, fn(i) { (c.nodes[i].parent, c.nodes[i].first, c.nodes[i].next, c.nodes[i].hit, c.nodes[i].id) })) }
  let before = nodes()
  let wrong = t.corner_faults()
  let after = nodes()
  let right = tree_card(tree_old(follow)).corner_faults()
  assert_eq((wants(wrong, follow), right, after == before), (true, [], true), msg=wrong.join("\n"))
}

///|
test "corners of the window's tree: a node's ground shown only while pointed at, 20 round in a node's 20, said as all is lit, not at rest; the hand as it was after" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(fn(v) {
    v.radius(Is(20.0)).ground(By(fn() { if v.pointed() { 0xEEEEEEFFL } else { 0L } })) |> ignore
  })
  let rest = t.corner_faults()
  let lit = t.lit_all_faults()
  let tree = view_tree().unwrap()
  let after = t.corner_faults()
  assert_eq((rest, wants(lit, follow), tree.pointed, tree.pressing, after), ([], true, None, None, []), msg=lit.join("\n"))
}

///|
test "corners of the window's tree, held on every frame at rest (Tester::hold_corners): a node's ground 20 round in a node's 20 said, a moment it waits for to come (a tip's) beside it; nothing moving" {
  let follow = concentric(20.0, 6.0)
  let t = tree_card(fn(v) {
    tree_ground(20.0)(v)
    // (something due on the tree's timeline, nothing drawn by it moving: a tip waiting to come)
    v.at_moment(1.0e9, fn() {  }) |> ignore
  })
  t.draw()
  let c = g()
  c.corner_ladder = [34.0, 26.0, 20.0, 10.0]
  let tree = view_tree().unwrap()
  let held = c.held_corner_faults()
  assert_eq((tree.due_count() > 0, c.motion_left, wants(held, follow)), (true, false, true), msg=held.join("\n"))
}

///|
/// A card of the tree, 200×120, its ground 20 round, cutting what it holds to it (`clips`) or not, holding what
/// `inside` makes there as big as it.
fn tree_cut_card(inside : (@view.View) -> Unit, clips : Bool) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(card) {
      card
      .width(Is(Some(200.0)))
      .height(Is(Some(120.0)))
      .ground(Is(0x333333FFL))
      .radius(Is(20.0))
      .clips(Is(clips))
      |> ignore
      card.box(fn(v) {
        v.width(Is(Some(200.0))).height(Is(Some(120.0))) |> ignore
        inside(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "corners of the window's tree: a square ground filling a node 20 round that cuts it, drawn round by the cut, nothing; not cut, said; an old view's the same" {
  let cut = tree_cut_card(tree_ground(0.0), true).corner_faults()
  let uncut = tree_cut_card(tree_ground(0.0), false).corner_faults()
  let old_cut = tree_cut_card(tree_old(0.0), true).corner_faults()
  let old_uncut = tree_cut_card(tree_old(0.0), false).corner_faults()
  assert_eq(
    (cut, wants(uncut, 20.0), old_cut, wants(old_uncut, 20.0)),
    ([], true, [], true),
    msg=(cut + uncut + old_cut + old_uncut).join("\n"),
  )
}
