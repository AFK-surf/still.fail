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
  {
    topic: fn(name, params) {
      let topic = src.topic(name, params)
      let read = fn() -> @settings.Read {
        let t = topic.get()
        { value: t.value, error: t.error, version: t.version }
      }
      @signals.computed_scoped(fn(_) { read() }, untracked_read=Some(fn() {
        if held_building.val { Some(read()) } else { None }
      }))
    },
    call: fn(name, params, done) { (src.call)(name, params, done) },
    push: fn(r) {
      match r {
        @settings.Route::Home => open_page(Settings)
        // (an account's page once what it shows is answered, the screen as it was meanwhile: account_open.mbt)
        _ => open_answered(src, route_asks(w.id, r), fn() { open_page(Setting(r)) }) |> ignore
      }
    },
    pop: fn() { go_back() |> ignore },
    in_place: fn(r) { open_in_place(Setting(r)) },
    home,
    open_chat: fn(station, session, title) {
      // its station's name, as the chats' rows have it
      let stations = station_rows(src, w.id)
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
    version_check: fn() { update_dialog(src) },
    update_auto_on,
    local_install: fn(join) { if join { local_station_install(src, w.id) } else { local_station_update() } },
    // the system's browser (LocalUriHandler.openUri); nothing took it, said so (android-misc.link.cantOpen)
    open_link: fn(url) {
      if !@ui.open_url(url) {
        toast_later(@sf.t("android-misc.link.cantOpen"))
      }
    },
    open_screen: fn(station, screen) { open_page(Screen({ station, screen, title: "", until_gone: true })) },
    pick_picture: fn(done) {
      @ui.pick(@hostapi.PickKind::Photos, on_got=fn(files) { done(files.get(0).map(fn(f) { f.bytes })) }) is Some(_)
    },
    bars: fn() { bars_in(src, w.id) },
    set_bars: fn(sets, cur) { set_bars(src, w.id, sets, cur) },
    place_icon: fn(c, place, color) {
      if place == "stations" {
        // one station on, as no station is meant
        let still : @sf.GlyphCounts = { online: 1, dim: 0, failing: 0, working: 0, asleep: false, connecting: 0 }
        @sf.station_glyph(c, still, 28.0, color, @sf.theme().p.red) |> ignore
      } else {
        @sf.icon(c, place_icon(place), size=28.0, color~) |> ignore
      }
    },
    reporting: fn() { reporting_on(src) },
    set_reporting: fn(on) {
      match reporting_host.get() {
        Some(h) => {
          (h.set)(on)
          reporting_said.set(Some(on))
        }
        // (where the core sends what people use and the host keeps no switch: the prefs' `reports`)
        None =>
          @settings.set_pref_with(
            fn(name, params, done) { (src.call)(name, params, done) },
            fn(said) { toast_later(said) },
            "reports",
            if on {
              ""
            } else {
              "off"
            },
          )
      }
    },
    login_card,
    share_card,
    face_preview: fn(id, index, variable) { face_preview(src, id, index, variable) },
    face_here: face_here,
    face_failed: face_failed,
    own_code_face: own_code_preview,
    read_only: if src.read_only { read_only_words } else { "" },
    devices_on: src.asks_devices,
  }
}

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
/// Whether this device's core sends what people use (client/core-ts/src/use-counts.ts: a build given still.fail's
/// PostHog project, on still.fail's own cloud), as its `client.reports` answered (`sends`); false till then, and under
/// a Tester, whose core says nothing of it.
pub let core_sends : @signals.Signal[Bool] = @signals.signal(false)

///|
/// Whether usage statistics and error reports go out from this device: as the host's switch is, where it keeps one;
/// else, where the core sends what people use, as the prefs' `reports` say (on unless `off`); None where nothing is
/// sent (no settings row then).
pub fn reporting_on(src : Source) -> Bool? {
  reporting_said.get() |> ignore
  match reporting_host.get() {
    Some(h) => Some((h.get)())
    None =>
      if core_sends.get() {
        Some(@settings.pref_from(src.topic("prefs", {}).get().value, "reports") != "off")
      } else {
        None
      }
  }
}

///|
/// The core told whether to count what people use on this device (`client.reports`, use-counts.ts) as the settings
/// say (reporting_on; where nothing says, on: the core sends nothing anyway unless it can), and as they change; its
/// answer says whether it sends at all (core_sends). Said as the app starts, before what it counts.
pub fn tell_reports(src : Source, on : Bool) -> Unit {
  (src.call)("client.reports", { "on": Json::boolean(on) }, fn(r) {
    match r {
      Ok(Object(m)) => core_sends.set(m.get("sends") is Some(True))
      _ => ()
    }
  })
}

///|
/// What this device was last set here to send them or not (None: not set here; what reads it reads the host again as
/// it is set otherwise).
// kept across runs: put back with the host (pages_reset)
let reporting_said : @signals.Signal[Bool?] = @signals.signal(None, same=fn(a, b) { a == b })
