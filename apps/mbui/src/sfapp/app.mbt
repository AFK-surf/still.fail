// still.fail, as its Android app is (ember apps/android app/App.kt): signed out it is the sign-in page; signed in,
// the chats of one workspace are home (Home.kt), and everything else a page pushed over it (@ui.Nav: sliding in,
// swiped back from the left edge; a new chat rising from the bottom), or a sheet from the bottom (sheet.mbt). The
// places of the bottom bar (bar.mbt) are the pages at the stack's root, switched in place.

///|
/// A page of the stack.
pub(all) enum Page {
  Home
  /// a chat (chat.mbt)
  Chat(ChatRef)
  /// the archived chats (from the filter's menu)
  Archived
  /// settings (the gear)
  Settings
  /// 文件: every station's folders lent (drive.mbt)
  Files
  /// a page of a station's drive: its roots, or a folder (drive.mbt)
  Drive(DriveAt)
  /// a text of a drive, read (drive_reader.mbt)
  DriveRead(DriveAt)
  /// a video or a song of a drive, played (play.mbt)
  DrivePlay(DriveAt)
  /// a web service an agent started, its page (service.mbt): its station, its job
  Service(String, String)
  /// the decisions waiting for the viewer, one at a time (奏: decisions.mbt); the bar's 奏 place
  Decisions
  /// an agent's execution history (history.mbt): its chat, its session
  History(ChatRef, String)
  /// an entry of a history opened in full: the line it was under, its words
  Words(String, String)
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats, 奏 and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
  /// a page under settings (src/sfapp/settings: me, appearance, stations, the workspace…)
  Setting(@settings.Route)
} derive(Eq)

///|
priv struct App {
  mut nav : @ui.Nav[Page]
  /// the workspace switched to here, before the core's prefs say it
  mut picked : String
  /// the list's filter chosen here, by workspace, before the prefs say it
  filters : Map[String, String]
  /// the filter's menu, and when it was opened
  mut menu : Bool
  mut menu_at : Double
  /// a place switched to on the bar: from which side (1 from the right, -1 the left, 0 from no side)
  mut switch_way : Int
  /// a row held: its id, since when (the time shows while it is)
  mut held : Int
  mut held_at : Double
  /// what was said last of a write (a toast), and when
  mut toast : String
  mut toast_at : Double
}

///|
let app : App = {
  nav: new_nav(),
  picked: "",
  filters: {},
  menu: false,
  menu_at: 0.0,
  switch_way: 0,
  held: 0,
  held_at: 0.0,
  toast: "",
  toast_at: 0.0,
}

///|
/// What a page left leaves behind: a chat's topic and what it told the core.
let left_pages : Array[Page] = []

///|
fn new_nav() -> @ui.Nav[Page] {
  @ui.Nav::new(Home, on_leave=fn(p) {
    left_pages.push(p)
    match p {
      Setting(r) => @settings.left(r)
      Archived => @settings.left(@settings.Route::Archive)
      Settings => @settings.left(@settings.Route::Home)
      // a place of the bar's whose page is the settings' (bar.mbt place_page)
      Place(name) =>
        match @settings.route_of(name) {
          Some(r) => @settings.left(r)
          None => ()
        }
      _ => ()
    }
  })
}

///|
/// A page of the settings opened over Home from the start (screenshots of them, a scripted run): by its name
/// (@settings.route_of).
pub fn open_setting(name : String) -> Unit {
  match @settings.route_of(name) {
    Some(@settings.Route::Home) => app.nav.push(Settings)
    Some(r) => {
      app.nav.push(Settings)
      app.nav.push(Setting(r))
    }
    None => ()
  }
}

///|
/// A chat opened over Home from the start (a link, a scripted run).
pub fn open_chat(r : ChatRef) -> Unit {
  app.nav.push(Chat(r))
}

///|
/// A page pushed over Home from the start (a scripted run; the bottom bar's places until there is one).
pub fn open_page(p : Page) -> Unit {
  app.nav.push(p)
}

