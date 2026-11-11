// Sharing a chat as a picture on a phone (sfpages' publish.mbt, the same as keyboard and mouse's) over the fixture's
// chat: the page with the picture as it would be, the attachments ticked, the picture taken and kept in the photo album.

///|
/// The source the last publish_core made.
let publish_src : Ref[Source?] = Ref(None)

///|
/// The page that draws the chat as a picture opened, as 分享图片 in the chat's "…" does (the menu's own: wide_publish_wbtest).
fn open_publish_page() -> Unit {
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfpages.open_publish(publish_src.val.unwrap(), r, 7.0)
}

///|
/// The chat's sheet open over the fixture's chat (`menu`: the chat in its detail with no sheet over it, its page opened by open_publish_page as its "…"'s
/// 分享图片 does); `chat.publishPreview` answered with fix_preview, the rest with nothing; `preview` in its place, where given; `finish` false: what is asked of the host (a
/// picture decoded) done only as the test says (Tester::finish).
fn publish_core(
  calls : Array[Made],
  preview? : () -> Json = fix_preview,
  finish? : Bool = true,
  menu? : Bool = false,
  platform? : Int = 2,
  width? : Double = 390.0,
  height? : Double = 844.0,
  nav_able? : Bool = false,
) -> @ui.Tester {
  new_run()
  let mode = if menu { "chat-detail" } else { "chat-info" }
  let base = fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match name {
        "chat.publishPreview" => done(Ok(preview()))
        _ => done(Ok(Json::object({})))
      }
    },
  }
  publish_src.val = Some(src)
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=height, platform~, finish~, nav_able~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "sharing a chat on a small screen: a table wider than the screen and the usual chat column fits in the saved picture" {
  let sentence = "A long cell of words that needs room to remain readable"
  let cell = fn(tag : String, words : String) -> Json { [Json::string(tag), [Json::string(words)]] }
  let heads = ["First", "Second", "Third", "Fourth", "Fifth", "Last"]
  let tree : Json = [["table", [
    ["tr", Json::array(heads.map(fn(s) { cell("th", s) }))],
    ["tr", Json::array(heads.map(fn(s) { cell("td", s + " " + sentence) }))],
  ]]]
  let preview = fn() -> Json {
    let p = fix_preview()
    guard p is Object(o) else { @halt.saying("missing preview") }
    let copy = o.copy()
    let list = items(Some(p), "list").copy()
    guard list[1] is Object(m) else { @halt.saying("missing agent message") }
    let message = m.copy()
    message["text"] = "A wide table"
    message["md"] = tree
    list[1] = Json::object(message)
    copy["list"] = Json::array(list)
    Json::object(copy)
  }
  let mut previous_height = 0
  for width in [320.0, 390.0] {
    let calls : Array[Made] = []
    let t = publish_core(calls, preview~, width~, menu=true)
    open_publish_page()
    t.frame()
    t.run_for(@sf.presented_rest() - t.time())
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="保存到相册")
    t.run_for(@kit.presence_in_ms)
    let (pw, ph) = png_size(t.kept()[0].2).unwrap()
    // Its width is the chat's widest column at two pixels a point, independent of the small screen's width.
    assert_eq(pw, 1520, msg="the picture should keep the chat's maximum width")
    if previous_height > 0 { assert_eq(ph, previous_height, msg="the screen's width changed the message layout") }
    previous_height = ph
    let words = t.shots()[0].join("|")
    assert_true(words.contains("First") && words.contains("Last"), msg=words)
  }
}

