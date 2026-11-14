// still.fail, as its Android app is: signed out it is the sign-in page; signed in,
// the chats of one workspace are home, and everything else a page pushed over it (@ui.Nav: sliding in,
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
  // 浏览文件夹 of a preset's folders (sfpages presets.mbt): the files' page's folder picker, a step further in
  @sfbase.folder_pick_asked.val = @sfdesk.folder_pick
  // a page's own key made as nodes (sfpages' chat page: Space): the tape's page brought over first, as the old page's
  @sfbase.page_for_key.val = @sfdesk.tape_page_for_key
  // an agent's card's jobs (sfpages): the chat's services and jobs as the screen shows them
  @sfbase.chat_jobs_asked.val = fn(c, src, r) { (@sfbase.chat_jobs_open.val)(src, r, c.window_size().0) }
  @sfbase.chat_jobs_open.val = fn(src, r, w) {
    if @sf.layout(w) is Small {
      open_chat_jobs(src, r)
    } else {
      @sfdesk.open_jobs_pop()
    }
  }
  // the library's run begun by the app's own reset where one was said by hand since a Tester last began (new_run): that
  // Tester begins none again, what the test opened in between is its run's (sf's run_begins.mbt)
  @sf.run_begun_by_app.val = fn() { reset_by_hand.val }
  @ui.on_reset(fn() {
    if !reset_by_hand.val {
      reset()
    }
    reset_by_hand.val = false
  })
}

///|
/// A run begun before its Tester is made (the made-up core given what it opens first, then the Tester): the run
/// before let go of first (its window's tree follows nothing this one says), then the app as at the start (reset).
fn new_run() -> Unit {
  @ui.run_let_go()
  reset()
}

///|
/// The app as at the start for a test that makes no Tester after it (a model's, a source's, a draft's): new_run, but
/// leaving nothing for a Tester to come. reset_by_hand is for what a test sets between new_run() and its own Tester;
/// left set by a test that made none, the next test's Tester (in the same process, whichever test that is) took the app
/// as that test had left it, not as at the start (2026-11-11). detlint's `reset-by-hand` holds new_run() to a Tester
/// after it.
// called by tests alone; here, as detlint's `reset-by-hand` wants it
#warnings("-unused_value")
fn fresh_app() -> Unit {
  new_run()
  reset_by_hand.val = false
}

///|
/// As at the start: Home alone, nothing chosen here yet (tests; every Tester as it starts: init above). Each global
/// of this package is put back here (or in what this calls) as its `let` has it, or says why it is kept across runs
/// (scripts/check.sh checks).
fn reset() -> Unit {
  files_cornered.val = false
  image_quoted_at.val = -1
  bar_glyph.val = None
  bar_stations_said.val = ""
  // the stack and what the app keeps of it (src/sfbase)
  @sfbase.reset()
  // the desktop's own (src/sfdesk)
  @sfdesk.reset()
  sheet_host.kind = NoSheet
  sheet_host.serial = 0
  bar_reset()
  bar_timing.val = None
  bar_timed.val = None
  place_switch.put(1.0)
  home_sheet_at_start.val = false
  peeks_reset()
  share_in.shared.set(None)
  share_in.files.set([])
  share_in.raised.set(false)
  // (taken: a Tester never reads the machine's MBUI_SHARE_TEXT)
  share_in.env_taken.set(true)
  share_in.searching.set(false)
  share_in.choosing.set(false)
  share_in.opening.set(None)
  share_in.error.set("")
  share_in.query.set("")
  share_in.find.set("")
  share_closing.val = false
  share_sinking.val = false
  share_wide.set(false)
  splash_waited.set(false)
  splash_from.val = -1.0
  splash_owner.val = None
  first_shown.set(false)
  first_waiting.val = false
  @sfbase.first_page_waits.set(false)
  first_has.val = 0
  first_expired.set(false)
  first_built_ready.set(false)
  first_held.set([])
  first_words.set("")
  first_answered.set(false)
  first_from.val = -1.0
  first_top.val = None
  first_wide.val = None
  frame_bare.val = false
  window_shown.val = false
  @sfbase.held_pictures_waiting.val = []
  cui.restore_error.clear()
  cui.doing.clear()
  pick_reset()
  chat_bar_reset()
  dv_reset()
  decide_reset()
  @settings.reset()
  @sfdesk.drive_rows_reset()
  ask_turns.clear()
  wide_reset()
  invite_reset()
  login_link_reset()
  // the library as a run begins (what is presented, the menus open, a group's and a page's rows, the viewers: the texts
  // read, the films played, the reader's layout; the system's bars): this is the moment the run begins where it is said
  // by hand (sf's run_begins.mbt)
  @sf.run_begin()
  outside_reset()
  attach_reset()
  // the menu bar given (menu_bar.mbt)
  // Home (home.mbt), the host told (above), a chat's page and what is in it
  flying.val = None
  opened_notices.clear()
  tool_parts.clear()
  flashing.val = ("", 0.0)
  bench_on.val = -1
  boxed_n.val = 0
  // the composer: what waits for it
  share_files_made.val = 0
  // the made-up core's own, where one is linked (a test's, a tool's: sffixture's, as its wire says)
  (@sfbase.made_reset.val)()
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  reset_by_hand.val = true
}

///|
/// What the app's own doings ask of the pages (sfbase shell.mbt): home and what is over the pages put their sheets
/// down too, an invitation's link shows its sheet, the screens live in their cards stop as the app goes behind; a file
/// asked beside, in the side panel of the chat in view where the frame is the wide one (`wide`, this frame's).
fn pages_shell(src : Source, wide : Bool) -> Shell {
  {
    home,
    close_overlays,
    open_invite,
    open_login,
    behind: peeks_stop_all,
    open: fn(p) { open_where(src, p) },
    open_over: fn(p) { open_over_where(src, p) },
    detail: detail_where,
    beside: fn(tab) { beside_where(src, wide, tab) },
    beside_room: fn() { wide && app.nav.top() is Chat(_) },
    back: fn() { back_where(src) },
    show: fn() {
      if @sfdesk.is_wide(@ui.current()) {
        @sfdesk.show_page()
      }
    },
    bring: fn() {
      if @sfdesk.wide.tape.get() && @sfdesk.shown_in_page(app.nav.top()) {
        @sfdesk.bring_page()
      }
    },
    edit_rail: fn() { @sfdesk.wide.editing.set(true) },
  }
}

///|
/// What back does where the layout has it (the tiers' table): the wide frame's (sfdesk's
/// wide_back); laid out Small, a page of the stack popped, a place's top page other than the chats back to the chats
/// in place (from no side), none at the chats' (the system's: the app left).
fn back_where(src : Source) -> (() -> Unit)? {
  let c = @ui.current()
  if @sfdesk.is_wide(c) {
    return @sfdesk.wide_back(src)
  }
  if app.nav.depth() > 1 {
    Some(@sfbase.back_pop)
  } else if app.nav.top() != Home {
    Some(fn() { go_place(c.moment(), "chats", [], -1) })
  } else {
    None
  }
}

