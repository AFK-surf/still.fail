// Settings from the gear (app/screens/SettingsHome.kt SettingsScreen): who is signed in and the workspace in view, each
// a card; then the workspace's in small groups (security and the vault; its stations, connects and profiles; its
// agents' automatic decisions, memory and usage), then this device's (how it looks, its bar, its notifications, what it
// keeps), then 关于 (AboutScreen: this build, the changelog, the reports, the terms). Each row has its icon, and says how
// things stand at its end, what is wrong in red. And how this device shows still.fail (AppearanceScreen), and the
// account (Me.kt).

///|
/// A page of the settings, by its route: call for the page the app's stack shows. `root`: a place of the bottom
/// bar's at the stack's root (PlacePage.kt), under the app's own top bar, so without its compact one. `top`: where
/// that bar is over the page rather than above it, how far down what it shows starts (it scrolls under the bar).
pub fn page(
  c : @ui.Ctx,
  core : Core,
  here : Here,
  route : Route,
  root? : Bool = false,
  top? : Double = 0.0,
) -> Unit {
  frame(core, here, root~, top~)
  // the wide frame's words as the web's settings pages size them (their rows 13, what is under them 12, a section's
  // title 14): the scale's body (Lg), secondary (Sm) and values (Base) taken down there, every page's words with them,
  // and Xl2 (Android's back, 17, which these pages never say) the web's body for a section's title (the desktop's own
  // pages, ported from the web's, are src/sfdesk's, in the library's sizes)
  if wide.val {
    let t = c.theme()
    c.with_theme({ ..t, text: { ..t.text, lg: wide_body, sm: wide_small, base: wide_body, xl2: wide_heading } }, fn() {
      route_page(c, core, here, route)
    })
  } else {
    route_page(c, core, here, route)
  }
}

///|
/// What a page of the settings is drawn in (`page`'s, and the desktop's own pages', src/sfdesk): its core, where it
/// stands, the sheet a fixture's mode puts up over it.
pub fn frame(core : Core, here : Here, root? : Bool = false, top? : Double = 0.0) -> Unit {
  frame_core.val = Some(core)
  at_root.val = root
  root_top.val = if root { top } else { 0.0 }
  left_core.val = Some(core)
  fixture_sheet(core, here)
}

///|
/// The wide frame's body words (the web's text-ui: 13 on 20) and what is under them (text-meta: 12 on 18).
let wide_body : (Double, Double) = (13.0, 20.0)

///|
let wide_small : (Double, Double) = (12.0, 18.0)

///|
/// A section's title in the wide frame (the web's text-body: 14 on 22).
let wide_heading : (Double, Double) = (14.0, 22.0)

///|
fn route_page(c : @ui.Ctx, core : Core, here : Here, route : Route) -> Unit {
  match route {
    Home => settings_home(c, core, here)
    Me => me_page(c, core, here)
    Appearance => appearance_page(c, core)
    Fonts => fonts_page(c, core)
    Workspace => workspace_page(c, core, here)
    Security => security_page(c, core, here)
    Vault => vault_page(c, core, here)
    Stations => stations_page(c, core, here)
    Station(a) => station_page(c, core, here, a)
    Profiles(only) => profiles_page(c, core, here, only)
    Profile(a, id) => profile_page(c, core, here, a, id)
    PickModels(a, id) => pick_models_page(c, core, here, a, id)
    ProfileModels(a, id) => profile_models_page(c, core, here, a, id)
    Connects(only) => connects_page(c, core, here, only)
    Connect(a, id) => connect_page(c, core, here, a, id)
    MemoryDoc(a, skill, at) => memory_doc_page(c, core, a, skill, at)
    Archive => archive_page(c, core, here)
    AdbShare(a) => adb_page(c, core, here, a)
    NewProfile(a) => new_profile_page(c, core, here, a)
    ProfileAccount(k) => profile_account_page(c, core, here, k)
    NewConnect(a) => new_connect_page(c, core, here, a)
    ConnectRun(a, id) => connect_run_page(c, core, a, id)
    SlackApp(a, id) => slack_app_page(c, core, a, id)
    VaultItem(v, item) => vault_item_page(c, core, here, v, item)
    AutoCompletion => completion_page(c, core, here)
    AutoPolicy(s) => policy_page(c, core, here, s)
    BarSettings => bars_page(c, core)
    KeptFiles => kept_page(c, core)
    KeptChat(s, thread) => kept_chat_page(c, core, s, thread)
    // one page for every frame (src/sfdesk about.mbt), drawn by the frame's setting_route
    Changelog | About | Memories | Memory(_) | AutoDecisions | UsagePrices(_) | Usage => ()
    LocalStation => local_station_page(c, core)
    // the desktop's own, drawn by its frame (src/sfdesk)
    Shortcuts | Version | Notifications | Permissions | Archiving | StationArchiving(_) => ()
    RunSettings(s, key) => run_settings_page(c, core, s, key)
  }
}

