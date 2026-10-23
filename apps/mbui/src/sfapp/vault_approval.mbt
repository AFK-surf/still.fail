// An agent's request for a vault item where its card is (Vault.kt VaultApproval; Decisions.kt: a post's options card
// with `vault`, in a chat and on the 奏 page): the three answers in place of the card's own when it waits on the viewer
// here (`vault.approve` once, for the chat's hour or until it is archived, as far as the item allows; `vault.deny`); shown
// but not to be tapped where they cannot be
// (another's to decide, `mine` false: the card says whose; a device that holds no key, said to be the app's); once
// decided (no longer among the vault's requests), nothing to tap, until its station takes the card back.

///|
fn vault_approval(c : @ui.Ctx, src : Source, ws : String, request : String, mine : Bool) -> Unit {
  let view = (src.topic)("vaults", { "workspace": ws.to_json() }).value
  let running = vault_answering(request) is Some(_)
  // (the longest the item is granted for: its request says, as the station posts it)
  let lasts = match items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == request }) {
    Some(r) => text(Some(r), "lasts")
    None => ""
  }
  if view is None || !mine {
    vault_options(c, src, ws, request, lasts, false)
  } else if !flag(view, "available") {
    vault_options(c, src, ws, request, lasts, false)
    c.box(style=vault_said_room, fn() { c.text(tr("android-settings.vault.approve.inApp"), style=vault_said) |> ignore })
    |> ignore
  } else if running || items(view, "requests").iter().any(fn(r) { text(Some(r), "id") == request }) {
    vault_options(c, src, ws, request, lasts, true)
  } else {
    c.text(tr("android-settings.vault.approve.decided"), style=vault_said) |> ignore
  }
}

///|
/// The answers (Vault.kt VaultOptions), in the decisions' options: once, this chat for an hour, this chat until it is
/// archived, as far as the item allows (`lasts`), the longest recommended; refused. The one under way turns where it was
/// tapped.
fn vault_options(c : @ui.Ctx, src : Source, ws : String, request : String, lasts : String, enabled : Bool) -> Unit {
  let scopes = @settings.vault_scopes_up_to(lasts)
  let options : Array[Choice] = scopes.mapi(fn(i, s) {
    {
      label: tr("android-settings.vault.approve." + s),
      detail: tr("android-settings.vault.approve." + s + "Detail"),
      recommended: i == scopes.length() - 1,
    }
  })
  options.push({
    label: tr("android-settings.vault.approve.deny"),
    detail: tr("android-settings.vault.approve.denyDetail"),
    recommended: false,
  })
  // (each answer's key by what it is: a scope's place among them all, refused after them)
  let key_of = fn(i : Int) { if i < scopes.length() { vault_scope_no(scopes[i]) } else { vault_deny_no } }
  let busy = match vault_answering(request) {
    Some(no) =>
      match Array::makei(options.length(), fn(i) { i }).search_by(fn(i) { key_of(i) == no }) {
        Some(i) => Some(options[i].label)
        None => None
      }
    None => None
  }
  match decision_options(c, "vault/" + request, options, enabled, busy) {
    Some(o) => {
      let at = options.search_by(fn(x) { x.label == o.label }).unwrap_or(options.length() - 1)
      let on : Map[String, Json] = { "workspace": ws.to_json(), "request": request.to_json() }
      if at >= scopes.length() {
        act(src, tr("android-settings.vault.approve.denyWhat"), vault_key(request, vault_deny_no), "vault.deny", Json::object(on))
      } else {
        on["scope"] = scopes[at].to_json()
        act(src, tr("android-settings.vault.approve.what"), vault_key(request, key_of(at)), "vault.approve", Json::object(on))
      }
    }
    None => ()
  }
}

///|
/// An answer's number in its key: a grant's place among every scope (once, hour, chat), refused after them.
fn vault_scope_no(scope : String) -> Int {
  match scope {
    "once" => 0
    "hour" => 1
    _ => 2
  }
}

///|
let vault_deny_no : Int = 3

///|
fn vault_key(request : String, option : Int) -> String {
  "vault/" + request + "/" + option.to_string()
}

///|
/// Which of a request's answers is under way (its number: vault_scope_no, vault_deny_no), if one is.
fn vault_answering(request : String) -> Int? {
  for i in 0..=vault_deny_no {
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
