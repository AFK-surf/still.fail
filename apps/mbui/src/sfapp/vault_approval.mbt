// An agent's request about a vault item where its card is (VaultAsk.tsx, VaultApproval.tsx): to use one or to keep one
// (docs/vault.md 申请和授权, agent 存入). In place of the post's words, a card of words (@sf.card): what is asked in its
// title, the command it is for, a risk only where there is one, and the answer at its foot: the answer most give as the
// one solid button (允许 / 存入), the other beside it (拒绝 / 不存), how long a use is allowed a choice beside them that
// starts at the longest the item is given for (`vault.approve`, `vault.deny`). Once decided, one line saying how it
// ended. Only the viewer's own request can be answered, and only in an app keeping keys; elsewhere a line says whose it
// is or where it is approved. A secret to keep while the vault is not on on this device: 开启密钥库, to the vault's page.

///|
/// The request whose length-of-use menu is open (empty: none); put back by `reset`.
let vault_menu : Ref[String] = Ref("")

///|
/// The length of use picked for each request; put back by `reset`.
let vault_picked : Map[String, String] = {}

///|
/// The card in place of an agent's post asking about a vault item (`card.vaultAsk`), at the chat's station.
fn vault_ask_card(c : @ui.Ctx, src : Source, here : Here, card : Card, ask : VaultAsk) -> Unit {
  if ask.status != "" {
    vault_outcome(c, ask)
    return
  }
  let t = @sf.theme()
  let ws = workspace_of(here.station)
  let me = here.view.me
  let mine = card.assignee == "" || me == "" || card.assignee.to_lower() == me.to_lower()
  let view = (src.topic)("vaults", { "workspace": ws.to_json() }).value
  let row = items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == card.vault })
  let save = ask.save_kind != ""
  // (a solid button at its foot where there is an answer to give here: the card's corner is then the button's)
  let answers = mine &&
    (flag(view, "available") || flag(view, "plain")) &&
    (row is Some(_) || vault_answering(card.vault) is Some(_))
  @sf.card(c, button_corner=answers, fn() {
    c.box(style=vault_what, fn() {
      let title = if save {
        fill("android-settings.vault.ask.save", [
          ("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)),
          ("name", ask.name),
        ])
      } else {
        fill("android-settings.vault.ask.use", [("name", ask.name)])
      }
      let runs = [@ui.span(title, weight=600, color=t.p.text)]
      if save && ask.username != "" {
        runs.push(@ui.span("  " + ask.username, color=t.p.muted))
      }
      c.rich(runs, style=vault_title) |> ignore
      if !save && ask.command != "" {
        c.rich([@ui.span(ask.command, mono=true)], style=vault_command) |> ignore
      }
      // only what is out of the ordinary: a command that reads the secret itself, one run on another station
      let risky = !save && ask.mode == "env"
      let elsewhere = !save && ask.station != ""
      if risky || elsewhere {
        let runs : Array[@ui.Run] = []
        if risky {
          runs.push(@ui.span(tr("android-settings.vault.ask.plain"), color=t.p.warn_ink))
        }
        if risky && elsewhere {
          runs.push(@ui.span(" · "))
        }
        if elsewhere {
          runs.push(@ui.span(fill("android-settings.vault.ask.on", [("station", ask.station)])))
        }
        c.rich(runs, style=vault_note) |> ignore
      }
    })
    |> ignore
    vault_actions(c, src, ws, card.vault, row, view, mine, save, card.assignee_text)
  })
  |> ignore
}

