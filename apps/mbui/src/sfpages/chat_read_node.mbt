// What a chat's page made as nodes tells the core of what is read and where the chat is, out of one fact: what its list
// has in sight (@view.ListPlace::on_sight), as the old page's list told it (sfbase's chat_list.mbt): the chat shows
// (`client.focus {chat}`) as that changes, where it is (`chat.place`) at rest alone. The chat shows: its end seen (at
// its foot, the window not short of the chat's end) and the last message seen whole, which marks what is read and
// places the unread line; where it is (`chat.place`): the message at the top and how far its top
// is under the list's (in the screen's pixels), none at its end, told as the message at the top changes; as the page goes
// (sfapp's chat_left, chat_read_left), that it shows no more and where it was left. Told while the page is drawn (sfbase's
// chat_page_made's `drawn`, what the old page's view was built by: none of it while another page covers it, what is in
// sight then told as it comes to be drawn again) and the app is shown, never with Source.read_only; the same fields the
// old page tells (sfbase's tell_focus, tell_place), the core unchanged.

///|
/// What a chat's page last told the core, to tell only as it differs: what its list last had in sight and its rows then
/// (to tell where it was left), the last message seen whole (the furthest: read up, what was read stays read), the
/// message at the top and its top under the list's (in points), the screen's scale. Where the core was last told the
/// chat is, the chat's Reading keeps (sfbase's reading_of, told_place and told_at): one account of it with the old
/// page's list, which still draws the chat beside a page over it on the wide frame (a service's, its tab shown).
priv struct ChatRead {
  mut sight : (@view.Sight[String], ChatBodyRows)?
  mut whole : Double
  mut top : (Double, Double)?
  mut scale : Double
  mut told_focus : String
}

///|
/// What each chat open on a page made as nodes was told, by its key (station + "\u{1}" + session): taken as the chat
/// is left (chat_read_left).
let chat_reads : Map[String, ChatRead] = Map([])

