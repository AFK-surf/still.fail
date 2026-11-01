// A chat as its page shows it, read from the core's `chat` view (client/core-ts src/shapes/schema.ts: ChatView,
// ChatMessage, Attachment, Quote, MessageCard, MessageDecision, MessageBy, ChatSentElsewhere, Outgoing, ChatAgent)
// into MoonBit, the fields the page draws. A field the view leaves out reads as nothing, as Shapes.kt decodes it.

///|
pub fn opt_number(v : Json?, key : String) -> Double? {
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
pub fn stamp_of(v : Json?, key : String) -> Stamp? {
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
  /// the id of this device's upload it is (`composer.add`), sent before it was up: its picture is still here
  /// (composer.mbt sent_picture); "" for any other
  upload : String
  /// a film's length (ms) and how many frames its picture has, as the station read them from its header (0: not said)
  duration : Double
  frames : Int
  /// its picture (an image's thumbnail, a video's still) kept on this device (the core's `held`): a decode away, so
  /// the app's first page waits for it as for the rest of what it shows
  held : Bool
}

///|
pub fn attachment_of(a : Json) -> Attachment {
  let s = Some(a)
  {
    name: text(s, "name"),
    path: text(s, "path"),
    size: number(s, "size"),
    width: number(s, "width"),
    height: number(s, "height"),
    thumbhash: text(s, "thumbhash"),
    owner: text(s, "owner"),
    upload: text(s, "upload"),
    duration: number(s, "duration"),
    frames: number(s, "frames").to_int(),
    held: field(s, "held") is Some(True),
  }
}

///|
/// A passage quoted with a message (Quote).
pub(all) struct Quote {
  author : String
  text : String
  comment : String
  ts : String
  /// agent | person | page (a mark on a previewed page) | image (a numbered mark on an image)
  role : String
  /// the name of the file among the message's that goes with it (a mark's screenshot, an image of the message
  /// quoted): shown in its card, not with the message's files; "" none
  file : String
}

///|
pub fn quote_of(q : Json) -> Quote {
  let s = Some(q)
  {
    author: text(s, "author"),
    text: text(s, "text"),
    comment: text(s, "comment"),
    ts: text(s, "ts"),
    role: text(s, "role"),
    file: text(s, "file"),
  }
}

///|
/// An answer a card offers (DecisionOption).
pub(all) struct Choice {
  label : String
  detail : String
  recommended : Bool
  /// picked, the card closes and no message of the viewer's comes of it
  closes : Bool
}

///|
pub fn choices_of(v : Json?, key : String) -> Array[Choice]? {
  match field(v, key) {
    Some(Array(a)) =>
      Some(
        a.map(fn(o) {
          {
            label: text(Some(o), "label"),
            detail: text(Some(o), "detail"),
            recommended: flag(Some(o), "recommended"),
            closes: flag(Some(o), "closes"),
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
  /// who is to decide (their email), where someone is
  assignee : String
  options : Array[Choice]?
  login : String
  station : String
  vault : String
  /// with `vault`: the request as the card says it (MessageCard.vaultAsk), drawn in place of the post's words
  ask : VaultAsk?
  /// an agent's request for its person's phone (MessageCard.phoneAsk), drawn in place of the post's words
  phone : PhoneAsk?
  /// an agent's ask to sign in to a site (MessageCard.signinAsk), drawn in place of the post's words
  signin : SignInAsk?
}

///|
/// An agent's ask to sign in to a site as its card says it (SignInAsk, ember docs/vault.md 登录态): its id, the site,
/// why, the chat's tab it is on (a screen of the chat's station), and how it goes (`status`: "" waiting, filling, code,
/// person, left, done, denied, expired, ended; `why` a person is needed; what the agent `said` is left; whether it is
/// to be kept, `keep`; the vault request keeping it, `save`, and how that went, `kept`).
pub(all) struct SignInAsk {
  id : String
  site : String
  reason : String
  screen : String
  status : String
  why : String
  said : String
  keep : Bool
  save : String
  kept : String
}

///|
/// An agent's request to debug its person's phone as its card says it (PhoneAsk, docs/adb-share.md): its id, the
/// agent's reason, and once decided how (`status`: granted, denied, ended; `scope`: hour, chat; `why` it ended).
pub(all) struct PhoneAsk {
  request : String
  reason : String
  status : String
  scope : String
  why : String
  /// granted, how its station's adb holds the phone, as the station said: connected, unpaired, off, unauthorized,
  /// missing, failed, gone ("": not said)
  link : String
  /// the longest its owner lets it be granted for: hour, chat
  lasts : String
}

///|
/// An agent's request about a vault item as its card says it (VaultAsk): the item, how it is given, the command it is
/// for; one to keep a secret (`save_kind` not empty): what kind, the account (a file: its name), whether the person
/// types it in (`typed`); once decided, how (`status`, `scope`).
pub(all) struct VaultAsk {
  name : String
  reason : String
  mode : String
  command : String
  /// How it is given, including the allowed hosts, as the core says it.
  how_text : String
  save_kind : String
  username : String
  /// a file's name, where the agent gave one
  filename : String
  typed : Bool
  status : String
  scope : String
  /// another station of the workspace its commands run on, by name (empty: the chat's)
  station : String
  /// how it is answered on this device, the core's from the vault it holds: approve, setUp, elsewhere (MessageCard's
  /// vaultAsk.answer)
  answer : String
  /// answered approve, a use: the longest it may be given for
  lasts : String
}

///|
/// Where a card stands (MessageDecision).
pub(all) struct Decision {
  resolved : Bool
  dismissed : Bool
  text : String?
  /// the option picked, once answered
  chosen : String?
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
pub fn by_of(v : Json?) -> By {
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
  app : String
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
  /// the files a person's message there came with
  attachments : Array[Attachment]
  by : By
  time : Stamp?
}

///|
pub fn elsewhere_of(e : Json) -> Elsewhere {
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
          app: text(p, "app"),
        })
      _ => None
    },
    failed: flag(s, "failed"),
    received: flag(s, "received"),
    attachments: items(s, "attachments").map(attachment_of),
    by: by_of(s),
    time: stamp_of(s, "createdAt"),
  }
}

///|
/// A runtime a notice says the station lacks, or a message of the viewer's waits for (RuntimeInstall).
pub(all) struct Install {
  /// the runtime it is (`software.update`'s id)
  runtime : String
  state : String
  title : String
  note : String
  action : String
  percent : Double?
  /// why installing it failed
  detail : String
}

///|
pub fn install_of(v : Json?, key : String) -> Install? {
  match field(v, key) {
    Some(Object(_)) as i =>
      Some({
        runtime: text(i, "runtime"),
        state: text(i, "state"),
        title: text(i, "title"),
        note: text(i, "note"),
        action: text(i, "action"),
        percent: opt_number(i, "percent"),
        detail: text(i, "detail"),
      })
    _ => None
  }
}

///|
/// A chat a message links to, as the core says it (LinkedChat): its link as written, its title (what the link written
/// bare reads as), whether it is archived and its words for where it stands then (已归档).
pub(all) struct LinkedChat {
  href : String
  title : String
  archived : Bool
  note : String
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
  md : Json?
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
  elsewhere : Array[Elsewhere]
  placed : Array[String]
  /// said while the chat shows (not caught up on): it comes in rather than being there at once
  said : Bool
  /// the outbox entry it was sent from here as (its row goes on being that one)
  outgoing : String
  /// a failure still.fail says that the viewer may send to the still.fail team (`chat.report`)
  reportable : Bool
  /// still.fail's notice as the core says it is shown (NoticeShown): a failure (red), its words as a line, where its
  /// link to `profile` begins (-1: none), its words' Markdown as the core read them
  notice_failed : Bool
  notice_words : String
  notice_link : Int
  notice_md : Json?
  /// the chats its words link to that their lists have (archived ones too)
  chats : Array[LinkedChat]
}

///|
pub fn message_of(m : Json) -> Message {
  let s = Some(m)
  {
    seq: number(s, "seq"),
    thread: number(s, "thread"),
    ts: text(s, "ts"),
    author_kind: text(s, "authorKind"),
    author: text(s, "author"),
    text: text(s, "text"),
    md: field(s, "md"),
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
          assignee: text(c, "assignee"),
          options: choices_of(c, "options"),
          login: text(c, "login"),
          station: text(c, "station"),
          vault: text(c, "vault"),
          ask: match field(c, "vaultAsk") {
            Some(Object(_)) as a =>
              Some({
                name: text(a, "name"),
                reason: text(a, "reason"),
                mode: text(a, "mode"),
                command: text(a, "command"),
                how_text: text(a, "howText"),
                save_kind: text(field(a, "save"), "kind"),
                username: text(field(a, "save"), "username"),
                filename: text(field(a, "save"), "filename"),
                typed: flag(field(a, "save"), "typed"),
                status: text(a, "status"),
                scope: text(a, "scope"),
                station: text(a, "station"),
                answer: text(a, "answer"),
                lasts: text(a, "lasts"),
              })
            _ => None
          },
          signin: match field(c, "signinAsk") {
            Some(Object(_)) as a =>
              Some({
                id: text(a, "id"),
                site: text(a, "site"),
                reason: text(a, "reason"),
                screen: text(a, "screen"),
                status: text(a, "status"),
                why: text(a, "why"),
                said: text(a, "said"),
                keep: match field(a, "keep") {
                  Some(False) => false
                  _ => true
                },
                save: text(a, "save"),
                kept: text(a, "kept"),
              })
            _ => None
          },
          phone: match field(c, "phoneAsk") {
            Some(Object(_)) as a =>
              Some({
                request: text(a, "request"),
                reason: text(a, "reason"),
                status: text(a, "status"),
                scope: text(a, "scope"),
                why: text(a, "why"),
                link: text(a, "link"),
                lasts: text(a, "lasts"),
              })
            _ => None
          },
        })
      _ => None
    },
    decision: match field(s, "decision") {
      Some(Object(_)) as d =>
        Some({
          resolved: flag(d, "resolved"),
          dismissed: flag(d, "dismissed"),
          text: opt_text(d, "text"),
          chosen: opt_text(d, "chosen"),
        })
      _ => None
    },
    asked: flag(s, "asked"),
    ending: text(s, "ending"),
    elsewhere: items(s, "elsewhere").map(elsewhere_of),
    placed: items(s, "placed").map(fn(n) {
      match n {
        String(x) => x
        _ => ""
      }
    }),
    said: flag(s, "said"),
    outgoing: text(s, "outgoing"),
    reportable: flag(s, "reportable"),
    notice_failed: flag(field(s, "notice"), "failed"),
    notice_words: text(field(s, "notice"), "words"),
    notice_link: match opt_number(field(s, "notice"), "linkAt") {
      Some(n) => n.to_int()
      None => -1
    },
    notice_md: field(field(s, "notice"), "md"),
    chats: items(s, "chats").map(fn(c) -> LinkedChat {
      let c = Some(c)
      { href: text(c, "href"), title: text(c, "title"), archived: flag(c, "archived"), note: text(c, "note") }
    }),
  }
}

