// What Home shows, read from the core's views (client/core-ts src/shapes/schema.ts: ChatsView, ChatDay, ChatItem,
// RowAgent, Person, ListNote; AccountWorkspaces as the `workspaces` topic has them; WorkspaceMarksView) into
// MoonBit, the fields Home draws. A field the view leaves out reads as nothing (""/false/None), as the Android app's
// generated Shapes.kt decode it.

///|
/// A field of the core's JSON, its words, its flag, its number, its items (a field left out reads as nothing), and the
/// workspace a station (`<workspace>/<station>`) is of: the settings' reading, the one for every package above them.
pub using @settings {
  workspace_of,
  field,
  text,
  opt_text,
  flag,
  number,
  items,
}

///|
/// An agent of a row, by what its mark shows: the model's maker, its runtime.
pub(all) struct RowAgent {
  /// its session's key
  key : String
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
  /// what the chat's bar calls them (「你」 for the viewer)
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
  /// what the core says leads it (need, done, wait, watch, decision, or ""), the lead word of a card's line (奏) and
  /// what follows the lead (watching: the whole line)
  state_lead : String
  state_lead_text : String
  state_rest : String
  /// the message `state_text` is about (a seq in the chat), not one that asks for a decision: opened from the line,
  /// the chat goes to it
  state_about : Double?
  /// a message of the viewer's in it did not go: its state line in red
  unsent : Bool
  decision_text : String?
  last : String?
  /// its last message when the viewer wrote it, by its seq: a chat written in here or elsewhere by them goes ahead
  /// at once, even in a list held still (rows.mbt viewer_moved)
  wrote : Double?
  offline : String?
  /// its station gone for its update: the update's mark in place of the unplugged one
  updating : Bool
  reconnecting : String?
  connect : Bool
  origin_text : String
  /// the kind of connect it came from (slack | feishu: the core's originKind), for its mark
  origin_kind : String
  /// the people in it in words, for a screen reader
  people_text : String
  pending : Bool
  settled : Bool
  /// made and its station there: a finger's swipe left archives it (the core's swipeArchive)
  swipe_archive : Bool
  watch_ask : String?
  /// what its swipe asks before archiving it (keeping watch, at work, or waiting on work it started: the core's swipeAsk)
  swipe_ask : String?
  /// lastActiveAt in words (3 分钟前), and as its day and time (its row's time's tip)
  ago : String
  full : String
  agents : Array[RowAgent]
  people : Array[Person]
  creator : String
  /// pinned to the list's top (None: a station from before pins), kept from the archive too
  pinned : Bool?
  /// the viewer kept it out of the archive (保留), pinned or not
  kept : Bool
  /// Personal list visibility (None: a station from before hiding).
  hidden : Bool?
  /// Personal notification setting (None: a station from before muting).
  muted : Bool?
  /// the key a chat asked for here went by before its station made it ("" for none): its row is the same row
  /// throughout
  client_key : String
  /// the chat an agent opened it from (chat_create): the way back there, a link only
  opener : Opener?
  /// what its menu offers besides the list's own, as its page's "…" (the core's mayShare, mayPublish, slackUrl, slackApp,
  /// feishuUrl): shared with the viewer's other workspaces, a picture of it, it in Slack or Feishu ("" none)
  may_share : Bool
  may_publish : Bool
  slack_url : String
  slack_app : String
  feishu_url : String
}

///|
/// The chat an agent opened a chat from (the core's Opener): where it is, as its list names it, and what it is to the
/// chat it opened in words (由「…」创建); `archived` with what says so (已归档).
pub(all) struct Opener {
  chat : ChatRef
  text : String
  archived : Bool
  note : String
}

///|
/// A chat a chat's agent opened (the core's OpenedChat): where it is, as its list names it, where it stands (its row's
/// mark, what leads its line and the line), and whether it is in its station's archive (with what says so).
pub(all) struct OpenedChat {
  chat : ChatRef
  mark : String
  state_lead : String
  state_text : String
  archived : Bool
  note : String
}

///|
/// A chat's `opened`, as the core gives it.
pub fn opened_of(v : Json?) -> Array[OpenedChat] {
  items(v, "opened").map(fn(j) {
    let o = Some(j)
    {
      chat: { station: text(o, "station"), session: text(o, "session"), title: text(o, "title"), station_name: "" },
      mark: text(o, "mark"),
      state_lead: text(o, "stateLead"),
      state_text: text(o, "stateText"),
      archived: flag(o, "archived"),
      note: text(o, "note"),
    }
  })
}

///|
/// A chat's or a row's `opener`, as the core gives it.
pub fn opener_of(v : Json?) -> Opener? {
  let o = field(v, "opener")
  match o {
    Some(Object(_)) =>
      Some({
        chat: { station: text(o, "station"), session: text(o, "session"), title: text(o, "title"), station_name: "" },
        text: text(o, "text"),
        archived: flag(o, "archived"),
        note: text(o, "note"),
      })
    _ => None
  }
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
  /// while what changed since the app was last with the stations is still coming: what the mark at the list's top
  /// says (正在同步, 正在同步 · 还剩 12 个对话)
  syncing : String?
}

