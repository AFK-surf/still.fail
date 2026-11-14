// A station's or a workspace's mark picked in a sheet (settings' station_mark.mbt open_mark_pick), on the three screens:
// a sheet from the foot with touch and with keyboard and mouse on a small window, a dialog in the middle of a wide one.
// The icons' side and the emoji's, the icons found by words typed, their colour, one picked; an emoji picked or pasted;
// a picture put up as it is or read and made small first, one that cannot be, one answered after the sheet has gone;
// none.

///|
/// What a test of the picker holds: its Tester, the marks it set (emoji, icon), what it said, the system's photo picker
/// asked (what answers it).
priv struct MarkRun {
  t : @ui.Tester
  set : Array[(String, String)]
  said : Array[String]
  asked : Ref[((Bytes?) -> Unit)?]
  core : @settings.Core
}

///|
/// The picker opened for `name` whose mark is `emoji` and `icon`, over the fixture's chat on a window of `platform` (390
/// by 844; `wide`: 1200 by 800); decodes done as the host is told they are where not `finish` (MarkRun's `finish`); at
/// rest unless not `rest` (the frame it opened in).
fn mark_open(
  platform~ : Int = 2,
  wide~ : Bool = false,
  name~ : String = "Willow",
  emoji~ : String = "🚀",
  icon~ : String = "glyph:rocket:orange",
  rest~ : Bool = true,
  finish~ : Bool = true,
) -> MarkRun {
  @sf.presenters_reset()
  new_run()
  let src = fixture("chat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~, finish~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.draw()
  t.run_for(@ui.move_most_ms)
  let set = []
  let said = []
  let asked = Ref(None)
  let w : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "lin@example.com" }
  let core = {
    ..settings_core(src, w),
    say: fn(s) { said.push(s) },
    pick_picture: fn(done) {
      asked.val = Some(done)
      true
    },
  }
  let run = { t, set, said, asked, core }
  mark_again(run, name~, emoji~, icon~)
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  run
}

///|
/// The picker opened again in the same run, for `name`.
fn mark_again(run : MarkRun, name~ : String, emoji~ : String = "", icon~ : String = "") -> Unit {
  @settings.open_mark_pick(run.core, name, emoji, icon, "图标", fn(e, i, _) { run.set.push((e, i)) })
  run.t.draw()
}

