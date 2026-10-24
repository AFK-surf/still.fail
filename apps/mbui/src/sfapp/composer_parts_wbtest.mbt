// The composer's parts as Android's (Composer.kt, ChatFiles.kt, StationFiles.kt, Keyboard.kt): what waits to go (its
// files in the order they were put in, a row that scrolls sideways; a picture opening in the viewer, a link opening,
// a file going up said as it goes), the quotes kept to 176, the archived chat's restore, what the buttons are called,
// a long press letting the keyboard be. Over the fake core of composer_wbtest.mbt.

///|
fn the_draft() -> Draft {
  drafts.get("ws1/st1:s-c1").unwrap()
}

///|
/// A PNG's first bytes (IHDR 1600 × 900): what a picture's size is read from.
fn png_head() -> Bytes {
  Bytes::from_array(
    [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x06, 0x40, 0, 0, 0x03,
      0x84, 8, 6, 0, 0, 0,
    ].map(fn(i) { i.to_byte() }),
  )
}

///|
test "a file goes to the core whole, named by its content, and says how far the core has sent it up" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, made~, ups~)
  let d = the_draft()
  let bytes = Bytes::make(1000, b'x')
  add_file(made.val.unwrap(), d, "ws1/st1", "大文件.bin", bytes, None)
  t.draw()
  let adds = named(calls, "composer.add")
  assert_eq(adds.length(), 1)
  // its bytes beside the call, all of them; its content's SHA-256 with it (a station that has it copies its own)
  let blob = field(handed(adds[0]), "blob")
  assert_eq(field(blob, "hostBytes"), Some([0, 1000]))
  assert_eq(text(blob, "sha256"), @zip.sha256(bytes))
  assert_eq(adds[0].bytes.map(fn(b) { b.length() }), Some(1000))
  assert_eq(text(Some(adds[0].params), "key"), "mbui:ws1/st1:s-c1")
  // a quarter of it up: so much
  going_up(ups, adds[0], 250)
  t.draw()
  assert_true(t.dump().contains("正在上传 25%"))
  upped(ups, adds[0])
  t.draw()
  assert_true(t.dump().contains("正在上传") == false)
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "a big file the host holds (a video): to the core by the host's id, read from there as it goes up; its tile the host's still" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, made~, ups~)
  let d = the_draft()
  let video : @hostapi.Picked = {
    name: "录屏.mp4",
    bytes: b"",
    held: 7,
    size: 300_000_000.0,
    src: "content://media/external/video/media/42",
  }
  add_held_file(made.val.unwrap(), d, "ws1/st1", video)
  t.draw()
  let adds = named(calls, "composer.add")
  assert_eq(adds.length(), 1)
  // nothing beside the call: the host's file, its size and kind (the core reads it a part at a time: picked.read)
  assert_true(adds[0].bytes is None)
  let blob = field(handed(adds[0]), "blob")
  assert_eq(field(blob, "hostFile"), Some(Json::number(7.0)))
  assert_eq(field(blob, "size"), Some(Json::number(300_000_000.0)))
  assert_eq(text(blob, "type"), "video/mp4")
  assert_eq(d.files[0].image, "content://media/external/video/media/42")
  // as far as the core has sent it up, then up
  going_up(ups, adds[0], 75_000_000)
  t.draw()
  assert_eq(d.files[0].sent, 75_000_000)
  upped(ups, adds[0])
  t.draw()
  assert_true(d.files[0].done is Some(_))
}

///|
test "sent while a file is going up: the message names it (uploads) and the core sends it once it is up" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let d = the_draft()
  add_file(made.val.unwrap(), d, "ws1/st1", "报告.pdf", b"%PDF-1.7", None)
  t.draw()
  t.tap_text("发消息")
  t.type_text("附上报告")
  // still going up, and the message can go
  assert_true(t.find("正在上传") is Some(_))
  assert_true(draft_ready(d, false))
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(field(Some(sent[0].params), "attachments"), Some([]))
  match field(Some(sent[0].params), "uploads") {
    Some(Array([u])) => {
      assert_eq(text(Some(u), "id"), text(handed(named(calls, "composer.add")[0]), "id"))
      assert_eq(text(Some(u), "name"), "报告.pdf")
      assert_eq(number(Some(u), "size"), 8.0)
    }
    _ => fail("the file going up was not named")
  }
  t.run_for(flight_wait_ms + composer_morph_ms)
  // (its row under way: said so once it has been a while, sfpages chat_rows.mbt)
  t.run_for(@sfpages.sending_shows_ms)
  t.assert_idle()
}