///|
/// reset() called by hand since the last Tester started: what the test set after it (its clock, its system) is the
/// next Tester's to start from, not forgotten again as it starts.
let reset_by_hand : Ref[Bool] = Ref(false)

///|
/// Every Tester starts from the app as at the start (mbui's on_reset), whatever ran before it in the process: what is
/// kept here from one Tester to the next would be an input the test does not give.
fn init {
  @ui.on_reset(fn() {
    if !reset_by_hand.val {
      reset()
    }
    reset_by_hand.val = false
  })
}

///|
/// As at the start: Home alone, nothing chosen here yet (tests; every Tester as it starts: init above). Each global
/// of this package is put back here (or in what this calls) as its `let` has it, or says why it is kept across runs
/// (scripts/check.sh checks).
fn reset() -> Unit {
  attention.told = false
  attention.visible = false
  attention.focused = false
  attention.workspace = ""
  attention.src = None
  app.nav = new_nav()
  app.picked = ""
  app.filters.clear()
  sheet_host.kind = NoSheet
  sheet_host.shown = NoSheet
  sheet_host.accounts = false
  bar_reset()
  fresh.became = None
  fresh.made = ""
  fresh.made_sig = ""
  fresh.sent = false
  fresh.starting = false
  fresh.scene = None
  new_fix.station = "st1"
  new_fix.model = "claude-opus-5-5"
  new_fix.runtime = "claude"
  new_fix.effort = "high"
  new_fix.d_model = "claude-opus-5-5"
  new_fix.d_runtime = "claude"
  new_fix.d_effort = "high"
  new_fix.d_profile = ""
  new_fix.made = 0
  app.switch_way = 0
  app.menu = false
  app.menu_at = 0.0
  app.held = 0
  app.held_at = 0.0
  reset_row_menu()
  app.toast = ""
  app.toast_at = 0.0
  read_views.clear()
  read_chats.clear()
  readings.clear()
  left_pages.clear()
  playing.clear()
  play_srcs.clear()
  service_pages.clear()
  svc_viewports.clear()
  share_in.shared = None
  share_in.files = []
  share_in.raised = false
  // (taken: a Tester never reads the machine's MBUI_SHARE_TEXT)
  share_in.env_taken = true
  share_in.searching = false
  share_in.choosing = false
  share_in.opening = None
  share_in.error = ""
  share_in.query = ""
  update.available = None
  update.asked = false
  update.checking = false
  update.installing = false
  update.phase = "idle"
  update.source = None
  update_version.val = 0
  svc_folded.val = false
  splash_first.val = -1.0
  drafts.clear()
  cui.attach = false
  cui.attach_at = 0.0
  cui.picking = None
  cui.picking_for = ""
  cui.was_down = false
  cui.press_new = false
  cui.released = false
  cui.down_x = 0.0
  cui.down_y = 0.0
  cui.down_at = 0.0
  cui.moved = false
  cui.outside = false
  cui.room = 0.0
  cui.doing.clear()
  pick_reset()
  fix_chats.clear()
  fix_timers.clear()
  fix_drafts.clear()
  fix_decided.clear()
  emits.clear()
  fix_kept.val = false
  dv_reset()
  decide_reset()
  close_now()
  @settings.reset()
  go_tos.clear()
  ask_turns.clear()
  flash_held.val = false
  notices_reset()
  wide_reset()
  // the made-up chats and their station (chat_fixture.mbt, service_fixture.mbt, drive_fixture.mbt)
  kept_chats.clear()
  fixture_pictures.clear()
  fix_threads.clear()
  fix_ctx.val = None
  fix_clock.val = fix_frame_clock
  fix_wake.val = fix_frame_wake
  fix_serial.val = 0
  fix_stream_ids.val = 0
  // Home (home.mbt), the host told (above), a chat's page and what is in it
  open_titled.val = ""
  shown_days.clear()
  marks_seen.clear()
  told_bars.val = None
  told_dark.val = None
  send_flight.val = None
  flying.val = None
  absolute_times.val = false
  opened_notices.clear()
  flashing.val = ("", 0.0)
  flash_row.val = None
  at_end_env.val = -1
  bench_on.val = -1
  boxed_n.val = 0
  run_picker_opened.val = false
  run_picker_saving.val = false
  svc_hold.val = -1.0
  // the composer: its ids counted from the start, what waits for it
  next_pending.val = 1
  quote_seeded.clear()
  upload_serial.val = 0
  marked_into.clear()
  shared_into.clear()
  share_files_made.val = 0
  recent.open = false
  recent.answers = -1
  recent.access = NoGallery
  recent.reading = None
  recent.photos = []
  // the viewer (preview.mbt, preview_marks.mbt: marks_leave above)
  marking.color = 0xE5704AFFL
  marking.next_id = 1
  marking.to_draft = false
  marking.job_name = ""
  marking.write_text = ""
  marking.note_text = ""
  pv_thumbs.clear()
  pv_hidden.val = ""
  pv_read.clear()
  pv_strip.leaving = None
  pv_strip.pinned = None
  pv_strip.near.clear()
  viewer_awake_env.val = -1
  src_now.val = fn() { 0.0 }
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  dv_fetches.clear()
  keepings.clear()
  reader_mds.clear()
  // the wide frame's keys (wide_keys.mbt)
  focus_composer.val = false
  switcher_query.val = ""
  rename_for.val = ""
  rename_seen.val = false
  reset_by_hand.val = true
}

