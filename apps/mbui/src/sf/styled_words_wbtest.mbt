// styled_words (page_node.mbt): one line of words filling it (`w=Full`) says it may be cut on it, as an old view's
// line of Fill does; one saying nothing of its width nor of being cut does not, and cut is a fault.

///|
/// Words much wider than the column of 60 they are in.
let sw_long : String = "words much wider than their column"

///|
/// The same words twice, each in a column 60 wide, one line of them: filling it (`w=Full`), and saying nothing of their
/// width.
fn sw_tester() -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=200.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    for style in [@ui.text_style(wrap=false, w=Full), @ui.text_style(wrap=false)] {
      root.box(fn(col) {
        col.width(Is(Some(60.0))) |> ignore
        col.box(fn(w) { styled_words(w, fn() { sw_long }, fn() { style }) |> ignore }) |> ignore
      })
      |> ignore
    }
  })
  t.draw()
  t
}

///|
test "styled_words: one line filling it, cut, said so; one saying nothing, cut, a fault; both laid out alike" {
  let t = sw_tester()
  let drawn = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == sw_long })
  guard drawn is [a, b] else { fail("the words drawn twice: \{drawn.length()}") }
  // (laid out alike: saying it may be cut is no layout of its own)
  assert_eq(a.w, b.w)
  assert_true(a.w <= 60.0, msg=a.w.to_string())
  // (named as the squeeze names a node: its first words)
  let faults = t.squeeze_faults().filter(fn(f) { f.contains("words much") })
  assert_eq(faults.length(), 1, msg=faults.join("\n"))
  assert_true(faults[0].contains("cut short without saying they may be"), msg=faults[0])
}
