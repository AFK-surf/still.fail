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
pub(all) struct App {
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
pub let app : App = {
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
pub let left_pages : Array[Page] = []

///|
pub fn new_nav() -> @ui.Nav[Page] {
  // settings are to the left of the list, as the gear is at its top left: they come in from the left and go back
  // that way (App.kt transition, swipe)
  @ui.Nav::new(Home, from_left=fn(p) { p is Settings }, on_leave=fn(p) {
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
  app.picked = ""
  app.filters.clear()
  app.menu = false
  app.switch_way = 0
  app.held = 0
  app.held_long = false
  app.toast = ""
  left_pages.clear()
  // the drive's files going up and being fetched (drive_upload.mbt, drive_keep.mbt)
  ups_reset()
  dv_fetches.clear()
  keepings.clear()
  // the chats' list (rows.mbt)
  read_views.clear()
  open_titled.val = ""
  shown_days.clear()
  // the core's downloads being taken and kept (downloads.mbt)
  downloads_reset()
  // what was asked of the core from a button, under way or failed (act.mbt)
  acting_reset()
  // the messages chats are to go to (jump.mbt)
  go_tos.clear()
  go_to_words.clear()
}

