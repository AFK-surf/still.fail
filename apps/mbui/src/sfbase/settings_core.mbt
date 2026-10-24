// What the settings' pages (src/sfapp/settings) read and call, and how they move, as both frames give it them
// (@settings.Core): the core's topics and calls, the stack, toasts, the system's pickers and browser, notifications,
// updates, this Mac's station, the faces, the bars; what differs by frame given by it.

///|
/// What the settings' pages read and call, and how they move, for both frames: the core as the app has it (Source),
/// the app's stack; the frame's own way home (`home`: the phone's sheets put down too) and a station's login as the
/// frame's card (by station and id, marked).
pub fn settings_core_of(
  src : Source,
  w : Workspace,
  home~ : () -> Unit,
  login_card~ : (@ui.Ctx, String, String, Bool) -> Unit,
) -> @settings.Core {
  // a picture asked of the system's picker for a mark: its answer given (the host asks for a frame as it answers)
  match picture_pick.val {
    Some((p, done)) =>
      match p.files() {
        Some(files) => {
          picture_pick.val = None
          done(files.get(0).map(fn(f) { f.bytes }))
        }
        None => ()
      }
    None => ()
  }
  {
    topic: fn(name, params) {
      let t = (src.topic)(name, params)
      { value: t.value, error: t.error, version: t.version }
    },
    call: fn(name, params, done) { (src.call)(name, params, done) },
    push: fn(r) {
      match r {
        @settings.Route::Home => app.nav.push(Settings)
        _ => app.nav.push(Setting(r))
      }
    },
    pop: fn() { app.nav.pop() |> ignore },
    home,
    open_chat: fn(station, session, title) {
      // its station's name, as the chats' rows have it
      let stations = (src.topic)("stations", { "scope": Json::string(w.id) })
      let mut name = ""
      match stations.value {
        Some(Array(a)) =>
          for x in a {
            if text(Some(x), "station") == station {
              name = text(Some(x), "name")
            }
          }
        _ => ()
      }
      app.nav.push(Chat({ station, session, title, station_name: name }))
    },
    open_drive: fn(station) { app.nav.push(Drive({ station, root: None, path: "" })) },
    sign_in: fn() { (src.sign_in)() },
    say: fn(words) {
      app.toast = words
      app.toast_n += 1
    },
    picture: fn(url, frame) { (src.picture)(url, frame) },
    now: src.now,
    notify_ask: fn() { ask_from_switch() },
    push_sync: fn(wanted) { if !src.read_only { push_sync(src, wanted) } },
    under: fn() {
      let pages = app.nav.pages()
      if pages.length() < 2 {
        return ""
      }
      match pages[pages.length() - 2] {
        Home => "chats"
        Settings | Setting(@settings.Route::Home) => "settings"
        _ => ""
      }
    },
    version_words: fn() { update_row_words() },
    version_tap: fn() { update_row_tapped(src) },
    local_install: fn(join) { if join { local_station_install(src, w.id) } else { local_station_update() } },
    // the system's browser (LocalUriHandler.openUri); nothing took it, said so (android-misc.link.cantOpen)
    open_link: fn(url) {
      if !@ui.open_url(url) {
        app.toast = @sf.t("android-misc.link.cantOpen")
        app.toast_n += 1
      }
    },
    pick_picture: fn(done) {
      match @ui.pick(@hostapi.PickKind::Photos) {
        Some(p) => {
          picture_pick.val = Some((p, done))
          true
        }
        None => false
      }
    },
    bars: fn() { bars_in(src, w.id) },
    set_bars: fn(sets, cur) { set_bars(src, w.id, sets, cur) },
    place_icon: fn(c, place, color) {
      if place == "stations" {
        // one station on, as no station is meant (BarSettings.kt Still)
        let still : @sf.GlyphCounts = { online: 1, dim: 0, failing: 0, working: 0, asleep: false, connecting: 0 }
        @sf.station_glyph(c, still, 28.0, color, @sf.theme().p.red) |> ignore
      } else {
        @sf.icon(c, place_icon(place), size=28.0, color~) |> ignore
      }
    },
    reporting: fn() { reporting_host.val.map(fn(h) { (h.get)() }) },
    set_reporting: fn(on) {
      match reporting_host.val {
        Some(h) => (h.set)(on)
        None => ()
      }
    },
    login_card,
    face_preview: fn(id, index, variable) { face_preview(src, id, index, variable) },
    face_here: face_here,
    face_failed: face_failed,
    own_code_face: own_code_preview,
    read_only: if src.read_only { read_only_words } else { "" },
  }
}

///|
/// A picture the settings asked the system's picker for (a station's or workspace's mark, a Slack app's icon), and who
/// takes it: through the framework, so a Tester's picker is the test's (Tester::picks).
pub let picture_pick : Ref[(@ui.Pick, (Bytes?) -> Unit)?] = Ref(None)

///|
/// Whether usage statistics and error reports go out from this device, as the host keeps it (src/stillfail
/// reports.mbt: Android's Crashes.reporting, the app's prefs); None where nothing is sent anyway: no settings row then.
pub(all) struct ReportingHost {
  get : () -> Bool
  set : (Bool) -> Unit
}

///|
/// The host's, set once as the app starts (src/stillfail main); None under a Tester (reset), unless its test sets one.
pub let reporting_host : Ref[ReportingHost?] = Ref(None)
