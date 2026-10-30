// An agent's request about a vault item as a card (VaultAsk.tsx AskCard, VaultApproval.tsx VaultActions): to use one
// or to keep one (docs/vault.md 申请和授权, agent 存入). One card wherever such a request is answered: in place of the
// agent's post in its chat (src/sfapp/vault_approval.mbt) and among the vault page's waiting requests. A card of words
// (@sf.card): what is asked in its title, the command it is for, a risk only where there is one, and the answer at its
// foot: the answer most give as the one solid button (允许 / 存入), the other beside it (拒绝 / 不存), how long a use is
// allowed a choice beside them that starts at the longest the item is given for (`vault.approve`, `vault.deny`). Only
// the viewer's own request can be answered, and only in an app keeping keys; elsewhere a line says whose it is or where
// it is approved. A secret to keep while the vault is not on on this device: 开启密钥库, to the vault's page. One the
// person types in (the agent has none): its field over the answer (a login's account too, where the agent named none; a
// file, the button that picks it, its name and size once picked), 存入 once something is in it, Enter as 存入; what was
// typed goes only with `vault.approve`, and is let go once it went.

///|
/// What a request's card says (VaultAsk.tsx Asked): the item's name, how it would be given (`mode`), the command it is
/// for; one to keep a secret, what it is (`save_kind`: login, token, ssh_key, file), its account (a file: its name),
/// and whether the person types it in (`typed`; a file: picks it); another station of the workspace its commands run
/// on, by name (empty: the chat's).
pub(all) struct Asked {
  name : String
  mode : String
  command : String
  save_kind : String
  username : String
  filename : String
  typed : Bool
  station : String
}

///|
/// A secret to keep that the person types in here (`save.typed`: the agent has none): its kind, and the account the
/// agent named (empty: a login's is asked for too).
pub(all) struct Typed {
  kind : String
  username : String
}

///|
/// The secret to type in of request `save` (its `save`), or None where it is not the person's to type.
pub fn typed_of(save : Json?) -> Typed? {
  if flag(save, "typed") {
    Some({ kind: text(save, "kind"), username: text(save, "username") })
  } else {
    None
  }
}

///|
/// The secret to type in of what is asked, or None.
fn Asked::typed_in(self : Asked) -> Typed? {
  if self.typed {
    Some({ kind: self.save_kind, username: self.username })
  } else {
    None
  }
}

///|
/// The request whose length-of-use menu is open (empty: none); put back by `reset`.
let vault_menu : Ref[String] = Ref("")

///|
/// Whether what is asked is a file the person picks: its card fills its column, as wide before the file is picked as
/// after.
fn Asked::picks_file(self : Asked) -> Bool {
  self.typed && self.save_kind == "file"
}

///|
/// The length of use picked for each request; put back by `reset`.
let vault_picked : Map[String, String] = {}

///|
/// What was tapped on each request while the core has it (`true`: the yes, `false`: the no), till it answers
/// (VaultActions' pending: the core's doing comes a frame later); put back by `reset`.
let vault_pending : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// What the person types in for each request whose secret is theirs to type, by request and field (`/secret`,
/// `/username`): kept only till it went with `vault.approve`; put back by `reset`.
let vault_typed : @sf.LiveMap[String, @ui.Field] = @sf.LiveMap::new()

///|
/// The file picked for each request whose secret is a file the person picks: its bytes in base64 and its name, kept
/// only till it went with `vault.approve`; and the system's picker while it asks. Put back by `reset`.
let vault_files : @sf.LiveMap[String, (String, String)] = @sf.LiveMap::new()

///|
let vault_file_picks : Map[String, @ui.Pick] = {}

///|
fn vault_ask_reset() -> Unit {
  vault_menu.val = ""
  vault_picked.clear()
  vault_pending.clear()
  vault_typed.clear()
  vault_files.clear()
  vault_file_picks.clear()
}

///|
/// The field typed in for `request`'s `part` (kept across frames).
fn typed_field(request : String, part : String) -> @ui.Field {
  let key = request + part
  match vault_typed.get(key) {
    Some(f) => f
    None => {
      let f = @ui.Field::new()
      vault_typed[key] = f
      f
    }
  }
}