///|
/// Back to Home (the stack's root), the sheets and the menu closed.
fn home() -> Unit {
  lower_sheet()
  app.menu = false
  dui.sheet = None
  dui.leaving = None
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
}

///|
/// The app over `src`: call each frame.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  fix_ctx.val = Some(c)
  appearance(src)
  let t = @sf.begin(c)
  // a desktop's width: the web app's wide frame (wide.mbt); below it the phone's pages
  wide_on.val = is_wide(c)
  @settings.wide.val = wide_on.val
  track_press(c)
  for p in left_pages {
    match p {
      Chat(r) => chat_left(src, r)
      DriveRead(at) => reader_left(at)
      DrivePlay(at) => play_left(at)
      Service(station, job) => service_left(src, station, job)
      History(r, key) => history_left(src, r, key)
      _ => ()
    }
  }
  left_pages.clear()
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let accounts = (src.topic)("accounts", {})
    match (accounts.value, (src.fatal)()) {
      (_, Some(why)) => splash(c, Some(why), true)
      (Some(Array(list)), _) if list.length() == 0 => sign_in_page(c, src)
      (Some(Array(_)), _) => signed_in(c, src)
      (_, _) =>
        splash(
          c,
          match accounts.error {
            Some(e) => Some(text(Some(e), "message"))
            None => None
          },
          accounts.error is Some(_),
        )
    }
  })
  |> ignore
}

