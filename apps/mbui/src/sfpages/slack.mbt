// Connecting a Slack connect on the desktop (still.fail web/src/slack.tsx): the steps that make its app in
// Slack from still.fail's manifest (CreateAppSteps), and its two tokens typed into the core's draft of them
// (useSlackTokens: `slackTokens {station, form}`, `slack.tokens.edit`, `.verify`, `.drop`), who they belong to said
// once the core has checked them (TokenFields).

///|
/// A draft of a connect's two tokens, the core's (useSlackTokens): its station and form, its fields, what was last
/// sent of them (the inputs echo what is typed at once, the core's draft has it a moment later), why a call failed.
priv struct SlackTokens {
  station : String
  form : String
  app : @ui.Field
  bot : @ui.Field
  mut app_sent : String
  mut bot_sent : String
  error : @signals.Signal[String]
}

///|
/// The drafts open, by what holds them (a connect's page, a dialog).
// kept across runs: opened by slack_tokens, let go by tokens_drop; slack_reset empties it
let slack_token_forms : Map[String, SlackTokens] = Map([])

///|
/// How many drafts were opened (each its own form).
// kept across runs: counted by slack_tokens; slack_reset puts it back
let slack_forms_made : Ref[Int] = Ref(0)

///|
fn slack_reset() -> Unit {
  slack_token_forms.clear()
  slack_forms_made.val = 0
}

///|
/// The draft `key` holds, opened for a connect's tokens (`connect`: a blank one keeps what it has) or an app
/// installed through Slack's OAuth (`install`, its state: its bot token is on the station already); the core told
/// once the frame's builds are over. `form`: a connect wizard's, whose draft it is.
fn slack_tokens(
  c : @ui.Ctx,
  core : Core,
  station : String,
  key : String,
  connect? : String = "",
  install? : String = "",
  form? : String = "",
) -> SlackTokens {
  slack_tokens_draft(core, station, key, connect, install, form, fn(tk, open) { c.tell("tokens-open/" + tk.form, open) })
}

///|
/// The draft `key` holds (slack_tokens'), opened as the first to ask for it does: the core told it is opened by `told`
/// (given the draft and that call: a build's after the frame's builds, what is made once at once).
fn slack_tokens_draft(
  core : Core,
  station : String,
  key : String,
  connect : String,
  install : String,
  form : String,
  told : (SlackTokens, () -> Unit) -> Unit,
) -> SlackTokens {
  match slack_token_forms.get(key) {
    Some(tk) => tk
    None => {
      slack_forms_made.val += 1
      let tk = {
        station,
        // (a wizard's draft its own form: useSlackTokens' `form`)
        form: if form != "" { form } else { "desk-tokens-" + slack_forms_made.val.to_string() },
        app: @ui.Field::new(),
        bot: @ui.Field::new(),
        app_sent: "",
        bot_sent: "",
        error: @signals.signal(""),
      }
      slack_token_forms[key] = tk
      told(tk, fn() { tokens_send(core, tk, "edit", Some(obj([("connect", opt_str(connect)), ("install", opt_str(install))]))) })
      tk
    }
  }
}

///|
fn opt_str(s : String) -> Json {
  if s == "" {
    Json::null()
  } else {
    str(s)
  }
}

///|
/// One of the draft's calls (`slack.tokens.<action>`); `then` its answer. A failure is said under the fields.
fn tokens_send(core : Core, tk : SlackTokens, action : String, input : Json?, then? : (Json) -> Unit = fn(_) {  }) -> Unit {
  let p = [("station", str(tk.station)), ("form", str(tk.form))]
  match input {
    Some(i) => p.push(("input", i))
    None => ()
  }
  (core.call)("slack.tokens." + action, obj(p), fn(r) {
    match r {
      Ok(v) => then(v)
      Err(e) => tk.error.set(error_text(e))
    }
  })
}

///|
/// The draft `key` held let go (its dialog closed, its connect connected).
fn tokens_drop(core : Core, key : String) -> Unit {
  match slack_token_forms.get(key) {
    Some(tk) => {
      slack_token_forms.remove(key)
      tokens_send(core, tk, "drop", None)
    }
    None => ()
  }
}

///|
/// The draft as the core has it.
fn tokens_view(core : Core, tk : SlackTokens) -> Json? {
  (core.topic)("slackTokens", { "station": str(tk.station), "form": str(tk.form) }).get().value
}

///|
/// Whether there is something to check (the core's `ready`).
fn tokens_ready(core : Core, tk : SlackTokens) -> Bool {
  flag(tokens_view(core, tk), "ready")
}

///|
/// Whether its check is on its way.
fn tokens_busy(core : Core, tk : SlackTokens) -> Bool {
  is_doing(core, ["slack.tokens.verify"], [("station", tk.station), ("form", tk.form)])
}