///|
test "a file that failed going up in the core: the message waits for it; tapped, it goes again (composer.retry)" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, made~, ups~)
  let d = the_draft()
  add_file(made.val.unwrap(), d, "ws1/st1", "报告.pdf", b"%PDF-1.7", None)
  let add = named(calls, "composer.add")[0]
  let id = text(handed(add), "id")
  ups[id] = { "id": Json::string(id), "name": "报告.pdf", "size": 8, "error": "station 没有回应" }
  t.draw()
  t.tap_text("发消息")
  t.type_text("附上报告")
  assert_true(t.find("station 没有回应") is Some(_))
  // never left out unsaid: nothing goes until it is sent again or taken out
  assert_false(draft_ready(d, false))
  let again = t.query(Button, label="重试上传").unwrap().rect
  t.tap(again.0 + again.2 / 2.0, again.1 + again.3 / 2.0)
  let retried = named(calls, "composer.retry")
  assert_eq(retried.length(), 1)
  assert_eq(text(Some(retried[0].params), "id"), id)
  assert_eq(text(Some(retried[0].params), "key"), "mbui:ws1/st1:s-c1")
  // going again: what failed not said meanwhile, and the message can go
  ups.remove(id)
  t.draw()
  assert_true(t.find("station 没有回应") is None)
  assert_true(draft_ready(d, false))
  upped(ups, add)
  t.draw()
  t.run_for(composer_morph_ms)
  t.assert_idle()
}

///|
test "a file taken out while it goes up: the core lets go of it (composer.remove)" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let d = the_draft()
  add_file(made.val.unwrap(), d, "ws1/st1", "报告.pdf", b"%PDF-1.7", None)
  t.draw()
  t.run_for(composer_morph_ms)
  take_out(made.val.unwrap(), d, d.files[0])
  let removed = named(calls, "composer.remove")
  assert_eq(removed.length(), 1)
  assert_eq(text(Some(removed[0].params), "id"), text(handed(named(calls, "composer.add")[0]), "id"))
  assert_eq(d.files.length(), 0)
}

///|
test "a picture waiting in the composer, tapped, opens in the viewer from the bytes picked" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, made~, ups~)
  let d = the_draft()
  let bytes = png_head()
  add_file(made.val.unwrap(), d, "ws1/st1", "照片.png", bytes, None)
  t.draw()
  t.run_for(composer_morph_ms)
  let f = d.files[0]
  let id = "ws1/st1//draft:\{f.id}"
  let tile = match pv_thumbs.get(id) {
    Some(tile) => tile
    None => fail("the tile is not kept for the viewer to fly from")
  }
  t.tap(tile.x + tile.w / 2.0, tile.y + tile.h / 2.0)
  match viewer.val {
    Some(v) => {
      assert_eq(v.file.path, "draft:\{f.id}")
      assert_eq(v.id(), id)
      // nothing to mark it into: it is in the draft already
      assert_eq(v.draft_key(), "")
      // from the bytes picked: none asked of the station
      assert_true(v.bytes is Some(_))
    }
    None => fail("the viewer did not open")
  }
  assert_eq(named(calls, "station.file").length(), 0)
  // the picture is not taken out by the tap
  assert_eq(d.files.length(), 1)
  t.back()
  t.run_for(preview_rest() - t.time())
  assert_true(viewer.val is None)
  upped(ups, named(calls, "composer.add")[0])
  t.draw()
  t.assert_idle()
}

///|
test "a link shared into the draft, tapped, opens" {
  let calls : Array[Made] = []
  let t = fake_core(calls, kept={
    "text": "",
    "quotes": [],
    "files": [],
    "links": [{ "url": "https://example.com/notes/a1", "title": "一篇笔记", "site": "example.com" }],
  })
  t.run_for(composer_morph_ms)
  t.tap_text("一篇笔记")
  assert_eq(t.opened(), ["https://example.com/notes/a1"])
  // still in the draft
  assert_eq(the_draft().files.length(), 1)
  t.assert_idle()
}

///|
test "the draft's files and its station files are one row, in the order they were put in, every card a file's mark" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, made~, ups~)
  let src = made.val.unwrap()
  let d = the_draft()
  add_file(src, d, "ws1/st1", "第一份.txt", b"one", None)
  draft_refs[d.key] = [draft_ref("ws1/st1", "Studio", "/Users/lin/文档", "第二份.md", "第二份.md", false, size=12.0)]
  add_file(src, d, "ws1/st1", "第三份.pdf", b"three", None)
  for p in named(calls, "composer.add") {
    upped(ups, p)
  }
  t.draw()
  t.run_for(composer_morph_ms)
  let x = fn(name : String) {
    match t.rect_of(name) {
      Some((x, _, _, _)) => x
      None => -1.0
    }
  }
  let (x1, x2, x3) = (x("第一份.txt"), x("第二份.md"), x("第三份.pdf"))
  assert_true(x1 >= 0.0 && x2 > x1 && x3 > x2)
  // their tops in line
  let y = fn(name : String) { t.rect_of(name).unwrap().1 }
  assert_eq(y("第一份.txt"), y("第二份.md"))
  // wider than the capsule: the row scrolls sideways, held still before it is let go (no fling)
  let (_, row_y, _, _) = t.rect_of("第一份.txt").unwrap()
  t.press_at(300.0, row_y)
  for step in 1..=8 {
    t.move(300.0 - step.to_double() * 30.0, row_y)
  }
  t.run_for(long_press_ms)
  t.release(60.0, row_y)
  assert_true(x("第三份.pdf") < x3)
  assert_true(x("第三份.pdf") > 0.0)
}

