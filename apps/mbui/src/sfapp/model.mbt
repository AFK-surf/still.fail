// What Home shows, read from the core's views (client/core-ts src/shapes/schema.ts: ChatsView, ChatDay, ChatItem,
// RowAgent, Person, ListNote; AccountWorkspaces as the `workspaces` topic has them; WorkspaceMarksView) into
// MoonBit, the fields Home draws. A field the view leaves out reads as nothing (""/false/None), as the Android app's
// generated Shapes.kt decode it.

///|
pub fn field(v : Json?, key : String) -> Json? {
  match v {
    Some(Object(m)) => m.get(key)
    _ => None
  }
}

///|
pub fn text(v : Json?, key : String) -> String {
  match field(v, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn opt_text(v : Json?, key : String) -> String? {
  match field(v, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
pub fn flag(v : Json?, key : String) -> Bool {
  match field(v, key) {
    Some(True) => true
    _ => false
  }
}

///|
fn number(v : Json?, key : String) -> Double {
  match field(v, key) {
    Some(Number(n, ..)) => n
    _ => 0.0
  }
}

///|
pub fn items(v : Json?, key : String) -> Array[Json] {
  match field(v, key) {
    Some(Array(a)) => a
    _ => []
  }
}

///|
/// An agent of a row, by what its mark shows: the model's maker, its runtime.
pub(all) struct RowAgent {
  maker : String
  runtime : String
  text : String
}

///|
/// Someone in a chat, as the core names them.
pub(all) struct Person {
  id : String
  email : String
  name : String
  /// how the viewer sees them (PersonShown.display: 你 for the viewer), where a chat shows its people (PeopleStack); a
  /// row of the list names them (RowPicture.kt Face: shown.name)
  display : String
  picture : String
  mine : Bool
}

///|
/// A row of the list (ChatItem).
pub(all) struct ChatItem {
  id : String
  session : String
  thread : Double?
  title : String
  unread : Bool
  station : String
  station_name : String
  station_emoji : String
  station_icon : String
  /// block | run | failed
  state : String
  /// alert | wait | busy | done | other, or ""
  tone : String
  state_text : String?
  decision_text : String?
  last : String?
  offline : String?
  reconnecting : String?
  connect : Bool
  origin_text : String
  pending : Bool
  settled : Bool
  archivable : Bool
  watch_ask : String?
  /// lastActiveAt in words (3 分钟前)
  ago : String
  agents : Array[RowAgent]
  people : Array[Person]
  creator : String
  /// pinned to the list's top (None: a station from before pins), kept from the archive
  pinned : Bool?
  kept : Bool
}

///|
/// A day of the list with its heading (今天, 昨天, 已固定…).
pub(all) struct ChatDay {
  label : String
  items : Array[ChatItem]
}

///|
/// What a list with no rows to show says in their place (ListNote).
pub(all) struct ListNote {
  reading : Bool
  text : String?
  failing : Array[String]
  empty : Bool
}

///|
/// A workspace's chats as Home lists them (ChatsView).
pub(all) struct ChatsView {
  stations : Int
  days : Array[ChatDay]
  /// agents | people: whose pictures lead the rows
  leading : String
  note : ListNote?
}

///|
fn person_of(p : Json) -> Person {
  let shown = field(Some(p), "shown")
  {
    id: text(Some(p), "id"),
    email: text(Some(p), "email"),
    name: text(shown, "name"),
    display: text(shown, "display"),
    picture: text(shown, "picture"),
    mine: flag(shown, "mine"),
  }
}

///|
pub fn chat_item(v : Json) -> ChatItem {
  let s = Some(v)
  let time = field(field(s, "time"), "lastActiveAt")
  {
    id: text(s, "id"),
    session: text(s, "session"),
    thread: match field(s, "thread") {
      Some(Number(n, ..)) => Some(n)
      _ => None
    },
    title: text(s, "title"),
    unread: flag(s, "unread"),
    station: text(s, "station"),
    station_name: text(s, "stationName"),
    station_emoji: text(s, "stationEmoji"),
    station_icon: text(s, "stationIcon"),
    state: text(s, "state"),
    tone: text(s, "tone"),
    state_text: opt_text(s, "stateText"),
    decision_text: opt_text(field(s, "decision"), "text"),
    last: opt_text(field(s, "last"), "preview"),
    offline: opt_text(s, "offline"),
    reconnecting: opt_text(s, "reconnecting"),
    connect: field(s, "connect") is Some(String(_)),
    origin_text: text(s, "originText"),
    pending: flag(s, "pending"),
    settled: flag(s, "settled"),
    archivable: flag(s, "archivable"),
    watch_ask: opt_text(field(s, "watch"), "ask"),
    ago: text(time, "ago"),
    agents: items(s, "agents").map(fn(a) {
      {
        maker: text(field(Some(a), "maker"), "id"),
        runtime: text(Some(a), "runtime"),
        text: text(Some(a), "agentText"),
      }
    }),
    people: items(s, "people").map(person_of),
    creator: text(field(s, "creator"), "id"),
    pinned: match field(s, "pinned") {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    },
    kept: flag(s, "kept"),
  }
}

///|
pub fn chats_view(v : Json) -> ChatsView {
  let s = Some(v)
  let note = match field(s, "note") {
    Some(Object(_)) as n =>
      Some({
        reading: flag(n, "reading"),
        text: opt_text(n, "text"),
        failing: items(n, "failing").map(fn(f) { text(Some(f), "text") }),
        empty: flag(n, "empty"),
      })
    _ => None
  }
  {
    stations: items(s, "stations").length(),
    days: items(s, "days").map(fn(d) {
      { label: text(Some(d), "label"), items: items(Some(d), "items").map(chat_item) }
    }),
    leading: match text(s, "leading") {
      "" => "agents"
      l => l
    },
    note,
  }
}

///|
/// A workspace the viewer is in, and the account they are in it by.
pub(all) struct Workspace {
  id : String
  name : String
  emoji : String
  icon : String
  email : String
}

///|
/// Every account's workspaces, each once (`workspaces`: AccountWorkspaces), and whether every account has answered.
pub fn workspaces_of(v : Json?) -> (Array[Workspace], Bool, Bool) {
  let all : Array[Workspace] = []
  let mut answered = true
  let mut invited = false
  match v {
    Some(Array(accounts)) =>
      for a in accounts {
        let s = Some(a)
        if !flag(s, "loaded") && field(s, "error") is None {
          answered = false
        }
        if items(s, "invitations").length() > 0 {
          invited = true
        }
        let email = text(field(s, "account"), "email")
        for w in items(s, "workspaces") {
          let id = text(Some(w), "id")
          if id != "" && !all.iter().any(fn(x) { x.id == id }) {
            all.push({
              id,
              name: text(Some(w), "name"),
              emoji: text(Some(w), "emoji"),
              icon: text(Some(w), "icon"),
              email,
            })
          }
        }
      }
    _ => answered = false
  }
  (all, answered, invited)
}

///|
/// Light then: a number's value as an Int (counts in the marks).
pub fn count(v : Json?, key : String) -> Int {
  number(v, key).to_int()
}

///|
/// Java's String.hashCode, over UTF-16 units, as the Android app picks a person's colour by it.
pub fn java_hash(s : String) -> Int {
  let mut h = 0
  for i in 0..<s.length() {
    h = h * 31 + s.at(i).to_int()
  }
  h
}
