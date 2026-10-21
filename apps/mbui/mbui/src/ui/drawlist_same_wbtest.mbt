///|
test "draw lists the same across machines: a number's last bit apart is the same, a thousandth is not" {
  // (a spinner's arc's points as an arm64 Mac and an x64 Linux worked them out: still.fail#873's decisions-idle)
  let mac = "mbui-dl 4\nwindow 390 844 3\ni 27.43265618309566 315.63844955817285 4.71718719901871 1 0.4239814778637678\ni 28.14984338211437 0"
  let linux = "mbui-dl 4\nwindow 390 844 3\ni 27.43265618309566 315.63844955817285 4.7171871990187135 1 0.4239814778637675\ni 28.149843382114373 0"
  assert_true(drawlist_same(mac, linux))
  assert_eq(drawlist_first_unlike(mac, linux), None)
  // a coordinate a thousandth apart: another screen, its line said
  let moved = mac.replace(old="27.43265618309566", new="27.43365618309566")
  assert_false(drawlist_same(mac, moved))
  assert_eq(drawlist_first_unlike(mac, moved).map(fn(u) { u.0 }), Some(3))
  // another word, or a number for a word
  assert_false(drawlist_same("glyph 0 13 400 0 0 \"a\"", "glyph 0 13 400 0 0 \"b\""))
  assert_false(drawlist_same("image 0 64 \"a.png\"", "image 0 64 \"1\""))
  // a glyph's words, an image's source, bytes: word for word, numbers in them too
  assert_false(drawlist_same("glyph 0 13 400 0 0 \"v 1.0000000001\"", "glyph 0 13 400 0 0 \"v 1.0000000002\""))
  assert_false(drawlist_same("bytes 0 1e5", "bytes 0 100000"))
  assert_true(drawlist_same("clear 0.9490196078431372 1 1", "clear 0.9490196078431373 1 1"))
  // a line more, or a word more
  assert_false(drawlist_same(mac, mac + "\ni 1 2"))
  assert_eq(drawlist_first_unlike(mac, mac + "\ni 1 2").map(fn(u) { (u.0, u.1, u.2) }), Some((5, "", "i 1 2")))
  assert_false(drawlist_same("i 1 2", "i 1 2 3"))
  // under 1, apart by a share of 1 (not of the number itself)
  assert_true(drawlist_same("i 0", "i 0.0000000000001"))
  assert_false(drawlist_same("i 0", "i 0.00001"))
}
