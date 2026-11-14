// The reader's layout (排版) as nodes of the window's tree (src/sf reader_layout_node.mbt), held to where the old panel
// drew it (desk_layout in the host's sheet on 小屏, in the panel docked at the right on a wide window: its words, its
// controls' places and their values as read out, recorded from the old body on main as of 53f883b00d; the size it
// starts at 16 since #3116), then each control pressed where it is drawn and what it changes; closed by Escape and by its close.

///|
/// The words drawn where `inside` says, each where it is (to half a point) and how big, in the order of where they are.
fn layout_words(t : @ui.Tester, inside : (Double, Double) -> Bool) -> Array[(String, Double, Double, Double, Double)] {
  let half = fn(x : Double) { (x * 2.0).round() / 2.0 }
  let out = t.words().filter(fn(w) { inside(w.1, w.2) && w.5 > 0.0 }).map(fn(w) { (w.0, half(w.1), half(w.2), half(w.3), half(w.4)) })
  out.sort_by(fn(a, b) { if a.2 != b.2 { a.2.compare(b.2) } else if a.1 != b.1 { a.1.compare(b.1) } else { a.0.compare(b.0) } })
  out
}

///|
/// Where the control of `role` named `label` is read out to be (to half a point), and its value.
fn layout_control(t : @ui.Tester, role : @ui.Role, label : String) -> ((Double, Double, Double, Double), String) raise {
  let half = fn(x : Double) { (x * 2.0).round() / 2.0 }
  let s = t.get(role, label~)
  let (x, y, w, h) = s.rect
  ((half(x), half(y), half(w), half(h)), s.value)
}

///|
/// The middle of the control of `role` named `label` as it is read out.
fn layout_middle(t : @ui.Tester, role : @ui.Role, label : String) -> (Double, Double) raise {
  let (x, y, w, h) = t.get(role, label~).rect
  (x + w / 2.0, y + h / 2.0)
}

///|
/// The reader's layout as it is now.
fn layout_style() -> @sf.ReaderStyle {
  (@sf.viewer_host().reader_style)()
}

///|
/// The novel read on a phone, its layout open (sffix's reader-layout), its sheet risen.
fn layout_phone() -> @ui.Tester {
  let t = drive_tester("reader-layout")
  t.run_for(@sf.reader_place_ms)
  t.run_for(sheet_way_ms(t))
  t
}

