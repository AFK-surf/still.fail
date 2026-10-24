///|
test "review credentials: trim email only, validate basic address, accept nonempty passwords without a new policy" {
  assert_eq(reviewer_validation("", "secret"), "review.emailRequired")
  assert_eq(reviewer_validation("not-an-email", "secret"), "review.emailInvalid")
  assert_eq(reviewer_validation("a@@b.com", "secret"), "review.emailInvalid")
  assert_eq(reviewer_validation("a@.com", "secret"), "review.emailInvalid")
  assert_eq(reviewer_validation("a @b.com", "secret"), "review.emailInvalid")
  assert_eq(reviewer_validation(" a@b.com ", ""), "review.passwordRequired")
  assert_eq(reviewer_validation(" a@b.com ", " "), "")
  assert_eq(reviewer_validation("a@b.com", " x "), "")
}

///|
test "review errors never expose raw credential or host failures" {
  assert_eq(reviewer_safe_error({ "code": "invalid_credentials", "message": "private detail" }), "review.invalidCredentials")
  assert_eq(reviewer_safe_error({ "code": "login_wrong_password" }), "review.invalidCredentials")
  assert_eq(reviewer_safe_error({ "code": "rate_limited" }), "login.rateLimited")
  assert_eq(reviewer_safe_error({ "code": "host", "message": "offline maybe" }), "login.failed")
}

///|
test "review form: empty fields, show-hide and back erase credentials without signing in" {
  let t = tester("signin")
  reviewer_open.val = true
  t.frame()
  t.run_for(@ui.nav_push_ms)
  assert_eq(reviewer_nav.val.depth(), 2)
  assert_eq(reviewer_email.text(), "")
  assert_eq(reviewer_password.text(), "")
  assert_false(reviewer_show.val)
  assert_true(t.get(@ui.TextField, label=tr("review.emailLabel")).actions.contains(@ui.Focus))
  assert_true(t.get(@ui.TextField, label=tr("review.passwordLabel")).actions.contains(@ui.Focus))
  let submit = t.get(@ui.Button, label=tr("review.submit"))
  assert_true(submit.disabled)
  assert_false(submit.actions.contains(@ui.Activate))
  // A stale native Activate must not bypass the disabled contract.
  t.act(@ui.Button, @ui.Activate, label=tr("review.submit"))
  assert_false(reviewer_busy.val)
  assert_eq(reviewer_attempt.val, "")
  t.act(@ui.TextField, @ui.Focus, label=tr("review.emailLabel"))
  assert_true(t.get(@ui.TextField, label=tr("review.emailLabel")).focused)
  assert_eq(t.ime_action(), @hostapi.ime_action_email)
  t.type_text("review@example.com")
  // The email keyboard's Next action is delivered as Enter, not a pointer hit on the password.
  t.press("Enter")
  assert_eq(reviewer_email.text(), "review@example.com")
  assert_true(t.get(@ui.TextField, label=tr("review.passwordLabel")).focused)
  assert_eq(t.ime_action(), @hostapi.ime_action_password)
  t.type_text(" synthetic secret ")
  assert_false(t.get(@ui.Button, label=tr("review.submit")).disabled)
  assert_true(t.get(@ui.Button, label=tr("review.submit")).actions.contains(@ui.Activate))
  assert_eq(t.get(@ui.TextField, label=tr("review.passwordLabel")).value, "")
  t.act(@ui.Button, @ui.Activate, label=tr("review.showPassword"))
  assert_true(reviewer_show.val)
  assert_eq(t.get(@ui.TextField, label=tr("review.passwordLabel")).value, "")
  assert_false(t.semantics_dump().contains(" synthetic secret "))
  t.act(@ui.Button, @ui.Activate, label=tr("review.hidePassword"))
  assert_false(reviewer_show.val)
  assert_eq(t.get(@ui.TextField, label=tr("review.passwordLabel")).value, "")
  t.act(@ui.Button, @ui.Activate, label=tr("common.back"))
  assert_false(reviewer_open.val)
  assert_eq(reviewer_password.text(), "")
  assert_eq(reviewer_email.text(), "")
  assert_false(reviewer_show.val)
}

