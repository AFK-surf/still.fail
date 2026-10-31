// The composer over a fake core: a source whose topics are the fixture's and whose calls are kept for the test to
// look at (and answer), so nothing is sent anywhere. Then over the fixture's own station, which takes what is sent.

///|
/// A call the page made: its name, its params, its bytes (if any) and its answer to give.
priv struct Made {
  name : String
  params : Json
  bytes : Bytes?
  done : (Result[Json, Json]) -> Unit
  /// a streamed call's: what it hears before its answer (a part going up: how much of it has gone)
  heard : ((Json, Bytes?) -> Unit)?
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
  ups? : Map[String, Json] = Map::new(),
  platform? : Int = 2,
  answers? : (String, Json) -> Json? = fn(_, _) { None },
) -> @ui.Tester {
  new_run()
  // the drafts the fake core has named (its `draft.put`)
  let drafts_named = Ref(0)
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      // (what the test answers for the core, `answers`: else as below)
      match answers(name, params) {
        Some(v) => {
          done(Ok(v))
          return
        }
        None => ()
      }
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
        // what still.fail's links open, as the core reads them (links_wbtest.mbt)
        "link.parse" => done(Ok(fixture_link_parse(text(Some(params), "url"))))
        // what is written, read as the core reads it (refLinks.ts, pasted.ts: its answers kept)
        "ref.at" | "ref.before" | "ref.marks" | "ref.pasted" | "paste.info" => (base.call)(name, params, done)
        // the chat's draft, as the core keeps it (the composer's: sfpages, its fixture compose_fixture.mbt)
        _ if name.has_prefix("composer.") => (base.call)(name, params, done)
        _ => ()
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      calls.push({ name, params, bytes: Some(bytes), done, heard: None })
      (base.call_bytes)(name, params, bytes, done)
    },
    stream: fn(name, params, bytes, on_value, done) {
      if name != "station.upload.part" {
        return (base.stream)(name, params, bytes, on_value, done)
      }
      calls.push({ name, params, bytes, done, heard: Some(on_value) })
      0
    },
    // the draft's files in the core's composer, as the test moves them on (`ups`: going_up, upped)
    topic: fn(name, params) {
      ignore(ups)
      // (what the test makes over the made-up core's, made up as it is read: followed by its version, as the core's
      // by what it says)
      topic_as_read(name, params, over(name, (base.topic)(name, params)))
    },
    now: fn() { now },
    read_only,
  }
  made.val = Some(src)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn named(calls : Array[Made], name : String) -> Array[Made] {
  calls.filter(fn(m) { m.name == name })
}

///|
/// The file a `composer.add` hands the core (the one each of these calls has).
fn handed(m : Made) -> Json? {
  match field(Some(m.params), "files") {
    Some(Array([one, ..])) => Some(one)
    _ => None
  }
}

///|
/// The core says the file `m` handed over has `sent` bytes up.
fn going_up(ups : Map[String, Json], m : Made, sent : Int) -> Unit {
  let f = handed(m)
  ups[text(f, "id")] = {
    "id": Json::string(text(f, "id")),
    "name": Json::string(text(f, "name")),
    "size": Json::number(number(f, "size")),
    "sent": Json::number(sent.to_double()),
  }
}

///|
/// The core says the file `m` handed over is up, at the station's `path` (its uploads' by default).
fn upped(ups : Map[String, Json], m : Made, path? : String = "") -> Unit {
  let f = handed(m)
  let name = text(f, "name")
  ups[text(f, "id")] = {
    "id": Json::string(text(f, "id")),
    "name": Json::string(name),
    "size": Json::number(number(f, "size")),
    "sent": Json::number(number(f, "size")),
    "done": {
      "name": Json::string(name),
      "path": Json::string(if path == "" { "uploads/u/" + name } else { path }),
      "size": Json::number(number(f, "size")),
    },
  }
}

