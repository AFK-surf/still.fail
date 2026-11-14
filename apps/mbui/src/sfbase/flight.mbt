// Words sent flying (FlightLayer): what is sent is in the list the frame it is
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
// go in pieces, what is on one line in the field and on one line in the message (a line
// each, but where a column narrower than the composer breaks a long one anew), each from where it was typed to where
// the message has it, as the bubble goes. Each piece is a copy of the message's words cut to it, so that it is what
// the message draws there as they land; meanwhile the message's own words are not drawn. Words their message has some
// other way (a reference to a chat a chip there) go as one block with their bubble.
//
// The files sent with them go from their tiles in the composer (landingFile, files): drawn as
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
// A new chat's first words are carried: drawn where they were typed from
// the frame they are sent, over the new chat's composer and then its chat's (newchat.mbt makes the chat, the page
// becomes it), until their row is laid out in the chat's list; then the list comes up out of the composer with them,
// on the way any words sent go (520 ms on the flight's curve, across first and up a little after: one motion with every
// send, not the web's quicker landing; 90 after on a phone: the choices fade first; in the wide frame from the middle
// of the page at once, the composer going down to the chat's foot meanwhile: sfpages composer.mbt), their bubble's
// ground and time coming in as they go across. The composer is held as tall as it was while they and their files are in it,
// the new chat's and then its chat's, as for words sent in a chat, till they set out. The list is not cut at the composer's top as
// Android's is: their bubble, in it, is drawn over the composer only while nothing over it cuts
// what it draws (@ui.Stratum's Flying), and what else is in it then (its time) is all but clear there.

///|
pub(all) struct SendFlight {
  /// which words sent these are, of all sent in the run: what is measured for them is kept by it (flight_words_key,
  /// flight_to_key), so that those sent before them, still on their way, keep their own (flights_on)
  n : Int
  /// the chat it was sent in (its draft's key; its list's turns'), its words, and where they were: their
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
  /// the composer's room when sent, and whether it is the desktop's (the web's flight: desk)
  room : Double
  desk : Bool
  /// what holds the composer they were sent from while they are in it, theirs (this send's, its chat's: another chat's
  /// composer never reads it): what its shape was for as they were sent (`shaped`, the composer's: its words, quotes
  /// and files) and how many lines they took in its field (`held_lines`), as the field had them; it stays as it is
  /// laid out for them till they let go of it (flight_lets_go), whatever is in it meanwhile
  shaped : String
  held_lines : Int
  /// how tall what was added to it (its quotes, its files) was laid out as they were sent, read in the frame they were
  /// sent once it was laid out with them (the frame built again for it: flight_start), -1 till then; held so too
  mut held_extras : Double
  /// the moment they were sent, and whether what the composer was on its way to then has been told to stop there
  /// (its growing a line: the words gone, it grows no further for them; sfpages composer's, @motion.stop_for)
  sent_at : Double
  mut stopped : Bool
  /// how far the list's foot is drawn over where it comes to stand (the composer's room at rest, its target: what is
  /// on its way to it, a line more just typed, not over), the composer's own: their row's place at rest is where this
  /// frame lays it out less that (flight_timed)
  mut foot_lift : (@ui.Ctx) -> Double
  /// the field's words as it laid them out (where each line starts, where each offset stood) and where the words sent
  /// start in them (what came before them trimmed off): what their pieces go from (flight_pieces); None, they go as
  /// one block
  lines : @ui.FieldLines?
  lead : Int
  /// the composer's marks in its words (refs_sent_marks), and the runs their row draws them in (refs_sent_runs: the
  /// core's; None, as they are), which they fly in from where the field drew them alike (refs_look)
  marks : Array[(Int, Int)]
  runs : Json?
  /// the files sent with them, from their tiles, and their quotes, from their cards
  files : Array[FlyingFile]
  /// its row's key (what was sent from here, then the core's row it became: chat.mbt row_keys), whether it is laid
  /// out (from the moment `set_out`); how far it has come (0 … 1, linear,
  /// told to go as its row is first laid out: at that moment still where it was, on its way from any after: flight_going)
  mut key : String
  mut placed : Bool
  way : @motion.Anim
  /// what was the composer's alone (a quote's ✕ and empty comment hint) leaving as they set out (@sf.leave)
  gone : @motion.Anim
  /// a new chat's first words: the list comes up with them (flight_carry_start). Where what they go to is to start
  /// from (their bubble's corner, or the first file's tile without words)
  carried : Bool
  from_top : Double
  /// how long their way takes (flight_way_ms: as long as it is far, from where they were typed to where their row
  /// stands at rest), said once, as their row is first laid out (`timed`, in the frame it is placed: flight_placed);
  /// when they set out (the moment their row was first in the list), after how long
  mut ms : Double
  mut timed : Bool
  mut set_out : Double
  mut after : Double
}

///|
/// A file sent with the words: the file it is in its message (file_key: one put up from here
/// its upload, from before it is up on; any other the station's path), its tile in the composer (x, y, w, h in the
/// window), a picture's key (None a card, Some("") a picture still coming), and the tile as the composer drew it (what
/// is drawn where it was while the row is not in the list). Its landing supplies the same picture painter its message
/// uses, so the flying picture and the one at rest always follow the same display path. A quote sent with them
/// (quote_key: its place among the message's quotes) flies from its card in the composer, `ground` that card's colour;
/// `leaving` is a part of that card only the composer shows, with its own place and face. `quote_words` keeps the
/// source's text width and the destination's measurement key; `quote_to` remembers its natural width once laid out.
pub(all) struct FlyingFile {
  key : String
  from : (Double, Double, Double, Double)
  /// The source's visible part and opacity, if it was still coming into its container when sent.
  shown : @ui.DrawnState?
  picture : String?
  mut paint : ((Double, Double, @ui.Fit, Double) -> Unit)?
  face : (@ui.Ctx) -> Unit
  ground : Int64
  leaving : ((Double, Double, Double, Double), (@ui.Ctx) -> Unit)?
  quote_words : (String, Double)?
  mut quote_to : Double?
}

///|
pub let send_flight : @signals.Signal[SendFlight?] = @signals.signal(None)

