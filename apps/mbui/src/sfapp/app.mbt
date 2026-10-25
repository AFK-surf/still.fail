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
  // ＋'s Station 文件 (a composer's, sfpages): the station files' picker (sfdesk's station_pick.mbt). Said once, as the
  // app starts (reset runs only as a Tester starts: a wire set there is never set in the app)
  station_files_asked.val = @sfdesk.station_files_pick
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
  image_quoted_at.val = -1
  bar_glyph.val = None
  bar_stations_said.val = ""
  // the stack and what the app keeps of it (src/sfbase)
  @sfbase.reset()
  // the desktop's own (src/sfdesk)
  @sfdesk.reset()
  steadies.clear()
  sheet_host.kind = NoSheet
  sheet_host.serial = 0
  bar_reset()
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
  new_fix.crowded = false
  bar_timing.val = None
  bar_timed.val = None
  home_sheet_at_start.val = false
  update_anchor_reset()
  screens_open.clear()
  screens_made.val = 0
  screen_uis.clear()
  screen_fix_mode.val = ""
  peeks_reset()
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
  share_closing.val = false
  splash_waited.val = false
  drafts.clear()
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
  fix_put_up.clear()
  fix_writes.clear()
  fix_xshared.clear()
  fix_decided.clear()
  fix_replied.clear()
  fix_vault.val = ""
  dv_reset()
  decide_reset()
  @settings.reset()
  found_marking.val = ("", [], 0.0)
  find_marking.val = []
  ask_turns.clear()
  wide_reset()
  invite_reset()
  // the library's viewers: the texts read, the films played, a desktop's player's 选集 and the pointer it last saw
  @sf.viewer_reset()
  // the menu open (@sf.menu_of, context_items)
  @sf.parts_reset()
  outside_reset()
  attach_reset()
  // the menu bar given (menu_bar.mbt)
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
  flying.val = None
  opened_notices.clear()
  tool_parts.clear()
  flashing.val = ("", 0.0)
  bench_on.val = -1
  boxed_n.val = 0
  // the composer: its ids counted from the start, what waits for it
  next_pending.val = 1
  quote_fields.clear()
  rename_field.set("")
  rename_given.val = ""
  share_files_made.val = 0
  fix_fetches.clear()
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  reset_by_hand.val = true
}

///|
/// What the app's own doings ask of the pages (sfbase shell.mbt): home and what is over the pages put their sheets
/// down too, an invitation's link shows its sheet, the screens live in their cards stop as the app goes behind.
fn pages_shell() -> Shell {
  {
    home,
    close_overlays,
    open_invite,
    behind: peeks_stop_all,
    open: open_where,
    detail: detail_where,
    back: back_where,
  }
}

///|
/// What back does where the layout has it (the tiers' table, docs/architecture.md): the wide frame's (sfdesk's
/// wide_back); laid out Small, a page of the stack popped, a place's top page other than the chats back to the chats
/// in place (from no side), none at the chats' (the system's: the app left).
fn back_where() -> (() -> Unit)? {
  let c = @ui.current()
  if @sfdesk.is_wide(c) {
    return @sfdesk.wide_back()
  }
  if app.nav.depth() > 1 {
    Some(fn() { app.nav.pop() |> ignore })
  } else if app.nav.top() != Home {
    Some(fn() { go_place(c, "chats", [], -1) })
  } else {
    None
  }
}

///|
/// Page `p` opened where the layout has it (the pane table, docs/architecture.md): on the wide frame the page pushed,
/// a chat's detail asked as a page (its history, a service, a file) laid beside its chat by the frame (sfdesk's
/// main_page), the page pane brought over on the tape to show it (sfdesk's show_page: also the chat already shown,
/// chosen again); laid out Small on the phone's stack (a new chat risen from the foot).
fn open_where(p : Page) -> Unit {
  if !@sfdesk.is_wide(@ui.current()) {
    stack_open(p)
    return
  }
  match p {
    Chat(r) => open_chat_beside(r)
    NewChat => new_chat_beside()
    // the settings: their list the sidebar's, the page of its first row beside it
    Settings => @sfdesk.open_settings_at(@sfdesk.settings_landing)
    _ => app.nav.push(p)
  }
  if @sfdesk.shown_in_page(p) {
    @sfdesk.show_page()
  }
}