///|
/// The themes to choose (SettingsHome.kt themes): the system's, light, dark.
// kept across runs: a table, never written
let themes : Array[(String, String)] = [
  ("system", "android-settings.theme.system"),
  ("light", "android-settings.theme.light"),
  ("dark", "android-settings.theme.dark"),
]

///|
/// What was chosen here before the core's prefs say it (prefs.set on its way): by the pref's name.
let chosen : Map[String, String] = Map::new()

///|
/// A pref as the core keeps it (the `prefs` topic), or as it was chosen here a moment ago.
pub fn pref(core : Core, name : String) -> String {
  let kept = text((core.topic)("prefs", Map::new()).value, name)
  match chosen.get(name) {
    Some(v) => {
      // the core has it now: what it keeps from here on (another device may change it)
      if v == kept {
        chosen.remove(name)
      }
      v
    }
    None => kept
  }
}

///|
/// A pref set (prefs.set), shown as chosen at once; "" takes it away (null: the default).
pub fn set_pref(core : Core, name : String, value : String) -> Unit {
  chosen[name] = value
  (core.call)(
    "prefs.set",
    obj([(name, if value == "" { Json::null() } else { str(value) })]),
    fn(r) {
      match r {
        Ok(_) => ()
        Err(e) => {
          chosen.remove(name)
          (core.say)(fill("android-misc.act.failed", [("what", tr("android-settings.appearance.title")), ("error", error_text(e))]))
        }
      }
    },
  )
}

///|
/// The theme chosen on this device: "system", "light" or "dark" (the prefs' `appearance`; the system's when none),
/// as chosen here before the core has it.
pub fn appearance(prefs : Json?) -> String {
  let kept = text(prefs, "appearance")
  let v = match chosen.get("appearance") {
    Some(v) => {
      if v == kept {
        chosen.remove("appearance")
      }
      v
    }
    None => kept
  }
  match v {
    "light" | "dark" => v
    _ => "system"
  }
}

///|
/// Whether the app is drawn dark: the theme chosen, or the system's (`system_dark`) when it follows it.
pub fn dark(prefs : Json?, system_dark : Bool) -> Bool {
  match appearance(prefs) {
    "dark" => true
    "light" => false
    _ => system_dark
  }
}