///|
pub fn person_of(p : Json) -> Person {
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
    state_lead: text(s, "stateLead"),
    state_lead_text: text(s, "stateLeadText"),
    state_rest: text(s, "stateRest"),
    state_about: match field(s, "stateAbout") {
      Some(Number(n, ..)) => Some(n)
      _ => None
    },
    unsent: flag(s, "unsent"),
    decision_text: opt_text(field(s, "decision"), "text"),
    last: opt_text(field(s, "last"), "preview"),
    wrote: match (field(s, "last"), flag(field(field(s, "last"), "by"), "mine")) {
      (Some(_) as l, true) =>
        match field(l, "seq") {
          Some(Number(n, ..)) => Some(n)
          _ => None
        }
      _ => None
    },
    offline: opt_text(s, "offline"),
    updating: flag(s, "updating"),
    reconnecting: opt_text(s, "reconnecting"),
    connect: field(s, "connect") is Some(String(_)),
    origin_text: text(s, "originText"),
    origin_kind: text(s, "originKind"),
    people_text: text(s, "peopleText"),
    pending: flag(s, "pending"),
    settled: flag(s, "settled"),
    swipe_archive: flag(s, "swipeArchive"),
    watch_ask: opt_text(field(s, "watch"), "ask"),
    swipe_ask: opt_text(s, "swipeAsk"),
    ago: text(time, "ago"),
    full: text(time, "full"),
    agents: items(s, "agents").map(fn(a) {
      {
        key: text(Some(a), "key"),
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
    hidden: match field(s, "hidden") {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    },
    muted: match field(s, "muted") {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    },
    client_key: text(s, "clientKey"),
    opener: opener_of(s),
    may_share: flag(s, "mayShare"),
    may_publish: flag(s, "mayPublish"),
    slack_url: text(s, "slackUrl"),
    slack_app: text(s, "slackApp"),
    feishu_url: text(s, "feishuUrl"),
  }
}

///|
/// A row as its station's state makes it (the `chats` list's `stations`: said once for a station, not on each of its
/// rows; client/core-ts views.ts `stationOn`, which this follows): offline, it is not swiped away; gone for its update,
/// its second line says so unless it needs the viewer. The row as it is while its station says nothing of it.
fn station_on(item : ChatItem, station : Json?) -> ChatItem {
  let offline = opt_text(station, "offline")
  let reconnecting = opt_text(station, "reconnecting")
  if offline is None && reconnecting is None {
    return item
  }
  let item = match offline {
    Some(_) => { ..item, offline, swipe_archive: false, swipe_ask: None }
    None => item
  }
  let item = match reconnecting {
    Some(_) => { ..item, reconnecting }
    None => item
  }
  if !flag(station, "updating") {
    return item
  }
  if item.state_lead == "need" {
    { ..item, updating: true }
  } else {
    { ..item, updating: true, state_text: offline, state_lead: "", state_lead_text: "", state_rest: "", state_about: None }
  }
}

///|
/// The chats' list made here, not read from the core's `chats` topic (a test's). The topic is read through chats_of,
/// worked out once for each version of it.
pub fn chats_view_made(v : Json) -> ChatsView {
  chats_view(v)
}

///|
/// The chats' list as the core gives it: for chats_of alone (chats_read).
fn chats_view(v : Json) -> ChatsView {
  let stations = stations_said(v)
  chats_view_by(v, fn(j) { station_on(chat_item(j), stations.get(text(Some(j), "station"))) })
}

///|
/// The list's stations that say something of each of their rows (station_on), by address.
fn stations_said(v : Json) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for s in items(Some(v), "stations") {
    if field(Some(s), "offline") is Some(_) || field(Some(s), "reconnecting") is Some(_) {
      out[text(Some(s), "station")] = s
    }
  }
  out
}

///|
/// The chats' list as the core gives it, each row read by `item` (chats_read's: read again only as it changed).
fn chats_view_by(v : Json, item : (Json) -> ChatItem) -> ChatsView {
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
      { label: text(Some(d), "label"), items: items(Some(d), "items").map(item) }
    }),
    leading: match text(s, "leading") {
      "" => "agents"
      l => l
    },
    note,
    syncing: opt_text(s, "syncing"),
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

///|
/// The first line of some words that has any: what a one-line event shows of them.
pub fn first_line(words : String) -> String {
  for l in words.split("\n") {
    let s = l.trim(chars=" \t").to_owned()
    if s != "" {
      return s
    }
  }
  ""
}

///|
/// The station this machine is, as its host says (its station's cloud.json),
/// read once it is one; "" where it is none, asked again (one 添加这台 Mac adds, known without the app opened again).
pub fn this_machine() -> String {
  match machine_here.val {
    Some(h) => h
    None => {
      let v = @json.parse(@hostapi.app_said("local_station")) catch { _ => Json::null() }
      let ws = field(Some(v), "workspace")
      let h = if text(ws, "id") != "" && text(ws, "station") != "" {
        text(ws, "id") + "/" + text(ws, "station")
      } else {
        ""
      }
      if h != "" {
        machine_here.val = Some(h)
      }
      h
    }
  }
}

///|
/// Whether `screen` of `station` is this machine's own display (its `desktop` screen): seen
/// from here it would only show itself, a window inside a window inside a window, and driven from here it would drive
/// the very pointer driving it. A browser's tab or a simulator of this machine is a screen of its own, and is not this.
pub fn own_screen(station : String, screen : String) -> Bool {
  (screen == "desktop" || screen.has_prefix("desktop:")) && station != "" && station == this_machine()
}

///|
/// The station this machine is, as read once it is one (this_machine).
pub let machine_here : Ref[String?] = Ref(None)
