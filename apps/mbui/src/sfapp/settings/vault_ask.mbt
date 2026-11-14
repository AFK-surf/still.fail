// An agent's request about a vault item as a card: to use one
// or to keep one ( 申请和授权, agent 存入). One card wherever such a request is answered: in place of the
// agent's post in its chat and among the vault page's waiting requests. A card of words
// (@sf.card): what is asked in its title, the command it is for, a risk only where there is one, and the answer at its
// foot: the answer most give as the one solid button (允许 / 存入), the other beside it (拒绝 / 不存), how long a use is
// allowed a choice beside them that starts at the longest the item is given for (`vault.approve`, `vault.deny`). Only
// the viewer's own request can be answered, and only in an app keeping keys; elsewhere a line says whose it is or where
// it is approved. A secret to keep while the vault is not on on this device: 开启密钥库, to the vault's page. One the
// person types in (the agent has none): its field over the answer (a login's account too, where the agent named none; a
// file, the button that picks it, its name and size once picked), 存入 once something is in it, Enter as 存入; what was
// typed goes only with `vault.approve`, and is let go once it went.

///|
/// What a request's card says: the item's name, how it would be given (`mode`), the command it is
/// for; one to keep a secret, what it is (`save_kind`: login, token, ssh_key, file), its account (a file: its name),
/// and whether the person types it in (`typed`; a file: picks it); another station of the workspace its commands run
/// on, by name (empty: the chat's).
pub(all) struct Asked {
  name : String
  reason : String
  timeout_kind : String
  timeout_seconds : Int
  approved_timeout_kind : String
  approved_timeout_seconds : Int
  mode : String
  command : String
  how_text : String
  save_kind : String
  username : String
  filename : String
  typed : Bool
  /// with `typed`, a service the person signs in to for it instead (slack)
  oauth : String
  station : String
  /// one to rename the item or change its about (secret_describe): its name as it would be (`new_name`), its about
  /// as it would be and as it was (`new_about`, `was_about`)
  describe : Bool
  new_name : String
  new_about : String
  was_about : String
  /// one to delete the item (secret_delete)
  remove : Bool
}

///|
/// Whether what is asked writes the item (one to keep, one to rename): answered once, with no length of use.
pub fn Asked::writes(self : Asked) -> Bool {
  self.save_kind != "" || self.describe || self.remove
}

///|
/// One to rename the item: whether its name would change.
fn Asked::renames(self : Asked) -> Bool {
  self.describe && self.new_name != "" && self.new_name != self.name
}

///|
/// One to rename the item: whether its about would change.
fn Asked::reabouts(self : Asked) -> Bool {
  self.describe && self.new_about != self.was_about
}

///|
/// One to rename the item, its title (the user, 2026-11-12: 「这 ui…是人能看懂的吗」, 「遣词正经一点」): 修改密钥的名称与说明, 修改密钥的名称, or 修改密钥 … 的说明
/// (its name heavier than the words around it), what changes said under it a part each.
fn describe_title_runs(ask : Asked, named : (String) -> @ui.Run, words : (String) -> @ui.Run) -> Array[@ui.Run] {
  if ask.renames() && ask.reabouts() {
    [words(tr("android-settings.vault.ask.describe.both"))]
  } else if ask.renames() {
    [words(tr("android-settings.vault.ask.describe.name"))]
  } else {
    fill_named("android-settings.vault.ask.describe.about", [("name", ask.name)], named, words)
  }
}

///|
/// A part's line as it was (`was`: crossed out, quiet) or as it would be (`strong`: heavier, a name's): each on a line of
/// its own, all of them where the card's words start, so the card has one edge (the user, 2026-11-12:
/// 「感觉视觉上还不够清晰」, 「你这样会导致对齐是错的」).
fn describe_words_runs(was : Bool, words : String, strong? : Bool = false) -> Array[@ui.Run] {
  let t = @sf.theme()
  if was {
    [@ui.span(words, color=t.p.muted, strike=true)]
  } else {
    [@ui.span(words, weight=if strong { 600 } else { 400 }, color=t.p.text)]
  }
}

///|
/// Its name's lines: as it is, then as it would be.
fn describe_name_lines(ask : Asked) -> Array[Array[@ui.Run]] {
  [describe_words_runs(true, ask.name), describe_words_runs(false, ask.new_name, strong=true)]
}

