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
