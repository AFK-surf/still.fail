// A chat, read (ember apps/android chat/screens/Chat.kt ChatScreen, Messages; ui/Follow.kt): its bar over its messages
// (back, the title, its people and its agents' marks with the station they run on, "…"), the messages as the core's
// `chat` view gives them, newest at the bottom, the list following its newest while it is at its end and "jump to
// the newest" over the composer's room otherwise; the page before loaded as the reader nears the top, what is in view
// staying put. While the chat is read the first time, the messages to come in their bones (the library's Waiting), what is
// wrong over them in red.
//
// What the page tells the core of the reader (the chat shown and its end seen: `client.focus`, which marks it read;
// where it was left: `chat.place`) is not said with MBUI_READONLY=1 (Source.readonly): a run on a real account then
// changes nothing in it. The composer at its foot is composer.mbt's.



///|
/// The bar's height (Home's top bar's, bar_h: the two bars' lines meet as the page is swiped back) and the room
/// the list keeps under it; the composer's room at the foot (ChatHost.kt roomForList: a line of words, the capsule's
/// insets, its toolbar and margins) and the list's under it.
let chat_bar_h : Double = bar_h

///|
/// The title's line in the bar (Chat.kt BarFrame: a Text with no line height of its own, 16 on the theme's 1.4em).
let chat_title_line : Double = 16.0 * 1.4

///|
let composer_room : Double = 110.0

///|
/// Where the chat's bar ends, from the list's top (the list runs on under it), and what the list keeps over its first
/// row: 14 under the bar (Chat.kt).
fn bar_foot() -> Double {
  status_top() + chat_bar_h
}

///|
fn list_top() -> Double {
  status_top() + chat_bar_h + 14.0
}

///|
/// What the list keeps under its last row over the composer's room: 10 (Chat.kt).
fn list_foot() -> Double {
  10.0
}

///|
/// The chat's list, its key.
fn list_key(r : ChatRef) -> String {
  "chat/" + r.station + "/" + r.session
}

///|
/// A chat opened over Home from the start at its message `seq`, as a notification opens it; `held`: its flash kept at
/// its peak (screenshots of it).
pub fn open_chat_at(r : ChatRef, seq : Double, held? : Bool = false) -> Unit {
  @sfbase.history_push()
  flash_held.val = held
  go_to(r, seq)
  app.nav.push(Chat(r))
}

///|
/// The chat left (its page gone): the core told it shows no more, and where it was left (`chat.place`: the message
/// at the top, none at its end). Never with Source.readonly.
fn chat_left(src : Source, r : ChatRef) -> Unit {
  let k = r.station + "\u{1}" + r.session
  match (chat_kept(r), readings.get(k)) {
    (Some(v), Some(rd)) if !src.read_only => {
      (src.call)("client.focus", { "left": focus_chat(r, v, None) }, fn(_) {  })
      match v.thread {
        Some(_) if rd.placed => tell_place(src, r, v, rd)
        _ => ()
      }
    }
    _ => ()
  }
  pick_clear()
  readings.remove(k)
  // what holds the chat's thread at the core with it (its jobs in the bar and their sheets, the images beside one
  // opened from it): while any is held the core keeps the thread's window as first read, and the chat opened again
  // where it was first opened, not where it was left (views.ts: chatJobs and imageNear are of the chat's topic)
  (src.leave)("chat", chat_params(r))
  (src.leave)("chatJobs", chat_params(r))
  (src.leave)("chatJobs", chat_jobs_summary_params(r))
  // what its agents' lines and its jobs' sheets read: their work as it goes, their logs as they grow
  @sfbase.let_go(src, @sfbase.chat_scope(r.station, r.session))
  @sfbase.let_go(src, @sfbase.jobs_scope(r.station))
  // what its agents and other chats' wrote each other, read for its sheet: let go if it was (held only once opened)
  match dui.letters_held.get(k) {
    Some(th) => {
      (src.leave)("chatLetters", letters_params(r, th))
      dui.letters_held.remove(k)
    }
    None => ()
  }
  near_left(src, r.station)
}

///|
/// Which of the chat's asks the bell went to last, by chat (it goes to the next one each time, round again).
let ask_turns : Map[String, Int] = {}

///|
let bar_drop_people : Int = 1

