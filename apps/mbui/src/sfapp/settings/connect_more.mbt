// A connect's sheets and pages past its page (Connects.kt): its "…" (reconnecting, its tokens, Slack, turning it off
// or on, its owner, deleting it), how its conversations become sessions (ModeSheet), its one session (SessionSheet),
// what it runs (ConnectRunScreen, the core's `pick` of `connect:<id>`), a new one a step a screen (NewConnectScreen
// over the core's `connectFlow`), the Slack apps made and not connected yet (WaitingApp), and its Slack app
// (SlackApp.kt: its name, description, colour and permissions written into the app's manifest; ConfigTokenSteps).

///|
/// The first of `keys` that `v` has, else `or_else`.
fn first_text(v : Json?, keys : Array[String], or_else : String) -> String {
  for k in keys {
    match opt_text(v, k) {
      Some(x) => return x
      None => ()
    }
  }
  or_else
}

///|
/// A connect call's params: its station and id, and what else it takes.
fn connect_params(station : String, id : String, more : Array[(String, Json)]) -> Json {
  let p = [("station", str(station)), ("id", str(id))]
  for x in more {
    p.push(x)
  }
  obj(p)
}

///|
/// What is done to a connect less often (openConnectMenu): each closes the sheet and goes on by itself, the connect's
/// page marking it under way, a toast saying how it ended.
fn open_connect_menu(_core : Core, here : Here, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let name = text(cv, "name")
  let on = [("station", station), ("id", id)]
  open_sheet(0.6, fn(c, core) {
    let t = @sf.theme()
    let reconnecting = is_doing(core, ["connect.reconnect"], on)
    let switching = is_doing(core, ["connect.put"], on)
    let run = fn(what : String, done : String, call : String, params : Json) {
      close_sheet()
      act(core, what, call, params, done~)
    }
    sheet_head(c, name)
    if pick_row(c, "connect-reconnect", tr("android-settings.connect.reconnect"), enabled=!switching, busy=reconnecting) {
      run(
        tr("android-settings.connect.reconnectWhat"),
        tr("android-settings.connect.reconnected"),
        "connect.reconnect",
        connect_params(station, id, []),
      )
    }
    let feishu = text(cv, "kind") == "feishu"
    if feishu {
      if pick_row(c, "connect-feishu-secret", tr("web-mobile.connects.feishu.replace")) {
        close_sheet()
        open_feishu_secret(core, station, cv)
      }
    } else if pick_row(c, "connect-tokens", tr("android-settings.connect.changeTokens")) {
      open_tokens(core, station, cv)
    }
    match opt_text(field(field(cv, "connection"), "workspace"), "url") {
      Some(url) if !feishu => if pick_row(c, "connect-open-slack", tr("android-settings.connect.openSlack")) { (core.open_link)(url) }
      _ => ()
    }
    match opt_text(field(cv, "feishu"), "console") {
      Some(url) => if pick_row(c, "connect-feishu-console", tr("web-mobile.connects.feishu.openConsole")) { (core.open_link)(url) }
      None => ()
    }
    if flag(cv, "enabled") {
      if pick_row(
          c,
          "connect-disable",
          tr("android-settings.connect.disable"),
          sub=tr(if feishu { "web-mobile.connects.disableNote.feishu" } else { "android-settings.connect.disableNote" }),
          enabled=!reconnecting,
          busy=switching,
        ) {
        run(
          tr("android-settings.connect.disableWhat"),
          tr(if feishu { "web-mobile.connects.disabled.feishu" } else { "android-settings.connect.disabled" }),
          "connect.put",
          connect_params(station, id, [("input", obj([("enabled", Json::boolean(false))]))]),
        )
      }
    } else if pick_row(c, "connect-enable", tr("android-settings.connect.enable"), enabled=!reconnecting, busy=switching) {
      run(
        tr("android-settings.connect.enableWhat"),
        tr("android-settings.connect.enabled"),
        "connect.put",
        connect_params(station, id, [("input", obj([("enabled", Json::boolean(true))]))]),
      )
    }
    let owner = field(cv, "createdBy")
    if pick_row(
        c,
        "connect-owner",
        tr("android-settings.connect.changeOwner"),
        sub=match text(field(owner, "shown"), "display") {
          "" => text(owner, "name")
          d => d
        },
      ) {
      open_owner(core, here, station, cv)
    }
    if pick_row(c, "connect-delete", tr("android-settings.connect.delete"), color=t.p.red) {
      let n = count(cv, "sessions")
      confirm(
        fill("android-settings.connect.deleteTitle", [("name", name)]),
        if n > 0 {
          fill(if feishu { "web-mobile.connects.deleteTextSessions.feishu" } else { "android-settings.connect.deleteTextSessions" }, [("n", n.to_string())])
        } else {
          tr(if feishu { "web-mobile.connects.deleteText.feishu" } else { "android-settings.connect.deleteText" })
        },
        tr("android-settings.connect.delete"),
        danger=true,
        fn() {
          (core.pop)()
          act(core, tr("android-settings.connect.deleteWhat"), "connect.delete", connect_params(station, id, []), done=tr("android-settings.connect.deleted"))
        },
      )
    }
  })
}