///|
test "分享图片: the page shows the picture as it would be, 取消, 复制 and 保存到相册 at its foot; 保存到相册 keeps it in the album, without what was left out; 复制 copies it" {
  let calls : Array[Made] = []
  let t = publish_core(calls, menu=true)
  open_publish_page()
  // the chat's sheet put down (to where it rests, gone), the page over the whole screen (the pages', as on a computer)
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0].params), "station"), "ws1/st1")
  assert_eq(number(Some(asked[0].params), "thread"), 7.0)
  // the picture as it would be: the chat's name over its messages, still.fail's at its foot; what was hidden said
  // under its message (the floating bar of a small screen says no more than its name)
  assert_true(t.find("部署登录页") is Some(_))
  assert_true(t.find("截图、日志和构建缓存都附上了") is Some(_))
  assert_true(t.find("已隐藏 1 处") is Some(_))
  // its messages as the chat's list draws them: the viewer's own at its end, in its bubble; an agent's request about a
  // vault item as the chat says it (allowed: how it ended), not the words its post has for where there is no card
  assert_true(picture_mine_at_end(t), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("已允许使用 Axiom 查询 token") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("申请使用「Axiom 查询 token」：查登录页的错误日志") is None)
  // the log and the cache left out: tapped, each is unticked (nothing opens); brought up from under the screen's foot
  // (a file's card says its name's stem and its extension apart, as the chat's)
  for _ in 0..<6 {
    match t.find("build-cache") {
      Some((_, y)) if y < publish_fold => break
      _ => t.wheel(195.0, 400.0, 300.0)
    }
  }
  t.tap_text(".log")
  t.tap_text(".tar")
  assert_true(@sfpages.publish_left_out("f1") && @sfpages.publish_left_out("f2"))
  assert_true(viewer.get() is None)
  // nothing is published
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  // the picture taken: the chat's name, its messages, their times as dates, still.fail's; not the attachments left
  // out, nor the notes of what was hidden (for the one sharing it)
  let shots = t.shots()
  assert_eq(shots.length(), 1)
  let words = shots[0].join("|")
  assert_true(words.contains("部署登录页") && words.contains("截图、日志和构建缓存都附上了"), msg=words)
  assert_true(words.contains("10月15日 10:00") && !words.contains("分钟前"), msg=words)
  assert_true(!words.contains(".log") && !words.contains(".tar") && !words.contains("已隐藏 1 处"), msg=words)
  assert_true(words.contains("still.fail"), msg=words)
  // kept in the photo album, at the usual chat column's width and the screen's scale, said once it is
  assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
  match png_size(t.kept()[0].2) {
    Some((pw, ph)) => assert_true(pw == 1520 && ph > 600, msg="\{Repr((pw, ph))}")
    None => fail("not a PNG")
  }
  assert_true(t.find("已保存到相册") is Some(_))
  // 复制 between 取消 and 保存到相册 (2026-11-06 用户「手机上都加复制」), the two before it as wide as their words, none
  // cut short; pressed, the picture on the clipboard, nothing more in the album, the button 已复制 a moment
  let cancel = t.query(Button, label="取消").unwrap().rect
  let copy = t.query(Button, label="复制").unwrap().rect
  let save = t.query(Button, label="保存到相册").unwrap().rect
  assert_true(cancel.0 < copy.0 && copy.0 < save.0 && cancel.1 == copy.1 && copy.1 == save.1, msg="\{Repr((cancel, copy, save))}")
  assert_true(copy.2 < save.2, msg="\{Repr((cancel, copy, save))}")
  assert_true(t.find("保存到…") is None, msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Button, label="复制")
  t.frame()
  t.frame()
  match t.clipboard_png().bind(png_size) {
    Some((pw, _)) => assert_eq(pw, 1520)
    None => fail("no picture copied")
  }
  assert_eq(t.kept().length(), 1)
  assert_true(t.query(Button, label="已复制") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // 取消, beside them at the foot, closes it: gone as a dialog goes
  t.click(Button, label="取消")
  t.run_for(@kit.pop_out_ms)
  assert_true(t.find("部署登录页") is None)
}

///|
test "分享图片 on an iPhone Duo: the system's tabs put away, its way back and 保存到相册 in the system's bars, its own bar and band none; kept from there, closed from there, the tabs back" {
  // (on its side, the system's column down its trailing edge; upright, its bars across the top)
  for size in [(951.0, 669.0, 84.0), (669.0, 951.0, 0.0)] {
    let (w, h, side) = size
    let calls : Array[Made] = []
    let t = publish_core(calls, menu=true, platform=1, width=w, height=h, nav_able=true)
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{side}}}")
    t.run_for(@ui.move_most_ms)
    open_publish_page()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("部署登录页") is Some(_))
    let said = t.nav_said()
    for id in ["\"bare\":true", "lead/over/close", "over/copy", "复制图片", "over/act", "保存到相册"] {
      if !said.contains(id) {
        fail("\{Repr(size)}: the bars handed hold no \{id}: \{said}")
      }
    }
    // (its title upright, in the bar across the top; on its side none, the system floating it over the page's top)
    assert_eq(said.contains("\"title\":\"分享图片"), side == 0.0, msg=said)
    // (none of the tabs' own buttons while it is up: the chat's)
    assert_false(said.contains("page/chat/"), msg=said)
    // (none of its own: no bar across the top, no band of 取消 and 保存到相册 at the foot)
    assert_true(t.query(Button, label="保存到相册") is None)
    assert_true(t.query(Button, label="复制图片") is None)
    assert_true(t.query(Button, label="取消") is None)
    // (its boxes to tick and the rest of it clear of the system's column)
    for s in t.semantics() {
      let (x, _, sw, _) = s.rect
      if !s.hidden && s.label != "收起侧边栏" && s.role == @ui.Role::Button && s.label != "" && sw > 0.0 && x + sw > w - side + 0.5 {
        fail("\{Repr(size)}: \{s.label} under the system's column: \{Repr(s.rect)}")
      }
    }
    // 保存到相册 chosen there: the picture kept in the photo album
    t.post(@hostapi.system_channel, "{\"nav\":\"over/act\"}")
    t.run_for(@kit.presence_in_ms)
    assert_eq(t.kept_ways().map(fn(k) { (k.0, k.1.to_string()) }), [("still.fail.png", "Photos")])
    // 复制图片 chosen there: the picture on the clipboard, nothing more in the album, 已复制 there a moment
    t.post(@hostapi.system_channel, "{\"nav\":\"over/copy\"}")
    t.run_for(@ui.move_most_ms / 4.0)
    assert_true(t.clipboard_png() is Some(_), msg="\{Repr(size)}: nothing copied")
    assert_eq(t.kept_ways().length(), 1)
    assert_true(t.nav_said().contains("已复制"), msg=t.nav_said())
    // closed there: gone as a dialog goes, the tabs back
    t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/close\"}")
    t.run_for(@kit.pop_out_ms)
    assert_true(t.find("部署登录页") is None)
    assert_true(t.nav_said().contains("\"bare\":false"), msg=t.nav_said())
  }
}

