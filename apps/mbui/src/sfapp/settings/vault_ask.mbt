// An agent's request about a vault item as a card (VaultAsk.tsx AskCard, VaultApproval.tsx VaultActions): to use one
// or to keep one (docs/vault.md 申请和授权, agent 存入). One card wherever such a request is answered: in place of the
// agent's post in its chat (src/sfapp/vault_approval.mbt) and among the vault page's waiting requests. A card of words
// (@sf.card): what is asked in its title, the command it is for, a risk only where there is one, and the answer at its
// foot: the answer most give as the one solid button (允许 / 存入), the other beside it (拒绝 / 不存), how long a use is
// allowed a choice beside them that starts at the longest the item is given for (`vault.approve`, `vault.deny`). Only
// the viewer's own request can be answered, and only in an app keeping keys; elsewhere a line says whose it is or where
// it is approved. A secret to keep while the vault is not on on this device: 开启密钥库, to the vault's page.

///|
/// What a request's card says (VaultAsk.tsx Asked): the item's name, how it would be given (`mode`), the command it is
/// for; one to keep a secret, what it is (`save_kind`: login, token, ssh_key) and its account; another station of the
/// workspace its commands run on, by name (empty: the chat's).
pub(all) struct Asked {
  name : String
  mode : String
  command : String
  save_kind : String
  username : String
  station : String
}

///|
/// The request whose length-of-use menu is open (empty: none); put back by `reset`.
let vault_menu : Ref[String] = Ref("")

///|
/// The length of use picked for each request; put back by `reset`.
let vault_picked : Map[String, String] = {}

///|
/// What was tapped on each request while the core has it (`true`: the yes, `false`: the no), till it answers
/// (VaultActions' pending: the core's doing comes a frame later); put back by `reset`.
let vault_pending : Map[String, Bool] = {}

///|
fn vault_ask_reset() -> Unit {
  vault_menu.val = ""
  vault_picked.clear()
  vault_pending.clear()
}

///|
/// Request `request` in workspace `ws` as a card: what is asked, and its answer at the foot (vault_actions; `mine`,
/// `who`, `extra` as there).
pub fn vault_ask(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  request : String,
  ask : Asked,
  mine : Bool,
  who? : String? = None,
  extra? : (() -> Unit)? = None,
) -> Unit {
  let view = vaults_of(core, ws)
  let row = items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == request })
  // (a solid button at its foot where there is an answer to give here: the card's corner is then the button's)
  let answers = mine &&
    (flag(view, "available") || flag(view, "plain")) &&
    (row is Some(_) || vault_pending.contains(request))
  @sf.card(c, button_corner=answers, fn() {
    vault_asked(c, ask)
    vault_actions(c, core, ws, request, mine, who~, extra~)
  })
  |> ignore
}

///|
/// What is asked (AskCard's what): its title (使用「…」, 存入密码「…」 and the account), the command, and only what is
/// out of the ordinary: a command that reads the secret itself, one run on another station.
fn vault_asked(c : @ui.Ctx, ask : Asked) -> Unit {
  let t = @sf.theme()
  let save = ask.save_kind != ""
  c.box(style=ask_what, fn() {
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
    c.rich(runs, style=ask_title) |> ignore
    if !save && ask.command != "" {
      c.rich([@ui.span(ask.command, mono=true)], style=ask_command) |> ignore
    }
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
      c.rich(runs, style=ask_note) |> ignore
    }
  })
  |> ignore
}

