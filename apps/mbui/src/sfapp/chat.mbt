// A chat, read (ember apps/android chat/screens/Chat.kt ChatScreen, Messages; ui/Follow.kt): its bar over its messages
// (back, the title, its people and its agents' marks with the station they run on, "…"), the messages as the core's
// `chat` view gives them, newest at the bottom, the list following its newest while it is at its end and "jump to
// the newest" over the composer's room otherwise; the page before loaded as the reader nears the top, what is in view
// staying put. While the chat is read the first time, the messages to come breathing (Waiting.kt Messages), what is
// wrong over them in red.
//
// What the page tells the core of the reader (the chat shown and its end seen: `client.focus`, which marks it read;
// where it was left: `chat.place`) is not said with MBUI_READONLY=1 (Source.readonly): a run on a real account then
// changes nothing in it. The composer at its foot is composer.mbt's.

///|
/// A chat the page is of: its station, the session it is opened by (a row's `session`), its title and its station's
/// name as the row said them (the page shows the view's own once it is read).
pub(all) struct ChatRef {
  station : String
  session : String
  title : String
  station_name : String
} derive(Eq)

///|
/// An entry of the list (Chat.kt Entry), with the room above the first (the bar's) and below the last (the
/// composer's).
priv enum Entry {
  Top
  Older
  Empty
  Line
  Said(Message)
  Sent(Elsewhere)
  Newer
  Out(Outgoing)
  Working(Agent)
  Foot
}

///|
fn Entry::id(self : Entry) -> String {
  match self {
    Top => "top"
    Older => "older"
    Empty => "empty"
    Line => "line"
    Said(m) => "m:" + m.ts
    Sent(e) => "s:" + e.key
    Newer => "newer"
    Out(o) => "o:" + o.id
    Working(a) => "act:" + a.key
    Foot => "foot"
  }
}

///|
/// The bar's height (6 + 40 + 8) and the room the list keeps under it; the composer's room at the foot (ChatHost.kt
/// roomForList: a line of words, the capsule's insets, its toolbar and margins) and the list's under it.
let chat_bar_h : Double = 54.0

///|
let composer_room : Double = 110.0

///|
/// The list's gap between messages (web mobile --list-gap), and under the viewer's message sent soon after the one
/// before it (`joined`).
let gap : Double = 20.0

///|
let joined_gap : Double = 4.0

///|
/// What the page keeps of a chat while it is open.
priv struct Reading {
  /// the first message's entry and where it was in the list, the last frame
  mut head : String
  mut head_at : Int
  /// put in place once (the unread line, where it was opened, or the end), and when
  mut placed : Bool
  mut placed_at : Double
  mut put : Bool
  /// the first message when the page before was asked for (once per page)
  mut asked : Double
  mut asked_newer : Double
  /// what the core was told of the chat shown, its end seen or not ("" nothing yet)
  mut told : String
  /// where the reader is: the message at the top of what shows (-1 none), and whether at the chat's end
  mut top_seq : Double
  mut at_end : Bool
  /// the jump button: shown since when (or hidden since when), and which
  mut jump : Bool
  mut jump_at : Double
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
  fresh : Map[String, Bool]
  /// the outbox entries messages were sent from here as, by seq (their rows go on being those: Chat.kt sentAs)
  sent : Map[Double, String]
  /// agents whose turn ended, still shown a moment (Chat.kt lingering: 600 ms, then fading 220), since when
  linger : Map[String, (Agent, Double)]
  /// the agents running as last drawn
  running : Map[String, Agent]
}

///|
let readings : Map[String, Reading] = {}

///|
fn reading_of(key : String) -> Reading {
  match readings.get(key) {
    Some(r) => r
    None => {
      let r = {
        head: "",
        head_at: -1,
        placed: false,
        placed_at: 0.0,
        put: false,
        asked: -1.0,
        asked_newer: -1.0,
        told: "",
        top_seq: -1.0,
        at_end: true,
        jump: false,
        jump_at: -1.0e9,
        bench: 0,
        bench_phase: 0,
        bench_rows: 0,
        bench_ms: [],
        bench_present: [],
        known: {},
        drawn: false,
        fresh: {},
        sent: {},
        linger: {},
        running: {},
      }
      readings[key] = r
      r
    }
  }
}

///|
/// The views read, by chat: the version they were read at, the view and its list.
let read_chats : Map[String, (Int, ChatView, Array[Entry])] = {}

///|
fn chat_params(r : ChatRef) -> Map[String, Json] {
  { "station": Json::string(r.station), "session": Json::string(r.session) }
}

