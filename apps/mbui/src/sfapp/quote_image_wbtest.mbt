// An image of a message held in the chat (its menu's 引用, sfpages menus.mbt; MessagePick.kt quoteFile): quoted into the draft,
// its file going again with the message; a quote's own file in its card, not among the files (Chat.kt QuoteCards,
// besideQuotes; Composer.kt DraftExtras).

///|
/// The chat open at its end (on `platform`'s screen: Android's, a finger), then a row up at a time until the image
/// `name` is drawn; where it is.
fn image_in_chat(name : String, platform? : Int = 2, w? : Double = 390.0) -> (@ui.Tester, Double, Double) {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~)
  nav_rested(t)
  let mut tries = 0
  while t.locate("img:" + name).length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:" + name)
  assert_true(at.length() > 0) catch { _ => () }
  let (x, y) = at[0]
  (t, x, y)
}

///|
/// The image at (`x`, `y`) held: its menu (a sheet, a finger's) up, 引用 tapped; its quote taken into the draft.
fn hold_quote(t : @ui.Tester, x : Double, y : Double) -> Unit {
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms + 20.0)
  t.release(x, y)
  t.draw()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("引用")
  t.frame()
  t.frame()
}

///|
fn chat_draft() -> @sfbase.Writing {
  @sfbase.writings.get(draft_key(chat_ref("ws1/st1", "s-c1"))).unwrap()
}

///|
/// Instances drawing `source`, in order with their position in the whole draw list.
fn picture_instances(t : @ui.Tester, source : String) -> Array[(Int, Array[Double])] raise {
  let named = t.drawlist_images().filter(fn(x) { x.1 == source })
  assert_true(named.length() > 0, msg="\{source} is not drawn")
  let insts = t.drawn_instances()
  let ids : Array[Int] = []
  for a in insts {
    if a[5] == 4.0 && !ids.contains(a[20].to_int()) {
      ids.push(a[20].to_int())
    }
  }
  let wanted = named.map(fn(x) { ids[x.0] })
  insts.mapi(fn(i, a) { (i, a) }).filter(fn(p) { p.1[5] == 4.0 && wanted.contains(p.1[20].to_int()) })
}

///|
test "a person's image held: quoted (whose, the file named), its file once in the draft as the station has it, felt; not opened" {
  let (t, x, y) = image_in_chat("插画参考.png")
  hold_quote(t, x, y)
  assert_true(viewer.get() is None)
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  // into the chat's draft as the core keeps it (sfpages' composer took it: quote_file_into)
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  let q = Some(d.quotes[0])
  assert_eq(text(q, "author"), "Ana")
  assert_eq(text(q, "role"), "person")
  assert_eq(text(field(q, "own"), "name"), "插画参考.png")
  assert_eq(d.files.length(), 0)
  // held again: another quote
  hold_quote(t, x, y)
  assert_eq(chat_draft().quotes.length(), 2)
}

///|
test "an image quoted: its picture in its card in the composer; sent, it grows from there to its place in the message, never there at once" {
  let (t, x, y) = image_in_chat("插画参考.png")
  hold_quote(t, x, y)
  t.run_for(@ui.move_most_ms)
  t.draw()
  // its tile in its card (as a picture waiting is: 56 square)
  let tile = match t.drawn_images().iter().find_first(fn(i) { (i[2] - 56.0).abs() < 0.5 && (i[3] - 56.0).abs() < 0.5 }) {
    Some(i) => i
    None => fail("no picture in the quote's card: \{t.drawn_images()}")
  }
  tap_send(t)
  // as it sets out: where its tile was
  assert_true(
    t.drawn_images().iter().any(fn(i) { (i[0] - tile[0]).abs() < 0.5 && (i[1] - tile[1]).abs() < 0.5 && (i[2] - 56.0).abs() < 0.5 }),
    msg="\{t.drawn_images()}",
  )
  // on its way: between its tile's size and its own, drawn at no size it has at rest
  t.run_for(@sfbase.flight_len(true) * 0.4)
  let mid = t.drawn_images().map(fn(i) { i[2] })
  t.run_for(@sfbase.flight_len(true) + @sf.hint_back_ms)
  assert_true(send_flight.get() is None)
  let rest = t.drawn_images().map(fn(i) { i[2] })
  let between = mid.filter(fn(w) { w > 56.5 && rest.iter().all(fn(r) { (r - w).abs() > 0.5 }) })
  assert_true(between.length() > 0, msg="drawn \{mid} on its way, at rest \{rest}")
}

