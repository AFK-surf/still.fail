// The small panel's retained note: the caller can change its words and presence without remaking it for every update.

///|
test "a panel note follows words, language, width and visibility while retaining its node" {
  let before_words = words_of.val
  let words = @signals.signal("The frame rate is chosen automatically.")
  let width = @signals.signal(260.0)
  let shown = @signals.signal(true)
  let made = Ref(0)
  let note : Ref[@view.View?] = Ref(None)
  let tester = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=600.0, platform=0)
  tester.check_looks(false)
  set_words(fn(key, _) { if key == "note" { words.get() } else { key } })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(panel) {
      panel.width(By(fn() { Some(width.get()) })) |> ignore
      panel.show(fn() { shown.get() }, fn(place) {
        made.val += 1
        note.val = Some(panel_note_node(place, fn() { t("note") }))
      })
    }) |> ignore
  })
  tester.draw()
  let first = note.val.unwrap()
  let id = first.id()
  let initial = tester.rect_of("The frame rate").unwrap()
  assert_eq(initial.0, 10.0)
  assert_true(tester.words_said().iter().any(fn(w) { w.0 == words.get() }))
  assert_eq(tester.all(@ui.Role::Text, label=words.get()).length(), 1)

  words.set("The frame rate changes with the network and the screen's recommended resolution.\nA second line stays visible.")
  tester.draw()
  let wide = tester.rect_of("The frame rate changes").unwrap()
  let wide_lines = tester.lines_of("The frame rate changes").length()
  assert_true(wide_lines >= 2)
  assert_true(tester.words_said().iter().any(fn(w) { w.0 == words.get() }))
  assert_eq(note.val.unwrap().id(), id)
  assert_eq(made.val, 1)

  width.set(150.0)
  tester.draw()
  let narrow = tester.rect_of("The frame rate changes").unwrap()
  assert_eq(narrow.0, 10.0)
  assert_true(narrow.3 > wide.3)
  assert_true(tester.lines_of("The frame rate changes").length() > wide_lines)
  assert_eq(note.val.unwrap().id(), id)

  set_words(fn(key, _) { if key == "note" { "推荐分辨率会随画面变化。\n调试结果已更新。" } else { key } })
  tester.draw()
  assert_true(tester.words_said().iter().any(fn(w) { w.0 == "推荐分辨率会随画面变化。\n调试结果已更新。" }))
  assert_eq(tester.all(@ui.Role::Text, label="推荐分辨率会随画面变化。\n调试结果已更新。").length(), 1)
  assert_eq(note.val.unwrap().id(), id)
  shown.set(false)
  tester.draw()
  assert_false(first.alive())
  assert_false(tester.words_said().iter().any(fn(w) { w.0.contains("推荐分辨率") }))
  assert_eq(tester.all(@ui.Role::Text, label="推荐分辨率会随画面变化。\n调试结果已更新。").length(), 0)
  shown.set(true)
  tester.draw()
  assert_eq(made.val, 2)
  assert_true(tester.words_said().iter().any(fn(w) { w.0.contains("推荐分辨率") }))
  set_words(before_words)
}

///|
test "a panel note is read as words and does not take keyboard focus or a press" {
  let presses = Ref(0)
  let tester = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=320.0, h=300.0, platform=0)
  tester.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    button_node(root, fn() { "Before" }, fn() { presses.val += 1 }) |> ignore
    panel_note_node(root, fn() { "Connection result" }) |> ignore
    button_node(root, fn() { "After" }, fn() { presses.val += 1 }) |> ignore
  })
  tester.draw()
  assert_true(tester.words_said().iter().any(fn(w) { w.0 == "Connection result" }))
  tester.key(@ui.key_tab)
  tester.draw()
  assert_eq(tester.focused().map(fn(s) { s.label }), Some("Before"))
  tester.key(@ui.key_tab)
  tester.draw()
  assert_eq(tester.focused().map(fn(s) { s.label }), Some("After"))
  let r = tester.rect_of("Connection result").unwrap()
  tester.tap(r.0 + 1.0, r.1 + 1.0)
  tester.draw()
  assert_eq(presses.val, 0)
}
