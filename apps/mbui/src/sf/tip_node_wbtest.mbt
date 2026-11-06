// A tip with an action's keys and what changes while it is shown.

///|
/// A tip saying these words and action as they change.
fn shortcut_tip_tester(
  words : @signals.Signal[String],
  action : @signals.Signal[String],
  there : @signals.Signal[Bool],
  keyboard : Bool,
  dark : Bool,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0, keyboard~, dark~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(g) { g.width(Is(Some(100.0))) |> ignore }) |> ignore
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.show(fn() { there.get() }, fn(h) {
      h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      let a = h.box(fn(v) {
        v.width(Is(Some(32.0))).height(Is(Some(32.0))).on_press(fn() {  }).focusable(Is(true))
        .says(By(fn() { Some(@view.said(Button, label=words.get())) })) |> ignore
      })
      tip_node(tips, a, fn() { words.get() }, shortcut=fn() { action.get() }) |> ignore
    })
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  t
}

///|
test "a tip's shortcut follows its words with the quiet look, only with a keyboard, in light and dark" {
  let before = shortcut_keys_of.val
  set_shortcuts(fn(action) { if action == "files.preview" { "Ctrl+P" } else { "" } })
  let mut uncut_key_width = 0.0
  for label in ["Preview", "Preview the selected file and keep it open while browsing the rest of this folder"] {
    for keyboard in [false, true] {
      for dark in [false, true] {
        let t = shortcut_tip_tester(@signals.signal(label), @signals.signal("files.preview"), @signals.signal(true), keyboard, dark)
        let button = t.get(Button, label~)
        t.move(button.rect.0 + 16.0, button.rect.1 + 16.0)
        t.run_for(tip_delay_ms + tip_settled_ms)
        let tip = t.get(Tooltip, label~)
        assert_eq(t.find("Ctrl+P") is Some(_), keyboard, msg="keys only with a keyboard")
        assert_true(tip.rect.2 <= tip_widest, msg="a long label stays within the tip's maximum width")
        if keyboard {
          let (wx, _, ww, _) = t.shown_of(label).unwrap()
          let (kx, _, key_width, _) = t.shown_of("Ctrl+P").unwrap()
          assert_true((kx - (wx + ww) - @ui.Space::px(S2)).abs() < 0.01, msg="the keys follow the words at the tip's gap")
          if label == "Preview" {
            uncut_key_width = key_width
          } else {
            assert_true(key_width < uncut_key_width, msg="the keys make room for a long, wrapped label")
          }
          let (_, _, quiet) = t.look_of("Ctrl+P").unwrap()
          assert_true((quiet - 0.6).abs() < 0.001, msg="the keys use the quiet opacity")
        }
      }
    }
  }
  set_shortcuts(before)
}

///|
test "a shown tip follows its words, action and a keyboard coming and going; its semantics and lifetime follow its control" {
  let before = shortcut_keys_of.val
  set_shortcuts(fn(action) {
    match action {
      "files.preview" => "Ctrl+P"
      "files.next" => "Alt+N"
      _ => ""
    }
  })
  let words = @signals.signal("Show preview")
  let action = @signals.signal("files.preview")
  let there = @signals.signal(true)
  let t = shortcut_tip_tester(words, action, there, true, false)
  t.tab()
  t.run_for(tip_settled_ms)
  assert_true(t.find("Ctrl+P") is Some(_))
  assert_eq(t.get(Tooltip, label="Show preview").label, "Show preview")
  words.set("Hide preview")
  action.set("files.next")
  t.draw()
  assert_true(t.find("Ctrl+P") is None)
  assert_true(t.find("Alt+N") is Some(_))
  assert_eq(t.get(Tooltip, label="Hide preview").label, "Hide preview")
  action.set("")
  t.draw()
  assert_true(t.find("Alt+N") is None)
  assert_eq(t.get(Tooltip, label="Hide preview").label, "Hide preview")
  action.set("files.preview")
  t.draw()
  assert_true(t.find("Ctrl+P") is Some(_))
  t.set_keyboard(false)
  t.draw()
  assert_true(t.find("Ctrl+P") is None, msg="keyboard taken away while the tip is shown")
  t.set_keyboard(true)
  t.draw()
  assert_true(t.find("Ctrl+P") is Some(_), msg="keyboard plugged in while the tip is shown")
  there.set(false)
  t.run_for(tip_settled_ms)
  assert_true(t.semantics().iter().all(fn(s) { s.role != Tooltip || s.hidden }), msg="tip went with its control")
  set_shortcuts(before)
}
