// Links to a station's screens and its 共享调试 in an agent's words (screen_links.mbt, over chat_fixture.mbt's
// chat-screens): their cards alone in a paragraph, their titles bare in a sentence, a tap opening the link; a tab's
// preview asked for while its card is on the screen and the app shown, its frames acknowledged peek_ms apart; an
// Android device's (H.264 alone) decoded in its card, two such at once.

///|
/// A streamed call the app made: its params, and what is told its values.
priv struct Streamed {
  params : Json
  on_value : (Json, Bytes?) -> Unit
}

///|
/// The fixture's chat-screens open, its streamed calls kept in `streams` (each one's id its place there, from 1), the
/// ones cancelled in `cancelled`, its calls in `calls`; `over` changes a topic's value.
fn screen_links_core(
  streams : Array[Streamed],
  cancelled : Array[Int],
  calls : Array[Made],
  over? : (String, Topic) -> Topic = fn(_, t) { t },
  h264? : Bool = false,
) -> @ui.Tester {
  new_run()
  let base = fixture("chat-screens")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
    stream: fn(_name, params, _bytes, on_value, _done) {
      streams.push({ params, on_value })
      streams.length()
    },
    cancel: fn(id) { cancelled.push(id) },
    topic_read: fn(name, params) { over(name, base.topic(name, params).get().snapshot()) },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, h264~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The streamed calls not cancelled.
fn running(streams : Array[Streamed], cancelled : Array[Int]) -> Array[Int] {
  let out = []
  for i in 1..=streams.length() {
    if !cancelled.contains(i) {
      out.push(i)
    }
  }
  out
}

///|
/// The colours the glyphs of the first words containing `words` are drawn in: those whose quads start in the words'
/// upper half (a line under them starts below it, however close).
fn inks_of(t : @ui.Tester, words : String) -> Array[Int64] {
  let (x, y, w, h) = t.rect_of(words).unwrap()
  let out = []
  for g in t.drawn_glyphs() {
    if g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 < y + h / 2.0 && !out.contains(g.2) {
      out.push(g.2)
    }
  }
  out
}

///|
/// The draw list's line of the image whose key holds `part`.
fn image_line(t : @ui.Tester, part : String) -> String {
  for line in t.drawlist().split("\n") {
    if line.contains(part) {
      return line.to_owned()
    }
  }
  ""
}

///|
test "a link alone in a paragraph is its card, a bare one in a sentence reads as its title, others stay links" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "Ana 正在查看")
  // the desktop's card: its title and line the core's, not the address
  assert_true(t.find("Ana 正在查看") is Some(_))
  assert_eq(t.run_rects("https://still.fail/w/ws1/s/st1/screen/desktop").length(), 0)
  // a tab's with the link's own words for its title
  scroll_to_words(t, "发布清单预览")
  assert_true(t.find("林 正在查看") is Some(_))
  assert_true(t.find("发布清单 - localhost") is None)
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  // 共享调试 bare in a sentence: its title, a link; alone: a link too, no card that asks anything (2026-11-11)
  assert_true(t.run_rects("共享调试").length() > 0)
  assert_eq(t.run_rects("https://still.fail/w/ws1/s/st1/adb").length(), 0)
  assert_true(t.find("允许 Willow 的 agent 调试此设备？") is None)
  // a link to anywhere else as it was
  assert_true(t.run_rects("https://example.com/login-v2").length() > 0)
  // the title in the sentence opens the link, as a tap on the link would
  t.tap_run("共享调试")
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb"])
  scroll_to_words(t, "Ana 正在查看")
  t.tap_text("Ana 正在查看")
  t.frame()
  // a screen's: its viewer here, nothing opened outside
  assert_eq(t.opened().length(), 1)
  guard app.nav.top() is Screen(at) else { fail("no viewer on top") }
  assert_eq(at.screen, "desktop")
}

///|
test "a link to the chat's web service alone in a paragraph is its card: its station and port, how it stands; a tap has the service over the chat" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "打开定价页")
  // (clear of the composer over the list's foot, where a tap is the composer's)
  middle_words(t, "打开定价页")
  // the link's own words its title, over the service's station with its port and how it stands, as the core says
  assert_true(t.find("Willow :5173 · 在线") is Some(_))
  assert_eq(t.run_rects("打开定价页").length(), 0, msg="a card, not a link in the words")
  t.tap_text("打开定价页")
  t.frame()
  t.frame()
  // (the service is this chat's: over it, nothing opened outside)
  assert_eq(t.opened().length(), 0)
  guard app.nav.top() is Service(station, job) else { fail("no service on top") }
  assert_eq((station, job), ("ws1/st1", "j-web"))
}