///|
/// Signed in: the workspace in view (the one switched to, else the one last open, else the first once every account
/// has answered), its Home at the root of the pages; the splash while none is known yet, and a page that says so when
/// there is none.
fn signed_in(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let ws = (src.topic)("workspaces", {})
  let prefs = (src.topic)("prefs", {})
  let (all, answered, invited) = workspaces_of(ws.value)
  let kept = if app.picked != "" {
    app.picked
  } else {
    text(prefs.value, "workspace")
  }
  let current = match all.iter().find_first(fn(w) { w.id == kept }) {
    Some(w) => Some(w)
    None =>
      if all.length() > 0 && (kept == "" || answered) {
        Some(all[0])
      } else {
        None
      }
  }
  match current {
    Some(w) => {
      attend(src, w.id)
      // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off
      notices_frame(src, w)
      // a newer build of the app asked for once (updates.mbt)
      update_first(src)
      // what another app shared in (share.mbt)
      share_in_frame(c)
      // files being kept on the device, said once kept (keep.mbt)
      keeps_frame(c)
      if wide_on.val {
        // the rail, the sidebar and the page beside it (wide.mbt); what opens over them after them
        wide_frame(c, src, w, all, invited)
        wide_overlays(c, src, w)
        pick_back(c)
        preview(c, src)
      } else {
        c.nav(app.nav, fn(page) { page_view(c, src, w, all, invited, page) }, bg=t.p.bg)
        |> ignore
        // a place's top page other than the chats, with nothing over it: back goes to the chats, in place
        let root = app.nav.top()
        if app.nav.depth() == 1 && root != Home && !app.menu && !sheet_open() {
          c.on_back(fn() { go_place(c, "chats", [], -1) })
        }
        // the player sideways: back turns it upright first
        play_back(c)
        // words picked in a chat, a link's menu: back lets go of them first (pick.mbt)
        pick_back(c)
        // the bottom bar: on a place's top page with nothing over it
        bottom_bar(c, src, w, place_of(root), app.nav.depth() == 1 && place_of(root) is Some(_))
        // a file open over the pages (preview.mbt), under the menu, the sheet and the toasts
        preview(c, src)
        filter_menu(c, src, w)
        // a row's menu, held long (home_menu.mbt)
        home_row_menu(c, src)
      }
      sheet_layer(c, fn(kind) {
        match kind {
          Workspaces => workspaces_sheet(c, src, w, all)
          PickStation(scope) => pick_station_sheet(c, src, scope)
          RunPicker(station) => run_picker_sheet(c, src, station)
          LoadOf(station, port) => load_sheet(c, src, station, port)
          PageSizes(key) => page_sizes_sheet(c, key)
          ShareSheet => share_in_sheet(c, src, w)
          NoSheet => ()
        }
      })
      // a chat's sheets (slice 8's: sheets.mbt, framed in decide.mbt)
      sheets(c, src, w)
      @settings.overlay(c, settings_core(src, w))
      toast(c)
    }
    None =>
      if ws.value is Some(_) && answered {
        no_workspace(c, ws.value)
      } else {
        let failed = match ws.error {
          Some(e) => Some(text(Some(e), "message"))
          None => None
        }
        splash(
          c,
          Some(failed.unwrap_or(t_reading_workspaces(src))),
          failed is Some(_),
        )
      }
  }
}

///|
/// 正在读取你的 workspace, with what the core has been waiting on for a while under it (`status`).
fn t_reading_workspaces(src : Source) -> String {
  let status = (src.topic)("status", {})
  match text(status.value, "text") {
    "" => tr("android-misc.workspaces.loading")
    s => tr("android-misc.workspaces.loading") + "\n" + s
  }
}

///|
fn page_view(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  all : Array[Workspace],
  invited : Bool,
  page : Page,
) -> Unit {
  // a place switched to on the bar comes in from the side the ball goes to, fading in (220 ms; 180 from no side)
  let root = app.nav.depth() == 1
  let e = if root { place_switch(c).get() } else { 1.0 }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    tx=app.switch_way.to_double() * 30.0 * (1.0 - e),
    opacity=e,
    fn() {
      match page {
        // a device waiting to be confirmed in the workspace's safe mode sees that instead of the chats (its
        // stations refuse it: Security.kt LockGate); its settings stay
        Home =>
          if lock_gate(c, src, w) {
            home_page(c, src, w, all, invited)
          }
        Chat(r) => {
          chat_page(c, src, w, r)
          new_chat_leaving(c, src, w, r)
        }
        NewChat => new_chat_page(c, src, w)
        Place(p) => place_page(c, src, w, p)
        // 文件: a place of the bar at the stack's root, else a page pushed
        Files => files_page(c, src, w, place=app.nav.depth() == 1)
        Drive(at) => drive_page(c, src, w, at)
        DriveRead(at) => reader_page(c, src, at)
        DrivePlay(at) => play_page(c, src, at)
        Service(station, job) => service_page(c, src, station, job)
        Archived => setting_page(c, src, w, @settings.Route::Archive)
        Settings => setting_page(c, src, w, @settings.Route::Home)
        Setting(r) => setting_page(c, src, w, r)
        // 奏: a place of the bar at the stack's root, else a page pushed
        Decisions => decisions_page(c, src, w)
        History(r, key) => history_page(c, src, r, key)
        Words(head, words) => words_page(c, src, head, words)
      }
    },
  )
  |> ignore
}