///|
/// The list's entries (Chat.kt Messages → all): the page before's spinner, the messages with the unread line over the
/// first unread and what went to Slack after each, the page after's spinner, the outbox, its agents at work.
fn entries_of(v : ChatView) -> Array[Entry] {
  let out : Array[Entry] = [Top]
  if v.more {
    out.push(Older)
  }
  if v.messages.length() == 0 && v.outbox.length() == 0 && v.elsewhere.length() == 0 {
    out.push(Empty)
  }
  for e in v.elsewhere {
    out.push(Sent(e))
  }
  for m in v.messages {
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
    for a in v.agents {
      if a.status == "running" {
        out.push(Working(a))
      }
    }
  }
  out.push(Foot)
  out
}

///|
fn view_of_chat(src : Source, r : ChatRef) -> (ChatView?, Array[Entry], Json?) {
  let topic = (src.topic)("chat", chat_params(r))
  let key = r.station + "\u{1}" + r.session
  match topic.value {
    Some(Object(_) as v) =>
      match read_chats.get(key) {
        Some((version, view, list)) if version == topic.version =>
          (Some(view), list, topic.error)
        _ => {
          let view = chat_view(v)
          let list = entries_of(view)
          read_chats[key] = (topic.version, view, list)
          (Some(view), list, topic.error)
        }
      }
    _ => (None, [], topic.error)
  }
}

///|
/// The chat's page.
fn chat_page(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef) -> Unit {
  let t = @sf.theme()
  let (view, list, error) = view_of_chat(src, r)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, fn() {
    match view {
      None => {
        // until the core has it, already a chat's page: its bar (no title yet), the messages to come breathing
        bar_frame(c, "", fn() {  }, fn() {  }, false)
        c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
        let failed = match error {
          Some(e) =>
            Some(
              fill("android-chat.chat.unreadable", [("error", text(Some(e), "message"))]),
            )
          None => None
        }
        waiting_messages(c, failed)
        c.layer(fn() {
          c.spacer()
          composer(c, src, r, None)
        })
        |> ignore
      }
      Some(v) => {
        messages(c, src, r, v, list)
        c.layer(fn() { chat_bar(c, src, w, r, v) }) |> ignore
        c.layer(fn() {
          c.spacer()
          composer(c, src, r, Some(v))
        })
        |> ignore
        // words sent, as typed, until their row is in the list (flight.mbt)
        flight_waiting(c, draft_key(r))
        pick_bar(c, src, r)
      }
    }
  })
  |> ignore
}

///|
/// The chat's list, its key.
fn list_key(r : ChatRef) -> String {
  "chat/" + r.station + "/" + r.session
}