///|
/// The novel read in a wide window, its layout opened by its tool (the third of the bar's four).
fn layout_wide() -> @ui.Tester {
  let t = desk_tester("reader")
  t.run_for(@sf.reader_place_ms)
  t.tap(desk_tool_x(1), 22.0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The novel's reading (its key as the drive's reader has it).
fn layout_reading() -> @sf.Reading {
  @sf.reading_for(reader_key({ station: "ws1/st1", root: Some(fix_docs), path: "长篇小说.txt" }))
}

///|
test "小屏: the layout a sheet half the window tall, each of its words and controls where the host's sheet had them" {
  let t = layout_phone()
  // (a paragraph of the book that begins under the sheet is the book's, many lines tall: not the layout's words)
  let words = layout_words(t, fn(_, y) { y >= 400.0 }).filter(fn(w) { w.4 < 100.0 })
  // (the old body in the host's sheet, as recorded; the reader's bars under it as they are)
  let old = [
    ("排版", 18.0, 451.0, 32.0, 22.5),
    ("背景", 20.0, 487.5, 350.0, 18.0),
    ("文", 44.0, 523.5, 16.0, 24.0),
    ("文", 115.5, 523.5, 16.0, 24.0),
    ("文", 187.0, 523.5, 16.0, 24.0),
    ("纸白", 40.0, 561.5, 24.0, 16.0),
    ("护眼", 111.5, 561.5, 24.0, 16.0),
    ("浅灰", 183.0, 561.5, 24.0, 16.0),
    ("字号", 20.0, 587.5, 350.0, 18.0),
    ("A−", 42.5, 626.5, 15.0, 22.0),
    ("16", 187.5, 626.5, 15.0, 22.0),
    ("A+", 332.5, 626.5, 15.0, 22.0),
    ("行距", 20.0, 676.5, 48.0, 18.0),
    ("170%", 344.0, 676.5, 26.0, 18.0),
    ("上一章", 33.0, 706.0, 39.0, 18.0),
    ("第三章 灯塔的钥匙", 140.0, 706.0, 110.5, 18.0),
    ("下一章", 318.0, 706.0, 39.0, 18.0),
    ("边距", 20.0, 714.5, 48.0, 18.0),
    ("22", 357.0, 714.5, 13.0, 18.0),
    ("43%", 350.5, 743.0, 19.5, 18.0),
    ("字体", 20.0, 747.5, 168.0, 18.0),
    ("缩进", 202.0, 747.5, 168.0, 18.0),
    ("宋体", 48.0, 781.0, 30.0, 21.0),
    ("黑体", 130.0, 781.0, 30.0, 21.0),
    ("首行缩进", 217.0, 781.0, 60.0, 21.0),
    ("顶格", 314.0, 781.0, 30.0, 21.0),
    ("目录", 65.0, 802.0, 24.0, 16.0),
    ("排版", 183.0, 802.0, 24.0, 16.0),
  ]
  assert_eq(words, old)
  // its controls where the old ones were read out (the sliders now named by their rows)
  assert_eq(layout_control(t, Button, "文 纸白").0, (20.0, 513.5, 63.5, 64.0))
  assert_eq(layout_control(t, Button, "文 护眼").0, (91.5, 513.5, 63.5, 64.0))
  assert_eq(layout_control(t, Button, "文 浅灰").0, (163.0, 513.5, 63.5, 64.0))
  assert_eq(layout_control(t, Button, "减小字号").0, (28.0, 621.5, 44.0, 32.0))
  assert_eq(layout_control(t, Button, "增大字号").0, (318.0, 621.5, 44.0, 32.0))
  assert_eq(layout_control(t, Slider, "行距"), ((78.0, 671.5, 234.0, 28.0), "1.7"))
  assert_eq(layout_control(t, Slider, "边距"), ((78.0, 709.5, 234.0, 28.0), "22"))
  assert_eq(layout_control(t, Radio, "宋体").0, (23.0, 776.5, 80.0, 30.0))
  assert_eq(layout_control(t, Radio, "黑体").0, (105.0, 776.5, 80.0, 30.0))
  assert_eq(layout_control(t, Radio, "首行缩进").0, (205.0, 776.5, 84.0, 30.0))
  assert_eq(layout_control(t, Radio, "顶格").0, (291.0, 776.5, 76.0, 30.0))
  t.assert_idle()
}

///|
test "小屏: the layout's controls pressed where they are drawn: the size, a paper, the lines, the face, the indent; Escape lets the sheet go" {
  let t = layout_phone()
  let r = layout_reading()
  assert_true(r.panel == @sf.ReaderPanel::Layout)
  let was = layout_style()
  // A+: a size more, said in its row
  let (x, y) = layout_middle(t, Button, "增大字号")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().size, was.size + 1)
  assert_true(t.find("\{was.size + 1}") is Some(_))
  // 护眼: its paper
  let (x, y) = layout_middle(t, Button, "文 护眼")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().paper, "green")
  // the lines tapped a quarter along (its knob's middle 11 in from either end): 1.2 + a quarter of 1.2, kept as it is
  // let go
  let ((sx, sy, sw, sh), _) = layout_control(t, Slider, "行距")
  t.tap(sx + 11.0 + (sw - 22.0) * 0.25, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true((layout_style().line - 1.5).abs() < 1.0e-9, msg="\{layout_style().line}")
  assert_true(t.find("150%") is Some(_))
  // 宋体, then 顶格: each chosen as it is pressed
  t.tap_text("宋体")
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().face, "serif")
  t.tap_text("顶格")
  t.run_for(@ui.move_most_ms)
  assert_false(layout_style().indent)
  // Escape: the panel closed at once, the sheet sinking away, then gone
  t.key(@ui.key_escape)
  assert_true(r.panel == @sf.ReaderPanel::NoPanel)
  t.run_for(sheet_way_ms(t))
  assert_true(t.find("背景") is None)
  t.assert_idle()
}

