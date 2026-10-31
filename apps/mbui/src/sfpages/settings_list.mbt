// The settings' list, one for every frame: the page the gear opens on a small screen (SettingsHome.kt, the web's
// mobile/Settings.tsx), and the sidebar beside the settings' pages on a medium or large one (the web's SettingsNav). One
// list in one order, read once here: who is signed in and the workspace in view; then the workspace's, in small groups
// (who may reach what: security mode and the vault; where its agents run: its stations, connects and profiles; how its
// agents work: what they decide by themselves, what they remember, when chats are archived, what they used); then this
// device's (how it looks, whether it notifies, its bottom bar, its keys, its own station, what it keeps); then 关于.
// Each row has its icon and says how things stand at its end, what is wrong in red, so the list is worth a look before
// anything is opened. Station, 连接, Profile and 用量 are among them wherever the rail has them too: the settings are one
// more way to them, not where they live (the user, 2026-10-15). What a page holds that has a page of its own elsewhere
// (更新日志 in 关于, the system's permission in 通知) is not a row of its own.

///|
/// What a row of the settings' list is by: one of still.fail's line icons, the account's picture, the workspace's mark
/// (its emoji, its icon).
pub(all) enum SettingsLead {
  Icon(String)
  Person
  Space(String, String)
}

///|
/// A row of the settings' list: the page it opens, its key, what it is by, its name, the line under it (the account's
/// and the workspace's), how things stand at its end (`bad` in red; `dot`, a red dot before it: something there is not
/// right, nothing wrong to say).
pub(all) struct SettingsRow {
  route : @settings.Route
  key : String
  lead : SettingsLead
  title : String
  line : String
  value : String
  bad : Bool
  dot : Bool
}

///|
/// A group of the list's rows, a heading over it where it has one.
pub(all) struct SettingsPart {
  heading : String
  rows : Array[SettingsRow]
}

///|
fn settings_row(
  route : @settings.Route,
  key : String,
  icon : String,
  title : String,
  value? : String = "",
  bad? : Bool = false,
  dot? : Bool = false,
) -> SettingsRow {
  { route, key, lead: Icon(icon), title, line: "", value, bad, dot }
}

