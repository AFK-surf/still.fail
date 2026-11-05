// A chat read on a large screen, its side panel opened beside it and closed again: the messages are where they were
// as the panel goes (the one read at the list's end still there, one read in the middle where it was), whatever the
// width they were laid out at meanwhile. 2026-11-05: closed, the list stood somewhere else.

///|
/// Where `words` is drawn (its first line's), as a reader sees it.
fn reading_at(t : @ui.Tester, words : String) -> (Double, Double)? {
  t.find(words)
}

///|
/// The side panel of chat `r` opened and closed again, a mouse's: each settled.
fn side_opened_closed(t : @ui.Tester, r : ChatRef) -> Unit {
  side_change(r, "open", Some("s-c1"))
  t.run_for(@ui.move_most_ms)
  side_change(r, "close", Some("s-c1"))
  t.run_for(@ui.move_most_ms)
}

///|
test "a chat's side panel opened and closed keeps its messages where they were, at the list's end and in its middle" {
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let out : Array[String] = []
  for w in [1280.0, 1600.0] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode="chat-long", w~, h=800.0, platform=0)
    t.run_for(@ui.move_most_ms)
    // (at its end: the newest message where it is drawn)
    let last = "第 3000 条"
    let before = reading_at(t, last)
    side_opened_closed(t, r)
    let after = reading_at(t, last)
    if before != after {
      out.push("at \{w}, at its end: \{last} \{before} → \{after}")
    }
    // (read in its middle: scrolled back a few screens, a message under the pointer)
    t.wheel(w * 0.6, 400.0, -2400.0)
    t.run_for(@ui.move_most_ms)
    // (a person's message on the screen's middle: long_chat's every fifth, from the newest back)
    let mut words = ""
    for k in 0..<120 {
      let seq = 2996 - 5 * k
      let wd = "第 \{seq} 条：这一步看起来可以了"
      match reading_at(t, wd) {
        Some((_, y)) if y > 200.0 && y < 600.0 => { words = wd; break }
        _ => ()
      }
    }
    if words == "" {
      out.push("at \{w}: nothing read in its middle")
    } else {
      let mid_before = reading_at(t, words)
      side_opened_closed(t, r)
      let mid_after = reading_at(t, words)
      if mid_before != mid_after {
        out.push("at \{w}, in its middle: \{words} \{mid_before} → \{mid_after}")
      }
    }
  }
  assert_eq(out, [])
}
