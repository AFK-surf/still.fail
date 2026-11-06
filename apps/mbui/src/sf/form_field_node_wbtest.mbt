// A retained labelled field keeps its body while its words change and names its input for accessibility.

///|
test "field follows its label, hint and error without remaking or renaming its input to the placeholder" {
  let label = @signals.signal("Name")
  let hint = @signals.signal("Optional")
  let error = @signals.signal("")
  let value = @ui.Field::new(text="Ada")
  let input : Ref[@view.View?] = Ref(None)
  let made = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=480.0, h=300.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    look_lent(root, Wide)
    field_node(root, fn() { label.get() }, fn(slot) {
      made.val += 1
      input.val = Some(input_node(slot, value, placeholder="Type a name"))
    }, hint=fn() { hint.get() }, error=fn() { error.get() },
      aside=fn(top) { words_node(top, fn() { "Edit" }, fn() { field_hint }) |> ignore }) |> ignore
  })
  t.draw()
  let id = input.val.unwrap().id()
  assert_eq(t.get(TextField, label="Name").value, "Ada")
  assert_true(t.find("Optional") is Some(_))
  assert_true(t.find("Edit") is Some(_))
  label.set("Display name")
  hint.set("Shown to others")
  error.set("Name is required")
  t.draw()
  assert_eq((made.val, input.val.unwrap().id()), (1, id))
  assert_eq(t.get(TextField, label="Display name").value, "Ada")
  assert_true(t.find("Name is required") is Some(_))
  assert_true(t.find("Shown to others") is None)
  error.set("")
  t.draw()
  assert_true(t.find("Name is required") is None)
  assert_true(t.find("Shown to others") is Some(_))
  t.act(TextField, Focus, label="Display name")
  t.type_text(" Lovelace")
  assert_true(value.text().contains("Lovelace"))
}

///|
test "field labels textarea and secret inputs without exposing a secret, while an outside input keeps its placeholder" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=480.0, h=400.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    field_node(root, fn() { "Notes" }, fn(slot) {
      textarea_node(slot, @ui.Field::new(text="Text"), placeholder="Write here") |> ignore
    }) |> ignore
    field_node(root, fn() { "Secret" }, fn(slot) {
      input_node(slot, @ui.Field::new(text="hidden"), placeholder="Password", secret=true) |> ignore
    }) |> ignore
    input_node(root, @ui.Field::new(), placeholder="Search") |> ignore
  })
  t.draw()
  assert_eq(t.get(TextField, label="Notes").value, "Text")
  assert_eq(t.get(TextField, label="Secret").value, "")
  assert_eq(t.get(TextField, label="Search").value, "")
}

///|
test "field limits its width on a wide page but fills a panel and a narrow page" {
  for (look, panel, expected) in [(Wide, false, 420.0), (Wide, true, 600.0), (Narrow, false, 600.0)] {
    let field : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=600.0, h=300.0, platform=0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      look_lent(root, look)
      if panel { panel_rows_lent(root, fn() { { sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false } }) }
      field.val = Some(field_node(root, fn() { "Name" }, fn(slot) {
        input_node(slot, @ui.Field::new(), placeholder="Type") |> ignore
      }))
    })
    t.draw()
    let drawn = @ui.view_tree().unwrap().drawn_of(field.val.unwrap().id()).unwrap()
    assert_eq(drawn.w, expected, msg="\{look}, panel=\{panel}")
  }
}