///|
/// A connect handed to another person of the workspace (OwnerSheet: `connect.put` with its owner).
fn open_owner(_core : Core, here : Here, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  let current = text(field(cv, "createdBy"), "id").to_lower()
  open_sheet(0.6, fn(c, core) {
    let t = @sf.theme()
    let busy = is_doing(core, ["connect.put"], [("station", station), ("id", id)])
    sheet_head(c, tr("android-settings.connect.changeOwner"))
    c.box(w=Fill(1.0), padx=20.0, pady=4.0, fn() {
      c.text(tr("android-settings.connect.ownerNote"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
    })
    |> ignore
    for m in items(workspace_view(core, here).value, "members") {
      let mv = Some(m)
      let email = text(mv, "email")
      let name = match text(mv, "name") {
        "" => email
        n => n
      }
      let is_it = email.to_lower() == current
      if pick_row(c, "owner/" + email, name, sub=email, checked=is_it, enabled=!busy) {
        close_sheet()
        if !is_it {
          act(
            core,
            tr("android-settings.connect.ownerWhat"),
            "connect.put",
            connect_params(station, id, [("input", obj([("owner", obj([("id", str(email)), ("name", str(name))]))]))]),
            done=tr("android-settings.connect.ownerChanged"),
          )
        }
      }
    }
  })
}

///|
/// What switching a connect to `mode` does to its conversations, in plain words (consequences).
fn consequences(cv : Json?, mode : String, mention : Bool, running : Int) -> Array[String] {
  // a Feishu connect's groups in place of Slack's threads and channels
  let feishu : Map[String, String] = {
    "android-settings.mode.toSingle": "web-pages.connect.effects.toSingle.feishu",
    "android-settings.mode.toMulti": "web-pages.connect.effects.toMulti.feishu",
    "android-settings.mode.oldThreads": "web-pages.connect.effects.threadsRestart.feishu",
    "android-settings.mode.mention": "web-pages.connect.effects.mentionOnly.feishu",
    "android-settings.mode.noMention": "web-pages.connect.effects.noMention.feishu",
  }
  let say = fn(k : String) { tr(if text(cv, "kind") == "feishu" { feishu.get(k).unwrap_or(k) } else { k }) }
  let out : Array[String] = []
  let was = text(cv, "mode")
  if was == "multi-session" && mode == "single-session" {
    out.push(say("android-settings.mode.toSingle"))
    out.push(say(if has(cv, "session") { "android-settings.mode.keepSession" } else { "android-settings.mode.newSession" }))
    if !mention {
      out.push(say("android-settings.mode.noMention"))
    }
  } else if was == "single-session" && mode == "multi-session" {
    out.push(say("android-settings.mode.toMulti"))
    out.push(say("android-settings.mode.oldThreads"))
    out.push(say("android-settings.mode.back"))
  } else if mention != flag(cv, "requireMention") {
    out.push(say(if mention { "android-settings.mode.mention" } else { "android-settings.mode.noMention" }))
  }
  if running > 0 {
    out.push(fill("android-settings.mode.running", [("n", running.to_string())]))
  }
  out
}

///|
/// The ways a connect's conversations become sessions, each with what it means, and in single-session whether it
/// waits for an @ (ModeChoices). Answers the choice tapped this frame.
fn mode_choices(c : @ui.Ctx, key : String, mode : String, mention : Bool, kind? : String = "") -> (String, Bool) {
  let t = @sf.theme()
  let mut out = (mode, mention)
  c.box(w=Fill(1.0), gap=8.0, fn() {
    for m in ["multi-session", "single-session"] {
      let on = mode == m
      let id = c.id(key + "/" + m)
      if hit(c, id) {
        out = (m, if m == "multi-session" { true } else { mention })
      }
      c.box(
        w=Fill(1.0),
        padx=14.0,
        pady=12.0,
        radius=14.0,
        bg=t.p.card,
        border=if on { 2.0 } else { 1.0 },
        border_color=if on { t.p.accent } else { t.p.line },
        id~,
        fn() {
          c.text(mode_label(m, kind~), size=15.0, weight=600, color=t.p.text, w=Fill(1.0), line=21.0) |> ignore
          c.text(mode_text(m, kind~), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
        },
      )
      |> ignore
    }
    if mode == "single-session" {
      let id = c.id(key + "/mention")
      if hit(c, id) {
        out = (mode, !mention)
      }
      c.box(dir=Row, w=Fill(1.0), padx=14.0, pady=10.0, radius=14.0, bg=t.p.chip, gap=12.0, align=ACenter, id~, fn() {
        c.box(w=Fill(1.0), fn() {
          c.text(tr("android-settings.mode.mentionTitle"), size=14.0, weight=600, color=t.p.text, w=Fill(1.0), line=20.0)
          |> ignore
          c.text(
            tr(
              match (mention, kind == "feishu") {
                (true, true) => "web-mobile.connects.mentionOn.feishu"
                (false, true) => "web-mobile.connects.mentionOff.feishu"
                (true, false) => "android-settings.mode.mentionOn"
                (false, false) => "android-settings.mode.mentionOff"
              },
            ),
            size=13.0,
            color=t.p.muted,
            w=Fill(1.0),
            line=18.0,
          )
          |> ignore
        })
        |> ignore
        switch(c, mention)
      })
      |> ignore
    }
  })
  |> ignore
  out
}

///|
/// How its conversations become sessions, picked with what changing it does said before it is done (ModeSheet).
fn open_mode(_core : Core, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let picked : Ref[(String, Bool)] = Ref((text(cv, "mode"), flag(cv, "requireMention")))
  open_sheet(0.8, fn(c, core) {
    let t = @sf.theme()
    let (mode, mention) = picked.val
    let busy = is_doing(core, ["connect.put"], [("station", station), ("id", id)])
    let changed = mode != text(cv, "mode") || (mode == "single-session" && mention != flag(cv, "requireMention"))
    let effects = if changed { consequences(cv, mode, mention, count(item, "running")) } else { [] }
    sheet_head(c, tr("android-settings.mode.title"))
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      scroll_page(c, "connect-mode", [
        fn() {
          c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() { picked.val = mode_choices(c, "mode-sheet", mode, mention, kind=text(cv, "kind")) })
          |> ignore
        },
        fn() {
          if effects.length() > 0 {
            c.box(w=Fill(1.0), padx=20.0, pb=10.0, fn() {
              c.box(w=Fill(1.0), pad=12.0, radius=12.0, gap=4.0, bg=@sf.alpha(warn, 0.12), fn() {
                c.text(tr("android-settings.mode.after"), size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0)
                |> ignore
                for e in effects {
                  c.text("· " + e, size=13.0, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
                }
              })
              |> ignore
            })
            |> ignore
          }
        },
        fn() {
          c.box(dir=Row, w=Fill(1.0), padx=20.0, pb=24.0, gap=8.0, justify=JEnd, fn() {
            if button(c, "mode-cancel", tr("common.cancel"), false) {
              close_sheet()
            }
            let label = if mode == text(cv, "mode") {
              tr("android-settings.mode.confirm")
            } else if mode == "single-session" {
              tr("android-settings.mode.toSingleButton")
            } else {
              tr("android-settings.mode.toMultiButton")
            }
            if button(c, "mode-go", label, true, enabled=changed && !busy) {
              close_sheet()
              act(
                core,
                tr("android-settings.mode.changeWhat"),
                "connect.put",
                connect_params(station, id, [
                  ("input", obj([("mode", str(mode)), ("requireMention", Json::boolean(mention))])),
                ]),
                done=tr("android-settings.mode.changed"),
              )
            }
          })
          |> ignore
        },
      ])
    })
    |> ignore
  })
}

///|
/// A single-session connect's session: the one its messages go into, switched, or a new one (SessionSheet:
/// `connect.bindSession`).
fn open_session(_core : Core, station : String, item : Json?) -> Unit {
  let cv = field(item, "connect")
  let id = text(cv, "id")
  let choice : Ref[String] = Ref(match opt_text(cv, "session") {
    Some(s) => s
    None => "new"
  })
  open_sheet(0.7, fn(c, core) {
    let t = @sf.theme()
    let busy = is_doing(core, ["connect.bindSession"], [("station", station), ("connect", id)])
    sheet_head(c, tr("android-settings.session.title"))
    let mut title = ""
    c.box(w=Fill(1.0), h=Fill(1.0), fn() {
      let blocks : Array[() -> Unit] = [
        fn() {
          c.box(w=Fill(1.0), padx=20.0, pb=4.0, fn() {
            c.text(fill("android-settings.session.note", [("name", text(cv, "name"))]), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0)
            |> ignore
          })
          |> ignore
        },
        fn() {
          if pick_row(c, "session-new", tr("android-settings.session.new"), sub=tr("android-settings.session.newNote"), checked=choice.val == "new") {
            choice.val = "new"
          }
          if choice.val == "new" {
            c.box(w=Fill(1.0), padx=20.0, fn() { title = field_box(c, "session-title", tr("android-settings.session.namePlaceholder")) })
            |> ignore
          }
        },
      ]
      for s in items(item, "candidates") {
        blocks.push(fn() {
          let key = text(Some(s), "key")
          if pick_row(c, "session/" + key, text(Some(s), "titleText"), sub=text(Some(s), "agentText"), checked=choice.val == key) {
            choice.val = key
          }
        })
      }
      blocks.push(fn() {
        c.box(dir=Row, w=Fill(1.0), padx=20.0, pady=6.0, gap=8.0, justify=JEnd, fn() {
          if button(c, "session-cancel", tr("common.cancel"), false) {
            c.blur()
            close_sheet()
          }
          let picked = choice.val
          if button(
              c,
              "session-go",
              tr(if picked == "new" { "android-settings.session.createUse" } else { "android-settings.session.use" }),
              true,
              enabled=Some(picked) != opt_text(cv, "session") && !busy,
            ) {
            c.blur()
            close_sheet()
            let params = [("station", str(station)), ("connect", str(id)), ("title", str(title.trim(chars=" ").to_owned()))]
            if picked != "new" {
              params.push(("session", str(picked)))
            }
            act(
              core,
              tr(if picked == "new" { "android-settings.session.createWhat" } else { "android-settings.session.switchWhat" }),
              "connect.bindSession",
              obj(params),
              done=tr(if picked == "new" { "android-settings.session.created" } else { "android-settings.session.switched" }),
            )
          }
        })
        |> ignore
      })
      scroll_page(c, "connect-session", blocks)
    })
    |> ignore
  })
}

///|
/// The core's draft of two Slack tokens (`slackTokens {station, form}`; Connects.kt Tokens): what is typed goes to it
/// (`slack.tokens.edit`), it says whether they can be checked, `slack.tokens.verify` checks them.
fn tokens_call(core : Core, station : String, form : String, action : String, input : Json?, then? : (Json) -> Unit = fn(_) {  }) -> Unit {
  let p = [("station", str(station)), ("form", str(form))]
  match input {
    Some(i) => p.push(("input", i))
    None => ()
  }
  act(
    core,
    tr(
      match action {
        "verify" => "android-settings.tokens.verify"
        "drop" => "android-settings.tokens.drop"
        _ => "android-settings.tokens.edit"
      },
    ),
    "slack.tokens." + action,
    obj(p),
    then~,
  )
}

///|
/// The two tokens' fields (TokenFields): App-Level Token and, unless the app was installed through Slack (its bot
/// token on the station already), Bot Token; each a secret's field, a blank one keeping what is saved; what checking
/// them found under them. Answers nothing: what is typed goes to the core's draft.
fn token_fields(c : @ui.Ctx, core : Core, station : String, form : String, masked : (String, String), install : Bool) -> Unit {
  let t = @sf.theme()
  let view = (core.topic)("slackTokens", { "station": str(station), "form": str(form) }).value
  let label = fn(words : String) {
    c.text(words, size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
  }
  let kept = fn(m : String, or_else : String) {
    if m == "" {
      or_else
    } else {
      fill("android-settings.tokens.kept", [("token", m)])
    }
  }
  c.box(w=Fill(1.0), gap=8.0, fn() {
    label("App-Level Token")
    let app_token = field_box(c, "tokens-app/" + form, kept(masked.0, "xapp-…"), secret=true)
    if app_token != tokens_sent.app_token {
      tokens_sent.app_token = app_token
      // (told the core once the frame's builds are over)
      c.tell("tokens-app/" + form, fn() { tokens_call(core, station, form, "edit", Some(obj([("appToken", str(app_token))]))) })
    }
    if !install {
      label("Bot Token")
      let bot = field_box(c, "tokens-bot/" + form, kept(masked.1, "xoxb-…"), secret=true)
      if bot != tokens_sent.bot_token {
        tokens_sent.bot_token = bot
        // (told the core once the frame's builds are over)
        c.tell("tokens-bot/" + form, fn() { tokens_call(core, station, form, "edit", Some(obj([("botToken", str(bot))]))) })
      }
    }
    match field(view, "verified") {
      Some(Object(_)) as v if text(view, "appToken") == tokens_sent.app_token =>
        c.text(
          fill("android-settings.tokens.verified", [("team", text(v, "team")), ("bot", text(v, "botName"))]),
          size=12.0,
          color=t.p.green,
          w=Fill(1.0),
          line=17.0,
        )
        |> ignore
      _ => ()
    }
    for e in strings(view, "errors") {
      c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
    }
  })
  |> ignore
}

///|
/// What was last sent to the tokens' draft (never shown, never logged).
priv struct TokensSent {
  mut app_token : String
  mut bot_token : String
}

///|
let tokens_sent : TokensSent = { app_token: "", bot_token: "" }

///|
/// A count of drafts opened: each its own `form`.
let tokens_form : Ref[Int] = Ref(0)

///|
/// A connect's Slack tokens replaced (openTokens: either one, the other kept), checked before they are saved
/// (`slack.tokens.verify`, then `connect.put` with them).
fn open_tokens(core : Core, station : String, cv : Json?) -> Unit {
  let id = text(cv, "id")
  tokens_form.val += 1
  let form = "mbui-tokens-" + tokens_form.val.to_string()
  tokens_sent.app_token = ""
  tokens_sent.bot_token = ""
  tokens_call(core, station, form, "edit", Some(obj([("connect", str(id))])))
  let dropped : Ref[Bool] = Ref(false)
  let drop = fn() {
    if !dropped.val {
      dropped.val = true
      tokens_call(core, station, form, "drop", None)
    }
  }
  let slack = field(cv, "slack")
  open_sheet(
    0.72,
    fn(c, core) {
      let t = @sf.theme()
      let view = (core.topic)("slackTokens", { "station": str(station), "form": str(form) }).value
      let busy = is_doing(core, ["connect.put"], [("station", station), ("id", id)]) ||
        is_doing(core, ["slack.tokens.verify"], [("station", station), ("form", form)])
      sheet_head(c, "Slack token")
      c.box(w=Fill(1.0), padx=20.0, pb=24.0, gap=10.0, fn() {
        c.text(tr("android-settings.tokens.note"), size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0) |> ignore
        token_fields(c, core, station, form, (text(slack, "appToken"), text(slack, "botToken")), false)
        c.box(dir=Row, w=Fill(1.0), gap=8.0, justify=JEnd, fn() {
          if button(c, "tokens-cancel", tr("common.cancel"), false) {
            c.blur()
            close_sheet()
            drop()
          }
          if button(c, "tokens-save", tr("android-settings.tokens.save"), true, busy~, enabled=flag(view, "ready")) {
            tokens_call(core, station, form, "verify", None, then=fn(ok) {
              if ok == Json::boolean(true) {
                // the tokens as typed go to the connect (a blank one keeps what is saved)
                let input = obj([("slack", obj([("appToken", str(tokens_sent.app_token)), ("botToken", str(tokens_sent.bot_token))]))])
                (core.call)("connect.put", connect_params(station, id, [("input", input)]), fn(r) {
                  match r {
                    Ok(_) => {
                      (core.say)(tr("android-settings.tokens.saved"))
                      close_sheet()
                      drop()
                    }
                    Err(e) => (core.say)(error_text(e))
                  }
                })
              }
            })
          }
        })
        |> ignore
      })
      |> ignore
    },
    on_close=fn() { drop() },
  )
}

///|
/// A connect's model, how hard it thinks and who runs it (ConnectRunScreen): picked as a new chat's are, in the core's
/// `pick` of `connect:<id>` (`pick.set`), saved for its new sessions (`pick.save`), or, another station's model, borrowed
/// once asked again (`pick.borrow`).
fn connect_run_page(c : @ui.Ctx, core : Core, station : String, id : String) -> Unit {
  let t = @sf.theme()
  let of = "connect:" + id
  let topic = (core.topic)("pick", { "station": str(station), "of": str(of) })
  let v = topic.value
  let pick = fn(more : Array[(String, Json)]) {
    let p = [("station", str(station)), ("of", str(of))]
    for x in more {
      p.push(x)
    }
    act(core, tr("android-settings.flow.choose"), "pick.set", obj(p))
  }
  if !run_opened.contains(of) {
    run_opened[of] = true
    pick([("open", Json::boolean(true))])
  }
  let list = run_list.get(of).unwrap_or("")
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let title = match list {
      "model" => tr("android-settings.connect.pickModel")
      "account" => tr("android-settings.run.pickAccount")
      _ => tr("android-settings.run.title")
    }
    if list != "" {
      // back to the page's first view, not off it
      c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, gap=8.0, align=ACenter, fn() {
        if nav_back(c, tr("android-settings.run.title")) {
          run_list.remove(of)
        }
        c.box(w=Fill(1.0), align=ACenter, fn() {
          c.text(title, size=17.0, weight=600, color=t.p.text, wrap=false, line=22.0) |> ignore
        })
        |> ignore
        c.box(w=Px(60.0), fn() {  }) |> ignore
      })
      |> ignore
      c.on_back(fn() { run_list.remove(of) })
    } else {
      nav_bar(c, core, tr("common.back"), title)
    }
    guard v is Some(Object(_)) else {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    let draft = field(v, "draft")
    let runtime = text(field(v, "value"), "runtime")
    let models = items(v, "options")
    match list {
      "model" => {
        // every model it can move to (SettingParts.kt ModelList)
        model_list(c, "run-models/" + of, models, runtime, text(draft, "model"), fn(m) {
          pick([("model", str(m))])
          run_list.remove(of)
        })
        return
      }
      "account" => {
        scroll_page(c, "run-accounts/" + of, [
          fn() {
            if pick_row(c, "run-account/auto", tr("android-settings.connect.autoAccount"), checked=!has(draft, "profile")) {
              pick([("profile", Json::null())])
              run_list.remove(of)
            }
            for a in items(v, "accounts") {
              let av = Some(a)
              if pick_row(
                  c,
                  "run-account/" + text(av, "id"),
                  text(av, "name"),
                  sub=text(av, "line"),
                  checked=text(draft, "profile") == text(av, "id"),
                ) {
                pick([("profile", str(text(av, "id")))])
                run_list.remove(of)
              }
            }
          },
        ])
        return
      }
      _ => ()
    }
    let group = fn(words : String) {
      c.box(w=Fill(1.0), pl=6.0, pt=16.0, pb=6.0, fn() {
        c.text(words, size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
    }
    let setting_row = fn(key : String, body : () -> Unit) {
      let rid = c.id(key)
      let tapped = hit(c, rid)
      c.box(dir=Row, w=Fill(1.0), padx=14.0, pady=12.0, gap=12.0, radius=14.0, bg=t.p.card, align=ACenter, id=rid, fn() {
        body()
        chevron(c)
      })
      |> ignore
      tapped
    }
    c.box(w=Fill(1.0), h=Fill(1.0), padx=18.0, fn() {
      if models.length() == 0 {
        c.box(w=Fill(1.0), pt=8.0, fn() {
          c.text(fill("android-settings.run.noModels", [("runtime", runtime_label(runtime))]), size=13.0, color=warn, w=Fill(1.0), line=18.0)
          |> ignore
        })
        |> ignore
      }
      group(tr("android-settings.connect.model"))
      if setting_row("run-model", fn() {
          @sf.maker_mark(c, text(field(v, "maker"), "id"), runtime, 18.0) |> ignore
          row_title(c, text(v, "modelText"))
        }) {
        run_list[of] = "model"
      }
      group(tr("android-settings.run.effort"))
      c.box(dir=Row, w=Fill(1.0), gap=8.0, fn() {
        let efforts : Array[String] = [""] + strings(v, "efforts")
        for e in efforts {
          let on = text(draft, "effort") == e
          let id2 = c.id("run-effort/" + e)
          if hit(c, id2) {
            pick([("effort", if e == "" { Json::null() } else { str(e) })])
          }
          c.box(padx=14.0, pady=8.0, radius=16.0, bg=if on { t.p.text } else { t.p.chip }, id=id2, fn() {
            c.text(if e == "" { tr("android-settings.connect.defaultEffort") } else { e }, size=14.0, color=if on { t.p.bg } else { t.p.text }, wrap=false)
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
      group(tr("android-settings.run.account"))
      if setting_row("run-account", fn() {
          row_lines(c, text(v, "accountText"), text(v, "accountNote"), wrap_sub=true)
        }) {
        run_list[of] = "account"
      }
      c.box(w=Fill(1.0), pady=12.0, fn() {
        c.text(tr("android-settings.run.note"), size=12.0, color=t.p.subtle, w=Fill(1.0), line=17.0) |> ignore
      })
      |> ignore
      c.spacer()
      // the model picked is another station's: said so over the button, which borrows it (asked again)
      match field(v, "borrow") {
        Some(Object(_)) as b => {
          let allowed = flag(b, "allowed")
          let borrowing = is_doing(core, ["pick.borrow"], [("station", station), ("of", of)])
          c.text(if allowed { text(b, "note") } else { opt_text(b, "why").unwrap_or(text(b, "note")) }, size=12.0, color=t.p.muted, w=Fill(1.0), line=17.0)
          |> ignore
          c.box(w=Fill(1.0), pt=8.0, pb=12.0, fn() {
            if wide_button(c, "run-borrow", text(b, "action"), allowed, busy=borrowing, enabled=allowed) {
              confirm_borrow(core, station, of, b)
            }
          })
          |> ignore
        }
        _ => {
          let changed = flag(v, "changed")
          let busy = is_doing(core, ["pick.save"], [("station", station), ("of", of)])
          c.box(w=Fill(1.0), pt=8.0, pb=12.0, fn() {
            if wide_button(c, "run-save", text(v, "saveText"), changed, busy~, enabled=!(changed && !has(draft, "model"))) {
              // back at once, not waiting on the station; failed, a toast says why
              (core.pop)()
              if changed {
                (core.call)("pick.save", obj([("station", str(station)), ("of", str(of))]), fn(r) {
                  match r {
                    Ok(_) => (core.say)(tr("android-settings.run.saved"))
                    Err(e) => (core.say)(fill("android-settings.run.saveFailed", [("error", error_text(e))]))
                  }
                })
              }
            }
          })
          |> ignore
        }
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The pickers opened (their `pick.set {open}` sent once a page), and which list a run page shows ("" its first view).
let run_opened : Map[String, Bool] = Map([])

///|
let run_list : Map[String, String] = Map([])

///|
/// Borrowing another station's model, asked again first (confirmBorrow: stations' setups may differ): its title, what
/// borrowing it means, then `pick.borrow` of `of` on `station` (a new chat's, a chat's agent's, a connect's).
pub fn confirm_borrow(core : Core, station : String, of : String, b : Json?) -> Unit {
  confirm(text(b, "title"), join(strings(b, "lines"), "\n\n"), text(b, "action"), fn() {
    act(core, text(b, "action"), "pick.borrow", obj([("station", str(station)), ("of", str(of))]), done=tr("android-chat.run.borrowed"))
  })
}

///|
/// Numbered steps, a line each, one with a link (`true`) its 打开 (Steps): which of them was tapped, -1 none.
fn steps(c : @ui.Ctx, key : String, list : Array[(String, Bool)]) -> Int {
  let t = @sf.theme()
  let mut tapped = -1
  c.box(w=Fill(1.0), gap=8.0, fn() {
    for i, s in list {
      c.box(dir=Row, w=Fill(1.0), gap=8.0, fn() {
        c.text((i + 1).to_string() + ".", size=14.0, color=t.p.muted, wrap=false, line=20.0) |> ignore
        c.box(w=Fill(1.0), gap=4.0, fn() {
          c.text(s.0, size=14.0, color=t.p.text, w=Fill(1.0), line=20.0) |> ignore
          if s.1 && tap_text(c, key + "/" + i.to_string(), tr("android-settings.open"), size=14.0) {
            tapped = i
          }
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  tapped
}

///|
/// A Slack workspace's app configuration token added (ConfigTokenSteps: by its refresh token, `slack.addConfigToken`;
/// in a new connect's flow, its draft's `connect.flow.config`), the access token Slack shows above it told apart.
fn config_token_steps(c : @ui.Ctx, core : Core, station : String, key : String, flow? : (String, Json?)? = None, saved? : (String) -> Unit = fn(_) {  }) -> Unit {
  let t = @sf.theme()
  let tapped = steps(c, key + "/steps", [
    (tr("android-settings.slack.step1"), true),
    (tr("android-settings.slack.step2"), false),
    (fill("android-settings.slack.step3", [("app", "still.fail")]), false),
  ])
  if tapped == 0 {
    (core.open_link)("https://api.slack.com/apps")
  }
  let config = field_box(c, key + "/config", "xoxe-1-…", secret=true).trim(chars=" \n").to_owned()
  match flow {
    Some((form, view)) => {
      if config != config_sent.val {
        config_sent.val = config
        // (told the core once the frame's builds are over)
        c.tell("config/" + form, fn() {
          act(core, tr("android-settings.flow.edit"), "connect.flow.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj([("config", str(config))]))]))
        })
      }
      match opt_text(view, "configError") {
        Some(e) => c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
        None => ()
      }
    }
    None =>
      if config.has_prefix("xoxe.xoxp-") {
        c.text(tr("android-settings.slack.accessToken"), size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      } else if config != "" && !config.has_prefix("xoxe-") {
        c.text(tr("android-settings.slack.refreshToken"), size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
      }
  }
  let (busy, ready) = match flow {
    Some((form, view)) =>
      (
        is_doing(core, ["connect.flow.config"], [("station", station), ("form", form)]),
        flag(view, "configReady"),
      )
    None => (is_doing(core, ["slack.addConfigToken"], [("station", station)]), config.has_prefix("xoxe-1-") && config.length() > 20)
  }
  c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
    if button(c, key + "/add", tr("android-settings.slack.add"), true, busy~, enabled=ready) {
      match flow {
        Some((form, _)) => flow_act(core, station, form, "config", fn(_) {  })
        None =>
          (core.call)("slack.addConfigToken", obj([("station", str(station)), ("refreshToken", str(config))]), fn(r) {
            match r {
              Ok(team) => {
                field_of(key + "/config").set("")
                (core.say)(tr("android-settings.slack.added"))
                saved(
                  match team {
                    String(s) => s
                    _ => text(Some(team), "team")
                  },
                )
              }
              Err(e) => (core.say)(error_text(e))
            }
          })
      }
    }
  })
  |> ignore
}

///|
/// What was last sent as a configuration token to a draft.
let config_sent : Ref[String] = Ref("")

// ---------------------------------------------------------------------------
// A new connect (NewConnectScreen over the core's `connectFlow`; ConnectFlow.kt)

///|
/// The new-connect pages open, by station: the draft's form, and what it resumes.
priv struct NewConnect {
  form : String
  resuming : String
  mut opened : Bool
  mut dropped : Bool
}

///|
let new_connects : Map[String, NewConnect] = Map([])

///|
/// A count of new connects' drafts opened (`connectFlow`): each its own `form`.
let connect_forms : Ref[Int] = Ref(0)

///|
/// A new connect on `station` (openNewConnect): from the start, or going on with a Slack app made before (`resuming`).
fn open_new_connect(core : Core, station : String, resuming? : String = "") -> Unit {
  connect_forms.val += 1
  new_connects[station] = { form: "mbui-connect-" + connect_forms.val.to_string(), resuming, opened: false, dropped: false }
  (core.push)(NewConnect(station))
}

///|
/// A step of the flow done (`connect.flow.<action>`), its answer to `done`.
fn flow_act(core : Core, station : String, form : String, action : String, done : (Json) -> Unit) -> Unit {
  (core.call)("connect.flow." + action, obj([("station", str(station)), ("form", str(form)), ("input", obj([]))]), fn(r) {
    match r {
      Ok(v) => done(v)
      Err(e) => (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.flow.add")), ("error", error_text(e))]))
    }
  })
}

///|
/// The draft of the new connect's page left (its page gone): `connect.flow.drop`.
fn new_connect_left(core : Core, station : String) -> Unit {
  match new_connects.get(station) {
    Some(n) if !n.dropped => {
      n.dropped = true
      act(core, tr("android-settings.flow.drop"), "connect.flow.drop", obj([("station", str(station)), ("form", str(n.form)), ("input", obj([]))]))
    }
    _ => ()
  }
}

///|
/// A new Slack connect, a step a screen (NewConnectScreen): the Slack workspace to make its app in (a configuration
/// token each, or a new one); the app's name and description; making and installing it, then the app-level token; last,
/// the model it runs and how its conversations become sessions. Without a configuration token the app is made in Slack
/// by hand and both tokens are pasted.
fn new_connect_page(c : @ui.Ctx, core : Core, here : Here, station : String) -> Unit {
  let t = @sf.theme()
  let n = match new_connects.get(station) {
    Some(n) => n
    None => {
      connect_forms.val += 1
      let n = { form: "mbui-connect-" + connect_forms.val.to_string(), resuming: "", opened: false, dropped: false }
      new_connects[station] = n
      n
    }
  }
  let form = n.form
  if !n.opened {
    n.opened = true
    tokens_sent.app_token = ""
    tokens_sent.bot_token = ""
    config_sent.val = ""
    // (opened once the frame's builds are over: the build that first comes to it alone)
    c.tell("flow-open/" + form, fn() {
      act(
        core,
        tr("android-settings.flow.open"),
        "connect.flow.open",
        obj([
          ("station", str(station)),
          ("form", str(form)),
          ("input", obj([("mobile", Json::boolean(true)), ("resume", if n.resuming == "" { Json::null() } else { str(n.resuming) })])),
        ]),
      )
    })
  }
  let view = (core.topic)("connectFlow", { "station": str(station), "form": str(form) }).value
  let edit = fn(input : Array[(String, Json)]) {
    act(core, tr("android-settings.flow.edit"), "connect.flow.edit", obj([("station", str(station)), ("form", str(form)), ("input", obj(input))]))
  }
  let go = fn(to : String) {
    (core.call)("connect.flow.go", obj([("station", str(station)), ("form", str(form)), ("input", obj([("to", str(to))]))]), fn(r) {
      match r {
        Ok(v) => if flag(Some(v), "close") { (core.pop)() }
        Err(e) => (core.say)(error_text(e))
      }
    })
  }
  let calls = ["connect.flow.config", "connect.flow.make", "connect.flow.verify", "connect.flow.register", "connect.flow.create"]
  let busy = is_doing(core, calls, [("station", station), ("form", form)])
  let error = failed_of(core, calls, [("station", station), ("form", form)])
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    guard view is Some(Object(_)) else {
      nav_bar(c, core, tr("common.cancel"), tr("android-settings.flow.title"))
      waiting_cards(c)
      return
    }
    let step = text(view, "step")
    let back = fn() { go("back") }
    if step != "team" {
      c.on_back(back)
    }
    // back: the step before, or (on the first) the page closed
    c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, gap=8.0, align=ACenter, fn() {
      if nav_back(c, tr(if text(view, "back") == "close" { "common.cancel" } else { "android-settings.flow.previous" })) {
        back()
      }
      c.box(w=Fill(1.0), align=ACenter, fn() {
        c.text(tr("android-settings.flow.title"), size=17.0, weight=600, color=t.p.text, wrap=false, line=22.0) |> ignore
        c.text("\{text(view, "title")} · \{count(view, "number")} / \{count(view, "total")}", size=11.0, color=t.p.muted, wrap=false, line=16.0)
        |> ignore
      })
      |> ignore
      c.box(w=Px(60.0), fn() {  }) |> ignore
    })
    |> ignore
    let blocks : Array[() -> Unit] = []
    let pad = fn(f : () -> Unit) { c.box(w=Fill(1.0), padx=18.0, pt=8.0, gap=12.0, f) |> ignore }
    let next = fn(key : String, label : String, enabled : Bool, run : () -> Unit) {
      flow_next(c, key, label, enabled, busy, run)
    }
    if step == "team" && flag(view, "noProfile") {
      // a connect runs a profile's model: with none on this station, that comes first
      blocks.push(fn() {
        c.box(w=Fill(1.0), pad=30.0, gap=10.0, align=ACenter, fn() {
          @sf.drawable(c, if t.dark { "illus_no_profile_dark" } else { "illus_no_profile" }, 240.0) |> ignore
          c.text(tr("android-settings.flow.noProfile"), size=17.0, weight=600, color=t.p.text, center=true, w=Fill(1.0)) |> ignore
          c.text(tr("android-settings.flow.noProfileNote"), size=14.0, color=t.p.muted, center=true, w=Fill(1.0), line=20.0)
          |> ignore
          if button(c, "flow-add-profile", tr("android-settings.flow.addProfile"), true) {
            (core.pop)()
            (core.push)(NewProfile(station))
          }
        })
        |> ignore
      })
    } else {
      // the model and mode pickers (Slack's last step; Feishu's bind, in its words)
      let bind = fn() {
              let pick = field(view, "pick")
              let models = items(pick, "options")
              let entry = field(pick, "valueOption")
              let rt = match text(field(pick, "value"), "runtime") {
                "" => "claude"
                r => r
              }
              c.text(tr("android-settings.connect.model"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              if models.length() == 0 {
                c.text(tr("android-settings.flow.noModels"), size=13.0, color=warn, w=Fill(1.0), line=18.0) |> ignore
              } else {
                c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, fn() {
                  for m in models {
                    let mv = Some(m)
                    let rts = strings(mv, "runtimes")
                    if pick_row(
                        c,
                        "flow-model/" + text(mv, "model"),
                        text(mv, "name"),
                        sub=join(rts.map(runtime_label), " · "),
                        checked=text(entry, "model") == text(mv, "model"),
                        mark=fn() { @sf.maker_mark(c, text(field(mv, "maker"), "id"), rts.get(0).unwrap_or("claude"), 18.0) |> ignore },
                      ) {
                      flow_choose(core, station, form, [("model", str(text(mv, "model")))])
                    }
                  }
                })
                |> ignore
              }
              let rts = strings(entry, "runtimes")
              if rts.length() > 1 {
                c.text(tr("android-settings.flow.runtime"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
                let i = seg(c, "flow-runtime", rts.map(runtime_label), rts.search(rt).unwrap_or(0), fill=true, height=36.0)
                if rts.get(i) != Some(rt) {
                  // (told the core once the frame's builds are over)
                  c.tell("flow-runtime/" + form, fn() { flow_choose(core, station, form, [("runtime", str(rts[i]))]) })
                }
              }
              c.text(tr("android-settings.mode.title"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              let mode = text(view, "mode")
              let mention = flag(view, "requireMention")
              let (m2, r2) = mode_choices(c, "flow-mode", mode, mention, kind=if step == "feishuBind" { "feishu" } else { "" })
              if m2 != mode || r2 != mention {
                edit([("mode", str(m2)), ("requireMention", Json::boolean(r2))])
              }
      }
      match step {
        "team" =>
          blocks.push(fn() {
            pad(fn() {
              let teams = items(view, "teams")
              if teams.length() == 0 {
                c.text(fill("android-settings.flow.tokenNote", [("app", "still.fail")]), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0)
                |> ignore
                flow_next(c, "flow-token", tr("android-settings.slack.addToken"), true, busy, fn() { go("token") })
                if tap_text(c, "flow-manual", tr("android-settings.flow.manualInSlack"), size=14.0) {
                  go("manual")
                }
              } else {
                c.text(tr("android-settings.flow.whichTeam"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
                let chosen = field(view, "chosen")
                c.box(w=Fill(1.0), radius=16.0, bg=t.p.card, clip=true, fn() {
                  for team in teams {
                    let tv = Some(team)
                    let owner = field(tv, "owner")
                    let sub = match owner {
                      Some(Object(_)) =>
                        text(owner, "user") +
                        (match opt_text(owner, "teamDomain") {
                          Some(d) => " · " + d + ".slack.com"
                          None => ""
                        })
                      _ => ""
                    }
                    if pick_row(c, "flow-team/" + text(tv, "teamId"), text(tv, "name"), sub~, checked=text(chosen, "teamId") == text(tv, "teamId")) {
                      edit([("team", str(text(tv, "teamId")))])
                    }
                  }
                })
                |> ignore
                if tap_text(c, "flow-add-team", tr("android-settings.flow.addTeamToken"), size=14.0) {
                  go("token")
                }
                match chosen {
                  Some(Object(_)) => {
                    let name = text(chosen, "name")
                    if tap_text(c, "flow-remove-team", fill("android-settings.flow.removeToken", [("name", name)]), color=t.p.muted, size=14.0) {
                      confirm(
                        fill("android-settings.flow.removeTokenTitle", [("name", name)]),
                        fill("android-settings.flow.removeTokenText", [("app", "still.fail")]),
                        tr("android-settings.members.remove"),
                        danger=true,
                        fn() {
                          act(core, tr("android-settings.flow.removeTokenWhat"), "slack.removeConfigToken", obj([("station", str(station)), ("team", str(text(chosen, "teamId")))]), done=tr("android-settings.flow.tokenRemoved"), then=fn(_) {
                            edit([("team", Json::null())])
                          })
                        },
                      )
                    }
                  }
                  _ => ()
                }
                if tap_text(c, "flow-manual", tr("android-settings.flow.manual"), size=14.0) {
                  go("manual")
                }
                flow_next(c, "flow-next", tr("android-settings.flow.next"), chosen is Some(Object(_)), busy, fn() { go("app") })
              }
            })
          })
        "token" => blocks.push(fn() { pad(fn() { config_token_steps(c, core, station, "flow-config", flow=Some((form, view))) }) })
        "app" =>
          blocks.push(fn() {
            pad(fn() {
              let settings = field(view, "settings")
              let label = fn(words : String) {
                c.text(words, size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
              }
              let fill_once = fn(key : String, value : String) {
                if !new_filled.contains(form + key) {
                  new_filled[form + key] = true
                  field_of(key).set(value)
                }
              }
              label(tr("android-settings.slack.name"))
              fill_once("flow-name/" + form, text(settings, "name"))
              let name = field_box(c, "flow-name/" + form, "still.fail")
              label(tr("android-settings.flow.description"))
              fill_once("flow-desc/" + form, text(settings, "description"))
              let desc = field_box(c, "flow-desc/" + form, tr("android-settings.slack.descriptionPlaceholder"))
              if name != text(settings, "name") || desc != text(settings, "description") {
                match settings {
                  Some(Object(m)) => {
                    let m2 = m.copy()
                    m2["name"] = str(name)
                    m2["displayName"] = str(name)
                    m2["description"] = str(desc)
                    edit([("settings", Json::object(m2))])
                  }
                  _ => ()
                }
              }
              // its icon and colour (AppLook, a new app's: the general helper to start)
              app_look(
                c,
                core,
                "flow-look/" + form,
                text(settings, "backgroundColor"),
                // (put in the flow once the frame is built: the look picks as it is built)
                fn(color) {
                  match settings {
                    Some(Object(m)) => {
                      let m2 = m.copy()
                      m2["backgroundColor"] = str(color)
                      c.after_build("flow-look/color", fn() { edit([("settings", Json::object(m2))]) })
                    }
                    _ => ()
                  }
                },
                fn(icon, error) {
                  c.after_build("flow-look/icon", fn() {
                    edit([
                    (
                      "icon",
                      match icon {
                        Some(i) => str(i)
                        None => Json::null()
                      },
                    ),
                      ("iconError", if error == "" { Json::null() } else { str(error) }),
                    ])
                  })
                },
                true,
              )
              match opt_text(view, "iconError") {
                Some(e) if e != "" => c.text(e, style=look_error) |> ignore
                _ => ()
              }
              c.text(tr("android-settings.flow.permsNote"), size=13.0, color=t.p.muted, w=Fill(1.0), line=18.0) |> ignore
              flow_next(c, "flow-make", tr("android-settings.flow.make"), flag(view, "canMake"), busy, fn() { flow_act(core, station, form, "make", fn(_) {  }) })
            })
          })
        "install" =>
          blocks.push(fn() {
            pad(fn() {
              let made = field(view, "made")
              guard made is Some(Object(_)) else {
                wait_line(c, tr("android-settings.flow.readingApp"))
                return
              }
              let install = opt_text(made, "install")
              let links = field(made, "links")
              let installed = flag(made, "installed")
              // its icon not taken by Slack (the app made all the same)
              match opt_text(view, "iconError") {
                Some(e) if e != "" => c.text(fill("android-settings.flow.iconFailed", [("error", e)]), style=look_error) |> ignore
                _ => ()
              }
              let team = first_text(made, ["installedTeam", "team"], tr("android-settings.flow.team"))
              let tapped = steps(c, "flow-install", [
                (
                  match install {
                    Some(_) =>
                      if installed {
                        fill("android-settings.flow.installed", [("team", team)])
                      } else {
                        tr("android-settings.flow.installOauth")
                      }
                    None => tr("android-settings.flow.installManual")
                  },
                  !installed,
                ),
                (tr("android-settings.flow.appToken"), true),
                (tr(if install is Some(_) { "android-settings.flow.pasteAppToken" } else { "android-settings.flow.pasteTokens" }), false),
              ])
              match tapped {
                0 => (core.open_link)(install.unwrap_or(text(links, "install")))
                1 => (core.open_link)(text(links, "appToken"))
                _ => ()
              }
              if install is None && tap_text(c, "flow-oauth", tr("android-settings.flow.oauthPage"), size=14.0) {
                (core.open_link)(text(links, "oauth"))
              }
              token_fields(c, core, station, form, ("", ""), install is Some(_))
              let tokens = (core.topic)("slackTokens", { "station": str(station), "form": str(form) }).value
              flow_next(c, "flow-verify", tr("android-settings.flow.next"), flag(tokens, "ready"), busy, fn() { flow_act(core, station, form, "verify", fn(_) {  }) })
            })
          })
        "manual" =>
          blocks.push(fn() {
            pad(fn() {
              let tapped = steps(c, "flow-manual-steps", [
                (fill("android-settings.flow.manual1", [("app", "still.fail")]), true),
                (tr("android-settings.flow.manual2"), false),
                (tr("android-settings.flow.manual3"), false),
                (tr("android-settings.flow.pasteTokens"), false),
              ])
              if tapped == 0 {
                (core.call)("slack.createAppUrl", obj([("station", str(station)), ("name", str("still.fail"))]), fn(r) {
                  match r {
                    Ok(String(url)) => (core.open_link)(url)
                    Ok(v) => (core.open_link)(text(Some(v), "url"))
                    Err(e) => (core.say)(error_text(e))
                  }
                })
              }
              token_fields(c, core, station, form, ("", ""), false)
              let tokens = (core.topic)("slackTokens", { "station": str(station), "form": str(form) }).value
              flow_next(c, "flow-verify", tr("android-settings.flow.next"), flag(tokens, "ready"), busy, fn() { flow_act(core, station, form, "verify", fn(_) {  }) })
            })
          })
        s if feishu_steps_drawn.contains(s) =>
          blocks.push(fn() { pad(fn() { feishu_steps(c, core, station, form, view, edit, go, bind, next, busy) }) })
        _ =>
          blocks.push(fn() {
            pad(fn() {
              bind()
              let entry = field(field(view, "pick"), "valueOption")
              flow_next(c, "flow-create", tr("android-settings.flow.create"), entry is Some(Object(_)), busy, fn() {
                flow_act(core, station, form, "create", fn(v) {
                  (core.say)(tr("android-settings.flow.created"))
                  (core.pop)()
                  (core.push)(Connect(station, text(Some(v), "id")))
                })
              })
            })
          })
      }
    }
    match error {
      Some(e) if !feishu_steps_drawn.contains(step) =>
        blocks.push(fn() {
          c.box(w=Fill(1.0), padx=18.0, pt=8.0, fn() {
            c.text(e, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
          })
          |> ignore
        })
      _ => ()
    }
    blocks.push(fn() { gap(c, 30.0) })
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { scroll_page(c, "new-connect/" + form + "/" + step, blocks) }) |> ignore
    ignore(here)
  })
  |> ignore
}

///|
/// The new connect's fields filled from its draft once (by form and field).
let new_filled : Map[String, Bool] = Map([])

///|
/// The model a new connect runs, picked and kept (ConnectFlow.choose: `pick.set` then `pick.save` of
/// `connect-new:<form>`).
fn flow_choose(core : Core, station : String, form : String, more : Array[(String, Json)]) -> Unit {
  let of = "connect-new:" + form
  let p = [("station", str(station)), ("of", str(of))]
  for x in more {
    p.push(x)
  }
  act(core, tr("android-settings.flow.choose"), "pick.set", obj(p), then=fn(_) {
    act(core, tr("android-settings.flow.choose"), "pick.save", obj([("station", str(station)), ("of", str(of))]))
  })
}

///|
/// A Slack app made on a station that no connect has taken yet (WaitingApp): where it stands, going on from there while
/// the station is online (`继续`), or its sheet (going on, or dropping it from here: `slack.dropApp`).
fn waiting_app(c : @ui.Ctx, core : Core, station : String, a : Json, online : Bool) -> Unit {
  let t = @sf.theme()
  let av = Some(a)
  let app_id = text(av, "appId")
  let where_ = if flag(av, "installed") {
    fill("android-settings.waiting.installed", [
      ("team", first_text(av, ["installedTeam", "team"], tr("android-settings.flow.team"))),
    ])
  } else if has(av, "install") {
    tr("android-settings.waiting.notInstalled")
  } else {
    tr("android-settings.waiting.noTokens")
  }
  let on = [("station", station), ("appId", app_id)]
  if list_row(c, key=if online { "waiting/" + app_id } else { "" }, fn() {
      c.box(w=Px(30.0), h=Px(30.0), align=ACenter, justify=JCenter, fn() { @sf.slack_mark(c, 16.0) |> ignore }) |> ignore
      row_lines(
        c,
        text(av, "name") +
        (match opt_text(av, "team") {
          Some(team) => " · " + team
          None => ""
        }),
        where_,
        wrap_sub=true,
        wrap_title=false,
      )
      doing_mark(c, is_doing(core, ["slack.dropApp"], on), failed_of(core, ["slack.dropApp"], on))
      if online {
        if tap_text(c, "waiting-go/" + app_id, tr("android-settings.waiting.continue"), size=14.0) {
          open_new_connect(core, station, resuming=app_id)
        }
      } else {
        c.text(tr("android-settings.waiting.offline"), size=12.0, color=t.p.muted, wrap=false) |> ignore
      }
    }) {
    open_sheet(0.36, fn(c, core) {
      let t = @sf.theme()
      sheet_head(c, text(av, "name"))
      if pick_row(c, "waiting-continue", tr("android-settings.waiting.continueRow")) {
        close_sheet()
        open_new_connect(core, station, resuming=app_id)
      }
      if pick_row(c, "waiting-remove", tr("android-settings.waiting.remove"), color=t.p.red) {
        confirm(
          fill("android-settings.station.removeTitle", [("name", text(av, "name"))]),
          fill("android-settings.waiting.removeText", [("app", "still.fail")]),
          tr("android-settings.members.remove"),
          danger=true,
          fn() {
            act(core, tr("android-settings.waiting.removeWhat"), "slack.dropApp", obj([("station", str(station)), ("appId", str(app_id))]), done=tr("android-settings.members.removed"))
          },
        )
      }
    })
  }
}

// ---------------------------------------------------------------------------
// A connect's Slack app (SlackApp.kt)

///|
/// Permission groups in their order (SLACK_GROUP_WORDS) and in the form's sections (SLACK_SECTIONS); those that work
/// only as Slack's admins allow (SLACK_ADMIN_GROUPS).
// kept across runs: a table of constants, never written
let slack_groups : Array[String] = [
  "base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics",
  "usergroups", "search", "connect", "more",
]

///|
// kept across runs: a table of constants, never written
let slack_sections : Array[(String, Array[String])] = [
  ("android-settings.slack.section.messages", ["base", "public", "dm", "customize", "reactions"]),
  ("android-settings.slack.section.channels", ["channels", "topics", "connect"]),
  ("android-settings.slack.section.files", ["files", "canvases", "lists"]),
  ("android-settings.slack.section.people", ["people", "usergroups", "search"]),
  ("android-settings.slack.section.other", ["extras", "more"]),
]

///|
/// (the groups' names: "android-settings.slack.group.base" "android-settings.slack.group.public" "android-settings.slack.group.dm" "android-settings.slack.group.customize" "android-settings.slack.group.files" "android-settings.slack.group.reactions" "android-settings.slack.group.channels" "android-settings.slack.group.people" "android-settings.slack.group.extras" "android-settings.slack.group.canvases" "android-settings.slack.group.lists" "android-settings.slack.group.topics" "android-settings.slack.group.usergroups" "android-settings.slack.group.search" "android-settings.slack.group.connect" "android-settings.slack.group.more")
// kept across runs: a table of constants, never written
let slack_admin_groups : Array[String] = ["connect", "usergroups"]

///|
/// A Slack app's settings being edited (AppDraft): what the form shows, by the connect, and what it started as (Slack's,
/// the key it was read under).
priv struct AppDraft {
  start : String
  mut name : String
  mut description : String
  mut color : String
  groups : Map[String, Bool]
  mut perms : Bool
  mut approve : Bool
  mut error : String
  mut fresh : Bool
  /// the icon made in its look (a data URL), to go with the rest; why one was not made, or not taken
  mut icon : String?
  mut icon_error : String
}

///|
let app_drafts : Map[String, AppDraft] = Map([])

///|
/// A connect's Slack app (SlackAppScreen): read from Slack through the station (`slackApp`); without the viewer's
/// configuration token for its Slack workspace, a way to add one; else its name, description, colour and
/// permissions, applied to Slack at once (`connect.putSlackApp`), Slack's page to approve new permissions handed over.
fn slack_app_page(c : @ui.Ctx, core : Core, station : String, connect : String) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("slackApp", { "station": str(station), "connect": str(connect) })
  let view = topic.value
  let k = station + "/" + connect
  let adding = slack_adding.get(k).unwrap_or(false)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    let sub = fn() { c.text(tr("android-settings.slack.sub"), size=11.0, color=t.p.muted, wrap=false, line=16.0) |> ignore }
    if adding {
      c.box(dir=Row, w=Fill(1.0), pl=10.0, pr=10.0, pt=6.0, pb=4.0, gap=8.0, align=ACenter, fn() {
        if nav_back(c, "Slack app") {
          slack_adding.remove(k)
        }
        c.box(w=Fill(1.0), align=ACenter, fn() {
          c.text(tr("android-settings.slack.addToken"), size=17.0, weight=600, color=t.p.text, wrap=false, line=22.0) |> ignore
          sub()
        })
        |> ignore
        c.box(w=Px(60.0), fn() {  }) |> ignore
      })
      |> ignore
      c.on_back(fn() { slack_adding.remove(k) })
    } else {
      nav_bar(c, core, tr("android-settings.connects.title"), "Slack app", sub~)
    }
    guard view is Some(Object(_)) else {
      waiting_cards(
        c,
        error=match topic.error {
          Some(e) => error_text(e)
          None => ""
        },
      )
      return
    }
    let blocks : Array[() -> Unit] = []
    let pad = fn(f : () -> Unit) { c.box(w=Fill(1.0), padx=18.0, pt=8.0, gap=12.0, f) |> ignore }
    let state = text(view, "state")
    let settings = field(view, "settings")
    let links = field(view, "links")
    if adding {
      blocks.push(fn() { pad(fn() { config_token_steps(c, core, station, "slack-config", saved=fn(_) { slack_adding.remove(k) }) }) })
    } else if state == "no_app" {
      blocks.push(fn() {
        pad(fn() {
          c.text(
            match opt_text(view, "error") {
              Some(e) => fill("android-settings.slack.noApp", [("error", e)])
              None => tr("android-settings.slack.notConnected")
            },
            size=14.0,
            color=t.p.muted,
            w=Fill(1.0),
            line=20.0,
          )
          |> ignore
        })
      })
    } else if state == "no_config_token" {
      blocks.push(fn() {
        pad(fn() {
          c.text(tr("android-settings.slack.needToken"), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0) |> ignore
          c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
            if button(c, "slack-add-token", tr("android-settings.slack.addToken"), true) {
              slack_adding[k] = true
            }
          })
          |> ignore
        })
      })
    } else if state == "error" || !(settings is Some(Object(_))) {
      blocks.push(fn() {
        pad(fn() {
          c.text(fill("android-settings.slack.readFailed", [("error", text(view, "error"))]), size=14.0, color=t.p.red, w=Fill(1.0), line=20.0)
          |> ignore
          c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
            if button(c, "slack-change-token", tr("android-settings.slack.changeToken"), false) {
              slack_adding[k] = true
            }
          })
          |> ignore
        })
      })
    } else {
      // made again from what Slack has: a change there (or a write from here) starts the form again from it
      let key = settings.unwrap().stringify()
      let d = match app_drafts.get(k) {
        Some(d) if d.start == key => d
        prev => {
          let groups : Map[String, Bool] = Map([])
          for g in slack_groups {
            groups[g] = flag(field(settings, "groups"), g)
          }
          let d = {
            start: key,
            name: text(settings, "name"),
            description: text(settings, "description"),
            color: text(settings, "backgroundColor"),
            groups,
            perms: false,
            approve: match prev {
              Some(p) => p.approve
              None => false
            },
            error: "",
            fresh: true,
            icon: None,
            icon_error: "",
          }
          // its look made again with it
          app_looks.remove("slack-app/" + k)
          app_drafts[k] = d
          d
        }
      }
      blocks.push(fn() { pad(fn() { app_form(c, core, station, connect, d, settings, links) }) })
    }
    match opt_text(links, "settings") {
      Some(url) if url != "" && !adding =>
        blocks.push(fn() {
          c.box(w=Fill(1.0), padx=18.0, pt=4.0, fn() {
            if tap_text(c, "slack-open", tr("android-settings.slack.open"), size=14.0) {
              (core.open_link)(url)
            }
          })
          |> ignore
        })
      _ => ()
    }
    blocks.push(fn() { gap(c, 30.0) })
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { scroll_page(c, "slack-app/" + k + "/" + adding.to_string(), blocks) }) |> ignore
  })
  |> ignore
}

///|
/// The Slack app pages adding a configuration token (by station/connect).
let slack_adding : Map[String, Bool] = Map([])

///|
/// The Slack app's form (AppForm): its name, description, colour, its permissions folded; 应用 writes what changed.
fn app_form(c : @ui.Ctx, core : Core, station : String, connect : String, d : AppDraft, settings : Json?, links : Json?) -> Unit {
  let t = @sf.theme()
  let busy = is_doing(core, ["connect.putSlackApp"], [("station", station), ("connect", connect)])
  let k = "slack-form/" + station + "/" + connect
  if d.fresh {
    d.fresh = false
    field_of(k + "/name").set(d.name)
    field_of(k + "/desc").set(d.description)
  }
  if d.approve {
    c.box(w=Fill(1.0), padx=12.0, pady=10.0, gap=8.0, radius=12.0, bg=@sf.alpha(t.p.blue, 0.10), fn() {
      c.box(dir=Row, w=Fill(1.0), gap=8.0, align=ACenter, fn() {
        @sf.icon(c, "shield-check", size=16.0, color=t.p.blue) |> ignore
        c.text(tr("android-settings.slack.approveNote"), size=13.0, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
      })
      |> ignore
      c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
        if button(c, "slack-approve", tr("android-settings.slack.approve"), true) {
          d.approve = false
          (core.open_link)(text(links, "install"))
        }
      })
      |> ignore
    })
    |> ignore
  }
  let label = fn(words : String) {
    c.text(words, size=13.0, weight=600, color=t.p.text, w=Fill(1.0), line=18.0) |> ignore
  }
  label(tr("android-settings.slack.name"))
  d.name = field_box(c, k + "/name", tr("android-settings.slack.name"))
  label(tr("android-settings.slack.description"))
  let desc = field_box(c, k + "/desc", tr("android-settings.slack.descriptionPlaceholder"))
  d.description = if desc.length() > 140 { desc.unsafe_substring(start=0, end=140) } else { desc }
  app_look(
    c,
    core,
    "slack-app/" + station + "/" + connect,
    d.color,
    fn(color) { d.color = color },
    fn(icon, error) {
      d.icon = icon
      d.icon_error = error
    },
    false,
  )
  if d.icon_error != "" {
    c.text(d.icon_error, style=look_error) |> ignore
  }
  // permissions, folded: changed now and then
  let on = slack_groups.iter().filter(fn(g) { d.groups.get(g).unwrap_or(false) }).count()
  c.box(dir=Row, w=Fill(1.0), pady=6.0, gap=6.0, align=ACenter, id=c.id(k + "/perms"), fn() {
    @sf.icon(c, if d.perms { "chevron-down" } else { "chevron-right" }, size=14.0, color=t.p.muted) |> ignore
    c.text(fill("android-settings.slack.perms", [("on", on.to_string()), ("n", slack_groups.length().to_string())]), size=14.0, color=t.p.muted, w=Fill(1.0), line=20.0)
    |> ignore
    if on < slack_groups.length() && tap_text(c, k + "/all-on", tr("android-settings.slack.allOn"), size=14.0) {
      for g in slack_groups {
        d.groups[g] = true
      }
    }
  })
  |> ignore
  if hit(c, c.id(k + "/perms")) {
    d.perms = !d.perms
  }
  if d.perms {
    for sec in slack_sections {
      let (title, groups) = sec
      let all = groups.iter().all(fn(g) { d.groups.get(g).unwrap_or(false) })
      c.box(dir=Row, w=Fill(1.0), pt=12.0, pb=2.0, gap=12.0, align=ACenter, fn() {
        c.text(tr(title), size=13.0, color=t.p.muted, wrap=false) |> ignore
        if tap_text(c, k + "/sec/" + title, tr(if all { "android-settings.none" } else { "android-settings.all" }), size=13.0) {
          for g in groups {
            d.groups[g] = g == "base" || !all
          }
        }
      })
      |> ignore
      for g in groups {
        let checked = d.groups.get(g).unwrap_or(false)
        let fixed = g == "base"
        let gid = c.id(k + "/group/" + g)
        if !fixed && hit(c, gid) {
          d.groups[g] = !checked
        }
        c.box(dir=Row, w=Fill(1.0), pady=9.0, gap=12.0, align=ACenter, id=gid, fn() {
          if fixed {
            c.box(w=Px(20.0), h=Px(20.0), align=ACenter, justify=JCenter, fn() {
              @sf.icon(c, "check", size=16.0, color=t.p.accent) |> ignore
            })
            |> ignore
          } else {
            c.box(w=Px(20.0), h=Px(20.0), radius=6.0, bg=if checked { t.p.accent } else { t.p.chip }, align=ACenter, justify=JCenter, fn() {
              if checked {
                @sf.icon(c, "check", size=13.0, color=t.p.bg) |> ignore
              }
            })
            |> ignore
          }
          c.text(tr("android-settings.slack.group." + g), size=14.0, color=if checked { t.p.text } else { t.p.muted }, wrap=false, w=Fill(1.0))
          |> ignore
          if slack_admin_groups.contains(g) {
            c.text(tr("android-settings.slack.admin"), size=12.0, color=t.p.muted, wrap=false) |> ignore
          }
        })
        |> ignore
      }
    }
  }
  if d.error != "" {
    c.text(d.error, size=13.0, color=t.p.red, w=Fill(1.0), line=18.0) |> ignore
  }
  // only what changed, for a write to an app that exists
  let changes : Array[(String, Json)] = []
  let name = d.name.trim(chars=" ").to_owned()
  if name != text(settings, "name") {
    changes.push(("name", str(name)))
    changes.push(("displayName", str(name)))
  }
  let description = d.description.trim(chars=" ").to_owned()
  if description != text(settings, "description") {
    changes.push(("description", str(description)))
  }
  if d.color != text(settings, "backgroundColor") {
    changes.push(("backgroundColor", str(d.color)))
  }
  if slack_groups.iter().any(fn(g) { d.groups.get(g).unwrap_or(false) != flag(field(settings, "groups"), g) }) {
    changes.push(("groups", Json::object(Map::from_array(slack_groups.map(fn(g) { (g, Json::boolean(d.groups.get(g).unwrap_or(false))) })))))
  }
  match d.icon {
    Some(icon) => changes.push(("icon", str(icon)))
    None => ()
  }
  let dirty = changes.length() > 0
  c.box(dir=Row, w=Fill(1.0), gap=8.0, justify=JEnd, fn() {
    if dirty && button(c, k + "/revert", tr("android-settings.slack.revert"), false) {
      app_drafts.remove(station + "/" + connect)
    }
    if button(c, k + "/apply", tr("android-settings.slack.apply"), true, busy~, enabled=dirty) {
      d.error = ""
      (core.call)("connect.putSlackApp", obj([("station", str(station)), ("connect", str(connect)), ("input", obj(changes))]), fn(r) {
        match r {
          Ok(v) => {
            // the icon gone with it: its look as it was, what Slack said of it kept
            d.icon = None
            d.icon_error = text(Some(v), "iconError")
            app_looks.remove("slack-app/" + station + "/" + connect)
            let updated = flag(Some(v), "permissionsUpdated")
            d.approve = updated
            // changed permissions are approved in Slack: its page handed over at once (the notice stays)
            if updated {
              (core.open_link)(text(links, "install"))
            }
            (core.say)(tr(if updated { "android-settings.slack.updatedApprove" } else { "android-settings.slack.updated" }))
          }
          Err(e) => d.error = error_text(e)
        }
      })
    }
  })
  |> ignore
}

///|
/// A colour written #RRGGBB, as a colour; None for anything else.
fn hex_color(s : String) -> Int64? {
  if s.length() != 7 || !s.has_prefix("#") {
    return None
  }
  let mut v = 0L
  for i in 1..<7 {
    let ch = s.unsafe_get(i).to_int()
    let d = if ch >= 48 && ch <= 57 {
      ch - 48
    } else if ch >= 65 && ch <= 70 {
      ch - 55
    } else if ch >= 97 && ch <= 102 {
      ch - 87
    } else {
      return None
    }
    v = v * 16L + d.to_int64()
  }
  Some((v << 8) | 0xFFL)
}

///|
/// A flow's step's button to go on, at its end: `run` as it is tapped.
fn flow_next(c : @ui.Ctx, key : String, label : String, enabled : Bool, busy : Bool, run : () -> Unit) -> Unit {
  c.box(dir=Row, w=Fill(1.0), justify=JEnd, fn() {
    if button(c, key, label, true, busy~, enabled~) {
      run()
    }
  })
  |> ignore
}
