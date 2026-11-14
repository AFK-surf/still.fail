// What takes a chat's page made as nodes elsewhere in its list (the old list's to_latest and list_after's go-to, as
// results): the way back to the newest, and a message gone to. Out of what the list has in sight (ListPlace::on_sight,
// told at causes) and what the chat is told to go to (sfbase's go_tos, told by go_tos_said); its own state made with
// the list and let go with it (ChatJump). What floats over the list's foot with the way to the newest (the bell to what
// waits to be decided, the round button to 对话目录; 对话目录's rail at the list's right on a wide page), and what a
// message gone to shows of it (its flash; a search's words marked in it).

///|
/// What a chat's list keeps of its way to the newest: whether it is away from its end (more than a corner of the screen
/// as it was last in sight); its latest page asked (chat.latest), the list to its end as it comes; the first and the last
/// key it had in sight (none before it was laid out: what waits to be decided is out of view only once it is); whether
/// it stands where a go-to put it (1 brought, 2 there: the page before not asked till the reader moves it; 0 not) and
/// the message that go-to went to and its top under the list's (-1 none); the
/// message ⌘F last asked the window moved about (chat.around, -1 none); the row last gone to that flashes, the moment
/// it was gone to and the passage of it a quote that led there quoted, where its words have it ("" none: the row lit
/// whole); the row a search opened the chat at and its words,
/// marked there for as long as the list is; 对话目录's round button while it shows (what ⌘G opens the outline beside);
/// where the reader is as the list last had it in sight (the message at the top of what shows, whether at the chat's
/// end: what the rail's long tick follows); 对话目录's rail while it shows (what ⌘G opens it beside where the round
/// button does not show).
priv struct ChatJump {
  away : @signals.Signal[Bool]
  mut latest : Bool
  sight : @signals.Signal[(String, String)?]
  put : @signals.Signal[Int]
  mut went : (Double, Double)
  mut around : Double
  flashed : @signals.Signal[(String, Double, String)]
  found : @signals.Signal[(String, Array[String])]
  mut outline_at : @view.View?
  reader : @signals.Signal[(Double, Bool)]
  mut rail_at : @view.View?
}

///|
/// None away yet, nothing asked, nothing gone to, no round button.
fn ChatJump::new() -> ChatJump {
  {
    away: @signals.signal(false, same=fn(a, b) { a == b }),
    latest: false,
    sight: @signals.signal(None, same=fn(a, b) { a == b }),
    put: @signals.signal(0, same=fn(a, b) { a == b }),
    went: (-1.0, 0.0),
    around: -1.0,
    flashed: @signals.signal(("", -1.0, ""), same=fn(a, b) { a == b }),
    found: @signals.signal(("", []), same=fn(a, b) { a == b }),
    outline_at: None,
    reader: @signals.signal((-1.0, true), same=fn(a, b) { a == b }),
    rail_at: None,
  }
}

///|
/// How far from its end the list is before the way to the newest shows (list_after's `away`: a corner of the screen).
let to_newest_away : Double = 120.0

