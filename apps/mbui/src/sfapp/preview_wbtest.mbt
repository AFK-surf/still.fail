///|
/// The made-up source the last preview_tester opened its file from (another made, its file opened again).
// kept across runs: set by each preview_tester before it is read
let preview_src : Ref[Source?] = Ref(None)

///|
/// Long past any wait the viewer's bars ever had: left alone this long they are still there (only a tap hides them).
let left_alone_ms : Double = 10000.0

///|
/// The made-up chat with one of its made-up files open in the preview (preview_fixture.mbt), the window `w` wide, on
/// `platform`'s screen; `finish` false, its pictures decoded only as the test says (Tester::finish).
fn preview_tester(what : String, w? : Double = 390.0, platform? : Int = 0, finish? : Bool = true) -> @ui.Tester {
  new_run()
  let src = fixture("chat-preview-" + what)
  preview_src.val = Some(src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=844.0, platform~, finish~)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  // seen once it is in (grown from its thumbnail, or faded in)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "kinds by name, as the Android app's kindOf" {
  assert_true(preview_kind("a.PNG").0 == Some(KImage))
  assert_true(preview_kind("录屏.mov").0 == Some(KVideo))
  assert_true(preview_kind("x.pdf").0 == Some(KPdf))
  assert_true(preview_kind("Makefile").0 == Some(KCode))
  assert_eq(preview_kind("app.mts").2, "ts")
  assert_true(preview_kind("build.log").0 == Some(KText))
  assert_true(preview_kind("备份.bin").0 is None)
  assert_true(@codec.looks_like_text(@utf8.encode("纯文本 plain")))
  assert_true(!@codec.looks_like_text(b"\x00\x01\x02"))
}

///|
test "an image opens fitted, its bar over it; a double tap zooms in, another back" {
  let t = preview_tester("image")
  assert_true(t.find("界面草图.png") is Some(_))
  assert_true(t.find("100%") is None)
  let v = viewer.get().unwrap()
  // a picture read whole, held in memory only (FilePreview.kt: FileData.fetch), not kept on the device
  assert_true(fix_fetches.iter().all(fn(f) { !flag(Some(f.1), "keep") }))
  // 600 × 400 in 390 × 844 with 12 round it: (390 - 24) / 600
  assert_true((shown_scale(t, v.zoom) - 366.0 / 600.0).abs() < 0.001)
  t.tap(195.0, 422.0)
  t.advance(double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  // (its glide: @ui.move_most_ms from the tap)
  t.run_for(@ui.move_most_ms)
  assert_true((shown_scale(t, v.zoom) - 1.525).abs() < 0.01)
  // (the next two taps a double tap of their own)
  t.run_for(double_tap_ms)
  t.tap(195.0, 422.0)
  t.advance(double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  // (its glide: @ui.move_most_ms from the tap)
  t.run_for(@ui.move_most_ms)
  assert_true((shown_scale(t, v.zoom) - 366.0 / 600.0).abs() < 0.001)
  // back closes it at once (only drawn going, back into its thumbnail or fading out), the chat under it again
  t.back()
  assert_true(viewer.get() is None)
  // to where its way out said it ends (@ui.move_most_ms or pv_fade_ms from when it set out)
  t.run_for(if v.flies { @ui.move_most_ms } else { pv_fade_ms })
  assert_true(t.find("界面草图.png") is None)
  t.assert_idle()
}

///|
test "the picture held by a finger, Small or Medium: its one menu, 保存到相册 (a phone pastes nowhere), not one more for each time the frame it opens in is built" {
  for w in [390.0, 720.0] {
    let t = preview_tester("image", w~, platform=2)
    assert_true(viewer.get() is Some(_), msg="\{w} wide")
    let before = @sf.last_presented()
    t.press_at(w / 2.0, 422.0)
    t.run_for(@ui.long_press_ms + 20.0)
    t.release(w / 2.0, 422.0)
    t.draw()
    t.run_for(@kit.sheet_rest("sf-present") - t.time())
    // (its sheet measures what it holds as it first comes, the frame built again then: that build sees no hold)
    assert_eq(@sf.last_presented() - before, 1, msg="\{w} wide")
    assert_true(t.reachable("保存到相册").length() > 0, msg="\{w} wide")
    assert_true(t.reachable("复制图片").length() == 0, msg="\{w} wide")
  }
}

///|
test "held by a finger round the picture, over the chat's words under the viewer: none of them picked" {
  let t = preview_tester("image", platform=2)
  assert_true(viewer.get() is Some(_))
  for y in [120.0, 200.0, 660.0, 740.0] {
    for x in [60.0, 195.0, 330.0] {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms + 20.0)
      t.release(x, y)
      t.draw()
      assert_eq(pk.ts, "", msg="\{x}, \{y}")
    }
  }
}

///|
test "a video plays in the one player (@sf.player_view), its bytes read through the core; its controls over it" {
  let t = preview_tester("video")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("open 1 1 ") }))
  assert_true(t.views().contains("control 1 1 0"))
  // 1280 × 720 edge to edge on the black, in the middle
  let holes = t.holes()
  assert_eq(holes.length(), 1)
  let (x, y, w, h) = holes[0]
  assert_eq(x, 0.0)
  assert_true((w - 390.0).abs() < 0.5 && (h - 390.0 * 720.0 / 1280.0).abs() < 0.5)
  assert_true((y + h / 2.0 - 422.0).abs() < 1.0)
  // its frames' times asked of the host and counted, once it says them (three frames a 30th of a second apart)
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("control 1 20 ") }))
  assert_true(t.view_said("{\"view\":{\"view\":1,\"what\":1,\"text\":\"0,33.333,66.667\"}}"))
  t.draw()
  assert_true(t.find(" / 3 帧") is Some(_))
  let v = viewer.get().unwrap()
  t.back()
  assert_true(viewer.get() is None)
  // faded out (pv_fade_ms from when it set out), its view closed
  t.run_for(pv_fade_ms)
  assert_true(t.views().contains("close 1"))
}

