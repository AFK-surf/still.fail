// A chat's list as both frames keep it (src/sfapp/chat.mbt the phone's, src/sfdesk's the desktop's): its rows, what
// the page keeps of a chat while it shows (Reading), where it was left, the rows new to it and their turns, the
// agents' lines lingering, the room they leave, what is read and where the reader is, told the core (client.focus,
// chat.place). Each frame draws the rows its own way.

///|
/// An entry of the list (Chat.kt Entry), with the room above the first (the bar's) and below the last (the
/// composer's).
pub(all) enum Entry {
  Top
  Older
  Empty
  Line
  Said(SaidRow)
  Sent(Elsewhere)
  Newer
  Out(Outgoing)
  /// where the chat stands (ChatView's `state`): its words, what leads them, what follows the lead
  State(String, String, String)
  Working(Agent)
  Foot
}

///|
pub fn Entry::id(self : Entry) -> String {
  match self {
    Top => "top"
    Older => "older"
    Empty => "empty"
    Line => "line"
    Said(m) => "m:" + m.ts
    Sent(e) => "s:" + e.key
    Newer => "newer"
    Out(o) => "o:" + o.id
    State(_, _, _) => state_key
    Working(a) => "act:" + a.key
    Foot => "foot"
  }
}

///|
/// What the page keeps of a chat while it is open.
pub(all) struct Reading {
  /// what the room under its rows is kept for besides the composer (its end clear of the bell floating over it:
  /// ask_clears), the Foot row's version: its height goes to another as that changes (list_size.mbt)
  mut foot_sign : String
  /// the last words sent from here that let go of the composer (their row's key): the composer's room under the rows
  /// goes down where it comes to stand as they do, the Foot row's version with it
  mut sent_foot : String
  /// the first message's entry and where it was in the list, the last frame
  mut head : String
  mut head_at : Int
  /// put in place once (the unread line, where it was opened, or the end)
  mut placed : Bool
  mut put : Bool
  /// the unread line shown: put at once it is (it may come after the chat opened, what came while the app was away
  /// read from the station after it)
  mut lined : Bool
  /// the first message when the page before was asked for (once per page)
  asked : @signals.Signal[Double]
  asked_newer : @signals.Signal[Double]
  /// the chat's latest page asked for in place of a window short of its end (chat_latest): the list goes to its end
  /// as it comes
  mut latest_asked : Bool
  /// its end asked for by a row (an option picked): handled by the retained list or list_after.
  end_asked : @signals.Signal[Bool]
  /// what the core was told of the chat shown, its end seen or not ("" nothing yet)
  mut told : String
  /// the newest message seen whole on this visit (-1 none): read up to there
  mut seen_whole : Double
  /// where the reader is: the message at the top of what shows (-1 none), and whether at the chat's end
  mut top_seq : Double
  /// the message at the foot of what shows (-1 none): what ⌘F starts at lies between (wide_find.mbt)
  mut bottom_seq : Double
  /// the frame those were last worked out in (read_place: once its builds were over, its page shown), whether where
  /// the chat stands (its State row) was in view then, and whether the list was still then (not gliding, nothing in
  /// its turns under way or waiting): what is on screen (Reading::sees)
  mut view_frame : Int
  mut state_seen : Bool
  mut view_still : Bool
  /// how far that message's top is below the list's (points: above it, less than 0)
  mut top_off : Double
  mut at_end : Bool
  /// where the core was last told the chat is (chat.place: "" not yet), and the screen's scale it was laid out at
  mut told_place : String
  mut scale : Double
  /// the jump button: shown since when (or hidden since when), and which
  mut jump : Bool
  mut jump_at : Double
  /// the bell to what waits to be decided: shown
  mut ask : Bool
  /// a scripted scroll through it (MBUI_CHAT_BENCH): frames so far, their times
  mut bench : Int
  /// 0: bringing in the pages before (up to 3000 messages), 1: measuring
  mut bench_phase : Int
  mut bench_rows : Int
  bench_ms : Array[Double]
  bench_present : Array[Double]
  /// the rows drawn so far, by key (what is new to the list rises in: Chat.kt known, arrived); whether it has been
  /// drawn; the rows new to it since, until they show
  known : Map[String, Bool]
  mut drawn : Bool
  /// the rows at its end that go from it as its turns go (by key): its agents' lines, where it stands. One gone leaves
  /// its room as a floor; an agent's line gone is forgotten (row_keys)
  acts : Map[String, Bool]
  /// the frame its old page was last built in
  mut shown_frame : Int
  /// while its list is a node of the window's tree, whether it shows (made, laid out somewhere): shown then without
  /// a build marking it
  mut shown_by : (() -> Bool)?
  fresh : Map[String, Bool]
  /// the frame a row new to it last came into it (`fresh`): what comes at its end then is glided after (Follow.kt)
  mut came_frame : Int
  /// the rows that came new to it while it shows, by key: the how-manieth (`came_n`), and the agent whose avatar it
  /// came out of ("" none). Words sent from here are not among them: they fly in (flight.mbt)
  came : Map[String, (Int, String)]
  mut came_n : Int
  /// what a row that makes way (an agent's line, what was sent not in the chat yet) last saw come in over it, as last
  /// built ("" nothing): its cause to glide down (sfpages chat_list)
  makes_way : Map[String, String]
  /// the newest row that came in over rows at its end while it was followed (what is at the end stays where it shows,
  /// the rows over it go up for it: sfpages chat_list), and the frame it came in ("" and -10: none yet)
  mut over : String
  mut over_frame : Int
  /// rows asked a turn to come in (turns.mbt: Chat.kt admitted)
  admitted : Map[String, Bool]
  /// its list, read as it was last laid out (its glide after what came set out there): a turn waits for that glide's
  /// end (ListInfo's `glide_rest`), not for the reader's hand (listQueue.ts listStill: following, and there)
  mut list_read : @ui.ListReader?
  /// the newest row (not an agent's line) as last built, and whether the list follows one from its top (Follow.kt
  /// anchor: a message arriving while it is followed is read from its start)
  mut newest : String
  mut following_row : Bool
  mut follow_key : String
  /// the outbox entries messages were sent from here as, by seq (their rows go on being those: Chat.kt sentAs)
  sent : Map[Double, String]
  /// the key each row of the core's that what was sent from here became goes on by: the key it had as it was sent
  /// ("o:local:n"), its one identity from the press on (its outbox entry's and its message's keys to it)
  sent_as : Map[String, String]
  /// Told when a local row is taken over, so a viewer opened before that can follow its new core identity.
  sent_as_told : @signals.Signal[Int]
  /// agents whose turn ended, still shown a moment (Chat.kt lingering: 600 ms, then fading 220): Lingering
  linger : Map[String, Lingering]
  /// how many have lingered (Lingering.id)
  mut lingered : Int
  /// the agents' lines in the order they first came to the list, by their keys: they stand so, one whose turn ended
  /// lingering where it was, not put after the others (a line gone past another at once, 2026-11-03)
  act_order : Map[String, Int]
  mut acts_seen : Int
  /// told as one comes to linger or goes (what reads `linger` built again for it: it is said before any page is built)
  linger_said : @signals.Signal[Int]
  /// the room agents' lines left as they went from the list (Chat.kt floor): the list never gets shorter under the
  /// reader. What comes in next takes it back (`floor_takers`: each row by key, as tall as the build last read it;
  /// `floor_laid`: as the frame before laid it out). Each agent's line's room (its row, the gap over it with it) as last
  /// read, by key; the frame the floor was last counted in
  mut floor : Double
  floor_takers : Map[String, Double]
  floor_laid : Map[String, Double]
  act_room : Map[String, Double]
  act_whole : Map[String, Bool]
  mut floor_frame : Int
  /// the room as it was last counted (more since: what went new, the rows making way for it from where they stood)
  mut floor_was : Double
  /// the agents running as last drawn
  running : Map[String, Agent]
  /// each agent's last turn as last ticked (Agent.last_turn)
  last_turns : Map[String, String]
  /// a message gone to (a notification's, "" none: ChatMotion.kt flashed) and how lit it is (flash_of)
  mut flash : String
  flash_lit : @motion.Anim
  /// flashes started (each one's own hold, with motion reduced)
  mut flash_n : Int
  /// what of it a quote that led there quoted ("" the whole of it: Chat.tsx flashRange), lit alone where it is found in
  /// its words; yet to be put in the list's middle when it lies low (`flash_centre`)
  mut flash_passage : String
  mut flash_centre : Bool
  /// a message the search opened the chat at (ChatMotion.kt foundAt, "" none) and its words marked in it (`found`),
  /// for as long as the chat shows; how far their strokes are drawn in (ms of drawFound's); its first word yet to be
  /// put in the list's middle when it lies low (Chat.kt rememberJump's FOUND)
  mut found_at : String
  mut found_words : Array[String]
  /// how many times what the search opened it at was said (found_at, found_words): what draws it follows
  found_told : @signals.Signal[Int]
  found_drawn : @motion.Anim
  mut found_centre : Bool
  /// its rows and their keys as row_keys last made them, and of what: made again only as one of those changed (a
  /// frame that changed nothing goes over none of its rows); its keys as the list's motion is told them (list_frame)
  mut rows_made : RowsMade?
  mut motion_of : Array[String]
  mut motion_list : String
  mut motion_keys : Array[String]
  /// its rows as last shown, by key and what each shows (ListRows: what came, went and changed worked out by the
  /// list, docs/list-motion.md): the last list made of it's (chat_list_node's)
  mut rows : @ui.ListRows[Entry]
  /// when words sent from here to it land, as their way declared it once their row was placed (-2: not placed yet, -1:
  /// none sent); kept so once they are there, their flight let go (what is drawn of them: nothing of its own here)
  landing : @signals.Computed[Double]
}

///|
/// What row_keys made of a chat's entries (`all`, of view `v`, the list following its end or not, nothing sent from
/// here waiting for its row, no row waiting its turn), and the rows it knew then.
pub struct RowsMade {
  all : Array[Entry]
  v : ChatView
  following : Bool
  rise_ms : Double
  known : Int
  list : Array[Entry]
  keys : Array[String]
}

///|
pub let readings : Map[String, Reading] = {}