///|
/// Chat `r`'s list (`jump` what it keeps of it, `place`, its rows `rows`, its view `view`): what it has in sight kept
/// (whether it is away from its end; where the reader is, for a go-to inside the chat to keep: sfbase's Reading,
/// keep_place_of), the kept place
/// forgotten at its end; and the message the chat is to go to (sfbase's go_tos) brought to the list's top (`top`: the
/// chat's bar and the room under it; places counted under what covers it, `cover` tall: the bar), or where the reader
/// was (go_back_to's offset, as kept: sfbase's kept_place_under), once its row is among the keys, the page before asked
/// (`older`, one at a time) while it is not and the chat has pages before, or what ⌘F found the window moved about
/// (chat.around, `src` asked) while its bar is open here; given up where none is left. Asked as the
/// list is made, as its keys change and as the chat is told to go somewhere.
fn chat_goes_to(
  v : @view.View,
  src : Source,
  r : ChatRef,
  jump : ChatJump,
  place : @view.ListPlace[String],
  rows : () -> ChatBodyRows,
  view : () -> ChatView,
  cover : () -> Double,
  top : () -> Double,
  older : () -> Unit,
  shows : () -> Bool,
) -> Unit {
  let chat = r.station + "\u{1}" + r.session
  place.on_sight(fn(s) {
    let cv = @signals.untracked(view)
    jump.away.set(!s.at_foot && s.from_foot > to_newest_away)
    jump.sight.set(Some((s.first, s.last)))
    // (where a go-to put it, then moved off it: the reader's)
    match jump.put.untracked() {
      1 => jump.put.set(2)
      2 => jump.put.set(0)
      _ => ()
    }
    // (placed while it shows: sfbase's keep_place_of)
    let rd = @sfbase.reading_of(chat)
    rd.placed = @signals.untracked(shows)
    match @signals.untracked(rows).rows.get(s.first).map(fn(row) { row.entry }) {
      Some(Said(m)) => {
        rd.top_seq = m.seq
        rd.top_off = @sfbase.kept_place_of(-s.into, @signals.untracked(cover))
      }
      _ => ()
    }
    // (standing where a go-to put it: the reader at the message gone to, put under the bar, whatever of the one over
    // it shows under the bar too: reader_top's)
    match jump.went {
      (seq, off) if jump.put.untracked() == 2 && seq >= 0.0 => {
        rd.top_seq = seq
        rd.top_off = off
      }
      _ => ()
    }
    rd.far = cv.newer || (!s.at_foot && s.from_foot > s.shows)
    // (at the chat's end: what the steps to what a person said and 对话目录 take the reader to be at, outline_current)
    rd.at_end = s.at_foot && !cv.newer
    if s.at_foot && !cv.newer {
      @sfbase.place_forget(chat)
    }
    // (where the reader is, told: the rail's long tick)
    jump.reader.set((rd.top_seq, rd.at_end))
  })
  v.reacts(shows, fn(on) { @sfbase.reading_of(chat).placed = on && place.sight_now() is Some(_) }, at_start=false)
  let goes = fn() {
    guard @sfbase.go_tos.get(chat) is Some(target) else { return }
    let rs = @signals.untracked(rows)
    let cv = @signals.untracked(view)
    let mut first = -1.0
    let mut at : String? = None
    for k in rs.keys {
      match rs.rows.get(k).map(fn(row) { row.entry }) {
        Some(Said(m)) => {
          if first < 0.0 {
            first = m.seq
          }
          if m.seq == target {
            at = Some(k)
            break
          }
        }
        _ => ()
      }
    }
    match at {
      Some(k) => {
        // (the passage a quote that led here quoted, where the message's words have it: lit alone as it flashes,
        // chat_passage_lit; else the row lit whole, Chat.tsx Quotes' jump)
        let passage = match (@sfbase.go_to_passages.get(chat), rs.rows.get(k).map(fn(row) { row.entry })) {
          (Some(p), Some(Said(m))) if !m.system && @sf.find_passage(m.text, p) is Some(_) => p
          _ => ""
        }
        @sfbase.go_tos.remove(chat)
        @sfbase.go_to_passages.remove(chat)
        let back = @sfbase.go_back_offsets.get(chat)
        @sfbase.go_back_offsets.remove(chat)
        let words = @sfbase.go_to_words.get(chat).unwrap_or([])
        @sfbase.go_to_words.remove(chat)
        jump.around = -1.0
        // (where it is put, as kept: a message gone to at the list's top, under the bar and its room)
        let c = @signals.untracked(cover)
        let off = match back {
          Some(off) => off
          None => @sfbase.kept_place_of(0.0, @signals.untracked(top))
        }
        jump.went = (target, off)
        jump.put.set(1)
        // (what was meant in it before the eyes too, where it lies low in a long message: a search's words, a quote's
        // passage; not back where the reader was: ListPlace::bring's `sought`, what its words mark: View::sought)
        place.bring(k, offset=@sfbase.kept_place_under(off, c), sought=back is None)
        // (back where the reader was: nothing of it shown; a search's: its words marked, nothing flashing; else it
        // flashes, from now)
        if back is None {
          if words.length() > 0 {
            jump.found.set((k, words))
          } else {
            let at = v.cause_at()
            jump.flashed.set((k, at, passage))
            @sfbase.flash_rest_nodes.val = at + @sfbase.flash_ms
            // (the chat's reading told the message gone to and what of it is lit, as the old page's list tells it:
            // where the reader is, reader_top's)
            match rs.rows.get(k).map(fn(row) { row.entry }) {
              Some(Said(m)) => {
                let rd = @sfbase.reading_of(chat)
                rd.flash = m.ts
                rd.flash_passage = passage
              }
              _ => ()
            }
          }
        }
      }
      // (what ⌘F found, or a message after an older window, not in the chat's window: the window moved about it
      // (chat.around), once for each)
      None if (find_chat() == chat || (cv.newer && (first < 0.0 || first < target))) && cv.thread is Some(_) =>
        if jump.around != target {
          jump.around = target
          (src.call)(
            "chat.around",
            {
              "station": Json::string(r.station),
              "thread": Json::number(cv.thread.unwrap()),
              "seq": Json::number(target),
            },
            fn(res) { if res is Err(_) { @sfbase.go_tos.remove(chat) } },
          )
        }
      // (the page before asked while the message is before what the window holds: once for each first, as it comes)
      None if cv.more && (first < 0.0 || first > target) => if cv.older == "" { older() }
      None => {
        @sfbase.go_tos.remove(chat)
        @sfbase.go_back_offsets.remove(chat)
      }
    }
  }
  v.reacts(fn() { (rows().keys, @sfbase.go_tos_said.get()) }, fn(_) { goes() })
  // (its latest page come in place of a window short of the chat's end, asked: the list at its end)
  v.reacts(
    fn() { view().newer },
    fn(newer) {
      if !newer && jump.latest {
        jump.latest = false
        place.to_end(glide=false)
      }
    },
    at_start=false,
  )
}

