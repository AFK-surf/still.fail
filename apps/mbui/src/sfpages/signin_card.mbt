// An agent's ask to sign in to a site, in place of its post's words (ember docs/vault.md 登录态, "Signing in from a
// card"; station vault/signin.ts): the one card a sign-in takes. Its person signs in from it with their own password
// manager, asked here as a page's login is filled from the remote screen (screen_fill.mbt: 1Password's command-line
// tool, which asks them itself, or the system's autofill service), and what it gives goes to the station
// (`signin.fill`), which types it into the chat's tab step by step and sends it; nothing of it is kept here, logged or
// shown. A code the page asks that the password manager did not give is typed on the card; where only the person can go
// on (a captcha, a code by mail), the card opens the tab's screen, and they say when they signed in. Signed in, kept in
// their vault as they chose on the card (登录后存入密钥库, the default, or not), approved here in place: no card of its
// own. Answered on screen, the card stays as it is until out of sight, then one line says how it went, as a vault
// request's does (vault_ask_card).

///|
/// What the password manager is asked of for a sign-in's card, between frames: the run of `op` under way, the logins to
/// pick from, and what was had of the one picked.
priv struct SignInRun {
  mut run : @hostapi.OpRun?
  mut choices : Array[@hostapi.PasswordLogin]
  mut picked : String
  mut username : String
  mut password : String
}

///|
let signin_runs : Map[String, SignInRun] = {}

///|
/// Where each card's asking is (by its id): "" nothing asked, listing / getting / otp (1Password asked), auto (the
/// system's autofill service offers its logins), choosing (logins to pick from), sending (to the station), said (why
/// it did not fill: `signin_notes`).
let signin_steps : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
let signin_notes : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// Whether each card's sign-in is to be kept in the vault (its menu's choice; kept unless said otherwise).
let signin_keep : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// The keep menu open (its card's id).
let signin_menu : Ref[String] = Ref("")

///|
/// The vault requests keeping a sign-in this device approved (asked, or failed): approved once.
let signin_saving : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// Each card's code field.
let signin_code : Map[String, @ui.Field] = {}

///|
fn signin_reset() -> Unit {
  signin_runs.clear()
  signin_steps.clear()
  signin_notes.clear()
  signin_keep.clear()
  signin_menu.val = ""
  signin_saving.clear()
  signin_code.clear()
}

///|
fn signin_run(id : String) -> SignInRun {
  match signin_runs.get(id) {
    Some(r) => r
    None => {
      let r = { run: None, choices: [], picked: "", username: "", password: "" }
      signin_runs[id] = r
      r
    }
  }
}

///|
/// Let go of what was asked for card `id`: the run stopped, what it gave forgotten.
fn signin_stop(id : String) -> Unit {
  match signin_runs.get(id) {
    Some(r) => {
      match r.run {
        Some(run) => run.end()
        None => ()
      }
      if signin_steps.get(id) == Some("auto") {
        @hostapi.autofill_end()
      }
    }
    None => ()
  }
  signin_runs.remove(id)
  signin_steps.remove(id)
  signin_notes.remove(id)
}

///|
fn signin_said(id : String, note : String) -> Unit {
  signin_stop(id)
  signin_notes[id] = note
  signin_steps[id] = "said"
}

///|
/// Whether this device can ask a password manager for a login: 1Password's tool (macOS, Windows), else the system's
/// autofill service (Android).
fn signin_manager() -> Bool {
  @hostapi.passwords() || @hostapi.autofill()
}

///|
/// 用 1Password 登录 pressed: the password manager asked for the site's logins.
fn signin_start(core : @settings.Core, station : String, ask : SignInAsk) -> Unit {
  signin_stop(ask.id)
  if !@hostapi.passwords() && @hostapi.autofill_ask(ask.site) {
    signin_steps[ask.id] = "auto"
    return
  }
  signin_op(core, station, ask, ["item", "list", "--categories", "Login", "--format", "json"], "listing")
}

