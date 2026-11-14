// A dialog of nodes in the window's middle, with a keyboard and mouse: what has the keyboard's focus as it opens and
// how Tab goes round it, as the old frame's dialog has it. It opens on the first of its body that takes what is typed or
// the arrow keys (a field, a choice of a few), on what its body says it opens on where it says one, and on none of it
// where nothing does (its own ground: the keys its, nothing typed going under it); Tab goes round its body and its foot,
// never to its close button.

///|
/// A wide window's page holding one field, the focus on it, what is presented over it.
fn cf_page(f : @ui.Field) -> @ui.Tester raise {
  let t = field_page_tester((0, 1200.0, 800.0), false, f)
  focus_page_field(t, "wide")
  t
}

///|
/// A dialog "盖住" of nodes opened over it by nothing: `body` what it holds, 确定 at its foot (`ok` counting its presses).
fn cf_open(t : @ui.Tester, body : (@view.View) -> Unit, ok : Ref[Int]) -> Unit {
  panel_nodes("盖住", fn(v, _) { body(v) }, from=Unanchored, foot=fn(v, _) {
    button_node(v, fn() { "确定" }, fn() { ok.val += 1 }, tone=Primary) |> ignore
  })
  t.frame()
  come_to_rest(t)
}

///|
/// What has the focus, as a screen reader is told: its role and name, or none.
fn cf_focus(t : @ui.Tester) -> String {
  match t.focused() {
    Some(s) => "\{s.role} \{s.label}"
    None => "none"
  }
}

///|
test "a dialog of nodes in the middle opens on the first of its body that takes what is typed, past a button before it" {
  let f = @ui.Field::new()
  let t = cf_page(f)
  let ok = Ref(0)
  let typed = @ui.Field::new()
  cf_open(t, fn(v) {
    button_node(v, fn() { "甲" }, fn() {  }) |> ignore
    input_node(v, typed, placeholder="乙框", label="乙框") |> ignore
  }, ok)
  assert_eq(cf_focus(t), "TextField 乙框")
  t.type_text("字")
  t.draw()
  assert_eq(typed.text(), "字")
  assert_eq(f.text(), "")
  close_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presenter_visible())
  presenters_reset()
}

///|
test "a dialog of nodes in the middle opens on its choice of a few, the first of its body that takes the arrows" {
  let f = @ui.Field::new()
  let t = cf_page(f)
  let ok = Ref(0)
  let chosen = @signals.signal(0)
  cf_open(t, fn(v) {
    v.box(fn(line) {
      line.row(Is(true)) |> ignore
      seg_node(line, fn() { ["一", "二"] }, fn() { chosen.get() }, fn(i) { chosen.set(i) }) |> ignore
    })
    |> ignore
    button_node(v, fn() { "甲" }, fn() {  }) |> ignore
  }, ok)
  assert_eq(cf_focus(t), "Radio 一")
  close_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presenter_visible())
  presenters_reset()
}

///|
test "a dialog of nodes in the middle with nothing that takes what is typed: no focus in it, nothing typed under it, Enter presses nothing, Escape closes it; Tab to its body's first, Shift+Tab to its foot's last, never its close button" {
  let f = @ui.Field::new()
  let t = cf_page(f)
  let ok = Ref(0)
  cf_open(t, fn(v) {
    button_node(v, fn() { "甲" }, fn() {  }) |> ignore
    button_node(v, fn() { "乙" }, fn() {  }) |> ignore
  }, ok)
  // (no button of it, its close button neither: the dialog's own ground, read out as none or the dialog)
  let focus = cf_focus(t)
  assert_true(focus == "none" || focus.has_prefix("Dialog"), msg=focus)
  assert_false(t.ime().0)
  t.type_text("字")
  t.draw()
  assert_eq(f.text(), "", msg="typed under it")
  // Enter there: nothing pressed, its foot's 确定 neither, the dialog still up (as the old dialog: no focus, no press)
  t.key(@ui.key_code_enter)
  t.draw()
  assert_eq(ok.val, 0)
  assert_true(presenter_visible())
  // Tab round it: its body, its foot, back to its body; never 关闭
  let tabs : Array[String] = []
  for _ in 0..<4 {
    t.key(@ui.key_tab)
    t.draw()
    tabs.push(cf_focus(t))
  }
  assert_eq(tabs, ["Button 甲", "Button 乙", "Button 确定", "Button 甲"])
  close_presented()
  t.run_for(@ui.move_most_ms)
  presenters_reset()
  // opened again: Shift+Tab to its foot's last
  let t = cf_page(f)
  cf_open(t, fn(v) {
    button_node(v, fn() { "甲" }, fn() {  }) |> ignore
    button_node(v, fn() { "乙" }, fn() {  }) |> ignore
  }, ok)
  t.key(@ui.key_tab, mods=@ui.mod_shift_key)
  t.draw()
  assert_eq(cf_focus(t), "Button 确定")
  // Escape: closed
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(presenter_visible(), msg="Escape closed it")
  presenters_reset()
}

///|
test "a dialog of nodes in the middle opens on what its body says it opens on, before a field" {
  let f = @ui.Field::new()
  let t = cf_page(f)
  let ok = Ref(0)
  cf_open(t, fn(v) {
    input_node(v, @ui.Field::new(), placeholder="乙框", label="乙框") |> ignore
    let yes = button_node(v, fn() { "甲" }, fn() {  })
    panel_opens_on_node(yes)
  }, ok)
  assert_eq(cf_focus(t), "Button 甲")
  close_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presenter_visible())
  presenters_reset()
}