///|
/// How a request is answered here (VaultApproval.tsx VaultActions' cases), what its card's foot is.
pub(all) enum Answer {
  /// 允许 / 存入 and 拒绝 / 不存: a use given for as long as `lasts` at the longest (unused for a secret to keep)
  Approve(String)
  /// a secret to keep while this device's vault is not on: 开启密钥库, to the vault's page, first
  SetUp
  /// approved only in an app that keeps keys (a web page keeps none)
  Elsewhere
  /// decided already, its card not saying so yet
  Decided
  /// another's to answer: whose (the card's 由…决定)
  Theirs(String)
} derive(Eq, Show)

///|
/// How a request is answered here as its card says it (`answer`, `lasts`: its `vaultAsk`'s), the core having answered
/// that with its message from the vault it holds: nothing more is asked of it. Not the viewer's (`mine`), `who`'s.
pub fn card_answer(answer : String, lasts : String, mine : Bool, who? : String? = None) -> Answer {
  if !mine {
    return match who {
      Some(w) => Theirs(w)
      None => Decided
    }
  }
  match answer {
    "setUp" => SetUp
    "elsewhere" => Elsewhere
    _ => Approve(lasts)
  }
}

///|
/// How request `request` in workspace `ws` is answered here, from the vaults topic (the vault page's, which lists the
/// requests from it; a card from before its station said what it asks), whether it is one to keep and its secret to type
/// in: None while the topic has not come.
fn topic_answer(core : Core, ws : String, request : String, mine : Bool, who : String?) -> (Answer, Bool, Typed?)? {
  let view = vaults_of(core, ws)
  if view is None {
    return None
  }
  // a web page keeps no keys (the plain library's, without security mode, are approved anywhere)
  if !flag(view, "available") && !flag(view, "plain") {
    return Some((Elsewhere, false, None))
  }
  let row = items(view, "requests").iter().find_first(fn(r) { text(Some(r), "id") == request })
  if !mine || (row is None && !vault_pending.contains(request)) {
    return Some(
      (
        match who {
          Some(w) if !mine => Theirs(w)
          _ => Decided
        },
        false,
        None,
      ),
    )
  }
  let save = field(row, "save") is Some(_)
  let typed = typed_of(field(row, "save"))
  if save && !flag(view, "plain") && !flag(view, "setUp") {
    Some((SetUp, save, typed))
  } else {
    Some((Approve(text(row, "lasts")), save, typed))
  }
}

///|
/// Request `request` in workspace `ws` as a card, from the vaults topic (the vault page's waiting requests): what is
/// asked (`said`: lines more of it, each its own, where they are not in its chat beside it: why the agent asks, how it
/// would be given), and its answer at the foot (`mine`, `who`, `extra` as vault_actions').
pub fn vault_ask(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  request : String,
  ask : Asked,
  mine : Bool,
  who? : String? = None,
  extra? : (() -> Unit)? = None,
  said? : Array[String] = [],
) -> Unit {
  let answer = topic_answer(core, ws, request, mine, who)
  @sf.card(c, fill=ask.picks_file(), corner=@sf.ask_corner, fn() {
    vault_asked(c, ask)
    for line in said {
      if line != "" {
        c.text(line, style=ask_note) |> ignore
      }
    }
    match answer {
      Some((a, save, _)) => vault_foot(c, core, ws, request, a, save, typed=ask.typed_in(), extra~, foot=a is (Approve(_) | SetUp))
      None => ()
    }
  })
  |> ignore
}

///|
/// Request `request` in workspace `ws` as its card where it is asked (a chat's): what is asked, and its
/// answer at the foot as the card says it (`answer`: card_answer), whole with its message. `ended`: how it went
/// (granted, denied, else ended; `scope`), once answered while the card shows: said in its answer's place
/// (answered_in_place).
pub fn vault_card(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  request : String,
  ask : Asked,
  answer : Answer,
  ended? : (String, String)? = None,
) -> Unit {
  @sf.card(c, fill=ask.picks_file(), corner=@sf.ask_corner, fn() {
    vault_asked(c, ask)
    answered_in_place(c, "vault/" + request, ended.map(fn(e) { (e.0 == "granted", vault_outcome_words(ask, e.0, e.1)) }), fn() {
      vault_foot(c, core, ws, request, answer, ask.save_kind != "", typed=ask.typed_in(), foot=answer is (Approve(_) | SetUp))
    })
  })
  |> ignore
}

