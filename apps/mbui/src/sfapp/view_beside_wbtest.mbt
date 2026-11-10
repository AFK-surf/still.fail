// A file opened beside a chat (sfbase's viewer_tab.mbt): a press with the command key held (beside_held), a file's
// menu's 在侧边打开 and the whole window's 移到侧边 put it in a tab of the chat's side panel on 大屏; the tab shows what
// the whole window would, its 全屏 opens that, closing it lets go of what it read; on 小屏 the same press opens the
// whole window, and nothing offers beside.

///|
/// The first row's chat of the made-up core (MBUI_FIXTURE `mode`), in a window `w` by `h` of `platform`'s, at rest.
fn beside_tester(mode? : String = "chat", w? : Double = 1280.0, h? : Double = 800.0, platform? : Int = 0) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  beside_src.val = Some(src)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  nav_rested(t)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What the tester is over (beside_tester's).
let beside_src : Ref[Source?] = Ref(None)

///|
/// The chat's tabs' key (the core's `chatTabs`) of the first row's chat.
let beside_chat : String = "ws1/st1:s-c1"

///|
/// Where the chat's own compare.png is (the message's, not a tab's picture of it: the leftmost), scrolled up to it.
fn chat_picture(t : @ui.Tester) -> (Double, Double) raise {
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let at = t.locate("img:compare.png")
  if at.length() == 0 {
    fail("the chat's picture never on the screen")
  }
  let mut most = at[0]
  for p in at {
    if p.0 < most.0 {
      most = p
    }
  }
  most
}

///|
/// A press on (x, y) with the command key held (`mods`), let go of after.
fn press_held(t : @ui.Tester, x : Double, y : Double, mods : Int) -> Unit {
  t.hold_mods(mods)
  t.tap(x, y)
  t.hold_mods(0)
  t.run_for(@ui.move_most_ms)
}

///|
/// The tabs of files beside the chat (their keys: `view:[…]`), as its view has them.
fn view_tabs(t : @ui.Tester) -> Array[String] {
  ignore(t)
  match beside_src.val {
    Some(src) =>
      match @sfbase.view_of_chat(src, { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }).0 {
        Some(v) => v.tabs.open.filter(fn(k) { k.has_prefix("view:") })
        None => []
      }
    None => []
  }
}

///|
/// Where the tab's stage begins across (its tools' row's left), the file named `name` in front.
fn tab_left(t : @ui.Tester, name : String) -> Double raise {
  t.get(Toolbar, label=name).rect.0
}

///|
/// Whether `words` are drawn in the tab (right of its left edge), the file named `name` in front.
fn shown_beside(t : @ui.Tester, name : String, words : String) -> Bool raise {
  let left = tab_left(t, name)
  match t.find(words) {
    Some((x, _)) => x >= left
    None => false
  }
}

///|
/// The audit's faults of something of a file's tab drawn over another's room to be pressed (`apart:`, a node made in
/// viewer_tab.mbt).
fn tab_apart(t : @ui.Tester) -> Array[String] {
  t.audit().filter(fn(f) { f.has_prefix("apart:") && f.contains("viewer_tab.mbt") })
}

///|
/// The picture drawn in the tab (its middle in its stage, right of `left`, `wide` across), larger than a thumbnail: x,
/// y, w, h.
fn tab_drawn(t : @ui.Tester, left : Double, wide : Double) -> (Double, Double, Double, Double) raise {
  let drawn = t.drawn_images().filter(fn(i) { i[0] + i[2] / 2.0 >= left && i[0] + i[2] / 2.0 <= left + wide && i[2] > 100.0 })
  if drawn.length() == 0 {
    fail("no picture drawn in the tab: \{t.drawn_images().length()} drawn")
  }
  let i = drawn[drawn.length() - 1]
  (i[0], i[1], i[2], i[3])
}

///|
/// The size the picture of the file tab in front is its own (as decoded here: the Tester's, not the file's).
fn tab_natural(t : @ui.Tester) -> (Double, Double) raise {
  let tabs = view_tabs(t)
  guard tabs.length() > 0 && beside_src.val is Some(src) else { fail("no file's tab") }
  match @sfbase.tab_viewer(beside_chat, tabs[tabs.length() - 1]) {
    Some(vw) => vw.natural_size(src)
    None => fail("no viewer of the tab")
  }
}

///|
/// A made-up file of the chat's (sffixture's preview_files), by its name.
fn made_file(name : String) -> Attachment raise {
  for f in @sffixture.preview_files() {
    if f.0.name == name {
      return f.0
    }
  }
  fail("no made-up file \{name}")
}

///|
test "大屏: a press with ⌘ held on a message's picture opens it in a tab of the side panel, in front, nothing over the whole window; again, that tab to the front, never a second; a plain press opens the whole window" {
  let t = beside_tester()
  let (x, y) = chat_picture(t)
  press_held(t, x, y, @ui.mod_cmd)
  assert_true(@sfbase.viewer.get() is None, msg="nothing over the whole window")
  assert_eq(view_tabs(t).length(), 1)
  assert_eq(t.all(Tab, label="compare.png", selected=true).length(), 1, msg="its tab, in front")
  for f in t.audit() {
    println("audit: \{f}")
  }
  // another file beside it, in front; the picture pressed so again: its tab to the front, still one
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("说明.md"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Tab, label="说明.md", selected=true).length(), 1)
  let (x, y) = chat_picture(t)
  press_held(t, x, y, @ui.mod_cmd)
  assert_eq(t.all(Tab, label="compare.png").length(), 1, msg="never a second")
  assert_eq(t.all(Tab, label="compare.png", selected=true).length(), 1, msg="brought to the front")
  assert_eq(view_tabs(t).length(), 2)
  assert_true(@sfbase.viewer.get() is None)
  // a plain press: the whole window, as before
  let (x, y) = chat_picture(t)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.viewer.get() is Some(_), msg="the whole window's preview")
  assert_eq(view_tabs(t).length(), 2, msg="no tab more")
}