///|
fn signin_op(_core : @settings.Core, _station : String, ask : SignInAsk, args : Array[String], step : String) -> Unit {
  match @hostapi.op_run(args) {
    Some(r) => {
      signin_run(ask.id).run = Some(r)
      signin_steps[ask.id] = step
    }
    None => signin_said(ask.id, @sf.t("android-misc.screen.fill.noOp"))
  }
}

///|
/// One of the site's logins picked (or the only one): its account and password asked for.
fn signin_pick(core : @settings.Core, station : String, ask : SignInAsk, l : @hostapi.PasswordLogin) -> Unit {
  let r = signin_run(ask.id)
  r.choices = []
  r.picked = l.id
  signin_op(core, station, ask, ["item", "get", l.id, "--fields", "label=username,label=password", "--reveal", "--format", "json"], "getting")
}

///|
/// The run under way ended: what it said taken (once).
fn signin_took(core : @settings.Core, station : String, ask : SignInAsk) -> Unit {
  let r = signin_run(ask.id)
  guard r.run is Some(run) else { return }
  guard run.done() is Some(d) else { return }
  run.end()
  r.run = None
  let step = signin_steps.get(ask.id).unwrap_or("")
  // (a login without a one-time code: sent without one; the page asks it on the card if it wants one)
  if step == "otp" {
    let code = if d.code == 0 { d.out.trim(chars=" \n").to_owned() } else { "" }
    signin_send(core, station, ask, r.username, r.password, code)
    return
  }
  match d.trouble() {
    Some(t) => {
      signin_said(ask.id, op_trouble_words(t))
      return
    }
    None => ()
  }
  match step {
    "listing" => {
      let found = @hostapi.logins_for(d.out, ask.site)
      if found.is_empty() {
        signin_said(ask.id, @sf.t("android-misc.screen.fill.none", args=[("host", ask.site)]))
      } else if found.length() == 1 {
        signin_pick(core, station, ask, found[0])
      } else {
        r.choices = found
        signin_steps[ask.id] = "choosing"
      }
    }
    "getting" => {
      let (username, password) = @hostapi.login_fields(d.out)
      if username == "" && password == "" {
        signin_said(ask.id, @sf.t("android-misc.screen.fill.empty"))
        return
      }
      r.username = username
      r.password = password
      // (its one-time code too, where it has one: the page asks it after the password)
      signin_op(core, station, ask, ["item", "get", r.picked, "--otp"], "otp")
    }
    _ => ()
  }
}

///|
/// What the password manager gave sent to the station, for the card's site only (the station types it into the tab
/// only while it is on that site); forgotten here once it went.
fn signin_send(core : @settings.Core, station : String, ask : SignInAsk, username : String, password : String, code : String) -> Unit {
  let login : Map[String, Json] = {}
  if username != "" {
    login["username"] = Json::string(username)
  }
  if password != "" {
    login["password"] = Json::string(password)
  }
  if code != "" {
    login["code"] = Json::string(code)
  }
  signin_stop(ask.id)
  signin_steps[ask.id] = "sending"
  // (the login an object: the core's doing keeps no copy of it)
  let params : Json = {
    "station": Json::string(station),
    "id": Json::string(ask.id),
    "login": Json::object(login),
    "keep": Json::boolean(signin_keep.get(ask.id).unwrap_or(true)),
  }
  (core.call)("signin.fill", params, fn(r) {
    match r {
      Ok(_) => signin_steps.remove(ask.id)
      Err(e) => signin_said(ask.id, @sf.t("android-misc.signin.failed", args=[("why", @settings.error_text(e))]))
    }
  })
}