///|
/// A place from the bottom bar (AppState.place): its page takes the stack's root, in place (nothing to go back to),
/// coming in from the side the ball goes to (App.kt placeSwitch); the same place again changes nothing. `sets`, `cur`:
/// the bar it is chosen in (none: from no side).
fn go_place(c : @ui.Ctx, place : String, sets : Array[Array[String]], cur : Int) -> Unit {
  let page = match place {
    "chats" => Home
    "files" => Files
    "decisions" => Decisions
    p => Place(p)
  }
  if app.nav.depth() == 1 && app.nav.top() == page {
    return
  }
  lower_sheet()
  app.menu = false
  let from = match place_of(app.nav.top()) {
    Some(p) => p
    None => ""
  }
  let bar_now = if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }
  let a = bar_now.search(from).unwrap_or(-1)
  let b = bar_now.search(place).unwrap_or(-1)
  app.switch_way = if a < 0 || b < 0 || a == b {
    0
  } else if b > a {
    1
  } else {
    -1
  }
  // it comes in from here (Arrive)
  let fade = place_switch(c)
  fade.snap(0.0)
  fade.animate(1.0, @motion.tween(if app.switch_way == 0 { switch_fade_ms } else { switch_side_ms }, ease=Arrive))
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  app.nav.replace(page)
}

///|
/// A page of the settings (src/sfapp/settings), over the workspace in view.
fn setting_page(c : @ui.Ctx, src : Source, w : Workspace, r : @settings.Route) -> Unit {
  let core = settings_core(src, w)
  // in the wide frame, a page under another of them shows back (the sidebar is the way to the others)
  let pages = app.nav.pages()
  @settings.wide_deep.val = pages.length() >= 2 && pages[pages.length() - 2] is Setting(_)
  @settings.page(c, core, @settings.here_of(core, w.id, w.name), r)
}

///|
/// The workspace's safe mode in its chats' place while this device waits to be confirmed in it (the settings'
/// lock_wait.mbt): true when there is nothing to wait for, and the page is the caller's to draw.
fn lock_gate(c : @ui.Ctx, src : Source, w : Workspace) -> Bool {
  let core = settings_core(src, w)
  if !@settings.lock_waiting(core, w.id) {
    return true
  }
  @settings.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
  false
}

///|
/// What the settings' pages read and call, and how they move: the core as the app has it (Source), the app's stack.
fn settings_core(src : Source, w : Workspace) -> @settings.Core {
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
    home: fn() { home() },
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
      app.toast_at = -1.0
    },
    picture: fn(url) { (src.picture)(url) },
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
  }
}

///|
/// How long a place switched to on the bar takes to come in: fading in from no side, from the side the ball goes to.
let switch_fade_ms : Double = 180.0

///|
let switch_side_ms : Double = 220.0

///|
/// How far a place switched to on the bar has come in (0 … 1).
fn place_switch(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "place/switch", 1.0, global=true)
}

///|
/// Light or dark, as this device is set (the prefs' `appearance`, Appearance.kt), or as the system is (@host.system_dark)
/// when it follows it; the host told when it changes (its bars follow).
fn appearance(src : Source) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let dark = @settings.dark(prefs, @ui.system_dark())
  @sf.set_dark(Some(dark))
  // (the host told once the prefs are read: not the system's first, then the one chosen)
  if prefs is Some(_) && told_dark.val != Some(dark) {
    told_dark.val = Some(dark)
    // (said on the log for scripted runs: e2e/flows checks the theme was taken)
    @host.log(if dark { "theme: dark" } else { "theme: light" })
  }
  // the system bars follow the page under them: the player's and a picture's or a video's in the viewer are dark
  // whatever the theme, a reader's as dark as its paper
  let bars = match page_dark(src) {
    Some(d) => d
    None => dark
  }
  if prefs is Some(_) && told_bars.val != Some(bars) {
    told_bars.val = Some(bars)
    @host.set_dark(bars)
  }
}

