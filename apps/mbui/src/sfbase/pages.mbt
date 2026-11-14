// The app's pages, as a stack both frames show (the phone's pages pushed and swiped back; the wide frame's pane beside
// the rail): what a page is, the stack and what the app keeps of it; a chat, a drive's place and a station's screen as
// a page names them.

///|
/// A page of the stack.
#derive(Eq)
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
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
  /// a page under settings (src/sfapp/settings: me, appearance, stations, the workspace…)
  Setting(@settings.Route)
  /// a station's screen, seen and driven (screen_view.mbt), over the app as Android's ScreenActivity is
  Screen(ScreenAt)
}

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
/// Whether a chat's page is made with its inside nodes (chat_page_made's `body` and `foot`): a bridge while the page
/// is moved off its old view, deleted at the switch-over; off, the page is as it was. Read as a page is made.
// kept across runs: chat_page_nodes_at_start as a run begins (reset)
pub let chat_page_nodes : @signals.Signal[Bool] = @signals.signal(chat_page_nodes_at_start, same=fn(a, b) { a == b })

///|
/// What chat_page_nodes is as a run begins.
// kept across runs: a value
let chat_page_nodes_at_start : Bool = false

///|
/// How a chat's column is laid out as the shell has it at a node's moment (chat_page_made's `narrower`): how much narrower
/// than it is drawn (`by`), how far across it is moved (`across`), and the width it is laid out at (`laid`: where that
/// steps, all it holds is laid out anew at once, View::lays_anew). None at rest but the width.
pub(all) struct ColumnLaid {
  by : Double
  across : Double
  laid : Double
}