///|
/// The messages (Chat.kt Messages): the list, put in place once, following its end, the page before brought in near
/// its top; the way to the newest over it.
fn messages(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  read : Array[Entry],
) -> Unit {
  let key = list_key(r)
  let rd = reading_of(r.station + "\u{1}" + r.session)
  let list = with_lingering(c, rd, v, read)
  let keys = row_keys(c, rd, v, list, key)
  let dkey = draft_key(r)
  flight_frame(c, dkey)
  let flight = flight_of(dkey)
  @motion.list_keys(c, key, keys.map(fn(k) { key + "\u{1}" + k })) |> ignore
  let here = { station: r.station, session: r.session, view: v }
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
  let n = list.length()
  // a new chat's list comes up out of the composer as it becomes this chat (newchat.mbt)
  c.box(w=Fill(1.0), h=Fill(1.0), ty=new_chat_rise(c, r), fn() {
    c.list(
      key,
      n,
      90.0,
      fn(i) {
        let e = list[i]
        let after_top = i > 0 && list[i - 1] is Top
        let joined = match e {
          Said(m) => m.joined
          Out(o) => o.joined
          _ => false
        }
        let top = if e is Top || e is Foot || after_top {
          0.0
        } else if joined {
          joined_gap
        } else {
          gap
        }
        match e {
          Top => c.box(h=Px(chat_bar_h + 14.0), fn() {  }) |> ignore
          Foot => c.box(h=Px(composer_room_of(c) + 10.0), fn() {  }) |> ignore
          Working(a) => {
            // coming in, its room opens (220 ms, Ease.Out) as it fades in and grows from its avatar; its turn over,
            // it stays a moment and fades (Chat.kt Activity)
            let mk = key + "\u{1}" + keys[i]
            let open = @motion.anim(c, "open/" + mk, 1.0, global=true)
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              open.snap(0.0)
              open.animate(1.0, @motion.tween(220.0, ease=Out))
            }
            let leaving = match rd.linger.get(a.key) {
              Some((_, at)) => c.now() - at >= 600.0
              None => false
            }
            let fade = @motion.animate(c, "fade/" + mk, if leaving { 0.0 } else { 1.0 }, spec=@motion.tween(220.0))
            let p = open.get()
            @motion.reveal(c, mk, p, fn() {
              let ri = c.box(w=Fill(1.0), pl=14.0, pr=14.0, pt=top, fn() {
                activity(c, src, here, a, leaving~)
              })
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(200.0)))
              // pushed down by what comes in above it, it glides there (Chat.kt ACTIVITY_GLIDE: spring(1, 300))
              if !older_came && flight is None {
                @motion.layout(c, ri, mk, spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              }
              c.look(ri, @ui.look(alpha=p * fade, scale=0.5 + 0.5 * p, ox=(14.0 + 9.0) / c.width, oy=0.5))
            })
          }
          _ => {
            // the row words sent go to: its bubble flies there from the composer (flight.mbt)
            let mine = match e {
              Out(_) => true
              Said(m) => m.mine && !m.system
              _ => false
            }
            let flies = flight_takes(dkey, keys[i], mine)
            flying.val = if flies { flight } else { None }
            match flight {
              Some(f) if flies => flight_placed(c, f)
              _ => ()
            }
            let ri = c.box(w=Fill(1.0), pl=14.0, pr=14.0, pt=top, fn() {
              entry_view(c, src, here, e, list)
            })
            flying.val = None
            match flight {
              Some(_) if flies => {
                // flown in, it does not rise in as well
                rd.known[keys[i]] = true
                rd.fresh.remove(keys[i]) |> ignore
              }
              // the rows above go up with the words (ChatHost.kt sendReflow)
              Some(f) if f.placed_at >= 0.0 =>
                @motion.layout(
                  c,
                  ri,
                  key + "\u{1}" + keys[i],
                  listed=false,
                  screen=true,
                  drive=flight_up(flight_p(c, f)),
                )
              _ => ()
            }
            // what is new to the list while it is followed rises in (Chat.kt rise: 14 up and from nothing, 320 ms
            // on the standard curve); what leaves the chat from the outbox fades (200 ms)
            let mk = key + "\u{1}" + keys[i]
            if e is Out(_) {
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(200.0)))
            } else {
              @motion.keyed(c, ri, mk)
            }
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              @motion.entering(c, ri, mk, @motion.trans(fade=0.0, dy=14.0, spec=@motion.tween(320.0)))
            }
          }
        }
      },
      stick_end=true,
      // what comes at the end while it follows is glided after (Follow.kt), half a second after it was put in place,
      // not while words sent fly (they put the list in place)
      glide_on_growth=rd.placed && flight is None && c.now() - rd.placed_at > 500.0,
    )
    |> ignore
    // put in place once: at the unread line (a few lines of what came before it in view), else where the core opened
    // it, else at its end (where the list starts)
    if !rd.placed && v.messages.length() > 0 && !v.unread_above {
      rd.placed = true
      rd.placed_at = c.now()
    }
    if rd.placed && !rd.put && !at_end_asked() {
      rd.put = true
      let mut line = -1
      let mut at = -1
      for i, e in list {
        match e {
          Line => line = i
          Said(m) =>
            match v.at {
              Some(a) if at < 0 && m.seq >= a => at = i
              _ => ()
            }
          _ => ()
        }
      }
      if line >= 0 {
        c.list_scroll_to(key, line, offset=-(chat_bar_h + 14.0 + 85.0))
      } else if at >= 0 {
        c.list_scroll_to(
          key,
          at,
          offset=-(chat_bar_h + 14.0 + v.at_offset.unwrap_or(0.0)),
        )
      }
    }
    let info = c.list_info(key)
    // near the top: the page before comes in, once per page
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.more && rd.placed && i.first >= 0 && i.first <= 3 => {
        let first = match list.iter().find_first(fn(e) { e is Said(_) }) {
          Some(Said(m)) => m.seq
          _ => -1.0
        }
        if rd.asked != first {
          rd.asked = first
          (src.call)(
            "chat.older",
            { "station": Json::string(r.station), "thread": Json::number(thread) },
            fn(res) {
              match res {
                Err(e) => {
                  rd.asked = -1.0
                  @host.log("chat.older failed: " + text(Some(e), "message"))
                }
                _ => ()
              }
            },
          )
        }
      }
      _ => ()
    }
    // near the end of a window short of the chat's: the page after
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.newer && rd.placed && i.last >= n - 4 => {
        let last = match v.messages.last() {
          Some(m) => m.seq
          None => -1.0
        }
        if rd.asked_newer != last {
          rd.asked_newer = last
          (src.call)(
            "chat.newer",
            { "station": Json::string(r.station), "thread": Json::number(thread) },
            fn(res) { if res is Err(_) { rd.asked_newer = -1.0 } },
          )
        }
      }
      _ => ()
    }
    // the core told the chat shows, and whether its end does (what is read follows): not on a read-only run
    let seen = match info {
      Some(i) => !v.newer && i.at_end
      None => false
    }
    rd.at_end = seen
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
    tell_focus(src, r, v, rd, seen)
    // the way to the newest: away from the end by more than a corner of the screen, or short of the chat's end
    let away = match info {
      Some(i) => i.below > 120.0 && !i.gliding
      None => false
    }
    jump_to_latest(c, src, r, v, rd, away || v.newer)
    chat_bench(c, key, rd, v.more, n)
  })
  |> ignore
}

