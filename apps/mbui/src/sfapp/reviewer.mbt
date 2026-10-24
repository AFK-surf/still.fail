// Reviewer password authentication is attempt-scoped. The core prepares tokens without publishing an account;
// only a still-visible form accepts them. Leaving invalidates the attempt in the core, not merely its rendering.

///|
let login_adding : Ref[Bool] = Ref(false)

///|
let reviewer_open : Ref[Bool] = Ref(false)

///|
let reviewer_pop : Ref[() -> Bool] = Ref(fn() { true })

///|
// Local UI deadline only: expiry means UNKNOWN, never that a native write failed.
let reviewer_save_budget_ms : Double = 15000.0

///|
let reviewer_countdown_tick_ms : Double = 1000.0

///|
fn reviewer_stack() -> @ui.Nav[Bool] {
  @ui.Nav::new(false, can_pop=fn(review) { !review || (reviewer_pop.val)() })
}

///|
let reviewer_nav : Ref[@ui.Nav[Bool]] = Ref(reviewer_stack())

///|
let reviewer_cancelling : Ref[Bool] = Ref(false)

///|
let reviewer_saving : Ref[Bool] = Ref(false)

///|
let reviewer_recovery : Ref[Bool] = Ref(false)

///|
let reviewer_checking : Ref[Bool] = Ref(false)

///|
let reviewer_deadline : Ref[Double] = Ref(0.0)

///|
// Operation identities, unlike view state, are never reused: a timed-out callback cannot finish a newer check.
let reviewer_operation : Ref[Int] = Ref(0)

///|
let reviewer_a11y_sent : Ref[String] = Ref("")

///|
// Kept until the host's acknowledgements are consumed, including after successful sign-in leaves this page.
// These calls carry only safe localized error text and its bounds, never credentials.
let reviewer_a11y_calls : Array[@ui.NativeCall] = []

///|
fn reviewer_accessibility_tick() -> Unit {
  let mut i = reviewer_a11y_calls.length() - 1
  while i >= 0 {
    if reviewer_a11y_calls[i].got() is Some(_) { reviewer_a11y_calls.remove(i) |> ignore }
    i -= 1
  }
}

///|
fn reviewer_accessibility_clear() -> Unit {
  if reviewer_a11y_sent.val != "" {
    reviewer_a11y_sent.val = ""
    reviewer_a11y_calls.push(@ui.native_call("accessibility.reviewError", { "text": "" }))
  }
}

///|
let reviewer_email : @ui.Field = @ui.Field::new()

///|
let reviewer_password : @ui.Field = @ui.Field::new()

///|
let reviewer_show : Ref[Bool] = Ref(false)

///|
let reviewer_reveal_id : Ref[Int] = Ref(0)

///|
fn init {
  // Passive VoiceOver traversal reveals a widget without changing the active editor or keyboard.
  @ui.on_message("still.fail.reviewer.reveal", fn(json, _) {
    let value = @json.parse(json) catch { _ => return }
    reviewer_reveal_id.val = number(Some(value), "id").to_int()
  })
}

///|
let reviewer_busy : Ref[Bool] = Ref(false)

///|
let reviewer_error : Ref[String] = Ref("")

///|
let reviewer_attempt : Ref[String] = Ref("")

///|
// kept across runs: an attempt id must never be reused while an old core callback could still arrive.
let reviewer_serial : Ref[Int] = Ref(0)

///|
let reviewer_email_focused : Ref[Bool] = Ref(false)

///|
let reviewer_password_focused : Ref[Bool] = Ref(false)

///|
let reviewer_retry_at : Ref[Double] = Ref(0.0)

///|
fn reviewer_reset() -> Unit {
  reviewer_accessibility_clear()
  reviewer_saving.val = false
  reviewer_recovery.val = false
  reviewer_checking.val = false
  reviewer_deadline.val = 0.0
  reviewer_operation.val += 1
  reviewer_nav.val = reviewer_stack()
  reviewer_cancelling.val = false
  login_adding.val = false
  reviewer_open.val = false
  reviewer_email.set("")
  reviewer_password.set("")
  reviewer_reveal_id.val = 0
  reviewer_show.val = false
  reviewer_busy.val = false
  reviewer_error.val = ""
  reviewer_attempt.val = ""
  reviewer_email_focused.val = false
  reviewer_password_focused.val = false
  reviewer_retry_at.val = 0.0
}

