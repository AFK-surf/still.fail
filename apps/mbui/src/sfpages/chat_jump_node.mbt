// What takes a chat's page made as nodes elsewhere in its list (the old list's to_latest and list_after's go-to, as
// results): the way back to the newest, and a message gone to. Out of what the list has in sight (ListPlace::on_sight,
// told at causes) and what the chat is told to go to (sfbase's go_tos, told by go_tos_said); its own state made with
// the list and let go with it (ChatJump). What floats over the list's foot with the way to the newest (the bell to what
// waits to be decided, the round button to 对话目录), and what a message gone to shows of it (its flash; a search's
// words marked in it).

///|
/// What a chat's list keeps of its way to the newest: whether it is away from its end (more than a corner of the screen
/// as it was last in sight); its latest page asked (chat.latest), the list to its end as it comes; the first and the last
/// key it had in sight (none before it was laid out: what waits to be decided is out of view only once it is); whether
/// it stands where a go-to put it (1 brought, 2 there: the page before not asked till the reader moves it; 0 not) and
/// the message that go-to went to and its top under the list's (-1 none); the
/// message ⌘F last asked the window moved about (chat.around, -1 none); the row last gone to that flashes and the moment it was gone to ("" none); the row a search opened the chat at and its words,
/// marked there for as long as the list is; 对话目录's round button while it shows (what ⌘G opens the outline beside).
priv struct ChatJump {
  away : @signals.Signal[Bool]
  mut latest : Bool
  sight : @signals.Signal[(String, String)?]
  put : @signals.Signal[Int]
  mut went : (Double, Double)
  mut around : Double
  flashed : @signals.Signal[(String, Double)]
  found : @signals.Signal[(String, Array[String])]
  mut outline_at : @view.View?
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
    flashed: @signals.signal(("", -1.0), same=fn(a, b) { a == b }),
    found: @signals.signal(("", []), same=fn(a, b) { a == b }),
    outline_at: None,
  }
}

///|
/// How far from its end the list is before the way to the newest shows (list_after's `away`: a corner of the screen).
let to_newest_away : Double = 120.0

///|
/// Chat `r`'s list (`jump` what it keeps of it, `place`, its rows `rows`, its view `view`): what it has in sight kept
/// (whether it is away from its end; where the reader is, for a go-to inside the chat to keep: sfbase's Reading,
/// keep_place_of), the kept place
/// forgotten at its end; and the message the chat is to go to (sfbase's go_tos) brought just under what covers the
/// list's top (`cover` tall: the chat's bar), or where the reader was (go_back_to's offset, as kept: sfbase's
/// kept_place_under), once its row is among the keys, the page before asked
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
        @sfbase.go_tos.remove(chat)
        @sfbase.go_to_passages.remove(chat)
        let back = @sfbase.go_back_offsets.get(chat)
        @sfbase.go_back_offsets.remove(chat)
        let words = @sfbase.go_to_words.get(chat).unwrap_or([])
        @sfbase.go_to_words.remove(chat)
        jump.around = -1.0
        // (where it is put, as kept: a message gone to at the edge under the bar)
        let c = @signals.untracked(cover)
        let off = match back {
          Some(off) => off
          None => @sfbase.kept_place_of(0.0, c)
        }
        jump.went = (target, off)
        jump.put.set(1)
        place.bring(k, offset=@sfbase.kept_place_under(off, c))
        // (back where the reader was: nothing of it shown; a search's: its words marked, nothing flashing; else it
        // flashes, from now)
        if back is None {
          if words.length() > 0 {
            jump.found.set((k, words))
          } else {
            let at = v.cause_at()
            jump.flashed.set((k, at))
            @sfbase.flash_rest_nodes.val = at + @sfbase.flash_ms
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
  chat_float_stand(foot, width, lift, shown, fn(o) {
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
/// What a row gone to shows of it (msgFlash, flash_start's): the accent's ground under what `row` holds (its outermost
/// node: across the list, square; a notice's pill, round: `round`), coming in over flash_in_ms on the ease-out, held to
/// flash_held_ms, gone by flash_ms on Leave, from the moment the chat went to row `key` (ChatJump's `flashed`), made then
/// or later; with motion reduced lit whole for flash_ms, then not.
fn chat_flash_node(row : @view.View, key : String, jump : ChatJump, round? : Bool = false) -> Unit {
  row.box(fn(b) {
    let way = @motion.Way::new(0.0)
    let due : Ref[() -> Unit] = Ref(fn() {  })
    b.over(Is(true)).presses(Is(false)) |> ignore
    if round {
      b.radius(Is(1.0e6)) |> ignore
    }
    b.reacts(fn() { chat_gone(jump) }, fn(g) {
      let (k, at) = g
      guard k == key && at >= 0.0 && b.cause_at() < at + @sfbase.flash_ms else { return }
      (due.val)()
      way.go(1.0, @motion.tween(@sfbase.flash_in_ms, ease=Out), at~)
      let out = at + (if @ui.reduced_motion() { @sfbase.flash_ms } else { @sfbase.flash_held_ms })
      due.val = b.at_moment(out, fn() {
        way.go(0.0, @motion.tween(@sfbase.flash_ms - @sfbase.flash_held_ms, ease=Leave), at=out)
      })
    })
    b.owns(fn() { (due.val)() }) |> ignore
    b.ground(By(fn() { lit_by(@ui.tree_theme().color(AccentBg), way.shown_on(b)) })) |> ignore
  })
  |> ignore
}

///|
/// The row the chat last went to that flashes, and the moment it was gone to ("" none), followed.
fn chat_gone(jump : ChatJump) -> (String, Double) {
  jump.flashed.get()
}

///|
/// Colour `c` (0xRRGGBBAA) as clear as `k` (0 to 1) of it.
fn lit_by(c : Int64, k : Double) -> Int64 {
  let a = (c & 0xFFL).to_double() * (if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k })
  (c & 0xFFFFFF00L) | (a + 0.5).to_int64()
}
