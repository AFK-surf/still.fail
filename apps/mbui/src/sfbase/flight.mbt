// Words sent flying (ChatHost.kt Flight, FlightLayer; web madeChat.ts): what is sent is in the list the frame it is
// sent, waiting for nothing (chat.mbt LocalSent: the core's row goes on from it once it comes), the words drawn where
// they were typed until its row is laid out; then its bubble goes from the words' place in the field to its own, over
// the composer: across first and up a little after, so the words rise on a curve (Ease.Flight over 80% of its 600 ms, up 12% late), its ground coming
// in round them from a quarter of the way, its time and the rest of its row coming in as they settle (Ease.Arrive from
// 24%). Meanwhile the rows above, put up by the new one at once, go there with the words (sendReflow: on the same
// way up); the composer (its box and its room) stays as tall as when they were sent until they are a quarter of the
// way, coming down then, not from under them as they set out, and its hint comes back once they are out of it (200
// ms, Ease.Arrive). Their row never laid out (its page not shown, 2 s): the composer as it was. With motion reduced (or
// in screenshots) none of it: the row is where it is.
//
// The words are set alike in the field and in their message, and break their lines alike (the theme's `words`, the
// composer's width: SendText.kt), so that only where they are changes: from the frame their message is laid out they
// go in pieces (ChatHost.kt Flight.pieces), what is on one line in the field and on one line in the message (a line
// each, but where a column narrower than the composer breaks a long one anew), each from where it was typed to where
// the message has it, as the bubble goes. Each piece is a copy of the message's words cut to it, so that it is what
// the message draws there as they land; meanwhile the message's own words are not drawn. Words their message has some
// other way (a reference to a chat a chip there) go as one block with their bubble.
//
// The files sent with them go from their tiles in the composer (ChatHost.kt FlyingFile, landingFile, files): drawn as
// their tiles were where they were until the row is in the list, then each to its place in the message, across and up
// as the words go: a picture's box growing from the tile's to the picture's own in the message (a letterboxed one's
// share of its box), the picture cropped to it as it is (opening out from the tile's square crop), on no ground and
// with a file's corner, as the tile and the message draw it; any other file's card carried there, from the tile's size
// to its own. The quotes sent with them go from their cards in the composer, each its card in the message: its words
// from where they were to where it has them, its ground from the composer's card to its own (its edges across, its
// top and bottom and its colour up, on the words' way: the composer's card is as wide as the composer, its own as
// wide as it needs), drawn where its card was, as the composer drew it, until it sets off; its ✕ going with it as it
// sets out, leaving as what leaves goes; its own picture (an image quoted) from its tile in the card to its place in
// the card in the message, as a picture sent with them goes. Sent with no words, the row comes in where it is, its files and quotes flying
// into it, and the composer's hint stays away while a quote is over it.
//
// A new chat's first words are carried (ChatHost.kt Flight.carried, web madeChat.ts): drawn where they were typed from
// the frame they are sent, over the new chat's composer and then its chat's (newchat.mbt makes the chat, the page
// becomes it), until their row is laid out in the chat's list; then the list comes up out of the composer with them,
// on the way any words sent go (520 ms on the flight's curve, across first and up a little after: one motion with every
// send, not the web's quicker landing; 90 after on a phone: the choices fade first; in the wide frame from the middle
// of the page at once, the composer going down to the chat's foot meanwhile: sfpages composer.mbt), their bubble's
// ground and time coming in as they go across. The composer is held as tall as it was while they and their files are in it,
// the new chat's and then its chat's, as for words sent in a chat, till they set out. The list is not cut at the composer's top as
// Android's is (ChatHost.kt clipRect): their bubble, in it, is drawn over the composer only while nothing over it cuts
// what it draws (@ui.Stratum's Flying), and what else is in it then (its time) is all but clear there.

///|
pub(all) struct SendFlight {
  /// the chat it was sent in (its draft's key; its list's turns', turns.mbt), its words, and where they were: their
  /// first line's top left, the field's room (a new chat's: its own, then its chat's as the page becomes it)
  mut chat : String
  mut turns : String
  text : String
  from_x : Double
  from_y : Double
  field_x : Double
  field_y : Double
  field_w : Double
  field_h : Double
  /// the composer's room when sent (held a quarter of the way: `hold`, the composer's own, told how long), and whether
  /// it is the desktop's (the web's flight: desk)
  room : Double
  mut hold : (Double) -> Unit
  desk : Bool
  /// the field's words as it laid them out (where each line starts, where each offset stood) and where the words sent
  /// start in them (what came before them trimmed off): what their pieces go from (flight_pieces); None, they go as
  /// one block
  lines : @ui.FieldLines?
  lead : Int
  /// the composer's marks in its words (refs_sent_marks): drawn as the field drew them, and as their row does
  marks : Array[(Int, Int)]
  /// the files sent with them, from their tiles, and their quotes, from their cards
  files : Array[FlyingFile]
  /// its row's key (what was sent from here, then the core's row it became: chat.mbt row_keys), whether it is laid
  /// out and from which frame; how far it has come (0 … 1, linear,
  /// told to go as its row is first laid out: as Compose's animation, it sets off the frame after)
  mut key : String
  mut placed : Bool
  mut placed_frame : Int
  way : @motion.Anim
  /// what was the composer's alone (a quote's ✕) leaving with them as they set out: from the frame they were sent, as
  /// what leaves goes (@sf.leave)
  gone : @motion.Anim
  /// a new chat's first words: the list comes up with them (flight_carry_start). Where what they go to is to start
  /// from (their bubble's corner, or the first file's tile without words)
  carried : Bool
  from_top : Double
}

