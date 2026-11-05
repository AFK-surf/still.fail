///|
test "a file card follows upload progress and failure, and its actions use the current file" {
  set_words(fn(key, args) { if key == "web-main.file.uploadingPart" { args[0].1 + "% " + args[1].1 } else { key } })
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=300.0, platform=2)
  let info = @signals.signal(file_card_info("draft.txt", 100.0, pending=true))
  let tried : Array[String] = []
  let card : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    card.val = Some(file_card_node(root, fn() { info.get() }, composer=true,
      retry=fn() { tried.push(info.get().name) }, retry_shown=fn() { info.get().error != "" }, retry_label=fn() { "Try again" }))
  })
  t.draw()
  let id = card.val.unwrap().id()
  info.set(file_card_info("draft.txt", 100.0, pending=true, sent=Some(50.0)))
  t.draw()
  assert_true(t.words().iter().any(fn(w) { w.0.contains("50%") }), msg="\{t.words()}")
  info.set(file_card_info("renamed.txt", 100.0, error="Transfer failed"))
  t.draw()
  assert_true(t.find("Transfer failed") is Some(_))
  t.click(Button, label="Try again")
  assert_eq(tried, ["renamed.txt"])
  assert_eq(card.val.unwrap().id(), id)
}

///|
test "a hung remove button takes presses where its corner is drawn" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=300.0, h=250.0, platform=2)
  let removed = Ref(0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((30.0, 30.0, 30.0, 30.0))) |> ignore
    with_corner_remove_node(root, fn() { "Remove preview" }, fn() { 18.0 }, fn() { removed.val += 1 },
      fn(v) { v.height(Is(Some(56.0))).radius(Is(18.0)).ground(Is(0xEEEEEEFFL)) |> ignore }, width=fn() { Some(56.0) }) |> ignore
  })
  t.draw()
  t.click(Button, label="Remove preview")
  assert_eq(removed.val, 1)
}

///|
test "a file card that cannot open still lets its retry button be pressed" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=300.0, platform=2)
  let opened = Ref(0)
  let retried = Ref(0)
  let held : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    held.val = Some(file_card_node(root, fn() { file_card_info("draft.txt", 100.0, error="Transfer failed") }, composer=true,
      open=fn() { opened.val += 1 }, open_shown=fn() { false },
      retry=fn() { retried.val += 1 }, retry_label=fn() { "Try again" }))
  })
  t.draw()
  t.click(Button, label="Try again")
  assert_eq(retried.val, 1)
  assert_eq(opened.val, 0)
  let tree = @ui.view_tree().unwrap()
  let card = held.val.unwrap().id()
  let retry = tree.said_order().iter().find_first(fn(s) {
    s.said.map(fn(said) { said.label == "Try again" }).unwrap_or(false)
  }).unwrap()
  assert_eq(tree.said_order().iter().find_first(fn(s) { s.id == card }).map(fn(s) { s.disabled }), Some(true))
  assert_false(retry.disabled)
  assert_false(tree.activate_at(card, t.time()))
  assert_true(tree.activate_at(retry.id, t.time()))
  assert_eq((opened.val, retried.val), (0, 2))
}
