// Words sent, built as a host builds (check_looks(false)): a row kept as its nodes whose list moves what it holds in
// it on the rows' way (a row's lead going to another, mbui's ListState::row_lead_off) draws what it kept drawn only
// where that came to the same, so every frame presented is what building every row each frame presents.

///|
/// Words sent in chat `mode` opened `w` by `h`, built as a host builds, the rows kept (`again`) or built every frame:
/// each frame presented from the send to 2.1 s on, its moment after the send and what it draws; how many rows were
/// kept over them all.
fn kept_drawing_sent(mode : String, again : Bool, w : Double, h : Double) -> (Array[(Double, Array[String])], Int) {
  let t = kept_rows_open(mode, w, h)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(again)
  t.tap_text("发消息")
  t.type_text("刚发的这一句")
  tap_send(t)
  let sent = t.time()
  let frames = []
  let mut kept = 0
  t.each_frame(
    Some(fn() {
      frames.push((t.time() - sent, drawn_from(t, -1000.0).map(kept_rows_inst)))
      kept = kept + t.rows_kept()
    }),
  )
  for _ in 0..<30 {
    t.run_for(kept_rows_still_ms)
  }
  t.each_frame(None)
  (frames, kept)
}

///|
/// Words sent in chat `mode` `w` by `h`: the same frames presented with the rows kept as built every frame, each drawn
/// the same, some rows kept.
fn kept_drawing_same(mode : String, w : Double, h : Double) -> Unit raise {
  let (kept, n) = kept_drawing_sent(mode, true, w, h)
  let (built, _) = kept_drawing_sent(mode, false, w, h)
  assert_true(n > 0, msg="rows kept: \{n}")
  assert_eq(kept.map(fn(f) { f.0 }), built.map(fn(f) { f.0 }))
  for i in 0..<kept.length() {
    let (at, a) = kept[i]
    let b = built[i].1
    for j in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
      if a[j] != b[j] {
        fail("\{at} ms after the send, instance \{j} of \{a.length()} kept, \{b.length()} built:\n  kept  \{a[j]}\n  built \{b[j]}")
      }
    }
    if a.length() != b.length() {
      fail("\{at} ms after the send: \{a.length()} instances kept, \{b.length()} built")
    }
  }
}

///|
test "words sent on 大屏, built as a host builds: each frame drawn with the rows kept as built, the row before them going to its new lead" {
  kept_drawing_same("chat", 1280.0, 800.0)
}

///|
test "words sent on 小屏, built as a host builds: each frame drawn with the rows kept as built" {
  kept_drawing_same("chat", 390.0, 844.0)
}

///|
test "words sent on 中屏's tape, built as a host builds: each frame drawn with the rows kept as built" {
  kept_drawing_same("chat", 720.0, 800.0)
}

///|
test "words sent in a long chat on 小屏, built as a host builds: each frame drawn with the rows kept as built" {
  kept_drawing_same("chat-long", 390.0, 844.0)
}

///|
test "words sent in a long chat on 中屏's tape, built as a host builds: each frame drawn with the rows kept as built" {
  kept_drawing_same("chat-long", 720.0, 800.0)
}

///|
test "words sent in a long chat on 大屏, built as a host builds: each frame drawn with the rows kept as built" {
  kept_drawing_same("chat-long", 1280.0, 800.0)
}