///|
/// Checked as the button that goes on is pressed (TokenCheck.then): `go` once the core found them right.
fn tokens_check(core : Core, tk : SlackTokens, go : () -> Unit) -> Unit {
  if tokens_busy(core, tk) {
    return
  }
  tk.error.set("")
  tokens_send(core, tk, "verify", None, then=fn(ok) {
    if ok == Json::boolean(true) {
      go()
    }
  })
}

///|
/// The tokens as typed, as a connect is written with them (a blank one keeps what is saved).
fn tokens_input(tk : SlackTokens) -> Json {
  obj([("appToken", str(tk.app_sent)), ("botToken", str(tk.bot_sent))])
}

///|
/// Its fields emptied, as after they were saved.
fn tokens_clear(core : Core, tk : SlackTokens) -> Unit {
  tk.app.set("")
  tk.bot.set("")
  tk.app_sent = ""
  tk.bot_sent = ""
  tokens_send(core, tk, "edit", Some(obj([("appToken", str("")), ("botToken", str("")), ("clear", Json::boolean(true))])))
}

///|
/// The two tokens' fields (TokenFields): App-Level Token and, unless the app was
/// installed through Slack (`install`), Bot Token, each a secret's field (`masked`: what is saved, kept while it is left
/// blank); who they were checked as, in green, while the draft is what is typed; what checking them found wrong, and
/// why a call failed, in red under them.
fn token_fields(c : @ui.Ctx, core : Core, tk : SlackTokens, masked? : (String, String) = ("", ""), install? : Bool = false) -> Unit {
  let view = tokens_view(core, tk)
  let kept = fn(m : String, or_else : String) {
    if m == "" {
      or_else
    } else {
      @sf.t("web-main.slack.saved", args=[("token", m)])
    }
  }
  c.box(style=sk_fields, fn() {
    @sf.field(c, "App-Level Token", fn() {
      // (told the core as it is typed)
      @sf.input(c, "tokens-app/" + tk.form, placeholder=kept(masked.0, "xapp-…"), secret=true, field=tk.app, on_change=fn(words) {
        let typed = words.trim(chars=" \t\n").to_owned()
        if typed != tk.app_sent {
          tk.app_sent = typed
          tokens_send(core, tk, "edit", Some(obj([("appToken", str(typed))])))
        }
      })
      |> ignore
    })
    if !install {
      @sf.field(c, "Bot Token", fn() {
        @sf.input(c, "tokens-bot/" + tk.form, placeholder=kept(masked.1, "xoxb-…"), secret=true, field=tk.bot, on_change=fn(words) {
          let typed = words.trim(chars=" \t\n").to_owned()
          if typed != tk.bot_sent {
            tk.bot_sent = typed
            tokens_send(core, tk, "edit", Some(obj([("botToken", str(typed))])))
          }
        })
        |> ignore
      })
    }
    match field(view, "verified") {
      Some(Object(_)) as v if text(view, "appToken") == tk.app_sent && text(view, "botToken") == tk.bot_sent =>
        @sf.verify_ok(c, @sf.t("web-main.slack.verified", args=[("team", text(v, "team")), ("bot", text(v, "botName"))]))
      _ => ()
    }
    let errors = strings(view, "errors")
    if errors.length() > 0 {
      c.box(style=sk_errors, fn() {
        for e in errors {
          c.text("• " + e, style=sk_error) |> ignore
        }
      })
      |> ignore
    }
    if tk.error.get() != "" {
      c.text(tk.error.get(), style=sk_error) |> ignore
    }
  })
  |> ignore
}

///|
/// Making the app in Slack (CreateAppSteps): from still.fail's manifest, named `name` (Slack's page opened by the
/// station's link: `slack.createAppUrl`), its App-Level Token, installing it, the two tokens filled in below.
fn create_app_steps(c : @ui.Ctx, core : Core, station : String, name : String) -> Unit {
  let named = match name.trim(chars=" \t\n").to_owned() {
    "" => "still.fail"
    n => n
  }
  let on = [("station", station)]
  let opening = is_doing(core, ["slack.createAppUrl"], on)
  @sf.steps(c, [
    fn() {
      c.text(@sf.t("web-main.slack.step.create", args=[("app", "still.fail"), ("name", named)]), style=@sf.step_words) |> ignore
      @sf.button(c, @sf.t("web-main.slack.create"), key="slack-create/" + station, icon="external", busy=opening, on_press=fn() {
        @settings.act(core, @sf.t("web-main.slack.create"), "slack.createAppUrl", obj([("station", str(station)), ("name", str(named))]), then=fn(
          v,
        ) {
          match opt_text(Some(v), "url") {
            Some(url) => (core.open_link)(url)
            None => ()
          }
        })
      }) |> ignore
    },
    fn() { c.text(@sf.t("web-main.slack.step.appToken"), style=@sf.step_words) |> ignore },
    fn() { c.text(@sf.t("web-main.slack.step.install"), style=@sf.step_words) |> ignore },
    fn() { c.text(@sf.t("web-main.slack.step.fill"), style=@sf.step_words) |> ignore },
  ])
}

