// The chat's things on 小屏 (open_things): a sheet whose body is nodes (@sfpages.things_node), held to the same page
// with its old body (@sfpages.things_body, the wide side pane's still) in the host's sheet of the same panel: where each
// of their words is drawn, the kinds' choice pressed where it is drawn, and 在对话中查看 closing it.

///|
/// A chat of the made-up core's, open on a phone.
fn things_chat() -> (@ui.Tester, Source, ChatRef) {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  (t, src, r)
}

///|
/// The chat's things with their old body in the host's sheet (open_things's panel as it was).
fn open_things_old(src : Source, r : ChatRef) -> Unit {
  @sf.panel(tr("web-main.things.title"), from=Unanchored, tall=0.8, grows=true, fn(c, close) {
    @sfpages.things_body(c, src, r, 7.0, true, fn(seq) {
      close()
      go_to(r, seq)
    })
  })
}

///|
/// The words drawn in the window's lower `share` (where a sheet that tall is): each, where it is (to half a point) and how
/// big, in the order of where they are.
fn words_below(t : @ui.Tester, share : Double) -> Array[(String, Double, Double, Double, Double)] {
  let half = fn(x : Double) { (x * 2.0).round() / 2.0 }
  let top = 844.0 * (1.0 - share)
  let out = t.words().filter(fn(w) { w.2 >= top && w.5 > 0.0 }).map(fn(w) { (w.0, half(w.1), half(w.2), half(w.3), half(w.4)) })
  out.sort_by(fn(a, b) { if a.2 != b.2 { a.2.compare(b.2) } else if a.1 != b.1 { a.1.compare(b.1) } else { a.0.compare(b.0) } })
  out
}

///|
/// How much of the window the things' sheet takes (open_things's `tall`).
let things_share : Double = 0.8

///|
/// The things' sheet opened by `open` on `kind`: the words it shows; then its 文件 pressed where it is drawn, the words it
/// shows then; closed by Escape and gone.
fn things_seen(t : @ui.Tester, r : ChatRef, open : () -> Unit) -> (Array[(String, Double, Double, Double, Double)], Array[(String, Double, Double, Double, Double)]) raise {
  @sfpages.things_choose(r, "media")
  open()
  t.run_for(sheet_way_ms(t))
  let first = words_below(t, things_share)
  t.tap_text("文件 2")
  t.run_for(@ui.move_most_ms)
  let files = words_below(t, things_share)
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  (first, files)
}

///|
test "小屏: the chat's things, a sheet whose body is nodes: each of its words where the host's sheet of its old body has it; 文件 pressed where it is drawn: its files, where the old one's are" {
  let (t, src, r) = things_chat()
  let (old_first, old_files) = things_seen(t, r, fn() { open_things_old(src, r) })
  let (first, files) = things_seen(t, r, fn() { open_things(src, r, 7.0) })
  assert_true(first.iter().any(fn(w) { w.0 == "媒体 4" }), msg="the kinds' choice")
  assert_eq(first, old_first)
  assert_true(files.iter().any(fn(w) { w.0 == "build.log" }), msg="its files")
  assert_false(files.iter().any(fn(w) { w.0 == "列表高度改前改后" }), msg="its pictures' words gone")
  assert_eq(files, old_files)
}

///|
test "小屏: the chat's things whose body is nodes: a file's 在对话中查看 closes the sheet, the chat at its message; the field finds among its kind's" {
  let (t, src, r) = things_chat()
  @sfpages.things_choose(r, "files")
  open_things(src, r, 7.0)
  t.run_for(sheet_way_ms(t))
  assert_true(t.find("性能报告.pdf") is Some(_), msg="its files")
  // (the field: what is typed finds among them)
  t.tap_text(@sf.t("web-main.things.find"))
  t.type_text("build")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("build.log") is Some(_), msg="found")
  assert_true(t.find("性能报告.pdf") is None, msg="the rest not")
  let shows = t.all(Button, label=@sf.t("web-main.things.show")).filter(fn(s) { s.rect.1 >= 844.0 * (1.0 - things_share) })
  assert_true(shows.length() > 0, msg="在对话中查看 on its row")
  let (x, y, w, h) = shows[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
}