///|
/// Settings (SettingsScreen).
fn settings_home(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let w = workspace_view(core, here)
  let v = w.value
  let stations = stations_of(core, here).value
  let connects = (core.topic)("connects", { "scope": str(here.workspace), "mine": Json::boolean(false) }).value
  let lock = (core.topic)("lock", { "workspace": str(here.workspace) }).value
  let vaults = (core.topic)("vaults", { "workspace": str(here.workspace) }).value
  let st = match stations {
    Some(Array(a)) => Some(a)
    _ => None
  }
  let manager = text(v, "role") == "owner" || text(v, "role") == "admin"
  let members = items(v, "members").length()
  let waiting = items(v, "added").length() + items(v, "invitations").length()
  let me_name = if here.person != "" { here.person } else { here.email }
  let people = match v {
    Some(_) =>
      if manager && waiting > 0 {
        fill("android-settings.members.waiting", [("n", members.to_string()), ("waiting", waiting.to_string())])
      } else {
        fill("android-settings.members.count", [("n", members.to_string())])
      }
    None => ""
  }
  scroll_page(c, "home", [
    fn() { top_back(c, core, tr("android-settings.home.back")) },
    fn() { large_title(c, tr("android-settings.title")) },
    fn() {
      if identity_card(
          c,
          "me-card",
          fn() { avatar(c, core, here.email, me_name, @sf.identity_mark, picture=here.picture) },
          me_name,
          here.email,
        ) {
        (core.push)(Me)
      }
    },
    // the workspace as the account is (SettingsHome.kt): its mark, its name, the viewer's role in it and its people
    fn() {
      let name = match v {
        Some(_) => text(v, "name")
        None => here.name
      }
      let line = match v {
        Some(_) => role_label(text(v, "role")) + " · " + people
        None => ""
      }
      if identity_card(c, "workspace-card", fn() { workspace_tile(c, name, text(v, "emoji"), text(v, "icon")) }, name, line) {
        (core.push)(Workspace)
      }
    },
    // who may do what: security mode, where the workspace has it, and the vault. Each row there from the first frame,
    // its words once the core has said them: a row put in only then pushed the page under it down a row while it was
    // looked at (security mode's taken out only where the core says there is none, still.fail's always has it)
    fn() {
      list_card(c, fn() {
        if lock is None || flag(lock, "available") {
          let attention = count(lock, "attention")
          let said = if lock is None {
            ""
          } else if !flag(lock, "locked") {
            tr("web-mobile.settings.securityOff")
          } else if attention > 0 {
            fill("web-mobile.settings.securityWaiting", [("n", attention.to_string())])
          } else {
            tr("web-mobile.settings.securityOn")
          }
          if go_row(c, "go-security", tr("web-pages.security.title"), value=said, bad=attention > 0, icon="shield-check") {
            (core.push)(Security)
          }
        }
        // the vault's row (Vault.kt VaultSettingsRow): what waits, else how many items, else off (the core's words)
        let said = text(vaults, "statusText")
        let n = if flag(vaults, "statusBad") { 1 } else { 0 }
        if go_row(c, "go-vault", tr("android-settings.vault.title"), value=said, bad=n > 0, icon="key") {
          (core.push)(Vault)
        }
      })
    },
    // its stations and what they run: the chats' ways in and the agents' accounts
    fn() {
      list_card(c, fn() {
        let (online, troubled, profiles, short) = match st {
          Some(a) => {
            let mut on = 0
            let mut p = 0
            let mut sh = 0
            for x in a {
              if flag(Some(x), "online") {
                on += 1
              }
              for pr in items(field(Some(x), "overview"), "profiles") {
                p += 1
                if has(Some(pr), "trouble") {
                  sh += 1
                }
              }
            }
            (on, on < a.length(), p, sh)
          }
          None => (0, false, 0, 0)
        }
        let st_value = match st {
          Some(a) => fill("android-settings.home.online", [("online", online.to_string()), ("total", a.length().to_string())])
          None => ""
        }
        if go_row(c, "go-stations", "Station", value=st_value, dot=troubled, icon="server") {
          (core.push)(Stations)
        }
        let mut failing = 0
        for x in items(connects, "items") {
          if text(field(Some(x), "connect"), "presence") == "error" {
            failing += 1
          }
        }
        let cn_value = match connects {
          Some(_) =>
            if failing > 0 {
              fill("android-settings.home.failing", [("n", failing.to_string())])
            } else {
              fill("android-settings.count", [("n", items(connects, "items").length().to_string())])
            }
          None => ""
        }
        if go_row(c, "go-connects", tr("android-settings.connects.title"), value=cn_value, bad=failing > 0, icon="im") {
          (core.push)(Connects(""))
        }
        let pr_value = match st {
          Some(_) =>
            if short > 0 {
              fill("android-settings.home.short", [("n", short.to_string())])
            } else {
              fill("android-settings.count", [("n", profiles.to_string())])
            }
          None => ""
        }
        if go_row(c, "go-profiles", "Profile", value=pr_value, bad=short > 0, icon="quota") {
          (core.push)(Profiles(""))
        }
      })
    },
    // its agents: what they decide by themselves, what they remember, what they used
    fn() {
      list_card(c, fn() {
        if go_row(c, "go-decisions", tr("web-pages.automaticDecisions.title"), icon="check") {
          (core.push)(AutoDecisions)
        }
        if go_row(c, "go-memory", tr("android-settings.memory"), icon="brain") {
          (core.push)(Memories)
        }
        if go_row(c, "go-usage", tr("android-settings.home.usage"), icon="chart") {
          (core.push)(Usage)
        }
      })
    },
    fn() { section_header(c, tr("android-settings.home.device"), start=S6) },
    fn() {
      list_card(c, fn() {
        let theme = appearance((core.topic)("prefs", Map::new()).value)
        let mut said = ""
        for th in themes {
          if th.0 == theme {
            said = tr(th.1)
          }
        }
        if go_row(c, "go-appearance", tr("android-settings.appearance.title"), value=said, icon="sliders") {
          (core.push)(Appearance)
        }
        // this device's bottom bars: none on a wide screen (SettingsHome.kt: !LocalWide)
        if go_row(c, "go-bars", tr("android-misc.bar.title"), value=bars_value(core), icon="view-columns") {
          (core.push)(BarSettings)
        }
        // notifications on this device, local notices and pushes alike (SettingsHome.kt Notify): as the core's
        // `notify` says, or as switched while `notify.set` is out (a spinner, not switched again meanwhile); its
        // switch says whether, no note under it
        let notify = (core.topic)("notify", Map::new()).value
        let pending = is_doing(core, ["notify.set"], []) || notify_switched.val is Some(_)
        let on = match notify_switched.val {
          Some(v) => v
          None => notify is None || flag(notify, "on")
        }
        if list_row(c, key=if pending { "" } else { "notify" }, fn() {
          row_icon(c, "bell")
          row_title(c, tr("android-settings.notify.title"))
          if pending {
            spinner(c)
          }
          switch(c, "notify", on)
        }) {
          use_notify(core, !on)
        }
        // what this device keeps, in all (SettingsHome.kt: KeptFiles.read's total), once the core has said
        kept_read(c, core)
        let kept_value = match kept.chats {
          Some(chats) => size_words(chats.fold(init=0.0, fn(s, x) { s + number(Some(x), "bytes") }))
          None => ""
        }
        if go_row(c, "go-files", tr("android-settings.files.title"), value=kept_value, icon="disk") {
          (core.push)(KeptFiles)
        }
      })
    },
    // 关于 (SettingsHome.kt AboutRow): this build, or the newer one there is
    fn() {
      list_card(c, fn() {
        let (words, newer) = (core.version_words)()
        if go_row(c, "go-about", tr("web-pages.settings.nav.about"), value=if newer { words } else { build_version() }, icon="info") {
          (core.push)(About)
        }
      })
    },
    fn() { gap(c, 30.0) },
  ])
}

