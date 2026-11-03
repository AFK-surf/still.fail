// A member's device set up without the key to a vault of the person's own, waiting on this one for it (the core's
// `lockPrompts` topic's `asks`, views/vault.ts `vaultAsks`: the topic every page has open and every recorded run asks, so no
// topic of its own; the lock's own prompts are lock_prompts.mbt): put up over whichever page is open, in any
// workspace of the person's, once, until given the key here (授权: `vault.addDevice {vault, device}`, this device's key
// unsealed, the person asked once) or put away (稍后, a tap beside it: `vault.hidePrompt {device}`, put up again once that
// device asks again: a certificate dated later). Given the key on another device, it goes by itself.

///|
/// The asks put up here (a device, a vault and when it asked, `key_ask_of`), then put away: not put up again while the
/// core has yet to drop them. The same device asking again (dated later) is put up again. What the core dropped is
/// forgotten here too.
let key_asks_closed : Array[String] = []

///|
fn key_ask_of(r : Json) -> String {
  text(Some(r), "workspace") + " " + text(Some(r), "vault") + " " + text(Some(r), "device") + " " + count(Some(r), "at").to_string()
}

///|
fn vault_prompts_reset() -> Unit {
  key_asks_closed.clear()
}

///|
/// The latest device waiting on this one for a key, put up in a sheet when nothing else is (`free`: no sheet of the
/// app's up): call each frame, over the pages.
pub fn vault_prompts(core : Core, free : Bool) -> Unit {
  let prompts = (core.topic)("lockPrompts", Map::new()).value
  let asks = items(prompts, "asks")
  if prompts is Some(_) {
    key_asks_closed.retain(fn(d) { asks.iter().any(fn(r) { key_ask_of(r) == d }) })
  }
  let waiting = asks.iter().find_first(fn(r) { !key_asks_closed.contains(key_ask_of(r)) })
  match waiting {
    Some(r) if free && !@sf.presenting() => key_ask_sheet(core, r)
    _ => ()
  }
}

///|
/// The sheet of a device asking for a key: which device and which vault (its workspace named too), that giving it
/// unlocks here once; 授权 (primary) and 稍后. Gone by itself once that device has the key (given here or elsewhere) or
/// asks no more.
fn key_ask_sheet(core : Core, r : Json) -> Unit {
  let rv = Some(r)
  let ws = text(rv, "workspace")
  let vault = text(rv, "vault")
  let device = text(rv, "device")
  let ask = key_ask_of(r)
  // (put up once: closed by hand or by the core's drop alike, not again)
  key_asks_closed.push(ask)
  let on = [("workspace", ws), ("vault", vault), ("device", device)]
  let hide = fn() {
    (core.call)("vault.hidePrompt", obj([("workspace", str(ws)), ("device", str(device)), ("at", Json::number(count(rv, "at").to_double()))]), fn(_) {  })
  }
  @sf.panel(fill("web-pages.vault.promptTitle", [("device", text(rv, "deviceText"))]), from=Unanchored, gone=hide, fn(c, close) {
    // given the key elsewhere, or put away there: gone here too
    let prompts = (core.topic)("lockPrompts", Map::new()).value
    let now = items(prompts, "asks").iter().find_first(fn(x) { key_ask_of(x) == ask })
    if prompts is Some(_) && now is None {
      close()
      return
    }
    c.box(style=key_ask_column, fn() {
      c.text(fill("web-pages.vault.promptBody", [("vault", text(rv, "vaultName")), ("at", text(rv, "atText"))]), style=key_ask_body)
      |> ignore
      c.text(text(rv, "workspaceName") + " · " + text(rv, "vaultName"), style=key_ask_where) |> ignore
      // put in the lock by someone else (an admin, under this person's name): said, so they know what they give to
      if !flag(rv, "own") {
        c.text(fill("web-pages.vault.promptBy", [("by", text(rv, "byText"))]), style=key_ask_warn) |> ignore
      }
      c.box(style=key_ask_buttons, fn() {
        let giving = is_doing(core, ["vault.addDevice"], on)
        if wide_button(c, "vault-key-give", tr("web-pages.vault.promptGive"), true, busy=giving) {
          act(core, tr("web-pages.vault.addDeviceWhat"), "vault.addDevice", obj([("workspace", str(ws)), ("vault", str(vault)), ("device", str(device))]), done=tr("web-pages.vault.addedDevice"))
        }
        if wide_button(c, "vault-key-later", tr("web-pages.vault.promptLater"), false, enabled=!giving) {
          close()
          hide()
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// What the panel holds, 12 apart (pair_column's).
// kept across runs: a value (no field of it changes)
let key_ask_column : @ui.Style = @ui.css("w=Full gap=S3")

///|
/// Which device asks what (14 in the muted).
// kept across runs: a value (no field of it changes)
let key_ask_body : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, w=Full)

///|
/// The workspace and vault it asks the key to (16 semibold).
// kept across runs: a value (no field of it changes)
let key_ask_where : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, color=Fg)

///|
/// That someone else put the device in the lock (13, in the warning's ink).
// kept across runs: a value (no field of it changes)
let key_ask_warn : @ui.TextStyle = @ui.text_style(size=Meta, color=WarnInk, w=Full)

///|
/// 授权 over 稍后, each as wide as the sheet, 8 apart, 16 over the sheet's foot (pair_deny_room's).
// kept across runs: a value (no field of it changes)
let key_ask_buttons : @ui.Style = @ui.css("w=Full gap=S2 pt=S1 pb=S4")
