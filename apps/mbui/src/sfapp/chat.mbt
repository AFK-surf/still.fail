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
  /// a run of what other chats' agents wrote to it, as its first message has it (the core's `letters`): its line
  Letters(Message)
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
    Letters(m) => "l:" + m.ts
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
/// The title's line in the bar (Chat.kt BarFrame: a Text with no line height of its own, 16 on the theme's 1.4em).
let chat_title_line : Double = 16.0 * 1.4

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
  /// put in place once (the unread line, where it was opened, or the end)
  mut placed : Bool
  mut put : Bool
  /// the first message when the page before was asked for (once per page)
  mut asked : Double
  mut asked_newer : Double
  /// the message gone to that the core was asked to show the run of what other chats' agents wrote around (once)
  mut around_asked : Double
  /// what the core was told of the chat shown, its end seen or not ("" nothing yet)
  mut told : String
  /// the newest message seen whole on this visit (-1 none): read up to there
  mut seen_whole : Double
  /// where the reader is: the message at the top of what shows (-1 none), and whether at the chat's end
  mut top_seq : Double
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
  /// the frame its page was last built in, and its own data last taken in (chat_tick: what comes out of its avatars
  /// played on, its activities' lingering)
  mut shown_frame : Int
  mut played : Int
  mut ticked : Int
  fresh : Map[String, Bool]
  /// rows asked a turn to come in (turns.mbt: Chat.kt admitted); each row's rise in, by key, while it rises
  admitted : Map[String, Bool]
  rises : Map[String, @motion.Anim]
  /// when the list's own motion is at rest, as last laid out (ListInfo's `rest`): a turn waits for it
  mut list_rest : Double
  /// the newest row (not an agent's line) as last built, and whether the list follows one from its top (Follow.kt
  /// anchor: a message arriving while it is followed is read from its start)
  mut newest : String
  mut following_row : Bool
  mut follow_key : String
  /// the outbox entries messages were sent from here as, by seq (their rows go on being those: Chat.kt sentAs)
  sent : Map[Double, String]
  /// agents whose turn ended, still shown a moment (Chat.kt lingering: 600 ms, then fading 220): Lingering
  linger : Map[String, Lingering]
  /// the agents running as last drawn
  running : Map[String, Agent]
  /// a message gone to (a notification's, "" none: ChatMotion.kt flashed) and how lit it is (flash_of)
  mut flash : String
  flash_lit : @motion.Anim
  /// flashes started (each one's own hold, with motion reduced)
  mut flash_n : Int
  /// a message the search opened the chat at (ChatMotion.kt foundAt, "" none) and its words marked in it (`found`),
  /// for as long as the chat shows; how far their strokes are drawn in (ms of drawFound's); its first word yet to be
  /// put in the list's middle when it lies low (Chat.kt rememberJump's FOUND)
  mut found_at : String
  mut found_words : Array[String]
  found_drawn : @motion.Anim
  mut found_centre : Bool
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
        put: false,
        asked: -1.0,
        asked_newer: -1.0,
        around_asked: -1.0,
        told: "",
        seen_whole: -1.0,
        top_seq: -1.0,
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
        shown_frame: -10,
        played: -10,
        ticked: -10,
        fresh: {},
        admitted: {},
        rises: {},
        list_rest: -1.0,
        newest: "",
        following_row: false,
        follow_key: "",
        sent: {},
        linger: {},
        running: {},
        flash: "",
        flash_lit: @motion.Anim::new(0.0),
        flash_n: 0,
        found_at: "",
        found_words: [],
        found_drawn: @motion.Anim::new(0.0),
        found_centre: false,
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
/// Where a chat was left this run (AppState.places, Chat.kt leave): the message at the top of what showed (its seq) and
/// how far its top was below the list's (points); and, left at its end, the newest message then (else -1). It opens
/// there again before where the core says (`at`): the chat's view can outlive its page (opened again before the core
/// lets it go, a minute after: store.ts EVICT_AFTER_MS) and still say where it was opened the first time.
priv struct KeptPlace {
  top : Double
  offset : Double
  bottom : Double
}