///|
test "分享图片: a message unticked fades on the page and is not in the picture" {
  let calls : Array[Made] = []
  let t = publish_core(calls, menu=true)
  open_publish_page()
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  // a box to tick for each message, all ticked; the agent's words (the second) left out
  let ticks = t.all(Checkbox, label="放进图片")
  assert_eq(ticks.length(), 4)
  assert_true(ticks.iter().all(fn(n) { n.check == Some(On) }))
  // in a column of their own before the words (the phone's picture: the pictures inline, at the words' start)
  assert_true(ticks_before_words(t, 0.0), msg=Repr(ticks.map(fn(n) { n.rect })).to_string())
  // its attachments not ticked: each has the composer's ✕ on its corner, which takes it out; then a ＋ puts it back
  assert_eq(t.all(Checkbox).length(), 4)
  let outs = t.all(Button, label="移出图片")
  assert_eq(outs.length(), 3)
  let (ox, oy, ow, oh) = outs[1].rect
  t.tap(ox + ow / 2.0, oy + oh / 2.0)
  assert_true(@sfpages.publish_left_out("f1"))
  assert_eq(t.all(Button, label="移出图片").length(), 2)
  let backs = t.all(Button, label="放回图片")
  assert_eq(backs.length(), 1)
  let (bx, by, bw, bh) = backs[0].rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  assert_true(!@sfpages.publish_left_out("f1"))
  let (x, y, w, h) = ticks[1].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(@sfpages.publish_message_left_out(6.0))
  assert_true(!@sfpages.publish_message_left_out(4.0))
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  let words = t.shots()[0].join("|")
  assert_true(words.contains("截图、日志和构建缓存都附上了") && !words.contains("跑了 42 秒"), msg=words)
}

///|
test "多选: the chat's picture opened from a message has that message alone ticked, brought into sight; the others ticked join it" {
  let calls : Array[Made] = []
  // (short, so that Ana's message, the last, is under the window's foot as the page opens)
  let t = publish_core(calls, menu=true, height=520.0)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfpages.open_publish(publish_src.val.unwrap(), r, 7.0, picked=Some(9.0))
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  // the whole chat asked for, as 分享图片 asks it
  let asked = named(calls, "chat.publishPreview")
  assert_eq(asked.length(), 1)
  assert_true(field(Some(asked[0].params), "turn") is None)
  assert_eq(t.all(Checkbox, label="放进图片").map(fn(n) { n.check == Some(On) }), [false, false, false, true])
  assert_true(@sfpages.publish_message_left_out(4.0) && @sfpages.publish_message_left_out(6.0))
  assert_true(!@sfpages.publish_message_left_out(9.0))
  match t.rect_of("截图、日志和构建缓存都附上了") {
    Some((_, y, _, h)) => assert_true(y > 0.0 && y + h < 520.0, msg="\{Repr((y, h))}")
    None => fail("Ana's message not drawn")
  }
  // another ticked (the one over it, scrolled back to): both in the picture, the rest not
  t.wheel(195.0, 260.0, -150.0)
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.all(Checkbox, label="放进图片")[2].rect
  assert_true(y > 0.0 && y + h < 520.0, msg="\{Repr((y, h))}")
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(!@sfpages.publish_message_left_out(7.0) && @sfpages.publish_message_left_out(6.0))
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  let words = t.shots()[0].join("|")
  assert_true(words.contains("截图、日志和构建缓存都附上了") && words.contains("Axiom 查询 token") && !words.contains("跑了 42 秒") && !words.contains("帮我把登录页部署到预发"), msg=words)
}