///|
test "review leaving an account addition keeps the original account and invalidates late callbacks" {
  reset()
  let calls : Array[String] = []
  let answer : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
  let source : Source = {
    ..fixture("home"),
    call: fn(name, _, done) {
      // The home fixture legitimately reads background topics/calls. Count only password auth, so the
      // duplicate-submit assertion catches extra auth without mistaking unrelated page work for a submission.
      if name.has_prefix("auth.password") { calls.push(name) }
      if name == "auth.password" {
        answer.val = Some(done)
      } else if name == "auth.password.cancel" {
        done(Ok({ "cancelled": true, "state": "cancelled" }))
      } else { done(Ok(Json::null())) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, source) }, w=390.0, h=844.0)
  login_adding.val = true
  reviewer_open.val = true
  reviewer_email.set("review@example.com")
  reviewer_password.set("synthetic secret")
  t.frame()
  t.run_for(@ui.nav_push_ms)
  t.act(@ui.TextField, @ui.Focus, label=tr("review.passwordLabel"))
  t.press("Enter")
  assert_eq(calls.length(), 1)
  assert_eq(calls[0], "auth.password")
  assert_true(reviewer_busy.val)
  assert_eq(reviewer_password.text(), "")
  // Enter or another click while pending cannot dispatch another password request.
  t.tap_text("正在登录…")
  assert_eq(calls.length(), 1)
  t.back()
  assert_eq(calls[1], "auth.password.cancel")
  match answer.val { Some(done) => done(Ok(Json::null())); None => abort("password call expected") }
  assert_eq(calls.length(), 2)
  assert_false(reviewer_busy.val)
  t.run_for(@ui.nav_push_ms)
  t.back()
  assert_false(login_adding.val)
  t.frame()
  assert_true(t.find("星火工作室") is Some(_))
}

