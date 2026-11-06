// A bar across that runs in from its ends as far as what it holds is padded at its start (View::scrolls' bar_in_held):
// that padding changed alone, the column and what it holds as wide as before, its thumb drawn where a tree made with
// that padding draws it, in the same frame (the padding read where its size is: Roomed, Painted).

///|
/// A column 200 wide scrolling across what it holds, 600 wide padded `pad()` at each side, its bar in from its ends by
/// that; the column scrolled `by` across once laid out.
fn bar_in_held_tree(pad : () -> Double) -> (Tree, Scroll, View) {
  let s = Scroll::across()
  let col : Ref[View?] = Ref(None)
  let tree = Tree::new(fn(root) {
    root.box(fn(c) {
      col.val = Some(c)
      c.width(Is(Some(200.0))).height(Is(Some(60.0))).scrolls(s, bar=held_test_bar(), bar_in_held=true, fn(held) {
        held.width(Is(Some(600.0))).height(Is(Some(60.0)))
        .padding(By(fn() { (pad(), 0.0, pad(), 0.0) })) |> ignore
      }) |> ignore
    }) |> ignore
  }, time=fn() { 0.0 })
  (tree, s, col.val.unwrap())
}

///|
/// A bar drawn always, as the across tests' is.
fn held_test_bar() -> ScrollBar {
  {
    drawn: fn() { true },
    ink: fn() { 0x00000042L },
    ink_held: fn() { 0x00000073L },
    ease: fn(t) { t },
    size: 3.0,
    inset: 2.0,
    least: 28.0,
    near: 12.0,
    grab: 4.0,
    hold_ms: 900.0,
    fade_ms: 200.0,
  }
}

///|
/// Its bar's thumb as drawn: where and how long.
fn thumb_drawn(tree : Tree) -> (Double, Double) {
  let ids = tree.thumbs.values().to_array()
  guard ids.length() == 1 else { abort("one thumb: \{ids.length()}") }
  let d = tree.drawn_of(ids[0]).unwrap()
  (d.x, d.w)
}

///|
test "a bar in by what it holds is padded: that padding changed alone, its thumb as a tree made with it draws it, in that frame" {
  let pad = @signals.signal(10.0, same=fn(a, b) { a == b })
  let (tree, _, _) = bar_in_held_tree(fn() { pad.get() })
  tree.frame(400.0, 200.0, now=0.0) |> ignore
  let before = thumb_drawn(tree)
  pad.set(40.0)
  tree.frame(400.0, 200.0, now=16.0) |> ignore
  let after = thumb_drawn(tree)
  tree.dispose()
  let (fresh, _, _) = bar_in_held_tree(fn() { 40.0 })
  fresh.frame(400.0, 200.0, now=0.0) |> ignore
  let made = thumb_drawn(fresh)
  fresh.dispose()
  assert_true(before != after, msg="the thumb moved in: \{before} -> \{after}")
  assert_eq(after, made)
}