///|
/// The settings' list as it stands, in its order, as the core says it: the topics its rows read are those the pages
/// they open read.
pub fn settings_parts(c : @ui.Ctx, core : Core, here : @settings.Here) -> Array[SettingsPart] {
  let w = @settings.workspace_view(core, here).value
  let stations = match @settings.stations_of(core, here).value {
    Some(Array(a)) => Some(a)
    _ => None
  }
  let connects = (core.topic)("connects", { "scope": Json::string(here.workspace), "mine": Json::boolean(false) }).value
  let lock = (core.topic)("lock", { "workspace": Json::string(here.workspace) }).value
  let vaults = (core.topic)("vaults", { "workspace": Json::string(here.workspace) }).value
  let profiles = (core.topic)("profiles", { "scope": Json::string(here.workspace) }).value
  let parts : Array[SettingsPart] = []
  // who is signed in, the workspace in view
  let me = if here.person != "" { here.person } else { here.email }
  let role = text(w, "role")
  let members = items(w, "members").length()
  let waiting = items(w, "added").length() + items(w, "invitations").length()
  let people = if (role == "owner" || role == "admin") && waiting > 0 {
    @sf.t("android-settings.members.waiting", args=[("n", members.to_string()), ("waiting", waiting.to_string())])
  } else {
    @sf.t("android-settings.members.count", args=[("n", members.to_string())])
  }
  parts.push({
    heading: "",
    rows: [
      { route: Me, key: "me", lead: Person, title: me, line: here.email, value: "", bad: false, dot: false },
      {
        route: Workspace,
        key: "workspace",
        lead: Space(text(w, "emoji"), text(w, "icon")),
        title: if w is Some(_) { text(w, "name") } else { here.name },
        line: if w is Some(_) { @settings.role_label(role) + " · " + people } else { "" },
        value: "",
        bad: false,
        dot: false,
      },
    ],
  })
  // who may reach what: security mode where the workspace has it (still.fail's always; taken out only where the core
  // says there is none, so the rows under it never move up a row while looked at), and the vault
  let access : Array[SettingsRow] = []
  if lock is None || flag(lock, "available") {
    let attention = count(lock, "attention")
    let said = if lock is None {
      ""
    } else if !flag(lock, "locked") {
      @sf.t("web-mobile.settings.securityOff")
    } else if attention > 0 {
      @sf.t("web-mobile.settings.securityWaiting", args=[("n", attention.to_string())])
    } else {
      @sf.t("web-mobile.settings.securityOn")
    }
    access.push(settings_row(Security, "security", "shield-check", @sf.t("web-pages.security.title"), value=said, bad=attention > 0))
  }
  access.push(
    settings_row(Vault, "vault", "key", @sf.t("android-settings.vault.title"), value=text(vaults, "statusText"), bad=flag(vaults, "statusBad")),
  )
  parts.push({ heading: "", rows: access })
  // where its agents run: its stations, the chats' ways in, the agents' accounts (as many as their list has, those
  // that need a look as the core counts them)
  let online = match stations {
    Some(a) => a.filter(fn(x) { flag(Some(x), "online") }).length()
    None => 0
  }
  let short = count(profiles, "attention")
  let mut failing = 0
  for x in items(connects, "items") {
    if text(field(Some(x), "connect"), "presence") == "error" {
      failing += 1
    }
  }
  parts.push({
    heading: "",
    rows: [
      settings_row(
        Stations,
        "stations",
        "server",
        "Station",
        value=match stations {
          Some(a) => @sf.t("android-settings.home.online", args=[("online", online.to_string()), ("total", a.length().to_string())])
          None => ""
        },
        dot=match stations {
          Some(a) => online < a.length()
          None => false
        },
      ),
      settings_row(
        Connects(""),
        "connects",
        "im",
        @sf.t("android-settings.connects.title"),
        value=if connects is None {
          ""
        } else if failing > 0 {
          @sf.t("android-settings.home.failing", args=[("n", failing.to_string())])
        } else {
          @sf.t("android-settings.count", args=[("n", items(connects, "items").length().to_string())])
        },
        bad=failing > 0,
      ),
      settings_row(
        Profiles(""),
        "profiles",
        "quota",
        "Profile",
        value=if profiles is None {
          ""
        } else if short > 0 {
          @sf.t("android-settings.home.short", args=[("n", short.to_string())])
        } else {
          @sf.t("android-settings.count", args=[("n", items(profiles, "items").length().to_string())])
        },
        bad=short > 0,
      ),
    ],
  })
  // how its agents work
  parts.push({
    heading: "",
    rows: [
      settings_row(AutoDecisions, "decisions", "check", @sf.t("web-pages.automaticDecisions.title")),
      settings_row(Memories, "memory", "brain", @sf.t("android-settings.memory")),
      settings_row(Archiving, "archiving", "archive", @sf.t("web-pages.archiving.title")),
      settings_row(Usage, "usage", "chart", @sf.t("android-settings.home.usage")),
    ],
  })
  // this device's: what there is of it here (the bottom bar where the window has one, 2026-10-26: 「为啥中型屏会有这个
  // 设置」; the keys, this computer's station a computer's)
  let prefs = (core.topic)("prefs", Map::new()).value
  let theme = match @settings.appearance(prefs) {
    "light" => @sf.t("android-settings.theme.light")
    "dark" => @sf.t("android-settings.theme.dark")
    _ => @sf.t("android-settings.theme.system")
  }
  // notifications as the core's `notify` says, or as switched while `notify.set` is out; refused by the system, in red
  let notify = (core.topic)("notify", Map::new()).value
  let on = match @settings.notify_switched.get() {
    Some(v) => v
    None => notify is None || flag(notify, "on")
  }
  let refused = text(notify, "permission") == "denied"
  let device : Array[SettingsRow] = [
    settings_row(Appearance, "appearance", "sliders", @sf.t("android-settings.appearance.title"), value=theme),
    settings_row(
      Notifications,
      "notifications",
      "bell",
      @sf.t("web-pages.settings.nav.notifications"),
      value=if refused {
        @sf.t("web-pages.permissions.state.denied")
      } else if on {
        @sf.t("web-pages.notifications.on")
      } else {
        @sf.t("web-pages.notifications.off")
      },
      bad=refused,
    ),
  ]
  if @sfbase.bars_shown(c) {
    device.push(settings_row(BarSettings, "bars", "view-columns", @sf.t("android-misc.bar.title"), value=@settings.bars_value(core)))
  }
  let platform = @ui.platform()
  if platform == 0 || platform == 3 || platform == 5 {
    device.push(settings_row(Shortcuts, "shortcuts", "command", @sf.t("web-pages.settings.nav.shortcuts")))
  }
  if platform == 0 {
    device.push(settings_row(LocalStation, "local-station", "monitor", @sf.t("web-pages.localStation.title")))
  }
  // 共享调试, the phone's (docs/adb-share.md): its page says which chats it is lent to
  if platform == 2 {
    device.push(settings_row(AdbShare(""), "adb", "phone", @sf.t("android-misc.adb.title")))
  }
  device.push(settings_row(KeptFiles, "files", "disk", @sf.t("android-settings.files.title"), value=@settings.kept_said(c, core)))
  parts.push({ heading: @sf.t("android-settings.home.device"), rows: device })
  // 关于: this build, or the newer one there is
  let v = (core.version_now)()
  parts.push({
    heading: "",
    rows: [
      settings_row(
        About,
        "about",
        "info",
        @sf.t("web-pages.settings.nav.about"),
        value=if v.ready != "" {
          @sf.t("android-settings.version.update", args=[("version", v.ready)])
        } else {
          @settings.build_version()
        },
      ),
    ],
  })
  parts
}