///|
/// The three screens these look at: touch on a small window (a sheet), keyboard and mouse there (a sheet too), a wide
/// window (a dialog in the middle).
let mark_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// Where the words `words` are drawn (the first of them): left, top, width, height.
fn mark_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().find_first(fn(w) { w.0 == words && w.5 > 0.0 }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
/// Pressed in the middle of the words `words`, then on to where what it set off is at rest.
fn mark_press(t : @ui.Tester, words : String) -> Unit {
  let (x, y, w, h) = mark_word(t, words)
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
}

///|
/// The buttons named `label` shown now.
fn mark_buttons(t : @ui.Tester, label : String) -> Array[@ui.SemNode] {
  t.all(Button, label~).filter(fn(s) { !s.hidden && s.rect.2 > 0.0 })
}

///|
/// The one button named `label`'s room.
fn mark_button(t : @ui.Tester, label : String) -> (Double, Double, Double, Double) {
  match mark_buttons(t, label) {
    [b] => b.rect
    l => @halt.saying("\{l.length()} buttons \{label}")
  }
}

///|
/// The grid's cells shown now (a button as wide as it is tall, wider than a colour's), from the first.
fn mark_cells(t : @ui.Tester) -> Array[@ui.SemNode] {
  t
  .all(Button)
  .filter(fn(b) { !b.hidden && b.rect.2 > 40.0 && b.rect.2 < 90.0 && (b.rect.2 - b.rect.3).abs() < 0.5 })
}

///|
/// The colours' buttons as a screen reader is told them: each its name and whether it is the one picked.
fn mark_colours_said(t : @ui.Tester) -> Array[(String, Bool)] {
  ["图标", "red", "orange", "amber", "green", "teal", "blue", "purple", "pink"].map(fn(l) {
    match mark_buttons(t, l).iter().find_first(fn(b) { b.rect.2 < 48.0 }) {
      Some(b) => (l, b.selected.unwrap_or(false))
      None => (l + " none", false)
    }
  })
}

///|
/// Every image the host is decoding now told done (`ok`: else failed), then on to rest.
fn mark_decoded(t : @ui.Tester, ok~ : Bool = true) -> Unit {
  for id in 1..=400 {
    t.finish(1, id, ok~)
  }
  t.frame()
  t.run_for(@ui.move_most_ms)
}

///|
/// The picker closed as a person closes it (Escape), on to where it is gone.
fn mark_close(t : @ui.Tester) -> Unit {
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
}

///|
test "图标: on each screen the icons' side, its field, the colours with the mark's own picked, the grid with none first and its icon on the accent; a picture its own side" {
  for s in mark_screens {
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    let about = "platform \{s.0}, wide \{s.1}"
    for w in ["为 Willow 选择图标", "图标", "Emoji", "搜索图标"] {
      assert_true(t.find(w) is Some(_), msg="\{about}: \{w}")
    }
    // (the side over the field, the colours under it, the grid under them)
    let side = mark_word(t, "Emoji")
    let field = mark_word(t, "搜索图标")
    let red = mark_button(t, "red")
    let cell = mark_cells(t)[0].rect
    assert_true(side.1 < field.1 && field.1 < red.1 && red.1 < cell.1, msg="\{about}")
    // the colours: the words' own first, the mark's orange picked
    let said = mark_colours_said(t)
    assert_eq(said.filter(fn(c) { c.1 }).map(fn(c) { c.0 }), ["orange"])
    assert_eq(said.length(), 9)
    assert_true(said.iter().all(fn(c) { !c.0.has_suffix(" none") }), msg="\{about}: \{Repr(said)}")
    // six to a row, as wide as they are tall, none of them picked but the mark's own
    let cells = mark_cells(t)
    assert_true(cells.length() >= 12, msg=about)
    assert_true((cells[6].rect.1 - cells[5].rect.1) > cell.3, msg=about)
    assert_true(cells.iter().all(fn(b) { b.selected == Some(b.label == "rocket") }), msg=about)
    // none the grid's first cell, not the mark's; a picture its own side, the third
    assert_eq(cells[0].label, "不使用图标", msg=about)
    assert_eq(cells[0].selected, Some(false), msg=about)
    assert_true(mark_word(t, "图片").0 > side.0, msg=about)
    assert_true(t.find("上传图片") is None, msg=about)
    mark_press(t, "图片")
    let up = mark_word(t, "上传图片")
    assert_true(up.1 > side.1, msg=about)
    assert_eq(mark_cells(t).length(), 0, msg="\{about}: no grid")
    assert_true(t.find("搜索图标") is None, msg="\{about}: no field")
    assert_true(mark_buttons(t, "red").length() == 0, msg="\{about}: no colours")
    mark_close(t)
    assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
    assert_eq(run.set, [])
  }
}

///|
test "图标: an icon pressed sets it in the colour picked, the sheet going; a colour pressed sets the mark's icon in it at once, the sheet staying" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    t.click(Button, label="teal")
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set, [("🚀", "glyph:rocket:teal")], msg=about)
    assert_eq(mark_colours_said(t).filter(fn(c) { c.1 }).map(fn(c) { c.0 }), ["teal"], msg=about)
    assert_true(@sf.presenting(), msg="\{about}: still up")
    // the words' own colour: the icon as it is
    let (x, y, w, h) = mark_buttons(t, "图标").iter().find_first(fn(b) { b.rect.2 < 48.0 }).unwrap().rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set[1], ("🚀", "glyph:rocket"), msg=about)
    // an icon: in the colour picked
    t.click(Button, label="purple")
    t.run_for(@ui.move_most_ms)
    let others = mark_cells(t).filter(fn(b) { b.label != "rocket" && b.label != "不使用图标" })
    let other = others[0]
    let (ox, oy, ow, oh) = other.rect
    t.tap(ox + ow / 2.0, oy + oh / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_true(run.set[run.set.length() - 1].1 == "glyph:" + other.label + ":purple", msg="\{about}: \{Repr(run.set)}")
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
  }
}

