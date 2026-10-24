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
test "a picture waiting in the composer, tapped, opens in the viewer from the bytes picked" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "照片.png", png_head())
  t.draw()
  t.run_for(@sfpages.morph_ms)
  let id = text(Some(@sfbase.writing(src, "ws1/st1:s-c1").files[0]), "id")
  let seen = "ws1/st1//draft:" + id
  let tile = match pv_thumbs.get(seen) {
    Some(tile) => tile
    None => fail("the tile is not kept for the viewer to fly from")
  }
  t.tap(tile.x + tile.w / 2.0, tile.y + tile.h / 2.0)
  match viewer.val {
    Some(v) => {
      assert_eq(v.file.path, "draft:" + id)
      assert_eq(v.id(), seen)
      // nothing to mark it into: it is in the draft already
      assert_eq(v.draft_key(), "")
      // from the bytes picked: none asked of the station
      assert_true(v.bytes is Some(_))
    }
    None => fail("the viewer did not open")
  }
  assert_eq(named(calls, "station.file").length(), 0)
  // the picture is not taken out by the tap
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.length(), 1)
  t.back()
  t.run_for(preview_rest() - t.time())
  assert_true(viewer.val is None)
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
test "the composer's buttons say what they are: ＋ (发送文件), 发送" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  t.tap_text("发消息")
  t.type_text("第一行要点")
  let labels = t.semantics().filter(fn(s) { s.role == @ui.Role::Button }).map(fn(s) { s.label })
  assert_true(labels.contains(@sf.t("web-main.composer.attach")))
  assert_true(labels.contains("发送"))
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
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "截图.png", png_head())
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
  assert_eq(ff.from.2, 56.0)
  // its row in the list (the outbox's, at once): the picture goes to where the message has it
  t.draw()
  t.draw()
  match @motion.measured_rect(t.ctx(), "flight/to/" + ff.path) {
    Some((_, _, w, _)) => assert_true(w > 56.0)
    None => fail("the message's picture is not where the flight can see it")
  }
  t.run_for(flight_ms)
  assert_true(send_flight.val is None)
  fix_clock.val = None
}
