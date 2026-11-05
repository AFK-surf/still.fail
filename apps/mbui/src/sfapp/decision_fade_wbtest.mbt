// A card's option chosen on a 740 tablet by touch, frame by frame (120 a second): what is under the post fades out as
// main's does (under_post's exit and its reveal's held look, 忽略's own fading as it is let go, one over the other),
// its words' opacity each frame from the first that changes the same as main's (2026-11-06, the 258dee sweep's 16th
// round; arch/next starts from the change that does it, main from the frame that builds after it, compared from there).

///|
/// The opacity (0 … 100) words `s` are drawn at in a frame (the first such words), None where they are not drawn.
fn fade_alpha_of(t : @ui.Tester, s : String) -> Int? {
  for w in t.words() {
    let (text, _, _, _, _, a) = w
    if text == s {
      return Some((a * 100.0).round().to_int())
    }
  }
  None
}

///|
test "a card's option chosen by touch at 740: its card, who decides and 忽略 fade out frame by frame as main's" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w=740.0, h=1000.0, platform=2)
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms * 2.0)
  // (on the tape the page brought over, a tap on what shows of it beside the list)
  let tap = fn(x : Double, y : Double, hold : Double) {
    t.touch_at(0, x, y, t.time())
    t.run_for(hold)
    t.touch_at(2, x, y, t.time())
  }
  tap(740.0 - 28.0, 500.0, 80.0)
  t.run_for(@ui.move_most_ms * 2.0)
  // (the card brought into the middle of the pane)
  for _ in 0..<30 {
    match t.rect_of("等 林 决定") {
      Some((_, y, _, _)) if y > 200.0 && y < 700.0 => break
      Some((_, y, _, _)) if y >= 700.0 => t.drag(530.0, 600.0, 530.0, 450.0, steps=10)
      _ => t.drag(530.0, 400.0, 530.0, 600.0, steps=10)
    }
    t.run_for(@ui.move_most_ms)
  }
  let option = t.semantics().iter().find_first(fn(s) { s.role == Button && s.label == "一起换 把首页和聊天页的截图都更新" }).unwrap()
  let (x, y, w, h) = option.rect
  let seen : Map[String, Array[Int]] = {}
  let words = ["把首页和聊天页的截图都更新", "等 林 决定", "忽略"]
  t.each_frame(Some(fn() {
    for s in words {
      match fade_alpha_of(t, s) {
        Some(a) => {
          let was = seen.get(s).unwrap_or([])
          // (from the first frame it is drawn fainter: where the fading begins)
          if a < 100 || was.length() > 0 {
            was.push(a)
            seen[s] = was
          }
        }
        None => ()
      }
    }
  }))
  tap(x + w / 2.0, y + h / 2.0, 80.0)
  t.run_for(@ui.move_most_ms * 3.0)
  t.each_frame(None)
  let first = fn(s : String) -> Array[Int] {
    let a = seen.get(s).unwrap_or([])
    a.iter().take(9).collect()
  }
  // (main's, frame by frame: the 258dee sweep's main 60dadd8bb5, the same steps; each to a hundredth, rounded as said)
  let near = fn(got : Array[Int], want : Array[Int]) -> Bool {
    got.length() == want.length() && want.mapi(fn(i, w) { (got[i] - w).abs() <= 1 }).iter().all(fn(b) { b })
  }
  let card = first("把首页和聊天页的截图都更新")
  assert_true(near(card, [96, 87, 72, 58, 43, 27, 14, 2, 0]), msg="the card: \{card}")
  let who = first("等 林 决定")
  assert_true(near(who, [96, 86, 70, 55, 40, 24, 12, 2, 0]), msg="who decides: \{who}")
  let dismiss = first("忽略")
  assert_true(near(dismiss, [78, 56, 34, 20, 11, 5, 2, 0, 0]), msg="忽略: \{dismiss}")
}