///|
/// The list with the activities of agents whose turn just ended, kept a moment (Chat.kt: 600 ms, then fading 220).
fn with_lingering(c : @ui.Ctx, rd : Reading, v : ChatView, list : Array[Entry]) -> Array[Entry] {
  let now = c.now()
  let running : Map[String, Agent] = {}
  if !v.newer {
    for a in v.agents {
      if a.status == "running" {
        running[a.key] = a
      }
    }
  }
  for k, a in rd.running {
    if !running.contains(k) && !rd.linger.contains(k) && !c.stable() {
      rd.linger[k] = (a, now)
    }
  }
  let over : Array[String] = []
  for k, l in rd.linger {
    if running.contains(k) || now - l.1 >= 820.0 {
      over.push(k)
    } else {
      c.wake_in(dmax(1.0, if now - l.1 < 600.0 { 600.0 - (now - l.1) } else { 820.0 - (now - l.1) }))
    }
  }
  for k in over {
    rd.linger.remove(k)
  }
  rd.running.clear()
  for k, a in running {
    rd.running[k] = a
  }
  if rd.linger.is_empty() {
    return list
  }
  // after the running ones, before the foot
  let out = list.copy()
  let foot = match out.last() {
    Some(Foot) => out.pop()
    _ => None
  }
  for _, l in rd.linger {
    out.push(Working(l.0))
  }
  match foot {
    Some(f) => out.push(f)
    None => ()
  }
  out
}

///|
/// The rows' keys, as they move (a message sent from here keeps its outbox row's: Chat.kt sentAs), and which are
/// new: what comes while the list follows its end and the chat shows, not caught up on (Chat.kt arrived, caught).
fn row_keys(
  c : @ui.Ctx,
  rd : Reading,
  v : ChatView,
  list : Array[Entry],
  key : String,
) -> Array[String] {
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
  let keys = list.map(fn(e) {
    match e {
      Said(m) =>
        match rd.sent.get(m.seq) {
          Some(o) => "o:" + o
          None => e.id()
        }
      _ => e.id()
    }
  })
  let following = match c.list_info(key) {
    Some(i) => i.at_end || i.gliding
    None => true
  }
  if rd.drawn && following && !c.stable() {
    for i, e in list {
      let caught = match e {
        Said(m) => !m.said
        Working(a) => !a.started
        Top | Foot => true
        _ => false
      }
      if !rd.known.contains(keys[i]) && !caught {
        rd.fresh[keys[i]] = true
      }
    }
  }
  for k in keys {
    rd.known[k] = true
  }
  rd.drawn = true
  keys
}

///|
/// MBUI_CHAT_AT_END=1: a chat opens at its end, whatever the core says of where it was left (scripted runs).
let at_end_env : Ref[Int] = { val: -1 }

///|
fn at_end_asked() -> Bool {
  if at_end_env.val < 0 {
    at_end_env.val = if @host.env("MBUI_CHAT_AT_END") == "1" { 1 } else { 0 }
  }
  at_end_env.val == 1
}

///|
/// Tells the core the chat shows, its end seen or not (Chat.kt: `client.focus` with `chat`), as that changes; it
/// marks what is read and where the unread line goes. Never with Source.readonly.
fn tell_focus(src : Source, r : ChatRef, v : ChatView, rd : Reading, seen : Bool) -> Unit {
  if src.read_only {
    return
  }
  let said = "\{seen}"
  if rd.told == said {
    return
  }
  rd.told = said
  (src.call)("client.focus", { "chat": focus_chat(r, v, Some(seen)) }, fn(_) {  })
}

