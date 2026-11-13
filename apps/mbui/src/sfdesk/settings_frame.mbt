// The settings as the desktop has them (SettingsNav): the sidebar of
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
  @settings.page(c, core, here, route)
}

///|
/// The settings' pages, one for every frame, by route: drawn in the frame it is shown in (the Small stack's, the wide
/// frame's pane: back, the room over and under it). False for a route whose page every frame makes once in its place
/// (关于, 更新日志, 记忆, 一台 station 的记忆, 用量, 价目表: pane_made, tape_made, narrow_made), and for one whose pages are not one yet (its frame draws its
/// own copy).
pub fn setting_route(c : @ui.Ctx, src : Source, w : Workspace, route : Route, frame : PageFrame) -> Bool {
  if !(route is (Fonts | BarSettings | Me | Vault | VaultItem(_, _))) {
    return false
  }
  let core = settings_core(src, w)
  let here = @settings.here_of(core, w.id, w.name)
  @settings.frame(core, here)
  settings_fixture(src, core)
  match route {
    Fonts => @sfpages.fonts_page(c, core, frame)
    BarSettings => @sfpages.bars_page(c, core, frame)
    Me => @sfpages.me_page(c, core, here, frame)
    Vault => @sfpages.vault_page(c, core, here, frame)
    VaultItem(v, item) => @sfpages.vault_item_page(c, core, here, frame, v, item)
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
/// @settings.fixture_desk), once the page is drawn with what it needs; before it is made where a frame makes it once
/// (pane_made, tape_made, the narrow frame's).
pub fn settings_fixture(src : Source, core : Core) -> Unit {
  match @settings.fixture_desk() {
    "policy-text" => @sfpages.fx_policy_up.val = "text"
    "policy-option" => @sfpages.fx_policy_up.val = "option"
    "lock-join" => join_dialog(core, "ws1", "st2", "Maple")
    "lock-off" => turn_off_dialog(core, "ws1", "星火工作室")
    "local-fonts" => @sfpages.local_open.val = true
    "connect-mode" =>
      // (the first connect listed, as its page has it: the ways it could change are its page's)
      match items((core.topic)("connects", { "scope": str("ws1"), "mine": Json::boolean(false) }).get().value, "items") {
        [row, ..] => {
          let station = text(Some(row), "station")
          let here = @settings.here_of(core, "ws1", "星火工作室")
          match @settings.connect_of(core, here, station, text(field(Some(row), "connect"), "id")) {
            Some(_) as item => @sfpages.cd_mode_dialog(core, station, item)
            None => ()
          }
        }
        _ => ()
      }
    "new-connect" => @sfpages.new_connect_dialog(src, core, @settings.here_of(core, "ws1", "星火工作室"), "ws1/st1")
    "vault-add" => @sfpages.fx_vault_add_up.val = true
    "vault-editor" => @sfpages.vault_editor_dialog(core, "ws1", "v1", None, kind="token")
    "vault-recover" => @sfpages.vault_recover_dialog(core, "ws1")
    "copies-confirm" =>
      match items(@settings.fixture_copies(), "offers") {
        [copy, ..] => @sfpages.copies_restore_confirm(core, "ws1/st1", Some(copy))
        _ => ()
      }
    // (Willow's retirement asked: its ⋯'s 迁走聊天并移出…'s panel, what it would take along as Willow says it)
    "retire-panel" =>
      @sfpages.station_retire_panel(
        core,
        @settings.here_of(core, "ws1", "星火工作室"),
        Some({ "station": Json::string("ws1/st1"), "name": Json::string("Willow") }),
        @settings.fixture_retire_preview(),
      )
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
    Setting(r) => Some(r)
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
    // Without the back row, keep the field below the sidebar's upper corners.
    let search_band = if @sf.native_on() { settings_search_native_band } else { settings_search_band }
    c.box(style=@sf.side_list().then(search_band), fn() { @sfpages.settings_search(c, side_at()) }) |> ignore
    side_scroll(c, "settings-nav", fn() {
      // (a row's page in place of the one open; on the tape brought over to show it)
      @sfpages.settings_side_rows(c, core, here, lit, fn(r) {
        @sfbase.history_push()
        app.nav.replace_above(1, [Setting(r)])
        @sfbase.show_chosen()
      }, side_at())
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
  let back = fn() {
    @sfpages.settings_search_reset()
    @sfbase.history_push()
    @sfbase.nav_over_home([])
    wide.landed.set("")
  }
  if band {
    band_row(c, "settings-nav/back", false, body, at=side_at(), on_press=back)
  } else {
    nav_row(c, "settings-nav/back", false, body, at=side_at(), on_press=back)
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

///|
// kept across runs: a value (no field of it changes)
let settings_search_band : @ui.Style = @ui.css("w=Full h=Hug pt=S0 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let settings_search_native_band : @ui.Style = @ui.css("w=Full h=Hug pt=S5 pb=S2")
