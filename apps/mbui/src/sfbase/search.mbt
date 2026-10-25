// What a few words find in a workspace (the core's `search` topic: SearchView, docs/search.md), as the phone's search
// and the desktop's ⌘K both read it, and where what it found opens (the core's `SearchItem.open`): the page each frame
// shows it on is the same page of the stack (app.nav).

///|
/// A chat the words found (SearchView.items): as Home lists it, and the part of it that has them when its title
/// shows them late or not at all (`foundText`, `foundMarks`), and whether it was found in its station's archive.
pub(all) struct FoundChat {
  item : ChatItem
  found : String?
  marks : Array[(Int, Int)]
  archived : Bool
}

///|
/// A message the words found (FoundMessage): its chat opens at it.
pub(all) struct FoundMessage {
  station : String
  seq : Double
  chat : ChatItem
  by : String
  text : String
  marks : Array[(Int, Int)]
  ago : String
}

///|
/// Something found besides a chat or a message (SearchItem), and where it opens (`open`, the core's: None where it
/// opens nowhere).
pub(all) struct FoundItem {
  kind : String
  key : String
  station : String
  station_name : String
  station_emoji : String
  station_icon : String
  title : String
  text : String
  marks : Array[(Int, Int)]
  chat_title : String
  dir : Bool
  ago : String
  open : FoundOpen?
}

///|
/// Where something found opens (SearchOpen, the core's search-open.ts `openOf`): `to` chat, service (its chat, its page
/// over it), task (its chat), station (its page), members (the workspace's), files (its station's: `root`, `path`
/// under it, `how` read or play, else the folder `path` shown).
pub(all) struct FoundOpen {
  to : String
  station : String
  chat : String?
  job : String?
  root : String?
  path : String
  how : String
} derive(Eq, Show)

///|
/// A kind of what was found (SearchGroup): its heading, what of it is listed, whether there is more of it.
pub(all) struct FoundGroup {
  kind : String
  title : String
  items : Array[FoundItem]
  more : Bool
}

///|
/// What a few words find in a workspace (the `search` topic: SearchView).
pub(all) struct SearchView {
  chats : Array[FoundChat]
  chats_more : Bool
  words : Array[String]
  messages : Array[FoundMessage]
  messages_more : Bool
  groups : Array[FoundGroup]
  /// the stations not answered yet (`wait`: ListNote), those that could not be searched
  reading : Bool
  wait_text : String?
  failing : Array[String]
  /// what the list says under it: stations offline or too old to search
  note : String?
}

///|
pub fn marks_of(v : Json?, key : String) -> Array[(Int, Int)] {
  items(v, key).map(fn(m) { (count(Some(m), "from"), count(Some(m), "to")) })
}

///|
pub fn search_view(v : Json) -> SearchView {
  let s = Some(v)
  let wait = field(s, "wait")
  {
    chats: items(s, "items").map(fn(c) {
      {
        item: chat_item(c),
        found: opt_text(Some(c), "foundText"),
        marks: marks_of(Some(c), "foundMarks"),
        archived: flag(Some(c), "archived"),
      }
    }),
    chats_more: flag(s, "chatsMore"),
    words: items(s, "words").map(fn(w) {
      match w {
        String(t) => t
        _ => ""
      }
    }),
    messages: items(s, "messages").map(fn(m) {
      let o = Some(m)
      {
        station: text(o, "station"),
        seq: number(o, "seq"),
        chat: match field(o, "chat") {
          Some(c) => chat_item(c)
          None => chat_item(Json::object({}))
        },
        by: text(o, "by"),
        text: text(o, "text"),
        marks: marks_of(o, "marks"),
        ago: text(field(field(o, "time"), "createdAt"), "ago"),
      }
    }),
    messages_more: flag(s, "messagesMore"),
    groups: items(s, "groups").map(fn(g) {
      let o = Some(g)
      {
        kind: text(o, "kind"),
        title: text(o, "title"),
        more: flag(o, "more"),
        items: items(o, "items").map(fn(it) {
          let i = Some(it)
          {
            kind: text(i, "kind"),
            key: text(i, "key"),
            station: text(i, "station"),
            station_name: text(i, "stationName"),
            station_emoji: text(i, "stationEmoji"),
            station_icon: text(i, "stationIcon"),
            title: text(i, "title"),
            text: text(i, "text"),
            marks: marks_of(i, "marks"),
            chat_title: text(i, "chatTitle"),
            dir: flag(i, "dir"),
            ago: text(field(field(i, "time"), "createdAt"), "ago"),
            open: match field(i, "open") {
              Some(Object(_)) as o =>
                Some({
                  to: text(o, "to"),
                  station: text(o, "station"),
                  chat: opt_text(o, "chat"),
                  job: opt_text(o, "job"),
                  root: opt_text(o, "root"),
                  path: text(o, "path"),
                  how: text(o, "how"),
                })
              _ => None
            },
          }
        }),
      }
    }),
    reading: flag(wait, "reading"),
    wait_text: opt_text(wait, "text"),
    failing: items(wait, "failing").map(fn(f) { text(Some(f), "text") }),
    note: opt_text(s, "note"),
  }
}

///|
/// The chat a row lists, as a page opens it.
pub fn chat_ref_of(item : ChatItem) -> ChatRef {
  { station: item.station, session: item.session, title: item.title, station_name: item.station_name }
}

///|
/// Opens what was found where the core says it opens (SearchItem.open: search-open.ts `openOf`): a service its chat and
/// its page over it, a task or anything else in a chat that chat; a station its page; a member the workspace's page; a
/// file its place in its station's files (a text read, a video or a song played, else its folder shown). Nothing where
/// it opens nowhere.
pub fn open_found(it : FoundItem) -> Unit {
  let o = match it.open {
    Some(o) => o
    None => return
  }
  let chat : ChatRef? = match o.chat {
    Some(k) => Some({ station: o.station, session: k, title: it.chat_title, station_name: it.station_name })
    None => None
  }
  match o.to {
    "station" => open_page(Setting(@settings.Station(o.station)))
    "members" => open_page(Setting(@settings.Workspace))
    "files" => {
      let at : DriveAt = { station: o.station, root: o.root, path: o.path }
      open_page(
        match o.how {
          "read" => DriveRead(at)
          "play" => DrivePlay(at)
          _ => Drive(at)
        },
      )
    }
    _ =>
      match chat {
        Some(r) => {
          open_page(Chat(r))
          match o.job {
            Some(job) if o.to == "service" => open_page(Service(o.station, job))
            _ => ()
          }
        }
        None => ()
      }
  }
}