///|
fn focus_chat(r : ChatRef, v : ChatView, end : Bool?) -> Json {
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
/// The chat left (its page gone): the core told it shows no more, and where it was left (`chat.place`: the message
/// at the top, none at its end). Never with Source.readonly.
fn chat_left(src : Source, r : ChatRef) -> Unit {
  let k = r.station + "\u{1}" + r.session
  match (read_chats.get(k), readings.get(k)) {
    (Some((_, v, _)), Some(rd)) if !src.read_only => {
      (src.call)("client.focus", { "left": focus_chat(r, v, None) }, fn(_) {  })
      match v.thread {
        Some(th) if rd.placed => {
          let place : Map[String, Json] = {
            "station": Json::string(r.station),
            "thread": Json::number(th),
          }
          if !rd.at_end && rd.top_seq >= 0.0 {
            place["seq"] = Json::number(rd.top_seq)
          }
          (src.call)("chat.place", Json::object(place), fn(_) {  })
        }
        _ => ()
      }
    }
    _ => ()
  }
  composer_left(src, r)
  readings.remove(k)
  (src.leave)("chat", chat_params(r))
  read_chats.remove(k)
}

///|
/// The way to the newest (Chat.kt JumpToLatest): over the send button, in line with it, a round capsule floating
/// over the list with ↓ (and, short of the chat's end, how many new messages wait there); it comes up growing and
/// goes the way it came. Tapped, the list glides to its end, following it again; short of the chat's end, the
/// chat's latest page is put in place of what shows.
fn jump_to_latest(
  c : @ui.Ctx,
  src : Source,
  r : ChatRef,
  v : ChatView,
  rd : Reading,
  shown : Bool,
) -> Unit {
  let t = @sf.theme()
  // it comes up growing and goes the way it came (Chat.kt JumpToLatest, web mJump: from 18 down at 60%; its opacity
  // 180 ms, CSS's ease, the rest 220 on the standard curve; going, 150 and 180), turned back mid-way from where it is
  let look = match
    @motion.presence(
      c,
      "chat-jump",
      shown,
      enter=@motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(220.0), fade_spec=@motion.tween(180.0, ease=Css)),
      exit=@motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(180.0), fade_spec=@motion.tween(150.0, ease=Css)),
    ) {
    Some(l) => l
    None => return
  }
  rd.jump = shown
  let count = if v.newer && v.unread > 0.0 { Some(v.unread.to_int()) } else { None }
  let id = c.id("chat-jump")
  if c.clicked(id) && shown {
    if !v.newer {
      c.list_to_end(list_key(r))
    } else {
      match v.thread {
        Some(th) =>
          (src.call)(
            "chat.latest",
            { "station": Json::string(r.station), "thread": Json::number(th) },
            fn(_) {  },
          )
        None => ()
      }
    }
  }
  c.layer(align=AEnd, fn() {
    c.spacer()
    c.box(pr=18.0, pb=composer_room_of(c) + 2.0, fn() {
      let pill = c.box(
        dir=Row,
        h=Px(36.0),
        min_w=36.0,
        padx=if count is Some(_) { 0.0 } else { 0.0 },
        pl=if count is Some(_) { 10.0 } else { 0.0 },
        pr=if count is Some(_) { 14.0 } else { 0.0 },
        gap=4.0,
        radius=18.0,
        align=ACenter,
        justify=JCenter,
        glass=@sf.glass_floating(),
        shadow=2.0,
        shadow_color=0x0000004DL,
        shadow_y=0.5,
        id~,
        fn() {
          @sf.icon(c, "arrow-down", size=18.0, color=t.p.text) |> ignore
          match count {
            Some(n) =>
              c.text(
                fill("android-chat.chat.newMessages", [("n", "\{n}")]),
                size=13.0,
                weight=500,
                color=t.p.text,
                wrap=false,
              )
              |> ignore
            None => ()
          }
        },
      )
      c.look(pill, look)
      // going, only drawn: a tap there goes to the rows under it
      @motion.leaving(c, pill, shown)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The bar's frame (Chat.kt BarFrame), the same while the chat is read and once it is: back, the title, what follows
/// it, what is at its end, and "…".
fn bar_frame(
  c : @ui.Ctx,
  title : String,
  after : () -> Unit,
  trailing : () -> Unit,
  more : Bool,
  room? : Double = 0.0,
  on_more? : () -> Unit = fn() {  },
) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), pl=4.0, pr=16.0, pt=6.0, pb=8.0, align=ACenter, fn() {
    let back = c.id("chat-back")
    if c.clicked(back) {
      app.nav.pop() |> ignore
    }
    c.box(
      w=Px(40.0),
      h=Px(40.0),
      radius=20.0,
      align=ACenter,
      justify=JCenter,
      bg=@sf.alpha(t.p.text, 0.08 * @motion.pressing(c, back)),
      id=back,
      fn() { @sf.icon(c, "chevron-left", size=22.0, color=t.p.accent) |> ignore },
    )
    |> ignore
    c.box(dir=Row, w=Fill(1.0), pr=8.0, gap=8.0, align=ACenter, fn() {
      // the title as long as there is room for it beside what follows it
      c.box(max_w=dmax(c.width - 4.0 - 40.0 - 16.0 - 8.0 - room, 40.0), fn() {
        c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false, line=22.0)
        |> ignore
      })
      |> ignore
      after()
    })
    |> ignore
    trailing()
    if more && nav_button(c, "more", 18.0, key="chat-more") {
      on_more()
    }
  })
  |> ignore
}

