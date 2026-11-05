// A web link's card under the link the pointer rests on, from the piece of line's start, as main lays it out: not at
// the chat's column's left.

///|
test "wide: a web link's card lies under the link it is of, from where that piece of line starts" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-peeks")
  let (lx, ly, _, lh) = words_rect(t, "https://example.com/bench/list")
  t.move(lx + 20.0, ly + lh / 2.0)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  let (cx, cy, _, _) = t.words().filter(fn(w) { w.0 == "列表滚动的性能数据" && w.5 > 0.5 }).map(fn(w) { (w.1, w.2, w.3, w.4) })[0]
  // (its title in from the card's left by the card's padding and the page's mark: past the link's start, not by more
  // than a card's lead; under the piece of line)
  assert_true(cx > lx && cx < lx + 100.0, msg="its title at \{cx}, the link from \{lx}")
  assert_true(cy > ly + lh, msg="its title at \{cy}, the link's line's foot \{ly + lh}")
}