///|
pub fn reading_of(key : String) -> Reading {
  match readings.get(key) {
    Some(r) => r
    None => {
      let r = {
        foot_sign: "",
        sent_foot: "",
        head: "",
        head_at: -1,
        placed: false,
        put: false,
        lined: false,
        asked: @signals.signal(-1.0),
        asked_newer: @signals.signal(-1.0, same=fn(a, b) { a == b }),
        latest_asked: false,
        end_asked: @signals.signal(false),
        told: "",
        seen_whole: -1.0,
        top_seq: -1.0,
        bottom_seq: -1.0,
        view_frame: -10,
        state_seen: false,
        view_still: true,
        top_off: 0.0,
        at_end: true,
        told_place: "",
        scale: 1.0,
        jump: false,
        ask: false,
        jump_at: -1.0e9,
        bench: 0,
        bench_phase: 0,
        bench_rows: 0,
        bench_ms: [],
        bench_present: [],
        known: {},
        drawn: false,
        acts: {},
        shown_frame: -10,
        shown_by: None,
        fresh: {},
        came_frame: -10,
        came: {},
        came_n: 0,
        makes_way: {},
        over: "",
        over_frame: -10,
        admitted: {},
        list_read: None,
        newest: "",
        following_row: false,
        follow_key: "",
        sent: {},
        sent_as: {},
        sent_as_told: @signals.signal(0),
        linger: {},
        act_order: {},
        acts_seen: 0,
        lingered: 0,
        linger_said: @signals.signal(0),
        floor: 0.0,
        floor_takers: {},
        floor_laid: {},
        act_room: {},
        act_whole: {},
        floor_frame: -1,
        floor_was: 0.0,
        running: {},
        last_turns: {},
        flash: "",
        flash_lit: @motion.Anim::new(0.0),
        flash_n: 0,
        flash_passage: "",
        flash_centre: false,
        found_at: "",
        found_told: @signals.signal(0),
        found_words: [],
        found_drawn: @motion.Anim::new(0.0),
        found_centre: false,
        rows_made: None,
        motion_of: [],
        motion_list: "",
        landing: @signals.computed(fn(was) {
          match send_flight.get() {
            Some(f) if f.turns == key => if f.placed { f.way.ends() } else { -2.0 }
            _ =>
              match was {
                Some(at) if at >= 0.0 => at
                _ => -1.0
              }
          }
        }, same=fn(a, b) { a == b }),
        motion_keys: [],
        rows: @ui.ListRows::new(),
      }
      readings[key] = r
      r
    }
  }
}

///|
/// Where a chat was left this run (AppState.places, Chat.kt leave): the message at the top of what showed (its seq) and
/// how far its top was below the list's (points); and, left at its end, the newest message then (else -1). It opens
/// there again before where the core says (`at`): the chat's view can outlive its page (opened again before the core
/// lets it go, a minute after: store.ts EVICT_AFTER_MS) and still say where it was opened the first time.
pub(all) struct KeptPlace {
  top : Double
  offset : Double
  bottom : Double
}

///|
pub let kept_places : Map[String, KeptPlace] = {}


///|
/// The key of where a chat stands among its list's rows (Entry::id): one at a time, at its end.
let state_key : String = "state"

///|
/// The list's entries (Chat.kt Messages → all): the page before's spinner, the messages with the unread line over the
/// first unread and what went to Slack after each, the page after's spinner, the outbox, where it stands (said only at
/// its end: none while an agent works), its agents at work.
pub fn entries_of(v : ChatView) -> Array[Entry] {
  let out : Array[Entry] = [Top]
  if v.more {
    out.push(Older)
  }
  // (nothing in it: not a window showing none of it, what it shows before being brought, `more`)
  if v.messages.length() == 0 && v.outbox.length() == 0 && v.elsewhere.length() == 0 && !v.more {
    out.push(Empty)
  }
  for e in v.elsewhere {
    out.push(Sent(e))
  }
  // (each as its row knows it, read off its JSON: none of them made a Message here, a long chat's thousands)
  for i in 0..<v.messages.length() {
    let m = v.messages.row(i)
    match v.unread_line {
      Some(l) if l == m.seq => out.push(Line)
      _ => ()
    }
    out.push(Said(m))
    for e in m.elsewhere {
      out.push(Sent(e))
    }
  }
  if v.newer {
    out.push(Newer)
  }
  for o in v.outbox {
    out.push(Out(o))
  }
  if !v.newer {
    match v.state {
      Some((words, lead, rest)) => out.push(State(words, lead, rest))
      None => ()
    }
  }
  if !v.newer {
    for a in v.agents {
      if a.status == "running" {
        out.push(Working(a))
      }
    }
  }
  out.push(Foot)
  entries_count.val += out.length()
  out
}

///|
// kept across runs: a count for tests (entries_made)
let entries_count : Ref[Int] = Ref(0)

///|
/// How many entries chats' lists were made of so far (entries_of): for a test that counts what a page costs.
pub fn entries_made() -> Int {
  entries_count.val
}

///|
// kept across runs: a count for tests (views_worked)
let views_worked_count : Ref[Int] = Ref(0)

///|
/// How many times a chat's view was worked out (view_of_chat's getter: the core's topic asked for each time): for a
/// test that counts what a page costs.
pub fn views_worked() -> Int {
  views_worked_count.val
}

///|
/// Chat `r`'s view (chat_view), its list's entries and its topic's error: worked out once for each version of what it
/// is made of (the topic, its messages, the chat a new chat became), whoever reads it in a frame (the page, its rows,
/// its side panel, the frame round it, the chats kept: linger_tick), each read after that the one kept (chat_views).
/// Asking for the topic is not free on a device (its params made, written out and looked for among the
/// subscriptions: core_topic, Client::subscribe), and a chat's page reads its view hundreds of times as it is entered
/// or left (its rows' words, its bar, its composer): 185 of a leave's 378 ms on a phone, when each read asked anew
/// (2026-11-05).
pub fn view_of_chat(src : Source, r : ChatRef) -> (ChatView?, Array[Entry], Json?) {
  chat_views.read(chat_key(r), fn(_) { view_of_chat_now(src, r) }, same=fn(a, b) {
    same_view(a.0, b.0) && physical_equal(a.1, b.1) && a.2 == b.2
  })
}

///|
/// Chat `r`'s view let go of as its page is left, before its topic is (chat.mbt chat_left): what read it on the page
/// still follows it till the page is gone, and a view kept would be worked out again as the topic ends, a watch
/// asking whether it changed (signals' check_dirty), and ask the core for the topic anew: the chat subscribed to
/// again as it is left. A read after this works it out anew, the topic asked then.
pub fn chat_view_left(r : ChatRef) -> Unit {
  chat_views.forget(chat_key(r))
  chat_bare_views.forget(chat_key(r))
}

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let chat_views : Kept[(ChatView?, Array[Entry], Json?)] = Kept::new()

///|
fn same_view(a : ChatView?, b : ChatView?) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => physical_equal(x, y)
    (None, None) => true
    _ => false
  }
}

///|
/// Chat `r`'s view as it is now (view_of_chat's getter): what reads the view follows the topic through it, so a page
/// left is told it changed by the topic's end.
fn view_of_chat_now(src : Source, r : ChatRef) -> (ChatView?, Array[Entry], Json?) {
  views_worked_count.val += 1
  let (read, present, error) = chat_read_now(src, r)
  match (read, present, fresh_view(r)) {
    // (the chat a new chat became is never said to be empty: its first message is in it from the frame it was sent,
    // sent_local, while the core has it made and not yet sent to)
    (Some(c), true, Some(_)) => {
      let list = c.entries()
      if list.iter().any(fn(e) { e is Empty }) {
        (Some(c.view), list.filter(fn(e) { !(e is Empty) }), error)
      } else {
        (Some(c.view), list, error)
      }
    }
    (Some(c), true, _) => (Some(c.view), c.entries(), error)
    // the chat a new chat became as its first words were sent, till the core's view of it is read: a chat with
    // nothing in it yet but what was sent from here (its own first view, as the core's will be: views.ts pendingChat)
    (_, _, Some((v, list))) => (Some(v), list, None)
    _ => (None, [], error)
  }
}

///|
/// The chat's view for a reader which does not need its list of entries (messages are made only as they are read):
/// kept as view_of_chat's is, its topic asked for once for each version of it, whoever reads it; what reads it told as
/// it changes (a request decided in its chat: vault_turn_wbtest, its card closing to how it went; signals' flush after a
/// computed, #4026).
pub fn chat_view_now(src : Source, r : ChatRef) -> ChatView? {
  chat_bare_views.read(chat_key(r), fn(_) { chat_view_bare(src, r) }, same=same_view)
}

///|
// kept across runs: as chat_views, let go of with it (chat_view_left)
let chat_bare_views : Kept[ChatView?] = Kept::new()

///|
fn chat_view_bare(src : Source, r : ChatRef) -> ChatView? {
  let (read, present, _) = chat_read_now(src, r)
  match (read, present, fresh_view(r)) {
    (Some(c), true, _) => Some(c.view)
    (_, _, Some((v, _))) => Some(v)
    _ => None
  }
}

///|
/// Follow the topic and its cached view without asking for its entries.
fn chat_read_now(src : Source, r : ChatRef) -> (ChatRead?, Bool, Json?) {
  let params = chat_params(r)
  let topic = (src.topic)("chat", params)
  let read = chat_reads.read(chat_key(r), fn(was) { chat_read(src, params, was) })
  (read, topic.value is Some(Object(_)), topic.error)
}

///|
/// Chat `r`'s view as a frame read it last (view_of_chat), if one did since the last: its topic not asked for (a chat
/// whose page was never drawn, or is left, asks nothing of the core for it).
pub fn chat_kept(r : ChatRef) -> ChatView? {
  match chat_reads.peek(chat_key(r)) {
    Some(Some(c)) => Some(c.view)
    _ => None
  }
}

///|
/// Chat `r`'s key among the chats read (chat_reads): its params', each chat's own.
fn chat_key(r : ChatRef) -> String {
  r.station + "\n" + r.session
}