///|
/// What a finger held on a file's row (`name`) of the things' sheet opened by `open` does, as it is held, let go and
/// its menu closed: what it is felt as (the haptics, from the hold on), where the row is drawn lit (the theme's Hover,
/// to half a point) while it is held and while its menu is open once let go, whether its menu opened, and the sheet
/// stepped back under it: where the row's words were drawn at rest, where they are drawn then and what of the sheet's
/// scrim is drawn over them.
fn things_held_seen(t : @ui.Tester, r : ChatRef, name : String, open : () -> Unit) -> (Array[@ui.Haptic], Array[(Double, Double, Double, Double)], Array[(Double, Double, Double, Double)], Bool, (Double, Array[(Double, Double)], Array[(Double, Double, Double, Double)])) raise {
  @sfpages.things_choose(r, "files")
  open()
  t.run_for(sheet_way_ms(t))
  let at = t.words().filter(fn(w) { w.0 == name && w.2 >= 844.0 * (1.0 - things_share) })
  guard at is [(_, x, y, w, h, _), ..] else { fail("\{name}: not drawn") }
  let (px, py) = (x + w / 2.0, y + h / 2.0)
  let half = fn(v : Double) { (v * 2.0).round() / 2.0 }
  let lit = fn() {
    let hover = @ui.tree_theme().color(Hover)
    t
    .drawn_rects()
    .filter(fn(b) { b.4 == hover && b.0 <= px && px <= b.0 + b.2 && b.1 <= py && py <= b.1 + b.3 })
    .map(fn(b) { (half(b.0), half(b.1), half(b.2), half(b.3)) })
  }
  let felt = t.haptics().length()
  t.press_at(px, py)
  t.run_for(@ui.long_press_ms + @ui.move_most_ms)
  let held = lit()
  t.release(px, py)
  t.run_for(@ui.move_most_ms)
  let menu_lit = lit()
  // (its menu's 在对话中查看 in words: the row's own is its icon alone)
  let menu = t.words().iter().any(fn(w) { w.0 == @sf.t("web-main.things.show") && w.5 > 0.0 })
  let haptics = t.haptics()[felt:].to_owned()
  // (the sheet under the menu: pushed back, its row's words where they are then, and dimmed, the scrim drawn over them)
  let pushed = t.words().filter(fn(w) { w.0 == name }).map(fn(w) { (half(w.1), half(w.2)) })
  let dimmed = match pushed {
    [(wx, wy), ..] =>
      t
      .drawn_rects()
      .filter(fn(b) { b.4 == @sf.sheet_scrim && b.0 <= wx && wx <= b.0 + b.2 && b.1 <= wy && wy <= b.1 + b.3 })
      .map(fn(b) { (half(b.0), half(b.1), half(b.2), half(b.3)) })
    [] => []
  }
  // (its menu closed, then the sheet)
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  (haptics, held, menu_lit, menu, (half(y), pushed, dimmed))
}

///|
test "小屏: the chat's things whose body is nodes: a file's row held by a finger is felt, lit and its menu opened as the old body's is, held and with its menu open, the sheet behind it pushed back and dimmed" {
  let (t, src, r) = things_chat()
  let old = things_held_seen(t, r, "build.log", fn() { open_things_old(src, r) })
  let now = things_held_seen(t, r, "build.log", fn() { open_things(src, r, 7.0) })
  assert_true(old.3, msg="the old one's menu opened")
  assert_eq(now.0, old.0, msg="felt")
  assert_eq(now.1, old.1, msg="lit while held")
  assert_eq(now.2, old.2, msg="lit while its menu is open")
  assert_eq(now.3, old.3, msg="its menu")
  // (the sheet behind it pushed back and dimmed: its row up from where it was, the scrim over it)
  assert_true(old.4.1.length() > 0 && old.4.1[0].1 < old.4.0, msg="the old one pushed back: \{Repr(old.4)}")
  assert_true(old.4.2.length() > 1, msg="the old one dimmed over itself: \{Repr(old.4)}")
  assert_eq(now.4, old.4, msg="pushed back and dimmed")
}

