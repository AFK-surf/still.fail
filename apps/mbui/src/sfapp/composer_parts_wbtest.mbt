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
  t.run_for(@ui.move_most_ms)
  let id = text(Some(@sfbase.writing(src, "ws1/st1:s-c1").files[0]), "id")
  let seen = "ws1/st1//draft:" + id
  let tile = match thumb_of(t.ctx(), seen) {
    Some(tile) => tile
    None => fail("the tile is not kept for the viewer to fly from")
  }
  t.tap(tile.x + tile.w / 2.0, tile.y + tile.h / 2.0)
  match viewer.get() {
    Some(v) => {
      assert_eq(v.file.path, "draft:" + id)
      assert_eq(v.id(), seen)
      // nothing to mark it into: it is in the draft already
      assert_eq(v.draft_key(), "")
      // from the bytes picked: none asked of the station
      assert_true(v.bytes.get() is Some(_))
    }
    None => fail("the viewer did not open")
  }
  assert_eq(named(calls, "station.file").length(), 0)
  // the picture is not taken out by the tap
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.length(), 1)
  t.back()
  t.run_for(preview_rest() - t.time())
  assert_true(viewer.get() is None)
}

///|
test "what waits to go has its ✕ hung on its corner, its centre on the curve, a picture's and a file's card alike, on a phone and a computer alike, clear of the next; tapped, it takes it out" {
  // (Android, then macOS: one design on every screen, docs/ui-panels.md)
  for platform in [2, 0] {
    let calls : Array[Made] = []
    let made : Ref[Source?] = Ref(None)
    let t = fake_core(calls, made~, platform~)
    let src = made.val.unwrap()
    let w = @sfbase.writing(src, "ws1/st1:s-c1")
    @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
    @sfbase.writing_add(src, w, "ws1/st1", "第二张.png", png_head())
    @sfbase.writing_add(src, w, "ws1/st1", "build.log", @utf8.encode("夜里的构建日志"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    let tiles = @sfbase.writing(src, "ws1/st1:s-c1").files.filter_map(fn(f) {
      thumb_of(t.ctx(), "ws1/st1//draft:" + text(Some(f), "id"))
    })
    assert_eq(tiles.length(), 2)
    let first = tiles[0]
    let next = tiles[1]
    let card = match t.query(Group, label="build.log") {
      Some(g) => g.rect
      None => fail("no card for build.log (platform \{platform})")
    }
    let near = fn(a : Double, b : Double) { (a - b).abs() < 0.01 }
    // each ✕'s centre on the curve of the corner it is hung on, as far past the top as past the right edge
    for one in [
      ("照片.png", first.x, first.y, first.w, first.radius),
      // (a file's card as round as a picture's: what waits, all alike)
      ("build.log", card.0, card.1, card.2, first.radius),
    ] {
      let (name, ox, oy, ow, corner) = one
      let (x, y, bw, bh) = match t.query(Button, label=@sf.t("web-main.file.remove", args=[("name", name)])) {
        Some(b) => b.rect
        None => fail("no ✕ on \{name} (platform \{platform})")
      }
      let m = @ui.smooth_middle(corner)
      assert_true(near(x + bw / 2.0, ox + ow - m), msg="\{name}'s ✕ across (platform \{platform}): \{x + bw / 2.0}")
      assert_true(near(y + bh / 2.0, oy + m), msg="\{name}'s ✕ down (platform \{platform}): \{y + bh / 2.0}")
      assert_true(near(oy - y, x + bw - (ox + ow)), msg="\{name}'s ✕ reach (platform \{platform})")
    }
    // the next picture the row's gap (6) past the first one's ✕, not under it
    let (x, y, bw, bh) = t.query(Button, label=@sf.t("web-main.file.remove", args=[("name", "照片.png")])).unwrap().rect
    assert_true(next.x >= x + bw + 6.0 - 0.01, msg="the next at \{next.x}, the ✕ ends at \{x + bw}")
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.draw()
    let (cx, cy, cw, ch) = t.query(Button, label=@sf.t("web-main.file.remove", args=[("name", "build.log")])).unwrap().rect
    t.tap(cx + cw / 2.0, cy + ch / 2.0)
    t.draw()
    let left = @sfbase.writing(src, "ws1/st1:s-c1").files
    assert_eq(left.length(), 1)
    assert_eq(text(Some(left[0]), "name"), "第二张.png")
  }
}

///|
test "a waiting file's card stands off the composer's frosted ground by its own ground alone, as tall as a picture beside it, on a phone and a computer alike" {
  // (the user, 2026-10-16: 附件有点难以分辨; 2026-10-25: 背景色好分辨就行了，不用这么深阴影; @sf.composer_card)
  for platform in [2, 0] {
    let calls : Array[Made] = []
    let made : Ref[Source?] = Ref(None)
    let t = fake_core(calls, made~, platform~)
    let src = made.val.unwrap()
    let w = @sfbase.writing(src, "ws1/st1:s-c1")
    @sfbase.writing_add(src, w, "ws1/st1", "照片.png", png_head())
    @sfbase.writing_add(src, w, "ws1/st1", "build.log", @utf8.encode("夜里的构建日志"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    let (x, y, cw, ch) = match t.query(Group, label="build.log") {
      Some(g) => g.rect
      None => fail("no card for build.log (platform \{platform})")
    }
    let near = fn(a : Double, b : Double) { (a - b).abs() < 0.5 }
    // (the capsule whiter than its paper: the neutral)
    let ground = @sf.theme().p.neutral_bg
    let drawn = t.drawn_rects().filter(fn(r) { near(r.0, x) && near(r.1, y) && near(r.2, cw) && near(r.3, ch) })
    assert_true(drawn.iter().any(fn(r) { r.4 == ground }), msg="its ground (platform \{platform}): \{drawn.map(fn(r) { r.4 })}, not \{ground}")
    assert_false(t.drawn_shadows().iter().any(fn(s) { near(s.0, x) && near(s.2, cw) }), msg="a shadow under it (platform \{platform})")
    let tiles = @sfbase.writing(src, "ws1/st1:s-c1").files.filter_map(fn(f) {
      thumb_of(t.ctx(), "ws1/st1//draft:" + text(Some(f), "id"))
    })
    assert_eq(tiles.length(), 1)
    assert_true(near(ch, tiles[0].h), msg="the card \{ch} high, the picture \{tiles[0].h} (platform \{platform})")
  }
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
  t.run_for(@ui.move_most_ms)
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "its agent's cache over: the current choice opens the choices and changing it asks once" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(v) => { ..tp, value: Some(@sffixture.with_cache_cold(v)) }
      None => tp
    }
  })
  assert_true(t.find("缓存已过期") is Some(_))
  assert_true(t.find("重读约 $1.49") is Some(_))
  t.click(Button, label="接着聊")
  assert_true(t.get(MenuItemRadio, label="接着聊").check is Some(On))
  assert_true(t.get(MenuItemRadio, label="换新上下文").check is Some(Off))
  t.click(MenuItemRadio, label="接着聊")
  t.draw()
  assert_eq(named(calls, "session.settings").length(), 0, msg="the one taken: nothing to ask")
  t.run_for(@kit.pop_out_ms)
  t.click(Button, label="接着聊")
  t.click(MenuItemRadio, label="换新上下文")
  t.draw()
  let asked = named(calls, "session.settings")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "key"), "s-c1")
  assert_eq(field(Some(asked[0].params), "afresh"), Some(Json::boolean(true)))
  t.draw()
  assert_true(t.get(Button, label="接着聊").disabled, msg="the choice is held while the change is on its way")
  assert_eq(named(calls, "session.settings").length(), 1, msg="on its way: not asked again")
}

