// An agent's request about a vault item answered here (vault_ask.mbt's vault_foot, vault_actions), as nodes of the
// window's tree, made once, following the card or the vaults topic and the core as they change: 允许 / 存入 and 拒绝 /
// 不存 with how long a use is allowed beside them (or on a line of its own over them where they have not the room: one
// of the two arrangements, by the width the foot is laid out at, View::one_of), what the person types in over them; a
// line where there is no answer to give here. What it keeps between frames is keyed by its request (vault_pending,
// vault_picked, vault_timeout_minutes, vault_typed: signals). Not here yet: a file the person picks (the system's
// picker's answer is only looked at each frame, @hostapi.polled): what asks for one draws nothing here.

///|
/// What stands at a request's foot in place of an answer where there is none to give here, as `answer` says it ("":
/// buttons, or nothing).
fn vault_line_words(answer : Answer?) -> String {
  match answer {
    Some(Elsewhere) => tr("android-settings.vault.approve.inApp")
    Some(NotHere) => tr("web-pages.vault.approve.notHere")
    Some(Decided) => tr("android-settings.vault.approve.decided")
    Some(Theirs(w)) => w
    _ => ""
  }
}

///|
/// `n` minutes in words (days, hours or minutes, the largest that says it whole).
fn vault_minutes_words(n : Int) -> String {
  let days = n % 1440 == 0
  let hours = n % 60 == 0
  fill(
    if days {
      "android-settings.vault.timeout.nDays"
    } else if hours {
      "android-settings.vault.timeout.nHours"
    } else {
      "android-settings.vault.timeout.nMinutes"
    },
    [("n", (if days { n / 1440 } else if hours { n / 60 } else { n }).to_string())],
  )
}