///|
/// The row of the list a settings page is under (lit beside it): a page under one of them, that one's.
pub fn settings_row_of(r : @settings.Route) -> @settings.Route {
  match r {
    Fonts => Appearance
    SecurityOpen => Security
    VaultItems | VaultItem(_, _) => Vault
    AdbShare("") => AdbShare("")
    Station(_) | AdbShare(_) => Stations
    Profile(_, _) | PickModels(_, _) | ProfileModels(_, _) | NewProfile(_) | ProfileAccount(_) => Profiles("")
    Connects(_) | Connect(_, _) | RunSettings(_, _) => Connects("")
    Memory(_) | MemoryDoc(_, _, _) => Memories
    AutoCompletion | AutoPolicy(_) => AutoDecisions
    StationArchiving(_) => Archiving
    UsagePrices(_) => Usage
    Permissions => Notifications
    Changelog => About
    KeptChat(_, _) => KeptFiles
    r => r
  }
}

///|
/// The list as a page of its own (a small screen's, the gear's): who is signed in and the workspace on cards of their
/// own, each group on its card under its heading. `open`: a row pressed, its page.
pub fn settings_blocks(c : @ui.Ctx, core : Core, here : @settings.Here, open : (@settings.Route) -> Unit) -> Array[() -> Unit] {
  let parts = settings_parts(c, core, here)
  let blocks : Array[() -> Unit] = []
  for part in parts {
    let identity = part.rows.iter().any(fn(r) { !(r.lead is Icon(_)) })
    // (the account and the workspace each a card of its own, as large as who and where they are)
    let cards = if identity { part.rows.map(fn(r) { [r] }) } else { [part.rows] }
    for i, rows in cards {
      let heading = if i == 0 { part.heading } else { "" }
      blocks.push(fn() {
        if heading != "" {
          @sf.heading(c, heading)
        }
        @sf.group(c, fn() {
          for row in rows {
            if @sf.link_row(
                c,
                "settings/" + row.key,
                row.title,
                value=row.value,
                value_bad=row.bad,
                value_dot=row.dot,
                note=row.line,
                strong=!(row.lead is Icon(_)),
                lead=fn() { settings_lead(c, core, here, row, false) },
              ) {
              open(row.route)
            }
          }
        })
      })
    }
  }
  blocks
}

