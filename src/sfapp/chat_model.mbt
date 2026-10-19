// A chat as its page shows it, read from the core's `chat` view (client/core-ts src/shapes/schema.ts: ChatView,
// ChatMessage, Attachment, Quote, MessageCard, MessageDecision, MessageBy, ChatSentElsewhere, Outgoing, ChatAgent)
// into MoonBit, the fields the page draws. A field the view leaves out reads as nothing, as Shapes.kt decodes it.

///|
fn opt_number(v : Json?, key : String) -> Double? {
  match field(v, key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// A moment in words, as the core says it (Stamp): `ago` (3 分钟前), `full` (9/20 14:05:09).
pub(all) struct Stamp {
  ago : String
  full : String
} derive(Eq)

///|
fn stamp_of(v : Json?, key : String) -> Stamp? {
  match field(field(v, "time"), key) {
    Some(Object(_)) as s => Some({ ago: text(s, "ago"), full: text(s, "full") })
    _ => None
  }
}

///|
/// A file sent with a message (Attachment).
pub(all) struct Attachment {
  name : String
  path : String
  size : Double
  width : Double
  height : Double
  thumbhash : String
  /// the session whose workspace keeps it (its preview and download go through it)
  owner : String
}

///|
fn attachment_of(a : Json) -> Attachment {
  let s = Some(a)
  {
    name: text(s, "name"),
    path: text(s, "path"),
    size: number(s, "size"),
    width: number(s, "width"),
    height: number(s, "height"),
    thumbhash: text(s, "thumbhash"),
    owner: text(s, "owner"),
  }
}

///|
/// A passage quoted with a message (Quote).
pub(all) struct Quote {
  author : String
  text : String
  comment : String
  ts : String
}

///|
fn quote_of(q : Json) -> Quote {
  let s = Some(q)
  { author: text(s, "author"), text: text(s, "text"), comment: text(s, "comment"), ts: text(s, "ts") }
}

///|
/// An answer a card offers (DecisionOption).
pub(all) struct Choice {
  label : String
  detail : String
  recommended : Bool
}

///|
fn choices_of(v : Json?, key : String) -> Array[Choice]? {
  match field(v, key) {
    Some(Array(a)) =>
      Some(
        a.map(fn(o) {
          {
            label: text(Some(o), "label"),
            detail: text(Some(o), "detail"),
            recommended: flag(Some(o), "recommended"),
          }
        }),
      )
    _ => None
  }
}

///|
/// The card a message carries (MessageCard): options, text or login.
pub(all) struct Card {
  kind : String
  assignee_text : String?
  options : Array[Choice]?
  login : String
  station : String
  vault : String
}

///|
/// Where a card stands (MessageDecision).
pub(all) struct Decision {
  resolved : Bool
  dismissed : Bool
  text : String?
}

///|
/// Who said a message (MessageBy).
pub(all) struct By {
  name : String
  agent : String
  maker : String
  runtime : String
  picture : String
  from : String
}

///|
fn by_of(v : Json?) -> By {
  let b = field(v, "by")
  {
    name: text(b, "name"),
    agent: text(b, "agent"),
    maker: text(field(b, "maker"), "id"),
    runtime: text(b, "runtime"),
    picture: text(b, "picture"),
    from: text(b, "from"),
  }
}

///|
/// A place a message went to or came from (Place).
pub(all) struct Place {
  name : String
  surface : String
  session : String
  url : String
}

///|
/// What an agent said in Slack, or was given from it (ChatSentElsewhere).
pub(all) struct Elsewhere {
  key : String
  after : Double
  text : String
  place : Place?
  failed : Bool
  received : Bool
  by : By
  time : Stamp?
}

///|
fn elsewhere_of(e : Json) -> Elsewhere {
  let s = Some(e)
  {
    key: text(s, "key"),
    after: number(s, "after"),
    text: text(s, "text"),
    place: match field(s, "place") {
      Some(Object(_)) as p =>
        Some({
          name: text(p, "name"),
          surface: text(p, "surface"),
          session: text(p, "session"),
          url: text(p, "url"),
        })
      _ => None
    },
    failed: flag(s, "failed"),
    received: flag(s, "received"),
    by: by_of(s),
    time: stamp_of(s, "createdAt"),
  }
}

///|
/// A runtime a notice says the station lacks, or a message of the viewer's waits for (RuntimeInstall).
pub(all) struct Install {
  state : String
  title : String
  note : String
  action : String
  percent : Double?
}

///|
fn install_of(v : Json?, key : String) -> Install? {
  match field(v, key) {
    Some(Object(_)) as i =>
      Some({
        state: text(i, "state"),
        title: text(i, "title"),
        note: text(i, "note"),
        action: text(i, "action"),
        percent: opt_number(i, "percent"),
      })
    _ => None
  }
}

///|
/// A message of the chat (ChatMessage), with what the core decides of it.
pub(all) struct Message {
  seq : Double
  thread : Double
  ts : String
  /// person | agent | ember
  author_kind : String
  author : String
  text : String
  attachments : Array[Attachment]
  quotes : Array[Quote]
  created_at : Double
  mine : Bool
  system : Bool
  profile : String
  install : Install?
  blocked : Install?
  by : By
  waiting : Bool
  followed : Bool
  joined : Bool
  time : Stamp?
  options : Array[Choice]?
  card : Card?
  decision : Decision?
  asked : Bool
  ending : String
  archive_check : (String, Bool)?
  elsewhere : Array[Elsewhere]
  placed : Array[String]
  /// said while the chat shows (not caught up on): it comes in rather than being there at once
  said : Bool
  /// the outbox entry it was sent from here as (its row goes on being that one)
  outgoing : String
}

///|
fn message_of(m : Json) -> Message {
  let s = Some(m)
  {
    seq: number(s, "seq"),
    thread: number(s, "thread"),
    ts: text(s, "ts"),
    author_kind: text(s, "authorKind"),
    author: text(s, "author"),
    text: text(s, "text"),
    attachments: items(s, "attachments").map(attachment_of),
    quotes: items(s, "quotes").map(quote_of),
    created_at: number(s, "createdAt"),
    mine: flag(s, "mine"),
    system: flag(s, "system"),
    profile: text(s, "profile"),
    install: install_of(s, "install"),
    blocked: install_of(s, "blocked"),
    by: by_of(s),
    waiting: flag(s, "waiting"),
    followed: flag(s, "followed"),
    joined: flag(s, "joined"),
    time: stamp_of(s, "createdAt"),
    options: choices_of(s, "options"),
    card: match field(s, "card") {
      Some(Object(_)) as c =>
        Some({
          kind: text(c, "type"),
          assignee_text: opt_text(c, "assigneeText"),
          options: choices_of(c, "options"),
          login: text(c, "login"),
          station: text(c, "station"),
          vault: text(c, "vault"),
        })
      _ => None
    },
    decision: match field(s, "decision") {
      Some(Object(_)) as d =>
        Some({
          resolved: flag(d, "resolved"),
          dismissed: flag(d, "dismissed"),
          text: opt_text(d, "text"),
        })
      _ => None
    },
    asked: flag(s, "asked"),
    ending: text(s, "ending"),
    archive_check: match field(s, "archiveCheck") {
      Some(Object(_)) as a => Some((text(a, "text"), flag(a, "failed")))
      _ => None
    },
    elsewhere: items(s, "elsewhere").map(elsewhere_of),
    placed: items(s, "placed").map(fn(n) {
      match n {
        String(x) => x
        _ => ""
      }
    }),
    said: flag(s, "said"),
    outgoing: text(s, "outgoing"),
  }
}

///|
/// A message sent from here that the chat does not show yet (Outgoing).
pub(all) struct Outgoing {
  id : String
  text : String
  attachments : Array[Attachment]
  quotes : Array[Quote]
  /// sending | failed
  state : String
  error : String
  joined : Bool
  followed : Bool
  /// the message's seq once the station has it (-1 before)
  seq : Double
}

///|
/// An agent of the chat (ChatAgent), as its marks and its activity show it.
pub(all) struct Agent {
  key : String
  runtime : String
  maker : String
  who : String
  /// block | run | failed, or "" (done)
  badge : String
  /// running while its turn runs
  status : String
  since : Double?
  wait : (Double, Double?, String)?
  /// seen starting while the chat shows: its activity comes in
  started : Bool
}

///|
fn agent_of(a : Json) -> Agent {
  let s = Some(a)
  let session = field(s, "session")
  {
    key: text(session, "key"),
    runtime: text(session, "runtime"),
    maker: text(field(session, "maker"), "id"),
    who: text(session, "agentText"),
    badge: text(s, "badge"),
    status: text(s, "status"),
    since: opt_number(s, "since"),
    wait: match field(s, "wait") {
      Some(Object(_)) as w => Some((number(w, "since"), opt_number(w, "seconds"), text(w, "text")))
      _ => None
    },
    started: flag(s, "started"),
  }
}

///|
/// A chat's page (ChatView): its chat with the viewer's read position, its agents and people.
pub(all) struct ChatView {
  title : String
  /// its thread's id, and how many wait past a window short of its end
  thread : Double?
  unread : Double
  people : Array[Person]
  agents : Array[Agent]
  messages : Array[Message]
  /// said in Slack before its first message
  elsewhere : Array[Elsewhere]
  more : Bool
  newer : Bool
  at : Double?
  at_offset : Double?
  unread_line : Double?
  unread_above : Bool
  outbox : Array[Outgoing]
  offline : Bool
  archived : Bool
  archivable : Bool
  archive_offered : Bool
  pending : Bool
  key : String
}

///|
pub fn chat_view(v : Json) -> ChatView {
  let s = Some(v)
  let thread = field(s, "thread")
  {
    title: text(s, "title"),
    thread: opt_number(thread, "id"),
    unread: number(thread, "unread"),
    people: items(s, "people").map(person_of),
    agents: items(s, "agents").map(agent_of),
    messages: items(s, "messages").map(message_of),
    elsewhere: items(s, "elsewhere").map(elsewhere_of),
    more: flag(s, "more"),
    newer: flag(s, "newer"),
    at: opt_number(s, "at"),
    at_offset: opt_number(s, "atOffset"),
    unread_line: opt_number(s, "unreadLine"),
    unread_above: flag(s, "unreadAbove"),
    outbox: items(s, "outbox").map(fn(o) {
      let s = Some(o)
      {
        id: text(s, "id"),
        text: text(s, "text"),
        attachments: items(s, "attachments").map(attachment_of),
        quotes: items(s, "quotes").map(quote_of),
        state: text(s, "state"),
        error: text(s, "error"),
        joined: flag(s, "joined"),
        followed: flag(s, "followed"),
        seq: opt_number(s, "seq").unwrap_or(-1.0),
      }
    }),
    offline: flag(s, "offline"),
    archived: flag(s, "archived"),
    archivable: flag(s, "archivable"),
    archive_offered: flag(s, "archiveOffered"),
    pending: flag(s, "pending"),
    key: text(s, "key"),
  }
}

///|
/// A station of the workspace as its marks show it (StationView): its address, name and mark, how it is reached.
pub(all) struct Station {
  address : String
  name : String
  emoji : String
  icon : String
  /// direct | relay | waiting | offline, or "" (StationViaDot)
  via : String
}

///|
pub fn stations_of(v : Json?) -> Array[Station] {
  match v {
    Some(Array(list)) =>
      list.map(fn(x) {
        let s = Some(x)
        let via = if !flag(s, "online") {
          "offline"
        } else if flag(s, "reconnecting") {
          "waiting"
        } else {
          match text(field(s, "net"), "via") {
            "direct" => "direct"
            "relay" => "relay"
            "choosing" => "waiting"
            _ => ""
          }
        }
        {
          address: text(s, "station"),
          name: text(s, "name"),
          emoji: text(s, "emoji"),
          icon: text(s, "icon"),
          via,
        }
      })
    _ => []
  }
}
