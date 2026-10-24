// The sidebars of the wide frame's places other than the chats' and the files' (sfdesk's: lists.mbt, chats.mbt,
// files_nav.mbt), given to it as `desk_pages().side`: the settings' pages (cloud/settings.tsx SettingsNav), the
// stations' and the profiles' lists (wide_places.mbt).

///|
/// A place's sidebar `width` wide.
fn sidebar(c : @ui.Ctx, src : Source, w : Workspace, width : Double) -> Unit {
  ignore(width)
  match @sfdesk.lit_place() {
    "stations" => stations_side(c, src, w)
    "profiles" => profiles_side(c, src, w)
    _ => settings_side(c, src, w)
  }
}

// ── settings (cloud/settings.tsx SettingsNav) ───────────────────────────

///|
/// The settings' sidebar: back to the chats, then its pages by where they act (this device, the stations, the cloud);
/// those in the rail (Station, Profile, 连接, 用量) are reached there.
fn settings_side(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  let t = @sf.theme()
  let here = match app.nav.top() {
    // (a page under one of them: that one lit)
    Setting(@settings.Route::StationArchiving(_)) => Some(@settings.Route::Archiving)
    Setting(@settings.Route::AutoCompletion) | Setting(@settings.Route::AutoPolicy(_)) =>
      Some(@settings.Route::AutoDecisions)
    Setting(r) => Some(r)
    Settings => Some(@settings.Route::Appearance)
    Archived => Some(@settings.Route::Archive)
    _ => None
  }
  let rails = @sfdesk.rail_items(src, w.id)
  let page = fn(r : @settings.Route, key : String, icon : String, label : String) {
    if @sfdesk.nav_row(c, "settings-nav/" + key, here == Some(r), fn() {
        @sf.icon(c, icon, size=16.0, color=t.p.muted) |> ignore
        @sfdesk.nav_words(c, label)
      }) {
      while app.nav.depth() > 1 {
        if !app.nav.pop() {
          break
        }
      }
      app.nav.push(Setting(r))
    }
  }
  let here_of = @settings.here_of(settings_core(src, w), w.id, w.name)
  c.box(w=Fill(1.0), h=Fill(1.0), fn() {
    @sfdesk.side_top(c)
    c.box(w=Fill(1.0), h=Fill(1.0), padx=8.0, pt=4.0, fn() {
      if @sfdesk.nav_row(c, "settings-nav/back", false, fn() {
          @sf.icon(c, "arrow-left", size=16.0, color=t.p.muted) |> ignore
          @sfdesk.nav_words(c, tr("web-pages.settings.nav.backToChats"))
        }) {
        while app.nav.depth() > 1 {
          if !app.nav.pop() {
            break
          }
        }
        if app.nav.top() != Home {
          app.nav.replace(Home)
        }
        @sfdesk.wide.landed = ""
      }
      @sfdesk.nav_heading(c, tr("web-pages.settings.nav.client"))
      page(@settings.Route::Appearance, "appearance", "sliders", tr("web-pages.settings.nav.appearance"))
      page(@settings.Route::Notifications, "notifications", "bell", tr("web-pages.settings.nav.notifications"))
      page(@settings.Route::Permissions, "permissions", "key", tr("web-pages.settings.nav.permissions"))
      page(@settings.Route::Changelog, "changelog", "sparks", tr("web-pages.settings.nav.changelog"))
      page(@settings.Route::About, "about", "info", tr("web-pages.settings.nav.about"))
      // the desktop's own (cloud/settings.tsx: the client's part)
      page(@settings.Route::Shortcuts, "shortcuts", "command", tr("web-pages.settings.nav.shortcuts"))
      page(@settings.Route::Version, "version", "info", tr("web-pages.settings.nav.version"))
      if @ui.platform() == 0 {
        page(@settings.Route::LocalStation, "local-station", "monitor", tr("web-pages.localStation.title"))
      }
      @sfdesk.nav_heading(c, "Station")
      if !rails.contains("stations") {
        page(@settings.Route::Stations, "stations", "server", "Station")
      }
      if !rails.contains("connects") {
        page(@settings.Route::Connects(""), "connects", "im", tr("web-pages.settings.nav.connects"))
      }
      if !rails.contains("profiles") {
        page(@settings.Route::Profiles(""), "profiles", "quota", "Profile")
      }
      page(@settings.Route::Archiving, "archive", "archive", tr("web-pages.archiving.title"))
      page(@settings.Route::AutoDecisions, "automatic-decisions", "check", tr("web-pages.automaticDecisions.title"))
      page(@settings.Route::Memories, "memory", "brain", tr("web-pages.settings.nav.memory"))
      if !rails.contains("usage") {
        page(@settings.Route::Usage, "usage", "chart", tr("web-pages.settings.nav.usage"))
      }
      @sfdesk.nav_heading(c, "Cloud")
      page(@settings.Route::Workspace, "workspace", "users", "Workspace · " + w.name)
      page(@settings.Route::Security, "security", "shield-check", tr("web-pages.security.title"))
      page(@settings.Route::Vault, "vault", "key", tr("web-pages.vault.title"))
      page(@settings.Route::Me, "account", "user", if here_of.email != "" { here_of.email } else { w.email })
    })
    |> ignore
  })
  |> ignore
}
