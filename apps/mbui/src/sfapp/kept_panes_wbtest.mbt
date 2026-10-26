// The frame's panes kept, the one in use as the others (sfdesk's tape_part): what each frame draws, says of the frame
// and reads out is what building every pane each frame does, as chats are opened from the sidebar and its list is
// scrolled, the marks of those at work stepping on meanwhile.

///|
/// Chat "chat" opened `w` by `h`, read out; then two chats of the sidebar opened in turn and its list dragged: what is
/// drawn, said and read out at moments after each, the panes drawn again where they can be (`again`) or built every
/// frame; how many panes were drawn again over it all.
fn kept_panes_run(again : Bool, w : Double, h : Double) -> (Array[Array[String]], Int) {
  let t = kept_rows_open("chat", w, h)
  t.keep_parts(true)
  t.drawn_again(again)
  t.set_a11y(true)
  t.said() |> ignore
  let out = []
  let mut kept = 0
  let look = fn() {
    for _ in 0..<6 {
      t.run_for(kept_rows_still_ms)
      out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_read_out(t, true) + kept_rows_said(t))
      kept = kept + t.parts_kept()
    }
  }
  look()
  t.tap_text("夜里的构建又失败了")
  look()
  t.tap_text("盯着 CI")
  look()
  let x = if w >= 1000.0 { 120.0 } else { w * 0.3 }
  t.drag(x, h * 0.7, x, h * 0.4, steps=6)
  look()
  (out, kept)
}

///|
/// The panes on `w` by `h` drawn kept as built, some of them drawn again.
fn kept_panes_same(w : Double, h : Double) -> Unit raise {
  let (kept, n) = kept_panes_run(true, w, h)
  let (built, _) = kept_panes_run(false, w, h)
  assert_true(n > 0, msg="panes drawn again: \{n}")
  kept_rows_same(kept, built)
}

///|
test "the panes kept on 大屏, the one in use too: drawn, said and read out as building them each frame, as chats are opened from the sidebar" {
  kept_panes_same(1280.0, 800.0)
}

///|
test "the panes kept on 中屏's tape, the one in use too: drawn, said and read out as building them each frame, as chats are opened from the sidebar" {
  kept_panes_same(720.0, 800.0)
}