///|
/// The person signs in on the tab's screen themselves (`done` false: the screen opened), or says they did.
fn signin_self(core : @settings.Core, station : String, ask : SignInAsk, done : Bool) -> Unit {
  if !done {
    (core.open_screen)(station, ask.screen)
  }
  (core.call)("signin.self", { "station": Json::string(station), "id": Json::string(ask.id), "done": Json::boolean(done) }, fn(r) {
    match r {
      Err(e) => (core.say)(@sf.t("android-misc.signin.failed", args=[("why", @settings.error_text(e))]))
      Ok(_) => ()
    }
  })
}

///|
/// Whether a sign-in's card has nothing more to answer: it ended, and what keeps it (where it is kept) was decided.
fn signin_over(ask : SignInAsk) -> Bool {
  match ask.status {
    "denied" | "expired" | "ended" => true
    "done" => ask.save == "" || ask.kept != ""
    _ => false
  }
}

///|
/// How it ended, in a line (vault_outcome's).
fn signin_outcome(c : @ui.Ctx, ask : SignInAsk, inline : Bool, history? : (String, (Int) -> Unit)? = None) -> Unit {
  @settings.ask_outcome(c, ask.status == "done", [@ui.span(signin_outcome_words(ask))], inline~, history~)
}

///|
fn signin_outcome_words(ask : SignInAsk) -> String {
  let site = [("site", ask.site)]
  match ask.status {
    "done" if ask.kept == "granted" => @sf.t("android-misc.signin.outcome.kept", args=site)
    "done" if ask.save != "" || !ask.keep => @sf.t("android-misc.signin.outcome.notKept", args=site)
    "done" => @sf.t("android-misc.signin.outcome.done", args=site)
    "denied" => @sf.t("android-misc.signin.outcome.denied", args=site)
    "expired" => @sf.t("android-misc.signin.outcome.expired", args=site)
    _ => @sf.t("android-misc.signin.outcome.ended")
  }
}

///|
/// What the card says the person is needed for, where only they can go on.
fn signin_person_words(ask : SignInAsk) -> String {
  match ask.why {
    "blocked" | "refused" | "stuck" | "self" => @sf.t("android-misc.signin.person." + ask.why)
    "elsewhere" => @sf.t("android-misc.signin.person.elsewhere", args=[("site", ask.site)])
    "agent" => @sf.t("android-misc.signin.person.agent", args=[("said", ask.said)])
    _ => @sf.t("android-misc.signin.person.stuck")
  }
}

///|
/// The card: its title and the agent's reason, and at its foot what is answered now (signin_foot); not the viewer's to
/// answer, whose it is.
fn signin_card(c : @ui.Ctx, here : MessageHere, card : Card, ask : SignInAsk) -> Unit {
  @sf.card(c, fn() {
    @sf.ask_words(c, @sf.t("android-misc.signin.title", args=[("site", ask.site)]), ask.reason)
    match here.core {
      Some(core) if mine_to(here, card.assignee) => signin_foot(c, core, here.station, ask)
      _ =>
        match card.assignee_text {
          Some(w) if w != "" => c.text(w, style=@sf.ask_note) |> ignore
          _ => ()
        }
    }
  })
  |> ignore
}

