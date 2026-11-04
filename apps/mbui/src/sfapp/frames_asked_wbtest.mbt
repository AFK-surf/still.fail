// The chat page and the chats' list as a device's host draws them: a frame only where the app asked for one. A
// Tester draws wherever the test says and at each motion's end by itself, so a motion that asks for no frame on its
// way passes every other test while on a device it stands still and jumps (2026-11-05: on a phone, 145 of the 173
// refreshes missed while scrolling, switching, typing and sending came after a frame under 4 ms).

///|
/// A phone's display (120 Hz) and a desktop's (60 Hz).
let asked_phone_period : Double = 1000.0 / 120.0

///|
let asked_desk_period : Double = 1000.0 / 60.0

///|
/// Longer than a fling a finger's drag sets off (Android's spline: about a second).
let asked_fling_ms : Double = 2000.0

///|
/// What `t` draws for `ms` where the app asked for no frame, said as `what` at window `w` into `out`.
fn asked_after(t : @ui.Tester, out : Array[String], what : String, w : Double, ms? : Double = @ui.move_most_ms) -> Unit {
  let missed = t.unasked_changes(ms)
  if !missed.is_empty() {
    out.push("\{what} at \{w}: \{missed.length()} frames changed unasked, first at \{missed[0]}")
  }
}

///|
test "a chat's page asks for every frame it changes on a phone: opened, scrolled, written in, sent, left, another opened" {
  let out : Array[String] = []
  let (w, h) = (390.0, 844.0)
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w~, h~, platform=2)
  t.set_frame_period(asked_phone_period)
  asked_after(t, out, "opened", w)
  t.drag(w / 2.0, h * 0.35, w / 2.0, h * 0.65, steps=6)
  asked_after(t, out, "flung", w, ms=asked_fling_ms)
  t.tap_text("发消息")
  asked_after(t, out, "focused", w)
  t.type_text("看")
  asked_after(t, out, "typed", w)
  tap_send(t)
  asked_after(t, out, "sent", w)
  t.back()
  asked_after(t, out, "left", w)
  t.tap_text("夜里的构建又失败了")
  asked_after(t, out, "another opened", w)
  assert_eq(out, [])
}

///|
test "a chat's page asks for every frame it changes on a desktop: written in, sent, another chat chosen" {
  let out : Array[String] = []
  for w in [1280.0, 740.0] {
    let calls : Array[Made] = []
    let t = parity_chat(calls, w, 800.0, 0)
    t.set_frame_period(asked_desk_period)
    asked_after(t, out, "opened", w)
    t.tap_text("发消息")
    asked_after(t, out, "focused", w)
    t.type_text("看")
    asked_after(t, out, "typed", w)
    t.enter()
    asked_after(t, out, "sent", w)
    if w > 840.0 {
      t.tap_text("夜里的构建又失败了")
      asked_after(t, out, "another chosen", w)
    }
  }
  assert_eq(out, [])
}