///|
test "图标: words typed find the icons named by them; none found says so, none (the grid's first) takes the mark away" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    mark_press(t, "搜索图标")
    // (the mark's own found: picked)
    t.type_text("rocket")
    t.run_for(@ui.move_most_ms)
    assert_eq(mark_buttons(t, "rocket").map(fn(b) { b.selected }), [Some(true)], msg=about)
    for _ in 0..<6 {
      t.backspace()
    }
    t.type_text("robot")
    t.run_for(@ui.move_most_ms)
    assert_eq(mark_buttons(t, "robot").length(), 1, msg=about)
    assert_eq(mark_buttons(t, "rocket").length(), 0, msg=about)
    t.type_text("zzzz")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("未找到图标") is Some(_), msg=about)
    assert_eq(mark_buttons(t, "robot").length(), 0, msg=about)
    t.click(Button, label="不使用图标")
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set, [("", "")], msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
  }
}

///|
test "Emoji: its side the emoji, the mark's own first where it is none of them; one pressed or pasted sets it" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    // (an emoji not offered: first, picked)
    let run = mark_open(platform=s.0, wide=s.1, emoji="🦖", icon="")
    let t = run.t
    assert_true(t.find("粘贴或输入任意 emoji") is Some(_), msg=about)
    assert_eq(mark_buttons(t, "🦖").map(fn(b) { b.selected }), [Some(true)], msg=about)
    assert_true(mark_button(t, "🦖").1 <= mark_button(t, "🖥️").1, msg=about)
    assert_true(mark_buttons(t, "red").length() == 0, msg="\{about}: no colours")
    // the icons' side and back: the emoji's again
    mark_press(t, "图标")
    assert_true(t.find("搜索图标") is Some(_), msg=about)
    mark_press(t, "Emoji")
    assert_true(t.find("粘贴或输入任意 emoji") is Some(_), msg=about)
    t.click(Button, label="🐳")
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set, [("🐳", "")], msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
    // one pasted, words after it: the emoji alone
    mark_again(run, name="Willow", emoji="🐳")
    t.run_for(@ui.move_most_ms)
    mark_press(t, "粘贴或输入任意 emoji")
    t.paste("🇯🇵 日本")
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set[1], ("🇯🇵", ""), msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
  }
}

///|
test "上传图片: a small picture put up as it is; a large one read and made small, then put up; one that cannot be read said so" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1, finish=false)
    let t = run.t
    mark_press(t, "图片")
    mark_press(t, "上传图片")
    (run.asked.val.unwrap())(Some(b"\x89PNG\r\n\x1a\nxyz"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set, [("", "data:image/png;base64,iVBORw0KGgp4eXo=")], msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
    // a picture put up: 更换图片
    mark_again(run, name="Willow", icon="data:image/png;base64,iVBORw0KGgp4eXo=")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("更换图片") is Some(_), msg=about)
    mark_press(t, "更换图片")
    (run.asked.val.unwrap())(Some(b"BM not one put up as it is"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set.length(), 1, msg="\{about}: read first")
    assert_true(@sf.presenting(), msg="\{about}: still up while it is read")
    mark_decoded(t)
    assert_eq(run.set.length(), 2, msg=about)
    assert_true(run.set[1].0 == "" && run.set[1].1.has_prefix("data:image/jpeg;base64,"), msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
    assert_eq(run.said, [], msg=about)
    // one that does not decode: said so, the sheet staying
    mark_again(run, name="Willow", emoji="🚀")
    t.run_for(@ui.move_most_ms)
    mark_press(t, "图片")
    mark_press(t, "上传图片")
    (run.asked.val.unwrap())(Some(b"BM not one either"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    mark_decoded(t, ok=false)
    assert_eq(run.said, ["无法读取此图片，或无法压缩到足够小"], msg=about)
    assert_eq(run.set.length(), 2, msg=about)
    assert_true(@sf.presenting(), msg="\{about}: still up")
    mark_close(t)
    assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
  }
}

///|
test "上传图片: a picture still being read as the sheet is closed is let go of: nothing put up, nothing said, its decode done or failed" {
  for s in mark_screens {
    for ok in [true, false] {
      let about = "platform \{s.0}, wide \{s.1}, decoded \{ok}"
      let run = mark_open(platform=s.0, wide=s.1, finish=false)
      let t = run.t
        mark_press(t, "图片")
        mark_press(t, "上传图片")
      (run.asked.val.unwrap())(Some(b"BM not one put up as it is"))
      t.draw()
      mark_close(t)
      assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
      mark_decoded(t, ok~)
      assert_eq((run.set, run.said), ([], []), msg=about)
      assert_true(!@sf.presenter_visible(), msg="\{about}: still closed")
    }
  }
}

///|
test "上传图片: the picker answering after the sheet has closed and opened for another station: nothing put up on either" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1, finish=false)
    let t = run.t
    mark_press(t, "图片")
    mark_press(t, "上传图片")
    let answer = run.asked.val.unwrap()
    mark_close(t)
    mark_again(run, name="Maple", emoji="🌲")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("为 Maple 选择图标") is Some(_), msg=about)
    // (one too large, read; then one put up as it is)
    answer(Some(b"BM not one put up as it is"))
    t.draw()
    mark_decoded(t)
    answer(Some(b"\x89PNG\r\n\x1a\nxyz"))
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_eq((run.set, run.said), ([], []), msg=about)
    assert_true(@sf.presenting(), msg="\{about}: Maple's still up")
    mark_close(t)
    assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
  }
}