///|
/// The chat a message's link `href` names, as the core says it with the message (Message's `chats`).
pub fn Message::linked(self : Message, href : String) -> LinkedChat? {
  self.chats.iter().find_first(fn(c) { c.href == href })
}

///|
/// A message sent from here that the chat does not show yet (Outgoing).
pub(all) struct Outgoing {
  id : String
  text : String
  attachments : Array[Attachment]
  quotes : Array[Quote]
  /// sending | sent (the station has it: `seq`) | failed
  state : String
  error : String
  joined : Bool
  followed : Bool
  /// the message's seq once the station has it (-1 before)
  seq : Double
  /// when it was sent, in words (Time), shown under it once it is sent
  time : Stamp?
  /// why it has not reached the station yet, in place of 正在发送 ("" none)
  waits : String
  /// its files going up (`waits` says so): how much of them all the station has, 0 to 1 (None: not said)
  progress : Double?
  /// its files still going up before it goes but its images, among its `attachments` already (`uploads`): each one's
  /// name, size and how much of it the station has
  uploads : Array[(String, Int, Int)]
  /// when it was sent (the frames' clock's: "正在发送" shows a while after), and whether it was refused as it is (sent
  /// again it would be again: its words go back to the composer)
  created_at : Double
  final : Bool
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
  /// its last turn's id (its session's lastTurn), "" before it has had one
  last_turn : String
}

