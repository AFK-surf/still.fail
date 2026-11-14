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
  ups? : Map[String, Json] = Map([]),
  platform? : Int = 2,
  nodes? : Bool = false,
) -> @ui.Tester {
  new_run()
  // (the chat's page made as nodes, where `nodes` says so: sfbase's chat_page_nodes)
  if nodes {
    @sfbase.chat_page_nodes.set(true)
  }
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
        // what still.fail's links open, as the core reads them (links_wbtest.mbt)
        "link.parse" => done(Ok(fixture_link_parse(text(Some(params), "url"))))
        // what is written, read as the core reads it (refLinks.ts, pasted.ts: its answers kept)
        "ref.at" | "ref.before" | "ref.marks" | "ref.words" | "ref.pasted" | "paste.info" => (base.call)(name, params, done)
        // the chat's draft, as the core keeps it (the composer's: sfpages, its fixture compose_fixture.mbt)
        _ if name.has_prefix("composer.") => (base.call)(name, params, done)
        _ => ()
      }
    },
    call_bytes: fn(name, params, bytes, done) {
      calls.push({ name, params, bytes: Some(bytes), done })
      (base.call_bytes)(name, params, bytes, done)
    },
    stream: fn(name, params, bytes, on_value, done) {
      if name != "station.upload.part" {
        return (base.stream)(name, params, bytes, on_value, done)
      }
      calls.push({ name, params, bytes, done })
      0
    },
    // the draft's files in the core's composer, as the test moves them on (`ups`)
    // (what the test makes over the made-up core's: what `over` reads of the test's own is a signal it sets, so what
    // reads the topic follows it as it follows the core's)
    topic_read: fn(name, params) {
      ignore(ups)
      over(name, base.topic(name, params).get().snapshot())
    },
    now: fn() { now },
    read_only,
  }
  made.val = Some(src)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
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
/// The send button: the capsule's bottom right (opened: under the field).
fn tap_send(t : @ui.Tester) -> Unit {
  t.click(Button, label=@sf.t("web-main.composer.send")) catch {
    e => @halt.saying("no send button: \{e}")
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
  // sent, felt as a key's light tap
  assert_eq(t.haptics(), [@ui.KeyboardTap])
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
  // sent, then refused: felt each
  assert_eq(t.haptics(), [@ui.KeyboardTap, @ui.Reject])
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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("第二屏的截图，帮我看看") is Some(_))
  t.run_for(@sfpages.sending_shows_ms)
  assert_true(t.find("正在上传 42%") is Some(_))
  t.assert_idle()
}

///|
/// A video waiting in the composer looked like a picture waiting (2026-11-04): its tile has a solid play mark in its
/// middle; a picture's none.
test "a video waiting is told apart from a picture waiting by its play mark" {
  new_run()
  let src = fixture("chat-attach-video")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.image_fade_ms)
  let tiles = t.drawn_images().filter(fn(i) { (i[2] - 56.0).abs() < 0.5 && (i[3] - 56.0).abs() < 0.5 })
  tiles.sort_by(fn(a, b) { a[0].compare(b[0]) })
  assert_eq(tiles.length(), 2)
  // white shapes in a tile's middle half (its ✕ is on its corner): the video's play mark; none in the picture's
  let over = fn(i : Array[Double]) {
    t.drawn_shapes().filter(fn(s) {
      s.5 == 0xFFFFFFFFL && s.0 > i[0] + 14.0 && s.0 + s.2 < i[0] + 42.0 && s.1 > i[1] + 14.0 && s.1 + s.3 < i[1] + 42.0
    })
  }
  assert_eq(over(tiles[0]).length(), 0)
  let marks = over(tiles[1])
  assert_true(marks.length() > 0)
  // (its bands, one box)
  let mut top = 1.0e9
  let mut foot = -1.0e9
  for m in marks {
    top = if m.1 < top { m.1 } else { top }
    foot = if m.1 + m.3 > foot { m.1 + m.3 } else { foot }
  }
  assert_true(((top + foot) / 2.0 - (tiles[1][1] + 28.0)).abs() < 3.0, msg="\{Repr(marks)} \{Repr(tiles[1])}")
  assert_eq(t.squeeze_faults(), [])
}

