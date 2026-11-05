// A chat's messages on the desktop (ember web/src/Chat.tsx ChatShown, ChatRows, useMessageList, ToLatest, ToAsk;
// Chat.css.ts chatMessages, chatToBottom, chatToAsk; styles/session.css.ts chatList): its rows in the column 760 wide
// at most in the pane's middle, running on under the composer; following its end, the pages before and after brought
// in near its edges, put in place once (the unread line, where it was left, where the core opened it), what is read and
// where the reader is told the core: all of that as the phone's list has it too (sfbase's chat_list.mbt: list_frame
// before the rows are drawn, list_after once they are). What comes in does so in its turn (list_turns.mbt): a message
// eases in, an agent's comes out of its activity's picture (emit.mbt), the viewer's own flies in from the composer the
// frame it is sent (flight.mbt), existing messages show at once. Over it, the way to its end
// (⌘↓) and to what waits to be decided.

///|
/// A chat's messages to come while it is read the first time (the library's Waiting, in its bones): made-up messages
/// as its list draws them (row_box, message_row: the viewer's in their bubble, an agent's words under its picture, name
/// and time), as far apart and as far in as the list has them, `top` over the first as over the list's first row.
pub fn chat_messages_sample(c : @ui.Ctx, top : Double) -> Unit {
  let narrow = c.width <= chat_narrow_w
  let gap = if narrow { list_gap_narrow } else { list_gap }
  let side = row_side(c)
  let view = @sfbase.chat_view_made({ "title": Json::string(""), "messages": [] })
  let here : MessageHere = {
    station: "",
    session: "",
    view,
    go: None,
    inline: narrow,
    gutter: side,
    list: None,
    core: None,
  }
  c.box(style=row_column, fn() {
    c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
    for i, m in sample_messages {
      let (mine, lines) = m
      let words = lines.map(@sf.sample_words)
      let said = @sfbase.message_of({
        "ts": Json::string("sample/" + i.to_string()),
        "authorKind": Json::string(if mine { "person" } else { "agent" }),
        "mine": Json::boolean(mine),
        "text": Json::string(words.join("\n\n")),
        "md": Json::array(words.map(fn(w) { Json::array([Json::string("p"), Json::array([Json::string(w)])]) })),
        "by": { "name": Json::string(@sf.sample_words(if mine { 2 } else { 6 })), "maker": { "id": "anthropic" } },
        "time": { "createdAt": { "ago": Json::string(@sf.sample_words(3)), "full": "" } },
      })
      row_box(c, side, if i == 0 { 0.0 } else { gap }, fn() { message_row(c, @sfbase.sample_source, here, said) })
      |> ignore
    }
  })
  |> ignore
}

///|
/// The made-up messages of chat_messages_sample: whether each is the viewer's, and how long each of its paragraphs is
/// (letters): a short ask, an answer of a few lines, and so on, as a chat goes.
// kept across runs: a table, never written
let sample_messages : Array[(Bool, Array[Int])] = [
  (true, [14]),
  (false, [70, 36]),
  (true, [22]),
  (false, [110, 48, 24]),
  (true, [9]),
  (false, [56]),
]

///|
/// Where a row of chat `r`'s list is, and how it moves there.
pub fn here_of(
  r : ChatRef,
  v : ChatView,
  rk : String,
  turns : Turns,
  em : Emits,
  flight : SendFlight?,
  core : Core,
  inline? : Bool = false,
  gutter? : Double = 0.0,
) -> MessageHere {
  {
    station: r.station,
    session: r.session,
    view: v,
    go: Some(fn(seq, passage) { @sfbase.go_to(r, seq, passage~) }),
    inline: inline,
    gutter: gutter,
    list: Some({ rk, turns, emits: em, flight }),
    core: Some(core),
  }
}

///|
/// Chat `r`'s list's key (the composer sends it to its end: the same as the phone's).
pub fn list_key(r : ChatRef) -> String {
  "chat/" + r.station + "/" + r.session
}

///|
/// Which of each chat's asks the bell goes to next (by the chat's key).
pub let ask_turns : Map[String, Int] = {}

///|
/// What ⌘F last asked the window moved about (`chat.around`), once (-1 none).
let find_around : Ref[Double] = Ref(-1.0)

///|
/// The list's ⌘F goes along (ChatFind.tsx `virtual`): the messages showing, the list to a message with the words marked
/// in it, its marks let go.
pub fn chat_find_list(r : ChatRef) -> FindList {
  let k = chat_key(r)
  {
    showing: fn() {
      let rd = reading_of(k)
      (rd.top_seq, rd.bottom_seq)
    },
    go: fn(seq, words) {
      go_tos[k] = seq
      go_to_words[k] = words
    },
    forget: fn() { find_forget() },
  }
}

