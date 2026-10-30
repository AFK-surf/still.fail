// What the settings' pages (src/sfapp/settings) read and call, and how they move (@settings.Core): the core's topics
// and calls, the stack, toasts, the system's pickers and browser, notifications, updates, this Mac's station, the
// faces, the bars; one for every frame (settings_core), what the shell does asked of the shell.

///|
/// What the settings' pages read and call, and how they move: the core as the app has it (Source), the app's stack,
/// the shell's way home (what is over the pages put down too), a station's login as the pages' card (`login_card_of`)
/// and the pages' card to share of the workspace's agents at work (`share_card_of`). One for every frame.
pub fn settings_core(src : Source, w : Workspace) -> @settings.Core {
  settings_core_of(
    src,
    w,
    home=fn() { (shell.val.home)() },
    login_card=fn(c, station, id, marked) { (login_card_of.val)(c, settings_core(src, w), station, id, marked) },
    share_card=fn() { (share_card_of.val)(src, w) },
  )
}

///|
/// A station's login as the pages draw its card (sfpages' login_card), given as the app starts.
// kept across runs: what the app says once as it starts
pub let login_card_of : Ref[(@ui.Ctx, @settings.Core, String, String, Bool) -> Unit] = Ref(fn(_, _, _, _, _) {  })

///|
/// The card to share of the workspace's agents at work, as the pages open it (sfpages' share_card_open), given as the
/// app starts.
// kept across runs: what the app says once as it starts
pub let share_card_of : Ref[(Source, Workspace) -> Unit] = Ref(fn(_, _) {  })

///|
/// settings_core's, its way home (`home`), a station's login card (by station and id, marked) and the card to share
/// (`share_card`) given.
fn settings_core_of(
  src : Source,
  w : Workspace,
  home~ : () -> Unit,
  login_card~ : (@ui.Ctx, String, String, Bool) -> Unit,
  share_card~ : () -> Unit,
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
        @settings.Route::Home => open_page(Settings)
        _ => open_page(Setting(r))
      }
    },
    pop: fn() { go_back() |> ignore },
    in_place: fn(r) { open_in_place(Setting(r)) },
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
      open_page(Chat({ station, session, title, station_name: name }))
    },
    open_drive: fn(station) { open_page(Drive({ station, root: None, path: "" })) },
    open_folder: fn(station, root) { open_page(Drive({ station, root: Some(root), path: "" })) },
    sign_in: fn() { (src.sign_in)() },
    say: fn(words) {
      toast_later(words)
    },
    picture: fn(url, frame) { (src.picture)(url, frame) },
    now: src.now,
    notify_ask: fn() { ask_from_switch() },
    push_sync: fn(wanted) { if !src.read_only { push_sync(src, wanted) } },
    under: fn() {
      match app.nav.under() {
        Some(Home) => "chats"
        Some(Settings | Setting(@settings.Route::Home)) => "settings"
        _ => ""
      }
    },
    version_now: fn() { update_stands() },
    version_tap: fn() { update_row_tapped(src) },
    local_install: fn(join) { if join { local_station_install(src, w.id) } else { local_station_update() } },
    // the system's browser (LocalUriHandler.openUri); nothing took it, said so (android-misc.link.cantOpen)
    open_link: fn(url) {
      if !@ui.open_url(url) {
        toast_later(@sf.t("android-misc.link.cantOpen"))
      }
    },
    open_screen: fn(station, screen) { open_page(Screen({ station, screen, title: "", until_gone: true })) },
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
    reporting: fn() {
      reporting_said.get() |> ignore
      reporting_host.get().map(fn(h) { (h.get)() })
    },
    set_reporting: fn(on) {
      match reporting_host.get() {
        Some(h) => {
          (h.set)(on)
          reporting_said.set(@signals.untracked(fn() { reporting_said.get() }) + 1)
        }
        None => ()
      }
    },
    login_card,
    share_card,
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
pub let reporting_host : @signals.Signal[ReportingHost?] = @signals.signal(None)

///|
/// Told as this device is set to send them or not (what reads it reads the host again).
// kept across runs: only counts on
let reporting_said : @signals.Signal[Int] = @signals.signal(0)
