// Words sent flying (ChatHost.kt Flight, FlightLayer; web madeChat.ts): what is sent is in the list the frame it is
// sent, waiting for nothing (chat.mbt LocalSent: the core's row goes on from it once it comes), the words drawn where
// they were typed until its row is laid out; then its bubble goes from the words' place in the field to its own, over
// the composer: across first and up a little after, so the words rise on a curve (Ease.Flight over 80% of its 600 ms, up 12% late), its ground coming
// in round them from a quarter of the way, its time and the rest of its row coming in as they settle (Ease.Arrive from
// 24%). Meanwhile the rows above, put up by the new one at once, go there with the words (sendReflow: on the same
// way up); the composer's room stays as tall as when they were sent until they are a quarter of the way, and its
// hint comes back once they are out of it (200 ms, Ease.Arrive). Their row never laid out (its page not shown, 2 s):
// the composer as it was. With motion reduced (or in screenshots) none of it: the row is where it is.
//
// The files sent with them go from their tiles in the composer (ChatHost.kt FlyingFile, landingFile, files): drawn as
// their tiles were where they were until the row is in the list, then each to its place in the message, across and up
// as the words go: a picture's box growing from the tile's to its own, the picture cropped to it as it is (opening out
// from the tile's square crop), its corner from the composer's (18) to its own (10); any other file's card carried
// there, from the tile's size to its own. Sent with no words, the row comes in where it is, its files flying into it,
// and the composer's hint stays.
//
// A new chat's first words are carried (ChatHost.kt Flight.carried, web madeChat.ts): drawn where they were typed from
// the frame they are sent, over the new chat's composer and then its chat's (newchat.mbt makes the chat, the page
// becomes it), until their row is laid out in the chat's list; then the list comes up out of the composer with them,
// across and up together on Ease.Arrive (480 ms, 90 after: the choices fade first), their bubble's ground and time
// coming in on the same way. The composer is not held for them. The list is not cut at the composer's top as Android's
// is (ChatHost.kt clipRect): their bubble, in it, is drawn over the composer only while nothing over it cuts what it
// draws (Ctx::put_over), and what else is in it then (its time) is all but clear there.

///|
priv struct SendFlight {
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
  /// the composer's room when sent (held a quarter of the way)
  room : Double
  /// the files sent with them, from their tiles
  files : Array[FlyingFile]
  /// its row's key (what was sent from here, then the core's row it became: chat.mbt row_keys), whether it is laid
  /// out and from which frame; how far it has come (0 … 1, linear,
  /// told to go as its row is first laid out: as Compose's animation, it sets off the frame after)
  mut key : String
  mut placed : Bool
  mut placed_frame : Int
  way : @motion.Anim
  /// a new chat's first words: the list comes up with them (flight_carry_start). Where what they go to is to start
  /// from (their bubble's corner, or the first file's tile without words); how far the list is drawn off its place in
  /// this build, and was in the one before (what was measured then was off by)
  carried : Bool
  from_top : Double
  mut shift : Double
  mut shift_was : Double
}

///|
/// A file sent with the words (ChatHost.kt FlyingFile): the station's path its message has it by, its tile in the
/// composer (x, y, w, h in the window), a picture's key ("" a card), and the tile as the composer drew it (what is
/// drawn where it was while the row is not in the list).
priv struct FlyingFile {
  path : String
  from : (Double, Double, Double, Double)
  picture : String
  face : () -> Unit
}

///|
let send_flight : Ref[SendFlight?] = { val: None }

///|
/// A tile's corner in the composer and a picture's in a message, which a flying picture's goes from and to.
let flight_tile_corner : Double = 18.0

///|
let flight_file_corner : Double = 10.0

///|
/// How long the words take to their place, the share of it they fly (the rest they settle), and from when they
/// settle (ChatHost.kt FLIGHT_MS, FLY, SETTLE).
pub let flight_ms : Double = 600.0