///|
/// The account's card and the workspace's (SettingsHome.kt): what it is by (`lead`: a picture, a mark), its name, a line
/// under it, a chevron; tapped, true the frame after.
fn identity_card(c : @ui.Ctx, key : String, lead : () -> Unit, name : String, line : String) -> Bool {
  card(c, key~, fn() {
    c.box(style=identity_row, fn() {
      lead()
      c.box(style=@sf.full_width, fn() {
        c.text(name, style=identity_name) |> ignore
        if line != "" {
          c.text(line, style=identity_line) |> ignore
        }
      })
      |> ignore
      chevron(c)
    })
    |> ignore
  })
}

///|
/// A card's row (SettingsHome.kt): what it is by, its words, its chevron, 14 apart, centred across it.
// kept across runs: a value (no field of it changes)
let identity_row : @ui.Style = @ui.css("row w=Full gap=S3_5 align=ACenter")

///|
/// The name on the account's card and the workspace's: 16 bold on one line, its line the theme's (1.4em: 22.4), as
/// Android's Text says none of its own.
// kept across runs: a value (no field of it changes)
let identity_name : @ui.TextStyle = @ui.text_style(size=Xl, weight=Bold, color=Fg, wrap=false, w=Full)

///|
/// The line under it: 13 in the muted, one line, the theme's line (18.2).
// kept across runs: a value (no field of it changes)
let identity_line : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, wrap=false, w=Full)