///|
/// A chat as chat_read made it: its view and its list's entries.
priv struct ChatRead {
  view : ChatView
  /// its entries, made only for a reader that asks for them (ChatRead::entries), once for each version
  mut list : Array[Entry]?
  /// what of its value its entries are made of besides its messages (entry_sign)
  sign : String
}

///|
/// Make the complete entry array only for a caller which asks for it, once per view.
fn ChatRead::entries(self : ChatRead) -> Array[Entry] {
  match self.list {
    Some(list) => list
    None => {
      let list = entries_of(self.view)
      self.list = Some(list)
      list
    }
  }
}

///|
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let chat_reads : Kept[ChatRead?] = Kept::new()

///|
/// A chat's view and its list's entries, as the core's `chat` topic gives them (its value but its messages) and its
/// messages as their list has them (Source.list: each made as it is read, the same ones as before where that is the
/// same list); worked out again as either changes. A made-up core's: its messages made of the topic's value.
fn chat_read(src : Source, params : Map[String, Json], was : ChatRead??) -> ChatRead? {
  let topic = (src.topic)("chat", params)
  guard topic.value is Some(Object(_) as v) else { return None }
  let messages = match (src.list)("chat", params, ["messages"], message_fields()) {
    Some(rows) =>
      match was {
        Some(Some(w)) if physical_equal(w.view.messages.rows, rows) => w.view.messages
        _ => ChatMessages::of(rows)
      }
    None =>
      match was {
        Some(Some(w)) => ChatMessages::of_value(topic.value, was=w.view.messages)
        _ => ChatMessages::of_value(topic.value)
      }
  }
  // (followed: worked out again as one comes, goes or is set; what is made of one gone let go of)
  let changed = messages.read_changes()
  let view = chat_view_of(v, messages)
  let sign = entry_sign(v)
  // (its entries as they were where nothing they are made of changed: a key typed in its composer, a read told, its
  // title, change the chat's value and none of its rows; not gone through again, a long chat's thousands)
  let list = match was {
    Some(Some(w)) if changed.is_empty() && physical_equal(w.view.messages, messages) && w.sign == sign => w.list
    _ => None
  }
  Some({ view, list, sign })
}

///|
/// What of a chat's value (its topic's, but its messages) its list's entries are made of (entries_of): what the page
/// before and after say, where the unread line is, what went elsewhere, its outbox, where it stands and its agents.
fn entry_sign(v : Json) -> String {
  let s = Some(v)
  let part = fn(k : String) {
    match field(s, k) {
      Some(j) => j.stringify()
      None => ""
    }
  }
  ["more", "newer", "unreadLine", "elsewhere", "outbox", "stateText", "stateLead", "stateRest", "agents"]
  .map(part)
  .join("\u{1}")
}

///|
/// A message's key in its chat, as the core keys them (client/core-ts collections.ts: `seq` and `outgoing`).
fn message_key(m : Json) -> String {
  let s = Some(m)
  number(s, "seq").to_string() + "\u{1}" + text(s, "outgoing")
}

///|
/// An activity whose agent's turn ended stays this long, then is gone from the list, leaving it as any row does
/// (ListRows::leave: fading where it is, then its room closing).
pub let linger_ms : Double = 600.0

///|
/// An agent whose turn ended, its activity still shown (with_lingering): from when (the moment its turn was seen over).
pub(all) struct Lingering {
  agent : Agent
  /// which of the chat's lingerings it is (Reading.lingered)
  id : Int
  at : Double
}

///|
/// When agent `k`'s line lingering as `l` is gone: linger_ms after its turn was seen over, or after its last message
/// came out of its avatar where that was later (as that was declared to end: emit_ended); none while its messages still
/// come out of it (`held`).
fn linger_ends(l : Lingering, em : Emits, k : String, held : Bool) -> Double {
  if held { @double.infinity } else { dmax(l.at, emit_ended(em, k)) + linger_ms }
}

///|
/// Each frame, before any page is built, of each chat kept whose list shows nowhere (one that shows is played by its
/// node: chat_play_node): from its own data (its agents running), whose activity stays a moment as its turn ends, gone
/// once its time is (chat_play: a function of the time, whichever frame sees it); a chat under another page lingers on
/// the time that goes by, as Chat.kt's. The chat's page draws what it says. `in_front`: the app shown (what is said then is
/// watched).
pub fn linger_tick(c : @ui.Ctx, src : Source, in_front~ : Bool) -> Unit {
  for rk, rd in readings {
    // every chat kept whose data the page read: its activities linger on the time that goes by, its page shown or not
    // (not one a message of it drawn elsewhere keeps: its topic never asked for)
    let (station, session) = match rk.find("\u{1}") {
      Some(i) => (rk.view(end_offset=i).to_owned(), rk.view(start_offset=i + 1).to_owned())
      None => continue
    }
    let r : ChatRef = { station, session, title: "", station_name: "" }
    if chat_kept(r) is None {
      continue
    }
    // (one whose list shows is played by its node, at its moments: chat_play_node)
    guard rd.shown_by is None else { continue }
    match chat_view_now(src, r) {
      Some(v) => {
        chat_take(c, rk, rd, v, shown=false, in_front~)
        chat_play(c, rk, rd, shown=false) |> ignore
      }
      None => ()
    }
  }
}

///|
/// Take a chat's data before publishing its rows. Replies waiting for an avatar never enter the list even for an
/// intermediate layout; the activity that just ended is still there to hand them off. Advancing their poses and
/// lingering deadlines belongs to chat_play, at their moments.
pub fn chat_take(c : @ui.Ctx, rk : String, rd : Reading, v : ChatView, shown~ : Bool, in_front~ : Bool) -> Unit {
  let running : Map[String, Agent] = {}
  if !v.newer {
    for a in v.agents {
      if a.status == "running" {
        running[a.key] = a
      }
    }
  }
  // Ended activities still show. Hand them to their lingering state before deciding how answers from this same
  // core update arrive; there is no frame in which their avatars have disappeared.
  for k, a in rd.running {
    if !running.contains(k) && !rd.linger.contains(k) {
      rd.lingered += 1
      rd.linger[k] = { agent: a, id: rd.lingered, at: c.moment() }
      linger_told(rd)
    }
  }
  // A turn begun and over between two ticks stays all the same: its identity, not a frame inside it, says it came.
  if !v.newer {
    for a in v.agents {
      match rd.last_turns.get(a.key) {
        Some(was) if a.last_turn != was &&
          a.last_turn != "" &&
          !running.contains(a.key) &&
          !rd.running.contains(a.key) &&
          !rd.linger.contains(a.key) => {
          rd.lingered += 1
          rd.linger[a.key] = { agent: a, id: rd.lingered, at: c.moment() }
          linger_told(rd)
        }
        _ => ()
      }
      rd.last_turns[a.key] = a.last_turn
    }
  }
  rd.running.clear()
  for k, a in running {
    rd.running[k] = a
  }
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt, ChatMotion.kt). (Once under way, it goes on while the end is near: the answer
  // coming in grows the list under the reader, who is a moment short of its end until the list follows; only
  // scrolled away, as the way to the newest shows, it ends.)
  // (played on while its page shows: under another page it waits where it is, as before)
  let em = emits_of(rk)
  if shown {
    let playing = em.current is Some(_) || em.queue.length() > 0
    let watched = (rd.at_end || rd.following_row || (playing && !rd.jump)) && !v.newer && in_front
    if watched != em.watched {
      em.watched = watched
      em.changed()
    }
    let showing : Map[String, Bool] = {}
    for k, _ in running {
      showing[k] = true
    }
    for k, _ in rd.linger {
      showing[k] = true
    }
    emit_take(c, em, v, showing)
  }
}

///|
/// A chat's own motions played on to the logic's moment, from the moments each was declared to end, whichever frame (or
/// none) sees it: its list's turns, what comes out of its avatars (`shown`: its list laid out somewhere), its agents'
/// lines lingering. Said where its chat is taken (chat_take) and at the moment the next of them is due, which it gives
/// (inf: none due): played by its list's node (chat_play_node), or, a chat not shown, as time goes by (linger_tick).
pub fn chat_play(c : @ui.Ctx, rk : String, rd : Reading, shown~ : Bool) -> Double {
  let em = emits_of(rk)
  let now = c.moment()
  let mut due = @double.infinity
  if shown {
    let turns = turns_of(rk)
    turns.now = now
    turns.step(c, match rd.list_read {
      Some(lr) =>
        match lr.info() {
          Some(i) => i.glide_rest
          None => -1.0
        }
      None => -1.0
    })
    // words sent from here: their landing as declared (-2: not laid out yet, -1 none), kept once they are there
    // (emit_step)
    let sending = @signals.untracked(fn() { rd.landing.get() })
    due = dmin(due, emit_step(c, rk, em, turns, sending))
  }
  // (an agent's line stays whole while its messages still come out of its avatar (ChatMotion.keeps), then linger_ms)
  let keeps = emit_keeps(em)
  let over : Array[String] = []
  for k, l in rd.linger {
    if rd.running.contains(k) {
      over.push(k)
      continue
    }
    let ends = linger_ends(l, em, k, keeps.contains(k))
    if ends <= now {
      over.push(k)
    } else {
      due = dmin(due, ends)
    }
  }
  for k in over {
    rd.linger.remove(k)
  }
  if !over.is_empty() {
    linger_told(rd)
  }
  due
}

///|
/// One came to linger or went: told to what reads which do (with_lingering).
fn linger_told(rd : Reading) -> Unit {
  rd.linger_said.set(@signals.untracked(fn() { rd.linger_said.get() }) + 1)
}

///|
/// The list with the activities of agents whose turn just ended, kept a moment (Chat.kt: 600 ms, then fading 220).
pub fn with_lingering(rd : Reading, list : Array[Entry]) -> Array[Entry] {
  rd.linger_said.get() |> ignore
  if rd.linger.is_empty() {
    return acts_in_order(rd, list)
  }
  // after the running ones, before the foot
  let out = list.copy()
  let foot = match out.last() {
    Some(Foot) => out.pop()
    _ => None
  }
  for _, l in rd.linger {
    out.push(Working(l.agent))
  }
  match foot {
    Some(f) => out.push(f)
    None => ()
  }
  acts_in_order(rd, out)
}

