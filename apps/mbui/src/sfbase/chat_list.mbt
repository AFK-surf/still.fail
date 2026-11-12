// A chat's list as both frames keep it (src/sfapp/chat.mbt the phone's, src/sfdesk's the desktop's): its rows, what
// the page keeps of a chat while it shows (Reading), where it was left, the rows new to it and their turns, the
// agents' lines lingering, the room they leave, what is read and where the reader is, told the core (client.focus,
// chat.place). Each frame draws the rows its own way.

///|
/// An entry of the list, with the room above the first (the bar's) and below the last (the
/// composer's).
pub(all) enum Entry {
  Top
  /// the page before coming, or why it could not be read ("" coming)
  Older(String)
  Empty
  Line
  Said(Message)
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
    Older(_) => "older"
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
  /// how its rows were last given laid out (shown_rows' `laid`): their versions read again as that changes
  mut rows_laid : String
  /// the first message's entry and where it was in the list, the last frame
  mut head : String
  mut head_at : Int
  /// the window's first entry and whether it was short of the chat's end, as its rows were last given (paged_in)
  mut first_was : Double
  mut newer_was : Bool
  /// put in place once (the unread line, where it was opened, or the end)
  mut placed : Bool
  /// put at a message by the app (a go-to), not moved by the reader since: the page before not asked while it stands
  /// there; and where it stands (ListReader::place: the first row in view, how far its top is above the list's), taken
  /// the first time the page before would be asked there
  mut put_there : Bool
  mut put_place : (Int, Double)?
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
  /// its end asked for where the list is not built (an option picked in one of its rows: decision.mbt, where its key
  /// names no list): gone to as what follows the list is built (list_after)
  mut end_asked : Bool
  /// what the core was told of the chat shown, its end seen or not ("" nothing yet)
  mut told : String
  /// the newest message seen whole on this visit (-1 none): read up to there
  mut seen_whole : Double
  /// where the reader is: the message at the top of what shows (-1 none), and whether at the chat's end
  mut top_seq : Double
  /// the message at the foot of what shows (-1 none): what ⌘F starts at lies between
  mut bottom_seq : Double
  /// how far that message's top is below the list's (points: above it, less than 0)
  mut top_off : Double
  mut at_end : Bool
  /// where the core was last told the chat is (chat.place: "" not yet), and the screen's scale it was laid out at
  mut told_place : String
  /// the message at the top as it was last told (its seq, "" at its end)
  mut told_at : String
  mut scale : Double
  /// the jump button: shown since when (or hidden since when), and which
  mut jump : Bool
  mut jump_at : Double
  /// more than the list's own height from the chat's end as its list was last laid out (its last row's bottom that far
  /// under the view's, or the window short of the chat's end): where a go-to in the chat keeps where the reader was
  /// (jump.mbt keep_place_of)
  mut far : Bool
  /// the bell to what waits to be decided: shown
  mut ask : Bool
  /// a scripted scroll through it (MBUI_CHAT_BENCH): frames so far, their times
  mut bench : Int
  /// 0: bringing in the pages before (up to 3000 messages), 1: measuring
  mut bench_phase : Int
  mut bench_rows : Int
  bench_ms : Array[Double]
  bench_present : Array[Double]
  /// the rows drawn so far, by key (arrived); whether it has been
  /// drawn; the rows new to it since, until they show
  known : Map[String, Bool]
  mut drawn : Bool
  /// the rows at its end that go from it as its turns go (by key): its agents' lines, where it stands. One gone leaves
  /// its room as a floor; an agent's line gone is forgotten (row_keys)
  acts : Map[String, Bool]
  /// its list shown (built, or kept as its build left it and drawn again) in the build begun last (`shown`), and in
  /// the build before that (`was_shown`: linger_tick hands one to the other as each build begins); its own data taken
  /// in the build begun last (chat_tick, once a build: what comes out of its avatars played on, its activities'
  /// lingering; let go as each build begins, linger_tick)
  mut shown : Bool
  mut was_shown : Bool
  mut played : Bool
  mut ticked : Bool
  /// the rows new to it, by key, until they show
  fresh : Map[String, Bool]
  /// the rows that came new to it while it shows, by key: the how-manieth (`came_n`), and the agent whose avatar it
  /// came out of ("" none). Words sent from here are not among them: they fly in (flight.mbt)
  came : Map[String, (Int, String)]
  mut came_n : Int
  /// what a row that makes way (an agent's line, what was sent not in the chat yet) last saw come in over it, as last
  /// built ("" nothing): its cause to glide down (sfpages chat_list)
  makes_way : Map[String, String]
  /// the newest row that came in over rows at its end while it was followed (what is at the end stays where it shows,
  /// the rows over it go up for it: sfpages chat_list; "" none yet)
  mut over : String
  /// rows that came into it new (Turns::admit)
  admitted : Map[String, Bool]
  /// the newest row (not an agent's line) as last built, and whether the list follows one from its top (Follow.kt
  /// anchor: a message arriving while it is followed is read from its start)
  mut newest : String
  mut following_row : Bool
  mut follow_key : String
  /// the outbox entries messages were sent from here as, by seq
  sent : Map[Double, String]
  /// the key each row of the core's that what was sent from here became goes on by: the key it had as it was sent
  /// ("o:local:n"), its one identity from the press on (its outbox entry's and its message's keys to it)
  sent_as : Map[String, String]
  /// Told when a local row is taken over, so a viewer opened before that can follow its new core identity.
  sent_as_told : @signals.Signal[Int]
  /// agents whose turn ended, still shown while their messages come out of their avatars: Lingering
  linger : Map[String, Lingering]
  /// the agents' lines in the order they first came to the list, by their keys: they stand so, one whose turn ended
  /// lingering where it was, not put after the others (a line gone past another at once, 2026-11-03)
  act_order : Map[String, Int]
  mut acts_seen : Int
  /// told as one comes to linger or goes (what reads `linger` built again for it: it is said before any page is built)
  linger_said : @signals.Signal[Int]
  /// the room agents' lines left as they went from the list: the list never gets shorter under the
  /// reader. What comes in next takes it back (`floor_takers`: each row by key, as tall as the build last read it;
  /// `floor_laid`: as the frame before laid it out). Each agent's line's room (its row, the gap over it with it) as last
  /// read, by key; whether the floor was counted in the build begun last, from what the layout before it left (once a
  /// build: let go as each begins, linger_tick)
  mut floor : Double
  floor_takers : Map[String, Double]
  floor_laid : Map[String, Double]
  act_room : Map[String, Double]
  act_whole : Map[String, Bool]
  mut floor_counted : Bool
  /// the room as it was last counted (more since: what went new, the rows making way for it from where they stood)
  mut floor_was : Double
  /// the agents running as last drawn
  running : Map[String, Agent]
  /// agents at work whose answer has come out of their avatars this turn, by their last turn then (Agent.last_turn):
  /// their line gone with it till that turn is over (chat_tick)
  answered : Map[String, String]
  /// agents whose answer was here as they were first seen at work: their line kept taking no room, unseen, till it is
  /// gone, what it is subscribed to as it was (with_lingering); till their next turn
  answered_unseen : Map[String, Bool]
  /// each agent's last turn as last ticked (Agent.last_turn)
  last_turns : Map[String, String]
  /// each agent at work, the last message here as it was first seen at work: what of its own comes past it is its answer
  turn_from : Map[String, Double]
  /// each agent not at work, the last message here as it was last ticked so: what of its own came past it came with
  /// its turn (turn_from)
  idle_here : Map[String, Double]
  /// a message gone to (a notification's) and how lit it is (flash_of)
  mut flash : String
  flash_lit : @motion.Anim
  /// flashes started (each one's own hold, with motion reduced)
  mut flash_n : Int
  /// what of it a quote that led there quoted ("" the whole of it: Chat.tsx flashRange), lit alone where it is found in
  /// its words; yet to be put in the list's middle when it lies low (`flash_centre`)
  mut flash_passage : String
  mut flash_centre : Bool
  /// a message the search opened the chat at ("" none) and its words marked in it (`found`),
  /// for as long as the chat shows; how far their strokes are drawn in (ms of drawFound's); its first word yet to be
  /// put in the list's middle when it lies low
  mut found_at : String
  mut found_words : Array[String]
  found_drawn : @motion.Anim
  mut found_centre : Bool
  /// its rows and their keys as row_keys last made them, and of what: made again only as one of those changed (a
  /// frame that changed nothing goes over none of its rows); its keys as the list's motion is told them (list_frame)
  mut rows_made : RowsMade?
  mut motion_of : Array[String]
  mut motion_list : String
  mut motion_keys : Array[String]
  /// its rows as last shown, by key and what each shows (ListRows: what came, went and changed worked out by the
  /// list, mbui's ui/list_size.mbt)
  rows : @ui.ListRows[Entry]
}