///|
/// Page `p` opened where the layout has it (the pane table): on the wide frame the page pushed,
/// a chat's detail asked as a page (its history, a service, a file) laid beside its chat by the frame (sfdesk's
/// beside_follow), on the tape shown in the page pane (sfdesk's show_page: brought over with the side panel in use, also
/// the chat already shown, chosen again); laid out Small on the phone's stack (a new chat risen from the foot).
fn open_where(src : Source, p : Page) -> Unit {
  if !@sfdesk.is_wide(@ui.current()) {
    stack_open(p)
    return
  }
  match app.nav.top() {
    Chat(r) => if @sfdesk.station_page_beside(src, r, p) { return }
    _ => ()
  }
  match p {
    Chat(r) => open_chat_beside(r)
    NewChat => new_chat_beside()
    // the settings: their list the sidebar's, the page of its first row beside it
    Settings => @sfdesk.settings_beside(@sfdesk.settings_landing)
    // (on the tape from the page in use: over it, as a phone's is, back coming to it again)
    _ => if @sfdesk.goes_over(p) { app.nav.push_over(p) } else { app.nav.push(p) }
  }
  if @sfdesk.shown_in_page(p) {
    @sfdesk.show_page()
  }
}

///|
/// Page `p` opened from the page in view (a chat's link in a message): on the wide frame, another chat over the chat
/// shown (Nav::push_over), so back comes to it again as the web's history does (the user, 2026-10-27: a chat's link
/// followed, back went to a new chat); else where the layout has it (open_where).
fn open_over_where(src : Source, p : Page) -> Unit {
  if @sfdesk.is_wide(@ui.current()) {
    match (app.nav.top(), p) {
      (Chat(open), Chat(r)) if open.station != r.station || open.session != r.session => {
        app.nav.push_over(p)
        @sfdesk.show_page()
        return
      }
      _ => ()
    }
  }
  open_where(src, p)
}

///|
/// A new chat on the wide frame (新建对话, ⌘N): the page pane's, in place of what was there, the chats the place in view;
/// one there already, nothing.
fn new_chat_beside() -> Unit {
  if app.nav.top() is NewChat {
    return
  }
  nav_over_home([NewChat])
}

