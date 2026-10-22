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
  /// a visualization as a page of its own (Preview.kt PreviewFileScreen): its station, the session that keeps it, its
  /// path and its name
  PreviewFile(String, String, String, String)
  /// the decisions waiting for the viewer, one at a time (奏: decisions.mbt); the bar's 奏 place
  Decisions
  /// an agent's execution history (history.mbt): its chat, its session, the transcript entry it opens at (a link's
  /// `entry`; None: its newest)
  History(ChatRef, String, Int?)
  /// an entry of a history opened in full: the line it was under, its words
  Words(String, String)
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats, 奏 and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
  /// a page under settings (src/sfapp/settings: me, appearance, stations, the workspace…)
  Setting(@settings.Route)
  /// a station's screen, seen and driven (screen_view.mbt), over the app as Android's ScreenActivity is
  Screen(ScreenAt)
} derive(Eq)

///|
/// A station's screen to view: its station (`<workspace>/<station>`), its id there, and its title until the core says
/// one (the link's own, or the row's it was opened from; "" none).
pub(all) struct ScreenAt {
  station : String
  screen : String
  title : String
} derive(Eq)

///|
priv struct App {
  mut nav : @ui.Nav[Page]
  /// the workspace switched to here, before the core's prefs say it
  mut picked : String
  /// the list's filter chosen here, by workspace, before the prefs say it
  filters : Map[String, String]
  /// the filter's menu open
  mut menu : Bool
  /// a place switched to on the bar: from which side (1 from the right, -1 the left, 0 from no side)
  mut switch_way : Int
  /// a row held: its id, and whether it has been held long (its time on @kit.after)
  mut held : Int
  mut held_long : Bool
  /// what was said last of a write (a toast), and which saying it is (one said again is a new one)
  mut toast : String
  mut toast_n : Int
}