///|
test "review final save is phase-bound, bounded, and recovery retries only the original stored attempt" {
  reset()
  let names : Array[String] = []
  let progress : Ref[((Json) -> Unit)?] = Ref(None)
  let finish : Ref[((Result[(Json, Bytes), Json]) -> Unit)?] = Ref(None)
  let check : Ref[((Result[(Json, Bytes), Json]) -> Unit)?] = Ref(None)
  let source : Source = {
    ..fixture("home"),
    call: fn(name, _, done) {
      if name.has_prefix("auth.password") { names.push(name) }
      done(Ok(Json::null()))
    },
    read_going: fn(name, _, on_value, done) {
      names.push(name)
      if name == "auth.password.accept" { progress.val = Some(on_value); finish.val = Some(done) }
      else if name == "auth.password.recover" { check.val = Some(done) }
      else { done(Ok((Json::null(), Bytes::new(0)))) }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, source) }, w=390.0, h=844.0)
  t.native_answers("accessibility.reviewError", fn(_) { Json::null() })
  login_adding.val = true
  reviewer_open.val = true
  reviewer_email.set("review@example.com")
  reviewer_password.set("synthetic secret")
  t.frame()
  t.run_for(@ui.nav_push_ms)
  t.act(@ui.Button, @ui.Activate, label=tr("review.submit"))
  assert_eq(names, ["auth.password", "auth.password.accept"])
  // Acceptance still includes cancellable profile work; only this explicit packet marks the durable boundary.
  assert_false(reviewer_saving.val)
  let attempt = reviewer_attempt.val
  progress.val.unwrap()({ "phase": "committing", "attempt": Json::string(attempt) })
  t.frame()
  assert_true(reviewer_saving.val)
  assert_true(t.find("正在完成登录…") is Some(_))
  assert_true(t.get(@ui.Button, label=tr("login.finishing")).disabled)
  assert_false(t.get(@ui.Button, label=tr("login.finishing")).actions.contains(@ui.Activate))
  assert_true(t.get(@ui.Button, label=tr("common.back")).disabled)
  assert_true(t.get(@ui.Button, label=tr("review.showPassword")).disabled)
  t.act(@ui.Button, @ui.Activate, label=tr("common.back"))
  t.back()
  assert_true(reviewer_open.val)
  assert_eq(reviewer_nav.val.depth(), 2)
  assert_eq(names.length(), 2)
  // This is a local UI wait bound, not a server retry-after and not proof the write failed.
  t.run_for(reviewer_save_budget_ms)
  assert_false(reviewer_busy.val)
  assert_true(reviewer_recovery.val)
  assert_true(t.find("暂时无法确认登录状态，请重试。") is Some(_))
  finish.val.unwrap()(Ok((Json::null(), Bytes::new(0))))
  t.frame()
  assert_true(reviewer_open.val)
  assert_eq(reviewer_attempt.val, attempt)
  let recovery_error = t.get(@ui.Status, label=tr("login.savedStateUnavailable"))
  assert_true(recovery_error.id != 0)
  assert_false(recovery_error.actions.contains(@ui.Activate))
  assert_true(t.get(@ui.Button, label=tr("common.back")).disabled)
  // Semantic selection cannot confuse the error's “retry” wording with the real Retry button.
  t.act(@ui.Button, @ui.Activate, label=tr("common.retry"))
  assert_eq(names, ["auth.password", "auth.password.accept", "auth.password.recover"])
  assert_true(reviewer_checking.val)
  assert_true(t.get(@ui.Button, label=tr("login.checkingSavedState")).disabled)
  assert_false(t.get(@ui.Button, label=tr("login.checkingSavedState")).actions.contains(@ui.Activate))
  assert_true(t.get(@ui.Button, label=tr("common.back")).disabled)
  check.val.unwrap()(Ok((Json::null(), Bytes::new(0))))
  t.frame()
  assert_false(reviewer_open.val)
  assert_false(login_adding.val)
}

///|
test "review error focus is requested once per error, not each countdown tick or rebuild" {
  reset()
  let now = Ref(0.0)
  let source : Source = { ..fixture("signin"), now: fn() { now.val } }
  let t = @ui.Tester::new(fn(c) { view(c, source) }, w=390.0, h=844.0)
  t.native_answers("accessibility.reviewError", fn(_) { Json::null() })
  reviewer_open.val = true
  t.frame()
  t.run_for(@ui.nav_push_ms)
  reviewer_error.val = "login.rateLimited"
  reviewer_retry_at.val = now.val + 5000.0
  t.frame()
  t.frame()
  let error = t.get(@ui.Status)
  assert_eq(error.label, fill("login.rateLimitedSeconds", [("seconds", "5")]))
  assert_true(error.id != 0)
  assert_false(error.actions.contains(@ui.Activate))
  let requests = t.native_asked().filter(fn(call) { call.0 == "accessibility.reviewError" })
  assert_eq(requests.length(), 1)
  now.val += reviewer_countdown_tick_ms
  t.run_for(reviewer_countdown_tick_ms)
  t.frame()
  assert_eq(t.get(@ui.Status).id, error.id)
  assert_eq(t.get(@ui.Status).label, fill("login.rateLimitedSeconds", [("seconds", "4")]))
  assert_eq(t.native_asked().filter(fn(call) { call.0 == "accessibility.reviewError" }).length(), 1)
  t.back()
  t.frame()
  t.frame()
}