///|
test "a video in the chat: the station's still of it (its poster) on the black, the play mark and its name over it" {
  new_run()
  let asked : Array[String] = []
  let src : Source = {
    ..fixture("chat"),
    poster: fn(station, key, name) {
      asked.push(station + " " + key + " " + name)
      fixture_file(name)
    },
  }
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = @ui.Tester::new(fn(c) { chat_file(c, src, a) }, w=390.0, h=844.0)
  t.draw()
  t.run_for(@ui.image_fade_ms)
  assert_eq(asked[0], "ws1/st1 s-c1 演示录屏.mp4")
  // 16:9 in 300 wide (image_box: 360 × 203 at most), covering its box
  let (bw, bh, _) = @sfpages.image_box(a, @sfpages.video_least)
  let h = bh * 300.0 / bw
  assert_true(
    t.drawn_images().iter().any(fn(i) { (i[2] - 300.0).abs() < 0.5 && (i[3] - h).abs() < 0.5 }),
  )
  assert_true(t.find("演示录屏.mp4") is Some(_))
  // its message saying none, no length beside its name
  assert_true(t.find("0:") is None)
}

///|
test "a video in the chat says how long it is at its name's end, as its message does (the station read it from its header)" {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, name) { fixture_file(name) } }
  let a : Attachment = {
    name: "一段很长很长很长很长很长很长很长很长很长的屏幕录制.mp4",
    path: "uploads/fx/录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 72500.0,
    frames: 2175,
    held: false,
  }
  let t = @ui.Tester::new(fn(c) { chat_file(c, src, a) }, w=390.0, h=844.0)
  t.draw()
  t.run_for(@ui.image_fade_ms)
  let (lx, ly) = t.find("1:13").unwrap()
  let (nx, ny) = t.find("一段很长").unwrap()
  // on the name's line, after it; the name cut short for it, nothing squeezed past that
  assert_true((ly - ny).abs() < 1.0 && lx > nx)
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a video's still over its picture until the player's first frame shows; then the picture alone" {
  let t = preview_tester("video")
  let poster_drawn = fn() {
    let (x, y, w, h) = t.holes()[0]
    t
    .drawn_images()
    .iter()
    .any(fn(i) { (i[0] - x).abs() < 1.0 && (i[1] - y).abs() < 1.0 && (i[2] - w).abs() < 1.0 && (i[3] - h).abs() < 1.0 })
  }
  // no frame shown yet: the chat's still where the picture will be
  t.set_player(1, shown=false)
  t.draw()
  t.run_for(@ui.image_fade_ms)
  assert_true(poster_drawn())
  // its first frame: the picture alone
  t.set_player(1, shown=true)
  t.draw()
  assert_true(!poster_drawn())
}

///|
/// A video open with ten frames a tenth of a second apart (as its player says them), a second long; its timeline's
/// track (from its left, how wide) and its middle.
fn ten_frames() -> (@ui.Tester, Double, Double, Double) raise {
  let t = preview_tester("video")
  t.set_player(1, duration=1000.0, playing=true)
  assert_true(
    t.view_said("{\"view\":{\"view\":1,\"what\":1,\"text\":\"0,100,200,300,400,500,600,700,800,900\"}}"),
  )
  t.draw()
  let (x, y, w, h) = t.ctx().rect_of(t.ctx().id("preview-media/timeline")).unwrap()
  (t, x + @sf.player_track_inset, w - 2.0 * @sf.player_track_inset, y + h / 2.0)
}

///|
test "a video's timeline dragged: paused, the player told a finger is on it, a seek to each frame it comes to, the head with it" {
  let (t, x0, span, mid) = ten_frames()
  let seeks = fn() { t.views().filter(fn(l) { l.has_prefix("control 1 3 ") }) }
  // down at a quarter: paused, the player's seeks one after another from now, to the frame showing there (200 ms)
  t.press_at(x0 + span * 0.25, mid)
  assert_true(t.views().contains("control 1 2 0"))
  assert_true(t.views().contains("control 1 9 1"))
  assert_eq(seeks(), ["control 1 3 200"])
  // on within that frame: nothing more asked
  t.move(x0 + span * 0.27, mid)
  assert_eq(seeks().length(), 1)
  // to three quarters: the frame there (700 ms), the head and the frame's count there before the player says it is
  // (it says the seek it is taking up: the first, still)
  t.set_player(1, position=200.0)
  t.move(x0 + span * 0.75, mid)
  assert_eq(seeks(), ["control 1 3 200", "control 1 3 700"])
  assert_true(t.find("8 / 10 帧") is Some(_))
  assert_true(
    t
    .drawn_rects()
    .iter()
    .any(fn(r) { (r.2 - 12.0).abs() < 0.5 && (r.3 - 12.0).abs() < 0.5 && (r.0 + 6.0 - (x0 + span * 0.7)).abs() < 0.5 }),
  )
  assert_true(!t.views().contains("control 1 9 0"))
  // let go further on than its last move (the two in one frame): to the frame there first (900 ms), then told so, and
  // played on as it played when the finger came
  let plays = t.views().filter(fn(l) { l == "control 1 1 0" }).length()
  t.release(x0 + span * 0.95, mid)
  assert_eq(seeks(), ["control 1 3 200", "control 1 3 700", "control 1 3 900"])
  let log = t.views()
  assert_true(log.search("control 1 3 900").unwrap() < log.search("control 1 9 0").unwrap())
  assert_eq(log.filter(fn(l) { l == "control 1 1 0" }).length(), plays + 1)
}

