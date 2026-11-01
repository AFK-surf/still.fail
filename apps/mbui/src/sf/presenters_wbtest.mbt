// The presenters (presenters.mbt), each at the Small tier with a finger (a sheet) and at the Large tier with a mouse
// (the web's: beside what opened it, or in the middle of the window).

///|
/// A phone's window (Small, a finger) and a desktop's (Large, a mouse).
let phone : (Int, Double, Double) = (2, 390.0, 844.0)

///|
let desk : (Int, Double, Double) = (0, 1280.0, 800.0)

///|
test "an anchored panel animates both entering and leaving before its presenter is removed" {
  let t = presenting_tester(desk, fn(from) {
    panel("动画面板", from~, fn(c, _) { c.text("面板内容") |> ignore })
  })
  t.tap_text("打开")
  t.run_for(@kit.pop_ms / 2.0)
  let (_, _, entering) = t.look_of("面板内容").unwrap()
  assert_true(entering > 0.0 && entering < 1.0)
  t.run_for(@kit.pop_ms)
  close_presented()
  t.frame()
  t.run_for(@kit.pop_out_ms / 2.0)
  let (_, _, leaving) = t.look_of("面板内容").unwrap()
  assert_true(leaving > 0.0 && leaving < 1.0)
  t.run_for(@kit.pop_out_ms)
  assert_true(t.look_of("面板内容") is None)
}

///|
/// A page with one button, 打开 (`at` its top, its middle, or its foot as a composer's choices are), that opens what
/// `open` presents (given what opened it), and the host over it.
fn presenting_view(open : (Anchor) -> Unit, at? : @ui.Justify = JStart) -> (@ui.Ctx) -> Unit {
  fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, justify=at, fn() {
        if button(c, "打开", key="open") {
          open(Of(c.id("open")))
        }
      })
      |> ignore
      presented(c)
    })
  }
}

///|
fn presenting_tester(at : (Int, Double, Double), open : (Anchor) -> Unit, button_at? : @ui.Justify = JStart) -> @ui.Tester {
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(presenting_view(open, at=button_at), w~, h~, platform~)
  t.draw()
  t
}

///|
/// What opened it as a menu's or a pick's (what presenting_view opened it by: its 打开).
fn beside_of(from : Anchor) -> Beside {
  match from {
    Anchor::Of(id) => Of(id)
    Anchor::At(x, y, w, h) => At(x, y, w, h)
    Unanchored => abort("a menu or a pick is opened beside what opened it")
  }
}

///|
/// 打开 pressed, and what it opened come in: a sheet risen, else the web's in.
fn open_it(t : @ui.Tester) -> Unit {
  t.tap_text("打开")
  if presented_how == [AsSheet] {
    t.run_for(@kit.sheet_rest("sf-present") - t.time())
  } else {
    t.run_for(@kit.presence_in_ms)
  }
}

///|
/// Where `words` are drawn, or a failure.
fn where_is(t : @ui.Tester, words : String) -> (Double, Double) raise {
  match t.find(words) {
    Some(at) => at
    None => fail("no \{words}")
  }
}

///|
fn menu_items_of(said : Array[String]) -> Array[MenuItem?] {
  [
    Some(menu_item_of("重命名", fn() { said.push("rename") }, icon="edit")),
    None,
    Some(menu_item_of("删掉", fn() { said.push("delete") }, danger=true)),
  ]
}

///|
test "a menu with a finger at Small: a sheet from the foot; an item tapped closes it and does what it says" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) { menu(menu_items_of(said), from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  // in the sheet's rows, low in the window
  assert_true(where_is(t, "重命名").1 > phone.2 / 2.0)
  t.tap_text("删掉")
  assert_eq(said, ["delete"])
  assert_true(!presenting())
}

///|
test "a menu with a mouse at Large: beside what opened it; Escape closes it, an item chosen does what it says" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { menu(menu_items_of(said), from=beside_of(from)) })
  let (_, by) = where_is(t, "打开")
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  // under the button, not far
  let (_, y) = where_is(t, "重命名")
  assert_true(y > by && y < by + 80.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, [])
  open_it(t)
  t.tap_text("重命名")
  assert_eq(said, ["rename"])
  assert_true(!presenting())
}

///|
/// The colours the glyphs of the first words containing `words` are drawn in (those whose quads start in the words'
/// upper half).
fn inks_of(t : @ui.Tester, words : String) -> Array[Int64] raise {
  let (x, y, w, h) = match t.rect_of(words) {
    Some(r) => r
    None => fail("no \{words}")
  }
  let out = []
  for g in t.drawn_glyphs() {
    if g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 < y + h / 2.0 && !out.contains(g.2) {
      out.push(g.2)
    }
  }
  out
}