///|
/// Chat `r`'s list (`jump` what it keeps of it, `place`, its view `view`) taken back to the newest: to where a go-to
/// inside the chat kept the reader first (go_back_to), else to its end, asking the chat's latest page first where the
/// window is short of it. The way to the newest pressed, and its key (chat.latest: chat_body_node's action).
fn chat_to_newest(
  src : Source,
  r : ChatRef,
  jump : ChatJump,
  place : @view.ListPlace[String],
  view : () -> ChatView,
) -> Unit {
  if (src.asks_outline)() && @sfbase.go_back_to(r) {
    return
  }
  let cv = @signals.untracked(view)
  if @sfbase.chat_latest_now(src, r, cv, @sf.t("web-main.chat.toLatest")) {
    jump.latest = true
  } else {
    place.to_end()
  }
}

///|
/// A button floating over the list's foot `foot` at its top (a row of no height, the button standing over it: where
/// the composer is, whatever its height), just over the send button (the composer's column `width` across, `float_in`
/// in from its side, float_lift over the foot), `lift` higher (over those that show under it: float_above each), while
/// `shown`; made by `build`.
fn chat_float_stand(
  foot : @view.View,
  width : () -> Double,
  lift : () -> Double,
  shown : () -> Bool,
  build : (@view.View) -> Unit,
) -> Unit {
  foot.box(fn(stand) {
    stand.row(Is(true)).height(Is(Some(0.0))) |> ignore
    stand.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    stand.show(shown, fn(o) {
      let reach = @sf.float_button_reach
      o
      .margin(
        By(fn() {
          let w = width()
          (
            0.0,
            -(float_side + 2.0 * reach + float_lift - reach + lift()),
            (w - composer_width(w)) / 2.0 + float_in - reach,
            0.0,
          )
        }),
      )
      |> ignore
      build(o)
    })
  })
  |> ignore
}

