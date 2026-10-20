// What the chat tells the core of its reader (`client.focus` with `chat`: its end seen or not) over the fixture's own
// station: told as it changes, not again for each lot of rows its list glides after while it stays at its end.

///|
/// The chat's `client.focus` reports so far (each its `end`: "true", "false"; "left" when it went).
fn focus_told(calls : Array[(String, Json)]) -> Array[String] {
  calls.filter_map(fn(c) {
    if c.0 != "client.focus" {
      return None
    }
    match c.1 {
      Object(m) =>
        match (m.get("chat"), m.get("left")) {
          (Some(Object(chat)), _) =>
            match chat.get("end") {
              Some(True) => Some("true")
              Some(False) => Some("false")
              _ => Some("?")
            }
          (_, Some(_)) => Some("left")
          _ => None
        }
      _ => None
    }
  })
}

///|
test "the chat at its end: its end told once, not again as the answer's rows come and the list glides after them" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = fn() { clock.val }
  fix_wake.val = fn(_) {  }
  let base = fixture("chat")
  let calls : Array[(String, Json)] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  assert_eq(focus_told(calls), ["true"])
  // a message sent, delivered and answered: rows come at the end (it, the agent's activity, its answer), the list
  // following them
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Fold.ms() + Float.ms())
  assert_true(t.find("收到：「测试一下」") is Some(_))
  println("client.focus chat told: \{focus_told(calls)}")
  // at its end throughout: told so once
  assert_eq(focus_told(calls), ["true"])
  fix_clock.val = fix_frame_clock
  fix_wake.val = fix_frame_wake
}

///|
test "a film open and still: where it is told once, not every 5 s while it stays there" {
  reset()
  let base = fixture("player-video")
  let places : Array[Json] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "drive.place" {
        places.push(params)
      }
      (base.call)(name, params, done)
    },
  }
  open_drive_fixture("player-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  t.run_for(@ui.nav_push_ms)
  t.run_for(3.0 * play_keep_ms)
  println("drive.place told \{places.length()} times in \{3.0 * play_keep_ms} ms, the film still")
  assert_true(places.length() <= 1)
}