///|
fn signin_foot(c : @ui.Ctx, core : @settings.Core, station : String, ask : SignInAsk) -> Unit {
  let id = ask.id
  // a run under way: its end taken once it came (after this frame); the autofill service's pick, once it came
  match signin_runs.get(id) {
    Some({ run: Some(r), .. }) if r.done() is Some(_) => c.tell("signin-took/" + id, fn() { signin_took(core, station, ask) })
    _ => ()
  }
  let step = signin_steps.get(id).unwrap_or("")
  if step == "auto" {
    match @hostapi.autofill_take() {
      Some((host, username, password)) if host == ask.site =>
        c.tell("signin-auto/" + id, fn() {
          @hostapi.autofill_end()
          signin_send(core, station, ask, username, password, "")
        })
      _ => ()
    }
  }
  // signed in and to be kept: approved here, once (the request is this device's to approve: its person's)
  if ask.status == "done" && ask.save != "" && ask.kept == "" && !signin_saving.contains(ask.save) {
    c.tell("signin-save/" + id, fn() {
      signin_saving[ask.save] = "asked"
      (core.call)("vault.approve", { "workspace": Json::string(workspace_of(station)), "request": Json::string(ask.save) }, fn(r) {
        match r {
          Err(e) => {
            signin_saving[ask.save] = "failed"
            (core.say)(@sf.t("android-misc.signin.saveFailed", args=[("why", @settings.error_text(e))]))
          }
          Ok(_) => ()
        }
      })
    })
  }
  let note = fn(words : String) { c.text(words, style=@sf.ask_note) |> ignore }
  match ask.status {
    "done" => {
      note(@sf.t(if signin_saving.get(ask.save) == Some("failed") { "android-misc.signin.saveFailedShort" } else { "android-misc.signin.saving" }))
      return
    }
    "left" => {
      note(@sf.t("android-misc.signin.left"))
      return
    }
    "filling" => {
      @sf.ask_buttons(c, fn() {
        @sf.button(c, @sf.t("android-misc.signin.filling"), key="signin/" + id + "/go", tone=Primary, busy=true, disabled=true) |> ignore
      })
      return
    }
    "code" => {
      note(@sf.t("android-misc.signin.code", args=[("site", ask.site)]))
      let f = match signin_code.get(id) {
        Some(f) => f
        None => {
          let f = @ui.Field::new()
          signin_code[id] = f
          f
        }
      }
      // (reaching out to the foot's corners as the buttons under it do: the field's ends where theirs are, its words
      // where theirs are: vault_foot's typed field)
      let mut typed : @kit.Field = { text: "", submitted: false }
      @sf.card_foot_words(fn() {
        c.box(style=signin_typed.then(@sf.over_foot_reach(@sf.button_height())), fn() {
          typed = @sf.input(c, "signin/" + id + "/code", placeholder=@sf.t("android-misc.signin.codeField"), solid=true, field=f)
        })
        |> ignore
      })
      let code = typed.text.trim(chars=" ").to_owned()
      @sf.ask_buttons(c, fn() {
        if @sf.button(c, @sf.t("android-misc.signin.codeSend"), key="signin/" + id + "/code-go", tone=Primary, busy=step == "sending", disabled=code == "" || step == "sending") ||
          (typed.submitted && code != "") {
          c.tell("signin-code/" + id, fn() {
            signin_code.remove(id)
            signin_send(core, station, ask, "", "", code)
          })
        }
        if @sf.button(c, @sf.t("android-misc.signin.openScreen"), key="signin/" + id + "/screen", tone=Ghost) {
          (core.open_screen)(station, ask.screen)
        }
      })
      return
    }
    "person" => {
      note(signin_person_words(ask))
      @sf.ask_buttons(c, fn() {
        if @sf.button(c, @sf.t("android-misc.signin.openScreen"), key="signin/" + id + "/screen", tone=Primary) {
          (core.open_screen)(station, ask.screen)
        }
        if @sf.button(c, @sf.t("android-misc.signin.doneSelf"), key="signin/" + id + "/self-done", tone=Ghost) {
          c.tell("signin-self/" + id, fn() { signin_self(core, station, ask, true) })
        }
      })
      return
    }
    _ => ()
  }
  // waiting: what the password manager is at, the logins to pick from, or why it did not fill
  match step {
    "said" => note(signin_notes.get(id).unwrap_or(""))
    "auto" => note(@sf.t("android-misc.screen.fill.autoPick", args=[("host", ask.site)]))
    "choosing" => note(@sf.t("android-misc.screen.fill.pick", args=[("host", ask.site)]))
    // (1Password can take a while, a request of its to its servers slow: what it waits for said, and the screen
    // still there to sign in on instead)
    "listing" | "getting" | "otp" => note(@sf.t("android-misc.screen.fill.asking"))
    _ => ()
  }
  let asking = step == "listing" || step == "getting" || step == "otp" || step == "sending"
  @sf.ask_buttons(c, fn() {
    if step == "choosing" {
      for i, l in signin_run(id).choices {
        let words = if l.username == "" { l.title } else { l.title + " · " + l.username }
        if @sf.button(c, words, key="signin/" + id + "/pick/\{i}", tone=if i == 0 { Primary } else { Ghost }) {
          let picked = l
          c.tell("signin-pick/" + id, fn() { signin_pick(core, station, ask, picked) })
        }
      }
      return
    }
    if signin_manager() {
      let label = @sf.t(if @hostapi.passwords() { "android-misc.signin.withOp" } else { "android-misc.signin.withAuto" })
      if @sf.button(c, label, key="signin/" + id + "/go", tone=Primary, busy=asking, disabled=asking) {
        c.tell("signin-start/" + id, fn() { signin_start(core, station, ask) })
      }
      // (while 1Password is asked too: it is let go of then)
      if @sf.button(c, @sf.t("android-misc.signin.onScreen"), key="signin/" + id + "/self", tone=Ghost, disabled=step == "sending") {
        c.tell("signin-self/" + id, fn() {
          signin_stop(id)
          signin_self(core, station, ask, false)
        })
      }
    } else if @sf.button(c, @sf.t("android-misc.signin.onScreen"), key="signin/" + id + "/self", tone=Primary) {
      c.tell("signin-self/" + id, fn() { signin_self(core, station, ask, false) })
    }
    // kept in the vault once signed in, unless said otherwise
    let keep = signin_keep.get(id).unwrap_or(true)
    let words = fn(k : Bool) { @sf.t(if k { "android-misc.signin.keep" } else { "android-misc.signin.keepNot" }) }
    let m = @sf.chooser(
      c,
      "signin/" + id + "/keep",
      words(keep),
      [@kit.menu_radio("keep", keep, label=words(true)), @kit.menu_radio("not", !keep, label=words(false))],
      fn() { signin_menu.val == id },
      fn(on) {
        if on {
          signin_menu.val = id
        } else if signin_menu.val == id {
          signin_menu.val = ""
        }
      },
      side=Top,
      as_button=true,
    )
    match m.chosen {
      Some(v) => {
        signin_keep[id] = v == "keep"
        signin_menu.val = ""
      }
      None => ()
    }
  })
}