///|
/// The send button: the capsule's bottom right (opened: under the field).
fn tap_send(t : @ui.Tester) -> Unit {
  t.click(Button, label=@sf.t("web-main.composer.send")) catch {
    e => abort("no send button: \{e}")
  }
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
  // the core keeps it as it is typed (composer.text)
  let kept = named(calls, "composer.text")
  assert_eq(text(Some(kept[kept.length() - 1].params), "text"), "第一行\n第二行")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  let p = Some(sent[0].params)
  assert_eq(text(p, "text"), "第一行\n第二行")
  assert_eq(text(p, "station"), "ws1/st1")
  assert_true(field(p, "thread") is Some(Number(7.0, ..)))
  let (_, after, _, _) = t.ime()
  assert_eq(after, "")
  // what was written taken from the draft the core keeps (composer.take), which it empties
  let taken = named(calls, "composer.take")
  assert_eq(taken.length(), 1)
  assert_eq(text(Some(taken[0].params), "key"), "ws1/st1:s-c1")
  // the words sent wait over the field for their row, which this core never gives; the composer's room held as
  // tall as they went meanwhile, then let go to its own height (both said as they set off)
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "words dragged in from another app and let go on ＋ beside the field go into it at its caret, the field focused" {
  let calls : Array[Made] = []
  let t = fake_core(calls, platform=0)
  let (px, py, pw, ph) = t.query(Button, label=@sf.t("web-main.composer.attach")).unwrap().rect
  t.drop_words(px + pw / 2.0, py + ph / 2.0, "对话 ID：c1")
  t.frame()
  let (active, words, _, _) = t.ime()
  assert_true(active)
  assert_eq(words, "对话 ID：c1")
  let kept = named(calls, "composer.text")
  assert_eq(text(Some(kept[kept.length() - 1].params), "text"), "对话 ID：c1")
}

///|
test "words dragged in from another app and let go on a message go into the composer at its caret" {
  let calls : Array[Made] = []
  let t = fake_core(calls, platform=0)
  let (x, y) = t.find("做完了：").unwrap()
  t.drop_words(x, y, "对话 ID：c1")
  t.frame()
  let (active, words, _, _) = t.ime()
  assert_true(active)
  assert_eq(words, "对话 ID：c1")
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
  t.run_for(@ui.move_most_ms)
  t.assert_idle()
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
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
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
  assert_eq(named(calls, "composer.add").length(), 0)
  assert_eq(named(calls, "session.warm").length(), 0)
  assert_true(t.find(read_only_words) is Some(_))
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
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
  t.run_for(flight_wait_ms + @ui.move_most_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
/// A picture sent while it went up said only 正在上传 under it, however long it took (2026-10-26): how far, as the core
/// says it, once it has been on its way a while.
test "a message going up says how far it has gone" {
  new_run()
  let src = fixture("chat-uploading")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第二屏的截图，帮我看看") is Some(_))
  t.run_for(@sfpages.sending_shows_ms)
  assert_true(t.find("正在上传 42%") is Some(_))
  t.assert_idle()
}

///|
test "the fixture's station: sending, then the message, then an answer; a failure, then 重试" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
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
  // (the station answers fix_answer_ms later: that time passes on the page too, the words landed and the agent's line
  // come in their turns meanwhile)
  t.run_for(fix_answer_ms)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  // said while its agent's activity shows: out of its avatar once it has folded and hopped (emit.mbt)
  t.run_for(Pose::Fold.ms() + Pose::Float.ms())
  assert_true(t.find("收到：「测试一下」") is Some(_))
  // (its avatar home: what comes out of avatars is over, its turn too (two frames on), the next words sent go in
  // their turn after it)
  t.run_for(Pose::Spit.ms() + Pose::Return.ms() + turn_calm_ms)
  // words with 失败 in them fail first
  t.tap_text("发消息")
  t.type_text("这条会失败")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  assert_true(t.find("未发送") is Some(_))
  // (its 重试 shown as its room opens to it: Ctx::row_size)
  t.run_for(@ui.move_most_ms)
  t.tap_text("重试")
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  // (what failed leaves the list as its room closes)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("未发送") is None)
  assert_true(t.find("这条会失败") is Some(_))
  // one that fails again: why, said once (无法重新发送：…)
  t.tap_text("发消息")
  t.type_text("这条失败了也重发不了")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("重试")
  t.draw()
  assert_eq(app.toast.get(), "无法重新发送：a.jpg 的上传源已丢失，请在新消息中重新添加附件。")
  fix_clock.val = None
}

///|
test "a picture sent from here is drawn in its message as it was picked, up before it was sent or after" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  // a PNG's header (IHDR 1600 × 900): a picture
  let png = Bytes::from_array([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x06, 0x40,
    0, 0, 0x03, 0x84, 8, 6, 0, 0, 0,
  ].map(fn(i) { i.to_byte() }))
  let w = @sfbase.writing(src, draft_key(r))
  @sfbase.writing_add(src, w, r.station, "shot.png", png)
  let id = text(Some(w.files[0]), "id")
  let shot = @sfbase.writing_pictures.get(id).unwrap()
  let file = fn(path : String, upload : String) {
    attachment_of({
      "name": Json::string("shot.png"),
      "path": Json::string(path),
      "size": Json::number(29.0),
      "upload": Json::string(upload),
    })
  }
  // sent while it still goes up: its message names its upload
  assert_eq(sent_picture(r.station, file("/w/s-c1/uploads/2026-10-23-c3-shot.png", id)), Some(shot))
  // up (the core says where the station keeps it): its message's file by that name, wherever it is moved
  t.draw()
  let up = text(field(Some(@sfbase.writing(src, draft_key(r)).files[0]), "done"), "path")
  assert_true(up != "")
  assert_eq(sent_picture(r.station, file("/w/s-c1/" + up, "")), Some(shot))
  // not another station's of that name
  assert_eq(sent_picture("ws1/st2", file("/w/s-c1/" + up, "")), None)
}

///|
test "a video picked shows as the host's still of it in its tile and its message, read whole or held; any other file as a card" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let _ = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let w = @sfbase.writing(src, draft_key(r))
  let picked = fn(name : String, held : Int, src : String) -> @hostapi.Picked {
    { name, bytes: if held == 0 { b"\x00\x00\x00\x18ftypmp42" } else { b"" }, held, size: 12.0, src }
  }
  @sfbase.writing_add_picked(src, w, r.station, picked("短片.mp4", 0, "content://media/video/7"))
  @sfbase.writing_add_picked(src, w, r.station, picked("长片.mov", 3, "content://media/video/8"))
  @sfbase.writing_add_picked(src, w, r.station, picked("合同.pdf", 0, "content://docs/9"))
  let ids = w.files.map(fn(f) { text(Some(f), "id") })
  assert_eq(ids.length(), 3)
  assert_eq(@sfbase.writing_pictures.get(ids[0]), Some("content://media/video/7"))
  assert_eq(@sfbase.writing_pictures.get(ids[1]), Some("content://media/video/8"))
  assert_eq(@sfbase.writing_pictures.get(ids[2]), None)
  // sent while it still goes up: its message draws the still from here, as a picture's does
  let file = attachment_of({
    "name": Json::string("短片.mp4"),
    "path": Json::string(@sfbase.upload_path(ids[0])),
    "size": Json::number(12.0),
    "upload": Json::string(ids[0]),
  })
  assert_eq(sent_picture(r.station, file), Some("content://media/video/7"))
}

