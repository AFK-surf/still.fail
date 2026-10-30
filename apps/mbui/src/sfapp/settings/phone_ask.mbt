// An agent's request to debug its person's phone as a card (docs/adb-share.md, 2026-10-29: as a vault request's): what
// is asked in its title, the agent's reason under it, and at its foot 允许 as the one solid button, 拒绝 beside it, and
// how long it is allowed a choice beside them that starts at the longest (`adb.decide` on the chat's station). Only the
// viewer's own request is answered; elsewhere a line says whose it is. Decided, a line says how it went. What it
// keeps between frames (its menu, the length picked, the answer under way) is the vault card's, keyed `phone/<id>`.
// Answered on the phone itself while it lacks something to be lent (Developer options, Wi-Fi, Wireless debugging the
// app cannot turn on, its 共享调试 switch off), it says what first and 查看步骤 takes the place of 允许: allowed then,
// nothing could reach it.

///|
/// The request's card while it waits: its words, and its answer where it is the viewer's (`mine`) and a core is there.
/// `how`: the 共享调试 page opened, where this phone lacks something first.
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
    ask_words(c, tr("android-misc.adb.ask.chat.title"), reason)
    match core {
      Some(core) if mine =>
        answered_in_place(c, "phone/" + request, ended.map(fn(e) { (e.0 == "granted", [@ui.span(phone_outcome_words(e.0, e.1, e.2))]) }), fn() {
          phone_foot(c, core, station, request, lasts, how)
        })
      _ =>
        match who {
          Some(w) if w != "" => c.text(w, style=ask_note) |> ignore
          _ => ()
        }
    }
  })
  |> ignore
}

///|
/// Its answer: 允许 (for the length chosen), 拒绝, and the length's menu; on a phone that lacks something first, what,
/// and 查看步骤 (`how`) in 允许's place.
fn phone_foot(c : @ui.Ctx, core : Core, station : String, request : String, lasts : String, how : () -> Unit) -> Unit {
  // (a device with no adb of its own, a computer's: the grant is for the person's phone, lent as it is ready)
  let lacks = match adb_ready(c) {
    AdbLacks(step) => Some(step)
    // (a phone whose 共享调试 is off lends to no chat: turned on first, on its page)
    AdbLends if !flag((core.topic)("adbShare", Map([])).value, "on") => Some(tr("android-misc.adb.step.on"))
    _ => None
  }
  // (up to its owner's 默认最长授权, starting at the longest)
  let scopes = if lasts == "hour" { ["hour"] } else { ["hour", "chat"] }
  let scope = match vault_picked.get("phone/" + request) {
    Some(s) if scopes.contains(s) => s
    _ => scopes[scopes.length() - 1]
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
    // (Wireless debugging the app may turn on itself: on as it is allowed, as a lending from the page does)
    if yes {
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
    Some(step) => c.text(fill("android-misc.adb.ask.first", [("step", step)]), style=ask_note) |> ignore
    None => ()
  }
  ask_buttons(c, fn() {
    if lacks is Some(_) {
      if @sf.button(c, tr("android-misc.adb.ask.how"), key="phone/" + request + "/how", tone=Primary) {
        how()
      }
    } else if @sf.button(c, tr("android-settings.vault.act.allow"), key="phone/" + request + "/yes", tone=Primary, busy=pending == Some(true), disabled=under) {
      decide(true)
    }
    if @sf.button(c, tr("android-settings.vault.act.deny"), key="phone/" + request + "/no", tone=Ghost, busy=pending == Some(false), disabled=under) {
      decide(false)
    }
    // (nothing to allow yet: no length to choose)
    if scopes.length() < 2 || lacks is Some(_) {
      return
    }
    let entries = scopes.map(fn(s) { @kit.menu_radio(s, s == scope, label=tr("android-settings.vault.scope." + s)) })
    let m = @sf.chooser(c, "phone/" + request + "/scope", tr("android-settings.vault.scope." + scope), entries, vault_menu.val == "phone/" + request)
    if m.open {
      vault_menu.val = "phone/" + request
    } else if vault_menu.val == "phone/" + request {
      vault_menu.val = ""
    }
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
/// once it is connected, and while the station waits to be paired with it, elsewhere than on the phone (`paired_here`
/// false: on the phone its pairing is a card of its own, decision.mbt's) that it is paired on the phone (2026-10-30:
/// approved, its station not paired, the card said 已允许 and nothing more, and its page could not be found).
pub fn phone_outcome(
  c : @ui.Ctx,
  status : String,
  scope : String,
  why : String,
  inline? : Bool = true,
  link? : String = "",
  paired_here? : Bool = false,
) -> Unit {
  let granted = status == "granted"
  let words = phone_outcome_words(status, scope, why)
  let linked = if granted && link != "" { words + " · " + phone_link_words(link) } else { words }
  ask_outcome(c, granted && (link == "" || link == "connected"), [@ui.span(linked)], inline~)
  // (elsewhere than on the phone: where it is paired, under the line's words where they start)
  if granted && link == "unpaired" && !paired_here {
    c.box(style=if inline { ask_ended_past } else { ask_ended_at }, fn() {
      c.text(tr("android-misc.adb.ask.link.onPhone"), style=ask_note) |> ignore
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
      let view = adb_lend_view((core.topic)("adbShare", Map([])).value, station)
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
/// Where a request's 查看步骤 takes the person: settings' 共享调试 while the phone's switch is off (it is turned on
/// there), else the 共享调试 of the chat's station (`station`), which says what is next for it, pairing with it too
/// (2026-10-30: it opened settings' page, which has nothing of any station, its pairing nowhere to be found).
pub fn phone_steps(core : Core?, station : String) -> Route {
  match core {
    Some(core) if flag((core.topic)("adbShare", Map([])).value, "on") => AdbShare(station)
    _ => AdbShare("")
  }
}

///|
/// Whether this device lends its own adb (a phone that has what it takes, or will once a step is done): where a
/// request's pairing card opens its station's 共享调试.
pub fn phone_lends(c : @ui.Ctx) -> Bool {
  match adb_ready(c) {
    AdbLends | AdbLacks(_) => true
    _ => false
  }
}

///|
/// How a request ended, in words (phone_outcome's).
pub fn phone_outcome_words(status : String, scope : String, why : String) -> String {
  let scope = if scope == "hour" { "hour" } else { "chat" }
  match status {
    "granted" => fill("android-misc.adb.ask.granted", [("scope", tr("android-settings.vault.scope." + scope))])
    "denied" if why == "" => tr("android-misc.adb.ask.denied")
    _ => fill("android-misc.adb.ask.ended", [("why", if why == "" { tr("android-misc.adb.ask.denied") } else { why })])
  }
}