///|
test "the fixture's station: sending, then the message, then an answer; a failure, then 重试" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // the chat pushed in over Home
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  assert_true(t.find("测试一下") is Some(_))
  assert_true(t.find("正在发送") is Some(_))
  // the station's clock on past its deliveries, its answers, a frame drawn for each
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  // (the line that said 正在发送 not seen once the station has it: drawn at no alpha over 0. Till 2026-11-14 this
  // said Tester::find found it no more, which reads no alpha: on the page made as nodes its part, leaving, is found
  // for 200 ms at alpha 0 in every frame, at (374, 719.1) 0×0 in the station's frame, never seen)
  let sending_seen = fn() { t.words().iter().any(fn(w) { w.0.contains("正在发送") && w.5 > 0.0 }) }
  let seen_at : Ref[Double?] = Ref(if sending_seen() { Some(t.time()) } else { None })
  assert_true(t.find("测试一下") is Some(_))
  // (the station answers fix_answer_ms later: that time passes on the page too, the words landed and the agent's line
  // come in meanwhile; 正在发送 seen in none of its frames)
  t.each_frame(Some(fn() { if seen_at.val is None && sending_seen() { seen_at.val = Some(t.time()) } }))
  t.run_for(fix_answer_ms)
  t.each_frame(None)
  assert_true(seen_at.val is None, msg="正在发送 seen once the station has it, at \{Repr(seen_at.val)}")
  fix_clock_set(clock, clock.val + fix_answer_ms)
  t.draw()
  // said while its agent's activity shows: out of its avatar once it has folded and hopped (emit.mbt)
  t.run_for(Pose::Fold.ms() + Pose::Float.ms())
  assert_true(t.find("收到：「测试一下」") is Some(_))
  // (its avatar home: what comes out of avatars is over, its turn too (two frames on), the next words sent go in
  // their turn after it)
  t.run_for(Pose::Spit.ms() + Pose::Return.ms() + 2.0 * @ui.frame_period_default)
  // words with 失败 in them fail first
  t.tap_text("发消息")
  t.type_text("这条会失败")
  tap_send(t)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  assert_true(t.find("未发送") is Some(_))
  // (its 重试 shown as its room opens to it: Ctx::row_size)
  t.run_for(@ui.move_most_ms)
  t.tap_text("重试")
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  // (what failed leaves the list as its room closes)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("未发送") is None)
  assert_true(t.find("这条会失败") is Some(_))
  // one that fails again: why, said once (无法重新发送：…)
  t.tap_text("发消息")
  t.type_text("这条失败了也重发不了")
  tap_send(t)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("重试")
  t.draw()
  assert_eq(app.toast.get().words, "无法重新发送：a.jpg 的上传源已丢失，请在新消息中重新添加附件。")
  fix_clock.val = None
}