///|
// A confirmed web completion also closes account addition, including signing in to an identity already in the
// list (which need not change the accounts topic). A cancellation/failure never calls this.
pub fn web_signed_in() -> Unit {
  if login_adding.val && !reviewer_open.val { reviewer_reset() }
}

///|
// Only a non-pending or acknowledged-cancelled attempt may leave. The native/system/edge Back paths all
// reach this same pre-pop guard. In-flight durable commits are not represented as successful cancellation.
fn reviewer_try_leave(c : @ui.Ctx, src : Source) -> Bool {
  if reviewer_saving.val || reviewer_recovery.val || reviewer_checking.val { return false }
  if !reviewer_busy.val {
    reviewer_leave(c, src)
    return true
  }
  if reviewer_cancelling.val { return false }
  let attempt = reviewer_attempt.val
  if attempt == "" { return false }
  reviewer_cancelling.val = true
  reviewer_password.set("")
  reviewer_show.val = false
  c.unfocus()
  (src.call)("auth.password.cancel", Json::object({ "attempt": Json::string(attempt) }), fn(result) {
    if reviewer_attempt.val != attempt { return }
    reviewer_cancelling.val = false
    match result {
      Ok(answer) if flag(Some(answer), "cancelled") => {
        reviewer_attempt.val = ""
        reviewer_busy.val = false
        // This second pop is now permitted; its guard clears the form before the slide begins.
        reviewer_nav.val.pop() |> ignore
      }
      Ok(answer) if text(Some(answer), "state") == "committing" || text(Some(answer), "state") == "committed" => {
        // The progress packet may still be in flight. A refused cancellation is not permission to dismiss.
        reviewer_saving.val = true
        reviewer_deadline.val = c.now + reviewer_save_budget_ms
        c.wake_in(reviewer_save_budget_ms)
      }
      // An unacknowledged transport failure retains ownership and the original request's result.
      _ => ()
    }
  })
  false
}

///|
fn reviewer_leave(c : @ui.Ctx, src : Source) -> Unit {
  c.tell("review-a11y-clear", fn() { reviewer_accessibility_clear() })
  let attempt = reviewer_attempt.val
  reviewer_attempt.val = ""
  reviewer_password.set("")
  reviewer_email.set("")
  reviewer_reveal_id.val = 0
  reviewer_show.val = false
  reviewer_busy.val = false
  reviewer_cancelling.val = false
  reviewer_error.val = ""
  reviewer_open.val = false
  c.unfocus()
  if attempt != "" {
    (src.call)("auth.password.cancel", Json::object({ "attempt": Json::string(attempt) }), fn(_) {  })
  }
}

///|
fn reviewer_email_valid(email : String) -> Bool {
  let parts = email.trim().split("@").map(fn(part) { part.to_string() }).to_array()
  parts.length() == 2 && parts[0] != "" && parts[1].contains(".") &&
  !parts[1].has_prefix(".") && !parts[1].has_suffix(".") &&
  !email.trim().contains(" ") && !email.contains("\n") && !email.contains("\t")
}

///|
fn reviewer_validation(email : String, password : String) -> String {
  if email.trim() == "" {
    "review.emailRequired"
  } else if !reviewer_email_valid(email) {
    "review.emailInvalid"
  } else if password == "" {
    "review.passwordRequired"
  } else {
    ""
  }
}

///|
fn reviewer_safe_error(error : Json) -> String {
  match text(Some(error), "code") {
    "login_wrong_password" | "invalid_credentials" => "review.invalidCredentials"
    "rate_limited" => "login.rateLimited"
    // Host failures are not reliably classified as offline/timeout: never infer those from raw message text.
    _ => "login.failed"
  }
}

