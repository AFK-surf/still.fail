// Links to a station's screens and its 共享调试 in an agent's words (screen_links.mbt, over chat_fixture.mbt's
// chat-screens): their cards alone in a paragraph, their titles bare in a sentence, a tap opening the link; a tab's
// preview asked for while its card is on the screen and the app shown, its frames acknowledged peek_ms apart.

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
) -> @ui.Tester {
  reset()
  let base = fixture("chat-screens")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
    stream: fn(_name, params, _bytes, on_value, _done) {
      streams.push({ params, on_value })
      streams.length()
    },
    cancel: fn(id) { cancelled.push(id) },
    topic: fn(name, params) { over(name, (base.topic)(name, params)) },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
      return line.to_string()
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
  // 共享调试 bare in a sentence: its title, a link; alone: its card
  assert_true(t.run_rects("共享调试").length() > 0)
  assert_eq(t.run_rects("https://still.fail/w/ws1/s/st1/adb").length(), 0)
  assert_true(t.find("允许 Studio 的 agent 调试此设备？") is Some(_))
  // a link to anywhere else as it was
  assert_true(t.run_rects("https://example.com/login-v2").length() > 0)
  // the title in the sentence opens the link, the card too, as a tap on the link would
  t.tap_run("共享调试")
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb"])
  guard adb_button_at(t, "详情") is Some((x, y)) else { fail("the card's 详情") }
  t.tap(x, y)
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb", "https://still.fail/w/ws1/s/st1/adb"])
  scroll_to_words(t, "Ana 正在查看")
  t.tap_text("Ana 正在查看")
  t.frame()
  // a screen's: its viewer here, nothing opened outside
  assert_eq(t.opened().length(), 2)
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
  assert_true(t.find("Studio :5173 · 在线") is Some(_))
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
  // (the phone's muted, as the card's line under it: ScreenLinks.kt's C.muted for both)
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
/// A button on 共享调试's card by its words, where it has one: its middle.
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
test "共享调试's card: lent from the chat where the phone has all it takes; else what it lacks first, its page a tap away" {
  let t = screen_links_core([], [], [])
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  // all it takes (the fixture's phone): the question, and 共享 lending to this station from here, the page not opened
  assert_true(t.find("一小时后自动停止") is Some(_))
  guard adb_button_at(t, "共享") is Some((x, y)) else { fail("the card's 共享") }
  t.tap(x, y)
  t.draw()
  let started = t.native_asked().filter(fn(a) { a.0 == "adb.start" })
  assert_eq(started.length(), 1)
  guard started[0].1 is Object(m) else { fail("adb.start's params") }
  assert_eq(m.get("station"), Some(Json::string("ws1/st1")))
  assert_eq(m.get("name"), Some(Json::string("Studio")))
  assert_eq(t.opened(), [])
  for c in t.native_calls() {
    t.answer_native(c.0, {})
  }
  t.draw()
  // Developer options off (said by the host as the app comes back): the card says so, no 共享; 查看步骤, the page
  t.post("native:adb.phone", adb_phone_of(developer=false).stringify())
  t.draw()
  assert_true(t.find("需要先打开开发者选项") is Some(_))
  assert_true(adb_button_at(t, "共享") is None)
  guard adb_button_at(t, "查看步骤") is Some((x, y)) else { fail("the card's 查看步骤") }
  t.tap(x, y)
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb"])
  // Wireless debugging off, which the app may turn on itself: 共享 again, turning it on as it lends
  t.post("native:adb.phone", adb_phone_of(can_switch=true).stringify())
  t.draw()
  guard adb_button_at(t, "共享") is Some((x, y)) else { fail("the card's 共享, the app turning Wireless debugging on") }
  t.tap(x, y)
  t.draw()
  let asked = t.native_asked().map(fn(a) { a.0 })
  assert_eq(asked.filter(fn(n) { n == "adb.switch" }).length(), 1)
  assert_eq(asked.filter(fn(n) { n == "adb.start" }).length(), 2)
}

///|
test "共享调试's card while it is lent there: how it stands, 停止共享 stopping it" {
  let calls : Array[Made] = []
  let t = screen_links_core([], [], calls, over=fn(name, topic) {
    if name == "adbCard" {
      { ..topic, value: Some({ "title": "共享调试", "line": "共享中 · 剩余 58 分钟", "sharing": true, "lendable": true }) }
    } else {
      topic
    }
  })
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("正在共享调试给 Studio") is Some(_))
  assert_true(t.find("共享中 · 剩余 58 分钟") is Some(_))
  guard adb_button_at(t, "停止共享") is Some((x, y)) else { fail("the card's 停止共享") }
  t.tap(x, y)
  t.draw()
  assert_eq(calls.filter(fn(m) { m.name == "adb.stop" }).length(), 1)
}

///|
test "共享调试's card on a device with no adb to lend: why, and nothing to press" {
  let t = screen_links_core([], [], [], over=fn(name, topic) {
    if name == "adbCard" {
      { ..topic, value: Some({ "title": "共享调试", "line": "仅安卓 app 支持共享调试", "sharing": false, "lendable": false }) }
    } else {
      topic
    }
  })
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("仅安卓 app 支持共享调试") is Some(_))
  assert_true(adb_button_at(t, "共享") is None)
  assert_true(adb_button_at(t, "详情") is None)
  t.tap_text("仅安卓 app 支持共享调试")
  t.draw()
  assert_eq(t.opened(), [])
  assert_eq(t.native_asked().length(), 0)
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
  t.move(195.0, 400.0)
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
  t.keep_parts(true)
  // frames with nothing from outside (the pointer moved about the chat): its row drawn again as it was
  t.move(100.0, 300.0)
  t.move(140.0, 300.0)
  t.move(180.0, 300.0)
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
