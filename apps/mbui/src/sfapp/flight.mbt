// Words sent flying (ChatHost.kt Flight, FlightLayer; web madeChat.ts): what is sent stays where it was typed until
// its row is in the list (the first of this device's own not there when it was sent: an outbox entry, or the message
// it became), then its bubble goes from the words' place in the field to its own, over the composer: across first and
// up a little after, so the words rise on a curve (Ease.Flight over 80% of its 600 ms, up 12% late), its ground coming
// in round them from a quarter of the way, its time and the rest of its row coming in as they settle (Ease.Arrive from
// 24%). Meanwhile the rows above, put up by the new one at once, go there with the words (sendReflow: on the same
// way up); the composer's room stays as tall as when they were sent until they are a quarter of the way, and its
// hint comes back once they are out of it (200 ms, Ease.Arrive). A row that never comes (2 s): the composer as it
// was. With motion reduced (or in screenshots) none of it: the row is where it is.
//
// The files sent with them go from their tiles in the composer (ChatHost.kt FlyingFile, landingFile, files): drawn as
// their tiles were where they were until the row is in the list, then each to its place in the message, across and up
// as the words go: a picture's box growing from the tile's to its own, the picture cropped to it as it is (opening out
// from the tile's square crop), its corner from the composer's (18) to its own (10); any other file's card carried
// there, from the tile's size to its own. Sent with no words, the row comes in where it is, its files flying into it,
// and the composer's hint stays.

///|
priv struct SendFlight {
  /// the chat it was sent in (its draft's key), its words, and where they were: their first line's top left, the
  /// field's room
  chat : String
  text : String
  from_x : Double
  from_y : Double
  field_x : Double
  field_y : Double
  field_w : Double
  field_h : Double
  /// the outbox's entries (and the rows they became) when it was sent: not where it goes
  before : Map[String, Bool]
  /// the composer's room when sent (held a quarter of the way)
  room : Double
  /// the files sent with them, from their tiles
  files : Array[FlyingFile]
  /// its row's key once it is in the list, whether it is and from which frame; how far it has come (0 … 1, linear,
  /// told to go as its row is first laid out: as Compose's animation, it sets off the frame after)
  mut key : String
  mut placed : Bool
  mut placed_frame : Int
  way : @motion.Anim
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
/// What is sent from the composer of chat `chat` takes off from the field (before it is emptied). The composer's room
/// is held as tall as it was until the words let go of it (composer_hold), said now: at most their wait for the row.
fn flight_start(
  c : @ui.Ctx,
  chat : String,
  words : String,
  v : ChatView,
  room : Double,
  files : Array[FlyingFile],
) -> Unit {
  send_flight.val = None
  if @ui.reduced_motion() || (words == "" && files.is_empty()) {
    return
  }
  match c.field_words(field_key) {
    Some(((x, y), (rx, ry, w, h))) => {
      let before : Map[String, Bool] = {}
      for o in v.outbox {
        before["o:" + o.id] = true
      }
      for m in v.messages {
        if m.outgoing != "" {
          before["o:" + m.outgoing] = true
        }
        before["m:" + m.ts] = true
      }
      // the field's words as laid out (scrolled to its last lines when there were more than it holds), its room
      send_flight.val = Some({
        chat,
        text: words,
        from_x: x,
        from_y: y,
        field_x: rx,
        field_y: ry,
        field_w: w,
        field_h: h,
        before,
        room,
        files,
        key: "",
        placed: false,
        placed_frame: -1,
        way: @motion.Anim::new(0.0),
      })
      composer_hold(chat, room, flight_wait_ms)
    }
    None => ()
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
/// Its ways across and up (ChatHost.kt Flight.across, up), eased.
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
      let waited = @kit.after(c, "flight/wait", !f.placed, flight_wait_ms)
      if (!f.placed && waited) || (f.placed && !f.way.moving()) {
        send_flight.val = None
      }
    }
    // (none: the wait starts again from nothing for the next words)
    None => @kit.after(c, "flight/wait", false, flight_wait_ms) |> ignore
  }
}

///|
/// Whether row `key` (new to the list or not) is where the words go: the first of this device's own not there
/// when they were sent.
fn flight_takes(chat : String, key : String, mine : Bool) -> Bool {
  match flight_of(chat) {
    Some(f) => {
      if f.key == "" && mine && !f.before.contains(key) {
        f.key = key
      }
      f.key == key
    }
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
    f.way.animate(1.0, @motion.tween(flight_ms, ease=Linear))
    composer_hold(f.chat, f.room, flight_settle * flight_ms)
  }
}

///|
/// The words as they were typed, over the field, until their row is in the list.
fn flight_waiting(c : @ui.Ctx, chat : String) -> Unit {
  let t = @sf.theme()
  match flight_of(chat) {
    Some(f) if !f.placed => {
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
    Some(f) if f.text != "" => !f.placed || flight_up(flight_p(c, f)) < 0.5
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
          let p = flight_p(c, f)
          let across = flight_across(p)
          let up = flight_up(p)
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
  let p = flight_p(c, f)
  let up = flight_up(p)
  // from the tile's size: by the larger of its two shares of its own (Compose's crop to the box)
  let s0 = match @motion.measured_rect(c, "flight/to/" + path) {
    Some((_, _, ew, eh)) if ew > 0.0 && eh > 0.0 => dmax(fw / ew, fh / eh)
    _ => 1.0
  }
  @motion.fly(c, i, fx, fy, scale=s0, px=flight_across(p), py=up, ps=up)
}