///|
/// A file sent with the words (ChatHost.kt FlyingFile): the file it is in its message (file_key: one put up from here
/// its upload, from before it is up on; any other the station's path), its tile in the composer (x, y, w, h in the
/// window), a picture's key ("" a card), and the tile as the composer drew it (what is drawn where it was while the row
/// is not in the list). A quote sent with them (quote_key: its place among the message's quotes) flies from its card in
/// the composer, `ground` that card's colour (0 a file's).
pub(all) struct FlyingFile {
  key : String
  from : (Double, Double, Double, Double)
  picture : String
  face : () -> Unit
  ground : Int64
}

///|
pub let send_flight : @signals.Signal[SendFlight?] = @signals.signal(None)

///|
/// What flies to the `i`th quote of the message words are sent to (as file_key says a file: "upload:<id>").
pub fn quote_key(i : Int) -> String {
  quote_prefix + i.to_string()
}

///|
let quote_prefix : String = "quote:"

///|
/// Where in its box in the message each file flying there lands (flight_landing's `share`, by its landing's key): the
/// share of the box's width and height its picture takes, centred.
let landing_shares : Map[String, (Double, Double)] = {}

///|
/// How long the words take to their place, the share of it they fly (the rest they settle), and from when they
/// settle (ChatHost.kt FLIGHT_MS, FLY, SETTLE).
pub let flight_ms : Double = 600.0

///|
/// How long the words wait over the field for their row; it not come by then, they go.
pub let flight_wait_ms : Double = 2000.0

///|
let flight_fly : Double = 0.8

///|
let flight_settle : Double = 0.24

///|
/// What is sent from the composer of chat `chat` takes off from its field (`field`, before it is emptied: its words set
/// as the theme's `words`, as their message sets them), to row `key` (in the list from now: sent_local). The composer (its box and its room)
/// is held as tall as it was until the words let go of it (`hold`, the composer's, told for how long), said now: at
/// most their wait for the row. `desk`: the desktop's flight (the web's).
pub fn flight_start(
  c : @ui.Ctx,
  chat : String,
  turns : String,
  key : String,
  words : String,
  room : Double,
  files : Array[FlyingFile],
  field~ : String,
  hold~ : (Double) -> Unit,
  desk~ : Bool,
  marks? : Array[(Int, Int)] = [],
) -> Unit {
  send_flight.set(None)
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match c.field_words(field) {
    Some(((x, y), (rx, ry, w, h))) => {
      // the field's words as laid out (scrolled to its last lines when there were more than it holds), its room
      let (lines, lead) = field_lines_of(c, field, words)
      send_flight.set(Some({
        chat,
        turns,
        text: words,
        from_x: x,
        from_y: y,
        field_x: rx,
        field_y: ry,
        field_w: w,
        field_h: h,
        room,
        hold,
        desk,
        lines,
        lead,
        marks,
        files,
        key,
        placed: false,
        placed_frame: -1,
        way: @motion.Anim::new(0.0),
        gone: leaving(),
        carried: false,
        from_top: y - 8.0,
      }))
      hold(flight_wait_ms)
      // a turn among what changes the list's height, till they have landed: what comes after them waits for it, they
      // wait for nothing (list_turns.mbt)
      turns_of(turns).send(c, flight_wait_ms + flight_len(desk))
    }
    None => ()
  }
}

///|
/// What leaves as what was sent sets out (SendFlight's `gone`), set off now.
fn leaving() -> @motion.Anim {
  let a = @motion.Anim::new(0.0)
  a.animate(1.0, @motion.tween(@sf.leave_ms, ease=Leave))
  a
}

///|
/// A new chat's first words (and files) take off from its field (before it is emptied), carried (ChatHost.kt sending,
/// carried): drawn where they were from now, while the chat is made, the new chat's composer held as tall as it was
/// till then (`hold`, its own, told for how long: at most their wait for their row; flight_carry_into hands it on to
/// its chat's). `chat`: the new chat's draft's key, till flight_carry_into; its field, the desktop's or not as
/// flight_start's.
pub fn flight_carry_start(
  c : @ui.Ctx,
  chat : String,
  words : String,
  files : Array[FlyingFile],
  field~ : String,
  hold~ : (Double) -> Unit,
  desk~ : Bool,
  marks? : Array[(Int, Int)] = [],
) -> Unit {
  send_flight.set(None)
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match c.field_words(field) {
    Some(((x, y), (rx, ry, w, h))) => {
      // without words, the list comes up from where the first file was (ChatHost.kt landingFile: rise)
      let from_top = if words != "" {
        y - 8.0
      } else {
        files[0].from.1
      }
      send_flight.set(Some({
        chat,
        turns: "",
        text: words,
        from_x: x,
        from_y: y,
        field_x: rx,
        field_y: ry,
        field_w: w,
        field_h: h,
        room: 0.0,
        hold,
        desk,
        // (carried with the list as its chat comes up: as one block)
        lines: None,
        lead: 0,
        marks,
        files,
        key: "",
        placed: false,
        placed_frame: -1,
        way: @motion.Anim::new(0.0),
        gone: leaving(),
        carried: true,
        from_top,
      }))
      hold(flight_wait_ms)
    }
    None => ()
  }
}