///|
/// What row_keys made of a chat's entries (`all`, of view `v`, nothing sent from here waiting for its
/// row), and the rows it knew then.
pub struct RowsMade {
  all : Array[Entry]
  v : ChatView
  rise_ms : Double
  known : Int
  list : Array[Entry]
  keys : Array[String]
}

///|
pub let readings : Map[String, Reading] = Map([])

///|
pub fn reading_of(key : String) -> Reading {
  match readings.get(key) {
    Some(r) => r
    None => {
      let r = {
        foot_sign: "",
        sent_foot: "",
        rows_laid: "",
        head: "",
        head_at: -1,
        first_was: -1.0,
        newer_was: false,
        placed: false,
        put_there: false,
        put_place: None,
        put: false,
        lined: false,
        asked: @signals.signal(-1.0),
        asked_newer: @signals.signal(-1.0, same=fn(a, b) { a == b }),
        latest_asked: false,
        end_asked: false,
        told: "",
        seen_whole: -1.0,
        top_seq: -1.0,
        bottom_seq: -1.0,
        top_off: 0.0,
        at_end: true,
        told_place: "",
        told_at: "\u{0}",
        scale: 1.0,
        jump: false,
        far: false,
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
        shown: false,
        was_shown: false,
        played: false,
        ticked: false,
        fresh: {},
        came: {},
        came_n: 0,
        makes_way: {},
        over: "",
        admitted: {},
        newest: "",
        following_row: false,
        follow_key: "",
        sent: {},
        sent_as: {},
        sent_as_told: @signals.signal(0),
        linger: {},
        act_order: {},
        acts_seen: 0,
        linger_said: @signals.signal(0),
        floor: 0.0,
        floor_takers: {},
        floor_laid: {},
        act_room: {},
        act_whole: {},
        floor_counted: false,
        floor_was: 0.0,
        running: {},
        answered: {},
        answered_unseen: {},
        last_turns: {},
        turn_from: {},
        idle_here: {},
        flash: "",
        flash_lit: @motion.Anim::new(0.0),
        flash_n: 0,
        flash_passage: "",
        flash_centre: false,
        found_at: "",
        found_words: [],
        found_drawn: @motion.Anim::new(0.0),
        found_centre: false,
        rows_made: None,
        motion_of: [],
        motion_list: "",
        motion_keys: [],
        rows: @ui.ListRows::new(),
      }
      readings[key] = r
      r
    }
  }
}

///|
/// Where a chat was left this run (AppState.places): the message at the top of what showed (its seq) and
/// how far its top was below the list's (points); and, left at its end, the newest message then (else -1). It opens
/// there again before where the core says (`at`): the chat's view can outlive its page (opened again before the core
/// lets it go, a minute after: store.ts EVICT_AFTER_MS) and still say where it was opened the first time.
pub(all) struct KeptPlace {
  top : Double
  offset : Double
  bottom : Double
}

///|
pub let kept_places : Map[String, KeptPlace] = Map([])


///|
/// The key of where a chat stands among its list's rows (Entry::id): one at a time, at its end.
let state_key : String = "state"

///|
/// The list's entries: the page before's spinner, the messages with the unread line over the
/// first unread and what went to Slack after each, the page after's spinner, the outbox, where it stands (said only at
/// its end: none while an agent works), its agents at work.
pub fn entries_of(v : ChatView) -> Array[Entry] {
  chat_entries(v).0
}

///|
/// Whether an agent's activity shows: at work, or given words it has yet to take (queued), which it goes on to work on.
/// Gone while queued, its line went and came back each time words were sent to it (2026-11-09).
fn at_work(a : Agent) -> Bool {
  a.status == "running" || a.status == "queued"
}

///|
/// The agents of view `v` whose card an answer on its way from here quotes (`all`'s outgoing rows: the core's outbox
/// and what was sent from here before the core has it), not at work by the view nor in `all` yet: at work from the
/// frame the answer is sent, as the core says them once it has it (views.ts answeredAt), so the agent's line comes in
/// with the answer, the card folding and the answer coming on one way of the list, not a moment after it (the user,
/// 2026-11-09: 「点选项时「处理中」立刻出来」).
fn answered_at(v : ChatView, all : Array[Entry]) -> Array[Agent] {
  let out : Array[Agent] = []
  let take = fn(by : String) {
    match v.agents.search_by(fn(a) { a.key == by }) {
      Some(i) => {
        let a = v.agents[i]
        let shown = all.iter().any(fn(x) { x is Working(w) && w.key == a.key })
        if !at_work(a) && !shown && !out.iter().any(fn(x) { x.key == a.key }) {
          out.push({ ..a, status: "queued", started: true })
        }
      }
      None => ()
    }
  }
  // (the chat's last word a card, answered by what is on its way: words sent under it answer it as a pick does)
  let last = v.messages.rev_iter().find_first(fn(m) { !m.system })
  for e in all {
    guard e is Out(o) && o.state != "failed" else { continue }
    for q in o.quotes {
      guard q.role == "agent" && q.ts != "" else { continue }
      match v.messages.search_by(fn(m) { m.ts == q.ts && m.card is Some(_) }) {
        Some(i) => take(v.messages[i].by.agent)
        None => ()
      }
    }
    match last {
      Some(m) if m.card is Some(_) && m.by.agent != "" && (m.decision is Some(d) && d.resolved && !d.dismissed) =>
        take(m.by.agent)
      _ => ()
    }
  }
  out
}

