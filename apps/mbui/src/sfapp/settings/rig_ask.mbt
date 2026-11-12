// An agent's request for a rig of the workspace as a card (a station that only runs tasks, 2026-11-10; as a phone's request is): which rig
// in its title, the agent's reason under it, and at its foot 允许 as the one solid button, 拒绝 beside it, and for
// how long a choice beside them that starts at what the agent asked (`rig.decide` on the chat's station). Only the
// rig's person answers it (the card's assignee); elsewhere a line says whose it is. What they allow is signed with a
// key on their own lock: a device not on it is sent there first, a web page says where to answer instead. Decided, a
// line says how it went. What it keeps between frames is the vault card's, keyed `rig/<id>`.

///|
/// The request's card while it waits: its words, and its answer where it is the viewer's (`mine`) and a core is there.
/// `ask`: what the card said of the chat (`rig.decide`'s `ask`: the rig, the session, the thread, its title, who
/// started it). `lock`: the person's own lock's page opened.
pub fn rig_card(
  c : @ui.Ctx,
  core : Core?,
  station : String,
  request : String,
  name : String,
  reason : String,
  timeout : (String, Int),
  ask : Json,
  mine : Bool,
  who? : String? = None,
  ended? : (Bool, String)? = None,
  lock? : () -> Unit = fn() {  },
  device? : String = "",
) -> Unit {
  @sf.card(c, fn() {
    // (one of its devices alone: named, with the station it is on)
    let title = if device == "" {
      fill("web-pages.rigs.ask.title", [("name", name)])
    } else {
      fill("web-pages.devices.ask.title", [("device", device), ("name", name)])
    }
    @sf.ask_words(c, title, reason)
    match core {
      Some(core) if mine =>
        answered_in_place(c, "rig/" + request, ended.map(fn(e) { (e.0, [@ui.span(e.1)]) }), fn() {
          rig_foot(c, core, station, request, timeout, ask, lock)
        })
      _ =>
        match who {
          Some(w) if w != "" => c.text(w, style=@sf.ask_note) |> ignore
          _ => ()
        }
    }
  })
  |> ignore
}

///|
/// A length of time in words: 45 分钟, 2 小时, 7 天 (the vault's).
fn rig_time_words(seconds : Int) -> String {
  let minutes = (seconds + 59) / 60
  let days = minutes % 1440 == 0
  let hours = minutes % 60 == 0
  fill(
    if days { "android-settings.vault.timeout.nDays" } else if hours { "android-settings.vault.timeout.nHours" } else { "android-settings.vault.timeout.nMinutes" },
    [("n", (if days { minutes / 1440 } else if hours { minutes / 60 } else { minutes }).to_string())],
  )
}

///|
/// A timeout in words: 闲置 1 小时后失效, 2 小时后失效 (the vault's).
pub fn rig_timeout_words(kind : String, seconds : Int) -> String {
  fill("android-settings.vault.timeout.button." + (if kind == "fixed" { "fixed" } else { "idle" }), [("time", rig_time_words(seconds))])
}

///|
/// A timeout as its choice on the card says it, short enough to stand beside 允许 and 拒绝 on a phone (the long
/// words took a line of their own, the choice in the card's corner off its curve): 闲置 1 小时, 固定 8 小时.
fn rig_timeout_short(kind : String, seconds : Int) -> String {
  fill("web-pages.rigs.ask.time." + (if kind == "fixed" { "fixed" } else { "idle" }), [("time", rig_time_words(seconds))])
}

///|
/// The times a grant is offered for: what the agent asked first, then an hour idle, and an hour, eight, a day and a
/// week fixed.
fn rig_timeouts(asked : (String, Int)) -> Array[(String, Int)] {
  let out = [asked]
  for t in [("idle", 3600), ("fixed", 3600), ("fixed", 28800), ("fixed", 86400), ("fixed", 604800)] {
    if !out.contains(t) {
      out.push(t)
    }
  }
  out
}

