// Where each entry of a transcript is, and the entries between two of them, as read/transcripts.ts and read/tail.ts
// keep and read them (`markedOf`, `chainOf`, `entriesOf`; `TranscriptTail` as a reader's thread runs it: marking, its
// entries counted, none kept): what the pages of a history ask for (GET /sessions/:key/timeline) and where a session's
// live view goes on from (sessions/live.ts). A transcript's reading and its marks are kept as the worker keeps them, in
// memory and on disk (`<data>/transcript-marks/`, the same files in the same JSON), so either reader goes on from what
// the other wrote. Its bytes are read through the shell (`fs.bytes`, as hex; a put-away one's frames decompressed there).

///|
/// read/transcript.ts READING: what a line gives changes with it, so marks of another are read anew. The same number
/// as there: a change to what a line gives here or there raises both.
let reading : Int = 2

///|
/// read/transcripts.ts KEPT, KEPT_BYTES; read/tail.ts PIECE, MARK_EVERY, MARK_BYTES; read/transcripts.ts PIECE_READ.
let kept_most : Int = 16

///|
let kept_bytes : Int64 = 256L << 10

///|
let piece_size : Int64 = 4L << 20

///|
let mark_every : Int = 256

///|
let mark_bytes : Int64 = 1L << 20

///|
let piece_read : Int64 = 1L << 20

///|
/// read/tail.ts `Mark`: the end of a line, the index of the entry the next line's first is, what reading keeps there.
pub struct Mark {
  offset : Int64
  index : Int
  inner : Array[(String, Int)]
}

///|
/// read/tail.ts `TailState`: where a transcript's reading stands (`partial`: a line still being written).
pub struct TailState {
  path : String
  runtime : String?
  offset : Int64
  partial : Bytes
  count : Int
  inner : Array[(String, Int)]
  packed_stamp : String?
}

///|
/// read/transcripts.ts `Marked`.
pub struct Marked {
  state : TailState
  marks : Array[Mark]
}

///|
/// The transcripts whose reading is kept in memory, the most recently read last.
let kept : Map[String, Marked] = Map([])

///|
/// Where each transcript's reading kept on disk stands, as this reader last read or wrote it.
let on_disk : Map[String, Int64] = Map([])

///|
/// The transcript put away before there were segments whose history is being read, decompressed.
let unpacked : Ref[(String, String?, Bytes)?] = { val: None }

///|
fn shell(host : @host.Host, op : String, args : Json) -> Json raise {
  host.shell_sync(op, args)
}

///|
/// A path's size and mtimeMs as Node's statSync says them; None when it cannot be.
fn meta(host : @host.Host, path : String) -> (Int64, Double)? {
  match (try { Ok(shell(host, "fs.meta", { "path": Json::string(path) })) } catch { e => Err(e) }) {
    Ok({ "size": Number(size, ..), "mtime": Number(mtime, ..), .. }) => Some((size.to_int64(), mtime))
    _ => None
  }
}

///|
/// Bytes of a file (`length` of them from `from`, or what its zstd frames there hold); None when it does not open.
fn bytes_of(host : @host.Host, path : String, from? : Int64 = 0L, length? : Int64, zstd? : Bool = false, exact? : Bool = false) -> Bytes? raise {
  let args : Map[String, Json] = { "path": Json::string(path), "from": Json::number(from.to_double()) }
  if length is Some(n) {
    args["length"] = Json::number(n.to_double())
  }
  if zstd {
    args["zstd"] = true
  }
  if exact {
    args["exact"] = true
  }
  match shell(host, "fs.bytes", Json::object(args)) {
    String(hex) => Some(@hex.decode(hex))
    _ => None
  }
}

///|
fn joined(parts : Array[BytesView]) -> Bytes {
  let mut n = 0
  for p in parts {
    n += p.length()
  }
  let out = FixedArray::make(n, b'\x00')
  let mut at = 0
  for p in parts {
    for b in p {
      out[at] = b
      at += 1
    }
  }
  Bytes::from_fixedarray(out)
}

///|
fn last_newline(b : BytesView) -> Int {
  let mut i = b.length() - 1
  while i >= 0 {
    if b[i] == b'\n' {
      return i
    }
    i -= 1
  }
  -1
}

///|
fn le32(b : BytesView, at : Int) -> Int64 {
  b[at].to_int64() | (b[at + 1].to_int64() << 8) | (b[at + 2].to_int64() << 16) | (b[at + 3].to_int64() << 24)
}