///|
/// Chat `r` opened on the wide frame, from anywhere (a list's row, a search's, ⌘K, a link): the chat in the page pane
/// already, nothing; else the chats the place in view (from settings or another place), and the chat in the page
/// pane in place of whatever was there, never over it: the stack then holds the list and the chat alone (laid out
/// Medium, back from it goes to the list). On the tape opened from the page or its side panel in use (a link in a
/// message, a history's chat, ⌘K there): over the page, as a phone's is, back coming to the page again.
fn open_chat_beside(r : ChatRef) -> Unit {
  if @sfdesk.page_goes_on() {
    match app.nav.top() {
      Chat(open) if open.station == r.station && open.session == r.session => ()
      _ => app.nav.push_over(Chat(r))
    }
    return
  }
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
  nav_over_home([Chat(r)])
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
/// A file's tab `tab` asked beside (Shell's `beside`): on the wide frame, in the side panel of the chat in view, in
/// front (that file's tab there already, brought to the front): the tab put there; else nowhere (None: it opens over
/// the whole window).
fn beside_where(src : Source, wide : Bool, tab : String) -> String? {
  match app.nav.top() {
    Chat(r) if wide => Some(@sfdesk.view_beside(src, r, tab))
    _ => None
  }
}

///|
/// Back to Home (the stack's root), what is over the pages put down (close_overlays: a file open over the window too,
/// as a notification tapped opens its chat over Home).
fn home() -> Unit {
  close_overlays()
  nav_home()
}

///|
/// The pages left since a build last began, told so (where each was left, what it held let go).
fn pages_left(src : Source) -> Unit {
  for i in 0..<left_pages.length() {
    let p = left_pages[i]
    let (page_src, chat_view) = @sfbase.left_page_source(src, i)
    match p {
      Chat(r) => {
        match page_src {
          Some(source) => {
            chat_left(source, r, saved=chat_view)
            viz_chat_left(r.station, r.session)
          }
          None => ()
        }
      }
      DriveRead(at) => reader_left(at)
      DrivePlay(at) => play_left(at)
      Service(station, job) => service_left(src, station, job)
      PreviewFile(station, key, path, _) => service_left(src, station, "file:" + key + "\n" + path)
      History(r, key, _) => history_left(src, r, key)
      // the drive's folders read, watched for changes while shown: let go of once no page of the drive is left on
      // the stack (a folder entered over another, its columns reading those above it, keeps them)
      Files | Drive(_) =>
        if !app.nav.pages().iter().any(fn(q) { q is (Files | Drive(_) | DriveRead(_) | DrivePlay(_)) }) {
          @sfbase.let_go(src, @sfbase.drive_scope)
        }
      Screen(at) => @sfpages.screen_left(src, at.station, at.screen)
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
  // (the made-up core, where one is linked, on this frame's runtime)
  (@sfbase.made_frame.val)(c)
  @sfbase.held_build()
  c.after_build("held/end", fn() { @sfbase.held_end() })
  shell_set(pages_shell(src, @sfdesk.is_wide(c)))
  // the Mac's menu bar, in the app's words (menu_bar.mbt); an item of the pages' chosen is done as its action is, at
  // that moment (@settings.ask_action)
  menu_bar(c, src)
  @sfdesk.window_zoom_keys(c, src)
  appearance(c, src, page_dark(src))
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
  @sfbase.left_said.get() |> ignore
  if left_pages.length() > 0 {
    c.after_build("pages-left", fn() { pages_left(src) })
  }
  // everything in still.fail's theme, as this frame's palette has it (light or dark, a phone's or a desktop's): the
  // styles' roles (@sf styles.mbt, the pages' own) its ink, its sizes, its corners; the one place it is put (the room
  // beside what the system has at the window's sides the tree's root keeps: app_tree, sides.mbt)
  c.after_build("station-tabs-left", fn() { @sfdesk.station_tabs_sweep(c, src) })
  // (the system's own bars as this frame wants them: the wide frame's tabs, else none: sfdesk's rail_native.mbt)
  c.with_theme(@sf.ui_theme(), fn() { @sfdesk.nav_frame(fn() { view_in(c, src) }) })
}

///|
fn view_in(c : @ui.Ctx, src : Source) -> Unit {
  // (the state the app is in, a node of the window's tree (app_tree), its pages old views of it put here; starting or
  // failed, signed out, the landing, reading or a window of its own, nodes with no old view to say it: said here, as the
  // state is)
  match app_is(src) {
    (Starting | Failed) as state => splash_said(src, state)
    // (signed out, or signed in at the landing: the ways in's nodes, entry_tree.mbt)
    SignedOut => entry_said()
    SignedIn if shell_is(src, c.window_size().0) is Landing => entry_said()
    // (signed in, its workspaces still read or failing to be: the splash's nodes)
    SignedIn if shell_is(src, c.window_size().0) is Reading => reading_said(src)
    // (a window of its own: its page, an old view the tree hosts, says nothing of the first page or the splash)
    SignedIn if shell_is(src, c.window_size().0) is Lone => entry_said()
    _ => ()
  }
  @ui.old_views_here(c)
  // the first page built with what it shows, the pictures the device holds in it decoded as it drew them (a likeness
  // in a picture's place for the frame or two its decoding takes is not shown): shown from this frame
  if first_waiting.val {
    // (what this frame built with what it shows answered: what it holds of the device's pictures not decoded yet
    // said with it, what first_page_done waits by; first_page_node read it of the core as it holds it now)
    if first_has.val == 1 {
      first_held.set(@sfbase.held_pictures_waiting.val.copy())
      first_built_ready.set(true)
    }
    if first_page_done() {
      first_shown.set(true)
      first_waiting.val = false
    }
  }
  first_hide(first_waiting.val)
  // the first page built, waiting for what it shows (signed_in): not shown yet, the splash over the window's ground
  // (what the host clears to, the ground's colour) in its place, its words as while the workspaces are read
  if first_waiting.val {
    // (each of the shell's old views: narrow_shell.mbt)
    @ui.old_views_look(c, { ..@ui.still_look, alpha: 0.0 }) |> ignore
    // (the splash itself the window's tree's nodes over the shell: first_splash_node; the ground alone till the app's
    // first splash has waited its second, the window held not shown for it)
    if !splash_waited.get() {
      frame_bare.val = true
    }
  }
  // the window held (host_setup) shown with the first frame that draws more than the ground (the host shows it once
  // the frame is on it)
  if !frame_bare.val && !window_shown.val {
    window_shown.val = true
    @hostapi.window_show()
  }
  // the window's own buttons where they are the app's (Windows'), over all of it as a title bar's are
  if @ui.window_keys_own() {
    c.layer(fn() { @sf.window_keys(c) }) |> ignore
  }
}

///|
/// What the app shows under all of it (view_in).
#derive(Eq)
priv enum AppIs {
  /// the core failed
  Failed
  /// signed out: the sign-in page
  SignedOut
  SignedIn
  /// the accounts not read yet, or failing to be
  Starting
}

///|
/// Whether the stack of pages laid out Small (narrow_shell.mbt) is in a finger's hand now: its lists dragged and words
/// held to pick (pick.mbt); else a mouse's, the wheel scrolling them and a drag picking words, as the wide frame's.
fn stack_by_finger() -> Bool {
  @ui.pointing() is Finger
}

///|
/// Which of the app's states it is in, as the core's accounts and its failure say.
fn app_is(src : Source) -> AppIs {
  match (src.topic("accounts", {}).get().value, (src.fatal)()) {
    (_, Some(_)) => Failed
    (Some(Array(list)), _) if list.length() == 0 => SignedOut
    (Some(Array(_)), _) => SignedIn
    _ => Starting
  }
}

///|
/// A layout's name as a hang report says it (@ui.journal_arranged): one of a fixed few, never more.
fn layout_name(l : @sf.Layout) -> String {
  match l {
    Small => "Small"
    Medium => "Medium"
    Large => "Large"
  }
}

///|
/// What the app shows as a whole in a window `width` wide (sfbase's Shown, its name shown_kind's): what the window's
/// tree picks (app_tree's share sheet over another app, app_is, shell_is), a page the stack's top: on 小屏 the page on
/// top, on 中屏 and 大屏 the page the pane lands on and shows (the chats' sidebar or the rail beside it are no page;
/// sfdesk's land pushes what it lands on), a window of its own its page. What is presented over it (a sheet, a panel,
/// a menu) is not said.
fn shown_now(src : Source, width : Double) -> @sfbase.Shown {
  if share_over.get() {
    return @sfbase.Shown::Share
  }
  match app_is(src) {
    Failed | Starting => @sfbase.Shown::Starting
    SignedOut => @sfbase.Shown::SignIn
    SignedIn =>
      match shell_is(src, width) {
        Stacked | Taped | Paned => @sfbase.Shown::Shows(app.nav.top())
        Lone =>
          match @sfbase.lone_page.val {
            Some(p) => @sfbase.Shown::Shows(p)
            None => @sfbase.Shown::Starting
          }
        Landing => @sfbase.Shown::Landing
        Reading | Unsized => @sfbase.Shown::Starting
      }
  }
}

///|
/// The window as a tree made once (mbui's view_host.mbt, the way there's 4: from the outside in): the
/// state the app is in (app_is) a node picked by it, made as it comes and let go as it goes, the app in that state an old
/// view in it, built the old way on the window's ground (`view` the old frame around it: what every state shares, the
/// theme, the window's sides, the layers over it).
pub fn app_tree(src : Source) -> (@view.View) -> Unit {
  fn(root) {
    // (the library's words, the app's catalog's, and their language as the core's prefs say it, said before any page of
    // nodes is made: what one says on its first frame is its words in that language, not their keys or the device's
    // laid out and then said again; the old frame tells them each build, the same)
    @sf.set_words(fill)
    // Keep the prefs reader with the tree from its first read, including before the first frame is built.
    root.reacts(fn() { src.topic("prefs", {}).get().value }, @sfbase.language_from_prefs)
    // (the chat page this device makes, as chosen in 外观's 试用新对话页, told before any page of nodes is made: the first
    // chat opened is the page chosen)
    root.reacts(fn() { src.topic("prefs", {}).get().value }, @sfbase.chat_page_from_prefs)
    // (the window's keys as the core's prefs keep them on this device, changed as they are: settings' keymap.mbt)
    root.keymap(By(fn() { @settings.keymap_of(src.topic("prefs", {}).get().value) })) |> ignore
    // (the window's height, what a chat list's and a chat's first window are worked out of wherever they are first
    // asked: sfbase's first_window, chat_first_window; said before any page of nodes is made, as it asks; none before
    // the first frame gives it, what was known kept till then)
    root.reacts(fn() { root.window().1 }, fn(h) { if h > 0.0 { @sfbase.window_tall.val = h } })
    // (the window's size from the menu bar, in every state: sfdesk's window_zoom.mbt)
    @sfdesk.zoom_actions(root, src)
    // (pictures by their address as the core gives them, said before any page of nodes is made: what one shows on its
    // first frame asks the core, not the library's stand-in; the old frame says it each build, the same)
    @sf.picture_of.val = fn(url, frame) { (src.picture)(url, frame) }
    // (what the app shows, by its kind alone, told the window thread's journal as it changes, on every host: what its
    // hang reports and the device's performance record say; no frame asks it)
    root.reacts(fn() { @sfbase.shown_kind(shown_now(src, root.window().0)) }, @ui.journal_shows)
    // (whether what people use is counted on this device, as the settings say, told the core as the app starts and as
    // they change; then what the app shows, by that same kind alone, counted where it is: client/core-ts's
    // use-counts.ts, which sends them only from a build given still.fail's project, on still.fail's own cloud)
    root.reacts(fn() { @sfbase.reporting_on(src).unwrap_or(true) }, fn(on) { @sfbase.tell_reports(src, on) })
    root.reacts(fn() { @sfbase.shown_kind(shown_now(src, root.window().0)) }, fn(kind) {
      (src.call)("client.shown", { "page": Json::string(kind) }, @sfbase.answer_unread)
    })
    // (how it lays out what it shows, 小屏/中屏/大屏 by @sf.layout's name, and the window's size, told the journal as
    // either changes: what a hang report says beside the page, so it is made again in a Tester's window of that size)
    root.reacts(
      fn() {
        let (w, h) = root.window()
        (layout_name(@sf.layout(w)), w, h)
      },
      // (none before the first frame gives the window)
      fn(a) { if a.1 > 0.0 { @ui.journal_arranged(a.0, a.1, a.2) } },
    )
    // (what the splash waits by, kept by what lives through the app's states: splash_begin)
    splash_owner.val = Some(root)
    // (its nodes drawn in still.fail's theme, the one its old views are built in, as light or dark is set: view's
    // with_theme)
    @ui.set_tree_theme(@sf.ui_theme_now)
    // (the window's sides beside the system's bars kept, all of it between: sides.mbt)
    root.sides(By(fn() { sides_room() })) |> ignore
    // over another app (a share sheet over the app it came from: share.mbt): nothing but the sheet, an old view of its
    // own; the app's state's nodes let go meanwhile, made again as it opens
    root.pick(fn() { share_over.get() }, fn(o, over) {
      o.grow(Is(1.0)) |> ignore
      if over {
        @ui.old(o, fn(c) { over_view(c, src) }).grow(Is(1.0)) |> ignore
      } else {
        app_state_tree(o, src)
      }
    })
    // (the core what the settings put up by what has none at hand draws with (a station's card from a chat), said as
    // the tree is made and as the workspace in view changes, before what is presented is made: one put up before the
    // first frame is built (a fixture's) is made with it, not with none; the old frame says it again each build:
    // settings' panels_frame)
    root.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(_) {
      match workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(settings_core(src, w), w.id)
        None => ()
      }
    })
    // the library's confirms in the middle of the window, each at its place in the window's stack of layers among what
    // else is presented (src/sf presented_node.mbt)
    @sf.presented_nodes(root)
    // what a write said, over all of it, in every state and shell (sfbase's toasts_node)
    @sfbase.toasts_node(root, fn() { toast_bottom_now(root) }) |> ignore
  }
}

///|
/// The app in the state it is in (app_is), a node picked by it (app_tree's, not over another app).
fn app_state_tree(root : @view.View, src : Source) -> Unit {
  root.pick(
    fn() { app_is(src) },
    fn(v, state) {
      v.grow(Is(1.0)) |> ignore
      match state {
        // starting or failed, the splash: the window's tree's nodes (splash_tree)
        Starting | Failed => splash_tree(v, src, state)
        // signed out, the sign-in page: the window's tree's nodes (entry_tree.mbt)
        SignedOut => signed_out_tree(v, src)
        SignedIn => {
        // where the app is, put in the history's entry now as the stack or the workspace in view changes, at that
        // change (sfbase's app_history.mbt: a person's act pushed an entry before it moved the stack, one for all the
        // steps it takes, noted once it is done: history_acts_ended); on the wide frame Home alone is passing (land)
        v.reacts(
          fn() {
            let ws = match workspace_in_view(src).0 {
              Some(now) => now.id
              None => ""
            }
            let wide = !(@sf.layout(v.window().0) is Small) || @sf.native_able()
            (ws, app.nav.pages(), wide, @sfbase.history_acts_ended())
          },
          fn(said) {
            let (ws, pages, wide, _) = said
            @sfbase.history_note(ws, wide && pages == [Home])
          },
        )
        // the first page's wait, at the moments its causes come (first_page_node)
        first_page_node(v, src)
        // what the page on top reads as it is first built, asked as it comes on top (sfbase's page_opens_node)
        @sfbase.page_opens_node(v, src)
        // what the start says of notifications, at the moment the core's notify is answered or the app shown again
        @sfbase.notices_said_node(v, src)
        // what the workspace in view opens on, asked as it comes to be in view, the splash or the shell before it
        // still shown (sfbase's opens_ahead_node): its shell's panes' (小屏's Home, home_opens; the wide frame's,
        // sfdesk's frame_opens)
        @sfbase.opens_ahead_node(v, src, fn() {
          let width = v.window().0
          if width <= 0.0 {
            None
          } else if @sf.layout(width) is Small && !@sf.native_able() {
            Some(("narrow", home_opens))
          } else {
            // (a page open already, not Home: the pane opens on it, not on what it would land on)
            match @signals.untracked(fn() { app.nav.top() }) {
              Home => Some(("wide", @sfdesk.frame_opens))
              p => Some(("wide", fn(src, ws, ask) { @sfdesk.frame_opens_on(src, ws, Some(p), ask) }))
            }
          }
        }, first_waits=fn() { !first_shown.get() })
        // signed in, the shell it is laid out in a node picked by the window's width and what is in view
        // (narrow_shell.mbt): laid out Small with a workspace, the narrow shell's nodes; on the tape, its panels' nodes
        // (tape_shell.mbt); the ways in, the splash, a window of its own; nothing before the window has a width
        v.pick(fn() { shell_is(src, v.window().0) }, fn(s, shell) {
          s.grow(Is(1.0)) |> ignore
          // the app's keys, in every tier with a workspace in view (sfdesk's keys.mbt): what is the wide frame's alone
          // passes the key on laid out Small
          if shell is (Stacked | Taped | Paned) {
            @sfdesk.frame_actions(s, src)
          }
          match shell {
            Stacked => narrow_shell(s, src)
            Taped => taped_shell(s, src)
            Paned => paned_shell(s, src)
            Landing => landing_tree(s, src)
            Reading => reading_tree(s, src)
            Lone => lone_tree(s, src)
            // (no width yet: nothing laid out, the window's first frame giving one before anything is (Tree::frame:
            // the room set before what follows it is worked out), the shell picked again by it)
            Unsized => ()
          }
        })
        // the first page built, waiting for what it shows: not shown yet, the splash over it, its words as while the
        // workspaces are read (first_words), on the window's ground (what the host clears to)
        first_splash_node(v)
        }
      }
    },
  )
}

///|
/// A window of its own (sfbase's window.mbt) in node `v` (shell_is's Lone): on the window's ground, its top dragging it
/// where its buttons are in the app's top row (under all of it), its page alone over all of it, an old view the tree
/// hosts (lone_page_view: closing it ends the run), the library's presenters and the toasts over that, taking a finger
/// only where they draw something.
fn lone_tree(v : @view.View, src : Source) -> Unit {
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  v.show(fn() { @ui.window_inset_now() }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(b) { b.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore }) |> ignore
  })
  @ui.old(v, fn(c) {
    match @sfbase.lone_page.val {
      Some(p) => lone_page_view(c, src, p)
      None => ()
    }
  })
  .over(Is(true))
  |> ignore
  @ui.old(v, fn(c) {
    @sf.presented(c)
  })
  .over(Is(true))
  |> @ui.old_takes_own
  |> ignore
}