///|
test "a picture sent from here is drawn in its message as it was picked, up before it was sent or after" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  // a PNG's header (IHDR 1600 × 900): a picture
  let png = Bytes::from_array([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x06, 0x40,
    0, 0, 0x03, 0x84, 8, 6, 0, 0, 0,
  ].map(fn(i) { i.to_byte() }))
  let w = @sfbase.writing(src, draft_key(r))
  @sfbase.writing_add(src, w, r.station, "shot.png", png)
  let id = text(Some(w.files.get()[0]), "id")
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
  let up = text(field(Some(@sfbase.writing(src, draft_key(r)).files.get()[0]), "done"), "path")
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
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let w = @sfbase.writing(src, draft_key(r))
  let picked = fn(name : String, held : Int, src : String) -> @hostapi.Picked {
    { name, bytes: if held == 0 { b"\x00\x00\x00\x18ftypmp42" } else { b"" }, held, size: 12.0, src }
  }
  @sfbase.writing_add_picked(src, w, r.station, picked("短片.mp4", 0, "content://media/video/7"))
  @sfbase.writing_add_picked(src, w, r.station, picked("长片.mov", 3, "content://media/video/8"))
  @sfbase.writing_add_picked(src, w, r.station, picked("合同.pdf", 0, "content://docs/9"))
  let ids = w.files.get().map(fn(f) { text(Some(f), "id") })
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
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let w = @sfbase.writing(src, draft_key(r))
  // (macOS's pasteboard and pickers, Windows', iOS's say no address for a file: no still of the host's)
  let clip = b"\x00\x00\x00\x14ftypqt  \x00\x00\x00\x08wide"
  @sfbase.writing_add(src, w, r.station, "录屏.mov", clip)
  let id = text(Some(w.files.get()[0]), "id")
  let seen = "ws1/st1//draft:" + id
  assert_eq(@sfbase.writing_pictures.get(id), None)
  // the composer built: a 56 × 56 picture tile from the first frame (never a 236 file card while its frame is read);
  // a player of it made out of sight, reading the bytes from here, its frame at 0 grabbed
  let before = t.views().length()
  t.draw()
  assert_eq(thumb_of(t.ctx(), seen).map(fn(tile) { (tile.w, tile.h, tile.picture) }), Some((56.0, 56.0, "")))
  assert_true(t.query(Group, label="录屏.mov") is None)
  // (a player's open: "open <id> 1 <its type's length>", video/quicktime)
  let opened = t.views()[before:].to_owned().filter(fn(l) { l.has_prefix("open ") && l.has_suffix(" 1 15") })
  assert_eq(opened.length(), 1)
  let view = (1).until(1000).find_first(fn(i) { opened[0].has_prefix("open \{i} ") }).unwrap()
  let req = t.view_reads(view, 0.0, 1 << 20)
  t.draw()
  assert_eq(thumb_of(t.ctx(), seen).map(fn(tile) { (tile.w, tile.h, tile.picture) }), Some((56.0, 56.0, "")))
  assert_true(t.query(Group, label="录屏.mov") is None)
  assert_eq(t.view_answers(view), [(req, clip.length(), clip.length().to_double())])
  assert_true(t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"89504e47\"}"))
  t.draw()
  let still = @sfbase.writing_pictures.get(id).unwrap()
  assert_true(still.has_prefix("mem:pv-first/"))
  assert_eq(thumb_of(t.ctx(), seen).map(fn(tile) { (tile.w, tile.h, tile.picture) }), Some((56.0, 56.0, still)))
  assert_true(t.query(Group, label="录屏.mov") is None)
  // sent while it still goes up: its message draws it from here, as a picture's
  let file = attachment_of({
    "name": Json::string("录屏.mov"),
    "path": Json::string(@sfbase.upload_path(id)),
    "size": Json::number(clip.length().to_double()),
    "upload": Json::string(id),
  })
  assert_eq(sent_picture(r.station, file), Some(still))
  // up before its first frame was ready: its message still draws it by the station's path
  let up = text(field(Some(@sfbase.writing(src, draft_key(r)).files.get()[0]), "done"), "path")
  assert_true(up != "")
  assert_eq(
    sent_picture(
      r.station,
      attachment_of({
        "name": Json::string("录屏.mov"),
        "path": Json::string("/w/s-c1/" + up),
        "size": Json::number(clip.length().to_double()),
        "upload": Json::string(""),
      }),
    ),
    Some(still),
  )
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
test "words sent as the composer grows a line: it slows to rest from as fast as it went, over the list's foot by no more than was left, then down with it" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一行")
  let foot = fn() {
    let rows = t.rows()
    rows[rows.length() - 1].2
  }
  let room = fn() { @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1") }
  let before = room()
  let over = foot() - before
  for line in ["第二行", "第三行", "第四行"] {
    t.enter()
    t.type_text(line)
  }
  // half way through its growing, sent: the composer slows to rest from as fast as it went (@motion.stop_for); the
  // list's room under the rows held as it was till the words let go of it, the composer over it by what was left to
  // grow at most, and down with it from then. Meant, till the composer is a node (send_hold_wbtest's hold_cover)
  t.run_for(@ui.row_size_ms / 2.0)
  let growing = room()
  assert_true(growing > before)
  assert_eq(foot(), growing + over)
  let left = @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1", settled=true) - growing
  tap_send(t)
  assert_eq(named(calls, "chat.send").length(), 1)
  let mut most = growing
  let mut was = @double.infinity
  let end = t.time() + @sfbase.flight_most_ms + @ui.move_most_ms
  while t.time() < end {
    let cover = room() + over - foot()
    // (the composer's way and the list's two curves to the same end, half a point apart at most, send_hold_wbtest's
    // hold_cover_slack)
    assert_true(cover <= left + 0.5, msg="at \{t.time()}: covers \{cover} of \{left}")
    match @sfbase.flight_lets_go("ws1/st1:s-c1") {
      // (let go of: less at every frame on, the list's room and the composer down to the same)
      Some((go, _)) if t.time() >= go => {
        assert_true(cover <= was + 0.5, msg="at \{t.time()}: covers \{cover} after \{was}")
        was = cover
      }
      _ => ()
    }
    most = if room() > most { room() } else { most }
    t.frame()
  }
  assert_true(was <= 0.5, msg="still over it by \{was} once down")
  // (carried on past where it was as it was sent, and down since)
  assert_true(most > growing && room() < most, msg="\{growing} \{most} \{room()}")
  t.run_for(draft_keep_ms)
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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_eq(ends, [true])
  // someone says something: it comes at the end, the list gliding to it (list_to_end, the frame it comes)
  said_by_ana(171, "我也来看看")
  fix_clock_set(clock, clock.val + fix_said_ms)
  t.draw()
  assert_true(t.find("我也来看看") is Some(_))
  let rest = t.rest_of("a list")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
  //  told end:false as it comes, its room
  // opening, end:true once it is open; at its end as it rests
  assert_true(ends.contains(false))
  assert_eq(ends[ends.length() - 1], true)
  // words sent, then the agent's answer (in over the agent's line, what is at the end: the list at its end at once, the
  // rows over it going up for it): at its end again as it rests
  t.tap_text("发消息")
  t.type_text("测试一下")
  tap_send(t)
  fix_clock_set(clock, clock.val + fix_deliver_ms)
  t.draw()
  // (the station answers fix_answer_ms later: that time passes on the page too)
  t.run_for(fix_answer_ms)
  fix_clock_set(clock, clock.val + fix_answer_ms)
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
  t.run_for(@sf.presented_rest() - t.time())
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
  t.run_for(@sf.presented_rest() - t.time())
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
  t.run_for(@sf.presented_rest() - t.time())
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
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
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

///|
test "lines typed while words sent let go of the composer: the list's foot goes where it comes to stand with them, not after" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一条")
  t.enter()
  t.type_text("两行")
  tap_send(t)
  // (as the words fly, two lines more: the composer comes to stand three lines tall, not one)
  t.run_for(@ui.row_size_ms / 2.0)
  t.type_text("接着写")
  t.enter()
  t.type_text("又一行")
  t.enter()
  let foot = fn() {
    let rows = t.rows()
    rows[rows.length() - 1].2
  }
  // every frame the rows steady (rows_steady.mbt: the foot's room opening at once, as the words' flight was over, put
  // every row over it up by it in one frame), and the foot where the composer comes to stand
  t.run_for(@ui.move_most_ms)
  let over = foot() - @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1")
  t.run_for(draft_keep_ms)
  // (the list's way and the composer's ground's to the same end, a hair apart on their last frames: a hundredth of a
  // point; the composer stopped where it was going as the words were sent, @motion.stop_for)
  let now = foot() - @sfpages.composer_room(t.ctx(), "ws1/st1:s-c1")
  assert_true((now - over).abs() < 0.01, msg="\{now} after \{over}")
  t.assert_idle()
}

///|
test "send pressed before a frame has shown the words typed: they go all the same" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  // (the words told by the input method and send pressed before the composer was built again: the button as it was
  // with the field empty, as a scripted run's type and tap a few milliseconds apart)
  t.text_told("马上发出去", t.time())
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "马上发出去")
}
