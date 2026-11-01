// The app's pages, as a stack both frames show (the phone's pages pushed and swiped back; the wide frame's pane beside
// the rail): what a page is, the stack and what the app keeps of it; a chat, a drive's place and a station's screen as
// a page names them.

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
  /// an agent's execution history (history.mbt): its chat, its session, the transcript entry it opens at (a link's
  /// `entry`; None: its newest)
  History(ChatRef, String, Int?)
  /// an entry of a history opened in full: the line it was under, its words
  Words(String, String)
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
  /// a page under settings (src/sfapp/settings: me, appearance, stations, the workspace…)
  Setting(@settings.Route)
  /// a station's screen, seen and driven (screen_view.mbt), over the app as Android's ScreenActivity is
  Screen(ScreenAt)
} derive(Eq)

///|
/// What the frame a page is shown in gives it: the library's (@sf.page's `frame`).
pub using @sf {
  type PageFrame,
}

///|
/// A station's screen to view: its station (`<workspace>/<station>`), its id there, and its title until the core says
/// one (the link's own, or the row's it was opened from; "" none). `until_gone`: opened for a while only (a login's
/// page in the station's browser, its tab closed as the login ends): the page goes back by itself once the screen is
/// gone.
pub(all) struct ScreenAt {
  station : String
  screen : String
  title : String
  until_gone : Bool
} derive(Eq)

///|
/// What page `p` is, by its kind alone (no chat's, station's or file's name: the device's performance record says it,
/// @ui.perf_also "page").
pub fn page_kind(p : Page) -> String {
  match p {
    Home => "Home"
    Chat(_) => "Chat"
    Archived => "Archived"
    Settings => "Settings"
    Files => "Files"
    Drive(_) => "Drive"
    DriveRead(_) => "DriveRead"
    DrivePlay(_) => "DrivePlay"
    Service(_, _) => "Service"
    PreviewFile(_, _, _, _) => "PreviewFile"
    History(_, _, _) => "History"
    Words(_, _) => "Words"
    NewChat => "NewChat"
    Place(place) => "Place " + place
    Setting(_) => "Setting"
    Screen(_) => "Screen"
  }
}

///|
pub(all) struct App {
  mut nav : @ui.Nav[Page]
  /// the workspace switched to here, before the core's prefs say it
  picked : @signals.Signal[String]
  /// the list's filter chosen here, by workspace, before the prefs say it
  filters : @sf.LiveMap[String, String]
  /// the filter's menu open
  mut menu : Bool
  /// a place switched to on the bar: from which side (1 from the right, -1 the left, 0 from no side)
  mut switch_way : Int
  /// a row held: its id, and whether it has been held long (its time on @kit.after)
  mut held : Int
  mut held_long : Bool
  /// what was said last of a write (a toast): its words, which saying it is (one said again is a new one), what it
  /// offers to do (its button's words, "" none: an archive's 撤销) and what that does, said together (toast_later)
  toast : @signals.Signal[ToastSaid]
}

///|
/// A write's toast as it was said (toast_later): its words ("" none), which saying it is, its button's words ("" none)
/// and what that does, one value: what reads it reads them all as one saying.
pub(all) struct ToastSaid {
  words : String
  n : Int
  action : String
  run : () -> Unit
}

///|
/// No toast (none said, or the one said gone).
pub let toast_none : ToastSaid = { words: "", n: 0, action: "", run: fn() {  } }

///|
pub let app : App = {
  nav: new_nav(),
  picked: @signals.signal("", same=fn(a, b) { a == b }),
  filters: @sf.LiveMap::new(),
  menu: false,
  switch_way: 0,
  held: 0,
  held_long: false,
  toast: @signals.signal(toast_none, same=fn(a, b) { physical_equal(a, b) }),
}

///|
/// What a page left leaves behind: a chat's topic and what it told the core.
pub let left_pages : Array[Page] = []

///|
/// Told as a page is left (left_pages): what tells where it was left (the frame's pages-left) built again for it.
// kept across runs: only counts on
pub let left_said : @signals.Signal[Int] = @signals.signal(0)

