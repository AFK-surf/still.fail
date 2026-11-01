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
  // an agent's card's jobs (sfpages): the chat's services and jobs as the screen shows them
  @sfbase.chat_jobs_asked.val = fn(c, src, r) {
    if @sf.layout(c.window_size().0) is Small {
      open_chat_jobs(src, r)
    } else {
      @sfdesk.open_jobs_pop()
    }
  }
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
  bar_timing.val = None
  bar_timed.val = None
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
  splash_waited.set(false)
  splash_from.val = -1.0
  splash_owner.val = None
  first_shown.val = false
  first_waiting.val = false
  first_has.val = 0
  frame_bare.val = false
  window_shown.val = false
  @sfbase.held_pictures_waiting.val = false
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
  dv_reset()
  decide_reset()
  @settings.reset()
  @sf.group_rows_reset()
  @sfdesk.drive_rows_reset()
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
  share_files_made.val = 0
  // the made-up core's own, where one is linked (a test's, a tool's: sffixture's, as its wire says)
  (@sfbase.made_reset.val)()
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  reset_by_hand.val = true
}

///|
/// What the app's own doings ask of the pages (sfbase shell.mbt): home and what is over the pages put their sheets
/// down too, an invitation's link shows its sheet, the screens live in their cards stop as the app goes behind.
fn pages_shell(src : Source) -> Shell {
  {
    home,
    close_overlays,
    open_invite,
    behind: peeks_stop_all,
    open: fn(p) { open_where(src, p) },
    open_over: fn(p) { open_over_where(src, p) },
    detail: detail_where,
    back: fn() { back_where(src) },
    show: fn() {
      if @sfdesk.is_wide(@ui.current()) {
        @sfdesk.show_page()
      }
    },
    edit_rail: fn() { @sfdesk.wide.editing.set(true) },
  }
}

///|
/// What back does where the layout has it (the tiers' table, docs/architecture.md): the wide frame's (sfdesk's
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
    Some(fn() { go_place(c, "chats", [], -1) })
  } else {
    None
  }
}

///|
/// Page `p` opened where the layout has it (the pane table, docs/architecture.md): on the wide frame the page pushed,
/// a chat's detail asked as a page (its history, a service, a file) laid beside its chat by the frame (sfdesk's
/// main_page), on the tape shown in the page pane (sfdesk's show_page: brought over with the side panel in use, also
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
/// Back to Home (the stack's root), what is over the pages put down (close_overlays: a file open over the window too,
/// as a notification tapped opens its chat over Home).
fn home() -> Unit {
  close_overlays()
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
  @sfbase.held_build(c.build_number())
  shell.val = pages_shell(src)
  // the Mac's menu bar, in the app's words (menu_bar.mbt); an item of the pages' chosen is read as its keys by the
  // frame after the menu said it (@settings.ask_action), and asked no more once that frame is built
  menu_bar(c, src)
  c.after_build("menu-asked", fn() { @settings.action_asked_done() })
  @sfdesk.window_zoom_keys(c, src)
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
  // a file opened since the last build set out before the pages, which read how it goes (sfbase viewer.mbt)
  @sfbase.viewer_set_out(c, src)
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
  // styles' roles (@sf styles.mbt, the pages' own) its ink, its sizes, its corners; the one place it is put
  // beside what the system has at the window's sides (sides.mbt)
  c.after_build("station-tabs-left", fn() { @sfdesk.station_tabs_sweep(c, src) })
  c.with_theme(@sf.ui_theme(), fn() { beside_sides(c, fn() { view_in(c, src) }) })
}

