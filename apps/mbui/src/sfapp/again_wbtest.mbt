// A Tester depends on its steps alone: what an earlier one left in this package (reset, run as each Tester starts:
// app.mbt init) is not an input of the next.

///|
/// Over the made-up chats from a Tester's start, with no reset() by hand: a chat opened from Home, words typed and
/// sent, the answer let come. Every frame's hash.
fn the_same_steps() -> Array[Int64] {
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let out = t.frames(40)
  t.tap_text("整理发布清单")
  out.append(t.frames(60))
  t.tap_text("发消息")
  out.append(t.frames(20))
  t.type_text("发布前再看一眼签名")
  out.append(t.frames(20))
  t.tap(390.0 - 10.0 - 8.0 - 18.0, 844.0 - 10.0 - 8.0 - 18.0)
  out.append(t.frames(240))
  out
}

///|
test "the same steps in a second Tester draw the same frames as in the first, frame for frame" {
  let a = the_same_steps()
  let b = the_same_steps()
  assert_eq(a.length(), 380)
  assert_eq(@ui.first_difference(a, b), None)
}