///|
/// The new chat's first words, carried from its draft `from`, go on to the chat it became: its draft `chat`, its list's
/// turns `turns`, row `key` (in its list from now: sent_local), its composer held as the new chat's was (`hold`, the
/// chat's own) till they set out. What is asked in its list after them waits for them.
pub fn flight_carry_into(
  from : String,
  chat : String,
  turns : String,
  key : String,
  hold~ : (Double) -> Unit,
) -> Unit {
  match flight_of(from) {
    Some(f) if f.carried => {
      f.chat = chat
      f.turns = turns
      f.key = key
      f.hold = hold
      hold(flight_wait_ms)
      turns_of(turns).send(@ui.current(), flight_wait_ms + flight_len(f.desk))
    }
    _ => ()
  }
}

///|
/// A new chat's first words, and its files, where they were, while its chat is made (over the new chat's page: till
/// the page is the chat, which draws them then).
pub fn flight_carry_waiting(c : @ui.Ctx) -> Unit {
  match send_flight.get() {
    Some(f) if f.carried => {
      flight_waiting(c, f.chat)
      flight_files(c, f.chat)
    }
    _ => ()
  }
}

///|
/// The new chat's first words not sent (the chat not made, or the message refused): they leave, back in the field.
pub fn flight_carry_gone(from : String) -> Unit {
  match flight_of(from) {
    Some(f) if f.carried => send_flight.set(None)
    _ => ()
  }
}

///|
/// How far the list of chat `chat` is drawn below its place while a new chat's first words carry it up out of the
/// composer (ChatHost.kt Flight.shift): from where they were typed to where their row has them, less as they go; 0
/// none. Where their row is is where this frame lays it out: read once it is laid out (@motion.placed), the list
/// drawn up by it in the same frame, never a frame behind.
pub fn flight_carry_shift(c : @ui.Ctx, chat : String) -> Double {
  match flight_of(chat) {
    Some(f) => flight_carry_rise(c, f) * (1.0 - flight_up_of(c, f))
    None => 0.0
  }
}

///|
/// How far a new chat's list has to come up in all, as its first words set out (flight_carry_shift's at the start):
/// from where they were typed to where their row has them, this frame laid out; 0 for any other words.
fn flight_carry_rise(c : @ui.Ctx, f : SendFlight) -> Double {
  if !f.carried || !f.placed {
    return 0.0
  }
  match @motion.measured_rect(c, flight_carry_anchor(f)) {
    Some((_, y, _, _)) => f.from_top - y
    None => 0.0
  }
}

///|
/// What a new chat's list comes up behind, as measured each build: their bubble (flight_bubble), or without words the
/// first file's place (flight_landing).
pub fn flight_carry_anchor(f : SendFlight) -> String {
  if f.text != "" {
    "flight/carry"
  } else {
    "flight/to/" + f.files[0].key
  }
}

///|
/// The new chat's first words carried, while they wait for their row and go (a new chat's draft `chat`).
pub fn flight_carried(chat : String) -> Bool {
  match flight_of(chat) {
    Some(f) => f.carried
    None => false
  }
}

///|
/// The flight of chat `chat`'s words, while there is one.
pub fn flight_of(chat : String) -> SendFlight? {
  match send_flight.get() {
    Some(f) if f.chat == chat => Some(f)
    _ => None
  }
}

///|
/// How far it has come (0 … 1, linear), from the frame after its row was first laid out.
pub fn flight_p(c : @ui.Ctx, f : SendFlight) -> Double {
  ignore(c)
  f.way.get()
}

///|
/// Its ways across and up (ChatHost.kt Flight.across, up), eased. A new chat's first words are words sent as any are:
/// on the same way, as long (the desktop's: what every composer sends with), the list coming up with them on their way
/// up (flight_carry_shift).
pub fn flight_across_of(c : @ui.Ctx, f : SendFlight) -> Double {
  flight_across(flight_p(c, f), flies_desk(f))
}

///|
pub fn flight_up_of(c : @ui.Ctx, f : SendFlight) -> Double {
  flight_up(flight_p(c, f), flies_desk(f))
}

///|
/// How settled it is (its time and the rest of its row), and how much of its bubble's ground shows.
pub fn flight_settled_of(c : @ui.Ctx, f : SendFlight) -> Double {
  flight_settled(flight_p(c, f), flies_desk(f))
}