///|
/// Whether the way to the newest shows: the list away from its end, or the window short of the chat's end.
fn chat_jumps(jump : ChatJump, view : () -> ChatView) -> Bool {
  jump.away.get() || view().newer
}

///|
/// Whether 对话目录's round button shows: with the way to the newest, where the outline may be asked for (not in a replay
/// of a run from before it, Source's `asks_outline`) and the chat is made.
fn chat_outlines(src : Source, jump : ChatJump, view : () -> ChatView) -> Bool {
  (src.asks_outline)() && chat_jumps(jump, view) && view().thread is Some(_)
}

///|
/// The way to the newest (to_latest's) in the list's foot `foot` (chat_float_stand's, the composer's column `width`
/// across): shown while chat_jumps (how many new messages wait at the chat's end said then). Pressed, chat_to_newest.
fn chat_to_newest_node(
  foot : @view.View,
  src : Source,
  r : ChatRef,
  jump : ChatJump,
  place : @view.ListPlace[String],
  view : () -> ChatView,
  width : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let chat = r.station + "\u{1}" + r.session
  // (not in a replay of a run from before the outline, whose way to the newest went to the end alone: `asks_outline`)
  let back = fn() { (src.asks_outline)() && @sfbase.place_kept(chat) }
  let press = fn() { chat_to_newest(src, r, jump, place, view) }
  chat_float_stand(foot, width, fn() { 0.0 }, fn() { chat_jumps(jump, view) }, fn(o) {
    @sf.float_button_node(
      o,
      "arrow-down",
      fn() { @sf.t(if back() { "web-main.outline.back" } else { "web-main.chat.toLatest" }) },
      press,
      count=fn() {
        let cv = view()
        if cv.newer && cv.unread > 0.0 {
          @sf.t("web-main.chat.newMessages", args=[("n", cv.unread.to_int().to_string())])
        } else {
          ""
        }
      },
      tips~,
      shortcut="chat.latest",
    )
    |> ignore
  })
}

///|
/// 对话目录's round button (outline_float's) over the way to the newest in the list's foot `foot`, with it
/// (chat_outlines); pressed, chat `r`'s outline beside it (a sheet on Small), at the message the reader is at
/// (outline_current: what the list last had in sight, sfbase's Reading); what ⌘G opens it beside while it shows
/// (`jump`'s outline_at). Its page's time on top `stint`.
fn chat_outline_node(
  foot : @view.View,
  src : Source,
  r : ChatRef,
  jump : ChatJump,
  view : () -> ChatView,
  width : () -> Double,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let chat = r.station + "\u{1}" + r.session
  chat_float_stand(foot, width, fn() { float_above }, fn() { chat_outlines(src, jump, view) }, fn(o) {
    // (beside the button itself, their feet together: its room, not the stand it floats in)
    let button : Ref[@view.View] = Ref(o)
    let press = fn() {
      let cv = @signals.untracked(view)
      guard cv.thread is Some(th) else { return }
      let rd = @sfbase.reading_of(chat)
      let current = outline_current(said_in_view(cv), rd.top_seq, rd.at_end)
      open_outline(src, r, th, current, from=Node(button.val), side=Left, stint=@signals.untracked(stint))
    }
    button.val = @sf.float_button_node(o, "list", fn() { @sf.t("web-main.outline.title") }, press, tips~, shortcut="chat.outline")
    // (⌘G's outline beside it while it shows: chat_body_node's chat.outline)
    jump.outline_at = Some(button.val)
    o.owns(fn() { if jump.outline_at.map(fn(b) { b.id() }) == Some(button.val.id()) { jump.outline_at = None } }) |> ignore
    // (a screen's fixture: the outline opened from it as it shows, its words typed, its field taking the keys, in
    // the button's moment's turn: outline_presets)
    match outline_presets.get(chat) {
      Some(words) => {
        outline_presets.remove(chat) |> ignore
        o.at_moment(o.cause_at(), fn() {
          let cv = @signals.untracked(view)
          guard cv.thread is Some(th) else { return }
          let rd = @sfbase.reading_of(chat)
          let current = outline_current(said_now(src, r, cv), rd.top_seq, rd.at_end)
          open_outline(src, r, th, current, from=Node(button.val), side=Left, keys=true, stint=@signals.untracked(stint), typed=words)
        })
        |> ignore
      }
      None => ()
    }
  })
}