///|
pub fn new_nav() -> @ui.Nav[Page] {
  // settings are to the left of the list, as the gear is at its top left: they come in from the left and go back
  // that way (App.kt transition, swipe)
  // what its own back comes to, back's in the history (app_history.mbt went_back)
  @ui.Nav::new(Home, from_left=fn(p) { p is Settings }, went_back~, on_leave=fn(p) {
    left_pages.push(p)
    left_said.set(@signals.untracked(fn() { left_said.get() }) + 1)
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
/// (@settings.route_of), through the pages one comes to it by (setting_way: a memory page under its station's memory,
/// under 记忆), so what is over it and back says are as a person finds them.
pub fn open_setting(name : String) -> Unit {
  match @settings.route_of(name) {
    Some(@settings.Route::Home) => open_page(Settings)
    Some(r) => {
      open_page(Settings)
      for w in setting_way(r) {
        open_page(Setting(w))
      }
      open_page(Setting(r))
    }
    None => ()
  }
}

///|
/// The settings' pages one comes through to `r` from their list, where it is not on it.
fn setting_way(r : @settings.Route) -> Array[@settings.Route] {
  match r {
    Memory(_) => [Memories]
    MemoryDoc(a, _, _) => [Memories, Memory(a)]
    AutoCompletion => [AutoDecisions]
    AutoPolicy(_) => [AutoDecisions, AutoCompletion]
    _ => []
  }
}

///|
/// Back to Home (the stack's root), the filter's menu closed: a workspace left, from either frame.
pub fn nav_home() -> Unit {
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
}

///|
/// A chat opened over Home from the start (a link, a scripted run).
pub fn open_chat(r : ChatRef) -> Unit {
  open_page(Chat(r))
}

///|
/// Page `p` opened, where the layout has it (Shell's `open`: the pane table, docs/architecture.md): what pages, links
/// and the app's own doings call, never the stack themselves.
pub fn open_page(p : Page) -> Unit {
  history_act(fn() { (shell.val.open)(p) })
}

///|
/// Page `p` opened from the page in view (a chat's link in a message): over it, back coming to it again, where the
/// layout has it (Shell's `open_over`).
pub fn open_page_over(p : Page) -> Unit {
  history_act(fn() { (shell.val.open_over)(p) })
}


///|
/// A chat the page is of: its station, the session it is opened by (a row's `session`), its title and its station's
/// name as the row said them (the page shows the view's own once it is read).
pub(all) struct ChatRef {
  station : String
  session : String
  title : String
  station_name : String
} derive(Eq)

///|
/// Where a page of a drive is: a station, one of its roots (None: the drive itself, its roots), a path under it.
pub(all) struct DriveAt {
  station : String
  root : String?
  path : String
} derive(Eq)

///|
/// As at the start: Home alone on the stack, nothing chosen here yet, nothing said, no page left (the app's reset; a
/// toast's count goes on, as before it was here).
pub fn reset() -> Unit {
  app.nav = new_nav()
  // where it has been (app_history.mbt)
  history_reset()
  app.picked.set("")
  @ui.set_motion_chosen(None)
  app.filters.clear()
  app.menu = false
  app.switch_way = 0
  app.held = 0
  app.held_long = false
  // (none said; which saying was last kept: the next a new one, as ever)
  app.toast.set({ ..toast_none, n: @signals.untracked(fn() { app.toast.get().n }) })
  left_pages.clear()
  // the topics read for what has not ended yet (held.mbt)
  held_reset()
  felt_holds.clear()
  nav_tapped.clear()
  // the drive's files going up and being fetched (drive_upload.mbt, drive_keep.mbt)
  ups_reset()
  dv_fetches.clear()
  keepings.clear()
  // what was worked out of the core's topics (derived.mbt)
  kept_reset()
  open_titled.val = ""
  shown_days.clear()
  held_from.clear()
  // the core's downloads being taken and kept (downloads.mbt)
  downloads_reset()
  // the drafts as the core keeps them (compose.mbt)
  writings_reset()
  // services' pages kept, their sizes, what was marked on them (service_page.mbt)
  service_pages_reset()
  // a file open over the pages, what it flew from and kept (viewer.mbt, viewer_marks.mbt)
  file_viewer_reset()
  // what comes and goes under the posts (under_post.mbt)
  under_reset()
  machine_here.val = None
  // a station's screens' cards live in a chat (screen_links.mbt)
  peeks_reset()
  // visualizations drawn, one open over the whole window, words they asked to send (viz_page.mbt)
  viz_pages_reset()
  // what was sent from here, not in the core's view yet (sent.mbt)
  sent_reset()
  // what the composers' fields were seen as, their marks and `@` words (refs.mbt)
  refs_reset()
  // a send asking about what it refers to (outside.mbt)
  outside_reset()
  // what was asked of the core from a button, under way or failed (act.mbt)
  acting_reset()
  // how an update stands (updates.mbt)
  update_reset()
  // a chat's relay picker (relay.mbt)
  relay_reset()
  // the messages chats are to go to (jump.mbt)
  go_tos.clear()
  go_to_passages.clear()
  go_to_words.clear()
  // a new chat while it is made (fresh.mbt)
  fresh_reset()
  // how times are said (message_words.mbt)
  absolute_times.val = false
  // a chat's list's turns and its messages out of avatars (list_turns.mbt, emit.mbt)
  turns_by.clear()
  emits.clear()
  // words sent flying (flight.mbt)
  send_flight.set(None)
  landing_shares.clear()
  // the chats' lists as kept while they show and where they were left (chat_list.mbt)
  readings.clear()
  kept_places.clear()
  flash_held.val = false
  at_end_env.val = -1
  // what the settings' core keeps (settings_core.mbt, notices.mbt, faces.mbt, bars.mbt)
  picture_pick.val = None
  reporting_host.set(None)
  notices_reset()
  faces_reset()
  bars_picked.set(None)
  // what the app does whichever frame draws it (app_frame.mbt, open_links.mbt, menu_bar.mbt, shell.mbt)
  app_frame_reset()
  links_reset()
  menu_bar_given.val = ""
  shell.val = bare_shell()
  // the page shown alone in a window of its own (window.mbt)
  lone_page.val = None
}

///|
/// Each hold's press as last felt (`what` held: a message's words picked, a link's menu, a page's bar folded): once a
/// press, whichever of a frame's builds saw it.
let felt_holds : Map[String, Int] = {}

///|
/// Felt as the hold `what` takes the press it is (MessagePick.kt, Links.kt, Preview.kt: HapticFeedbackType.LongPress),
/// once.
pub fn feel_hold(c : @ui.Ctx, what : String) -> Unit {
  let at = c.press().frame
  c.after_build("haptic/hold/" + what, fn() {
    if felt_holds.get(what) != Some(at) {
      felt_holds[what] = at
      @ui.haptic(LongPress)
    }
  })
}

///|
/// What back over a page says: the title of the page it goes back to.
pub fn back_label(p : Page) -> String {
  match p {
    Home => @sf.t("android-misc.bar.place.chats")
    Settings | Setting(@settings.Route::Home) => @sf.t("android-settings.title")
    Setting(@settings.Route::About) => @sf.t("web-pages.settings.nav.about")
    Setting(@settings.Route::Permissions) => @sf.t("web-pages.settings.nav.permissions")
    Setting(@settings.Route::Memories) | Setting(@settings.Route::Memory(_)) => @sf.t("web-pages.settings.memory.title")
    Setting(@settings.Route::AutoDecisions) => @sf.t("web-pages.automaticDecisions.title")
    Setting(@settings.Route::AutoCompletion) => @sf.t("web-pages.automaticDecisions.completion")
    Setting(@settings.Route::Archiving) => @sf.t("web-pages.archiving.title")
    Setting(@settings.Route::Shortcuts) => @sf.t("web-main.shortcuts.title")
    Setting(@settings.Route::Usage) => @sf.t("web-pages.settings.nav.usage")
    Setting(@settings.Route::Security) => @sf.t("web-pages.security.title")
    Setting(@settings.Route::Vault) => @sf.t("web-pages.vault.title")
    Setting(@settings.Route::VaultItems) => @sf.t("web-pages.vault.all")
    Setting(@settings.Route::Connects(_)) | Place("connects") => @sf.t("android-settings.connects.title")
    Place("usage") => @sf.t("web-pages.settings.nav.usage")
    _ => @sf.t("common.back")
  }
}

///|
/// The page picked in a place with a list of its own (the stations', the profiles'), by workspace and place
/// (`place_key`); none: the shell's first. Said by the place's list (a row pressed) and by a page that leads to another
/// of its list or is gone from it (a profile's other stations, a profile deleted); the shell shows it (src/sfdesk
/// places.mbt place_route). Each workspace keeps its own: one picked in another is none of this one's list.
// kept across runs: said by a row or a page; the shell's places_reset empties it
pub let place_pick : @sf.LiveMap[String, @settings.Route] = @sf.LiveMap::new()

///|
/// `place_pick`'s key for `place` in the workspace `ws`.
pub fn place_key(ws : String, place : String) -> String {
  ws + "\n" + place
}
