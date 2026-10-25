// The settings as the desktop has them (ember web/src/cloud/settings.tsx SettingsPage, SettingsNav): the sidebar of
// their pages by where they act, and the page picked beside it: the desktop's own ported from the web's (account.mbt,
// notifications.mbt, …, in settings_page.mbt's frame), the others the settings' package's (src/sfapp/settings) in the
// wide frame's scale until they are ported. What both read and call (the core's calls, the models) is that
// package's, once.

///|
/// The settings page `route` in the pane.
fn setting_page(c : @ui.Ctx, src : Source, w : Workspace, route : Route) -> Unit {
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  // a page under another of them shows back (the sidebar is the way to the others)
  let stack = app.nav.pages()
  let deep = stack.length() >= 2 && stack[stack.length() - 2] is Setting(_)
  settings_deep.val = deep
  // (the settings' pages not ported yet read it too)
  @settings.wide_deep.val = deep
  // a page merged for every frame: back over it only under another settings page or a place of the rail's (a connect's
  // under 连接; the sidebar is the way to the others)
  let frame : PageFrame = {
    back: if deep || (stack.length() >= 2 && stack[stack.length() - 2] is Place(_)) {
      Some(back_label(stack[stack.length() - 2]))
    } else {
      None
    },
    top: 0.0,
    foot: 0.0,
    named: false,
  }
  if setting_route(c, src, w, route, frame) {
    return
  }
  @settings.frame(core, here)
  settings_fixture(src, core)
  match route {
    NewProfile(a) => add_profile_page(c, core, here, a)
    MemoryDoc(a, skill, at) => memory_doc_page(c, core, a, skill, at)
    AutoCompletion => completion_page(c, core, here)
    AutoPolicy(s) => policy_page(c, core, here, s)
    LocalStation => local_station_page(c, core)
    _ => @settings.page(c, core, here, route)
  }
}

///|
/// The settings' pages, one for every frame, by route: drawn in the frame it is shown in (the Small stack's, the wide
/// frame's pane: back, the room over and under it). False for a route whose pages are not one yet (its frame draws its
/// own copy).
pub fn setting_route(c : @ui.Ctx, src : Source, w : Workspace, route : Route, frame : PageFrame) -> Bool {
  if !(route is (Appearance | Fonts | BarSettings | About | Changelog | Memories | Memory(_) | AutoDecisions | Permissions | UsagePrices(_) | Usage | Archiving | StationArchiving(_) | Notifications | PickModels(_, _) | ProfileModels(_, _) | Shortcuts | Me | Workspace | Security | SecurityOpen | Vault | VaultItem(_, _) | Connects(_) | Connect(_, _) | Station(_) | Profile(_, _))) {
    return false
  }
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  @settings.frame(core, here)
  settings_fixture(src, core)
  match route {
    Appearance => appearance_page(c, core, frame)
    Fonts => fonts_page(c, core, frame)
    BarSettings => bars_page(c, core, frame)
    About => about_page(c, core, frame)
    Changelog => changelog_page(c, core, frame)
    Memories => memories_page(c, core, here, frame)
    Memory(a) => memory_page(c, core, here, frame, a)
    AutoDecisions => decisions_page(c, core, here, frame)
    Permissions => permissions_page(c, core, frame)
    UsagePrices(days) => usage_prices_page(c, core, here, frame, days)
    Usage => usage_page(c, core, here, frame)
    Archiving => archiving_page(c, core, here, frame)
    StationArchiving(st) => station_archiving_page(c, core, here, frame, st)
    Notifications => notify_page(c, core, here, frame)
    PickModels(a, id) => pick_models_page(c, core, here, frame, a, id)
    ProfileModels(a, id) => profile_models_page(c, core, here, frame, a, id)
    Shortcuts => shortcuts_page(c, core, frame)
    Me => me_page(c, core, here, frame)
    Workspace => workspace_page(c, core, here, frame)
    Security => security_page(c, core, here, frame)
    SecurityOpen => security_open_page(c, core, here, frame)
    Vault => vault_page(c, core, here, frame)
    VaultItem(v, item) => vault_item_page(c, core, here, frame, v, item)
    Connects(only) => connects_page(c, src, core, here, frame, only)
    Connect(station, id) => connect_page(c, src, core, here, frame, station, id)
    Station(a) => station_page(c, core, here, frame, a)
    Profile(a, id) => profile_page(c, core, here, frame, a, id)
    _ => ()
  }
  true
}

///|
/// Whether the settings page drawn is under another of them (its head's back shown).
// kept across runs: said again by every settings page as it is drawn (setting_page)
let settings_deep : Ref[Bool] = Ref(false)

///|
/// A dialog a fixture's mode puts up over its page (MBUI_FIXTURE=settings-policy-text, settings-security-confirm, …:
/// @settings.fixture_desk), once the page is drawn with what it needs.
fn settings_fixture(src : Source, core : Core) -> Unit {
  match @settings.fixture_desk() {
    "policy-text" => fx_policy_up.val = "text"
    "policy-option" => fx_policy_up.val = "option"
    "lock-confirm" =>
      match items((core.topic)("lock", { "workspace": Json::string("ws1") }).value, "requests") {
        [r, ..] => confirm_dialog(core, "ws1", r)
        _ => ()
      }
    "lock-join" => join_dialog(core, "ws1", "st2", "MBA")
    "lock-off" => turn_off_dialog(core, "ws1", "星火工作室")
    "local-fonts" => local_open.val = true
    "connect-mode" =>
      match items((core.topic)("connects", { "scope": str("ws1"), "mine": Json::boolean(false) }).value, "items") {
        [item, ..] => cd_mode_dialog(core, "ws1/st1", Some(item))
        _ => ()
      }
    "new-connect" => new_connect_dialog(src, core, @settings.here_of(core, "ws1", "星火工作室"), "ws1/st1")
    "vault-add" => vault_add_dialog(core, @settings.here_of(core, "ws1", "星火工作室"))
    "vault-editor" => vault_editor_dialog(core, "ws1", "v1", None, kind="token")
    "vault-recover" => vault_recover_dialog(core, "ws1")
    _ => ()
  }
}

