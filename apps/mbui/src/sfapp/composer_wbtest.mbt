// The composer over a fake core: a source whose topics are the fixture's and whose calls are kept for the test to
// look at (and answer), so nothing is sent anywhere. Then over the fixture's own station, which takes what is sent.

///|
/// A call the page made: its name, its params, its bytes (if any) and its answer to give.
priv struct Made {
  name : String
  params : Json
  bytes : Bytes?
  done : (Result[Json, Json]) -> Unit
}

///|
/// The made-up chat open over Home, its calls kept in `calls` (draft.get answered by `kept`, the rest left waiting
/// unless `answer` says).
fn fake_core(
  calls : Array[Made],
  kept? : Json = Json::null(),
  read_only? : Bool = false,
) -> @ui.Tester {
  reset()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match name {
        "draft.get" => done(Ok(kept))
        "draft.put" | "session.warm" | "client.focus" | "chat.place" => done(Ok(Json::object({})))
        _ => ()
      }
    },
    call_bytes: fn(name, params, bytes, done) { calls.push({ name, params, bytes: Some(bytes), done }) },
    read_only,
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  // the chat pushed in over Home
  t.run_for(@ui.nav_push_ms)
  t
}

///|
fn named(calls : Array[Made], name : String) -> Array[Made] {
  calls.filter(fn(m) { m.name == name })
}

///|
/// The send button: the capsule's bottom right (opened: under the field).
fn tap_send(t : @ui.Tester) -> Unit {
  t.tap(390.0 - 10.0 - 8.0 - 18.0, 844.0 - 10.0 - 8.0 - 18.0)
}

///|
test "words typed go with send: by the chat's thread, the field emptied, Enter a new line" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  let (active, _, _, _) = t.ime()
  assert_true(active)
  t.compose("di'yi")
  t.type_text("第一行")
  t.enter()
  t.type_text("第二行")
  // Enter did not send: a new line
  assert_eq(named(calls, "chat.send").length(), 0)
  let (_, words, _, _) = t.ime()
  assert_eq(words, "第一行\n第二行")
  // kept a moment after it changed
  assert_eq(named(calls, "draft.put").length(), 0)
  t.run_for(draft_keep_ms)
  let kept = named(calls, "draft.put")
  assert_eq(kept.length(), 1)
  assert_eq(text(Some(kept[0].params), "text"), "第一行\n第二行")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  let p = Some(sent[0].params)
  assert_eq(text(p, "text"), "第一行\n第二行")
  assert_eq(text(p, "station"), "ws1/st1")
  assert_true(field(p, "thread") is Some(Number(7.0, ..)))
  let (_, after, _, _) = t.ime()
  assert_eq(after, "")
  // the draft kept as it is now: empty
  let puts = named(calls, "draft.put")
  assert_true(puts.length() > 0)
  assert_eq(text(Some(puts[puts.length() - 1].params), "text"), "")
  assert_eq(text(Some(puts[puts.length() - 1].params), "key"), "ws1/st1:s-c1")
}

///|
test "nothing to send: the button does nothing" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("   ")
  tap_send(t)
  assert_eq(named(calls, "chat.send").length(), 0)
  // the capsule opened round the field
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "a chat's kept draft comes back into the field" {
  let calls : Array[Made] = []
  let t = fake_core(calls, kept={ "text": "还没写完的话", "quotes": [], "files": [] })
  assert_true(t.dump().contains("还没写完的话"))
  assert_eq(named(calls, "draft.get").length(), 1)
  assert_eq(text(Some(named(calls, "draft.get")[0].params), "key"), "ws1/st1:s-c1")
  t.assert_idle()
}

///|
test "a kept quote's comment comes back into its line and goes with the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls, kept={
    "text": "",
    "quotes": [{ "author": "林", "text": "先把列表改好", "comment": "这里要对齐", "role": "person" }],
    "files": [],
  })
  assert_true(t.dump().contains("这里要对齐"))
  t.tap_text("发消息")
  t.type_text("带评论的引用")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  match field(Some(sent[0].params), "quotes") {
    Some(Array([q])) => assert_eq(text(Some(q), "comment"), "这里要对齐")
    _ => fail("the quote did not go with the message")
  }
}

