// Code and text shown as they come: read through the core a part at a time (Viewer::read_part: a chat's file, a
// drive's, one a message names by its path), its lines shown as soon as its first part is here, the next part read as
// the end of what has come scrolls near; never read whole first, never cut at a size. Code is coloured a piece at a
// time (`code.ink` on each piece's whole lines, at most HIGHLIGHT_LIMIT), so a file of any size is. One that comes
// whole in its first part is shown as any file read whole is (its bytes: Viewer::text_stage, a desktop's reader).

///|
/// How much of it a part reads.
pub let flow_part : Int = 256 * 1024

///|
/// How many rows of 60 lines before the end of what has come the next part is read.
pub let flow_ahead : Int = 10

///|
/// Lines coloured together: `from` its first, `to` past its last, its words until they are coloured.
pub(all) struct FlowPiece {
  from : Int
  to : Int
  mut words : String
  mut done : Bool
}

///|
/// What has come of a text shown as it comes.
pub(all) struct Flow {
  /// its lines ended so far
  lines : Array[String]
  /// the line begun and not ended yet, and a character cut at the last part's end (its first bytes)
  mut tail : String
  mut carry : Bytes
  /// how much of it has been read; its whole size as the station says (-1 until then)
  mut got : Double
  mut total : Double
  mut reading : Bool
  /// how many parts have come (what its stage reads: built again as one comes), why reading on failed
  parts : @signals.Signal[Int]
  failed : @signals.Signal[String?]
  /// its lines coloured (code), a piece at a time, a line's runs each once its piece is; for the dark theme or not
  pieces : Array[FlowPiece]
  colored : Array[Array[@ui.Run]?]
  mut colored_dark : Bool
}

///|
pub fn Flow::new() -> Flow {
  {
    lines: [],
    tail: "",
    carry: b"",
    got: 0.0,
    total: -1.0,
    reading: false,
    parts: @signals.signal(0),
    failed: @signals.signal(None),
    pieces: [],
    colored: [],
    colored_dark: false,
  }
}

///|
/// Whether all of it has come.
pub fn Flow::whole(self : Flow) -> Bool {
  self.total >= 0.0 && self.got >= self.total
}

///|
/// Whether it is shown as it comes: code, and text but for one a desktop reads as a book (its size known, and small
/// enough to be read whole: show_limit).
pub fn Viewer::flows(self : Viewer) -> Bool {
  match self.shown_kind() {
    Some(KCode) => true
    Some(KText) => {
      let size = self.listed_size()
      !(size > 0.0 && size <= show_limit.to_double())
    }
    _ => false
  }
}

///|
/// Whether it shows what has come of it as it comes: some has, and it did not all come in its first part (then it is
/// a file read whole, its bytes).
pub fn Viewer::flowing(self : Viewer) -> Bool {
  match self.flow.get() {
    Some(f) => self.bytes.get() is None && f.parts.get() > 0
    None => false
  }
}

///|
/// Its next part asked of the core, unless one is on its way, all of it has come or reading failed. The first part
/// that brings all of it makes it a file read whole (its bytes).
pub fn Viewer::read_on(self : Viewer, src : Source) -> Unit {
  let v = self
  let f = match v.flow.get() {
    Some(f) => f
    None => {
      let f = Flow::new()
      v.flow.set(Some(f))
      f
    }
  }
  guard !f.reading && !f.whole() && f.failed.get() is None else { return }
  f.reading = true
  let first = f.got == 0.0
  v.read_part(src, f.got, flow_part, "file", fn(r) {
    f.reading = false
    match r {
      Ok((said, bytes)) => {
        // (its whole size: a part's `total`, `file.open`'s `size`)
        let total = match field(Some(said), "total") {
          Some(Number(n, ..)) => n
          _ =>
            match field(Some(said), "size") {
              Some(Number(n, ..)) => n
              _ => f.got + bytes.length().to_double()
            }
        }
        f.total = if bytes.length() == 0 { f.got } else { total }
        f.got += bytes.length().to_double()
        if first && f.whole() {
          v.bytes.set(Some(bytes))
        } else {
          f.take(bytes)
        }
        f.parts.set(f.parts.get() + 1)
      }
      Err(e) => {
        let said = match text(Some(e), "message") {
          "" => e.stringify()
          m => m
        }
        // (its first part: it cannot be shown; a later one: said under what has come)
        if first {
          v.error.set(Some(said))
        }
        f.failed.set(Some(said))
      }
    }
  })
}