///|
test "a screen its station no longer has: its title muted; a live one's in the ink" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "此屏幕已不存在")
  let c = t.ctx()
  // (the phone's muted)
  assert_eq(inks_of(t, "浏览器标签页"), inks_of(t, "此屏幕已不存在"))
  assert_true(inks_of(t, "浏览器标签页") != [c.color(Fg)])
  scroll_to_words(t, "发布清单预览")
  assert_eq(inks_of(t, "发布清单预览"), [c.color(Fg)])
}

///|
/// The list scrolled until `words` are in the screen's middle half (found, they may lie under the bars at its ends).
fn middle_words(t : @ui.Tester, words : String) -> Unit {
  for _ in 0..<8 {
    guard t.rect_of(words) is Some((_, y, _, h)) else { return }
    let mid = y + h / 2.0
    if mid >= 211.0 && mid <= 633.0 {
      return
    }
    t.wheel(195.0, 400.0, mid - 422.0)
    t.run_for(@ui.move_most_ms)
  }
}

///|
/// The height of the preview above the title, including its fixed spacing to the preceding paragraph.
fn preview_gap(t : @ui.Tester) -> Double {
  let (_, y, _, h) = t.rect_of("预览在它的浏览器里").unwrap()
  let (_, below, _, _) = t.rect_of("发布清单预览").unwrap()
  below - y - h
}

///|
/// A button by its words, where one shows: its middle.
fn adb_button_at(t : @ui.Tester, label : String) -> (Double, Double)? {
  for s in t.semantics() {
    if s.role == @ui.Role::Button && s.label == label && !s.hidden {
      let (x, y, w, h) = s.rect
      return Some((x + w / 2.0, y + h / 2.0))
    }
  }
  None
}

///|
test "共享调试 alone in a paragraph: a link, nothing in the chat lending the phone to the station" {
  let t = screen_links_core([], [], [])
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("一小时后自动停止") is None)
  for label in ["共享", "停止共享", "查看步骤", "详情"] {
    assert_true(adb_button_at(t, label) is None, msg=label)
  }
  // (alone: its title, as one bare in a sentence)
  // (its paragraph's words, the link at their start)
  let alone = t.words().filter(fn(w) { w.0 == "共享调试" })
  guard alone.last() is Some(w) else { fail("the link alone: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  t.tap(w.1 + 8.0, w.2 + w.4 / 2.0)
  t.draw()
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb"], msg="\{Repr(alone)}")
  assert_eq(t.native_asked().filter(fn(a) { a.0 == "adb.start" }), [])
}

///|
test "a tab's preview: asked for while its card is on the screen, cancelled as it goes from view, asked again back" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "发布清单预览")
  let live = running(streams, cancelled)
  assert_eq(live.length(), 1)
  let p = streams[live[0] - 1].params
  assert_eq(text(Some(p), "station"), "ws1/st1")
  assert_eq(text(Some(p), "screen"), "browser:T1")
  assert_true(flag(Some(p), "peek"))
  assert_eq(number(Some(p), "maxWidth"), peek_size)
  assert_eq(number(Some(p), "maxHeight"), peek_size)
  assert_eq(field(Some(p), "codecs"), Some(["jpeg"]))
  let first_view = text(Some(p), "view")
  // scrolled up until its card is not built: cancelled
  t.move_to(195.0, 400.0)
  for _ in 0..<12 {
    if t.find("林 正在查看") is None {
      break
    }
    t.wheel(195.0, 400.0, -300.0)
  }
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("林 正在查看") is None)
  assert_eq(running(streams, cancelled).length(), 0)
  // back, its card on the screen (built is not enough: a row is built a little before it shows): a view of its own
  for _ in 0..<12 {
    match t.rect_of("林 正在查看") {
      Some((_, y, _, h)) if y >= 0.0 && y + h <= 844.0 => break
      _ => ()
    }
    t.wheel(195.0, 400.0, 150.0)
  }
  t.run_for(@ui.move_most_ms)
  let again = running(streams, cancelled)
  assert_eq(again.length(), 1)
  assert_true(text(Some(streams[again[0] - 1].params), "view") != first_view)
  t.run_for(t.rest_of("a list") - t.time())
  // (the chat's pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "a tall browser picture fills its preview from the top of the page" {
  let frame_w = @sf.peek_frame_px
  let frame_h = frame_w / 1.6
  let t = @ui.Tester::new(
    fn(c) {
      c.box(style=@ui.style(w=Fixed(frame_w), h=Fixed(frame_h), clip=true), fn() {
        @sfbase.peek_picture(c, "screen.png")
      })
      |> ignore
    },
    w=frame_w,
    h=frame_h,
    images=[("screen.png", 390, 760)],
  )
  t.draw()
  let drawn = t.drawn_images()
  assert_eq(drawn.length(), 1)
  let image = drawn[0]
  assert_true(
    image[0].abs() < 0.01 && image[1].abs() < 0.01 && (image[2] - frame_w).abs() < 0.01 &&
    (image[3] - frame_h).abs() < 0.01,
    msg="the picture fills the card without empty sides",
  )
  assert_true(image[5].abs() < 0.01 && image[7] < 1.0, msg="the card shows the top of the page")
}