///|
test "a long paste goes as a text file, up to the station, and with the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  let long = "第一行要点\n" + String::make(6000, 'x')
  t.type_text(long)
  t.draw()
  // not in the field: a card with its first line, going up
  let (_, words, _, _) = t.ime()
  assert_eq(words, "")
  assert_true(t.find("第一行要点") is Some(_))
  assert_true(t.find("正在上传") is Some(_))
  let parts = named(calls, "station.upload.part")
  assert_eq(parts.length(), 1)
  let p = Some(parts[0].params)
  assert_true(text(p, "name").has_prefix("pasted-text-"))
  assert_true(text(p, "name").has_suffix(".txt"))
  assert_eq(parts[0].bytes.unwrap().length(), 6016)
  // up: so many characters, and it can be put back
  (parts[0].done)(Ok({ "file": { "name": Json::string(text(p, "name")), "path": "uploads/u1/p.txt", "size": 6016 } }))
  t.draw()
  assert_true(t.find("\{long.length()} 字符") is Some(_))
  assert_true(t.find("展开到输入框") is Some(_))
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  match field(Some(sent[0].params), "attachments") {
    Some(Array([a])) => assert_eq(text(Some(a), "path"), "uploads/u1/p.txt")
    _ => fail("the pasted file did not go with the message")
  }
  // the words sent wait over the field for their row, which this core never gives; then the capsule takes its own
  // height
  t.run_for(flight_wait_ms)
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "a station's file sent as a file: staged on the chat's station, the message carries it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let r = draft_ref("ws1/st1", "Studio", "/Users/lin/文档", "发布清单.md", "发布清单.md", false, size=4096.0)
  r.mode = "file"
  draft_refs["ws1/st1:s-c1"] = [r]
  t.draw()
  let staged = named(calls, "drive.stage")
  assert_eq(staged.length(), 1)
  assert_eq(text(Some(staged[0].params), "path"), "发布清单.md")
  (staged[0].done)(Ok({ "name": "发布清单.md", "path": "uploads/u1/发布清单.md", "size": 4096 }))
  t.draw()
  t.tap_text("发消息")
  t.type_text("作为文件")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  // as a file: an attachment, and no line naming its path
  assert_eq(text(Some(sent[0].params), "text"), "作为文件")
  match field(Some(sent[0].params), "attachments") {
    Some(Array([a])) => assert_eq(text(Some(a), "path"), "uploads/u1/发布清单.md")
    _ => fail("the station's file did not go with the message")
  }
  assert_eq(refs_of("ws1/st1:s-c1").length(), 0)
}

///|
test "refused before the outbox, the words come back and why is said" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("发不出去的话")
  tap_send(t)
  let sent = named(calls, "chat.send")
  (sent[0].done)(Err({ "code": "invalid_params", "message": "没有这个对话" }))
  t.draw()
  assert_true(t.dump().contains("发不出去的话"))
  assert_true(t.find("没有这个对话") is Some(_))
  // the words sent wait over the field for their row, which this core never gives; then the capsule takes its own
  // height
  t.run_for(flight_wait_ms)
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "read-only: nothing is sent, no draft kept, no file put up" {
  let calls : Array[Made] = []
  let t = fake_core(calls, read_only=true)
  t.tap_text("发消息")
  t.type_text("不该发出去")
  // longer than a draft is kept after
  t.run_for(draft_keep_ms)
  tap_send(t)
  t.type_text(String::make(6000, 'y'))
  t.run_for(draft_keep_ms)
  assert_eq(named(calls, "chat.send").length(), 0)
  assert_eq(named(calls, "draft.put").length(), 0)
  assert_eq(named(calls, "station.upload.part").length(), 0)
  assert_eq(named(calls, "session.warm").length(), 0)
  assert_true(t.find(read_only_words) is Some(_))
  t.assert_idle()
}

