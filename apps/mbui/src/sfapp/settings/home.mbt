// Settings from the gear (app/screens/SettingsHome.kt SettingsScreen): who is signed in, then the workspace's (its
// people, security, the vault, stations, connects, profiles, memory, usage), then this device's (how it looks, its
// notifications, this build). Each row says how things stand at its end, what is wrong in red. And how this device
// shows still.fail (AppearanceScreen), and the account (Me.kt).

///|
/// A page of the settings, by its route: call for the page the app's stack shows. `root`: a place of the bottom
/// bar's at the stack's root (PlacePage.kt), under the app's own top bar, so without its compact one.
pub fn page(c : @ui.Ctx, core : Core, here : Here, route : Route, root? : Bool = false) -> Unit {
  frame_ctx.val = Some(c)
  frame_core.val = Some(core)
  at_root.val = root
  match route {
    Home => settings_home(c, core, here)
    Me => me_page(c, core, here)
    Appearance => appearance_page(c, core)
    Workspace => workspace_page(c, core, here)
    Security => security_page(c, core, here)
    Vault => vault_page(c, core, here)
    Stations => stations_page(c, core, here)
    Station(a) => station_page(c, core, here, a)
    Profiles(only) => profiles_page(c, core, here, only)
    Profile(a, id) => profile_page(c, core, here, a, id)
    Connects(only) => connects_page(c, core, here, only)
    Connect(a, id) => connect_page(c, core, a, id)
    Memories => memories_page(c, core, here)
    Memory(a) => memory_page(c, core, here, a)
    MemoryDoc(a, skill, at) => memory_doc_page(c, core, a, skill, at)
    Usage => usage_page(c, core, here)
    Archive => archive_page(c, core, here)
  }
}