///|
pub fn flight_ground_of(c : @ui.Ctx, f : SendFlight) -> Double {
  flight_ground(flight_p(c, f), flies_desk(f))
}

///|
/// Whether it flies the desktop's way (the web's, 520 ms on the flight's curve): what a composer sends does
/// (`desk`), a new chat's first words too, from either frame.
fn flies_desk(f : SendFlight) -> Bool {
  f.desk || f.carried
}

///|
pub fn flight_across(p : Double, desk : Bool) -> Double {
  @ui.Flight.at(dmin(dmin(p / fly_share(desk), 1.0) / 0.88, 1.0))
}

///|
pub fn flight_up(p : Double, desk : Bool) -> Double {
  @ui.Flight.at(dmax((dmin(p / fly_share(desk), 1.0) - 0.12) / 0.88, 0.0))
}

///|
/// The desktop's flight is the web's (madeChat.ts sendingHere): 520 ms, flown the whole of it, its bubble's ground and
/// its time coming in as it goes across; the phone's (ChatHost.kt) 600, flown over 80%, settling from 24%.
pub fn flight_len(desk : Bool) -> Double {
  if desk {
    flight_desk_ms
  } else {
    flight_ms
  }
}

///|
pub let flight_desk_ms : Double = 520.0

///|
pub fn fly_share(desk : Bool) -> Double {
  if desk {
    1.0
  } else {
    flight_fly
  }
}

///|
/// How settled it is (its time and the rest of its row coming in), and how much of its bubble's ground shows.
pub fn flight_settled(p : Double, desk : Bool) -> Double {
  if desk {
    return flight_across(p, desk)
  }
  @ui.Out.at(dclamp((p - flight_settle) / (1.0 - flight_settle), 0.0, 1.0))
}

///|
pub fn flight_ground(p : Double, desk : Bool) -> Double {
  if desk {
    return flight_across(p, desk)
  }
  dclamp((p - flight_settle) / (flight_fly - flight_settle), 0.0, 1.0)
}

///|
/// Each frame, before the chat's list is built: a flight landed, or whose row never came (its wait out: a frame then),
/// is over. On its way it moves by itself (its `way`, told as it set off).
pub fn flight_frame(c : @ui.Ctx, chat : String) -> Unit {
  match flight_of(chat) {
    Some(f) => {
      let turns = turns_of(f.turns)
      let waited = @kit.after(c, "flight/wait", !f.placed, flight_wait_ms)
      // (landed: their way at the end it declared as it set out)
      let landed = f.placed && f.way.over()
      if (!f.placed && waited) || landed {
        send_flight.set(None)
        // their turn over: where they were declared to land (or now, never having set out)
        turns.over(c, Send, if landed { f.way.ends() } else { turns.moment(c) })
      }
    }
    // (none: the wait starts again from nothing for the next words)
    None => @kit.after(c, "flight/wait", false, flight_wait_ms) |> ignore
  }
}

///|
/// Whether row `key` is where the words go.
pub fn flight_takes(chat : String, key : String) -> Bool {
  match flight_of(chat) {
    Some(f) => f.key == key
    None => false
  }
}

///|
/// The row the words go to is in the list: they go from the next frame on, all of their way said now (and the
/// composer let go a quarter of the way).
pub fn flight_placed(c : @ui.Ctx, f : SendFlight) -> Unit {
  if !f.placed {
    f.placed = true
    // the message sent is in the list, its row by its key (its outbox entry's id, or the message's): what a run waits
    // for (`said`), not the words' way there
    c.say("sent row in the list \{f.key}")
    f.placed_frame = c.frame_number()
    if f.carried {
      // a new chat's: once its choices have faded (web: 90 ms after what leaves has begun to); in the wide frame at
      // once, the composer going to the chat's foot with them (Chat.tsx toMadeChat: no wait)
      let after = if f.desk { 0.0 } else { flight_carry_after_ms }
      f.way.animate(1.0, @motion.tween(flight_carry_ms, ease=Linear, delay=after))
      // (the composer let go as they set out: their ground comes in round them from there)
      (f.hold)(after)
    } else {
      f.way.animate(1.0, @motion.tween(flight_len(f.desk), ease=Linear))
      (f.hold)(flight_settle * flight_len(f.desk))
    }
  }
}

///|
/// How long a new chat's first words take to their place (as long as any words sent: flight_len), from how long after
/// their row is laid out (on a phone, once its choices have faded: ChatHost.kt's delay; web madeChat.ts).
pub let flight_carry_ms : Double = flight_desk_ms

///|
pub let flight_carry_after_ms : Double = 90.0