///|
/// The workspace's mark on its card (SettingsHome.kt WorkspaceTile), as the account's picture is on its own: a picture
/// put up fills the square; one of still.fail's icons or an emoji on the chips' ground; else its first letter, muted,
/// as the web's rail has it.
fn workspace_tile(c : @ui.Ctx, name : String, emoji : String, icon : String) -> Unit {
  let t = @sf.theme()
  let picture = icon.has_prefix("https://") || icon.has_prefix("http://") || icon.has_prefix("data:image/")
  c.box(style=@sf.workspace_tile.then(@ui.style(bg=Data(if picture { t.p.card } else { t.p.chip }))), fn() {
    if picture {
      @sf.station_mark(c, emoji, icon, @sf.identity_mark, t.p.text)
    } else if @sf.has_station_mark(emoji, icon) {
      @sf.station_mark(c, emoji, icon, @sf.workspace_tile_mark, t.p.text)
    } else {
      c.text(@sf.initial(name), style=@sf.workspace_letter) |> ignore
    }
  })
  |> ignore
}

///|
/// Notifications as switched here, until the core has answered (AppState.useNotify's `notify` meanwhile).
pub let notify_switched : Ref[Bool?] = Ref(None)

///|
/// Notifications turned on or off on this device (SettingsHome.kt Notify, AppState.useNotify): turned on, the system
/// asked to allow them too; the core keeps it (`notify.set`), taking this device's pushes off the accounts when off,
/// and the push registration follows what it answers (Push.sync). Not done: said in a toast, the switch back.
pub fn use_notify(core : Core, on : Bool) -> Unit {
  if on {
    (core.notify_ask)()
  }
  notify_switched.val = Some(on)
  (core.call)("notify.set", obj([("on", Json::boolean(on))]), fn(r) {
    notify_switched.val = None
    match r {
      Ok(v) =>
        (core.push_sync)(
          match field(Some(v), "push") {
            Some(True) => Some(true)
            Some(False) => Some(false)
            _ => None
          },
        )
      Err(e) => {
        (core.say)(
          fill(
            if on {
              "android-misc.notify.onFailed"
            } else {
              "android-misc.notify.offFailed"
            },
            [("error", error_text(e))],
          ),
        )
        (core.push_sync)(None)
      }
    }
  })
}

///|
/// This build's version, as the version row says it after the app's name (SettingsHome.kt Version: its versionName,
/// 0.1.<build>): the build where the host knows it (Android's version code), the line alone where it does not.
pub fn build_version() -> String {
  let v = @ui.app_version()
  if v > 0 {
    "0.1." + v.to_string()
  } else {
    "0.1"
  }
}

///|
/// The words under a switch (SettingsHome.kt's notes under a Seg; Fonts.kt's under the faces): 24 in, 8 under it, 13
/// on 19.5 in the muted.
fn seg_note(c : @ui.Ctx, note : String) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), pl=24.0, pr=24.0, pt=8.0, fn() { c.text(note, size=13.0, color=t.p.muted, w=Fill(1.0), line=19.5) |> ignore })
  |> ignore
}