///|
fn reviewer_uncertain(c : @ui.Ctx) -> Unit {
  reviewer_operation.val += 1
  reviewer_password.set("")
  reviewer_show.val = false
  reviewer_saving.val = false
  reviewer_checking.val = false
  reviewer_busy.val = false
  reviewer_cancelling.val = false
  reviewer_recovery.val = true
  reviewer_deadline.val = 0.0
  reviewer_error.val = "login.savedStateUnavailable"
  c.unfocus()
}

///|
fn reviewer_progress(c : @ui.Ctx, attempt : String, operation : Int, value : Json) -> Unit {
  if reviewer_attempt.val != attempt || reviewer_operation.val != operation || !reviewer_open.val { return }
  if text(Some(value), "attempt") == attempt && text(Some(value), "phase") == "committing" {
    reviewer_password.set("")
    reviewer_show.val = false
    if !reviewer_saving.val {
      reviewer_saving.val = true
      reviewer_deadline.val = c.now + reviewer_save_budget_ms
      c.wake_in(reviewer_save_budget_ms)
    }
    c.unfocus()
  }
}

///|
fn reviewer_recover(c : @ui.Ctx, src : Source) -> Unit {
  if !reviewer_recovery.val || reviewer_checking.val { return }
  let attempt = reviewer_attempt.val
  reviewer_operation.val += 1
  let operation = reviewer_operation.val
  reviewer_checking.val = true
  reviewer_busy.val = true
  reviewer_error.val = ""
  reviewer_deadline.val = c.now + reviewer_save_budget_ms
  c.wake_in(reviewer_save_budget_ms)
  (src.read_going)("auth.password.recover", { "attempt": Json::string(attempt) }, fn(_) {  }, fn(result) {
    if reviewer_attempt.val != attempt || reviewer_operation.val != operation || !reviewer_open.val { return }
    match result {
      Ok(_) => reviewer_reset()
      Err(error) => reviewer_failed(c, src, attempt, error)
    }
  })
}

///|
fn reviewer_failed(c : @ui.Ctx, src : Source, attempt : String, error : Json) -> Unit {
  if reviewer_attempt.val != attempt { return }
  reviewer_password.set("")
  reviewer_show.val = false
  let code = text(Some(error), "code")
  if code == "session_commit_unknown" || ((reviewer_saving.val || reviewer_recovery.val) && code != "session_storage_unavailable") {
    // Only an explicit confirmed storage failure releases this attempt. Transport/host failures during a
    // check do not prove that a quarantined native write failed and must not enable another password login.
    reviewer_uncertain(c)
    return
  }
  let cancelled = reviewer_cancelling.val
  reviewer_cancelling.val = false
  let save_failed = reviewer_saving.val || reviewer_recovery.val || text(Some(error), "code") == "session_storage_unavailable"
  reviewer_saving.val = false
  reviewer_recovery.val = false
  reviewer_checking.val = false
  reviewer_deadline.val = 0.0
  reviewer_busy.val = false
  reviewer_email_focused.val = false
  reviewer_password_focused.val = false
  reviewer_error.val = if save_failed { "login.saveFailed" } else { reviewer_safe_error(error) }
  let seconds = number(Some(error), "retry_after")
  if seconds > 0.0 { reviewer_retry_at.val = (src.now)() + seconds * 1000.0 }
  (src.call)("auth.password.cancel", Json::object({ "attempt": Json::string(attempt) }), fn(_) {  })
  reviewer_attempt.val = ""
  c.unfocus()
  if cancelled { reviewer_nav.val.pop() |> ignore }
}