///|
test "a video's timeline tapped: to about the frame there at once (the nearest key frame), played on as it was, no finger along it told" {
  let (t, x0, span, mid) = ten_frames()
  t.tap(x0 + span * 0.55, mid)
  assert_true(t.views().contains("control 1 11 500"))
  assert_true(!t.views().iter().any(fn(l) { l.has_prefix("control 1 3 ") }))
  assert_true(!t.views().contains("control 1 2 0"))
  assert_true(!t.views().iter().any(fn(l) { l.has_prefix("control 1 9 ") }))
}

///|
test "a video's ‹ and › go to a frame's very start, a frame on from the one the player says it is at (in whole ms)" {
  let t = preview_tester("video")
  assert_true(t.view_said("{\"view\":{\"view\":1,\"what\":1,\"text\":\"0,33.333,66.667\"}}"))
  t.draw()
  let tap_button = fn(key : String) {
    let (x, y, w, h) = t.ctx().rect_of(t.ctx().id(key)).unwrap()
    t.tap(x + w / 2.0, y + h / 2.0)
  }
  // (paused, the player's ±15 s are its frames' keys)
  // › from the first: to the second's start, as the file has it (no ms rounded up: past it is the third's)
  tap_button("preview-media/frame-on")
  assert_true(t.views().contains("control 1 3 33.333"))
  // the player there says 33 (whole ms): that is the second still, so › goes to the third
  t.set_player(1, position=33.0)
  t.draw()
  tap_button("preview-media/frame-on")
  assert_true(t.views().contains("control 1 3 66.667"))
  // and ‹ from the third (66) back to the second
  t.set_player(1, position=66.0)
  t.draw()
  tap_button("preview-media/frame-back")
  assert_eq(t.views().filter(fn(l) { l == "control 1 3 33.333" }).length(), 2)
}

///|
/// A chat's video (16:9, its still the station's poster) alone on a page, the viewer over it once it is tapped open.
fn video_in_chat() -> @ui.Tester {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, name) { fixture_file(name) } }
  let a : Attachment = {
    name: "演示录屏.mp4",
    path: "uploads/fx/演示录屏.mp4",
    size: 5242880.0,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = @ui.Tester::new(
    fn(c) {
      chat_file(c, src, a)
      preview(c, src)
    },
    w=390.0,
    h=844.0,
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  t
}

///|
/// The bytes in hex (a host's grabbed frame as a run's line says it: Tester::view_said).
fn hex_bytes(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder::new()
  for x in b {
    out.write_char(digits.get_char(x.to_int() >> 4).unwrap())
    out.write_char(digits.get_char(x.to_int() & 15).unwrap())
  }
  out.to_string()
}

///|
test "a video flies from its thumbnail in the chat, its still flying; the player's picture once it is in" {
  let t = video_in_chat()
  t.tap_text("演示录屏.mp4")
  assert_true(viewer.get() is Some(_))
  // halfway: its still flies (the thumbnail hidden meanwhile), the player's picture not yet
  t.run_for(@ui.move_most_ms / 2.0)
  assert_eq(t.holes().length(), 0)
  assert_eq(pv_hidden.val, "ws1/st1/s-c1/uploads/fx/演示录屏.mp4")
  assert_true(t.drawn_images().iter().any(fn(i) { i[2] > 300.0 && i[2] < 390.0 }))
  // in: the player's picture where the still was, edge to edge
  t.run_for(@ui.move_most_ms)
  assert_eq(pv_hidden.val, "")
  assert_eq(t.holes().length(), 1)
  assert_true((t.holes()[0].2 - 390.0).abs() < 0.5)
}

///|
test "a video closed: the frame it shows grabbed, flown back with and kept by its thumbnail; opened again, on from there" {
  let t = video_in_chat()
  t.tap_text("演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  // the player 4 s in
  t.set_player(1, position=4000.0)
  t.draw()
  t.back()
  // the frame it shows grabbed first, the player's picture there meanwhile
  assert_true(t.views().contains("control 1 22 640"))
  assert_eq(t.holes().length(), 1)
  // grabbed: kept, with where it was; flown back with
  let frame = fixture_file_png("演示录屏.mp4")
  assert_true(t.view_said("{\"still\":{\"view\":1},\"b\":\"\{hex_bytes(frame)}\"}"))
  t.draw()
  let id = "ws1/st1/s-c1/uploads/fx/演示录屏.mp4"
  match pv_frames.get(id) {
    Some((_, ms)) => assert_eq(ms, 4000.0)
    None => fail("no frame kept")
  }
  assert_eq(t.holes().length(), 0)
  assert_eq(pv_hidden.val, id)
  // landed: the viewer gone, its player closed, the thumbnail shown again (with the frame kept)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None)
  assert_true(t.views().contains("close 1"))
  assert_eq(pv_hidden.val, "")
  // opened again: on from where it was left, played once its player says how long it is (not left at its end); the
  // video itself pressed (its name's tip shows under it now, the pointer rested on it as it landed)
  t.click(Button, label=@sf.t("web-main.file.play", args=[("name", "演示录屏.mp4")]))
  t.draw()
  let log = t.views()
  let seek = log.search("control 2 3 4000")
  let play = log.search("control 2 1 0")
  assert_true(seek is Some(_) && play is Some(_) && seek.unwrap() < play.unwrap())
}

///|
test "a video closed before its first frame shows: back into its thumbnail with its still, nothing kept" {
  let t = video_in_chat()
  t.tap_text("演示录屏.mp4")
  t.run_for(@ui.move_most_ms)
  t.set_player(1, shown=false)
  t.draw()
  t.back()
  assert_true(!t.views().iter().any(fn(l) { l.has_prefix("control 1 22 ") }))
  t.run_for(@ui.move_most_ms)
  assert_true(pv_leaving.get() is None)
  assert_true(pv_frames.is_empty())
}

///|
/// A chat's video of `size` bytes the station made no poster of, alone on a page.
fn posterless(size : Double) -> @ui.Tester {
  new_run()
  let src : Source = { ..fixture("chat"), poster: fn(_, _, _) { "!" } }
  let a : Attachment = {
    name: "录屏.mp4",
    path: "uploads/fx/录屏.mp4",
    size,
    width: 1280.0,
    height: 720.0,
    thumbhash: "",
    owner: "s-c1",
    upload: "",
    duration: 0.0,
    frames: 0,
    held: false,
  }
  let t = @ui.Tester::new(fn(c) { chat_file(c, src, a) }, w=390.0, h=844.0)
  t.draw()
  t
}

///|
test "a small video the station made no poster of: its first frame drawn in the chat, by a player of it out of sight" {
  let t = posterless(big_file / 8.0)
  // a player of it opened, never placed (no hole), its frame at 0 asked for
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("open 1 1 ") }))
  assert_true(t.views().contains("control 1 21 0"))
  assert_eq(t.holes().length(), 0)
  // grabbed: in the box, covering it; the player let go
  assert_true(
    t.view_said("{\"still\":{\"view\":1},\"b\":\"\{hex_bytes(fixture_file_png("演示录屏.mp4"))}\"}"),
  )
  t.draw()
  t.run_for(@ui.image_fade_ms)
  assert_true(t.views().contains("close 1"))
  assert_true(t.drawn_images().iter().any(fn(i) { (i[2] - 300.0).abs() < 0.5 }))
}

