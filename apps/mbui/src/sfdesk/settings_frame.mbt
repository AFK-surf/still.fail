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
  let under = app.nav.under()
  let deep = under is Some(Setting(_))
  settings_deep.val = deep
  // (the settings' pages not ported yet read it too)
  @settings.wide_deep.val = deep
  // a page merged for every frame: back over it only under another settings page or a place of the rail's (a connect's
  // under 连接; the sidebar is the way to the others)
  let frame : PageFrame = {
    back: match under {
      Some(u) if u is (Setting(_) | Place(_)) => Some(@sfbase.back_label(u))
      _ => None
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
    _ => @settings.page(c, core, here, route)
  }
}

///|
/// The settings' pages, one for every frame, by route: drawn in the frame it is shown in (the Small stack's, the wide
/// frame's pane: back, the room over and under it). False for a route whose page every frame makes once in its place
/// (关于, 更新日志, 记忆, 一台 station 的记忆, 用量, 价目表: pane_made, tape_made, narrow_made), and for one whose pages are not one yet (its frame draws its
/// own copy).
pub fn setting_route(c : @ui.Ctx, src : Source, w : Workspace, route : Route, frame : PageFrame) -> Bool {
  if !(route is (Home | Appearance | Fonts | BarSettings | Permissions | Notifications | Shortcuts | Me | Workspace | Security | SecurityOpen | Vault | VaultItems | VaultItem(_, _) | Connects(_) | Connect(_, _) | Station(_) | Profile(_, _) | LocalStation | MemoryDoc(_, _, _) | AutoCompletion | AutoPolicy(_))) {
    return false
  }
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  @settings.frame(core, here)
  settings_fixture(src, core)
  match route {
    // the settings' list as a page of its own (a small screen's: sfpages' settings_list.mbt), a row pressed its page
    // pushed
    Home =>
      @sf.page(c, on_back=core.pop, frame~, "home", @sf.t("android-settings.title"), @sfpages.settings_blocks(c, core, here, fn(r) {
        (core.push)(r)
      }))
    Appearance => @sfpages.appearance_page(c, core, frame)
    Fonts => @sfpages.fonts_page(c, core, frame)
    BarSettings => @sfpages.bars_page(c, core, frame)
    Permissions => @sfpages.permissions_page(c, core, frame)
    Notifications => @sfpages.notify_page(c, core, here, frame)
    Shortcuts => @sfpages.shortcuts_page(c, core, frame)
    Me => @sfpages.me_page(c, core, here, frame)
    Workspace => @sfpages.workspace_page(c, core, here, frame)
    Security => @sfpages.security_page(c, core, here, frame)
    SecurityOpen => @sfpages.security_open_page(c, core, here, frame)
    Vault => @sfpages.vault_page(c, core, here, frame)
    VaultItems => @sfpages.vault_items_page(c, core, here, frame)
    VaultItem(v, item) => @sfpages.vault_item_page(c, core, here, frame, v, item)
    Connects(only) => @sfpages.connects_page(c, src, core, here, frame, only)
    Connect(station, id) => @sfpages.connect_page(c, src, core, here, frame, station, id)
    Station(a) => @sfpages.station_page(c, core, here, frame, a)
    Profile(a, id) => @sfpages.profile_page(c, core, here, frame, a, id)
    LocalStation => @sfpages.local_station_page(c, core, frame)
    MemoryDoc(a, skill, at) => @sfpages.memory_doc_page(c, core, here, frame, a, skill, at)
    AutoCompletion => @sfpages.completion_page(c, core, here, frame)
    AutoPolicy(s) => @sfpages.policy_page(c, core, here, frame, s)
    _ => ()
  }
  true
}

///|
/// Whether the settings page drawn is under another of them (its head's back shown).
// kept across runs: said again by every settings page as it is drawn (setting_page)
let settings_deep : Ref[Bool] = Ref(false)

