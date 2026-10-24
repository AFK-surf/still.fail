// still.fail, as its Android app is (ember apps/android app/App.kt): signed out it is the sign-in page; signed in,
// the chats of one workspace are home (Home.kt), and everything else a page pushed over it (@ui.Nav: sliding in,
// swiped back from the left edge; a new chat rising from the bottom), or a sheet from the bottom (sheet.mbt). The
// places of the bottom bar (bar.mbt) are the pages at the stack's root, switched in place.

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
  @sf.set_language(None)
  files_cornered.val = false
  felt_menu.val = -1
  felt_past.clear()
  felt_holds.clear()
  image_quoted_at.val = -1
  attention.told = false
  picture_pick.val = None
  bar_glyph.val = None
  bar_stations_said.val = ""
  attention.visible = false
  attention.focused = false
  attention.workspace = ""
  attention.src = None
  // the stack and what the app keeps of it (src/sfbase)
  @sfbase.reset()
  // the desktop's own (src/sfdesk)
  @sfdesk.reset()
  // what the drive's pages ask of the app: its file preview
  @sfbase.drive_viewer.val = open_file
  // what the desktop's messages draw that is this package's: the file preview, visualizations, links (wide_panel.mbt)
  @sfbase.chat_parts.val = desk_chat_parts()
  home_rows.val = []
  steadies.clear()
  sheet_host.kind = NoSheet
  sheet_host.shown = NoSheet
  sheet_host.accounts = false
  bar_reset()
  composer_page_from.val = None
  new_fix.station = "st1"
  new_fix.model = "claude-opus-5-5"
  new_fix.runtime = "claude"
  new_fix.effort = "high"
  new_fix.d_model = "claude-opus-5-5"
  new_fix.d_runtime = "claude"
  new_fix.d_effort = "high"
  new_fix.d_profile = ""
  new_fix.made = 0
  new_fix.reading = 0
  bar_timing.val = None
  reporting_host.val = None
  bar_timed.val = None
  reset_row_menu()
  login_cards_reset()
  update_anchor_reset()
  landing_reset()
  new_ws_reset()
  news_reset()
  screens_open.clear()
  screens_made.val = 0
  screen_uis.clear()
  screen_fix_mode.val = ""
  peeks_reset()
  viz_frames.clear()
  viz_heights.clear()
  viz_full.val = None
  viz_unmade.clear()
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
  share_closing.val = false
  splash_waited.val = false
  drafts.clear()
  sent_pictures.clear()
  cui.attach = false
  cui.picking = None
  cui.picking_for = ""
  cui.outside = false
  cui.restore_error.clear()
  cui.room_for = ("", None)
  cui.cap_id = 0
  cui.content_id = 0
  cui.doing.clear()
  pick_reset()
  fix_chats.clear()
  fix_timers.clear()
  fix_downloads.clear()
  fix_due.clear()
  fix_unsaid.clear()
  fix_drafts.clear()
  fix_composers.clear()
  fix_writes.clear()
  fix_xshared.clear()
  fix_decided.clear()
  fix_replied.clear()
  dv_reset()
  decide_reset()
  close_now()
  @settings.reset()
  found_marking.val = ("", [], 0.0)
  find_marking.val = []
  search_reset()
  ask_turns.clear()
  notices_reset()
  faces_reset()
  links_reset()
  wide_reset()
  // the library's viewers: the texts read, the films played, a desktop's player's 选集 and the pointer it last saw
  @sf.viewer_reset()
  // the menu open (@sf.menu_of, context_items)
  @sf.parts_reset()
  badge_told.val = -1
  // the menu bar given (menu_bar.mbt)
  menu_bar_given.val = ""
  dock_reset()
  // the made-up chats and their station (chat_fixture.mbt, service_fixture.mbt, drive_fixture.mbt)
  kept_chats.clear()
  fixture_pictures.clear()
  fix_threads.clear()
  fix_browse_reset()
  fix_ctx.val = None
  fix_clock.val = None
  fix_serial.val = 0
  fix_stream_ids.val = 0
  // Home (home.mbt), the host told (above), a chat's page and what is in it
  marks_seen.clear()
  told_bars.val = None
  told_dark.val = None
  flying.val = None
  opened_notices.clear()
  tool_parts.clear()
  flashing.val = ("", 0.0)
  flash_row.val = None
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
  pv_frames.clear()
  fix_fetches.clear()
  pv_frames_n.val = 0
  pv_first.clear()
  pv_hidden.val = ""
  pv_read.clear()
  pv_strip.leaving = None
  pv_strip.pinned = None
  pv_strip.near.clear()
  near_asked.clear()
  viewer_awake_env.val = -1
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
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
  // the Mac's menu bar, in the app's words (menu_bar.mbt); an item of the pages' chosen is read as its keys by the
  // frame after the menu said it (@settings.ask_action), and asked no more once that frame is built
  menu_bar(c, src)
  c.after_build("menu-asked", fn() { @settings.action_asked_done() })
  appearance(src)
  faces(src)
  // pictures put up by their address come as the core gives them (a GIF among them moves)
  @sf.picture_of.val = fn(url, frame) { (src.picture)(url, frame) }
  // a tip's keys, as the core's prefs set them (sfdesk's keys.mbt)
  @sf.set_shortcuts(@sfdesk.tip_keys(src))
  // the library's words, the app's catalog's; what its viewers ask of the page (viewer_host.mbt)
  @sf.set_words(fill)
  @sf.set_viewer_host(viewer_host_of(c, src))
  // a chat's file downloaded by the core, all here: kept where the system keeps downloads, whatever page shows
  // (downloads.mbt)
  downloads_frame(c, src)
  let t = @sf.begin(c)
  // under it all, the app's ground (what shows under the keyboard as it moves, the frame before the page follows it)
  // (the palette's colours are 0xRRGGBBAA; what the host clears to is said as 0xAARRGGBB, a window's background)
  c.set_clear((t.p.bg >> 8) & 0xFFFFFFL)
  // laid out Medium or Large (@sf.layout: the screen's room and kind, never what it is pointed with): the web app's
  // wide frame (sfdesk's frame.mbt: on a tape, Medium); Small, the phone's pages
  wide_on.val = @sfdesk.is_wide(c)
  // the wide frame's lines set as the desktop app's pages set them (a browser's way)
  @ui.set_web_lines(wide_on.val)
  @settings.wide.val = wide_on.val
  @settings.status_top.val = status_top()
  @settings.nav_foot.val = nav_foot()
  @settings.bar_room.val = bar_room_now()
  linger_tick(c, src, in_front=app_in_front())
  // the screens live in their cards (screen_links.mbt): which are on the screen, their frames acknowledged
  peeks_frame(c, src)
  // pages left: where they were left told once the frame's builds are over (a later build would see them left too)
  if left_pages.length() > 0 {
    c.after_build("pages-left", fn() { pages_left(src) })
  }
  // everything in still.fail's theme, as this frame's palette has it (light or dark, a phone's or a desktop's): the
  // styles' roles (@sf styles.mbt, the pages' own) its ink, its sizes, its corners; the one place it is put
  // beside what the system has at the window's sides (sides.mbt)
  c.with_theme(@sf.ui_theme(), fn() { beside_sides(c, fn() { view_in(c, src, t) }) })
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
/// The number last put on the app's icon (-1 none yet).
let badge_told : Ref[Int] = Ref(-1)

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
      // the number on the app's icon (the desktop app's followBadge): the core's badge, else what is wrong and what
      // waits in every workspace; told as it changes
      let marks = (src.topic)("workspaceMarks", { "workspace": Json::string(w.id) }).value
      let badge = match field(marks, "badge") {
        Some(Number(_, ..)) => count(marks, "badge")
        _ =>
          match field(marks, "workspaces") {
            Some(Object(m)) => m.values().fold(init=0, fn(n, x) { n + count(Some(x), "alert") + count(Some(x), "wait") })
            _ => 0
          }
      }
      // the desktop's dock (dock.mbt): every workspace's chats that want the person, on the screen's edge
      dock_frame(c, src, all)
      if marks is Some(_) && badge != badge_told.val {
        c.after_build("badge", fn() {
          badge_told.val = badge
          @ui.set_badge(badge)
        })
      }
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
        // the wide frame's keys (sfdesk's keys.mbt), then the rail, the sidebar and the page beside it (sfdesk's frame.mbt,
        // this package's pages given to it: wide_pages.mbt); what opens over them after them
        @sfdesk.keys(c, src, w, desk_pages())
        @sfdesk.frame(c, src, w, all, invited, desk_pages())
        // a station's screen: over the whole window, as Android's ScreenActivity is over the app
        match app.nav.top() {
          Screen(at) =>
            c.layer(fn() { screen_page(c, src, at.station, at.screen, at.title) }) |> ignore
          // a drive's text read, a film played: over the whole window too, as the web's pages of a file opened
          // (Drive.css.ts opened: fixed over everything)
          DriveRead(at) => c.layer(fn() { reader_page(c, src, at) }) |> ignore
          DrivePlay(at) => c.layer(fn() { play_page(c, src, at) }) |> ignore
          _ => ()
        }
        // what opens over them (sfdesk's overlays.mbt)
        @sfdesk.overlays(c, src, w, desk_pages())
        // the player sideways (a phone on its side for a film): back turns it upright first
        play_back(c)
        pick_back(c)
        preview(c, src)
        viz_full_layer(c, src)
      } else {
        // a page opened slides in once the core has given what it shows (App.kt Pages: LOCAL_MS at most)
        app.nav.comes_when(fn() { page_ready(src, app.nav.top()) }, page_local_ms)
        let page_took = c.took_back(fn() {
          c.nav(app.nav, fn(page) { page_view(c, src, w, all, invited, page) }, bg=t.p.bg) |> ignore
        })
        // a place's top page other than the chats, with nothing over it or in it taking back: back goes to the chats,
        // in place
        let root = app.nav.top()
        if app.nav.depth() == 1 && root != Home && !page_took && !app.menu && !sheet_open() {
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
      // the desktop's settings pages' dialogs (src/sfdesk settings_page.mbt), under the settings' questions
      @sfdesk.settings_overlay(c)
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
          if lock_gate(c, src, w, bar=invited) {
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
      // in a window with its buttons in the app's top row, their band drags it (as a title bar does)
      if @ui.window_inset() && !wide_on.val {
        c.layer(fn() {
          let id = c.id("window-band")
          c.window_drag(id)
          c.box(style=@ui.style(w=Full, h=Fixed(window_band)), id~, fn() {  }) |> ignore
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
  let page : Page = match place {
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
  @settings.page(c, core, @settings.here_of(core, w.id, w.name), r)
}

///|
/// Whether the workspace's pages are shown: not while this device waits to be confirmed in its safe mode, whose page is
/// drawn instead (Security.kt LockGate). `bar` (whether invitations wait): on a phone, under Home's top bar, settings
/// and the workspace's name, its switcher (Security.kt SecurityWaitingScreen: with no bottom bar either, a phone had no
/// way out of the workspace, 2026-10-23); none beside the wide screen's rail, which has them.
fn lock_gate(c : @ui.Ctx, src : Source, w : Workspace, bar? : Bool) -> Bool {
  let core = settings_core(src, w)
  if !@settings.lock_waiting(core, w.id) {
    return true
  }
  match bar {
    None => @settings.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
    Some(invited) =>
      c.box(style=gate_fill, fn() {
        c.layer(fn() { @settings.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name)) }) |> ignore
        c.layer(fn() { top_bar(c, src, w, None, "all", invited) }) |> ignore
      })
      |> ignore
  }
  false
}

///|
/// The waiting page and Home's top bar over it, the screen's whole.
// kept across runs: a value (no field of it changes)
let gate_fill : @ui.Style = @ui.css("w=Full h=Full")

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
    read_only: if src.read_only { read_only_words } else { "" },
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
  // the words' language too, the core's (its `lang`: as chosen, else the device's), I18n.kt's follow
  @sf.set_language(if prefs is Some(_) { Some(text(prefs, "lang")) } else { None })
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
/// What a write said (Sheet.kt ToastHost), mbui's toast (@kit.toaster) in still.fail's look: over the foot, clear of
/// the bar and the action standing over it (bar_room above it), in ink, 2.6 s (paused while the pointer is on it),
/// coming in and going out; one said again is a new one.
fn toast(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  // the wide frame's the web's (the library's: @sf.toast_look, 24 over the window's foot, what an unconfirmed write
  // did said as not known)
  if wide_on.val {
    let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", @sf.toast_said(app.toast))] } else { [] }
    let r = @kit.toaster(c, "toast", said, duration=toast_ms, bottom=@sf.toast_bottom, look=fn(c, s, _action, _close) {
      @sf.toast_look(c, s)
    })
    if app.toast != "" && r.open.is_empty() {
      app.toast = ""
    }
    return
  }
  let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", app.toast)] } else { [] }
  // (above the navigation bar the view reaches under: Sheet.kt's navigationBars padding)
  let foot = nav_foot()
  let r = @kit.toaster(c, "toast", said, duration=toast_ms, bottom=bar_room + foot, look=fn(c, s, _action, _close) {
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
/// How long a toast stays (paused while the pointer is on it): the library's (toast.tsx).
pub let toast_ms : Double = @sf.toast_ms

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
/// The sign-in button's width at most in a desktop's window, as the desktop app's.
let sign_in_wide_w : Double = 300.0

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
  // a desktop's: the picture and 登录或注册 alone, no words around them (asked for, 2026-10-23)
  let wide = !@sf.touch_system() && @sfdesk.is_wide(c)
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
      if !wide {
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
      }
      c.box(h=Px(6.0), fn() {  }) |> ignore
      let id = c.id("sign-in")
      if c.clicked(id) && !busy {
        (src.sign_in)()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        // a desktop's no wider than the desktop app's (web cloud/gate.css.ts `ways`)
        max_w=if wide { sign_in_wide_w } else { c.width },
        h=Px(50.0),
        radius=25.0,
        bg=t.p.text,
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
          // SignIn.kt: clip(CircleShape).clickable
          if !busy {
            @motion.ripple(c, id, 25.0)
          }
        },
      )
      |> ignore
      if !wide {
        c.text(
          tr("android-settings.signIn.many"),
          size=12.0,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      }
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
  let said = @hostapi.system_said(json)
  for s in said {
    match s {
      // a link the system opened the app with (links.mbt): opened once the app can (signed in, its workspace known)
      Link(url) => link_later.push(app_link(url))
      // shown over another app, or in its own window again (share.mbt)
      Over(over) => share_over.val = over
      // (how far the bars reach in over the view: mbui keeps it, @ui.system_bars, bars.mbt)
      _ => ()
    }
  }
  let src = match attention.src {
    Some(s) => s
    None => return
  }
  if src.read_only {
    return
  }
  for s in said {
    match s {
      Shown(away~) => {
        (src.call)("client.wake", { "away": Json::number(away) }, fn(_) {  })
        update_check(src, false)
      }
      // 检查更新 from the menu bar (menu_bar.mbt)
      Menu("update.check") => update_from_menu(src)
      // one of the pages' actions from the menu bar: as its keys pressed (keymap.mbt action_pressed)
      Menu(action) => @settings.ask_action(action)
      // a package handed to the system's installer could not be installed (FilePreview.kt install's toast)
      InstallAllow(..) => toast_later(pv_fill("android-chat.file.allowInstall", [("app", "still.fail")]))
      InstallFailed(error~, ..) => toast_later(pv_fill("android-chat.file.installFailed", [("error", error)]))
      Network =>
        (src.call)(
          "client.wake",
          { "away": Json::number(0.0), "network": Json::boolean(true) },
          fn(_) {  },
        )
      _ => ()
    }
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
/// How long a page opening waits for what the core has on the device (App.kt LOCAL_MS, the library's: motion.ts): never
/// for a station.
let page_local_ms : Double = @sf.local_ms

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

///|
/// A link the system opened the app with, as the core reads it (`link.parse`): one of still.fail's desktop app's own
/// (stillfail://, ember://, stillfail-beta://: …//o/<workspace>/<station>/<chat>, as the web's /o/ page hands an item
/// to that app, which this one takes as it is built in its place: scripts/mac-app.sh) as the same page's on the
/// cloud; any other as it is.
fn app_link(url : String) -> String {
  for scheme in ["stillfail://", "ember://", "stillfail-beta://"] {
    if url.has_prefix(scheme) {
      return "\{cloud_origin()}/\{url.view(start_offset=scheme.length())}"
    }
  }
  url
}