///|
/// A card's answer at its foot (`answer`), answered while the card shows (`ended`: whether it was granted, and how it
/// went in words): its answer fades out where it is (answered_fade_ms, Leave), only drawn, then how it went fades in
/// after it over the room it leaves, its dot and its words in the middle of it. The answer stays laid out (unseen):
/// the card keeps its size to the point, and the list it is in changes its height only once it is out of sight
/// (sfbase's list_turns.mbt Turns::in_turn).
pub fn answered_in_place(c : @ui.Ctx, key : String, ended : (Bool, Array[@ui.Run])?, answer : () -> Unit) -> Unit {
  let was = @motion.presence(
    c,
    "answered-was/" + key,
    ended is None,
    exit=@motion.trans(fade=0.0, spec=@motion.tween(answered_fade_ms, ease=Leave)),
  )
  c.box(style=answered_whole, fn() {
    let a = c.box(style=answered_room, answer)
    match ended {
      None => ()
      Some((granted, words)) => {
        c.look(a, was.unwrap_or(@ui.look(alpha=0.0)))
        c.draw_only(a)
        if was is None {
          let now = @motion.presence(
            c,
            "answered-now/" + key,
            true,
            enter=@motion.trans(fade=0.0, spec=@motion.tween(answered_fade_ms, ease=Out)),
            initial=true,
          )
          c.layer(fn() {
            let o = c.box(style=answered_over, fn() {
              c.box(style=if granted { ask_dot_on } else { ask_dot }, fn() {  }) |> ignore
              c.rich(words, style=ask_ended_words) |> ignore
            })
            c.look(o, now.unwrap_or(@ui.look()))
          })
          |> ignore
        }
      }
    }
  })
  |> ignore
}

///|
/// How long a card's answer takes to fade out once answered where it shows, and how it went to fade in after it.
pub let answered_fade_ms : Double = 200.0

///|
/// What is asked as its card alone, with no answer at its foot (AskCard without children: where nothing is answered).
pub fn vault_ask_words(c : @ui.Ctx, ask : Asked) -> Unit {
  @sf.card(c, corner=@sf.ask_corner, fn() { vault_asked(c, ask) }) |> ignore
}

