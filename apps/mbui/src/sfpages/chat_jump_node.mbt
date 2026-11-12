// What takes a chat's page made as nodes elsewhere in its list (the old list's to_latest and list_after's go-to, as
// results): the way back to the newest, and a message gone to. Out of what the list has in sight (ListPlace::on_sight,
// told at causes) and what the chat is told to go to (sfbase's go_tos, told by go_tos_said); its own state made with
// the list and let go with it (ChatJump).

///|
/// What a chat's list keeps of its way to the newest: whether it is away from its end (more than a corner of the screen
/// as it was last in sight); its latest page asked (chat.latest), the list to its end as it comes.
priv struct ChatJump {
  away : @signals.Signal[Bool]
  mut latest : Bool
}

///|
/// None away yet, nothing asked.
fn ChatJump::new() -> ChatJump {
  { away: @signals.signal(false, same=fn(a, b) { a == b }), latest: false }
}

///|
/// How far from its end the list is before the way to the newest shows (list_after's `away`: a corner of the screen).
let to_newest_away : Double = 120.0

///|
/// Chat `r`'s list (`jump` what it keeps of it, `place`, its rows `rows`, its view `view`): what it has in sight kept
/// (whether it is away from its end; where the reader is, for a go-to inside the chat to keep: sfbase's Reading,
/// keep_place_of), the kept place
/// forgotten at its end; and the message the chat is to go to (sfbase's go_tos) brought just under the list's room at
/// its top (`top`), or where the reader was (go_back_to's offset), once its row is among the keys, the page before asked
/// (`older`, one at a time) while it is not and the chat has pages before; given up where none is left. Asked as the
/// list is made, as its keys change and as the chat is told to go somewhere.
fn chat_goes_to(
  v : @view.View,
  r : ChatRef,
  jump : ChatJump,
  place : @view.ListPlace[String],
  rows : () -> ChatBodyRows,
  view : () -> ChatView,
  top : () -> Double,
  older : () -> Unit,
  shows : () -> Bool,
) -> Unit {
  let chat = r.station + "\u{1}" + r.session
  place.on_sight(fn(s) {
    let cv = @signals.untracked(view)
    jump.away.set(!s.at_foot && s.from_foot > to_newest_away)
    // (placed while it shows: sfbase's keep_place_of)
    let rd = @sfbase.reading_of(chat)
    rd.placed = @signals.untracked(shows)
    match @signals.untracked(rows).rows.get(s.first).map(fn(row) { row.entry }) {
      Some(Said(m)) => {
        rd.top_seq = m.seq
        rd.top_off = -s.into
      }
      _ => ()
    }
    rd.far = cv.newer || (!s.at_foot && s.from_foot > s.shows)
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
        place.bring(k, offset=match back {
          Some(off) => -off
          None => -@signals.untracked(top)
        })
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
/// The way to the newest (to_latest's) in the list's foot `foot`, over its top just over the send button (the composer's
/// column `width` across, `float_in` in from its side, float_lift over the foot): shown while the list is away from its
/// end or the window is short of the chat's end (`view().newer`; how many new messages wait there said then). Pressed,
/// back to where a go-to inside the chat kept the reader first (go_back_to, named 回到刚才的位置), else to its end,
/// asking the chat's latest page first where the window is short of it.
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
  let press = fn() {
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
  // (a row of no height at the foot's top, the button standing over it: where the composer is, whatever its height)
  foot.box(fn(stand) {
    stand.row(Is(true)).height(Is(Some(0.0))) |> ignore
    stand.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
    stand.show(fn() { jump.away.get() || view().newer }, fn(o) {
      let reach = @sf.float_button_reach
      o
      .margin(
        By(fn() {
          let w = width()
          (0.0, -(float_side + 2.0 * reach + float_lift - reach), (w - composer_width(w)) / 2.0 + float_in - reach, 0.0)
        }),
      )
      |> ignore
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
  })
  |> ignore
}