///|
/// Page `p` of a window of its own, alone over all of it (lone_tree's): a station's screen, closing it
/// ending the run (its window closed as its own close button closes it).
fn lone_page_view(c : @ui.Ctx, src : Source, p : Page) -> Unit {
  match p {
    Screen(at) =>
      @sfpages.screen_page(c, src, at, system_frame(), on_close=fn() {
        c.after_build("lone-closed", fn() { @hostapi.exit(0) })
      })
    _ => ()
  }
}

///|
/// What the splash says while no workspace is in view yet and the landing is not shown (reading_tree's): why reading the
/// workspaces failed (the core's words), else 正在读取你的 workspace and what it waits on (t_reading_workspaces); and
/// whether it failed (said at once, not after the splash's second).
fn reading_said_words(src : Source) -> (String, Bool) {
  match src.topic("workspaces", {}).get().error {
    Some(e) => (text(Some(e), "message"), true)
    None => (t_reading_workspaces(src), false)
  }
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), as the frame begins (view_in's): what is
/// said of the frame: no first page waiting nor its pictures; the ground
/// alone until the splash's second, unless it failed.
fn reading_said(src : Source) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = []
  // (whether it failed alone: the words, the core's status read, are the splash's nodes' (reading_tree), read as they
  // change; read by a frame, status was held till the frame after the workspace came into view, not let go of then)
  frame_bare.val = !splash_waited.get() && src.topic("workspaces", {}).get().error is None
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), in node `v`: the splash's nodes saying so
/// as it changes (reading_said_words).
fn reading_tree(v : @view.View, src : Source) -> Unit {
  splash_of_tree(v, fn() { Some(reading_said_words(src).0) }, fn() { reading_said_words(src).1 })
}