///|
test "a browser's card keeps its size as the browser is opened and closed on a small screen" {
  let size = @signals.signal((1280.0, 800.0))
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls, over=fn(name, topic) {
    guard name == "screenCard" && topic.value is Some(Object(card)) && text(topic.value, "kind") == "browser" &&
      !flag(topic.value, "gone") else { topic }
    let next = card.copy()
    next["width"] = Json::number(size.get().0)
    next["height"] = Json::number(size.get().1)
    { ..topic, value: Some(Json::object(next)) }
  })
  scroll_to_words(t, "发布清单预览")
  middle_words(t, "发布清单预览")
  let gap = fn() { preview_gap(t) }
  let before = gap()
  let s = streams[running(streams, cancelled)[0] - 1]
  (s.on_value)({ "frame": { "ts": 101 } }, Some(fixture_file_png("peek.png")))
  t.frame()
  assert_eq(gap(), before, msg="the picture arriving does not change the card")
  // The browser is laid out for a small screen while its viewer is open. Its reported viewport changes in the
  // screen list, including while the chat is still visible; it goes back when the viewer closes.
  size.set((390.0, 760.0))
  t.frame()
  assert_eq(gap(), before, msg="the browser adapting to its viewer does not resize its card")
  // A new, portrait picture can arrive too; it replaces the old one inside the same card.
  let view = text(Some(s.params), "view")
  (s.on_value)({ "frame": { "ts": 102 } }, Some(fixture_file_png("after.png")))
  t.run_for(@ui.move_most_ms)
  assert_true(image_line(t, "mem:sf/peek/\{view}/1") != "")
  assert_eq(gap(), before, msg="a picture in the new shape does not resize the card")
  t.tap_text("发布清单预览")
  t.frame()
  assert_true(app.nav.top() is Screen(_))
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(gap(), before, msg="the card has the same size on returning to the chat")
  size.set((1280.0, 800.0))
  t.frame()
  assert_eq(gap(), before, msg="the browser returning to its former size does not resize its card")
  size.set((0.0, 0.0))
  t.frame()
  assert_eq(gap(), before, msg="the screen's size not yet known does not resize its card")
}

///|
test "a simulator's preview follows the simulated screen when it turns" {
  let size = @signals.signal((390.0, 844.0))
  let t = screen_links_core([], [], [], over=fn(name, topic) {
    guard name == "screenCard" && topic.value is Some(Object(card)) && text(topic.value, "kind") == "browser" &&
      !flag(topic.value, "gone") else { topic }
    let next = card.copy()
    next["kind"] = Json::string("simulator")
    next["width"] = Json::number(size.get().0)
    next["height"] = Json::number(size.get().1)
    { ..topic, value: Some(Json::object(next)) }
  })
  scroll_to_words(t, "发布清单预览")
  middle_words(t, "发布清单预览")
  let before = preview_gap(t)
  size.set((844.0, 390.0))
  t.frame()
  assert_true(preview_gap(t) < before, msg="the landscape simulator has a shorter preview")
}

///|
test "a preview goes on while its card's row is drawn again, not built: asked for once, its picture kept" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "发布清单预览")
  let s = streams[running(streams, cancelled)[0] - 1]
  let view = text(Some(s.params), "view")
  // (its frame told here, not by a host: built whole, as a host's answer builds what is kept)
  (s.on_value)({ "frame": { "ts": 101 } }, Some(fixture_file_png("peek.png")))
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  t.set_rows_on_pixels(true)
  // frames with nothing from outside (the pointer moved about the chat): its row drawn again as it was
  t.move_to(100.0, 300.0)
  t.move_to(140.0, 300.0)
  t.move_to(180.0, 300.0)
  t.run_for(peek_ms)
  assert_eq(streams.length(), 1)
  assert_eq(running(streams, cancelled).length(), 1)
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
}