///|
test "a big video the station made no poster of: the black alone, nothing read for its frame" {
  let t = posterless(big_file * 2.0)
  assert_true(!t.views().iter().any(fn(l) { l.has_prefix("open ") }))
  assert_eq(t.drawn_images().length(), 0)
}

///|
test "a PDF's pages, drawn by the host" {
  let t = preview_tester("pdf")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("pdf ") }))
  let v = viewer.get().unwrap()
  assert_eq(v.pdf.unwrap().pages, 3)
  // kept on the device with its chat, by its size, as Android keeps a PDF it opens (FilePreview.kt OnDisk)
  let asked = fix_fetches.filter(fn(f) { f.0 == "station.file" && text(Some(f.1), "name") == "设计说明.pdf" })
  assert_true(asked.length() > 0)
  assert_true(flag(Some(asked[0].1), "keep"))
  assert_eq(number(Some(asked[0].1), "size"), 2400.0)
}

///|
test "HTML in a page of its own; its source in the code face" {
  let t = preview_tester("html")
  assert_true(t.views().iter().any(fn(l) { l.has_prefix("open 1 2 ") }))
  assert_eq(t.holes().length(), 1)
  let (_, y, _, _) = t.holes()[0]
  assert_eq(y, 60.0)
  t.tap_text("源码")
  assert_true(t.views().contains("close 1"))
  assert_true(t.find("周报草稿") is Some(_))
}

///|
test "a file of no kind it can show: told of, with the download" {
  let t = preview_tester("none")
  assert_true(t.find("此文件类型不支持预览") is Some(_))
  assert_true(t.find("4 KB · BIN") is Some(_))
  assert_true(t.find("下载") is Some(_))
}

///|
test "an APK told of: 安装 first, handed to the system's installer once its bytes are here; 下载 beside it" {
  let t = preview_tester("apk")
  assert_true(t.find("安装") is Some(_))
  assert_true(t.find("下载") is Some(_))
  t.tap_text("安装")
  // read through the core first (the fixture answers at once), then handed over
  t.frame()
  assert_eq(t.installs(), ["测试版.apk"])
}

///|
test "an APK asked for: downloaded by the core, how far it has come in its words over a bar (FileProgress) as it tells it" {
  new_run()
  let src = fixture("chat-preview-apk")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.tap_text("下载")
  t.frame()
  // asked of the core, nothing of it here yet
  assert_true(t.find("正在下载 0% · 8 KB") is Some(_))
  // (its 下载 no longer there)
  assert_true(!t.words().iter().any(fn(w) { w.0 == "下载" }))
  // half of it here (the fixture's core: a twentieth each step)
  t.run_for(fix_download_step_ms * 10.0)
  assert_true(t.find("正在下载 50% · 8 KB") is Some(_))
}

///|
test "an APK without the leave to install apps: the system's page, and said to tap again; a failure later said" {
  let t = preview_tester("apk")
  t.tap_text("安装")
  t.frame()
  assert_eq(t.installs(), ["测试版.apk"])
  // the system's page for the leave opened in its place, said so (the host's system channel)
  t.post(@hostapi.system_channel, "{\"install\":{\"name\":\"测试版.apk\",\"allow\":true}}")
  t.frame()
  assert_true(t.find("允许 still.fail 安装应用后，再次点击安装") is Some(_))
  t.run_for(toast_ms)
  // what the installer says, later (the host's system channel)
  t.post(@hostapi.system_channel, "{\"install\":{\"name\":\"测试版.apk\",\"error\":\"签名不一致\"}}")
  t.frame()
  assert_true(t.find("无法安装：签名不一致") is Some(_))
}

///|
test "Markdown rendered; code as it is; a table" {
  let t = preview_tester("md")
  assert_true(t.find("发布前要做的") is Some(_))
  let t = preview_tester("code")
  assert_true(t.find("export const estimate = 66;") is Some(_))
  let t = preview_tester("csv")
  assert_true(t.find("帧时间（毫秒）") is Some(_))
  assert_true(t.find("设置, 外观") is Some(_))
}