///|
fn reviewer_submit(c : @ui.Ctx, src : Source) -> Unit {
  if reviewer_busy.val || reviewer_recovery.val || (src.signing_in)() || (src.now)() < reviewer_retry_at.val { return }
  let invalid = reviewer_validation(reviewer_email.text(), reviewer_password.text())
  if invalid != "" {
    reviewer_error.val = invalid
    return
  }
  reviewer_serial.val += 1
  let attempt = "mbui-review-" + (src.now)().to_string() + "-" + reviewer_serial.val.to_string()
  reviewer_attempt.val = attempt
  reviewer_busy.val = true
  reviewer_error.val = ""
  let params = Json::object({
    "attempt": Json::string(attempt),
    "email": Json::string(reviewer_email.text().trim().to_string()),
    "password": Json::string(reviewer_password.text()),
  })
  // No saved defaults, history, or credential logging. Clear the editor immediately after constructing the request.
  reviewer_password.set("")
  reviewer_show.val = false
  c.unfocus()
  (src.call)("auth.password", params, fn(result) {
    if reviewer_attempt.val != attempt || !reviewer_open.val { return }
    match result {
      Err(error) => reviewer_failed(c, src, attempt, error)
      Ok(_) => {
        if reviewer_cancelling.val { return }
        reviewer_operation.val += 1
        let operation = reviewer_operation.val
        // Profile work remains cancellable. Only the explicit committing progress crosses the save boundary.
        (src.read_going)("auth.password.accept", Json::object({ "attempt": Json::string(attempt) }),
          fn(value) { reviewer_progress(c, attempt, operation, value) }, fn(accepted) {
          if reviewer_attempt.val != attempt || reviewer_operation.val != operation || !reviewer_open.val { return }
          match accepted {
            Err(error) => reviewer_failed(c, src, attempt, error)
            Ok(_) => {
              reviewer_attempt.val = ""
              reviewer_reset()
            }
          }
        })
      }
    }
  })
}

///|
fn login_action(c : @ui.Ctx, key : String, words : String, primary : Bool, disabled : Bool) -> Bool {
  let id = c.id(key)
  c.focusable(id)
  let node = c.box(id~, label=words, disabled~,
    style=if primary { @sf.login_primary_action } else { @sf.login_action }, fn() {
      c.text(words, style=if primary { @sf.login_primary_words } else { @sf.login_action_words }) |> ignore
    })
  c.semantics(node, Button, id~, label=words, disabled~, actions=if disabled { [Focus] } else { [Activate, Focus] })
  !disabled && c.clicked(id)
}

///|
fn login_view(c : @ui.Ctx, src : Source) -> Unit {
  reviewer_pop.val = fn() { reviewer_try_leave(c, src) }
  if reviewer_open.val && !reviewer_nav.val.top() { reviewer_nav.val.push(true) }
  c.with_theme(@sf.login_theme(c.theme()), fn() {
    c.nav(reviewer_nav.val, fn(review) { login_page(c, src, review) }, bg=@sf.theme().p.bg) |> ignore
  })
}

///|
fn login_reveal(c : @ui.Ctx, key : String, review : Bool) -> Unit {
  let viewport = c.laid_rect(c.id(key))
  let mut dy = 0.0
  // A list's row 0 has its own id scope. Read unclipped layout, never the clipped hit rect.
  c.scope(0, fn() {
    let keys = if review {
      ["review/back", "review/email", "review/password", "review/show", "review/error",
        "review/submit", "review/recover", "review/checking", "review/finishing"]
    } else { ["login/back", "sign-in", "login/reviewer"] }
    for target in keys {
      let id = c.id(target)
      if c.action_asked(id, Focus) || reviewer_reveal_id.val == id {
        match (viewport, c.laid_rect(id)) {
          (Some((_, top, _, height)), Some((_, y, _, h))) if height > 0.0 => {
            dy = if h > height || y < top { y - top } else if y + h > top + height { y + h - top - height } else { 0.0 }
          }
          _ => ()
        }
      }
    }
  })
  if dy != 0.0 { c.list_scroll_by(key, dy) }
  let requested = reviewer_reveal_id.val
  if requested != 0 {
    c.tell("review-reveal-consumed", fn() {
      if reviewer_reveal_id.val == requested { reviewer_reveal_id.val = 0 }
    })
  }
}

