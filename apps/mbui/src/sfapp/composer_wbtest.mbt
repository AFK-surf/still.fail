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
  now? : Double = 0.0,
  over? : (String, Topic) -> Topic = fn(_, t) { t },
  made? : Ref[Source?] = Ref(None),
) -> @ui.Tester {
  reset()
  // the drafts the fake core has named (its `draft.put`)
  let drafts_named = Ref(0)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match name {
        "draft.get" => done(Ok(kept))
        // the core's name for the draft (DraftView.id): another once it is put back empty
        "draft.put" => {
          let blank = text(Some(params), "text") == "" &&
            (match field(Some(params), "files") {
              Some(Array(fs)) => fs.length() == 0
              _ => true
            })
          if blank {
            drafts_named.val += 1
          }
          done(Ok({ "id": Json::string("draft-\{drafts_named.val}") }))
        }
        "session.warm" | "client.focus" | "chat.place" => done(Ok(Json::object({})))
        _ => ()
      }
    },
    call_bytes: fn(name, params, bytes, done) { calls.push({ name, params, bytes: Some(bytes), done }) },
    topic: fn(name, params) { over(name, (base.topic)(name, params)) },
    now: fn() { now },
    read_only,
  }
  made.val = Some(src)
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
}

///|
test "a long paste goes up by the same id and name whatever the clocks say: from its words and its place alone" {
  let long = "第一行要点\n" + String::make(6000, 'x')
  // two runs: other times of day, the frames' clock further on in the second
  let ids = []
  for run in [(0.0, 0.0), (1792462301917.0, 4321.0)] {
    let calls : Array[Made] = []
    let t = fake_core(calls, now=run.0)
    t.run_for(run.1)
    t.tap_text("发消息")
    t.type_text(long)
    let parts = named(calls, "station.upload.part")
    assert_eq(parts.length(), 1)
    let p = Some(parts[0].params)
    ids.push((text(p, "id"), text(p, "name")))
  }
  assert_eq(ids[0], ids[1])
  // as the station takes an upload's id (hub.ts savePart: [A-Za-z0-9_-], 8 to 64 long): 32 hex digits, whatever goes
  for id in [ids[0].0, upload_id("", 0), upload_id("drive\u{1}/\u{1}a.txt", 12345)] {
    assert_eq(id.length(), 32)
    assert_true(id.iter().all(fn(ch) { (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') }))
  }
  // another paste, or the same one second in its draft, is another file
  assert_true(paste_name("d", long + "y", 0) != paste_name("d", long, 0))
  assert_true(paste_name("d", long, 1) != paste_name("d", long, 0))
}

///|
test "an upload's id is the same in every run and on js and native: written out, not compared within one run" {
  // MoonBit's own hash() is seeded anew in each process and differs between js and native, so two ids made in one
  // run agreed while a recording and its replay did not (93, 96, 18): these are FNV-1a's (@ui.stable_hash), fixed
  assert_eq(upload_id("", 0), "a092d94b70696d701bdbc07e71af9cee")
  assert_eq(upload_id("drive\u{1}/\u{1}a.txt", 12345), "bc9e091661ed62a8e324d39c70a25f05")
  let seed = file_seed("ws/st", "照片.png", b"abc")
  assert_eq(seed, "ws/st\u{1}照片.png\u{1}3\u{1}-1792535898324117685")
  assert_eq(upload_id("new:ws/st\u{1}draft-0123456789abcdef01\u{1}" + seed, 0), "d0a7b4599668b44a462604fa8617fc77")
}

///|
test "the same paste in the next message is another upload: the core names the next draft anew" {
  let long = "第一行要点\n" + String::make(6000, 'x')
  let calls : Array[Made] = []
  let t = fake_core(calls)
  let up = fn() {
    t.tap_text("发消息")
    t.type_text(long)
    let parts = named(calls, "station.upload.part")
    let p = Some(parts[parts.length() - 1].params)
    (parts[parts.length() - 1].done)(
      Ok({ "file": { "name": Json::string(text(p, "name")), "path": "uploads/u/p.txt", "size": 6016 } }),
    )
    t.draw()
    (text(p, "id"), text(p, "name"))
  }
  let first = up()
  tap_send(t)
  assert_eq(named(calls, "chat.send").length(), 1)
  // the draft emptied as it went is kept so (draft.put), and the core names the next one
  t.run_for(draft_keep_ms)
  let second = up()
  assert_true(first.0 != second.0)
  assert_true(first.1 != second.1)
}

///|
test "a file going up keeps the id it was given as it went in, whatever comes to the chat meanwhile" {
  let calls : Array[Made] = []
  // a message comes to the chat between the file's two parts
  let came = Ref(false)
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~, over=fn(name, tp) {
    if name != "chat" || !came.val {
      return tp
    }
    match tp.value {
      Some(Object(o)) =>
        match o.get("messages") {
          Some(Array(ms)) if ms.length() > 0 =>
            match ms[ms.length() - 1] {
              Object(m) => {
                let next = m.copy()
                next["seq"] = Json::number(9999.0)
                let o2 = o.copy()
                o2["messages"] = Json::array(ms + [Json::object(next)])
                { ..tp, value: Some(Json::object(o2)), version: tp.version + 1 }
              }
              _ => tp
            }
          _ => tp
        }
      _ => tp
    }
  })
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let d = drafts.get(draft_key(r)).unwrap()
  let before = d.id
  // two parts' worth
  let bytes = Bytes::make(part_size + 10, b'x')
  add_file(made.val.unwrap(), d, r.station, "big.bin", bytes, None)
  let first = named(calls, "station.upload.part")
  assert_eq(first.length(), 1)
  came.val = true
  t.draw()
  assert_eq(d.id, before)
  (first[0].done)(Ok({ "have": Json::number(part_size.to_double()) }))
  let parts = named(calls, "station.upload.part")
  assert_eq(parts.length(), 2)
  assert_eq(text(Some(parts[1].params), "id"), text(Some(parts[0].params), "id"))
  assert_eq(text(Some(parts[1].params), "name"), text(Some(parts[0].params), "name"))
}

///|
test "the same file twice in a draft is two uploads, and again after it was sent a third; none is the draft's name" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let _t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let d = drafts.get(draft_key(r)).unwrap()
  // the core's name for the draft as it was last kept (the fake core's draft.put)
  sent_draft(d, 1)
  save_draft(src, d)
  let named_as = d.id
  assert_true(named_as != "")
  let bytes = b"the same bytes"
  let ids = fn() { named(calls, "station.upload.part").map(fn(m) { text(Some(m.params), "id") }) }
  add_file(src, d, r.station, "a.txt", bytes, None)
  add_file(src, d, r.station, "a.txt", bytes, None)
  // sent: the draft emptied, kept so, named anew; the same file put in again
  d.files.clear()
  sent_draft(d, 2)
  save_draft(src, d)
  assert_true(d.id != named_as)
  add_file(src, d, r.station, "a.txt", bytes, None)
  let all = ids()
  assert_eq(all.length(), 3)
  assert_true(all[0] != all[1])
  assert_true(all[2] != all[0] && all[2] != all[1])
  // each as the station takes an upload's id (32 hex digits), none the draft's name as it is
  for id in all {
    assert_eq(id.length(), 32)
    assert_true(id.iter().all(fn(ch) { (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') }))
    assert_true(id != named_as && id != d.id)
  }
}

///|
test "a draft emptied, not sent: the core names the next, and the same file put in again is another upload" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let _t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let d = drafts.get(draft_key(r)).unwrap()
  let bytes = b"the same bytes"
  add_file(src, d, r.station, "a.txt", bytes, None)
  let first = named(calls, "station.upload.part")[0]
  // up: the draft holds it, kept so (draft.put with the file: the same draft, its name kept)
  (first.done)(Ok({ "file": { "name": "a.txt", "path": "uploads/u/a.txt", "size": 14 } }))
  save_draft(src, d)
  let named_as = d.id
  assert_true(named_as != "")
  // taken out again, nothing sent: kept empty, and the core names the next draft
  d.files.clear()
  save_draft(src, d)
  assert_true(d.id != named_as)
  assert_eq(named(calls, "chat.send").length(), 0)
  add_file(src, d, r.station, "a.txt", bytes, None)
  let parts = named(calls, "station.upload.part")
  assert_eq(parts.length(), 2)
  assert_true(text(Some(parts[1].params), "id") != text(Some(first.params), "id"))
}

///|
test "a long paste goes as a text file, up to the station, and with the message" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  let long = "第一行要点\n" + String::make(6000, 'x')
  t.type_text(long)
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
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
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + composer_morph_ms)
  t.assert_idle()
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