///|
pub fn agent_of(a : Json) -> Agent {
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
    last_turn: text(field(session, "lastTurn"), "id"),
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
  /// the first and last entries loaded (letters and edits are not messages): the cursors for loading pages
  first_entry : Double?
  last_entry : Double?
  /// how many letters its agents and other chats' wrote each other (not in `messages`: their own sheet)
  letters : Int
  at : Double?
  at_offset : Double?
  unread_line : Double?
  unread_above : Bool
  outbox : Array[Outgoing]
  offline : Bool
  /// its station down, the line over the composer (why, and that what is sent goes once it is reached)
  offline_note : String?
  /// its station gone for its update: that line marked with the update's mark in place of the unplugged one
  updating : Bool
  /// its agent's prompt cache over (the core's `cacheCold`): that agent's session, the status, what rereading costs,
  /// and whether it goes on afresh as it is next started (as its chat chose, or else its station is set)
  cache_cold : (String, String, String, Bool)?
  /// where it stands, as its row's second line says it without a card waiting (the core's `stateText`, `stateLead`,
  /// `stateRest`): said at the end of its messages
  state : (String, String, String)?
  /// what an agent needs a person for, as `state` says it (the core's `stateAsk`): the post that asks it, let go right
  /// under the line rather than under that post
  state_ask : Double?
  /// one of `asks` is not at the end itself (the core's `askClear`): the end keeps clear of the bell that leads to it
  ask_clear : Bool
  archived : Bool
  archivable : Bool
  pending : Bool
  key : String
  /// what waits to be decided in it (the core's `asks`), by the post each is about
  asks : Array[Double]
  /// its station's update, as the bar says it (StationUpdateNotice)
  station_update : Json?
  /// the viewer's email, as the chat knows them (`me`): whose a card is to decide
  me : String
  /// its side panel's tabs, as the core keeps them for it on this device (`tabs`, client/core-ts/src/chat-tabs.ts)
  tabs : ChatTabs
  /// its agents' Slack and Feishu threads, the one said in last first: what is sent from here is copied to those
  /// ticked (`cc`, `chat.cc`); empty when they are in none
  cc : Array[ChatCcTo]
  /// the screens of the station it runs on (the core's `screens`), its own display first: its bar's way to them
  screens : Array[ChatScreen]
  /// the chat an agent opened it from: before its title in its bar, the way back there
  opener : Opener?
  /// the chats its agent made, the first first, and how many in words (创建了 3 个对话): its info's list of them
  opened : Array[OpenedChat]
  opened_text : String
}

