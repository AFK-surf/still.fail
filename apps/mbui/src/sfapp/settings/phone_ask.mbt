// An agent's request to debug its person's phone as a card (2026-10-29: as a vault request's): what
// is asked in its title, the agent's reason under it, and at its foot 允许 as the one solid button, 拒绝 beside it, and
// how long it is allowed a choice beside them that starts at the longest (`adb.decide` on the chat's station). Only the
// viewer's own request is answered; elsewhere a line says whose it is. Decided, a line says how it went. What it
// keeps between frames (its menu, the length picked, the answer under way) is the vault card's, keyed `phone/<id>`.
// Allowed on the phone itself, its 共享调试 switch is turned on with it; what the phone still lacks is a card under the
// line once granted (decision.mbt), each step done from there (2026-11-11: it said 需要先… and 查看步骤 took 允许's
// place, a settings page away, and back again for pairing). Only what cannot be allowed here at all takes 允许 away:
// this device not approved yet (查看步骤: settings' 共享调试 is that step), a station from before signatures.

///|
/// The request's card while it waits: its words, and its answer where it is the viewer's (`mine`) and a core is there.
/// `how`: settings' 共享调试 opened, where this device is to be approved first.
pub fn phone_card(
  c : @ui.Ctx,
  core : Core?,
  station : String,
  request : String,
  reason : String,
  mine : Bool,
  lasts? : String = "chat",
  who? : String? = None,
  ended? : (String, String, String)? = None,
  how? : () -> Unit = fn() {  },
) -> Unit {
  // (a card of words, as a vault request's: its answer in its foot corners; answered while it shows, how it went in its
  // answer's place: answered_in_place)
  @sf.card(c, fn() {
    @sf.ask_words(c, tr("android-misc.adb.ask.chat.title"), reason)
    match core {
      Some(core) if mine =>
        answered_in_place(c, "phone/" + request, ended.map(fn(e) { (e.0 == "granted", [@ui.span(phone_outcome_words(e.0, e.1, e.2))]) }), fn() {
          phone_foot(c, core, station, request, lasts, how)
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
/// A request as the core has it (`adbShare`'s `grants`): whose it is, and what stands in its way.
fn phone_row(core : Core, request : String) -> Json? {
  items((core.topic)("adbShare", Map([])).get().value, "grants").iter().find_first(fn(g) { text(Some(g), "id") == request })
}

///|
/// Its answer: 允许 (for the length chosen), 拒绝, and the length's menu; where it cannot be allowed here yet, why, and
/// 查看步骤 (`how`) in 允许's place for a device to be approved.
fn phone_foot(c : @ui.Ctx, core : Core, station : String, request : String, lasts : String, how : () -> Unit) -> Unit {
  // (a device with no adb of its own, a computer's: the grant is for the person's phone, lent as it is ready)
  let row = phone_row(core, request)
  // (a station from before signatures: allowed, nothing would lend)
  let lacks = if flag(row, "oldStation") {
    Some(tr("android-misc.personal.updateStation"))
  } else if flag(row, "join") {
    // (this device not approved by the person's trusted devices, or theirs set up again elsewhere: not allowed here
    // until it is, settings' 共享调试 a tap away; with none yet, 允许 as anywhere: allowing begins them)
    Some(tr("android-misc.adb.ask.approve"))
  } else {
    None
  }
  // (on a phone whose 共享调试 is off: turned on as it is allowed, as its switch turns it on)
  let turn_on = phone_lends(c) && !flag((core.topic)("adbShare", Map([])).get().value, "on")
  // (every length, starting at an hour unused: a device's timeouts, 2026-11-10; a station from before offered an hour
  // alone where its owner's 默认最长授权 said so)
  let scopes = if lasts == "hour" { ["hour"] } else { ["hour", "idle", "eight", "chat"] }
  let scope = match vault_picked.get("phone/" + request) {
    Some(s) if scopes.contains(s) => s
    _ => if scopes.contains("idle") { "idle" } else { scopes[scopes.length() - 1] }
  }
  let on = [("station", station), ("request", request)]
  let pending = vault_pending.get("phone/" + request)
  let under = pending is Some(_) || is_doing(core, ["adb.decide"], on)
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending["phone/" + request] = yes
    // (Wireless debugging the app may turn on itself: on as it is allowed, as the switch turned on does)
    if yes && turn_on {
      adb_turn(core, true)
    } else if yes {
      adb_switch_on()
    }
    let params : Array[(String, Json)] = [("station", str(station)), ("request", str(request))]
    if yes {
      params.push(("scope", str(scope)))
    }
    (core.call)("adb.decide", obj(params), fn(r) {
      match r {
        Err(e) => {
          vault_pending.remove("phone/" + request)
          let what = tr(if yes { "android-settings.vault.act.allowWhat" } else { "android-settings.vault.act.denyWhat" })
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  }
  match lacks {
    Some(step) => c.text(fill("android-misc.adb.ask.first", [("step", step)]), style=@sf.ask_note) |> ignore
    None => ()
  }
  @sf.ask_buttons(c, fn() {
    if flag(row, "join") {
      @sf.button(c, tr("android-misc.adb.ask.how"), key="phone/" + request + "/how", tone=Primary, on_press=how)
    } else if lacks is None {
      @sf.button(c, tr("android-settings.vault.act.allow"), key="phone/" + request + "/yes", tone=Primary, busy=pending == Some(true), disabled=under, on_press=fn() { decide(true) })
    }
    @sf.button(c, tr("android-settings.vault.act.deny"), key="phone/" + request + "/no", tone=Ghost, busy=pending == Some(false), disabled=under, on_press=fn() { decide(false) })
    // (nothing to allow yet: no length to choose)
    if scopes.length() < 2 || lacks is Some(_) {
      return
    }
    let entries = scopes.map(fn(s) { @kit.menu_radio(s, s == scope, label=tr("android-settings.vault.scope." + s)) })
    let m = @sf.chooser(
      c,
      "phone/" + request + "/scope",
      tr("android-settings.vault.scope." + scope),
      entries,
      fn() { vault_menu.val == "phone/" + request },
      fn(on) { vault_menu_set("phone/" + request, on) },
    )
    match m.chosen {
      Some(s) => {
        vault_picked["phone/" + request] = s
        vault_menu.val = ""
      }
      None => ()
    }
  })
}

///|
/// How a request ended, in a line: a dot (green while granted) and 已允许调试手机 · 本对话内, 已拒绝调试手机, or why it
/// ended (已收回, 对话已归档, 授权已到期); laid as vault_outcome's (`inline`: by the message's picture). Granted, how
/// its station's adb holds the phone (`link`, phone_link's; "": not said, as from a station before it did): green only
/// once it is connected, and while the station waits to be paired with it, elsewhere than on the phone that it is paired
/// on the phone (2026-10-30: approved, its station not paired, the card said 已允许 and nothing more, and its page could
/// not be found). `step_here`: on the phone, a card under the line says what is left to do (decision.mbt's), so the
/// line says no more than what was allowed.
pub fn phone_outcome(
  c : @ui.Ctx,
  status : String,
  scope : String,
  why : String,
  inline? : Bool = true,
  link? : String = "",
  step_here? : Bool = false,
  history? : (String, (Int) -> Unit)? = None,
) -> Unit {
  let granted = status == "granted"
  let words = phone_outcome_words(status, scope, why)
  // (on the phone, a step left: its card under the line says so, the line not again, 2026-11-11)
  let linked = if granted && link != "" && !step_here {
    words + " · " + phone_link_words(link)
  } else {
    words
  }
  ask_outcome(c, granted && (link == "" || link == "connected"), [@ui.span(linked)], inline~, history~)
  // (elsewhere than on the phone: where it is paired, under the line's words where they start)
  if granted && link == "unpaired" && !step_here {
    c.box(style=if inline { ask_ended_past } else { ask_ended_at }, fn() {
      c.text(tr("android-misc.adb.ask.link.onPhone"), style=@sf.ask_note) |> ignore
    })
    |> ignore
  }
}

///|
/// How a granted phone is held by its station's adb, in words (phone_outcome's).
fn phone_link_words(link : String) -> String {
  match link {
    "connected" | "unpaired" | "gone" | "off" | "unauthorized" | "failed" | "missing" => tr("android-misc.adb.ask.link." + link)
    _ => tr("android-misc.adb.attaching")
  }
}

///|
/// How the station at `station` holds this phone for a granted request: as this phone's own lending to it says
/// (`adbShare`'s `lends`, as it changes) where it is lent there, else as the station said on the card (`said`).
pub fn phone_link(core : Core?, station : String, said : String) -> String {
  match core {
    Some(core) => {
      let view = adb_lend_view((core.topic)("adbShare", Map([])).get().value, station)
      if flag(view, "sharing") && text(view, "station") == station && text(view, "phase") == "offered" && text(view, "adb") != "" {
        text(view, "adb")
      } else {
        said
      }
    }
    None => said
  }
}

///|
/// How a request ended, in words (phone_outcome's).
pub fn phone_outcome_words(status : String, scope : String, why : String) -> String {
  let scope = if scope == "hour" || scope == "idle" || scope == "eight" { scope } else { "chat" }
  match status {
    "granted" => fill("android-misc.adb.ask.granted", [("scope", tr("android-settings.vault.scope." + scope))])
    "denied" if why == "" => tr("android-misc.adb.ask.denied")
    _ => fill("android-misc.adb.ask.ended", [("why", if why == "" { tr("android-misc.adb.ask.denied") } else { why })])
  }
}
