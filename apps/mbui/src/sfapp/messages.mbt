// What the phone's chat keeps of its messages (the flight of words sent, notices opened). The messages themselves are
// drawn as their chat draws them, by sfpages' rows (message.mbt, message_files.mbt); what a post asks, under it, by
// sfpages' decision.mbt.
///|
/// Times in messages say how long ago; a tap on one says when, in all of them, until tapped again.

///|
/// The flight of words sent whose row is being built (flight.mbt), for its bubble and what is under it.
let flying : Ref[SendFlight?] = { val: None }

///|
/// System notices opened (all their words, and their time), by message.
let opened_notices : Map[String, Bool] = Map([])

///|
/// The press an image of a message was last quoted by (file_item): a passage of its message is not picked by it too.
let image_quoted_at : Ref[Int] = { val: -1 }
