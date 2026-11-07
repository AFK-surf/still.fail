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
let flying : Ref[SendFlight?] = { val: None }

///|
/// System notices opened (all their words, and their time), by message.
let opened_notices : Map[String, Bool] = {}

///|
/// The press an image of a message was last quoted by (file_item): a passage of its message is not picked by it too.
let image_quoted_at : Ref[Int] = { val: -1 }

///|
/// What an activity shows, steadied (Chat.kt steady): another thing replaces the shown one once it has stayed 700 ms
/// (a passing 请求中 does not flicker by); the same thing's new words show at once. Per row: what shows (its key, its
/// words), what showed before it, and when it came (the frames' clock).
priv struct Steady {
  mut key : String
  mut words : String
  mut was : String
  mut at : Double
}

///|
let steadies : Map[String, Steady] = {}

///|
/// How far an activity's ring reaches round its avatar (Chat.kt: the messages' 18dp avatar, its ring 3dp round it).
let ring_room : Double = 3.0
