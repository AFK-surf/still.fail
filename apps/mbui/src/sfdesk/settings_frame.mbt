// The settings as the desktop has them (ember web/src/cloud/settings.tsx SettingsPage, SettingsNav): the sidebar of
// their pages by where they act, and the page picked beside it: the desktop's own ported from the web's (account.mbt,
// notifications.mbt, …, in settings_page.mbt's frame), the others the settings' package's (src/sfapp/settings) in the
// wide frame's scale until they are ported. What both read and call (the core's calls, the models) is that
// package's, once.

///|
/// The settings page `route` in the pane.
fn setting_page(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages, route : Route) -> Unit {
  let core = (pages.core)(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  // a page under another of them shows back (the sidebar is the way to the others)
  let stack = app.nav.pages()
  let deep = stack.length() >= 2 && stack[stack.length() - 2] is Setting(_)
  settings_deep.val = deep
  // (the settings' pages not ported yet read it too)
  @settings.wide_deep.val = deep
  @settings.desk_vault.val = Some(desk_vault)
  @settings.frame(core, here)
  settings_fixture(core)
  match route {
    Me => me_page(c, core, here)
    Appearance => appearance_page(c, core)
    About => about_page(c, core)
    Changelog => changelog_page(c, core)
    Workspace => workspace_page(c, core, here)
    Security => security_page(c, core, here)
    Vault => vault_page(c, core, here)
    VaultItem(v, item) => vault_item_page(c, core, here, v, item)
    Connects("") => connects_page(c, src, core, here)
    Connect(station, id) => connect_page(c, src, core, here, station, id)
    Memories => memories_page(c, core, here)
    Usage => usage_page(c, core, here)
    Station(a) => station_page(c, core, here, a)
    Profile(a, id) => profile_page(c, core, here, a, id)
    NewProfile(a) => add_profile_page(c, core, here, a)
    PickModels(a, id) => pick_models_page(c, core, here, a, id)
    Memory(a) => memory_page(c, core, here, a)
    AutoDecisions => decisions_page(c, core, here)
    AutoCompletion => completion_page(c, core, here)
    AutoPolicy(s) => policy_page(c, core, here, s)
    Shortcuts => shortcuts_page(c, core)
    Version => version_page(c, core)
    LocalStation => local_station_page(c, core)
    Notifications => notify_page(c, core, here)
    Permissions => permissions_page(c, core)
    Archiving => archiving_page(c, core, here)
    StationArchiving(s) => station_archiving_page(c, core, here, s)
    _ => @settings.page(c, core, here, route)
  }
}

///|
/// The vault's dialogs, for the settings' pages not ported yet (@settings.desk_vault).
// kept across runs: a value (no field of it changes)
let desk_vault : @settings.DeskVault = {
  add: vault_add_dialog,
  editor: fn(core, ws, vault, editing, kind, plain) {
    vault_editor_dialog(core, ws, vault, editing, kind~, plain~, kinds=kind == "")
  },
  recover: vault_recover_dialog,
}

///|
/// Whether the settings page drawn is under another of them (its head's back shown).
// kept across runs: said again by every settings page as it is drawn (setting_page)
let settings_deep : Ref[Bool] = Ref(false)

///|
/// A dialog a fixture's mode puts up over its page (MBUI_FIXTURE=settings-policy-text, settings-security-confirm, …:
/// @settings.fixture_desk), once the page is drawn with what it needs.
fn settings_fixture(core : Core) -> Unit {
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
    _ => ()
  }
}

///|
/// The settings pages' dialogs over everything the frame shows (the app draws them, under the settings' questions).
pub fn settings_overlay(c : @ui.Ctx) -> Unit {
  desk_dialog_overlay(c)
}

///|
/// What the settings pages here keep put back as the app begins anew.
fn settings_reset() -> Unit {
  notify_page_reset()
  waiting_menu.val = ""
  ws_menu.val = ""
  mine_filter_open.clear()
  desk_dialog.val = None
  desk_dialog_last.val = None
  desk_dialogs.val = 0
  fx_policy_up.val = ""
  local_menu.val = false
  settings_deep.val = false
  connect_reset()
  new_connect_reset()
  cn_add_open.val = ""
}