///|
/// How long the words wait over the field for their row; it not come by then, they go.
let flight_wait_ms : Double = 2000.0

///|
let flight_fly : Double = 0.8

///|
let flight_settle : Double = 0.24

///|
/// What is sent from the composer of chat `chat` takes off from the field (before it is emptied), to row `key` (in
/// the list from now: sent_local). The composer's room is held as tall as it was until the words let go of it
/// (composer_hold), said now: at most their wait for the row.
fn flight_start(
  c : @ui.Ctx,
  chat : String,
  turns : String,
  key : String,
  words : String,
  room : Double,
  files : Array[FlyingFile],
) -> Unit {
  send_flight.val = None
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match c.field_words(field_key) {
    Some(((x, y), (rx, ry, w, h))) => {
      // the field's words as laid out (scrolled to its last lines when there were more than it holds), its room
      send_flight.val = Some({
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
        files,
        key,
        placed: false,
        placed_frame: -1,
        way: @motion.Anim::new(0.0),
        carried: false,
        from_top: y - 8.0,
        shift: 0.0,
        shift_was: 0.0,
      })
      composer_hold(chat, room, flight_wait_ms)
      // a turn among what changes the list's height, till they have landed: what comes after them waits for it, they
      // wait for nothing (turns.mbt)
      turns_of(turns).send(c)
    }
    None => ()
  }
}

///|
/// A new chat's first words (and files) take off from its field (before it is emptied), carried (ChatHost.kt sending,
/// carried): drawn where they were from now, while the chat is made; nothing held of the composer. `chat`: the new
/// chat's draft's key, till flight_carry_into.
fn flight_carry_start(c : @ui.Ctx, chat : String, words : String, files : Array[FlyingFile]) -> Unit {
  send_flight.val = None
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match c.field_words(field_key) {
    Some(((x, y), (rx, ry, w, h))) => {
      // without words, the list comes up from where the first file was (ChatHost.kt landingFile: rise)
      let from_top = if words != "" {
        y - 8.0
      } else {
        files[0].from.1
      }
      send_flight.val = Some({
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
        files,
        key: "",
        placed: false,
        placed_frame: -1,
        way: @motion.Anim::new(0.0),
        carried: true,
        from_top,
        shift: 0.0,
        shift_was: 0.0,
      })
    }
    None => ()
  }
}

///|
/// The new chat's first words, carried from its draft `from`, go on to the chat it became: its draft `chat`, its list's
/// turns `turns`, row `key` (in its list from now: sent_local). What is asked in its list after them waits for them.
fn flight_carry_into(from : String, chat : String, turns : String, key : String) -> Unit {
  match flight_of(from) {
    Some(f) if f.carried => {
      f.chat = chat
      f.turns = turns
      f.key = key
      turns_of(turns).send(@ui.current())
    }
    _ => ()
  }
}

///|
/// A new chat's first words, and its files, where they were, while its chat is made (over the new chat's page: till
/// the page is the chat, which draws them then).
fn flight_carry_waiting(c : @ui.Ctx) -> Unit {
  match send_flight.val {
    Some(f) if f.carried => {
      flight_waiting(c, f.chat)
      flight_files(c, f.chat)
    }
    _ => ()
  }
}

///|
/// The new chat's first words not sent (the chat not made, or the message refused): they leave, back in the field.
fn flight_carry_gone(from : String) -> Unit {
  match flight_of(from) {
    Some(f) if f.carried => send_flight.val = None
    _ => ()
  }
}

