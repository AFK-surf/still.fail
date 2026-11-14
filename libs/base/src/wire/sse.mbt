// A stream of events as text (text/event-stream), read as its chunks come: blocks ended by a blank line, of lines
// `event: <name>`, `id: <id>`, `data: <text>`. An event is its name ("message" where none is said), its data (its
// `data:` lines, one a line) and its id where it has one; a block with an id and no data is an id alone (its name and
// data ""). CRs are dropped (one only ever comes as CRLF here: data is JSON, which escapes it).
//
// The core in TypeScript has a reader of its own (client/core-ts/src/sse.ts), and this one reads as that one does, to
// the byte: sse_made_test.mbt holds it to what that one gives. What has come and is no whole block yet is kept as
// bytes in one buffer, as there, and only what came since is looked through for the blank line that ends one (a big
// event comes in many chunks: looking through all it holds at each is quadratic); nothing is pushed a byte at a time
// or moved after each block.
// The three things done to many bytes at once (a chunk put after what is kept, what is kept moved to the front, the
// next newline found) are the target's own (sse_js.mbt, sse_native.mbt): on js the engine's, since a loop a byte is
// what an engine that compiles nothing (Hermes) is slowest at: 2.3 to 2.6 times slower there (measured, 2026-11-14).
// So is the keeping and joining of an event's `data:` lines (`Lines`), for an event of very many: on js MoonBit's
// `join` makes the string again at each line, and its `Array` as it grows is copied from its last place down into
// an array made empty, each their number squared under Hermes (40,000 lines of 26 bytes in one event took this
// reader 9.8 s so, and take it 64 ms; twice as many 41 s, and 129 ms: the command line of React Native 0.81.4's
// hermes, 2026-11-14). And nothing here makes a view of what is held for each line looked at: under Hermes a typed
// array's `subarray` costs by the size of what it is a view of (sse_js.mbt, `newline`).
//
// Where the two differ: this one keeps `most` bytes of a block at most (`Sse::new`), and fails at a longer one
// (`TooLong`); that one keeps what comes without a bound. What a peer sends is not this reader's to trust.

///|
#derive(Eq)
pub(all) struct Event {
  name : String
  data : String
  id : String?
}

///|
/// How long a block (an event's lines, up to its blank line, CRs not counted) may be unless its reader is made with
/// another bound: more than a device is told at once, and no more of a peer's bytes than it can hold beside its work.
pub let max_event : Int = 16 * 1024 * 1024

///|
/// A block of an event stream is longer than its reader keeps of one (`most` bytes): the stream is not read further.
pub(all) suberror TooLong {
  TooLong(most~ : Int)
}

///|
pub struct Sse {
  /// What came and is not read yet: `held` from `start` to `end`; up to `looked` looked through for a blank line.
  priv mut held : FixedArray[Byte]
  priv mut start : Int
  priv mut end : Int
  priv mut looked : Int
  /// How long a block may be, and whether one longer came: nothing is read after it.
  priv most : Int
  priv mut over : Bool
}

///|
/// A reader that keeps `most` bytes of one block at most (`max_event` unless said).
pub fn Sse::new(most? : Int = max_event) -> Sse {
  { held: FixedArray::make(4096, b'\x00'), start: 0, end: 0, looked: 0, most, over: false }
}

///|
/// The events `chunk` ends, in order. The chunk is not kept: what it says is copied.
///
/// A block longer than `most` bytes ends the reading, whatever the chunks it comes in: the events before it are
/// given as ever, and the feed that would give nothing more for it fails (`TooLong`: this one where no event came
/// before the block in it, the next otherwise), as does every feed after. What was held is let go of then: the
/// reader holds a block's `most` bytes and the chunk it is fed, never more.
pub fn Sse::feed(self : Sse, chunk : Bytes) -> Array[Event] raise TooLong {
  if self.over {
    raise TooLong(most=self.most)
  }
  self.append(chunk)
  let events = []
  while self.blank() is Some(end) {
    if end - self.start > self.most {
      self.over = true
      break
    }
    // (a block ends at a newline, so it never splits a UTF-8 sequence. A byte order mark at a block's head is not of
    // its text, and a sequence cut short is one U+FFFD: so MoonBit's own decoder reads natively and the WHATWG's on
    // js, Node's and a browser's, and the tests hold that. On js the decoder is the host's `TextDecoder`, made as
    // MoonBit's core is loaded: under one that ignores its options (written for an engine that has none) the mark
    // stays, so the line after it is no field, and such a sequence may be one U+FFFD a byte)
    let block = @utf8.decode_lossy(as_bytes(self.held)[self.start:end], ignore_bom=true)
    self.start = end + 2
    self.looked = self.start
    if event_of(block) is Some(event) {
      events.push(event)
    }
  }
  // (what is left has no blank line. Its last byte may be the first newline of one: so a byte past the bound is
  // waited for, and two are a block too long whatever comes. Asked of what is held less one, never of the bound and
  // one: the most an Int says is a bound too)
  if self.over || self.end - self.start - 1 > self.most {
    self.over = true
    self.held = FixedArray::make(0, b'\x00')
    self.start = 0
    self.end = 0
    self.looked = 0
    if events.is_empty() {
      raise TooLong(most=self.most)
    }
  } else if self.start == self.end {
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
      let to : FixedArray[Byte] = FixedArray::make(grown(room, kept + chunk.length()), b'\x00')
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
/// The room made for `need` bytes where `room` is too little: twice the room, or `need` where that is more. Twice a
/// room of 1 GiB or more is no Int (it wrapped, and the room then grew by what each chunk needed, all of it copied
/// each time): the most an Int says then.
fn grown(room : Int, need : Int) -> Int {
  let twice = if room >= 0x4000_0000 { 0x7FFF_FFFF } else { room * 2 }
  if twice > need { twice } else { need }
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
/// and an id are said so, as the core's reader in TypeScript says them. (Asked a character at a time, not by
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
  let data = lines()
  let mut rest : StringView = block
  while true {
    let (line, after) = match rest.find("\n") {
      Some(i) => (rest.clamped_view(end=i), Some(rest.clamped_view(start=i + 1)))
      None => (rest, None)
    }
    if line.has_prefix("data:") {
      let from = if line.length() > 5 && line.at(5) == ' ' { 6 } else { 5 }
      line_kept(data, line.clamped_view(start=from).to_owned())
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
  if lines_kept(data) > 0 {
    Some({ name, data: lines_joined(data), id })
  } else if id is Some(_) {
    Some({ name: "", data: "", id })
  } else {
    None
  }
}