///|
/// ⌘F let go in the chat it is open in: the words it marked, where it was going, its bar.
pub fn find_forget() -> Unit {
  let k = find_chat()
  match readings.get(k) {
    Some(rd) => {
      rd.found_at = ""
      rd.found_words = []
      rd.found_told.set(@signals.untracked(fn() { rd.found_told.get() }) + 1)
    }
    None => ()
  }
  go_tos.remove(k)
  go_to_words.remove(k)
  find_around.val = -1.0
  find_close()
}

///|
/// The frame each chat's list was last drawn in (chat_list): one not drawn the frame before is coming into view.
// kept across runs: put back by list_reset (reset)
let lists_drawn : Map[String, Int] = {}

///|
/// What the list keeps of its own, let go (the package's reset).
fn list_reset() -> Unit {
  lists_drawn.clear()
  flashing_now.val = ("", 0.0)
  ask_turns.clear()
  find_around.val = -1.0
}

///|
/// How far the rows stand in from the pane's sides: the column 760 wide at most in its middle, 40 in at least
/// (session.css.ts chatList).
fn native_row_inset() -> Double {
  @sf.pane_foot_rest(holds=@sf.theme().round.side) + @sf.composer_pad + 8.0
}

///|
fn row_side(c : @ui.Ctx) -> Double {
  row_side_in(c.width)
}

///|
/// The message column's inset, shared by the list's old rows and its retained loading sample.
fn row_side_in(width : Double) -> Double {
  // Inline avatars need no hanging-avatar gutter. Narrow beside the system's bars (an iPhone Duo's), the rows as wide
  // as the composer words under them, including its inner text padding; elsewhere 16 in.
  if width <= chat_narrow_w {
    return if @sf.native_on() { native_row_inset() } else { row_side_narrow }
  }
  // (beside the system's bars, an iPhone Duo's: the rows across the pane, dense_row_side in)
  if @sf.native_on() {
    return dense_row_side
  }
  dmax(row_side_least, (width - chat_column_w) / 2.0)
}

///|
/// (its pictures out in that room, 29 before the words, about as far from the card's edge as the chat's title: the
/// user, 2026-10-28, 头像都贴边了)
let dense_row_side : Double = 48.0

///|
/// The column's width at most, and how far in its sides stand at least.
let chat_column_w : Double = 760.0

///|
let row_side_least : Double = 40.0

///|
/// A row's height as guessed before it is laid out.
let chat_row_est : Double = 90.0

///|
/// The rows 28 apart (session.css.ts chatList gap), one sent soon after the one before 4 under it.
let list_gap : Double = 28.0

///|
/// The widest a list is laid out narrow (Chat.css.ts `max-width: 700px`), and then 20 between its messages (the web's
/// mobile --list-gap) and 16 in from its sides (session.css.ts chatList).
pub let chat_narrow_w : Double = 700.0

///|
let list_gap_narrow : Double = 20.0

///|
let row_side_narrow : Double = 16.0

///|
let joined_gap : Double = 4.0

///|
pub let bar_foot : Double = 45.0

///|
/// The round buttons over the list (chatToBottom): 32 across, 6 in from the send button's side, 12 over the composer's
/// room; the bell 8 over the way to the end when both show; their icon 16; how long they come and go.
let float_side : Double = 32.0

///|
let float_in : Double = 6.0

///|
let float_lift : Double = 12.0

///|
let float_above : Double = 40.0

///|
let float_icon : Double = 16.0

///|
/// The ring's room round a picture in it (24 round 18).
let ring_room : Double = 3.0