///|
/// `list` with its agents' lines (at its end, before its foot) in the order they first came (Reading's `act_order`):
/// the list itself where they are so already.
fn acts_in_order(rd : Reading, list : Array[Entry]) -> Array[Entry] {
  let mut end = list.length()
  if end > 0 && list[end - 1] is Foot {
    end = end - 1
  }
  let mut start = end
  while start > 0 && list[start - 1] is Working(_) {
    start = start - 1
  }
  let order = fn(e : Entry) {
    let k = e.id()
    match rd.act_order.get(k) {
      Some(n) => n
      None => {
        rd.acts_seen += 1
        rd.act_order[k] = rd.acts_seen
        rd.acts_seen
      }
    }
  }
  let mut sorted = true
  for i in start..<end {
    if i > start && order(list[i - 1]) > order(list[i]) {
      sorted = false
    }
  }
  if sorted {
    return list
  }
  let out = list.copy()
  let block = out[start:end].to_array()
  block.sort_by(fn(a, b) { order(a).compare(order(b)) })
  for i, e in block {
    out[start + i] = e
  }
  out
}

///|
/// The room of each agent's line in the list as it was last laid out whole (its own room open, not opening: read back,
/// laid out otherwise the frame is built again), what it leaves as a floor when it goes (row_keys).
pub fn act_rooms(c : @ui.Ctx, rd : Reading, key : String, keys : Array[String]) -> Unit {
  for k, whole in rd.act_whole {
    if !whole {
      continue
    }
    // (looked for from the end, where the agents' lines are)
    for i = keys.length() - 1; i >= 0; i = i - 1 {
      if keys[i] == k {
        match c.list_row_height(key, i) {
          Some(h) => rd.act_room[k] = h
          None => ()
        }
        break
      }
    }
  }
}

///|
/// How tall the floor agents' lines left is in this build (Chat.kt floor, web's): what they left, less the rows that
/// came in since, each as tall as last laid out (read back: laid out otherwise, the frame is built again). As a frame
/// begins, from what the frame before laid out: once they fill it, it is gone; one gone from the list (an outbox entry
/// become its message, by another key), its height is taken for good.
pub fn floor_of(c : @ui.Ctx, rd : Reading, key : String, keys : Array[String]) -> Double {
  // (how much of it is still kept: the rows making way for the line gone, from the frame it went)
  let out = @motion.anim(c, "floor/out/" + key, 0.0, global=true)
  if rd.floor <= 0.0 {
    rd.floor = 0.0
    rd.floor_takers.clear()
    rd.floor_laid.clear()
    rd.floor_was = 0.0
    out.snap(0.0)
    return 0.0
  }
  if rd.floor_frame != c.frame_number() {
    rd.floor_frame = c.frame_number()
    rd.floor_laid.clear()
    let mut took = 0.0
    for k, h in rd.floor_takers {
      rd.floor_laid[k] = h
      took += h
    }
    if took >= rd.floor {
      rd.floor = 0.0
      rd.floor_takers.clear()
      rd.floor_laid.clear()
      return 0.0
    }
  }
  let gone = rd.floor_takers.keys().filter(fn(k) { !keys.contains(k) }).collect()
  for k in gone {
    rd.floor = rd.floor - rd.floor_laid.get(k).unwrap_or(0.0)
    rd.floor_takers.remove(k)
    rd.floor_laid.remove(k)
  }
  let mut took = 0.0
  for i, k in keys {
    if rd.floor_takers.contains(k) {
      let h = c.list_row_height(key, i).unwrap_or(0.0)
      rd.floor_takers[k] = h
      took += h
    }
  }
  // the rows over it making way for the line gone (docs/motion.md kind 3, its cause the line's going): from where they
  // stood, on the rows' spring, nothing dropped at once and no room left empty for good (whether rows came before
  // the line went or after, the list at rest the same)
  if rd.floor > rd.floor_was {
    out.snap(out.get() + rd.floor - rd.floor_was)
    out.animate(0.0, @sf.move_spring)
  }
  rd.floor_was = rd.floor
  // (made way: none left)
  if out.target() == 0.0 && out.get() <= 0.0 {
    rd.floor = 0.0
    rd.floor_was = 0.0
    rd.floor_takers.clear()
    rd.floor_laid.clear()
    return 0.0
  }
  dmax(0.0, dmin(out.get(), rd.floor - took))
}

///|
/// What the chat's page builds from where its list is (messages): whether it is laid out, near its top (the page
/// before asked for) or its end (the page after), at its end, away from it (the way to the newest), and whether the
/// asks waiting are all in view (the bell over the way to the end, jump_to_ask). A scroll changing none of that builds
/// nothing again.
pub(all) struct ListMade {
  laid : Bool
  near_top : Bool
  near_end : Bool
  at_end : Bool
  away : Bool
  asks_seen : Bool
} derive(Eq)

///|
pub fn list_made(info : @ui.ListInfo?, n : Int, ask_rows : Array[Int]) -> ListMade {
  match info {
    Some(i) =>
      {
        laid: i.first >= 0,
        near_top: i.first >= 0 && i.first <= 3,
        near_end: i.last >= n - 4,
        at_end: i.at_end,
        away: i.first >= 0 && i.below > 120.0 && !i.gliding,
        asks_seen: asks_in_view(ask_rows, info),
      }
    None => { laid: false, near_top: false, near_end: false, at_end: false, away: false, asks_seen: false }
  }
}

///|
/// The rows of the asks waiting in the chat (its cards to decide; what an agent needs where the chat's end says it,
/// the core's `stateAsk`; none in a chat archived or not made yet): -1 for one not in the list.
pub fn ask_rows_of(v : ChatView, list : Array[Entry]) -> Array[Int] {
  let asks = if v.archived || v.thread is None { [] } else { v.asks }
  asks.map(fn(seq) {
    let mut at = -1
    for i, e in list {
      match e {
        Said(m) if m.seq == seq && v.state_ask != Some(seq) => {
          at = i
          break
        }
        State(_, _, _) if v.state_ask == Some(seq) => {
          at = i
          break
        }
        _ => ()
      }
    }
    at
  })
}

///|
/// Whether there are asks waiting and every one is in view.
pub fn asks_in_view(ask_rows : Array[Int], info : @ui.ListInfo?) -> Bool {
  ask_rows.length() > 0 &&
  ask_rows.iter().all(fn(at) {
    match info {
      Some(i) => at >= 0 && at >= i.first && at <= i.last
      None => false
    }
  })
}

///|
/// Whether the list follows its end (at it, gliding to it, a row followed): what the rows coming in are built from.
pub fn follows(info : @ui.ListInfo?) -> Bool? {
  match info {
    Some(i) => Some(i.at_end || i.gliding || i.following_row)
    None => None
  }
}

///|
/// Where the reader is, as the list stands once the frame's builds are over (messages): the last message wholly in view
/// between the bar (`top`) and the composer (`room` over the list's foot), while the window is not short of the chat's
/// end (read up to there: a message shown whole on a page in front is read, its end seen or not); the first and the
/// last message in view, and how far the first's top is below the list's.
pub fn read_place(
  rd : Reading,
  v : ChatView,
  list : Array[Entry],
  lr : @ui.ListReader,
  top : Double,
  room : Double,
  frame : Int,
) -> Unit {
  let n = list.length()
  let info = lr.info()
  rd.view_frame = frame
  rd.state_seen = match info {
    Some(i) if i.first >= 0 => {
      let mut k = i.first
      let mut seen = false
      while k <= i.last && k < n {
        if list[k] is State(_, _, _) {
          seen = true
        }
        k = k + 1
      }
      seen
    }
    _ => false
  }
  match (info, lr.place()) {
    (Some(i), Some((first, past, _))) if i.first >= 0 && !v.newer => {
      let foot = i.height - room
      let mut y = -past
      let mut k = first
      while k <= i.last && k < n {
        let h = lr.row_height(k).unwrap_or(0.0)
        match list[k] {
          Said(m) if y >= top - 0.5 && y + h <= foot + 0.5 && m.seq > rd.seen_whole => rd.seen_whole = m.seq
          _ => ()
        }
        y = y + h
        k = k + 1
      }
    }
    _ => ()
  }
  rd.top_seq = match info {
    Some(i) if i.first >= 0 => {
      let mut k = i.first
      while k < n && !(list[k] is Said(_)) {
        k = k + 1
      }
      match list.get(k) {
        Some(Said(m)) => m.seq
        _ => -1.0
      }
    }
    _ => -1.0
  }
  rd.bottom_seq = match info {
    Some(i) if i.first >= 0 => {
      let mut k = if i.last < n { i.last } else { n - 1 }
      while k >= 0 && !(list[k] is Said(_)) {
        k = k - 1
      }
      match list.get(k) {
        Some(Said(m)) => m.seq
        _ => -1.0
      }
    }
    _ => -1.0
  }
  // that message's top, below the list's (the first row in view scrolled past its top, the rows over it)
  rd.top_off = match (info, lr.place()) {
    (Some(i), Some((first, past, _))) if i.first >= 0 => {
      let mut y = -past
      let mut k = first
      while k < n && !(list[k] is Said(_)) {
        y = y + lr.row_height(k).unwrap_or(0.0)
        k = k + 1
      }
      y
    }
    _ => 0.0
  }
}

///|
/// Whether the row of message `seq` (None: where the chat stands, its State row) was on screen as the frame before
/// `frame` left the list, its page shown then: what changes in it is seen changing (Turns::in_turn's `seen`). The
/// chat left and opened again, or the row scrolled away and back, it was not. While the list moves (gliding, a turn
/// under way or waiting) it counts as seen whatever is in view: what goes out of sight goes once the list is still,
/// never changing the rows' places while they are on their way.
pub fn Reading::sees(self : Reading, frame : Int, seq : Double?) -> Bool {
  if self.view_frame != frame - 1 {
    return false
  }
  if !self.view_still {
    return true
  }
  match seq {
    Some(s) => self.top_seq >= 0.0 && s >= self.top_seq && s <= self.bottom_seq
    None => self.state_seen
  }
}