///|
test "多选: a message not ticked fades, its box to tick does not" {
  let calls : Array[Made] = []
  let t = publish_core(calls, menu=true)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfpages.open_publish(publish_src.val.unwrap(), r, 7.0, picked=Some(9.0))
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(@sfpages.publish_message_left_out(6.0))
  // the boxes of those not ticked drawn whole, not faded with their messages
  // (how opaque the box of message `i` is drawn: its own and every box's it is in)
  let box_alpha = fn(i : Int) -> Double {
    let (x, y, w, h) = t.all(Checkbox, label="放进图片")[i].rect
    let laid = t.boxes()
    let by_index : Map[Int, @ui.Laid] = Map([])
    for b in laid {
      by_index[b.index] = b
    }
    let mut most = 0.0
    for b in laid {
      if (b.x - x).abs() < 0.5 && (b.y - y).abs() < 0.5 && (b.w - w).abs() < 0.5 && (b.h - h).abs() < 0.5 {
        let mut a = 1.0
        let mut at = Some(b)
        while at is Some(n) {
          a = a * n.opacity
          at = by_index.get(n.parent)
        }
        most = dmax(most, a)
      }
    }
    most
  }
  t.run_for(@ui.move_most_ms)
  assert_eq(box_alpha(1), 1.0)
}

///|
test "多选 from a message the preview does not hold: all of it ticked" {
  let calls : Array[Made] = []
  let t = publish_core(calls, menu=true)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfpages.open_publish(publish_src.val.unwrap(), r, 7.0, picked=Some(11.0))
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  assert_true(t.all(Checkbox, label="放进图片").iter().all(fn(n) { n.check == Some(On) }))
}

///|
/// Whether the picture's boxes to tick (one for each of fix_preview's four messages) stand in one column of their own
/// before its words, 12 short of where they start (its title's start, less the pictures' `reach` out in the margin
/// before them), not over a message; each on the middle of its message's first line: the viewer's own words, Ana's
/// name over hers.
fn ticks_before_words(t : @ui.Tester, reach : Double) -> Bool {
  let ticks = t.all(Checkbox, label="放进图片")
  guard ticks.length() == 4 &&
    t.rect_of("部署登录页") is Some((title_x, _, _, _)) &&
    t.rect_of("帮我把登录页部署到预发") is Some((_, mine_y, _, mine_h)) else {
    return false
  }
  let (x, _, w, _) = ticks[0].rect
  // (Ana's name on the page: past its boxes, not the chat's list's under it)
  guard t.words().iter().find_first(fn(n) { n.0 == "Ana" && n.1 > x }) is Some((_, _, ana_y, _, ana_h, _)) else {
    return false
  }
  let middle = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
  // (the viewer's own words' first line: however many it wraps to)
  let words_line = t.ctx().style_size(@sf.theme().t.words).1
  ticks.iter().all(fn(n) { n.rect.0 == x }) &&
  x + w + 12.0 <= title_x - reach &&
  (middle(ticks[0].rect) - (mine_y + dmin(mine_h, words_line) / 2.0)).abs() < 0.5 &&
  (middle(ticks[3].rect) - (ana_y + ana_h / 2.0)).abs() < 0.5
}

///|
/// Whether the viewer's message stands further along than someone else's in the picture shown (its bubble at the
/// column's end, as the chat's list has it).
fn picture_mine_at_end(t : @ui.Tester) -> Bool {
  // (where their words start: however wide each wraps to, the viewer's in its bubble further along)
  match (t.rect_of("帮我把登录页部署到预发，token 是 [已隐藏]"), t.rect_of("截图、日志和构建缓存都附上了")) {
    (Some((mx, _, _, _)), Some((ox, _, _, _))) => mx > ox
    _ => false
  }
}

///|
/// Where the chat's sheet's rows are well in view on a phone (844 high): a row under it is brought up to it.
let publish_fold : Double = 600.0