///|
/// The first frames drawn here (grab_first's pictures, `mem:pv-first/…`), each where it is drawn (to half a point).
fn things_firsts_drawn(t : @ui.Tester) -> Array[(String, Double, Double, Double, Double)] {
  let half = fn(v : Double) { (v * 2.0).round() / 2.0 }
  t
  .drawn_instances()
  .filter_map(fn(i) {
    let k = if i[5] == 4.0 && i[11] > 0.0 { t.image_src(i[20].to_int()) } else { "" }
    if k.has_prefix("mem:pv-first/") {
      Some((k, half(i[0]), half(i[1]), half(i[2]), half(i[3])))
    } else {
      None
    }
  })
}

///|
/// The things' sheet opened by `open` on its pictures and videos where the station made no still of its video: the
/// grabs of a frame its players were asked (by view: `control N 21 …`), then, the first answered with `frame`, the
/// first frames drawn; closed.
fn things_first_seen(t : @ui.Tester, r : ChatRef, frame : Bytes, open : () -> Unit) -> (Int, Array[(String, Double, Double, Double, Double)]) raise {
  @sfbase.pv_first.clear()
  @sfpages.things_choose(r, "media")
  let before = t.views().length()
  open()
  t.run_for(sheet_way_ms(t))
  let grabs = t
    .views()[before:]
    .to_owned()
    .filter_map(fn(l) {
      match l.split(" ").map(fn(p) { p.to_owned() }).to_array() {
        ["control", view, "21", ..] => Some(view)
        _ => None
      }
    })
  guard grabs is [view, ..] else { fail("no frame asked of a player: \{Repr(t.views())}") }
  assert_true(t.view_said("{\"still\":{\"view\":\{view}},\"b\":\"\{hex_bytes(frame)}\"}"), msg="answered")
  t.run_for(@ui.move_most_ms)
  let drawn = things_firsts_drawn(t)
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  (grabs.length(), drawn)
}

///|
test "小屏: the chat's things whose body is nodes: a video the station made no still of shows its first frame drawn here, as the old body's tile does: a frame asked of a player of it, shown where the old one's is once the host answers" {
  let (t, base, r) = things_chat()
  let src : Source = { ..base, poster: fn(_, _, _) { "!" } }
  let frame = fixture_file_png("演示录屏.mp4")
  let old = things_first_seen(t, r, frame, fn() { open_things_old(src, r) })
  let now = things_first_seen(t, r, frame, fn() { open_things(src, r, 7.0) })
  assert_true(old.0 > 0 && old.1.length() > 0, msg="the old one's first frame: \{Repr(old)}")
  assert_eq(now, old)
}

///|
/// The chat's things open on a phone used with a mouse (an iPad's, a narrow window's): what shows a link's card. Its
/// pictures (`link.preview.picture`) as `pictures` has them by the link's address and which, its type PNG.
fn things_chat_mouse(previews? : Map[String, Json] = {}, pictures? : Map[String, Bytes] = {}) -> (@ui.Tester, Source, ChatRef) {
  new_run()
  let base = fixture("chat")
  // (a link's card as `previews` has it by its address, where it has one: the made-up core's otherwise)
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      match previews.get(text(Some(Json::object(params)), "url")) {
        Some(v) if name == "linkPreview" => { ..got, value: Some(v) }
        _ => got
      }
    },
    read_bytes: fn(name, params, done) {
      match pictures.get(text(Some(params), "url") + "\u{1}" + text(Some(params), "which")) {
        Some(b) if name == "link.preview.picture" => done(Ok(({ "type": "image/png" }, b)))
        _ => (base.read_bytes)(name, params, done)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2, pointing=Mouse)
  t.run_for(@ui.move_most_ms)
  (t, src, r)
}