///|
/// The rows in the list and their keys, as they move (a message sent from here keeps its outbox row's: Chat.kt
/// sentAs), and which are new: what comes while the list follows its end and the chat shows, not caught up on (Chat.kt
/// arrived, caught). What comes then (a message simply coming in, an agent's line, an outbox entry) comes in its turn
/// among what changes the list's height (turns.mbt, Chat.kt newcomers), kept out of the list till then. What was sent
/// from here never waits: in the list the frame it is sent, before the core has it (LocalSent).
pub fn row_keys(
  c : @ui.Ctx,
  rd : Reading,
  rk : String,
  v : ChatView,
  all : Array[Entry],
  key : String,
  turns : Turns,
  em : Emits,
  flight : SendFlight?,
  rise_ms~ : Double,
) -> (Array[Entry], Array[String]) {
  let info = c.list_info_as(key, follows)
  let following = match info {
    Some(i) => i.at_end || i.gliding || i.following_row
    None => true
  }
  rd.following_row = match info {
    Some(i) => i.following_row
    None => false
  }
  rd.list_read = Some(c.list_reader(key))
  rd.foot_sign = if ask_clears(v) { "+ask" } else { "" }
  // the same entries of the same view as the last frame's, the list following as it did, nothing sent from here
  // waiting for its row and no row for its turn (then and now): what it made then, its rows not gone over again
  let sending = sending_of(rk)
  match rd.rows_made {
    Some(m) if rd.drawn &&
      physical_equal(m.all, all) &&
      physical_equal(m.v, v) &&
      m.following == following &&
      m.rise_ms == rise_ms &&
      m.known == rd.known.length() &&
      sending.is_empty() &&
      turns.waiting.is_empty() => return shown_rows(c, rd, m.list, m.keys, !v.newer, flight)
    _ => ()
  }
  let made_whole = sending.is_empty() && turns.waiting.is_empty()
  let given = all
  let (all, all_keys, came_new) = sent_rows_taken(rd, rk, v, all, flight)
  // a row gone from the chat's end as its turns go: an agent's line (its turn over, its moment stayed), where the chat
  // stands (a person wrote, an agent took it up). An agent's line is new to the list again: its next turn comes in as
  // its first did, its room opening, not there at once (its key is its agent's, the same each turn)
  if !v.newer && !rd.acts.is_empty() {
    let gone = rd.acts.keys().filter(fn(k) { !all_keys.contains(k) }).collect()
    for k in gone {
      rd.acts.remove(k)
      if k != state_key {
        rd.known.remove(k)
        rd.admitted.remove(k)
      }
      // (its room closes as it stays in the list going: Reading's `going`)
      rd.act_room.remove(k) |> ignore
      rd.act_whole.remove(k) |> ignore
    }
  }
  if rd.drawn && following {
    for i, e in all {
      let k = all_keys[i]
      if rd.known.contains(k) || rd.admitted.contains(k) {
        continue
      }
      let comes = match e {
        Working(a) => a.started
        // (what was sent from here is in the list at once)
        Out(o) => !local_sent(o)
        // (one out of an avatar comes out of it instead)
        Said(m) => m.said && !emit_goes(em, m.seq)
        _ => false
      }
      if comes {
        rd.admitted[k] = true
        if e is Working(_) {
          rd.acts[k] = true
        }
        match e {
          // (after what closes under a post as its agent starts)
          Working(_) => turns.admit(c, k, working_turn_ms, after=true)
          _ => turns.admit(c, k, rise_ms)
        }
      }
    }
  }
  let list : Array[Entry] = []
  let keys : Array[String] = []
  for i, e in all {
    let k = all_keys[i]
    if turns.waiting.contains(k) {
      continue
    }
    list.push(e)
    keys.push(k)
  }
  if rd.drawn && following && rd.floor > 0.0 {
    for k in came_new {
      rd.floor_takers[k] = 0.0
    }
  }
  if rd.drawn && following {
    // (what came now, and the last row that was there before it: the end it comes in over, if under it)
    let mut came_last = -1
    let mut was_last = -1
    for i, e in list {
      let caught = match e {
        Said(m) => !m.said
        Working(a) => !a.started
        Top | Foot => true
        _ => false
      }
      if !rd.known.contains(keys[i]) && !caught {
        rd.fresh[keys[i]] = true
        rd.came_frame = c.frame_number()
        // (out of whose avatar; words sent from here fly in, as nothing coming)
        let from = match e {
          Out(o) if local_sent(o) => None
          Said(m) =>
            match em.current {
              Some(t) if t.seq == m.seq => Some(t.agent)
              _ => Some("")
            }
          _ => Some("")
        }
        match from {
          Some(a) => {
            rd.came_n += 1
            rd.came[keys[i]] = (rd.came_n, a)
            came_last = i
          }
          None => ()
        }
        // what comes in takes back the room an agent's line left (Chat.kt floor)
        if rd.floor > 0.0 {
          rd.floor_takers[keys[i]] = 0.0
        }
      } else if !(e is (Top | Foot)) {
        was_last = i
      }
    }
    if came_last >= 0 && was_last > came_last {
      rd.over = keys[came_last]
      rd.over_frame = c.frame_number()
    }
  }
  // what each row that makes way saw come in over it last: the newest of the rows over it that came, by whose avatar
  // they came out of (an agent's line not for its own: its avatar away, it comes back to where the line now is)
  let newest : Map[String, (Int, String)] = {}
  rd.makes_way.clear()
  for i, k in keys {
    match list[i] {
      Working(_) | Out(_) => {
        let own = match list[i] {
          Working(a) => a.key
          _ => "\u{1}"
        }
        let mut best = (0, "")
        for from, n in newest {
          if from != own && n.0 > best.0 {
            best = n
          }
        }
        rd.makes_way[k] = best.1
      }
      _ => ()
    }
    match rd.came.get(k) {
      Some((n, from)) =>
        match newest.get(from) {
          Some((m, _)) if m >= n => ()
          _ => newest[from] = (n, k)
        }
      None => ()
    }
    rd.known[k] = true
    if list[i] is (Working(_) | State(_, _, _)) {
      rd.acts[k] = true
    }
  }
  rd.drawn = true
  rd.rows_made = if made_whole && turns.waiting.is_empty() {
    Some({ all: given, v, following, rise_ms, known: rd.known.length(), list, keys })
  } else {
    None
  }
  // (what changes comes, goes and changes on the list's way whether the list follows its end or is read up it: the
  // row read from stays where it shows, what is over and under it moving away from it, docs/list-motion.md; nothing
  // at once in view, 2026-10-31 the user: 「有一些是凭空出现的，有一些是凭空消失的」)
  shown_rows(c, rd, list, keys, !v.newer, flight)
}

///|
/// A chat's rows as they show (`list`, `keys`): with what went from them in among them while its room closes, what
/// came and changed said from now while its newest are in it (docs/list-motion.md); what words sent fly to opening its
/// room as long as their flight.
fn shown_rows(
  c : @ui.Ctx,
  rd : Reading,
  list : Array[Entry],
  keys : Array[String],
  watched : Bool,
  flight : SendFlight?,
) -> (Array[Entry], Array[String]) {
  // words sent let go of the composer as they leave it, a share of their way on (flight_placed): their row opens
  // from then, the composer's room closes from then (composer_hold), as long, so that what is over them goes one way;
  // their row opening from the moment they were sent, the room after, on a curve of its own, had it go up, then down
  // (set out this frame as their row is in the list, when not yet: flight_placed); what else changes the rows' heights
  // from now till then (a card they answer closing) sets out with them, one way
  let now = c.moment()
  let mut told_foot = false
  let leaving = match flight {
    Some(f) if !f.carried => {
      if f.placed && rd.sent_foot != "/" + f.key {
        rd.sent_foot = "/" + f.key
        told_foot = true
      }
      let set_out = if f.placed { f.set_out } else { now }
      Some((f.key, set_out + flight_settle * f.ms, (1.0 - flight_settle) * f.ms))
    }
    _ => None
  }
  rd.rows.rows(
    c,
    // (given anew as the Foot row's version changes with them: the same arrays as the frame before are not looked over)
    if told_foot { keys.copy() } else { keys },
    list,
    fn(e) {
      match e {
        Foot => "foot" + rd.foot_sign + rd.sent_foot
        _ => shown_sign(e)
      }
    },
    watched~,
    ms=fn(k) {
      match (leaving, flight) {
        (Some((key, _, ms)), _) if key == k || k == "foot" => Some(ms)
        (_, Some(f)) if f.key == k => Some(flight_ms_of(f))
        _ => None
      }
    },
    from=fn(k) {
      match leaving {
        Some((_, at, _)) if at > now => Some(at)
        _ => None
      }
    },
    // (what was said before it was shown, caught up on: there at once; an agent's line comes as it shows, at work or
    // not yet, its room opening: there at once, it put every row over it up by its height in one frame, rows_steady.mbt)
    comes=fn(e) {
      match e {
        Said(m) => m.said
        Working(_) => true
        Top | Foot => false
        _ => true
      }
    },
  )
}

///|
/// The newest row (a message, an outbox entry; not an agent's line, which folds away) come while the list follows its
/// end: followed from its top, its top follow_margin under the bar (Chat.kt newestKey, Follow.kt anchor), not past its
/// end; the row kept by its key as rows come and go round it. The viewer's own (an outbox entry, a message of theirs)
/// is not read from its start: they wrote it, and the list follows on to its end, its pictures and the agent's line
/// under it (the web's Chat.tsx: what comes with its agent's activity after it goes on to the end).
pub fn follow_newest(c : @ui.Ctx, rd : Reading, list : Array[Entry], keys : Array[String], key : String, top~ : Double) -> Unit {
  // (the last that is not one of those: looked for from the end)
  let mut at = -1
  for i = list.length() - 1; i >= 0; i = i - 1 {
    match list[i] {
      State(_, _, _) | Working(_) | Foot | Newer => ()
      _ => {
        at = i
        break
      }
    }
  }
  let newest = if at >= 0 { keys[at] } else { "" }
  let info = c.list_info_as(key, follows)
  let following = match info {
    Some(i) => i.at_end || i.gliding || i.following_row
    None => false
  }
  let came = rd.placed && rd.newest != "" && newest != rd.newest && following
  let at_end = info is Some(i) && i.at_end
  if came && at >= 0 && own_row(list[at]) && at_end {
    rd.follow_key = ""
    c.list_follow_from(key, -1)
  } else if came {
    rd.follow_key = newest
  }
  rd.newest = newest
  // (by its index as the rows stand now, while the list holds it: the reader's scroll lets it go)
  if came || rd.following_row {
    // (looked for from the end, where the newest are)
    for i = keys.length() - 1; i >= 0; i = i - 1 {
      if keys[i] == rd.follow_key {
        // the viewer's own, sent from up the list: glided to as a row followed is (its words flying there), then on
        // to the end from there
        if own_row(list[i]) && at_end && !came {
          rd.follow_key = ""
          c.list_to_end(key)
        } else {
          c.list_follow_from(key, i, margin=top + follow_margin)
        }
        break
      }
    }
  }
}