///|
test "a preview's frames: each acknowledged peek_ms after the one before, the picture before shown until the next is decoded" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "发布清单预览")
  let s = streams[running(streams, cancelled)[0] - 1]
  let view = text(Some(s.params), "view")
  let acks = fn() { named(calls, "screen.ack") }
  // the first at once
  (s.on_value)({ "frame": { "ts": 101 } }, Some(fixture_file_png("peek.png")))
  t.frame()
  assert_eq(acks().length(), 1)
  assert_eq(text(Some(acks()[0].params), "view"), view)
  assert_eq(number(Some(acks()[0].params), "ts"), 101.0)
  // (half of peek_ms on: the page still coming in, the first drawn on it)
  let shown = peek_ms / 2.0
  t.run_for(shown)
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  // the next waits out peek_ms from the first's (`shown` of it gone already)
  (s.on_value)({ "frame": { "ts": 102 } }, Some(fixture_file_png("peek.png")))
  t.frame()
  assert_eq(acks().length(), 1)
  // the picture before still shown while the new one decodes
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  // (a tenth of peek_ms each side of the second's due)
  let near = peek_ms / 10.0
  t.run_for(peek_ms - shown - near)
  assert_eq(acks().length(), 1)
  assert_true(image_line(t, "mem:sf/peek/\{view}/1") != "")
  assert_eq(image_line(t, "mem:sf/peek/\{view}/0"), "")
  t.run_for(near * 2.0)
  assert_eq(acks().length(), 2)
  assert_eq(number(Some(acks()[1].params), "ts"), 102.0)
  t.run_for(peek_ms)
  t.assert_idle()
}

///|
test "a preview stops as the app goes behind, and is asked for again as it comes back" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  scroll_to_words(t, "发布清单预览")
  assert_eq(running(streams, cancelled).length(), 1)
  t.app_state(false, false)
  assert_eq(running(streams, cancelled).length(), 0)
  t.run_for(@ui.move_most_ms)
  assert_eq(running(streams, cancelled).length(), 0)
  t.app_state(true, true)
  t.run_for(@ui.move_most_ms)
  assert_eq(running(streams, cancelled).length(), 1)
  assert_eq(streams.length(), 2)
  t.assert_idle()
}

///|
/// The card's preview as the app keeps it (one card in the fixture's chat has one).
fn only_peek() -> @sfbase.Peek raise {
  let all = @sfbase.peeks.values().to_array()
  assert_eq(all.length(), 1)
  all[0]
}

///|
test "an Android device's preview: H.264 where the host decodes it, drawn from the card's decoder, each frame acknowledged once shown" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls, h264=true)
  scroll_to_words(t, "发布清单预览")
  let s = streams[running(streams, cancelled)[0] - 1]
  assert_eq(field(Some(s.params), "codecs"), Some(["jpeg", "h264"]))
  let view = text(Some(s.params), "view")
  let acks = fn() { named(calls, "screen.ack") }
  (s.on_value)({ "config": { "codec": "h264", "width": 320, "height": 640 } }, Some(b"\x01\x42\x00\x1f"))
  (s.on_value)({ "frame": { "ts": 101, "key": true } }, Some(b"\x00\x00\x00\x01\x65"))
  t.frame()
  let st = only_peek().stream.unwrap()
  assert_eq(@sfbase.video_peeks.val, 1)
  // not acknowledged until its decoder says what became of it
  assert_eq(acks().length(), 0)
  t.stream_shows(st.id(), 101.0, 320, 640)
  t.frame()
  assert_eq(acks().length(), 1)
  assert_eq(text(Some(acks()[0].params), "view"), view)
  assert_eq(number(Some(acks()[0].params), "ts"), 101.0)
  assert_true(t.drawlist().contains("stream 320x640"), msg="its picture drawn in the card")
  // the next acknowledged as it is shown, nothing else built in between (the station paces it)
  (s.on_value)({ "frame": { "ts": 102, "key": false } }, Some(b"\x00\x00\x00\x01\x41"))
  t.frame()
  t.stream_shows(st.id(), 102.0, 320, 640)
  t.frame()
  assert_eq(acks().length(), 2)
  assert_eq(number(Some(acks()[1].params), "ts"), 102.0)
  // gone from view: its decoder stopped, its place given back
  t.app_state(false, false)
  assert_eq(running(streams, cancelled).length(), 0)
  assert_eq(@sfbase.video_peeks.val, 0)
}

///|
test "an Android device's preview past the app's two videos: let go, its mark shown, asked again peek_again_ms on" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls, h264=true)
  scroll_to_words(t, "发布清单预览")
  // (two previews decoded elsewhere)
  @sfbase.video_peeks.val = @sfbase.video_peeks_most
  let s = streams[running(streams, cancelled)[0] - 1]
  (s.on_value)({ "config": { "codec": "h264", "width": 320, "height": 640 } }, Some(b"\x01\x42\x00\x1f"))
  t.frame()
  assert_eq(running(streams, cancelled).length(), 0)
  assert_true(only_peek().stream is None)
  assert_eq(@sfbase.video_peeks.val, @sfbase.video_peeks_most)
  // one of them gone; a while on, this one asks again
  @sfbase.video_peeks.val = 1
  t.run_for(@sfbase.peek_again_ms / 2.0)
  assert_eq(streams.length(), 1)
  t.run_for(@sfbase.peek_again_ms / 2.0 + @ui.move_most_ms)
  assert_eq(streams.length(), 2)
  assert_eq(running(streams, cancelled).length(), 1)
  @sfbase.video_peeks.val = 0
}