///|
/// The things' sheet opened by `open` on `kind`, the pointer rested on its first row (`name`): the words its card
/// shows (those drawn then and not before, each where it is, to half a point, in the order of where they are); then
/// the pointer gone off it: whether the card went with it.
fn things_peek_seen(t : @ui.Tester, r : ChatRef, kind : String, name : String, open : () -> Unit) -> (Array[(String, Double, Double, Double, Double)], Bool) raise {
  @sfpages.things_choose(r, kind)
  open()
  t.run_for(sheet_way_ms(t))
  let before = words_below(t, 1.0)
  let at = t.words().filter(fn(w) { w.0 == name && w.2 >= 844.0 * (1.0 - things_share) })
  guard at is [(_, x, y, w, h, _), ..] else { fail("\{name}: not drawn: \{Repr(before)}") }
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
  let card = words_below(t, 1.0).filter(fn(w) { !before.contains(w) })
  // (off the row, onto the sheet's head: gone)
  t.move_to(x + w / 2.0, 844.0 * (1.0 - things_share))
  t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
  let gone = words_below(t, 1.0).filter(fn(w) { !before.contains(w) }).length() == 0
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_false(@sf.presenting(), msg="closed")
  (card, gone)
}

///|
test "小屏 with a mouse: the chat's things whose body is nodes: a link's row and a pull request's pointed at show its card (web_peek) where the old body's do, each of its words, and it goes as the pointer leaves" {
  let (t, src, r) = things_chat_mouse()
  for k in [("links", "列表滚动的性能数据"), ("pulls", "首页列表按天分组")] {
    let (kind, name) = k
    let old = things_peek_seen(t, r, kind, name, fn() { open_things_old(src, r) })
    let now = things_peek_seen(t, r, kind, name, fn() { open_things(src, r, 7.0) })
    assert_true(old.0.length() > 0 && old.1, msg="\{kind}: the old one's card, gone after: \{Repr(old)}")
    assert_eq(now, old, msg="\{kind}: \{Repr(now)}, the old one's \{Repr(old)}")
  }
}

///|
/// The card of the things' sheet's first row of `kind` (`name`) opened by `open`, the pointer onto it: what `seen`
/// sees of it (once it has had the time to open), then gone off it and the sheet closed.
fn things_card_seen(t : @ui.Tester, r : ChatRef, kind : String, name : String, open : () -> Unit, seen : (Double, Double) -> String) -> String raise {
  @sfpages.things_choose(r, kind)
  open()
  t.run_for(sheet_way_ms(t))
  let at = t.words().filter(fn(w) { w.0 == name && w.2 >= 844.0 * (1.0 - things_share) })
  guard at is [(_, x, y, w, h, _), ..] else { fail("\{name}: not drawn") }
  let (px, py) = (x + w / 2.0, y + h / 2.0)
  t.move_to(px, py)
  t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
  let out = seen(px, py)
  t.move_to(px, 844.0 * (1.0 - things_share))
  t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
  // (a card as tall as the window is still under the pointer: Escape shuts it first, then the sheet)
  for _ in 0..<2 {
    if @sf.presenting() {
      t.key(@ui.key_escape)
      t.run_for(sheet_way_ms(t))
    }
  }
  assert_false(@sf.presenting(), msg="closed")
  out
}

///|
/// Where each word drawn in the window is (to half a point), in the order of where they are: what a card shows, by
/// those drawn and not before.
fn things_words_drawn(t : @ui.Tester) -> Array[(String, Double, Double, Double, Double)] {
  words_below(t, 1.0).filter(fn(w) { w.2 >= 0.0 && w.2 < 844.0 })
}