///|
/// Its about's lines: as it was where it said one, then as it would be (that it goes, quiet).
fn describe_about_lines(ask : Asked) -> Array[Array[@ui.Run]] {
  let out = if ask.was_about != "" { [describe_words_runs(true, ask.was_about)] } else { [] }
  if ask.new_about == "" {
    out.push([@ui.span(tr("android-settings.vault.ask.describe.noAbout"), color=@sf.theme().p.muted)])
  } else {
    out.push(describe_words_runs(false, ask.new_about))
  }
  out
}

///|
// kept across runs: a value (no field of it changes)
let ask_describe_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, w=Full)

///|
/// A part of what renaming changes, apart from what is over it by room alone (no ground of its own: the card's one edge
/// for all its words): what it is (名称, 说明), quiet, over its lines.
// kept across runs: a value (no field of it changes)
let ask_describe_part : @ui.Style = @ui.css("w=Full gap=S0_5 pt=S3")

///|
/// A secret to keep that the person types in here (`save.typed`: the agent has none): its kind, and the account the
/// agent named (empty: a login's is asked for too).
pub(all) struct Typed {
  kind : String
  username : String
  /// a service the person signs in to for it in place of typing it in (slack: `vault_oauth_of`), "" none
  oauth : String
}

///|
/// The secret to type in of request `save` (its `save`), or None where it is not the person's to type.
pub fn typed_of(save : Json?) -> Typed? {
  if flag(save, "typed") {
    Some({ kind: text(save, "kind"), username: text(save, "username"), oauth: text(save, "oauth") })
  } else {
    None
  }
}

///|
/// The secret to type in of what is asked, or None.
fn Asked::typed_in(self : Asked) -> Typed? {
  if self.typed {
    Some({ kind: self.save_kind, username: self.username, oauth: self.oauth })
  } else {
    None
  }
}

///|
/// The request whose length-of-use menu is open (empty: none); put back by `reset`.
let vault_menu : Ref[String] = Ref("")

///|
/// The scope's menu of request `key` open, or closed where it is the one open.
fn vault_menu_set(key : String, on : Bool) -> Unit {
  if on {
    vault_menu.val = key
  } else if vault_menu.val == key {
    vault_menu.val = ""
  }
}

///|
/// Which request's scope menu is open now ("" none).
pub fn vault_menu_open() -> String {
  vault_menu.val
}

///|
/// Whether what is asked is a file the person picks: its card fills its column, as wide before the file is picked as
/// after.
fn Asked::picks_file(self : Asked) -> Bool {
  self.typed && self.save_kind == "file"
}

///|
/// The length of use picked for each request (a rig's, a phone's too, keyed `rig/<id>`, `phone/<id>`): read by what is
/// made once of a card as by the old view's; put back by `reset`.
let vault_picked : @sf.LiveMap[String, String] = @sf.LiveMap::new()

///|
/// How long each requested timeout is chosen to be, in minutes (授权时限's): read by what is made once of a card as by
/// the old view's; put back by `reset`.
let vault_timeout_minutes : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
// kept across runs: an immutable style
let vault_timeout_panel : @ui.Style = @ui.css("w=Full gap=S4")

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
/// only till it went with `vault.approve`. Put back by `reset`.
let vault_files : @sf.LiveMap[String, (String, String)] = @sf.LiveMap::new()

///|
fn vault_ask_reset() -> Unit {
  vault_menu.val = ""
  vault_timeout_minutes.clear()
  vault_picked.clear()
  vault_pending.clear()
  vault_typed.clear()
  vault_files.clear()
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
/// How a request is answered here, what its card's foot is.
#derive(Eq, Debug)
pub(all) enum Answer {
  /// 允许 / 存入 and 拒绝 / 不存: a use given for as long as `lasts` at the longest (unused for a secret to keep)
  Approve(String)
  /// a secret to keep while this device's vault is not on: 开启密钥库, to the vault's page, first
  SetUp
  /// approved only in an app that keeps keys (a web page keeps none)
  Elsewhere
  /// a secret to keep its station sealed to the person's devices set up then, this one not among them: approved on
  /// one of those (or here once the station has this device's certificate and seals it again)
  NotHere
  /// decided already, its card not saying so yet
  Decided
  /// another's to answer: whose (the card's 由…决定)
  Theirs(String)
}

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
    "notHere" => NotHere
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
  // (one to rename the item is answered as one to keep: written into the vault, by a device set up)
  let save = field(row, "save") is Some(_) || field(row, "describe") is Some(_) || flag(row, "remove")
  let typed = typed_of(field(row, "save"))
  if save && !flag(view, "plain") && !flag(view, "setUp") {
    Some((SetUp, save, typed))
  } else if save && flag(row, "notHere") {
    Some((NotHere, save, typed))
  } else {
    Some((Approve(text(row, "lasts")), save, typed))
  }
}