///|
/// A file a message names by its path (`path`, the made-up station's: fixture_named) open in the preview, the window
/// 390 wide.
fn named_tester(path : String) -> @ui.Tester {
  new_run()
  let src = fixture("chat-preview-named")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  open_preview("ws1/st1", "s-c1", attachment_of({ "name": Json::string(base_name(path)), "path": Json::string(path) }), named=true)
  t.frame()
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a long log a message names: its first part shown at once, the next read as its end comes near, never all of it first" {
  let t = named_tester("logs/build.log")
  let reads = fn() { fix_fetches.filter(fn(f) { f.0 == "file.open" }) }
  // read by its path, a part from its start, shown
  assert_eq(reads().length(), 1)
  assert_eq(text(Some(reads()[0].1), "path"), "logs/build.log")
  assert_eq(number(Some(reads()[0].1), "offset"), 0.0)
  assert_eq(number(Some(reads()[0].1), "length"), @sfbase.flow_part.to_double())
  assert_true(t.find("[build] 第 1 行：编译 src/module_1.mbt 完成，用时 1 ms") is Some(_))
  // scrolled on towards the end of what has come: the next part read
  for _ in 0..<80 {
    if reads().length() > 1 {
      break
    }
    t.wheel(195.0, 400.0, 3000.0)
  }
  assert_eq(reads().length(), 2)
  assert_eq(number(Some(reads()[1].1), "offset"), @sfbase.flow_part.to_double())
}

///|
test "a text shown as it comes: its lines whole however its parts cut them, a character cut at a part's end and all" {
  let log = fixture_log()
  let f = @sfbase.Flow::new()
  f.total = log.length().to_double()
  // in parts of 1000 bytes: each cuts a line, and most a character of three bytes
  let mut at = 0
  while at < log.length() {
    let to = if at + 1000 < log.length() { at + 1000 } else { log.length() }
    f.got = to.to_double()
    f.take(log[at:to].to_bytes())
    at = to
  }
  assert_eq(f.lines.length(), 12000)
  assert_eq(f.lines[0], "[build] 第 1 行：编译 src/module_1.mbt 完成，用时 1 ms")
  assert_eq(f.lines[11999], "[build] 第 12000 行：编译 src/module_69.mbt 完成，用时 1 ms")
  assert_eq(f.tail, "")
  assert_eq(@sfbase.utf8_whole(@utf8.encode("行")[0:2].to_bytes()), 0)
  assert_eq(@sfbase.utf8_whole(@utf8.encode("a行")), 4)
}

///|
test "a file a message names that comes whole in its first part: shown as any file read whole, its code coloured" {
  let t = named_tester("src/list/place.mbt")
  assert_true(viewer.get().unwrap().bytes.get() is Some(_))
  assert_true(t.find("self.anchor = self.anchor + n") is Some(_) || t.locate("self.anchor = self.anchor + n").length() > 0)
}

///|
test "two fingers pinch an image round the point between them; no tap comes of it" {
  let t = preview_tester("image")
  let v = viewer.get().unwrap()
  let fit = shown_scale(t, v.zoom)
  let awake = v.awake
  t.touch(0, 150.0, 422.0)
  t.draw()
  t.touch(4, 240.0, 422.0)
  t.draw()
  t.touch(5, 330.0, 422.0)
  t.draw()
  // 90 apart, then 180: twice as big
  assert_true((shown_scale(t, v.zoom) - fit * 2.0).abs() < 0.001)
  t.touch(6, 330.0, 422.0)
  t.draw()
  t.touch(2, 150.0, 422.0)
  t.draw()
  assert_eq(v.awake, awake)
}

