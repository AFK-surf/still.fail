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
  reviewer_email.set("review@example.com")
  reviewer_password.set(" synthetic secret ")
  t.frame()
  assert_eq(t.get(@ui.TextField, label=tr("review.passwordLabel")).value, "")
  t.tap_text("显示密码")
  assert_true(reviewer_show.val)
  assert_eq(t.get(@ui.TextField, label=tr("review.passwordLabel")).value, "")
  assert_false(t.semantics_dump().contains(" synthetic secret "))
  t.back()
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
  let (submit_x, submit_y) = t.find_last("登录").unwrap()
  t.tap(submit_x, submit_y)
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
  let (x, y) = t.find_last("登录").unwrap()
  t.tap(x, y)
  assert_eq(names, ["auth.password", "auth.password.accept"])
  // Acceptance still includes cancellable profile work; only this explicit packet marks the durable boundary.
  assert_false(reviewer_saving.val)
  let attempt = reviewer_attempt.val
  progress.val.unwrap()({ "phase": "committing", "attempt": Json::string(attempt) })
  t.frame()
  assert_true(reviewer_saving.val)
  assert_true(t.find("正在完成登录…") is Some(_))
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
  // tap_text uses the first substring match, which is the inline error ending in “请重试。” here.
  // Select the last matching node: the actual Retry action below the error, as for Sign in above.
  let (retry_x, retry_y) = t.find_last("重试").unwrap()
  t.tap(retry_x, retry_y)
  assert_eq(names, ["auth.password", "auth.password.accept", "auth.password.recover"])
  assert_true(reviewer_checking.val)
  check.val.unwrap()(Ok((Json::null(), Bytes::new(0))))
  t.frame()
  assert_false(reviewer_open.val)
  assert_false(login_adding.val)
}

///|
test "review error focus is requested once per error, not each countdown tick or rebuild" {
  let t = tester("signin")
  t.native_answers("accessibility.reviewError", fn(_) { Json::null() })
  reviewer_open.val = true
  t.frame()
  t.run_for(@ui.nav_push_ms)
  reviewer_error.val = "login.rateLimited"
  reviewer_retry_at.val = (fixture("signin").now)() + 5000.0
  t.frame()
  t.frame()
  let requests = t.native_asked().filter(fn(call) { call.0 == "accessibility.reviewError" })
  assert_eq(requests.length(), 1)
  t.run_for(reviewer_countdown_tick_ms)
  t.frame()
  assert_eq(t.native_asked().filter(fn(call) { call.0 == "accessibility.reviewError" }).length(), 1)
  t.back()
  t.frame()
  t.frame()
}
