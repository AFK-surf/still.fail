// What the phone's chat keeps of its messages (the flight of words sent, notices opened, an activity steadied) and the
// chat's colours. The messages themselves are drawn as their chat draws them, by sfpages' rows (message.mbt,
// message_files.mbt); what a post asks, under it, by sfpages' decision.mbt.
///|
/// What the rows need to know of the chat.
priv struct Here {
  station : String
  session : String
  view : ChatView
}

///|
/// The chat's own colours (ChatInk.kt): the wide screen's tokens over the phone's paper; `neutral` is its bubble.
priv struct Ink {
  text : Int64
  muted : Int64
  subtle : Int64
  neutral : Int64
  name : Int64
  card : Int64
  accent : Int64
  canvas : Int64
}

///|
fn ink() -> Ink {
  if @sf.theme().dark {
    {
      text: 0xE9E9EAFFL,
      muted: 0xA3A5A9FFL,
      subtle: 0x8C8F94FFL,
      neutral: 0x313237FFL,
      name: 0xFC9B6FFFL,
      card: 0x27282BFFL,
      accent: 0xF57E4DFFL,
      canvas: 0x1F2023FFL,
    }
  } else {
    {
      text: 0x24272BFFL,
      muted: 0x646970FFL,
      subtle: 0x73787DFFL,
      neutral: 0xE8E4DCFFL,
      name: 0xA23203FFL,
      card: 0xF6F6F7FFL,
      accent: 0xEF6A3CFFL,
      canvas: 0xFFFFFFFFL,
    }
  }
}

///|
/// Times in messages say how long ago; a tap on one says when, in all of them, until tapped again.

///|
/// The flight of words sent whose row is being built (flight.mbt), for its bubble and what is under it.
let flying : @signals.Signal[SendFlight?] = @signals.signal(None)

///|
/// System notices opened (all their words, and their time), by message.
let opened_notices : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// The press an image of a message was last quoted by (file_item): a passage of its message is not picked by it too.
let image_quoted_at : @signals.Signal[Int] = @signals.signal(-1, same=fn(a, b) { a == b })

///|
/// The kind of a file by its name (FileKinds.kt kindOf): image, video, or anything else.
fn kind_of(name : String) -> String {
  let lower = @sf.lower(name)
  let ext = match lower.rev_find(".") {
    Some(i) if i > 0 => lower.view(start_offset=i + 1).to_string()
    _ => ""
  }
  match ext {
    "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "avif" | "bmp" | "ico" => "image"
    "mp4" | "m4v" | "webm" | "mov" | "ogv" => "video"
    _ => ""
  }
}



///|
/// The session whose workspace keeps a file: as the core says it, else the chat's first agent's.
fn owner_of(here : Here, a : Attachment) -> String {
  if a.owner != "" {
    a.owner
  } else {
    match here.view.agents.get(0) {
      Some(ag) => ag.key
      None => here.session
    }
  }
}

///|
/// What an activity shows, steadied (Chat.kt steady): another thing replaces the shown one once it has stayed 700 ms
/// (a passing 请求中 does not flicker by); the same thing's new words show at once. Per row: what shows (its key, its
/// words), what showed before it, and when it came (the frames' clock).
priv struct Steady {
  key : @signals.Signal[String]
  words : @signals.Signal[String]
  was : @signals.Signal[String]
  at : @signals.Signal[Double]
}

///|
let steadies : @sf.LiveMap[String, Steady] = @sf.LiveMap::new()

///|
/// How far an activity's ring reaches round its avatar (Chat.kt: the messages' 18dp avatar, its ring 3dp round it).
let ring_room : Double = 3.0

///|
/// An agent's ring round its avatar (Chat.kt WorkRing): at work, eight arcs in the accent, the brightest a step further
/// round every 100 ms (Spokes.kt); waiting on work it started, a still, quiet whole ring.
fn work_ring(c : @ui.Ctx, waiting : Bool) -> Unit {
  let t = @sf.theme()
  if waiting {
    c.box(w=Px(24.0), h=Px(24.0), radius=12.0, border=1.5, border_color=t.p.line, fn() {  }) |> ignore
  } else {
    @sf.segments(c, 24.0, 1.5, ink().accent, t.p.bg) |> ignore
  }
}

///|
/// The chat a row is of.
fn ref_of(here : Here) -> ChatRef {
  { station: here.station, session: here.session, title: here.view.title, station_name: "" }
}