///|
/// Chat `r`'s view `v` and its entries `list` as the core will say them once it has the words sent from here that it
/// does not have yet (sent.mbt's local_sending: in the list from the frame they are sent, LocalSent), where the chat's
/// last card still waits: they answer it at once, and the core says so from the moment it has them, all in one word
/// of its own (decisions.ts inMessages: what is sending answers the last card; views.ts: the card no more asked, the
/// chat's asks without it, where it stands gone as its agent has words to take). That word comes a few frames after
/// the press, more on a phone: till then the words' row came in alone, the list going up for it, and the card folded,
/// the line of where the chat stands went and the room kept clear of the bell closed only then, the list turning
/// back down under the hand (the user, 2026-11-10: 「现在发一条消息都会有奇怪的跳动」). Said so from the frame they are
/// sent, all of it goes on one way with them (their agent's line too: answered_at). Not sent after all, their row
/// gone, the core's word stands again: the card waits.
fn sent_here_view(r : ChatRef, v : ChatView, list : Array[Entry]) -> (ChatView, Array[Entry]) {
  let rk = r.station + "\u{1}" + r.session
  guard local_sending.get(rk) is Some(sending) && !sending.is_empty() else {
    // (nothing sent from here on its way: what was made of its views while there was, let go)
    sent_here_made.remove(rk)
    return (v, list)
  }
  // (made of this view and these words already: that, the same rows to the list)
  let sig = sending.map(fn(l) { l.row.id + "@" + l.newest.to_string() }).join(",")
  let kept = match sent_here_made.get(rk) {
    Some(k) => k
    None => {
      let k : Array[SentHereMade] = []
      sent_here_made[rk] = k
      k
    }
  }
  for m in kept {
    if physical_equal(m.of, v) && physical_equal(m.list, list) && m.sending == sig {
      return (m.view, m.entries)
    }
  }
  let mut at = -1
  for i, m in v.messages {
    if m.card is Some(_) {
      at = i
    }
  }
  guard at >= 0 else { return (v, list) }
  let m = v.messages[at]
  // (answered already, or a person's words after it in the chat: the core's word stands)
  guard m.decision is Some(d) && !d.resolved else { return (v, list) }
  // (there as they were sent: a card come since, their agent's answer to them, is not what they answer; the frame the
  // core has them, its view read before their row is taken over, would have said that one answered for a frame)
  guard sending.iter().any(fn(l) { m.seq <= l.newest }) else { return (v, list) }
  for i in (at + 1)..<v.messages.length() {
    if v.messages[i].author_kind == "person" {
      return (v, list)
    }
  }
  let said = @sf.t("core-logic.decisions.replied", args=[("name", @sf.t("core-logic.decisions.you"))])
  let messages = v.messages.copy()
  // (no more asked: letting it go is not offered under it)
  messages[at] = { ..m, asked: false, decision: Some({ resolved: true, dismissed: false, text: Some(said), chosen: None }) }
  let asks = v.asks.filter(fn(seq) { seq != m.seq })
  let made = { ..v, messages, asks, ask_clear: v.ask_clear && !asks.is_empty(), state: None, state_ask: None }
  let out = (made, chat_entries(made).0)
  // (of other words sent, or more than its readers are: let go)
  kept.retain(fn(m) { m.sending == sig })
  if kept.length() >= sent_here_kept_most {
    kept.remove(0) |> ignore
  }
  kept.push({ of: v, list, sending: sig, view: out.0, entries: out.1 })
  out
}

///|
/// What sent_here_view made of a chat's view, and of what: the core's view and entries it was made from and the words
/// sent then. The same again while those are (each frame of the words' flight reads it, a phone's core answering many
/// frames after the press): a view and entries made anew each read were other rows to the list every frame, all of
/// them built again, twice a frame while the frame is built again for what it set. One for each of the chat's readers
/// (its page, the frame round it, linger_tick: each its source's own view of it), a few at most.
priv struct SentHereMade {
  of : ChatView
  list : Array[Entry]
  sending : String
  view : ChatView
  entries : Array[Entry]
}

///|
// kept across runs: forgotten with what was sent (sent_reset, as a run starts)
let sent_here_made : Map[String, Array[SentHereMade]] = Map([])

///|
/// How many of a chat's views sent_here_view keeps what it made of: more readers than this at once make theirs again.
let sent_here_kept_most : Int = 4

///|
/// The entries and where their messages end, before the live rows at the foot.
fn chat_entries(v : ChatView) -> (Array[Entry], Int) {
  let out : Array[Entry] = [Top]
  if v.more {
    out.push(Older(if v.older == "failed" { v.older_failed } else { "" }))
  }
  // (nothing in it: not a window showing none of it, what it shows before being brought, `more`)
  if v.messages.length() == 0 && v.outbox.length() == 0 && v.elsewhere.length() == 0 && !v.more {
    out.push(Empty)
  }
  for e in v.elsewhere {
    out.push(Sent(e))
  }
  for m in v.messages {
    chat_entry_message(out, m, v.unread_line)
  }
  let end = out.length()
  chat_entry_tail(out, v)
  (out, end)
}

///|
fn chat_entry_message(out : Array[Entry], m : Message, unread : Double?) -> Unit {
  match unread {
    Some(l) if l == m.seq => out.push(Line)
    _ => ()
  }
  out.push(Said(m))
  for e in m.elsewhere {
    out.push(Sent(e))
  }
}

///|
fn chat_entry_tail(out : Array[Entry], v : ChatView) -> Unit {
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
      if at_work(a) {
        out.push(Working(a))
      }
    }
  }
  out.push(Foot)
}

///|
/// Chat `r`'s view (chat_view), its list's entries and its topic's error: worked out once for each version of it,
/// whoever reads it in a frame (the page, its side panel, the frame round it, the chats kept: linger_tick).
pub fn view_of_chat(src : Source, r : ChatRef) -> (ChatView?, Array[Entry], Json?) {
  let key = chat_inputs_key(r)
  let live = match chat_inputs.peek_from(src, key) {
    Some(input) => input.live
    None => Ref(true)
  }
  let input = chat_inputs.read(src, key, fn(was) {
    if !live.val {
      // The page has left. Tell anything still following this computation to read again, without re-subscribing as
      // the old subscription ends; a reader still in use obtains a new input on its next read.
      match was {
        Some(before) => { source: before.source, read: before.read, topic: before.topic, live }
        None => @halt.saying("a chat input was left before it was read")
      }
    } else {
      let (read, topic) = chat_read.read(src, chat_params(r))
      { source: src.topic_read, read, topic, live }
    }
  }, same=fn(a, b) {
    b.live.val && physical_equal(a, b)
  })
  let read = input.read
  let topic = input.topic
  page_chat_view_read(src, r, read.map(fn(chat) { chat.view }))
  match (read, topic.value, fresh_view(r)) {
    // (the chat a new chat became is never said to be empty: its first message is in it from the frame it was sent,
    // sent_local, while the core has it made and not yet sent to)
    (Some(c), Some(Object(_)), Some(_)) if c.list.iter().any(fn(e) { e is Empty }) =>
      (Some(c.view), c.list.filter(fn(e) { !(e is Empty) }), topic.error)
    (Some(c), Some(Object(_)), _) => {
      // (what was sent from here and the core does not have yet answers the last card waiting: sent_here_view)
      let (view, list) = sent_here_view(r, c.view, c.list)
      (Some(view), list, topic.error)
    }
    // the chat a new chat became as its first words were sent, till the core's view of it is read: a chat with
    // nothing in it yet but what was sent from here (its own first view, as the core's will be: views.ts pendingChat)
    (_, _, Some((v, list))) => (Some(v), list, None)
    _ => (None, [], topic.error)
  }
}

///|
/// The topic and its derived messages are shared by reads of a chat until the topic changes. A different source gets
/// its own reading. The fresh view is still read by each caller above: its full ChatRef can differ for the same topic.
// kept across runs: the Kept is registered on first use and its stored inputs are cleared by kept_reset (derived.mbt)
let chat_inputs : SourceKept[ChatInput] = { kept: {}, listed: false }

///|
priv struct ChatInput {
  source : (String, Map[String, Json]) -> Topic
  read : ChatRead?
  topic : Topic
  live : Ref[Bool]
}

///|
/// A distinct key for each pair, without relying on a separator being absent from a station or session.
fn chat_inputs_key(r : ChatRef) -> String {
  r.station.length().to_string() + ":" + r.station + r.session
}

///|
/// Let the computed go before the core's chat topic is left, so an ending topic cannot cause it to subscribe again.
pub fn chat_inputs_left(r : ChatRef) -> Unit {
  let key = chat_inputs_key(r)
  match chat_inputs.kept.get(key) {
    Some(entries) =>
      for entry in entries {
        match entry.value.peek() {
          Some(input) => input.live.val = false
          None => ()
        }
      }
    None => ()
  }
  chat_inputs.forget(key)
}

///|
/// Let one source's chat input go without invalidating another source that still reads the chat.
pub fn chat_inputs_left_from(src : Source, r : ChatRef) -> Unit {
  let key = chat_inputs_key(r)
  match chat_inputs.peek_from(src, key) {
    Some(input) => input.live.val = false
    None => ()
  }
  chat_inputs.forget_from(src, key)
}

///|
/// Chat `r`'s view as a frame read it last (view_of_chat), if one did since the last: its topic not asked for (a chat
/// whose page was never drawn, or is left, asks nothing of the core for it).
pub fn chat_kept(r : ChatRef) -> ChatView? {
  match chat_read.kept(chat_params(r)) {
    Some(c) => Some(c.view)
    None => None
  }
}