///|
test "wide: the layout docked at the right under the bar, each of its words and controls where the old panel had them" {
  let t = layout_wide()
  let words = layout_words(t, fn(x, y) { x >= 955.0 && y >= 40.0 })
  let old = [
    ("排版", 979.0, 60.0, 32.0, 24.0),
    ("背景", 981.0, 97.0, 279.0, 18.0),
    ("文", 998.0, 133.0, 16.0, 24.0),
    ("文", 1055.5, 133.0, 16.0, 24.0),
    ("文", 1113.0, 133.0, 16.0, 24.0),
    ("纸白", 995.0, 171.0, 22.0, 16.0),
    ("护眼", 1052.5, 171.0, 22.0, 16.0),
    ("浅灰", 1110.0, 171.0, 22.0, 16.0),
    ("字号", 981.0, 197.0, 279.0, 18.0),
    ("A−", 1004.5, 237.0, 13.0, 20.0),
    ("16", 1114.0, 237.0, 13.0, 20.0),
    ("A+", 1223.5, 237.0, 13.0, 20.0),
    ("行距", 981.0, 286.0, 48.0, 18.0),
    ("170%", 1236.0, 286.0, 24.0, 18.0),
    ("边距", 981.0, 324.0, 48.0, 18.0),
    ("22", 1248.0, 324.0, 12.0, 18.0),
    ("字体", 981.0, 357.0, 279.0, 18.0),
    ("宋体", 1039.0, 392.0, 26.0, 18.0),
    ("黑体", 1176.5, 392.0, 26.0, 18.0),
    ("缩进", 981.0, 429.0, 279.0, 18.0),
    ("首行缩进", 1026.0, 464.0, 52.0, 18.0),
    ("顶格", 1176.5, 464.0, 26.0, 18.0),
  ]
  assert_eq(words, old)
  // on the paper, 319 wide at the window's right, from under the bar to its foot
  let ground = @sf.reader_paper(layout_style().paper).ground
  assert_true(
    t.drawn_rects().iter().any(fn(r) { r.0 == 961.0 && r.1 == 45.0 && r.2 == 319.0 && r.3 == 755.0 && r.4 == ground }),
    msg="its paper",
  )
  assert_eq(layout_control(t, Button, "关闭").0, (1238.0, 57.0, 30.0, 30.0))
  assert_eq(layout_control(t, Button, "文 纸白").0, (981.0, 123.0, 49.5, 64.0))
  assert_eq(layout_control(t, Button, "文 护眼").0, (1038.5, 123.0, 49.5, 64.0))
  assert_eq(layout_control(t, Button, "文 浅灰").0, (1096.0, 123.0, 49.5, 64.0))
  assert_eq(layout_control(t, Button, "减小字号").0, (989.0, 231.0, 44.0, 32.0))
  assert_eq(layout_control(t, Button, "增大字号").0, (1208.0, 231.0, 44.0, 32.0))
  assert_eq(layout_control(t, Slider, "行距"), ((1039.0, 281.0, 163.0, 28.0), "1.7"))
  assert_eq(layout_control(t, Slider, "边距"), ((1039.0, 319.0, 163.0, 28.0), "22"))
  assert_eq(layout_control(t, Radio, "宋体").0, (984.0, 386.0, 135.5, 30.0))
  assert_eq(layout_control(t, Radio, "黑体").0, (1121.5, 386.0, 135.5, 30.0))
  assert_eq(layout_control(t, Radio, "首行缩进").0, (984.0, 458.0, 135.5, 30.0))
  assert_eq(layout_control(t, Radio, "顶格").0, (1121.5, 458.0, 135.5, 30.0))
  t.assert_idle()
}

///|
test "wide: the layout's controls pressed where they are drawn: the size, a paper, the margins dragged and stepped by the keys, the face, the indent; Esc closes it, then goes back; its close closes it" {
  let t = layout_wide()
  let r = layout_reading()
  assert_true(r.panel == @sf.ReaderPanel::Layout)
  let was = layout_style()
  let (x, y) = layout_middle(t, Button, "减小字号")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().size, was.size - 1)
  let (x, y) = layout_middle(t, Button, "文 浅灰")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().paper, "grey")
  // the margins dragged from their knob past the line's end: the most, kept as it is let go
  let ((sx, sy, sw, sh), _) = layout_control(t, Slider, "边距")
  let (least, most) = @sf.reader_margins
  let from = sx + 11.0 + (sw - 22.0) * (was.margin - least).to_double() / (most - least).to_double()
  t.drag(from, sy + sh / 2.0, sx + sw + 20.0, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().margin, most)
  assert_true(t.find_last("\{most}") is Some(_))
  // its focus there from the press: ← a step back, kept at once
  t.key(@ui.key_code_left)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().margin, most - 1)
  // a screen reader's step up
  t.act(Slider, Increment, label="边距")
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().margin, most)
  t.tap_text("宋体")
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().face, "serif")
  t.tap_text("顶格")
  t.run_for(@ui.move_most_ms)
  assert_false(layout_style().indent)
  // Esc: closed at once; again: back to the folder
  t.key(@ui.key_escape)
  assert_true(r.panel == @sf.ReaderPanel::NoPanel)
  assert_true(t.find("背景") is None)
  // opened again, its close closes it
  t.tap(desk_tool_x(1), 22.0)
  t.run_for(@ui.move_most_ms)
  assert_true(r.panel == @sf.ReaderPanel::Layout)
  let (x, y) = layout_middle(t, Button, "关闭")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(r.panel == @sf.ReaderPanel::NoPanel)
  assert_true(t.find("背景") is None)
  t.key(@ui.key_escape)
  assert_false(app.nav.top() is DriveRead(_))
}