///|
test "review semantic blur and Next validate email with a stable localized error node" {
  let t = tester("signin")
  t.native_answers("accessibility.reviewError", fn(_) { Json::null() })
  reviewer_open.val = true
  t.frame()
  t.run_for(@ui.nav_push_ms)
  t.act(@ui.TextField, @ui.Focus, label=tr("review.emailLabel"))
  t.act(@ui.TextField, @ui.Focus, label=tr("review.passwordLabel"))
  assert_true(t.get(@ui.TextField, label=tr("review.passwordLabel")).focused)
  let required = t.get(@ui.Status, label=tr("review.emailRequired"))
  assert_true(required.id != 0)
  t.act(@ui.TextField, @ui.Focus, label=tr("review.emailLabel"))
  t.type_text("not-an-email")
  t.press("Enter")
  let invalid = t.get(@ui.Status, label=tr("review.emailInvalid"))
  assert_eq(invalid.id, required.id)
  assert_eq(invalid.value, "")
  assert_false(invalid.actions.contains(@ui.Activate))
  t.frame()
  assert_eq(t.get(@ui.Status, label=tr("review.emailInvalid")).id, invalid.id)
  assert_true(t.get(@ui.Button, label=tr("review.submit")).disabled)
  t.act(@ui.Button, @ui.Activate, label=tr("review.submit"))
  assert_false(reviewer_busy.val)
  assert_eq(reviewer_attempt.val, "")
  t.act(@ui.Button, @ui.Activate, label=tr("common.back"))
  assert_false(reviewer_open.val)
}

///|
test "review native bridge markers scope welcome and two credential fields without semantic secrets" {
  let t = tester("signin")
  t.set_a11y(true)
  t.frame()
  assert_true(t.a11y_said().contains("\u{1F}still.fail.reviewer.welcome\u{1F}"))
  t.act(@ui.Button, @ui.Activate, label=tr("login.reviewAction"))
  t.run_for(@ui.nav_push_ms)
  let roots = t.semantics().filter(fn(node) { node.role == @ui.Group && node.description == "still.fail.reviewer" })
  assert_eq(roots.length(), 1)
  assert_eq(roots[0].value, "")
  assert_eq(t.semantics().filter(fn(node) { !node.hidden && node.role == @ui.TextField }).length(), 2)
  reviewer_email.set("review@example.com")
  reviewer_password.set("synthetic shown credential")
  t.frame()
  t.act(@ui.Button, @ui.Activate, label=tr("review.showPassword"))
  let password = t.get(@ui.TextField, label=tr("review.passwordLabel"))
  let lines = t.a11y_said()
  assert_true(lines.contains("\u{1F}still.fail.reviewer\u{1F}"))
  assert_false(lines.contains("synthetic shown credential"))
  assert_false(lines.contains("review@example.com"))
  assert_true(lines.contains(tr("review.emailLabel")))
  assert_eq(t.get(@ui.TextField, label=tr("review.emailLabel")).value, "")
  let mut password_rows = 0
  for line in lines.split("\n") {
    if line == "" { continue }
    let fields = line.split("\u{1F}").map(fn(field) { field.to_string() }).to_array()
    assert_eq(fields.length(), 16)
    if fields[3] == "TextField" && fields[9] == tr("review.passwordLabel") {
      password_rows += 1
      // Native actions address widget field 2, never the serialized node identity in field 0.
      assert_eq(fields[2], password.id.to_string())
      assert_eq(fields[10], "")
      assert_eq(fields[15], "f")
    }
  }
  assert_eq(password_rows, 1)
  t.act(@ui.Button, @ui.Activate, label=tr("common.back"))
  t.run_for(@ui.nav_push_ms)
  assert_false(t.a11y_said().contains("\u{1F}still.fail.reviewer\u{1F}"))
  assert_true(t.a11y_said().contains("\u{1F}still.fail.reviewer.welcome\u{1F}"))
}