///|
/// One of the screens of a chat's station (the chat view's `screens`): its id, kind, title, what its station says of it,
/// and whether an agent drives it now.
pub(all) struct ChatScreen {
  id : String
  kind : String
  title : String
  line : String
  agent : Bool
}

///|
/// A thread a chat's messages can be copied to (the chat view's `cc`, docs/relay.md "抄送"): its id (`chat.cc`'s `to`),
/// where it is (#channel, 私信, the Feishu group), its platform for its mark ("slack" or "feishu"), and whether it is
/// ticked.
pub(all) struct ChatCcTo {
  thread : Double
  place : String
  via : String
  on : Bool
}

///|
/// A chat's side panel's tabs (the chat view's `tabs`): those open, in order (an agent's history by its session's key,
/// `jobs`, `files`, `letters`, the web's `service:<job>` and `file:[…]`), the one in front, and whether they are the
/// ones the chat opens by itself (its agent with no chat yet: its history), not opened by anyone.
pub(all) struct ChatTabs {
  open : Array[String]
  shown : String?
  auto : Bool
}

///|
/// A chat's view made here, not read from the core's `chat` topic: a decision's messages as their chat would show
/// them, a test's. A chat's topic is read through view_of_chat, worked out once for each version of it.
pub fn chat_view_made(v : Json) -> ChatView {
  chat_view(v)
}