///|
test "大屏: each kind in a tab shows what the whole window would: Markdown's words, code, a table's cells, a picture drawn, a file of no kind told of with its download" {
  let t = beside_tester()
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("说明.md"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_true(shown_beside(t, "说明.md", "发布前要做的"), msg="Markdown's words")
  // (the reader's tools in the tab's row)
  assert_eq(t.all(Button, label=@sf.t("web-pages.drive.reader.contents")).length(), 1)
  for f in t.audit() {
    println("audit md: \{f}")
  }
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("list.ts"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_true(shown_beside(t, "list.ts", "export const estimate"), msg="code")
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("数据.csv"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_true(shown_beside(t, "数据.csv", "帧时间（毫秒）"), msg="a table's head")
  assert_true(shown_beside(t, "数据.csv", "0.57"), msg="a table's cell")
  // (预览 / 源码, as the whole window's bar has them)
  assert_true(t.find(@sf.t("web-main.preview.source")) is Some(_))
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("界面草图.png"), beside=true)
  t.run_for(@ui.move_most_ms)
  let (px, py, pw, ph) = t.get(Image, label="界面草图.png").rect
  let drawn = t.drawn_images().filter(fn(i) { i[0] >= px - 1.0 && i[1] >= py - 1.0 && i[0] + i[2] <= px + pw + 1.0 && i[1] + i[3] <= py + ph + 1.0 && i[2] > 100.0 })
  assert_true(drawn.length() > 0, msg="the picture drawn in its stage: \{t.drawn_images().length()} drawn")
  for f in t.audit() {
    println("audit image: \{f}")
  }
  assert_eq(tab_apart(t), [], msg="nothing of the tab's picture drawn over another's room to be pressed")
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("备份.bin"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_true(shown_beside(t, "备份.bin", @sf.t("web-main.preview.unsupported")), msg="told of")
  assert_true(t.all(Button, label=@sf.t("web-main.preview.download")).length() >= 1, msg="its download")
  // (its note takes no press: nothing of the tab's under the panel's edge)
  assert_eq(tab_apart(t), [], msg="nothing of the tab's drawn over another's room to be pressed")
  assert_eq(view_tabs(t).length(), 5)
  assert_true(@sfbase.viewer.get() is None)
}

///|
test "大屏: a picture's menu opens it beside; the whole window's 移到侧边 closes it for its tab; the tab's 全屏 opens the whole window, the tab staying" {
  let t = beside_tester()
  let (x, y) = chat_picture(t)
  t.right_click(x, y)
  t.draw()
  t.click(MenuItem, label=@sf.t("web-main.preview.openBeside"))
  t.run_for(@ui.move_most_ms)
  assert_eq(view_tabs(t).length(), 1)
  assert_true(@sfbase.viewer.get() is None)
  // closed; opened over the whole window; 移到侧边
  t.click(Button, label=@sf.t("web-pages.chat.close", args=[("name", "compare.png")]))
  t.run_for(@ui.move_most_ms)
  assert_eq(view_tabs(t).length(), 0)
  let (x, y) = chat_picture(t)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.viewer.get() is Some(_))
  t.click(Button, label=@sf.t("web-main.preview.moveBeside"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.viewer.get() is None, msg="the whole window closed")
  assert_eq(view_tabs(t).length(), 1, msg="its tab")
  // 全屏: the whole window over it, the tab staying
  t.click(Button, label=@sf.t("web-main.preview.fullWindow"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.viewer.get() is Some(_), msg="over the whole window")
  assert_eq(view_tabs(t).length(), 1, msg="the tab stays")
}

///|
test "大屏: a tab closed lets go of its viewer; a chat opened with a file's tab kept shows it with nothing pressed; Escape with it in front closes nothing" {
  let t = beside_tester(mode="chat-view-side")
  let tab = @sffixture.fixture_view_tab("chat-view-side")
  assert_true(shown_beside(t, "说明.md", "发布前要做的"), msg="shown as the chat opens")
  assert_true(@sfbase.tab_viewer_held(beside_chat, tab))
  for f in t.audit() {
    println("audit kept: \{f}")
  }
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_eq(view_tabs(t), [tab], msg="Escape closed nothing")
  assert_true(shown_beside(t, "说明.md", "发布前要做的"))
  t.click(Button, label=@sf.t("web-pages.chat.close", args=[("name", "说明.md")]))
  t.run_for(@ui.move_most_ms)
  assert_eq(view_tabs(t).length(), 0)
  assert_true(!@sfbase.tab_viewer_held(beside_chat, tab), msg="its viewer let go")
}

///|
test "大屏: a picture kept beside is drawn as the chat opens" {
  let t = beside_tester(mode="chat-view-side-image")
  let (px, py, pw, ph) = t.get(Image, label="界面草图.png").rect
  let drawn = t.drawn_images().filter(fn(i) { i[0] >= px - 1.0 && i[1] >= py - 1.0 && i[0] + i[2] <= px + pw + 1.0 && i[1] + i[3] <= py + ph + 1.0 && i[2] > 100.0 })
  assert_true(drawn.length() > 0, msg="the picture drawn: \{t.drawn_images().length()} drawn")
}

///|
test "小屏: a press with Ctrl held opens the whole window, and a picture's menu offers nothing beside" {
  let t = beside_tester(w=390.0, h=844.0, platform=2)
  let (x, y) = chat_picture(t)
  t.right_click(x, y)
  t.draw()
  assert_eq(t.all(MenuItem, label=@sf.t("web-main.preview.openBeside")).length(), 0, msg="no 在侧边打开")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let (x, y) = chat_picture(t)
  press_held(t, x, y, @ui.mod_ctrl)
  assert_true(@sfbase.viewer.get() is Some(_), msg="the whole window")
  assert_eq(view_tabs(t).length(), 0)
}

///|
test "大屏: Markdown in a tab 360 wide reads in one column there, its 目录 and 排版 opened from the tab's tools over its stage, closed again by them" {
  let t = beside_tester(mode="chat-view-side", w=1100.0)
  let (left, _, wide, _) = t.get(Toolbar, label="说明.md").rect
  assert_true(wide >= 359.0 && wide <= 361.0, msg="the tab \{wide} wide")
  assert_true(shown_beside(t, "说明.md", "发布前要做的"), msg="its words")
  // (no bar of the reader's own in the tab: its tools are the tab's, once)
  assert_eq(t.all(Button, label=@sf.t("web-pages.drive.reader.contents")).length(), 1)
  t.click(Button, label=@sf.t("web-pages.drive.reader.contents"))
  t.run_for(@ui.move_most_ms)
  match t.find(@sf.t("web-pages.drive.reader.findPlaceholder")) {
    Some((x, _)) => assert_true(x >= left && x <= left + wide, msg="目录 over the tab's stage: \{x}")
    None => fail("目录 not open")
  }
  t.click(Button, label=@sf.t("web-pages.drive.reader.contents"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-pages.drive.reader.findPlaceholder")) is None, msg="closed by its tool")
  t.click(Button, label=@sf.t("web-pages.drive.reader.layout"))
  t.run_for(@ui.move_most_ms)
  match t.find(@sf.t("web-pages.drive.reader.layout")) {
    Some((x, _)) => assert_true(x >= left && x <= left + wide, msg="排版 over the tab's stage: \{x}")
    None => fail("排版 not open")
  }
  for f in t.audit() {
    println("audit 360: \{f}")
  }
  t.click(Button, label=@sf.t("web-pages.drive.reader.layout"))
  t.run_for(@ui.move_most_ms)
  let key = @sfbase.tab_viewer(beside_chat, @sffixture.fixture_view_tab("chat-view-side")).unwrap().read_key()
  assert_true(@sf.reader_panel_of(key) == @sf.ReaderPanel::NoPanel, msg="排版 closed by its tool")
}

///|
test "大屏: a tab's 排版 is the tab's: another tab brought to the front takes it off the screen" {
  let t = beside_tester(mode="chat-view-side")
  let margin = @sf.t("web-pages.drive.reader.margin")
  t.click(Button, label=@sf.t("web-pages.drive.reader.layout"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(margin) is Some(_), msg="排版 open")
  // 任务 beside the chat, in front
  @sfdesk.side_change(beside_src.val.unwrap(), { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }, "open", Some("jobs"))
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Tab, label="说明.md", selected=true).length(), 0, msg="another tab in front")
  assert_true(t.find(margin) is None, msg="排版 gone with its tab")
  assert_eq(t.all(Slider, label=@sf.t("web-pages.drive.reader.lines")).length(), 0, msg="its controls gone with its tab")
  // the file's tab to the front again: its 排版 there again, within its stage
  let within = fn(what : String) raise {
    let (left, _, wide, _) = t.get(Toolbar, label="说明.md").rect
    let (x, _, w, _) = t.get(Slider, label=@sf.t("web-pages.drive.reader.lines")).rect
    assert_true(x >= left && x + w <= left + wide + 0.5, msg="\{what}: its controls \{x}..\{x + w} within the tab's \{left}..\{left + wide}")
  }
  t.click(Tab, label="说明.md")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(margin) is Some(_), msg="排版 there again")
  within("back in front")
  // the window made larger: it follows the stage
  t.resize(1440.0, 900.0)
  t.run_for(@ui.move_most_ms)
  within("the window larger")
  // closed by its own ×
  t.click(Button, label=@sf.t("common.close"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(margin) is None, msg="closed by its ×")
}

///|
test "大屏: a file kept only while the app runs (a draft's: a Mermaid picture, an attachment waiting) asked beside opens the whole window, no tab, and its bar offers no 移到侧边" {
  let t = beside_tester()
  let svg = b"<svg xmlns='http://www.w3.org/2000/svg' width='40' height='30'><rect width='40' height='30' fill='red'/></svg>"
  let file = fn(path : String) -> Attachment {
    {
      name: "Mermaid.svg",
      path,
      size: svg.length().to_double(),
      width: 40.0,
      height: 30.0,
      thumbhash: "",
      owner: "",
      upload: "",
      duration: 0.0,
      frames: 0,
      held: false,
    }
  }
  @sfbase.keep_read("ws1/st1//draft:mermaid/0123456789abcdef", svg)
  @sfbase.open_preview("ws1/st1", "", file("draft:mermaid/0123456789abcdef"), beside=true)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.viewer.get() is Some(_), msg="the whole window's preview")
  assert_eq(view_tabs(t).length(), 0, msg="no tab")
  assert_eq(t.all(Button, label=@sf.t("web-main.preview.moveBeside")).length(), 0, msg="no 移到侧边")
  // (one read again from where it lies: 移到侧边 on its bar)
  @sfbase.keep_read("ws1/st1//uploads/fx/Mermaid.svg", svg)
  @sfbase.open_preview("ws1/st1", "", file("uploads/fx/Mermaid.svg"), beside=false)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Button, label=@sf.t("web-main.preview.moveBeside")).length(), 1, msg="移到侧边 for a file kept")
}

///|
test "大屏: a picture in a tab is fitted as over the whole window: one larger than its stage 12 in from its nearer edges, one smaller at its own size in its middle" {
  // larger: wider than a stage 373 wide (its own size the Tester's decode's)
  let t = beside_tester()
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("界面草图.png"), beside=true)
  t.run_for(@ui.move_most_ms)
  let (left, _, wide, _) = t.get(Toolbar, label="界面草图.png").rect
  // (the stage's middle: the middle of the room the hand takes it in, as far in from each of its edges)
  let middle = fn() raise {
    let (ax, ay, aw, ah) = t.get(Image, label="界面草图.png").rect
    (ax + aw / 2.0, ay + ah / 2.0)
  }
  let (nw, nh) = tab_natural(t)
  assert_true(nw > wide, msg="its own \{nw} × \{nh}, wider than the stage \{wide}")
  let (x, y, w, h) = tab_drawn(t, left, wide)
  assert_true((x - (left + 12.0)).abs() <= 1.0 && (x + w - (left + wide - 12.0)).abs() <= 1.0, msg="12 in from its sides: \{x}..\{x + w} in \{left}..\{left + wide}")
  assert_true((h / w - nh / nw).abs() < 0.01, msg="as tall for as wide: \{w} × \{h}, its own \{nw} × \{nh}")
  assert_true((y + h / 2.0 - middle().1).abs() <= 1.0, msg="in its middle: \{y + h / 2.0}, the stage's \{middle().1}")
  assert_eq(tab_apart(t), [])
  // smaller: the same in a window wide enough for a stage wider than it and its margins
  let t = beside_tester(w=2400.0, h=1000.0)
  @sfbase.open_preview("ws1/st1", "s-c1", made_file("界面草图.png"), beside=true)
  t.run_for(@ui.move_most_ms)
  let (left, _, wide, _) = t.get(Toolbar, label="界面草图.png").rect
  let (nw, nh) = tab_natural(t)
  assert_true(wide > nw + 24.0, msg="the stage \{wide} wide, the picture \{nw}")
  let (x, y, w, h) = tab_drawn(t, left, wide)
  assert_true((w - nw).abs() <= 1.0 && (h - nh).abs() <= 1.0, msg="at its own size: \{w} × \{h}, its own \{nw} × \{nh}")
  assert_true((x + w / 2.0 - (left + wide / 2.0)).abs() <= 1.0, msg="in its middle across: \{x + w / 2.0}")
  let (ax, ay, aw, ah) = t.get(Image, label="界面草图.png").rect
  assert_true((x + w / 2.0 - (ax + aw / 2.0)).abs() <= 1.0 && (y + h / 2.0 - (ay + ah / 2.0)).abs() <= 1.0, msg="in its middle: \{x + w / 2.0}, \{y + h / 2.0}")
  // a double press on its middle: zoomed in round it (its middle staying), and back
  let (cx, cy) = (x + w / 2.0, y + h / 2.0)
  t.tap(cx, cy)
  t.advance(@ui.double_tap_ms / 2.0)
  t.tap(cx, cy)
  t.run_for(@ui.move_most_ms)
  let (x2, y2, w2, h2) = tab_drawn(t, left, wide)
  assert_true(w2 > w * 1.5, msg="zoomed in: \{w2} wide")
  assert_true((x2 + w2 / 2.0 - cx).abs() <= 1.0 && (y2 + h2 / 2.0 - cy).abs() <= 1.0, msg="round where it was pressed: \{x2 + w2 / 2.0}, \{y2 + h2 / 2.0}")
}

///|
test "大屏: the whole window's picture offers 移到侧边 with nothing pressed; the window made 小屏-wide it goes, wide again it is back" {
  let t = beside_tester(mode="chat-preview-image")
  let moves = fn() { t.all(Button, label=@sf.t("web-main.preview.moveBeside")).length() }
  assert_true(@sfbase.viewer.get() is Some(_), msg="the whole window's preview")
  assert_eq(moves(), 1, msg="移到侧边 offered")
  t.resize(390.0, 844.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(moves(), 0, msg="not on 小屏")
  t.resize(1280.0, 800.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(moves(), 1, msg="offered again")
}