///|
/// Whether entry `e` is the viewer's own words: an outbox entry, or a message of theirs.
fn own_row(e : Entry) -> Bool {
  match e {
    Out(_) => true
    Said(m) => m.mine
    _ => false
  }
}

///|
/// How far under the list's room at its top a row followed from its top stops (Chat.kt followMargin).
pub let follow_margin : Double = 12.0

///|
pub let flash_held : Ref[Bool] = Ref(false)

///|
/// A message gone to flashes (ChatMotion.kt flash): the accent's ground in over `flash_in_ms` on Ease.Out, held to
/// `flash_held_ms`, gone by `flash_ms` on the standard curve.
pub let flash_in_ms : Double = 160.0

///|
pub let flash_held_ms : Double = 900.0

///|
pub let flash_ms : Double = 1700.0

///|
/// When the flash of the messages gone to (in every chat read) is over (the frames' clock; -1: none flashes): a test
/// runs to it after opening a chat at a message (a notification tapped, a decision's post).
pub fn flash_rest() -> Double {
  let mut end = -1.0
  readings.each(fn(_, rd) { if rd.flash_lit.ends_at() > end { end = rd.flash_lit.ends_at() } })
  end
}

///|
/// The flash of the message gone to, all of its way said as it starts.
pub fn flash_start(rd : Reading) -> Unit {
  rd.flash_n += 1
  rd.flash_lit.snap(0.0)
  rd.flash_lit.animate(
    0.0,
    @motion.keyframes_to(
      [1.0, 1.0, 0.0],
      duration=flash_ms,
      times=[0.0, flash_in_ms / flash_ms, flash_held_ms / flash_ms, 1.0],
      eases=[
        fn(t) { @ui.Ease::Out.at(t) },
        fn(t) { t },
        fn(t) { @ui.Ease::Leave.at(t) },
      ],
    ),
  )
}

///|
/// How much a message gone to is lit now (flash_start); 0 for any other message. With motion reduced it is lit whole
/// for `flash_ms`, then not: less motion, not less said (which message it went to).
pub fn flash_of(c : @ui.Ctx, rd : Reading, ts : String) -> Double {
  if rd.flash == "" || rd.flash != ts {
    return 0.0
  }
  if flash_held.val {
    return 1.0
  }
  if @ui.reduced_motion() {
    return if @kit.after(c, "chat-flash/\{rd.flash_n}", true, flash_ms) { 0.0 } else { 1.0 }
  }
  rd.flash_lit.get()
}

///|
/// MBUI_CHAT_AT_END=1: a chat opens at its end, whatever the core says of where it was left (scripted runs).
pub let at_end_env : Ref[Int] = { val: -1 }

///|
pub fn at_end_asked() -> Bool {
  if at_end_env.val < 0 {
    at_end_env.val = if @ui.env("MBUI_CHAT_AT_END") == "1" { 1 } else { 0 }
  }
  at_end_env.val == 1
}

///|
/// Tells the core the chat shows, its end seen or not (Chat.kt: `client.focus` with `chat`), and the last message seen
/// whole (`seen`), as either changes; it marks what is read and where the unread line goes. Never with
/// Source.readonly.
pub fn tell_focus(
  src : Source,
  r : ChatRef,
  v : ChatView,
  rd : Reading,
  seen : Bool,
  whole : Double,
) -> Unit {
  if src.read_only {
    return
  }
  let said = "\{seen} \{whole}"
  if rd.told == said {
    return
  }
  rd.told = said
  let chat = focus_chat(r, v, Some(seen))
  if whole >= 0.0 {
    match chat {
      Object(o) => o["seen"] = Json::number(whole)
      _ => ()
    }
  }
  (src.call)("client.focus", { "chat": chat }, fn(_) {  })
}

///|
/// Chat `r` (its view `v`) shown short of its end: its latest page in place of what shows (`chat.latest`; Chat.kt
/// atLatest), its list at its end as it comes (list_after). Asked as the way to the newest is pressed, and as words are
/// sent: they go at the chat's end, not after what was being read.
pub fn chat_latest(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, what : String) -> Unit {
  guard v.newer && v.thread is Some(th) else { return }
  let rd = reading_of(r.station + "\u{1}" + r.session)
  rd.latest_asked = true
  let station = r.station
  c.tell("chat.latest/" + r.station + "/" + r.session, fn() {
    act(src, what, "", "chat.latest", { "station": Json::string(station), "thread": Json::number(th) }, failed=fn() {
      rd.latest_asked = false
    })
  })
}

///|
pub fn focus_chat(r : ChatRef, v : ChatView, end : Bool?) -> Json {
  let o : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(r.session),
  }
  match v.thread {
    Some(th) => o["thread"] = Json::number(th)
    None => ()
  }
  match end {
    Some(e) => o["end"] = Json::boolean(e)
    None => ()
  }
  Json::object(o)
}

///|
/// Where the chat is, told the core (`chat.place`, Chat.kt leave): the message at the top and how far its top is below
/// the list's (in the screen's pixels, as Android's app tells it), none at its end; told again only where that moved.
pub fn tell_place(src : Source, r : ChatRef, v : ChatView, rd : Reading) -> Unit {
  // kept here too, for opening it again this run (Chat.kt leave: app.places)
  if rd.top_seq >= 0.0 {
    kept_places[r.station + "\u{1}" + r.session] = {
      top: rd.top_seq,
      offset: rd.top_off,
      bottom: if rd.at_end {
        match v.messages.last() {
          Some(m) => m.seq
          None => -1.0
        }
      } else {
        -1.0
      },
    }
  }
  guard v.thread is Some(th) && !src.read_only else { return }
  let scale = rd.scale
  let place : Map[String, Json] = { "station": Json::string(r.station), "thread": Json::number(th) }
  if !rd.at_end && rd.top_seq >= 0.0 {
    place["seq"] = Json::number(rd.top_seq)
    place["offset"] = Json::number((rd.top_off * scale).round())
  }
  let said = Json::object(place).stringify()
  if said == rd.told_place {
    return
  }
  rd.told_place = said
  (src.call)("chat.place", Json::object(place), fn(_) {  })
}

///|
/// Whether the composer's room under chat list `rd`'s rows is let go by words sent (`flight`, the list's this frame) as
/// its rows were given this frame: its Foot row told so (shown_rows), its room laid out where it comes to stand.
pub fn sent_let_go(rd : Reading, flight : SendFlight?) -> Bool {
  match flight {
    Some(f) => f.placed && !f.carried && rd.sent_foot == "/" + f.key
    None => false
  }
}

///|
/// What a chat's list is made of this frame, as both frames make it, before they draw it (sfapp's messages, sfdesk's
/// chat_list): its rows and their keys (`read`, its entries; those coming out of an avatar held out of it till their
/// turn), its turns and its messages out of avatars played on, the list following its newest, words sent flying from
/// the composer of draft `draft`, whether what comes at its end glides, and the page before come in above what is
/// in view keeping it where it is. `rise_ms`, `top`, `in_front`: as row_keys', follow_newest's,
/// chat_play's.
pub fn list_frame(
  c : @ui.Ctx,
  r : ChatRef,
  v : ChatView,
  read : Array[Entry],
  key~ : String,
  draft~ : String,
  rise_ms~ : Double,
  top~ : Double,
  in_front~ : Bool,
) -> ListFrame {
  let rd = reading_of(r.station + "\u{1}" + r.session)
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt, ChatMotion.kt)
  // (taken and played on, before the page is built, by linger_tick)
  let ek = r.station + "\u{1}" + r.session
  let em = emits_of(ek)
  // (shown each frame its list is: built, or kept as its build left it and drawn again, as what a build marks used is
  // marked again: linger_tick plays it on then)
  rd.shown_frame = c.frame_number()
  @ui.built_used(fn() { rd.shown_frame = @ui.current().frame_number() })
  chat_take(c, ek, rd, v, shown=true, in_front~)
  chat_play(c, ek, rd, shown=true) |> ignore
  let read = if em.queue.length() > 0 || em.current is Some(_) {
    read.filter(fn(e) {
      match e {
        Said(m) => !emit_held(em, m.seq)
        _ => true
      }
    })
  } else {
    read
  }
  let turns = turns_of(ek)
  let (list, keys) = row_keys(
    c,
    rd,
    ek,
    v,
    with_lingering(rd, read),
    key,
    turns,
    em,
    flight_of(draft),
    rise_ms~,
  )
  follow_newest(c, rd, list, keys, key, top~)
  flight_frame(c, draft)
  let flight = flight_of(draft)
  // (the first of what was sent from here not in the chat yet: a message out of an avatar comes in over it, emit.mbt;
  // the outbox lies at the list's end, before where it stands, its agents at work and its foot (entries_of): looked for
  // from there, not through a long chat's thousands of messages each frame)
  let mut out_at = -1
  let mut i = list.length() - 1
  while i >= 0 {
    match list[i] {
      Out(_) => out_at = i
      State(_, _, _) | Working(_) | Foot => ()
      _ => break
    }
    i = i - 1
  }
  let out_key = if out_at >= 0 { keys[out_at] } else { "" }
  if out_key != em.out_key {
    em.out_key = out_key
    em.changed()
  }
  // what comes at its end glides after it when it is new to the list (said while it shows, sent, an agent starting:
  // row_keys's fresh), not what was there or caught up on (the chat opened, its pages coming in), at once
  // (not what came in over rows at its end: there at once, the rows over it going up for it, sfpages chat_list)
  let glides = rd.came_frame == c.frame_number() && rd.over_frame != c.frame_number()
  // (the same keys as the last frame's, the same names: the motion goes over none of them)
  if !physical_equal(rd.motion_of, keys) || rd.motion_list != key {
    rd.motion_of = keys
    rd.motion_list = key
    rd.motion_keys = keys.map(fn(k) { key + "\u{1}" + k })
  }
  @motion.list_keys(c, key, rd.motion_keys) |> ignore
  // the first message's row: the page before come in above it, it stays where it is (Chat.kt: the list keeps its
  // first item in view by its key, or the first row after the spinner)
  let mut head = ""
  let mut head_at = -1
  for i, e in list {
    if e is Said(_) {
      head = e.id()
      head_at = i
      break
    }
  }
  // rows came at the top (the page before): what is in view stays where it is, and nothing glides for it
  let older_came = rd.head != "" && head != rd.head && rd.placed
  if older_came {
    for i, e in list {
      if e.id() == rd.head {
        if i != rd.head_at {
          c.list_moved(key, rd.head_at, i - rd.head_at)
        }
        break
      }
    }
  }
  rd.head = head
  rd.head_at = head_at
  { key, rk: ek, rd, em, turns, list, keys, flight, glides, draft }
}