///|
/// What is asked (AskCard's what): its title (使用 …, 存入密码 … and the account; the item's name in it heavier than the
/// words around it, not in quotes), the command, and only what is
/// out of the ordinary: a command that reads the secret itself, one run on another station.
fn vault_asked(c : @ui.Ctx, ask : Asked) -> Unit {
  let t = @sf.theme()
  let save = ask.save_kind != ""
  c.box(style=ask_what, fn() {
    let named = fn(n) { @ui.span(n, weight=600, color=t.p.text) }
    let words = fn(w) { @ui.span(w, weight=400, color=t.p.text) }
    let runs = if save {
      fill_named(
        "android-settings.vault.ask.save",
        [("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)), ("name", ask.name)],
        named,
        words,
      )
    } else {
      fill_named("android-settings.vault.ask.use", [("name", ask.name)], named, words)
    }
    let sub = if ask.username != "" { ask.username } else { ask.filename }
    if save && sub != "" {
      runs.push(@ui.span("  " + sub, color=t.p.muted))
    }
    c.rich(runs, style=ask_title) |> ignore
    if !save && ask.command != "" {
      c.rich([@ui.span(ask.command, mono=true)], style=ask_command) |> ignore
    }
    let risky = !save && (ask.mode == "env" || ask.mode == "file")
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
/// An agent's ask as a card says it where it is not a vault's (a station's 共享调试 asked for: @sfbase's
/// adb_link_card), as vault_asked says one: its title the question, 14 on 20, and under it the one line the answer
/// turns on ("" none), 12 and quiet.
pub fn ask_words(c : @ui.Ctx, title : String, note : String) -> Unit {
  let t = @sf.theme()
  c.box(style=ask_what, fn() {
    c.rich([@ui.span(title, weight=600, color=t.p.text)], style=ask_title) |> ignore
    if note != "" {
      c.text(note, style=ask_note) |> ignore
    }
  })
  |> ignore
}

///|
/// Its answer's buttons, as vault_foot lays them last on its card: a line of them, on to a second what has not the room
/// on the first, out in the card's foot corners.
pub fn ask_buttons(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=ask_foot.then(@sf.foot_reach(@sf.button_height(), corner=@sf.ask_corner)), flow=true, line_gap=ask_foot_lines, fn() {
    @sf.foot_buttons(@sf.ask_corner, body)
  })
  |> ignore
}

///|
/// How a request ended (`status`: granted, denied, else expired; `scope`: how long a use was granted), in a line: a dot
/// (green once granted) and 已存入密码 …, 已允许使用 … · 本对话内, 已拒绝使用 ….
pub fn vault_outcome(c : @ui.Ctx, ask : Asked, status : String, scope : String, inline? : Bool = true) -> Unit {
  ask_outcome(c, status == "granted", vault_outcome_words(ask, status, scope), inline~)
}

///|
/// A request's outcome line (vault_outcome's, phone_outcome's): a dot (green once `granted`) and its words.
pub fn ask_outcome(c : @ui.Ctx, granted : Bool, words : Array[@ui.Run], inline? : Bool = true) -> Unit {
  // the dot in the middle of the words' first line, not of all of them (on two lines it stays by the first); under the
  // message's picture, as wide as it, laid over the line as the picture is over its head (message.mbt: inline at the
  // head's start, the words past it where the name is; else out in the margin, the words at the row's start)
  let line = c.sp(c.theme().leading(ask_ended_leading).unwrap_or(c.text_size(ask_ended_size).1))
  c.box(style=ask_ended, fn() {
    c.box(style=if inline { ask_ended_past } else { ask_ended_at }, fn() { c.rich(words, style=ask_ended_words) |> ignore })
    |> ignore
    c.layer(fn() {
      c.box(style=(if inline { ask_dot_line } else { ask_dot_line_out }).then(@ui.style(h=Fixed(line))), fn() {
        c.box(style=if granted { ask_dot_on } else { ask_dot }, fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How a request ended, in words (vault_outcome's): the item's name in the words' strong ink (ended_name), the rest
/// quiet.
pub fn vault_outcome_words(ask : Asked, status : String, scope : String) -> Array[@ui.Run] {
  let save = ask.save_kind != ""
  let scope = if scope == "once" || scope == "hour" { scope } else { "chat" }
  let said = fn(key, args) { fill_named(key, args, ended_name, fn(w) { @ui.span(w) }) }
  match status {
    "granted" if save =>
      said("android-settings.vault.ask.kept", [
        ("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)),
        ("name", ask.name),
      ])
    "granted" => said("android-settings.vault.ask.granted", [("name", ask.name), ("scope", tr("android-settings.vault.scope." + scope))])
    "denied" if save => said("android-settings.vault.ask.notKept", [("name", ask.name)])
    "denied" => said("android-settings.vault.ask.denied", [("name", ask.name)])
    _ => [@ui.span(tr("android-settings.vault.ask.expired"))]
  }
}

///|
/// An item's name in a line saying how its request ended: set apart from the quiet words around it by the strong ink
/// and a heavier weight, not by quotes (the user, 2026-10-30: 「名字不要再用方括号括起来，而是用 GUI 的方式来处理」).
fn ended_name(name : String) -> @ui.Run {
  @ui.span(name, weight=500, color=@sf.theme().p.text)
}

///|
/// The answer to request `request` in workspace `ws` (VaultActions), from the vaults topic (a card from before its
/// station said what it asks, under its post): the buttons while it waits on the viewer (`mine`), or a line where there
/// is no answer to give here (`who`: whose it is); nothing while the topic has not come.
pub fn vault_actions(c : @ui.Ctx, core : Core, ws : String, request : String, mine : Bool, who? : String? = None) -> Unit {
  match topic_answer(core, ws, request, mine, who) {
    Some((a, save, typed)) => vault_foot(c, core, ws, request, a, save, typed~)
    None => ()
  }
}

///|
/// The answer to request `request` in workspace `ws` as `answer` says (`save`: one to keep a secret; `typed`: its secret
/// the person's to type in, its field over them): the buttons (`foot`: last on its card, in the card's foot corners:
/// @sf.foot_reach), or a line where there is none to give here.
/// `extra`: after the buttons (the vault page's 打开对话). Tapped, the button turns till what it did shows: its card saying how it went
/// (the core says so at once), or the request gone from the vault page.
pub fn vault_foot(
  c : @ui.Ctx,
  core : Core,
  ws : String,
  request : String,
  answer : Answer,
  save : Bool,
  typed? : Typed? = None,
  extra? : (() -> Unit)? = None,
  foot? : Bool = false,
) -> Unit {
  let note = fn(words : String) { c.text(words, style=ask_note) |> ignore }
  let lasts = match answer {
    Elsewhere => {
      note(tr("android-settings.vault.approve.inApp"))
      return
    }
    Decided => {
      note(tr("android-settings.vault.approve.decided"))
      return
    }
    Theirs(w) => {
      note(w)
      return
    }
    SetUp => ""
    Approve(l) => l
  }
  let pending = vault_pending.get(request)
  let scopes = if save { ["once"] } else { vault_scopes_up_to(lasts) }
  let scope = match vault_picked.get(request) {
    Some(s) if scopes.contains(s) => s
    _ => scopes[scopes.length() - 1]
  }
  let on = [("workspace", ws), ("request", request)]
  let busy = fn(yes : Bool) {
    pending == Some(yes) || is_doing(core, [if yes { "vault.approve" } else { "vault.deny" }], on)
  }
  let under = pending is Some(_) || is_doing(core, ["vault.approve", "vault.deny"], on)
  let act = fn(yes : Bool, call : String, what : String, params : Json) {
    if core.read_only != "" {
      (core.say)(core.read_only)
      return
    }
    vault_pending[request] = yes
    // (what was typed in is answered: its field goes as the card says how it went, the keyboard with it, not left up
    // over a field no longer there)
    if typed is Some(_) && c.field_focused() {
      c.blur()
    }
    (core.call)(call, params, fn(r) {
      // (gone through, it stays turning till what it did shows: the core says how it went on the card first; what was
      // typed in for it let go)
      match r {
        Err(e) => {
          vault_pending.remove(request)
          (core.say)(fill("android-misc.act.failed", [("what", what), ("error", error_text(e))]))
        }
        Ok(_) => {
          vault_typed.remove(request + "/secret")
          vault_typed.remove(request + "/username")
          vault_files.remove(request)
        }
      }
    })
  }
  // a secret the person types in: its field over the buttons (a login's account first, where the agent named none),
  // its ends where theirs are on a page card (last on it: out in its foot corners)
  let mut secret = ""
  let mut username = ""
  let mut filename = ""
  let mut entered = false
  match (answer, typed) {
    (Approve(_), Some(ty)) =>
      // (reaching out to the foot's corners as the buttons do: a field's ends, a file's button, where theirs are)
      c.box(style=if foot { ask_typed.then(@sf.over_foot_reach(@sf.button_height(), corner=@sf.ask_corner)) } else { ask_typed }, fn() {
        if ty.kind == "login" && ty.username == "" {
          let words = tr("android-settings.vault.ask.typed.username")
          username = @sf.input(c, "vault/" + request + "/username", placeholder=words, disabled=under, solid=true, field=typed_field(request, "/username")).text
        }
        let words = tr("android-settings.vault.ask.typed." + ty.kind)
        if ty.kind == "file" {
          // the system's picker answered: the file it gave (one too big said so, and none kept)
          match vault_file_picks.get(request) {
            Some(p) =>
              if take_picked_file(core, p, fn(content, name) { vault_files[request] = (content, name) }) {
                vault_file_picks.remove(request)
              }
            None => ()
          }
          // (the button the same before and after, the card as wide (it fills its column): what was picked fades in
          // beside it, the row no higher)
          c.box(style=ask_file, fn() {
            if @sf.button(c, words, key="vault/" + request + "/file", tone=Plain, disabled=under) {
              match @ui.pick(Files) {
                Some(p) => vault_file_picks[request] = p
                None => ()
              }
            }
            match vault_files.get(request) {
              Some((content, name)) => {
                secret = content
                filename = name
                let shown = @kit.presence(c, "vault/" + request + "/file/" + name, true).t
                c.rich([@ui.span(name + " · " + file_size(content), color=@sf.alpha(@sf.theme().p.text, shown))], style=ask_file_name)
                |> ignore
              }
              None => ()
            }
          })
          |> ignore
        } else if ty.kind == "ssh_key" {
          secret = @sf.textarea(c, "vault/" + request + "/secret", rows=4, placeholder=words, solid=true, field=typed_field(request, "/secret"))
        } else {
          let f = @sf.input(c, "vault/" + request + "/secret", placeholder=words, secret=true, disabled=under, solid=true, field=typed_field(request, "/secret"))
          secret = f.text
          entered = f.submitted
        }
      })
      |> ignore
    _ => ()
  }
  let empty = typed is Some(_) && secret.trim(chars=" \n\t").to_string() == ""
  // (what goes with the approval: an object, never kept among what the core is doing)
  let given : Json? = match typed {
    Some(_) => {
      let words : Array[(String, Json)] = [("secret", str(secret))]
      if username.trim(chars=" ").to_string() != "" {
        words.push(("username", str(username)))
      }
      if filename != "" {
        words.push(("filename", str(filename)))
      }
      Some(obj(words))
    }
    None => None
  }
  // its buttons, last in the card's foot corners; how long beside them where the line has the room for it, else on a
  // line of its own over them (never under: the buttons keep the foot), its ends where theirs are (over_foot_reach).
  // Whether it has the room: the widths they were laid at, against the card's width inside it (the last frame's; none
  // yet: beside them). Not the foot's own: it is as wide as what is in it, a line short of the room once one goes over
  let room_id = c.id("vault/" + request + "/room")
  let acts_id = c.id("vault/" + request + "/acts")
  let picks = !save && scopes.length() > 1
  let over = picks &&
    (match (c.laid_size(room_id), c.laid_size(acts_id), c.laid_size(c.id("vault/" + request + "/scope"))) {
      (Some((fw, _)), Some((aw, _)), Some((sw, _))) => {
        // (its foot reaching out past the card's words to its corners on a page card: that room the line's too)
        let out = if foot { 2.0 * dmax(0.0, @sf.card_pad - @sf.card_foot_in(@sf.button_height(), corner=@sf.ask_corner)) } else { 0.0 }
        aw + ask_foot_gap + sw > fw + out + 0.5
      }
      _ => false
    })
  let pick = fn() {
    if picks {
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
  }
  let acts = fn() {
    c.box(style=ask_foot, id=acts_id, fn() {
      if answer is SetUp {
        // kept only in a vault that is on here: the way to turn it on first
        if @sf.button(c, tr("android-settings.vault.turnOn"), key="vault/" + request + "/on", tone=Primary) {
          (core.push)(Route::Vault)
        }
      } else {
        let yes = if save { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }
        let pressed = @sf.button(c, tr(yes), key="vault/" + request + "/yes", tone=Primary, busy=busy(true), disabled=under || empty)
        if pressed || (entered && !under && !empty) {
          let what = tr(if save { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" })
          let params : Array[(String, Json)] = [("workspace", str(ws)), ("request", str(request)), ("scope", str(if save { "once" } else { scope }))]
          if given is Some(g) {
            params.push(("typed", g))
          }
          // (told once the frame's builds are over: Enter in the field is seen by the build it came to)
          c.tell("vault/" + request + "/approve", fn() { act(true, "vault.approve", what, obj(params)) })
        }
      }
      let no = if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }
      if @sf.button(c, tr(no), key="vault/" + request + "/no", tone=Ghost, busy=busy(false), disabled=under) {
        act(false, "vault.deny", tr("android-settings.vault.act.denyWhat"), obj([("workspace", str(ws)), ("request", str(request))]))
      }
    })
    |> ignore
  }
  c.box(style=ask_room, id=room_id, fn() {
    if over {
      c.box(style=if foot { ask_over.then(@sf.over_foot_reach(@sf.button_height(), corner=@sf.ask_corner)) } else { ask_over }, pick) |> ignore
    }
    c.box(style=if foot { ask_foot.then(@sf.foot_reach(@sf.button_height(), corner=@sf.ask_corner)) } else { ask_foot }, flow=true, line_gap=ask_foot_lines, fn() {
      @sf.foot_buttons(@sf.ask_corner, fn() {
        acts()
        if !over {
          pick()
        }
        match extra {
          Some(f) => f()
          None => ()
        }
      })
    })
    |> ignore
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
let ask_title : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
/// The command, one line of it, 12 and quiet.
// kept across runs: a value (no field of it changes)
let ask_command : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4_75, color=Muted, wrap=false, max_lines=1, w=Full)

///|
/// A line of what is out of the ordinary, or where there is no answer to give here: 12 and quiet.
// kept across runs: a value (no field of it changes)
let ask_note : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4_75, color=Muted, w=Full)

///|
/// What the person types in, over the answer: its fields 8 apart, the card's width (VaultAsk.css.ts typed).
// kept across runs: a value (no field of it changes)
let ask_typed : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// A file to pick: its name and size, then the button that picks it, 8 apart (VaultAsk.css.ts typedFile).
// kept across runs: a value (no field of it changes)
let ask_file : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ask_file_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// The answer's buttons, 10 apart (pages.css.ts cardFoot).
// kept across runs: a value (no field of it changes)
let ask_foot : @ui.Style = @ui.css("row gap=S2_5 align=ACenter")

///|
/// Between the answer's buttons (ask_foot's gap), to say whether how long has the room beside them.
let ask_foot_gap : Double = 10.0

///|
/// The answer across the card, its width what says whether how long has the room beside the buttons.
// kept across runs: a value (no field of it changes)
let ask_room : @ui.Style = @ui.css("w=Full")

///|
/// How long, on a line of its own over the buttons where it has not the room beside them: the foot's lines apart.
// kept across runs: a value (no field of it changes)
let ask_over : @ui.Style = @ui.css("row mb=S2")


///|
/// Between the foot's lines, where its buttons go on to a second (8).
let ask_foot_lines : Double = 8.0
///|
/// How it ended: a dot and its words, a little under what is over it.
// kept across runs: a value (no field of it changes)
let ask_ended : @ui.Style = @ui.css("w=Full mt=S0_5")

///|
/// Its words inline: past the message's picture, where its name is (message.mbt msg_head_inline).
// kept across runs: a value (no field of it changes)
let ask_ended_past : @ui.Style = @ui.style(w=Full, pl=@sf.message_head_in)

///|
/// Its words with the picture out in the margin: at the row's start, as the name is.
// kept across runs: a value (no field of it changes)
let ask_ended_at : @ui.Style = @ui.css("w=Full")

///|
/// Where the dot stands: as wide as the message's picture (18) and under it, the dot in its middle; as high as a line
/// of the words, the theme's (ask_outcome).
// kept across runs: a value (no field of it changes)
let ask_dot_line : @ui.Style = @ui.css("row w=S4_5 align=ACenter justify=JCenter")

///|
/// The same out in the margin, where the picture is then (message_avatar_out).
// kept across runs: a value (no field of it changes)
let ask_dot_line_out : @ui.Style = ask_dot_line.then(@ui.style(ml=@sf.message_avatar_out))

///|
/// A card's answer's room at its foot (answered_in_place): the card's width, what is in it as far apart as in the card
/// (@sf.card's 14).
// kept across runs: a value (no field of it changes)
let answered_room : @ui.Style = @ui.css("w=Full gap=S3_5")

///|
/// What holds a card's answer and how it went over it (answered_in_place): the card's width.
// kept across runs: a value (no field of it changes)
let answered_whole : @ui.Style = @ui.css("w=Full")

///|
/// How it went over a card's answer's room: its dot and its words on a line in the middle of the room's height.
// kept across runs: a value (no field of it changes)
let answered_over : @ui.Style = @ui.css("row w=Full h=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ask_ended_words : @ui.TextStyle = @ui.text_style(size=ask_ended_size, leading=ask_ended_leading, color=Muted)

///|
/// Its words' size and line (ask_ended_words), the line the dot beside them stands in the middle of.
// kept across runs: a value (no field of it changes)
let ask_ended_size : @ui.TextSize = Meta

///|
// kept across runs: a value (no field of it changes)
let ask_ended_leading : @ui.Leading = L5

///|
/// Its dot, 6 round: green once granted, else quiet.
// kept across runs: a value (no field of it changes)
let ask_dot : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Subtle")

///|
// kept across runs: a value (no field of it changes)
let ask_dot_on : @ui.Style = @ui.css("w=S1_5 h=S1_5 radius=Full bg=Positive")