///|
/// A chat's page made once in node `v` of a stack's (entry `serial`'s: nav_view's and nav_flat_view's `made`), and the
/// new chat that becomes it in place, the same page: what it holds its old view as yet, its island (Nav::page_island),
/// built by `build` as the stack built it before (a chat from the source it keeps while its entry is on the stack, its
/// reader held: page_entry_source, page_chat_reader; a new chat from the node's own), again as `key` changes. Over it
/// a picture flying from its list while under its bar (viewer_flight_slot), and over that what of it is nodes already (`over`: given a node over the island, the chat's source, what the page is now and its
/// time on top, `stint`; made while `drawn` says its entry is drawn: shown, or kept shown in place while the one on top
/// waits, as its island is). What it reads by, the source it keeps (its reads the page's, let go with it), given back:
/// what is beside it reads by it too. With chat_page_nodes on as the page is made, its inside as what the page is,
/// one in the other's place at once as it changes: a new chat its old view (what that reads let go as it goes); a chat,
/// one made so or a new chat become it in place (Nav::become), its inside nodes, chat `r`'s messages made by `body` in
/// a column, given what makes its composer (by `foot`, its old view in a node of its own, as tall as it is laid out) in
/// the node it is put in, the foot of the messages' list, and whether its entry is drawn (as `drawn` says). On the
/// page's way to another width (a side panel sliding in or out beside it), its column laid out as at the narrower of
/// where the way set off and where it goes, from the frame it sets off till the one it is there, so that its rows are
/// laid out anew only at those two (as the old list's laid_w had it held), and moved across by as much as its rows'
/// words start further in at the width it is drawn at than at the one it is laid out at, so that they go across with
/// the page, never stepping where it is laid out anew: both the shell's to say, at a node's moment (`narrower`: how much
/// narrower, how far across; none at rest). Its composer, in the list's foot, an old view as yet, is laid out at the
/// width the column is drawn at all the way, and goes its way to another as with_side has it, by itself.
pub fn chat_page_made(
  v : @view.View,
  src : Source,
  serial : Int,
  build : (@ui.Ctx, Source, Page) -> Unit,
  key? : () -> String = fn() { "" },
  over? : (@view.View, Source, () -> Page?, () -> Int) -> Unit,
  stint? : () -> Int = fn() { 0 },
  drawn? : (Int) -> Bool = fn(serial) { app.nav.shows(serial) },
  body? : (@view.View, Source, ChatRef, (@view.View) -> Unit, () -> Bool) -> Unit,
  foot? : (@ui.Ctx, Source, ChatRef) -> Unit,
  narrower? : (@view.View) -> ColumnLaid,
) -> Source {
  let retained = page_entry_source(src, v, serial)
  let page_read = page_chat_reader(retained, v, serial)
  let shown = src.owned_by(v)
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (with chat_page_nodes on as the page is made, a chat's made as nodes inside, as what the page is: a new chat its old
  // view, a chat once it has become one in place, Nav::become, its nodes, at once, the one in the other's place)
  let nodes = match (body, foot) {
    (Some(b), Some(f)) if @signals.untracked(fn() { chat_page_nodes.get() }) => Some((b, f))
    _ => None
  }
  match nodes {
    Some((b, f)) => {
      // (which chat the page is, by its station and session, "" while a new chat; as it was once its entry is gone)
      let was = Ref("")
      v.pick(
        fn() {
          match app.nav.page_of(serial) {
            Some((Chat(r), _)) => was.val = r.station + "\u{1}" + r.session
            Some(_) => was.val = ""
            None => ()
          }
          was.val
        },
        fn(col, chat) {
          col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          let made = if chat == "" { None } else { @signals.untracked(fn() { app.nav.page_of(serial) }) }
          match made {
            Some((Chat(r), _)) => {
              // a column: the chat's messages growing to all of it, the composer in their list's foot at its own
              // height, its old view in a node of its own as yet (built as the stack's island is, what the page reads
              // read there)
              col.ground(By(fn() { @sf.theme().p.bg })) |> ignore
              // (on the page's way to another width, laid out as at the narrower end the whole way, at its left, and
              // moved across as its rows' words would be: the shell's to say, `narrower`, read as it is drawn; none at
              // rest)
              match narrower {
                Some(by) =>
                  col
                  .padding(By(fn() { (0.0, 0.0, by(col).by, 0.0) }))
                  .offset(By(fn() { (by(col).across, 0.0) }))
                  .lays_anew(By(fn() { by(col).laid }))
                  |> ignore
                None => ()
              }
              // (coming to need the viewer while open, felt, as its old view felt it)
              feel_needed_node(col, retained, r)
              b(col, retained, r, fn(n) {
                // (its height going the way the composer's ground sets out on for what it holds, from that cause's
                // moment and by its spec, so the room under the last row goes with that ground, one motion:
                // composer_set_out, foot_resizes)
                let island : Ref[@view.View?] = Ref(None)
                island.val = app.nav.page_island(
                  n,
                  serial,
                  fn(c, page) {
                    page_entry_read(serial, retained, page)
                    page_read(page)
                    f(c, retained, r)
                  },
                  key~,
                  natural=true,
                  // (cut to itself, its ground its shape all the way: laid out at its one line as words are sent from
                  // it, its ground going down to that on its own way drawn whole over its node's top, not cut flat)
                  over=true,
                  reshaped=fn(_was) { foot_resizes(island.val, r) },
                )
                // (in the list's foot, nothing to the hand but what it holds that takes it: the room round the
                // composer's capsule, over it and the bar's under it, the page's, as a press or what is let go there
                // from outside)
                |> @ui.old_takes_own
                |> Some
                // (the composer as wide as the column is drawn, where it is drawn, whatever the column is laid out
                // at: its own way to another width with_side's)
                match narrower {
                  Some(by) =>
                    n
                    .margin(By(fn() { (0.0, 0.0, -by(n).by, 0.0) }))
                    .offset(By(fn() { (-by(n).across, 0.0) }))
                    |> ignore
                  None => ()
                }
              }, fn() { drawn(serial) })
            }
            _ => {
              // (a new chat: its old view, what it reads let go with this node as the page becomes its chat)
              let here = src.owned_by(col)
              app.nav.page_island(
                col,
                serial,
                fn(c, page) {
                  page_entry_read(serial, retained, page)
                  page_read(page)
                  build(c, if page is Chat(_) { retained } else { here }, page)
                },
                key~,
              )
              .grow(Is(1.0))
              |> ignore
            }
          }
        },
        at_once=true,
      )
    }
    None =>
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
  // (a picture flying from its list drawn here while under its bar, the bar over it: viewer_flight_slot)
  v.box(fn(slot) { viewer_flight_slot(slot, retained, serial, fn() { slot.window() }) }) |> ignore
  match over {
    Some(f) =>
      // (while the page shows, as its old view is built: what it reads let go of while another covers it)
      v.show(fn() { drawn(serial) }, fn(o) {
        o.over(Is(true)) |> ignore
        f(o, retained, fn() { app.nav.page_of(serial).map(fn(e) { e.0 }) }, stint)
      })
    None => ()
  }
  retained
}

///|
/// The way a chat's composer's ground last set out on for what it holds (a line more, a file, a quote; sfpages'
/// composer reshape, its `by` changed): its draft, the moment its build said it, and where that way is declared (when
/// it set out, how long, and how far on it the ground is drawn at a moment: @motion.reshape_way, reshape_share, read
/// once the frame that set it off is laid out). Said by the composer's build at that cause, none for words sent from
/// it (their row carries its room) nor once a later build sets out on none; taken by the one height change of its node
/// in a list's foot it comes out as (foot_resizes).
// kept across runs: said again by each composer's build, taken once
pub let composer_set_out : Ref[(String, Double, () -> (Double, Double, (Double) -> Double)?)?] = Ref(None)

///|
/// The old view `island` holding chat `r`'s composer in its list's foot come to another height: where its composer's
/// ground set out on a way for that (composer_set_out), its height goes that very way (View::resizes, kept to its foot:
/// the composer grows from it): from when the ground set out, as long as its way is declared, at each moment as far on
/// as the ground is drawn then (its own way read, not one worked out beside it), so the room under the last row and
/// what stands on the foot go with the ground in the same frames, one way, as the old list's foot went with it
/// (sfpages' composer_way_for_list). Otherwise at once.
fn foot_resizes(island : @view.View?, r : ChatRef) -> Unit {
  guard composer_set_out.val is Some((draft, _, declared)) &&
    draft == r.station + ":" + r.session &&
    island is Some(v) else {
    return
  }
  composer_set_out.val = None
  guard declared() is Some((start, dur, ground)) && dur > 0.0 else {
    v.resizes(foot=true) |> ignore
    return
  }
  // (told after it set out: the rest of its way, from where it has got to)
  let since = @ui.tree_cause().unwrap_or(start) - start
  let gone = if since > 0.0 { since } else { 0.0 }
  let left = dur - gone
  guard left > 0.0 else { return }
  let p0 = ground(start + gone)
  v.resizes(
    spec=(left, fn(f) {
      if p0 >= 1.0 {
        1.0
      } else {
        (ground(start + gone + f * left) - p0) / (1.0 - p0)
      }
    }),
    foot=true,
  )
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
let page_sources : Map[Int, Array[PageSource]] = Map([])

///|
priv struct LeftPageChat {
  source : Source
  view : ChatView?
}

///|
// An explicitly absent entry means a navigation entry left before it had a page source. A missing map entry is an
// older caller that placed a page directly in left_pages and still uses the surrounding source.
let left_page_sources : Map[Int, LeftPageChat?] = Map([])

///|
let page_source_seen : Ref[Int] = Ref(0)

///|
priv struct PendingChatReader {
  reader : TopicLease
  mut unkeep : (() -> Unit)?
}

///|
let pending_chat_readers : Map[Int, PendingChatReader] = Map([])

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
/// The readers a page handed over as it opened another in its place (open_handing), by the entry opened's serial:
/// each the entry's as its view is made (page_entry_source), let go once its first build has read what it reads
/// (page_entry_read).
let handed_readers : Map[Int, Array[TopicLease]] = Map([])

///|
/// `open` run (a page opening the next in its place: a folder the folder it goes into), with this page's reader of
/// topic `name` handed over to the entry it opened: kept past this page as it leaves (as a row's early reader is,
/// prepare_chat_handoff), taken by that entry as its view is made and let go as its first build ends. So a next page
/// that reads it as it is first built reads the subscription this one read, never one made again after this one let
/// it go (a press opens the next at once, outside any build: the old entry leaves before the new one is built); one
/// that does not read it then lets it go then, as it would have been had the open come in a build. Only a topic this
/// page holds is handed over: one nothing reads is not asked for here (a lease of it would be a subscription of its
/// own).
pub fn open_handing(src : Source, name : String, params : Map[String, Json], open : () -> Unit) -> Unit {
  if !topic_held(name, params) {
    open()
    return
  }
  hand_over([src.lease_topic(name, params)], open)
}

///|
/// `open` run (a place of a sidebar's opening its page in place of the one shown: a favorite folder, a station),
/// with every topic held now handed over to the entry it opened as open_handing hands one: the page it opens reads, as
/// it is first built, what the page it leaves read, never one asked for again after that one let it go (opened in a
/// build, the page left was let go only once the one opened was built in the same frame); what it does not read then
/// is let go as its first build ends. Not what a place of the page left browses (its topic said by that `place`,
/// browse_where): that place goes with it, and kept past it, it would be asked again for what the opening changes
/// (the tabs it keeps), the page opened browsing its own.
pub fn open_handing_held(open : () -> Unit) -> Unit {
  let held = topics_held().filter(fn(t) { !t.2.contains("place") })
  hand_over(held.map(fn(t) { t.0.lease_topic(t.1, t.2) }), open)
}

///|
/// `open` run, `leases` handed to the entry it put on top (open_handing): kept past the page that leaves, taken by
/// that entry as its view is made; let go at once where nothing was put on top.
fn hand_over(leases : Array[TopicLease], open : () -> Unit) -> Unit {
  let readers : Array[TopicLease] = []
  for lease in leases {
    match prepare_chat_handoff(lease) {
      Some(reader) => readers.push(reader)
      None => ()
    }
  }
  let (before, _) = @signals.untracked(fn() { app.nav.top_stay() })
  open()
  let (serial, _) = @signals.untracked(fn() { app.nav.top_stay() })
  // (nothing opened in its place: no one to hand them to)
  if serial == before {
    for reader in readers {
      reader.release()
    }
    return
  }
  match handed_readers.get(serial) {
    Some(had) => had.append(readers)
    None => handed_readers[serial] = readers
  }
}

///|
/// The readers a press handed over to a page it shows in a pane in place of the one there, no entry of the stack put on
/// top (a place's side list's pick: hand_over_shown), by what that page is shown for (`at`): taken as that page is
/// first built (shown_read), let go at that frame's end, as an entry's are (page_entry_read).
let handed_shown : Map[String, Array[TopicLease]] = Map([])

///|
/// `open` run (a press showing a page in a pane in place of the one there: a place's side list's row), `leases` handed
/// to the page it shows, `at` what that page is shown for (shown_read's): kept past the page that leaves, let go at the
/// end of the frame the page shown is first built in. What was handed for the same page and not taken yet is let go
/// first (shown again before it was built).
pub fn hand_over_shown(at : String, leases : Array[TopicLease], open : () -> Unit) -> Unit {
  let readers : Array[TopicLease] = []
  for lease in leases {
    match prepare_chat_handoff(lease) {
      Some(reader) => readers.push(reader)
      None => ()
    }
  }
  match handed_shown.get(at) {
    Some(had) => for reader in had { reader.release() }
    None => ()
  }
  handed_shown[at] = readers
  open()
}

///|
/// The page shown for `at` (hand_over_shown's) first built, or a reader of a page switched in place having read anew
/// (switch_answered's): what was handed to it let go once this build has read what it reads, at its frame's end; what
/// it read is its own reader's by then.
pub fn shown_read(at : String) -> Unit {
  match handed_shown.get(at) {
    Some(readers) => {
      handed_shown.remove(at)
      @ui.after_frame(fn() { for reader in readers { reader.release() } })
    }
    None => ()
  }
}

///|
/// What a profile's page is shown for (hand_over_shown, shown_read): its station and profile.
pub fn profile_shown_at(station : String, id : String) -> String {
  "profile\u{1}" + station + "\u{1}" + id
}

///|
/// The source for one actual navigation entry. Keep its identity until the entry leaves so its final events can
/// use the same projection that the page read, rather than the surrounding window's source. What the page before it
/// handed over as it opened it (open_handing) is the entry's from here, till its first build (page_entry_read).
pub fn page_entry_source(src : Source, entry : @view.View, serial : Int) -> Source {
  match handed_readers.get(serial) {
    Some(readers) => for reader in readers { reader.bind_to(entry) }
    None => ()
  }
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
  // (what the page before handed over, open_handing: let go once this build has read what it reads, at its frame's
  // end; what it read is its own reader's by then)
  match handed_readers.get(serial) {
    Some(readers) => {
      handed_readers.remove(serial)
      @ui.after_frame(fn() { for reader in readers { reader.release() } })
    }
    None => ()
  }
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
#derive(Eq)
pub(all) struct ScreenAt {
  station : String
  screen : String
  title : String
  until_gone : Bool
}

///|
/// What page `p` is, by its kind alone: a name out of a fixed set written here, never a chat's, station's, session's,
/// file's, job's or person's id, name, title or path, nor anything typed. What the window thread's hang reports sent
/// to PostHog say of the page shown (shown_kind, mbui's journal_shows) and the device's performance record says too.
/// Each is a constructor's literal; a place, data, only as one of `bar_places` (else `other`); a page of the settings
/// as its route's constructor alone (setting_kind). sfapp's shown_wbtest holds every name a screen comes to.
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
    NewChat => "NewChat"
    Place(place) => "Place " + place_kind(place)
    Setting(r) => "Setting " + setting_kind(r)
    Screen(_) => "Screen"
  }
}

///|
/// A place of the bar's by its name, as a literal of the places a bar can hold (bars.mbt's bar_places); any other
/// `other`: what comes in a string is never said as it came.
fn place_kind(place : String) -> String {
  match place {
    "chats" => "chats"
    "files" => "files"
    "stations" => "stations"
    "profiles" => "profiles"
    "connects" => "connects"
    "usage" => "usage"
    "archive" => "archive"
    "vault" => "vault"
    _ => "other"
  }
}

///|
/// A page of the settings by its route's constructor alone: no station's address, id or key it carries.
fn setting_kind(r : @settings.Route) -> String {
  match r {
    Home => "Home"
    Me => "Me"
    Appearance => "Appearance"
    Fonts => "Fonts"
    Workspace => "Workspace"
    Security => "Security"
    SecurityOpen => "SecurityOpen"
    Vault => "Vault"
    Stations => "Stations"
    Station(_) => "Station"
    Profiles(_) => "Profiles"
    Profile(_, _) => "Profile"
    Connects(_) => "Connects"
    Connect(_, _) => "Connect"
    Memories => "Memories"
    Memory(_) => "Memory"
    MemoryDoc(_, _, _) => "MemoryDoc"
    Usage => "Usage"
    Archive => "Archive"
    AdbShare(_) => "AdbShare"
    NewProfile(_) => "NewProfile"
    ProfileAccount(_) => "ProfileAccount"
    VaultItems => "VaultItems"
    VaultItem(_, _) => "VaultItem"
    AutoDecisions => "AutoDecisions"
    AutoCompletion => "AutoCompletion"
    AutoPolicy(_) => "AutoPolicy"
    BarSettings => "BarSettings"
    KeptFiles => "KeptFiles"
    KeptChat(_, _) => "KeptChat"
    Changelog => "Changelog"
    About => "About"
    Shortcuts => "Shortcuts"
    LocalStation => "LocalStation"
    Notifications => "Notifications"
    Permissions => "Permissions"
    Archiving => "Archiving"
    StationArchiving(_) => "StationArchiving"
    UsagePrices(_) => "UsagePrices"
    RunSettings(_, _) => "RunSettings"
  }
}

///|
/// What the app shows as a whole (sfapp's shown_now says which): before it can show a workspace (the splash, the
/// accounts or workspaces still read or failing), the way in signed out, the landing with no workspace, a share sheet
/// over another app, or a page (the stack's top, the page the pane lands on on 中屏 and 大屏; a window of its own's).
#derive(Eq)
pub(all) enum Shown {
  Starting
  SignIn
  Landing
  Share
  Shows(Page)
}

///|
/// What the app shows by its kind alone (page_kind's for a page): what it tells the window thread's journal as that
/// changes (mbui's journal_shows), which its hang reports and the device's performance record say.
pub fn shown_kind(s : Shown) -> String {
  match s {
    Starting => "Starting"
    SignIn => "Sign in"
    Landing => "Landing"
    Share => "Share"
    Shows(p) => page_kind(p)
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
/// The page last left (left_pages), by its entry's serial (unique across every Nav, never one again): what tells where
/// it was left (the frame's pages-left) built again as another is left.
// kept across runs: a serial is never given twice (nav.mbt), so the last left of a run before is no page of this one
pub let left_said : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

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
    left_said.set(serial)
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
/// The stack's root made `page`'s, the one there put on its shelf and `page`'s entry taken back from it where it is
/// there (Nav::replace_kept: where what holds the stack keeps pages so, the narrow shell; else as Nav::replace): what a
/// place of the bar switched to is on 小屏, from the bar, back or the history. A place taken back is as it was left, its
/// scroll and 连接's 我的 too (the owner, 2026-11-12: 「三样都记得」); one put on the shelf has not left the stack yet, so
/// nothing is let go of it here (@settings.left is page_entry_left's, as its entry leaves for good).
pub fn nav_root_kept(page : Page) -> Unit {
  app.nav.replace_kept(page)
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
/// What page `p` reads of the core as it is first built, each asked of `ask`, in the order its build asks them: a
/// chat its view, its draft, its workspace's stations (the names it shows its agents by) and its jobs' summary. A
/// page not said here asks as its build runs. Only what it reads on every screen, at once: what its build reads
/// later or on one screen alone is its build's (sfapp's declared_read_wbtest holds each said here read at rest, and
/// the frame that builds it asking nothing more).
///
/// A bridge while pages are built by the old view, as opens_ahead_node's is (apps/mbui/AGENTS.md): only for a page the
/// old view builds whose first screen reads the core (the chat's, so far; another added only with the coordinator of
/// the migration, 2026-11-12), not a table every page is put in. A page made as nodes says what it reads where it is
/// made, and goes from here then.
pub fn page_opens(p : Page, ask : (String, Map[String, Json]) -> Unit) -> Unit {
  match p {
    Chat(r) => {
      ask("chat", chat_params(r))
      ask("composer", { "key": Json::string(r.station + ":" + r.session) })
      ask("stations", stations_asked(workspace_of(r.station)))
      ask("chatJobs", chat_jobs_summary_params(r))
    }
    _ => ()
  }
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
#derive(Eq)
pub(all) struct ChatRef {
  station : String
  session : String
  title : String
  station_name : String
}

///|
/// Where a page of a drive is: a station, one of its roots (None: the drive itself, its roots), a path under it.
#derive(Eq)
pub(all) struct DriveAt {
  station : String
  root : String?
  path : String
}

///|
/// As at the start: Home alone on the stack, nothing chosen here yet, nothing said, no page left (the app's reset; a
/// toast's count goes on, as before it was here).
pub fn reset() -> Unit {
  app.nav = new_nav()
  // (the core given no mermaid: a run's core is a new one)
  mermaid_begin()
  // (no page on its way: a frame with no wide page in it says none, the last run's left as it was)
  page_way_said("", 0.0, ends=0.0)
  // where it has been (app_history.mbt)
  history_reset()
  last_reset()
  ahead_reset()
  switch_reset()
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
  let shown = handed_shown.values().collect()
  handed_shown.clear()
  for readers in shown {
    for reader in readers {
      reader.release()
    }
  }
  let handed = handed_readers.values().collect()
  handed_readers.clear()
  for readers in handed {
    for reader in readers {
      reader.release()
    }
  }
  page_sources.clear()
  left_page_sources.clear()
  page_source_seen.val = 0
  // the topics read for what has not ended yet (held.mbt)
  held_reset()
  felt_holds.clear()
  nav_tapped.set([])
  // the drive's files going up and being fetched (drive_upload.mbt, drive_keep.mbt)
  ups_reset()
  dv_fetches.clear()
  dv_orders_reset()
  keepings.clear()
  // what was worked out of the core's topics (derived.mbt)
  kept_reset()
  // how many rows each chats' list was told to grow to, the window's height they are worked out of (rows.mbt)
  chat_windows_reset()
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
  // what the core said of the composers' fields, their marks and `@` words (refs.mbt)
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
  // and where each chat's reader was as a go-to took its list away (jump.mbt)
  places_back.clear()
  go_back_offsets.clear()
  places_back_said.set(0)
  // when the flash of a message gone to on a page made as nodes is over (chat_list.mbt)
  flash_rest_nodes.val = -1.0
  // a new chat while it is made (fresh.mbt)
  fresh_reset()
  // how times are said (message_words.mbt)
  absolute_times.set(false)
  // whether a chat's page is made as nodes inside (chat_page_nodes)
  chat_page_nodes.set(chat_page_nodes_at_start)
  // a chat's list's turns and its messages out of avatars (list_turns.mbt, emit.mbt)
  turns_by.clear()
  emits.clear()
  // words sent flying (flight.mbt)
  flights_reset()
  // the chats' lists as kept while they show and where they were left (chat_list.mbt)
  readings.clear()
  kept_places.clear()
  flash_held.val = false
  at_end_env.val = -1
  // what the settings' core keeps (settings_core.mbt, notices.mbt, faces.mbt, bars.mbt)
  reporting_host.set(None)
  reporting_said.set(None)
  core_sends.set(false)
  notices_reset()
  faces_reset()
  bars_picked.set(None)
  // what the app does whichever frame draws it (app_frame.mbt, open_links.mbt, menu_bar.mbt, shell.mbt)
  app_frame_reset()
  links_reset()
  menu_bar_given.val = ""
  shell.val = bare_shell()
  beside_room_now.set(false)
  // the page shown alone in a window of its own (window.mbt)
  lone_page.val = None
  windows_open.clear()
}

///|
/// Each hold's press as last felt (`what` held: a message's words picked, a link's menu, a page's bar folded): once a
/// press, whichever of a frame's builds saw it.
let felt_holds : Map[String, Int] = Map([])

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