///|
/// The answer to request `request()` in workspace `ws()` in `v` (vault_foot's, as nodes), as `answer()` says it now
/// (None: nothing yet), `save()` (one to keep a secret), `typed()` (its secret the person's to type in: its fields over
/// the buttons), `timeout()` (the kind and seconds asked for: how long, chosen in 授权时限): the buttons, or a line where
/// there is none to give here, each made in `v` as the old one's are in what holds it (its gap between them). `foot`:
/// last on its card, in the card's foot corners (@sf.foot_reach), its words where the card's are. Pressed, the one
/// pressed turns and neither takes a press till the core has it; what was typed goes with 允许 and is let go once it
/// went, the keyboard with it.
pub fn vault_foot_node(
  v : @view.View,
  core : Core,
  ws : () -> String,
  request : () -> String,
  answer : () -> Answer?,
  save : () -> Bool,
  typed : () -> Typed?,
  timeout : () -> (String, Int),
  foot~ : Bool,
  describe? : () -> Bool = fn() { false },
  remove? : () -> Bool = fn() { false },
) -> Unit {
  let lasts = fn() {
    match answer() {
      Some(Approve(l)) => l
      _ => ""
    }
  }
  let timed = fn() { !save() && timeout().1 > 0 }
  let scopes = fn() {
    if save() {
      ["once"]
    } else if timed() {
      if lasts() == "once" {
        ["once"]
      } else {
        ["once", "idle", "fixed"]
      }
    } else {
      vault_scopes_up_to(lasts())
    }
  }
  let scope = fn() {
    let all = scopes()
    match vault_picked.get(request()) {
      Some(s) if all.contains(s) => s
      _ => if timed() && all.contains(timeout().0) { timeout().0 } else { all[all.length() - 1] }
    }
  }
  let pending = fn() { vault_pending.get(request()) }
  let on = fn() { [("workspace", ws()), ("request", request())] }
  let busy = fn(yes : Bool) {
    pending() == Some(yes) || is_doing(core, [if yes { "vault.approve" } else { "vault.deny" }], on())
  }
  let under = fn() { pending() is Some(_) || is_doing(core, ["vault.approve", "vault.deny"], on()) }
  let max_minutes = fn() { if lasts() == "hour" { 60 } else { 43200 } }
  let minutes = fn() {
    let asked = (timeout().1 + 59) / 60
    let most = max_minutes()
    vault_timeout_minutes.get(request()).unwrap_or(if asked < most { asked } else { most })
  }
  let valid_time = fn() {
    let m = minutes()
    !timed() || scope() == "once" || (m > 0 && m <= max_minutes())
  }
  // (what is typed in for each request, kept by it: the one kept from before, else one of its own here till something
  // is typed in it, then kept)
  let fields : Map[String, @ui.Field] = Map([])
  let field_of = fn(part : String) {
    let key = request() + part
    match fields.get(key) {
      Some(f) => f
      None => {
        let f = @signals.untracked(fn() { vault_typed.get(key) }).unwrap_or(@ui.Field::new())
        fields[key] = f
        f
      }
    }
  }
  let keep = fn(part : String) {
    let key = @signals.untracked(request) + part
    if !vault_typed.contains(key) {
      vault_typed[key] = field_of(part)
    }
  }
  let typing = fn() {
    match (answer(), typed()) {
      (Some(Approve(_)), Some(ty)) if ty.kind != "file" => Some(ty)
      _ => None
    }
  }
  let asks_user = fn() {
    match typing() {
      Some(ty) => ty.kind == "login" && ty.username == ""
      None => false
    }
  }
  let empty = fn() { typed() is Some(_) && field_of("/secret").text().trim(chars=" \n\t").to_owned() == "" }
  let act = fn(yes : Bool, call : String, what : String, params : Json) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    let r = @signals.untracked(request)
    vault_pending[r] = yes
    // (what was typed in is answered: its field goes as the card says how it went, the keyboard with it)
    if @signals.untracked(typed) is Some(_) {
      for part in ["/secret", "/username"] {
        match fields.get(r + part) {
          Some(f) => f.let_go()
          None => ()
        }
      }
    }
    (core.call)(call, params, fn(res) {
      match res {
        Err(e) => {
          vault_pending.remove(r)
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => {
          vault_typed.remove(r + "/secret")
          vault_typed.remove(r + "/username")
          vault_files.remove(r)
        }
      }
    })
  }
  let approve = fn() {
    @signals.untracked(fn() {
      let s = save()
      let sc = scope()
      let t = timed()
      let m = minutes()
      let what = tr(if remove() { "android-settings.vault.act.removeWhat" } else if describe() { "android-settings.vault.act.changeWhat" } else if s { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" })
      let chosen = if !t || sc == "once" { if s { "once" } else { sc } } else if m <= 60 { "hour" } else { "chat" }
      let params : Array[(String, Json)] = [("workspace", str(ws())), ("request", str(request())), ("scope", str(chosen))]
      if t && sc != "once" {
        params.push(("timeout", obj([("kind", str(sc)), ("seconds", Json::number((m * 60).to_double()))])))
      }
      if typed() is Some(_) {
        let given : Array[(String, Json)] = [("secret", str(field_of("/secret").text()))]
        let user = if asks_user() { field_of("/username").text() } else { "" }
        if user.trim(chars=" ").to_owned() != "" {
          given.push(("username", str(user)))
        }
        params.push(("typed", obj(given)))
      }
      act(true, "vault.approve", what, obj(params))
    })
  }
  let ready = fn() { !under() && !empty() && valid_time() }
  // where there is no answer to give here: a line saying so
  v.show(fn() { vault_line_words(answer()) != "" }, fn(s) {
    @sf.words_node(s, fn() { vault_line_words(answer()) }, fn() { @sf.ask_note }) |> ignore
  })
  // a secret the person types in: its fields over the buttons (a login's account first, where the agent named none),
  // its ends where theirs are on a card (out in its foot corners)
  v.show(fn() { typing() is Some(_) }, fn(s) {
    s.width_share(Is(1.0)) |> ignore
    s.pick(fn() { (request(), typing().map(fn(ty) { ty.kind }).unwrap_or(""), asks_user()) }, fn(p, at) {
      p.width_share(Is(1.0)) |> ignore
      let (_, kind, user) = at
      p.box(fn(b) {
        @sf.style_node(b, fn() { if foot { ask_typed.then(@sf.over_foot_reach(@sf.button_height())) } else { ask_typed } })
        if user {
          @sf.input_node(
            b,
            field_of("/username"),
            placeholder=tr("android-settings.vault.ask.typed.username"),
            disabled=under,
            solid=true,
            card_words=foot,
            edited=fn(_) { keep("/username") },
          )
          |> ignore
        }
        let words = tr("android-settings.vault.ask.typed." + kind)
        if kind == "ssh_key" {
          @sf.textarea_node(b, field_of("/secret"), rows=4, placeholder=words, solid=true, card_words=foot, edited=fn(_) {
            keep("/secret")
          })
          |> ignore
        } else {
          @sf.input_node(
            b,
            field_of("/secret"),
            placeholder=words,
            secret=true,
            disabled=under,
            solid=true,
            card_words=foot,
            edited=fn(_) { keep("/secret") },
            // (Enter as 存入, where it may be pressed)
            submitted=fn(_) { if @signals.untracked(ready) { approve() } },
          )
          |> ignore
        }
      })
      |> ignore
    })
  })
  // its buttons, last in the card's foot corners; how long beside them where the foot has the room for it, else on a
  // line of its own over them (never under: the buttons keep the foot), its ends where theirs are; beside them on a
  // card, how long chosen in 授权时限 across from them, in the foot's end corner as they are in its start corner
  let picks = fn() { !save() && scopes().length() > 1 }
  let choice = fn(at : @view.View) {
    at.pick(timed, fn(p, by_panel) {
      if by_panel {
        // (how long in words, pressed for 授权时限)
        let words = fn() {
          if scope() == "once" {
            tr("android-settings.vault.scope.once")
          } else {
            fill("android-settings.vault.timeout.button." + scope(), [("time", vault_minutes_words(minutes()))])
          }
        }
        let open = fn() {
          @signals.untracked(fn() { vault_timeout_open(request(), minutes(), max_minutes(), scope()) })
        }
        if foot {
          @sf.foot_chooser_node(p, words, fn() { [] }, fn() { "" }, fn(_) {  }, press=open, disabled=under) |> ignore
        } else {
          @sf.chooser_node(p, words, fn() { [] }, fn() { "" }, fn(_) {  }, press=open, disabled=under) |> ignore
        }
      } else {
        let words = fn() { tr("android-settings.vault.scope." + scope()) }
        let choices = fn() { scopes().map(fn(s) { (s, tr("android-settings.vault.scope." + s)) }) }
        let choose = fn(s : String) { vault_picked[@signals.untracked(request)] = s }
        if foot {
          @sf.foot_chooser_node(p, words, choices, scope, choose) |> ignore
        } else {
          @sf.chooser_node(p, words, choices, scope, choose) |> ignore
        }
      }
    })
  }
  let acts = fn(at : @view.View) {
    at.pick(fn() { answer() is Some(SetUp) }, fn(p, set_up) {
      @sf.style_node(p, fn() { @sf.ask_foot })
      if set_up {
        // (kept only in a vault that is on here: the way to turn it on first)
        @sf.button_node(p, fn() { tr("android-settings.vault.turnOn") }, fn() { (core.push)(Route::Vault) }, tone=Primary, card_words=foot)
        |> ignore
      } else {
        @sf.button_node(
          p,
          fn() { tr(if remove() { "android-settings.vault.act.remove" } else if describe() { "android-settings.vault.act.change" } else if save() { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }) },
          approve,
          tone=Primary,
          busy=fn() { busy(true) },
          disabled=fn() { under() || empty() || !valid_time() },
          card_words=foot,
        )
        |> ignore
      }
      @sf.button_node(
        p,
        fn() { tr(if remove() { "android-settings.vault.act.dontRemove" } else if describe() { "android-settings.vault.act.dontChange" } else if save() { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }) },
        fn() {
          let r = @signals.untracked(request)
          act(false, "vault.deny", tr("android-settings.vault.act.denyWhat"), obj([("workspace", str(@signals.untracked(ws))), ("request", str(r))]))
        },
        tone=Ghost,
        busy=fn() { busy(false) },
        disabled=under,
        card_words=foot,
      )
      |> ignore
    })
  }
  let foot_row = fn(at : @view.View, beside : Bool) {
    at.box(fn(f) {
      @sf.style_node(f, fn() {
        if foot && beside && timed() {
          // (how long, chosen in 授权时限, across from the buttons in the card's foot end corner, concentric with it)
          @sf.ask_foot_chosen_end()
        } else if foot {
          @sf.ask_foot.then(@sf.foot_reach(@sf.button_height()))
        } else {
          @sf.ask_foot
        }
      }, in_row=beside)
      f.wraps(By(fn() { Some(@sf.ask_foot_lines()) })) |> ignore
      acts(f)
      if beside {
        choice(f)
      }
    })
    |> ignore
  }
  v.show(fn() { answer() is Some(Approve(_) | SetUp) }, fn(s) {
    s.width_share(Is(1.0)) |> ignore
    s.pick(picks, fn(r, two) {
      // (across what holds it: ask_room's)
      r.width_share(Is(1.0)) |> ignore
      if !two {
        foot_row(r, false)
      } else {
        // (the first that has the room whole: how long beside the buttons, else on its own line over them)
        r.row(Is(true)).one_of(Is(true)) |> ignore
        foot_row(r, true)
        r.box(fn(w) {
          w.box(fn(o) {
            @sf.style_node(o, fn() { if foot { ask_over.then(@sf.over_foot_reach(@sf.button_height())) } else { ask_over } })
            choice(o)
          })
          |> ignore
          foot_row(w, false)
        })
        |> ignore
      }
    })
  })
}

///|
/// The answer to request `request()` in workspace `ws()` in `v` (vault_actions', as nodes), as the vaults topic says it
/// now (a card from before its station said what it asks, under its post): the buttons while it waits on the viewer
/// (`mine()`), or a line where there is no answer to give here (`who()`: whose it is); nothing while the topic has not
/// come, nor where it asks for a file to be picked (not here yet: see the head).
pub fn vault_actions_node(
  v : @view.View,
  core : Core,
  ws : () -> String,
  request : () -> String,
  mine : () -> Bool,
  who? : () -> String? = fn() { None },
) -> Unit {
  let row = fn() { items(vaults_of(core, ws()), "requests").iter().find_first(fn(r) { text(Some(r), "id") == request() }) }
  let said = fn() {
    match topic_answer(core, ws(), request(), mine(), who()) {
      Some((Approve(_), _, Some({ kind: "file", .. }))) => None
      s => s
    }
  }
  vault_foot_node(
    v,
    core,
    ws,
    request,
    fn() { said().map(fn(s) { s.0 }) },
    fn() { said().map(fn(s) { s.1 }).unwrap_or(false) },
    fn() { said().bind(fn(s) { s.2 }) },
    fn() {
      let r = row()
      (text(r, "timeoutKind"), count(r, "timeoutSeconds"))
    },
    foot=false,
    describe=fn() { field(row(), "describe") is Some(_) },
    remove=fn() { flag(row(), "remove") },
  )
}

///|
/// What is asked's title (vault_asked's): 使用 …, 存入密码 … and the account (the item's name in it heavier than the
/// words around it, not in quotes), as the theme has its ink now.
fn vault_title_runs(ask : Asked) -> Array[@ui.Run] {
  let t = @sf.theme()
  let save = ask.save_kind != ""
  let named = fn(n) { @ui.span(n, weight=600, color=t.p.text) }
  let words = fn(w) { @ui.span(w, weight=400, color=t.p.text) }
  let runs = if ask.remove {
    fill_named("android-settings.vault.ask.remove", [("name", ask.name)], named, words)
  } else if ask.describe {
    describe_title_runs(ask, named, words)
  } else if save {
    fill_named(
      "android-settings.vault.ask.save",
      [("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)), ("name", ask.name)],
      named,
      words,
    )
  } else {
    fill_named("android-settings.vault.ask.use", [("name", ask.name)], named, words)
  }
  let sub = if ask.username != "" { ask.username } else { ask.filename }
  if save && sub != "" {
    runs.push(@ui.span("  " + sub, color=t.p.muted))
  }
  runs
}

///|
/// What is out of the ordinary in what is asked (vault_asked's): a command that reads the secret itself, one run on
/// another station; none where neither is.
fn vault_odd_runs(ask : Asked) -> Array[@ui.Run] {
  let risky = !ask.writes() && (ask.mode == "env" || ask.mode == "file")
  let elsewhere = ask.station != ""
  let runs : Array[@ui.Run] = []
  if risky {
    runs.push(@ui.span(tr("android-settings.vault.ask.plain"), color=@sf.theme().p.warn_ink))
  }
  if risky && elsewhere {
    runs.push(@ui.span(" · "))
  }
  if elsewhere {
    runs.push(@ui.span(fill("android-settings.vault.ask.on", [("station", ask.station)])))
  }
  runs
}

///|
/// Words `runs()` in `v` in `style` (its size, line, ink: what a TextStyle says of words), as they say it now.
fn vault_runs_node(v : @view.View, runs : () -> Array[@ui.Run], style : @ui.TextStyle) -> @view.View {
  v.box(fn(w) {
    w.words_runs(By(runs)).words_look(By(fn() { @ui.style_words(style) })).ink(By(fn() { @ui.style_ink(style) })) |> ignore
    if @ui.style_fills(style) && !@ui.style_words(style).wrap {
      // (one line, cut short where it has not the room: ask_command's)
      w.allow_ellipsis(Is(true)) |> ignore
    }
  })
}

///|
/// What is asked in `v` (vault_asked's, as nodes), as `ask()` says it now: its title, the agent's reason, the command
/// (one line of it; `full_command`: all of it, a history's), how it is given, and only what is out of the ordinary.
fn vault_asked_node(v : @view.View, ask : () -> Asked, full_command : Bool) -> Unit {
  v.box(fn(w) {
    @sf.style_node(w, fn() { @sf.ask_what })
    vault_runs_node(w, fn() { vault_title_runs(ask()) }, @sf.ask_title) |> ignore
    w.show(fn() { ask().reason != "" }, fn(s) { @sf.words_node(s, fn() { ask().reason }, fn() { @sf.ask_note }) |> ignore })
    w.show(fn() { ask().command != "" }, fn(s) {
      vault_runs_node(s, fn() { [@ui.span(ask().command, mono=true)] }, if full_command { @sf.ask_note } else { ask_command })
      |> ignore
    })
    // (one to rename: what changes, a part each, in place of how it is given)
    w.show(fn() { ask().renames() }, fn(s) {
      s.box(fn(p) {
        @sf.style_node(p, fn() { ask_describe_part })
        @sf.words_node(p, fn() { tr("android-settings.vault.ask.describe.nameLabel") }, fn() { @sf.ask_note }) |> ignore
        vault_runs_node(p, fn() { describe_name_lines(ask())[0] }, ask_describe_words) |> ignore
        vault_runs_node(p, fn() { describe_name_lines(ask())[1] }, ask_describe_words) |> ignore
      })
      |> ignore
    })
    w.show(fn() { ask().reabouts() }, fn(s) {
      s.box(fn(p) {
        @sf.style_node(p, fn() { ask_describe_part })
        @sf.words_node(p, fn() { tr("android-settings.vault.ask.describe.aboutLabel") }, fn() { @sf.ask_note }) |> ignore
        // (as it was where it said one, then as it would be)
        p.show(fn() { ask().was_about != "" }, fn(w) { vault_runs_node(w, fn() { describe_about_lines(ask())[0] }, ask_describe_words) |> ignore })
        vault_runs_node(p, fn() { describe_about_lines(ask()).last().unwrap_or([]) }, ask_describe_words) |> ignore
      })
      |> ignore
    })
    w.show(fn() { ask().how_text != "" && !ask().describe && !ask().remove }, fn(s) {
      @sf.words_node(s, fn() { ask().how_text }, fn() { @sf.ask_note }) |> ignore
    })
    w.show(fn() { vault_odd_runs(ask()).length() > 0 }, fn(s) {
      vault_runs_node(s, fn() { vault_odd_runs(ask()) }, @sf.ask_note) |> ignore
    })
  })
  |> ignore
}

///|
/// Request `request()` in workspace `ws()` as its card in `v` (vault_card's, as nodes), as its message says it now:
/// what is asked, and its answer at its foot as the card says it (`answer()`: card_answer), answered in place once
/// `ended()` says how it went (status, scope).
pub fn vault_card_node(
  v : @view.View,
  core : Core,
  ws : () -> String,
  request : () -> String,
  ask : () -> Asked,
  answer : () -> Answer,
  ended : () -> (String, String)?,
) -> Unit {
  @sf.ask_card_node(v, fn(k) {
    vault_asked_node(k, ask, false)
    answered_in_place_node(
      k,
      fn() { ended().map(fn(e) { (e.0 == "granted", vault_outcome_words(ask(), e.0, e.1)) }) },
      fn(a) {
        vault_foot_node(
          a,
          core,
          ws,
          request,
          fn() { Some(answer()) },
          fn() { ask().writes() },
          fn() { ask().typed_in() },
          fn() { (ask().timeout_kind, ask().timeout_seconds) },
          foot=true,
          describe=fn() { ask().describe },
          remove=fn() { ask().remove },
        )
      },
    )
  })
  |> ignore
}

///|
/// What is asked as its card alone in `v`, no answer at its foot (vault_ask_words', as nodes: where nothing is
/// answered).
pub fn vault_ask_words_node(v : @view.View, ask : () -> Asked) -> Unit {
  @sf.ask_card_node(v, fn(k) { vault_asked_node(k, ask, false) }) |> ignore
}

///|
/// What was asked without its card or its answer in `v` (vault_ask_details', as nodes: a history's), the command all of
/// it.
pub fn vault_ask_details_node(v : @view.View, ask : () -> Asked) -> Unit {
  vault_asked_node(v, ask, true)
}

///|
/// How a request ended in `v` (vault_outcome's, as nodes), as `status()` (granted, denied, else expired) and `scope()`
/// say it now: a dot (green once granted) and its words. `inline`, `history`: ask_outcome_node's.
pub fn vault_outcome_node(
  v : @view.View,
  ask : () -> Asked,
  status : () -> String,
  scope : () -> String,
  inline : () -> Bool,
  history? : ((@view.View) -> Unit)? = None,
) -> Unit {
  ask_outcome_node(v, fn() { status() == "granted" }, fn() { vault_outcome_words(ask(), status(), scope()) }, inline, history~)
}
