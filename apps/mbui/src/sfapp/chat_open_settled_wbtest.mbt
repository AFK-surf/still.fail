// A chat opened on a wide window: its last messages where they rest from the first frame they show, its composer's
// room laid out by the chat's own room in the first layout (sfdesk chat_node.mbt's chat_talk_node), not grown into it.

///|
/// On a window `w` by `h` (a mouse's), the chat list's row a third down its side clicked (pressed and let go at once): the y of `last` (the last
/// message of the chat it opens) in each frame it shows in until it has rested, and where it rests.
fn opened_last_ys(w : Double, h : Double, last : String) -> (Array[Double], Double) {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w~, h~, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  // (the row whose words stand nearest a third down the list, at its side)
  let lx = if w >= 600.0 { 150.0 } else { w / 2.0 }
  let side = if w >= 1000.0 { 300.0 } else { w }
  let mut at : (Double, Double)? = None
  let mut d = 1.0e9
  for wd in t.words() {
    let (_, x, y, ww, hh, _) = wd
    let (cx, cy) = (x + ww / 2.0, y + hh / 2.0)
    let e = (cy - h * 0.3).abs() + (cx - lx).abs() * 0.2
    if cx < side && cy > 100.0 && e < d {
      d = e
      at = Some((cx, cy))
    }
  }
  let (x, y) = at.unwrap()
  let ys : Array[Double] = []
  t.each_frame(Some(fn() {
    match t.words().iter().find_first(fn(wd) { wd.0 == last }) {
      Some(wd) => ys.push(wd.2)
      None => ()
    }
  }))
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.run_for(@ui.move_most_ms * 3.0)
  t.each_frame(None)
  let rest = t.words().iter().find_first(fn(wd) { wd.0 == last }).unwrap().2
  (ys, rest)
}

///|
test "a chat opened on a wide window by a mouse: its last message where it rests from the first frame it shows in, not falling into place as its composer's room shrinks" {
  for size in [(740.0, 1000.0), (1280.0, 800.0)] {
    let (w, h) = size
    let (ys, rest) = opened_last_ys(w, h, "好的，我来处理。")
    assert_true(ys.length() >= 8, msg="\{w}: shown over its frames: \{ys}")
    for i in 0..<8 {
      assert_true((ys[i] - rest).abs() < 0.5, msg="\{w}: frame \{i} of it at \{ys[i]}, resting at \{rest}: \{ys}")
    }
  }
}