///|
/// Words sent before the last, on their way as more were sent (flight_start): each goes on to its row as it was
/// going, until it lands (flight_frame). The last sent alone (send_flight) are the composer's and the list's: these
/// are only their rows' (flight_to), which draw them. Dropped as the next were sent, they stood in their row at once,
/// from wherever they were on the way (26 points off it, in one frame, with the next sent 300 ms after them).
let flights_on : @signals.Signal[Array[SendFlight]] = @signals.signal([], same=fn(a, b) {
  // (the same words sent, by their numbers: none set again as none tells nothing)
  guard a.length() == b.length() else { return false }
  for i in 0..<a.length() {
    if a[i].n != b[i].n {
      return false
    }
  }
  true
})

///|
/// How many words sent have flown in the run (SendFlight's `n`).
let flights_n : Ref[Int] = { val: 0 }

///|
/// More is sent: the words sent before, on their way to their row and out of the field (flight_out), go on
/// (flights_on). Still over the field, where the words now sent are drawn as typed till their row is laid out, they
/// would lie under those: in their row at once, as those not yet set out (their row not laid out) and a new chat's
/// first (its list coming up with them).
fn flight_next(c : @ui.Ctx) -> Int {
  match send_flight.get() {
    Some(f) if !f.carried && flight_going(c, f) && !f.way.over(c) && flight_out(c, f) =>
      flights_on.set([..flights_on.get(), f])
    _ => ()
  }
  send_flight.set(None)
  flights_n.val += 1
  flights_n.val
}

///|
/// No words sent fly (a run's start).
pub fn flights_reset() -> Unit {
  send_flight.set(None)
  flights_on.set([])
  flights_n.val = 0
  landing_shares.clear()
}

///|
/// The words sent in chat `chat` on their way to row `key`: the last sent (flight_of), or those sent before them
/// still going there.
pub fn flight_to(chat : String, key : String) -> SendFlight? {
  match flight_of(chat) {
    Some(f) if f.key == key => Some(f)
    _ => flights_on.get().iter().find_first(fn(f) { f.chat == chat && f.key == key })
  }
}

///|
/// Where the words of the message words sent `f` go to are laid out is kept by this (flight_landing_words).
pub fn flight_words_key(f : SendFlight) -> String {
  "flight/landing-words/\{f.n}"
}

///|
/// Where file `key` (file_key, quote_key) of the message words sent `f` go to is laid out is kept by this
/// (flight_landing, flight_quote_landing).
pub fn flight_to_key(f : SendFlight, key : String) -> String {
  "flight/to/\{f.n}/" + key
}

///|
/// What flies to the `i`th quote of the message words are sent to (as file_key says a file: "upload:<id>").
pub fn quote_key(i : Int) -> String {
  quote_prefix + i.to_string()
}

///|
/// What flies to the picture in the `i`th quote: each quote has its own picture even when several name one file.
pub fn quote_picture_key(i : Int) -> String {
  quote_picture_prefix + i.to_string()
}

///|
let quote_picture_prefix : String = "quote-picture:"

///|
let quote_prefix : String = "quote:"

///|
/// Where in its box in the message each file flying there lands (flight_landing's `share`, by its landing's key): the
/// share of the box's width and height its picture takes, centred, and whether its crop begins at the top.
let landing_shares : Map[String, (Double, Double, Bool)] = Map([])

///|
/// How long the words take to their place, the share of it they fly (the rest they settle), and from when they
/// settle (FLY, SETTLE).
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
  field~ : @ui.Field,
  shaped~ : String,
  foot_lift~ : (@ui.Ctx) -> Double,
  desk~ : Bool,
  marks? : Array[(Int, Int)] = [],
  runs? : Json? = None,
) -> Unit {
  let n = flight_next(c)
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match field.words_at() {
    Some(((x, y), (rx, ry, w, h))) => {
      // the field's words as laid out (scrolled to its last lines when there were more than it holds), its room
      let (lines, lead) = field_lines_of(field, words)
      send_flight.set(Some({
        n,
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
        desk,
        shaped,
        held_lines: field_lines_n(field),
        held_extras: -1.0,
        sent_at: c.moment(),
        stopped: false,
        foot_lift,
        lines,
        lead,
        marks,
        runs,
        files,
        key,
        placed: false,
        way: @motion.Anim::new(0.0),
        gone: leaving(c),
        carried: false,
        from_top: y - 8.0,
        ms: flight_len(desk),
        timed: false,
        set_out: -1.0,
        after: 0.0,
      }))
      // (they wait for nothing, nor does anything wait for them: the chat's list's turns told they set out,
      // list_turns.mbt)
      turns_of(turns).send(c)
    }
    None => ()
  }
}

///|
/// How many lines the words in field `field` take in it, as it lays them out now (none: a line).
pub fn field_lines_n(field : @ui.Field) -> Int {
  match field.lines() {
    Some(l) => if l.starts.length() > 0 { l.starts.length() } else { 1 }
    None => 1
  }
}

///|
/// What leaves as what was sent sets out (SendFlight's `gone`), set off now.
fn leaving(c : @ui.Ctx) -> @motion.Anim {
  let a = @motion.Anim::new(0.0)
  a.animate(c, 1.0, @motion.tween(@sf.leave_ms, ease=Leave))
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
  field~ : @ui.Field,
  shaped~ : String,
  desk~ : Bool,
  marks? : Array[(Int, Int)] = [],
  runs? : Json? = None,
) -> Unit {
  let n = flight_next(c)
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match field.words_at() {
    Some(((x, y), (rx, ry, w, h))) => {
      // without words, the list comes up from where the first file was
      let from_top = if words != "" {
        y - 8.0
      } else {
        files[0].from.1
      }
      send_flight.set(Some({
        n,
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
        desk,
        shaped,
        held_lines: field_lines_n(field),
        held_extras: -1.0,
        sent_at: c.moment(),
        stopped: false,
        // (not timed: their way is the list's coming up, flight_carry_ms)
        foot_lift: fn(_) { 0.0 },
        // (carried with the list as its chat comes up: as one block)
        lines: None,
        lead: 0,
        marks,
        runs,
        files,
        key: "",
        placed: false,
        way: @motion.Anim::new(0.0),
        gone: leaving(c),
        carried: true,
        ms: flight_carry_ms,
        timed: false,
        set_out: -1.0,
        after: 0.0,
        from_top,
      }))
    }
    None => ()
  }
}