///|
/// The words sent (`chat`'s), as they were typed, over the field, until their row is in the list (and the build it is
/// first laid out in: flight_bubble does not draw them then), their bubble flying whole after; none once their message
/// has them as they were typed, which draws them in pieces from then (flight_pieces_in).
pub fn flight_waiting(c : @ui.Ctx, chat : String) -> Unit {
  let t = @sf.theme()
  match flight_of(chat) {
    // (in pieces: drawn in their bubble, flight_pieces_in)
    Some(f) if flight_pieces(c, f) is Some(_) => ()
    Some(f) if !f.placed || f.placed_frame == c.frame_number() => {
      let l = c.layer(fn() {
        // the field's room where it was in the window, what is in it moved from its corner: moved from where it is
        // laid out (its layer's corner, wherever the page is in the window: a pane beside the sidebar)
        let room = c.box(style=@ui.style(w=Fixed(f.field_w), h=Fixed(f.field_h), clip=true), fn() {
          let words = c.box(style=@sf.full_width, fn() {
            // as the field had them: in the face chosen for what people write (ChatHost.kt SendTextFaced), its marks
            // as it drew them
            c.rich(refs_runs(f.text, f.marks, t.p.accent), key="flight/words", style=t.t.words, trim=true, w=Fill(1.0), words=true)
            |> ignore
          })
          c.look(words, @ui.look(dx=f.from_x - f.field_x, dy=f.from_y - f.field_y))
        })
        @motion.placed(c, room, fn() {
          let (x, y, _, _) = c.node_rect(room)
          @ui.look(dx=f.field_x - x, dy=f.field_y - y)
        })
      })
      // drawn only (ChatHost.kt FlightLayer draws it): not the message, which is not in the list yet
      c.draw_only(l)
    }
    _ => ()
  }
}

///|
/// The words of the message the words sent go to, as its row lays them out (its words' box, marked so: flight_landing_words):
/// where their pieces go.
pub let flight_words_key : String = "flight/landing-words"

///|
/// The box holding the words of the message words sent go to (node `i`, in its bubble): kept where it is laid out and
/// how (words_of, measured_rect), and not drawn while their pieces are (flight_pieces_in).
pub fn flight_landing_words(c : @ui.Ctx, f : SendFlight, i : Int) -> Unit {
  if f.carried {
    return
  }
  c.words(i, flight_words_key)
  @motion.measure(c, i, flight_words_key)
  if flight_pieces(c, f) is Some(_) {
    c.look(i, @ui.look(alpha=0.0))
  }
}

///|
/// A piece of the words sent (ChatHost.kt Piece): what is on one line both in the field and in their message, from
/// `a` until `b` of them; where it stood in the field (its x and its line's top, in the window), and its room in the
/// message's words (x, y, w, h, from their top left).
pub(all) struct FlightPiece {
  a : Int
  b : Int
  from : (Double, Double)
  at : (Double, Double, Double, Double)
}

///|
/// The words sent cut into the pieces that go on their own (ChatHost.kt Flight.pieces), with their message's words as
/// laid out: what is on one line in the field and on one line in the message, each from where it was typed to where
/// the message has it, set alike in both (the theme's `words`), so that only where each is changes. None until their
/// message's words are laid out, or when those are not the words sent (a reference to a chat is a chip there), nor for
/// a new chat's first words (they come up with its list): they go as one block.
pub fn flight_pieces(c : @ui.Ctx, f : SendFlight) -> (Array[FlightPiece], @ui.WordsPiece)? {
  guard f.lines is Some(lines) && !f.carried else { return None }
  // (their shape, not where they lie: placed where they are as laid out, flight_pieces_drawn)
  guard c.words_shape_of(flight_words_key) is Some(w) &&
    w.pieces.length() == 1 &&
    w.text == f.text else {
    return None
  }
  let wp = w.pieces[0]
  let lay = wp.layout
  let n = f.text.length()
  // where a line starts in the field or in the message
  let cuts : Array[Int] = [0, n]
  for s in lines.starts {
    let k = s - f.lead
    if k > 0 && k < n && !cuts.contains(k) {
      cuts.push(k)
    }
  }
  for l in 0..<lay.line_count() {
    let k = lay.line_range(l).0
    if k > 0 && k < n && !cuts.contains(k) {
      cuts.push(k)
    }
  }
  cuts.sort()
  let (_, ry, _, rh) = lines.room
  let lh = lines.line_h()
  let out : Array[FlightPiece] = []
  let shown : Array[Bool] = []
  for i in 0..<(cuts.length() - 1) {
    let a = cuts[i]
    // (without the break that ends its line)
    let mut b = cuts[i + 1]
    while b > a && is_break(f.text.unsafe_charcode_at(b - 1)) {
      b = b - 1
    }
    if b <= a {
      continue
    }
    match lay.rects(a, b) {
      [r] => {
        let (fx, fy) = lines.place(f.lead + a)
        out.push({ a, b, from: (fx, fy), at: r })
        // scrolled out of the field: not seen there
        shown.push(fy + lh / 2.0 >= ry && fy + lh / 2.0 <= ry + rh)
      }
      // (not on one line in the message: as one block)
      _ => return None
    }
  }
  // what was scrolled out of the field comes with the first piece that showed, as the message lays it out by that
  // (one block with it, not each from a place out of sight)
  let mut first = -1
  for i in 0..<shown.length() {
    if shown[i] && first < 0 {
      first = i
    }
  }
  guard first >= 0 else { return None }
  let by = out[first]
  for i in 0..<out.length() {
    let p = out[i]
    if !shown[i] {
      out[i] = { ..p, from: (by.from.0 + p.at.0 - by.at.0, by.from.1 + p.at.1 - by.at.1) }
    }
  }
  Some((out, wp))
}