///|
test "a quoted image sent while reading above the end does not jump the chat to its newest message" {
  let (t, x, y) = image_in_chat("compare.png")
  hold_quote(t, x, y)
  t.run_for(@ui.move_most_ms)
  assert_false(t.at_end(), msg="the quoted image must be above the chat's end")
  let before = t.visible()
  tap_send(t)
  let first = t.visible()
  assert_eq(first.0, before.0, msg="the chat jumped from \{before} to \{first} on sending")
  assert_false(t.at_end(), msg="the chat jumped to its end on sending")
  t.run_for(@sfbase.flight_wait_ms + @sfbase.flight_most_ms)
  assert_true(t.at_end(), msg="the chat did not reach its newest message")
}

///|
test "a quoted picture remains visible over its card as they fly to the message" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let file : Json = {
    "name": "quoted-order.png", "path": "/w/uploads/quoted-order.png", "size": 120,
    "width": 1200, "height": 800, "owner": "s-c1",
  }
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "quoted-order.png", "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  tap_send(t)
  t.run_for(@sfbase.flight_len(true) * 0.4)
  let insts = t.drawn_instances()
  let moving = picture_instances(t, "mem:fixture/quoted-order.png").filter(fn(p) {
    let a = p.1
    a[2] > 56.5 && a[11] > 0.9
  })
  assert_eq(moving.length(), 1, msg="the quoted picture on its way: \{moving}")
  let (index, picture) = moving[0]
  let (x, y) = (picture[0] + picture[2] / 2.0, picture[1] + picture[3] / 2.0)
  assert_true(corner_cover(picture, x, y, 2.0) > 0.9, msg="the picture is clipped away")
  let over = insts.mapi(fn(i, a) { (i, a) }).filter(fn(p) {
    let a = p.1
    p.0 > index && (a[5] == 0.0 || a[5] == 4.0) && a[11] > 0.9 && corner_cover(a, x, y, 2.0) > 0.9
  })
  assert_eq(over.length(), 0, msg="the picture is covered on its way: \{over}")
}

///|
fn local_quote_visible(name : String) -> Unit raise {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    // The original message draws the picture it already has; a station thumbnail is not available yet.
    file: fn(station, owner, file) {
      if file == name { "" } else { (base.file)(station, owner, file) }
    },
    poster: fn(station, owner, file) {
      if file == name { "" } else { (base.poster)(station, owner, file) }
    },
    // Keep the message on screen while its station does not answer.
    call: fn(name, params, done) {
      if name != "chat.send" { (base.call)(name, params, done) }
    },
  }
  let station = "ws1/st1"
  let path = "/w/uploads/" + name
  let picture = "mem:test/quoted-local"
  open_chat({ station, session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  @ui.add_image(picture, png_head())
  @sfbase.sent_pictures[@sfbase.sent_key(station, path)] = picture
  let file = attachment_of({
    "name": Json::string(name), "path": path, "size": 120, "width": 1600, "height": 900,
    "owner": "s-c1", "upload": "original-upload",
  })
  let w = @sfbase.writing(src, station + ":s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": Json::string(name), "ts": "ts8" }, file=@sfbase.attachment_json(file, "s-c1"))
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  assert_true(t.drawlist().contains(picture), msg="the quoted picture is missing from the composer")
  tap_send(t)
  let sent = t.time()
  while t.time() < sent + @sfbase.flight_most_ms {
    assert_true(t.drawlist().contains(picture), msg="the quoted picture disappeared at \{t.time()}")
    t.frame()
  }
  assert_true(t.drawlist().contains(picture), msg="the quoted picture is missing from the message")
}

///|
test "a local picture stays visible throughout sending its quote without the station" {
  local_quote_visible("quoted-local.png")
}

///|
test "a local video cover stays visible throughout sending its quote without the station" {
  local_quote_visible("quoted-local.mp4")
}