///|
/// How far the list of chat `chat` is drawn below its place while a new chat's first words carry it up out of the
/// composer (ChatHost.kt Flight.shift): from where they were typed to where their row has them, less as they go; None
/// the build their row is first laid out (where it is not known yet: the list is not drawn then).
fn flight_carry_shift(c : @ui.Ctx, chat : String) -> Double? {
  match flight_of(chat) {
    Some(f) if f.carried && f.placed => {
      // (where its row was measured the build before, off its place by what the list was drawn off then; nothing of
      // it measured after all, where it is)
      let shift = if c.frame_number() <= f.placed_frame {
        None
      } else {
        match @motion.measured_rect(c, flight_carry_anchor(f)) {
          Some((_, y, _, _)) => Some((f.from_top - (y - f.shift)) * (1.0 - flight_carry_e(f)))
          None => Some(0.0)
        }
      }
      f.shift_was = f.shift
      f.shift = shift.unwrap_or(0.0)
      shift
    }
    _ => Some(0.0)
  }
}

///|
/// What a new chat's list comes up behind, as measured each build: their bubble (flight_bubble), or without words the
/// first file's place (flight_landing).
fn flight_carry_anchor(f : SendFlight) -> String {
  if f.text != "" {
    "flight/carry"
  } else {
    "flight/to/" + f.files[0].path
  }
}

///|
/// How far a new chat's first words have come (0 … 1, Ease.Arrive): across, up, their ground and time all at once.
fn flight_carry_e(f : SendFlight) -> Double {
  @motion.Arrive.at(f.way.get())
}

///|
/// The new chat's first words carried, while they wait for their row and go (a new chat's draft `chat`).
fn flight_carried(chat : String) -> Bool {
  match flight_of(chat) {
    Some(f) => f.carried
    None => false
  }
}

///|
/// The flight of chat `chat`'s words, while there is one.
fn flight_of(chat : String) -> SendFlight? {
  match send_flight.val {
    Some(f) if f.chat == chat => Some(f)
    _ => None
  }
}

///|
/// How far it has come (0 … 1, linear), from the frame after its row was first laid out.
fn flight_p(c : @ui.Ctx, f : SendFlight) -> Double {
  ignore(c)
  f.way.get()
}

///|
/// Its ways across and up (ChatHost.kt Flight.across, up), eased; a new chat's both on Ease.Arrive (flight_carry_e).
fn flight_across_of(c : @ui.Ctx, f : SendFlight) -> Double {
  if f.carried {
    flight_carry_e(f)
  } else {
    flight_across(flight_p(c, f))
  }
}

///|
fn flight_up_of(c : @ui.Ctx, f : SendFlight) -> Double {
  if f.carried {
    flight_carry_e(f)
  } else {
    flight_up(flight_p(c, f))
  }
}

///|
/// How settled it is (its time and the rest of its row), and how much of its bubble's ground shows; a new chat's coming
/// in on its way.
fn flight_settled_of(c : @ui.Ctx, f : SendFlight) -> Double {
  if f.carried {
    flight_carry_e(f)
  } else {
    flight_settled(flight_p(c, f))
  }
}

///|
fn flight_ground_of(c : @ui.Ctx, f : SendFlight) -> Double {
  if f.carried {
    flight_carry_e(f)
  } else {
    flight_ground(flight_p(c, f))
  }
}

///|
fn flight_across(p : Double) -> Double {
  @motion.Flight.at(dmin(dmin(p / flight_fly, 1.0) / 0.88, 1.0))
}

///|
fn flight_up(p : Double) -> Double {
  @motion.Flight.at(dmax((dmin(p / flight_fly, 1.0) - 0.12) / 0.88, 0.0))
}

///|
/// How settled it is (its time and the rest of its row coming in), and how much of its bubble's ground shows.
fn flight_settled(p : Double) -> Double {
  @motion.Arrive.at(dclamp((p - flight_settle) / (1.0 - flight_settle), 0.0, 1.0))
}

///|
fn flight_ground(p : Double) -> Double {
  dclamp((p - flight_settle) / (flight_fly - flight_settle), 0.0, 1.0)
}

