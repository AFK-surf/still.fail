// What was sent from here and is not in the chat yet (sfpages' chat_rows.mbt outbox_row, outbox_unsent): 正在发送 a
// while after it went (or what it waits on), its time once the station has it, and what did not go: 未发送 with 重试 (or,
// refused as it is, 编辑: its words back in the composer) and 删除, each asking the core by the chat's thread.

///|
/// The fixture's chat with `out` (the core's ChatView `outbox`) after its messages, its calls kept in `calls`;
/// `offline`: its station not reached.
fn outbox_chat(calls : Array[Made], out : Json, offline? : Bool = false) -> @ui.Tester {
  fake_core(calls, over=fn(name, tp) {
    guard name == "chat" && tp.value is Some(Object(m)) else { return tp }
    let o = m.copy()
    o["outbox"] = Json::array([out])
    o["askClear"] = Json::boolean(false)
    if offline {
      o["offline"] = Json::boolean(true)
    }
    { ..tp, value: Some(Json::object(o)) }
  })
}

///|
fn outgoing(
  state : String,
  refused? : Bool = false,
  error? : String = "",
  waits? : String = "",
  at? : Double = 0.0,
) -> Json {
  {
    "id": "o-1",
    "text": "这条还在路上",
    "state": Json::string(state),
    "final": Json::boolean(refused),
    "error": Json::string(error),
    "waits": Json::string(waits),
    "createdAt": Json::number(at),
    "time": { "createdAt": { "at": 0, "ago": "刚刚", "full": "10/19 06:40:00", "until": "", "past": true } },
  }
}

///|
/// Whether `words` are drawn and seen (not at nothing).
fn outbox_seen(t : @ui.Tester, words : String) -> Bool {
  t.words().iter().any(fn(w) { w.0 == words && w.5 > 0.0 })
}

///|
fn unsent_press(t : @ui.Tester, label : String) -> Unit raise {
  guard t.query(Button, label~) is Some(b) else { fail("no \{label}") }
  let (x, y, w, h) = b.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
}

///|
test "what did not go says 未发送 under it; 重试 asks the core to send it again, 删除 to drop it, each by the chat's thread" {
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("failed", error="连不上 Willow"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("这条还在路上") is Some(_))
  assert_true(t.find("未发送") is Some(_))
  assert_true(t.find("编辑") is None)
  unsent_press(t, "重试")
  let made = named(calls, "chat.retry")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "id"), "o-1")
  assert_eq(text(Some(made[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(made[0].params), "thread"), 7.0)
  unsent_press(t, "删除")
  let made = named(calls, "chat.discard")
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "id"), "o-1")
}

///|
test "what was refused as it is says why, and 编辑 in place of 重试 puts its words back in the composer as it drops it" {
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("failed", refused=true, error="a.jpg 的上传源已丢失"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("发送失败：a.jpg 的上传源已丢失") is Some(_))
  assert_true(t.query(Button, label="重试") is None)
  unsent_press(t, "编辑")
  assert_eq(named(calls, "chat.discard").length(), 1)
  assert_eq(named(calls, "chat.retry").length(), 0)
  // (its words in the composer's field, to be sent anew)
  let typed = named(calls, "composer.text").map(fn(m) { text(Some(m.params), "text") })
  assert_true(typed.contains("这条还在路上"), msg="\{Repr(typed)}")
}

///|
test "its station not reached, what did not go cannot be sent again from here (重试 not pressed); 删除 still drops it" {
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("failed"), offline=true)
  t.run_for(@ui.move_most_ms)
  unsent_press(t, "重试")
  assert_eq(named(calls, "chat.retry").length(), 0)
  unsent_press(t, "删除")
  assert_eq(named(calls, "chat.discard").length(), 1)
}

///|
test "正在发送 shows under what is on its way only once it has been a while (800 ms), what it waits on in its place where the core says" {
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("sending"))
  t.draw()
  assert_true(!outbox_seen(t, "正在发送"))
  t.run_for(@sfpages.sending_shows_ms)
  assert_true(outbox_seen(t, "正在发送"))
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("sending", waits="正在上传 2 个文件"))
  t.run_for(@sfpages.sending_shows_ms)
  assert_true(outbox_seen(t, "正在上传 2 个文件"))
  assert_true(!outbox_seen(t, "正在发送"))
}

///|
test "a chat opened on what has been on its way a while says 正在发送 under it at once, its wait counted from when it was sent" {
  let calls : Array[Made] = []
  // (sent 5 s before the source's time of day: the fixture's, 0)
  let t = outbox_chat(calls, outgoing("sending", at=-5000.0))
  t.draw()
  assert_true(outbox_seen(t, "正在发送"))
}

///|
test "once the station has it, what was sent says its time under it, not 正在发送, till its message takes its place" {
  let calls : Array[Made] = []
  let t = outbox_chat(calls, outgoing("sent"))
  t.run_for(@sfpages.sending_shows_ms)
  assert_true(!outbox_seen(t, "正在发送"))
  assert_true(outbox_seen(t, "刚刚"), msg="\{Repr(t.words().map(fn(w) { w.0 }))}")
  assert_true(t.find("未发送") is None)
}