///|
let app : App = {
  nav: new_nav(),
  picked: "",
  filters: {},
  menu: false,
  switch_way: 0,
  held: 0,
  held_long: false,
  toast: "",
  toast_n: 0,
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
  files_cornered.val = false
  felt_menu.val = -1
  felt_past.clear()
  felt_holds.clear()
  attention.told = false
  focus_said.val = ""
  picture_pick.val = None
  bar_glyph.val = None
  bar_stations_said.val = ""
  attention.visible = false
  attention.focused = false
  attention.workspace = ""
  attention.src = None
  app.nav = new_nav()
  home_rows.val = []
  steadies.clear()
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
  bar_timing.val = None
  reporting_host.val = None
  bar_timed.val = None
  app.menu = false
  app.held = 0
  app.held_long = false
  reset_row_menu()
  login_cards_reset()
  update_anchor_reset()
  landing_reset()
  new_ws_reset()
  news_reset()
  app.toast = ""
  read_views.clear()
  read_chats.clear()
  readings.clear()
  kept_places.clear()
  left_pages.clear()
  playing.clear()
  play_srcs.clear()
  screens_open.clear()
  screens_made.val = 0
  screen_uis.clear()
  screen_fix_mode.val = ""
  peeks_reset()
  service_pages.clear()
  svc_viewports.clear()
  viz_loads.clear()
  viz_frames.clear()
  viz_heights.clear()
  viz_full.val = None
  viz_unmade.clear()
  service_files.clear()
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
  share_in.find.set("")
  share_over.val = false
  bars_top.val = 0.0
  bars_foot.val = 0.0
  share_closing.val = false
  update.available = None
  update.asked = false
  update.checking = false
  update.installing = false
  update.phase = "idle"
  update.source = None
  update_version.val = 0
  svc_folded.val = false
  splash_waited.val = false
  drafts.clear()
  cui.attach = false
  cui.picking = None
  cui.picking_for = ""
  cui.was_down = false
  cui.press_new = false
  cui.released = false
  cui.down_x = 0.0
  cui.down_y = 0.0
  cui.down_frame = 0
  cui.moved = false
  cui.outside = false
  cui.long = false
  cui.restore_error.clear()
  sharing.val = None
  cui.room_for = ("", None)
  cui.cap_id = 0
  cui.content_id = 0
  cui.doing.clear()
  pick_reset()
  fix_chats.clear()
  fix_timers.clear()
  fix_due.clear()
  fix_unsaid.clear()
  fix_drafts.clear()
  fix_composers.clear()
  fix_xshared.clear()
  fix_decided.clear()
  fix_replied.clear()
  emits.clear()
  turns_by.clear()
  dv_reset()
  decide_reset()
  close_now()
  @settings.reset()
  go_tos.clear()
  ref_fields.clear()
  go_to_words.clear()
  found_marking.val = ("", [], 0.0)
  search_reset()
  ask_turns.clear()
  flash_held.val = false
  notices_reset()
  faces_reset()
  links_reset()
  wide_reset()
  // the made-up chats and their station (chat_fixture.mbt, service_fixture.mbt, drive_fixture.mbt)
  kept_chats.clear()
  fixture_pictures.clear()
  fix_threads.clear()
  fix_ctx.val = None
  fix_clock.val = None
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
  quote_fields.clear()
  rename_field.set("")
  rename_given.val = ""
  relay_reset()
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
  marking.write_field.set("")
  marking.note_field.set("")
  pv_thumbs.clear()
  pv_hidden.val = ""
  pv_read.clear()
  pv_strip.leaving = None
  pv_strip.pinned = None
  pv_strip.near.clear()
  near_asked.clear()
  viewer_awake_env.val = -1
  src_now.val = fn() { 0.0 }
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  dv_fetches.clear()
  keepings.clear()
  reader_mds.clear()
  // the wide frame's keys (wide_keys.mbt)
  focus_composer.val = false
  switcher_query.val = ""
  switcher_field.set("")
  rename_for.val = ""
  side_rename_field.set("")
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
/// The pages left since a build last began, told so (where each was left, what it held let go).
fn pages_left(src : Source) -> Unit {
  for p in left_pages {
    match p {
      Chat(r) => {
        chat_left(src, r)
        viz_chat_left(r.station, r.session)
      }
      DriveRead(at) => reader_left(at)
      DrivePlay(at) => play_left(at)
      Service(station, job) => service_left(src, station, job)
      PreviewFile(station, key, path, _) => service_left(src, station, "file:" + key + "\n" + path)
      History(r, key, _) => history_left(src, r, key)
      Screen(at) => screen_left(src, at.station, at.screen)
      _ => ()
    }
  }
  left_pages.clear()
}

///|
/// The app over `src`: call each frame.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  fix_ctx.val = Some(c)
  appearance(src)
  faces(src)
  // pictures put up by their address come as the core gives them (a GIF among them moves)
  @sf.picture_of.val = fn(url) { (src.picture)(url) }
  let t = @sf.begin(c)
  // under it all, the app's ground (what shows under the keyboard as it moves, the frame before the page follows it)
  // (the palette's colours are 0xRRGGBBAA; what the host clears to is said as 0xAARRGGBB, a window's background)
  c.set_clear((t.p.bg >> 8) & 0xFFFFFFL)
  // a desktop's width: the web app's wide frame (wide.mbt); below it the phone's pages
  wide_on.val = is_wide(c)
  @settings.wide.val = wide_on.val
  @settings.status_top.val = status_top()
  @settings.nav_foot.val = nav_foot()
  @settings.bar_room.val = if wide_on.val { 0.0 } else { bar_room }
  track_press(c)
  linger_tick(c, src)
  // the screens live in their cards (screen_links.mbt): which are on the screen, their frames acknowledged
  peeks_frame(c, src)
  // pages left: where they were left told once the frame's builds are over (a later build would see them left too)
  if left_pages.length() > 0 {
    c.after_build("pages-left", fn() { pages_left(src) })
  }
  // everything in still.fail's theme, as this frame's palette has it (light or dark, a phone's or a desktop's): the
  // styles' roles (@sf styles.mbt, the pages' own) its ink, its sizes, its corners; the one place it is put
  c.with_theme(@sf.ui_theme(), fn() { view_in(c, src, t) })
}