///|
test "a menu with a mouse at Large: an item not to be chosen now in the subtle ink (it is never lit), clicked does nothing" {
  let said : Array[String] = []
  let items = [
    Some(menu_item_of("重命名", fn() { said.push("rename") }, icon="edit")),
    Some(menu_item_of("启动", fn() { said.push("start") }, icon="play", disabled=true)),
  ]
  let t = presenting_tester(desk, fn(from) { menu(items, from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let p = theme().p
  assert_eq(inks_of(t, "启动"), [p.subtle])
  assert_eq(inks_of(t, "重命名"), [p.text])
  t.tap_text("启动")
  assert_eq(said, [])
  assert_true(presenting())
}

///|
/// Choices to pick from, `n` of them: 第1项 … 第n项, known as c1 … cn. (No words are told in a test: a key is said
/// as it is, common.search.)
fn choices_of(n : Int) -> Array[Choice] {
  Array::makei(n, fn(i) { choice("c\{i + 1}", "第\{i + 1}项", note=if i == 0 { "最近用过" } else { "" }) })
}

///|
test "a pick with a finger at Small: a sheet of the choices; one tapped is chosen and it closes" {
  let chosen = Ref("c1")
  let t = presenting_tester(phone, fn(from) { pick("选一个", choices_of(3), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from)) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("选一个") is Some(_))
  assert_true(t.find("最近用过") is Some(_))
  t.tap_text("第3项")
  assert_eq(chosen.val, "c3")
  assert_true(!presenting())
}

///|
test "a long pick with a mouse at Large: its search over it finds by the words, Enter picks the first found" {
  let chosen = Ref("c1")
  let t = presenting_tester(desk, fn(from) {
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from))
  })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  assert_true(t.find("第2项") is Some(_))
  t.type_text("第11")
  assert_true(t.find("第2项") is None)
  assert_true(t.find("第11项") is Some(_))
  t.type_text("x")
  assert_true(t.find("common.noMatch") is Some(_))
  t.backspace()
  assert_true(t.key_named("enter"))
  assert_eq(chosen.val, "c11")
  assert_true(!presenting())
}

///|
test "a long pick with a finger at Small: the search in its sheet finds by the words" {
  let chosen = Ref("c1")
  let t = presenting_tester(phone, fn(from) {
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from))
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  t.tap_text("common.search")
  t.type_text("第12")
  assert_true(t.find("第3项") is None)
  t.tap_text("第12项")
  assert_eq(chosen.val, "c12")
}

///|
/// A panel: its words, and a button at its foot that closes it (a small panel's: PanelText, PanelFoot, PanelButton).
fn panel_body(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    panel_text(c, fn() { c.text("面板里的话", style=paragraph) |> ignore })
    panel_foot(c, fn() {
      if panel_button(c, "ok", "好的", tone=Filled) {
        said.push("ok")
        close()
      }
    })
  }
}

///|
test "a panel with a finger at Small: a sheet; back closes it" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) { panel("面板", panel_body(said), from~) })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("面板里的话") is Some(_))
  t.back()
  assert_true(!presenting())
  open_it(t)
  t.tap_text("好的")
  assert_eq(said, ["ok"])
  assert_true(!presenting())
}

///|
test "a panel with a mouse at Large: beside what opened it; a press outside closes it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { panel("面板", panel_body(said), from~) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (_, by) = where_is(t, "打开")
  assert_true(where_is(t, "面板").1 > by)
  t.tap(desk.1 - 40.0, desk.2 - 40.0)
  assert_true(!presenting())
  assert_eq(said, [])
}

///|
/// A panel's body of `n` lines (第1行 … 第n行), saying in `held` whether it was drawn held short of them (panel_held).
fn lines_body(n : Int, held : Ref[Bool]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _) {
    held.val = panel_held()
    for i in 1..=n {
      c.text("第\{i}行", style=paragraph) |> ignore
    }
  }
}

///|
/// A panel's foot: 好的, which says so and closes it.
fn ok_foot(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    if button(c, "好的", key="ok", tone=Primary) {
      said.push("ok")
      close()
    }
  }
}