///|
/// A chat's list as list_frame made it this frame (its key, its chat's key, what the page keeps of it, its messages
/// out of avatars, its turns, its rows and their keys, the words sent flying to it, whether what comes at its end
/// glides, and the composer's draft words sent fly from (a new chat's first words carry its list up out of it:
/// flight.mbt flight_carry_shift).
pub(all) struct ListFrame {
  key : String
  rk : String
  rd : Reading
  em : Emits
  turns : Turns
  list : Array[Entry]
  keys : Array[String]
  flight : SendFlight?
  glides : Bool
  draft : String
}

///|
/// What a chat's list does once drawn this frame, as both frames do it (sfapp's messages, sfdesk's chat_list): put in
/// place once (at the unread line `lead` under its `top`, where it was left here, else where the core opened it); a
/// message gone to (a notification's, a search's: `on_found` told of one with its words; ⌘F's, `finding`: the window
/// moved about it once, `find_around` the one asked) brought into view; the page before near its top and the page
/// after near the end of a window short of the chat's asked; what is read and where the reader is (between the bar's
/// foot `bar` and the composer's `room`) told the core. Says what the list is as laid out, the rows of the posts that
/// ask, and whether it is away from its end.
pub fn list_after(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  f : ListFrame,
  top~ : Double,
  lead~ : Double,
  bar~ : Double,
  room~ : Double,
  finding~ : Bool,
  on_found~ : (Reading) -> Unit,
  find_around~ : Ref[Double],
) -> ListAfter {
  let (key, rd, list) = (f.key, f.rd, f.list)
  let n = list.length()
    // put in place once: at the unread line (a few lines of what came before it in view), else where the core opened
    // it, else at its end (where the list starts)
    // (a window showing none of what is before it, its latest page all letters to other chats: nothing to put in
    // place, at its end as it starts, and the page before asked as it comes, below)
    if !rd.placed && (v.messages.length() > 0 || v.more) && !v.unread_above {
      rd.placed = true
    }
    // put in place this build: the list scrolled there is laid out again in this frame (mbui's same-frame rebuild: a
    // list scrolled is a read changed), and what goes by where it is waits for that build
    let mut put_now = false
    if rd.placed && !rd.put && !at_end_asked() {
      rd.put = true
      // where it was left here this run (Chat.kt kept): unless at its end with nothing new since, then at its end
      let newest = match v.messages.last() {
        Some(m) => m.seq
        None => -1.0
      }
      let kept = kept_places.get(r.station + "\u{1}" + r.session)
      let left_at_end = match kept {
        Some(p) => p.bottom >= 0.0 && p.bottom == newest
        None => false
      }
      let opened_at = if left_at_end { None } else { v.at }
      let mut line = -1
      let mut at = -1
      let mut was = -1
      for i, e in list {
        match e {
          Line => line = i
          Said(m) => {
            match opened_at {
              Some(a) if at < 0 && m.seq >= a => at = i
              _ => ()
            }
            match kept {
              Some(p) if !left_at_end && m.seq == p.top => was = i
              _ => ()
            }
          }
          _ => ()
        }
      }
      put_now = line >= 0 || was >= 0 || at >= 0
      rd.lined = line >= 0
      if line >= 0 {
        c.list_scroll_to(key, line, offset=-(top + lead))
      } else if was >= 0 {
        c.list_scroll_to(key, was, offset=-kept.unwrap().offset)
      } else if at >= 0 {
        // where it was left: that message's top as far below the list's as it was (atOffset, the screen's pixels);
        // else its top under the bar
        c.list_scroll_to(key, at, offset=match v.at_offset {
          Some(px) => -(px / c.scale)
          None => -top
        })
      }
    }
    // the unread line come after the list was put in place (what came while the app was away, read after the chat
    // opened: the list was put at its end at once as it came): put there, as it is at a chat opened with it, while the
    // reader is still at the end (Chat.tsx `lined`); not over a message asked to be gone to
    let gk = r.station + "\u{1}" + r.session
    if rd.put && !put_now && !rd.lined {
      let line = list.search_by(fn(e) { e is Line })
      if line is Some(i) {
        rd.lined = true
        let following = match c.list_info_as(key, follows) {
          Some(f) => f.at_end || f.gliding || f.following_row
          None => false
        }
        if following && !go_tos.contains(gk) {
          put_now = true
          c.list_scroll_to(key, i, offset=-(top + lead))
        }
      }
    }
    // opened at a message (a notification's), once the list is in place (the build after it was put there, in the same
    // frame): there, its top under the bar,
    // flashing; the pages before brought in until it is (none left, or it is gone: where the chat opened). Chat.kt
    // LaunchedEffect(host.goTo)
    match go_tos.get(gk) {
      Some(target) if rd.placed && !put_now => {
        let mut at = -1
        let mut first = -1.0
        let mut found = false
        for i, e in list {
          match e {
            Said(m) => {
              if first < 0.0 {
                first = m.seq
              }
              if m.seq == target {
                at = i
                // opened from a search: its words marked in it, nothing flashing (Chat.kt markWords, FOUND)
                match go_to_words.get(gk) {
                  Some(words) => {
                    go_to_words.remove(gk)
                    rd.found_at = m.ts
                    rd.found_words = words
                    found = true
                  }
                  None => {
                    rd.flash = m.ts
                    rd.flash_passage = go_to_passages.get(gk).unwrap_or("")
                    rd.flash_centre = rd.flash_passage != ""
                  }
                }
                break
              }
            }
            _ => ()
          }
        }
        if at >= 0 {
          go_tos.remove(gk)
          go_to_passages.remove(gk)
          if found {
            on_found(rd)
          } else {
            flash_start(rd)
          }
          c.list_scroll_to(key, at, offset=-top)
          @hostapi.log("chat: gone to message \{target.to_int()}")
        } else {
          match v.thread {
            // what ⌘F found, not in the chat's window: the window moved about it (chat.around), once
            Some(thread) if finding =>
              if find_around.val != target {
                find_around.val = target
                c.tell("chat.around/" + gk, fn() {
                  (src.call)(
                    "chat.around",
                    {
                      "station": Json::string(r.station),
                      "thread": Json::number(thread),
                      "seq": Json::number(target),
                    },
                    fn(res) { if res is Err(_) { go_tos.remove(gk) } },
                  )
                })
              }
            Some(thread) if v.more && first > target =>
              if rd.asked.get() != first {
                rd.asked.set(first)
                // (asked once the frame's builds are over)
                c.tell("chat.older/" + gk, fn() {
                  (src.call)(
                    "chat.older",
                    { "station": Json::string(r.station), "thread": Json::number(thread) },
                    fn(res) { if res is Err(_) { go_tos.remove(gk) } },
                  )
                })
              }
            _ => go_tos.remove(gk)
          }
        }
      }
      _ => ()
    }
    // (read back by what the page builds from it: not at every step of a scroll, which changes none of that)
    let ask_rows = ask_rows_of(v, list)
    let info = c.list_info_as(key, fn(i) { list_made(i, n, ask_rows) })
    // near the top: the page before comes in, once per page
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.more && rd.placed && i.first >= 0 && i.first <= 3 => {
        // by entries, not messages: a page of what the chat does not show (letters, edits) moves it too
        let first = match v.first_entry {
          Some(f) => f
          None =>
            match list.iter().find_first(fn(e) { e is Said(_) }) {
              Some(Said(m)) => m.seq
              _ => -1.0
            }
        }
        // (asked once the frame's builds are over, from where the last laid the list out)
        if rd.asked.get() != first {
          c.after_build("older", fn() {
            if rd.asked.get() == first {
              return
            }
            rd.asked.set(first)
            (src.call)(
              "chat.older",
              { "station": Json::string(r.station), "thread": Json::number(thread) },
              fn(res) {
                match res {
                  Err(e) => {
                    rd.asked.set(-1.0)
                    @hostapi.log("chat.older failed: " + text(Some(e), "message"))
                  }
                  _ => ()
                }
              },
            )
          })
        }
      }
      _ => ()
    }
    // its end asked for from one of its rows: gone to, gliding
    if rd.end_asked.get() {
      rd.end_asked.set(false)
      c.list_to_end(key)
    }
    // the chat's latest page come in place of a window short of its end, asked for (chat_latest): at its end at once
    if rd.latest_asked && !v.newer {
      rd.latest_asked = false
      c.list_to_end(key, glide=false)
    }
    // near the end of a window short of the chat's: the page after
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.newer && rd.placed && i.last >= n - 4 => {
        let last = match v.last_entry {
          Some(l) => l
          None =>
            match v.messages.last() {
              Some(m) => m.seq
              None => -1.0
            }
        }
        if rd.asked_newer.get() != last {
          c.after_build("newer", fn() {
            if rd.asked_newer.get() == last {
              return
            }
            rd.asked_newer.set(last)
            (src.call)(
              "chat.newer",
              { "station": Json::string(r.station), "thread": Json::number(thread) },
              fn(res) { if res is Err(_) { rd.asked_newer.set(-1.0) } },
            )
          })
        }
      }
      _ => ()
    }
    // the core told the chat shows, and whether its end does (what is read follows): not on a read-only run
    // (its end in view: not while it glides to rows that came, as Android's Chat.kt has it (endInView, lastLaidOut):
    // rows not in view yet are not read)
    // (nor while a row come at its end still opens its room: not wholly in view yet, its rest read once it is)
    let opening = rd.rows.opening(c)
    let seen = match info {
      Some(i) => !v.newer && i.at_end && !opening
      None => false
    }
    rd.at_end = seen
    // where the reader is, worked out once the frame's builds are over from where its last layout left the list, never
    // read back: told the core (what was seen whole, the place), not drawn (tell_place, tell_focus, after it)
    let lr = c.list_reader(key)
    let frame = c.frame_number()
    // (still: what goes out of sight goes only then, never shifting rows on their way: Reading::sees)
    let tu = turns_of(r.station + "\u{1}" + r.session)
    let still = !c.list_moving(key) && tu.asks.is_empty() && !tu.open
    c.after_build("reading", fn() {
      read_place(rd, v, list, lr, bar, room, frame)
      rd.view_still = still
    })
    // where it is told the core as the reader comes to rest, not only as the chat is left (Chat.kt leave: an app gone
    // from memory never leaves the page)
    rd.scale = c.scale
    if rd.placed && !c.list_moving(key) {
      c.after_build("place", fn() { tell_place(src, r, v, rd) })
    }
    // (told once the frame's builds are over, as the last says it: a build let go of, the frame built again, read the
    // list from before its layout)
    c.after_build("focus", fn() { tell_focus(src, r, v, rd, seen, rd.seen_whole) })
    // the way to the newest: away from the end by more than a corner of the screen, or short of the chat's end (not
    // before the list is first laid out: until then nothing is in view, and the end is not far, only not known)
    let away = match info {
      Some(i) => i.first >= 0 && i.below > 120.0 && !i.gliding
      None => false
    }
  { info, ask_rows, away }
}