///|
test "a video picked or pasted that the host has no picture of shows its first frame, made from its bytes, in its tile and its message" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  let w = @sfbase.writing(src, draft_key(r))
  // (macOS's pasteboard and pickers, Windows', iOS's say no address for a file: no still of the host's)
  let clip = b"\x00\x00\x00\x14ftypqt  \x00\x00\x00\x08wide"
  @sfbase.writing_add(src, w, r.station, "录屏.mov", clip)
  let id = text(Some(w.files[0]), "id")
  assert_eq(@sfbase.writing_pictures.get(id), None)
  // the composer built: a player of it made out of sight, reading the bytes from here, its frame at 0 grabbed
  let before = t.views().length()
  t.draw()
  // (a player's open: "open <id> 1 <its type's length>", video/quicktime)
  let opened = t.views()[before:].to_array().filter(fn(l) { l.has_prefix("open ") && l.has_suffix(" 1 15") })
  assert_eq(opened.length(), 1)
  let view = (1).until(1000).find_first(fn(i) { opened[0].has_prefix("open \{i} ") }).unwrap()
  let req = t.view_reads(view, 0.0, 1 << 20)
  t.draw()
  assert_eq(t.view_answers(view), [(req, clip.length(), clip.length().to_double())])
  assert_true(t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"89504e47\"}"))
  t.draw()
  let still = @sfbase.writing_pictures.get(id).unwrap()
  assert_true(still.has_prefix("mem:pv-first/"))
  // sent while it still goes up: its message draws it from here, as a picture's
  let file = attachment_of({
    "name": Json::string("录屏.mov"),
    "path": Json::string(@sfbase.upload_path(id)),
    "size": Json::number(clip.length().to_double()),
    "upload": Json::string(id),
  })
  assert_eq(sent_picture(r.station, file), Some(still))
  // the player let go
  t.draw()
  assert_true(t.views().contains("close \{view}"))
}