///|
let told_bars : Ref[Bool?] = Ref(None)

///|
let told_dark : Ref[Bool?] = Ref(None)

///|
/// What a write said (Sheet.kt ToastHost), mbui's toast (@kit.toaster) in still.fail's look: over the foot (90 above
/// it), in ink, 2.6 s (paused while the pointer is on it), coming in and going out; one said again is a new one.
fn toast(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  // said from a call's answer, between frames: from this frame on
  if app.toast != "" && app.toast_at < 0.0 {
    app.toast_at = c.now()
  }
  let said = if app.toast != "" { [@kit.toast("t\{app.toast_at}", app.toast)] } else { [] }
  let r = @kit.toaster(c, "toast", said, duration=toast_ms, bottom=90.0, look=fn(c, s, _action, _close) {
    let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
    c.box(padx=16.0, pady=10.0, bg=t.p.text, radius=18.0, opacity=k, tx=s.dx, fn() {
      c.text(s.toast.title, size=14.0, color=t.p.bg, line=20.0) |> ignore
    })
    |> ignore
  })
  if app.toast != "" && r.open.is_empty() {
    app.toast = ""
  }
}

///|
/// How long a toast stays (paused while the pointer is on it).
let toast_ms : Double = 2600.0

///|
fn say(c : @ui.Ctx, words : String) -> Unit {
  app.toast = words
  app.toast_at = c.now()
}

///|
/// The app starting, or waiting for what every page needs (Parts.kt Splash): still.fail's mark floating; what it
/// waits for said only once it takes a while (a second), or at once when `now` (a failure).
fn splash(c : @ui.Ctx, label : String?, now : Bool) -> Unit {
  let t = @sf.theme()
  let since = splash_since(c)
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    pad=24.0,
    gap=16.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      let lift = if c.stable() {
        0.0
      } else {
        c.request_frame()
        // 900 ms up, 900 down, eased
        let k = c.now() / splash_float_ms
        let f = k - k.floor()
        let p = if f < 0.5 { f * 2.0 } else { 2.0 - f * 2.0 }
        p * p * (3.0 - 2.0 * p)
      }
      c.box(ty=-5.0 * lift, fn() {
        @sf.drawable(
          c,
          if t.dark {
            "stillfail_mark_dark"
          } else {
            "stillfail_mark"
          },
          56.0,
        )
        |> ignore
      })
      |> ignore
      match label {
        Some(s) => {
          let shown = now || c.now() - since > splash_label_ms
          if !shown {
            c.wake_in(splash_label_ms - (c.now() - since))
          }
          c.box(opacity=if shown { 1.0 } else { 0.0 }, fn() {
            c.text(s, size=13.0, color=t.p.muted, center=true, line=18.0)
            |> ignore
          })
          |> ignore
        }
        None => ()
      }
    },
  )
  |> ignore
}

///|
/// How long the splash waits before it says what it waits for.
let splash_label_ms : Double = 1000.0

///|
/// The splash's mark floating: up and down once in this long.
let splash_float_ms : Double = 1800.0

///|
let splash_first : Ref[Double] = { val: -1.0 }

///|
fn splash_since(c : @ui.Ctx) -> Double {
  if splash_first.val < 0.0 {
    splash_first.val = c.now()
  }
  splash_first.val
}