///|
/// The themes to choose (SettingsHome.kt themes): the system's, light, dark.
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
fn pref(core : Core, name : String) -> String {
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
fn set_pref(core : Core, name : String, value : String) -> Unit {
  chosen[name] = value
  wake()
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
  let t = @sf.theme()
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
  scroll_page(c, "home", [
    fn() { top_back(c, core, tr("android-settings.home.back")) },
    fn() { large_title(c, tr("android-settings.title")) },
    fn() {
      if card(c, key="me-card", fn() {
          c.box(dir=Row, w=Fill(1.0), gap=14.0, align=ACenter, fn() {
            avatar(c, core, here.email, me_name, 46.0, picture=here.picture)
            c.box(w=Fill(1.0), fn() {
              c.text(me_name, size=16.0, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=22.0) |> ignore
              c.text(here.email, size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0) |> ignore
            })
            |> ignore
            chevron(c)
          })
          |> ignore
        }) {
        (core.push)(Me)
      }
    },
    fn() {
      section_header(
        c,
        match v {
          Some(_) =>
            fill("android-settings.home.workspace", [("name", text(v, "name")), ("role", role_label(text(v, "role")))])
          None => here.name
        },
      )
    },
    fn() {
      list_card(c, fn() {
        let people = match v {
          Some(_) =>
            if manager && waiting > 0 {
              fill("android-settings.members.waiting", [("n", members.to_string()), ("waiting", waiting.to_string())])
            } else {
              fill("android-settings.members.count", [("n", members.to_string())])
            }
          None => ""
        }
        if go_row(c, "go-workspace", "Workspace", value=people) {
          (core.push)(Workspace)
        }
        if flag(lock, "available") {
          let attention = count(lock, "attention")
          let said = if !flag(lock, "locked") {
            tr("web-mobile.settings.securityOff")
          } else if attention > 0 {
            fill("web-mobile.settings.securityWaiting", [("n", attention.to_string())])
          } else {
            tr("web-mobile.settings.securityOn")
          }
          if go_row(c, "go-security", tr("web-pages.security.title"), value=said, bad=attention > 0) {
            (core.push)(Security)
          }
        }
        // the vault's row (Vault.kt VaultSettingsRow): what waits, else how many items, else off
        match vaults {
          Some(_) => {
            let n = items(vaults, "requests").length()
            let said = if n > 0 {
              fill("android-settings.vault.waiting", [("n", n.to_string())])
            } else if items(vaults, "vaults").length() > 0 {
              let mut total = 0
              for x in items(vaults, "vaults") {
                total += count(Some(x), "items")
              }
              fill("android-settings.vault.items", [("n", total.to_string())])
            } else {
              tr("android-settings.vault.off")
            }
            if go_row(c, "go-vault", tr("android-settings.vault.title"), value=said, bad=n > 0) {
              (core.push)(Vault)
            }
          }
          None => ()
        }
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
        if go_row(c, "go-stations", "Station", value=st_value, dot=troubled) {
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
        if go_row(c, "go-connects", tr("android-settings.connects.title"), value=cn_value, bad=failing > 0) {
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
        if go_row(c, "go-profiles", "Profile", value=pr_value, bad=short > 0) {
          (core.push)(Profiles(""))
        }
        // (the automatic decisions' page is a later slice's: its row, not opened yet)
        go_row(c, "go-decisions", tr("web-pages.automaticDecisions.title")) |> ignore
        if go_row(c, "go-memory", tr("android-settings.memory")) {
          (core.push)(Memories)
        }
        if go_row(c, "go-usage", tr("android-settings.home.usage")) {
          (core.push)(Usage)
        }
      })
    },
    fn() { section_header(c, tr("android-settings.home.device")) },
    fn() {
      list_card(c, fn() {
        let theme = appearance((core.topic)("prefs", Map::new()).value)
        let mut said = ""
        for th in themes {
          if th.0 == theme {
            said = tr(th.1)
          }
        }
        if go_row(c, "go-appearance", tr("android-settings.appearance.title"), value=said) {
          (core.push)(Appearance)
        }
        // the bottom bar's places, what is kept on this device, the changelog: later slices' pages, their rows
        go_row(c, "go-bars", tr("android-misc.bar.title")) |> ignore
        go_row(c, "go-files", tr("android-settings.files.title")) |> ignore
        // notifications on this device, local notices and pushes alike (SettingsHome.kt Notify): as the core's
        // `notify` says, or as switched while `notify.set` is out (a spinner, not switched again meanwhile)
        let notify = (core.topic)("notify", Map::new()).value
        let pending = is_doing(core, ["notify.set"], []) || notify_switched.val is Some(_)
        let on = match notify_switched.val {
          Some(v) => v
          None => notify is None || flag(notify, "on")
        }
        if list_row(c, key=if pending { "" } else { "notify" }, fn() {
          c.box(w=Fill(1.0), fn() {
            c.text(tr("android-settings.notify.title"), size=15.0, color=t.p.text, line=21.0) |> ignore
            c.text(
              if on {
                tr("android-settings.notify.on")
              } else {
                tr("android-settings.notify.off")
              },
              size=13.0,
              color=t.p.muted,
              line=18.0,
            )
            |> ignore
          })
          |> ignore
          if pending {
            spinner(c)
          }
          switch(c, on)
        }) {
          use_notify(core, !on)
        }
        // this build (Version): its name and version, and the way to a newer one (tapped: installed, or asked now)
        let (words, newer) = (core.version_words)()
        if list_row(c, key="version", fn() {
            c.text("still.fail " + build_version, size=15.0, color=t.p.text, wrap=false, w=Fill(1.0), line=21.0)
            |> ignore
            c.text(words, size=15.0, color=if newer { t.p.accent } else { t.p.muted }, wrap=false, line=21.0)
            |> ignore
          }) {
          (core.version_tap)()
        }
        go_row(c, "go-changelog", tr("android-settings.changelog.title")) |> ignore
      })
    },
    fn() { gap(c, 30.0) },
  ])
}

///|
/// Notifications as switched here, until the core has answered (AppState.useNotify's `notify` meanwhile).
let notify_switched : Ref[Bool?] = Ref(None)

///|
/// Notifications turned on or off on this device (SettingsHome.kt Notify, AppState.useNotify): turned on, the system
/// asked to allow them too; the core keeps it (`notify.set`), taking this device's pushes off the accounts when off,
/// and the push registration follows what it answers (Push.sync). Not done: said in a toast, the switch back.
fn use_notify(core : Core, on : Bool) -> Unit {
  if on {
    (core.notify_ask)()
  }
  notify_switched.val = Some(on)
  (core.call)("notify.set", obj([("on", Json::boolean(on))]), fn(r) {
    notify_switched.val = None
    wake()
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
/// This build's version, as the settings' last rows say it.
let build_version : String = "mbui 0.1"

///|
/// How this device shows still.fail (AppearanceScreen): its theme, its motion, the language it speaks, when a done chat
/// is offered to archive; each the core's prefs (`appearance`, `motion`, `language`, `archiveHint`).
fn appearance_page(c : @ui.Ctx, core : Core) -> Unit {
  let t = @sf.theme()
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
      fn() { section_header(c, title) },
      fn() {
        let mut at = fallback
        for i, o in options {
          if o.0 == now {
            at = i
          }
        }
        c.box(w=Fill(1.0), padx=12.0, fn() {
          let picked = seg(c, key, options.map(fn(o) { tr(o.1) }), at, fill=true, height=34.0)
          if picked != at {
            set_pref(core, key, options[picked].0)
          }
        })
        |> ignore
        if note != "" {
          c.box(w=Fill(1.0), pl=24.0, pr=24.0, pt=8.0, fn() {
            c.text(note, size=13.0, color=t.p.muted, w=Fill(1.0), line=19.5) |> ignore
          })
          |> ignore
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
  blocks.append(choice("appearance", tr("android-settings.appearance.theme"), themes, appearance(prefs), 0, ""))
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
    fn() {
      card(c, fn() {
        c.box(dir=Row, w=Fill(1.0), gap=14.0, align=ACenter, fn() {
          avatar(c, core, here.email, me_name, 46.0, picture=here.picture)
          c.box(w=Fill(1.0), fn() {
            c.text(me_name, size=16.0, weight=700, color=t.p.text, wrap=false, w=Fill(1.0), line=22.0) |> ignore
            c.text(here.email + " · Google", size=13.0, color=t.p.muted, wrap=false, w=Fill(1.0), line=18.0)
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    fn() { section_header(c, tr("android-settings.me.accounts")) },
    fn() {
      list_card(c, fn() {
        for a in accounts {
          let sub = text(Some(a), "sub")
          let email = text(Some(a), "email")
          list_row(c, fn() {
            row_title(c, email)
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
          })
          |> ignore
        }
        if list_row(c, key="add-account", fn() {
            c.text(tr("android-settings.me.addAccount"), size=15.0, color=t.p.accent, wrap=false, w=Fill(1.0), line=21.0)
            |> ignore
          }) {
          (core.sign_in)()
        }
      })
    },
    fn() { section_header(c, tr("android-settings.me.devices")) },
    fn() { devices(c, core, here) },
    fn() { gap(c, 30.0) },
  ])
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