///|
test "review passive native reveal preserves editor focus in a keyboard-constrained viewport" {
  reset()
  let source = fixture("signin")
  reviewer_open.val = true
  let viewport : Ref[(Double, Double, Double, Double)?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    login_page(c, source, true)
    viewport.val = c.laid_rect(c.id("login/review-scroll"))
  }, w=320.0, h=560.0)
  t.native_answers("accessibility.reviewError", fn(_) { Json::null() })
  t.frame()
  // Like ios_app.m: resize the app frame AND report the declared IME inset.
  // set_ime_inset alone never resizes a Tester's frame.
  t.set_ime_inset(220.0)
  t.resize(320.0, 340.0)
  let bottom = 340.0 - status_top() - nav_foot()
  let (_, top, _, height) = viewport.val.unwrap()
  assert_eq(height, bottom)
  assert_eq(top + height, bottom)
  t.act(@ui.TextField, @ui.Focus, label=tr("review.emailLabel"))
  // Passive native traversal must not activate disabled Submit, unfocus email, or dismiss its IME.
  for label in [tr("review.showPassword"), tr("review.submit"), tr("common.back")] {
    let target = t.get(@ui.Button, label~)
    t.post("still.fail.reviewer.reveal", "{\"id\":" + target.id.to_string() + "}")
    t.frame()
    // Another ordinary rebuild must not snap back to the active email editor.
    t.frame()
    let (_, y, _, h) = t.get(@ui.Button, label~).rect
    assert_true(y >= 0.0)
    assert_true(y + h <= bottom)
    assert_true(t.get(@ui.TextField, label=tr("review.emailLabel")).focused)
  }
  assert_false(reviewer_busy.val)
  reviewer_error.val = "review.invalidCredentials"
  t.frame()
  let status = t.get(@ui.Status, label=tr("review.invalidCredentials"))
  t.post("still.fail.reviewer.reveal", "{\"id\":" + status.id.to_string() + "}")
  t.frame()
  let (_, y, _, h) = t.get(@ui.Status, label=tr("review.invalidCredentials")).rect
  assert_true(y >= 0.0)
  assert_true(y + h <= bottom)
  assert_eq(reviewer_attempt.val, "")
}

///|
test "review native tap and Next reveal focused editors after host keyboard resize exactly once" {
  reset()
  let calls : Array[String] = []
  let source : Source = {
    ..fixture("signin"),
    call: fn(name, _, _) { calls.push(name) },
  }
  reviewer_open.val = true
  let viewport : Ref[(Double, Double, Double, Double)?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    login_page(c, source, true)
    viewport.val = c.laid_rect(c.id("login/review-scroll"))
  }, w=320.0, h=780.0)
  t.frame()
  let (_, _, _, full_height) = viewport.val.unwrap()
  assert_eq(full_height, 780.0 - status_top() - nav_foot())
  // An ordinary pointer tap, not a semantic Focus request or passive reveal packet.
  let (x, y, w, h) = t.get(@ui.TextField, label=tr("review.emailLabel")).rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_true(t.get(@ui.TextField, label=tr("review.emailLabel")).focused)
  t.type_text("review@example.com")
  // The native host owns keyboard avoidance: both values describe the SAME occlusion.
  t.set_ime_inset(440.0)
  t.resize(320.0, 340.0)
  let bottom = 340.0 - status_top() - nav_foot()
  let (_, top, _, height) = viewport.val.unwrap()
  assert_eq(height, bottom)
  assert_eq(top + height, bottom)
  let (_, ey, _, eh) = t.get(@ui.TextField, label=tr("review.emailLabel")).rect
  assert_true(eh > 0.0)
  assert_true(ey >= top)
  assert_true(ey + eh <= bottom)
  t.press("Enter")
  let password = t.get(@ui.TextField, label=tr("review.passwordLabel"))
  assert_true(password.focused)
  let (_, py, _, ph) = password.rect
  assert_true(ph > 0.0)
  assert_true(py >= top)
  assert_true(py + ph <= bottom)
  assert_eq(t.ime_action(), @hostapi.ime_action_password)
  assert_eq(reviewer_email.text(), "review@example.com")
  assert_true(reviewer_email_valid(reviewer_email.text()))
  assert_eq(reviewer_error.val, "")
  assert_false(reviewer_busy.val)
  assert_eq(reviewer_attempt.val, "")
  assert_eq(calls.length(), 0)
}