///|
/// Chat `r`'s page (in `v`, its view `view` as it changes) telling the core what is read and where it is from what its
/// list `place` has in sight (the file's head), its rows as `rows` has them, while `shows` (it is drawn), where it is
/// at rest (`scroll`, the list's, neither in the hand nor going on by itself); where it is kept and told as a place is (sfbase's
/// kept_place_of), what covers the list's top `cover` tall.
fn chat_read_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView,
  place : @view.ListPlace[String],
  scroll : @view.Scroll,
  rows : () -> ChatBodyRows,
  shows : () -> Bool,
  cover : () -> Double,
) -> Unit {
  let k = r.station + "\u{1}" + r.session
  // (the chat's while it is open: a page made again for it, as another comes over it and goes, goes on from it)
  let a : ChatRead = match chat_reads.get(k) {
    Some(was) => was
    None =>
      ChatRead::{
        sight: None,
        whole: -1.0,
        top: None,
        scale: 1.0,
        told_focus: "",
      }
  }
  chat_reads[k] = a
  // (while the chat is open, none once it is left, and its page is drawn)
  let live = fn() { chat_reads.get(k) is Some(now) && physical_equal(now, a) && @signals.untracked(shows) }
  // what is in sight taken as it changes, the hand on it or not, as the old page's list read it each frame (sfbase's
  // read_place): where it is (where it was left, to the pixel, as it is left there: chat_read_left) and the last
  // message seen whole
  let taken = fn(s : @view.Sight[String]) {
    let rs = @signals.untracked(rows)
    let cv = @signals.untracked(view)
    a.sight = Some((s, rs))
    a.scale = @signals.untracked(fn() { v.pixel_scale() })
    // the message at the top, its top under the list's: where the first in sight is one (else as it was)
    match rs.rows.get(s.first).map(fn(row) { row.entry }) {
      Some(Said(m)) => a.top = Some((m.seq, @sfbase.kept_place_of(-s.into, @signals.untracked(cover))))
      _ => ()
    }
    // the last message seen whole: the message the last key wholly in sight is, or the last before it
    match s.whole {
      Some(w) if !cv.newer => {
        let mut i = rs.keys.length() - 1
        while i >= 0 && rs.keys[i] != w {
          i = i - 1
        }
        while i >= 0 {
          match rs.rows.get(rs.keys[i]).map(fn(row) { row.entry }) {
            Some(Said(m)) => {
              if m.seq > a.whole {
                a.whole = m.seq
              }
              break
            }
            _ => i = i - 1
          }
        }
      }
      _ => ()
    }
  }
  // told once the frame (or the change between frames) that took it is over, as the old page told it once its
  // frame's builds were over (sfbase's after_build_or_scroll): what is in sight then, the last of what its passes
  // told (a moment's layout tells it again as the rows it brought in are measured, each nearer what is so). That it
  // shows, its end seen or not and the last message seen whole, as either changes (sfbase's tell_focus, the old page
  // telling it moving or not); where it is only where it was owed at rest (`placing`, settle's)
  let telling = Ref(false)
  let placing = Ref(false)
  let tell = fn() {
    guard !telling.val else { return }
    telling.val = true
    @ui.after_frame(fn() {
      telling.val = false
      guard live() && app_in_front() && a.sight is Some((s, _)) else {
        placing.val = false
        return
      }
      let cv = @signals.untracked(view)
      chat_read_focus(src, r, cv, a, !cv.newer && s.at_foot)
      if placing.val && !@signals.untracked(fn() { scroll.in_hand() }) {
        placing.val = false
        chat_read_place(src, r, cv, a, exact=false)
      }
    })
  }
  // where it is (`chat.place`) told at rest alone, as the old page told it only while its list was not moving (ui's
  // Ctx::list_moving: held, flung, easing): never while the hand holds the list (each move of a finger is an input the
  // list tells what is in sight at), nor while it goes on by itself after (a fling's glide, a notch of the wheel easing
  // in: Scroll::glides_till), but once as the hand lets go with nothing to go on by, or as that ends; a pixel wheel's
  // stroke, which eases not, leaves it at rest at once, told then, as the old page did
  let owed = Ref(false)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  fn settle() -> Unit {
    guard owed.val else { return }
    guard live() else {
      owed.val = false
      return
    }
    guard !@signals.untracked(fn() { scroll.in_hand() }) else { return }
    (due.val)()
    due.val = fn() {  }
    match scroll.glides_till() {
      Some(end) if end > v.cause_at() => due.val = v.at_moment(end, settle)
      _ => {
        owed.val = false
        placing.val = true
        tell()
      }
    }
  }
  let seen = fn(s : @view.Sight[String]) {
    guard live() else { return }
    taken(s)
    owed.val = true
    tell()
    settle()
  }
  place.on_sight(seen)
  v.reacts(fn() { scroll.in_hand() }, fn(held) { if !held { settle() } }, at_start=false)
  // (told only as what is in sight differs: as it comes to be drawn again, what is in sight then)
  v.reacts(shows, fn(on) { if on && place.sight_now() is Some(s) { seen(s) } }, at_start=false)
}