///|
/// A row's room (its node): in from the pane's sides to the column (`side` each), `top` over it. `lit`: how lit it is
/// as a message gone to, and how far its ground reaches over and under it (square, out to the pane's sides as the row
/// runs: nothing of it in a corner; lit one after another, such grounds meet), its words where they are without it;
/// `lit_by`, that band's ground as it is painted instead (Ctx::bg_by: a menu open for it).
fn row_box(
  c : @ui.Ctx,
  side : Double,
  top : Double,
  body : () -> Unit,
  lit? : (Double, Double, Double)? = None,
  lit_by? : (() -> Int64)? = None,
) -> Int {
  // The system column is reserved by the shell; the text still needs its own
  // inset from the card's edge, also when a details card stands beside it.
  let trailing = if @sf.native_side() { native_row_inset() } else { side }
  c.box(style=row_column, fn() {
    if top > 0.0 {
      c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
    }
    let line = match lit {
      Some((_, over, under)) =>
        row_line.then(@ui.style(pt=@sf.room_of(over), mt=@sf.room_of(-over), pb=@sf.room_of(under), mb=@sf.room_of(-under)))
      None => row_line
    }
    c.box(style=line, fn() {
      match lit {
        Some((alpha, _, _)) =>
          match lit_by {
            Some(f) => {
              let g = c.layer(fn() { c.box(style=band_ground, fn() {  }) |> ignore })
              c.bg_by(g, f)
            }
            None => {
              let g = c.layer(fn() { c.box(style=flash_ground, fn() {  }) |> ignore })
              c.look(g, @ui.look(alpha~))
            }
          }
        None => ()
      }
      c.box(style=@ui.style(w=Fixed(side)), fn() {  }) |> ignore
      c.box(style=row_middle, body) |> ignore
      c.box(style=@ui.style(w=Fixed(trailing)), fn() {  }) |> ignore
    })
    |> ignore
  })
}

///|
// kept across runs: a value (no field of it changes)
let row_column : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let row_line : @ui.Style = @ui.css("row w=Full")

///|
// kept across runs: a value (no field of it changes)
let row_middle : @ui.Style = @ui.style(w=@sf.grow)

///|
/// A message's band in a ground drawn as it is painted (its menu open: Ctx::bg_by), the band's room alone.
// kept across runs: a value (no field of it changes)
let band_ground : @ui.Style = @ui.css("w=Full h=Full")

///|
/// A message gone to lit whole, its ground (msgFlash): the accent's, as its row's band (row_box).
// kept across runs: a value (no field of it changes)
let flash_ground : @ui.Style = @ui.css("w=Full h=Full bg=AccentBg")

///|
/// The message gone to flashing in the list drawn now and how far its flash is (its ts, 0 to 1): its row's band
/// (row_box), or the passage a quote quoted behind its words (passage_lit).
pub let flashing_now : Ref[(String, Double)] = Ref(("", 0.0))

///|
/// The passage a quote that led to message `ts` quoted, where its words (box `key` laid out as `words`) have it, and
/// the ground it is drawn on as lit now: the accent's as a passage picked in it has it (pickable), fading with its
/// flash; None for any other message, or one lit whole.
fn passage_lit(c : @ui.Ctx, here : MessageHere, ts : String) -> (Int, Int, Int64)? {
  let rd = match here.list {
    Some(l) => reading_of(l.rk)
    None => return None
  }
  if rd.flash != ts || rd.flash_passage == "" {
    return None
  }
  let lit = flash_of(c, rd, ts)
  match c.words_of("pick/" + ts) {
    Some(w) =>
      match @sf.find_passage(w.text, rd.flash_passage) {
        Some((a, b)) if lit > 0.0 => Some((a, b, @sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha * lit)))
        _ => None
      }
    None => None
  }
}

///|
/// Whether message `ts`'s words are to be kept as laid out for a passage a quote quoted to be found in them.
fn passage_wanted(here : MessageHere, ts : String) -> Bool {
  match here.list {
    Some(l) => {
      let rd = reading_of(l.rk)
      rd.flash == ts && rd.flash_passage != ""
    }
    None => false
  }
}

///|
// kept across runs: a value (no field of it changes)
let float_count : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)


///|
/// The composer's width on a chat's page (dock.css.ts, the chat's: the column and the capsule's curve each side, 760
/// and 22 each side at most, 12 clear of the pane's edges).
pub fn composer_width(pane : Double) -> Double {
  composer_width_in(pane, composer_side())
}

///|
fn composer_width_in(pane : Double, side : Double) -> Double {
  if @sf.native_on() {
    return pane - 2.0 * side
  }
  dmin(pane - 2.0 * side, composer_most)
}

///|
/// The composer's widest (dock.css.ts: 760 and its curve each side), its clearance from the pane's sides.
let composer_most : Double = 804.0

///|
/// The composer's widest as its room is said (composer_width_in): none on a native screen, where it is as wide as its
/// pane leaves it.
fn composer_widest() -> Double? {
  if @sf.native_on() { None } else { Some(composer_most) }
}

///|
/// (In a panel of its own, as far in as makes its box concentric with the panel's foot corners its round controls can
/// follow in turn in its own: @sf.pane_foot_in.)
pub fn composer_side() -> Double {
  @sf.pane_foot_in(holds=@sf.theme().round.side)
}
