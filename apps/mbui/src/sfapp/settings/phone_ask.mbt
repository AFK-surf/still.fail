// An agent's request to debug its person's phone as a card (docs/adb-share.md, 2026-10-29: as a vault request's): what
// is asked in its title, the agent's reason under it, and at its foot 允许 as the one solid button, 拒绝 beside it, and
// how long it is allowed a choice beside them that starts at the longest (`adb.decide` on the chat's station). Only the
// viewer's own request is answered; elsewhere a line says whose it is. Decided, a line says how it went.

///|
/// The length picked for each request; put back with the app.
let phone_picked : Map[String, String] = {}

///|
/// The request whose length menu is open (empty: none).
let phone_menu : Ref[String] = Ref("")

///|
/// The answer under way for each request (true: 允许), till the card says how it went.
let phone_pending : Map[String, Bool] = {}

///|
/// The request's card while it waits: its words, and its answer where it is the viewer's (`mine`) and a core is there.
pub fn phone_card(
  c : @ui.Ctx,
  core : Core?,
  station : String,
  request : String,
  reason : String,
  mine : Bool,
  lasts? : String = "chat",
  who? : String? = None,
) -> Unit {
  // (a card of words, as a vault request's: its answer in its foot corners)
  @sf.card(c, fn() {
    ask_words(c, tr("android-misc.adb.ask.chat.title"), reason)
    match core {
      Some(core) if mine => phone_foot(c, core, station, request, lasts)
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
/// Its answer: 允许 (for the length chosen), 拒绝, and the length's menu.
fn phone_foot(c : @ui.Ctx, core : Core, station : String, request : String, lasts : String) -> Unit {
  // (up to its owner's 默认最长授权, starting at the longest)
  let scopes = if lasts == "hour" { ["hour"] } else { ["hour", "chat"] }
  let scope = match phone_picked.get(request) {
    Some(s) if scopes.contains(s) => s
    _ => scopes[scopes.length() - 1]
  }
  let on = [("station", station), ("request", request)]
  let pending = phone_pending.get(request)
  let under = pending is Some(_) || is_doing(core, ["adb.decide"], on)
  let decide = fn(yes : Bool) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    phone_pending[request] = yes
    let params : Array[(String, Json)] = [("station", str(station)), ("request", str(request))]
    if yes {
      params.push(("scope", str(scope)))
    }
    (core.call)("adb.decide", obj(params), fn(r) {
      match r {
        Err(e) => {
          phone_pending.remove(request)
          let what = tr(if yes { "android-settings.vault.act.allowWhat" } else { "android-settings.vault.act.denyWhat" })
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => ()
      }
    })
  }
  ask_buttons(c, fn() {
    if @sf.button(c, tr("android-settings.vault.act.allow"), key="phone/" + request + "/yes", tone=Primary, busy=pending == Some(true), disabled=under) {
      decide(true)
    }
    if @sf.button(c, tr("android-settings.vault.act.deny"), key="phone/" + request + "/no", tone=Ghost, busy=pending == Some(false), disabled=under) {
      decide(false)
    }
    if scopes.length() < 2 {
      return
    }
    let entries = scopes.map(fn(s) { @kit.menu_radio(s, s == scope, label=tr("android-settings.vault.scope." + s)) })
    let m = @sf.chooser(c, "phone/" + request + "/scope", tr("android-settings.vault.scope." + scope), entries, phone_menu.val == request)
    if m.open {
      phone_menu.val = request
    } else if phone_menu.val == request {
      phone_menu.val = ""
    }
    match m.chosen {
      Some(s) => {
        phone_picked[request] = s
        phone_menu.val = ""
      }
      None => ()
    }
  })
}

///|
/// How a request ended, in a line: a dot (green while granted) and 已允许调试手机 · 本对话内, 已拒绝调试手机, or why it
/// ended (已收回, 对话已归档, 授权已到期).
pub fn phone_outcome(c : @ui.Ctx, status : String, scope : String, why : String) -> Unit {
  let scope = if scope == "hour" { "hour" } else { "chat" }
  let words = match status {
    "granted" => fill("android-misc.adb.ask.granted", [("scope", tr("android-settings.vault.scope." + scope))])
    "denied" if why == "" => tr("android-misc.adb.ask.denied")
    _ => fill("android-misc.adb.ask.ended", [("why", if why == "" { tr("android-misc.adb.ask.denied") } else { why })])
  }
  c.box(style=ask_ended, fn() {
    c.box(style=if status == "granted" { ask_dot_on } else { ask_dot }, fn() {  }) |> ignore
    c.text(words, style=ask_ended_words) |> ignore
  })
  |> ignore
}
