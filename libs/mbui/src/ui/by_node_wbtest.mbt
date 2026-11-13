// What is kept for each of the window tree's nodes by its index (ByNode): one made again at an index is another node,
// none of what was kept for the one before it.

///|
test "kept by node: one made again at an index is another, the one before it neither found nor let go of in its place" {
  let kept : ByNode[String] = ByNode::new()
  let first : @view.NodeId = { at: 3, gen: 1 }
  let again : @view.NodeId = { at: 3, gen: 2 }
  kept[first] = "first"
  assert_eq(kept.get(first), Some("first"))
  assert_eq(kept.get(again), None)
  kept[again] = "again"
  assert_eq(kept.get(first), None)
  assert_eq(kept.get(again), Some("again"))
  assert_eq(kept.length(), 1)
  // (the one before let go after: what is kept for the one made since stays)
  kept.remove(first)
  assert_eq(kept.get(again), Some("again"))
  assert_eq(kept.keys(), [again])
  kept.remove(again)
  assert_eq(kept.length(), 0)
  assert_eq(kept.get({ at: 99, gen: 1 }), None)
}

///|
test "window tree: one part let go and another made in its place, again and again: each drawn as it is, none as the one before" {
  let blue = 0x2244CCFFL
  let which = @signals.signal(false, same=fn(a, b) { a == b })
  let view = fn(c : Ctx) { c.text("old", size=12.0) |> ignore }
  let t = Tester::new(view)
  set_view_app(fn(root) {
    root.pick(fn() { which.get() }, fn(v, red) {
      v.height(Is(Some(20.0))).ground(Is(if red { island_red } else { blue })) |> ignore
    })
    old(root, view).grow(Is(1.0)) |> ignore
  })
  t.draw()
  let base = view_blocks.length()
  let grounds = fn() {
    t.drawn_rects().filter(fn(r) { r.4 >> 8 == island_red >> 8 || r.4 >> 8 == blue >> 8 }).map(fn(r) { r.4 })
  }
  // (every instance drawn, each of its numbers by its bits: rects, words, images, clips)
  let whole = fn() { t.drawn_instances().map(fn(i) { i.map(fn(x) { x.reinterpret_as_int64() }) }) }
  let mut keys = view_blocks.keys()
  let mut before : @view.NodeId? = None
  for k in 0..<6 {
    let red = k % 2 == 0
    which.set(red)
    t.drawn_now()
    assert_eq(grounds(), [if red { island_red } else { blue }], msg="turn \{k}")
    assert_eq(view_blocks.length(), base, msg="turn \{k}: what the one before drew let go with it")
    let fresh = view_blocks.keys().filter(fn(id) { !keys.contains(id) })
    assert_eq(fresh.length(), 1, msg="turn \{k}: one part made anew")
    let made = fresh[0]
    // (made at the index the one before it was let go of: another node there)
    if before is Some(b) {
      assert_eq(made.at, b.at, msg="turn \{k}")
      assert_true(made.gen != b.gen, msg="turn \{k}")
      // (the one before let go of late, after what was made in its place drew: that stays, and draws as it did)
      view_blocks.remove(b)
      assert_true(view_blocks.contains(made), msg="turn \{k}")
      let drawn = whole()
      t.draw()
      assert_eq(whole(), drawn, msg="turn \{k}")
      // (as all of it made again draws it)
      view_blocks.clear()
      t.draw()
      assert_eq(whole(), drawn, msg="turn \{k}: as drawn whole")
      assert_eq(view_blocks.length(), base, msg="turn \{k}")
    }
    before = Some(made)
    keys = view_blocks.keys()
  }
  // (the run over, nothing kept)
  view_forget()
  assert_eq(view_blocks.length(), 0)
}

///|
fn[V] ByNode::length(self : ByNode[V]) -> Int {
  self.count
}