///|
test "wide: the layout of a chat's Markdown answers its controls, is under a later dialog, and closes" {
  let t = desk_tester("chat-preview-md")
  t.run_for(@sf.reader_place_ms)
  let (x, y) = layout_middle(t, Button, "排版")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let was = layout_style()
  let (x, y) = layout_middle(t, Button, "增大字号")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().size, was.size + 1)
  assert_true(t.find("\{was.size + 1}") is Some(_))
  let (x, y) = layout_middle(t, Button, "文 护眼")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().paper, "green")
  let ((sx, sy, sw, sh), _) = layout_control(t, Slider, "行距")
  t.tap(sx + 11.0 + (sw - 22.0) * 0.25, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true((layout_style().line - 1.5).abs() < 1.0e-9)
  let ((sx, sy, sw, sh), _) = layout_control(t, Slider, "边距")
  let (least, most) = @sf.reader_margins
  let from = sx + 11.0 + (sw - 22.0) * (was.margin - least).to_double() / (most - least).to_double()
  // The whole gesture between frames: it is still captured by this slider when let go beyond its end.
  t.touch(0, from, sy + sh / 2.0)
  t.touch(1, sx + sw + 20.0, sy + sh / 2.0)
  t.touch(2, sx + sw + 20.0, sy + sh / 2.0)
  t.draw()
  assert_eq(layout_style().margin, most)
  let (x, y) = layout_middle(t, Radio, "宋体")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().face, "serif")
  let (x, y) = layout_middle(t, Radio, "顶格")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_false(layout_style().indent)
  // A dialog opened afterwards owns the input until it is dismissed.
  @sf.confirm("确认", "继续吗？", "继续", fn() {  })
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Button, label="增大字号").length(), 0)
  let (x, y) = layout_middle(t, Button, "取消")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("背景") is None)
  assert_true(viewer.get() is Some(_))
  let (x, y) = layout_middle(t, Button, "排版")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let (x, y) = layout_middle(t, Button, "关闭")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("背景") is None)
}

///|
test "小屏: the layout of a chat's Markdown answers its controls and closes" {
  let t = preview_tester("md", platform=2)
  t.run_for(@sf.reader_place_ms)
  let (x, y, w, h) = t.get(Button, has="发布前要做的").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  let (x, y) = layout_middle(t, Button, "排版")
  t.tap(x, y)
  t.run_for(sheet_way_ms(t))
  let was = layout_style().size
  let (x, y) = layout_middle(t, Button, "增大字号")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(layout_style().size, was + 1)
  assert_true(layout_words(t, fn(_, _) { true }).iter().any(fn(w) { w.0 == "\{was + 1}" }))
  t.key(@ui.key_escape)
  t.run_for(sheet_way_ms(t))
  assert_true(t.find("背景") is None)
  assert_true(viewer.get() is Some(_))
}

///|
test "wide: layout changes show while the core is still keeping them" {
  new_run()
  let base = fixture("reader")
  let pending : Array[Json] = []
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "prefs.set" && field(Some(params), "reader") is Some(_) {
        pending.push(params)
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.draw()
  app.nav.replace(Home)
  open_drive_fixture("reader")
  t.run_for(@ui.move_most_ms)
  t.run_for(@sf.reader_place_ms)
  let (x, y) = layout_middle(t, Button, "排版")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let was = layout_style().size
  let (x, y) = layout_middle(t, Button, "增大字号")
  t.tap(x, y)
  t.draw()
  assert_eq(layout_style().size, was + 1)
  assert_eq(pending.length(), 1)
  assert_true(
    layout_words(t, fn(_, _) { true }).iter().any(fn(w) { w.0 == "\{was + 1}" }),
    msg="the chosen size shows before the core replies",
  )
  let (x, y) = layout_middle(t, Radio, "宋体")
  t.tap(x, y)
  t.draw()
  assert_eq(layout_style().face, "serif")
  assert_eq(t.get(Radio, label="宋体").check, Some(On))
  let ((sx, sy, sw, sh), _) = layout_control(t, Slider, "行距")
  t.tap(sx + 11.0 + (sw - 22.0) * 0.25, sy + sh / 2.0)
  t.draw()
  assert_true(t.find("150%") is Some(_))
  assert_eq(pending.length(), 3)
}

///|
test "wide: the mouse's pointer over the layout's ground (its title, a heading's words) is the arrow, over its controls the hand (@sf.ground_node)" {
  let t = layout_wide()
  let words = layout_words(t, fn(x, y) { x >= 955.0 && y >= 40.0 })
  let shape_on = fn(x : Double, y : Double) {
    t.move_to(x, y)
    t.run_for(@ui.move_most_ms)
    t.cursor()
  }
  let grounds = ["排版", "背景"].map(fn(s) {
    match words.filter(fn(w) { w.0 == s }) {
      [(_, x, y, w, h), ..] => (s, shape_on(x + w / 2.0, y + h / 2.0))
      [] => (s, NotAllowed)
    }
  })
  assert_eq(grounds, [("排版", Arrow), ("背景", Arrow)], msg="\{Repr(words)}")
  let (kx, ky) = layout_middle(t, Button, "增大字号")
  assert_eq(shape_on(kx, ky), Hand)
}