///|
fn view_in(c : @ui.Ctx, src : Source, t : @sf.Theme) -> Unit {
  // over another app (a share sheet over the app it came from: share.mbt share_over): nothing but the sheet
  if share_over.val {
    over_view(c, src)
    return
  }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    let accounts = (src.topic)("accounts", {})
    match (accounts.value, (src.fatal)()) {
      (_, Some(why)) => splash(c, Some(why), true)
      (Some(Array(list)), _) if list.length() == 0 => {
        sign_in_page(c, src)
        // an invitation's link opened signed out: its sheet over the page, saying to sign in first (links.mbt)
        if !link_later.is_empty() {
          c.tell("links", fn() { signed_out_links(src) })
        }
        sheet_layer(c, fn(kind) { if kind == InviteLink { invite_sheet(c, src) } })
      }
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
      // (told once the frame's builds are over, as the last saw the app and the workspace)
      c.after_build("attend", fn() { attend(src, w.id) })
      // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off (once the
      // frame's builds are over: a build let go of follows no workspace)
      c.after_build("notices", fn() { notices_frame(src, w) })
      // the core and the workspace links are opened against, as the frame ends (links.mbt)
      c.after_build("links", fn() { links_frame(src, w) })
      // a link the system opened the app with, told once: what the core says of it shown by the frame after (Ctx::tell)
      if !link_later.is_empty() {
        c.tell("links-given", fn() { links_given(src) })
      }
      // a newer build of the app asked for once (updates.mbt)
      // (asked once, with the app's version: nothing a build changes)
      update_first(src)
      // what another app shared in (share.mbt)
      share_in_frame(c)
      // files being kept on the device, said once kept (keep.mbt)
      keeps_frame(c)
      if wide_on.val {
        // the rail, the sidebar and the page beside it (wide.mbt); what opens over them after them
        wide_frame(c, src, w, all, invited)
        // a station's screen: over the whole window, as Android's ScreenActivity is over the app
        match app.nav.top() {
          Screen(at) =>
            c.layer(fn() { screen_page(c, src, at.station, at.screen, at.title) }) |> ignore
          _ => ()
        }
        wide_overlays(c, src, w)
        pick_back(c)
        preview(c, src)
        viz_full_layer(c, src)
      } else {
        // a page opened slides in once the core has given what it shows (App.kt Pages: LOCAL_MS at most)
        app.nav.comes_when(fn() { page_ready(src, app.nav.top()) }, page_local_ms)
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
        // the bottom bar: on a place's top page with nothing over it; none while this device waits to be confirmed in
        // the workspace's safe mode (its Home is the wait: lock_gate; App.kt PlaceBar)
        let waiting = root == Home && @settings.lock_waiting(settings_core(src, w), w.id)
        bottom_bar(
          c,
          src,
          w,
          place_of(root),
          app.nav.depth() == 1 && place_of(root) is Some(_) && !search_bar_away() && !waiting,
        )
        // a file open over the pages (preview.mbt), under the menu, the sheet and the toasts
        preview(c, src)
        // a visualization over the whole screen (viz.mbt)
        viz_full_layer(c, src)
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
          InviteLink => invite_sheet(c, src)
          NewWorkspace => new_workspace_sheet(c, src)
          NoSheet => ()
        }
      })
      // a chat's sheets (slice 8's: sheets.mbt, framed in decide.mbt)
      sheets(c, src, w)
      // a new device waiting on this one's code, in any workspace of the person's, over whichever page is open
      // (App.kt LockPrompts): put up when no other sheet is
      @settings.lock_prompts(settings_core(src, w), !sheet_open() && dui.sheet is None)
      @settings.overlay(c, settings_core(src, w))
      toast(c)
    }
    None =>
      if ws.value is Some(_) && answered {
        no_workspace(c, src, ws.value)
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
  if root {
    bar_built(c, page)
  }
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
        PreviewFile(station, key, path, name) => preview_file_page(c, src, station, key, path, name)
        Archived => setting_page(c, src, w, @settings.Route::Archive)
        Settings => setting_page(c, src, w, @settings.Route::Home)
        Setting(r) => setting_page(c, src, w, r)
        // 奏: a place of the bar at the stack's root, else a page pushed
        Decisions => decisions_page(c, src, w)
        History(r, key, entry) => history_page(c, src, r, key, entry)
        Words(head, words) => words_page(c, src, head, words)
        Screen(at) => screen_page(c, src, at.station, at.screen, at.title)
      }
      // the page runs under the status bar; it keeps the paper behind its icons, moving with it (App.kt: the list, a
      // place's top page with the bar and a chat have frosted bars there instead; a book and a film their own)
      let own_top = match page {
        Home | Chat(_) | NewChat | DriveRead(_) | DrivePlay(_) => true
        Place(_) | Files | Decisions => root
        _ => false
      }
      if !own_top && status_top() > 0.0 {
        c.layer(fn() {
          c.box(style=@ui.style(w=Full, h=Fixed(status_top()), bg=Bg), fn() {  }) |> ignore
        })
        |> ignore
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
  // (timed from here: BarTiming)
  bar_placed(from, place)
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
/// A picture the settings asked the system's picker for (a station's or workspace's mark, a Slack app's icon), and who
/// takes it: through the framework, so a Tester's picker is the test's (Tester::picks).
let picture_pick : Ref[(@ui.Pick, (Bytes?) -> Unit)?] = Ref(None)

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
      app.toast_n += 1
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
    // the system's browser (LocalUriHandler.openUri); nothing took it, said so (android-misc.link.cantOpen)
    open_link: fn(url) {
      if !@ui.open_url(url) {
        app.toast = tr("android-misc.link.cantOpen")
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
    login_card: fn(c, station, id, marked) { login_card(c, src, station, id, marked~, fill=true) },
    face_preview: fn(id, index, variable) { face_preview(src, id, index, variable) },
    face_here: face_here,
    face_failed: face_failed,
    own_code_face: own_code_preview,
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
pub let reporting_host : Ref[ReportingHost?] = Ref(None)

///|
/// How long a place switched to on the bar takes to come in: fading in from no side, from the side the ball goes to.
pub let switch_fade_ms : Double = 180.0

///|
pub let switch_side_ms : Double = 220.0

///|
/// How far a place switched to on the bar has come in (0 … 1).
fn place_switch(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "place/switch", 1.0, global=true)
}

///|
/// Light or dark, as this device is set (the prefs' `appearance`, Appearance.kt), or as the system is (@hostapi.system_dark)
/// when it follows it; the host told when it changes (its bars follow).
fn appearance(src : Source) -> Unit {
  let prefs = (src.topic)("prefs", {}).value
  let dark = @settings.dark(prefs, @ui.system_dark())
  @sf.set_dark(Some(dark))
  // (the host told once the prefs are read: not the system's first, then the one chosen)
  if prefs is Some(_) && told_dark.val != Some(dark) {
    told_dark.val = Some(dark)
    // (said on the log for scripted runs: e2e/flows checks the theme was taken)
    @hostapi.log(if dark { "theme: dark" } else { "theme: light" })
  }
  // the system bars follow the page under them: the player's and a picture's or a video's in the viewer are dark
  // whatever the theme, a reader's as dark as its paper
  let bars = match page_dark(src) {
    Some(d) => d
    None => dark
  }
  // (told once the frame's builds are over, as the last saw the page)
  if prefs is Some(_) && told_bars.val != Some(bars) {
    @ui.current().after_build("bars", fn() {
      if told_bars.val != Some(bars) {
        told_bars.val = Some(bars)
        @hostapi.set_dark(bars)
      }
    })
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
  let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", app.toast)] } else { [] }
  // (above the navigation bar the view reaches under: Sheet.kt's navigationBars padding)
  let foot = nav_foot()
  let r = @kit.toaster(c, "toast", said, duration=toast_ms, bottom=90.0 + foot, look=fn(c, s, _action, _close) {
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
pub let toast_ms : Double = 2600.0

///|
fn say(c : @ui.Ctx, words : String) -> Unit {
  ignore(c)
  app.toast = words
  app.toast_n += 1
}

///|
/// The app starting, or waiting for what every page needs (Parts.kt Splash): still.fail's mark floating; what it
/// waits for said only once it takes a while (a second), or at once when `now` (a failure).
fn splash(c : @ui.Ctx, label : String?, now : Bool) -> Unit {
  let t = @sf.theme()
  // a second after the app's first splash, what it waits for is said from then on
  if !splash_waited.val && @kit.after(c, "splash-label", true, splash_label_ms) {
    splash_waited.val = true
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    pad=24.0,
    gap=16.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      // up for half of splash_float_ms, down the other half, eased: a cycle while it shows
      let lift = {
        let f = c.cycle(splash_float_ms)
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
          let shown = now || splash_waited.val
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
/// Whether the app's first splash has waited its second (splash_label_ms): what it waits for said from then on.
let splash_waited : Ref[Bool] = { val: false }

///|
/// Signed out (SignIn.kt SignInScreen): the illustration, what still.fail is for, and 登录或注册.
fn sign_in_page(c : @ui.Ctx, src : Source) -> Unit {
  // inside the bars (SignIn.kt: windowInsetsPadding(systemBars))
  within_bars(c, fn() { sign_in_body(c, src) })
}

///|
fn sign_in_body(c : @ui.Ctx, src : Source) -> Unit {
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
        Some(s) => {
          attend(s, attention.workspace)
          // the screens live in their cards stopped as the app goes behind (ScreenLinks.kt Peek: under STARTED)
          if !@ui.app_visible() {
            peeks_stop_all(s)
          }
        }
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

///|
/// What the system said between frames (@hostapi.system_channel; its handler set as the package starts, before the first
/// frame takes what came with the app's start), to the core: back on screen after `away` ms off it, the
/// core gives up requests that went out before and reconnects links gone quiet (MainActivity.kt wake: `client.wake
/// {away}`, client/core-ts src/wake.ts), and a newer build is asked for again (onStart's checkUpdates); the default
/// network changed, every link it had is taken for dead (NetworkWatch: `client.wake {away: 0, network: true}`).
fn system_said(json : String) -> Unit {
  let v = @json.parse(json) catch { _ => return }
  // a link the system opened the app with (links.mbt): opened once the app can (signed in, its workspace known)
  match field(Some(v), "link") {
    Some(String(url)) => link_later.push(url)
    _ => ()
  }
  // shown over another app, or in its own window again (share.mbt)
  match field(Some(v), "over") {
    Some(True) => share_over.val = true
    Some(False) => share_over.val = false
    _ => ()
  }
  // how far the bars reach in over the view (bars.mbt): edge to edge, or over another app
  let bars = field(Some(v), "bars")
  if bars is Some(Object(_)) {
    bars_top.val = number(bars, "top")
    bars_foot.val = number(bars, "bottom")
  }
  let src = match attention.src {
    Some(s) => s
    None => return
  }
  if src.read_only {
    return
  }
  match field(Some(v), "shown") {
    Some(Object(_) as s) => {
      let away = match field(Some(s), "away") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      (src.call)("client.wake", { "away": Json::number(away) }, fn(_) {  })
      update_check(src, false)
    }
    _ => ()
  }
  // a package handed to the system's installer could not be installed (FilePreview.kt install's toast)
  match field(Some(v), "install") {
    Some(Object(_) as i) if flag(Some(i), "allow") =>
      toast_later(pv_fill("android-chat.file.allowInstall", [("app", "still.fail")]))
    Some(Object(_) as i) =>
      toast_later(pv_fill("android-chat.file.installFailed", [("error", text(Some(i), "error"))]))
    _ => ()
  }
  if flag(Some(v), "network") {
    (src.call)(
      "client.wake",
      { "away": Json::number(0.0), "network": Json::boolean(true) },
      fn(_) {  },
    )
  }
}

///|
/// The system's say has its handler before the first frame (what is posted as the app starts, a link it was opened
/// with, would be left with none).
fn init {
  @ui.on_message(@hostapi.system_channel, fn(json, _) { system_said(json) })
  // what the phone has for 共享调试, as its host says by itself (the app's Android: AdbShare.java)
  @ui.on_message("native:adb.phone", fn(json, _) { @settings.adb_phone_said(json) })
}

///|
/// How long a page opening waits for what the core has on the device (App.kt LOCAL_MS, web motion.ts): never for a
/// station.
let page_local_ms : Double = 100.0

///|
/// Whether the core has answered (a value or why not) for what page `p` shows as it opens (App.kt opening): a chat,
/// an agent's history; any other page is not waited for.
fn page_ready(src : Source, p : Page) -> Bool {
  let answered = fn(t : Topic) { t.value is Some(_) || t.error is Some(_) }
  match p {
    Chat(r) => answered((src.topic)("chat", chat_params(r)))
    History(r, key, _) => answered((src.topic)("chat", chat_params(r))) && answered((src.topic)("history", history_params(r, key)))
    _ => true
  }
}
