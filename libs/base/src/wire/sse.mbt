// A stream of events as text (text/event-stream), read as its chunks come: blocks ended by a blank line, of lines
// `event: <name>`, `id: <id>`, `data: <text>`. An event is its name ("message" where none is said), its data (its
// `data:` lines, one a line) and its id where it has one; a block with an id and no data is an id alone (its name and
// data ""). CRs are dropped (one only ever comes as CRLF here: data is JSON, which escapes it).
//
// The core in TypeScript reads its event streams by this too (client/core-ts/src/sse.ts, through this library built
// for JavaScript: build.sh, js/base.js), and this reads as that one read while it was TypeScript, to the byte: its
// tests are held there (client/core-ts/test/sse.test.ts) and here. What has come and is no whole block yet is kept
// as bytes, and only what came since is looked through for the blank line that ends one (a big event comes in many
// chunks: looking through all it holds at each was quadratic, and pushing it a byte at a time into an array, then
// cutting off what was left after each block, made a phone's core spend most of its time here with agents at work).
// The three things done to many bytes at once (a chunk put after what is kept, what is kept moved to the front, the
// next newline found) are the target's own (sse_js.mbt, sse_native.mbt): on js the engine's, since a loop a byte is
// what an engine that compiles nothing (Hermes, which the apps run the core in) is slowest at.

///|
#derive(Eq)
pub(all) struct Event {
  name : String
  data : String
  id : String?
}

///|
pub struct Sse {
  /// What came and is not read yet: `held` from `start` to `end`; up to `looked` looked through for a blank line.
  priv mut held : FixedArray[Byte]
  priv mut start : Int
  priv mut end : Int
  priv mut looked : Int
}

///|
pub fn Sse::new() -> Sse {
  { held: FixedArray::make(4096, b'\x00'), start: 0, end: 0, looked: 0 }
}

///|
/// The events `chunk` ends, in order. The chunk is not kept: what it says is copied.
pub fn Sse::feed(self : Sse, chunk : Bytes) -> Array[Event] {
  self.append(chunk)
  let events = []
  while self.blank() is Some(end) {
    // (a block ends at a newline, so it never splits a UTF-8 sequence; a byte order mark at a block's head is not
    // of its text, as JavaScript's TextDecoder, which read each block there, takes one off)
    let block = @utf8.decode_lossy(as_bytes(self.held)[self.start:end], ignore_bom=true)
    self.start = end + 2
    self.looked = self.start
    if event_of(block) is Some(event) {
      events.push(event)
    }
  }
  if self.start == self.end {
    self.start = 0
    self.end = 0
    self.looked = 0
  }
  events
}

///|
/// `held` as the bytes they are, not copied: read at once and let go of, before `held` is next written.
fn as_bytes(held : FixedArray[Byte]) -> Bytes = "%identity"

///|
/// `chunk` after what is kept, without its CRs.
fn Sse::append(self : Sse, chunk : Bytes) -> Unit {
  let kept = self.end - self.start
  let room = self.held.length()
  if self.end + chunk.length() > room {
    // (what is kept moved to the front, into room for the chunk)
    if kept + chunk.length() > room {
      let grown = if room * 2 > kept + chunk.length() { room * 2 } else { kept + chunk.length() }
      let to : FixedArray[Byte] = FixedArray::make(grown, b'\x00')
      moved(to, self.held, self.start, self.end)
      self.held = to
    } else {
      moved(self.held, self.held, self.start, self.end)
    }
    self.looked = self.looked - self.start
    self.start = 0
    self.end = kept
  }
  self.end = put(self.held, self.end, chunk)
}

///|
/// Where the first blank line (two newlines) of what is kept starts, None while there is none; what was looked
/// through is not looked through again.
fn Sse::blank(self : Sse) -> Int? {
  let from = if self.looked > self.start { self.looked } else { self.start }
  let mut i = newline(self.held, from, self.end)
  while i >= 0 && i + 1 < self.end {
    if self.held[i + 1] == b'\n' {
      return Some(i)
    }
    i = newline(self.held, i + 1, self.end)
  }
  // (a newline at the very end may begin one with the next chunk)
  self.looked = if i >= 0 { i } else { self.end }
  None
}

///|
/// `text` without what JavaScript's `trim` takes off its ends (ECMAScript's WhiteSpace and LineTerminator): a name
/// and an id are said so, as the core's reader in TypeScript said them. (Asked a character at a time, not by
/// `trim(chars=…)`, which looks through all of its characters for each one that is none of them.)
fn trimmed(text : StringView) -> StringView {
  let mut from = 0
  let mut to = text.length()
  while from < to && blank(text.at(from)) {
    from = from + 1
  }
  while to > from && blank(text.at(to - 1)) {
    to = to - 1
  }
  text.clamped_view(start=from, end=to)
}

///|
/// Whether a UTF-16 unit is white space or a line's end to JavaScript (none of them is beyond the basic plane).
fn blank(unit : UInt16) -> Bool {
  let c = unit.to_int()
  if c <= 0x20 {
    c == 0x20 || (c >= 0x09 && c <= 0x0D)
  } else if c < 0xA0 {
    false
  } else {
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF
  }
}

///|
fn event_of(block : String) -> Event? {
  let mut name = "message"
  let mut id : String? = None
  let data : Array[String] = []
  let mut rest : StringView = block
  while true {
    let (line, after) = match rest.find("\n") {
      Some(i) => (rest.clamped_view(end=i), Some(rest.clamped_view(start=i + 1)))
      None => (rest, None)
    }
    if line.has_prefix("data:") {
      let from = if line.length() > 5 && line.at(5) == ' ' { 6 } else { 5 }
      data.push(line.clamped_view(start=from).to_owned())
    } else if line.has_prefix("event:") {
      name = trimmed(line.clamped_view(start=6)).to_owned()
    } else if line.has_prefix("id:") {
      id = Some(trimmed(line.clamped_view(start=3)).to_owned())
    }
    match after {
      Some(more) => rest = more
      None => break
    }
  }
  if data.length() == 1 {
    Some({ name, data: data[0], id })
  } else if data.length() > 1 {
    Some({ name, data: data.join("\n"), id })
  } else if id is Some(_) {
    Some({ name: "", data: "", id })
  } else {
    None
  }
}