///|
test "its agent's cache over, set to go on afresh: 换新上下文 taken, 接着聊 takes going on" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["cacheCold"] = { "session": "s-c1", "status": "缓存已过期", "detail": "重读约 $1.49", "afresh": true }
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  assert_true(t.find("缓存已过期") is Some(_))
  assert_true(t.find("重读约 $1.49") is Some(_))
  t.click(Button, label="换新上下文")
  assert_true(t.get(MenuItemRadio, label="换新上下文").check is Some(On))
  t.click(MenuItemRadio, label="接着聊")
  t.draw()
  let asked = named(calls, "session.settings")
  assert_eq(asked.length(), 1)
  assert_eq(field(Some(asked[0].params), "afresh"), Some(Json::boolean(false)))
}

///|
test "an offline station's cache choice stays visible but cannot be opened" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" { return tp }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["cacheCold"] = { "session": "s-c1", "status": "缓存已过期", "detail": "重读约 $1.49", "afresh": false }
        o2["offline"] = Json::boolean(true)
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  assert_true(t.get(Button, label="接着聊").disabled)
  assert_true(t.query(MenuItemRadio, label="换新上下文") is None)
  assert_eq(named(calls, "session.settings").length(), 0)
}

///|
test "a cache notice on a narrow page keeps its cost together and both choices reachable" {
  let calls : Array[Made] = []
  let status = "缓存已过期"
  let detail = "重读约 $7.50"
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["cacheCold"] = { "session": "s-c1", "status": Json::string(status), "detail": Json::string(detail), "afresh": true }
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  t.resize(360.0, 844.0)
  t.set_font_scale(1.3)
  t.draw()
  assert_eq(t.lines_of(status), [status], msg="the status fits beside the mark")
  assert_eq(t.lines_of(detail), [detail], msg="the cost stays together")
  t.click(Button, label="换新上下文")
  assert_true(t.get(MenuItemRadio, label="换新上下文").check is Some(On))
  t.click(MenuItemRadio, label="接着聊")
  let asked = named(calls, "session.settings")
  assert_eq(asked.length(), 1)
  assert_eq(field(Some(asked[0].params), "afresh"), Some(Json::boolean(false)))
}