///|
/// A chat's view as the core gives it, each of its messages read: for view_of_chat alone (chat_read), so no page
/// works it out of the topic again, each frame.
fn chat_view(v : Json) -> ChatView {
  chat_view_of(v, items(Some(v), "messages").map(message_of))
}

///|
/// A chat's view as the core gives it, its messages read already (`messages`: chat_read's, each read again only as it
/// changed).
fn chat_view_of(v : Json, messages : Array[Message]) -> ChatView {
  let s = Some(v)
  let thread = field(s, "thread")
  {
    title: text(s, "title"),
    thread: opt_number(thread, "id"),
    unread: number(thread, "unread"),
    people: items(s, "people").map(person_of),
    agents: items(s, "agents").map(agent_of),
    messages,
    elsewhere: items(s, "elsewhere").map(elsewhere_of),
    more: flag(s, "more"),
    newer: flag(s, "newer"),
    first_entry: opt_number(s, "firstEntry"),
    last_entry: opt_number(s, "lastEntry"),
    letters: number(s, "letters").to_int(),
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
        time: stamp_of(s, "createdAt"),
        waits: text(s, "waits"),
        progress: opt_number(s, "progress"),
        uploads: items(s, "uploads").map(fn(u) {
          (text(Some(u), "name"), number(Some(u), "size").to_int(), number(Some(u), "sent").to_int())
        }),
        created_at: number(s, "createdAt"),
        final: flag(s, "final"),
      }
    }),
    offline: flag(s, "offline"),
    offline_note: opt_text(s, "offlineNote"),
    updating: flag(s, "updating"),
    cache_cold: match field(s, "cacheCold") {
      Some(Object(_)) as cold => Some((text(cold, "session"), text(cold, "status"), text(cold, "detail"), flag(cold, "afresh")))
      _ => None
    },
    state: match opt_text(s, "stateText") {
      Some(words) => Some((words, text(s, "stateLead"), text(s, "stateRest")))
      None => None
    },
    state_ask: opt_number(s, "stateAsk"),
    ask_clear: flag(s, "askClear"),
    archived: flag(s, "archived"),
    archivable: flag(s, "archivable"),
    asks: items(s, "asks").map(fn(a) { number(Some(a), "seq") }),
    station_update: field(s, "stationUpdate"),
    me: text(field(s, "me"), "email"),
    pending: flag(s, "pending"),
    key: text(s, "key"),
    tabs: {
      open: items(field(s, "tabs"), "open").filter_map(fn(t) { if t is String(k) { Some(k) } else { None } }),
      shown: opt_text(field(s, "tabs"), "shown"),
      auto: flag(field(s, "tabs"), "auto"),
    },
    cc: items(s, "cc").map(fn(o) {
      let o = Some(o)
      { thread: number(o, "thread"), place: text(o, "place"), via: text(o, "via"), on: flag(o, "on") }
    }),
    screens: items(s, "screens").map(fn(o) {
      let o = Some(o)
      { id: text(o, "id"), kind: text(o, "kind"), title: text(o, "title"), line: text(o, "line"), agent: flag(o, "agent") }
    }),    opener: opener_of(s),
    opened: opened_of(s),
    opened_text: text(s, "openedText"),
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
        let via = @settings.station_via(s)
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

///|
/// A chat's topics' params: its station and session.
pub fn chat_params(r : ChatRef) -> Map[String, Json] {
  { "station": Json::string(r.station), "session": Json::string(r.session) }
}

///|
/// The last part of a path.
pub fn base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(i) => path.view(start_offset=i + 1).to_string()
    None => path
  }
}