///|
test "image sizes from their bytes" {
  // a PNG's header (IHDR 1600 × 900), a GIF's (3 × 2)
  let png = Bytes::from_array([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x06, 0x40,
    0, 0, 0x03, 0x84, 8, 6, 0, 0, 0,
  ].map(fn(i) { i.to_byte() }))
  assert_eq(@pixels.image_size(png), Some((1600, 900)))
  let gif = Bytes::from_array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 3, 0, 2, 0, 0, 0].map(fn(i) { i.to_byte() }))
  assert_eq(@pixels.image_size(gif), Some((3, 2)))
  assert_eq(@pixels.image_size(b"plain words"), None)
  assert_eq(uuid("0123456789abcdef0123456789abcdef"), "01234567-89ab-cdef-0123-456789abcdef")
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

///|
test "the list keeps clear the room the composer takes in the very frame it grows, each frame of its morph" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一行")
  let foot = fn() {
    let rows = t.rows()
    rows[rows.length() - 1].2
  }
  let before = @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1")
  // (what the foot keeps over the composer's room: its 10, and the bell's room, the chat's cards waiting to be decided)
  let over = foot() - before
  // lines enough that it outgrows the least room the list keeps (composer_room): in the frame that takes each, the
  // list's foot is already the room the composer takes then (not the one it took a frame before)
  for line in ["第二行", "第三行", "第四行", "第五行", "第六行"] {
    t.enter()
    t.type_text(line)
    assert_eq(foot(), @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1") + over)
  }
  // and each frame of its morph, as the display draws them, to its end
  let end = t.time() + @ui.move_most_ms
  while t.time() < end {
    t.frame()
    assert_eq(foot(), @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1") + over)
  }
  assert_true(@sfpages.composer_room(t.ctx(), "ws1/st1:s-c1") > before)
  t.run_for(draft_keep_ms)
  t.assert_idle()
}

///|
test "at its end, a row that comes at it: the core told the end is not in view while the list glides to it, then that it is" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  // what the page tells the core of the chat shown: its `end` each time, and each time what it says
  let ends : Array[Bool] = []
  let told : Array[String] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "client.focus" {
        match field(Some(params), "chat") {
          Some(chat) => {
            told.push(chat.stringify())
            match field(Some(chat), "end") {
              Some(True) => ends.push(true)
              Some(False) => ends.push(false)
              _ => ()
            }
          }
          None => ()
        }
      }
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(ends, [true])
  // someone says something: it comes at the end, the list gliding to it (list_to_end, the frame it comes)
  said_by_ana(171, "我也来看看")
  clock.val = clock.val + fix_said_ms
  t.draw()
  assert_true(t.find("我也来看看") is Some(_))
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  // (Android's Chat.kt: rows that came are not read before they are in view) told end:false as it comes, its room
  // opening, end:true once it is open; at its end as it rests
  assert_true(ends.contains(false))
  assert_eq(ends[ends.length() - 1], true)
  // words sent, then the agent's answer (in over the agent's line, what is at the end: the list at its end at once, the
  // rows over it going up for it): at its end again as it rests
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  clock.val = clock.val + fix_deliver_ms
  t.draw()
  // (the station answers fix_answer_ms later: that time passes on the page too)
  t.run_for(fix_answer_ms)
  clock.val = clock.val + fix_answer_ms
  t.draw()
  t.run_for(Pose::Fold.ms() + Pose::Float.ms())
  assert_true(t.find("收到：「测试一下」") is Some(_))
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  assert_eq(ends[ends.length() - 1], true)
  let mut k = 1
  while k < told.length() {
    // (each said as it changes: the end, or the message seen whole)
    assert_true(told[k] != told[k - 1])
    k += 1
  }
  fix_clock.val = None
}