///|
/// A dialog a fixture's mode puts up over its page (MBUI_FIXTURE=settings-policy-text, settings-security-join, …:
/// @settings.fixture_desk), once the page is drawn with what it needs.
fn settings_fixture(src : Source, core : Core) -> Unit {
  match @settings.fixture_desk() {
    "policy-text" => @sfpages.fx_policy_up.val = "text"
    "policy-option" => @sfpages.fx_policy_up.val = "option"
    "lock-join" => join_dialog(core, "ws1", "st2", "MBA")
    "lock-off" => turn_off_dialog(core, "ws1", "星火工作室")
    "local-fonts" => @sfpages.local_open.val = true
    "connect-mode" =>
      match items((core.topic)("connects", { "scope": str("ws1"), "mine": Json::boolean(false) }).value, "items") {
        [item, ..] => @sfpages.cd_mode_dialog(core, "ws1/st1", Some(item))
        _ => ()
      }
    "new-connect" => @sfpages.new_connect_dialog(src, core, @settings.here_of(core, "ws1", "星火工作室"), "ws1/st1")
    "vault-add" => @sfpages.fx_vault_add_up.val = true
    "vault-editor" => @sfpages.vault_editor_dialog(core, "ws1", "v1", None, kind="token")
    "vault-recover" => @sfpages.vault_recover_dialog(core, "ws1")
    _ => ()
  }
}

///|
/// What the settings pages here keep put back as the app begins anew.
fn settings_reset() -> Unit {
  settings_deep.val = false
}

///|
/// The settings' sidebar: back to the chats, then the settings' list (sfpages' settings_list.mbt: the same rows in the
/// same groups as a small screen's settings page), the row of the page beside it lit; a row pressed, its page beside
/// it, in place of the one there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let lit = match app.nav.top() {
    Setting(r) => Some(@sfpages.settings_row_of(r))
    // (the settings come to: their first row's page, settings_landing)
    Settings => Some(settings_landing)
    _ => None
  }
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  c.box(style=settings_side_fill, fn() {
    side_top(c)
    // The way back belongs to the sidebar's band, not to the list that scrolls beneath it.
    // (none beside the system's tabs: 对话 is one of them, rail_native.mbt)
    let updating = update_shown()
    if updating {
      // The update and the back action share the same band as the other sidebars' actions: the band's spacing gives
      // each key its press room, and keeps the update concentric with the sidebar's corner.
      let band = if @sf.native_on() { update_band() } else { update_back_band() }
      c.box(style=band, fn() {
        c.box(style=side_full, fn() {
          if !@sf.native_on() {
            settings_back(c, true)
          }
        })
        |> ignore
        update_in_row(c, src)
      })
      |> ignore
    } else if !@sf.native_on() {
      c.box(style=@sf.side_list().then(settings_back_band), fn() { settings_back(c, false) }) |> ignore
    }
    side_scroll(c, "settings-nav", fn() {
      // (a row's page in place of the one open; on the tape brought over to show it)
      @sfpages.settings_side_rows(c, core, here, lit, fn(r) {
        @sfbase.history_push()
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        app.nav.push(Setting(r))
        @sfbase.show_chosen()
      })
    })
  })
  |> ignore
}

///|
/// The way back, a band's action when the update is beside it; otherwise the settings list's own row.
fn settings_back(c : @ui.Ctx, band : Bool) -> Unit {
  let t = @sf.theme()
  let body = fn() {
    @sf.icon(c, "arrow-left", size=settings_nav_icon, color=t.p.muted) |> ignore
    nav_words(c, @sf.t("web-pages.settings.nav.backToChats"))
  }
  let pressed = if band {
    band_row(c, "settings-nav/back", false, body)
  } else {
    nav_row(c, "settings-nav/back", false, body)
  }
  if pressed {
    @sfbase.history_push()
    while app.nav.depth() > 1 {
      if !app.nav.pop() {
        break
      }
    }
    if app.nav.top() != Home {
      app.nav.replace(Home)
    }
    wide.landed.set("")
  }
}

///|
/// The page the settings come to beside their list on a medium or large screen (the stack's root, the gear pressed):
/// the list's first row's, the account's, as a list's page is the one first in it.
// kept across runs: a value (no field of it changes)
pub let settings_landing : Route = Route::Me

///|
let settings_nav_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let settings_side_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The list supplies four points of its own top room; with the band's ten the groups remain fourteen apart.
// kept across runs: a value (no field of it changes)
let settings_back_band : @ui.Style = @ui.css("h=Hug pb=S2_5")
