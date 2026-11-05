// The frame's panes kept, the one in use as the others (sfdesk's tape_part), and on 小屏 its pages (sfapp's view): what
// each frame draws, says of the frame and reads out is what building every one each frame does, as chats are opened
// and left and their list is scrolled, the marks of those at work stepping on meanwhile.

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
  // (counted as each frame is drawn: a frame of the working marks' looks alone builds nothing, keeps nothing)
  let mut kept = 0
  t.each_frame(Some(fn() { kept = kept + t.parts_kept() }))
  let look = fn() {
    for _ in 0..<6 {
      t.run_for(kept_rows_still_ms)
      out.push(drawn_from(t, -1000.0).map(kept_rows_inst) + kept_rows_read_out(t, true) + kept_rows_said(t))
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
  t.each_frame(None)
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

///|
/// On 小屏, the pages kept (sfapp's view: each as a part, read out): chat "chat" opened, back to the chats, another
/// opened from them, back again by the system's gesture, a new chat risen, its composer opened and let go of, the new
/// chat sunk back, the list dragged: what is
/// drawn, said and read out at moments after each, drawn again
/// where they can be (`again`) or built every frame, and at each frame of their slides; how many pages were drawn again
/// over it all, and in `slid` how many as each slide went (back, opened, back by the gesture, risen, its composer opened
/// and let go of, sunk).
fn kept_pages_run(again : Bool, slid : Array[Int]) -> (Array[Array[String]], Int) {
  let (w, h) = (390.0, 844.0)
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
  // (each frame of a page sliding in or out, a display's frame apart: what is drawn)
  let slide = fn() {
    let mut n = 0
    for _ in 0..<24 {
      t.run_for(kept_slide_ms)
      out.push(drawn_from(t, -1000.0).map(kept_rows_inst))
      kept = kept + t.parts_kept()
      n = n + t.parts_kept()
    }
    slid.push(n)
  }
  look()
  t.back()
  slide()
  look()
  t.tap_text("夜里的构建又失败了")
  slide()
  look()
  // (the system's back gesture, let go: the page goes on from where it was let go)
  t.back_gesture(w * 0.3, true)
  slide()
  look()
  // (a new chat rises from the foot over the chats; its composer opened and let go of, reshaping, what stands round it
  // with it; and it sinks back)
  open_page(NewChat)
  slide()
  look()
  t.tap_text("做任何事")
  slide()
  t.tap(w * 0.5, h * 0.45)
  slide()
  look()
  t.back()
  slide()
  t.drag(w * 0.5, h * 0.7, w * 0.5, h * 0.4, steps=6)
  look()
  (out, kept)
}

///|
/// How far apart the frames of a page sliding are looked at (a display's at 60 Hz).
let kept_slide_ms : Double = 16.0

///|
test "the pages kept on 小屏: drawn, said and read out as building them each frame, as chats are opened and left, each frame of their slides too, the page left drawn again as it slides or sinks out" {
  let slid = []
  let (kept, n) = kept_pages_run(true, slid)
  let (built, _) = kept_pages_run(false, [])
  assert_true(n > 0, msg="pages drawn again: \{n}")
  kept_rows_same(kept, built)
}