///|
/// A transcript's line as its record (read/tail.ts `recordOf`): None when empty or not JSON; its \r before its \n goes.
fn record_of(line : String) -> @jsjson.JValue? {
  let text = if line.has_suffix("\r") { line.view(end_offset=line.length() - 1).to_owned() } else { line }
  if text == "" {
    return None
  }
  Some(@jsjson.parse(text)) catch {
    _ => None
  }
}

///|
/// read/packed.ts `Frame`.
priv struct Frame {
  at : Int64
  packed : Int64
  from : Int64
  size : Int64
}

///|
/// read/packed.ts SKIPPABLE, SEEKABLE, FOOTER.
let skippable : Int64 = 0x184d2a5eL

///|
let seekable : Int64 = 0x8f92eab1L

///|
let footer_size : Int64 = 9L

///|
fn bytes_at(host : @host.Host, path : String, at : Int64, n : Int64) -> Bytes raise {
  guard bytes_of(host, path, from=at, length=n, exact=true) is Some(b) else { fail("a put-away transcript ended early") }
  b
}

///|
/// read/packed.ts `framesOf`: a put-away transcript's frames from its table; None without one, or one that does not add
/// up to the file.
fn frames_of(host : @host.Host, path : String) -> Array[Frame]? raise {
  guard meta(host, path) is Some((size, _)) else { fail("a put-away transcript is not there") }
  if size < 8L + footer_size {
    return None
  }
  let footer = bytes_at(host, path, size - footer_size, footer_size)
  if le32(footer[:], 5) != seekable || (footer[4].to_int() & 0x7f) != 0 {
    return None
  }
  let entry = if (footer[4].to_int() & 0x80) != 0 { 12L } else { 8L }
  let length = 8L + le32(footer[:], 0) * entry + footer_size
  if length > size {
    return None
  }
  let table = bytes_at(host, path, size - length, length)
  if le32(table[:], 0) != skippable || le32(table[:], 4) != length - 8L {
    return None
  }
  let n = (length - 8L - footer_size) / entry
  let frames = []
  let mut at = 0L
  let mut from = 0L
  for i = 0L; i < n; i = i + 1L {
    let packed = le32(table[:], (8L + i * entry).to_int())
    let each = le32(table[:], (12L + i * entry).to_int())
    frames.push({ at, packed, from, size: each })
    at += packed
    from += each
  }
  if at == size - length { Some(frames) } else { None }
}

///|
/// read/packed.ts `writtenSize`.
fn written_size(host : @host.Host, path : String) -> Int64? raise {
  guard frames_of(host, path) is Some(frames) else { return None }
  let mut n = 0L
  for f in frames {
    n += f.size
  }
  Some(n)
}