///|
/// A station named in a small outlined tag (PageParts.kt StationTag): how it is reached as a dot, its mark, its name.
/// The dot leading it stands in its round end as far in as makes it concentric with it (20 high: its half less the
/// dot's), its words 8 in otherwise.
fn station_tag(c : @ui.Ctx, s : Station) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    max_w=104.0,
    pl=if s.via != "" { station_dot_in } else { station_tag_end },
    pr=station_tag_end,
    pady=2.0,
    gap=4.0,
    radius=12.0,
    border=1.0,
    border_color=t.p.line,
    align=ACenter,
    // (StationTag: its name to a screen reader)
    label=s.name,
    fn() {
      if s.via != "" {
        via_dot(c, s.via, via_dot_side, 0.0)
      }
      if @sf.has_station_mark(s.emoji, s.icon) {
        @sf.station_mark(c, s.emoji, s.icon, 12.0, t.p.muted)
      }
      c.box(fn() { c.text(s.name, size=t.t.caption, color=t.p.muted, wrap=false, line=16.0) |> ignore })
      |> ignore
    },
  )
  |> ignore
}

///|
/// The tag's height (its words' 16 and 2 over and under), its words' room at its ends, its dot's side.
let station_tag_h : Double = 20.0

///|
/// Where the dot leading a station's tag stands in its round end (a capsule's: round, @sf.capsule_in's room its half).
let station_dot_in : Double = @sf.capsule_in(station_tag_h / 2.0, via_dot_side, room=station_tag_h / 2.0)

///|
let station_tag_end : Double = 8.0

///|
let via_dot_side : Double = 7.0

///|
/// How a station is reached (StationLink.css.ts dot, cornerDot): the online green direct, amber through the relay, red
/// offline, grey while it is being reached; ringed in the page's ground on a tile's corner.
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
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.online, fn() {  })
          |> ignore
        "relay" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=0xD9962BFFL, fn() {  })
          |> ignore
        "offline" =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.red, fn() {  })
          |> ignore
        _ =>
          c.box(w=Px(inner), h=Px(inner), radius=inner / 2.0, bg=t.p.muted, fn() {  })
          |> ignore
      }
    },
  )
  |> ignore
}

///|
/// An agent's mark in the bar: 22 square on the card's ground with a line round it (PageParts.kt), its maker .6 of it,
/// a station's mark 13.
fn mark_side() -> Double {
  22.0
}

///|
fn mark_ground() -> (Int64, Double) {
  let p = @sf.theme().p
  (p.card, 1.0)
}

///|
/// Its corner: 6.
fn mark_corner(side : Double) -> Double {
  6.0
}

///|
fn mark_logo(side : Double) -> Double {
  side * 0.6
}

///|
fn mark_station() -> Double {
  13.0
}

///|
fn station_part_type() -> (Double, Double, Double) {
  (96.0, 5.0, 14.0)
}

///|
/// People overlapping a little, each ringed in the ground they are on (Parts.kt PeopleStack: Avatar(p.id,
/// p.shown.display), `ring` C.bg unless said): laid out side by side, each drawn 5 over the one before it, the first
/// over them all (zIndex(-i)).
fn people_stack(
  c : @ui.Ctx,
  src : Source,
  people : Array[Person],
  size : Double,
  ring? : Int64 = @sf.theme().p.bg,
) -> Unit {
  let step = size + 3.0
  let n = people.length()
  c.box(w=Px(step * n.to_double()), h=Px(step), fn() {
    // the last drawn first, each under the one before it
    for j in 0..<n {
      let i = n - 1 - j
      let p = people[i]
      c.layer(fn() {
        c.box(
          w=Px(step),
          h=Px(step),
          radius=step / 2.0,
          bg=ring,
          tx=(step - 5.0) * i.to_double(),
          align=ACenter,
          justify=JCenter,
          fn() {
            // coloured by their id, lettered by what the bar calls them (the viewer 「你」)
            avatar(c, src, p.id, p.display, p.picture, size)
          },
        )
        |> ignore
      })
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
  @sf.avatar(c, id, name, if picture != "" { (src.picture)(picture, c.page_stint()) } else { "" }, size)
}

///|
/// The chat read the first time (the library's Waiting): its messages to come in their bones, as its list draws them,
/// the first as far under the bar as the list's first row; what could not be read over them in red (the bones still).
fn waiting_messages(c : @ui.Ctx, failed : String?) -> Unit {
  @sf.waiting(c, fn() { @sfpages.chat_messages_sample(c, list_top() - top_bar_h()) }, error=failed.unwrap_or(""))
}

///|
/// MBUI_CHAT_BENCH=1: once the chat is in place, the pages before are brought in (held at its top) until it has 3000
/// messages or no more (a minute at most); then from its end it is scrolled up 600 frames at 40 a frame, and the
/// frames' times are said (CHATBENCH …) and the app ends.
let bench_on : Ref[Int] = { val: -1 }

///|
/// The bar's keys at its end (its archive, its jobs, its "…") as far apart as makes each a press's room across
/// (@sf.keys_apart: 2 with keyboard and mouse, 10 with touch), the room before each.
fn bar_keys_apart() -> Double {
  @sf.keys_apart(size=nav_key_side)
}