///|
test "quotes taller than 176 scroll inside it" {
  let calls : Array[Made] = []
  let quotes : Array[Json] = []
  for i in 1..=6 {
    quotes.push({ "author": "林", "text": Json::string("第 \{i} 段要再看一遍的话"), "comment": "", "role": "person" })
  }
  let t = fake_core(calls, kept={ "text": "", "quotes": Json::array(quotes), "files": [] })
  t.run_for(composer_morph_ms)
  let (_, first_y, _, _) = t.rect_of("第 1 段要再看一遍的话").unwrap()
  let (_, last_y, _, _) = t.rect_of("第 6 段要再看一遍的话").unwrap()
  // more than 176 of them: the last laid out below what is shown
  assert_true(last_y - first_y > 176.0)
  t.press_at(195.0, first_y)
  for step in 1..=8 {
    t.move(195.0, first_y - step.to_double() * 20.0)
  }
  t.run_for(long_press_ms)
  t.release(195.0, first_y - 160.0)
  let (_, moved_y, _, _) = t.rect_of("第 6 段要再看一遍的话").unwrap()
  assert_true(moved_y < last_y)
}

///|
test "an archived chat's restore failing says why under it, in red; tapped again it is tried again" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["archived"] = Json::boolean(true)
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  t.tap_text("还原对话")
  let asked = named(calls, "chat.archive")
  assert_eq(asked.length(), 1)
  assert_true(t.find("正在还原") is Some(_))
  (asked[0].done)(Err({ "code": "offline", "message": "station 没有回应" }))
  t.draw()
  assert_true(t.find("station 没有回应") is Some(_))
  t.tap_text("还原对话")
  assert_eq(named(calls, "chat.archive").length(), 2)
  // tried again: what failed before is not said meanwhile
  assert_true(t.find("station 没有回应") is None)
  // the capsule back to its height without the line
  t.run_for(composer_morph_ms)
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "the composer's buttons say what they are: 添加到消息, 发送; a pasted text's remove 删除粘贴片段" {
  let calls : Array[Made] = []
  let ups : Map[String, Json] = {}
  let t = fake_core(calls, ups~)
  t.tap_text("发消息")
  t.type_text("第一行要点\n" + String::make(6000, 'x'))
  let labels = t.semantics().filter(fn(s) { s.role == @ui.Role::Button }).map(fn(s) { s.label })
  assert_true(labels.contains("添加到消息"))
  assert_true(labels.contains("发送"))
  assert_true(labels.contains("删除粘贴片段"))
  upped(ups, named(calls, "composer.add")[0], path="uploads/u/p.txt")
  t.draw()
  t.run_for(draft_keep_ms)
  t.assert_idle()
}

///|
test "a long press on a message lets the keyboard be; a tap on it lets it go" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("写到一半")
  // (a message above the opened composer: a press on it is outside it)
  let (x, y) = t.find("推送截图前要先登录 gh。").unwrap()
  // the field's top (an editor's node holds its placeholder, not its words: where the input method is told it is)
  let (_, cap_y, _, _) = t.ime_rect()
  assert_true(y < cap_y - 60.0)
  t.press_at(x, y)
  t.run_for(long_press_ms)
  t.release(x, y)
  let (active, _, _, _) = t.ime()
  assert_true(active)
  // what was picked let go, then a tap on the message's words: the keyboard goes
  t.back()
  t.tap(x, y)
  let (after, _, _, _) = t.ime()
  assert_false(after)
}

///|
test "files sent fly from their tiles to their places in the message, then are its own" {
  reset()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  // a picture up at once (the fixture's station takes it), its tile in the composer
  add_file(src, the_draft(), "ws1/st1", "截图.png", png_head(), None)
  t.draw()
  t.run_for(composer_morph_ms)
  t.tap_text("发消息")
  t.type_text("看这张")
  tap_send(t)
  let f = match send_flight.val {
    Some(f) => f
    None => fail("nothing flies")
  }
  assert_eq(f.files.length(), 1)
  let ff = f.files[0]
  assert_true(ff.path.has_prefix("uploads/"))
  assert_true(ff.picture != "")
  // from its tile: 56 across
  assert_eq(ff.from.2, picture_tile)
  // its row in the list (the outbox's, at once): the picture goes to where the message has it
  t.draw()
  t.draw()
  match @motion.measured_rect(t.ctx(), "flight/to/" + ff.path) {
    Some((_, _, w, _)) => assert_true(w > picture_tile)
    None => fail("the message's picture is not where the flight can see it")
  }
  t.run_for(flight_ms)
  assert_true(send_flight.val is None)
  fix_clock.val = None
}