///|
/// Each frame, before the chat's list is built: a flight landed, or whose row never came (its wait out: a frame then),
/// is over. On its way it moves by itself (its `way`, told as it set off).
fn flight_frame(c : @ui.Ctx, chat : String) -> Unit {
  match flight_of(chat) {
    Some(f) => {
      let turns = turns_of(f.turns)
      let waited = @kit.after(c, "flight/wait", !f.placed, flight_wait_ms)
      let landed = f.placed && !f.way.moving()
      if (!f.placed && waited) || landed {
        send_flight.val = None
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
fn flight_takes(chat : String, key : String) -> Bool {
  match flight_of(chat) {
    Some(f) => f.key == key
    None => false
  }
}

///|
/// The row the words go to is in the list: they go from the next frame on, all of their way said now (and the
/// composer's room let go a quarter of the way).
fn flight_placed(c : @ui.Ctx, f : SendFlight) -> Unit {
  if !f.placed {
    f.placed = true
    // the message sent is in the list, its row by its key (its outbox entry's id, or the message's): what a run waits
    // for (`said`), not the words' way there
    c.say("sent row in the list \{f.key}")
    f.placed_frame = c.frame_number()
    if f.carried {
      // a new chat's: once its choices have faded (web: 90 ms after what leaves has begun to)
      f.way.animate(1.0, @motion.tween(flight_carry_ms, ease=Linear, delay=flight_carry_after_ms))
    } else {
      f.way.animate(1.0, @motion.tween(flight_ms, ease=Linear))
      composer_hold(f.chat, f.room, flight_settle * flight_ms)
    }
  }
}

///|
/// How long a new chat's first words take to their place, from how long after their row is laid out (ChatHost.kt
/// ARRIVE_MS, its delay; web madeChat.ts).
let flight_carry_ms : Double = 480.0

///|
let flight_carry_after_ms : Double = 90.0

///|
/// The words as they were typed, over the field, until their row is in the list (and the build it is first laid out
/// in, where they go from: flight_bubble does not draw them then).
fn flight_waiting(c : @ui.Ctx, chat : String) -> Unit {
  let t = @sf.theme()
  match flight_of(chat) {
    Some(f) if !f.placed || f.placed_frame == c.frame_number() => {
      let l = c.layer(fn() {
        c.box(
          w=Px(f.field_w),
          h=Px(f.field_h),
          tx=f.field_x,
          ty=f.field_y,
          clip=true,
          fn() {
            c.box(style=@sf.full_width, tx=f.from_x - f.field_x, ty=f.from_y - f.field_y, fn() {
              // as the field had them: in the face chosen for what people write (ChatHost.kt SendTextFaced)
              c.rich([@ui.span(f.text)], key="flight/words", size=send_size, color=t.p.text, line=send_line, trim=true, w=Fill(1.0), words=true)
              |> ignore
            })
            |> ignore
          },
        )
        |> ignore
      })
      // drawn only (ChatHost.kt FlightLayer draws it): not the message, which is not in the list yet
      c.draw_only(l)
    }
    _ => ()
  }
}

///|
/// The bubble of the row the words go to (node `i`, its words `pad` in from its corner): flown from the field to
/// where it is, over the composer; its ground coming in.
fn flight_bubble(c : @ui.Ctx, f : SendFlight, i : Int) -> Unit {
  if f.carried {
    // up with the list (flight_carry_shift), across on its own, over the composer
    @motion.measure(c, i, flight_carry_anchor(f))
    if !f.placed || f.placed_frame == c.frame_number() {
      c.look(i, @ui.look(alpha=0.0))
    }
    @motion.fly(c, i, f.from_x - 14.0, f.from_y - 8.0, px=flight_carry_e(f), py=1.0)
    return
  }
  if !f.placed || f.placed_frame == c.frame_number() {
    // its first frame: not seen (the words are still drawn as typed, over the field)
    c.look(i, @ui.look(alpha=0.0))
    @motion.fly(c, i, f.from_x - 14.0, f.from_y - 8.0, px=0.0, py=0.0)
    return
  }
  let p = flight_p(c, f)
  @motion.fly(c, i, f.from_x - 14.0, f.from_y - 8.0, px=flight_across(p), py=flight_up(p))
}

///|
/// Whether the composer's hint is away: words sent are over it, not yet out of it.
fn flight_hint_away(c : @ui.Ctx, chat : String) -> Bool {
  match flight_of(chat) {
    // (only words pass over it: files alone leave it where it is)
    Some(f) if f.text != "" => !f.placed || flight_up_of(c, f) < 0.5
    _ => false
  }
}

///|
/// The file of the flight with `path`, if one flies there.
fn flight_file_of(f : SendFlight, path : String) -> FlyingFile? {
  f.files.iter().find_first(fn(x) { x.path == path })
}

///|
/// Each file sent (ChatHost.kt FlightLayer, files): as its tile was, where it was, until the row is in the list; then a
/// picture from there to its place in the message (where the message's own box is laid out: flight_landing), its box
/// growing to its own and its corner to the message's. Over the composer and the list, drawn only.
fn flight_files(c : @ui.Ctx, chat : String) -> Unit {
  let f = match flight_of(chat) {
    Some(f) if f.files.length() > 0 => f
    _ => return
  }
  let l = c.layer(fn() {
    for ff in f.files {
      let (fx, fy, fw, fh) = ff.from
      let landing = if f.placed && f.placed_frame != c.frame_number() {
        @motion.measured_rect(c, "flight/to/" + ff.path)
      } else {
        None
      }
      match landing {
        Some((ex, ey, ew, eh)) if ff.picture != "" => {
          let across = flight_across_of(c, f)
          let up = flight_up_of(c, f)
          // (a new chat's: where its list is drawn now, not where it was measured)
          let ey = ey + f.shift - f.shift_was
          let w = fw + (ew - fw) * up
          let h = fh + (eh - fh) * up
          c.box(
            style=flying_picture,
            w=Px(w),
            h=Px(h),
            tx=fx + (ex - fx) * across,
            ty=fy + (ey - fy) * up,
            radius=flight_tile_corner + (flight_file_corner - flight_tile_corner) * up,
            fn() { c.image(ff.picture, w=Px(w), h=Px(h), fit=FitCover, bg=0L) |> ignore },
          )
          |> ignore
        }
        // a card on its way is the message's own, carried (flight_landing)
        Some(_) => ()
        None => c.box(tx=fx, ty=fy, fn() { (ff.face)() }) |> ignore
      }
    }
  })
  // drawn only (ChatHost.kt FlightLayer draws them): not the files, which are the message's
  c.draw_only(l)
}

///|
/// A flying picture's box: its ground the chip's, what it holds cut to its corner.
// kept across runs: a value (no field of it changes)
let flying_picture : @ui.Style = @ui.style(bg=Neutral, clip=true)

///|
/// A file of the message words were sent to (node `i`, the box it is laid out in), while a file flies there
/// (ChatHost.kt landingFile): where it is, kept for the picture flying to it (drawn there by flight_files, not here);
/// a card, carried from its tile on the words' way, grown from the tile's size to its own.
fn flight_landing(c : @ui.Ctx, f : SendFlight, i : Int, path : String) -> Unit {
  let ff = match flight_file_of(f, path) {
    Some(ff) => ff
    None => return
  }
  @motion.measure(c, i, "flight/to/" + path)
  let (fx, fy, fw, fh) = ff.from
  if ff.picture != "" || !f.placed || f.placed_frame == c.frame_number() {
    // its first frame (and a picture all the way): not seen here
    c.look(i, @ui.look(alpha=0.0))
    return
  }
  let up = flight_up_of(c, f)
  // from the tile's size: by the larger of its two shares of its own (Compose's crop to the box)
  let s0 = match @motion.measured_rect(c, "flight/to/" + path) {
    Some((_, _, ew, eh)) if ew > 0.0 && eh > 0.0 => dmax(fw / ew, fh / eh)
    _ => 1.0
  }
  @motion.fly(c, i, fx, fy, scale=s0, px=flight_across_of(c, f), py=up, ps=up)
}