///|
test "a sheet's action buttons keep their words whole, sharing the row or going onto another" {
  for (first, second, separate, disabled) in [
    ("取消", "添加到此 workspace", false, false),
    ("取消", "添加到此 workspace", false, true),
    ("Doesn't match, deny", "Turn off security mode", true, false),
  ] {
    let t = presenting_tester((2, 320.0, 844.0), fn(from) {
      panel("Actions", from~, fn(c, _) { c.text("Content") |> ignore }, foot=fn(c, _) {
        button(c, first, key="first") |> ignore
        button(c, second, key="second", tone=Primary, disabled~) |> ignore
      })
    })
    open_it(t)
    assert_eq(t.lines_of(first), [first], msg="first: \{t.lines_of(first)}")
    assert_eq(t.lines_of(second), [second], msg="second: \{t.lines_of(second)}")
    let a = t.rect_of(first).unwrap()
    let b = t.rect_of(second).unwrap()
    if separate {
      assert_true(b.1 >= a.1 + a.3, msg="buttons overlap: \{a}, \{b}")
    } else {
      assert_true((a.1 - b.1).abs() < 1.0, msg="the buttons fit side by side: \{a}, \{b}")
    }
  }
}

///|
/// Where `words` are drawn now (their top and bottom, moved as what holds them scrolls), or a failure.
fn drawn_span(t : @ui.Tester, words : String) -> (Double, Double) raise {
  match t.words().iter().find_first(fn(w) { w.0 == words }) {
    Some((_, _, y, _, h, _)) => (y, y + h)
    None => fail("\{words} not drawn")
  }
}

///|
test "a panel with a mouse beside what opened it, as tall as what it holds where that fits: not held" {
  let held = Ref(true)
  let t = presenting_tester(desk, fn(from) { panel("面板", lines_body(3, held), from~, foot=ok_foot([])) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  assert_true(!held.val)
  // its foot right under what it holds
  let (_, last) = drawn_span(t, "第3行")
  let (foot, _) = drawn_span(t, "好的")
  assert_true(foot > last && foot < last + 60.0)
}

///|
test "a panel with a mouse opened at the window's foot, with the room over it: over it, as tall as what it holds" {
  let held = Ref(true)
  let short = (0, 1280.0, 360.0)
  let t = presenting_tester(short, fn(from) { panel("面板", lines_body(3, held), from~, foot=ok_foot([])) }, button_at=JEnd)
  let (_, by) = where_is(t, "打开")
  open_it(t)
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(bottom < by, msg="not over what opened it")
  assert_true(!held.val)
}

///|
test "a panel with a mouse taller than the room on either side of what opened it, not than the window: moved over it to stay in, as tall as what it holds" {
  let held = Ref(true)
  let mid = (0, 1280.0, 400.0)
  let t = presenting_tester(mid, fn(from) { panel("面板", lines_body(10, held), from~, foot=ok_foot([])) }, button_at=JCenter)
  let (_, by) = where_is(t, "打开")
  open_it(t)
  // all of it in the window, over the button rather than shortened
  let (top, _) = drawn_span(t, "面板")
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(top > 0.0 && bottom < mid.2, msg="out of the window")
  assert_true(top < by && bottom > by, msg="not moved over what opened it")
  assert_true(!held.val, msg="shortened while the window has the room for it")
  assert_true(drawn_span(t, "第10行").1 < bottom)
}

///|
test "a panel with a mouse taller than the window: as tall as the window lets it, its title and foot in it, what it holds scrolled to" {
  let said : Array[String] = []
  let held = Ref(false)
  let short = (0, 1280.0, 320.0)
  let t = presenting_tester(short, fn(from) { panel("面板", lines_body(40, held), from~, foot=ok_foot(said)) })
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (top, _) = drawn_span(t, "面板")
  let (_, bottom) = drawn_span(t, "好的")
  assert_true(top > 0.0, msg="its title out of the window")
  assert_true(bottom < short.2, msg="its foot out of the window")
  assert_true(held.val, msg="what it holds not told it scrolls as one")
  // its last line under the foot until what it holds is scrolled, then over it
  let (foot, _) = drawn_span(t, "好的")
  assert_true(drawn_span(t, "第40行").0 > foot)
  let (lx, ly) = where_is(t, "第1行")
  t.wheel(lx, ly, 2000.0)
  assert_true(drawn_span(t, "第40行").1 < foot, msg="what it holds not scrolled to its end")
  assert_true(drawn_span(t, "面板").0 == top, msg="its title scrolled with what it holds")
  t.tap_text("好的")
  assert_eq(said, ["ok"])
  assert_true(!presenting())
}

///|
test "a confirm with a finger at Small: a sheet; its action does it, the cancel does not" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    confirm("归档这个对话？", "归档后仍可在归档里找到。", "确认归档", fn() { said.push("archived") }, danger=true, from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  t.tap_text("common.cancel")
  assert_eq(said, [])
  assert_true(!presenting())
  open_it(t)
  t.tap_text("确认归档")
  assert_eq(said, ["archived"])
  assert_true(!presenting())
}

///|
test "a confirm with a mouse at Large: a dialog in the middle of the window; Escape closes it, its action does it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) {
    confirm("归档这个对话？", "归档后仍可在归档里找到。", "确认归档", fn() { said.push("archived") }, from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  let (x, _) = where_is(t, "归档后仍可在归档里找到。")
  assert_true(x > desk.1 / 2.0 - confirm_w / 2.0 && x < desk.1 / 2.0 + confirm_w / 2.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  open_it(t)
  t.tap_text("确认归档")
  assert_eq(said, ["archived"])
  assert_true(!presenting())
}

///|
test "a question with a finger at Small: a sheet with its line; its action, once the line differs, goes on with it" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    ask("重命名", "保存", fn(line) { said.push(line) }, value="旧名字", from~)
  })
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  // the same line as it was: nothing to save
  t.tap_text("保存")
  assert_eq(said, [])
  t.type_text(" 新的 ")
  t.tap_text("保存")
  assert_eq(said, ["旧名字 新的"])
  assert_true(!presenting())
}