///|
/// 正在读取你的 workspace, with what the core has been waiting on for a while under it, a line each (`status`'s
/// lines: what is read and how far it has come, then what lasts).
fn t_reading_workspaces(src : Source) -> String {
  let lines = items(src.topic("status", {}).get().value, "lines").filter_map(fn(l) {
    match l {
      String(s) => Some(s)
      _ => None
    }
  })
  [tr("android-misc.workspaces.loading"), ..lines].join("\n")
}

///|
fn page_view(
  c : @ui.Ctx,
  src : Source,
  w : Workspace,
  page : Page,
  barred? : Bool = false,
) -> Unit {
  // a place switched to on the bar comes in from the side the ball goes to, fading in (220 ms; 180 from no side); the
  // page at the stack's root is so with a page sliding in over it or back off it too (where it stands, not how deep
  // the stack is: Nav::under), its place's top bar kept. How far it has come is read as it is painted (moved there,
  // tapped there too, and faded), not as it is built: nothing built as it comes in
  let root = app.nav.under() is None
  if root {
    bar_built(c, page)
  }
  let at = c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    fn() {
      match page {
        // a device waiting to be confirmed in the workspace's safe mode sees that instead of the chats (its
        // stations refuse it: Security.kt LockGate); its settings stay
        // (made once: narrow_shell.mbt's Home)
        Home => ()
        Chat(r) => {
          chat_page(c, src, w, r, barred~)
          new_chat_leaving(c, src, w, r)
        }
        NewChat => new_chat_page(c, src, w)
        Place(p) => place_page(c, src, w, p)
        // 文件: a place of the bar at the stack's root, else a page pushed
        Files => files_page(c, src, w, place=root)
        Drive(at) => drive_page(c, src, w, at)
        DriveRead(at) => @sfpages.reader_page(c, src, at)
        DrivePlay(at) => @sfpages.play_page(c, src, at)
        Service(station, job) => service_page(c, src, station, job)
        PreviewFile(station, key, path, name) => preview_file_page(c, src, station, key, path, name)
        Archived => setting_page(c, src, w, @settings.Route::Archive)
        Settings => setting_page(c, src, w, @settings.Route::Home)
        Setting(r) => setting_page(c, src, w, r)
        // (made once: narrow_shell.mbt's history_node)
        History(_, _, _) => ()
        Screen(at) => @sfpages.screen_page(c, src, at, system_frame())
      }
      // the page runs under the status bar; it keeps the paper behind its icons, moving with it (App.kt: the list, a
      // place's top page with the bar and a chat have frosted bars there instead; a book and a film their own)
      let own_top = match page {
        Home | Chat(_) | NewChat | DriveRead(_) | DrivePlay(_) => true
        Place(_) | Files => root
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
          c.box(style=@ui.style(w=Full, h=Fixed(window_band())), id~, fn() {  }) |> ignore
        })
        |> ignore
      }
    },
  )
  if root {
    c.moved_by(at, fn(_, _) { (app.switch_way.to_double() * switch_slide * (1.0 - place_switch.get(c)), 0.0) })
    c.look_by(at, fn() { @ui.look(alpha=place_switch.get(c)) })
  }
}

///|
/// A place from the bottom bar (AppState.place): its page takes the stack's root, in place (nothing to go back to),
/// coming in from the side the ball goes to; the same place again changes nothing. `sets`, `cur`:
/// the bar it is chosen in (none: from no side). The page left kept and the one come to taken back where it was kept
/// (go_place_by's `kept`).
fn go_place(at : Double, place : String, sets : Array[Array[String]], cur : Int) -> Unit {
  go_place_by(at, place, sets, cur, true)
}

///|
/// go_place's, the page that leaves the stack's root put on its shelf and the one come to taken back from it where it is
/// there (`kept`: sfbase's nav_root_kept), or let go and made anew (not `kept`: what a test compares a page kept with,
/// bar_places_kept_wbtest.mbt).
fn go_place_by(at : Double, place : String, sets : Array[Array[String]], cur : Int, kept : Bool) -> Unit {
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
  // (Arrive), from this moment; the page left kept on the stack's shelf, the one come to taken back from it where it is
  // there (sfbase's nav_root_kept)
  if !@sfbase.go_place(place, way~, kept~) {
    return
  }
  bar_placed(from, place)
  place_switch.put(0.0)
  place_switch.go(
    1.0,
    if way == 0 { @motion.tween(switch_fade_ms, ease=Out) } else { @motion.moved(points=switch_slide) },
    at~,
  )
  // (what a finger's press on its tab asked ahead held till the place has come in: sfbase's places_ahead_node)
  @sfbase.place_switched(place_switch.ends_at())
}