///|
/// Whether a code unit ends a line (a break typed in the field, the message's own).
fn is_break(u : Int) -> Bool {
  u == 10 || u == 13
}

///|
/// The words sent, in pieces (flight_pieces), drawn in their bubble (node `bubble`, in which this is built: what its
/// row draws over everything as it flies, its ground under them as it comes in), over all it holds.
pub fn flight_pieces_in(c : @ui.Ctx, f : SendFlight, bubble : Ref[Int]) -> Unit {
  match flight_pieces(c, f) {
    Some((pieces, w)) => {
      let l = c.layer(fn() { flight_pieces_drawn(c, f, pieces, w, bubble) })
      c.draw_only(l)
    }
    None => ()
  }
}

///|
/// Where a bubble words fly to sets out from, from the first line of the words as they were typed: its sides round
/// them (the bubble's padding, sfpages message.mbt `bubble`).
let bubble_in_x : Double = 14.0

///|
let bubble_in_y : Double = 8.0

///|
/// The words sent, as their message sets them: one copy of them for each piece, cut to its room there, from where it
/// was in the field to where the message is laid out this frame (flown across and up as their bubble is), with the
/// message's own runs (links as its), so that each piece is what the message draws there when they land. Drawn in
/// the bubble, which is drawn off its place as it flies (flight_bubble): each piece placed in the window, less that.
fn flight_pieces_drawn(
  c : @ui.Ctx,
  f : SendFlight,
  pieces : Array[FlightPiece],
  w : @ui.WordsPiece,
  bubble : Ref[Int],
) -> Unit {
  let t = @sf.theme()
  let flying = f.placed && f.placed_frame != c.frame_number()
  let across = if flying { flight_across_of(c, f) } else { 0.0 }
  let up = if flying { flight_up_of(c, f) } else { 0.0 }
  let runs = message_runs(f.text, t.p.accent, marks=f.marks)
  for k, p in pieces {
    let (ax, ay, aw, ah) = p.at
    let cut = c.box(style=@ui.style(w=Fixed(aw), h=Fixed(ah), clip=true), fn() {
      let all = c.box(style=@ui.style(w=Fixed(w.w)), fn() {
        c.rich(runs, key="flight/piece/\{k}", style=t.t.words, link_color=t.p.blue, words=true) |> ignore
      })
      c.look(all, @ui.look(dx=-ax, dy=-ay))
    })
    // where the message's words are laid out this frame (the list gliding meanwhile), not a frame behind; less how far
    // off its place its bubble is drawn (flight_bubble: from the first line as typed, across and up)
    @motion.placed(c, cut, fn() {
      match @motion.measured_rect(c, flight_words_key) {
        Some((wx, wy, _, _)) if bubble.val >= 0 => {
          let (x, y, _, _) = c.node_rect(cut)
          let (bx, by, _, _) = c.node_rect(bubble.val)
          let ox = (f.from_x - bubble_in_x - bx) * (1.0 - across)
          let oy = (f.from_y - bubble_in_y - by) * (1.0 - up)
          let (fx, fy) = p.from
          @ui.look(dx=fx + (wx + ax - fx) * across - x - ox, dy=fy + (wy + ay - fy) * up - y - oy)
        }
        _ => @ui.look(alpha=0.0)
      }
    })
  }
}

///|
/// The field's lines (`field`'s, as it laid them out) and where `words` start in them, after what came before them
/// that was trimmed off; none when they are not there as they are.
fn field_lines_of(c : @ui.Ctx, field : String, words : String) -> (@ui.FieldLines?, Int) {
  match c.field_lines(field) {
    Some(l) => {
      let mut lead = 0
      while lead < l.text.length() &&
            (
              l.text.unsafe_charcode_at(lead) == 32 ||
              l.text.unsafe_charcode_at(lead) == 9 ||
              is_break(l.text.unsafe_charcode_at(lead))
            ) {
        lead = lead + 1
      }
      if lead + words.length() <= l.text.length() &&
        l.text.view(start_offset=lead, end_offset=lead + words.length()).to_string() == words {
        (Some(l), lead)
      } else {
        (None, 0)
      }
    }
    None => (None, 0)
  }
}