///|
/// The list ⌘F goes along where chat `r`'s page is made as nodes (find.mbt's FindList): the messages showing out of
/// what its list last had in sight as it was told the core (the first message in sight and the last; none where it was
/// told none), the list to a message as any go-to inside the chat is (sfbase's go_to: chat_goes_to brings it just under
/// the list's room; the words found are bold in every row while the bar is open in it, find_words_in, so a go-to's own
/// words are not kept for it), nothing left to go to as it is let go.
fn chat_nodes_find_list(r : ChatRef) -> FindList {
  let k = r.station + "\u{1}" + r.session
  {
    showing: fn() {
      guard chat_reads.get(k) is Some(a) && a.sight is Some((s, rs)) else { return (-1.0, -1.0) }
      let seq = fn(key : String) {
        match rs.rows.get(key).map(fn(row) { row.entry }) {
          Some(Said(m)) => Some(m.seq)
          _ => None
        }
      }
      let (from, to) = match (rs.keys.search(s.first), rs.keys.search(s.last)) {
        (Some(a), Some(b)) => (a, b)
        _ => return (-1.0, -1.0)
      }
      let mut first = -1.0
      for i = from; i <= to; i = i + 1 {
        if seq(rs.keys[i]) is Some(q) {
          first = q
          break
        }
      }
      let mut last = -1.0
      for i = to; i >= from; i = i - 1 {
        if seq(rs.keys[i]) is Some(q) {
          last = q
          break
        }
      }
      (first, last)
    },
    go: fn(seq, _) { @sfbase.go_to(r, seq, keep_place=false) },
    forget: fn() { @sfbase.go_tos.remove(k) },
  }
}

///|
/// The core told chat `r` (view `v`) shows, its end seen or not, and the last message seen whole, as either changes.
fn chat_read_focus(src : Source, r : ChatRef, v : ChatView, a : ChatRead, end : Bool) -> Unit {
  let said = "\{end} \{a.whole}"
  guard !src.read_only && a.told_focus != said else { return }
  a.told_focus = said
  let chat = @sfbase.focus_chat(r, v, Some(end))
  if a.whole >= 0.0 {
    match chat {
      Object(o) => o["seen"] = Json::number(a.whole)
      _ => ()
    }
  }
  (src.call)("client.focus", { "chat": chat }, @sfbase.answer_unread)
}

///|
/// The core told where chat `r` (view `v`) is (`chat.place`): the message at the top and its top under the list's in the
/// screen's pixels, none at its end; told again as the message at the top changes, and to the pixel as it is left
/// (`exact`). Kept for opening it again this run (sfbase's kept_places).
fn chat_read_place(src : Source, r : ChatRef, v : ChatView, a : ChatRead, exact~ : Bool) -> Unit {
  guard a.sight is Some((s, _)) else { return }
  let end = !v.newer && s.at_foot
  match a.top {
    Some((seq, off)) =>
      @sfbase.kept_places[r.station + "\u{1}" + r.session] = {
        top: seq,
        offset: off,
        bottom: match (end, v.messages.last()) {
          (true, Some(m)) => m.seq
          _ => -1.0
        },
      }
    None => ()
  }
  guard v.thread is Some(th) && !src.read_only else { return }
  let place : Map[String, Json] = { "station": Json::string(r.station), "thread": Json::number(th) }
  let mut at = ""
  match a.top {
    Some((seq, off)) if !end => {
      place["seq"] = Json::number(seq)
      place["offset"] = Json::number((off * a.scale).round())
      at = Json::number(seq).stringify()
    }
    _ => ()
  }
  let said = Json::object(place).stringify()
  let rd = @sfbase.reading_of(r.station + "\u{1}" + r.session)
  if said == rd.told_place || (!exact && at == rd.told_at) {
    return
  }
  rd.told_place = said
  rd.told_at = at
  (src.call)("chat.place", Json::object(place), @sfbase.answer_unread)
}

///|
/// Chat `r`'s page made as nodes gone (sfapp's chat_left, as the page goes), its view `v` as it was left: the core told
/// it shows no more, and where it was left, to the pixel (once its list was laid out). False where no such page was the
/// chat's (the old page's, which tells it itself).
pub fn chat_read_left(src : Source, r : ChatRef, v : ChatView?) -> Bool {
  let k = r.station + "\u{1}" + r.session
  guard chat_reads.get(k) is Some(a) else { return false }
  chat_reads.remove(k)
  match v {
    Some(view) if !src.read_only => {
      (src.call)("client.focus", { "left": @sfbase.focus_chat(r, view, None) }, @sfbase.answer_unread)
      chat_read_place(src, r, view, a, exact=true)
    }
    _ => ()
  }
  true
}