///|
/// A chat's list as list_after left it: as laid out, the rows of the posts that ask, whether it is away from its end
/// (by more than a corner of the screen, not gliding).
pub(all) struct ListAfter {
  info : @ui.ListInfo?
  ask_rows : Array[Int]
  away : Bool
}

///|
/// What of a row a change of shows as its height may change (its words, its files, its time come, what is under it
/// decided, how it stands): what it was built from made again the same (the core's view read again) is no change.
pub fn shown_sign(e : Entry) -> String {
  match e {
    // (a message as its list's version of it: set again, a change of it, whatever of it changed; its JSON read again the
    // same, none. Not made a Message for it: every row's sign is asked, a long chat's thousands)
    Said(m) => "m\{m.version}|\{m.joined}"
    Out(o) => "o\{o.text.length()}|\{o.attachments.length()}|\{o.state}|\{o.joined}|\{o.followed}"
    State(a, b, c) => "s" + a + b + c
    Working(_) => "w"
    other => other.id()
  }
}


///|
/// Whether the end of chat `v`'s list keeps clear of the bell floating over it (what waits to be decided there, its
/// end not one: the core's `askClear`): the room under its rows the taller.
pub fn ask_clears(v : ChatView) -> Bool {
  !(v.archived || v.thread is None) && !v.asks.is_empty() && v.ask_clear
}

///|
/// Whether its list shows: its old view built (or drawn again as it was) this frame or the one before, or its node
/// shown now.
pub fn Reading::shown(self : Reading, c : @ui.Ctx) -> Bool {
  self.shown_frame >= c.frame_number() - 1 ||
  (match self.shown_by {
    Some(f) => f()
    None => false
  })
}

///|
/// The rows of chat `rk`'s list (`all`, of view `v`) with what was sent from here (sending_of) in it: each taken by the
/// core's row once it has it (the first of this device's own not there when it was sent, each taken once), going on by
/// the key it was sent as (Reading's sent_as; words flying there, `flight`, go on to it); the rest after the outbox,
/// before the agents' lines and the room under them. Their keys, and those taken now new to the list. What each list
/// shows its rows by (row_keys's, the window's tree's chat_list_node).
pub fn sent_rows_taken(
  rd : Reading,
  rk : String,
  v : ChatView,
  all : Array[Entry],
  flight : SendFlight?,
) -> (Array[Entry], Array[String], Array[String]) {
  let sending = sending_of(rk)
  for o in v.outbox {
    if o.seq >= 0.0 {
      rd.sent[o.seq] = o.id
    }
  }
  for i in 0..<v.messages.length() {
    let m = v.messages.row(i)
    if m.outgoing != "" {
      rd.sent[m.seq] = m.outgoing
    }
  }
  // (the core's keys, what was there as words were sent is told by: sent_before)
  let core_keys = all.map(fn(e) {
    match e {
      Said(m) =>
        match rd.sent.get(m.seq) {
          Some(o) => "o:" + o
          None => e.id()
        }
      _ => e.id()
    }
  })
  let all_keys = core_keys.map(fn(k) { rd.sent_as.get(k).unwrap_or(k) })
  // what was sent from here: the core's row once it has it (the first of this device's own not there when it was
  // sent, each taken once), going on as that row (drawn already: it does not rise in, nor wait a turn; words flying
  // there go on to it)
  let taken : Map[String, Bool] = {}
  let still : Array[LocalSent] = []
  // (the core's rows taken for what was sent before its own row was ever in the list: new to the list's end, they take
  // back the floor as what comes in does)
  let came_new : Array[String] = []
  for l in sending {
    let mut came = ""
    for i, e in all {
      let k = core_keys[i]
      let mine = match e {
        Out(_) => true
        // (after what was there as it was sent: not one of an older page read meanwhile)
        Said(m) => m.mine && !m.system && m.seq > l.newest
        _ => false
      }
      if mine && !l.before.contains(k) && !taken.contains(k) && !rd.sent_as.contains(k) {
        // (the row goes on by the key it was sent as)
        came = "o:" + l.row.id
        rd.sent_as[k] = came
        rd.sent_as_told.set(@signals.untracked(fn() { rd.sent_as_told.get() }) + 1)
        all_keys[i] = came
        taken[k] = true
        break
      }
    }
    if came == "" {
      still.push(l)
      continue
    }
    if !rd.known.contains(came) && !rd.known.contains("o:" + l.row.id) {
      came_new.push(came)
    }
    rd.known[came] = true
    match flight {
      Some(f) if f.key == "o:" + l.row.id => f.key = came
      _ => ()
    }
  }
  sending.clear()
  for l in still {
    sending.push(l)
  }
  // (after the outbox, before the agents' lines and the room under them)
  let all = all.copy()
  let all_keys = all_keys.copy()
  if still.length() > 0 {
    let mut at = all.length()
    for i, e in all {
      if e is (State(_, _, _) | Working(_) | Foot) {
        at = i
        break
      }
    }
    for j, l in still {
      all.insert(at + j, Out(l.row))
      all_keys.insert(at + j, "o:" + l.row.id)
    }
  }
  (all, all_keys, came_new)
}

///|
/// A message's row's key as the page has it before what was sent from here takes it (sent_rows_taken's core keys):
/// the outbox entry it was, else `m:` and its ts.
pub fn said_key(rd : Reading, m : SaidRow) -> String {
  if m.outgoing != "" {
    "o:" + m.outgoing
  } else {
    match rd.sent.get(m.seq) {
      Some(o) => "o:" + o
      None => "m:" + m.ts
    }
  }
}

///|
/// The rows at the end of chat `v`'s list (ChatRows' tail: the page after's spinner, the outbox and what was sent from
/// here not in it yet, where it stands, its agents at work and those lingering, Foot), what was sent from here taken by
/// the core's row once it has it (sent_rows_taken's, the messages looked at from the end: those newer than what was
/// there as it was sent, and the outbox).
pub fn tail_taken(rd : Reading, rk : String, v : ChatView, flight : SendFlight?) -> Array[Entry] {
  for o in v.outbox {
    if o.seq >= 0.0 {
      rd.sent[o.seq] = o.id
    }
  }
  let sending = sending_of(rk)
  if sending.length() > 0 {
    // (what may be one's: the messages newer than the oldest newest any was sent after, from the end; the outbox)
    let oldest = sending.fold(init=@double.infinity, fn(a, l) { if l.newest < a { l.newest } else { a } })
    let recent : Array[SaidRow] = []
    let mut i = v.messages.length() - 1
    while i >= 0 {
      let m = v.messages.row(i)
      if m.seq <= oldest {
        break
      }
      recent.push(m)
      i -= 1
    }
    recent.rev_in_place()
    let taken : Map[String, Bool] = {}
    let still : Array[LocalSent] = []
    for l in sending {
      let came = Ref("")
      let take = fn(k : String) {
        if !l.before.contains(k) && !taken.contains(k) && !rd.sent_as.contains(k) {
          came.val = "o:" + l.row.id
          rd.sent_as[k] = came.val
          rd.sent_as_told.set(@signals.untracked(fn() { rd.sent_as_told.get() }) + 1)
          taken[k] = true
          true
        } else {
          false
        }
      }
      for m in recent {
        if m.mine && !m.system && m.seq > l.newest && take(said_key(rd, m)) {
          break
        }
      }
      if came.val == "" {
        for o in v.outbox {
          if take("o:" + o.id) {
            break
          }
        }
      }
      if came.val == "" {
        still.push(l)
        continue
      }
      rd.known[came.val] = true
      match flight {
        Some(f) if f.key == "o:" + l.row.id => f.key = came.val
        _ => ()
      }
    }
    sending.clear()
    for l in still {
      sending.push(l)
    }
  }
  let out : Array[Entry] = []
  if v.newer {
    out.push(Newer)
  }
  for o in v.outbox {
    out.push(Out(o))
  }
  for l in sending {
    out.push(Out(l.row))
  }
  if !v.newer {
    match v.state {
      Some((words, lead, rest)) => out.push(State(words, lead, rest))
      None => ()
    }
    for a in v.agents {
      if a.status == "running" {
        out.push(Working(a))
      }
    }
  }
  out.push(Foot)
  with_lingering(rd, out)
}