///|
/// A new chat on the wide frame (新建对话, ⌘N): the page pane's, in place of what was there, the chats the place in view;
/// one there already, nothing.
fn new_chat_beside() -> Unit {
  if app.nav.top() is NewChat {
    return
  }
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  if app.nav.top() != Home {
    app.nav.replace(Home)
  }
  app.nav.push(NewChat)
}

///|
/// Chat `r` opened on the wide frame, from anywhere (a list's row, a search's, ⌘K, a link): the chat in the page pane
/// already, nothing; else the chats the place in view (from settings or another place), and the chat in the page
/// pane in place of whatever was there, never over it: the stack then holds the list and the chat alone (laid out
/// Medium, back from it goes to the list).
fn open_chat_beside(r : ChatRef) -> Unit {
  // (the chat in the page pane: the stack's last chat, the chats the place in view; what is laid beside it, its
  // detail asked as a page, stays)
  if @sfdesk.lit_place() == "chats" && !app.nav.pages().contains(Archived) {
    let pages = app.nav.pages()
    for k = pages.length() - 1; k >= 0; k = k - 1 {
      match pages[k] {
        Chat(open) if open.station == r.station && open.session == r.session => return
        Chat(_) => break
        _ => ()
      }
    }
  }
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
  if app.nav.top() != Home {
    app.nav.replace(Home)
  }
  app.nav.push(Chat(r))
}

///|
/// Chat `r`'s detail `tab` opened where the layout has it: on the wide frame its side panel's tab, toggled; laid out
/// Small the page it is (an agent's history, what the pages' message rows ask).
fn detail_where(src : Source, r : ChatRef, tab : String) -> Unit {
  if @sfdesk.is_wide(@ui.current()) {
    @sfdesk.side_toggle(src, r, tab)
  } else {
    app.nav.push(History(r, tab, None))
  }
}