///|
/// A chat view last read through this source, without acquiring its topic.
pub fn chat_kept_from(src : Source, r : ChatRef) -> ChatView? {
  match chat_read.kept_from(src, chat_params(r)) {
    Some(c) => Some(c.view)
    None => None
  }
}

///|
/// A chat as chat_read made it: its view, its list's entries, and each message with the JSON it was read from (the
/// next version's same JSON, a message that did not change, not read again: made_again).
priv struct ChatRead {
  message_json : Array[Json]
  view : ChatView
  list : Array[Entry]
  message_end : Int
  read : Array[(Json, Message)]
}

///|
/// Whether the messages are still the ones made last. A source can reuse its array and change its contents in place,
/// so compare to the recorded messages, not just the array's identity.
fn same_chat_messages(jsons : Array[Json], read : Array[(Json, Message)]) -> Bool {
  if jsons.length() != read.length() {
    return false
  }
  for i, j in jsons {
    if !physical_equal(j, read[i].0) {
      return false
    }
  }
  true
}

///|
/// The rows are unchanged for a chat with no outbox, external messages or running activities when these inputs are
/// unchanged. With any of those dynamic rows, make the list afresh from the new view.
fn chat_entries_same(a : ChatView, b : ChatView) -> Bool {
  physical_equal(a.messages, b.messages) &&
  a.more == b.more &&
  a.newer == b.newer &&
  a.unread_line == b.unread_line &&
  a.state == b.state &&
  a.elsewhere.is_empty() && b.elsewhere.is_empty() &&
  a.outbox.is_empty() && b.outbox.is_empty() &&
  a.agents.iter().all(fn(agent) { !at_work(agent) }) &&
  b.agents.iter().all(fn(agent) { !at_work(agent) })
}

///|
/// Messages appended after an unchanged history keep its entries. The old array remains untouched, since a frame
/// may still use it. Other list changes take the ordinary path.
fn chat_entries_appended(v : ChatView, was : ChatRead) -> (Array[Entry], Int)? {
  let before = was.view.messages
  if before.is_empty() || before.length() >= v.messages.length() ||
     was.view.more != v.more || was.view.unread_line != v.unread_line ||
     !was.view.elsewhere.is_empty() || !v.elsewhere.is_empty() {
    return None
  }
  for i, m in before {
    if !physical_equal(m, v.messages[i]) {
      return None
    }
  }
  let out = was.list.copy()
  while out.length() > was.message_end {
    out.pop() |> ignore
  }
  for i in before.length()..<v.messages.length() {
    chat_entry_message(out, v.messages[i], v.unread_line)
  }
  let end = out.length()
  chat_entry_tail(out, v)
  Some((out, end))
}

///|
/// A chat's view and its list's entries, as the core's `chat` topic gives them: its messages read again only as they
/// changed (one came: that one read).
// kept across runs: what it keeps is let go of by a run anew and by reset (derived.mbt)
let chat_read : Derived[ChatRead] = Derived::new("chat", fn(v, was) {
  let message_json = items(Some(v), "messages")
  let (read, messages) = match was {
    Some(w) if physical_equal(w.message_json, message_json) && same_chat_messages(message_json, w.read) =>
      (w.read, w.view.messages)
    _ => {
      let read = made_again(
        message_json,
        match was {
          Some(w) => w.read
          None => []
        },
        message_key,
        message_of,
      )
      (read, read.map(fn(p) { p.1 }))
    }
  }
  let view = chat_view_of(v, messages)
  let (list, message_end) = match was {
    Some(w) if chat_entries_same(w.view, view) => (w.list, w.message_end)
    Some(w) =>
      match chat_entries_appended(view, w) {
        Some(entries) => entries
        None => chat_entries(view)
      }
    None => chat_entries(view)
  }
  { message_json, view, list, message_end, read }
})

///|
/// A message's key in its chat, as the core keys them (client/core-ts collections.ts: `seq` and `outgoing`).
fn message_key(m : Json) -> String {
  let s = Some(m)
  number(s, "seq").to_string() + "\u{1}" + text(s, "outgoing")
}

///|
/// An agent whose turn ended, its activity still shown (with_lingering) while its messages come out of its avatar.
pub(all) struct Lingering {
  agent : Agent
  /// a turn begun and over between two ticks: there in the one tick that found it, as one seen running is
  mut once : Bool
  /// there taking no room and unseen, its activity read as a seen one's is (its answer, if any, out of where its avatar
  /// would be): never coming in and going a moment after (the list down and up again)
  unseen : Bool
  /// the answer its turn is about, told over before that answer came (by its seq; -1 none): it stays till the answer
  /// comes and leaves its avatar, the two changing places on the list's one way, not its room closed alone and the
  /// answer's opened a moment after (the list down and up again: 2026-11-09 the user, 「现在发个消息都抖了」「偶现」)
  mut awaits : Double
}

///|
/// Each frame, before any page is built, whatever page shows: from each chat kept's own data (its agents running, its
/// messages coming out of an avatar), whose activity stays as its turn ends (while its messages come out of its avatar,
/// no longer: chat_tick); a chat under another page lets them go meanwhile. The chat's page draws what it says.
/// `in_front`: the app shown (what is said then is watched). As each build begins (here, before any page): whether each
/// chat's list was shown in the one before (Reading's `was_shown`), and not yet in this one; its data not taken in this
/// one yet, nor its floor counted.
pub fn linger_tick(c : @ui.Ctx, src : Source, in_front~ : Bool) -> Unit {
  for rk, rd in readings {
    rd.was_shown = rd.shown
    rd.shown = false
    rd.played = false
    rd.ticked = false
    rd.floor_counted = false
    // every chat kept whose data the page read: its activities whose turn is over let go, its page shown or not
    // (not one a message of it drawn elsewhere keeps: its topic never asked for)
    let (station, session) = match rk.find("\u{1}") {
      Some(i) => (rk.exact_view(end=i).to_owned(), rk.exact_view(start=i + 1).to_owned())
      None => continue
    }
    let r : ChatRef = { station, session, title: "", station_name: "" }
    let page_src = page_source_for_chat(src, r)
    if chat_kept_from(page_src, r) is None {
      continue
    }
    match view_of_chat(page_src, r).0 {
      Some(v) => chat_tick(c, rk, rd, v, shown=rd.was_shown, in_front~)
      None => ()
    }
  }
}

