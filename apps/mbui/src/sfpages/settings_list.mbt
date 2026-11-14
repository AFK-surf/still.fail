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
/// A group of the list's rows, a heading over it where it has one; `key`, which group it is, whatever rows it has now
/// and whatever language its heading is in.
pub(all) struct SettingsPart {
  key : String
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
/// The settings' list as it stands, in its order, as the core says it, built in `c` (settings_parts_of: the bottom bar's
/// row as `c`'s window has the bar, what is kept as asked of the core now).
pub fn settings_parts(c : @ui.Ctx, core : Core, here : @settings.Here) -> Array[SettingsPart] {
  settings_parts_of(core, here, bars=@sfbase.bars_shown(c), kept=@settings.kept_said(c, core))
}

///|
/// The settings' list as it stands, in its order, as the core says it: the topics its rows read are those the pages
/// they open read. `bars`: whether the window has the bottom bar; `kept`: what 本机缓存's row says (@settings.kept_said,
/// or kept_told: as last read, nothing asked of the core for it, what reads it asking: kept_ask).
fn settings_parts_of(core : Core, here : @settings.Here, bars~ : Bool, kept~ : String) -> Array[SettingsPart] {
  let w = @settings.workspace_view(core, here).value
  let stations = match @settings.stations_of(core, here).value {
    Some(Array(a)) => Some(a)
    _ => None
  }
  let connects = (core.topic)("connects", { "scope": Json::string(here.workspace), "mine": Json::boolean(false) }).get().value
  let lock = (core.topic)("lock", { "workspace": Json::string(here.workspace) }).get().value
  let vaults = (core.topic)("vaults", { "workspace": Json::string(here.workspace) }).get().value
  let profiles = (core.topic)("profiles", { "scope": Json::string(here.workspace) }).get().value
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
    key: "who",
    heading: "",
    rows: [
      { route: Me, key: "me", lead: Person, title: me, line: here.email, value: "", bad: false, dot: false },
      {
        route: Workspace,
        key: "workspace",
        lead: Space(text(w, "emoji"), text(w, "icon")),
        title: if w is Some(_) { text(w, "name") } else { here.name },
        // (its line held before the workspace is read, a space: the row as tall as it will be, nothing under it moved
        // when it is said; its tile no taller than its words then, the ladder's inset over and under it)
        line: if w is Some(_) { @settings.role_label(role) + " · " + people } else { "\u{00A0}" },
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
  parts.push({ key: "access", heading: "", rows: access })
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
    key: "run",
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
    key: "work",
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
  let prefs = (core.topic)("prefs", Map([])).get().value
  let theme = match @settings.appearance(prefs) {
    "light" => @sf.t("android-settings.theme.light")
    "dark" => @sf.t("android-settings.theme.dark")
    _ => @sf.t("android-settings.theme.system")
  }
  // notifications as the core's `notify` says, or as switched while `notify.set` is out; refused by the system, in red
  let notify = (core.topic)("notify", Map([])).get().value
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
  if bars {
    device.push(settings_row(BarSettings, "bars", "view-columns", @sf.t("android-misc.bar.title"), value=@settings.bars_value(core)))
  }
  let platform = @ui.platform()
  if platform == 0 || platform == 3 || platform == 5 {
    device.push(settings_row(Shortcuts, "shortcuts", "keyboard", @sf.t("web-pages.settings.nav.shortcuts")))
  }
  if @settings.local_station_managed() {
    device.push(settings_row(LocalStation, "local-station", "monitor", @sf.t("web-pages.localStation.title")))
  }
  // 共享调试: on a phone its switch and which chats it is lent to; on every app, which chats were allowed, how long a
  // grant lasts, and the devices that approve it (their own page under 安全 of before, gone: the user, 2026-11-10, to
  // people there is one safe mode). Not the web's: a page signs nothing
  if platform != 4 {
    device.push(settings_row(AdbShare(""), "adb", "phone", @sf.t("android-misc.adb.title")))
  }
  device.push(settings_row(KeptFiles, "files", "disk", @sf.t("android-settings.files.title"), value=kept))
  parts.push({ key: "device", heading: @sf.t("android-settings.home.device"), rows: device })
  // 关于: this build, or the newer one there is
  let v = (core.version_now)()
  parts.push({
    key: "about",
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
    AdbShare(_) => AdbShare("")
    Station(_) => Stations
    Profile(_, _) | NewProfile(_) | ProfileAccount(_) => Profiles("")
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
/// The search belongs to the settings list as it moves between a page and a sidebar. Its field follows edits and is
/// kept while a result is open, so going back to the list does not lose the search.
let settings_search_field : @ui.Field = @ui.Field::new()

///|
pub fn settings_search_reset() -> Unit {
  settings_search_field.set("")
}

///|
/// The same field over the list in either frame, as the chats' search over their list is (search.mbt
/// search_field_ground): a round ground of its own with the search mark, as tall as the theme's band, no outline.
/// While it holds words, clearing them is a press at its end, inside it. Its words as far in as where its list stands
/// (`at`) has them (band_pad_in).
pub fn settings_search(c : @ui.Ctx, at : @sf.ListAt) -> Unit {
  let t = @sf.theme()
  let l = t.chat_list
  let pad = @sf.band_pad_in(at)
  let (size, line) = c.text_size(Ui)
  // (its end's room the clear press's while it holds words: round in the round ground's end, concentric)
  let held = settings_search_field.text() != ""
  let end = if held { @sf.room_of(0.0) } else { @sf.room_of(pad) }
  c.box(style=settings_search_ground.then(@ui.style(h=Fixed(l.band_h), pl=@sf.room_of(pad), pr=end)), fn() {
    @sf.icon(c, "search", size=l.band_icon, color=t.p.muted) |> ignore
    c.box(style=settings_search_grow, fn() {
      c.editor(
        "settings/search",
        placeholder=@sf.t("web-pages.settings.search"),
        font_size=size,
        max_lines=1,
        plain=true,
        line~,
        color=t.p.text,
        placeholder_color=t.p.subtle,
        caret_color=t.p.accent,
        field=settings_search_field,
      )
      |> ignore
    })
    |> ignore
    if held {
      @sf.icon_button(
        c,
        "close",
        key="settings/search/clear",
        size=l.band_h,
        icon_size=l.band_icon,
        round=true,
        label=@sf.t("android-misc.drive.pick.filterClear"),
        on_press=fn() {
          settings_search_field.set("")
          settings_search_field.focus()
        },
      )
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let settings_search_ground : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter radius=Full").then(@ui.style(bg=@sf.search_ground))

///|
// kept across runs: a value (no field of it changes)
let settings_search_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let settings_search_page : @ui.Style = @ui.css("w=Full pb=S3 clip=true")

///|
/// The same search control (settings_search's) as nodes, over the settings' list made once: its round ground as tall as
/// the theme's band, the search mark, the field, and while it holds words the clear key at its end, inside the ground,
/// as round as it; 12 under it. Its field an editor of its own (a Field is one editor's: the list made once while
/// another of it still leaves, the sidebar's old one), what it holds the list's words (settings_search_field: kept as a
/// result is opened, the sidebar's the same), each told the other's as they change.
fn settings_search_node(parent : @view.View) -> Unit {
  let own = @ui.Field::new(text=@signals.untracked(fn() { settings_search_field.text() }))
  let held = fn() { own.text() != "" }
  parent.box(fn(page) {
    @sf.style_node(page, fn() { settings_search_page })
    page.reacts(fn() { own.text() }, fn(w) { settings_search_field.set(w) })
    page.reacts(fn() { settings_search_field.text() }, fn(w) {
      if @signals.untracked(fn() { own.text() }) != w {
        own.set(w)
      }
    })
    page.box(fn(g) {
      // (its end's room the clear key's while it holds words: round in the round ground's end, concentric)
      @sf.style_node(g, fn() {
        // (a page across the whole screen, a phone's: its words as far in as there, band_pad_in)
        let l = @sf.theme().chat_list
        let pad = @sf.band_pad_in(Whole)
        let end = if held() { @sf.room_of(0.0) } else { @sf.room_of(pad) }
        settings_search_ground.then(@ui.style(h=Fixed(l.band_h), pl=@sf.room_of(pad), pr=end))
      })
      @sf.icon_node(g, "search", @sf.theme().chat_list.band_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      @ui.field(
        g,
        own,
        placeholder_by=fn() { @sf.t("web-pages.settings.search") },
        max_lines=1,
        enter_sends=true,
        size_by=fn() { @sf.theme().t.ui },
        line=@signals.untracked(fn() { @sf.theme().t.ui_line }),
        colors_by=fn() {
          let p = @sf.theme().p
          (p.text, p.subtle, p.accent)
        },
      )
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
      g.show(held, fn(k) {
        let l = @signals.untracked(fn() { @sf.theme().chat_list })
        @sf.icon_button_node(
          k,
          "close",
          fn() { @sf.t("android-misc.drive.pick.filterClear") },
          fn() {
            own.set("")
            own.focus()
          },
          size=l.band_h,
          icon_size=l.band_icon,
        )
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// Searchable settings below a list row. A result names its parent and opens the page that owns the setting; entries
/// with their own page go there directly. Only children of rows actually offered in this frame are considered.
fn settings_search_children(row : SettingsRow, core : Core) -> Array[SettingsRow] {
  let entries : Array[(String, String, @settings.Route)] = match row.key {
    "me" => [
      ("account", @sf.t("android-settings.me.title"), Me),
      ("devices", @sf.t("web-pages.settings.account.sessions"), Me),
      ("sign-out", @sf.t("android-settings.me.signOutOnly"), Me),
      ("delete-account", @sf.t("android-settings.me.delete"), Me),
    ]
    "workspace" => [
      ("workspace", @sf.t("android-settings.workspace.title"), Workspace),
      ("name", @sf.t("android-settings.workspace.name"), Workspace),
      ("members", @sf.t("android-settings.members.title"), Workspace),
    ]
    "security" => [("signing", @sf.t("web-pages.security.signing"), Security)]
    "vault" => [("all", @sf.t("web-pages.vault.all"), VaultItems)]
    "decisions" => [("completion", @sf.t("web-pages.automaticDecisions.completion"), AutoCompletion)]
    "archiving" => [
      ("suggest", @sf.t("web-pages.appearance.archive.title"), Archiving),
      ("automatic", @sf.t("web-pages.archiving.auto.title"), Archiving),
    ]
    "appearance" => {
      let a : Array[(String, String, @settings.Route)] = [
        ("theme", @sf.t("web-pages.appearance.theme.title"), Appearance),
        ("accent", @sf.t("web-pages.appearance.accent.title"), Appearance),
        ("fonts", @sf.t("web-pages.appearance.fonts.title"), Fonts),
        ("motion", @sf.t("web-pages.appearance.motion.title"), Appearance),
        ("haptics", @sf.t("web-pages.appearance.haptics.title"), Appearance),
        ("language", @sf.t("common.language"), Appearance),
      ]
      if @ui.window_zoom_supported() {
        a.push(("zoom", @sf.t("desktop.menu.zoom"), Appearance))
      }
      if @ui.takes_drops() {
        a.push(("drop", @sf.t("web-pages.appearance.drop.title"), Appearance))
      }
      a
    }
    "notifications" => [
      ("ways", @sf.t("web-pages.notifications.ways.title"), Notifications),
      ("kinds", @sf.t("web-pages.notifications.kinds.title"), Notifications),
      ("preview", @sf.t("web-pages.notifications.preview"), Notifications),
      ("permissions", @sf.t("web-pages.settings.nav.permissions"), Permissions),
    ]
    "about" => {
      let a : Array[(String, String, @settings.Route)] = [
        ("version", @sf.t("web-pages.settings.nav.version"), About),
        ("changelog", @sf.t("web-pages.settings.nav.changelog"), Changelog),
        ("terms", @sf.t("common.legal.terms"), About),
        ("privacy", @sf.t("common.legal.privacy"), About),
      ]
      if (core.reporting)() is Some(_) {
        a.push(("telemetry", @sf.t("common.telemetry.title"), About))
      }
      if @ui.platform() != 4 {
        a.push(("dht", @sf.t("web-pages.about.dht.title"), About))
      }
      a
    }
    _ => []
  }
  entries.map(fn(e) {
    let lead = match row.lead {
      Person => Icon("user")
      Space(_, _) => Icon("users")
      lead => lead
    }
    { route: e.2, key: "find/" + row.key + "/" + e.0, lead, title: e.1, line: row.title, value: row.title, bad: false, dot: false }
  })
}

///|
/// Every word must be present, case independently. A child must match one word itself: searching a parent's name
/// alone shows that row, not every setting under it. Its parent may supply the other words.
fn settings_search_matches(row : SettingsRow, query : String, child : Bool) -> Bool {
  let own = row.title.to_lower()
  let all = (own + " " + row.line).to_lower()
  let mut own_match = false
  for word in query.split(" ") {
    let word = word.to_owned()
    if word == "" {
      continue
    }
    if !all.contains(word) {
      return false
    }
    if own.contains(word) {
      own_match = true
    }
  }
  !child || own_match
}

///|
fn settings_found(parts : Array[SettingsPart], core : Core, query : String) -> Array[SettingsPart] {
  if query == "" {
    return parts
  }
  let found : Array[SettingsPart] = []
  for part in parts {
    let rows : Array[SettingsRow] = []
    for row in part.rows {
      if settings_search_matches(row, query, false) {
        rows.push(row)
      }
      for child in settings_search_children(row, core) {
        if settings_search_matches(child, query, true) {
          rows.push(child)
        }
      }
    }
    if !rows.is_empty() {
      found.push({ key: part.key, heading: part.heading, rows })
    }
  }
  found
}

///|
/// The list as a sidebar's (beside the settings' pages on a medium or large screen): the same rows in the same groups,
/// a sidebar's rows (the theme's side_row, as its other rows of one line), the room of a heading between two groups
/// with none. `lit`: the row of the page beside it. `at`: where the list stands (a side column, the tape's).
pub fn settings_side_rows(
  c : @ui.Ctx,
  core : Core,
  here : @settings.Here,
  lit : @settings.Route?,
  open : (@settings.Route) -> Unit,
  at : @sf.ListAt,
) -> Unit {
  let t = @sf.theme()
  let query = settings_search_field.text().trim(chars=" \t\n\r").to_owned().to_lower()
  let parts = settings_found(settings_parts(c, core, here), core, query)
  if parts.is_empty() && query != "" {
    c.box(style=settings_search_empty, fn() { c.text(@sf.t("common.noMatch"), style=@sf.secondary) |> ignore }) |> ignore
  }
  for k, part in parts {
    if part.heading != "" {
      @sf.list_heading(c, part.heading, at)
    } else if k > 0 {
      @sf.list_apart(c)
    }
    for i, row in part.rows {
      let key = "settings-nav/" + row.key
      let id = c.id(key)
      let selected = if row.key.has_prefix("find/") { lit == Some(row.route) } else { lit.map(settings_row_of) == Some(row.route) }
      let ground = @sf.nav_ground_by(c, key, c.lit(id) || c.pressed(id), selected)
      // (a sidebar's row of one line, as its others are: its mark, its words, how things stand at its end, left out
      // where the row has not the room: its words whole till then, cut only where they alone have not)
      let draw = fn() {
        let look = @sf.side_row_at(at).then(settings_side_across).then(@sf.row_least_h())
        let n = c.box(style=look, id~, fn() {
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
        // (its ground eased as it is painted)
        c.bg_by(n, ground)
        n
      }
      let b = if i + 1 < part.rows.length() {
        let mut b = 0
        c.box(style=@sf.list_more(at), fn() { b = draw() }) |> ignore
        b
      } else {
        draw()
      }
      c.semantics(b, Link, id~, label=row.title)
      c.on_press(id, fn() {
        open(row.route)
      })
    }
  }
}

///|
// kept across runs: a value (no field of it changes)
let settings_search_empty : @ui.Style = @ui.css("w=Full px=S3 py=S4")

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
      c.box(style=@sf.row_tile(c).then(@ui.style(bg=Data(if picture { t.p.card } else { t.p.chip }))), fn() {
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
/// A sidebar row's mark's side (ICON's 16).
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


///|
/// The list as a page of its own made once as nodes (the gear's on a small screen) in node `v`: who
/// is signed in and the workspace on cards of their own, each group on its card under its heading. The page's frame
/// and how far it is scrolled kept whatever changes; its cards and their rows each a node of its own by its group's key
/// and its own, come, gone and in their order as the core says which there are (security mode where the
/// workspace has none, the bottom bar's where the window has one), what each says (a heading, a row's words and how
/// things stand at its end) followed as it changes, in the language as it is. What a row is by: its icon; the account's
/// picture and the workspace's mark old views, hosted (settings_lead). `open`: a row pressed, its page. `here`: who
/// and where, as that changes. `bars`: whether the window has the bottom bar (the shell's to say), as that changes. `stint`: the page's time on top
/// (its stack's entry's), what a picture is asked for on.
pub fn settings_home_node(
  v : @view.View,
  core : Core,
  here : () -> @settings.Here,
  open : (@settings.Route) -> Unit,
  on_back~ : () -> Unit,
  frame~ : () -> PageFrame,
  bars~ : () -> Bool,
  stint~ : () -> Int,
) -> Unit {
  // (the bottom bar's row where the shell says the window has the bar, as that changes; what is kept asked of the core as
  // it is asked to be read again, not as the list is worked out)
  let query = fn() { settings_search_field.text().trim(chars=" \t\n\r").to_owned().to_lower() }
  let parts = @signals.computed(fn(_) {
    settings_found(settings_parts_of(core, here(), bars=bars(), kept=@settings.kept_told()), core, query())
  })
  v.reacts(fn() { @settings.kept_asked() }, fn(_) { @settings.kept_ask(core) })
  // (its cards: each by its group's key (the account's and the workspace's by their rows'), its heading, its rows' keys; the account and the workspace each a card of
  // their own, as large as who and where they are)
  let cards = fn() -> Array[(String, String, Array[String])] {
    let out = []
    for part in parts.get() {
      let identity = part.rows.iter().any(fn(r) { !(r.lead is Icon(_)) })
      let groups = if identity { part.rows.map(fn(r) { [r] }) } else { [part.rows] }
      for i, rows in groups {
        if rows.length() > 0 {
          // (a card by its group's key; the account's and the workspace's each by its own row's too)
          let id = if identity { part.key + "/" + rows[0].key } else { part.key }
          out.push((id, if i == 0 { part.heading } else { "" }, rows.map(fn(r) { r.key })))
        }
      }
    }
    out
  }
  let card_of = fn(id : String) { cards().search_by(fn(c) { c.0 == id }).map(fn(i) { cards()[i] }) }
  let row_of = fn(key : String) -> SettingsRow? {
    for p in parts.get() {
      for r in p.rows {
        if r.key == key {
          return Some(r)
        }
      }
    }
    None
  }
  let blocks = fn() -> Array[String] {
    let all = ["settings-search"]
    let found = cards()
    if found.is_empty() && query() != "" {
      all.push("settings-search-empty")
    }
    for card in found {
      all.push(card.0)
    }
    all
  }
  @sf.page_node(v, fn() { @sf.t("android-settings.title") }, on_back=fn() { settings_search_reset(); on_back() }, frame~, blocks, fn(
    block,
    id,
  ) {
    if id == "settings-search" {
      settings_search_node(block)
    } else if id == "settings-search-empty" {
      @sf.page_note_node(block, fn() { @sf.t("common.noMatch") })
    } else {
      let heading = fn() { card_of(id).map(fn(c) { c.1 }).unwrap_or("") }
      block.show(fn() { heading() != "" }, fn(h) { @sf.heading_node(h, heading) })
      @sf.group_node(block, fn(g) {
        g.each(fn() { card_of(id).map(fn(c) { c.2 }).unwrap_or([]) }, fn(k) { k }, fn(rb, key) {
          let key = key.untracked()
          settings_row_node(rb, core, here, key, row_of, open, stint)
        })
      })
    }
  })
}

///|
/// The settings' list's row `key` in node `v` (settings_home_node's): what it says as row_of has it now; what it is by
/// as settings_lead draws it, as nodes: its icon; the account's picture (on the page's time on top, `stint`), else its
/// initial; the workspace's mark (a picture put up filling its square, else its glyph or emoji in it, else its first
/// letter).
fn settings_row_node(
  v : @view.View,
  core : Core,
  here : () -> @settings.Here,
  key : String,
  row_of : (String) -> SettingsRow?,
  open : (@settings.Route) -> Unit,
  stint : () -> Int,
) -> Unit {
  let row = fn() { row_of(key) }
  let said = fn(f : (SettingsRow) -> String) { fn() { row().map(f).unwrap_or("") } }
  let shown = @signals.untracked(row)
  let lead : @sf.RowLead = match shown.map(fn(r) { r.lead }) {
    Some(Icon(name)) => LeadIcon(name)
    Some(Person) =>
      LeadMade(fn(l) {
        @sf.avatar_node(l, fn() { here().email }, said(fn(r) { r.title }), fn() {
          let p = here().picture
          if p == "" { "" } else { (core.picture)(p, stint()) }
        }, @sf.identity_mark)
      })
    Some(Space(_, _)) => LeadTile(fn(l) { settings_space_node(l, row, stint) })
    None => NoLead
  }
  @sf.link_row_node(
    v,
    said(fn(r) { r.title }),
    fn() {
      match @signals.untracked(row) {
        Some(r) => open(r.route)
        None => ()
      }
    },
    value=said(fn(r) { if r.key.has_prefix("find/") { "" } else { r.value } }),
    value_bad=fn() { row().map(fn(r) { r.bad }).unwrap_or(false) },
    value_dot=fn() { row().map(fn(r) { r.dot }).unwrap_or(false) },
    note=said(fn(r) { r.line }),
    strong=shown.map(fn(r) { !(r.lead is Icon(_)) }).unwrap_or(false),
    note_cut=shown.map(fn(r) { r.lead is Space(_, _) }).unwrap_or(false),
    lead~,
  )
}

///|
/// The workspace's mark on its row (settings_lead's Space, as nodes) in `parent`: in its square (workspace_tile), a
/// picture put up filling it on the card's ground; else on the chips' ground one of still.fail's icons or an emoji, 26,
/// else its first letter, muted; each as `row` says it now.
fn settings_space_node(parent : @view.View, row : () -> SettingsRow?, stint : () -> Int) -> Unit {
  let mark = fn() {
    match row() {
      Some({ lead: Space(emoji, icon), title, .. }) => (emoji, icon, title)
      _ => ("", "", "")
    }
  }
  let picture = fn() {
    let icon = mark().1
    icon.has_prefix("https://") || icon.has_prefix("http://") || icon.has_prefix("data:image/")
  }
  parent.box(fn(t) {
    let side = @sf.row_tile_side_node(parent, t)
    t
    .width(By(side))
    .height(By(side))
    .radius(By(fn() { @ui.tree_theme().corner(@sf.small_radius) }))
    // (the row's lead tile (LeadTile): the ladder's inset (8) from its start, top and foot, concentric with its corners
    // there, the small block's 10)
    .clips(Is(true))
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ground(By(fn() {
      let p = @sf.theme().p
      if picture() { p.card } else { p.chip }
    }))
    |> ignore
    let ink = fn() { @sf.theme().p.text }
    t.show(picture, fn(p) {
      @sf.station_mark_node(p, fn() { mark().0 }, fn() { mark().1 }, @sf.identity_mark, ink, stint)
    })
    t.show(fn() { !picture() && @sf.has_station_mark(mark().0, mark().1) }, fn(p) {
      @sf.station_mark_node(p, fn() { mark().0 }, fn() { mark().1 }, @sf.workspace_tile_mark, ink, stint)
    })
    t.show(fn() { !picture() && !@sf.has_station_mark(mark().0, mark().1) }, fn(l) {
      l
      .words(By(fn() { @sf.initial(mark().2) }))
      .words_look(By(fn() { @ui.style_words(@sf.workspace_letter) }))
      .ink(By(fn() { @ui.style_ink(@sf.workspace_letter) }))
      |> ignore
    })
  })
  |> ignore
}