///|
/// What 对话目录's rail of chat `r` (its view `view`) shows: each day's count of what people said and their seqs, oldest
/// first (the core's chatOutline, subscribed only while it may show), while the outline may be asked for (Source's
/// `asks_outline`), the chat is made, the list `width` wide leaves the rail room at its right (rail_fits) and people
/// said three things or more (rail_least); none otherwise. `outline`: the chat's outline, read only then.
fn chat_rail_said(
  src : Source,
  outline : @signals.Computed[@sfbase.TopicState],
  view : () -> ChatView,
  width : () -> Double,
) -> (Array[Int], Array[Double])? {
  guard (src.asks_outline)() && rail_fits(width()) && view().thread is Some(_) else { return None }
  let value = outline.get().value
  let said = outline_seqs(value)
  guard said.length() >= rail_least else { return None }
  Some((items(value, "days").map(fn(d) { items(Some(d), "seqs").length() }), said))
}

///|
/// A tick of the rail as its row draws it (rail_ticks' RailTick, laid out one under another): its place, the message it
/// stands for (its place among what people said), how long its turn is, whether it is the reader's, whether a day starts
/// at it after another (a day's gap over it).
#derive(Eq)
priv struct ChatRailTick {
  i : Int
  at : Int
  turn : Int
  reader : Bool
  day : Bool
}

///|
/// The rail's ticks in a row, one after another, for what `said` says (chat_rail_said's), the reader at `reader`
/// (ChatJump's: the message at the top of what shows, whether at the end), the chat's newest message `latest`, in
/// `most` tall.
fn chat_rail_ticks(said : (Array[Int], Array[Double]), reader : (Double, Bool), latest : Double, most : Double) -> Array[ChatRailTick] {
  let (days, seqs) = said
  let current = outline_current(seqs, reader.0, reader.1)
  let at = seqs.search(current).unwrap_or(seqs.length() - 1)
  let out : Array[ChatRailTick] = []
  for g, group in rail_ticks(days, at, rail_turns(seqs, latest), most) {
    for j, t in group {
      out.push({ i: out.length(), at: t.at, turn: t.turn, reader: t.reader, day: g > 0 && j == 0 })
    }
  }
  out
}

///|
/// Which of `ticks` (chat_rail_ticks') a press at `y` down the rail's press `h` tall lies on: the one whose middle is
/// nearest, as they are laid out in its middle (each tick_gap and its line tall, a day's tick_day_gap over the first of
/// a day). None where there are none.
fn chat_rail_tick_at(ticks : Array[ChatRailTick], y : Double, h : Double) -> ChatRailTick? {
  let room = tick_thick + tick_gap.px()
  let tall = ticks.fold(init=0.0, fn(a, t) { a + room + (if t.day { tick_day_gap.px() } else { 0.0 }) })
  let mut top = (h - tall) / 2.0
  let mut best : ChatRailTick? = None
  let mut far = 1.0e9
  for t in ticks {
    if t.day {
      top = top + tick_day_gap.px()
    }
    let d = (top + room / 2.0 - y).abs()
    if d < far {
      far = d
      best = Some(t)
    }
    top = top + room
  }
  best
}