///|
test "a question with a mouse at Large: a dialog with its line; Enter says it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, fn(from) { ask("重命名", "保存", fn(line) { said.push(line) }, placeholder="名字", from~) })
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  assert_true(t.key_named("enter"))
  assert_eq(said, [])
  t.type_text("新名字")
  assert_true(t.key_named("enter"))
  assert_eq(said, ["新名字"])
  assert_true(!presenting())
}

///|
test "one over another: a confirm from a menu's item comes when the menu has gone; back closes the topmost first" {
  let said : Array[String] = []
  let t = presenting_tester(phone, fn(from) {
    panel("面板", fn(c, _) {
      if button(c, "删除它", key="del") {
        confirm("删掉吗？", "删掉后不能恢复。", "删掉", fn() { said.push("deleted") }, danger=true)
      }
    }, from~)
  })
  open_it(t)
  t.tap_text("删除它")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_eq(presented_how, [AsSheet, AsSheet])
  t.back()
  assert_eq(presented_how, [AsSheet])
  t.back()
  assert_true(!presenting())
  assert_eq(said, [])
}

///|
/// A panel opened by nothing (a form's dialog): its words, its foot's button closing it as said; what it lets go of
/// as it closes unsaid.
fn dialog_panel(said : Array[String]) -> (Anchor) -> Unit {
  fn(_) {
    panel(
      "添加一项",
      fn(c, _) { c.text("填好下面的内容", style=paragraph) |> ignore },
      from=Unanchored,
      description="每项都会加密保存",
      foot=fn(c, close) {
        if button(c, "确认添加", key="add") {
          said.push("added")
          close()
        }
      },
      gone=fn() { said.push("gone") },
    )
  }
}

///|
test "a panel opened by nothing with a mouse at Large: a dialog in the middle; Escape lets go of it, its foot says it" {
  let said : Array[String] = []
  let t = presenting_tester(desk, dialog_panel(said))
  open_it(t)
  assert_eq(presented_how, [AsDialog])
  assert_true(t.find("每项都会加密保存") is Some(_))
  let (x, _) = where_is(t, "填好下面的内容")
  assert_true(x > desk.1 / 2.0 - dialog_w / 2.0 && x < desk.1 / 2.0 + dialog_w / 2.0)
  assert_true(t.key_named("esc"))
  assert_true(!presenting())
  assert_eq(said, ["gone"])
  open_it(t)
  t.tap_text("确认添加")
  assert_true(!presenting())
  assert_eq(said, ["gone", "added"])
}

///|
test "a panel opened by nothing with a finger at Small: a sheet with its words and its foot" {
  let said : Array[String] = []
  let t = presenting_tester(phone, dialog_panel(said))
  open_it(t)
  assert_eq(presented_how, [AsSheet])
  assert_true(t.find("每项都会加密保存") is Some(_))
  t.tap_text("确认添加")
  assert_eq(said, ["added"])
  assert_true(!presenting())
}

///|
test "a short pick with a mouse at Large: a menu of choices beside what opened it, the chosen checked; one clicked" {
  let chosen = Ref("c1")
  let t = presenting_tester(desk, fn(from) { pick("选一个", choices_of(3), chosen.val, fn(k) { chosen.val = k }, from=beside_of(from)) })
  let (_, by) = where_is(t, "打开")
  open_it(t)
  assert_eq(presented_how, [AsPopover])
  let (_, y) = where_is(t, "第1项")
  assert_true(y > by && y < by + 80.0)
  // its note at its end
  assert_true(t.find("最近用过") is Some(_))
  t.tap_text("第2项")
  assert_eq(chosen.val, "c2")
  assert_true(!presenting())
}