///|
/// How this device shows still.fail (AppearanceScreen): its theme, its motion, the language it speaks, when a done chat
/// is offered to archive; each the core's prefs (`appearance`, `motion`, `language`, `archiveHint`).
fn appearance_page(c : @ui.Ctx, core : Core) -> Unit {
  let prefs = (core.topic)("prefs", Map::new()).value
  let choice = fn(
    key : String,
    title : String,
    options : Array[(String, String)],
    now : String,
    fallback : Int,
    note : String,
  ) {
    [
      fn() {
        section_header(c, title, start=S6)
        // (the wide frame's says what it is about under its head, as the web's; a phone's under its switch)
        section_note(c, note)
      },
      fn() {
        let mut at = fallback
        for i, o in options {
          if o.0 == now {
            at = i
          }
        }
        inset(c, fn() {
          let picked = seg(c, key, options.map(fn(o) { tr(o.1) }), at, fill=true, height=34.0)
          if picked != at {
            set_pref(core, key, options[picked].0)
          }
        })
        if note != "" {
          seg_note(c, note)
        }
      },
    ]
  }
  let hint_now = pref(core, "archiveHint")
  let hint_key = match hint_now {
    "off" | "reviewed" => hint_now
    _ => "done"
  }
  let blocks : Array[() -> Unit] = [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-settings.appearance.title")) },
  ]
  blocks.append(
    choice(
      "appearance",
      tr("android-settings.appearance.theme"),
      themes,
      appearance(prefs),
      0,
      "",
    ),
  )
  // SettingsHome.kt: 12 under the theme's switch, the faces' row on a card of its own
  blocks.push(fn() {
    gap(c, 12.0)
    list_card(c, fn() { font_row(c, core) })
  })
  blocks.append(
    choice(
      "motion",
      tr("web-pages.appearance.motion.title"),
      [
        ("", "web-pages.appearance.motion.system"),
        ("reduce", "web-pages.appearance.motion.reduce"),
        ("full", "web-pages.appearance.motion.full"),
      ],
      pref(core, "motion"),
      0,
      tr("web-pages.appearance.motion.description"),
    ),
  )
  blocks.append(
    choice(
      "language",
      tr("common.language"),
      [("", "common.language.system"), ("zh", "common.language.zh"), ("en", "common.language.en")],
      pref(core, "language"),
      0,
      "",
    ),
  )
  blocks.append(
    choice(
      "archiveHint",
      tr("web-pages.appearance.archive.title"),
      [
        ("off", "web-pages.appearance.archive.off"),
        ("", "web-pages.appearance.archive.done"),
        ("reviewed", "web-pages.appearance.archive.reviewed"),
      ],
      if hint_now == "done" { "" } else { hint_now },
      1,
      tr("web-pages.appearance.archive." + hint_key + "Hint"),
    ),
  )
  blocks.push(fn() { gap(c, 30.0) })
  scroll_page(c, "appearance", blocks)
}

///|
/// The account (Me.kt MeScreen): who is signed in, the accounts on this device (signing each out, adding another), and
/// where it is signed in (Devices).
fn me_page(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let accounts = match (core.topic)("accounts", Map::new()).value {
    Some(Array(a)) => a
    _ => []
  }
  let me_name = if here.person != "" { here.person } else { here.email }
  scroll_page(c, "me", [
    fn() { top_back(c, core, tr("android-settings.title")) },
    fn() { large_title(c, tr("android-settings.me.title")) },
    // the accounts on this device, on one card (Me.kt): the one in view first, with who it is, then the others; each
    // signed out of by itself (with one account it is just 退出登录), and another can be added
    fn() {
      let sign_out = fn(a : Json) {
        let sub = text(Some(a), "sub")
        let email = text(Some(a), "email")
        if is_doing(core, ["auth.signOut"], [("account", sub)]) {
          spinner(c, inline=true)
        } else if tap_text(
            c,
            "sign-out/" + sub,
            if accounts.length() > 1 {
              tr("android-settings.me.signOut")
            } else {
              tr("android-settings.me.signOutOnly")
            },
            color=t.p.red,
          ) {
          (core.home)()
          act(
            core,
            tr("android-settings.me.signOutWhat"),
            "auth.signOut",
            obj([("account", str(sub))]),
            done=if accounts.length() > 1 {
              fill("android-settings.me.signedOut", [("email", email)])
            } else {
              ""
            },
          )
        }
      }
      list_card(c, fn() {
        list_row(c, fn() {
          avatar(c, core, here.email, me_name, 46.0, picture=here.picture)
          c.box(w=Fill(1.0), fn() {
            c.text(me_name, size=16.0, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=22.0) |> ignore
            c.text(here.email + " · Google", size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0)
            |> ignore
          })
          |> ignore
          for a in accounts {
            if text(Some(a), "sub") == here.sub {
              sign_out(a)
            }
          }
        })
        |> ignore
        for a in accounts {
          if text(Some(a), "sub") != here.sub {
            list_row(c, fn() {
              row_title(c, text(Some(a), "email"))
              sign_out(a)
            })
            |> ignore
          }
        }
        if list_row(c, key="add-account", fn() {
            c.text(tr("android-settings.me.addAccount"), size=15.0, color=@sf.link_ink(), wrap=false, w=Fill(1.0), line=21.0)
            |> ignore
          }) {
          (core.sign_in)()
        }
      })
    },
    fn() { section_header(c, tr("android-settings.me.devices"), start=S6) },
    fn() { devices(c, core, here) },
    // deleting the account in view, at the foot as deleting a workspace is: asked first (Me.kt)
    fn() { gap(c, 18.0) },
    fn() {
      list_card(c, fn() {
        if list_row(c, key="delete-account", fn() { row_title(c, tr("android-settings.me.delete"), color=t.p.red) }) {
          confirm(
            tr("android-settings.me.deleteTitle"),
            fill("android-settings.me.deleteText", [("email", here.email)]),
            tr("android-settings.me.deleteAction"),
            danger=true,
            fn() {
              (core.home)()
              act(
                core,
                tr("android-settings.me.deleteAction"),
                "auth.deleteAccount",
                obj([("account", str(here.sub))]),
                done=fill("android-settings.me.deleted", [("email", here.email)]),
              )
            },
          )
        }
      })
    },
    fn() { gap(c, 30.0) },
  ])
}