///|
/// A part's bytes taken in: its whole characters added to the line begun, the lines it ends kept, a piece made of
/// them to colour; the line left begun is the last once all has come.
pub fn Flow::take(self : Flow, bytes : Bytes) -> Unit {
  let all = if self.carry.length() == 0 {
    bytes
  } else {
    let b = Buffer(size_hint=self.carry.length() + bytes.length())
    b.write_bytes(self.carry)
    b.write_bytes(bytes)
    b.to_bytes()
  }
  let end = if self.whole() { all.length() } else { utf8_whole(all) }
  self.carry = all[end:].to_bytes()
  let words = self.tail + @codec.utf8_text(all[:end].to_bytes(), end)
  let parts = words.split("\n").map(fn(s) { s.to_owned() }).to_array()
  self.tail = parts.pop().unwrap_or("")
  let from = self.lines.length()
  for line in parts {
    self.lines.push(if line.has_suffix("\r") { line.view(end_offset=line.length() - 1).to_owned() } else { line })
  }
  if self.whole() && self.tail != "" {
    self.lines.push(self.tail)
    self.tail = ""
  }
  if self.lines.length() > from {
    let words = self.lines[from:].iter().collect().join("\n")
    self.pieces.push({ from, to: self.lines.length(), words, done: false })
  }
  while self.colored.length() < self.lines.length() {
    self.colored.push(None)
  }
}

///|
/// How many bytes of `b` are whole UTF-8 characters: all but a character its end cuts.
pub fn utf8_whole(b : Bytes) -> Int {
  let n = b.length()
  let mut i = n - 1
  // back over at most 3 bytes that go on a character, to the byte that begins it
  while i >= 0 && n - i <= 4 && b[i].to_int() >= 0x80 && b[i].to_int() < 0xC0 {
    i -= 1
  }
  guard i >= 0 && n - i <= 4 else { return n }
  let x = b[i].to_int()
  let len = if x < 0x80 { 1 } else if x >= 0xF0 { 4 } else if x >= 0xE0 { 3 } else if x >= 0xC0 { 2 } else { 1 }
  if i + len > n {
    i
  } else {
    n
  }
}

///|
/// Its pieces coloured as the core says of the file's language (asked as they come, each once), for the theme shown.
pub fn Flow::ink(self : Flow, c : @ui.Ctx, lang : String) -> Unit {
  guard lang != "" else { return }
  let dark = @sf.theme().dark
  if self.colored_dark != dark {
    self.colored_dark = dark
    for p in self.pieces {
      if p.done {
        // (its words again, to colour for this theme)
        p.words = self.lines[p.from:p.to].iter().collect().join("\n")
        p.done = false
      }
    }
  }
  for p in self.pieces {
    guard !p.done else { continue }
    match @sf.code_ink(c, p.words, lang) {
      // (asked: plain until the core says)
      None => ()
      Some(ink) => {
        match ink {
          Some(ink) =>
            for k, line in runs_by_line(@sf.ink_runs(p.words, ink, dark)) {
              if p.from + k < p.to {
                self.colored[p.from + k] = Some(line)
              }
            }
          None => ()
        }
        p.done = true
        p.words = ""
      }
    }
  }
}

///|
/// What has come of it, on the stage as a file's text is (Viewer::lines_stage): its lines and the one begun, coloured
/// where they are; the next part read as its end comes near; why reading on failed over them.
pub fn Viewer::flow_stage(self : Viewer, c : @ui.Ctx, src : Source, f : Flow, kind : PKind, stage : Int) -> Unit {
  let v = self
  ignore(f.parts.get())
  tap_stage(c, v, stage)
  let (_, _, language) = preview_kind(v.name)
  f.ink(c, if kind == KCode { language } else { "" })
  let count = f.lines.length() + (if f.tail != "" { 1 } else { 0 })
  let near = v.lines_stage(
    c,
    kind,
    count,
    fn(k) { if k < f.lines.length() { f.lines[k] } else { f.tail } },
    fn(k) {
      match f.colored.get(k) {
        Some(Some(line)) => Some(line)
        _ => None
      }
    },
    match f.failed.get() {
      Some(e) => Some(@sf.t("web-main.preview.loadFailed", args=[("error", e)]))
      None => None
    },
  )
  if near && !f.reading && !f.whole() && f.failed.get() is None {
    // (asked once the frame's builds are over)
    c.tell("preview/read-on", fn() { v.read_on(src) })
  }
}