///|
/// 对话目录's rail (the old view's outline_rail, made once as nodes): where the list `width` wide leaves it room at its
/// right, while chat_rail_said says what it shows, a strip of ticks, one for each message a person said, as long as its
/// turn, the reader's (ChatJump's `reader`) longest and in the ink; standing in the middle of the list `anchor` (what
/// holds the page's list), at its right, clear of its scroll bar. Made in the list's foot `foot` (a stand of no height
/// there), so a wheel over it is the list's as anywhere (what holds it the list's foot); placed beside nothing but the
/// list, out of any column's flow, so it comes and goes at once, with the page as it is made, never making its way in
/// (no cause of its own: the outline answered, the page made wider). Pressed with the hand where a tick is, the chat goes
/// to its message (@sfbase.go_to: flashing, where the reader was kept for ↓); pressed by the keys or a screen reader,
/// the outline opens beside it. As tall as a press at least, its ticks half the list's height at most (of the window's,
/// under the bar's `top`): past that a steady map of the whole chat (rail_ticks). Its tip says ⌘G's 对话目录. While it
/// shows, ⌘G opens the outline beside it (`jump`'s rail_at) where the round button does not show.
fn chat_rail_node(
  foot : @view.View,
  src : Source,
  r : ChatRef,
  jump : ChatJump,
  view : () -> ChatView,
  width : () -> Double,
  top : () -> Double,
  anchor : @view.View,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  // (the chat's thread as the page is made: a page made as nodes is of a chat made, never a new one, Nav::become)
  guard @signals.untracked(view).thread is Some(th) else { return }
  let outline = src.topic("chatOutline", outline_params(r, th))
  let said = @signals.computed(fn(_) { chat_rail_said(src, outline, view, width) }, same=fn(a, b) {
    match (a, b) {
      (Some((d1, s1)), Some((d2, s2))) => d1 == d2 && s1 == s2
      (None, None) => true
      _ => false
    }
  })
  foot.box(fn(stand) {
    stand.height(Is(Some(0.0))) |> ignore
    stand.show(fn() { said.get() is Some(_) }, at_once=true, fn(o) {
      o
      .beside(anchor.id(), side=Right, along=Middle, offset=-(rail_press_w + @ui.scroll_bar_room), padding=0.0)
      |> ignore
      let ticks = @signals.computed(fn(_) {
        match said.get() {
          Some(s) => {
            let latest = view().messages.fold(init=-1.0, fn(m, x) { if x.seq > m { x.seq } else { m } })
            let (_, h) = o.window()
            let most = dmax(0.0, (h - top()) * rail_share - 2.0 * rail_pad.px())
            chat_rail_ticks(s, jump.reader.get(), latest, most)
          }
          None => []
        }
      }, same=fn(a, b) { a == b })
      let go = fn(t : ChatRailTick) {
        guard @signals.untracked(fn() { said.get() }) is Some((_, seqs)) && seqs.get(t.at) is Some(seq) else { return }
        @sfbase.go_to(r, seq)
      }
      o.box(fn(press) {
        @sf.style_node(press, fn() { chat_rail_press })
        press
        .says(By(fn() { Some(@view.said(Button, label=@sf.t("web-main.outline.title"))) }))
        .cursor(Is(Some(Hand)))
        // (the keys' or a screen reader's press: the outline beside it, at the message the reader is at)
        .on_press(fn() {
          let cv = @signals.untracked(view)
          guard cv.thread is Some(th) && @signals.untracked(fn() { said.get() }) is Some((_, seqs)) else { return }
          let (seq, at_end) = jump.reader.untracked()
          let current = outline_current(seqs, seq, at_end)
          open_outline(src, r, th, current, from=Node(press), side=Left, along=Middle, stint=@signals.untracked(stint))
        })
        // (the hand's, a finger's or the pointer's: the message of the tick it went down on)
        .gesture(@ui.touch_slop(), tap=fn(d) {
          match chat_rail_tick_at(@signals.untracked(fn() { ticks.get() }), d.y, d.h) {
            Some(t) => go(t)
            None => ()
          }
        })
        |> ignore
        press.each(
          fn() { ticks.get() },
          fn(t) { t.i },
          fn(row, t) {
            // (a day's gap over the first of a day after another)
            row.box(fn(g) { g.height(By(fn() { Some(if t.get().day { tick_day_gap.px() } else { 0.0 }) })) |> ignore })
            |> ignore
            row.box(fn(room) {
              @sf.style_node(room, fn() { tick_room })
              room.box(fn(line) {
                line
                .width(By(fn() { Some(if t.get().reader { tick_long } else { tick_w(t.get().turn) }) }))
                .height(Is(Some(tick_thick)))
                .ground(By(fn() { @ui.tree_theme().color(if t.get().reader { Fg } else { Line }) }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          },
          // (a map of the chat, steady: no tick makes its way, as none of the old rail's did)
          at_once=true,
        )
        @sf.tip_node(tips, press, fn() { @sf.t("web-main.keymap.chat.outline") }, side=Left, shortcut="chat.outline")
        |> ignore
        jump.rail_at = Some(press)
        press.owns(fn() { if jump.rail_at.map(fn(b) { b.id() }) == Some(press.id()) { jump.rail_at = None } }) |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// The rail's press (rail_press's): 44 wide and 44 tall at least, its ticks one under another in its middle at its
/// right, rail_pad in over, under and at its right.
// kept across runs: a value (no field of it changes)
let chat_rail_press : @ui.Style = @ui.style(
  w=Fixed(rail_press_w),
  min_h=Fixed(rail_press_w),
  align=AEnd,
  justify=JCenter,
  py=rail_pad,
  pr=rail_pad,
)

///|
/// The bell to what waits to be decided in chat `r` (to_ask's: the core's `asks`) over the round buttons that show
/// under it in the list's foot `foot`, while none of their posts is among the rows the list has in sight (once it has
/// any; `rows` its rows); pressed, the chat goes to the post (@sfbase.go_to), the next one's the next time (ask_turns).
fn chat_ask_node(
  foot : @view.View,
  r : ChatRef,
  src : Source,
  jump : ChatJump,
  view : () -> ChatView,
  rows : () -> ChatBodyRows,
  width : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let chat = r.station + "\u{1}" + r.session
  let shown = fn() {
    let asks = asks_of(view())
    guard asks.length() > 0 && jump.sight.get() is Some((first, last)) else { return false }
    let rs = rows()
    let mut inside = false
    let mut seen = false
    for k in rs.keys {
      if k == first {
        inside = true
      }
      if inside {
        match rs.rows.get(k).map(fn(row) { row.entry }) {
          Some(Said(m)) if asks.contains(m.seq) => seen = true
          _ => ()
        }
      }
      if k == last || seen {
        break
      }
    }
    !seen
  }
  let lift = fn() {
    (if chat_jumps(jump, view) { float_above } else { 0.0 }) +
    (if chat_outlines(src, jump, view) { float_above } else { 0.0 })
  }
  // (over the round buttons under it: as one comes or goes, it moves there from where it is on a Move, set off at
  // their cause, as the old page's chat-ask/lift)
  let lifted = @motion.Way::new(@signals.untracked(lift))
  foot.reacts(lift, fn(to) { lifted.go(to, @sf.move_spring, at=foot.cause_at()) }, at_start=false)
  chat_float_stand(foot, width, fn() { lifted.shown_on(foot) }, shown, fn(o) {
    let press = fn() {
      let asks = asks_of(@signals.untracked(view))
      guard asks.length() > 0 else { return }
      let turn = ask_turns.get(chat).unwrap_or(0)
      @sfbase.go_to(r, asks[turn % asks.length()])
      ask_turns[chat] = turn + 1
    }
    @sf.float_button_node(o, "bell", fn() { @sf.t("web-main.chat.asks.go") }, press, tips~) |> ignore
  })
}

///|
/// What a row gone to shows of it (msgFlash, flash_start's), led there by no quote's passage its words have: the
/// accent's ground under what `row` holds (its outermost node: across the list, square; a notice's pill, round:
/// `round`), as lit as its flash is (`flash`: chat_flash_way's for row `key`).
fn chat_flash_node(row : @view.View, key : String, jump : ChatJump, flash : @motion.Way, round? : Bool = false) -> Unit {
  row.box(fn(b) {
    b.over(Is(true)).presses(Is(false)) |> ignore
    if round {
      b.radius(Is(1.0e6)) |> ignore
    }
    b.ground(
      By(fn() {
        match chat_gone(jump) {
          (k, _, "") if k == key => lit_by(@ui.tree_theme().color(AccentBg), flash.shown_on(b))
          _ => 0L
        }
      }),
    )
    |> ignore
  })
  |> ignore
}

///|
/// The passage of row `key` a quote that led there quoted (ChatJump's `flashed`), lit where its words have it as the
/// row's flash goes (chat_flash_way, in node `v`, what makes the row): its words and the ground it is drawn on now, the
/// accent's as a passage picked in a message is (picked_alpha), as lit as the flash is; ("", clear) for another row, or
/// one lit whole. What a message's words mark it by (passage_marks). As lit as the row's flash is (`flash`, read in
/// node `v`: chat_flash_way's for it).
fn chat_passage_lit(v : @view.View, key : String, jump : ChatJump, flash : @motion.Way) -> () -> (String, Int64) {
  fn() {
    match chat_gone(jump) {
      (k, _, passage) if k == key && passage != "" =>
        (passage, lit_by(@sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha), flash.shown_on(v)))
      _ => ("", 0L)
    }
  }
}

///|
/// How lit row `key` gone to is (0 to 1), followed in node `b` (what makes the row): coming in over flash_in_ms on the
/// ease-out, held to flash_held_ms, gone by flash_ms on Leave, from the moment the chat went to it (ChatJump's
/// `flashed`: the press's, its cause), made then or later; with motion reduced lit whole for flash_ms, then not.
fn chat_flash_way(b : @view.View, key : String, jump : ChatJump) -> @motion.Way {
  let way = @motion.Way::new(0.0)
  let due : Ref[() -> Unit] = Ref(fn() {  })
  b.reacts(fn() { chat_gone(jump) }, fn(g) {
    let (k, at, _) = g
    guard k == key && at >= 0.0 && b.cause_at() < at + @sfbase.flash_ms else { return }
    (due.val)()
    way.go(1.0, @motion.tween(@sfbase.flash_in_ms, ease=Out), at~)
    let out = at + (if @ui.reduced_motion() { @sfbase.flash_ms } else { @sfbase.flash_held_ms })
    due.val = b.at_moment(out, fn() {
      way.go(0.0, @motion.tween(@sfbase.flash_ms - @sfbase.flash_held_ms, ease=Leave), at=out)
    })
  })
  b.owns(fn() { (due.val)() }) |> ignore
  way
}

///|
/// The row the chat last went to that flashes, the moment it was gone to and the passage of it lit ("" none), followed.
fn chat_gone(jump : ChatJump) -> (String, Double, String) {
  jump.flashed.get()
}

///|
/// Colour `c` (0xRRGGBBAA) as clear as `k` (0 to 1) of it; none at all (0) where none of it shows, so a box whose ground
/// it is draws nothing of its own then (a row gone to at rest, a message's menu shut): not a clear ground over every
/// row, a box of its own whose height what judges a drawn box's size (ui's sizes_steady) reads as the row's.
fn lit_by(c : Int64, k : Double) -> Int64 {
  let a = (c & 0xFFL).to_double() * (if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k })
  let a = (a + 0.5).to_int64()
  if a <= 0L {
    0L
  } else {
    (c & 0xFFFFFF00L) | a
  }
}