///|
/// The bubble of the row the words go to (node `i`, its words `pad` in from its corner): flown from the field to
/// where it is, over the composer; its ground coming in.
pub fn flight_bubble(c : @ui.Ctx, f : SendFlight, i : Int) -> Unit {
  if f.carried {
    // up with the list (flight_carry_shift), across on its own, over the composer
    @motion.measure(c, i, flight_carry_anchor(f))
    if !f.placed || f.placed_frame == c.frame_number() {
      c.look(i, @ui.look(alpha=0.0))
    }
    @motion.fly(c, i, f.from_x - 14.0, f.from_y - 8.0, px=flight_across_of(c, f), py=1.0)
    return
  }
  if !f.placed || f.placed_frame == c.frame_number() {
    // its first frame: not seen while the words are still drawn as typed, over the field; in pieces, they are its
    // own from it on (its ground not come in yet)
    if flight_pieces(c, f) is None {
      c.look(i, @ui.look(alpha=0.0))
    }
    @motion.fly(c, i, f.from_x - bubble_in_x, f.from_y - bubble_in_y, px=0.0, py=0.0)
    return
  }
  let p = flight_p(c, f)
  @motion.fly(c, i, f.from_x - bubble_in_x, f.from_y - bubble_in_y, px=flight_across(p, f.desk), py=flight_up(p, f.desk))
}

///|
/// Whether the composer's hint is away: words sent are over it, or quotes (their cards as wide as it, the field coming
/// up under them as it comes down), not yet out of it.
pub fn flight_hint_away(c : @ui.Ctx, chat : String) -> Bool {
  match flight_of(chat) {
    // (files alone leave it where it is)
    Some(f) if f.text != "" || f.files.iter().any(fn(ff) { ff.key.has_prefix(quote_prefix) }) =>
      !f.placed || flight_up_of(c, f) < 0.5
    _ => false
  }
}

///|
/// The file of the flight that is file `key` (file_key), if one flies there.
pub fn flight_file_of(f : SendFlight, key : String) -> FlyingFile? {
  f.files.iter().find_first(fn(x) { x.key == key })
}

///|
/// Each file sent (ChatHost.kt FlightLayer, files): as its tile was, where it was, until the row is in the list; then a
/// picture from there to its place in the message (where the message's own box is laid out: flight_landing), its box
/// growing to its picture's there (a letterboxed one's share of it). Over the composer and the list, drawn only.
pub fn flight_files(c : @ui.Ctx, chat : String) -> Unit {
  let f = match flight_of(chat) {
    Some(f) if f.files.length() > 0 => f
    _ => return
  }
  let l = c.layer(fn() {
    for ff in f.files {
      let (fx, fy, fw, fh) = ff.from
      let landing = if f.placed && f.placed_frame != c.frame_number() {
        @motion.measured_rect(c, "flight/to/" + ff.key)
      } else {
        None
      }
      let to = "flight/to/" + ff.key
      let (sw, sh) = landing_shares.get(to).unwrap_or((1.0, 1.0))
      match landing {
        Some((_, _, bw, bh)) if ff.picture != "" => {
          let across = flight_across_of(c, f)
          let up = flight_up_of(c, f)
          let (ew, eh) = (bw * sw, bh * sh)
          let w = fw + (ew - fw) * up
          let h = fh + (eh - fh) * up
          // (on no ground, its corner its tile's in the composer as it leaves, a file's in its message as it lands,
          // in the one change of shape: sfpages composer.mbt, message_files.mbt)
          let corner = @sf.composer_inner() + (@sf.message_file_corner - @sf.composer_inner()) * up
          let pic = c.box(style=@ui.style(w=Fixed(w), h=Fixed(h)), fn() {
            c.image(ff.picture, w=Px(w), h=Px(h), fit=FitCover, radius=corner, bg=0L) |> ignore
          })
          // between its tile and its place as this frame lays it out (not a frame behind), on the words' way: a new
          // chat's list comes up with them on the same (flight_carry_shift), so the picture goes from its tile to its
          // place straight, as their bubble goes from where they were typed to its own, each as far from the other all
          // the way as it starts and ends (a place moving with the list as the target would have it lag the list and
          // cross the words); moved from where it is laid out (its layer's corner, wherever the chat is in the window)
          @motion.placed(c, pic, fn() {
            match @motion.measured_rect(c, to) {
              Some((bx, by, bw, bh)) => {
                let (ex, ey) = (bx + bw * (1.0 - sw) / 2.0, by + bh * (1.0 - sh) / 2.0)
                let (px, py, _, _) = c.node_rect(pic)
                @ui.look(dx=fx + (ex - fx) * across - px, dy=fy + (ey - fy) * up - py)
              }
              None => @ui.look(alpha=0.0)
            }
          })
        }
        // a card on its way is the message's own, carried (flight_landing)
        Some(_) => ()
        None => {
          let tile = c.box(fn() { (ff.face)() })
          @motion.placed(c, tile, fn() {
            let (tx, ty, _, _) = c.node_rect(tile)
            @ui.look(dx=fx - tx, dy=fy - ty)
          })
        }
      }
    }
  })
  // drawn only (ChatHost.kt FlightLayer draws them): not the files, which are the message's
  c.draw_only(l)
  // a quote's ✕, hung on its card's corner as the composer hung it: it goes with the card as it sets out, leaving as
  // what leaves goes (@sf.leave: fading, down to 0.9) from the frame it was sent; over its card, which is over
  // everything as it flies (so in a layer of its own: what is in one only drawn is over the rest of that one alone)
  let gone = f.gone.get()
  if gone < 1.0 && f.files.iter().any(fn(ff) { ff.key.has_prefix(quote_prefix) }) {
    let across = flight_across_of(c, f)
    let up = flight_up_of(c, f)
    let flying = f.placed && f.placed_frame != c.frame_number()
    let reach = @sf.corner_remove_reach(@sf.composer_inner())
    c.layer(fn() {
      for ff in f.files {
        if !ff.key.has_prefix(quote_prefix) {
          continue
        }
        let (fx, fy, fw, _) = ff.from
        let to = "flight/to/" + ff.key
        let x = @sf.corner_remove_face(c)
        c.stratum(x, Flying)
        c.draw_only(x)
        @motion.placed(c, x, fn() {
          // (on the card's ground as this frame draws it: flight_quote_landing's)
          let (gx, gy, gw) = match @motion.measured_rect(c, to) {
            Some((bx, by, bw, _)) if flying => (fx + (bx - fx) * across, fy + (by - fy) * up, fw + (bw - fw) * across)
            _ => (fx, fy, fw)
          }
          let (xx, xy, xw, _) = c.node_rect(x)
          @ui.look(
            alpha=1.0 - gone,
            scale=1.0 - (1.0 - @sf.leave_scale) * gone,
            dx=gx + gw + reach - xw - xx,
            dy=gy - reach - xy,
          )
        })
      }
    })
    |> ignore
  }
}

