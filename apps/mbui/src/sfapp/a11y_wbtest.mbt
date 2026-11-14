// What a screen reader is told of the app (mbui's semantics, the host's a11y lines): its icon buttons named as
// Android's app names them (their contentDescription), its pressed rows by their words.

///|
test "a screen reader on home: the bar's buttons named as Android's, told to the host" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_a11y(true)
  t.draw()
  t.get(Button, label=tr("android-chat.home.settings")) |> ignore
  let filter = fill("android-chat.home.filter.label", [("filter", tr("android-chat.home.filter.all"))])
  t.get(Button, label=filter) |> ignore
  // told to the host as lines, the settings' button among them, its action a press
  let said = t.a11y_said()
  assert_true(
    said
    .split("\n")
    .any(fn(v) {
      let l = v.to_owned()
      // (its actions the line's last field: a press among them, the focus too where it takes it)
      let actions = l.split("\u{1F}").to_array().last().map(fn(a) { a.to_owned() }).unwrap_or("")
      l.contains("\u{1F}Button\u{1F}") && l.contains(tr("android-chat.home.settings")) && actions.contains("a")
    }),
    msg=said,
  )
}
