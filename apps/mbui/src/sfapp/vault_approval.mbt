// An agent's request for a vault item where its card is (Vault.kt VaultApproval; Decisions.kt: a post's options card
// with `vault`, in a chat and on the 奏 page): the three answers in place of the card's own when it waits on the viewer
// here (`vault.approve` once or for the chat's hour, `vault.deny`); shown but not to be tapped where they cannot be
// (another's to decide, `mine` false: the card says whose; a device that holds no key, said to be the app's); once
// decided (no longer among the vault's requests), nothing to tap, until its station takes the card back.

///|
fn vault_approval(c : @ui.Ctx, src : Source, ws : String, request : String, mine : Bool) -> Unit {
  let view = (src.topic)("vaults", { "workspace": ws.to_json() }).value
  let running = vault_answering(request) is Some(_)
  if view is None || !mine {
    vault_options(c, src, ws, request, false)
  } else if !flag(view, "available") {
    vault_options(c, src, ws, request, false)
    c.box(style=vault_said_room, fn() { c.text(tr("android-settings.vault.approve.inApp"), style=vault_said) |> ignore })
    |> ignore
  } else if running || items(view, "requests").iter().any(fn(r) { text(Some(r), "id") == request }) {
    vault_options(c, src, ws, request, true)
  } else {
    c.text(tr("android-settings.vault.approve.decided"), style=vault_said) |> ignore
  }
}

///|
/// The three answers (Vault.kt VaultOptions), in the decisions' options: once (the one recommended), this chat for an
/// hour, refused; the one under way turns where it was tapped.
fn vault_options(c : @ui.Ctx, src : Source, ws : String, request : String, enabled : Bool) -> Unit {
  let options : Array[Choice] = [
    {
      label: tr("android-settings.vault.approve.once"),
      detail: tr("android-settings.vault.approve.onceDetail"),
      recommended: true,
    },
    {
      label: tr("android-settings.vault.approve.hour"),
      detail: tr("android-settings.vault.approve.hourDetail"),
      recommended: false,
    },
    {
      label: tr("android-settings.vault.approve.deny"),
      detail: tr("android-settings.vault.approve.denyDetail"),
      recommended: false,
    },
  ]
  let busy = match vault_answering(request) {
    Some(i) => Some(options[i].label)
    None => None
  }
  match decision_options(c, "vault/" + request, options, enabled, busy) {
    Some(o) => {
      let at = if o.label == options[0].label { 0 } else if o.label == options[1].label { 1 } else { 2 }
      let on : Map[String, Json] = { "workspace": ws.to_json(), "request": request.to_json() }
      if at == 2 {
        act(src, tr("android-settings.vault.approve.denyWhat"), vault_key(request, 2), "vault.deny", Json::object(on))
      } else {
        on["scope"] = (if at == 0 { "once" } else { "hour" }).to_json()
        act(src, tr("android-settings.vault.approve.what"), vault_key(request, at), "vault.approve", Json::object(on))
      }
    }
    None => ()
  }
}

///|
fn vault_key(request : String, option : Int) -> String {
  "vault/" + request + "/" + option.to_string()
}

///|
/// Which of a request's answers is under way, if one is.
fn vault_answering(request : String) -> Int? {
  for i in 0..<3 {
    if doing(vault_key(request, i)) {
      return Some(i)
    }
  }
  None
}

///|
/// What is said in place of the answers (13 on 19, the chat's subtle: Vault.kt:443), 6 under them where they show.
// kept across runs: a value (no field of it changes)
let vault_said : @ui.TextStyle = @ui.text_style(size=Sm, leading=L4_75, color=Subtle, w=Full)

///|
// kept across runs: a value (no field of it changes)
let vault_said_room : @ui.Style = @ui.style(w=Full, pt=S1_5)
