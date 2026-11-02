// A viewer of words going over the words of the page under it (a table closed over its chat on a wide window): no
// frame of its fade shows its words over the page's, both seen (words_over.mbt). Main's (acb0068613) did, its ground
// going clear before its words; in a file of its own, as a fault of it ends its program.

///|
test "a table read in the viewer over its chat on a wide window, closed by Esc: none of its words over the chat's as it fades, gone after" {
  let held = Ref(None)
  let t = outer_viewer("csv", held, w=1280.0, h=800.0)
  outer_give(t, held, "数据.csv")
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="gone")
}