///|
fn login_page(c : @ui.Ctx, src : Source, review : Bool) -> Unit {
  let t = @sf.theme()
  let busy = reviewer_busy.val || (src.signing_in)()
  if !review && login_adding.val {
    c.on_back(fn() { if !busy { login_adding.val = false } })
  }
  let scroll_key = if review { "login/review-scroll" } else { "login/welcome-scroll" }
  login_reveal(c, scroll_key, review)
  c.list(scroll_key, 1, 720.0, fn(_) {
    c.box(style=@sf.login_page, fn() {
      let column = c.box(style=@sf.login_column, fn() {
        if review {
          reviewer_form(c, src)
        } else {
          if login_adding.val && login_action(c, "login/back", tr("common.back"), false, busy) {
            login_adding.val = false
          }
          c.hidden_from_semantics(fn() {
            @sf.drawable(c, if t.dark { "illus_sign_in_dark" } else { "illus_sign_in" },
              dmin(if c.height < 650.0 { 160.0 } else { 260.0 }, c.width - 48.0)) |> ignore
          })
          c.text(tr("android-settings.signIn.title"), style=@sf.login_welcome_title) |> ignore
          c.text(tr("android-settings.signIn.note"), style=@sf.login_welcome_body) |> ignore
          c.box(style=@sf.login_notice, fn() {
            c.text(tr("login.accountNotice"), style=@sf.login_body) |> ignore
          }) |> ignore
          if login_action(c, "sign-in", tr(if busy { "login.webWaiting" } else { "login.webAction" }), false, busy) {
            (src.sign_in)()
          }
          c.text(tr("login.webHint"), style=@sf.login_hint) |> ignore
          if login_action(c, "login/reviewer", tr("login.reviewAction"), false, busy) {
            reviewer_open.val = true
            reviewer_show.val = false
            reviewer_email_focused.val = false
            reviewer_email.set("")
            reviewer_password.set("")
            reviewer_error.val = ""
          }
          c.text(tr("login.reviewHint"), style=@sf.login_hint) |> ignore
        }
      })
      // Native accessibility is scoped to these login trees, never other editors or account pages.
      c.semantics(column, Group, description=if review { "still.fail.reviewer" } else { "still.fail.reviewer.welcome" })
    }) |> ignore
  }, h=Px(dmax(0.0, c.height - status_top() - nav_foot() - c.ime_inset()))) |> ignore
}

///|
fn reviewer_field(c : @ui.Ctx, key : String, label : String, placeholder : String, field : @ui.Field, secret : Bool, ime_action : Int) -> @ui.EditorResult {
  let t = @sf.theme()
  c.text(tr(label), style=@sf.login_field_label) |> ignore
  let mut result : @ui.EditorResult? = None
  c.box(style=@sf.login_field, fn() {
    result = Some(c.editor(key, field~, placeholder=tr(placeholder), accessible_label=tr(label), private_value=true, secret~, plain=true, max_lines=1,
      font_size=@sf.login_editor_size, line=@sf.login_editor_line, trim=false, color=t.p.text, placeholder_color=t.p.muted,
      ime_action~))
  }) |> ignore
  result.unwrap()
}