///|
/// Its answer: 允许 (for the time chosen), 拒绝, and the time's menu; on a device that does not sign as its person
/// (a web page, one not on their own lock), what first, and the way there in 允许's place.
fn rig_foot(
  c : @ui.Ctx,
  core : Core,
  station : String,
  request : String,
  asked : (String, Int),
  ask : Json,
  lock : () -> Unit,
) -> Unit {
  let ws = match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
    None => ""
  }
  let rigs = (core.topic)("rigs", { "workspace": str(ws) }).get().value
  // (not read yet: as an app whose device its person's trusted devices approved, the commonest; allowed there, the
  // core says what is missing. This device not approved yet, or theirs set up again elsewhere: not allowed here until
  // it is, settings' 共享调试 a tap away, as a phone's request is: phone_ask.mbt)
  let lacks = if rigs is Some(_) && !flag(rigs, "app") {
    Some((tr("web-pages.rigs.ask.appOnly"), false))
  } else if rigs is Some(_) && (text(rigs, "personal") == "outside" || text(rigs, "personal") == "replaced") {
    Some((tr("android-misc.adb.lock.join"), true))
  } else {
    None
  }
  let times = rig_timeouts(if asked.1 > 0 { asked } else { ("idle", 3600) })
  let label = fn(t : (String, Int)) { t.0 + "/" + t.1.to_string() }
  let time = match vault_picked.get("rig/" + request) {
    Some(s) =>
      match times.iter().find_first(fn(t) { label(t) == s }) {
        Some(t) => t
        None => times[0]
      }
    None => times[0]
  }
  let on = [("station", station), ("request", request)]
  let pending = vault_pending.get("rig/" + request)
  let under = pending is Some(_) || is_doing(core, ["rig.decide"], on)
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending["rig/" + request] = yes
    let params : Array[(String, Json)] = [("station", str(station)), ("request", str(request)), ("allow", Json::boolean(yes)), ("ask", ask)]
    if yes {
      params.push(("timeoutKind", str(time.0)))
      params.push(("timeoutSeconds", Json::number(time.1.to_double())))
    }
    (core.call)("rig.decide", obj(params), fn(r) {
      match r {
        Err(e) => {
          vault_pending.remove("rig/" + request)
          let what = tr(if yes { "android-settings.vault.act.allowWhat" } else { "android-settings.vault.act.denyWhat" })
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  }
  match lacks {
    Some((step, _)) => c.text(step, style=@sf.ask_note) |> ignore
    None => ()
  }
  @sf.ask_buttons(c, fn() {
    match lacks {
      Some((_, true)) => @sf.button(c, tr("android-misc.adb.ask.how"), key="rig/" + request + "/lock", tone=Primary, on_press=lock)
      Some(_) => ()
      None =>
        @sf.button(c, tr("android-settings.vault.act.allow"), key="rig/" + request + "/yes", tone=Primary, busy=pending == Some(true), disabled=under, on_press=fn() {
          decide(true)
        })
    }
    @sf.button(c, tr("android-settings.vault.act.deny"), key="rig/" + request + "/no", tone=Ghost, busy=pending == Some(false), disabled=under, on_press=fn() {
      decide(false)
    })
    // (nothing to allow yet: no time to choose)
    if lacks is Some(_) {
      return
    }
    let entries = times.map(fn(t) { @kit.menu_radio(label(t), t == time, label=rig_timeout_words(t.0, t.1)) })
    let m = @sf.chooser(
      c,
      "rig/" + request + "/time",
      rig_timeout_short(time.0, time.1),
      entries,
      fn() { vault_menu.val == "rig/" + request },
      fn(on) { vault_menu_set("rig/" + request, on) },
    )
    match m.chosen {
      Some(s) => {
        vault_picked["rig/" + request] = s
        vault_menu.val = ""
      }
      None => ()
    }
  })
}

///|
/// How a request ended, in a line: a dot (green once the rig took the grant) and its words (rig_outcome_words).
pub fn rig_outcome(
  c : @ui.Ctx,
  status : String,
  why : String,
  delivered : Bool,
  granted : (String, Int),
  inline? : Bool = true,
  history? : (String, (Int) -> Unit)? = None,
) -> Unit {
  ask_outcome(c, status == "granted" && delivered, [@ui.span(rig_outcome_words(status, why, delivered, granted))], inline~, history~)
}

///|
/// How a request ended, in words: 已允许使用这台 station · 闲置 1 小时后失效; approved while the rig was away, that it
/// waits for it; 已拒绝使用这台 station; or why it ended (所有者已收回, 对话已归档, 授权已到期, 闲置超时).
pub fn rig_outcome_words(status : String, why : String, delivered : Bool, granted : (String, Int)) -> String {
  match status {
    "granted" if !delivered => tr("web-pages.rigs.ask.away")
    "granted" => fill("web-pages.rigs.ask.granted", [("how", rig_timeout_words(granted.0, granted.1))])
    "denied" if why == "" => tr("web-pages.rigs.ask.denied")
    _ => fill("web-pages.rigs.ask.ended", [("why", if why == "" { tr("web-pages.rigs.ask.denied") } else { why })])
  }
}