///|
/// How a request ended, in a line: a dot (green once granted) and 已存入密码「…」, 已允许使用「…」 · 本对话内, 已拒绝使用「…」.
fn vault_outcome(c : @ui.Ctx, ask : VaultAsk) -> Unit {
  let save = ask.save_kind != ""
  let scope = if ask.scope == "once" || ask.scope == "hour" { ask.scope } else { "chat" }
  let words = match ask.status {
    "granted" if save =>
      fill("android-settings.vault.ask.kept", [
        ("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)),
        ("name", ask.name),
      ])
    "granted" => fill("android-settings.vault.ask.granted", [("name", ask.name), ("scope", tr("android-settings.vault.scope." + scope))])
    "denied" if save => fill("android-settings.vault.ask.notKept", [("name", ask.name)])
    "denied" => fill("android-settings.vault.ask.denied", [("name", ask.name)])
    _ => tr("android-settings.vault.ask.expired")
  }
  c.box(style=vault_ended, fn() {
    c.box(style=if ask.status == "granted" { vault_dot_on } else { vault_dot }, fn() {  }) |> ignore
    c.text(words, style=vault_ended_words) |> ignore
  })
  |> ignore
}

///|
/// The answer to request `request` (its row among the vault's requests, `row`, while it waits on the viewer): the
/// buttons, or a line where there is no answer to give here (`who`: whose it is).
fn vault_actions(
  c : @ui.Ctx,
  src : Source,
  ws : String,
  request : String,
  row : Json?,
  view : Json?,
  mine : Bool,
  save : Bool,
  who : String?,
) -> Unit {
  let note = fn(words : String) { c.text(words, style=vault_note) |> ignore }
  if view is None {
    return
  }
  if !flag(view, "available") && !flag(view, "plain") {
    note(tr("android-settings.vault.approve.inApp"))
    return
  }
  let running = vault_answering(request)
  if !mine || (row is None && running is None) {
    note(
      match who {
        Some(w) if !mine => w
        _ => tr("android-settings.vault.approve.decided")
      },
    )
    return
  }
  let scopes = if save { ["once"] } else { @settings.vault_scopes_up_to(text(row, "lasts")) }
  let scope = match vault_picked.get(request) {
    Some(s) if scopes.contains(s) => s
    _ => scopes[scopes.length() - 1]
  }
  let on : Map[String, Json] = { "workspace": ws.to_json(), "request": request.to_json() }
  c.box(style=vault_foot, fn() {
    if save && !flag(view, "plain") && !flag(view, "setUp") {
      // kept only in a vault that is on here: the way to turn it on first
      if @sf.button(c, tr("android-settings.vault.turnOn"), key="vault/" + request + "/on", tone=Primary) {
        app.nav.push(Setting(@settings.Route::Vault))
      }
    } else {
      let yes = if save { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }
      let busy = match running {
        Some(n) => n != vault_deny_no
        None => false
      }
      if @sf.button(c, tr(yes), key="vault/" + request + "/yes", tone=Primary, busy~, disabled=running is Some(_)) {
        let given = if save { "once" } else { scope }
        on["scope"] = given.to_json()
        let what = if save { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" }
        act(src, tr(what), vault_key(request, vault_scope_no(given)), "vault.approve", Json::object(on))
      }
    }
    let no = if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }
    if @sf.button(c, tr(no), key="vault/" + request + "/no", tone=Ghost, busy=running == Some(vault_deny_no), disabled=running is Some(_)) {
      act(src, tr("android-settings.vault.act.denyWhat"), vault_key(request, vault_deny_no), "vault.deny", Json::object(on))
    }
    if !save && scopes.length() > 1 {
      let entries = scopes.map(fn(s) { @kit.menu_radio(s, s == scope, label=tr("android-settings.vault.scope." + s)) })
      let m = @sf.chooser(c, "vault/" + request + "/scope", tr("android-settings.vault.scope." + scope), entries, vault_menu.val == request)
      if m.open {
        vault_menu.val = request
      } else if vault_menu.val == request {
        vault_menu.val = ""
      }
      match m.chosen {
        Some(s) => {
          vault_picked[request] = s
          vault_menu.val = ""
        }
        None => ()
      }
    }
  })
  |> ignore
}

///|
/// The answer under a card that names a vault request but says nothing of it (from a station before `vaultAsk`), and
/// on the 奏 page under such a post: the buttons alone.
fn vault_approval(c : @ui.Ctx, src : Source, ws : String, request : String, mine : Bool) -> Unit {
  let view = (src.topic)("vaults", { "workspace": ws.to_json() }).value
  let row = items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == request })
  vault_actions(c, src, ws, request, row, view, mine, field(row, "save") is Some(_), None)
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
/// What is asked, over the answer: its lines 2 apart (VaultAsk.css.ts what).
// kept across runs: a value (no field of it changes)
let vault_what : @ui.Style = @ui.style(w=Full, gap=S0_5)

///|
/// Its title, 14 on 20 (the account after it quieter, its own run).
// kept across runs: a value (no field of it changes)
let vault_title : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Fg, w=Full)

///|
/// The command, one line of it, 12 and quiet.
// kept across runs: a value (no field of it changes)
let vault_command : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, color=Muted, wrap=false, max_lines=1, w=Full)

///|
/// A line of what is out of the ordinary, or where there is no answer to give here: 12 and quiet.
// kept across runs: a value (no field of it changes)
let vault_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, color=Muted, w=Full)

///|
/// The answer's buttons, 10 apart (pages.css.ts cardFoot).
// kept across runs: a value (no field of it changes)
let vault_foot : @ui.Style = @ui.style(row=true, gap=S2_5, align=ACenter)

///|
/// How it ended: a dot and its words, 8 apart.
// kept across runs: a value (no field of it changes)
let vault_ended : @ui.Style = @ui.style(row=true, gap=S2, align=ACenter, pt=S0_5)

///|
// kept across runs: a value (no field of it changes)
let vault_ended_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Muted)

///|
/// Its dot, 6 round: green once granted, else quiet.
// kept across runs: a value (no field of it changes)
let vault_dot : @ui.Style = @ui.style(w=S1_5, h=S1_5, radius=Full, bg=Subtle)

///|
// kept across runs: a value (no field of it changes)
let vault_dot_on : @ui.Style = @ui.style(w=S1_5, h=S1_5, radius=Full, bg=Positive)