///|
fn view_in(c : @ui.Ctx, src : Source) -> Unit {
  // over another app (a share sheet over the app it came from: share.mbt share_over): nothing but the sheet (where the
  // window is a tree, a node of it picked by that: app_tree)
  if !@ui.old_islands_around() && share_over.get() {
    over_view(c, src)
    return
  }
  // under it all, the app's ground, made once (mbui's made.mbt; docs/retained.md, the way there's 4): what it holds is
  // the state the app is in, built the old way
  // (the state it is in, a node of the window's tree where the app runs as one (app_tree): its old view put here;
  // else made once among the frame's)
  if @ui.old_islands_around() {
    // (starting or failed, nodes of the window's tree with no old view to say it: said here, as the state is)
    match app_is(src) {
      (Starting | Failed) as state => splash_said(src, state)
      // (signed out, or signed in at the landing: the ways in's nodes, entry_tree.mbt)
      SignedOut => entry_said()
      SignedIn if shell_is(src, @ui.current().window_size().0) is Landing => entry_said()
      // (signed in, its workspaces still read or failing to be: the splash's nodes)
      SignedIn if shell_is(src, @ui.current().window_size().0) is Reading => reading_said(src)
      _ => ()
    }
    @ui.old_views_here(c)
  } else {
    c.made("app-ground", fn() { app_ground(c, src) })
  }
  // the first page built with what it shows, the pictures the device holds in it decoded as it drew them (a likeness
  // in a picture's place for the frame or two its decoding takes is not shown): shown from this frame
  if first_waiting.val &&
    (first_has.val == 2 || (first_has.val == 1 && !@sfbase.held_pictures_waiting.val)) {
    first_shown.val = true
    first_waiting.val = false
  }
  // the first page built, waiting for what it shows (signed_in): not shown yet, the splash over the window's ground
  // (what the host clears to, the ground's colour) in its place, its words as while the workspaces are read
  if first_waiting.val {
    // (the state's old view, or each of the shell's: narrow_shell.mbt)
    if !@ui.old_views_look(c, { ..@ui.still_look, alpha: 0.0 }) {
      c.look(state_node.val, { ..@ui.still_look, alpha: 0.0 })
    }
    c.layer(fn() { splash(c, Some(t_reading_workspaces(src)), false) }) |> ignore
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
priv enum AppIs {
  /// the core failed
  Failed
  /// signed out: the sign-in page
  SignedOut
  SignedIn
  /// the accounts not read yet, or failing to be
  Starting
} derive(Eq)

///|
/// Whether the stack of pages laid out Small (narrow_shell.mbt) is in a finger's hand now: its lists dragged and words
/// held to pick (pick.mbt); else a mouse's, the wheel scrolling them and a drag picking words, as the wide frame's.
fn stack_by_finger() -> Bool {
  @ui.pointing() is Finger
}

///|
/// The window's whole, on its ground (the theme's), that the app's state is built in.
fn app_ground_style() -> @ui.Style {
  page_whole.then(@ui.style(bg=Data(@sf.theme().p.bg)))
}

///|
/// The node the app's state is built in, this frame (app_ground): hidden while the first page waits (view_in).
// kept across runs: written by each build
let state_node : Ref[Int] = Ref(-1)

///|
/// Which of the app's states it is in, as the core's accounts and its failure say.
fn app_is(src : Source) -> AppIs {
  match ((src.topic)("accounts", {}).value, (src.fatal)()) {
    (_, Some(_)) => Failed
    (Some(Array(list)), _) if list.length() == 0 => SignedOut
    (Some(Array(_)), _) => SignedIn
    _ => Starting
  }
}

///|
/// The app's ground, made once: the window's ground, its top dragging it where the window's buttons are in the app's
/// top row, and the state the app is in (app_is), made as it comes and built the old way in it (its pages islands of
/// their own), saying afresh whether the frame draws the ground alone and whether the first page waits (frame_bare,
/// first_waiting).
fn app_ground(c : @ui.Ctx, src : Source) -> @ui.Made {
  let picked = @ui.made_pick(fn() { app_is(src) }, fn(state) { @ui.made_old(fn(c) { app_state_island(c, src, state) }) })
  @ui.made_holding(
    fn(c) { c.box(style=app_ground_style(), fn() {  }) |> ignore },
    fn() { picked() },
  )
}

///|
/// The window as a tree made once (mbui's view_host.mbt; docs/retained.md, the way there's 4: from the outside in): the
/// state the app is in (app_is) a node picked by it, made as it comes and let go as it goes, the app in that state an old
/// view in it, built the old way on the window's ground (`view` the old frame around it: what every state shares, the
/// theme, the window's sides, the layers over it).
pub fn app_tree(src : Source) -> (@view.View) -> Unit {
  fn(root) {
    // (the library's words, the app's catalog's, and their language as the core's prefs say it, said before any page of
    // nodes is made: what one says on its first frame is its words in that language, not their keys or the device's
    // laid out and then said again; the old frame tells them each build, the same)
    @sf.set_words(fill)
    @sfbase.language_said(src)
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
  }
}

///|
/// The app in the state it is in (app_is), a node picked by it (app_tree's, not over another app).
fn app_state_tree(root : @view.View, src : Source) -> Unit {
  root.pick(
    fn() { app_is(src) },
    fn(v, state) {
      v.grow(Is(1.0)) |> ignore
      let whole = fn(v : @view.View) {
        @ui.old(v, fn(c) {
          c.box(style=app_ground_style(), fn() { app_state_island(c, src, state) }) |> ignore
        })
        .grow(Is(1.0))
        |> ignore
      }
      if state == Starting || state == Failed {
        // starting or failed, the splash: the window's tree's nodes (splash_tree)
        splash_tree(v, src, state)
      } else if state == SignedOut {
        // signed out, the sign-in page: the window's tree's nodes (entry_tree.mbt)
        signed_out_tree(v, src)
      } else if state == SignedIn {
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
        // signed in, the shell it is laid out in a node picked by the window's width and what is in view
        // (narrow_shell.mbt): laid out Small with a workspace, the narrow shell's nodes; on the tape, its panels' nodes
        // (tape_shell.mbt); else the old view whole
        v.pick(fn() { shell_is(src, v.window().0) }, fn(s, shell) {
          s.grow(Is(1.0)) |> ignore
          match shell {
            Stacked => narrow_shell(s, src)
            Taped => taped_shell(s, src)
            Paned => paned_shell(s, src)
            Landing => landing_tree(s, src)
            Reading => reading_tree(s, src)
            Whole => whole(s)
          }
        })
      } else {
        whole(v)
      }
    },
  )
}

///|
/// The app in state `state` as an old view (app_ground's, app_tree's): the window's top dragging it where the window's
/// buttons are in the app's top row, and the state built the old way, saying afresh whether the frame draws the ground
/// alone and whether the first page waits (frame_bare, first_waiting).
fn app_state_island(c : @ui.Ctx, src : Source, state : AppIs) -> Unit {
  // in a window with its buttons in the app's top row, its top drags it whatever is shown (the splash, signing in,
  // a window of its own still starting): under all of it, so what a page puts there takes its own presses
  if @ui.window_inset() {
    let id = c.id("window-ground-band")
    c.window_drag(id)
    c.box(style=@ui.style(h=Fixed(window_band())), left=0.0, top=0.0, right=0.0, id~, fn() {  }) |> ignore
  }
  first_waiting.val = false
  frame_bare.val = false
  // (said by this build: image_item, video_item)
  @sfbase.held_pictures_waiting.val = false
  // (in a box of its own: what the frame says of it, its look while the first page waits, is said of what is built
  // anew each frame, not of the ground made once)
  state_node.val = c.box(style=page_whole, fn() { app_state(c, src, state) })
}

///|
/// The app in state `state` (app_ground's island).
fn app_state(c : @ui.Ctx, src : Source, state : AppIs) -> Unit {
  match state {
    Failed => splash(c, splash_label(src, state), true)
    SignedOut => {
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
    SignedIn => signed_in(c, src)
    Starting => {
      let label = splash_label(src, state)
      splash(c, label, label is Some(_))
    }
  }
}

///|
/// A window of its own (sfbase's window.mbt): page `p` alone over all of it, closing it ending the run (its window
/// closed as its own close button closes it); the library's presenters and the toasts over it. None of the app's: no
/// workspace, its notifications, the number on its icon, its updates (the app's run beside it has them).
fn lone_view(c : @ui.Ctx, src : Source, p : Page) -> Unit {
  match p {
    Screen(at) =>
      @sfpages.screen_page(c, src, at, system_frame(), on_close=fn() {
        c.after_build("lone-closed", fn() { @hostapi.exit(0) })
      })
    _ => ()
  }
  @sf.presented(c)
  toast(c)
}

///|
/// Signed in: the workspace in view (the one switched to, else the one last open, else the first once every account
/// has answered), its Home at the root of the pages; the splash while none is known yet and until the first page has
/// what it shows, and a page that says so when there is none.
fn signed_in(c : @ui.Ctx, src : Source) -> Unit {
  // a window of its own (@sfbase.lone_page): its page alone, none of the app's
  match @sfbase.lone_page.val {
    Some(p) => {
      lone_view(c, src, p)
      return
    }
    None => ()
  }
  let t = @sf.theme()
  let ws = (src.topic)("workspaces", {})
  let (current, all, answered, invited) = workspace_in_view(src)
  match current {
    Some(w) => {
      signed_in_frame(c, src, w)
      if @sfdesk.is_wide(c) {
        // (the wide frame is the window's tree's, its shell picked by the window's width as a frame gives it: app_tree,
        // tape_shell.mbt; laid out wide before it is known, none of it yet)
        ()
      } else {
        // a page opened slides in once the core has given what it shows, or said it waits on a station (page_local_ms at
        // most)
        app.nav.comes_when(fn() { page_ready(src, w, app.nav.top()) }, page_local_ms)
        narrow_lists(c)
        let finger = stack_by_finger()
        let page_took = c.took_back(fn() {
          let pages = fn() {
            c.nav(app.nav, fn(page) { narrow_page(c, src, w, page) }, bg=t.p.bg) |> ignore
            // ⌘K's search over a page other than the lists (sfdesk's keys.mbt, sfpages' search.mbt), under the bars
            @sfpages.search_over(c, src, w, status_top())
          }
          if finger {
            pages()
          } else {
            c.selectable(color=@sf.alpha(t.p.blue, 0.28), pages)
          }
        })
        if !page_took {
          narrow_root_back(c)
        }
        // the player sideways: back turns it upright first; words picked in a chat, a link's menu: back lets go of
        // them first (pick.mbt)
        play_back(c)
        pick_back(c)
        narrow_over(c, src, w)
      }
      signed_in_over(c, src, w)
    }
    None =>
      // (none in view while the prefs are read too: workspace_in_view)
      if ws.value is Some(_) && answered && all.is_empty() {
        // the landing inside the bars (Workspaces.kt Landing: windowInsetsPadding(systemBars.union(keyboard)))
        // (sfpages' cloud_app.mbt); an invitation's link pasted (用邀请链接加入): its sheet over the page
        within_bars(c, fn() { @sfpages.no_workspace(c, src, ws.value, open_invite_link) })
        sheet_contents(fn(kind) { if kind == InviteLink { invite_sheet(c, src) } })
        // the library's presenters over it (the sheet among them: src/sf presenters.mbt), then the toasts
        @sf.presented(c)
        toast(c)
        finger_loupe(c)
      } else {
        let (said, failed) = reading_said_words(src)
        splash(c, Some(said), failed)
      }
  }
}

///|
/// What the splash says while no workspace is in view yet and the landing is not shown (signed_in's): why reading the
/// workspaces failed (the core's words), else 正在读取你的 workspace and what it waits on (t_reading_workspaces); and
/// whether it failed (said at once, not after the splash's second).
fn reading_said_words(src : Source) -> (String, Bool) {
  match (src.topic)("workspaces", {}).error {
    Some(e) => (text(Some(e), "message"), true)
    None => (t_reading_workspaces(src), false)
  }
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), as the frame begins (view_in's): what the
/// old view's build said of the frame (app_state_island, splash): no first page waiting nor its pictures; the ground
/// alone until the splash's second, unless it failed.
fn reading_said(src : Source) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = false
  frame_bare.val = !splash_waited.get() && !reading_said_words(src).1
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), in node `v`: the splash's nodes saying so
/// as it changes (reading_said_words).
fn reading_tree(v : @view.View, src : Source) -> Unit {
  splash_of_tree(v, fn() { Some(reading_said_words(src).0) }, fn() { reading_said_words(src).1 })
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
  // a place switched to on the bar comes in from the side the ball goes to, fading in (220 ms; 180 from no side); the
  // page at the stack's root is so with a page sliding in over it or back off it too (where it stands, not how deep
  // the stack is: Nav::under), its place's top bar kept
  let root = app.nav.under() is None
  let e = if root { place_switch(c).get() } else { 1.0 }
  if root {
    bar_built(c, page)
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    tx=app.switch_way.to_double() * switch_slide * (1.0 - e),
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
        Files => files_page(c, src, w, place=root)
        Drive(at) => drive_page(c, src, w, at)
        DriveRead(at) => @sfpages.reader_page(c, src, at)
        DrivePlay(at) => @sfpages.play_page(c, src, at)
        Service(station, job) => service_page(c, src, station, job)
        PreviewFile(station, key, path, name) => preview_file_page(c, src, station, key, path, name)
        Archived => setting_page(c, src, w, @settings.Route::Archive)
        Settings => setting_page(c, src, w, @settings.Route::Home)
        Setting(r) => setting_page(c, src, w, r)
        History(r, key, entry) => history_page(c, src, r, key, entry)
        Words(head, words) => words_page(c, src, head, words)
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
  fade.animate(1.0, if way == 0 { @motion.tween(switch_fade_ms, ease=Out) } else { @motion.move(points=switch_slide) })
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
/// How long a place switched to on the bar takes to come in: fading in from no side, from the side the ball goes to.
pub let switch_fade_ms : Double = 180.0

///|
/// How far a place switched to on the bar comes in from its side (points), a Move as long as that is far.
pub let switch_slide : Double = 30.0

///|
/// How far a place switched to on the bar has come in (0 … 1).
fn place_switch(c : @ui.Ctx) -> @motion.Anim {
  @motion.anim(c, "place/switch", 1.0, global=true)
}

///|
/// What a write said (sfbase's toasts), where the frame has it: the wide frame's 24 over the window's foot (the web's),
/// the narrow one's over the foot, clear of the bar and the action standing over it (bar_room above it) and above the
/// navigation bar the view reaches under (Sheet.kt's navigationBars padding); over the system's tabs across the foot
/// where they are (an iPhone Duo upright: @sf.native_foot).
fn toast(c : @ui.Ctx) -> Unit {
  @sfbase.toasts(c, if @sfdesk.is_wide(c) { @sf.toast_bottom + @sf.native_foot() } else { bar_room + nav_foot() })
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
/// The app starting, or waiting for what every page needs (Parts.kt Splash): the ground alone, as the system's own
/// splash before the app's first frame is (Android's theme, iOS's launch screen), so an opening quicker than a second
/// is one picture and then the page; once it takes a while (a second), still.fail's mark and what it waits for under
/// it, from then on; at once when `now` (a failure). (The mark at once, on Android after the launcher's
/// icon on the system's splash, then the page: three pictures in a second, 2026-10-26 「打开的时候感觉乱闪」.)
fn splash(c : @ui.Ctx, label : String?, now : Bool) -> Unit {
  let t = @sf.theme()
  // a second after the app's first splash, it is said that it waits, and for what, from then on: set at that moment
  // by what lives through the app's states (splash_begin), nothing set as this is built; with no window's tree (a
  // test's old view alone), as the build finds it waited
  if !splash_waited.get() {
    match splash_owner.val {
      Some(owner) if owner.alive() => splash_begin(owner, c.moment())
      _ =>
        if @kit.after(c, "splash-label", true, splash_label_ms) {
          splash_waited.set(true)
        }
    }
  }
  if !now && !splash_waited.get() {
    // (the ground alone: the window held is not shown for it, view_in)
    frame_bare.val = true
    return
  }
  c.box(
    w=Fill(1.0),
    h=Fill(1.0),
    pad=24.0,
    gap=16.0,
    align=ACenter,
    justify=JCenter,
    fn() {
      @sf.drawable(c, if t.dark { "stillfail_mark_dark" } else { "stillfail_mark" }, 56.0) |> ignore
      match label {
        Some(s) =>
          c.text(s, size=t.t.meta, color=t.p.muted, center=true, line=18.0)
          |> ignore
        None => ()
      }
    },
  )
  |> ignore
}

///|
/// What the splash says it waits for, or what failed (`state` Starting or Failed): the core's failure; the accounts'
/// error. Said at once where there is one (splash's `now`).
fn splash_label(src : Source, state : AppIs) -> String? {
  match state {
    Failed => (src.fatal)()
    _ =>
      match (src.topic)("accounts", {}).error {
        Some(e) => Some(text(Some(e), "message"))
        None => None
      }
  }
}

///|
/// Starting or failed, the window's tree's nodes in its place (app_state_tree): what an old view's build of the app's
/// state says of the frame (app_state_island), said from the state it is in as the frame begins (view_in): no first
/// page waiting nor its pictures; the ground alone until the splash's second, unless there is something to say at once.
fn splash_said(src : Source, state : AppIs) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = false
  frame_bare.val = !splash_waited.get() && splash_label(src, state) is None
}

///|
/// The splash (`state` Starting or Failed) as the window's tree's nodes (app_state_tree's): splash_of_tree saying what
/// it waits for or what failed (splash_label), at once where there is something to say.
fn splash_tree(v : @view.View, src : Source, state : AppIs) -> Unit {
  splash_of_tree(v, fn() { splash_label(src, state) }, fn() { splash_label(src, state) is Some(_) })
}

///|
/// The splash as the window's tree's nodes in `v` (splash's): saying `label` as it changes, the ground alone till the
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
      m.show(fn() { label() is Some(_) }, fn(w) {
        w
        .words(By(fn() { label().unwrap_or("") }))
        .words_look(By(fn() { { size: @sf.theme().t.meta, weight: 400, line: 18.0, wrap: true } }))
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
/// How long the splash shows the ground alone before it says that it waits, and for what.
let splash_label_ms : Double = 1000.0

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
/// opening): a chat (or said its messages wait on a station: its page shows them to come), an agent's history, Home's
/// list and what the last update brought over it (home.mbt); any other page is not waited for.
fn page_ready(src : Source, w : Workspace, p : Page) -> Bool {
  let answered = fn(t : Topic) { t.value is Some(_) || t.error is Some(_) }
  match p {
    Chat(r) => chat_answered(src, r)
    History(r, key, _) => chat_answered(src, r) && answered((src.topic)("history", history_params(r, key)))
    Home => list_ready(src, w) && answered((src.topic)("changelog", Map::new()))
    _ => true
  }
}

///|
/// Whether the core has answered for workspace `w`'s chats' list as it is filtered (Home's, the wide frame's sidebar's).
fn list_ready(src : Source, w : Workspace) -> Bool {
  let (list, error) = chats_of(src, w.id, filter_of(src, w.id))
  list is Some(_) || error is Some(_)
}

///|
/// Whether the app's first page shows: once the core has answered for what it shows (first_page_ready), or
/// `first_page_ms` after the workspace came into view, from then on.
fn first_page_shown(c : @ui.Ctx, src : Source, w : Workspace) -> Bool {
  if !first_shown.val {
    first_has.val = if @kit.after(c, "first-page", true, first_page_ms) {
      2
    } else if first_page_ready(c, src, w) {
      1
    } else {
      0
    }
  }
  first_shown.val
}

///|
/// What the first page not shown yet has this frame (first_page_shown): 0 not what it shows, 1 what it shows (shown
/// once the pictures the device holds in it are decoded too: view_in), 2 first_page_ms gone by (shown as it is).
let first_has : Ref[Int] = Ref(0)

///|
/// Whether the core has answered for what the app's first page shows, as a page opening waits for it: laid out Small
/// the page on top (page_ready), in the wide frame the sidebar's list and the page in the pane (pane_ready), the chat
/// the pane lands on once it has (@sfdesk.landing: not the empty pane before it).
fn first_page_ready(c : @ui.Ctx, src : Source, w : Workspace) -> Bool {
  if @sfdesk.is_wide(c) {
    list_ready(src, w) && !@sfdesk.landing(w) && pane_ready(src, app.nav.top())
  } else {
    page_ready(src, w, app.nav.top())
  }
}

///|
/// Whether the app's first page has shown (first_page_shown).
let first_shown : Ref[Bool] = Ref(false)

///|
/// Whether this frame's first page is built and not shown yet (signed_in, view_in).
let first_waiting : Ref[Bool] = Ref(false)

///|
/// Whether this frame drew the ground alone (splash), and whether the window held (host_setup) is shown (view_in).
let frame_bare : Ref[Bool] = Ref(false)

///|
let window_shown : Ref[Bool] = Ref(false)

///|
/// Whether the core has answered for what the wide frame's pane shows of page `p`: a chat; an agent's history, a
/// service and a file asked as pages are their chat's with them beside it (sfdesk's frame.mbt main_page), the chat
/// shown already, what is beside it waited for in its tab; any other page is not waited for.
fn pane_ready(src : Source, p : Page) -> Bool {
  match p {
    Chat(r) => chat_answered(src, r)
    _ => true
  }
}

///|
/// Whether the core has answered for chat `r`: its view, why it has none, or that its messages wait on a station (none
/// of them on the device: Source.waits).
fn chat_answered(src : Source, r : ChatRef) -> Bool {
  let params = chat_params(r)
  let t = (src.topic)("chat", params)
  t.value is Some(_) || t.error is Some(_) || (src.waits)("chat", params)
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
  // out of sight till it has more than its ground to show (view_in): the first page as it is shown, else the splash
  // once it says that it waits (splash_label_ms), not an empty window for the page's first moments
  @hostapi.window_hold()
  if @ui.platform() == 1 {
    @ui.feel_as(2)
  }
}