///|
/// An agent's ask to sign in, in place of its post's words: its card while it is answered, then a line saying how it
/// went (phone_ask_card's).
fn signin_ask_card(c : @ui.Ctx, here : MessageHere, m : Message, card : Card, ask : SignInAsk) -> Unit {
  let decided = signin_over(ask)
  let asking = fn() {
    c.box(style=@sf.ask_card_room.then(ask_card_under_head), fn() { signin_card(c, here, card, ask) }) |> ignore
  }
  let ended = fn() { signin_outcome(c, ask, here.inline) }
  match here.list {
    Some(l) => {
      let key = here.station + "/" + m.ts
      let open = l.turns.in_turn(c, "signin/" + m.ts, !decided, close_turn_ms, seen=seen_in(c, here, Some(m.seq)))
      let start_at = l.turns.start("signin/" + m.ts)
      under_post(
        c,
        "signin-card/" + key,
        open,
        exit=@motion.trans(fade=0.0, scale=options_scale, spec=@motion.tween(options_out_ms, ease=options_ease)),
        close=close_gap,
        start_at?,
        asking,
      )
      under_post(
        c,
        "signin-ended/" + key,
        decided && !open,
        start_at?,
        enter=@motion.trans(
          fade=0.0,
          spec=@motion.Snap(0.0),
          fade_spec=@motion.tween(options_out_ms, ease=Leave, delay=options_out_ms),
        ),
        open=close_gap,
        exit=@motion.trans(spec=@motion.Snap(0.0)),
        close=@motion.Snap(0.0),
        fn() {
          signin_outcome(c, ask, here.inline, history=Some(("signin/" + key, fn(id) {
            card_history(c, "signin/" + key, id, fn(p) {
              @sf.ask_words(p, @sf.t("android-misc.signin.title", args=[("site", ask.site)]), ask.reason)
            })
          })))
        },
      )
    }
    None => if decided { ended() } else { asking() }
  }
}