///|
/// The two tokens' fields (token_fields', as nodes) in `b`, the connect's page's: App-Level Token and Bot Token, each a
/// secret's line told to the core's draft as it is typed; who they were checked as, in green, while the draft is what is
/// typed; what checking them found wrong, and why a call failed, in red under them. (Their old view stays the
/// dialogs' till they are nodes: token_fields.)
fn token_fields_node(b : @view.View, core : Core, tk : SlackTokens) -> Unit {
  let view = fn() { tokens_view(core, tk) }
  b.box(fn(f) {
    @sf.style_node(f, fn() { sk_fields })
    @sf.labelled_field_node(f, fn() { "App-Level Token" }, fn(l) {
      @sf.input_node(l, tk.app, placeholder="xapp-…", secret=true) |> ignore
    })
    @sf.labelled_field_node(f, fn() { "Bot Token" }, fn(l) {
      @sf.input_node(l, tk.bot, placeholder="xoxb-…", secret=true) |> ignore
    })
    // (told the core as it is typed)
    f.reacts(fn() { tk.app.text().trim(chars=" \t\n").to_owned() }, fn(typed) {
      if typed != tk.app_sent {
        tk.app_sent = typed
        tokens_send(core, tk, "edit", Some(obj([("appToken", str(typed))])))
      }
    })
    f.reacts(fn() { tk.bot.text().trim(chars=" \t\n").to_owned() }, fn(typed) {
      if typed != tk.bot_sent {
        tk.bot_sent = typed
        tokens_send(core, tk, "edit", Some(obj([("botToken", str(typed))])))
      }
    })
    let verified = fn() {
      let v = view()
      match field(v, "verified") {
        Some(Object(_)) as w if text(v, "appToken") == tk.app.text().trim(chars=" \t\n").to_owned() &&
          text(v, "botToken") == tk.bot.text().trim(chars=" \t\n").to_owned() =>
          @sf.t("web-main.slack.verified", args=[("team", text(w, "team")), ("bot", text(w, "botName"))])
        _ => ""
      }
    }
    f.show(fn() { verified() != "" }, fn(o) { @sf.verify_ok_node(o, verified) })
    f.show(fn() { strings(view(), "errors").length() > 0 }, fn(e) {
      e.box(fn(l) {
        @sf.style_node(l, fn() { sk_errors })
        l.each(fn() { strings(view(), "errors").mapi(fn(i, w) { (i, w) }) }, fn(x) { x.0 }, fn(w, x) {
          @sf.words_node(w, fn() { "• " + x.get().1 }, fn() { sk_error }) |> ignore
        })
      })
      |> ignore
    })
    f.show(fn() { tk.error.get() != "" }, fn(e) { @sf.words_node(e, fn() { tk.error.get() }, fn() { sk_error }) |> ignore })
  })
  |> ignore
}

///|
/// Making the app in Slack (create_app_steps', as nodes) in `b`, named as `name` says now (still.fail where it says
/// none): from still.fail's manifest, opened by the station's link; its App-Level Token, installing it, the two tokens
/// filled in below. (Their old view stays the new connect's dialog's till it is nodes: create_app_steps.)
fn create_app_steps_node(b : @view.View, core : Core, station : String, name : () -> String) -> Unit {
  let named = fn() {
    match name().trim(chars=" \t\n").to_owned() {
      "" => "still.fail"
      n => n
    }
  }
  let words = fn(s : @view.View, w : () -> String) { @sf.words_node(s, w, fn() { @sf.step_words }) |> ignore }
  @sf.steps_node(b, [
    fn(s) {
      words(s, fn() { @sf.t("web-main.slack.step.create", args=[("app", "still.fail"), ("name", named())]) })
      @sf.button_node(
        s,
        fn() { @sf.t("web-main.slack.create") },
        fn() {
          let n = @signals.untracked(named)
          @settings.act(core, @sf.t("web-main.slack.create"), "slack.createAppUrl", obj([("station", str(station)), ("name", str(n))]), then=fn(
            v,
          ) {
            match opt_text(Some(v), "url") {
              Some(url) => (core.open_link)(url)
              None => ()
            }
          })
        },
        icon="external",
        busy=fn() { is_doing(core, ["slack.createAppUrl"], [("station", station)]) },
      )
      |> ignore
    },
    fn(s) { words(s, fn() { @sf.t("web-main.slack.step.appToken") }) },
    fn(s) { words(s, fn() { @sf.t("web-main.slack.step.install") }) },
    fn(s) { words(s, fn() { @sf.t("web-main.slack.step.fill") }) },
  ])
}

///|
// kept across runs: a value (no field of it changes)
let sk_fields : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// What checking them found (fieldErrorList: the meta's 12 in red, a list 18 in).
// kept across runs: a value (no field of it changes)
let sk_errors : @ui.Style = @ui.css("w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let sk_error : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, color=Danger, w=Full)
