// The presenters (presenters.mbt), each at the Small tier with a finger (a sheet) and at the Large tier with a mouse
// (the web's: beside what opened it, or in the middle of the window).

///|
/// A phone's window (Small, a finger) and a desktop's (Large, a mouse).
let phone : (Int, Double, Double) = (2, 390.0, 844.0)

///|
let desk : (Int, Double, Double) = (0, 1280.0, 800.0)

///|
/// A page with one button, 打开, that opens what `open` presents (given what opened it), and the host over it.
fn presenting_view(open : (Anchor) -> Unit) -> (@ui.Ctx) -> Unit {
  fn(c) {
    begin(c) |> ignore
    c.with_theme(ui_theme(), fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), pad=40.0, fn() {
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
fn presenting_tester(at : (Int, Double, Double), open : (Anchor) -> Unit) -> @ui.Tester {
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(presenting_view(open), w~, h~, platform~)
  t.draw()
  t
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
  let t = presenting_tester(phone, fn(from) { menu(menu_items_of(said), from~) })
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
  let t = presenting_tester(desk, fn(from) { menu(menu_items_of(said), from~) })
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
/// Choices to pick from, `n` of them: 第1项 … 第n项, known as c1 … cn. (No words are told in a test: a key is said
/// as it is, common.search.)
fn choices_of(n : Int) -> Array[Choice] {
  Array::makei(n, fn(i) { choice("c\{i + 1}", "第\{i + 1}项", note=if i == 0 { "最近用过" } else { "" }) })
}

///|
test "a pick with a finger at Small: a sheet of the choices; one tapped is chosen and it closes" {
  let chosen = Ref("c1")
  let t = presenting_tester(phone, fn(from) { pick("选一个", choices_of(3), chosen.val, fn(k) { chosen.val = k }, from~) })
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
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from~)
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
    pick("选一个", choices_of(pick_search_from + 4), chosen.val, fn(k) { chosen.val = k }, from~)
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
/// A panel: its words, and a button in it that closes it.
fn panel_body(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    c.text("面板里的话", style=paragraph) |> ignore
    if button(c, "好的", key="ok") {
      said.push("ok")
      close()
    }
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
