// A wait as nodes (wait_line_node) laid out as wait_line's once its moment has come: its words where the old one's are
// (after its spinner and the gap), as wide and as high (the Ui size, L5's line), at the system's size of words as it is
// and made larger.

///|
/// Where the words of a wait are drawn a moment and a half on (x, y, w, h): the old one's (`old`) or the node's, at the
/// window's top left, the system's size of words `fs`.
fn wait_words_at(old : Bool, fs : Double) -> Array[(Double, Double, Double, Double)] {
  let t = @ui.Tester::new(fn(c) { if old { wait_line(c, "正在打开", key="w") } }, w=300.0, h=200.0, platform=0)
  if !old {
    @ui.set_view_app(fn(root) { wait_line_node(root, fn() { "正在打开" }) |> ignore })
  }
  t.set_font_scale(fs)
  t.draw()
  t.run_for(later_ms * 1.5)
  t.words().filter(fn(w) { w.0 == "正在打开" }).map(fn(w) { (w.1, w.2, w.3, w.4) })
}

///|
test "a wait as nodes, its moment come: its words where wait_line's are, as wide and as high, at the system's size of words 1 and 2" {
  for fs in [1.0, 2.0] {
    let node = wait_words_at(false, fs)
    let line = wait_words_at(true, fs)
    assert_true(node.length() == 1, msg="the node's words, at \{fs}: \{node}")
    assert_eq(node, line, msg="at \{fs}: the node's \{node}, wait_line's \{line}")
  }
}