///|
/// A chat's own data, once a build, before its page is built (linger_tick; its page the first build it shows in):
/// what comes out of its avatars played on, whose activity stays as its turn ends.
pub fn chat_tick(c : @ui.Ctx, rk : String, rd : Reading, v : ChatView, shown~ : Bool, in_front~ : Bool) -> Unit {
  let lingered = rd.ticked
  let played = rd.played
  if lingered && (played || !shown) {
    return
  }
  let running : Map[String, Agent] = Map([])
  if !v.newer {
    for a in v.agents {
      if at_work(a) {
        running[a.key] = a
      }
    }
  }
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt). (Once under way, it goes on while the end is near: the answer
  // coming in grows the list under the reader, who is a moment short of its end until the list follows; only
  // scrolled away, as the way to the newest shows, it ends.)
  // (played on while its page shows: under another page it waits where it is, as before)
  let em = emits_of(rk)
  if shown && !played {
    rd.played = true
    // messages out of avatars: their turn, asked by now, starts (list_turns.mbt)
    let turns = turns_of(rk)
    turns.step(c)
    let playing = em.current is Some(_) || em.queue.length() > 0
    let watched = (rd.at_end || rd.following_row || (playing && !rd.jump)) && !v.newer && in_front
    if watched != em.watched {
      em.watched = watched
      em.changed()
    }
    let showing : Map[String, Bool] = Map([])
    for k, _ in running {
      showing[k] = true
    }
    for k, _ in rd.linger {
      showing[k] = true
    }
    emit_take(c, em, v, showing)
    // words sent from here on their way: their landing as declared (-2: not laid out yet), -1 none or landed
    // (emit_step)
    let sending = fn() {
      match send_flight.get() {
        Some(f) if f.turns == rk && !f.placed => -2.0
        Some(f) if f.turns == rk && !f.way.over(c) => f.way.ends()
        _ => -1.0
      }
    }
    emit_step(c, em, turns, sending)
  }
  if lingered {
    return
  }
  rd.ticked = true
  // its turn over: it stays only while its messages come out of its avatar (they need it to come out of), and goes as
  // the last of them leaves it, its room opening in the list (Float), on the list's way with it: no moment after, which closed
  // its room alone and took the list back the other way from where what its turn said had just moved it (2026-11-09
  // the user, of an answer at once to a card picked: 「点一个决策后上下摇晃」; 「处理中」不再单独收一次).
  let keeps = emit_keeps(em)
  // (the last message here, by seq: an answer past it is on its way)
  let here = v.messages.iter().fold(init=-1.0, fn(m, x) { if x.seq > m { x.seq } else { m } })
  let on_its_way = fn(a : Agent) {
    match a.about {
      Some(seq) if seq > here && !v.newer => seq
      _ => -1.0
    }
  }
  for k, a in rd.running {
    if !running.contains(k) && !rd.linger.contains(k) {
      // (as it was told over: its own about, the summary read now)
      let now = v.agents.iter().find_first(fn(b) { b.key == k }).unwrap_or(a)
      let awaits = on_its_way(now)
      if keeps.contains(k) || awaits >= 0.0 {
        rd.linger[k] = { agent: a, once: false, unseen: false, awaits }
        linger_told(rd)
      }
    }
  }
  // a turn begun and over between two ticks, its agent never seen running, as if it had been, for that tick (and on
  // while its messages come out of its avatar): that a frame fell inside it is the moment's (how what came was
  // taken), not the chat's
  if !v.newer {
    for a in v.agents {
      match rd.last_turns.get(a.key) {
        Some(was) if a.last_turn != was &&
          a.last_turn != "" &&
          !running.contains(a.key) &&
          !rd.running.contains(a.key) &&
          !rd.linger.contains(a.key) => {
          rd.linger[a.key] = { agent: a, once: true, unseen: true, awaits: -1.0 }
          linger_told(rd)
        }
        _ => ()
      }
      rd.last_turns[a.key] = a.last_turn
    }
  }
  // at work still, its answer out of its avatar (the last of what it said: none waiting after it), its line goes as the
  // answer's room opens (Float), on the list's one way: the answer takes its place, never the list up and back down
  // again (2026-11-09 the user, 「点一个决策后上下摇晃」: 「处理中」跟回复同一次换位). It does not come back this turn.
  // Only a post that ends its turn (its `ending`) is the answer: after one saying how far it got the agent works on,
  // and its line stays (2026-11-09 the user: 「agent 发完消息 activity 不出现」).
  match em.current {
    Some(t) if t.pose != Fold &&
      running.contains(t.agent) &&
      !rd.answered.contains(t.agent) &&
      !keeps.contains(t.agent) &&
      ends_turn(v, t.seq) => {
      rd.answered[t.agent] = running.get(t.agent).map(fn(a) { a.last_turn }).unwrap_or("")
      linger_told(rd)
    }
    _ => ()
  }
  // its answer come in with no avatar to come out of (the list not followed at its end as it came, say, a moment after
  // the words sent: emit_take): its line goes as that answer's room opens, the same, not closed alone as its turn ends
  // (2026-11-09 the user, 「现在发个消息都抖了」)
  for k, a in running {
    // (from the last message there before: its answer may come in the same read as the words it answers, the agent
    // first seen at work with it already here, said while the chat shows; one of its own there as the chat opened, or
    // seen while it was not at work, is from before)
    let first = !rd.turn_from.contains(k)
    if first {
      // (one from a turn before, its line gone by now)
      rd.answered_unseen.remove(k) |> ignore
      let idle = rd.idle_here.get(k).unwrap_or(-1.0)
      rd.turn_from[k] = v.messages
        .iter()
        .filter(fn(m) { !(m.author_kind == "agent" && m.by.agent == k && m.said && m.seq > idle) })
        .fold(init=-1.0, fn(n, m) { if m.seq > n { m.seq } else { n } })
    }
    if rd.answered.contains(k) || keeps.contains(k) {
      continue
    }
    let from = rd.turn_from[k]
    let came = v.messages.iter().any(fn(m) {
      m.seq > from &&
      m.author_kind == "agent" &&
      m.by.agent == k &&
      !m.mine &&
      !m.system &&
      m.ending != "" &&
      !emit_goes(em, m.seq)
    })
    if came {
      rd.answered[k] = a.last_turn
      if first {
        rd.answered_unseen[k] = true
      }
      linger_told(rd)
    }
  }
  for a in v.agents {
    if !running.contains(a.key) {
      rd.idle_here[a.key] = here
    }
  }
  let gone_by = rd.turn_from.keys().filter(fn(k) { !running.contains(k) }).collect()
  for k in gone_by {
    rd.turn_from.remove(k)
  }
  // (its turn over, or over and another begun between two ticks: its line back for the next)
  let done = rd.answered
    .iter()
    .filter(fn(e) {
      match running.get(e.0) {
        Some(a) => a.last_turn != e.1
        None => true
      }
    })
    .map(fn(e) { e.0 })
    .collect()
  for k in done {
    rd.answered.remove(k)
  }
  if !done.is_empty() {
    linger_told(rd)
  }
  rd.running.clear()
  for k, a in running {
    rd.running[k] = a
  }
  let over : Array[String] = []
  for k, l in rd.linger {
    if l.once && !running.contains(k) {
      l.once = false
      continue
    }
    // (its answer come since: from here on it goes as that answer leaves its avatar, as any)
    if l.awaits >= 0.0 && l.awaits <= here {
      l.awaits = -1.0
    }
    if running.contains(k) || (!keeps.contains(k) && l.awaits < 0.0) {
      over.push(k)
    }
  }
  for k in over {
    rd.linger.remove(k)
  }
  if !over.is_empty() {
    linger_told(rd)
  }
}

///|
/// One came to linger or went: told to what reads which do (with_lingering).
fn linger_told(rd : Reading) -> Unit {
  rd.linger_said.set(rd.linger_said.untracked() + 1)
}

///|
/// Whether the message `seq` is a post that ended its agent's turn (all_done, need_help, waiting), not one saying how
/// far it got. (From the end: what comes out of an avatar is among the newest.)
fn ends_turn(v : ChatView, seq : Double) -> Bool {
  for i = v.messages.length() - 1; i >= 0; i = i - 1 {
    if v.messages[i].seq == seq {
      return v.messages[i].ending != ""
    }
  }
  false
}

