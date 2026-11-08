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
  /// a visualization as a page of its own: its station, the session that keeps it, its
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
/// Keep a chat's own reader while its navigation entry remains on the stack, including while another page covers it.
/// Other pages keep only the readers of their visible views.
pub fn page_chat_reader(src : Source, entry : @view.View, serial : Int) -> (Page) -> Unit {
  let held : Ref[(String, TopicLease)?] = Ref(None)
  fn(page) {
    match page {
      Chat(r) => {
        let key = r.station + "\u{1}" + r.session
        if held.val is Some((old, reader)) && old == key && reader.alive() {
          page_chat_ready(serial, src, key)
          return
        }
        let next = src.lease_topic("chat", chat_params(r))
        next.bind_to(entry)
        let previous = held.val
        held.val = Some((key, next))
        match previous { Some((_, reader)) => reader.release(); None => () }
        if next.alive() { page_chat_ready(serial, src, key) }
      }
      _ => {
        let previous = held.val
        held.val = None
        match previous { Some((_, reader)) => reader.release(); None => () }
      }
    }
  }
}

///|
/// A chat's page made once in node `v` of a stack's (entry `serial`'s: nav_view's and nav_flat_view's `made`), and the
/// new chat that becomes it in place, the same page: what it holds its old view as yet, its island (Nav::page_island),
/// built by `build` as the stack built it before (a chat from the source it keeps while its entry is on the stack, its
/// reader held: page_entry_source, page_chat_reader; a new chat from the node's own), again as `key` changes.
pub fn chat_page_made(
  v : @view.View,
  src : Source,
  serial : Int,
  build : (@ui.Ctx, Source, Page) -> Unit,
  key? : () -> String = fn() { "" },
) -> Unit {
  let retained = page_entry_source(src, v, serial)
  let page_read = page_chat_reader(retained, v, serial)
  let shown = src.owned_by(v)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  app.nav.page_island(
    v,
    serial,
    fn(c, page) {
      page_entry_read(serial, retained, page)
      page_read(page)
      build(c, if page is Chat(_) { retained } else { shown }, page)
    },
    key~,
  )
  .grow(Is(1.0))
  |> ignore
}

///|
/// Whether page `page` is a chat's made once (chat_page_made): a chat, or the new chat that becomes one in place.
pub fn chat_page_is(page : Page) -> Bool {
  page is (Chat(_) | NewChat)
}

///|
priv struct PageSource {
  source : Source
  mut page : Page?
  mut seen : Int
  mut chat_ready : String
  mut chat_view : ChatView?
  mut active : Bool
}

///|
let page_sources : Map[Int, Array[PageSource]] = {}

///|
priv struct LeftPageChat {
  source : Source
  view : ChatView?
}

///|
// An explicitly absent entry means a navigation entry left before it had a page source. A missing map entry is an
// older caller that placed a page directly in left_pages and still uses the surrounding source.
let left_page_sources : Map[Int, LeftPageChat?] = {}

///|
let page_source_seen : Ref[Int] = Ref(0)

///|
priv struct PendingChatReader {
  reader : TopicLease
  mut unkeep : (() -> Unit)?
}

///|
let pending_chat_readers : Map[Int, PendingChatReader] = {}

///|
/// Whether a row is still keeping an early reader for this navigation entry.
pub fn chat_open_is_pending(serial : Int) -> Bool {
  pending_chat_readers.contains(serial)
}

///|
fn stop_pending_chat(pending : PendingChatReader) -> Unit {
  match pending.unkeep {
    Some(unkeep) => { pending.unkeep = None; unkeep() }
    None => ()
  }
  pending.reader.release()
}

///|
fn release_pending_chat(serial : Int) -> Unit {
  match pending_chat_readers.get(serial) {
    Some(pending) => {
      pending_chat_readers.remove(serial)
      stop_pending_chat(pending)
    }
    None => ()
  }
}

///|
fn page_chat_ready(serial : Int, src : Source, key : String) -> Unit {
  match page_sources.get(serial) {
    Some(sources) => for current in sources {
      if physical_equal(current.source, src) { current.chat_ready = key }
    }
    None => ()
  }
  // The page's own reader was acquired before the early reader can be stopped.
  release_pending_chat(serial)
}

///|
/// Keep a row's reader through the open callback, which may synchronously let the row's view go.
pub fn prepare_chat_handoff(reader : TopicLease) -> TopicLease? {
  match @ui.view_tree() {
    Some(tree) => match reader.detach_to(tree.root()) {
      Some(next) => Some(next)
      None => { reader.release(); None }
    }
    None => { reader.release(); None }
  }
}