///|
/// A picture counts as visible only where nothing painted later covers its centre.
fn quote_picture_visible(t : @ui.Tester, source : String) -> Bool {
  let instances = t.drawn_instances()
  instances.mapi(fn(i, a) { (i, a) }).iter().any(fn(p) {
    let (index, a) = p
    if a[5] != 4.0 || t.image_src(a[20].to_int()) != source || a[11] < 0.99 { return false }
    let (x, y) = (a[0] + a[2] / 2.0, a[1] + a[3] / 2.0)
    if corner_cover(a, x, y, 2.0) < 0.99 { return false }
    !instances.mapi(fn(i, v) { (i, v) }).iter().any(fn(p) {
      let (i, v) = p
      i > index && (v[5] == 0.0 || v[5] == 4.0) && v[11] > 0.01 && corner_cover(v, x, y, 2.0) > 0.99
    })
  })
}

///|
fn local_quote_uncovered(name : String) -> Unit raise {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    file: fn(station, owner, file) {
      if file == name { "" } else { (base.file)(station, owner, file) }
    },
    poster: fn(station, owner, file) {
      if file == name { "" } else { (base.poster)(station, owner, file) }
    },
  }
  let station = "ws1/st1"
  let path = "/w/uploads/" + name
  let picture = "mem:test/uncovered-quote"
  open_chat({ station, session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  @ui.add_image(picture, png_head())
  @sfbase.sent_pictures[@sfbase.sent_key(station, path)] = picture
  @sffixture.fix_put_up[path] = "original-upload"
  let file : Json = {
    "name": Json::string(name), "path": path, "size": 120, "width": 1600, "height": 900, "owner": "s-c1",
  }
  let w = @sfbase.writing(src, station + ":s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": Json::string(name), "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  assert_true(quote_picture_visible(t, picture), msg="the picture in the composer is covered")
  tap_send(t)
  let sent = t.time()
  while send_flight.get() is Some(_) {
    assert_true(quote_picture_visible(t, picture), msg="the picture is hidden at \{t.time() - sent} ms")
    t.frame()
  }
  assert_true(quote_picture_visible(t, picture), msg="the picture in the message is covered")
}

///|
test "a quoted local picture is never covered as its card flies to the message" {
  local_quote_uncovered("uncovered.png")
}

///|
test "a quoted local video cover is never covered as its card flies to the message" {
  local_quote_uncovered("uncovered.mp4")
}

///|
fn quoted_media_handoff(name : String) -> Unit raise {
  let has = Ref(false)
  let made : Ref[Source?] = Ref(None)
  let calls : Array[Made] = []
  let path = "/w/uploads/" + name
  let file : Json = {
    "name": Json::string(name), "path": path, "size": 120, "width": 1600, "height": 900,
    "owner": "s-c1",
  }
  let t = fake_core(calls, made~, over=fn(topic, tp) {
    match (topic, tp.value) {
      ("chat", Some(Object(m))) if has.val => {
        let v = m.copy()
        v["outbox"] = [{
          "id": "out-1", "text": "", "createdAt": 0, "state": "sending",
          "attachments": [{
            "name": Json::string(name), "path": path, "size": 120, "width": 1600, "height": 900,
            "owner": "s-c1", "upload": "original-upload",
          }],
          "quotes": [{ "author": "Ana", "text": Json::string(name), "ts": "ts8", "comment": "", "file": Json::string(name) }],
        }]
        { ..tp, value: Some(Json::object(v)), version: tp.version + 1 }
      }
      _ => tp
    }
  })
  let src = made.val.unwrap()
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": Json::string(name), "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  tap_send(t)
  has.val = true
  t.frame()
  t.run_for(@sfbase.flight_len(true) * 0.4)
  let images = picture_instances(t, "mem:fixture/" + name).map(fn(p) { p.1 }).filter(fn(a) { a[11] > 0.9 })
  assert_eq(images.length(), 1, msg="the picture as the core's row takes over: \{images}")
  assert_true(images[0][2] > 56.5 && images[0][2] < 300.0, msg="the picture jumped rather than flying: \{images}")
}

///|
test "a quoted picture keeps its identity when the core's row takes over during its flight" {
  quoted_media_handoff("quoted-upload.png")
}

///|
test "a quoted video cover keeps its identity when the core's row takes over during its flight" {
  quoted_media_handoff("quoted-upload.mp4")
}

///|
test "a quoted video cover that arrives during the flight is shown on that same flight" {
  new_run()
  let base = fixture("chat")
  let available = @signals.signal(false)
  let name = "late-quote.mp4"
  let src : Source = {
    ..base,
    poster: fn(station, owner, file) {
      if file == name && !available.get() { "" } else { (base.poster)(station, owner, file) }
    },
  }
  let station = "ws1/st1"
  open_chat({ station, session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  let file : Json = {
    "name": Json::string(name), "path": "/w/uploads/late-quote.mp4", "size": 120,
    "width": 1600, "height": 900, "owner": "s-c1",
  }
  let w = @sfbase.writing(src, station + ":s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "late-quote.mp4", "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms)
  tap_send(t)
  let pictures = send_flight.get().unwrap().files.filter(fn(f) { f.key == @sfbase.quote_picture_key(0) })
  assert_eq(pictures.length(), 1, msg="the waiting cover has no flight")
  assert_eq(pictures[0].picture, Some(""))
  // Deliver the cover between host frames, without a test step rebuilding the whole page at that moment.
  let arrival = t.time() + @sfbase.flight_len(true) * 0.2
  let given = Ref(false)
  t.set_frame_period(t.period)
  t.between_frames(fn() {
    if !given.val && t.time() >= arrival {
      given.val = true
      available.set(true)
    }
  })
  t.run_for(@sfbase.flight_len(true) * 0.2 + @ui.image_fade_ms + 20.0)
  t.between_frames(fn() {  })
  assert_true(given.val, msg="the cover did not arrive")
  assert_true(send_flight.get() is Some(_), msg="the flight ended before the cover arrived")
  let shown = picture_instances(t, "mem:fixture/" + name).filter(fn(p) { p.1[11] > 0.9 })
  assert_eq(shown.length(), 1, msg="the cover was not drawn on its flight: \{shown}")
  assert_true(shown[0].1[2] > 56.5, msg="the cover remained at its starting tile: \{shown}")
}

///|
test "the same picture quoted twice flies to each quote's own place" {
  let calls : Array[Made] = []
  let made : Ref[Source?] = Ref(None)
  let t = fake_core(calls, made~)
  let src = made.val.unwrap()
  let file : Json = {
    "name": "twice.png", "path": "/w/uploads/twice.png", "size": 120,
    "width": 1200, "height": 800, "owner": "s-c1",
  }
  let w = @sfbase.writing(src, "ws1/st1:s-c1")
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "第一处", "ts": "ts8" }, file~)
  @sfbase.writing_quote(src, w, { "author": "Ana", "text": "第二处", "ts": "ts8" }, file~)
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  tap_send(t)
  t.draw()
  t.draw()
  let pictures = send_flight.get().unwrap().files.filter(fn(f) { f.picture == Some("mem:fixture/twice.png") })
  assert_eq(pictures.length(), 2)
  let first = @motion.measured_rect(t.ctx(), "flight/to/" + pictures[0].key).unwrap()
  let second = @motion.measured_rect(t.ctx(), "flight/to/" + pictures[1].key).unwrap()
  assert_true((first.1 - second.1).abs() > 0.5, msg="both pictures fly to the same place: \{first}, \{second}")
}

///|
test "a video quoted: its still in its card in the composer; sent, it grows from there to its box in the message, never there at once" {
  // what was seen: its box in the message drawn whole as it set out from the composer, its card's ground still growing
  // round it on its way up
  new_run()
  let src : Source = { ..fixture("chat-download"), poster: fn(_, _, name) { fixture_file(name) } }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.reachable("演示录屏.mp4")[0]
  t.right_click(x, y)
  t.draw()
  t.tap_text("引用")
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  t.draw()
  // its still in its card (as a picture waiting is: 56 square)
  let tile = match t.drawn_images().iter().find_first(fn(i) { (i[2] - 56.0).abs() < 0.5 && (i[3] - 56.0).abs() < 0.5 }) {
    Some(i) => i
    None => fail("no still in the quote's card: \{t.drawn_images()}")
  }
  tap_send(t)
  // as it sets out: where its tile was
  assert_true(
    t.drawn_images().iter().any(fn(i) { (i[0] - tile[0]).abs() < 0.5 && (i[1] - tile[1]).abs() < 0.5 && (i[2] - 56.0).abs() < 0.5 }),
    msg="\{t.drawn_images()}",
  )
  // on its way: between its tile's size and its box's, drawn at no size it has at rest
  t.run_for(@sfbase.flight_len(true) * 0.4)
  let mid = t.drawn_images().map(fn(i) { i[2] })
  t.run_for(@sfbase.flight_len(true) + @sf.hint_back_ms)
  assert_true(send_flight.get() is None)
  let rest = t.drawn_images().map(fn(i) { i[2] })
  let between = mid.filter(fn(w) { w > 56.5 && rest.iter().all(fn(r) { (r - w).abs() > 0.5 }) })
  assert_true(between.length() > 0, msg="drawn \{mid} on its way, at rest \{rest}")
}

///|
test "an agent's video and file card right clicked: 引用 quotes each, its file named, nothing played or opened" {
  new_run()
  let src = fixture("chat-download")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_fixture_mode("chat-download")
  t.run_for(@ui.move_most_ms)
  // (the video in its middle, nothing over it naming it; the card on its name)
  let (x, y) = t.reachable("演示录屏.mp4")[0]
  let card = t.words().filter(fn(w) { w.0.has_prefix("发布包") })
  assert_true(card.length() > 0)
  for at in [(x, y), (card[0].1 + 4.0, card[0].2 + 4.0)] {
    t.right_click(at.0, at.1)
    t.draw()
    t.tap_text("引用")
    t.frame()
    t.frame()
  }
  assert_true(viewer.get() is None)
  let d = chat_draft()
  assert_eq(d.quotes.map(fn(q) { text(field(Some(q), "own"), "name") }), ["演示录屏.mp4", "发布包.zip"])
  assert_eq(text(Some(d.quotes[0]), "role"), "agent")
  assert_eq(d.files.length(), 0)
}

///|
test "an agent's image held: quoted, not a passage of its words picked; whose it is the agent's" {
  let (t, x, y) = image_in_chat("compare.png")
  hold_quote(t, x, y)
  assert_eq(pk.ts, "")
  let d = chat_draft()
  assert_eq(d.quotes.length(), 1)
  assert_eq(text(Some(d.quotes[0]), "role"), "agent")
  assert_eq(text(field(Some(d.quotes[0]), "own"), "name"), "compare.png")
}

///|
test "an image right clicked: its one menu, again on that menu still the one; in the preview over the chat, the picture's own, never the chat's 引用" {
  // (macOS: a mouse; Large, menus beside what opened them, the chat its own column: docs/architecture.md, rule 3)
  let (t, x, y) = image_in_chat("compare.png", platform=0, w=1280.0)
  // (引用 a press reaches: a menu's, not what lies under what is over it)
  let quotes = fn() { t.reachable("引用").length() }
  let before = quotes()
  t.right_click(x, y)
  assert_eq(quotes(), before + 1)
  let menu = @sf.last_presented()
  // on the menu, which opened over the image: the menu's, no second menu of the image's over it
  t.right_click(x + 10.0, y + 10.0)
  t.draw()
  assert_eq(@sf.last_presented(), menu)
  assert_true(@sf.presented_open_of(menu))
  assert_eq(quotes(), before + 1)
  // closed, and the image opened over the whole window
  t.key(@ui.key_escape)
  t.draw()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_))
  // where the chat's image is under it: never that image's menu (its 引用 into the draft the preview covers)
  t.right_click(x, y)
  assert_eq(quotes(), 0)
  // (the picture's own, if it was on the picture there, closed)
  if @sf.presenting() {
    t.key(@ui.key_escape)
    t.draw()
  }
  assert_true(viewer.get() is Some(_))
  // on its picture, in the middle: its own menu, 复制图片 (as its bar's 复制)
  t.right_click(640.0, 422.0)
  assert_true(t.reachable("复制图片").length() > 0)
  assert_eq(quotes(), 0)
}