///|
/// The page over a chat with a page of HTML in it, as `publish_core` opens it, on the system `platform` numbers.
fn publish_viz_page(calls : Array[Made], platform? : Int = 2) -> @ui.Tester {
  let t = publish_core(calls, preview=fix_preview_viz, platform~, menu=true)
  open_publish_page()
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The page of HTML drawn on the sharing page: its view's id, it told loaded and drawn by its host.
fn publish_viz_drawn_up(t : @ui.Tester) -> Int raise {
  let mut view = 0
  for k, f in viz_frames {
    if k.has_prefix("publish/") {
      view = f.view.id()
    }
  }
  assert_true(view != 0, msg="no page of HTML on the sharing page")
  assert_true(t.view_said("{\"info\":{\"view\":\{view},\"state\":1,\"at\":[-1,0,0,0,0,0,0,0,0,0]}}"))
  t.frame()
  view
}

///|
/// A PNG `w` by `h`, all of one colour.
fn publish_blank_png(w : Int, h : Int) -> Bytes {
  let png = @pixels.PngRows::new(w, h)
  png.add(FixedArray::make(w * h * 4, b'\x80'), h)
  png.end()
}

///|
test "分享图片: a page of HTML its words place is drawn live on the page and, grabbed as the picture is asked for, in the picture" {
  let calls : Array[Made] = []
  let t = publish_viz_page(calls)
  let view = publish_viz_drawn_up(t)
  t.run_for(@ui.move_most_ms)
  let (bw, bh) = match view_rect(t, view) {
    Some((_, _, w, h)) => (w, h)
    None => fail("the page is not in sight")
  }
  t.click(Button, label="保存到相册")
  // not taken till its page is grabbed: first left to draw what comes in as it does
  t.run_for(@sfpages.publish_viz_settle_ms + 100.0)
  assert_eq(t.shots().length(), 0)
  let png = publish_blank_png((bw * 2.0).to_int(), (bh * 2.0).to_int())
  let drawn : Ref[(Double, Double)?] = Ref(None)
  t.each_frame(Some(fn() {
    for (src, w, h) in t.image_nodes() {
      if src.has_prefix("mem:publish/") { drawn.val = Some((w, h)) }
    }
  }))
  assert_true(t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"\{@codec.hex(png)}\"}"))
  t.run_for(@kit.presence_in_ms)
  t.each_frame(None)
  // The picture is wider than this screen, but its captured page keeps its original size and is not cropped.
  guard drawn.val is Some((iw, ih)) else { fail("no captured page in the picture") }
  assert_true((iw - bw).abs() <= 2.0 && (ih - bh).abs() <= 2.0, msg="the captured page changed size: \{Repr((iw, ih))} vs \{Repr((bw, bh))}")
  assert_eq(t.shots().length(), 1)
  // its card not in it: its grab where it was
  assert_true(!t.shots()[0].join("|").contains(".html"), msg=t.shots()[0].join("|"))
  assert_true(@sfpages.publish_has_still("f0"))
  assert_eq(t.kept().length(), 1)
}

///|
test "分享图片: a page of HTML whose grab fails, or is of a part of it, is its card in the picture" {
  for said in ["", "part"] {
    let calls : Array[Made] = []
    let t = publish_viz_page(calls)
    let view = publish_viz_drawn_up(t)
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="保存到相册")
    t.run_for(@sfpages.publish_viz_settle_ms + 100.0)
    if said == "" {
      assert_true(t.view_said("{\"view\":{\"view\":\{view},\"what\":2,\"text\":\"-1\"}}"))
    } else {
      assert_true(t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"\{@codec.hex(publish_blank_png(100, 10))}\"}"))
    }
    t.run_for(@kit.presence_in_ms)
    assert_eq(t.shots().length(), 1)
    assert_true(t.shots()[0].join("|").contains(".html"), msg=t.shots()[0].join("|"))
    assert_true(!@sfpages.publish_has_still("f0"))
  }
}

///|
test "分享图片: a page of HTML taken out of the picture is its card on the page, not grabbed" {
  let calls : Array[Made] = []
  let t = publish_viz_page(calls)
  let outs = t.all(Button, label="移出图片")
  assert_eq(outs.length(), 1)
  let (x, y, w, h) = outs[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfpages.publish_left_out("f0"))
  assert_true(t.find(".html") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  // (taken at once: nothing to wait for)
  assert_eq(t.shots().length(), 1)
  assert_true(!t.shots()[0].join("|").contains(".html"), msg=t.shots()[0].join("|"))
}

///|
test "分享图片: in a browser, which grabs no page, a page of HTML is its card on the page and in the picture" {
  let calls : Array[Made] = []
  let t = publish_viz_page(calls, platform=4)
  assert_true(t.find(".html") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(!viz_frames.keys().any(fn(k) { k.has_prefix("publish/") }))
  t.click(Button, label="复制图片")
  t.run_for(@kit.presence_in_ms)
  assert_eq(t.shots().length(), 1)
  assert_true(t.shots()[0].join("|").contains(".html"), msg=t.shots()[0].join("|"))
}