///|
/// The settings' sidebar: back to the chats, then its pages by where they act (this device, the stations, the cloud);
/// those in the rail (Station, Profile, 连接, 用量) are reached there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace, pages : Pages) -> Unit {
  let t = @sf.theme()
  let here = match app.nav.top() {
    // (a page under one of them: that one lit)
    Setting(Route::StationArchiving(_)) => Some(Route::Archiving)
    Setting(Route::AutoCompletion) | Setting(Route::AutoPolicy(_)) =>
      Some(Route::AutoDecisions)
    Setting(r) => Some(r)
    Settings => Some(Route::Appearance)
    Archived => Some(Route::Archive)
    _ => None
  }
  let rails = rail_items(src, w.id)
  let page = fn(r : @settings.Route, key : String, icon : String, label : String) {
    if nav_row(c, "settings-nav/" + key, here == Some(r), fn() {
        @sf.icon(c, icon, size=settings_nav_icon, color=t.p.muted) |> ignore
        nav_words(c, label)
      }) {
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Setting(r))
    }
  }
  let here_of = @settings.here_of((pages.core)(src, w), w.id, w.name)
  c.box(style=settings_side_fill, fn() {
    side_top(c)
    c.box(style=settings_nav_list, fn() {
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
      nav_heading(c, @sf.t("web-pages.settings.nav.client"))
      page(Route::Appearance, "appearance", "sliders", @sf.t("web-pages.settings.nav.appearance"))
      page(Route::Notifications, "notifications", "bell", @sf.t("web-pages.settings.nav.notifications"))
      page(Route::Permissions, "permissions", "key", @sf.t("web-pages.settings.nav.permissions"))
      page(Route::Changelog, "changelog", "sparks", @sf.t("web-pages.settings.nav.changelog"))
      page(Route::About, "about", "info", @sf.t("web-pages.settings.nav.about"))
      // the desktop's own (cloud/settings.tsx: the client's part)
      page(Route::Shortcuts, "shortcuts", "command", @sf.t("web-pages.settings.nav.shortcuts"))
      page(Route::Version, "version", "info", @sf.t("web-pages.settings.nav.version"))
      if @ui.platform() == 0 {
        page(Route::LocalStation, "local-station", "monitor", @sf.t("web-pages.localStation.title"))
      }
      nav_heading(c, "Station")
      if !rails.contains("stations") {
        page(Route::Stations, "stations", "server", "Station")
      }
      if !rails.contains("connects") {
        page(Route::Connects(""), "connects", "im", @sf.t("web-pages.settings.nav.connects"))
      }
      if !rails.contains("profiles") {
        page(Route::Profiles(""), "profiles", "quota", "Profile")
      }
      page(Route::Archiving, "archive", "archive", @sf.t("web-pages.archiving.title"))
      page(Route::AutoDecisions, "automatic-decisions", "check", @sf.t("web-pages.automaticDecisions.title"))
      page(Route::Memories, "memory", "brain", @sf.t("web-pages.settings.nav.memory"))
      if !rails.contains("usage") {
        page(Route::Usage, "usage", "chart", @sf.t("web-pages.settings.nav.usage"))
      }
      nav_heading(c, "Cloud")
      page(Route::Workspace, "workspace", "users", "Workspace · " + w.name)
      page(Route::Security, "security", "shield-check", @sf.t("web-pages.security.title"))
      page(Route::Vault, "vault", "key", @sf.t("web-pages.vault.title"))
      page(Route::Me, "account", "user", if here_of.email != "" { here_of.email } else { w.email })
    })
    |> ignore
  })
  |> ignore
}

///|
let settings_nav_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let settings_side_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// Its pages under the band, 8 in at its sides, 4 under it (Sidebar.css.ts navList).
// kept across runs: a value (no field of it changes)
let settings_nav_list : @ui.Style = @ui.css("w=Full h=Full px=S2 pt=S1")