///|
/// Request `request` in workspace `ws` as a card, from the vaults topic (the vault page's waiting requests): what is
/// asked, and its answer at the foot (`mine`, `who`, `extra` as vault_actions').
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
  let answer = topic_answer(core, ws, request, mine, who)
  @sf.card(c, fill=ask.picks_file(), fn() {
    vault_asked(c, ask)
    match answer {
      Some((a, save, _)) => vault_foot(c, core, ws, request, a, save, typed=ask.typed_in(), timeout_kind=ask.timeout_kind, timeout_seconds=ask.timeout_seconds, extra~, foot=a is (Approve(_) | SetUp), describe=ask.describe, remove=ask.remove)
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
  @sf.card(c, fill=ask.picks_file(), fn() {
    vault_asked(c, ask)
    answered_in_place(c, "vault/" + request, ended.map(fn(e) { (e.0 == "granted", vault_outcome_words(ask, e.0, e.1)) }), fn() {
      vault_foot(c, core, ws, request, answer, ask.writes(), typed=ask.typed_in(), timeout_kind=ask.timeout_kind, timeout_seconds=ask.timeout_seconds, foot=answer is (Approve(_) | SetUp), describe=ask.describe, remove=ask.remove)
    })
  })
  |> ignore
}

///|
/// A card's answer at its foot (`answer`), answered while the card shows (`ended`: whether it was granted, and how it
/// went in words): its answer fades out where it is (answered_fade_ms, Leave), only drawn, then how it went fades in
/// after it over the room it leaves, its dot and its words in the middle of it. The answer stays laid out (unseen):
/// the card keeps its size to the point. In a chat's list the card itself goes as its room closes from the moment it
/// was decided, one line in its place (sfpages' decision.mbt vault_ask_card, Turns::in_turn).
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
  @sf.card(c, fn() { vault_asked(c, ask) }) |> ignore
}

///|
/// The request's original contents without its card or its answer, for a read-only history panel.
pub fn vault_ask_details(c : @ui.Ctx, ask : Asked) -> Unit {
  vault_asked(c, ask, full_command=true)
}

///|
/// What is asked (AskCard's what): its title (使用 …, 存入密码 … and the account; the item's name in it heavier than the
/// words around it, not in quotes), the command, and only what is
/// out of the ordinary: a command that reads the secret itself, one run on another station.
fn vault_asked(c : @ui.Ctx, ask : Asked, full_command? : Bool = false) -> Unit {
  let t = @sf.theme()
  let save = ask.save_kind != ""
  c.box(style=@sf.ask_what, fn() {
    let named = fn(n) { @ui.span(n, weight=600, color=t.p.text) }
    let words = fn(w) { @ui.span(w, weight=400, color=t.p.text) }
    let runs = if ask.remove {
      fill_named("android-settings.vault.ask.remove", [("name", ask.name)], named, words)
    } else if ask.describe {
      describe_title_runs(ask, named, words)
    } else if save {
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
    if ask.oauth != "" {
      // (one the person signs in to a service for: its mark, what it connects and the item's name, in place of the
      // title; vault_ask_node's vault_oauth_head_node)
      c.box(style=vault_oauth_head, fn() {
        @sf.drawable(c, ask.oauth, vault_oauth_mark) |> ignore
        c.box(style=vault_oauth_words, fn() {
          c.text(tr("web-pages.vault.oauth.card.title." + ask.oauth), style=vault_oauth_title) |> ignore
          c.text(ask.name, style=@sf.ask_note) |> ignore
        })
        |> ignore
      })
      |> ignore
    } else {
      c.rich(runs, style=@sf.ask_title) |> ignore
    }
    if ask.reason != "" {
      c.text(ask.reason, style=@sf.ask_note) |> ignore
    }
    if ask.oauth != "" {
      // (what signing in lets agents do, and that it stays theirs: vault_oauth_gives_node's)
      c.box(style=vault_oauth_gives, fn() {
        for line in vault_oauth_lines {
          let (icon, key) = line
          c.box(style=vault_oauth_give, fn() {
            c.box(style=vault_oauth_give_icon, fn() { @sf.icon(c, icon, size=vault_oauth_glyph, color=t.p.muted) |> ignore }) |> ignore
            c.text(tr("web-pages.vault.oauth.card." + key + "." + ask.oauth), style=vault_oauth_give_words) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    }
    if ask.command != "" {
      c.rich([@ui.span(ask.command, mono=true)], style=if full_command { @sf.ask_note } else { ask_command }, breaks=full_command) |> ignore
    }
    // (one to rename: what changes, a part each, in place of how it is given)
    if ask.renames() {
      c.box(style=ask_describe_part, fn() {
        c.text(tr("android-settings.vault.ask.describe.nameLabel"), style=@sf.ask_note) |> ignore
        for runs in describe_name_lines(ask) {
          c.rich(runs, style=ask_describe_words) |> ignore
        }
      })
      |> ignore
    }
    if ask.reabouts() {
      c.box(style=ask_describe_part, fn() {
        c.text(tr("android-settings.vault.ask.describe.aboutLabel"), style=@sf.ask_note) |> ignore
        for runs in describe_about_lines(ask) {
          c.rich(runs, style=ask_describe_words) |> ignore
        }
      })
      |> ignore
    }
    if ask.how_text != "" && !ask.describe && !ask.remove && ask.oauth == "" {
      c.text(ask.how_text, style=@sf.ask_note) |> ignore
    }
    let risky = !ask.writes() && (ask.mode == "env" || ask.mode == "file")
    let elsewhere = ask.station != ""
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
      c.rich(runs, style=@sf.ask_note) |> ignore
    }
  })
  |> ignore
}

///|
/// How a request ended (`status`: granted, denied, else expired; `scope`: how long a use was granted), in a line: a dot
/// (green once granted) and 已存入密码 …, 已允许使用 … · 本对话内, 已拒绝使用 ….
pub fn vault_outcome(c : @ui.Ctx, ask : Asked, status : String, scope : String, inline? : Bool = true, history? : (String, (Int) -> Unit)? = None) -> Unit {
  ask_outcome(c, status == "granted", vault_outcome_words(ask, status, scope), inline~, history~)
}

///|
/// A request's outcome line (vault_outcome's, phone_outcome's): a dot (green once `granted`) and its words.
pub fn ask_outcome(c : @ui.Ctx, granted : Bool, words : Array[@ui.Run], inline? : Bool = true, history? : (String, (Int) -> Unit)? = None) -> Unit {
  // the dot in the middle of the words' first line, not of all of them (on two lines it stays by the first); under the
  // message's picture, as wide as it, laid over the line as the picture is over its head (message.mbt: inline at the
  // head's start, the words past it where the name is; else out in the margin, the words at the row's start)
  let line = c.sp(c.theme().leading(ask_ended_leading).unwrap_or(c.text_size(ask_ended_size).1))
  c.box(style=ask_ended, fn() {
    let base_style = if inline { ask_ended_past } else { ask_ended_at }
    c.box(style=if history is Some(_) { base_style.then(ask_ended_start) } else { base_style }, fn() {
      match history {
        Some((key, show)) => {
          let id = @sf.ask_history_trigger(c, key, words, ask_ended_words, line)
          show(id)
        }
        None => c.rich(words, style=ask_ended_words) |> ignore
      }
    })
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
    "withdrawn" => [@ui.span(tr("android-settings.vault.ask.withdrawn"))]
    "granted" if ask.remove => said("android-settings.vault.ask.removed", [("name", ask.name)])
    "denied" if ask.remove => said("android-settings.vault.ask.notRemoved", [("name", ask.name)])
    "granted" if ask.describe => said("android-settings.vault.ask.changed", [("name", ask.name)])
    "denied" if ask.describe => said("android-settings.vault.ask.notChanged", [("name", ask.name)])
    "granted" if save =>
      said("android-settings.vault.ask.kept", [
        ("kind", tr("android-settings.vault.ask.kind." + ask.save_kind)),
        ("name", ask.name),
      ])
    "granted" if ask.approved_timeout_seconds > 0 => {
      let days = ask.approved_timeout_seconds % 86400 == 0
      let hours = ask.approved_timeout_seconds % 3600 == 0
      let n = if days { ask.approved_timeout_seconds / 86400 } else if hours { ask.approved_timeout_seconds / 3600 } else { ask.approved_timeout_seconds / 60 }
      let time = fill(if days { "android-settings.vault.timeout.nDays" } else if hours { "android-settings.vault.timeout.nHours" } else { "android-settings.vault.timeout.nMinutes" }, [("n", n.to_string())])
      let how = fill("android-settings.vault.timeout.approved." + ask.approved_timeout_kind, [("time", time)])
      said("android-settings.vault.ask.granted", [("name", ask.name), ("scope", how)])
    }
    "granted" if ask.timeout_seconds > 0 && scope != "once" => said("android-settings.vault.ask.timedGranted", [("name", ask.name)])
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
  let row = items(vaults_of(core, ws), "requests").iter().find_first(fn(r) { text(Some(r), "id") == request })
  match topic_answer(core, ws, request, mine, who) {
    Some((a, save, typed)) => vault_foot(c, core, ws, request, a, save, typed~, timeout_kind=text(row, "timeoutKind"), timeout_seconds=count(row, "timeoutSeconds"), describe=field(row, "describe") is Some(_), remove=flag(row, "remove"))
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
  timeout_kind? : String = "",
  timeout_seconds? : Int = 0,
  extra? : (() -> Unit)? = None,
  foot? : Bool = false,
  describe? : Bool = false,
  remove? : Bool = false,
) -> Unit {
  let note = fn(words : String) { c.text(words, style=@sf.ask_note) |> ignore }
  let lasts = match answer {
    Elsewhere => {
      note(tr("android-settings.vault.approve.inApp"))
      return
    }
    NotHere => {
      note(tr("web-pages.vault.approve.notHere"))
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
  let timed = !save && timeout_seconds > 0
  let scopes = if save { ["once"] } else if timed { if lasts == "once" { ["once"] } else { ["once", "idle", "fixed"] } } else { vault_scopes_up_to(lasts) }
  let scope = match vault_picked.get(request) {
    Some(s) if scopes.contains(s) => s
    _ => if timed && scopes.contains(timeout_kind) { timeout_kind } else { scopes[scopes.length() - 1] }
  }
  let on = [("workspace", ws), ("request", request)]
  let busy = fn(yes : Bool) {
    pending == Some(yes) || is_doing(core, [if yes { "vault.approve" } else { "vault.deny" }], on)
  }
  let under = pending is Some(_) || is_doing(core, ["vault.approve", "vault.deny"], on)
  let max_minutes = if lasts == "hour" { 60 } else { 43200 }
  let asked_minutes = (timeout_seconds + 59) / 60
  let initial_minutes = if asked_minutes < max_minutes { asked_minutes } else { max_minutes }
  let minutes = vault_timeout_minutes.get(request).unwrap_or(initial_minutes)
  let valid_time = !timed || scope == "once" || (minutes > 0 && minutes <= max_minutes)
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
  // (one the person signs in to a service for in place of typing it: that service, "" none)
  let signs_in = match typed {
    Some(ty) => ty.oauth
    None => ""
  }
  match (answer, typed) {
    (Approve(_), Some(ty)) if ty.oauth == "" =>
      // (reaching out to the foot's corners as the buttons do: a field's ends, a file's button, where theirs are)
      @sf.card_foot_words(on=foot, fn() {
        c.box(style=if foot { ask_typed.then(@sf.over_foot_reach(@sf.button_height())) } else { ask_typed }, fn() {
          if ty.kind == "login" && ty.username == "" {
            let words = tr("android-settings.vault.ask.typed.username")
            username = @sf.input(c, "vault/" + request + "/username", placeholder=words, disabled=under, solid=true, field=typed_field(request, "/username")).text
          }
          let words = tr("android-settings.vault.ask.typed." + ty.kind)
          if ty.kind == "file" {
            // (the button the same before and after, the card as wide (it fills its column): what was picked fades in
            // beside it, the row no higher)
            c.box(style=ask_file, fn() {
              @sf.button(c, words, key="vault/" + request + "/file", tone=Plain, disabled=under, on_press=fn() {
                pick_vault_file(core, fn(content, name) { vault_files[request] = (content, name) })
              })
              match vault_files.get(request) {
                Some((content, name)) => {
                  secret = content
                  filename = name
                  // (faded in as it is drawn)
                  let shown = @kit.presence(c, "vault/" + request + "/file/" + name, true).t
                  let i = c.rich([@ui.span(name + " · " + file_size(content), color=@sf.theme().p.text)], style=ask_file_name)
                  c.look_by(i, fn() { @ui.look(alpha=@sf.dmax(0.0, @sf.dmin(1.0, shown.get(c)))) })
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
      })
    _ => ()
  }
  let empty = typed is Some(_) && signs_in == "" && secret.trim(chars=" \n\t").to_owned() == ""
  // (what goes with the approval: an object, never kept among what the core is doing)
  let given : Json? = match typed {
    Some(_) => {
      let words : Array[(String, Json)] = [("secret", str(secret))]
      if username.trim(chars=" ").to_owned() != "" {
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
        let out = if foot { 2.0 * dmax(0.0, @sf.card_pad - @sf.card_foot_in(@sf.button_height())) } else { 0.0 }
        aw + ask_foot_gap + sw > fw + out + 0.5
      }
      _ => false
    })
  let pick = fn() {
    if picks && timed {
      let words = if scope == "once" { tr("android-settings.vault.scope.once") } else {
        let days = minutes % 1440 == 0
        let hours = minutes % 60 == 0
        let duration = fill(if days { "android-settings.vault.timeout.nDays" } else if hours { "android-settings.vault.timeout.nHours" } else { "android-settings.vault.timeout.nMinutes" }, [("n", (if days { minutes / 1440 } else if hours { minutes / 60 } else { minutes }).to_string())])
        fill("android-settings.vault.timeout.button." + scope, [("time", duration)])
      }
      let open_panel = fn() {
        vault_timeout_open(request, minutes, max_minutes, scope)
      }
      @sf.chooser(c, "vault/" + request + "/scope", words, [], fn() { false }, fn(on) { if on { open_panel() } }, disabled=under) |> ignore
    } else if picks {
      let entries = scopes.map(fn(s) { @kit.menu_radio(s, s == scope, label=tr("android-settings.vault.scope." + s)) })
      let m = @sf.chooser(c, "vault/" + request + "/scope", tr("android-settings.vault.scope." + scope), entries, fn() { vault_menu.val == request }, fn(on) { vault_menu_set(request, on) })
      match m.chosen {
        Some(s) => { vault_picked[request] = s; vault_menu.val = "" }
        None => ()
      }
    }
  }
  let acts = fn() {
    c.box(style=@sf.ask_foot, id=acts_id, fn() {
      if answer is SetUp {
        // kept only in a vault that is on here: the way to turn it on first
        @sf.button(c, tr("android-settings.vault.turnOn"), key="vault/" + request + "/on", tone=Primary, on_press=fn() {
          (core.push)(Route::Vault)
        })
      } else {
        let yes = if signs_in != "" { "web-pages.vault.oauth.signIn." + signs_in } else if remove { "android-settings.vault.act.remove" } else if describe { "android-settings.vault.act.change" } else if save { "android-settings.vault.act.save" } else { "android-settings.vault.act.allow" }
        let approve = fn() {
          // (存入 by signing in to the service: its page in the browser, the request approved with the token as it
          // comes back; given up, the buttons again)
          if signs_in != "" {
            if core.read_only != "" {
              (core.say)(core.read_only)
              return
            }
            vault_pending[request] = true
            (core.vault_oauth)(ws, "", signs_in, request, fn(res) {
              match res {
                Ok(_) => ()
                Err(why) => {
                  vault_pending.remove(request)
                  if why != "cancelled" {
                    (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.vault.act.saveWhat")), ("error", if why == "" { tr("web-pages.vault.oauth.failed") } else { why })]))
                  }
                }
              }
            })
            return
          }
          let what = tr(if remove { "android-settings.vault.act.removeWhat" } else if describe { "android-settings.vault.act.changeWhat" } else if save { "android-settings.vault.act.saveWhat" } else { "android-settings.vault.act.allowWhat" })
          let chosen_scope = if !timed || scope == "once" { if save { "once" } else { scope } } else if minutes <= 60 { "hour" } else { "chat" }
          let params : Array[(String, Json)] = [("workspace", str(ws)), ("request", str(request)), ("scope", str(chosen_scope))]
          if timed && scope != "once" {
            params.push(("timeout", obj([("kind", str(scope)), ("seconds", Json::number((minutes * 60).to_double()))])))
          }
          if given is Some(g) {
            params.push(("typed", g))
          }
          act(true, "vault.approve", what, obj(params))
        }
        @sf.button(c, tr(yes), key="vault/" + request + "/yes", tone=if remove { DangerSolid } else { Primary }, busy=busy(true), disabled=under || empty || !valid_time, on_press=approve)
        if entered && !under && !empty && valid_time {
          // (told once the frame's builds are over: Enter in the field is seen by the build it came to)
          c.tell("vault/" + request + "/approve", approve)
        }
      }
      let no = if remove { "android-settings.vault.act.dontRemove" } else if describe { "android-settings.vault.act.dontChange" } else if save { "android-settings.vault.act.dontSave" } else { "android-settings.vault.act.deny" }
      @sf.button(c, tr(no), key="vault/" + request + "/no", tone=Ghost, busy=busy(false), disabled=under, on_press=fn() {
        act(false, "vault.deny", tr("android-settings.vault.act.denyWhat"), obj([("workspace", str(ws)), ("request", str(request))]))
      })
    })
    |> ignore
  }
  @sf.card_foot_words(on=foot, fn() {
    c.box(style=ask_room, id=room_id, fn() {
      if over {
        c.box(style=if foot { ask_over.then(@sf.over_foot_reach(@sf.button_height())) } else { ask_over }, pick) |> ignore
      }
      c.box(style=if foot { @sf.ask_foot.then(@sf.foot_reach(@sf.button_height())) } else { @sf.ask_foot }, flow_reverse=true, line_gap=@sf.ask_foot_lines(), fn() {
        acts()
        if !over {
          pick()
        }
        match extra {
          Some(f) => f()
          None => ()
        }
      })
      |> ignore
    })
    |> ignore
  })
}

///|
/// The workspace's vaults as the core has them (`vaults`: its requests, whether keys are kept here).
fn vaults_of(core : Core, ws : String) -> Json? {
  (core.topic)("vaults", { "workspace": str(ws) }).get().value
}

///|
/// The command, one line of it, 12 and quiet.
// kept across runs: a value (no field of it changes)
let ask_command : @ui.TextStyle = @ui.text_style(size=Caption, leading=L4_75, color=Muted, wrap=false, max_lines=1, w=Full)

///|
/// What the person types in, over the answer: its fields 8 apart, the card's width.
// kept across runs: a value (no field of it changes)
let ask_typed : @ui.Style = @ui.css("w=Full gap=S2")

///|
/// A file to pick: its name and size, then the button that picks it, 8 apart.
// kept across runs: a value (no field of it changes)
let ask_file : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let ask_file_name : @ui.TextStyle = @ui.text_style(size=Ui, leading=L5, color=Fg, wrap=false, w=Cut)

///|
/// Between the answer's buttons (@sf.ask_foot's gap), to say whether how long has the room beside them.
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
// kept across runs: a value (no field of it changes)
let ask_ended_start : @ui.Style = @ui.css("align=AStart")

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

///|
/// The length of use of request `request` chosen in a panel (授权时限, a form: in the window's middle, a sheet with a
/// finger), as `minutes` (at most `max_minutes`) and `scope` (once, idle, fixed) say it now: 时长, one of the presets or
/// 自定义 (its minutes or hours typed, the unit at the head's end: a choice of the two, what is typed turned into the
/// other as it is chosen); 失效方式 (idle or fixed) where it is not once. 完成 keeps them for the card (vault_picked,
/// vault_timeout_minutes), not pressed while what is typed is out of bounds. What it holds nodes of the window's tree,
/// made once as it opens (@sf.panel_nodes), its choices signals of its own: what it shows as 完成 closes it is what it
/// shows on its way out.
fn vault_timeout_open(request : String, minutes : Int, max_minutes : Int, scope : String) -> Unit {
  let same = fn(a : String, b : String) { a == b }
  let unit = @signals.signal(if minutes % 60 == 0 { "hours" } else { "minutes" }, same~)
  let field = @ui.Field::new(text=(if minutes % 60 == 0 { minutes / 60 } else { minutes }).to_string())
  // (what the field holds, as it is typed and as it is put in it here: what binds reads this)
  let typed = @signals.signal(field.text(), same~)
  let chosen = @signals.signal(if scope == "fixed" { "fixed" } else { "idle" }, same~)
  let duration = @signals.signal(if scope == "once" { "once" } else { minutes.to_string() }, same~)
  let duration_words = fn(n : Int) -> String {
    let days = n % 1440 == 0
    let hours = n % 60 == 0
    fill(if days { "android-settings.vault.timeout.nDays" } else if hours { "android-settings.vault.timeout.nHours" } else { "android-settings.vault.timeout.nMinutes" }, [("n", (if days { n / 1440 } else if hours { n / 60 } else { n }).to_string())])
  }
  let presets = [60, 1440, 2160, 10080, 43200]
  let values = presets.filter(fn(n) { n <= max_minutes && n != minutes && (presets.contains(minutes) || n != 2160) })
  values.push(minutes)
  values.sort()
  let options = [("once", tr("android-settings.vault.scope.once"))]
  for n in values {
    options.push((n.to_string(), duration_words(n)))
  }
  options.push(("custom", tr("android-settings.vault.timeout.custom")))
  // (what is typed in minutes, as the unit it is in says: none where it is longer than five figures)
  let typed_minutes = fn(words : String, u : String) {
    if words.length() > 5 { 0 } else { int_of(words, 0) * (if u == "hours" { 60 } else { 1 }) }
  }
  @sf.panel_nodes(
    tr("android-settings.vault.timeout.title"),
    from=Unanchored,
    form=true,
    fn(v, _) {
      v.box(fn(b) {
        @sf.style_node(b, fn() { @sf.panel_words_in_node(b).then(vault_timeout_panel) })
        @sf.field_node(b, fn() { tr("android-settings.vault.timeout.duration") }, fn(f) {
          @sf.select_node(f, fn() { duration.get() }, fn() { options }, fn(x) { duration.set(x) }, label=fn() {
            tr("android-settings.vault.timeout.duration")
          })
        })
        b.show(fn() { duration.get() == "custom" }, fn(s) {
          @sf.field_node(
            s,
            fn() { tr("android-settings.vault.timeout.custom") },
            fn(f) {
              @sf.input_node(f, field, label=tr("android-settings.vault.timeout.custom"), solid=true, edited=fn(w) {
                typed.set(w)
              })
              |> ignore
            },
            aside=fn(a) {
              @sf.chooser_node(
                a,
                fn() { tr("android-settings.vault.timeout." + unit.get()) },
                fn() { ["hours", "minutes"].map(fn(u) { (u, tr("android-settings.vault.timeout." + u)) }) },
                fn() { unit.get() },
                fn(u) {
                  let was = unit.untracked()
                  if u != was {
                    let current = typed_minutes(field.text(), was)
                    field.set(if u == "hours" && current % 60 != 0 { "" } else { (if u == "hours" { current / 60 } else { current }).to_string() })
                    typed.set(field.text())
                    unit.set(u)
                  }
                },
              )
              |> ignore
            },
          )
        })
        b.show(fn() { duration.get() != "once" }, fn(s) {
          @sf.field_node(s, fn() { tr("android-settings.vault.timeout.method") }, fn(f) {
            for k in ["idle", "fixed"] {
              @sf.choice_row_node(
                f,
                fn() { tr("android-settings.vault.timeout." + k) },
                fn() { chosen.get() == k },
                note=fn() { tr("android-settings.vault.timeout.detail." + k) },
                press=fn() { chosen.set(k) },
              )
            }
          })
        })
      })
      |> ignore
    },
    foot=fn(v, close) {
      let n = fn() { if duration.get() == "custom" { typed_minutes(typed.get(), unit.get()) } else { int_of(duration.get(), 0) } }
      let once = fn() { duration.get() == "once" }
      @sf.button_node(
        v,
        fn() { tr("android-settings.vault.timeout.done") },
        fn() {
          let o = once()
          vault_picked[request] = if o { "once" } else { chosen.untracked() }
          if !o {
            vault_timeout_minutes[request] = @signals.untracked(n)
          }
          close()
        },
        tone=Primary,
        disabled=fn() { !once() && (n() < 1 || n() > max_minutes) },
      )
      |> ignore
    },
  )
}