///|
test "the cache notice keeps status and cost together with a compact choice on a narrow page" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" { return tp }
    match tp.value {
      Some(v) => { ..tp, value: Some(@sffixture.with_cache_cold(v)) }
      None => tp
    }
  })
  t.resize(360.0, 844.0)
  t.draw()
  let (sx, sy, sw, _) = t.rect_of("缓存已过期").unwrap()
  let (dx, dy, _, _) = t.rect_of("重读约 $1.49").unwrap()
  let (cx, cy, cw, _) = t.get(Button, label="接着聊").rect
  assert_true(dx >= sx + sw && dy == sy, msg="the status and cost share a line")
  let glass = t.drawn_glass_corners().filter(fn(g) { g.0 < sx && g.0 + g.2 > cx + cw && g.1 < sy && g.1 + g.3 > cy })
  assert_eq(glass.length(), 1)
  t.click(Button, label="接着聊")
  t.click(MenuItemRadio, label="换新上下文")
  assert_eq(named(calls, "session.settings").length(), 1)
}

///|
test "its agent's cache over, in the wide frame: said over the composer, 换新上下文 sets it to go on afresh" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-cache-cold", wide=true)
  assert_true(t.find("缓存已过期") is Some(_))
  assert_true(t.find("重读约 $1.49") is Some(_))
  let (_, sy, _, sh) = t.rect_of("缓存已过期").unwrap()
  let (_, cy, _, ch) = t.get(Button, label="接着聊").rect
  assert_true((sy + sh / 2.0 - cy - ch / 2.0).abs() < 1.0, msg="status and choice are centred together")
  t.click(Button, label="接着聊")
  t.click(MenuItemRadio, label="换新上下文")
  t.draw()
  let asked = named(calls, "session.settings")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "key"), "s-c1")
  assert_eq(field(Some(asked[0].params), "afresh"), Some(Json::boolean(true)))
}