///|
/// How a request ended (`status`: granted, denied, else expired; `scope`: how long a use was granted), in a line: a dot
/// (green once granted) and 已存入密码「…」, 已允许使用「…」 · 本对话内, 已拒绝使用「…」.
pub fn vault_outcome(c : @ui.Ctx, ask : Asked, status : String, scope : String) -> Unit {
  let save = ask.save_kind != ""
  let scope = if scope == "once" || scope == "hour" { scope } else { "chat" }
  let words = match status {
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
  c.box(style=ask_ended, fn() {
    c.box(style=if status == "granted" { ask_dot_on } else { ask_dot }, fn() {  }) |> ignore
    c.text(words, style=ask_ended_words) |> ignore
  })
  |> ignore
}

///|
/// The answer to request `request` in workspace `ws` (VaultActions): the buttons while it waits on the viewer (`mine`),
/// or a line where there is no answer to give here (`who`: whose it is). `extra`: after the buttons (the vault page's
/// 打开对话).
pub fn vault_actions(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  request : String,
  mine : Bool,
  who? : String? = None,
  extra? : (() -> Unit)? = None,
) -> Unit {
  let note = fn(words : String) { c.text(words, style=ask_note) |> ignore }
  let view = vaults_of(core, ws)
  if view is None {
    return
  }
  // a web page keeps no keys (the plain library's, without security mode, are approved anywhere)
  if !flag(view, "available") && !flag(view, "plain") {
    note(tr("android-settings.vault.approve.inApp"))
    return
  }
  let row = items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == request })
  let pending = vault_pending.get(request)
  if !mine || (row is None && pending is None) {
    note(
      match who {
        Some(w) if !mine => w
        _ => tr("android-settings.vault.approve.decided")
      },
    )
    return
  }
  let save = field(row, "save") is Some(_)
  let scopes = if save { ["once"] } else { vault_scopes_up_to(text(row, "lasts")) }
  let scope = match vault_picked.get(request) {
    Some(s) if scopes.contains(s) => s
    _ => scopes[scopes.length() - 1]
  }
  let on = [("workspace", ws), ("request", request)]
  let busy = fn(yes : Bool) {
    pending == Some(yes) || is_doing(core, [if yes { "vault.approve" } else { "vault.deny" }], on)
  }
  let under = pending is Some(_) || is_doing(core, ["vault.approve", "vault.deny"], on)
  let answer = fn(yes : Bool, call : String, what : String, params : Json) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending[request] = yes
    (core.call)(call, params, fn(r) {
      vault_pending.remove(request)
      if r is Err(e) {
        (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
      }
    })
  }
  // (on a second line what has not the room on the first)
  c.box(style=ask_foot, flow=true, line_gap=ask_foot_lines, fn() {
    if save && !flag(view, "plain") && !flag(view, "setUp") {
      // kept only in a vault that is on here: the way to turn it on first
      if @sf.button(c, tr("android-settings.vault.turnOn"), key="vault/" + request + "/on", tone=Primary) {
        (core.push)(Route::Vault)
      }
    } else {
      let yes = if save { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }
      if @sf.button(c, tr(yes), key="vault/" + request + "/yes", tone=Primary, busy=busy(true), disabled=under) {
        let what = tr(if save { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" })
        answer(true, "vault.approve", what, obj([("workspace", str(ws)), ("request", str(request)), ("scope", str(if save { "once" } else { scope }))]))
      }
    }
    let no = if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }
    if @sf.button(c, tr(no), key="vault/" + request + "/no", tone=Ghost, busy=busy(false), disabled=under) {
      answer(false, "vault.deny", tr("android-settings.vault.act.denyWhat"), obj([("workspace", str(ws)), ("request", str(request))]))
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
    match extra {
      Some(f) => f()
      None => ()
    }
  })
  |> ignore
}

///|
/// The workspace's vaults as the core has them (`vaults`: its requests, whether keys are kept here).
fn vaults_of(core : Core, ws : String) -> Json? {
  (core.topic)("vaults", { "workspace": str(ws) }).value
}

///|
/// What is asked, over the answer: its lines 2 apart (VaultAsk.css.ts what).
// kept across runs: a value (no field of it changes)
let ask_what : @ui.Style = @ui.css("w=Full gap=S0_5")

///|
/// Its title, 14 on 20 (the account after it quieter, its own run).
// kept across runs: a value (no field of it changes)
let ask_title : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Fg, w=Full)

///|
/// The command, one line of it, 12 and quiet.
// kept across runs: a value (no field of it changes)
let ask_command : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, color=Muted, wrap=false, max_lines=1, w=Full)

///|
/// A line of what is out of the ordinary, or where there is no answer to give here: 12 and quiet.
// kept across runs: a value (no field of it changes)
let ask_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L4_75, color=Muted, w=Full)

///|
/// The answer's buttons, 10 apart (pages.css.ts cardFoot).
// kept across runs: a value (no field of it changes)
let ask_foot : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")


///|
/// Between the foot's lines, where its buttons go on to a second (8).
let ask_foot_lines : Double = 8.0
///|
/// How it ended: a dot and its words, 8 apart.
// kept across runs: a value (no field of it changes)
let ask_ended : @ui.Style = @ui.css("row gap=S2 align=ACenter pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let ask_ended_words : @ui.TextStyle = @ui.text_style(size=Base, leading=L5, color=Muted)

///|
/// Its dot, 6 round: green once granted, else quiet.
// kept across runs: a value (no field of it changes)
let ask_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Subtle")

///|
// kept across runs: a value (no field of it changes)
let ask_dot_on : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Positive")