///|
test "a message held: its words quoted into the draft, with a line for a comment" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let (x, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  t.press_at(x, y)
  t.run_for(long_press_ms)
  t.release(x, y)
  t.draw()
  assert_true(t.find("引用") is Some(_))
  // a word was picked; all of the message, then quoted
  t.tap_text("全选")
  t.tap_text("引用")
  assert_true(t.find("添加说明（可选）") is Some(_))
  // the comment's field has the focus
  let (active, _, _, _) = t.ime()
  assert_true(active)
  t.type_text("这里再确认一下")
  t.tap_text("发消息")
  t.type_text("看看这个")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  match field(Some(sent[0].params), "quotes") {
    Some(Array([q])) => {
      assert_eq(text(Some(q), "comment"), "这里再确认一下")
      assert_eq(text(Some(q), "role"), "agent")
      assert_true(text(Some(q), "text").has_prefix("做完了"))
    }
    _ => fail("no quote went")
  }
}

///|
test "the fixture's station: sending, then the message, then an answer; a failure, then 重试" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = fn() { clock.val }
  fix_wake.val = fn(_) {  }
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0)
  // the chat pushed in over Home
  t.run_for(@ui.nav_push_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  assert_true(t.find("测试一下") is Some(_))
  assert_true(t.find("正在发送") is Some(_))
  // the station's clock on past its deliveries, its answers, a frame drawn for each
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  assert_true(t.find("正在发送") is None)
  assert_true(t.find("测试一下") is Some(_))
  clock.val = clock.val + fix_answer_ms
  t.draw()
  // said while its agent's activity shows: out of its avatar once it has folded and hopped (emit.mbt)
  t.run_for(Fold.ms() + Float.ms())
  assert_true(t.find("收到：「测试一下」") is Some(_))
  // words with 失败 in them fail first
  t.tap_text("发消息")
  t.type_text("这条会失败")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  assert_true(t.find("未发送") is Some(_))
  t.tap_text("重试")
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  assert_true(t.find("未发送") is None)
  assert_true(t.find("这条会失败") is Some(_))
  fix_clock.val = fix_frame_clock
  fix_wake.val = fix_frame_wake
}

///|
test "image sizes from their bytes" {
  // a PNG's header (IHDR 1600 × 900), a GIF's (3 × 2)
  let png = Bytes::from_array([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x06, 0x40,
    0, 0, 0x03, 0x84, 8, 6, 0, 0, 0,
  ].map(fn(i) { i.to_byte() }))
  assert_eq(image_size(png), Some((1600, 900)))
  let gif = Bytes::from_array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 3, 0, 2, 0, 0, 0].map(fn(i) { i.to_byte() }))
  assert_eq(image_size(gif), Some((3, 2)))
  assert_eq(image_size(b"plain words"), None)
  assert_eq(paste_preview("\n  first line\r\nsecond"), "first line")
  assert_eq(uuid("0123456789abcdef0123456789abcdef"), "01234567-89ab-cdef-0123-456789abcdef")
  assert_eq(utf8_bytes("会").length(), 3)
}

///|
test "the app tells the core it is shown and in front, in which workspace, and when it leaves the front" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let told = named(calls, "client.focus").filter(fn(m) { m.params.stringify().contains("\"visible\"") })
  assert_eq(told.length(), 1)
  let first = told[0].params.stringify()
  assert_true(first.contains("\"visible\":true"))
  assert_true(first.contains("\"focused\":true"))
  assert_true(first.contains("\"workspace\":\"ws1\""))
  // the window covered or the activity paused: said at once (no frame need come after it), and only once
  t.app_state(false, false)
  t.draw()
  let after = named(calls, "client.focus").filter(fn(m) { m.params.stringify().contains("\"visible\"") })
  assert_eq(after.length(), 2)
  assert_true(after[1].params.stringify().contains("\"visible\":false"))
  // back in front
  t.app_state(true, true)
  let back = named(calls, "client.focus").filter(fn(m) { m.params.stringify().contains("\"visible\"") })
  assert_eq(back.length(), 3)
  assert_true(back[2].params.stringify().contains("\"focused\":true"))
  t.assert_idle()
}