///|
/// What the settings pages here keep put back as the app begins anew.
fn settings_reset() -> Unit {
  notify_page_reset()
  ws_menu.val = ""
  mine_filter_open.clear()
  desk_dialogs.val = 0
  fx_policy_up.val = ""
  local_menu.val = false
  settings_deep.val = false
  connect_reset()
  new_connect_reset()
}

///|
/// The settings' sidebar: back to the chats, then its pages by where they act (this device, the stations, the cloud);
/// those in the rail (Station, Profile, 连接, 用量) are reached there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let here = match app.nav.top() {
    // (a page under one of them: that one lit)
    Setting(Route::StationArchiving(_)) => Some(Route::Archiving)
    Setting(Route::SecurityOpen) => Some(Route::Security)
    Setting(Route::AutoCompletion) | Setting(Route::AutoPolicy(_)) =>
      Some(Route::AutoDecisions)
    Setting(r) => Some(r)
    Settings => Some(Route::Appearance)
    Archived => Some(Route::Archive)
    _ => None
  }
  let rails = rail_items(src, w.id)
  let here_of = @settings.here_of(settings_core(src, w), w.id, w.name)
  // its lines, a heading over each part and a row a page, so a row knows whether another row is under it
  let lines : Array[SettingsLine] = [
    Part(@sf.t("web-pages.settings.nav.client")),
    PageRow(Route::Appearance, "appearance", "sliders", @sf.t("web-pages.settings.nav.appearance")),
    PageRow(Route::Notifications, "notifications", "bell", @sf.t("web-pages.settings.nav.notifications")),
    PageRow(Route::Permissions, "permissions", "key", @sf.t("web-pages.settings.nav.permissions")),
    PageRow(Route::Changelog, "changelog", "sparks", @sf.t("web-pages.settings.nav.changelog")),
    PageRow(Route::About, "about", "info", @sf.t("web-pages.settings.nav.about")),
    // the desktop's own (cloud/settings.tsx: the client's part)
    PageRow(Route::Shortcuts, "shortcuts", "command", @sf.t("web-pages.settings.nav.shortcuts")),
  ]
  if @ui.platform() == 0 {
    lines.push(PageRow(Route::LocalStation, "local-station", "monitor", @sf.t("web-pages.localStation.title")))
  }
  lines.push(Part("Station"))
  if !rails.contains("stations") {
    lines.push(PageRow(Route::Stations, "stations", "server", "Station"))
  }
  if !rails.contains("connects") {
    lines.push(PageRow(Route::Connects(""), "connects", "im", @sf.t("web-pages.settings.nav.connects")))
  }
  if !rails.contains("profiles") {
    lines.push(PageRow(Route::Profiles(""), "profiles", "quota", "Profile"))
  }
  lines.push(PageRow(Route::Archiving, "archive", "archive", @sf.t("web-pages.archiving.title")))
  lines.push(PageRow(Route::AutoDecisions, "automatic-decisions", "check", @sf.t("web-pages.automaticDecisions.title")))
  lines.push(PageRow(Route::Memories, "memory", "brain", @sf.t("web-pages.settings.nav.memory")))
  if !rails.contains("usage") {
    lines.push(PageRow(Route::Usage, "usage", "chart", @sf.t("web-pages.settings.nav.usage")))
  }
  lines.push(Part("Cloud"))
  lines.push(PageRow(Route::Workspace, "workspace", "users", "Workspace · " + w.name))
  lines.push(PageRow(Route::Security, "security", "shield-check", @sf.t("web-pages.security.title")))
  lines.push(PageRow(Route::Vault, "vault", "key", @sf.t("web-pages.vault.title")))
  lines.push(PageRow(Route::Me, "account", "user", if here_of.email != "" { here_of.email } else { w.email }))
  c.box(style=settings_side_fill, fn() {
    side_top(c)
    side_scroll(c, "settings-nav", fn() {
      if nav_row(c, "settings-nav/back", false, fn() {
          @sf.icon(c, "arrow-left", size=settings_nav_icon, color=t.p.muted) |> ignore
          nav_words(c, @sf.t("web-pages.settings.nav.backToChats"))
        }) {
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        if app.nav.top() != Home {
          app.nav.replace(Home)
        }
        wide.landed = ""
      }
      for i, line in lines {
        match line {
          Part(label) => @sf.list_heading(c, label, Side)
          PageRow(r, key, icon, label) => {
            let more = i + 1 < lines.length() && lines[i + 1] is PageRow(_)
            if nav_row(
                c,
                "settings-nav/" + key,
                here == Some(r),
                fn() {
                  @sf.icon(c, icon, size=settings_nav_icon, color=t.p.muted) |> ignore
                  nav_words(c, label)
                },
                more~,
              ) {
              while app.nav.depth() > 1 {
                if !app.nav.pop() {
                  break
                }
              }
              app.nav.push(Setting(r))
            }
          }
        }
      }
    })
  })
  |> ignore
}

///|
/// A line of the settings' sidebar: a heading over a part, or a page's row (its route, key, icon and words).
priv enum SettingsLine {
  Part(String)
  PageRow(@settings.Route, String, String, String)
}

///|
let settings_nav_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let settings_side_fill : @ui.Style = @ui.css("w=Full h=Full")