///|
/// ＋ tapped: its sheet up over the chat (the chat a page pushed over Home).
fn plus_opened() -> @ui.Tester raise {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  assert_eq(app.nav.depth(), 2)
  t.click(Button, label=@sf.t("web-main.composer.attach"))
  assert_true(@sf.presenting())
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t
}

///|
test "back with ＋'s sheet up puts the sheet away, the chat stays; back again leaves the chat" {
  // what was reported: the sheet's back taken by the pages' stack, the chat left under it (Sheet.kt SheetHost's
  // BackHandler is asked before the pages')
  let t = plus_opened()
  t.back()
  assert_true(!@sf.presenting())
  assert_eq(app.nav.depth(), 2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("整理发布清单") is Some(_))
  t.back()
  t.run_for(@ui.nav_rest() - t.time())
  assert_eq(app.nav.depth(), 1)
}

///|
test "the system's back gesture with ＋'s sheet up puts the sheet away, the chat not moved by it" {
  let t = plus_opened()
  t.back_gesture(200.0, false)
  // called off: the sheet still up, the chat where it was
  assert_true(@sf.presenting())
  assert_eq(app.nav.depth(), 2)
  t.back_gesture(200.0, true)
  assert_true(!@sf.presenting())
  assert_eq(app.nav.depth(), 2)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "a swipe from the left edge with ＋'s sheet up does not take the chat away" {
  let t = plus_opened()
  t.touch(0, 2.0, 300.0)
  for i in 1..=10 {
    t.touch(1, 2.0 + 30.0 * i.to_double(), 300.0)
  }
  t.touch(2, 302.0, 300.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
}

///|
test "words sent fly to their own row though an older page with the viewer's messages comes in before the core has them" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let base = fixture("chat")
  // the core's answer to the send held back: what was sent is not in its view yet
  let held : Array[() -> Unit] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "chat.send" {
        held.push(fn() { (base.call)(name, params, done) })
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("刚发的这一句")
  tap_send(t)
  // an older page read meanwhile (the reader was near the top a moment ago): the viewer's own messages in it, none of
  // them what was just sent
  (src.call)("chat.older", { "station": "ws1/st1", "session": "s-c1" }, fn(_) {  })
  t.draw()
  t.draw()
  match send_flight.get() {
    Some(f) => assert_true(f.placed, msg="flying to \{f.key}")
    None => fail("nothing flies")
  }
  assert_true(t.find("刚发的这一句") is Some(_))
  // the core has it now: still its row
  for h in held {
    h()
  }
  t.draw()
  t.draw()
  assert_true(t.find("刚发的这一句") is Some(_))
  fix_clock.val = None
}