///|
/// read/packed.ts `readSegments`: what a put-away transcript holds from `from` up to `end`, a segment at a time while
/// `take` wants more; false without a table.
fn read_segments(host : @host.Host, path : String, from : Int64, end : Int64, take : (BytesView) -> Bool raise) -> Bool raise {
  guard frames_of(host, path) is Some(frames) else { return false }
  let mut lo = 0
  let mut hi = frames.length() - 1
  while lo < hi {
    let mid = (lo + hi + 1) >> 1
    if frames[mid].from <= from {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  for i = lo; i < frames.length(); i = i + 1 {
    let f = frames[i]
    if f.from + f.size <= from {
      continue
    }
    if f.from >= end {
      break
    }
    let bytes = bytes_of(host, path, from=f.at, length=f.packed, zstd=true, exact=true).unwrap_or(Bytes::default())
    let a = @cmp.maximum(0L, from - f.from).to_int()
    let b = @cmp.minimum(bytes.length().to_int64(), end - f.from).to_int()
    if !take(if a < b { bytes[a:b] } else { bytes[0:0] }) {
      break
    }
  }
  true
}

///|
/// Where each line of `bytes` up to `cut` ends (just past its \n).
fn lines_of(bytes : BytesView, cut : Int) -> Array[Int] {
  let out = []
  for i in 0..<cut {
    if bytes[i] == b'\n' {
      out.push(i + 1)
    }
  }
  out
}

///|
/// read/tail.ts `TranscriptTail` as a reader's thread runs it: marking, counting what it reads.
priv struct Tail {
  runtime : String
  path : String
  mut offset : Int64
  mut packed_stamp : String?
  mut parts : Array[Bytes]
  mut held : Int
  mut state : ReadState
  mut count : Int
  mut marks : Array[Mark]
  mut anew : Bool
  /// What it reads given back, not only counted (`tail_read`: the live view's), and where the last read began
  mut collect : Array[Entry]?
  mut began : Int?
}

///|
fn Tail::new(runtime : String, path : String) -> Tail {
  {
    runtime,
    path,
    offset: 0L,
    packed_stamp: None,
    parts: [],
    held: 0,
    state: ReadState::new(),
    count: 0,
    marks: [],
    anew: false,
    collect: None,
    began: None,
  }
}

///|
/// read/tail.ts `TranscriptTail.from`, with its marks.
fn Tail::from(runtime : String, state : TailState, marks : Array[Mark]) -> Tail {
  let tail = Tail::new(state.runtime.unwrap_or(runtime), state.path)
  tail.marks = marks.copy()
  tail.offset = state.offset
  tail.hold(state.partial)
  tail.count = state.count
  tail.state = ReadState::of(state.inner)
  tail.packed_stamp = state.packed_stamp
  tail
}

///|
fn Tail::hold(self : Tail, rest : Bytes) -> Unit {
  self.parts = if rest.length() > 0 { [rest] } else { [] }
  self.held = rest.length()
}

///|
/// read/tail.ts `snapshot`.
fn Tail::snapshot(self : Tail) -> TailState {
  if self.parts.length() > 1 {
    self.parts = [joined(self.parts.map(p => p[:]))]
  }
  {
    path: self.path,
    runtime: Some(self.runtime),
    offset: self.offset,
    partial: self.parts.get(0).unwrap_or(Bytes::default()),
    count: self.count,
    inner: self.state.pairs(),
    packed_stamp: self.packed_stamp,
  }
}

///|
/// A read under way (read/tail.ts `#begin`'s `take` and `end`).
priv struct Run {
  tail : Tail
  had : Int
  mut read : Int
}

///|
fn Run::take(self : Run, piece : BytesView) -> Unit raise {
  let tail = self.tail
  let last = last_newline(piece)
  if last < 0 {
    tail.parts.push(joined([piece]))
    tail.held += piece.length()
    return
  }
  let bytes = if tail.held > 0 { joined(tail.parts.map(p => p[:]) + [piece]) } else { joined([piece]) }
  let cut = tail.held + last + 1
  tail.hold(joined([bytes[cut:]]))
  let base = tail.offset - bytes.length().to_int64()
  let mut from = 0
  for end in lines_of(bytes[:], cut) {
    let records = []
    for line in @utf8.decode_lossy(bytes[from:end]).split("\n") {
      if record_of(line.to_owned()) is Some(r) {
        records.push(r)
      }
    }
    from = end
    let entries = []
    for r in records {
      timeline_of(tail.runtime, r, tail.state, entries)
    }
    if tail.collect is Some(out) {
      out.append(entries)
    }
    self.read += entries.length()
    let index = self.had + self.read
    let (last_offset, last_index) = match tail.marks.last() {
      Some(m) => (m.offset, m.index)
      None => (0L, 0)
    }
    if index - last_index >= mark_every || (index > last_index && base + end.to_int64() - last_offset >= mark_bytes) {
      tail.marks.push({ offset: base + end.to_int64(), index, inner: tail.state.pairs() })
    }
  }
}

///|
fn Run::end(self : Run) -> Unit {
  self.tail.count += self.read
}

///|
/// read/tail.ts `#begin`: None when nothing came.
fn Tail::begin(self : Tail, stamp : String?, size : Int64) -> Run? {
  self.packed_stamp = stamp
  if size < self.offset {
    // Rewritten: start over.
    self.anew = true
    self.offset = 0L
    self.hold(Bytes::default())
    self.count = 0
    self.marks = []
  }
  if size == self.offset {
    return None
  }
  self.began = Some(self.count)
  Some({ tail: self, had: self.count, read: 0 })
}

///|
/// read/tail.ts `TranscriptTail.read`: what came since the last read, counted and marked.
fn Tail::read(self : Tail, host : @host.Host) -> Unit raise {
  let compressed = meta(host, self.path) is None
  let disk = if compressed { self.path + ".zst" } else { self.path }
  guard meta(host, disk) is Some((size, mtime)) else { return }
  let stamp = "\{size}:\{@jsjson.stringify(Num(mtime))}"
  if compressed && self.packed_stamp == Some(stamp) {
    return
  }
  let mut whole : Bytes? = None
  let mut size = size
  if compressed {
    let got = try {
      match written_size(host, disk) {
        Some(w) => Ok(w)
        None => {
          let b = bytes_of(host, disk, zstd=true).unwrap_or(Bytes::default())
          whole = Some(b)
          Ok(b.length().to_int64())
        }
      }
    } catch {
      e => Err(e)
    }
    match got {
      Ok(n) => size = n
      Err(_) => return
    }
  }
  guard self.begin(if compressed { Some(stamp) } else { None }, size) is Some(run) else { return }
  match whole {
    Some(b) => {
      let mut at = self.offset
      while at < size {
        let e = @cmp.minimum(size, at + piece_size)
        self.offset = e
        run.take(b[at.to_int():e.to_int()])
        at += piece_size
      }
      self.offset = size
    }
    None if compressed =>
      try {
        ignore(
          read_segments(host, disk, self.offset, size, piece => {
            self.offset += piece.length().to_int64()
            run.take(piece)
            true
          }),
        )
      } catch {
        // What could be read is kept; the rest is read next time.
        _ => ()
      }
    None =>
      try {
        while self.offset < size {
          let n = @cmp.minimum(piece_size, size - self.offset)
          guard bytes_of(host, self.path, from=self.offset, length=n) is Some(piece) else { break }
          if piece.length() == 0 {
            break
          }
          self.offset += piece.length().to_int64()
          run.take(piece[:])
        }
      } catch {
        // What could be read is kept; the rest is read next time.
        _ => ()
      }
  }
  run.end()
}

///|
/// read/transcripts.ts `marksDir`.
pub fn marks_dir(sep : String, data : String) -> String {
  @nodepath.join(sep, [data, "transcript-marks"])
}

///|
fn file_of(sep : String, dir : String, path : String) -> String {
  @nodepath.join(sep, [dir, "\{@replica.sha1_hex(path)}.json"])
}

///|
fn pairs_json(pairs : Array[(String, Int)]) -> Json {
  Json::array(pairs.map(p => Json::array([Json::string(p.0), Json::number(p.1.to_double())])))
}

///|
fn pairs_of(v : Json?) -> Array[(String, Int)] raise {
  guard v is Some(Array(xs)) else { fail("no pairs") }
  xs.map(x => match x {
    [String(k), Number(n, ..)] => (k, n.to_int())
    _ => fail("not a pair")
  })
}

///|
/// A transcript's reading as read/transcripts.ts writes it (`JSON.stringify(now)`).
fn marked_json(m : Marked) -> Json {
  let s = m.state
  {
    "reading": Json::number(reading.to_double()),
    "state": {
      "path": Json::string(s.path),
      "runtime": match s.runtime { Some(r) => Json::string(r); None => Json::null() },
      "offset": Json::number(s.offset.to_double()),
      "partial": Json::string(@base64.encode(s.partial[:])),
      "count": Json::number(s.count.to_double()),
      "inner": pairs_json(s.inner),
      "packedStamp": match s.packed_stamp { Some(p) => Json::string(p); None => Json::null() },
    },
    "marks": Json::array(
      m.marks.map(k => { "offset": Json::number(k.offset.to_double()), "index": Json::number(k.index.to_double()), "inner": pairs_json(k.inner) }),
    ),
  }
}

///|
/// A transcript's reading where the file says one: what it read, as written there.
fn state_of_json(v : Json) -> TailState raise {
  guard v is { "path": String(path), "offset": Number(offset, ..), "partial": String(partial), "count": Number(count, ..), .. } else {
    fail("no state")
  }
  {
    path,
    runtime: match v.value("runtime") { Some(String(r)) => Some(r); _ => None },
    offset: offset.to_int64(),
    partial: @base64.decode(partial),
    count: count.to_int(),
    inner: pairs_of(v.value("inner")),
    packed_stamp: match v.value("packedStamp") { Some(String(p)) => Some(p); _ => None },
  }
}

///|
fn marked_of_json(v : Json) -> (Int, Marked) raise {
  guard v is { "reading": Number(r, ..), "state": state, "marks": Array(marks), .. } else { fail("no reading") }
  let marks = marks.map(k => match k {
    { "offset": Number(o, ..), "index": Number(i, ..), "inner": inner, .. } => { offset: o.to_int64(), index: i.to_int(), inner: pairs_of(Some(inner)) }
    _ => fail("no mark")
  })
  (r.to_int(), { state: state_of_json(state), marks })
}

///|
/// read/transcripts.ts `markedOf`: a transcript's reading, read on to where it is written now, from what is kept, else
/// from disk, else from its start. `dir`: where readings are kept on disk.
fn marked_of(host : @host.Host, sep : String, runtime : String, path : String, dir : String?) -> Marked raise {
  let mut had = kept.get(path)
  kept.remove(path)
  if had is None && dir is Some(d) {
    let file = match (try { Ok(shell(host, "fs.read", { "path": Json::string(file_of(sep, d, path)), "strict": false })) } catch { e => Err(e) }) {
      Ok(String(text)) => Some(text)
      _ => None
    }
    if file is Some(text) {
      match (try { Ok(marked_of_json(@json.parse(text))) } catch { e => Err(e) }) {
        Ok((r, v)) if r == reading && v.state.path == path && v.state.runtime.unwrap_or(runtime) == runtime => {
          had = Some(v)
          on_disk[path] = v.state.offset
        }
        _ => ()
      }
    }
  }
  if had is Some(h) && h.state.runtime.unwrap_or(runtime) != runtime {
    had = None
  }
  let tail = match had {
    None => Tail::new(runtime, path)
    Some(h) => Tail::from(runtime, h.state, h.marks)
  }
  tail.read(host)
  let now = { state: tail.snapshot(), marks: tail.marks }
  kept[path] = now
  if kept.length() > kept_most {
    let first = kept.iter().next().unwrap().0
    kept.remove(first)
  }
  let behind = match on_disk.get(path) {
    Some(o) => now.state.offset - o >= kept_bytes
    None => true
  }
  let changed = match had {
    None => true
    Some(h) => tail.anew || now.marks.length() != h.marks.length() || now.state.packed_stamp != h.state.packed_stamp || behind
  }
  if dir is Some(d) && changed {
    try {
      ignore(shell(host, "fs.write", { "path": Json::string(file_of(sep, d, path)), "text": Json::string(marked_json(now).stringify()) }))
      on_disk[path] = now.state.offset
    } catch {
      _ => ()
    }
  }
  now
}

///|
/// read/transcripts.ts `chainOf`: a session's transcripts read as one, each one's reading read on to where it is
/// written now.
pub fn chain_of(host : @host.Host, sep : String, paths : Array[(String, String)], dir : String?) -> Array[Marked] raise {
  if unpacked.val is Some((p, _, _)) && !paths.iter().any(r => r.0 == p) {
    unpacked.val = None
  }
  paths.map(r => marked_of(host, sep, r.1, r.0, dir))
}

///|
/// read/transcripts.ts `lengthOf`.
pub fn length_of(chain : Array[Marked]) -> Int {
  let mut n = 0
  for m in chain {
    n += m.state.count
  }
  n
}

///|
/// read/tail.ts `TailState` as JSON (read/transcripts.ts `stateOf`, for the live view to go on from).
pub fn state_json(s : TailState) -> Json {
  let out : Map[String, Json] = { "path": Json::string(s.path) }
  if s.runtime is Some(r) {
    out["runtime"] = Json::string(r)
  }
  out["offset"] = Json::number(s.offset.to_double())
  out["partial"] = Json::string(@base64.encode(s.partial[:]))
  out["count"] = Json::number(s.count.to_double())
  out["inner"] = pairs_json(s.inner)
  out["packedStamp"] = match s.packed_stamp { Some(p) => Json::string(p); None => Json::null() }
  Json::object(out)
}

///|
/// read/transcripts.ts `entriesOf`: entries `from ..< to` of a chain as `chain_of` read it, whole or in brief, each
/// read from the mark before it (fewer where it has fewer, or where one could not be read: none after it).
pub fn entries_of(host : @host.Host, runtime : String, chain : Array[Marked], from : Double, to : Double, in_brief : Bool) -> Array[Json] {
  let out = []
  let mut first = 0.0
  for m in chain {
    let a = @cmp.maximum(from, first)
    let b = @cmp.minimum(to, first + m.state.count.to_double())
    if a < b {
      let got = read_between(host, m.state.runtime.unwrap_or(runtime), m, a - first, b - first)
      for e in got {
        if in_brief {
          let (shown, briefed) = brief(e)
          out.push(entry_json(shown, briefed))
        } else {
          out.push(entry_json(e, false))
        }
      }
      if got.length().to_double() < b - a {
        break
      }
    }
    first += m.state.count.to_double()
  }
  out
}

///|
/// read/transcripts.ts `readBetween`: entries `from ..< to` of one transcript, read from the last mark at or before
/// `from` up to where its reading stands.
fn read_between(host : @host.Host, runtime : String, m : Marked, from : Double, to : Double) -> Array[Entry] {
  let mut mark : Mark = { offset: 0L, index: 0, inner: [] }
  for each in m.marks {
    if each.index.to_double() > from {
      break
    }
    mark = each
  }
  let path = m.state.path
  // Up to the end of its last whole line read: what comes after is the next read's.
  let end = m.state.offset - m.state.partial.length().to_int64()
  let state = ReadState::of(mark.inner)
  let out = []
  let mut index = mark.index
  // A line read: whether more are wanted.
  let line = fn(bytes : BytesView) -> Bool raise {
    guard record_of(@utf8.decode_lossy(bytes)) is Some(record) else { return true }
    let entries = []
    timeline_of(runtime, record, state, entries)
    for e in entries {
      if index.to_double() >= from && index.to_double() < to {
        out.push(e)
      }
      index += 1
    }
    index.to_double() < to
  }
  // Lines from `data` on, while more are wanted: what is left of the last, not yet whole (None: no more wanted).
  let lines = fn(data : BytesView) -> Bytes? raise {
    let mut at = 0
    for i in 0..<data.length() {
      if data[i] == b'\n' {
        if !line(data[at:i]) {
          return None
        }
        at = i + 1
      }
    }
    Some(joined([data[at:]]))
  }
  let packed = meta(host, path) is None
  if packed {
    // Put away: the segments from the mark on, while more are wanted; one put away before there were segments
    // decompressed once while its history is read.
    let disk = path + ".zst"
    try {
      let mut carry = Bytes::default()
      let segmented = read_segments(host, disk, mark.offset, end, piece => {
        match lines(if carry.length() > 0 { joined([carry[:], piece])[:] } else { piece }) {
          None => false
          Some(left) => {
            carry = left
            true
          }
        }
      })
      if segmented {
        return out
      }
      let stamp = m.state.packed_stamp
      let bytes = match unpacked.val {
        Some((p, s, b)) if p == path && s == stamp => b
        _ => {
          let b = bytes_of(host, disk, zstd=true).unwrap_or(Bytes::default())
          unpacked.val = Some((path, stamp, b))
          b
        }
      }
      let a = @cmp.minimum(mark.offset, bytes.length().to_int64()).to_int()
      let b = @cmp.maximum(a.to_int64(), @cmp.minimum(end, bytes.length().to_int64())).to_int()
      ignore(lines(bytes[a:b]))
    } catch {
      _ => ()
    }
    return out
  }
  try {
    let mut carry = Bytes::default()
    let mut at = mark.offset
    while at < end {
      guard bytes_of(host, path, from=at, length=@cmp.minimum(piece_read, end - at)) is Some(piece) else { break }
      if piece.length() == 0 {
        break
      }
      at += piece.length().to_int64()
      match lines(if carry.length() > 0 { joined([carry[:], piece[:]])[:] } else { piece[:] }) {
        None => break
        Some(left) => carry = left
      }
    }
  } catch {
    // What could be read is given.
    _ => ()
  }
  out
}

///|
/// read/tail.ts `TranscriptTail.from(…).readSoon()` (the live view's, sessions/live.ts): what a transcript gained since
/// where its reading stood (`state`: a TailState as JSON, or only `path` and `runtime` for one not read yet), as
/// `{start, entries, state}`, the entries whole as the timeline gives them.
pub fn tail_read(host : @host.Host, runtime : String, state : Json) -> Json raise {
  let st = match state {
    { "offset": Number(_), .. } => state_of_json(state)
    { "path": String(path), .. } =>
      {
        path,
        runtime: match state.value("runtime") { Some(String(r)) => Some(r); _ => None },
        offset: 0L,
        partial: Bytes::default(),
        count: 0,
        inner: [],
        packed_stamp: None,
      }
    _ => fail("no state")
  }
  let tail = Tail::from(runtime, st, [])
  let out = []
  tail.collect = Some(out)
  tail.read(host)
  let start = match tail.began {
    Some(at) => at
    None => tail.count
  }
  {
    "start": Json::number(start.to_double()),
    "entries": Json::array(out.map(e => entry_json(e, false))),
    "state": state_json(tail.snapshot()),
  }
}