///|
/// The new chat's first words, carried from its draft `from`, go on to the chat it became: its draft `chat`, its list's
/// turns `turns`, row `key` (in its list from now: sent_local), its composer held as the new chat's was (theirs, read by
/// the composer of the chat they are in: flight_held_lines) till they set out. What is asked in its list after them
/// waits for them.
pub fn flight_carry_into(
  c : @ui.Ctx,
  from : String,
  chat : String,
  turns : String,
  key : String,
) -> Unit {
  match flight_of(from) {
    Some(f) if f.carried => {
      f.chat = chat
      f.turns = turns
      f.key = key
      turns_of(turns).send(c)
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
/// composer: from where they were typed to where their row has them, less as they go; 0
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
    flight_to_key(f, f.files[0].key)
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
/// How far it has come (0 … 1, linear), from the moment its row was first laid out.
pub fn flight_p(c : @ui.Ctx, f : SendFlight) -> Double {
  ignore(c)
  f.way.get(c)
}

///|
/// Its ways across and up (up), eased. A new chat's first words are words sent as any are:
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
/// Whether its bubble's ground shows whole (flight_ground_of at its end), read as it gets there, not where it is each
/// frame (way_reaches): what is built otherwise till then (its ground drawn apart, coming in) built again at that moment.
pub fn flight_grounded(c : @ui.Ctx, f : SendFlight) -> Bool {
  // (told anew as it is timed: built again, as what reads whether it is over is; flight_frame reads it so too)
  ignore(f.way.over(c))
  way_reaches(c, f.way, fn(p) { flight_ground(p, flies_desk(f)) >= 1.0 })
}

///|
/// Whether `holds` holds of where `a` (words sent's way, what leaves as they set out) is at this moment, read as it is
/// built without following the way frame by frame: what reads it is built again in the first frame drawn at or past
/// the first moment on its declared way that `holds` does (Ctx::shows_from: drawn each frame while it goes, it asks no
/// frame of its own), so that it shows what that frame's moment is, as reading where it is each frame did, and nothing
/// built from it is built again each frame it goes. `holds` once true stays so on the rest of the way (a share of it
/// reached). What is told anew (words sent's way, as it is timed) its caller follows (Anim::over).
fn way_reaches(c : @ui.Ctx, a : @motion.Anim, holds : (Double) -> Bool) -> Bool {
  let now = c.moment()
  if holds(a.value_at(now)) {
    return true
  }
  let end = a.ends()
  if end < @double.infinity && end > now && holds(a.value_at(end)) {
    // (the first moment it holds, on the way told: as near as the clock's numbers tell)
    let mut lo = now
    let mut hi = end
    for _ in 0..<80 {
      let mid = lo + (hi - lo) / 2.0
      if mid <= lo || mid >= hi {
        break
      }
      if holds(a.value_at(mid)) {
        hi = mid
      } else {
        lo = mid
      }
    }
    c.shows_from(hi)
  }
  false
}

///|
/// How far what leaves as they set out has gone (SendFlight's `gone`), where it is drawn.
fn flight_gone(c : @ui.Ctx, f : SendFlight) -> Double {
  f.gone.get(c)
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
/// The desktop's flight is the web's: 520 ms, flown the whole of it, its bubble's ground and
/// its time coming in as it goes across; the phone's 600, flown over 80%, settling from 24%.
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
/// How long the composer words were sent from takes to come down once they let go of it, its room with it
/// (composer_hold): words sent's own, set with their flight's (sf/motion.mbt kind 4), not a Move's by its way.
pub let sent_down_ms : Double = 300.0


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
/// Words sent `f` are over: where their files landed in their boxes (landing_shares) is kept no more.
fn flight_shares_gone(f : SendFlight) -> Unit {
  for ff in f.files {
    landing_shares.remove(flight_to_key(f, ff.key))
  }
}

///|
/// Each frame, before the chat's list is built: a flight landed, or whose row never came (its wait out: a frame then),
/// is over. On its way it moves by itself (its `way`, told as it set off).
pub fn flight_frame(c : @ui.Ctx, chat : String) -> Unit {
  // (those sent before the last, landed: their rows' own from here, whichever chat's)
  if flights_on.get().iter().any(fn(f) { f.way.over(c) }) {
    flights_on.get().each(fn(f) { if f.way.over(c) { flight_shares_gone(f) } })
    flights_on.set(flights_on.get().filter(fn(f) { !f.way.over(c) }))
  }
  match flight_of(chat) {
    Some(f) => {
      let turns = turns_of(f.turns)
      flight_timed(c, f)
      // (landed: their way at the end it declared as it set out; till their row is in the list they wait for it, no
      // moment of theirs said: it is in it from the press, sent_local)
      let landed = f.placed && f.timed && f.way.over(c)
      if landed {
        send_flight.set(None)
        flight_shares_gone(f)
        // their turn over: where they were declared to land (or now, never having set out)
        turns.over(c, Send)
      }
    }
    None => ()
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
/// The row the words go to is in the list: they set out at this moment. A new chat's go as their list comes up, all of
/// their way said now; any other's is said in this frame too, once their row is laid out (flight_timed: the height of
/// it read as it is built, the frame built again at this moment once it is laid out, before it is drawn, as any read
/// of a height laid out in that frame is, mbui's motion measures_told_once), so no frame draws them on a way not theirs.
pub fn flight_placed(c : @ui.Ctx, f : SendFlight) -> Unit {
  if !f.placed {
    f.placed = true
    // the message sent is in the list, its row by its key (its outbox entry's id, or the message's): what a run waits
    // for (`said`), not the words' way there
    c.say("sent row in the list \{f.key}")
    f.set_out = c.moment()
    if f.carried {
      // a new chat's: once its choices have faded (web: 90 ms after what leaves has begun to); in the wide frame at
      // once, the composer going to the chat's foot with them (Chat.tsx toMadeChat: no wait); the composer let go as
      // they set out, their ground coming in round them from there (flight_lets_go)
      f.after = if f.desk { 0.0 } else { flight_carry_after_ms }
      f.timed = true
      f.way.animate(c, 1.0, @motion.tween(f.ms, ease=Linear, delay=f.after))
    } else {
      // (how tall what they go to is, read as their row is built: none yet, the frame built again once this build has
      // laid it out, their way said then, flight_timed)
      ignore(@motion.measured(c, flight_target_key(f)))
    }
  }
}

///|
/// Whether words sent are on their way: their row was first in the list at a moment before this one (flight_placed's
/// `set_out`), so it has been laid out and where it is known. At the moment it is placed (in every frame drawn then,
/// however many) they are still where they were, its row not seen: what is drawn at a moment is what that moment
/// is, not how many frames came before it.
fn flight_going(c : @ui.Ctx, f : SendFlight) -> Bool {
  // (placed now: what reads it built again the next frame, as they set out)
  if f.placed && c.moment() <= f.set_out {
    c.shows_until(f.set_out)
  }
  f.placed && c.moment() > f.set_out
}

///|
/// Where words sent `f` go to in their row, what their way is timed by (flight_timed): their words' box, or the first
/// file's place ("": nothing).
fn flight_target_key(f : SendFlight) -> String {
  if f.text != "" {
    flight_words_key(f)
  } else if f.files.length() > 0 {
    flight_to_key(f, f.files[0].key)
  } else {
    ""
  }
}

///|
/// Once their row is laid out (the frame it was placed in, built again: flight_placed), their way said, once: as long as
/// it is far from where they were typed to where their row stands at rest (their words' box, or the first file's
/// place), the furthest of across and up, from the moment they set out. Where it stands at rest: the list's foot where
/// it comes to stand (the composer's room at its target, `foot_lift` under where it is drawn now), their row as far over
/// it as this frame lays it out (a place in the list against its foot, whatever is on its way under it). Its row's room
/// and the composer's letting go go by that (flight_lets_go, shown_rows).
fn flight_timed(c : @ui.Ctx, f : SendFlight) -> Unit {
  // (a new chat's first words go with their page's change, the composer going to the chat's foot on their clock,
  // told as the page changed: as long as any, flight_carry_ms)
  if !f.placed || f.timed || f.carried {
    return
  }
  let to = flight_target_key(f)
  // (laid out yet in this frame: none the build that placed it, the frame built again once it is, its height read
  // here; nothing to read, a flight of nothing, timed as it is)
  if to != "" && @motion.measured(c, to) is None {
    return
  }
  f.timed = true
  match @motion.measured_rect(c, to) {
    Some((x, y, _, _)) => {
      match c.list_info(flight_list_key(f)) {
        // (read up the list so far that its end is not laid out, gliding to it as they go, list_to_end: where their row
        // comes to stand is not known of its layout, as long as words sent take over their usual way)
        Some(i) if !i.at_end && i.below >= 1.0e8 => ()
        info => {
          // (read up the list a little: at rest as far up as its end is under its view now)
          let below = match info {
            Some(i) if !i.at_end && i.below > 0.0 => i.below
            _ => 0.0
          }
          let rest_y = y + (f.foot_lift)(c) - below
          f.ms = flight_way_ms(flies_desk(f), dmax((x - f.from_x).abs(), (rest_y - f.from_y).abs()))
        }
      }
    }
    // (nowhere laid out: as long as words sent take over their usual way)
    None => ()
  }
  f.way.animate(c, 1.0, @motion.tween(f.ms, ease=Linear, delay=f.after), start_at=f.set_out)
}

///|
/// The list of the chat words sent `f` go into (sfpages chat_list's key: its station's and its session's).
fn flight_list_key(f : SendFlight) -> String {
  "chat/" + f.turns.replace(old="\u{1}", new="/")
}

///|
/// When the composer of chat `chat` is let go by the words sent from it, and how long it then takes to come down (its
/// room with it): a share of their way on, as long as what is left of it, so their row opening, the composer coming
/// down and its room closing go as one (shown_rows, the composer's reshape); a new chat's as they set out, down in sent_down_ms. Said once,
/// as their way is (flight_timed); None till then, the composer held as it is.
pub fn flight_lets_go(chat : String) -> (Double, Double)? {
  match flight_of(chat) {
    Some(f) if f.placed && f.timed =>
      if f.carried {
        Some((f.set_out + f.after, sent_down_ms))
      } else {
        Some((f.set_out + flight_settle * f.ms, (1.0 - flight_settle) * f.ms))
      }
    _ => None
  }
}

///|
/// The lines the words sent from chat `chat` took in its composer's field, while they hold it (till they let go of
/// it, flight_lets_go): 0 when nothing does.
pub fn flight_held_lines(c : @ui.Ctx, chat : String) -> Int {
  match (flight_of(chat), flight_lets_go(chat)) {
    (Some(_), Some((at, _))) if c.moment() >= at => 0
    (Some(f), held) => {
      // (built again as they let go of it, in the first frame drawn at or past that moment: their way is drawn each
      // frame meanwhile)
      match held {
        Some((at, _)) if c.moment() < at => c.shows_from(at)
        _ => ()
      }
      f.held_lines
    }
    _ => 0
  }
}

///|
/// What the composer of chat `chat` is shaped for while words sent from it hold it (as they were sent, SendFlight's
/// `shaped`); None when nothing does.
pub fn flight_held_shaped(c : @ui.Ctx, chat : String) -> String? {
  if flight_held_lines(c, chat) > 0 {
    flight_of(chat).map(fn(f) { f.shaped })
  } else {
    None
  }
}

///|
/// How long words sent take over a way `points` far: as their flight takes over a sent message's usual way
/// (flight_len, 200 points: from a phone's field across to its bubble), longer or shorter as a Move of it is
/// (@ui.move_ms: the further the longer, not in proportion).
pub fn flight_way_ms(desk : Bool, points : Double) -> Double {
  (flight_len(desk) * @ui.move_ms(points) / @ui.move_ms(flight_way_points)).round()
}

///|
/// The longest words sent take to their place, however far (a phone's flight over a Move's longest way): any flight is
/// over by then.
pub let flight_most_ms : Double = (flight_ms * @ui.move_most_ms / @ui.move_ms(flight_way_points)).round()

///|
/// A sent message's usual way from where it was typed to its bubble (points): what flight_len is the length of.
let flight_way_points : Double = 200.0

///|
/// How long words sent `f` take to their place, as it is told now (flight_timed).
pub fn flight_ms_of(f : SendFlight) -> Double {
  f.ms
}

///|
/// How long a new chat's first words take to their place (as long as any words sent: flight_len), from how long after
/// their row is laid out (on a phone).
pub let flight_carry_ms : Double = flight_desk_ms

///|
pub let flight_carry_after_ms : Double = 90.0

///|
/// The words sent (`chat`'s), as they were typed, over the field, until their row is in the list (and at the moment it is
/// first laid out: flight_bubble does not draw them then), their bubble flying whole after; none once their message
/// has them as they were typed, which draws them in pieces from then (flight_pieces_in).
pub fn flight_waiting(c : @ui.Ctx, chat : String) -> Unit {
  let t = @sf.theme()
  match flight_of(chat) {
    // (in pieces: drawn in their bubble, flight_pieces_in)
    Some(f) if flight_pieces(c, f) is Some(_) => ()
    Some(f) if !flight_going(c, f) => {
      let l = c.layer(fn() {
        // the field's room where it was in the window, what is in it moved from its corner: moved from where it is
        // laid out (its layer's corner, wherever the page is in the window: a pane beside the sidebar)
        let room = c.box(style=@ui.style(w=Fixed(f.field_w), h=Fixed(f.field_h), clip=true), fn() {
          let words = c.box(style=@sf.full_width, fn() {
            // in the face chosen for what people write, as their message will draw them
            c.rich(person_runs(f.text, f.runs, t.p.accent), key="flight/words", style=t.t.words, link_color=t.p.blue, trim=true, w=Fill(1.0), words=true)
            |> ignore
          })
          c.look(words, @ui.look(dx=f.from_x - f.field_x, dy=f.from_y - f.field_y))
        })
        @motion.placed(c, room, fn() {
          let (x, y, _, _) = c.node_rect(room)
          @ui.look(dx=f.field_x - x, dy=f.field_y - y)
        })
      })
      // drawn only: not the message, which is not in the list yet
      c.draw_only(l)
    }
    _ => ()
  }
}

///|
/// The box holding the words of the message words sent go to (node `i`, in its bubble): kept where it is laid out and
/// how (words_of, measured_rect), and not drawn while their pieces are (flight_pieces_in).
pub fn flight_landing_words(c : @ui.Ctx, f : SendFlight, i : Int) -> Unit {
  if f.carried {
    return
  }
  c.words(i, flight_words_key(f))
  @motion.measure(c, i, flight_words_key(f))
  if flight_pieces(c, f) is Some(_) {
    c.look(i, @ui.look(alpha=0.0))
  }
}

///|
/// A piece of the words sent: what is on one line both in the field and in their message, from
/// `a` until `b` of them; where it stood in the field (its x and its line's top, in the window), and its room in the
/// message's words (x, y, w, h, from their top left).
pub(all) struct FlightPiece {
  a : Int
  b : Int
  from : (Double, Double)
  at : (Double, Double, Double, Double)
}

///|
/// The words sent cut into the pieces that go on their own, with their message's words as
/// laid out: what is on one line in the field and on one line in the message, each from where it was typed to where
/// the message has it, set alike in both (the theme's `words`), so that only where each is changes. None until their
/// message's words are laid out, or when those are not the words sent (a run the core changed, such as a link written out), nor for
/// a new chat's first words (they come up with its list): they go as one block.
pub fn flight_pieces(c : @ui.Ctx, f : SendFlight) -> (Array[FlightPiece], @ui.WordsPiece)? {
  guard f.lines is Some(lines) && !f.carried else { return None }
  // (their shape, not where they lie: placed where they are as laid out, flight_pieces_drawn)
  let gone = marks_brackets(f.marks)
  let said = flight_said(f)
  guard c.words_shape_of(flight_words_key(f)) is Some(w) &&
    w.pieces.length() == 1 &&
    w.text == said else {
    return None
  }
  let wp = w.pieces[0]
  let lay = wp.layout
  let n = said.length()
  // where a line starts in the field or in the message
  let cuts : Array[Int] = [0, n]
  for s in lines.starts {
    let k = said_at(s - f.lead, gone)
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
    while b > a && is_break(said.unsafe_get(b - 1).to_int()) {
      b = b - 1
    }
    if b <= a {
      continue
    }
    match lay.rects(a, b) {
      [r] => {
        let (fx, fy) = lines.place(f.lead + sent_at(a, gone))
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
/// What the words sent say in their message: a mark's `[` and `]` are the field's alone, taking no room there.
pub fn flight_said(f : SendFlight) -> String {
  words_without(f.text, marks_brackets(f.marks))
}

///|
/// Where marks `marks` (in words sent) have their `[` and `]`, in order.
fn marks_brackets(marks : Array[(Int, Int)]) -> Array[Int] {
  let out : Array[Int] = []
  for m in marks {
    out.push(m.0 + 1)
    out.push(m.1 - 1)
  }
  out
}

///|
/// Words `s` without what stands at `gone`.
fn words_without(s : String, gone : Array[Int]) -> String {
  let sb = StringBuilder()
  let mut at = 0
  for g in gone {
    sb.write_string(s.clamped_view(start=at, end=g).to_owned())
    at = g + 1
  }
  sb.write_string(s.clamped_view(start=at).to_owned())
  sb.to_string()
}

///|
/// Offset `k` of words sent, in them without what stood at `gone`.
fn said_at(k : Int, gone : Array[Int]) -> Int {
  k - gone.filter(fn(g) { g < k }).length()
}

///|
/// Offset `k` of words without what stood at `gone`, in them as sent.
fn sent_at(k : Int, gone : Array[Int]) -> Int {
  let mut at = k
  for g in gone {
    if g <= at {
      at += 1
    }
  }
  at
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
/// The part of a flying piece left visible by larger pieces it crosses while its source and destination wrap
/// differently. A longer piece keeps the space it covers, so a short fragment gives way instead of hiding a line.
fn flight_piece_room(
  pieces : Array[FlightPiece],
  k : Int,
  wx : Double,
  wy : Double,
  across : Double,
  up : Double,
) -> (Double, Double) {
  let p = pieces[k]
  let (ax, ay, aw, ah) = p.at
  let (fx, fy) = p.from
  let px = fx + (wx + ax - fx) * across
  let py = fy + (wy + ay - fy) * up
  let mut left = 0.0
  let mut right = aw
  for j in 0..<pieces.length() {
    if j == k { continue }
    let other = pieces[j]
    let (bx, by, bw, bh) = other.at
    if bw < aw || (bw == aw && j > k) { continue }
    let (sx, sy) = other.from
    let x = sx + (wx + bx - sx) * across
    let y = sy + (wy + by - sy) * up
    if x < px + aw && x + bw > px && y < py + ah && y + bh > py {
      if x <= px {
        left = dmax(left, x + bw - px)
      } else {
        right = dmin(right, x - px)
      }
    }
  }
  (dmin(dmax(left, 0.0), aw), dmin(dmax(right, 0.0), aw))
}

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
  let flying = flight_going(c, f)
  // (where they are on their way read where each piece is drawn, as the frame is laid out and painted, not as their
  // row is built)
  let across = fn() { if flying { flight_across_of(c, f) } else { 0.0 } }
  let up = fn() { if flying { flight_up_of(c, f) } else { 0.0 } }
  let runs = person_runs(f.text, f.runs, t.p.accent)
  for k, p in pieces {
    let (ax, ay, aw, ah) = p.at
    let cut = c.box(style=@ui.style(w=Fixed(aw), h=Fixed(ah), clip=true), fn() {
      let all = c.box(style=@ui.style(w=Fixed(w.w)), fn() {
        c.rich(runs, key="flight/piece/\{f.n}/\{k}", style=t.t.words, link_color=t.p.blue, words=true) |> ignore
      })
      c.look(all, @ui.look(dx=-ax, dy=-ay))
    })
    // The pieces can cross when the field and message wrap at different places. Give each only the room left by the
    // larger pieces, as rows give way to what moves over them; the actual flight stays on its original path.
    @motion.flying_placed(c, cut)
    c.cut_across_by(cut, fn() {
      match @motion.measured_rect(c, flight_words_key(f)) {
        Some((wx, wy, _, _)) => flight_piece_room(pieces, k, wx, wy, across(), up())
        None => (0.0, aw)
      }
    })
    // where the message's words are laid out this frame (the list gliding meanwhile), not a frame behind; less how far
    // off its place its bubble is drawn (flight_bubble: from the first line as typed, across and up)
    @motion.placed(c, cut, fn() {
      match @motion.measured_rect(c, flight_words_key(f)) {
        Some((wx, wy, _, _)) if bubble.val >= 0 => {
          let (across, up) = (across(), up())
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
fn field_lines_of(field : @ui.Field, words : String) -> (@ui.FieldLines?, Int) {
  match field.lines() {
    Some(l) => {
      let mut lead = 0
      while lead < l.text.length() &&
            (
              l.text.unsafe_get(lead).to_int() == 32 ||
              l.text.unsafe_get(lead).to_int() == 9 ||
              is_break(l.text.unsafe_get(lead).to_int())
            ) {
        lead = lead + 1
      }
      if lead + words.length() <= l.text.length() &&
        l.text.clamped_view(start=lead, end=lead + words.length()).to_owned() == words {
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
    if !flight_going(c, f) {
      c.look(i, @ui.look(alpha=0.0))
    }
    // (where it is on its way read as the frame is laid out, not as its row is built: fly_by)
    @motion.fly_by(c, i, fn() { (f.from_x - 14.0, f.from_y - 8.0, 1.0, flight_across_of(c, f), 1.0, 1.0) })
    return
  }
  if !flight_going(c, f) {
    // the moment it is placed: not seen while the words are still drawn as typed, over the field; in pieces, they are its
    // own from it on (its ground not come in yet)
    if flight_pieces(c, f) is None {
      c.look(i, @ui.look(alpha=0.0))
    }
    @motion.fly(c, i, f.from_x - bubble_in_x, f.from_y - bubble_in_y, px=0.0, py=0.0)
    return
  }
  // (where it is on its way read as the frame is laid out, not as its row is built: fly_by)
  @motion.fly_by(c, i, fn() {
    let p = flight_p(c, f)
    (f.from_x - bubble_in_x, f.from_y - bubble_in_y, 1.0, flight_across(p, f.desk), flight_up(p, f.desk), 1.0)
  })
}

///|
/// Whether the composer's hint is away: words sent are over it, or quotes (their cards as wide as it, the field coming
/// up under them as it comes down), not yet out of it.
pub fn flight_hint_away(c : @ui.Ctx, chat : String) -> Bool {
  match flight_of(chat) {
    // (files alone leave it where it is)
    Some(f) if f.text != "" || f.files.iter().any(fn(ff) { ff.key.has_prefix(quote_prefix) }) => !flight_out(c, f)
    _ => false
  }
}

///|
/// Whether words sent `f` are out of the field they were typed in: half their way up.
pub fn flight_out(c : @ui.Ctx, f : SendFlight) -> Bool {
  // (as they get there, not where they are each frame: way_reaches; their way told anew as it is timed: built again,
  // as what reads whether it is over is)
  if !f.placed {
    return false
  }
  ignore(f.way.over(c))
  way_reaches(c, f.way, fn(p) { flight_up(p, flies_desk(f)) >= 0.5 })
}

///|
/// The file of the flight that is file `key` (file_key), if one flies there.
pub fn flight_file_of(f : SendFlight, key : String) -> FlyingFile? {
  f.files.iter().find_first(fn(x) { x.key == key })
}

///|
/// A quote's words start with their composer's line breaks and change width with the card toward their message's.
/// The message's natural width is measured at the moment it is placed, while it is hidden, before the width starts following the way.
pub fn flight_quote_words(c : @ui.Ctx, f : SendFlight, key : String) -> (String, Double?) {
  match flight_file_of(f, key) {
    Some(ff) =>
      match ff.quote_words {
        Some((word_key, from)) => {
          if ff.quote_to is None && flight_going(c, f) {
            match c.words_shape_of(word_key) {
              Some(words) if words.pieces.length() == 1 => ff.quote_to = Some(words.pieces[0].w)
              _ => ()
            }
          }
          let width = ff.quote_to.map(fn(to) { from + (to - from) * flight_across_of(c, f) })
          (word_key, width)
        }
        None => ("", None)
      }
    None => ("", None)
  }
}

///|
/// A thing sent while it was coming into its container starts with the part and opacity that were visible. As it goes
/// to its message, its existing flight opens that cut and brings its opacity to the message's, on the same way.
fn flight_shown(c : @ui.Ctx, node : Int, shown : @ui.DrawnState?, from : (Double, Double, Double, Double), w : Double, h : Double, up : Double) -> Double {
  match shown {
    None => 1.0
    Some(s) => {
      let (x, y, fw, fh) = from
      if fw <= 0.0 || fh <= 0.0 { return s.alpha }
      let p = dclamp(up, 0.0, 1.0)
      let (l, t, r, b) = s.clip
      let left = dclamp((l - x) / fw, 0.0, 1.0) * (1.0 - p)
      let top = dclamp((t - y) / fh, 0.0, 1.0) * (1.0 - p)
      let right = 1.0 - (1.0 - dclamp((r - x) / fw, 0.0, 1.0)) * (1.0 - p)
      let bottom = 1.0 - (1.0 - dclamp((b - y) / fh, 0.0, 1.0)) * (1.0 - p)
      let soft = dmax(dmax(s.soft.0, s.soft.1), dmax(s.soft.2, s.soft.3)) * (1.0 - p)
      if left > 0.0 { c.cut_to_right(node, w * (1.0 - left), soft~) }
      if top > 0.0 { c.cut_to_bottom(node, h * (1.0 - top), soft~) }
      if right < 1.0 { c.cut_to_left(node, w * right, soft~) }
      if bottom < 1.0 { c.cut_to_top(node, h * bottom, soft~) }
      s.alpha + (1.0 - s.alpha) * p
    }
  }
}

///|
/// Each file sent (files): as its tile was, where it was, until the row is in the list; then a
/// picture from there to its place in the message (where the message's own box is laid out: flight_landing), its box
/// growing to its picture's there (a letterboxed one's share of it). Over the composer and the list, drawn only.
pub fn flight_files(c : @ui.Ctx, chat : String) -> Unit {
  // (those sent before the last and still on their way, then the last: each its own)
  for f in flights_on.get() {
    if f.chat == chat {
      flight_files_of(c, f)
    }
  }
  match flight_of(chat) {
    Some(f) => flight_files_of(c, f)
    None => ()
  }
}

///|
fn flight_files_of(c : @ui.Ctx, f : SendFlight) -> Unit {
  if f.files.is_empty() {
    return
  }
  let l = c.layer(fn() {
    for ff in f.files {
      let (fx, fy, fw, fh) = ff.from
      // (where it lands, once its message is laid out: a picture's from the moment it is placed, drawn at its tile all
      // that moment; a card's, the message's own, once it is on its way: flight_landing)
      let landing = if flight_going(c, f) || (f.placed && ff.picture is Some(_)) {
        @motion.measured_rect(c, flight_to_key(f, ff.key))
      } else {
        None
      }
      let to = flight_to_key(f, ff.key)
      let (sw, sh, top_crop) = landing_shares.get(to).unwrap_or((1.0, 1.0, false))
      match (landing, ff.picture, ff.paint) {
        (Some((_, _, bw, bh)), Some(_), Some(paint)) => {
          // (its size goes with them as it is built: its box's room, laid out)
          let up = flight_up_of(c, f)
          let (ew, eh) = (bw * sw, bh * sh)
          let w = fw + (ew - fw) * up
          let h = fh + (eh - fh) * up
          // (on no ground, its corner its tile's in the composer as it leaves, a file's in its message as it lands
          // (a quote's picture's, concentric with its card), in the one change of shape: sfpages composer.mbt,
          // message_files.mbt)
          let lands = if ff.key.has_prefix(quote_picture_prefix) {
            @sf.quote_picture_corner
          } else {
            @sf.message_file_corner
          }
          let corner = @sf.composer_inner() + (lands - @sf.composer_inner()) * up
          let pic = c.box(style=@ui.style(w=Fixed(w), h=Fixed(h), radius=@sf.radius_between(corner), clip=true), fn() {
            let fit : @ui.Fit = if top_crop { FitCoverAt(0.5 * (1.0 - up)) } else { FitCover }
            paint(w, h, fit, corner)
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
                let across = flight_across_of(c, f)
                let (px, py, pw, ph) = c.node_rect(pic)
                let alpha = flight_shown(c, pic, ff.shown, ff.from, pw, ph, up)
                @ui.look(alpha~, dx=fx + (ex - fx) * across - px, dy=fy + (ey - fy) * up - py)
              }
              None => @ui.look(alpha=0.0)
            }
          })
        }
        // a card on its way is the message's own, carried (flight_landing)
        (Some(_), None, _) => ()
        _ => {
          let tile = c.box(fn() { (ff.face)(c) })
          @motion.placed(c, tile, fn() {
            let (tx, ty, tw, th) = c.node_rect(tile)
            let alpha = flight_shown(c, tile, ff.shown, ff.from, tw, th, 0.0)
            @ui.look(alpha~, dx=fx - tx, dy=fy - ty)
          })
        }
      }
    }
  })
  // The quote cards also fly: draw their pictures later in that same stratum, over the cards' grounds.
  c.stratum(l, Flying)
  // drawn only: not the files, which are the message's
  c.draw_only(l)
  // What belongs only to a quote in the composer goes with its card, leaving from the frame it is sent. Draw it over
  // the card in its own layer: a layer drawn only is over the rest of that layer alone.
  // (gone: as it gets there, not where it is each frame, way_reaches; where it is, and where they are on their way,
  // read where each is drawn, as the frame is laid out)
  if f.files.iter().any(fn(ff) { ff.key.has_prefix(quote_prefix) }) && !way_reaches(c, f.gone, fn(g) { g >= 1.0 }) {
    let flying = flight_going(c, f)
    let reach = @sf.corner_remove_reach(@sf.composer_inner())
    c.layer(fn() {
      for ff in f.files {
        if !ff.key.has_prefix(quote_prefix) {
          continue
        }
        let (fx, fy, fw, _) = ff.from
        let to = flight_to_key(f, ff.key)
        match ff.leaving {
          Some(((lx, ly, lw, lh), face)) => {
            let part = c.box(style=@ui.style(w=Fixed(lw), h=Fixed(lh)), fn() { face(c) })
            c.stratum(part, Flying)
            c.draw_only(part)
            @motion.placed(c, part, fn() {
              let (gone, across, up) = (flight_gone(c, f), flight_across_of(c, f), flight_up_of(c, f))
              let (gx, gy) = match @motion.measured_rect(c, to) {
                Some((bx, by, _, _)) if flying => (fx + (bx - fx) * across, fy + (by - fy) * up)
                _ => (fx, fy)
              }
              let (px, py, pw, ph) = c.node_rect(part)
              let alpha = flight_shown(c, part, ff.shown, (lx, ly, lw, lh), pw, ph, up)
              @ui.look(alpha=alpha * (1.0 - gone), dx=gx + lx - fx - px, dy=gy + ly - fy - py)
            })
          }
          None => ()
        }
        let x = @sf.corner_remove_face(c)
        c.stratum(x, Flying)
        c.draw_only(x)
        @motion.placed(c, x, fn() {
          let (gone, across, up) = (flight_gone(c, f), flight_across_of(c, f), flight_up_of(c, f))
          // (on the card's ground as this frame draws it: flight_quote_landing's)
          let (gx, gy, gw) = match @motion.measured_rect(c, to) {
            Some((bx, by, bw, _)) if flying => (fx + (bx - fx) * across, fy + (by - fy) * up, fw + (bw - fw) * across)
            _ => (fx, fy, fw)
          }
          let (xx, xy, xw, xh) = c.node_rect(x)
          let alpha = flight_shown(c, x, ff.shown, (fx + fw + reach - xw, fy - reach, xw, xh), xw, xh, up)
          @ui.look(
            alpha=alpha * (1.0 - gone),
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
/// while a file flies there: where it is, kept for the picture flying to it (drawn there by
/// flight_files, not here), and the `share` of the box its picture takes (a letterboxed one's, centred); a card,
/// carried from its tile on the words' way, grown from the tile's size to its own.
pub fn flight_landing(
  c : @ui.Ctx,
  f : SendFlight,
  i : Int,
  key : String,
  share? : (Double, Double) = (1.0, 1.0),
  top_crop? : Bool = false,
  paint? : ((Double, Double, @ui.Fit, Double) -> Unit)? = None,
) -> Unit {
  let ff = match flight_file_of(f, key) {
    Some(ff) => ff
    None => return
  }
  // A picture is drawn on its flight by the same painter as the message's, including its loading state.
  if ff.picture is Some(_) {
    ff.paint = paint
    if paint is None { return }
  }
  @motion.measure(c, i, flight_to_key(f, key))
  landing_shares[flight_to_key(f, key)] = (share.0, share.1, top_crop)
  let (fx, fy, fw, fh) = ff.from
  if ff.picture is Some(_) || !flight_going(c, f) {
    // the moment it is placed (and a picture all the way): not seen here
    c.look(i, @ui.look(alpha=0.0))
    return
  }
  // from the tile's size: by the larger of its two shares of its own (Compose's crop to the box)
  let s0 = match @motion.measured_size(c, flight_to_key(f, key)) {
    Some((ew, eh)) if ew > 0.0 && eh > 0.0 => dmax(fw / ew, fh / eh)
    _ => 1.0
  }
  // (in a new chat's list coming up with the words, drawn below its place by as much: from its tile all the same,
  // straight, as its words go: flight_carry_shift)
  let rise = flight_carry_rise(c, f)
  // (where they are on their way read as the frame is laid out, not as its row is built)
  @motion.fly_by(c, i, fn() {
    let up = flight_up_of(c, f)
    (fx, fy - rise, s0, flight_across_of(c, f), up, up)
  })
  // (read where it is as it is placed: its message's row kept as its nodes is put back elsewhere among the frame's as
  // what is built before it makes more nodes or fewer, this not made again)
  let held = c.node_held(i)
  @motion.placed(c, i, fn() {
    match held.at() {
      Some(i) => {
        let (_, _, w, h) = c.node_rect(i)
        @ui.look(alpha=flight_shown(c, i, ff.shown, ff.from, w, h, flight_up_of(c, f)))
      }
      None => @ui.still_look
    }
  })
}

///|
/// A quote's card in the message words were sent to (node `card`, its own box: quote_key `key`), while its card in the
/// composer flies there: what it holds from where it was there (its words `shift` further in there than here:
/// @sf.quote_sent_shift) to where it is laid out, across and up on the words' way, over everything; its ground from
/// the composer's card to its own, its edges across and its top and bottom up, its colour from that card's as it goes
/// up (as seen over anything: the composer's may be see-through). Where each is this frame laid out (@motion.placed), not a frame behind; not seen at the moment it is placed (drawn
/// where it was by flight_files).
pub fn flight_quote_landing(c : @ui.Ctx, f : SendFlight, card : Int, key : String, shift : (Double, Double)) -> Unit {
  let ff = match flight_file_of(f, key) {
    Some(ff) => ff
    None => return
  }
  @motion.measure(c, card, flight_to_key(f, key))
  if !flight_going(c, f) {
    c.look(card, @ui.look(alpha=0.0))
    return
  }
  let (fx, fw) = (ff.from.0, ff.from.2)
  let fh = ff.from.3
  let (sx, sy) = shift
  let own = c.node_bg(card)
  let from = if ff.ground != 0L { ff.ground } else { own }
  // (in a new chat's list coming up with the words, drawn below its place by as much: from its card all the same,
  // straight: flight_carry_shift)
  let fy = ff.from.1 - flight_carry_rise(c, f)
  @motion.flying_placed(c, card)
  // (read where it is as it is placed, as flight_landing's; where they are on their way read then too, as the frame is
  // laid out, not as its row is built)
  let held = c.node_held(card)
  @motion.placed(c, card, fn() {
    guard held.at() is Some(card) else { return @ui.still_look }
    let across = flight_across_of(c, f)
    let up = flight_up_of(c, f)
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
    @ui.look(alpha=flight_shown(c, card, ff.shown, ff.from, w, h, up), dx~, dy~)
  })
}