///|
test "图标 and Emoji: the grid is the other side's, or what the words typed find, in the frame they change, from its top" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    let top = mark_cells(t)[0].rect
    // a word typed: in that frame the icons it finds alone
    mark_press(t, "搜索图标")
    t.type_text("robot")
    assert_eq(mark_buttons(t, "robot").length(), 1, msg="\{about}: at once")
    assert_eq(mark_buttons(t, "rocket").length(), 0, msg="\{about}: at once")
    assert_true((mark_button(t, "robot").1 - top.1).abs() < 0.5, msg="\{about}: first")
    mark_close(t)
    // scrolled down the icons, then the emoji's side: its first row where the grid begins, in that frame
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    let first = mark_cells(t)[0]
    let (x, y, w, h) = first.rect
    t.wheel(x + w / 2.0, y + h / 2.0, 600.0)
    t.run_for(@ui.move_most_ms)
    assert_true(mark_buttons(t, first.label).length() == 0, msg="\{about}: scrolled")
    let (ex, ey, ew, eh) = mark_word(t, "Emoji")
    t.tap(ex + ew / 2.0, ey + eh / 2.0)
    t.draw()
    // (the emoji's first row the first of the grid, the icons gone; at rest where the colours were, as they go)
    let cells = mark_cells(t)
    assert_eq(cells.filter(fn(b) { b.label != "不使用图标" && !station_emoji_has(b.label) }).length(), 0, msg="\{about}: the icons gone")
    // (none not picked there either: the mark is an icon)
    assert_eq(cells[0].selected, Some(false), msg="\{about}: none")
    assert_true(cells.iter().all(fn(b) { b.rect.1 >= mark_button(t, "🖥️").1 - 0.5 }), msg="\{about}: from its top")
    t.run_for(@ui.move_most_ms)
    assert_true(mark_button(t, "🖥️").1 < top.1 - 30.0, msg="\{about}: \{Repr(mark_button(t, "🖥️"))} \{Repr(top)}")
    assert_true(mark_buttons(t, "red").length() == 0, msg="\{about}: no colours")
    mark_close(t)
    assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
  }
}