///|
test "小屏 with a mouse: a link's card whose row is nodes waits for the hand to carry no press, as the old body's: none while a button is held down elsewhere and the pointer rests on its row; shown its time after it is let go" {
  let (t, src, r) = things_chat_mouse()
  let seen = fn(open : () -> Unit) -> (Bool, Bool) raise {
    @sfpages.things_choose(r, "links")
    open()
    t.run_for(sheet_way_ms(t))
    let at = t.words().filter(fn(w) { w.0 == "列表滚动的性能数据" && w.2 >= 844.0 * (1.0 - things_share) })
    guard at is [(_, x, y, w, h, _), ..] else { fail("the link's row: not drawn") }
    // (held down in the sheet's field, carried onto the row, rested there)
    let title = t.words().filter(fn(w) { w.0 == @sf.t("web-main.things.find") })
    guard title is [(_, tx, ty, tw, th, _), ..] else { fail("the sheet's field: not drawn") }
    t.press_at(tx + tw / 2.0, ty + th / 2.0)
    t.move_to(x + w / 2.0, y + h / 2.0)
    t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
    let held = t.find(@sf.t("common.link.copy")) is Some(_)
    t.release(x + w / 2.0, y + h / 2.0)
    t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
    let after = t.find(@sf.t("common.link.copy")) is Some(_)
    t.move_to(x + w / 2.0, 844.0 * (1.0 - things_share))
    t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
    t.key(@ui.key_escape)
    t.run_for(sheet_way_ms(t))
    (held, after)
  }
  let old = seen(fn() { open_things_old(src, r) })
  let now = seen(fn() { open_things(src, r, 7.0) })
  assert_eq(old, (false, true), msg="the old one's")
  assert_eq(now, old)
}

///|
/// A page's icon not square (the made-up still of 演示录屏.mp4, 16:9), as the core answers it (`link.preview.picture`):
/// what its card's square holds.
fn things_wide_icon() -> Bytes {
  fixture_file_png("演示录屏.mp4")
}

///|
test "小屏 with a mouse: a link's card whose row is nodes holds a page's icon not square in its square whole, as the old body's (FitContain): drawn where the old one's is, as big" {
  let page : Json = {
    "kind": "page",
    "url": "https://example.com/bench/list",
    "title": "列表滚动的性能数据",
    "site": "Example",
    "icon": "wide-icon",
  }
  let (t, src, r) = things_chat_mouse(previews={ "https://example.com/bench/list": page }, pictures={
    "https://example.com/bench/list\u{1}icon": things_wide_icon(),
  })
  // (its image's key, once its card asked it)
  let key = fn() { @sfbase.link_picture(src, r.station, "https://example.com/bench/list", Some(page), "icon") }
  let drawn = fn(_x : Double, _y : Double) { media_drawn(t, key()).map(fn(b) { "\{@ui.rect_text(b)}" }).join(" ") }
  let old = things_card_seen(t, r, "links", "列表滚动的性能数据", fn() { open_things_old(src, r) }, drawn)
  let now = things_card_seen(t, r, "links", "列表滚动的性能数据", fn() { open_things(src, r, 7.0) }, drawn)
  assert_true(old != "", msg="the old one's icon")
  assert_eq(now, old)
}

///|
/// An issue with more labels than a card as tall as the window holds (the test's).
let things_many_labels : Int = 120

///|
/// How far the wheel scrolls a card (points).
let things_card_wheel : Double = 300.0

///|
test "小屏 with a mouse: a link's card whose row is nodes taller than the window scrolls in it, as the old body's (in_room): its words where the old one's are, then wheeled on, where the old one's go" {
  let issue : Json = {
    "kind": "github_issue",
    "url": "https://github.com/acme/shop/pull/128",
    "repository": "acme/shop",
    "number": 128,
    "title": "首页列表按天分组",
    "state": "open",
    "author": { "login": "lin" },
    "labels": Json::array(Array::makei(things_many_labels, fn(i) { Json::string("label \{i}") })),
    "time": { "updatedAt": { "at": 0, "ago": "3 小时前", "full": "10/26 09:00", "until": "", "past": true } },
  }
  let (t, src, r) = things_chat_mouse(previews={ "https://github.com/acme/shop/pull/128": issue })
  let seen = fn(open : () -> Unit) -> String raise {
    things_card_seen(t, r, "pulls", "首页列表按天分组", open, fn(_, _) {
      let shown = things_words_drawn(t).filter(fn(w) { w.0.has_prefix("label ") })
      // (wheeled on over the card, at its middle: its first label's line, as the card has it)
      let (lx, ly) = match shown {
        [(_, x, y, w, h), ..] => (x + w / 2.0, y + h / 2.0)
        _ => (0.0, 0.0)
      }
      t.move_to(lx, ly)
      t.wheel(lx, ly, things_card_wheel)
      t.run_for(@ui.move_most_ms)
      let wheeled = things_words_drawn(t).filter(fn(w) { w.0.has_prefix("label ") })
      "\{@ui.list_text(shown.map(fn(w) { "(\{w.0}, \{w.1}, \{w.2}, \{w.3}, \{w.4})" }))}\n\{@ui.list_text(wheeled.map(fn(w) { "(\{w.0}, \{w.1}, \{w.2}, \{w.3}, \{w.4})" }))}"
    })
  }
  let old = seen(fn() { open_things_old(src, r) })
  let now = seen(fn() { open_things(src, r, 7.0) })
  assert_true(old.contains("label 0"), msg="the old one's card")
  assert_eq(now, old)
}