///|
test "stepping through the chat's images: the way to the next (imageNear), a tap goes there" {
  let t = preview_tester("step")
  assert_true(t.find("界面草图.png") is Some(_))
  // fitted 600 × 400 in 366 wide: the way to the one after on the right
  let v = viewer.get().unwrap()
  let (_, after) = v.near(preview_src.val.unwrap())
  assert_true(after is Some(_))
  t.tap(390.0 - 8.0 - 18.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  assert_true(t.find("第二版.png") is Some(_))
}

///|
test "a swipe past a fifth of the stage goes to the next; a short one comes back" {
  let t = preview_tester("step")
  t.drag(300.0, 422.0, 260.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "界面草图.png")
  t.drag(300.0, 422.0, 100.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
}

///|
test "a swipe carries the picture under the finger from where it went down; a second finger takes it back, not left between two" {
  let t = preview_tester("step")
  let (x, y, w, h) = viewer.get().unwrap().zoom.rect().unwrap()
  let at = fn(dx : Double) {
    drawn_pictures(t).any(fn(d) {
      (d.0 - (x + dx)).abs() < 0.001 && (d.1 - y).abs() < 0.001 && (d.2 - w).abs() < 0.001 && (d.3 - h).abs() < 0.001
    })
  }
  t.hold_drag(300.0, 422.0, 250.0, 422.0)
  // 50 left, as the finger went: none of its way lost to the slop
  assert_true(at(-50.0))
  t.touch(4, 100.0, 422.0)
  t.draw()
  t.touch(6, 100.0, 422.0)
  t.draw()
  t.release(250.0, 422.0)
  t.run_for(strip_rest(t))
  assert_eq(viewer.get().unwrap().file.name, "界面草图.png")
  assert_true(at(0.0))
}

///|
test "a step keeps the bars as they were: hidden by a tap, the next comes without them" {
  let t = preview_tester("step")
  t.tap(195.0, 422.0)
  t.run_for(double_tap_ms)
  assert_true(!viewer.get().unwrap().awake)
  t.drag(300.0, 422.0, 100.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  assert_true(!viewer.get().unwrap().awake)
}

///|
test "pinched smaller than fitted and let go: back to fitted" {
  let t = preview_tester("image")
  let v = viewer.get().unwrap()
  let fit = shown_scale(t, v.zoom)
  t.touch(0, 150.0, 422.0)
  t.draw()
  t.touch(4, 330.0, 422.0)
  t.draw()
  t.touch(5, 240.0, 422.0)
  t.draw()
  assert_true(shown_scale(t, v.zoom) < fit * 0.75)
  t.touch(6, 240.0, 422.0)
  t.draw()
  t.touch(2, 150.0, 422.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true((shown_scale(t, v.zoom) - fit).abs() < 0.001)
}

///|
test "a swipe back as the step to the next still slides: a finger catches it there, and a quick short move back goes back" {
  let t = preview_tester("step")
  t.drag(300.0, 422.0, 100.0, 422.0)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  // at once, the next mostly in: a quick 60 to the right, the way back
  t.drag(100.0, 422.0, 160.0, 422.0, steps=3)
  t.run_for(strip_rest(t))
  assert_eq(viewer.get().unwrap().file.name, "界面草图.png")
  // and a finger down on a slide and up again: it stays at the one nearest, no tap of it
  t.drag(300.0, 422.0, 100.0, 422.0)
  t.run_for(@ui.input_step_ms)
  let awake = viewer.get().unwrap().awake
  t.touch(0, 195.0, 422.0)
  t.draw()
  t.touch(2, 195.0, 422.0)
  t.draw()
  t.run_for(strip_rest(t))
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
  assert_eq(viewer.get().unwrap().awake, awake)
}

///|
/// The pictures drawn in the last frame (x, y, w, h), left to right.
fn drawn_pictures(t : @ui.Tester) -> Array[(Double, Double, Double, Double)] {
  let out = t.drawn_images().map(fn(i) { (i[0], i[1], i[2], i[3]) })
  out.sort_by(fn(a, b) { a.0.compare(b.0) })
  out
}

///|
test "the frame a swipe is let go in shows both pictures where the finger left them, never this one where the next comes" {
  for way in [(300.0, 100.0), (100.0, 300.0)] {
    let t = preview_tester("step")
    if way.0 < way.1 {
      // from the second, back toward the first
      t.drag(300.0, 422.0, 100.0, 422.0)
      t.run_for(strip_rest(t))
    }
    let from = viewer.get().unwrap().file.name
    t.hold_drag(way.0, 422.0, way.1, 422.0)
    let held = drawn_pictures(t)
    // (the frame drawn at the moment it is let go: from where the finger left them, nothing moved yet)
    t.touch(2, way.1, 422.0)
    t.frame_at(t.time())
    assert_true(viewer.get().unwrap().file.name != from)
    let drawn = drawn_pictures(t)
    assert_eq(drawn.length(), held.length())
    for i, d in drawn {
      let h = held[i]
      assert_true(
        (d.0 - h.0).abs() < 0.001 &&
        (d.1 - h.1).abs() < 0.001 &&
        (d.2 - h.2).abs() < 0.001 &&
        (d.3 - h.3).abs() < 0.001,
      )
    }
  }
}

///|
/// The viewer's image zoomed in by a double tap in its middle (2.5 times fitted: 915 × 610 on the 390 × 844 stage, 262.5
/// to go either way across), the next taps a double tap of their own.
fn zoom_in_middle(t : @ui.Tester) -> @kit.Zoom raise {
  t.tap(195.0, 422.0)
  t.advance(double_tap_ms / 2.0)
  t.tap(195.0, 422.0)
  t.run_for(@ui.move_most_ms)
  t.run_for(double_tap_ms)
  let z = viewer.get().unwrap().zoom
  assert_true(z.zoomed_at(t.time()))
  z
}

///|
test "zoomed in, let go moving it goes on that way, slowing, to its edge; a finger on it stops it and taps nothing" {
  let t = preview_tester("image")
  let v = viewer.get().unwrap()
  let z = zoom_in_middle(t)
  // a quick move left (60 in 50 ms), let go: on after the finger, three of its moves' time later well on
  t.drag(250.0, 422.0, 190.0, 422.0, steps=3)
  let let_go = shown_x(t, z)
  assert_true(let_go < 0.0)
  t.run_for(3.0 * @ui.input_step_ms)
  assert_true(shown_x(t, z) < let_go - 20.0)
  // a finger down on it: it stops there, and the bars stay as they were
  let awake = v.awake
  t.touch(0, 195.0, 422.0)
  t.draw()
  let held = shown_x(t, z)
  t.touch(2, 195.0, 422.0)
  t.draw()
  t.run_for(@kit.zoom_fling_ms)
  assert_eq(shown_x(t, z), held)
  assert_eq(v.awake, awake)
  // flung harder: it stops at its edge (its right edge at the stage's), when its way said it ends
  t.drag(250.0, 422.0, 130.0, 422.0, steps=3)
  t.run_for(z.fling_ends() - t.time())
  let (x, _, w, _) = z.rect().unwrap()
  assert_true((x + w - 390.0).abs() < 0.001)
  t.run_for(@kit.zoom_fling_ms)
  assert_true((z.rect().unwrap().0 - x).abs() < 0.001)
}

///|
test "zoomed in, dragged on past its edge the next comes in; a quick move that came to its edge on the way comes back" {
  let t = preview_tester("step")
  let z = zoom_in_middle(t)
  // quick (95 a move), from its middle: to its edge and 22.5 past, let go there: back, and it stays at its edge
  t.drag(385.0, 422.0, 5.0, 422.0, steps=4)
  t.run_for(strip_rest(t))
  assert_eq(viewer.get().unwrap().file.name, "界面草图.png")
  let (x, _, w, _) = z.rect().unwrap()
  assert_true((x + w - 390.0).abs() < 0.001)
  // from its edge, a short quick move on: the next
  t.drag(300.0, 422.0, 260.0, 422.0, steps=2)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
}

///|
test "zoomed in, dragged slowly far past its edge it stops there, nothing beside it pulled; another drag from there: the next" {
  let t = preview_tester("step")
  let z = zoom_in_middle(t)
  t.drag(385.0, 422.0, 5.0, 422.0, steps=20)
  t.run_for(strip_rest(t))
  assert_eq(viewer.get().unwrap().file.name, "界面草图.png")
  let (x, _, w, _) = z.rect().unwrap()
  assert_true((x + w - 390.0).abs() < 0.001)
  t.drag(385.0, 422.0, 5.0, 422.0, steps=20)
  assert_eq(viewer.get().unwrap().file.name, "第二版.png")
}

///|
test "marking: a box drawn on the picture is numbered, its note kept, its quote says where it is" {
  let t = preview_tester("image")
  marks_start()
  t.draw()
  let v = viewer.get().unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  // from (100, 100) to (300, 200) in the picture's pixels
  t.drag(x + 100.0 * k, y + 100.0 * k, x + 300.0 * k, y + 200.0 * k)
  assert_eq(marking.shapes.length(), 1)
  assert_eq(marking.shapes[0].kind, "box")
  assert_eq(mark_numbers(marking.shapes).get(marking.shapes[0].id), Some(1))
  // what is said of it, then its quote
  marking.comments[marking.shapes[0].id] = "这里对齐"
  let q = marks_quotes("界面草图-标注.png", "界面草图.png", v.zoom.nw, v.zoom.nh)
  assert_eq(q.length(), 1)
  assert_eq(q[0].0, "图片 界面草图.png 标注 1")
  assert_true(q[0].1.has_prefix("框 · 左上角 ("))
  assert_eq(q[0].2, "这里对齐")
  // undone, none; redone, back
  marks_undo()
  assert_eq(marking.shapes.length(), 0)
  marks_redo()
  assert_eq(marking.shapes.length(), 1)
  marks_leave()
}

///|
test "a picture of the chat grows from its thumbnail; back closes it at once and it flies back into the thumbnail, then nothing moves" {
  new_run()
  let src = fixture("chat-preview-named")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  nav_rested(t)
  // the picture's message is above what shows first (the chat opens at its end): the list put a row up at a time
  // (not wheeled: a wheel shows the list's scroll bar, which goes after a while of its own)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:compare.png")
  assert_true(at.length() > 0)
  let (x, y) = at[0]
  t.tap(x, y)
  let v = viewer.get().unwrap()
  assert_eq(v.file.name, "compare.png")
  assert_true(v.flies && !v.fly_back)
  // grown in: @ui.move_most_ms from the tap
  t.run_for(@ui.move_most_ms)
  assert_true(!v.flies)
  // where its thumbnail is in the chat under it
  let th = thumb_of(t.ctx(), v.id()).unwrap()
  let tc = (th.x + th.w / 2.0, th.y + th.h / 2.0)
  t.back()
  // closed as back is taken: only drawn, flying back into its thumbnail
  assert_true(viewer.get() is None)
  assert_true(pv_leaving.get() is Some(_))
  assert_true(v.flies && v.fly_back)
  let to = v.zoom.rect().unwrap()
  // each frame of the way back the picture is drawn where its flight is, nearer the thumbnail than the frame before,
  // the last one on it
  let mut last = 1.0e9
  let mut frames = 0
  // its way back: @ui.move_most_ms from back
  let end = t.time() + @ui.move_most_ms
  while t.time() < end {
    t.frame()
    let p = v.flying()
    let ex = th.x + (to.0 - th.x) * p + (th.w + (to.2 - th.w) * p) / 2.0
    let ey = th.y + (to.1 - th.y) * p + (th.h + (to.3 - th.h) * p) / 2.0
    let drawn = t
      .drawn_images()
      .iter()
      .any(fn(i) { (i[0] + i[2] / 2.0 - ex).abs() < 0.5 && (i[1] + i[3] / 2.0 - ey).abs() < 0.5 && i[2] > th.w / 2.0 })
    assert_true(drawn)
    let d = (ex - tc.0).abs() + (ey - tc.1).abs()
    assert_true(d <= last)
    last = d
    frames += 1
  }
  assert_true(frames > 3)
  assert_true(last < 0.5)
  assert_true(pv_leaving.get() is None)
  assert_eq(pv_hidden.val, "")
  // (the chat's other pictures brushed in once decoded: sfpages message_files.mbt)
  t.run_for(@sfpages.reveal_ms)
  t.assert_idle()
}

///|
test "marking a picture of a long name: the bar's 取消, download and 添加到对话 whole, the name cut short instead" {
  let t = preview_tester("step")
  // the same picture under a long name, opened from the chat (a draft to put it in)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", { ..a, name: "web-open-2-folded-preview-of-the-chat.png" }, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  marks_start()
  t.draw()
  let (px, _, pw, _) = t.rect_of("添加到对话").unwrap()
  let (cx, _, cw, _) = t.rect_of("取消").unwrap()
  // the bar 8 in from the window's right (fpHead under 640), 6 inside it the × (32), 2 before it the pill, its words
  // 12 inside it
  assert_true(px + pw <= 390.0 - 8.0 - 6.0 - 32.0 - 2.0 - 12.0 + 0.5, msg="添加到对话 inside its ground, clear of ×")
  assert_true(cw >= 24.0, msg="取消 whole")
  assert_true(cx + cw <= px, msg="取消 before 添加到对话")
  match t.rect_of("web-open-2") {
    Some((nx, _, _, _)) => assert_true(nx < cx)
    None => ()
  }
  marks_leave()
}

///|
test "marking: a box's pin up and right of its corner wherever the marks before it are; its note's box as Notes.kt's, the tools away" {
  let t = preview_tester("step")
  marks_start()
  t.draw()
  let v = viewer.get().unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  // a line drawn by hand first, then a box from (100, 100) to (300, 200) in the picture's pixels
  marking.tool = Pen
  t.drag(x + 20.0 * k, y + 300.0 * k, x + 200.0 * k, y + 350.0 * k)
  marking.tool = Rect
  t.drag(x + 100.0 * k, y + 100.0 * k, x + 300.0 * k, y + 200.0 * k)
  t.draw()
  // its pin (24 square, 2 left of the corner and 22 over it), its number in its middle
  let (px, py, pw, ph) = t.rect_of("1").unwrap()
  assert_true((px + pw / 2.0 - (x + 100.0 * k - 2.0 + 12.0)).abs() < 1.0, msg="the pin's x")
  assert_true((py + ph / 2.0 - (y + 100.0 * k - 22.0 + 12.0)).abs() < 1.0, msg="the pin's y")
  // its note open: 框, the field's 添加批注（可选）, the tick; the tools and their cards away (the field an old view's,
  // drawn once the note coming in from nothing shows)
  assert_eq(marking.note, marking.shapes[1].id)
  assert_true(t.find("框") is Some(_))
  t.run_for(note_pop_ms)
  assert_true(t.find("添加批注（可选）") is Some(_))
  assert_true(t.find("只引用") is None)
  t.type_text("这里对齐")
  let tick = t.reachable("icon:check")
  assert_eq(tick.length(), 1)
  t.tap(tick[0].0, tick[0].1)
  t.draw()
  assert_eq(marking.note, -1)
  assert_eq(marking.comments.get(marking.shapes[1].id), Some("这里对齐"))
  // the card says it, what it is under it
  assert_true(t.find("这里对齐") is Some(_))
  marks_leave()
}

///|
test "a desktop's video opened over its chat has the keys: Space plays it each time, the chat's composer under it never taking them" {
  new_run()
  let src = fixture("chat-preview-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_))
  let played = fn() { t.views().filter(fn(l) { l == "control 1 1 0" }).length() }
  let before = played()
  // (the chat's own Space, with no field focused, puts the cursor in its composer: not under the film)
  t.key(@ui.key_space)
  assert_false(t.ctx().field_focused())
  t.key(@ui.key_space)
  assert_false(t.ctx().field_focused())
  assert_eq(played(), before + 2)
}

///|
/// A chat's file `a` as its message draws it (sfpages' message_files), in a column 300 wide.
fn chat_file(c : @ui.Ctx, src : Source, a : Attachment, list? : String = "") -> Unit {
  let here : @sfpages.MessageHere = {
    station: "ws1/st1",
    session: "s-c1",
    view: chat_view_made(Json::object({})),
    go: None,
    inline: true,
    gutter: 0.0,
    // (in chat list `list`, where it is in one)
    list: if list == "" {
      None
    } else {
      Some({ rk: list, turns: @sfbase.turns_of(list), emits: @sfbase.emits_of(list), flight: None })
    },
    core: None,
  }
  c.box(style=@ui.style(w=Fixed(300.0)), fn() { @sfpages.message_files(c, src, here, [a], false) }) |> ignore
}

///|
test "marking: a note written and done, the picture put in the chat: its quote there says it, no field takes the keyboard" {
  let t = preview_tester("step", w=951.0, platform=2)
  let (a, _) = preview_files().iter().find_first(fn(f) { f.0.name == "界面草图.png" }).unwrap()
  open_preview("ws1/st1", "s-c1", a, steps=InChat(Some(1.0), "s-c1"))
  t.run_for(@ui.move_most_ms)
  marks_start()
  t.draw()
  let v = viewer.get().unwrap()
  let (x, y, w, _) = v.zoom.rect().unwrap()
  let k = w / v.zoom.nw
  t.drag(x + 100.0 * k, y + 100.0 * k, x + 300.0 * k, y + 200.0 * k)
  t.run_for(note_pop_ms)
  t.type_text("这里对齐")
  let tick = t.reachable("icon:check")
  t.tap(tick[0].0, tick[0].1)
  t.draw()
  let (px, py, pw, ph) = t.get(Button, label=pv("android-chat.preview.put")).rect
  t.tap(px + pw / 2.0, py + ph / 2.0)
  // the viewer closed back to the chat, the quote of the mark in its composer with what its note said
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None)
  assert_true(t.semantics().iter().any(fn(s) { s.value == "这里对齐" }))
  assert_false(t.ctx().field_focused())
}

///|
/// How long till the strip of pictures is where its way said it goes (none: 0).
fn strip_rest(t : @ui.Tester) -> Double {
  dmax(0.0, pv_strip.way.end() - t.time())
}

///|
/// How big the picture is shown at the tester's moment (where it is drawn then: Zoom::rect_at).
fn shown_scale(t : @ui.Tester, z : @kit.Zoom) -> Double {
  z.scale_at(t.time())
}

///|
/// How far across from the stage's middle the picture's middle is shown at the tester's moment.
fn shown_x(t : @ui.Tester, z : @kit.Zoom) -> Double {
  let (x, _, w, _) = z.rect_at(t.time()).unwrap()
  x + w / 2.0 - z.bw / 2.0
}
