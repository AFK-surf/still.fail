///|
test "picking the page's retained words keeps the field focused and copies the page's selection" {
  let t = Tester::new(fn(_) { }, w=400.0, h=200.0, platform=0)
  let draft = Field::new(text="draft")
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(22.0))) |> ignore
      words_picked(page)
      page.box(fn(words) {
        words.width(Is(Some(300.0))).words_runs(Is([plain("hello world")]), ink=0x333333FFL,
          look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false }) |> ignore
      }) |> ignore
    }) |> ignore
    field(root, draft).over(Is(true)).offset(Is((0.0, 40.0)))
    .width(Is(Some(300.0))).height(Is(Some(22.0))) |> ignore
  })
  t.draw()
  draft.focus()
  t.draw()
  t.drag(1.0, 11.0, 299.0, 11.0)
  t.frame()
  assert_eq(t.ctx().selected_text(), "hello world")
  assert_true(t.ctx().field_focused())
  t.key(key_code_copy, mods=mod_cmd)
  assert_eq(t.clipboard(), "hello world")
  assert_eq(draft.text(), "draft")
  t.key(key_code_select_all, mods=mod_cmd)
  t.key(key_code_copy, mods=mod_cmd)
  assert_eq(t.clipboard(), "draft")
}

///|
test "a retained field's right click opens its editing menu, keeps its selection and edits that field" {
  let f = Field::new(text="hello world")
  let asked : Ref[(Int, Double, Double)?] = Ref(None)
  let page_menu = Ref(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=100.0)
  set_view_app(fn(root) {
    root.on_menu(fn(_) { page_menu.val += 1 }) |> ignore
    field(root, f, font_size=10.0) |> ignore
    old(root, fn(c) {
      match c.field_right_clicked() {
        Some(a) => asked.val = Some(a)
        None => ()
      }
    }) |> ignore
  })
  t.draw()
  let (fx, fy, fw, fh) = t.get(TextField).rect
  let at = (fx + fw / 2.0, fy + fh / 2.0)
  t.right_click(at.0, at.1)
  guard asked.val is Some((id, x, y)) else { fail("the field's editing menu was not asked for") }
  assert_eq((x, y, page_menu.val), (at.0, at.1, 0))
  assert_eq(t.ctx().focused_id(), id)
  t.ctx().field_edit(id, @hostapi.text_menu_select_all)
  t.draw()
  t.right_click(at.0, at.1)
  assert_eq(f.selection(), (0, 11))
  t.ctx().field_edit(id, @hostapi.text_menu_cut)
  t.draw()
  assert_eq((f.text(), t.clipboard()), ("", "hello world"))
  t.ctx().field_edit(id, @hostapi.text_menu_paste, paste="again")
  t.draw()
  assert_eq(f.text(), "again")
}

///|
test "a retained field's completion takes its Enter and Tab before editing, and only while its focus receives keys" {
  let t = Tester::new(fn(_) {  }, w=300.0, h=240.0)
  let f = Field::new(text="draft")
  let other = Field::new(text="other")
  let completing = @signals.signal(true)
  let modal = @signals.signal(false)
  let keys : Array[Int] = []
  let sent : Array[String] = []
  set_view_app(fn(root) {
    field(root, f, enter_sends=true, submitted=fn(s) { sent.push(s) }, keys=fn(code, mods) {
      if completing.get() && mods == 0 && (code == key_enter || code == key_tab) {
        keys.push(code)
        true
      } else { false }
    }).focusable(Is(true), keys=0) |> ignore
    field(root, other) |> ignore
    root.show(fn() { modal.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)).leaves_typing() |> ignore
    })
  })
  t.draw()
  f.focus()
  t.key(key_enter)
  t.key(key_tab)
  assert_eq(keys, [key_enter, key_tab])
  assert_eq(sent.length(), 0)
  t.type_text("!")
  assert_eq(f.text(), "draft!")
  other.focus()
  t.key(key_enter)
  assert_eq(keys.length(), 2)
  f.focus()
  modal.set(true)
  t.draw()
  assert_true(t.ime().0, msg="a menu that leaves typing keeps the retained editor's input method")
  t.type_text("?")
  assert_eq(f.text(), "draft!?")
  t.key(key_enter)
  assert_eq(keys.length(), 2)
  modal.set(false)
  completing.set(false)
  t.draw()
  f.focus()
  t.key(key_enter)
  assert_eq(sent, ["draft!?"])
  assert_eq(keys.length(), 2)
}

///|
test "scrolling a retained editor's choices keeps its keyboard, but dismisses another editor's" {
  for own in [true, false] {
    let t = Tester::new(fn(_) {  }, w=400.0, h=400.0, platform=2, pointing=Finger)
    let offered = Field::new()
    let other = Field::new()
    let scroll = @view.Scroll::new()
    set_view_app(fn(root) {
      let editor = field(root, offered, placeholder="查找")
      field(root, other, placeholder="其他") |> ignore
      root.box(fn(menu) {
        menu.height(Is(Some(150.0))).scrolls(scroll, for_field=editor.id(), fn(rows) {
          for i in 0..<8 {
            rows.box(fn(row) { row.height(Is(Some(40.0))).words(Is("选项 \{i}")) |> ignore }) |> ignore
          }
        }) |> ignore
      }) |> ignore
    })
    t.draw()
    if own { offered.focus() } else { other.focus() }
    t.draw()
    assert_true(t.ime().0)
    let (x, y) = t.find("选项 2").unwrap()
    t.measure_as_host()
    let at = t.time()
    t.touch_at(0, x + 5.0, y + 5.0, at)
    t.touch_at(1, x + 5.0, y - 70.0, at + 10.0)
    t.touch_at(2, x + 5.0, y - 70.0, at + 20.0)
    t.frame_at(at + 30.0)
    assert_eq(t.ime().0, own)
    let (_, after) = t.find("选项 2").unwrap_or((x, y))
    assert_true(after < y, msg="the choices scrolled")
    assert_eq(t.built_why(), "", msg="a retained scroll and its focus change build no old view: own=\{own}, \{t.built_why()}")
  }
}