///|
test "小屏 with a mouse: a link's card whose row is nodes, its address copied, says 已复制 as it is shown again within copied_ms, as the old body's (by the link); then 复制链接" {
  let (t, src, r) = things_chat_mouse()
  let seen = fn(open : () -> Unit) -> (Bool, Bool) raise {
    @sfpages.things_choose(r, "links")
    open()
    t.run_for(sheet_way_ms(t))
    let at = t.words().filter(fn(w) { w.0 == "列表滚动的性能数据" && w.2 >= 844.0 * (1.0 - things_share) })
    guard at is [(_, x, y, w, h, _), ..] else { fail("the link's row: not drawn") }
    let (px, py) = (x + w / 2.0, y + h / 2.0)
    t.move_to(px, py)
    t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
    guard t.all(Button, label=@sf.t("common.link.copy")) is [b, ..] else { fail("its copy: not drawn") }
    let (bx, by, bw, bh) = b.rect
    t.move_to(bx + bw / 2.0, by + bh / 2.0)
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    // (off the card and the row: gone; back on the row: shown again)
    t.move_to(px, 844.0 * (1.0 - things_share))
    t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
    t.move_to(px, py)
    t.run_for(@sfpages.hover_open_ms + @ui.move_most_ms)
    let again = t.find(@sf.t("common.copied")) is Some(_)
    t.run_for(@sf.copied_ms)
    let after = t.find(@sf.t("common.link.copy")) is Some(_)
    t.move_to(px, 844.0 * (1.0 - things_share))
    t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
    t.key(@ui.key_escape)
    t.run_for(sheet_way_ms(t))
    (again, after)
  }
  let old = seen(fn() { open_things_old(src, r) })
  let now = seen(fn() { open_things(src, r, 7.0) })
  assert_eq(old, (true, true), msg="the old one's")
  assert_eq(now, old)
}

///|
test "小屏 with a mouse: a link's card in the chat's things (web_peek_node): the pointer over its ground is the arrow (@sf.ground_node)" {
  let (t, src, r) = things_chat_mouse()
  let seen = fn(_px : Double, _py : Double) {
    // (the card: the last group read out, drawn over all of the window, as wide as a card at least)
    match t.semantics().filter(fn(s) { s.role == Group && !s.hidden && s.rect.2 >= 200.0 }).last() {
      Some(c) => {
        let (x, y, w, h) = c.rect
        [(x + 3.0, y + h / 2.0), (x + w / 2.0, y + 3.0), (x + w / 2.0, y + h - 3.0), (x + w - 3.0, y + h / 2.0)]
        .map(fn(p) {
          t.move_to(p.0, p.1)
          t.run_for(@ui.move_most_ms)
          "\{t.cursor()}"
        })
        .join(" ") +
        " \{Repr(c.rect)}"
      }
      None => "none"
    }
  }
  let got = things_card_seen(t, r, "links", "列表滚动的性能数据", fn() { open_things(src, r, 7.0) }, seen)
  assert_true(got.has_prefix("Arrow Arrow Arrow Arrow "), msg=got)
}
