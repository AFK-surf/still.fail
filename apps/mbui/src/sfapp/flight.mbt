// Words sent flying (ChatHost.kt Flight, FlightLayer; web madeChat.ts): what is sent stays where it was typed until
// its row is in the list (the first of this device's own not there when it was sent: an outbox entry, or the message
// it became), then its bubble goes from the words' place in the field to its own, over the composer: across first and
// up a little after, so the words rise on a curve (Ease.Flight over 80% of its 600 ms, up 12% late), its ground coming
// in round them from a quarter of the way, its time and the rest of its row coming in as they settle (Ease.Arrive from
// 24%). Meanwhile the rows above, put up by the new one at once, go there with the words (sendReflow: on the same
// way up); the composer's room stays as tall as when they were sent until they are a quarter of the way, and its
// hint comes back once they are out of it (200 ms, Ease.Arrive). A row that never comes (2 s): the composer as it
// was. With motion reduced (or in screenshots) none of it: the row is where it is.

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
  sent_at : Double
  /// its row's key once it is in the list, when it first was (-1 not yet), and when it set off: the frame after (as
  /// Compose's animation starts the frame after it is asked)
  mut key : String
  mut placed_at : Double
  mut started_at : Double
}

///|
let send_flight : Ref[SendFlight?] = { val: None }

///|
/// How long the words take to their place, the share of it they fly (the rest they settle), and from when they
/// settle (ChatHost.kt FLIGHT_MS, FLY, SETTLE).
pub let flight_ms : Double = 600.0

///|
let flight_fly : Double = 0.8

///|
let flight_settle : Double = 0.24

///|
/// What is sent from the composer of chat `chat` takes off from the field (before it is emptied).
fn flight_start(c : @ui.Ctx, chat : String, words : String, v : ChatView, room : Double) -> Unit {
  send_flight.val = None
  if c.stable() || @ui.reduced_motion() || words == "" {
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
        sent_at: c.now(),
        key: "",
        placed_at: -1.0,
        started_at: -1.0,
      })
      c.request_frame()
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
  if f.started_at < 0.0 {
    return 0.0
  }
  dmin((c.now() - f.started_at) / flight_ms, 1.0)
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
/// Each frame, before the chat's list is built: a flight landed, or whose row never came, is over; one under way
/// asks for the next frame.
fn flight_frame(c : @ui.Ctx, chat : String) -> Unit {
  match flight_of(chat) {
    Some(f) => {
      if f.placed_at < 0.0 && c.now() - f.sent_at > 2000.0 {
        send_flight.val = None
        return
      }
      // (from the frame after it was placed, timed from its placing: it ends flight_ms after, whenever frames come)
      if f.placed_at >= 0.0 && f.started_at < 0.0 && c.now() > f.placed_at {
        f.started_at = f.placed_at
      }
      if f.started_at >= 0.0 && flight_p(c, f) >= 1.0 {
        send_flight.val = None
        return
      }
      c.request_frame()
    }
    None => ()
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
/// The row the words go to is in the list: they go from the next frame on.
fn flight_placed(c : @ui.Ctx, f : SendFlight) -> Unit {
  if f.placed_at < 0.0 {
    f.placed_at = c.now()
  }
}

///|
/// The words as they were typed, over the field, until their row is in the list.
fn flight_waiting(c : @ui.Ctx, chat : String) -> Unit {
  let t = @sf.theme()
  match flight_of(chat) {
    Some(f) if f.placed_at < 0.0 => {
      let l = c.layer(fn() {
        c.box(
          w=Px(f.field_w),
          h=Px(f.field_h),
          tx=f.field_x,
          ty=f.field_y,
          clip=true,
          fn() {
            c.box(w=Fill(1.0), tx=f.from_x - f.field_x, ty=f.from_y - f.field_y, fn() {
              c.text(f.text, size=send_size, color=t.p.text, line=send_line, w=Fill(1.0)) |> ignore
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
  if f.placed_at < 0.0 || f.placed_at == c.now() {
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
    Some(f) => f.placed_at < 0.0 || flight_up(flight_p(c, f)) < 0.5
    None => false
  }
}