///|
/// After a row opens a chat, keep its early reader until the actual navigation entry has acquired its reader.
pub fn handoff_chat_open(r : ChatRef, reader : TopicLease) -> Unit {
  if !reader.alive() { return }
  let target = @signals.untracked(fn() { app.nav.top() })
  match target {
    Chat(chat) if chat.station == r.station && chat.session == r.session => {
      let (serial, _) = @signals.untracked(fn() { app.nav.top_stay() })
      let key = r.station + "\u{1}" + r.session
      if page_sources.get(serial) is Some(sources) && sources.iter().any(fn(current) {
        current.chat_ready == key && @signals.untracked(fn() { (current.source.topic_alive)() })
      }) {
        reader.release()
        return
      }
      let previous = pending_chat_readers.get(serial)
      let pending : PendingChatReader = { reader, unkeep: None }
      pending_chat_readers[serial] = pending
      match @ui.view_tree() {
        Some(tree) => {
          let root = tree.root()
          if root.alive() {
            pending.unkeep = Some(root.owns_while(fn() {
              match pending_chat_readers.get(serial) {
                Some(current) if physical_equal(current, pending) => pending_chat_readers.remove(serial)
                _ => ()
              }
              stop_pending_chat(pending)
            }))
          } else {
            release_pending_chat(serial)
          }
        }
        None => release_pending_chat(serial)
      }
      match previous { Some(old) => stop_pending_chat(old); None => () }
    }
    _ => reader.release()
  }
}

///|
/// The source for one actual navigation entry. Keep its identity until the entry leaves so its final events can
/// use the same projection that the page read, rather than the surrounding window's source.
pub fn page_entry_source(src : Source, entry : @view.View, serial : Int) -> Source {
  let source = src.owned_by(entry)
  let current : PageSource = { source, page: None, seen: 0, chat_ready: "", chat_view: None, active: true }
  let sources = match page_sources.get(serial) {
    Some(sources) => sources
    None => { let sources : Array[PageSource] = []; page_sources[serial] = sources; sources }
  }
  sources.push(current)
  entry.owns(fn() {
    current.active = false
    match page_sources.get(serial) {
      Some(sources) => {
        // An entry can leave through another navigation path after this view's cleanup. Keep its most recently
        // read ended source for that callback, and at most one such source while the entry stays on the stack.
        let mut latest_ended : PageSource? = None
        for candidate in sources {
          if !candidate.active && (latest_ended is None || candidate.seen > latest_ended.unwrap().seen) {
            latest_ended = Some(candidate)
          }
        }
        let remaining = sources.filter(fn(other) {
          other.active || (latest_ended is Some(last) && physical_equal(other, last))
        })
        page_sources[serial] = remaining
      }
      _ => ()
    }
  }) |> ignore
  source
}

///|
fn page_source_read_page(source : PageSource, page : Page) -> Bool {
  match (source.page, page) {
    (Some(Chat(a)), Chat(b)) => a.station == b.station && a.session == b.session
    (Some(a), b) => a == b
    _ => false
  }
}

///|
fn entry_last_source(serial : Int, page : Page) -> PageSource? {
  let mut chosen : PageSource? = None
  match page_sources.get(serial) {
    Some(sources) => for candidate in sources {
      match chosen {
        None => chosen = Some(candidate)
        Some(previous) => {
          let read = page_source_read_page(candidate, page)
          let previous_read = page_source_read_page(previous, page)
          if (read && !previous_read) || (read == previous_read &&
            ((candidate.active && !previous.active) ||
             (candidate.active == previous.active && candidate.seen > previous.seen))) {
            chosen = Some(candidate)
          }
        }
      }
    }
    None => ()
  }
  match chosen {
    Some(current) if page_source_read_page(current, page) => Some(current)
    _ => None
  }
}

///|
pub fn page_entry_read(serial : Int, source : Source, page : Page) -> Unit {
  match page_sources.get(serial) {
    Some(sources) => for current in sources {
      if !physical_equal(current.source, source) { continue }
      if !page_source_read_page(current, page) { current.chat_view = None }
      page_source_seen.val += 1
      current.seen = page_source_seen.val
      current.page = Some(page)
    }
    None => ()
  }
}