///|
/// The list with the activities of agents whose turn just ended, kept while their messages come out of their avatars.
pub fn with_lingering(rd : Reading, list : Array[Entry]) -> Array[Entry] {
  rd.linger_said.get() |> ignore
  // (an agent at work whose answer came out of its avatar: its line gone, chat_tick)
  let list = if rd.answered.is_empty() {
    list
  } else {
    list.filter(fn(e) { !(e is Working(a) && rd.answered.contains(a.key) && !rd.answered_unseen.contains(a.key)) })
  }
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
  let block = out[start:end].to_owned()
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
/// How tall the floor agents' lines left is in this build (web's): what they left, less the rows that
/// came in since, each as tall as last laid out (read back: laid out otherwise, the frame is built again). As each
/// build first asks, from what the layout before it laid out: once they fill it, it is gone; one gone from the list
/// (an outbox entry become its message, by another key), its height is taken for good.
pub fn floor_of(c : @ui.Ctx, rd : Reading, key : String, keys : Array[String]) -> Double {
  // (how much of it is still kept: the rows making way for the line gone, from the frame it went)
  let out = @motion.anim(c, "floor/out/" + key, 0.0, global=true)
  if rd.floor <= 0.0 {
    rd.floor = 0.0
    rd.floor_takers.clear()
    rd.floor_laid.clear()
    rd.floor_was = 0.0
    out.snap(c, 0.0)
    return 0.0
  }
  if !rd.floor_counted {
    rd.floor_counted = true
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
  // the rows over it making way for the line gone (sf/motion.mbt kind 3, its cause the line's going): from where they
  // stood, on the rows' spring, nothing dropped at once and no room left empty for good (whether rows came before
  // the line went or after, the list at rest the same)
  if rd.floor > rd.floor_was {
    out.snap(c, out.get(c) + rd.floor - rd.floor_was)
    out.animate(c, 0.0, @sf.move_spring)
  }
  rd.floor_was = rd.floor
  // (made way: none left)
  if out.target() == 0.0 && out.get(c) <= 0.0 {
    rd.floor = 0.0
    rd.floor_was = 0.0
    rd.floor_takers.clear()
    rd.floor_laid.clear()
    return 0.0
  }
  dmax(0.0, dmin(out.get(c), rd.floor - took))
}

///|
/// What the chat's page builds from where its list is (messages): whether it is laid out, near its top (the page
/// before asked for) or its end (the page after), at its end, away from it (the way to the newest), and whether the
/// asks waiting are all in view (the bell over the way to the end, jump_to_ask). A scroll changing none of that builds
/// nothing again.
#derive(Eq)
pub(all) struct ListMade {
  laid : Bool
  near_top : Bool
  near_end : Bool
  at_end : Bool
  away : Bool
  asks_seen : Bool
}

///|
pub fn list_made(info : @ui.ListInfo?, n : Int, ask_rows : Array[Int], lr : @ui.ListReader) -> ListMade {
  match info {
    Some(i) =>
      {
        laid: i.first >= 0,
        near_top: i.first >= 0 && chat_short_above(i, lr),
        near_end: i.last >= n - 4,
        at_end: i.at_end,
        away: i.first >= 0 && i.below > 120.0 && !i.gliding,
        asks_seen: asks_in_view(ask_rows, info),
      }
    None => { laid: false, near_top: false, near_end: false, at_end: false, away: false, asks_seen: false }
  }
}

///|
/// Whether a chat's list wants the page before it (`info` as it was last laid out, `lr` the list as it is now): what it
/// lays out does not fill its window (the screen shows less than it could), or the reader has moved it off its end
/// (it is not pinned to its newest: info's `at_end`) and less than a screen of it is above what shows. Its page then
/// asks for more before it (chat_grow_rows), so that a hand reading it back at its fastest never comes to its top
/// before they are in; while it sits at its end, as it opens or as messages come, nothing is asked ahead of need.
/// Measured in points: the rows above at the height they were laid out at, one not laid out yet (above where it
/// opened) at the least a row the core counts has (chat_row_least), never more than it can be; counted only as far as a
/// screen.
pub fn chat_short_above(info : @ui.ListInfo, lr : @ui.ListReader) -> Bool {
  if info.content < info.height {
    return true
  }
  if info.at_end {
    return false
  }
  match lr.place() {
    Some((first, off, _)) => {
      let mut above = off
      for k in 0..<first {
        if above >= info.height {
          break
        }
        above += lr.row_height(k).unwrap_or(chat_row_least)
      }
      above < info.height
    }
    None => false
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
) -> Unit {
  let n = list.length()
  let info = lr.info()
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
/// The rows in the list and their keys, as they move (a message sent from here keeps its outbox row's: Chat.kt
/// sentAs), and which are new: what comes while the list follows its end and the chat shows, not caught up on (Chat.kt
/// arrived, caught). What comes then (a message simply coming in, an agent's line, an outbox entry) is in the list at
/// once, its room opening from then (Turns::admit), as is what was sent from here, the frame it is sent, before the
/// core has it (LocalSent).
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
  laid? : String = "",
  laid_at? : Double,
  foot_way? : (Double, Double),
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
  rd.foot_sign = if ask_clears(v) { "+ask" } else { "" }
  // The same entries and message-to-outbox mapping as last time, nothing sent from here waiting for its row: what it
  // made then, its rows not gone over again. Other view fields may change without changing
  // those inputs (the chat's title, for example). Whether the list follows its end is not asked: it only lets in rows
  // not known yet, and with the same entries every row was made known then.
  // (a page read in, before the window or reaching the chat's end: what it brings was said long ago, there at once,
  // the rows it joins as they are now; only what is said while the list is at the chat's end comes and changes)
  let watched = !v.newer && !paged_in(rd, v)
  let sending = sending_of(rk)
  match rd.rows_made {
    Some(m) if rd.drawn &&
      physical_equal(m.all, all) &&
      (physical_equal(m.v, v) ||
       (physical_equal(m.v.messages, v.messages) &&
        m.v.outbox.is_empty() && v.outbox.is_empty() &&
        m.v.newer == v.newer &&
        ask_clears(m.v) == ask_clears(v))) &&
      m.rise_ms == rise_ms &&
      m.known == rd.known.length() &&
      sending.is_empty() => return shown_rows(c, rd, m.list, m.keys, watched, flight, laid~, laid_at~, foot_way~)
    _ => ()
  }
  let made_whole = sending.is_empty()
  let given = all
  for o in v.outbox {
    if o.seq >= 0.0 {
      rd.sent[o.seq] = o.id
    }
  }
  for m in v.messages {
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
  let taken : Map[String, Bool] = Map([])
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
        rd.sent_as_told.set(rd.sent_as_told.untracked() + 1)
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
  // (what its core's rows took over gone from it: told, what follows it read again)
  let taken_over = still.length() != sending.length()
  sending.clear()
  for l in still {
    sending.push(l)
  }
  if taken_over {
    sending_changed()
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
    sent_among(all, all_keys, at, still)
  }
  // an agent whose card was just answered from here: at work from the frame the answer is sent, its line coming with
  // the answer (answered_at)
  for a in answered_at(v, all) {
    let at = all.length() - (if all.length() > 0 && all[all.length() - 1] is Foot { 1 } else { 0 })
    all.insert(at, Working(a))
    all_keys.insert(at, "act:" + a.key)
  }
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
        turns.admit(c, k)
      }
    }
  }
  let list : Array[Entry] = []
  let keys : Array[String] = []
  for i, e in all {
    list.push(e)
    keys.push(all_keys[i])
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
        // what comes in takes back the room an agent's line left
        if rd.floor > 0.0 {
          rd.floor_takers[keys[i]] = 0.0
        }
      } else if !(e is (Top | Foot)) {
        was_last = i
      }
    }
    if came_last >= 0 && was_last > came_last {
      rd.over = keys[came_last]
    }
  }
  // what each row that makes way saw come in over it last: the newest of the rows over it that came, by whose avatar
  // they came out of (an agent's line not for its own: its avatar away, it comes back to where the line now is)
  let newest : Map[String, (Int, String)] = Map([])
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
  rd.rows_made = if made_whole {
    Some({ all: given, v, rise_ms, known: rd.known.length(), list, keys })
  } else {
    None
  }
  // (what changes comes, goes and changes on the list's way whether the list follows its end or is read up it: the
  // row read from stays where it shows, what is over and under it moving away from it, mbui's ui/list_size.mbt; nothing
  // at once in view, 2026-10-31 the user: 「有一些是凭空出现的，有一些是凭空消失的」)
  shown_rows(c, rd, list, keys, watched, flight, laid~, laid_at~, foot_way~)
}

///|
/// Whether chat `v`'s window took in a page since its rows were last given: the page before it (its first entry
/// earlier), or the page that reaches the chat's end (short of it till now).
fn paged_in(rd : Reading, v : ChatView) -> Bool {
  let first = match v.first_entry {
    Some(f) => f
    None =>
      match v.messages.get(0) {
        Some(m) => m.seq
        None => -1.0
      }
  }
  let paged = (first >= 0.0 && rd.first_was >= 0.0 && first < rd.first_was) || (rd.newer_was && !v.newer)
  rd.first_was = first
  rd.newer_was = v.newer
  paged
}