///|
test "a notice over the composer wrapped to lines: round as one line is, its mark on its first line" {
  let calls : Array[Made] = []
  let said = "「ccvm」正在更新：当前显示的是之前读取的内容，更新完成后会自动重新连接，发出的消息届时送达"
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["offline"] = Json::boolean(true)
        o2["updating"] = Json::boolean(true)
        o2["offlineNote"] = Json::string(said)
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  t.run_for(@ui.move_most_ms)
  let (wx, wy, _, wh) = t.rect_of(said).unwrap()
  let line = @sf.theme().t.meta_line
  assert_true(wh > 1.5 * line, msg="wrapped (\{wh} high)")
  let notice = t
    .drawn_glass_corners()
    .filter(fn(g) { g.0 < wx && g.0 + g.2 > wx && g.1 < wy && g.1 + g.3 > wy + wh })
  assert_eq(notice.length(), 1)
  let (gx, gy, _, _, corner) = notice[0]
  // as round as it is high on one line: its words' line and 8 over and under it
  assert_eq(corner, line / 2.0 + 8.0)
  // its mark in the middle of its round start, on its words' first line: its ring's (its lines each a piece of their
  // own; its leftmost pieces, about its middle, the ring's: the arrows in it, one hidden under it, are narrower)
  let marks = t
    .drawn_order()
    .filter(fn(d) { d.0 != 5 && d.0 != 6 && d.1 >= gx && d.1 + d.3 <= wx && d.2 >= gy && d.2 + d.4 <= wy + wh })
  assert_true(marks.length() > 0, msg="its mark drawn")
  let left = marks.fold(init=@double.infinity, fn(a, m) { if m.1 < a { m.1 } else { a } })
  let ring = marks.filter(fn(m) { m.1 < left + 0.5 })
  let mid = ring.fold(init=0.0, fn(a, m) { a + m.2 + m.4 / 2.0 }) / ring.length().to_double()
  assert_true((mid - (wy + line / 2.0)).abs() < 1.0, msg="its mark at \{mid}, its first line's middle \{wy + line / 2.0}")
  assert_true((mid - (gy + corner)).abs() < 1.0, msg="its mark at \{mid}, its round start's middle \{gy + corner}")
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
test "a picture restored in the composer remains visible in the sending message" {
  new_run()
  let base = fixture("chat")
  let in_draft = Ref(true)
  let src : Source = {
    ..base,
    draft_picture: fn(_, _) {
      @ui.add_image("mem:test/restored", png_head())
      "mem:test/restored"
    },
    // Its station has not supplied a picture: the message must use the one already in the composer.
    file: fn(_, _, _) { "" },
    topic: fn(name, params) {
      let now = (base.topic)(name, params)
      if name != "composer" || !in_draft.val { return now }
      let m = match now.value { Some(Object(v)) => v.copy(); _ => {} }
      m["files"] = [{ "id": "kept-1", "name": "截图.png", "size": 120, "sent": 40 }]
      m["ready"] = Json::boolean(true)
      { value: Some(Json::object(m)), error: now.error, version: now.version + 1 }
    },
    call: fn(name, params, done) {
      match name {
        "composer.take" => {
          in_draft.val = false
          done(Ok({ "text": "", "quotes": [], "attachments": [], "uploads": [{ "id": "kept-1", "name": "截图.png", "size": 120 }], "version": 2 }))
        }
        "chat.send" => ()
        _ => (base.call)(name, params, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  assert_true(t.locate("img:mem:test/restored").length() > 0)
  tap_send(t)
  let flying = send_flight.get().unwrap().files
  assert_eq(flying.map(fn(f) { (f.key, f.picture) }), [("upload:kept-1", "mem:test/restored")])
  t.run_for(@sfbase.flight_most_ms)
  let points = t.locate("img:mem:test/restored")
  assert_true(points.length() > 0, msg="the sending message has no picture")
  assert_true(points.iter().any(fn(p) {
    t.drawn_images().iter().any(fn(i) { i[8] > 0.9 && p.0 >= i[0] && p.0 <= i[0] + i[2] && p.1 >= i[1] && p.1 <= i[1] + i[3] })
  }), msg="the sending message did not draw the picture: \{t.drawn_images()}")
}

///|
test "a freshly picked picture remains visible throughout sending" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "截图.png", png_head())
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  let tile = t.drawn_images().filter(fn(i) { (i[2] - 56.0).abs() < 0.5 && i[8] > 0.9 })
  assert_true(tile.length() > 0, msg="no visible picture in the composer: \{t.drawn_images()}")
  tap_send(t)
  assert_true(t.drawn_images().iter().any(fn(i) { i[2] >= 55.5 && i[8] > 0.9 }), msg="as it is sent: \{t.drawn_images()}")
  t.run_for(@sfbase.flight_len(true) * 0.4)
  assert_true(t.drawn_images().iter().any(fn(i) { i[2] > 56.5 && i[8] > 0.9 }), msg="on its way: \{t.drawn_images()}")
  t.run_for(@sfbase.flight_len(true) + @sf.hint_back_ms)
  assert_true(t.drawn_images().iter().any(fn(i) { i[2] > 56.5 && i[8] > 0.9 }), msg="in the message: \{t.drawn_images()}")
}

///|
test "files sent fly from their tiles to their places in the message, then are its own" {
  new_run()
  let clock : Ref[Double] = { val: 0.0 }
  fix_clock.val = Some(fn() { clock.val })
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // a picture up at once (the fixture's station takes it), its tile in the composer
  @sfbase.writing_add(src, @sfbase.writing(src, "ws1/st1:s-c1"), "ws1/st1", "截图.png", png_head())
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("发消息")
  t.type_text("看这张")
  tap_send(t)
  let f = match send_flight.get() {
    Some(f) => f
    None => fail("nothing flies")
  }
  assert_eq(f.files.length(), 1)
  let ff = f.files[0]
  // (put up from here: its upload, as its message has it, file_key)
  assert_true(ff.key.has_prefix("upload:"))
  assert_true(ff.picture != "")
  // from its tile: 56 across
  assert_eq(ff.from.2, 56.0)
  // its row in the list (the outbox's, at once): the picture goes to where the message has it
  t.draw()
  t.draw()
  match @motion.measured_rect(t.ctx(), "flight/to/" + ff.key) {
    Some((_, _, w, _)) => assert_true(w > 56.0)
    None => fail("the message's picture is not where the flight can see it")
  }
  t.run_for(@sfbase.flight_most_ms)
  assert_true(send_flight.get() is None)
  fix_clock.val = None
}

///|
test "a chat linked to one Slack thread: 抄送 while writing opens it to tick, and closes once ticked (chat.cc)" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, tp) {
    if name != "chat" {
      return tp
    }
    match tp.value {
      Some(Object(o)) => {
        let o2 = o.copy()
        o2["cc"] = [{ "thread": 21, "place": "#still-fail", "via": "slack", "on": false }]
        { ..tp, value: Some(Json::object(o2)) }
      }
      _ => tp
    }
  })
  // (the capsule says nothing of it; opened to write, its row under the words has it)
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label=@sf.t("web-main.composer.ccLabel"))
  t.click(MenuItemCheckbox, label="#still-fail")
  let asked = named(calls, "chat.cc")
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].params, { "station": "ws1/st1", "thread": 7, "to": 21, "on": true })
  t.draw()
  // one: closed once ticked
  assert_true(t.find("#still-fail") is None, msg=t.words().map(fn(x) { x.0 }).join("|"))
}