///|
/// The chat's bar (Chat.kt ChatBar): its title from the left, then its people, then its agents' marks (the first's
/// tile carrying the station it runs on); its services and jobs, its archive while nothing is left in it, and "…".
/// Frosted glass over the messages, a hairline under it.
fn chat_bar(c : @ui.Ctx, src : Source, w : Workspace, r : ChatRef, v : ChatView) -> Unit {
  let t = @sf.theme()
  let stations = stations_of((src.topic)("stations", { "scope": Json::string(w.id) }).value)
  let station = stations.iter().find_first(fn(s) { s.address == r.station })
  let jobs = (src.topic)("chatJobs", chat_params(r))
  let has_jobs = items(jobs.value, "jobs").length() > 0
  let archive = v.archivable && !v.archived
  let people = if v.people.length() > 5 { v.people[:5].to_array() } else { v.people }
  // what follows the title, as wide as it is drawn
  let mut room = 0.0
  if v.agents.length() == 0 {
    match station {
      Some(s) => room = room + 8.0 + station_tag_w(s)
      None => ()
    }
  }
  if people.length() > 0 {
    room = room + 8.0 + 19.0 + 14.0 * (people.length() - 1).to_double()
  }
  for i, a in v.agents {
    ignore(a)
    room = room + 8.0 + (if i == 0 && station is Some(_) { 46.0 } else { 22.0 })
  }
  room = room + (if v.thread is Some(_) { 34.0 } else { 0.0 }) +
    (if has_jobs { 34.0 } else { 0.0 }) +
    (if archive { 34.0 } else { 0.0 })
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    bar_frame(
      c,
      v.title,
      fn() {
        if v.agents.length() == 0 {
          match station {
            Some(s) => station_tag(c, s)
            None => ()
          }
        }
        if people.length() > 0 {
          people_stack(c, src, people, 16.0)
        }
        for i, a in v.agents {
          // each opens its card (AgentSheet.kt)
          let id = c.id("bar-agent/" + a.key)
          if c.clicked(id) {
            open_sheet(c, AgentOf(r, a.key))
          }
          c.box(id~, fn() {
            if i == 0 {
              agent_station_mark(c, a, station)
            } else {
              model_mark(c, a, 22.0)
            }
          })
          |> ignore
        }
      },
      fn() {
        if archive {
          if doing("archive/" + r.station + "/" + r.session) {
            c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() {
              @sf.spinner(c) |> ignore
            })
            |> ignore
          } else if nav_button(c, "archive", 20.0, key="chat-archive") {
            archive_chat(src, r, v)
          }
        }
        if has_jobs {
          // a dot when one died lately (red) or a service is started again (amber)
          let alarm = text(jobs.value, "alarm")
          c.box(fn() {
            if nav_button(c, "web", 20.0, key="chat-jobs") {
              dui.jobs_all = false
              open_sheet(c, JobsOf(r))
            }
            if alarm == "fail" || alarm == "restart" {
              c.layer(align=AEnd, fn() {
                c.box(pt=6.0, pr=6.0, fn() {
                  c.box(w=Px(11.0), h=Px(11.0), radius=5.5, bg=t.p.bg, pad=2.0, fn() {
                    c.box(
                      w=Fill(1.0),
                      h=Fill(1.0),
                      radius=3.5,
                      bg=if alarm == "fail" { t.p.red } else { 0xD9962BFFL },
                      fn() {  },
                    )
                    |> ignore
                  })
                  |> ignore
                })
                |> ignore
              })
              |> ignore
            }
          })
          |> ignore
        }
      },
      v.thread is Some(_),
      room~,
      on_more=fn() { open_sheet(c, Info(r)) },
    )
    c.box(w=Fill(1.0), h=Px(0.5), bg=t.p.line, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A station named in a small outlined tag (PageParts.kt StationTag): how it is reached as a dot, its mark, its name.
fn station_tag(c : @ui.Ctx, s : Station) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    max_w=104.0,
    padx=8.0,
    pady=2.0,
    gap=4.0,
    radius=12.0,
    border=1.0,
    border_color=t.p.line,
    align=ACenter,
    fn() {
      if s.via != "" {
        via_dot(c, s.via, 7.0, 0.0)
      }
      if @sf.has_station_mark(s.emoji, s.icon) {
        @sf.station_mark(c, s.emoji, s.icon, 12.0, t.p.muted)
      }
      c.box(fn() { c.text(s.name, size=12.0, color=t.p.muted, wrap=false, line=16.0) |> ignore })
      |> ignore
    },
  )
  |> ignore
}

///|
fn station_tag_w(s : Station) -> Double {
  let name = s.name.length().to_double() * 7.0
  dmin(
    104.0,
    16.0 +
    (if s.via != "" { 11.0 } else { 0.0 }) +
    (if @sf.has_station_mark(s.emoji, s.icon) { 16.0 } else { 0.0 }) +
    name,
  )
}

///|
/// How a station is reached (PageParts.kt StationViaDot): green direct, amber through the relay, red offline, a grey
/// ring while it is being reached; ringed in the page's ground on a tile's corner.
fn via_dot(c : @ui.Ctx, via : String, size : Double, ring : Double) -> Unit {
  let t = @sf.theme()
  let inner = size - ring * 2.0
  c.box(
    w=Px(size),
    h=Px(size),
    radius=size / 2.0,
    bg=if ring > 0.0 { t.p.bg } else { 0L },
    align=ACenter,
    justify=JCenter,
    fn() {
      match via {
        "direct" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.green, fn() {  })
          |> ignore
        "relay" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=0xD9962BFFL, fn() {  })
          |> ignore
        "offline" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.red, fn() {  })
          |> ignore
        _ =>
          c.box(
            w=Px(inner),
            h=Px(inner),
            radius=inner / 2.0,
            border=1.5,
            border_color=t.p.muted,
            fn() {  },
          )
          |> ignore
      }
    },
  )
  |> ignore
}

