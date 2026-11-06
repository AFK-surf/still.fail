// An agent's asks as cards (vault_ask.mbt's vault_card, phone_ask.mbt's phone_card) as nodes of the window's tree, made
// once: what is asked, its answer at its foot (its buttons, what is typed in for it, how long it is allowed), answered
// where it shows how it went in its answer's place; and a line saying how one ended. What a card keeps between its
// answers (the length picked, the answer under way, what is typed) the same maps the old views keep, by request.

///|
/// Told as what a card keeps that is not a signal changes (vault_picked, vault_timeout_minutes, vault_menu): what reads
/// them follows.
let vault_told : @signals.Signal[Int] = @signals.signal(0)

///|
fn vault_tell() -> Unit {
  vault_told.set(@signals.untracked(fn() { vault_told.get() }) + 1)
}

///|
/// A card's answer at its foot (answered_in_place's) in `parent`, `answer` making it: answered while it shows (`ended`:
/// whether it was granted, and how it went in words), its answer fades out where it is (answered_fade_ms, Leave),
/// laid out still (the card keeps its size), then how it went fades in after it over the room it leaves, its dot and its
/// words in the middle of it. Answered as it is made: how it went at once.
pub fn answered_in_place_node(
  parent : @view.View,
  ended : () -> (Bool, Array[@ui.Run])?,
  answer : (@view.View) -> Unit,
) -> Unit {
  let first = @signals.untracked(ended) is Some(_)
  let was = @motion.Way::new(if first { 0.0 } else { 1.0 })
  let now = @motion.Way::new(if first { 1.0 } else { 0.0 })
  parent.reacts(fn() { ended() is Some(_) }, fn(done) {
    let at = parent.cause_at()
    if done {
      was.go(0.0, @motion.tween(answered_fade_ms, ease=Leave), at~)
      now.go(1.0, @motion.tween(answered_fade_ms, ease=Out, delay=answered_fade_ms), at~)
    } else {
      was.put(1.0)
      now.put(0.0)
    }
  })
  parent.box(fn(whole) {
    whole.box(fn(a) {
      a.gap(Is(14.0)).alpha(By(fn() { shown_of(was, a) })).presses(By(fn() { ended() is None })) |> ignore
      answer(a)
    })
    |> ignore
    whole.show(fn() { ended() is Some(_) }, fn(o) {
      o
      .over(Is(true))
      .row(Is(true))
      .gap(Is(8.0))
      .lines_up(Is(Some(Middle)))
      .alpha(By(fn() { shown_of(now, o) }))
      |> ignore
      ask_dot_node(o, fn() { ended().map(fn(e) { e.0 }).unwrap_or(false) })
      o.box(fn(w) {
        w
        .words_runs(By(fn() { ended().map(fn(e) { e.1 }).unwrap_or([]) }))
        .words_look(By(fn() { @ui.style_words(ask_ended_words) }))
        .ink(By(fn() { @ui.style_ink(ask_ended_words) }))
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// Where way `w` is as `v` is drawn: at the moment it is drawn at while it goes, where it went once there.
fn shown_of(w : @motion.Way, v : @view.View) -> Double {
  w.said()
  if w.goes_at(v.logic_at()) {
    w.value_at(v.drawn_at())
  } else {
    w.target()
  }
}

///|
/// A request's dot (ask_dot's), 6 round: green once `granted`, else quiet.
fn ask_dot_node(parent : @view.View, granted : () -> Bool) -> Unit {
  parent.box(fn(d) {
    d
    .width(Is(Some(6.0)))
    .height(Is(Some(6.0)))
    .radius(Is(3.0))
    .ground(By(fn() { @ui.tree_theme().color(if granted() { Positive } else { Subtle }) }))
    |> ignore
  })
  |> ignore
}

///|
/// A request's outcome line (ask_outcome's) in `parent`: a dot (green once `granted`) in the middle of the words' first
/// line and its words; `inline` by the message's picture (the words where the name is, the dot under the picture), else
/// out in the margin. `history`: pressed, its card as it was (told where it is in the window).
pub fn ask_outcome_node(
  parent : @view.View,
  granted : () -> Bool,
  words : () -> Array[@ui.Run],
  inline : () -> Bool,
  history? : ((@sf.Anchor) -> Unit)? = None,
) -> Unit {
  // (as the words are measured: again as the system's size of words changes)
  let line = fn() {
    parent.words_redone() |> ignore
    @ui.words_line_px(@ui.style_words(ask_ended_words))
  }
  parent.box(fn(e) {
    e.padding(Is((0.0, 2.0, 0.0, 0.0))) |> ignore
    e.box(fn(at) {
      at.padding(By(fn() { (if inline() { 25.0 } else { 0.0 }, 0.0, 0.0, 0.0) })).lines_up(Is(Some(Start))) |> ignore
      match history {
        Some(open) =>
          at.box(fn(h) {
            let lit = @motion.Way::new(0.0)
            h.reacts(fn() { h.pointed() || h.focused() }, fn(on) {
              lit.go(if on { 1.0 } else { 0.0 }, @motion.tween(@sf.dur_ms, ease=Out), at=h.cause_at())
            })
            h
            .row(Is(true))
            .gap(Is(4.0))
            .lines_up(Is(Some(Start)))
            .says(By(fn() { Some(@view.said(Button, label=words().map(fn(r) { r.text }).join("") + " · " + @sf.t("web-main.history.details"))) }))
            |> ignore
            // (beside where it is on screen as it is pressed)
            @sf.presses_node(h, fn() {
              match h.shown_rect() {
                Some((x, y, w, ht)) => open(At(x, y, w, ht))
                None => open(Unanchored)
              }
            })
            h.box(fn(w) {
              w.words_runs(By(words)).words_look(By(fn() { @ui.style_words(ask_ended_words) })).ink(By(fn() { @ui.style_ink(ask_ended_words) })) |> ignore
            })
            |> ignore
            h.box(fn(m) {
              m.height(By(fn() { Some(line()) })).lies_along(Is(Middle)) |> ignore
              @sf.icon_node(m, "chevron-right", 12.0, By(fn() {
                let t = @sf.theme()
                @sf.mix(t.p.text, shown_of(lit, m), t.p.muted)
              }))
              |> ignore
            })
            |> ignore
          })
          |> ignore
        None =>
          at.box(fn(w) {
            w.words_runs(By(words)).words_look(By(fn() { @ui.style_words(ask_ended_words) })).ink(By(fn() { @ui.style_ink(ask_ended_words) })) |> ignore
          })
          |> ignore
      }
    })
    |> ignore
    // (the dot in the middle of the words' first line, under the message's picture or out in the margin)
    e.box(fn(d) {
      d
      .over(Is(true))
      .row(Is(true))
      .width(Is(Some(18.0)))
      .height(By(fn() { Some(line()) }))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      .offset(By(fn() { (if inline() { 0.0 } else { -@sf.message_avatar_reach }, 2.0) }))
      |> ignore
      ask_dot_node(d, granted)
    })
    |> ignore
  })
  |> ignore
}

///|
/// A request to debug its person's phone as a card (phone_card's) in `parent`: what is asked and the agent's reason,
/// and its answer where it is the viewer's (`mine`) and a core is there (phone_foot_node), else whose it is.
pub fn phone_card_node(
  parent : @view.View,
  core : Core?,
  station : String,
  request : String,
  reason : () -> String,
  mine : Bool,
  lasts : () -> String,
  who : String?,
  ended : () -> (String, String, String)?,
  how : () -> Unit,
  chat? : String = "",
) -> Unit {
  @sf.card_node(parent, fn(k) {
    @sf.ask_words_node(k, fn() { tr("android-misc.adb.ask.chat.title") }, reason) |> ignore
    match core {
      Some(core) if mine =>
        answered_in_place_node(k, fn() {
          ended().map(fn(e) { (e.0 == "granted", [@ui.span(phone_outcome_words(e.0, e.1, e.2))]) })
        }, fn(a) { phone_foot_node(a, core, station, request, lasts, how, chat) })
      _ =>
        match who {
          Some(w) if w != "" => @sf.words_node(k, fn() { w }, fn() { @sf.ask_note }) |> ignore
          _ => ()
        }
    }
  })
  |> ignore
}

///|
/// A phone request's answer (phone_foot's) in `parent`: 允许 (for the length chosen), 拒绝, and the length's menu; on a
/// phone that lacks something first, what, and 查看步骤 (`how`) in 允许's place.
fn phone_foot_node(parent : @view.View, core : Core, station : String, request : String, lasts : () -> String, how : () -> Unit, chat : String) -> Unit {
  let key = "phone/" + request
  parent.reacts(fn() { () }, fn(_) { adb_phone_ask() })
  let lacks = fn() {
    let row = phone_row(core, request)
    if flag(row, "oldStation") {
      Some(tr("android-misc.personal.updateStation"))
    } else if flag(row, "join") {
      Some(tr("android-misc.personal.open"))
    } else { match adb_ready_now() {
      AdbLacks(step) => Some(step)
      // (a phone whose 共享调试 is off lends to no chat: turned on first, on its page)
      AdbLends if !flag((core.topic)("adbShare", Map([])).value, "on") => Some(tr("android-misc.adb.step.on"))
      _ => None
    } }
  }
  let scopes = fn() { if lasts() == "hour" { ["hour"] } else { ["hour", "chat"] } }
  let scope = fn() {
    vault_told.get() |> ignore
    let all = scopes()
    match vault_picked.get(key) {
      Some(s) if all.contains(s) => s
      _ => all[all.length() - 1]
    }
  }
  let on = [("station", station), ("request", request)]
  let pending = fn() { vault_pending.get(key) }
  let under = fn() { pending() is Some(_) || is_doing(core, ["adb.decide"], on) }
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending[key] = yes
    // (Wireless debugging the app may turn on itself: on as it is allowed, as a lending from the page does)
    if yes {
      adb_switch_on()
    }
    let params : Array[(String, Json)] = [("station", str(station)), ("request", str(request))]
    if yes {
      params.push(("scope", str(@signals.untracked(scope))))
      if chat != "" { params.push(("chat", str(chat))) }
    }
    (core.call)("adb.decide", obj(params), fn(r) {
      match r {
        Err(e) => {
          vault_pending.remove(key) |> ignore
          let what = tr(if yes { "android-settings.vault.act.allowWhat" } else { "android-settings.vault.act.denyWhat" })
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  }
  parent.show(fn() { lacks() is Some(_) }, fn(n) {
    @sf.words_node(n, fn() { fill("android-misc.adb.ask.first", [("step", lacks().unwrap_or(""))]) }, fn() { @sf.ask_note }) |> ignore
  })
  @sf.ask_buttons_node(parent, fn(b) {
    b.pick(fn() { lacks() is Some(_) }, fn(first, lacking) {
      if lacking {
        @sf.button_node(first, fn() {
          tr(if flag(phone_row(core, request), "join") { "android-misc.personal.open" } else { "android-misc.adb.ask.how" })
        }, how, tone=Primary, at_foot=true) |> ignore
      } else {
        @sf.button_node(first, fn() { tr("android-settings.vault.act.allow") }, fn() { decide(true) }, tone=Primary, busy=fn() {
          pending() == Some(true)
        }, disabled=under, at_foot=true)
        |> ignore
      }
    })
    @sf.button_node(b, fn() { tr("android-settings.vault.act.deny") }, fn() { decide(false) }, tone=Ghost, busy=fn() {
      pending() == Some(false)
    }, disabled=under, at_foot=true)
    |> ignore
    // (nothing to allow yet: no length to choose)
    b.show(fn() { scopes().length() >= 2 && lacks() is None }, fn(c) {
      @sf.chooser_node(c, fn() { tr("android-settings.vault.scope." + scope()) }, fn() {
        scopes().map(fn(s) {
          Some(@sf.menu_item_of(tr("android-settings.vault.scope." + s), fn() {
            vault_picked[key] = s
            vault_menu.val = ""
            vault_tell()
          }, chosen=s == scope()))
        })
      }, fn() {
        vault_told.get() |> ignore
        vault_menu.val == key
      }, fn(open) {
        vault_menu_set(key, open)
        vault_tell()
      }, at_foot=true)
      |> ignore
    })
  })
  |> ignore
}

///|
/// A request about a vault item as a card (vault_card's) in `parent`: what is asked, and its answer at its foot
/// (vault_foot_node) where it is answered here; answered while it shows (`ended`: its status and scope), how it went in
/// its answer's place.
pub fn vault_card_node(
  parent : @view.View,
  core : Core,
  ws : String,
  request : String,
  ask : () -> Asked,
  answer : () -> Answer,
  ended : () -> (String, String)?,
) -> Unit {
  @sf.card_node(parent, fill=@signals.untracked(ask).picks_file(), fn(k) {
    vault_asked_node(k, ask)
    answered_in_place_node(k, fn() {
      ended().map(fn(e) { (e.0 == "granted", vault_outcome_words(ask(), e.0, e.1)) })
    }, fn(a) {
      let now = @signals.untracked(ask)
      vault_foot_node(a, core, ws, request, answer, now.save_kind != "", typed=now.typed_in(), timeout_kind=now.timeout_kind, timeout_seconds=now.timeout_seconds, foot=@signals.untracked(answer) is (Approve(_) | SetUp))
    })
  })
  |> ignore
}

///|
/// What is asked (vault_asked's) in `parent`: its title (使用 …, 存入密码 … and the account; the item's name in it
/// heavier), the reason, the command (one line), how it is given, and only what is out of the ordinary: a command that
/// reads the secret itself, one run on another station. `full_command`: all of the command.
pub fn vault_asked_node(parent : @view.View, ask : () -> Asked, full_command? : Bool = false) -> Unit {
  parent.box(fn(w) {
    w.gap(Is(2.0)) |> ignore
    let save = fn() { ask().save_kind != "" }
    w.box(fn(t) {
      t
      .words_runs(By(fn() {
        let a = ask()
        let ink = @sf.theme().p.text
        let named = fn(n) { @ui.span(n, weight=600, color=ink) }
        let words = fn(x) { @ui.span(x, weight=400, color=ink) }
        let runs = if save() {
          fill_named(
            "android-settings.vault.ask.save",
            [("kind", tr("android-settings.vault.ask.kind." + a.save_kind)), ("name", a.name)],
            named,
            words,
          )
        } else {
          fill_named("android-settings.vault.ask.use", [("name", a.name)], named, words)
        }
        let sub = if a.username != "" { a.username } else { a.filename }
        if save() && sub != "" {
          runs.push(@ui.span("  " + sub, color=@sf.theme().p.muted))
        }
        runs
      }))
      .words_look(By(fn() { @ui.style_words(@sf.ask_title) }))
      .ink(By(fn() { @ui.style_ink(@sf.ask_title) }))
      |> ignore
    })
    |> ignore
    w.show(fn() { ask().reason != "" }, fn(r) { @sf.words_node(r, fn() { ask().reason }, fn() { @sf.ask_note }) |> ignore })
    w.show(fn() { ask().command != "" }, fn(cmd) {
      cmd
      .words_runs(By(fn() { [@ui.span(ask().command, mono=true)] }))
      .words_look(By(fn() { @ui.style_words(if full_command { @sf.ask_note } else { ask_command }) }))
      .ink(By(fn() { @ui.style_ink(@sf.ask_note) }))
      |> ignore
    })
    w.show(fn() { ask().how_text != "" }, fn(h) { @sf.words_node(h, fn() { ask().how_text }, fn() { @sf.ask_note }) |> ignore })
    let risky = fn() { !save() && (ask().mode == "env" || ask().mode == "file") }
    let elsewhere = fn() { ask().station != "" }
    w.show(fn() { risky() || elsewhere() }, fn(o) {
      o
      .words_runs(By(fn() {
        let runs : Array[@ui.Run] = []
        if risky() {
          runs.push(@ui.span(tr("android-settings.vault.ask.plain"), color=@sf.theme().p.warn_ink))
        }
        if risky() && elsewhere() {
          runs.push(@ui.span(" · "))
        }
        if elsewhere() {
          runs.push(@ui.span(fill("android-settings.vault.ask.on", [("station", ask().station)])))
        }
        runs
      }))
      .words_look(By(fn() { @ui.style_words(@sf.ask_note) }))
      .ink(By(fn() { @ui.style_ink(@sf.ask_note) }))
      |> ignore
    })
  })
  |> ignore
}

///|
/// The answer to request `request` in workspace `ws` as `answer` says (vault_foot's) in `parent`: a line where there is
/// no answer to give here; else what the person types in for it over the buttons (`typed`), 允许 / 存入 and 拒绝 / 不存,
/// how long a use is allowed (a menu, or for a timed one a panel of its own), on a line of its own over the buttons
/// where they have not the room beside it. Pressed, the button turns till what it did shows.
pub fn vault_foot_node(
  parent : @view.View,
  core : Core,
  ws : String,
  request : String,
  answer : () -> Answer,
  save : Bool,
  typed? : Typed? = None,
  timeout_kind? : String = "",
  timeout_seconds? : Int = 0,
  foot? : Bool = false,
) -> Unit {
  ignore(foot)
  parent.pick(fn() {
    match answer() {
      Elsewhere => 1
      NotHere => 2
      Decided => 3
      Theirs(_) => 4
      SetUp => 5
      Approve(_) => 0
    }
  }, fn(f, which) {
    let note = fn(words : () -> String) { @sf.words_node(f, words, fn() { @sf.ask_note }) |> ignore }
    match which {
      1 => note(fn() { tr("android-settings.vault.approve.inApp") })
      2 => note(fn() { tr("web-pages.vault.approve.notHere") })
      3 => note(fn() { tr("android-settings.vault.approve.decided") })
      4 =>
        note(fn() {
          match answer() {
            Theirs(w) => w
            _ => ""
          }
        })
      5 =>
        @sf.ask_buttons_node(f, fn(b) {
          // kept only in a vault that is on here: the way to turn it on first
          @sf.button_node(b, fn() { tr("android-settings.vault.turnOn") }, fn() { (core.push)(Route::Vault) }, tone=Primary, at_foot=true) |> ignore
        })
        |> ignore
      _ => vault_answer_node(f, core, ws, request, answer, save, typed, timeout_kind, timeout_seconds)
    }
  })
}

///|
/// The answer to a vault request the viewer gives (vault_foot's Approve), in `f`.
fn vault_answer_node(
  f : @view.View,
  core : Core,
  ws : String,
  request : String,
  answer : () -> Answer,
  save : Bool,
  typed : Typed?,
  timeout_kind : String,
  timeout_seconds : Int,
) -> Unit {
  f.gap(Is(8.0)) |> ignore
  let lasts = fn() {
    match answer() {
      Approve(l) => l
      _ => ""
    }
  }
  let timed = !save && timeout_seconds > 0
  let scopes = fn() {
    if save {
      ["once"]
    } else if timed {
      if lasts() == "once" { ["once"] } else { ["once", "idle", "fixed"] }
    } else {
      vault_scopes_up_to(lasts())
    }
  }
  let scope = fn() {
    vault_told.get() |> ignore
    let all = scopes()
    match vault_picked.get(request) {
      Some(s) if all.contains(s) => s
      _ => if timed && all.contains(timeout_kind) { timeout_kind } else { all[all.length() - 1] }
    }
  }
  let on = [("workspace", ws), ("request", request)]
  let pending = fn() { vault_pending.get(request) }
  let busy = fn(yes : Bool) { pending() == Some(yes) || is_doing(core, [if yes { "vault.approve" } else { "vault.deny" }], on) }
  let under = fn() { pending() is Some(_) || is_doing(core, ["vault.approve", "vault.deny"], on) }
  let max_minutes = fn() { if lasts() == "hour" { 60 } else { 43200 } }
  let minutes = fn() {
    vault_told.get() |> ignore
    let asked = (timeout_seconds + 59) / 60
    let most = max_minutes()
    vault_timeout_minutes.get(request).unwrap_or(if asked < most { asked } else { most })
  }
  let valid_time = fn() { !timed || scope() == "once" || (minutes() > 0 && minutes() <= max_minutes()) }
  // (what the person types in: as it is, followed)
  let secret_field = typed_field(request, "/secret")
  let username_field = typed_field(request, "/username")
  let secret = fn() {
    match typed {
      Some({ kind: "file", .. }) => vault_files.get(request).map(fn(x) { x.0 }).unwrap_or("")
      Some(_) => secret_field.text()
      None => ""
    }
  }
  let empty = fn() { typed is Some(_) && secret().trim(chars=" \n\t").to_string() == "" }
  let act = fn(yes : Bool, call : String, what : String, params : Json) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending[request] = yes
    (core.call)(call, params, fn(r) {
      // (gone through, it stays turning till what it did shows; what was typed in for it let go)
      match r {
        Err(e) => {
          vault_pending.remove(request) |> ignore
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => {
          vault_typed.remove(request + "/secret") |> ignore
          vault_typed.remove(request + "/username") |> ignore
          vault_files.remove(request) |> ignore
        }
      }
    })
  }
  let approve = fn() {
    if @signals.untracked(fn() { under() || empty() || !valid_time() }) {
      return
    }
    let what = tr(if save { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" })
    let s = @signals.untracked(scope)
    let n = @signals.untracked(minutes)
    let chosen_scope = if !timed || s == "once" { if save { "once" } else { s } } else if n <= 60 { "hour" } else { "chat" }
    let params : Array[(String, Json)] = [("workspace", str(ws)), ("request", str(request)), ("scope", str(chosen_scope))]
    if timed && s != "once" {
      params.push(("timeout", obj([("kind", str(s)), ("seconds", Json::number((n * 60).to_double()))])))
    }
    match typed {
      Some(ty) => {
        let words : Array[(String, Json)] = [("secret", str(@signals.untracked(secret)))]
        let user = username_field.text().trim(chars=" ").to_string()
        if ty.kind == "login" && ty.username == "" && user != "" {
          words.push(("username", str(user)))
        }
        match vault_files.get(request) {
          Some((_, name)) if ty.kind == "file" => words.push(("filename", str(name)))
          _ => ()
        }
        params.push(("typed", obj(words)))
      }
      None => ()
    }
    act(true, "vault.approve", what, obj(params))
  }
  // a secret the person types in: its field over the buttons (a login's account first, where the agent named none)
  match typed {
    Some(ty) =>
      @sf.over_foot_node(f, fn(t) {
        if ty.kind == "login" && ty.username == "" {
          @sf.input_node(t, username_field, placeholder=tr("android-settings.vault.ask.typed.username"), disabled=under, at_foot=true) |> ignore
        }
        let words = tr("android-settings.vault.ask.typed." + ty.kind)
        if ty.kind == "file" {
          t.box(fn(r) {
            r.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
            @sf.button_node(r, fn() { words }, fn() {
              match @ui.pick(Files) {
                Some(p) => {
                  vault_file_picks[request] = p
                  vault_tell()
                }
                None => ()
              }
            }, disabled=under, at_foot=true)
            |> ignore
            // (the system's picker answered: the file it gave, beside the button)
            r.reacts(fn() {
              vault_told.get() |> ignore
              r.drawn_at() |> ignore
              vault_file_picks.get(request) is Some(_)
            }, fn(_) {
              match vault_file_picks.get(request) {
                Some(p) =>
                  if take_picked_file(core, p, fn(content, name) { vault_files[request] = (content, name) }) {
                    vault_file_picks.remove(request) |> ignore
                    vault_tell()
                  }
                None => ()
              }
            })
            r.show(fn() { vault_files.get(request) is Some(_) }, fn(n) {
              n
              .words(By(fn() {
                match vault_files.get(request) {
                  Some((content, name)) => name + " · " + file_size(content)
                  None => ""
                }
              }))
              .words_look(By(fn() { @ui.style_words(ask_file_name) }))
              .ink(By(fn() { @ui.style_ink(ask_file_name) }))
              |> ignore
            })
          })
          |> ignore
        } else if ty.kind == "ssh_key" {
          @sf.textarea_node(t, secret_field, rows=4, placeholder=words, at_foot=true) |> ignore
        } else {
          @sf.input_node(t, secret_field, placeholder=words, secret=true, disabled=under, submitted=fn(_) { approve() }, at_foot=true) |> ignore
        }
      })
      |> ignore
    None => ()
  }
  // how long a use is allowed: a menu of its lengths, or for a timed one a panel of its own (vault_timeout_open)
  let picks = !save
  let pick = fn(p : @view.View) {
    p.show(fn() { picks && scopes().length() > 1 }, fn(c) {
      if timed {
        @sf.chooser_node(c, fn() {
          let s = scope()
          if s == "once" {
            tr("android-settings.vault.scope.once")
          } else {
            let n = minutes()
            let days = n % 1440 == 0
            let hours = n % 60 == 0
            let duration = fill(if days { "android-settings.vault.timeout.nDays" } else if hours { "android-settings.vault.timeout.nHours" } else { "android-settings.vault.timeout.nMinutes" }, [("n", (if days { n / 1440 } else if hours { n / 60 } else { n }).to_string())])
            fill("android-settings.vault.timeout.button." + s, [("time", duration)])
          }
        }, fn() { [] }, fn() { false }, fn(open) {
          if open {
            vault_timeout_open(request, @signals.untracked(minutes), @signals.untracked(scope), @signals.untracked(max_minutes))
          }
        }, disabled=under)
        |> ignore
      } else {
        @sf.chooser_node(c, fn() { tr("android-settings.vault.scope." + scope()) }, fn() {
          scopes().map(fn(s) {
            Some(@sf.menu_item_of(tr("android-settings.vault.scope." + s), fn() {
              vault_picked[request] = s
              vault_menu.val = ""
              vault_tell()
            }, chosen=s == scope()))
          })
        }, fn() {
          vault_told.get() |> ignore
          vault_menu.val == request
        }, fn(open) {
          vault_menu_set(request, open)
          vault_tell()
        })
        |> ignore
      }
    })
  }
  @sf.ask_buttons_node(f, fn(b) {
    let yes = if save { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }
    @sf.button_node(b, fn() { tr(yes) }, approve, tone=Primary, busy=fn() { busy(true) }, disabled=fn() {
      under() || empty() || !valid_time()
    }, at_foot=true)
    |> ignore
    let no = if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }
    @sf.button_node(b, fn() { tr(no) }, fn() {
      act(false, "vault.deny", tr("android-settings.vault.act.denyWhat"), obj([("workspace", str(ws)), ("request", str(request))]))
    }, tone=Ghost, busy=fn() { busy(false) }, disabled=under, at_foot=true)
    |> ignore
    pick(b)
  })
  |> ignore
}

///|
/// The answer to request `request` in workspace `ws` from the vaults topic (vault_actions'), in `parent`: the buttons
/// while it waits on the viewer (`mine`), or a line where there is no answer to give here (`who`: whose it is);
/// nothing while the topic has not come. Made again as whether it keeps a secret, and how it is typed, changes.
pub fn vault_actions_node(parent : @view.View, core : Core, ws : String, request : String, mine : () -> Bool, who? : String? = None) -> Unit {
  let answered = fn() { topic_answer(core, ws, request, mine(), who) }
  let row = fn() { items(vaults_of(core, ws), "requests").iter().find_first(fn(r) { text(Some(r), "id") == request }) }
  parent.pick(fn() {
    match answered() {
      Some((_, save, typed)) => Some((save, typed.map(fn(t) { t.kind + "\n" + t.username })))
      None => None
    }
  }, fn(f, kind) {
    guard kind is Some(_) else { return }
    let (_, save, typed) = @signals.untracked(answered).unwrap()
    let r = @signals.untracked(row)
    vault_foot_node(
      f,
      core,
      ws,
      request,
      fn() { answered().map(fn(a) { a.0 }).unwrap_or(Decided) },
      save,
      typed~,
      timeout_kind=text(r, "timeoutKind"),
      timeout_seconds=count(r, "timeoutSeconds"),
    )
  })
}

///|
/// Whether this device lends its own adb (phone_lends'), as its host says it now, followed: for a node of the window's
/// tree.
pub fn phone_lends_now() -> Bool {
  match adb_ready_now() {
    AdbLends | AdbLacks(_) => true
    _ => false
  }
}
