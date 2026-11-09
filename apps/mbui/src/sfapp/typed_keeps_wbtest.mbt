// Words typed into the composer of a long chat (小屏 and 大屏): the composer's old view alone built for each, the rows of
// the messages over it kept, nothing else of the page built (mbui's view_host.mbt typed_part, hand_typed; the chat's
// rows a part of their own in it, chat_list.mbt).

///|
/// Chat-long opened `w` by `h`, the composer tapped, a word typed in it and `n` more a moment apart: each frame after
/// each of those is drawn, what it built that is no part (a row of a list), and parts built, more than one; and whether
/// what was typed went as it was sent. (The first word typed sets the send button going as the composer is built, which
/// builds the frame again keeping none: not counted.)
fn typed_builds(w : Double, h : Double, n : Int) -> Array[String] {
  let t = kept_rows_open("chat-long", w, h)
  t.tap_text(@sf.t("web-main.composer.placeholder"))
  t.run_for(800.0)
  t.text_told("字", t.time())
  t.run_for(800.0)
  let out = []
  for k in 0..<n {
    t.text_told("字", t.time())
    for i in 0..<6 {
      t.frame(ms=16.0)
      let built = t.rows_built()
      let rows = built.filter(fn(b) { b.1 >= 0 })
      let parts = built.filter(fn(b) { b.1 < 0 })
      if rows.length() > 0 || parts.length() > 1 {
        out.push("key \{k} frame \{i} (\{t.built_why()}): rows \{rows}, parts \{parts}")
      }
    }
    t.run_for(100.0)
  }
  // (and what was typed is what is sent)
  tap_send(t)
  t.run_for(@ui.move_most_ms)
  if t.find("字字字字") is None {
    out.push("the words typed not sent")
  }
  out
}

///|
test "words typed into a long chat's composer on 小屏: its old view alone built, the rows kept" {
  assert_eq(typed_builds(390.0, 844.0, 3), [])
}

///|
test "words typed into a long chat's composer on 大屏: its old view alone built, the rows kept" {
  assert_eq(typed_builds(1280.0, 800.0, 3), [])
}
