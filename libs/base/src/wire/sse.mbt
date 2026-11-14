// A stream of events as text (text/event-stream), read as its chunks come: blocks ended by a blank line, of lines
// `event: <name>`, `id: <id>`, `data: <text>`. As the core's reader of it reads (client/core-ts/src/sse.ts `SseParser`):
// an event is its name ("message" where none is said), its data (its `data:` lines, one a line) and its id where it
// has one; a block with an id and no data is an id alone (its name and data ""). CRs are dropped.

///|
#derive(Eq)
pub(all) struct Event {
  name : String
  data : String
  id : String?
}

///|
pub struct Sse {
  /// What came and is no whole block yet.
  priv held : Array[Byte]
  /// Up to where `held` was looked through for a blank line.
  priv mut looked : Int
}

///|
pub fn Sse::new() -> Sse {
  { held: [], looked: 0 }
}

///|
/// The events `chunk` ends, in order.
pub fn Sse::feed(self : Sse, chunk : Bytes) -> Array[Event] {
  for b in chunk {
    if b != b'\r' {
      self.held.push(b)
    }
  }
  let events = []
  let mut start = 0
  let mut i = self.looked
  while i + 1 < self.held.length() {
    if self.held[i] == b'\n' && self.held[i + 1] == b'\n' {
      // (a block ends at a newline, so it never splits a UTF-8 sequence)
      let from = start
      let block = @utf8.decode_lossy(Bytes::makei(i - from, j => self.held[from + j]))
      start = i + 2
      i = start
      if event_of(block) is Some(event) {
        events.push(event)
      }
    } else {
      i = i + 1
    }
  }
  if start > 0 {
    ignore(self.held.drain(0, start))
  }
  // (a newline at the very end may begin a blank line with the next chunk)
  self.looked = if self.held.length() > 0 { self.held.length() - 1 } else { 0 }
  events
}

///|
fn event_of(block : String) -> Event? {
  let mut name = "message"
  let mut id : String? = None
  let data : Array[String] = []
  for line in block.split("\n") {
    if line.strip_prefix("event:") is Some(rest) {
      name = rest.trim().to_owned()
    } else if line.strip_prefix("id:") is Some(rest) {
      id = Some(rest.trim().to_owned())
    } else if line.strip_prefix("data:") is Some(rest) {
      data.push(
        match rest.strip_prefix(" ") {
          Some(after) => after.to_owned()
          None => rest.to_owned()
        },
      )
    }
  }
  if data.length() > 0 {
    Some({ name, data: data.join("\n"), id })
  } else if id is Some(_) {
    Some({ name: "", data: "", id })
  } else {
    None
  }
}