///|
pub fn page_source_for_chat(fallback : Source, r : ChatRef) -> Source {
  let mut latest = -1
  let mut result = fallback
  for _, sources in page_sources {
    for current in sources {
      match current.page {
        Some(Chat(chat)) if current.active && chat.station == r.station && chat.session == r.session && current.seen > latest &&
          @signals.untracked(fn() { (current.source.topic_alive)() }) => {
          latest = current.seen
          result = current.source
        }
        _ => ()
      }
    }
  }
  result
}

///|
// Save the actual projection while its owner is live. Disposing a view can invalidate its derived value before the
// navigation entry's leave callback runs; an ending source must not replace the last live projection with None.
fn page_chat_view_read(source : Source, chat : ChatRef, value : ChatView?) -> Unit {
  if !@signals.untracked(fn() { (source.topic_alive)() }) { return }
  for _, sources in page_sources {
    for current in sources {
      if physical_equal(current.source, source) && page_source_read_page(current, Chat(chat)) {
        current.chat_view = value
      }
    }
  }
}

///|
pub fn left_page_source(fallback : Source, index : Int) -> (Source?, ChatView?) {
  let saved = left_page_sources.get(index)
  left_page_sources.remove(index)
  match saved {
    Some(Some(chat)) => (Some(chat.source), chat.view)
    Some(None) => (None, None)
    None => (Some(fallback), None)
  }
}

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
fn page_entry_left(serial : Int, p : Page) -> Unit {
    let entry = entry_last_source(serial, p)
    let chat : LeftPageChat? = match (p, entry) {
      (Chat(r), Some(current)) => {
        let view = match chat_kept_from(current.source, r) {
          Some(view) => Some(view)
          None => current.chat_view
        }
        Some({ source: current.source, view })
      }
      _ => None
    }
    page_sources.remove(serial)
    release_pending_chat(serial)
    match p {
      Chat(_) => left_page_sources[left_pages.length()] = chat
      _ => ()
    }
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
}

///|
pub fn new_nav() -> @ui.Nav[Page] {
  // what its own back comes to, back's in the history (app_history.mbt went_back); settings' gear is at the right of
  // every top bar, so it comes in from the right like any page
  @ui.Nav::new(Home, went_back~, on_entry_leave=page_entry_left)
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
/// The stack made Home and `pages` over it, in place, as one change (Nav::replace_above): Home kept where it is the
/// root, else put in place of the root.
pub fn nav_over_home(pages : Array[Page]) -> Unit {
  if app.nav.pages()[0] == Home {
    app.nav.replace_above(1, pages)
  } else {
    app.nav.replace_above(0, [Home, ..pages])
  }
}

///|
/// A chat opened over Home from the start (a link, a scripted run).
pub fn open_chat(r : ChatRef) -> Unit {
  open_page(Chat(r))
}

///|
/// Page `p` opened, where the layout has it (Shell's `open`: the pane table): what pages, links
/// and the app's own doings call, never the stack themselves.
pub fn open_page(p : Page) -> Unit {
  if window_front(p) {
    return
  }
  history_act(fn() { (shell.val.open)(p) })
}

///|
/// Page `p` opened from the page in view (a chat's link in a message): over it, back coming to it again, where the
/// layout has it (Shell's `open_over`).
pub fn open_page_over(p : Page) -> Unit {
  if window_front(p) {
    return
  }
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
  // (no page on its way: a frame with no wide page in it says none, the last run's left as it was)
  page_way_said("", 0.0, ends=0.0)
  // where it has been (app_history.mbt)
  history_reset()
  app.picked.set("")
  @ui.set_motion_chosen(None)
  @ui.set_haptics(true)
  felt_reset()
  app.filters.clear()
  app.menu = false
  app.switch_way = 0
  app.held = 0
  app.held_long = false
  // (none said; which saying was last kept: the next a new one, as ever)
  app.toast.set({ ..toast_none, n: @signals.untracked(fn() { app.toast.get().n }) })
  left_pages.clear()
  let pending = pending_chat_readers.values().collect()
  pending_chat_readers.clear()
  for reader in pending { stop_pending_chat(reader) }
  page_sources.clear()
  left_page_sources.clear()
  page_source_seen.val = 0
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
  // how many of each chats' list are asked (rows.mbt)
  chat_limits_reset()
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
  reporting_said.set(None)
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
  windows_open.clear()
}

///|
/// Each hold's press as last felt (`what` held: a message's words picked, a link's menu, a page's bar folded): once a
/// press, whichever of a frame's builds saw it.
let felt_holds : Map[String, Int] = {}

///|
/// Felt as the hold `what` takes the press it is,
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
    Place("vault") => @sf.t("android-settings.vault.title")
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
