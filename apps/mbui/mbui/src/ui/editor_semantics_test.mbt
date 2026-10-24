///|
test "editor semantics: shown passwords remain redacted, ordinary and secret fields retain their values policy" {
  let password = @ui.Field::new(text="never expose this password")
  let ordinary = @ui.Field::new(text="ordinary words")
  let hidden = @ui.Field::new(text="another secret")
  let secret = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.editor("password", placeholder="Password", field=password, secret=secret.val, ime_action=@hostapi.ime_action_password) |> ignore
      c.editor("ordinary", placeholder="Message", field=ordinary) |> ignore
      c.editor("hidden", placeholder="Secret", field=hidden, secret=true) |> ignore
    }) |> ignore
  })
  assert_eq(t.get(@ui.TextField, label="Password").value, "")
  assert_eq(t.get(@ui.TextField, label="Message").value, "ordinary words")
  assert_eq(t.get(@ui.TextField, label="Secret").value, "")
  // Show changes only the custom rendering, not the field's credential classification.
  secret.val = false
  t.draw()
  assert_eq(password.text(), "never expose this password")
  assert_eq(t.get(@ui.TextField, label="Password").value, "")
  assert_false(t.semantics_dump().contains("never expose this password"))
  password.set("a changed shown password")
  t.draw()
  assert_eq(t.get(@ui.TextField, label="Password").value, "")
  assert_false(t.semantics_dump().contains("a changed shown password"))
  assert_eq(t.get(@ui.TextField, label="Message").value, "ordinary words")
  assert_eq(t.get(@ui.TextField, label="Secret").value, "")
}

///|
test "editor semantics: the actual label survives placeholder changes and Focus asks for editor focus" {
  let field = @ui.Field::new()
  let placeholder = Ref("Enter your account")
  let focused = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    focused.val = c.editor("account", placeholder=placeholder.val, accessible_label="Account", field~).focused
  })
  let account = t.get(@ui.TextField, label="Account")
  assert_true(account.actions.contains(@ui.Focus))
  assert_false(account.focused)
  assert_false(focused.val)
  placeholder.val = "A different hint"
  t.draw()
  assert_eq(t.get(@ui.TextField, label="Account").label, "Account")
  t.act(@ui.TextField, @ui.Focus, label="Account")
  assert_true(t.get(@ui.TextField, label="Account").focused)
  assert_true(focused.val)
  t.type_text("person@example.com")
  assert_eq(field.text(), "person@example.com")
  assert_eq(t.get(@ui.TextField, label="Account").value, "person@example.com")
}

///|
test "private editor values are opt-in and never change rendering or ordinary semantics" {
  let private_field = @ui.Field::new(text="synthetic-private@example.com")
  let ordinary = @ui.Field::new(text="ordinary@example.com")
  let t = @ui.Tester::new(fn(c) {
    c.column(fn() {
      c.editor("private", field=private_field, accessible_label="Reviewer email", private_value=true) |> ignore
      c.editor("ordinary", field=ordinary, accessible_label="Ordinary email") |> ignore
    }) |> ignore
  })
  t.set_a11y(true)
  t.frame()
  assert_eq(t.get(@ui.TextField, label="Reviewer email").value, "")
  assert_eq(t.get(@ui.TextField, label="Ordinary email").value, "ordinary@example.com")
  assert_false(t.a11y_said().contains("synthetic-private@example.com"))
  assert_true(t.a11y_said().contains("Reviewer email"))
  t.act(@ui.TextField, @ui.Focus, label="Reviewer email")
  t.type_text(".test")
  assert_eq(private_field.text(), "synthetic-private@example.com.test")
  assert_eq(t.get(@ui.TextField, label="Reviewer email").value, "")
}