///|
/// An agent's state at its mark's corner (Parts.kt AgentStateMark): a 12 disc of the ground, red in it when it wants
/// someone, a turning yellow ring with a gap at work; nothing when done.
fn agent_state_mark(c : @ui.Ctx, badge : String) -> Unit {
  let t = @sf.theme()
  match badge {
    "run" =>
      c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.bg, align=ACenter, justify=JCenter, fn() {
        @sf.spinner(
          c,
          size=8.0,
          ring=@sf.alpha(mark_yellow, 0.25),
          arc=mark_yellow,
          sweep=0.75,
          period=1200.0,
        )
        |> ignore
      })
      |> ignore
    "block" | "failed" =>
      c.box(w=Px(12.0), h=Px(12.0), radius=6.0, bg=t.p.bg, align=ACenter, justify=JCenter, fn() {
        c.box(w=Px(8.0), h=Px(8.0), radius=4.0, bg=mark_red, fn() {  }) |> ignore
      })
      |> ignore
    _ => ()
  }
}

///|
/// An agent's mark (Parts.kt ModelMark, small, as a list's): its maker's mark on a soft tile, its state on the corner.
fn model_mark(c : @ui.Ctx, a : Agent, size : Double) -> Unit {
  let t = @sf.theme()
  c.box(w=Px(size), h=Px(size), fn() {
    c.box(
      w=Px(size),
      h=Px(size),
      radius=6.0,
      bg=t.p.card,
      border=1.0,
      border_color=t.p.line,
      align=ACenter,
      justify=JCenter,
      fn() { @sf.maker_mark(c, a.maker, a.runtime, size * 0.6) |> ignore },
    )
    |> ignore
    if a.badge != "" {
      c.layer(fn() {
        c.box(tx=size - 9.0, ty=size - 9.0, fn() { agent_state_mark(c, a.badge) }) |> ignore
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The chat's first agent with the station it runs on, one tile (PageParts.kt AgentStationMark): the maker's
/// square, then the station's mark or name; the agent's state on the maker's corner, how the station is reached on the
/// tile's. Until the station is known, the agent's mark alone.
fn agent_station_mark(c : @ui.Ctx, a : Agent, station : Station?) -> Unit {
  let t = @sf.theme()
  match station {
    None => model_mark(c, a, 22.0)
    Some(s) =>
      c.box(fn() {
        c.box(
          dir=Row,
          h=Px(22.0),
          radius=6.0,
          bg=t.p.card,
          border=1.0,
          border_color=t.p.line,
          align=ACenter,
          fn() {
            c.box(w=Px(22.0), h=Px(22.0), align=ACenter, justify=JCenter, fn() {
              @sf.maker_mark(c, a.maker, a.runtime, 13.2) |> ignore
            })
            |> ignore
            c.box(max_w=96.0, padx=5.0, align=ACenter, fn() {
              if @sf.has_station_mark(s.emoji, s.icon) {
                @sf.station_mark(c, s.emoji, s.icon, 13.0, t.p.muted)
              } else {
                c.text(s.name, size=12.0, color=t.p.muted, wrap=false, line=14.0)
                |> ignore
              }
            })
            |> ignore
          },
        )
        |> ignore
        c.layer(fn() {
          c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
            c.box(tx=13.0, ty=13.0, fn() { agent_state_mark(c, a.badge) }) |> ignore
            c.spacer()
            if s.via != "" {
              c.box(tx=3.0, ty=15.0, fn() { via_dot(c, s.via, 10.0, 2.0) }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
  }
}

///|
/// People overlapping a little, each ringed in the page's ground (Parts.kt PeopleStack).
fn people_stack(c : @ui.Ctx, src : Source, people : Array[Person], size : Double) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, align=ACenter, fn() {
    for i, p in people {
      c.box(
        w=Px(size + 3.0),
        h=Px(size + 3.0),
        radius=(size + 3.0) / 2.0,
        bg=t.p.bg,
        tx=-5.0 * i.to_double(),
        align=ACenter,
        justify=JCenter,
        fn() {
          avatar(
            c,
            src,
            if p.email != "" { p.email } else { p.id },
            if p.name != "" { p.name } else { p.email },
            p.picture,
            size,
          )
        },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// A person, round (Parts.kt Avatar): their picture once it is here, their initial on their colour until then.
fn avatar(
  c : @ui.Ctx,
  src : Source,
  id : String,
  name : String,
  picture : String,
  size : Double,
) -> Unit {
  let pic = if picture != "" { (src.picture)(picture) } else { "" }
  c.box(
    w=Px(size),
    h=Px(size),
    radius=size / 2.0,
    bg=avatar_color(id),
    align=ACenter,
    justify=JCenter,
    fn() {
      if pic != "" {
        c.image(pic, w=Px(size), h=Px(size), radius=size / 2.0, bg=0L) |> ignore
      } else {
        c.text(
          initial(name),
          size=size * 0.5,
          weight=600,
          color=0xFFFFFFFFL,
          wrap=false,
          line=size * 0.5,
        )
        |> ignore
      }
    },
  )
  |> ignore
}

///|
let shapes : Array[(Bool, Double, Double)] = [
  (false, 220.0, 40.0),
  (false, 160.0, 58.0),
  (true, 180.0, 40.0),
  (false, 240.0, 76.0),
  (true, 120.0, 40.0),
  (false, 200.0, 40.0),
]

///|
/// The chat read the first time (Waiting.kt Waiting, WaitShapes Messages): the messages to come breathing, theirs
/// with a picture on the left, the viewer's on the right; what could not be read over them in red (the shapes still).
fn waiting_messages(c : @ui.Ctx, failed : String?) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), fn() {
    match failed {
      Some(f) =>
        c.box(w=Fill(1.0), pl=20.0, pr=20.0, pt=14.0, pb=4.0, align=ACenter, fn() {
          c.box(padx=12.0, pady=6.0, radius=15.0, bg=t.p.chip, fn() {
            c.text(f, size=13.0, color=t.p.red, line=18.0, center=true) |> ignore
          })
          |> ignore
        })
        |> ignore
      None => ()
    }
    let breath = if failed is None { @sf.breath(c) } else { 0.6 }
    let most = c.width * 0.7
    c.box(w=Fill(1.0), pt=8.0, gap=14.0, opacity=breath, fn() {
      for s in shapes {
        let (mine, w, h) = s
        c.box(dir=Row, w=Fill(1.0), padx=16.0, justify=if mine { JEnd } else { JStart }, fn() {
          if !mine {
            c.box(w=Px(28.0), h=Px(28.0), radius=14.0, bg=t.p.neutral_bg, fn() {  })
            |> ignore
            c.box(w=Px(10.0), fn() {  }) |> ignore
          }
          c.box(w=Px(dmin(w, most)), h=Px(h), radius=18.0, bg=t.p.neutral_bg, fn() {  })
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// MBUI_CHAT_BENCH=1: once the chat is in place, the pages before are brought in (held at its top) until it has 3000
/// messages or no more (a minute at most); then from its end it is scrolled up 600 frames at 40 a frame, and the
/// frames' times are said (CHATBENCH …) and the app ends.
let bench_on : Ref[Int] = { val: -1 }

///|
fn chat_bench(c : @ui.Ctx, key : String, rd : Reading, more : Bool, rows : Int) -> Unit {
  if bench_on.val < 0 {
    bench_on.val = if @host.env("MBUI_CHAT_BENCH") != "" { 1 } else { 0 }
  }
  if bench_on.val == 0 || !rd.placed {
    return
  }
  rd.bench = rd.bench + 1
  c.request_frame()
  if rd.bench_phase == 0 {
    if rows != rd.bench_rows {
      rd.bench_rows = rows
      @host.log("CHATBENCH rows=\{rows} after \{rd.bench} frames")
    }
    if more && rows < 3000 && rd.bench < 3600 {
      c.list_scroll_to(key, 0)
      return
    }
    rd.bench_phase = 1
    rd.bench = 0
    c.list_to_end(key, glide=false)
    return
  }
  // settled first (a second), then measured: each frame's build, layout and paint, and its present
  if rd.bench <= 60 {
    return
  }
  if rd.bench > 61 {
    rd.bench_ms.push(c.frame_ms())
    rd.bench_present.push(c.present_ms())
  }
  if rd.bench <= 660 {
    c.list_scroll_by(key, -40.0)
    return
  }
  if rd.bench == 661 {
    let a = rd.bench_ms.copy()
    a.sort_by(fn(x, y) { x.compare(y) })
    let n = a.length()
    let mut sum = 0.0
    let mut slow = 0
    for x in rd.bench_ms {
      sum = sum + x
      if x > 8.0 {
        slow = slow + 1
      }
    }
    let mut psum = 0.0
    for x in rd.bench_present {
      psum = psum + x
    }
    let info = c.list_info(key)
    let rows = match info {
      Some(i) => i.count
      None => 0
    }
    @host.log(
      "CHATBENCH frames=\{n} rows=\{rows} cpu_avg=\{sum / n.to_double()} cpu_p50=\{a[n / 2]} " +
      "cpu_p95=\{a[n * 95 / 100]} cpu_p99=\{a[n * 99 / 100]} cpu_max=\{a[n - 1]} slow(>8ms)=\{slow} " +
      "present_avg=\{psum / n.to_double()}",
    )
    @host.exit(0)
  }
}