///|
test "图标: the colours read out as buttons by their names, the picked one said so; pressed a little outside a dot's ring, as a finger's room has it" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    assert_eq(
      mark_colours_said(t),
      [
        ("图标", false),
        ("red", false),
        ("orange", true),
        ("amber", false),
        ("green", false),
        ("teal", false),
        ("blue", false),
        ("purple", false),
        ("pink", false),
      ],
      msg=about,
    )
    // (as far apart as they go across the field's width: the first at its start, the last at its end)
    let field = t.all(TextField).filter(fn(f) { !f.hidden })[0].rect
    let first = mark_buttons(t, "red")[0].rect
    let words = mark_buttons(t, "图标").iter().find_first(fn(b) { b.rect.2 < 48.0 }).unwrap().rect
    let last = mark_button(t, "pink")
    assert_true(words.0 <= field.0 + 0.5 && last.0 + last.2 >= field.0 + field.2 - 0.5, msg="\{about}: \{Repr(words)} \{Repr(last)} \{Repr(field)}")
    assert_true(first.0 - (words.0 + words.2) > 0.0, msg=about)
    // 4 under the ring: a finger's press there is the dot's; a mouse's is not
    let (x, y, w, h) = mark_button(t, "teal")
    t.tap(x + w / 2.0, y + h + 4.0)
    t.run_for(@ui.move_most_ms)
    let want = if s.0 == 2 { [("🚀", "glyph:rocket:teal")] } else { [] }
    assert_eq(run.set, want, msg=about)
    mark_close(t)
    assert_true(!@sf.presenter_visible(), msg="\{about}: closed")
  }
}

///|
test "图标 with keys: Tab goes from the field to the colours, then the grid; Enter on a colour picks it, Space on an icon sets it" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1)
    let t = run.t
    let order = []
    for _ in 0..<14 {
      t.tab()
      match t.focused() {
        Some(f) => order.push("\{f.role} \{f.label}")
        None => order.push("none")
      }
    }
    let from = order.search("TextField 搜索图标").unwrap_or(-1)
    assert_true(from >= 0, msg="\{about}: \{Repr(order)}")
    assert_eq(
      order[from + 1:from + 10].to_owned(),
      ["Button 图标", "Button red", "Button orange", "Button amber", "Button green", "Button teal", "Button blue", "Button purple", "Button pink"],
      msg=about,
    )
    // (none the grid's first, then its icons)
    assert_eq(order[from + 10], "Button 不使用图标", msg=about)
    let first = mark_cells(t)[1].label
    // back to blue: Enter picks it, the focus staying there
    for _ in 0..<14 {
      if t.focused() is Some(f) && f.label == "blue" {
        break
      }
      t.tab(back=true)
    }
    t.key(@ui.key_code_enter)
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set, [("🚀", "glyph:rocket:blue")], msg=about)
    assert_true(t.focused() is Some(f) && f.label == "blue", msg="\{about}: \{t.focus_said()}")
    // on to the grid's first: Space sets it in blue, the sheet going
    for _ in 0..<14 {
      if t.focused() is Some(f) && f.label == first {
        break
      }
      t.tab()
    }
    t.key(@ui.key_space)
    t.run_for(@ui.move_most_ms)
    assert_eq(run.set[1].1, "glyph:" + first + ":blue", msg=about)
    assert_true(!@sf.presenter_visible(), msg="\{about}: gone")
  }
}

///|
/// Whether `label` is one of the emoji offered.
fn station_emoji_has(label : String) -> Bool {
  ["🖥️", "💻", "🍎", "🐧", "🪟", "☁️", "🏠", "🏢", "🚀", "⚡", "🔥", "🧪", "🛠️", "🐳", "🦀", "🐙", "🌲", "🌊", "🌙", "☀️", "🍊", "🍋", "🍇", "🐱", "🐶", "🦊", "🐼", "🐸", "🦉", "🐝", "🦄", "🐢", "🌵", "🌸", "🍄", "🌈", "❄️", "⭐", "🪐", "🌍", "🍉", "🍒", "🥑", "🍕", "☕", "🎧", "🎮", "🤖"].contains(label)
}

///|
test "不使用图标: a mark with none has none's cell picked, the grid's first, on the icons' side and the emoji's" {
  for s in mark_screens {
    let about = "platform \{s.0}, wide \{s.1}"
    let run = mark_open(platform=s.0, wide=s.1, emoji="", icon="")
    let t = run.t
    assert_eq(mark_cells(t).filter(fn(b) { b.selected == Some(true) }).map(fn(b) { b.label }), ["不使用图标"], msg=about)
    mark_press(t, "Emoji")
    assert_eq(mark_cells(t).filter(fn(b) { b.selected == Some(true) }).map(fn(b) { b.label }), ["不使用图标"], msg=about)
    mark_close(t)
  }
}