///|
/// A code's field over the card's buttons, as wide as the card's foot (vault_ask's ask_typed).
// kept across runs: a value (no field of it changes)
let signin_typed : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// The sign-in card (signin_card's) as nodes of the window's tree in `parent`, `ask` as it is now: its title and the
/// agent's reason, and at its foot what is answered now (signin_foot_node); not the viewer's to answer, whose it is.
fn signin_card_node(parent : @view.View, here : () -> MessageHere, card : () -> Card, ask : () -> SignInAsk) -> Unit {
  @sf.card_node(parent, fn(k) {
    @sf.ask_words_node(k, fn() { @sf.t("android-misc.signin.title", args=[("site", ask().site)]) }, fn() { ask().reason }) |> ignore
    let h = @signals.untracked(here)
    match h.core {
      Some(core) if mine_to(h, @signals.untracked(card).assignee) => signin_foot_node(k, core, h.station, ask)
      _ =>
        match @signals.untracked(card).assignee_text {
          Some(w) if w != "" => @sf.words_node(k, fn() { w }, fn() { @sf.ask_note }) |> ignore
          _ => ()
        }
    }
  })
  |> ignore
}

///|
/// What the sign-in card answers now (signin_foot's) in `k`: signed in and being kept, saying so; filling, its turning
/// button; a code the page asks, its field and 发送 (and the screen); where only the person can go on, why, the screen
/// and 我已登录; else what the password manager is at, the logins to pick from, or why it did not fill, and the ways
/// to sign in, the keep menu after them. What the host's password manager is asked runs between frames: taken as it
/// ends, followed while it goes (View::cycle).
fn signin_foot_node(k : @view.View, core : @settings.Core, station : String, ask : () -> SignInAsk) -> Unit {
  let id = @signals.untracked(ask).id
  let step = fn() { signin_steps.get(id).unwrap_or("") }
  let asking = fn() { step() == "listing" || step() == "getting" || step() == "otp" || step() == "sending" }
  // (a run under way, or the autofill service's pick: looked at as the frames go while it is asked, taken once it came)
  k.reacts(fn() {
    let s = step()
    if s == "listing" || s == "getting" || s == "otp" || s == "auto" {
      k.cycle(1000.0) |> ignore
      true
    } else {
      false
    }
  }, fn(waiting) {
    guard waiting else { return }
    let now = @signals.untracked(ask)
    match signin_runs.get(id) {
      Some({ run: Some(r), .. }) if r.done() is Some(_) => signin_took(core, station, now)
      _ => ()
    }
    if @signals.untracked(step) == "auto" {
      match @hostapi.autofill_take() {
        Some((host, username, password)) if host == now.site => {
          @hostapi.autofill_end()
          signin_send(core, station, now, username, password, "")
        }
        _ => ()
      }
    }
  })
  // (signed in and to be kept: approved here, once: the request is this device's to approve, its person's)
  k.reacts(fn() {
    let a = ask()
    a.status == "done" && a.save != "" && a.kept == "" && !signin_saving.contains(a.save)
  }, fn(due) {
    guard due else { return }
    let save = @signals.untracked(ask).save
    signin_saving[save] = "asked"
    (core.call)("vault.approve", { "workspace": Json::string(workspace_of(station)), "request": Json::string(save) }, fn(r) {
      match r {
        Err(e) => {
          signin_saving[save] = "failed"
          (core.say)(@sf.t("android-misc.signin.saveFailed", args=[("why", @settings.error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  })
  let note = fn(v : @view.View, words : () -> String) { @sf.words_node(v, words, fn() { @sf.ask_note }) |> ignore }
  k.pick(fn() {
    match ask().status {
      "done" | "left" | "filling" | "code" | "person" as s => s
      _ => ""
    }
  }, fn(f, status) {
    f.gap(Is(14.0)) |> ignore
    match status {
      "done" =>
        note(f, fn() {
          @sf.t(if signin_saving.get(ask().save) == Some("failed") { "android-misc.signin.saveFailedShort" } else { "android-misc.signin.saving" })
        })
      "left" => note(f, fn() { @sf.t("android-misc.signin.left") })
      "filling" =>
        @sf.ask_buttons_node(f, fn(b) {
          @sf.button_node(b, fn() { @sf.t("android-misc.signin.filling") }, fn() {  }, tone=Primary, busy=fn() { true }, disabled=fn() { true }, at_foot=true) |> ignore
        })
        |> ignore
      "code" => {
        note(f, fn() { @sf.t("android-misc.signin.code", args=[("site", ask().site)]) })
        let field = match signin_code.get(id) {
          Some(x) => x
          None => {
            let x = @ui.Field::new()
            signin_code[id] = x
            x
          }
        }
        let code = fn() { field.text().trim(chars=" ").to_owned() }
        let send = fn() {
          let c = @signals.untracked(code)
          if c != "" && @signals.untracked(step) != "sending" {
            signin_code.remove(id)
            signin_send(core, station, @signals.untracked(ask), "", "", c)
          }
        }
        @sf.over_foot_node(f, fn(o) {
          @sf.input_node(o, field, placeholder=@sf.t("android-misc.signin.codeField"), submitted=fn(_) { send() }, at_foot=true) |> ignore
        })
        |> ignore
        @sf.ask_buttons_node(f, fn(b) {
          @sf.button_node(b, fn() { @sf.t("android-misc.signin.codeSend") }, send, tone=Primary, busy=fn() { step() == "sending" }, disabled=fn() {
            code() == "" || step() == "sending"
          }, at_foot=true)
          |> ignore
          @sf.button_node(b, fn() { @sf.t("android-misc.signin.openScreen") }, fn() { (core.open_screen)(station, ask().screen) }, tone=Ghost, at_foot=true) |> ignore
        })
        |> ignore
      }
      "person" => {
        note(f, fn() { signin_person_words(ask()) })
        @sf.ask_buttons_node(f, fn(b) {
          @sf.button_node(b, fn() { @sf.t("android-misc.signin.openScreen") }, fn() { (core.open_screen)(station, ask().screen) }, tone=Primary, at_foot=true) |> ignore
          @sf.button_node(b, fn() { @sf.t("android-misc.signin.doneSelf") }, fn() { signin_self(core, station, @signals.untracked(ask), true) }, tone=Ghost, at_foot=true) |> ignore
        })
        |> ignore
      }
      _ => {
        // waiting: what the password manager is at, the logins to pick from, or why it did not fill
        f.show(fn() { step() != "" && step() != "sending" }, fn(n) {
          note(n, fn() {
            match step() {
              "said" => signin_notes.get(id).unwrap_or("")
              "auto" => @sf.t("android-misc.screen.fill.autoPick", args=[("host", ask().site)])
              "choosing" => @sf.t("android-misc.screen.fill.pick", args=[("host", ask().site)])
              // (1Password can take a while: what it waits for said, the screen still there to sign in on instead)
              "listing" | "getting" | "otp" => @sf.t("android-misc.screen.fill.asking")
              _ => ""
            }
          })
        })
        @sf.ask_buttons_node(f, fn(b) {
          b.pick(fn() { if step() == "choosing" { 2 } else if signin_manager() { 1 } else { 0 } }, fn(row, way) {
            let choosing = way == 2
            row.row(Is(true)).gap(Is(10.0)).wraps(By(fn() { Some(@sf.ask_foot_lines()) })).wraps_up(Is(true)) |> ignore
            if choosing {
              for i, l in signin_run(id).choices {
                let words = if l.username == "" { l.title } else { l.title + " · " + l.username }
                let picked = l
                @sf.button_node(row, fn() { words }, fn() { signin_pick(core, station, @signals.untracked(ask), picked) }, tone=if i == 0 {
                  Primary
                } else {
                  Ghost
                }, at_foot=true)
                |> ignore
              }
              return
            }
            if way == 1 {
              let label = @sf.t(if @hostapi.passwords() { "android-misc.signin.withOp" } else { "android-misc.signin.withAuto" })
              @sf.button_node(row, fn() { label }, fn() { signin_start(core, station, @signals.untracked(ask)) }, tone=Primary, busy=asking, disabled=asking, at_foot=true) |> ignore
              // (while 1Password is asked too: it is let go of then)
              @sf.button_node(row, fn() { @sf.t("android-misc.signin.onScreen") }, fn() {
                signin_stop(id)
                signin_self(core, station, @signals.untracked(ask), false)
              }, tone=Ghost, disabled=fn() { step() == "sending" }, at_foot=true)
              |> ignore
            } else {
              @sf.button_node(row, fn() { @sf.t("android-misc.signin.onScreen") }, fn() { signin_self(core, station, @signals.untracked(ask), false) }, tone=Primary, at_foot=true) |> ignore
            }
            // kept in the vault once signed in, unless said otherwise
            let keep = fn() { signin_keep.get(id).unwrap_or(true) }
            let words = fn(k : Bool) { @sf.t(if k { "android-misc.signin.keep" } else { "android-misc.signin.keepNot" }) }
            let menu_told = @signals.signal(0)
            @sf.chooser_node(row, fn() { words(keep()) }, fn() {
              [true, false].map(fn(k) {
                Some(@sf.menu_item_of(words(k), fn() {
                  signin_keep[id] = k
                  signin_menu.val = ""
                  menu_told.set(menu_told.get() + 1)
                }, chosen=k == keep()))
              })
            }, fn() {
              menu_told.get() |> ignore
              signin_menu.val == id
            }, fn(on) {
              if on {
                signin_menu.val = id
              } else if signin_menu.val == id {
                signin_menu.val = ""
              }
              menu_told.set(@signals.untracked(fn() { menu_told.get() }) + 1)
            }, side=Top, at_foot=true, as_button=true)
            |> ignore
          })
        })
        |> ignore
      }
    }
  })
}

///|
/// An agent's ask to sign in in place of post `m`'s words (signin_ask_card's) in `v`: its card while it is answered,
/// then a line saying how it went, its card as it was a press away.
fn signin_ask_card_node(v : @view.View, here : () -> MessageHere, m : () -> Message) -> Unit {
  let card = fn() { m().card.unwrap() }
  let ask = fn() {
    match m().card {
      Some({ signin: Some(a), .. }) => a
      _ => abort("no sign-in")
    }
  }
  let decided = fn() {
    match m().card {
      Some({ signin: Some(a), .. }) => signin_over(a)
      _ => true
    }
  }
  asked_or_ended_node(v, here, decided, fn(u) {
    u.padding(Is((0.0, 8.0, 0.0, 0.0))) |> ignore
    @sf.ask_card_room_node(u, fn(room) { signin_card_node(room, here, card, ask) }) |> ignore
  }, fn(u) {
    @settings.ask_outcome_node(u, fn() { ask().status == "done" }, fn() { [@ui.span(signin_outcome_words(ask()))] }, fn() {
      here().inline
    }, history=Some(fn(at) {
      let a = @signals.untracked(ask)
      card_history_open(at, fn(p) { @sf.ask_words(p, @sf.t("android-misc.signin.title", args=[("site", a.site)]), a.reason) })
    }))
  })
}