///|
/// still.fail's terms or privacy policy on the web (SettingsHome.kt Legal; the app speaks Chinese: no /en).
pub fn legal_url(page : String) -> String {
  "https://still.fail/" + page
}

///|
/// Where the account is signed in (Settings.kt Devices, the `loginSessions` topic): each, this one marked 本机; one
/// not this signed out from here (`loginSession.revoke`).
fn devices(c : @ui.Ctx, core : Core, here : Here) -> Unit {
  let t = @sf.theme()
  let topic = (core.topic)("loginSessions", { "account": str(here.sub) })
  let list = match topic.value {
    Some(Array(a)) => a
    _ => {
      match topic.error {
        Some(e) =>
          wait_line(c, fill("android-settings.devices.failed", [("error", error_text(e))]), error=true, pad=true)
        None => wait_line(c, tr("common.reading"), pad=true)
      }
      return
    }
  }
  list_card(c, fn() {
    for d in list {
      let id = text(Some(d), "id")
      let current = flag(Some(d), "current")
      list_row(c, fn() {
        c.box(w=Fill(1.0), fn() {
          c.box(dir=Row, gap=6.0, align=ACenter, fn() {
            c.text(
              match text(Some(d), "name") {
                "" => tr("android-settings.devices.unnamed")
                n => n
              },
              size=15.0,
              color=t.p.text,
              wrap=false,
              line=21.0,
            )
            |> ignore
            if current {
              you(c, tr("android-settings.devices.here"))
            }
          })
          |> ignore
          c.text(
            fill("android-settings.devices.times", [
              ("ago", stamp(Some(d), "created_at", "ago")),
              ("until", stamp(Some(d), "expires_at", "until")),
            ]),
            size=13.0,
            color=t.p.muted,
            w=Fill(1.0),
            line=18.0,
          )
          |> ignore
        })
        |> ignore
        if !current {
          if is_doing(core, ["loginSession.revoke"], [("id", id)]) {
            spinner(c)
          } else {
            c.box(dir=Row, gap=6.0, align=ACenter, fn() {
              doing_mark(c, false, failed_of(core, ["loginSession.revoke"], [("id", id)]))
              if tap_text(c, "revoke/" + id, tr("android-settings.devices.signOut"), color=t.p.red) {
                act(
                  core,
                  tr("android-settings.devices.signOutWhat"),
                  "loginSession.revoke",
                  obj([("id", str(id)), ("account", str(here.sub))]),
                  done=tr("android-settings.devices.signedOut"),
                )
              }
            })
            |> ignore
          }
        }
      })
      |> ignore
    }
  })
}