///|
let kept_places : Map[String, KeptPlace] = {}

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
    // the first of a run of what other chats' agents wrote to it: the run's line, the message only open
    match m.letters {
      Some(l) => {
        out.push(Letters(m))
        if l.open {
          out.push(Said(m))
        }
      }
      None => out.push(Said(m))
    }
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
  // over the navigation bar (ChatHost.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
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
          // over the navigation bar (a layer goes on under the page's padding)
          bar_room_box(c, nav_foot())
        })
        |> ignore
      }
      Some(v) => {
        messages(c, src, r, v, list)
        c.layer(fn() { chat_bar(c, src, w, r, v) }) |> ignore
        c.layer(fn() {
          c.spacer()
          composer(c, src, r, Some(v))
          // over the navigation bar (a layer goes on under the page's padding)
          bar_room_box(c, nav_foot())
        })
        |> ignore
        // words sent, as typed, until their row is in the list (flight.mbt)
        flight_waiting(c, draft_key(r))
        // and the files sent with them, from their tiles to their places (flight.mbt)
        flight_files(c, draft_key(r))
        // a passage picked: its handles and its bar over the list (pick.mbt)
        pick_layer(c, src, r)
        // a link held: its menu (link_menu.mbt)
        link_menu_layer(c)
        // the station's update opened under the bar's word (station_update.mbt)
        station_update_popover(c, src, r.station, v.station_update)
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
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt, ChatMotion.kt)
  // (taken and played on, before the page is built, by linger_tick)
  let ek = r.station + "\u{1}" + r.session
  let em = emits_of(ek)
  rd.shown_frame = c.frame_number()
  chat_tick(c, ek, rd, v, shown=true)
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
  let dkey = draft_key(r)
  let turns = turns_of(ek)
  let (list, keys) = row_keys(c, rd, v, with_lingering(rd, read), key, turns, em, flight_of(dkey))
  follow_newest(c, rd, list, keys, key)
  flight_frame(c, dkey)
  let flight = flight_of(dkey)
  // half a second after it was put in place (shown), what comes at its end may glide: asked each frame it is drawn
  // (later: nothing shown waits for it)
  let glides = @kit.after(c, "glide/" + key, rd.placed, glide_after_place_ms, later=true)
  @motion.list_keys(c, key, keys.map(fn(k) { key + "\u{1}" + k })) |> ignore
  let here = { station: r.station, session: r.session, view: v }
  // the first message's row: the page before come in above it, it stays where it is (Chat.kt: the list keeps its
  // first item in view by its key, or the first row after the spinner)
  let mut head = ""
  let mut head_at = -1
  for i, e in list {
    if e is (Said(_) | Letters(_)) {
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
  // a message gone to, flashing: its words' bubble (yours) or a ground under its row (flash.mbt's underlay)
  flashing.val = (rd.flash, flash_of(c, rd, rd.flash))
  // a search's words marked in the message it opened the chat at (search_marks.mbt)
  found_marking.val = (rd.found_at, rd.found_words, rd.found_drawn.get())
  found_centre(c, rd, key)
  flash_row.val = None
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
          Top => c.box(h=Px(status_top() + chat_bar_h + 14.0), fn() {  }) |> ignore
          Foot => c.box(h=Px(composer_room_for(c, draft_key(r), Some(v)) + 10.0), fn() {  }) |> ignore
          Working(a) => {
            // coming in, its room opens (220 ms, Ease.Out) as it fades in and grows from its avatar; its turn over,
            // it stays a moment and fades (Chat.kt Activity)
            let mk = key + "\u{1}" + keys[i]
            let open = @motion.anim(c, "open/" + mk, 1.0, global=true)
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              open.snap(0.0)
              // from when its turn came (turns.mbt), else now
              let at = turns.started_at(keys[i])
              open.animate(1.0, @motion.tween(working_turn_ms, ease=Out), start_at?=if at >= 0.0 { Some(at) } else { None })
            }
            let leaving = match rd.linger.get(a.key) {
              Some(l) => l.leaving
              None => false
            }
            let fade = @motion.animate(
              c,
              "fade/" + mk,
              if leaving { 0.0 } else { 1.0 },
              spec=@motion.tween(linger_out_ms),
            )
            let p = open.get()
            @motion.reveal(c, mk, p, fn() {
              let ri = c.box(w=Fill(1.0), pl=row_side(c), pr=row_side(c), pt=top, fn() {
                activity(c, src, here, a, leaving~)
              })
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(200.0)))
              // pushed down by what comes in above it, it glides there (Chat.kt ACTIVITY_GLIDE: spring(1, 300)), not
              // while its avatar is away flying
              if !older_came && flight is None && !emit_away(em, a.key) {
                @motion.layout(c, ri, mk, spec=@motion.spring(stiffness=300.0, threshold=1.0), listed=false)
              }
              c.look(ri, @ui.look(alpha=p * fade, scale=0.5 + 0.5 * p, ox=(row_side(c) + 9.0) / c.width, oy=0.5))
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
            let ri = c.box(w=Fill(1.0), pl=row_side(c), pr=row_side(c), pt=top, fn() {
              entry_view(c, src, here, e, list)
            })
            flying.val = None
            match e {
              Said(m) if m.ts == flashing.val.0 && flashing.val.1 > 0.0 && !m.system && !(m.mine && m.text != "") =>
                flash_under(c, ri, top, flashing.val.1)
              _ => ()
            }
            match flight {
              Some(_) if flies => {
                // flown in, it does not rise in as well
                rd.known[keys[i]] = true
                rd.fresh.remove(keys[i]) |> ignore
              }
              // the rows above go up with the words (ChatHost.kt sendReflow)
              Some(f) if f.placed =>
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
              @motion.keyed(c, ri, mk, exit=@motion.trans(fade=0.0, spec=@motion.tween(out_leave_ms)))
            } else {
              @motion.keyed(c, ri, mk)
            }
            // (one out of an avatar does not rise in as well)
            let emitted = match e {
              Said(m) => emit_goes(em, m.seq)
              _ => false
            }
            if rd.fresh.contains(keys[i]) {
              rd.fresh.remove(keys[i])
              if !emitted {
                // from when its turn came (turns.mbt), else now
                let a = @motion.Anim::new(0.0)
                let at = turns.started_at(keys[i])
                a.animate(1.0, @motion.tween(row_turn_ms, ease=Standard), start_at?=if at >= 0.0 { Some(at) } else { None })
                rd.rises[keys[i]] = a
              }
            }
            match rd.rises.get(keys[i]) {
              Some(a) => {
                let p = a.get()
                if !a.moving() && p >= 1.0 {
                  rd.rises.remove(keys[i]) |> ignore
                } else {
                  c.look(ri, @ui.look(alpha=p, dy=rise_dy * (1.0 - p)))
                }
              }
              None => ()
            }
          }
        }
      },
      stick_end=true,
      // what comes at the end while it follows is glided after (Follow.kt), half a second after it was put in place,
      // not while words sent fly (they put the list in place)
      glide_on_growth=glides && flight is None,
    )
    |> ignore
    // put in place once: at the unread line (a few lines of what came before it in view), else where the core opened
    // it, else at its end (where the list starts)
    if !rd.placed && v.messages.length() > 0 && !v.unread_above {
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
      if line >= 0 {
        c.list_scroll_to(key, line, offset=-(status_top() + chat_bar_h + 14.0 + 85.0))
      } else if was >= 0 {
        c.list_scroll_to(key, was, offset=-kept.unwrap().offset)
      } else if at >= 0 {
        // where it was left: that message's top as far below the list's as it was (atOffset, the screen's pixels);
        // else its top under the bar
        c.list_scroll_to(key, at, offset=match v.at_offset {
          Some(px) => -(px / c.scale)
          None => -(status_top() + chat_bar_h + 14.0)
        })
      }
    }
    // opened at a message (a notification's), once the list is in place (the build after it was put there, in the same
    // frame): there, its top under the bar,
    // flashing; the pages before brought in until it is (none left, or it is gone: where the chat opened). Chat.kt
    // LaunchedEffect(host.goTo)
    let gk = r.station + "\u{1}" + r.session
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
                  None => rd.flash = m.ts
                }
                break
              }
            }
            _ => ()
          }
        }
        if at >= 0 {
          go_tos.remove(gk)
          if found {
            found_start(rd)
          } else {
            flash_start(rd)
          }
          c.list_scroll_to(key, at, offset=-(status_top() + chat_bar_h + 14.0))
          @hostapi.log("chat: gone to message \{target.to_int()}")
        } else {
          match v.thread {
            Some(thread) if v.more && first > target =>
              if rd.asked != first {
                rd.asked = first
                // (asked once the frame's builds are over)
                c.tell("chat.older/" + gk, fn() {
                  (src.call)(
                    "chat.older",
                    { "station": Json::string(r.station), "thread": Json::number(thread) },
                    fn(res) { if res is Err(_) { go_tos.remove(gk) } },
                  )
                })
              }
            // among what other chats' agents wrote to it, folded: the core asked to show it (their run comes
            // whole, and this again finds it)
            Some(thread) if rd.around_asked != target &&
              v.messages.iter().any(fn(m) { m.letters is Some(l) && !l.open }) => {
              rd.around_asked = target
              c.tell("chat.around/" + gk, fn() {
                (src.call)(
                  "chat.around",
                  { "station": Json::string(r.station), "thread": Json::number(thread), "seq": Json::number(target) },
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
    let info = c.list_info(key)
    // near the top: the page before comes in, once per page
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.more && rd.placed && i.first >= 0 && i.first <= 3 => {
        let first = match list.iter().find_first(fn(e) { e is Said(_) }) {
          Some(Said(m)) => m.seq
          _ => -1.0
        }
        // (asked once the frame's builds are over, from where the last laid the list out)
        if rd.asked != first {
          c.after_build("older", fn() {
            if rd.asked == first {
              return
            }
            rd.asked = first
            (src.call)(
              "chat.older",
              { "station": Json::string(r.station), "thread": Json::number(thread) },
              fn(res) {
                match res {
                  Err(e) => {
                    rd.asked = -1.0
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
    // near the end of a window short of the chat's: the page after
    match (info, v.thread) {
      (Some(i), Some(thread)) if v.newer && rd.placed && i.last >= n - 4 => {
        let last = match v.messages.last() {
          Some(m) => m.seq
          None => -1.0
        }
        if rd.asked_newer != last {
          c.after_build("newer", fn() {
            if rd.asked_newer == last {
              return
            }
            rd.asked_newer = last
            (src.call)(
              "chat.newer",
              { "station": Json::string(r.station), "thread": Json::number(thread) },
              fn(res) { if res is Err(_) { rd.asked_newer = -1.0 } },
            )
          })
        }
      }
      _ => ()
    }
    // the core told the chat shows, and whether its end does (what is read follows): not on a read-only run
    // (its end in view: not while it glides to rows that came, as Android's Chat.kt has it (endInView, lastLaidOut):
    // rows not in view yet are not read)
    let seen = match info {
      Some(i) => !v.newer && i.at_end
      None => false
    }
    rd.at_end = seen
    // the last message wholly in view, between the bar and the composer, while it is not short of the chat's end:
    // read up to there (a message shown whole on a page in front is read), its end seen or not
    match (info, c.list_place(key)) {
      (Some(i), Some((first, past, _))) if i.first >= 0 && !v.newer => {
        let top = status_top() + chat_bar_h
        let foot = i.height - composer_room_for(c, draft_key(r), Some(v))
        let mut y = -past
        let mut k = first
        while k <= i.last && k < n {
          let h = c.list_row_height(key, k).unwrap_or(0.0)
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
    // that message's top, below the list's (the first row in view scrolled past its top, the rows over it)
    rd.top_off = match (info, c.list_place(key)) {
      (Some(i), Some((first, past, _))) if i.first >= 0 => {
        let mut y = -past
        let mut k = first
        while k < n && !(list[k] is Said(_)) {
          y = y + c.list_row_height(key, k).unwrap_or(0.0)
          k = k + 1
        }
        y
      }
      _ => 0.0
    }
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
    jump_to_latest(c, src, r, v, rd, away || v.newer)
    // what waits to be decided and does not show: a bell over the way to the end (Chat.kt JumpToAsk)
    rd.ask = jump_to_ask(c, r, v, list, info, away || v.newer)
    // the avatar flying out of an activity to its message and back, over the list
    emit_flyer(c, ek, em, v)
    chat_bench(c, key, rd, v.more, n)
  })
  |> ignore
}

///|
/// How long what leaves the chat from the outbox (sent, or deleted) takes to fade.
pub let out_leave_ms : Double = 200.0

///|
/// How far a row new to the list comes up as it fades in (Chat.kt rise: 14, over its turn's 320 ms, the standard
/// curve).
let rise_dy : Double = 14.0

///|
/// How long after a chat is put in place what comes at its end glides after it (Follow.kt).
let glide_after_place_ms : Double = 500.0

///|
/// An activity whose agent's turn ended stays this long, then fades (`linger_out_ms`), then is gone.
let linger_fade_ms : Double = 600.0

///|
let linger_out_ms : Double = 220.0

///|
/// An activity's whole stay once its agent's turn ended: there, then faded.
pub let linger_ms : Double = linger_fade_ms + linger_out_ms

///|
/// An agent whose turn ended, its activity still shown (with_lingering): its moment's count (anew each time its
/// messages stop coming out of its avatar), past its 600 ms (fading).
struct Lingering {
  agent : Agent
  mut n : Int
  mut leaving : Bool
}

///|
/// Each frame, before any page is built, whatever page shows: from each chat kept's own data (its agents running, its
/// messages coming out of an avatar), whose activity stays a moment as its turn ends, and how long, counted by the
/// framework (@kit.after) from the build that sees the turn over; a chat under another page lingers on the time that
/// goes by, as Chat.kt's. The chat's page draws what it says.
fn linger_tick(c : @ui.Ctx, src : Source) -> Unit {
  for rk, rd in readings {
    // every chat kept whose data the page read: its activities linger on the time that goes by, its page shown or not
    if !read_chats.contains(rk) {
      continue
    }
    let (station, session) = match rk.find("\u{1}") {
      Some(i) => (rk.view(end_offset=i).to_owned(), rk.view(start_offset=i + 1).to_owned())
      None => continue
    }
    match view_of_chat(src, { station, session, title: "", station_name: "" }).0 {
      Some(v) => chat_tick(c, rk, rd, v, shown=rd.shown_frame >= c.frame_number() - 1)
      None => ()
    }
  }
}

///|
/// A chat's own data, once a frame, before its page is built (linger_tick; its page the first frame it shows): what
/// comes out of its avatars played on, whose activity stays a moment and how long.
fn chat_tick(c : @ui.Ctx, rk : String, rd : Reading, v : ChatView, shown~ : Bool) -> Unit {
  let frame = c.frame_number()
  let lingered = rd.ticked == frame
  let played = rd.played == frame
  if lingered && (played || !shown) {
    return
  }
  let running : Map[String, Agent] = {}
  if !v.newer {
    for a in v.agents {
      if a.status == "running" {
        running[a.key] = a
      }
    }
  }
  // an agent's messages said while its activity shows come out of its avatar, one at a time; until their turn they
  // wait out of the list (emit.mbt, ChatMotion.kt). (Once under way, it goes on while the end is near: the answer
  // coming in grows the list under the reader, who is a moment short of its end until the list follows; only
  // scrolled away, as the way to the newest shows, it ends.)
  // (played on while its page shows: under another page it waits where it is, as before)
  let em = emits_of(rk)
  if shown && !played {
    rd.played = frame
    // what changes the list's height, one at a time (turns.mbt): each whose turn has come starts
    let turns = turns_of(rk)
    turns.step(c, rd.list_rest)
    let playing = em.current is Some(_) || em.queue.length() > 0
    em.watched = (rd.at_end || rd.following_row || (playing && !rd.jump)) && !v.newer && app_in_front()
    let showing : Map[String, Bool] = {}
    for k, _ in running {
      showing[k] = true
    }
    for k, _ in rd.linger {
      showing[k] = true
    }
    emit_take(c, em, v, showing)
    emit_step(c, em, turns)
  }
  if lingered {
    return
  }
  rd.ticked = frame
  // its turn over: it stays a moment
  for k, a in rd.running {
    if !running.contains(k) && !rd.linger.contains(k) {
      rd.linger[k] = { agent: a, n: 0, leaving: false }
    }
  }
  rd.running.clear()
  for k, a in running {
    rd.running[k] = a
  }
  // while its messages still come out of its avatar it stays whole (ChatMotion.keeps): each build they are still coming
  // it takes a new count (`n`, its timers' keys), so the count it keeps, asked first in the last of those builds, runs
  // from there (linger_wbtest: fading 600 ms, gone 820 after the last frame they came)
  let keeps = emit_keeps(em)
  let over : Array[String] = []
  for k, l in rd.linger {
    if running.contains(k) {
      over.push(k)
      continue
    }
    if keeps.contains(k) {
      l.n += 1
    }
    let at = "linger/" + rk + "/" + k + "/\{l.n}"
    let held = keeps.contains(k)
    // (asked while held too: its count starts at the last build they were still coming)
    let faded = @kit.after(c, at + "/fade", true, linger_fade_ms)
    l.leaving = !held && faded
    if @kit.after(c, at + "/gone", true, linger_ms) && !held {
      over.push(k)
    }
  }
  for k in over {
    rd.linger.remove(k)
  }
}

///|
/// The list with the activities of agents whose turn just ended, kept a moment (Chat.kt: 600 ms, then fading 220).
fn with_lingering(rd : Reading, list : Array[Entry]) -> Array[Entry] {
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
    out.push(Working(l.agent))
  }
  match foot {
    Some(f) => out.push(f)
    None => ()
  }
  out
}

///|
/// The rows in the list and their keys, as they move (a message sent from here keeps its outbox row's: Chat.kt
/// sentAs), and which are new: what comes while the list follows its end and the chat shows, not caught up on (Chat.kt
/// arrived, caught). What comes then (a message simply coming in, an agent's line, an outbox entry) comes in its turn
/// among what changes the list's height (turns.mbt, Chat.kt newcomers), kept out of the list till then; so are the
/// words sent from here (`flight`) till theirs.
fn row_keys(
  c : @ui.Ctx,
  rd : Reading,
  v : ChatView,
  all : Array[Entry],
  key : String,
  turns : Turns,
  em : Emits,
  flight : SendFlight?,
) -> (Array[Entry], Array[String]) {
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
  let all_keys = all.map(fn(e) {
    match e {
      Said(m) =>
        match rd.sent.get(m.seq) {
          Some(o) => "o:" + o
          None => e.id()
        }
      _ => e.id()
    }
  })
  let info = c.list_info(key)
  let following = match info {
    Some(i) => i.at_end || i.gliding || i.following_row
    None => true
  }
  rd.following_row = match info {
    Some(i) => i.following_row
    None => false
  }
  rd.list_rest = match info {
    Some(i) => i.rest
    None => -1.0
  }
  // words sent from here (a flight's): their row, the first of this device's own not there when they were sent
  let sent_row = fn(e : Entry, k : String) {
    match flight {
      Some(f) =>
        !f.before.contains(k) &&
        (match e {
          Out(_) => true
          Said(m) => m.mine && !m.system
          _ => false
        })
      None => false
    }
  }
  if rd.drawn && following {
    for i, e in all {
      let k = all_keys[i]
      if rd.known.contains(k) || rd.admitted.contains(k) || sent_row(e, k) {
        continue
      }
      let comes = match e {
        Working(a) => a.started
        Out(_) => true
        // (one out of an avatar comes out of it instead)
        Said(m) => m.said && !emit_goes(em, m.seq)
        Letters(m) => m.said
        _ => false
      }
      if comes {
        rd.admitted[k] = true
        match e {
          // (after what closes under a post as its agent starts)
          Working(_) => turns.admit(c, k, working_turn_ms, after=true)
          _ => turns.admit(c, k, row_turn_ms)
        }
      }
    }
  }
  let list : Array[Entry] = []
  let keys : Array[String] = []
  for i, e in all {
    let k = all_keys[i]
    if turns.waiting.contains(k) || (turns.send_waiting && sent_row(e, k)) {
      continue
    }
    list.push(e)
    keys.push(k)
  }
  if rd.drawn && following {
    for i, e in list {
      let caught = match e {
        Said(m) | Letters(m) => !m.said
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
  (list, keys)
}

///|
/// The newest row (a message, an outbox entry; not an agent's line, which folds away) come while the list follows its
/// end: followed from its top, its top follow_margin under the bar (Chat.kt newestKey, Follow.kt anchor), not past its
/// end; the row kept by its key as rows come and go round it.
fn follow_newest(c : @ui.Ctx, rd : Reading, list : Array[Entry], keys : Array[String], key : String) -> Unit {
  let mut at = -1
  for i, e in list {
    match e {
      Working(_) | Foot | Newer => ()
      _ => at = i
    }
  }
  let newest = if at >= 0 { keys[at] } else { "" }
  let following = match c.list_info(key) {
    Some(i) => i.at_end || i.gliding || i.following_row
    None => false
  }
  let came = rd.placed && rd.newest != "" && newest != rd.newest && following
  if came {
    rd.follow_key = newest
  }
  rd.newest = newest
  // (by its index as the rows stand now, while the list holds it: the reader's scroll lets it go)
  if came || rd.following_row {
    match keys.search(rd.follow_key) {
      Some(i) => c.list_follow_from(key, i, margin=status_top() + chat_bar_h + 14.0 + follow_margin)
      None => ()
    }
  }
}

///|
/// How far under the list's room at its top a row followed from its top stops (Chat.kt followMargin).
let follow_margin : Double = 12.0

///|
/// The message each chat is to go to once its list is in place (Screen.Chat.at: a notification's), by chat.
let go_tos : Map[String, Double] = {}

///|
/// The chat `r`, once open and in place, goes to its message `seq` (the pages before it brought in until it is
/// there), which flashes (ChatHost.kt goTo).
fn go_to(r : ChatRef, seq : Double) -> Unit {
  go_tos[r.station + "\u{1}" + r.session] = seq
}

///|
/// A chat opened over Home from the start at its message `seq`, as a notification opens it; `held`: its flash kept at
/// its peak (screenshots of it).
pub fn open_chat_at(r : ChatRef, seq : Double, held? : Bool = false) -> Unit {
  flash_held.val = held
  go_to(r, seq)
  app.nav.push(Chat(r))
}

///|
let flash_held : Ref[Bool] = Ref(false)

///|
/// The words a search opened each chat at its message with (Screen.Chat.words), by chat: marked in that message
/// rather than it flashing (Chat.kt host.goToWords).
let go_to_words : Map[String, Array[String]] = {}

///|
/// The chat `r` opened from the search at its message `seq`, the search's `words` marked there (Search.kt FoundRow).
fn open_chat_found(r : ChatRef, seq : Double, words : Array[String]) -> Unit {
  go_to(r, seq)
  if words.length() > 0 {
    go_to_words[r.station + "\u{1}" + r.session] = words
  }
  app.nav.push(Chat(r))
}

///|
/// A message gone to flashes (ChatMotion.kt flash): the accent's ground in over `flash_in_ms` on Ease.Out, held to
/// `flash_held_ms`, gone by `flash_ms` on the standard curve.
let flash_in_ms : Double = 160.0

///|
let flash_held_ms : Double = 900.0

///|
let flash_ms : Double = 1700.0

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
fn flash_start(rd : Reading) -> Unit {
  rd.flash_n += 1
  rd.flash_lit.snap(0.0)
  rd.flash_lit.animate(
    0.0,
    @motion.keyframes_to(
      [1.0, 1.0, 0.0],
      duration=flash_ms,
      times=[0.0, flash_in_ms / flash_ms, flash_held_ms / flash_ms, 1.0],
      eases=[
        fn(t) { @motion.Ease::Out.at(t) },
        fn(t) { t },
        fn(t) { @motion.Ease::Standard.at(t) },
      ],
    ),
  )
}

///|
/// How much a message gone to is lit now (flash_start); 0 for any other message. With motion reduced it is lit whole
/// for `flash_ms`, then not: less motion, not less said (which message it went to).
fn flash_of(c : @ui.Ctx, rd : Reading, ts : String) -> Double {
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
let at_end_env : Ref[Int] = { val: -1 }

///|
fn at_end_asked() -> Bool {
  if at_end_env.val < 0 {
    at_end_env.val = if @ui.env("MBUI_CHAT_AT_END") == "1" { 1 } else { 0 }
  }
  at_end_env.val == 1
}

///|
/// Tells the core the chat shows, its end seen or not (Chat.kt: `client.focus` with `chat`), and the last message seen
/// whole (`seen`), as either changes; it marks what is read and where the unread line goes. Never with
/// Source.readonly.
fn tell_focus(
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
/// Where the chat is, told the core (`chat.place`, Chat.kt leave): the message at the top and how far its top is below
/// the list's (in the screen's pixels, as Android's app tells it), none at its end; told again only where that moved.
fn tell_place(src : Source, r : ChatRef, v : ChatView, rd : Reading) -> Unit {
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
/// The chat left (its page gone): the core told it shows no more, and where it was left (`chat.place`: the message
/// at the top, none at its end). Never with Source.readonly.
fn chat_left(src : Source, r : ChatRef) -> Unit {
  let k = r.station + "\u{1}" + r.session
  match (read_chats.get(k), readings.get(k)) {
    (Some((_, v, _)), Some(rd)) if !src.read_only => {
      (src.call)("client.focus", { "left": focus_chat(r, v, None) }, fn(_) {  })
      match v.thread {
        Some(_) if rd.placed => tell_place(src, r, v, rd)
        _ => ()
      }
    }
    _ => ()
  }
  composer_left(src, r)
  readings.remove(k)
  // what holds the chat's thread at the core with it (its jobs in the bar and their sheets, the images beside one
  // opened from it): while any is held the core keeps the thread's window as first read, and the chat opened again
  // where it was first opened, not where it was left (views.ts: chatJobs and imageNear are of the chat's topic)
  (src.leave)("chat", chat_params(r))
  (src.leave)("chatJobs", chat_params(r))
  near_left(src, r.station)
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
  // (whether it shows, said before it may be gone: gone, nothing below is built, and what it was would stay)
  rd.jump = shown
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
    // (in the wide frame right over the send button, the composer's column in the pane's middle: Chat.css.ts)
    c.box(pr=if wide_on.val { (c.width - dmin(c.width - 24.0, column_w + 44.0)) / 2.0 + 6.0 } else { 18.0 }, pb=composer_room_for(c, draft_key(r), Some(v)) + 2.0, fn() {
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
        shadow=@sf.floating.sigma,
        shadow_color=@sf.floating.color,
        shadow_y=@sf.floating.dy,
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
/// Which of the chat's asks the bell went to last, by chat (it goes to the next one each time, round again).
let ask_turns : Map[String, Int] = {}

///|
/// How long the bell rises over the way to the end as that comes, and goes back down.
let ask_lift_ms : Double = 200.0

///|
/// The way to what waits to be decided in the chat (Chat.kt JumpToAsk, web Chat.tsx useAsksShown): its asks whose
/// posts are not all in view (one not loaded counts as not in view), a bell (no words) floating where the way to the
/// end goes, over it while that shows; tapped, the list goes to an ask's post (as a notification's does: go_to), then
/// the next one's, round again. It comes and goes as the way to the end does. None in an archived chat.
fn jump_to_ask(
  c : @ui.Ctx,
  r : ChatRef,
  v : ChatView,
  list : Array[Entry],
  info : @ui.ListInfo?,
  to_end : Bool,
) -> Bool {
  let t = @sf.theme()
  let asks = if v.archived || v.thread is None { [] } else { v.asks }
  let in_view = asks.length() > 0 &&
    asks.iter().all(fn(seq) {
      let mut at = -1
      for i, e in list {
        match e {
          Said(m) if m.seq == seq => {
            at = i
            break
          }
          _ => ()
        }
      }
      match info {
        Some(i) => at >= 0 && at >= i.first && at <= i.last
        None => false
      }
    })
  let shown = asks.length() > 0 && !in_view
  let look = match
    @motion.presence(
      c,
      "chat-ask",
      shown,
      enter=@motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(220.0), fade_spec=@motion.tween(180.0, ease=Css)),
      exit=@motion.trans(fade=0.0, scale=0.6, dy=18.0, spec=@motion.tween(180.0), fade_spec=@motion.tween(150.0, ease=Css)),
    ) {
    Some(l) => l
    None => return shown
  }
  let lift = @motion.animate(c, "chat-ask/lift", if to_end { 44.0 } else { 0.0 }, spec=@motion.tween(ask_lift_ms, ease=Standard))
  let id = c.id("chat-ask")
  if c.clicked(id) && shown {
    let k = r.station + "\u{1}" + r.session
    let turn = ask_turns.get(k).unwrap_or(0)
    go_to(r, asks[turn % asks.length()])
    ask_turns[k] = turn + 1
  }
  c.layer(align=AEnd, fn() {
    c.spacer()
    c.box(pr=if wide_on.val { (c.width - dmin(c.width - 24.0, column_w + 44.0)) / 2.0 + 6.0 } else { 18.0 }, pb=composer_room_for(c, draft_key(r), Some(v)) + 2.0 + lift, fn() {
      let bell = c.box(
        w=Px(36.0),
        h=Px(36.0),
        radius=18.0,
        align=ACenter,
        justify=JCenter,
        glass=@sf.glass_floating(),
        shadow=@sf.floating.sigma,
        shadow_color=@sf.floating.color,
        shadow_y=@sf.floating.dy,
        id~,
        fn() { @sf.icon(c, "bell", size=18.0, color=t.p.text) |> ignore },
      )
      c.look(bell, look)
      @motion.leaving(c, bell, shown)
    })
    |> ignore
  })
  |> ignore
  shown
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
  on_more? : () -> Unit = fn() {  },
) -> Unit {
  let t = @sf.theme()
  // under the status bar (Chat.kt BarFrame: windowInsetsPadding(statusBars), then 6)
  c.box(dir=Row, w=Fill(1.0), pl=4.0, pr=16.0, pt=status_top() + 6.0, pb=8.0, align=ACenter, fn() {
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
      // the title as long as there is room for it beside what follows it (weight(1f, fill = false): what follows is
      // measured first, as wide as it is, and the title has what is left)
      c.box(fn() {
        c.text(title, size=16.0, weight=600, color=t.p.text, wrap=false, line=chat_title_line)
        |> ignore
      })
      |> ignore
      c.box(dir=Row, gap=8.0, align=ACenter, keep=true, fn() { after() }) |> ignore
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
  // 归档 comes and goes as nothing is left in the chat or something is again (Chat.kt ChatBar: 280 ms, ArchiveEase;
  // fading, from or to 85%, its width from its end)
  let archive_key = "bar-archive/" + r.station + "/" + r.session
  let archive_look = @motion.presence(
    c,
    archive_key,
    archive,
    enter=@motion.trans(fade=0.0, scale=0.85, spec=archive_tween),
  )
  let archive_w = @motion.anim(c, archive_key + "/w", if archive { 1.0 } else { 0.0 }, global=true)
  archive_w.follow(if archive { 1.0 } else { 0.0 }, archive_tween)
  let archive_share = if archive_look is None { 0.0 } else { archive_w.get() }
  let people = if v.people.length() > 5 { v.people[:5].to_array() } else { v.people }
  c.box(w=Fill(1.0), glass=@sf.glass_bar(), fn() {
    bar_frame(
      c,
      v.title,
      fn() {
        if v.agents.length() == 0 {
          match station {
            Some(s) => station_chip(c, r.station, s)
            None => ()
          }
        }
        // its station's update (station_update.mbt)
        station_update_control(c, src, r.station, v.station_update)
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
        match archive_look {
          Some(look) =>
            c.box(dir=Row, w=Px(34.0 * archive_share), justify=JEnd, fn() {
              let b = c.box(w=Px(34.0), min_w=34.0, h=Px(34.0), fn() {
                if doing("archive/" + r.station + "/" + r.session) {
                  c.box(w=Px(34.0), h=Px(34.0), align=ACenter, justify=JCenter, fn() {
                    @sf.spinner(c) |> ignore
                  })
                  |> ignore
                } else if nav_button(c, "archive", 20.0, key="chat-archive") && archive {
                  archive_chat(src, r, v)
                }
              })
              c.look(b, look)
              @motion.leaving(c, b, archive)
            })
            |> ignore
          None => ()
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
/// The station's tag in a chat's bar while no agent is in it (PageParts.kt ChatStationChip): a tap opens its card
/// (Stations.kt openStationPeek).
fn station_chip(c : @ui.Ctx, address : String, s : Station) -> Unit {
  let id = c.id("bar-station")
  c.cursor(id, Hand)
  if c.clicked(id) {
    @settings.open_station_peek(address)
  }
  c.box(id~, fn() { station_tag(c, s) }) |> ignore
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
/// someone, yellow spokes stepping round at work (Spokes.kt); nothing when done.
fn agent_state_mark(c : @ui.Ctx, badge : String) -> Unit {
  let t = @sf.theme()
  match badge {
    // yellow spokes 10 across stepping round, no disc round them (it showed as a dark rim)
    "run" => @sf.spokes(c, 10.0, mark_yellow, box=12.0) |> ignore
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
/// People overlapping a little, each ringed in the page's ground (Parts.kt PeopleStack: Avatar(p.id, p.shown.display)).
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
          // coloured by their id, lettered by what the bar calls them (the viewer 「你」)
          avatar(c, src, p.id, p.display, p.picture, size)
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
// kept across runs: a table, never written
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
    bench_on.val = if @ui.env("MBUI_CHAT_BENCH") != "" { 1 } else { 0 }
  }
  if bench_on.val == 0 || !rd.placed {
    return
  }
  rd.bench = rd.bench + 1
  // every frame drawn while it runs (only in the host's bench mode: MBUI_BENCH, which the bench's script sets)
  c.bench_frames(true)
  if rd.bench_phase == 0 {
    if rows != rd.bench_rows {
      rd.bench_rows = rows
      @hostapi.log("CHATBENCH rows=\{rows} after \{rd.bench} frames")
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
    @hostapi.log(
      "CHATBENCH frames=\{n} rows=\{rows} cpu_avg=\{sum / n.to_double()} cpu_p50=\{a[n / 2]} " +
      "cpu_p95=\{a[n * 95 / 100]} cpu_p99=\{a[n * 99 / 100]} cpu_max=\{a[n - 1]} slow(>8ms)=\{slow} " +
      "present_avg=\{psum / n.to_double()}",
    )
    // the bench's end, once its frames are counted and the frame's builds are over (MBUI_CHAT_BENCH runs only)
    c.tell("chat-bench-end", fn() { @hostapi.exit(0) })
  }
}