///|
/// Back to Home (the stack's root), the sheets and the menu closed.
fn home() -> Unit {
  lower_sheet()
  dui.sheet = None
  dui.leaving = None
  nav_home()
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
/// A page of the stack, all of what it is given.
// kept across runs: a value (no field of it changes)
let page_whole : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The app over `src`: call each frame.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  fix_ctx.val = Some(c)
  shell.val = pages_shell()
  // the Mac's menu bar, in the app's words (menu_bar.mbt); an item of the pages' chosen is read as its keys by the
  // frame after the menu said it (@settings.ask_action), and asked no more once that frame is built
  menu_bar(c, src)
  c.after_build("menu-asked", fn() { @settings.action_asked_done() })
  appearance(src, page_dark(src))
  faces(src, @sfdesk.is_wide(c))
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
  let wide = @sfdesk.is_wide(c)
  // the wide frame's lines set as the desktop app's pages set them (a browser's way)
  @ui.set_web_lines(wide)
  @settings.wide.val = wide
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
        // the sign-in page inside the bars (SignIn.kt: windowInsetsPadding(systemBars)) (sfpages' gate.mbt)
        within_bars(c, fn() { @sfpages.sign_in_page(c, src) })
        // an invitation's link opened signed out: its sheet over the page, saying to sign in first (links.mbt)
        if !link_later.is_empty() {
          c.tell("links", fn() { signed_out_links(src) })
        }
        sheet_contents(fn(kind) { if kind == InviteLink { invite_sheet(c, src) } })
        // the library's menus, sheets and dialogs (src/sf presenters.mbt), over the page
        @sf.presented(c)
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
  let (current, all, answered, invited) = workspace_in_view(src)
  match current {
    Some(w) => {
      // (told once the frame's builds are over, as the last saw the app and the workspace)
      c.after_build("attend", fn() { attend(src, w.id) })
      // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off (once the
      // frame's builds are over: a build let go of follows no workspace)
      c.after_build("notices", fn() { notices_frame(src, w) })
      // the core and the workspace links are opened against, as the frame ends (links.mbt)
      c.after_build("links", fn() { links_frame(src, w) })
      // the number on the app's icon (app_frame.mbt)
      badge_frame(c, src, w)
      // the desktop's dock (dock.mbt): every workspace's chats that want the person, on the screen's edge
      dock_frame(c, src, all)
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
      // the app's keys, in every tier (sfdesk's keys.mbt): what is the wide frame's alone does nothing laid out Small
      @sfdesk.keys(c, src, w)
      if @sfdesk.is_wide(c) {
        // a page opened in the pane shows once the core has given what it shows, the one before staying till then
        // (LOCAL_MS at most), as a page pushed on a phone slides in then
        app.nav.shows_when(fn() { pane_ready(src, app.nav.top()) }, page_local_ms)
        // the wide frame's keys (sfdesk's keys.mbt), then the rail, the sidebar and the page beside it (sfdesk's
        // frame.mbt); what opens over them after them
        @sfdesk.frame(c, src, w, all, invited)
        // a station's screen: over the whole window, as Android's ScreenActivity is over the app
        match app.nav.top() {
          Screen(at) =>
            c.layer(fn() { screen_page(c, src, at) }) |> ignore
          // a drive's text read, a film played: over the whole window too, as the web's pages of a file opened
          // (Drive.css.ts opened: fixed over everything)
          DriveRead(at) => c.layer(fn() { reader_page(c, src, at) }) |> ignore
          DrivePlay(at) => c.layer(fn() { play_page(c, src, at) }) |> ignore
          _ => ()
        }
        // what opens over them (sfdesk's overlays.mbt)
        @sfdesk.overlays(c, src, w)
        // the player sideways (a phone on its side for a film): back turns it upright first
        play_back(c)
        pick_back(c)
        viz_full_layer(c, src)
      } else {
        // a page opened slides in once the core has given what it shows (App.kt Pages: LOCAL_MS at most)
        app.nav.comes_when(fn() { page_ready(src, app.nav.top()) }, page_local_ms)
        // pointed at with a mouse (a desktop's narrow window): the wheel and the trackpad scroll the lists and a drag
        // picks words, as on the wide frame's page; a finger drags the lists and holds to pick (pick.mbt)
        let finger = @ui.pointing() is Finger
        c.mouse_drags_lists(finger)
        let page_took = c.took_back(fn() {
          let pages = fn() {
            c.nav(
              app.nav,
              fn(page) {
                // what moves in the page of its own (the composer) takes its place from the page's foot, as the wide
                // frame's pane says (sfdesk's frame.mbt): the page sliding in or out, a keyboard making it shorter,
                // move none of it (it goes with the page, at once)
                let whole = c.box(style=page_whole, fn() { page_view(c, src, w, all, invited, page) })
                @motion.scope(c, whole, bottom=true)
              },
              bg=t.p.bg,
            )
            |> ignore
            // ⌘K's search over a page other than the lists (sfdesk's keys.mbt, sfpages' search.mbt), under the bars
            @sfpages.search_over(c, src, w, status_top())
          }
          if finger {
            pages()
          } else {
            c.selectable(color=@sf.alpha(t.p.blue, 0.28), pages)
          }
        })
        // at the stack's root, with nothing over it or in it taking back: the shell's back (back_where: a place's
        // top page other than the chats back to the chats, in place); above it the stack's own (Ctx::nav: swiped from
        // the edge, the back key), which pops as back_where does
        let root = app.nav.top()
        if app.nav.depth() == 1 && !page_took && !app.menu && !sheet_open() && !@sf.presenting() {
          match @sfbase.back_step() {
            Some(f) => c.on_back(f)
            None => ()
          }
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
          app.nav.depth() == 1 && place_of(root) is Some(_) && !@sfpages.search_bar_away() && !waiting,
        )
        // a file open over the pages (preview.mbt), under the menu, the sheet and the toasts
        preview(c, src)
        // the chat being made public (sfpages' publish.mbt)
        @sfpages.publish_layer(c, src)
        // a visualization over the whole screen (viz.mbt)
        viz_full_layer(c, src)
      }
      sheet_contents(fn(kind) {
        match kind {
          ShareSheet => share_in_sheet(c, src, w)
          InviteLink => invite_sheet(c, src)
          NoSheet => ()
        }
      })
      // a chat's sheets (slice 8's: sheets.mbt, framed in decide.mbt)
      sheets(c, src, w)
      // a new device waiting on this one's code, in any workspace of the person's, over whichever page is open
      // (App.kt LockPrompts): put up when no other sheet is
      @settings.lock_prompts(settings_core(src, w), !sheet_open() && dui.sheet is None)
      @settings.overlay(c, settings_core(src, w))
      // ⌘K's panel and ⌘/'s shortcuts, in every tier over the pages, under the presenters (sfdesk's switcher.mbt,
      // shortcuts.mbt)
      @sfdesk.switcher(c, src, w)
      @sfdesk.keys_dialog(c, src)
      // the library's menus, picks, panels, confirms and questions (src/sf presenters.mbt), over all of those
      @sf.presented(c)
      toast(c)
    }
    None =>
      if ws.value is Some(_) && answered {
        // the landing inside the bars (Workspaces.kt Landing: windowInsetsPadding(systemBars.union(keyboard)))
        // (sfpages' cloud_app.mbt); an invitation's link pasted (用邀请链接加入): its sheet over the page
        within_bars(c, fn() { @sfpages.no_workspace(c, src, ws.value, open_invite_link) })
        sheet_contents(fn(kind) { if kind == InviteLink { invite_sheet(c, src) } })
        // the library's presenters over it (the sheet among them: src/sf presenters.mbt), then the toasts
        @sf.presented(c)
        toast(c)
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
        Screen(at) => screen_page(c, src, at)
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
      if @ui.window_inset() && !@sfdesk.is_wide(c) {
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
  let from = match place_of(app.nav.top()) {
    Some(p) => p
    None => ""
  }
  // the side it comes in from: the bar's order now
  let bar_now = if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }
  let a = bar_now.search(from).unwrap_or(-1)
  let b = bar_now.search(place).unwrap_or(-1)
  let way = if a < 0 || b < 0 || a == b {
    0
  } else if b > a {
    1
  } else {
    -1
  }
  // the shell's (sfbase's shell.mbt), then the bar's own: timed from here (BarTiming), the page coming in from its side
  // (Arrive)
  if !@sfbase.go_place(place, way~) {
    return
  }
  bar_placed(from, place)
  let fade = place_switch(c)
  fade.snap(0.0)
  fade.animate(1.0, @motion.tween(if way == 0 { switch_fade_ms } else { switch_side_ms }, ease=Arrive))
}

///|
/// A page of the settings, over the workspace in view, in the stack's frame: back to the page under it, under the status
/// bar, over the navigation bar. One not merged yet: the phone's copy (src/sfapp/settings).
fn setting_page(c : @ui.Ctx, src : Source, w : Workspace, r : @settings.Route) -> Unit {
  let pages = app.nav.pages()
  let frame : PageFrame = {
    back: if pages.length() >= 2 {
      Some(@sfdesk.back_label(pages[pages.length() - 2]))
    } else {
      None
    },
    top: status_top(),
    foot: nav_foot(),
    named: false,
  }
  if !@sfdesk.setting_route(c, src, w, r, frame) {
    let core = settings_core(src, w)
    @settings.page(c, core, @settings.here_of(core, w.id, w.name), r)
  }
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
  // (sfpages' page, in the box the frame gives it: over the navigation bar)
  let page = fn() {
    c.box(style=gate_fill, fn() {
      c.box(style=@ui.style(w=Full, h=@sf.grow), fn() {
        @sfpages.lock_wait_page(c, core, @settings.here_of(core, w.id, w.name))
      })
      |> ignore
      c.box(style=@ui.style(w=Full, h=Fixed(nav_foot())), fn() {  }) |> ignore
    })
    |> ignore
  }
  match bar {
    None => page()
    Some(invited) =>
      c.box(style=gate_fill, fn() {
        c.layer(page) |> ignore
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
/// What the settings' pages read and call, and how they move, as the phone has them: the core as the app has it, its
/// stack, its own way home (its sheets put down) and a station's login as its card.
fn settings_core(src : Source, w : Workspace) -> @settings.Core {
  settings_core_of(src, w, home~, login_card=fn(c, station, id, marked) {
    @sfpages.login_card(c, settings_core(src, w), station, id, marked~)
  })
}

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
/// What a write said (Sheet.kt ToastHost), mbui's toast (@kit.toaster) in still.fail's look: over the foot, clear of
/// the bar and the action standing over it (bar_room above it), in ink, 2.6 s (paused while the pointer is on it),
/// coming in and going out; one said again is a new one.
fn toast(c : @ui.Ctx) -> Unit {
  let t = @sf.theme()
  let action = if app.toast != "" { app.toast_action } else { "" }
  let duration = if action != "" { toast_action_ms } else { toast_ms }
  // its action's button the toaster's (the focus on it holds the toast)
  let action_id = c.id("toast/t\{app.toast_n}/action")
  // pressed: done, and the toast goes
  let acted = fn() {
    let run = app.toast_run
    app.toast = ""
    app.toast_action = ""
    app.toast_run = fn() {  }
    run()
  }
  // the wide frame's the web's (the library's: @sf.toast_look, 24 over the window's foot, what an unconfirmed write
  // did said as not known)
  if @sfdesk.is_wide(c) {
    let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", @sf.toast_said(app.toast))] } else { [] }
    let mut pressed = false
    let r = @kit.toaster(c, "toast", said, duration~, bottom=@sf.toast_bottom, look=fn(c, s, _action, _close) {
      let live = s.toast.id == "t\{app.toast_n}"
      if @sf.toast_look(c, s, action=if live { action } else { "" }, action_id~) {
        pressed = true
      }
    })
    if pressed {
      acted()
    } else if app.toast != "" && r.open.is_empty() {
      app.toast = ""
    }
    return
  }
  let said = if app.toast != "" { [@kit.toast("t\{app.toast_n}", app.toast)] } else { [] }
  // (above the navigation bar the view reaches under: Sheet.kt's navigationBars padding)
  let foot = nav_foot()
  let mut pressed = false
  let r = @kit.toaster(c, "toast", said, duration~, bottom=bar_room + foot, look=fn(c, s, _action, _close) {
    let k = if s.t > 1.0 { 1.0 } else if s.t < 0.0 { 0.0 } else { s.t }
    let live = s.toast.id == "t\{app.toast_n}"
    c.box(padx=16.0, pady=10.0, bg=t.p.text, radius=18.0, opacity=k, tx=s.dx, fn() {
      let words = fn() { c.text(s.toast.title, size=t.t.ui, color=t.p.bg, line=20.0) |> ignore }
      if live && action != "" {
        c.box(style=@sf.toast_row, fn() {
          words()
          if @sf.toast_button(c, action_id, action) {
            pressed = true
          }
        })
        |> ignore
      } else {
        words()
      }
    })
    |> ignore
  })
  if pressed {
    acted()
  } else if app.toast != "" && r.open.is_empty() {
    app.toast = ""
  }
}

///|
/// How long a toast stays (paused while the pointer is on it): the library's (toast.tsx).
pub let toast_ms : Double = @sf.toast_ms

///|
/// How long a toast offering something to do stays (an archive's 撤销): the library's.
pub let toast_action_ms : Double = @sf.toast_action_ms

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
            c.text(s, size=t.t.meta, color=t.p.muted, center=true, line=18.0)
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
/// Whether the core has answered for what the wide frame's pane shows of page `p`: a chat; an agent's history, a
/// service and a file asked as pages are their chat's with them beside it (sfdesk's frame.mbt main_page), the chat
/// shown already, what is beside it waited for in its tab; any other page is not waited for.
fn pane_ready(src : Source, p : Page) -> Bool {
  match p {
    Chat(r) => {
      let t = (src.topic)("chat", chat_params(r))
      t.value is Some(_) || t.error is Some(_)
    }
    _ => true
  }
}

///|
fn wide_reset() -> Unit {
  @sfdesk.side_slide_reset()
  @sfpages.find_forget()
  find_around.val = -1.0
}

///|
/// The system's side of still.fail (before @ui.run). The desktop's window: 1280 by 820 at first, as still.fail's
/// desktop app opens (apps/desktop main.ts), its size not kept (the desktop app keeps none either); at least 360 by
/// 560, a phone's page below the breakpoint; on macOS its title bar the app's (its buttons in its top row, as the
/// desktop app's hiddenInset: the rail's and the sidebar's tops, a phone's page under their band), on Windows the
/// system's. On a phone the app is
/// Android's whatever the phone: on iOS too its lists fling and give at their edges as Android's,
/// its fields take a tap, draw their caret and handles and pick words as Android's (@ui.feel_as).
pub fn host_setup() -> Unit {
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0, inset=true)
  if @ui.platform() == 1 {
    @ui.feel_as(2)
  }
}