///|
fn reviewer_form(c : @ui.Ctx, src : Source) -> Unit {
  if reviewer_deadline.val > 0.0 && (reviewer_saving.val || reviewer_checking.val) {
    if c.now >= reviewer_deadline.val {
      reviewer_uncertain(c)
    } else { c.wake_in(reviewer_deadline.val - c.now) }
  }
  if login_action(c, "review/back", tr("common.back"), false, reviewer_cancelling.val || reviewer_saving.val || reviewer_recovery.val || reviewer_checking.val) {
    reviewer_nav.val.pop() |> ignore
  }
  c.text(tr("review.title"), style=@sf.login_title) |> ignore
  c.text(tr("review.body"), style=@sf.login_explanation) |> ignore
  let email = reviewer_field(c, "review/email", "review.emailLabel", "review.emailPlaceholder", reviewer_email, false, @hostapi.ime_action_email)
  // Editors consume submitted text like a composer. A form's Next must retain the address for validation/auth.
  if email.submitted is Some(words) { reviewer_email.set(words) }
  if reviewer_email_focused.val && !email.focused && !reviewer_busy.val && !reviewer_recovery.val {
    reviewer_error.val = if reviewer_email.text().trim() == "" { "review.emailRequired" } else if !reviewer_email_valid(reviewer_email.text()) { "review.emailInvalid" } else { "" }
  }
  reviewer_email_focused.val = email.focused
  if email.submitted is Some(_) { c.focus_editor("review/password") }
  let password = reviewer_field(c, "review/password", "review.passwordLabel", "review.passwordPlaceholder", reviewer_password, !reviewer_show.val, @hostapi.ime_action_password)
  // Keep Done's consumed text only until reviewer_submit builds the attempt and immediately erases it.
  if password.submitted is Some(words) { reviewer_password.set(words) }
  if reviewer_password_focused.val && !password.focused && !reviewer_busy.val && !reviewer_recovery.val && reviewer_password.text() == "" {
    reviewer_error.val = "review.passwordRequired"
  }
  reviewer_password_focused.val = password.focused
  if login_action(c, "review/show", tr(if reviewer_show.val { "review.hidePassword" } else { "review.showPassword" }), false, reviewer_busy.val || reviewer_recovery.val) {
    reviewer_show.val = !reviewer_show.val
  }
  if reviewer_error.val != "" {
    let remaining = (reviewer_retry_at.val - (src.now)()) / 1000.0
    let seconds = if remaining > remaining.to_int().to_double() { remaining.to_int() + 1 } else { remaining.to_int() }
    let words = if reviewer_error.val == "login.rateLimited" && seconds > 0 {
      c.wake_in(dmin(reviewer_countdown_tick_ms, remaining * 1000.0))
      fill("login.rateLimitedSeconds", [("seconds", seconds.to_string())])
    } else { tr(reviewer_error.val) }
    let error_id = c.id("review/error")
    let error_node = c.box(id=error_id, fn() { c.text(words, style=@sf.login_error) |> ignore })
    // Rebuilds and countdown wording retain one semantic identity; only safe localized text reaches the host.
    c.semantics(error_node, Status, id=error_id, label=words, actions=[Focus])
    // A countdown changes its words, not its error identity: focus/announce once, not on every tick or rebuild.
    if reviewer_a11y_sent.val != reviewer_error.val {
      let error_key = reviewer_error.val
      c.tell("review-a11y-error", fn() {
        if reviewer_open.val && reviewer_error.val == error_key {
          reviewer_a11y_sent.val = error_key
          let (x, y, w, h) = c.node_rect(error_node)
          reviewer_a11y_calls.push(@ui.native_call("accessibility.reviewError", {
            "text": Json::string(words), "x": Json::number(x), "y": Json::number(y),
            "w": Json::number(w), "h": Json::number(h),
          }))
        }
      })
    }
  } else {
    c.tell("review-a11y-clear", fn() { reviewer_accessibility_clear() })
  }
  if reviewer_checking.val {
    login_action(c, "review/checking", tr("login.checkingSavedState"), true, true) |> ignore
  } else if reviewer_saving.val {
    login_action(c, "review/finishing", tr("login.finishing"), true, true) |> ignore
    c.text(tr("login.finishingHint"), style=@sf.login_hint) |> ignore
  } else if reviewer_recovery.val {
    // Only recheck this same stored attempt: never send another password while a native write is unresolved.
    if login_action(c, "review/recover", tr("common.retry"), true, false) { reviewer_recover(c, src) }
  } else {
    let blocked = reviewer_busy.val || (src.signing_in)() || (src.now)() < reviewer_retry_at.val ||
      reviewer_validation(reviewer_email.text(), reviewer_password.text()) != ""
    let submit = login_action(c, "review/submit", tr(if reviewer_busy.val { "review.submitting" } else { "review.submit" }), true, blocked)
    if submit || password.submitted is Some(_) { reviewer_submit(c, src) }
  }
}