///|
/// A file of the message words were sent to (node `i`, the box it is laid out in; the file it is, `key`: file_key),
/// while a file flies there (ChatHost.kt landingFile): where it is, kept for the picture flying to it (drawn there by
/// flight_files, not here), and the `share` of the box its picture takes (a letterboxed one's, centred); a card,
/// carried from its tile on the words' way, grown from the tile's size to its own.
pub fn flight_landing(c : @ui.Ctx, f : SendFlight, i : Int, key : String, share? : (Double, Double) = (1.0, 1.0)) -> Unit {
  let ff = match flight_file_of(f, key) {
    Some(ff) => ff
    None => return
  }
  @motion.measure(c, i, "flight/to/" + key)
  landing_shares["flight/to/" + key] = share
  let (fx, fy, fw, fh) = ff.from
  if ff.picture != "" || !f.placed || f.placed_frame == c.frame_number() {
    // its first frame (and a picture all the way): not seen here
    c.look(i, @ui.look(alpha=0.0))
    return
  }
  let up = flight_up_of(c, f)
  // from the tile's size: by the larger of its two shares of its own (Compose's crop to the box)
  let s0 = match @motion.measured_rect(c, "flight/to/" + key) {
    Some((_, _, ew, eh)) if ew > 0.0 && eh > 0.0 => dmax(fw / ew, fh / eh)
    _ => 1.0
  }
  // (in a new chat's list coming up with the words, drawn below its place by as much: from its tile all the same,
  // straight, as its words go: flight_carry_shift)
  @motion.fly(c, i, fx, fy - flight_carry_rise(c, f), scale=s0, px=flight_across_of(c, f), py=up, ps=up)
}

///|
/// A quote's card in the message words were sent to (node `card`, its own box: quote_key `key`), while its card in the
/// composer flies there: what it holds from where it was there (its words `shift` further in there than here:
/// @sf.quote_sent_shift) to where it is laid out, across and up on the words' way, over everything; its ground from
/// the composer's card to its own, its edges across and its top and bottom up, its colour from that card's as it goes
/// up (as seen over anything: the composer's may be see-through). Where each is this frame laid out (@motion.placed), not a frame behind; its first frame not seen here (drawn
/// where it was by flight_files).
pub fn flight_quote_landing(c : @ui.Ctx, f : SendFlight, card : Int, key : String, shift : (Double, Double)) -> Unit {
  let ff = match flight_file_of(f, key) {
    Some(ff) => ff
    None => return
  }
  @motion.measure(c, card, "flight/to/" + key)
  if !f.placed || f.placed_frame == c.frame_number() {
    c.look(card, @ui.look(alpha=0.0))
    return
  }
  let (fx, fw) = (ff.from.0, ff.from.2)
  // (in a new chat's list coming up with the words, drawn below its place by as much: from its card all the same,
  // straight: flight_carry_shift)
  let fy = ff.from.1 - flight_carry_rise(c, f)
  let fh = ff.from.3
  let (sx, sy) = shift
  let across = flight_across_of(c, f)
  let up = flight_up_of(c, f)
  let own = c.node_bg(card)
  let from = if ff.ground != 0L { ff.ground } else { own }
  c.stratum(card, Flying)
  @motion.placed(c, card, fn() {
    let (x, y, w, h) = c.node_rect(card)
    let dx = (fx + sx - x) * (1.0 - across)
    let dy = (fy + sy - y) * (1.0 - up)
    // (its ground drawn before its look, which moves it too)
    c.draw_ground(
      card,
      fx + (x - fx) * across - dx,
      fy + (y - fy) * up - dy,
      fw + (w - fw) * across,
      fh + (h - fh) * up,
      c.node_radii(card),
      bg=@sf.mix_seen(from, 1.0 - up, own),
    )
    @ui.look(dx~, dy~)
  })
}
