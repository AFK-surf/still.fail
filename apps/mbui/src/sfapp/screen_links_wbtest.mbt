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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
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
/// The name of the picture drawn as shapes (sf's draw_drawable: its key, size, scale and tint) whose name holds `part`.
fn shapes_named(t : @ui.Tester, part : String) -> String {
  for b in t.shape_boxes() {
    if b.0.contains(part) {
      return b.0
    }
  }
  ""
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
  t.run_for(@ui.nav_push_ms)
  // 共享调试 bare in a sentence: its title, a link; alone: its card
  assert_true(t.run_rects("共享调试").length() > 0)
  assert_eq(t.run_rects("https://still.fail/w/ws1/s/st1/adb").length(), 0)
  assert_true(t.find("未共享") is Some(_))
  // a link to anywhere else as it was
  assert_true(t.run_rects("https://example.com/login-v2").length() > 0)
  // the title in the sentence opens the link, the card too, as a tap on the link would
  t.tap_run("共享调试")
  assert_eq(t.opened(), ["https://still.fail/w/ws1/s/st1/adb"])
  t.tap_text("未共享")
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
test "共享调试's phone in the accent while this phone's adb is shared there, else muted" {
  let streams = []
  let cancelled = []
  let calls : Array[Made] = []
  let t = screen_links_core(streams, cancelled, calls)
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.nav_push_ms)
  // (the phone's muted: as the card's line, 未共享)
  let muted = inks_of(t, "未共享")[0]
  assert_true(shapes_named(t, "sf/icon/phone/24/").has_suffix("/\{muted}"))
  let t = screen_links_core(streams, cancelled, calls, over=fn(name, topic) {
    if name == "adbCard" {
      { ..topic, value: Some({ "title": "共享调试", "line": "共享中 · 剩余 58 分钟", "sharing": true, "lendable": true }) }
    } else {
      topic
    }
  })
  t.wheel(195.0, 400.0, 2000.0)
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("共享中 · 剩余 58 分钟") is Some(_))
  // (the phone's accent, sf's narrow palette: tokens.mbt)
  let accent = 0xCC5A34FFL
  assert_true(shapes_named(t, "sf/icon/phone/24/").has_suffix("/\{accent}"))
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
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("林 正在查看") is None)
  assert_eq(running(streams, cancelled).length(), 0)
  // back: a view of its own
  for _ in 0..<12 {
    if t.find("林 正在查看") is Some(_) {
      break
    }
    t.wheel(195.0, 400.0, 300.0)
  }
  t.run_for(@ui.nav_push_ms)
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
  t.run_for(@ui.nav_push_ms)
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  t.keep_parts(true)
  // frames with nothing from outside (the pointer moved about the chat): its row drawn again as it was
  t.move(100.0, 300.0)
  t.move(140.0, 300.0)
  t.move(180.0, 300.0)
  assert_true(t.rows_kept() > 0)
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
  t.run_for(@ui.nav_push_ms)
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  // the next waits out peek_ms from the first's (nav_push_ms of it gone already)
  (s.on_value)({ "frame": { "ts": 102 } }, Some(fixture_file_png("peek.png")))
  t.frame()
  assert_eq(acks().length(), 1)
  // the picture before still shown while the new one decodes
  assert_true(image_line(t, "mem:sf/peek/\{view}/0") != "")
  // (a tenth of peek_ms each side of the second's due)
  let near = peek_ms / 10.0
  t.run_for(peek_ms - @ui.nav_push_ms - near)
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
  t.run_for(@ui.nav_push_ms)
  assert_eq(running(streams, cancelled).length(), 0)
  t.app_state(true, true)
  t.run_for(@ui.nav_push_ms)
  assert_eq(running(streams, cancelled).length(), 1)
  assert_eq(streams.length(), 2)
  t.assert_idle()
}