///|
/// The list as a sidebar's (beside the settings' pages on a medium or large screen): the same rows in the same groups,
/// a sidebar's rows (the theme's side_row, as its other rows of one line), the room of a heading between two groups
/// with none. `lit`: the row of the page beside it.
pub fn settings_side_rows(
  c : @ui.Ctx,
  core : Core,
  here : @settings.Here,
  lit : @settings.Route?,
  open : (@settings.Route) -> Unit,
) -> Unit {
  let t = @sf.theme()
  let parts = settings_parts(c, core, here)
  for k, part in parts {
    if part.heading != "" {
      @sf.list_heading(c, part.heading, Side)
    } else if k > 0 {
      @sf.list_apart(c)
    }
    for i, row in part.rows {
      let key = "settings-nav/" + row.key
      let id = c.id(key)
      let ground = @sf.nav_ground(c, key, c.lit(id) || c.pressed(id), lit == Some(row.route))
      // (a sidebar's row of one line, as its others are: its mark, its words, how things stand at its end, left out
      // where the row has not the room: its words whole till then, cut only where they alone have not)
      let draw = fn() {
        let look = t.chat_list.side_row.then(settings_side_across).then(@sf.row_least_h())
        c.box(style=look.then(@ui.style(bg=Data(ground))), id~, fn() {
          settings_lead(c, core, here, row, true)
          c.box(style=settings_side_words, keep=true, fn() {
            c.text(row.title, style=t.chat_list.title.then(settings_side_title), keep=true) |> ignore
          })
          |> ignore
          if row.value != "" {
            c.box(style=settings_side_end, drop=1, fn() {
              if row.dot {
                @sf.status_dot(c, "error")
              }
              let said = t.chat_list.last.then(settings_side_said)
              c.text(row.value, style=if row.bad { said.then(@sf.bad) } else { said }) |> ignore
            })
            |> ignore
          }
        })
      }
      let b = if i + 1 < part.rows.length() {
        let mut b = 0
        c.box(style=@sf.list_more(Side), fn() { b = draw() }) |> ignore
        b
      } else {
        draw()
      }
      c.semantics(b, Link, id~, label=row.title)
      if c.clicked(id) {
        open(row.route)
      }
    }
  }
}

///|
/// What a row is by. On a page's row, its line icon in the muted ink, the account's picture, the workspace's mark (its
/// letter where it has none), the two as large as their cards have them. In a sidebar row, a line icon in its mark's
/// column (16 across) as every other row there has (the account's a person's, the workspace's people's): what fills
/// that column whole would stand in the row's rounded end off its corner (the corner ladder).
fn settings_lead(c : @ui.Ctx, core : Core, here : @settings.Here, row : SettingsRow, side : Bool) -> Unit {
  let t = @sf.theme()
  match (row.lead, side) {
    (Icon(name), _) =>
      @sf.icon(c, name, size=if side { settings_side_mark } else { @sf.row_icon }, color=t.p.muted) |> ignore
    (Person, true) => @sf.icon(c, "user", size=settings_side_mark, color=t.p.muted) |> ignore
    (Space(_, _), true) => @sf.icon(c, "users", size=settings_side_mark, color=t.p.muted) |> ignore
    (Person, false) => @settings.avatar(c, core, here.email, row.title, @sf.identity_mark, picture=here.picture)
    (Space(emoji, icon), false) => {
      let w : Workspace = { id: here.workspace, name: row.title, emoji, icon, email: here.email }
      // a picture put up fills the square; one of still.fail's icons or an emoji on the chips' ground; else its first
      // letter, muted, as the rail has it
      let picture = icon.has_prefix("https://") || icon.has_prefix("http://") || icon.has_prefix("data:image/")
      c.box(style=@sf.workspace_tile.then(@ui.style(bg=Data(if picture { t.p.card } else { t.p.chip }))), fn() {
        if picture {
          @sf.station_mark(c, emoji, icon, @sf.identity_mark, t.p.text)
        } else {
          workspace_mark(c, w, @sf.workspace_tile_mark, t.p.text, @sf.workspace_letter)
        }
      })
      |> ignore
    }
  }
}

///|
/// A sidebar row's mark's side (the rows' icons': SidebarList.css.ts mark, ICON's 16).
let settings_side_mark : Double = 16.0

///|
/// A sidebar row's mark, words and what is at its end, across its middle.
// kept across runs: a value (no field of it changes)
let settings_side_across : @ui.Style = @ui.css("align=ACenter")

///|
/// A sidebar row's words: what the row leaves its mark and what is at its end (settings_side_rows).
// kept across runs: a value (no field of it changes)
let settings_side_words : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let settings_side_title : @ui.TextStyle = @ui.text_style(w=Cut)

///|
// kept across runs: a value (no field of it changes)
let settings_side_end : @ui.Style = @ui.css("row gap=S1_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let settings_side_said : @ui.TextStyle = @ui.text_style(w=Hug)

