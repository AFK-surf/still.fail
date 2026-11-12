// A chat's whole row (the core's `chatRow {station, session}`, ChatItem): what a row of the list (the core's ListedChat)
// is made without, read only as the row is pressed, held, swiped or pointed at, and by the chat's page's "…": its
// menu's (固定, 保留, 静音, 分享…, its links in Slack and Feishu), its swipe's question, its time in words. It is asked
// as the gesture begins (a pointer down on the row, the pointer coming to rest over it, a swipe setting out: ask_whole),
// so that what it opens finds it answered, held while that is open and let go after; where it is not answered yet, what
// opens waits for it and opens whole the frame it is (whole_answered), never on the list's row and then filled. The
// chat's page holds its own while it is open (chat_whole_held).

///|
/// What a chat's whole row is asked by: its station, its agent's session.
pub fn whole_params(station : String, session : String) -> Map[String, Json] {
  { "station": Json::string(station), "session": Json::string(session) }
}

///|
/// The whole row of list row `item` as `s` says it: None while not answered; the core's row, with what the list says
/// of its station's state on the list's row (offline, updating, reconnecting, whether a swipe takes it: station_on's);
/// the list's row itself where the core has no such chat or could not say (what the list has is all there is).
pub fn whole_of_state(item : ChatItem, s : TopicState) -> ChatItem? {
  match (s.value, s.error) {
    (Some(Object(_) as v), _) => {
      let w = chat_item(v)
      Some({
        ..w,
        offline: item.offline,
        updating: item.updating,
        reconnecting: item.reconnecting,
        swipe_archive: item.swipe_archive,
        swipe_ask: if item.swipe_archive { w.swipe_ask } else { None },
      })
    }
    (Some(_), _) | (_, Some(_)) => Some(item)
    _ => None
  }
}

///|
/// Whether `item` says what its whole row would itself, so nothing waits for `chatRow`: decided by what the app can know
/// of it. A row of the core's `chats` list (ListedChat) never says its time in words, and every ChatItem the core sends
/// whole does (`time`: a search's, the `@` menu's, share-in's), as a made-up sample does: one saying its time (`ago`)
/// is whole already, its menu's fields and its swipe's question with it. And a source that asks nothing (read only: a
/// sample's, drawn in bones or for a part's own test) has no whole row to wait for: what its item says is all there is.
/// Only a list's lean row over a source that asks waits for its chat's whole row.
pub fn whole_already(src : Source, item : ChatItem) -> Bool {
  src.read_only || item.ago != ""
}

///|
/// The whole row of list row `item` as the core says it now, read where it is read (a binding: held while it reads it):
/// None while not answered; `item` itself where it is whole already (whole_already).
pub fn whole_row(src : Source, item : ChatItem) -> ChatItem? {
  if whole_already(src, item) {
    return Some(item)
  }
  whole_of_state(item, src.topic("chatRow", whole_params(item.station, item.session)).get())
}

///|
/// Whether the whole row of `item` is answered (whole_row's, read where it is read).
pub fn whole_answered(src : Source, item : ChatItem) -> Bool {
  whole_row(src, item) is Some(_)
}

///|
/// The whole row of list row `item` asked of the core ahead of what reads it (a gesture beginning), held by what it
/// gives till that lets it go (TopicLease::cancel); None where nothing need be asked (whole_already).
pub fn ask_whole(src : Source, item : ChatItem) -> TopicLease? {
  if whole_already(src, item) || item.pending || item.session == "" {
    return None
  }
  Some(src.lease_topic("chatRow", whole_params(item.station, item.session)))
}

///|
/// What a row's view holds of its chat's whole row: asked once for the chat it is of (`ask`), let go of as nothing holds
/// it (`let_go`), or as the row is taken for another chat.
pub struct WholeAsk {
  priv mut lease : TopicLease?
  priv mut of : String
}

///|
pub fn WholeAsk::new() -> WholeAsk {
  { lease: None, of: "" }
}

///|
/// `item`'s whole row asked of `src`, unless it is held already; one held for another chat let go of.
pub fn WholeAsk::ask(self : WholeAsk, src : Source, item : ChatItem) -> Unit {
  let key = item.station + "\u{1}" + item.session
  match self.lease {
    Some(l) if self.of == key && l.alive() => return
    Some(l) => l.cancel()
    None => ()
  }
  self.of = key
  self.lease = ask_whole(src, item)
}

///|
/// What it holds let go of.
pub fn WholeAsk::let_go(self : WholeAsk) -> Unit {
  match self.lease {
    Some(l) => {
      self.lease = None
      self.of = ""
      l.cancel()
    }
    None => ()
  }
}

///|
/// What a chat's page's "…" reads of its row: its whole row (`chatRow`), held for as long as the chat's page is open
/// (under its chat's scope, let go of as it is left: the app's chat_left), asked as the page opens. As whole_row's.
pub fn chat_whole_held(src : Source, r : ChatRef) -> TopicState {
  hold(src, chat_scope(r.station, r.session), "chatRow", whole_params(r.station, r.session)).get()
}