///|
/// A page of the settings, over the workspace in view, in the stack's frame: back to the page under it, under the status
/// bar, over the navigation bar. One not merged yet: the phone's copy (src/sfapp/settings).
fn setting_page(c : @ui.Ctx, src : Source, w : Workspace, r : @settings.Route) -> Unit {
  let frame : PageFrame = {
    back: app.nav.under().map(@sfbase.back_label),
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
/// What a device waiting to be confirmed in the workspace's safe mode sees in Home's place, in `q` (all of the page's
/// room): sfpages' page over the navigation bar, Home's top bar over it (settings and the workspace's switcher: with no
/// bottom bar either, a phone had no way out of the workspace, Security.kt SecurityWaitingScreen, 2026-10-23).
fn lock_gate_node(q : @view.View, src : Source, core : @settings.Core) -> Unit {
  let workspace = fn() { workspace_in_view(src).0 }
  q.box(fn(page) {
    page.over(Is(true)) |> ignore
    page.box(fn(held) {
      held.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      held.show(fn() { workspace() is Some(_) }, fn(p) {
        let w = @signals.untracked(workspace).unwrap()
        p.grow(Is(1.0)) |> ignore
        // (the top bar lies over the page's top: its column stays out from under it, home_top_bar_node's height)
        @sfpages.lock_wait_node(p, core, @settings.here_of(core, w.id, w.name), clear=fn() {
          status_top_now(p.window().0) + bar_h
        })
        |> ignore
      })
    })
    |> ignore
    page.box(fn(foot) { foot.height(By(fn() { Some(nav_foot()) })) |> ignore }) |> ignore
  })
  |> ignore
  q.box(fn(bar) {
    bar.over(Is(true)).lies_along(Is(Start)) |> ignore
    // (nothing it shows has a tip: no chats' view, so nothing catching up)
    home_top_bar_node(bar, src, @sf.TipLayer::new(fn() { None }), workspace, fn() { None }, bell=false)
  })
  |> ignore
}

///|
/// How long a place switched to on the bar takes to come in: fading in from no side, from the side the ball goes to.
pub let switch_fade_ms : Double = 180.0

///|
/// How far a place switched to on the bar comes in from its side (points), a Move as long as that is far.
pub let switch_slide : Double = 30.0

///|
/// How far the page at the stack's root has come in as its place was switched to on the bar (0 … 1, go_place's way
/// from the moment it was switched to, from the side app.switch_way says): its old view's (page_view) and its nodes'
/// where it is made once (place_comes_in) read this one, whenever made.
// kept across runs: put back as a run begins (reset)
let place_switch : @motion.Way = @motion.Way::new(1.0)

///|
/// How far over what the system's bars leave of the window's foot the toast is, for the window's tree's (toast's,
/// followed): the wide frame's 24; the narrow one's over the bar's room.
fn toast_bottom_now(v : @view.View) -> Double {
  let wide = !(@sf.layout(v.window().0) is Small) || @sf.native_able()
  // (over the system's bars at the window's foot: the toaster keeps clear of them itself, View::clear)
  if wide {
    @sf.toast_bottom
  } else {
    bar_room
  }
}

///|
/// What a finger hides as it drags a field's caret or what is picked (@ui.Ctx::finger_reads), shown larger over it:
/// kit's loupe, of the glass a switch's knob held is (@sf.glass_knob), over everything.
fn finger_loupe(c : @ui.Ctx) -> Unit {
  @kit.loupe(c, "loupe", c.finger_reads(), glass=@sf.glass_knob())
}

///|
/// How long a toast stays (paused while the pointer is on it): the library's (toast.tsx).
pub let toast_ms : Double = @sf.toast_ms

///|
/// How long a toast offering something to do stays (an archive's 撤销): the library's.
pub let toast_action_ms : Double = @sf.toast_action_ms

///|
/// What the splash says it waits for, or what failed (`state` Starting or Failed): the core's failure; the accounts'
/// error. Said at once where there is one (splash's `now`).
fn splash_label(src : Source, state : AppIs) -> String? {
  match state {
    Failed => (src.fatal)()
    _ =>
      match src.topic("accounts", {}).get().error {
        Some(e) => Some(text(Some(e), "message"))
        None => None
      }
  }
}

///|
/// Starting or failed, the window's tree's nodes in its place (app_state_tree): what is said of the frame, said from the state it is in as the frame begins (view_in): no first
/// page waiting nor its pictures; the ground alone until the splash's second, unless there is something to say at once.
fn splash_said(src : Source, state : AppIs) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = []
  frame_bare.val = !splash_waited.get() && splash_label(src, state) is None
}

///|
/// The splash (`state` Starting or Failed) as the window's tree's nodes (app_state_tree's): splash_of_tree saying what
/// it waits for or what failed (splash_label), at once where there is something to say.
fn splash_tree(v : @view.View, src : Source, state : AppIs) -> Unit {
  splash_of_tree(v, fn() { splash_label(src, state) }, fn() { splash_label(src, state) is Some(_) })
}

///|
/// The app starting, or waiting for what every page needs: the ground alone, as the system's own splash before the
/// app's first frame is (Android's theme, iOS's launch screen), so an opening quicker than a second is one picture and
/// then the page; once it takes a while (a second), still.fail's mark and what it waits for under it, from then on; at
/// once when `now` (a failure). (The mark at once, on Android after the launcher's icon on the system's splash, then
/// the page: three pictures in a second, 2026-10-26 「打开的时候感觉乱闪」.)
/// The splash as the window's tree's nodes in `v`: saying `label` as it changes, the ground alone till the
/// app's first splash has waited its second unless `now` says to show it at once (splash_begin, at this moment if none
/// has begun); then still.fail's mark and what it says under it, its lines each in the middle, all in the middle of the
/// window. Where the window's buttons are in the app's top row (as that changes), its top drags it, under all of it.
fn splash_of_tree(v : @view.View, label : () -> String?, now : () -> Bool) -> Unit {
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  v.show(fn() { @ui.window_inset_now() }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(b) { b.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore }) |> ignore
  })
  match splash_owner.val {
    Some(owner) if owner.alive() => splash_begin(owner, v.cause_at())
    _ => ()
  }
  let mark = fn() { if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" } }
  v.box(fn(s) {
    s.over(Is(true)).pad(Is(24.0)).lines_up(Is(Some(Middle))) |> ignore
    // (in the middle of the window's height: as much room above as below)
    s.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    s.show(fn() { splash_waited.get() || now() }, fn(m) {
      m.gap(Is(16.0)).lines_up(Is(Some(Middle))) |> ignore
      // (the mark, its curves cut for the pixels the window is drawn at)
      m.box(fn(k) {
        k
        .width(Is(Some(56.0)))
        .height(By(fn() { Some(@sf.drawable_height(mark(), 56.0)) }))
        .picture(By(fn() { @sf.drawable_vector(mark()) }))
        |> ignore
      })
      |> ignore
      m.show(fn() { !now() }, fn(p) {
        p.box(fn(b) {
          b.width(Is(Some(splash_bar_w))) |> ignore
          @sf.progress_node(b, fn() { None }, fn() { @ui.tree_theme().line }, fn() { @sf.theme().p.accent }) |> ignore
        })
        |> ignore
      })
      m.show(fn() { label() is Some(_) }, fn(w) {
        w
        .words(By(fn() { label().unwrap_or("") }))
        .words_look(By(fn() { { size: @sf.theme().t.meta, weight: 400, line: 18.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 } }))
        .ink(By(fn() { @sf.theme().p.muted }))
        .words_centered(Is(true))
        |> ignore
      })
    })
    s.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// How wide the splash's bar is, under still.fail's mark while it waits.
let splash_bar_w : Double = 120.0

///|
/// How long the splash shows the ground alone before it says that it waits, and for what (the app's first splash's
/// second, waited by the window's tree from its start whatever state the app comes to meanwhile).
pub let splash_label_ms : Double = 1000.0

///|
/// Whether the app's first splash has waited its second (splash_label_ms): its mark and what it waits for shown from
/// then on.
let splash_waited : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// When the app's first splash began (-1: none yet), and what keeps the moment it has waited its second: the window's
/// tree's root, which lives through the app's states (app_tree).
// kept across runs: put back as a run begins (new_run)
let splash_from : Ref[Double] = Ref(-1.0)

///|
// kept across runs: put back as a run begins (new_run)
let splash_owner : Ref[@view.View?] = Ref(None)

///|
/// The app's first splash begun at `at` (once; a splash begun again, in another of the app's states, waits for the same
/// moment): the moment it has waited its second kept by `owner`, splash_waited set then, at that moment.
fn splash_begin(owner : @view.View, at : Double) -> Unit {
  if splash_from.val >= 0.0 {
    return
  }
  splash_from.val = at
  owner.at_moment(at + splash_label_ms, fn() { splash_waited.set(true) }) |> ignore
}

///|
/// How long a page opening waits at most for the core's answer: what it shows, as the device holds it, or that it
/// waits on a station (Source.waits: a chat none of whose messages are here), never for a station. As long as the
/// first page's (first_page_ms), not LOCAL_MS: the core reads what is here in its own time, slower on a phone and
/// busy as the app comes back (what came meanwhile read in); cut short at LOCAL_MS, a chat on the device slid in as its
/// messages' bones, they a moment later (2026-10-31, android 0.1.6303: no request to a station as the chats opened).
let page_local_ms : Double = splash_label_ms

///|
/// How long the app's first page waits for what it shows (all of it the core's on the device, as a page opening's):
/// as long as the window shows its ground alone (splash_label_ms), not a page opening's LOCAL_MS. The core is starting
/// then and answers more slowly than in a running app; cut short at LOCAL_MS, the page came in pieces (2026-10-27,
/// the sidebar by itself, then the chat's bones, then its messages), where an opening quicker than that is meant to be
/// one picture and then the page (splash).
let first_page_ms : Double = splash_label_ms

///|
/// Whether the core has answered (a value or why not) for what page `p` of workspace `w` shows as it opens (App.kt
/// opening): a chat (or said its messages wait on a station: its page shows them to come), an agent's history, Home
/// (all it opens on: home_opens, what a workspace switched waits for too); any other page is not waited for.
fn page_ready(src : Source, w : Workspace, p : Page) -> Bool {
  page_opens_by(src, w, p, @sfbase.read_now(src))
}

///|
/// page_ready's, each topic asked of `ask`.
fn page_opens_by(
  src : Source,
  w : Workspace,
  p : Page,
  ask : (String, Map[String, Json]) -> @sfbase.TopicState,
) -> Bool {
  match p {
    Chat(r) => @sfbase.chat_opens(r, ask)
    History(r, key, _) => {
      let t = ask("history", history_params(r, key))
      @sfbase.chat_opens(r, ask) && (t.value is Some(_) || t.error is Some(_))
    }
    Home => home_opens(src, w.id, ask)
    _ => true
  }
}

///|
/// Whether the app's first page shows: once the core has answered for what it shows and the pictures the device holds
/// in it are decoded (first_page_done), or `first_page_ms` after the workspace came into view (first_expired), from
/// then on. What the frame finds of it as it begins (first_has), for view_in to say after its builds.
fn first_page_shown(c : @ui.Ctx, src : Source, w : Workspace) -> Bool {
  if !first_shown.get() {
    first_has.val = if first_expired.get() {
      2
    } else if first_page_ready_by(src, w, @sfdesk.is_wide(c), @sfbase.read_now(src)) {
      1
    } else {
      0
    }
  }
  first_shown.get()
}

///|
/// What the first page not shown yet has this frame (first_page_shown): 0 not what it shows, 1 what it shows (shown
/// once the pictures the device holds in it are decoded too: view_in), 2 first_page_ms gone by (shown as it is).
let first_has : Ref[Int] = Ref(0)

///|
/// Whether the core has answered for what the app's first page shows, as a page opening waits for it, each topic asked
/// of `ask`: laid out Small the page on top as the wait began (first_top: one opened over it before it is shown, a
/// chat tapped on what shows of it, is that page's own wait, not the first page's), in the wide frame (`wide`) what it
/// opens on, as opens_ahead_node declares it: on Home the rail, the sidebar and the page the pane lands on, whether or
/// not a frame has landed it yet (@sfdesk.landing_opens), on another page that page in the pane.
fn first_page_ready_by(
  src : Source,
  w : Workspace,
  wide : Bool,
  ask : (String, Map[String, Json]) -> @sfbase.TopicState,
) -> Bool {
  if wide {
    // (the pane landed by a frame (sfdesk's land): waited for by that, as landing(w) was till 2026-11-12, the first
    // page was answered no sooner than the frame after what it shows was; a page opened before it lands is in the
    // pane in its place, never landed on, so the page on top now, as opens_ahead_node has it)
    match app.nav.top() {
      Home => @sfdesk.landing_opens(src, w.id, ask)
      p => @sfdesk.frame_opens_on(src, w.id, Some(p), ask)
    }
  } else {
    page_opens_by(src, w, first_top.val.unwrap_or(app.nav.top()), ask)
  }
}

///|
/// Whether the first page waits no more, at the moment its cause comes: `first_page_ms` gone by (first_expired), or
/// what it shows answered as a frame built it (first_built_ready) and each picture the device holds in it that build
/// found not decoded decoded since (first_held: the host's word on each, image_decoded's moment).
fn first_page_done() -> Bool {
  first_expired.get() ||
  (first_built_ready.get() && first_held.get().iter().all(fn(k) { @ui.image_any_ready(k) }))
}

///|
/// Whether `first_page_ms` has gone by since the workspace came into view, not shown yet (first_page_node: set at
/// that moment).
let first_expired : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether a frame has built the first page with what it shows answered (view_in: what it holds of the device's
/// pictures said with it, first_held).
let first_built_ready : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// The pictures the device holds in the first page that its build found not decoded (sfbase's held_pictures_waiting,
/// as the frame that built it with what it shows answered left it: view_in).
let first_held : @signals.Signal[Array[String]] = @signals.signal([], same=fn(a, b) { a == b })

///|
/// What the splash over the first page says while it waits (first_page_node: 正在读取你的 workspace and what the core
/// waits on, read till what the page shows is answered, the last of it said after).
let first_words : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// Whether what the first page shows has been answered as first_page_node read it (the splash's words read of the
/// core's status no more from then).
let first_answered : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// The first page's wait in node `v` (signed in), at the moments its causes come, between frames: `first_page_ms`
/// after the workspace came into view, the first page shown as it ends (first_expired); the first page shown at the
/// moment it waits no more (first_page_done: its pictures decoded, the host's word's moment); and the splash's words
/// over it (first_words) read of the core's `status` only till what the page shows is answered, so what was asked for
/// them is let go of at that moment, not as a frame after it builds.
fn first_page_node(v : @view.View, src : Source) -> Unit {
  // (its first_page_ms waited for no more once it has shown: nothing left due)
  let expiry : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(ws) {
    if ws is Some(_) && !first_shown.get() && first_from.val < 0.0 {
      first_from.val = v.cause_at()
      first_top.val = Some(app.nav.top())
      expiry.val = v.at_moment(first_from.val + first_page_ms, fn() { first_expired.set(true) })
    }
  })
  v.reacts(fn() { first_shown.get() }, fn(shown) {
    if shown {
      (expiry.val)()
    }
  })
  v.reacts(fn() { !first_shown.get() && first_from.val >= 0.0 && first_page_done() }, fn(done) {
    if done {
      first_shown.set(true)
      first_waiting.val = false
      first_hide(false)
    }
  })
  v.reacts(
    fn() {
      if first_shown.get() {
        return None
      }
      // (told again as a page declares more of what it reads: a chat's login cards, as its view says them, sfbase's
      // page_opens_node; read held then)
      @sfbase.page_declared_now() |> ignore
      // (once answered, the core's status read no more for it, though what the first page shows comes to be another)
      let answered = first_answered.get()
      guard workspace_in_view(src).0 is Some(w) else { return None }
      // (read once what its shell opens on is declared, each of it followed then: read before, none of it is, and
      // nothing would tell this of what comes to be; a frame after was what told it, till 2026-11-12)
      if @sfbase.opens_declared_now() != Some(w.id) {
        return Some(if answered { None } else { Some(t_reading_workspaces(src)) })
      }
      // (the shell whose function was declared, as it was: a window resized across the breakpoint before it shows
      // declares nothing again (opens_ahead_node), the page it began on waited for as it was)
      let wide = match first_wide.val {
        Some(wide) => wide
        None => {
          let wide = !(@sf.layout(v.window().0) is Small) || @sf.native_able()
          first_wide.val = Some(wide)
          wide
        }
      }
      let held = @sfbase.read_held_found(src)
      let ask = fn(n : String, p : Map[String, Json]) -> @sfbase.TopicState {
        match held(n, p) {
          Some(st) => st
          None => {
            // (what the first page waits for that its shell's function does not say: followed by nothing, so read
            // as not answered, never told when it is)
            // (one the function comes to say as this change answers what it read, declared in it too (opens_ahead_node):
            // told again then; one still not declared as the change is told whole, a fault: under a Tester it stops
            // the test, on a device it is told as a ui_fault report (src/stillfail/reports.mbt) and the app goes on,
            // the first page waiting for it as not answered till first_page_ms. A read the first page comes to have
            // goes in its shell's function, sfapp's home_opens or sfdesk's frame_opens, never here)
            let params = p.copy()
            @signals.after_flush(fn() {
              if @sfbase.read_held_found(src)(n, params) is None {
                @view.fault(
                  "first_page_node (stillfail/src/sfapp/app.mbt): the first page reads \{n} \{Json::object(params).stringify()}, which the shell's function it opens by (sfapp's home_opens, sfdesk's frame_opens) does not say",
                )
              }
            })
            { value: None, error: None, version: -1, waiting: false }
          }
        }
      }
      // (what it read held on to till the first page shows, answered or not: its readers are built by then, and
      // what was declared and read by this alone, let go of as this stops, would be asked again by them)
      if first_page_ready_by(src, w, wide, ask) || answered {
        Some(None)
      } else {
        Some(Some(t_reading_workspaces(src)))
      }
    },
    fn(said) {
      match said {
        Some(Some(words)) => first_words.set(words)
        // (answered: the core's status no longer read, the words last read kept; none read yet, the words alone)
        Some(None) => {
          first_answered.set(true)
          if first_words.get() == "" {
            first_words.set(tr("android-misc.workspaces.loading"))
          }
        }
        _ => ()
      }
    },
  )
}

///|
/// The splash over the first page while it is built and waits for what it shows (sfbase's first_page_waits, told by
/// the frame as it is: first_hide), in node `v`, over all it holds: splash_of_tree saying first_words, once the app's
/// first splash has waited its second; before it nothing over what the shell's nodes draw, its old views drawn at none
/// (view_in), as the old view's splash was.
fn first_splash_node(v : @view.View) -> Unit {
  v.show(fn() { @sfbase.first_page_waits.get() && splash_waited.get() }, fn(s) {
    s.over(Is(true)) |> ignore
    splash_of_tree(s, fn() { Some(first_words.get()) }, fn() { false })
  })
}

///|
/// When the workspace came into view, the first page's wait begun (-1: not yet): first_page_node's.
// kept across runs: put back as a run begins (new_run)
let first_from : Ref[Double] = Ref(-1.0)

///|
/// The page on top as the first page's wait began (first_page_node), laid out Small: the first page, what its wait
/// waits for (first_page_ready_by), whatever is opened over it meanwhile.
// kept across runs: put back as a run begins (new_run)
let first_top : Ref[Page?] = Ref(None)

///|
/// Whether the shell whose function was declared as the workspace came into view (opens_ahead_node) is the wide frame,
/// as first_page_node first read it so (None: not yet): what the first page waits for is what that shell declared
/// (first_page_ready_by), the window resized across the breakpoint before it shows or not.
// kept across runs: put back as a run begins (new_run)
let first_wide : Ref[Bool?] = Ref(None)

///|
/// Whether the app's first page has shown (first_page_shown).
let first_shown : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether this frame's first page is built and not shown yet (signed_in, view_in).
let first_waiting : Ref[Bool] = Ref(false)

///|
/// The chats' lists made once drawn at none while `on` (sfbase's first_page_waits), told only as it changes.
fn first_hide(on : Bool) -> Unit {
  if @signals.untracked(fn() { @sfbase.first_page_waits.get() }) != on {
    @sfbase.first_page_waits.set(on)
  }
}

///|
/// Whether this frame drew the ground alone (splash), and whether the window held (host_setup) is shown (view_in).
let frame_bare : Ref[Bool] = Ref(false)

///|
let window_shown : Ref[Bool] = Ref(false)

///|
/// Whether the core has answered for what the wide frame's pane shows of page `p` (sfdesk's pane_opens, what a
/// workspace switched waits for the page its pane lands on too): a chat; a new chat; an agent's history, a service and
/// a file asked as pages are their chat's with them beside it (sfdesk's service_tab.mbt beside_follow), the chat shown already,
/// what is beside it waited for in its tab; any other page is not waited for.
fn pane_ready(src : Source, p : Page) -> Bool {
  match workspace_in_view(src).0 {
    Some(w) => @sfdesk.pane_opens(w.id, p, @sfbase.read_now(src))
    None => true
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
/// its fields take a tap, draw their caret and handles and pick words as Android's (@ui.feel_as). So in a browser
/// started with a finger (a phone's or a tablet's): a browser has no field's ways of its own for a finger, and the
/// desktop's give a finger no way to its menu (粘贴 on a field held, its caret's handle tapped), as a finger has none to
/// right-click.
pub fn host_setup() -> Unit {
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0, inset=true)
  // out of sight till it has more than its ground to show (view_in): the first page as it is shown, else the splash
  // once it says that it waits (splash_label_ms), not an empty window for the page's first moments
  @hostapi.window_hold()
  if @ui.platform() == 1 || (@ui.platform() == 4 && @ui.native_pointing() is Finger) {
    @ui.feel_as(2)
  }
}

///|
using @sf {
  dmin,
  dmax,
  dclamp,
}