///|
/// Signed out (SignIn.kt SignInScreen): the illustration, what still.fail is for, and 登录或注册.
fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  let t = @sf.theme()
  let busy = (src.signing_in)()
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    padx=30.0,
    pady=40.0,
    gap=12.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_sign_in_dark"
        } else {
          "illus_sign_in"
        },
        dmin(300.0, c.width - 60.0),
      )
      |> ignore
      c.box(pt=10.0, fn() {
        c.text(
          tr("android-settings.signIn.title"),
          size=28.0,
          weight=700,
          color=t.p.text,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
      c.text(
        tr("android-settings.signIn.note"),
        size=15.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=21.0,
      )
      |> ignore
      c.box(h=Px(6.0), fn() {  }) |> ignore
      let id = c.id("sign-in")
      if c.clicked(id) && !busy {
        (src.sign_in)()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(50.0),
        radius=25.0,
        bg=if c.pressed(id) {
          @sf.mix(t.p.text, 0.85, t.p.bg)
        } else {
          t.p.text
        },
        align=ACenter,
        justify=JCenter,
        id~,
        fn() {
          c.text(
            if busy {
              tr("common.opening")
            } else {
              tr("android-settings.signIn.google")
            },
            size=16.0,
            weight=600,
            color=t.p.bg,
            wrap=false,
          )
          |> ignore
        },
      )
      |> ignore
      c.text(
        tr("android-settings.signIn.many"),
        size=12.0,
        color=t.p.muted,
        wrap=false,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
/// Signed in, with no workspace yet (Workspaces.kt Landing): said so. (Making one, or joining by an invitation, is
/// a later slice's.)
fn no_workspace(c : @ui.Ctx, ws : Json?) -> Unit {
  let t = @sf.theme()
  let email = match ws {
    Some(Array(a)) if a.length() > 0 => text(field(Some(a[0]), "account"), "email")
    _ => ""
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    padx=24.0,
    pady=40.0,
    gap=12.0,
    align=ACenter,
    fn() {
      @sf.drawable(
        c,
        if t.dark {
          "illus_sign_in_dark"
        } else {
          "illus_sign_in"
        },
        dmin(260.0, c.width - 48.0),
      )
      |> ignore
      c.text(
        tr("android-misc.workspace.none"),
        size=22.0,
        weight=700,
        color=t.p.text,
        center=true,
        w=Fill(1.0),
      )
      |> ignore
      c.text(
        fill("android-misc.workspace.none.lead", [
          ("app", "still.fail"),
          ("email", email),
        ]),
        size=14.0,
        color=t.p.muted,
        center=true,
        w=Fill(1.0),
        line=20.0,
      )
      |> ignore
    },
  )
  |> ignore
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// What this app last told the core of its attention (`client.focus`): shown, in front, the workspace in view; and
/// where to tell it again when the system says the app left the front between frames.
priv struct Attention {
  mut told : Bool
  mut visible : Bool
  mut focused : Bool
  mut workspace : String
  mut src : Source?
}

///|
let attention : Attention = {
  told: false,
  visible: false,
  focused: false,
  workspace: "",
  src: None,
}

///|
/// Tells the core where this app's attention is, as the Android app's activity and App.kt do: shown and in front or
/// not (`client.focus {visible, focused}`, as the system says: @ui.app_visible, app_focused) and the workspace in view
/// (`workspace`); a chat's own place (`chat`, `left`) is chat.mbt's. Only a change is told. What is read follows from
/// it: the core marks a chat read only while a page in view (visible) shows its end, and shows no notice of a chat
/// one in front shows.
fn attend(src : Source, workspace : String) -> Unit {
  if attention.src is None {
    // the system's say between frames (Android's activity pausing: no frame comes after it)
    @ui.on_app_change(fn(_, _) {
      match attention.src {
        Some(s) => attend(s, attention.workspace)
        None => ()
      }
      notices_app_change(@ui.app_visible())
    })
  }
  attention.src = Some(src)
  let visible = @ui.app_visible()
  let focused = @ui.app_focused()
  if attention.told &&
    visible == attention.visible &&
    focused == attention.focused &&
    workspace == attention.workspace {
    return
  }
  attention.told = true
  attention.visible = visible
  attention.focused = focused
  attention.workspace = workspace
  let params : Map[String, Json] = {
    "visible": Json::boolean(visible),
    "focused": Json::boolean(focused),
    "workspace": Json::string(workspace),
  }
  (src.call)("client.focus", Json::object(params), fn(_) {  })
}