///|
/// A chat's rows as they show (`list`, `keys`): with what went from them in among them while its room closes, what
/// came and changed said from now while its newest are in it (mbui's ui/list_size.mbt); what words sent fly to opening its
/// room as long as their flight. `laid`: how the list is laid out other than by its width as it is ("" by that; on a
/// page's way, the width it is kept at: sfpages' laid_w), its rows another version each when that changes, so their
/// room goes on the list's way to what it is now; from `laid_at` if said, a moment before now (its way there then,
/// whichever frame finds it so), else from now.
fn shown_rows(
  c : @ui.Ctx,
  rd : Reading,
  list : Array[Entry],
  keys : Array[String],
  watched : Bool,
  flight : SendFlight?,
  laid~ : String,
  laid_at~ : Double?,
  foot_way~ : (Double, Double)?,
) -> (Array[Entry], Array[String]) {
  // words sent let go of the composer as they leave it, a share of their way on (flight_placed): their row opens
  // from then, the composer's room closes from then (flight_lets_go), as long, so that what is over them goes one way;
  // their row opening from the moment they were sent, the room after, on a curve of its own, had it go up, then down
  // (set out this frame as their row is in the list, when not yet: flight_placed); what else changes the rows' heights
  // from now till then (a card they answer closing) sets out with them, one way
  let now = c.moment()
  let mut told_foot = false
  let leaving = match flight {
    Some(f) if !f.carried => {
      // (once their way is said, in the frame their row is placed: flight_timed)
      if f.placed && f.timed && rd.sent_foot != "/" + f.key {
        rd.sent_foot = "/" + f.key
        told_foot = true
      }
      // (said in the one place the composer's coming down is: flight_lets_go; not placed yet, from now, as long as
      // their usual way's share)
      match flight_lets_go(f.chat) {
        Some((at, ms)) => Some((f.key, at, ms))
        None => Some((f.key, now + flight_settle * f.ms, (1.0 - flight_settle) * f.ms))
      }
    }
    _ => None
  }
  // (built again as their row opens, in the first frame drawn at or past that moment: their way is drawn each frame
  // meanwhile)
  match leaving {
    Some((_, at, _)) if at > now => c.shows_from(at)
    _ => ()
  }
  let told_laid = laid != rd.rows_laid
  rd.rows_laid = laid
  // (the composer's ground on that way now: the Foot row's change goes on it, from when it set out, as long)
  let (way_at, way_ms) = foot_way.unwrap_or((-1.0, 0.0))
  let on_way = way_at >= 0.0 && way_at + way_ms > now
  rd.rows.rows(
    c,
    // (given anew as the Foot row's version changes with them, or every row's as the list is laid out otherwise: the
    // same arrays as the frame before are not looked over)
    if told_foot || told_laid || on_way { keys.copy() } else { keys },
    list,
    // (laid out at another width as a page's way sets off or is there, each row's words wrapped otherwise, as far from
    // the one before (20 or 28 narrow or not) and its picture inline or out in the margin: each its room going there on
    // the list's way, not stepped at once in one frame, rows_steady.mbt)
    fn(e) {
      match e {
        Foot => "foot" + rd.foot_sign + "@\{way_at}" + rd.sent_foot
        Top => shown_sign(e)
        _ => shown_sign(e) + laid
      }
    },
    watched~,
    ms=fn(k) {
      match (leaving, flight) {
        (Some((key, _, ms)), _) if key == k || k == "foot" => Some(ms)
        _ if k == "foot" && on_way => Some(way_ms)
        (_, Some(f)) if f.key == k => Some(flight_ms_of(f))
        _ => None
      }
    },
    from=fn(k) {
      match (leaving, laid_at) {
        (Some((_, at, _)), _) if at > now => Some(at)
        (None, _) if k == "foot" && on_way => Some(way_at)
        (_, Some(at)) if told_laid && at < now => Some(at)
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
/// end: followed from its top, its top follow_margin under the bar, not past its
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
/// How far under the list's room at its top a row followed from its top stops.
pub let follow_margin : Double = 12.0

///|
pub let flash_held : Ref[Bool] = Ref(false)

///|
/// A message gone to flashes: the accent's ground in over `flash_in_ms` on Ease.Out, held to
/// `flash_held_ms`, gone by `flash_ms` on the standard curve.
pub let flash_in_ms : Double = 160.0

///|
pub let flash_held_ms : Double = 900.0

///|
pub let flash_ms : Double = 1700.0

///|
/// When the flash of the messages gone to (in every chat read) is over (the frames' clock; once over, the end it was
/// given, Anim::ended_at; -1: none has flashed): a test
/// runs to it after opening a chat at a message (a notification tapped, a decision's post).
pub fn flash_rest() -> Double {
  let mut end = -1.0
  readings.each(fn(_, rd) { if rd.flash_lit.ended_at() > end { end = rd.flash_lit.ended_at() } })
  end
}

///|
/// The flash of the message gone to, all of its way said as it starts.
pub fn flash_start(c : @ui.Ctx, rd : Reading) -> Unit {
  rd.flash_n += 1
  rd.flash_lit.snap(c, 0.0)
  rd.flash_lit.animate(
    c,
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
  rd.flash_lit.get(c)
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
/// Tells the core the chat shows, its end seen or not, and the last message seen
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
  (src.call)("client.focus", { "chat": chat }, answer_unread)
}

///|
/// Chat `r` (its view `v`) shown short of its end: its latest page in place of what shows (`chat.latest`; Chat.kt
/// atLatest), its list at its end as it comes (list_after). Asked as the way to the newest is pressed, and as words are
/// sent: they go at the chat's end, not after what was being read.
pub fn chat_latest(c : @ui.Ctx, src : Source, r : ChatRef, v : ChatView, what : String) -> Unit {
  place_forget(r.station + "\u{1}" + r.session)
  guard v.newer && v.thread is Some(th) else { return }
  let rd = reading_of(r.station + "\u{1}" + r.session)
  rd.latest_asked = true
  c.tell("chat.latest/" + r.station + "/" + r.session, fn() { chat_latest_act(src, r.station, th, what, rd) })
}

///|
/// chat_latest's, asked at once, for a page made as nodes (its press's handler): the place kept forgotten, and where the
/// window is short of the chat's end its latest page asked (true; false where it is not short of it).
pub fn chat_latest_now(src : Source, r : ChatRef, v : ChatView, what : String) -> Bool {
  place_forget(r.station + "\u{1}" + r.session)
  guard v.newer && v.thread is Some(th) else { return false }
  let rd = reading_of(r.station + "\u{1}" + r.session)
  rd.latest_asked = true
  chat_latest_act(src, r.station, th, what, rd)
  true
}

///|
/// The chat's latest page asked (`chat.latest`), its Reading `rd` told where it fails.
fn chat_latest_act(src : Source, station : String, th : Double, what : String, rd : Reading) -> Unit {
  act(src, what, "", "chat.latest", { "station": Json::string(station), "thread": Json::number(th) }, failed=fn() {
    rd.latest_asked = false
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
/// Where the chat is, told the core (`chat.place`): the message at the top and how far its top is below
/// the list's (in the screen's pixels, as Android's app tells it), none at its end; told again as the message at the
/// top changes, and where it is to the pixel as it is left (`exact`). Not each pixel it moves: rows moving on their own
/// (words sent going up into the list) moved it each frame, told and written down each frame (2026-11-08: 20 a send).
/// Opened again this run, it is where it was to the pixel (kept_places).
pub fn tell_place(src : Source, r : ChatRef, v : ChatView, rd : Reading, exact? : Bool = false) -> Unit {
  // kept here too, for opening it again this run
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
  let at = match place.get("seq") {
    Some(seq) => seq.stringify()
    None => ""
  }
  if said == rd.told_place || (!exact && at == rd.told_at) {
    return
  }
  rd.told_place = said
  rd.told_at = at
  (src.call)("chat.place", Json::object(place), answer_unread)
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
/// the composer of draft `draft`, and the page before come in above what is in view keeping it where it is.
/// `rise_ms`, `top`, `in_front`: as row_keys', follow_newest's, chat_tick's.
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
  laid? : String = "",
  laid_at? : Double,
  foot_way? : (Double, Double),
) -> ListFrame {
  let rd = reading_of(r.station + "\u{1}" + r.session)
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt)
  // (taken and played on, before the page is built, by linger_tick)
  let ek = r.station + "\u{1}" + r.session
  let em = emits_of(ek)
  // (shown each frame its list is: built, or kept as its build left it and drawn again, as what a build marks used is
  // marked again: linger_tick plays it on then)
  rd.shown = true
  @ui.built_used(fn() { rd.shown = true })
  chat_tick(c, ek, rd, v, shown=true, in_front~)
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
    laid~,
    laid_at?,
    foot_way?,
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
  // rows came or went over it (the page before, the spinner over it gone with the chat's last page): what is in view
  // stays where it is, and nothing glides for it (the spinner's going told too: the rows were otherwise put a row on,
  // what was in view jumping up by a row's height, go_older_wbtest.mbt)
  if rd.head != "" && rd.placed {
    for i, e in list {
      if e.id() == rd.head {
        if i != rd.head_at {
          let n = i - rd.head_at
          c.list_moved(key, if n > 0 { rd.head_at } else { i }, n)
        }
        break
      }
    }
  }
  rd.head = head
  rd.head_at = head_at
  { key, rk: ek, rd, em, turns, list, keys, flight, draft }
}

///|
/// A chat's list as list_frame made it this frame (its key, its chat's key, what the page keeps of it, its messages
/// out of avatars, its turns, its rows and their keys, the words sent flying to it, and the composer's draft words
/// sent fly from (a new chat's first words carry its list up out of it:
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
      // where it was left here this run: unless at its end with nothing new since, then at its end
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
        // (back to where the reader was, kept as a go-to took it away: there as it was, nothing flashing)
        let back = go_back_offsets.get(gk)
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
                // opened from a search: its words marked in it, nothing flashing (FOUND)
                match go_to_words.get(gk) {
                  Some(words) => {
                    go_to_words.remove(gk)
                    rd.found_at = m.ts
                    rd.found_words = words
                    found = true
                  }
                  None if back is Some(_) => ()
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
          go_back_offsets.remove(gk)
          if found {
            on_found(rd)
          } else if back is None {
            flash_start(c, rd)
          }
          rd.put_there = true
          rd.put_place = None
          c.list_scroll_to(key, at, offset=match back {
            Some(off) => -off
            None => -top
          })
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
            _ => {
              go_tos.remove(gk)
              go_back_offsets.remove(gk)
            }
          }
        }
      }
      _ => ()
    }
    // (read back by what the page builds from it: not at every step of a scroll, which changes none of that; whether
    // less than a screen is above what shows among it, a Bool, built again only as that turns)
    let ask_rows = ask_rows_of(v, list)
    let lr = c.list_reader(key)
    let made = fn(i) { list_made(i, n, ask_rows, lr) }
    let info = c.list_info_as(key, made)
    let short_above = made(info).near_top
    // off its end with less than a screen laid out above what shows, or not filling its window: as many more before it
    // as chat_grow_rows, once for each first
    match (info, v.thread) {
      // (not while the core reads it, nor while it waits after a read that failed: it says when to ask again)
      (Some(_), Some(thread)) if v.more && v.older == "" && rd.placed && short_above => {
        // by entries, not messages: a page of what the chat does not show (letters, edits) moves it too
        let first = match v.first_entry {
          Some(f) => f
          None =>
            match list.iter().find_first(fn(e) { e is Said(_) }) {
              Some(Said(m)) => m.seq
              _ => -1.0
            }
        }
        // (asked once the frame's builds are over, from where the last laid the list out; told again after a frame
        // whose scroll built nothing, from where the list is then)
        if rd.asked.get() != first {
          c.after_build_or_scroll("older", fn() {
            if rd.asked.get() == first {
              return
            }
            // (only as the reader moves it: where the app put it, nothing while it stands there)
            let now = lr.place().map(fn(p) { (p.0, p.1) })
            if rd.put_there {
              match rd.put_place {
                None => {
                  rd.put_place = now
                  return
                }
                Some(p) if now == Some(p) => return
                _ => {
                  rd.put_there = false
                  rd.put_place = None
                }
              }
            }
            // (told again after a scroll: still less than a screen above what shows)
            guard lr.info() is Some(i) && chat_short_above(i, lr) else { return }
            rd.asked.set(first)
            (src.call)(
              "chat.older",
              {
                "station": Json::string(r.station),
                "thread": Json::number(thread),
                "rows": Json::number(chat_grow_rows.to_double()),
              },
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
    if rd.end_asked {
      rd.end_asked = false
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
    // (nor while a row come at its end still opens its room: not wholly in view yet, its rest read once it is; read as
    // it opened, what the read changes of the chat (its agent's line) came while the rows moved, and moved them back)
    let opening = rd.rows.opening(c)
    let seen = match info {
      Some(i) => !v.newer && i.at_end && !opening
      None => false
    }
    rd.at_end = seen
    // (at its end: where the reader was before a go-to forgotten)
    if seen {
      place_forget(gk)
    }
    // where the reader is, worked out once the frame's builds are over from where its last layout left the list, never
    // read back: told the core (what was seen whole, the place), not drawn (tell_place, tell_focus, after it)
    let lr = c.list_reader(key)
    c.after_build_or_scroll("reading", fn() { read_place(rd, v, list, lr, bar, room) })
    // where it is told the core as the reader comes to rest, not only as the chat is left (Chat.kt leave: an app gone
    // from memory never leaves the page)
    rd.scale = c.scale
    if rd.placed && !c.list_moving(key) {
      c.after_build_or_scroll("place", fn() { tell_place(src, r, v, rd) })
    }
    // (told once the frame's builds are over, as the last says it: a build let go of, the frame built again, read the
    // list from before its layout)
    c.after_build_or_scroll("focus", fn() { tell_focus(src, r, v, rd, seen, rd.seen_whole) })
    // the way to the newest: away from the end by more than a corner of the screen, or short of the chat's end (not
    // before the list is first laid out: until then nothing is in view, and the end is not far, only not known)
    let away = match info {
      Some(i) => i.first >= 0 && i.below > 120.0 && !i.gliding
      None => false
    }
    rd.far = v.newer || (match info {
      Some(i) => i.first >= 0 && !i.at_end && i.below > i.height
      None => false
    })
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
fn shown_sign(e : Entry) -> String {
  match e {
    Said(m) => {
      let d = match m.decision {
        Some(d) => "\{d.resolved}\{d.dismissed}\{@ui.some_text(d.chosen)}"
        None => ""
      }
      "m\{m.text.length()}|\{m.attachments.length()}|\{m.quotes.length()}|\{m.time is Some(_)}|\{m.waiting}|\{m.joined}|\{m.followed}|\{d}|\{m.notice_failed}|\{m.notice_words.length()}|\{m.notice_retry_session}|\{m.notice_again_session}|\{m.notice_detail.length()}"
    }
    Out(o) => "o\{o.text.length()}|\{o.attachments.length()}|\{o.state}|\{o.joined}|\{o.followed}"
    State(a, b, c) => "s" + a + b + c
    Working(_) => "w"
    Older(why) => "older" + why
    other => other.id()
  }
}


///|
/// Whether the end of chat `v`'s list keeps clear of the bell floating over it (what waits to be decided there, its
/// end not one: the core's `askClear`): the room under its rows the taller.
pub fn ask_clears(v : ChatView) -> Bool {
  !(v.archived || v.thread is None) && !v.asks.is_empty() && v.ask_clear
}
