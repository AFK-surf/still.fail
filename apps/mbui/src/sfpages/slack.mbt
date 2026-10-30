// Connecting a Slack connect on the desktop (ember web/src/slack.tsx, slack.css.ts): the steps that make its app in
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
  // (plain: what the core was last told, compared before telling it again)
  mut app_sent : String
  mut bot_sent : String
  error : @signals.Signal[String]
}

///|
/// The drafts open, by what holds them (a connect's page, a dialog).
// kept across runs: opened by slack_tokens, let go by tokens_drop; slack_reset empties it
let slack_token_forms : Map[String, SlackTokens] = {}

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
      c.tell("tokens-open/" + tk.form, fn() {
        tokens_send(core, tk, "edit", Some(obj([("connect", opt_str(connect)), ("install", opt_str(install))])))
      })
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
  (core.topic)("slackTokens", { "station": str(tk.station), "form": str(tk.form) }).value
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
/// The two tokens' fields (TokenFields; slack.css.ts tokenFields: 12 apart): App-Level Token and, unless the app was
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
      let typed = @sf.input(c, "tokens-app/" + tk.form, placeholder=kept(masked.0, "xapp-…"), secret=true, field=tk.app).text.trim(
          chars=" \t\n",
        ).to_owned()
      if typed != tk.app_sent {
        tk.app_sent = typed
        // (told the core once the frame's builds are over)
        c.tell("tokens-app/" + tk.form, fn() { tokens_send(core, tk, "edit", Some(obj([("appToken", str(typed))]))) })
      }
    })
    if !install {
      @sf.field(c, "Bot Token", fn() {
        let typed = @sf.input(c, "tokens-bot/" + tk.form, placeholder=kept(masked.1, "xoxb-…"), secret=true, field=tk.bot).text.trim(
            chars=" \t\n",
          ).to_owned()
        if typed != tk.bot_sent {
          tk.bot_sent = typed
          c.tell("tokens-bot/" + tk.form, fn() { tokens_send(core, tk, "edit", Some(obj([("botToken", str(typed))]))) })
        }
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
      if @sf.button(c, @sf.t("web-main.slack.create"), key="slack-create/" + station, icon="external", busy=opening) {
        @settings.act(core, @sf.t("web-main.slack.create"), "slack.createAppUrl", obj([("station", str(station)), ("name", str(named))]), then=fn(
          v,
        ) {
          match opt_text(Some(v), "url") {
            Some(url) => (core.open_link)(url)
            None => ()
          }
        })
      }
    },
    fn() { c.text(@sf.t("web-main.slack.step.appToken"), style=@sf.step_words) |> ignore },
    fn() { c.text(@sf.t("web-main.slack.step.install"), style=@sf.step_words) |> ignore },
    fn() { c.text(@sf.t("web-main.slack.step.fill"), style=@sf.step_words) |> ignore },
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
