// What the system's media and sharing do for the app (as @hostapi's views, share-in and marks have them), through the
// framework, so that under a Tester they are the test's: a player's reads of the app's bytes and its state
// (Tester::view_reads, set_player), what another app shares in (Tester::share_in) and what the app shares out
// (Tester::shared_out), the marks drawn onto an image (Tester::marks_drawn), each at the next frame, as a host's event
// comes at a frame's boundary.

///|
/// A player's ask for the app's bytes (view_read_next): `length` from `offset`; a read let go of: minus its number.
priv struct FakeRead {
  view : Int
  req : Int
  offset : Double
  length : Int
}

///|
fn fake_read_next(f : FakeHost, view : Int, out : FixedArray[Double]) -> Int {
  for i, r in f.reads {
    if r.view == view {
      f.reads.remove(i) |> ignore
      out[0] = r.offset
      out[1] = r.length.to_double()
      if r.req > 0 {
        f.read_from[(view, r.req)] = r.offset
      }
      return r.req
    }
  }
  0
}

///|
/// Native view `view`'s player asks the app for `length` of its bytes from `offset` (as a player streaming from the
/// app does: NativeView's `read`), handed to the app at the next frame; its number (what view_answers says it by).
pub fn Tester::view_reads(self : Tester, view : Int, offset : Double, length : Int) -> Int {
  self.fake.read_ids += 1
  self.fake.reads.push({ view, req: self.fake.read_ids, offset, length })
  self.fake.wants = true
  self.fake.read_ids
}

///|
/// Native view `view`'s player lets go of its read `req` (it wants none of what is left of it: a seek elsewhere),
/// handed to the app at the next frame.
pub fn Tester::view_lets_go(self : Tester, view : Int, req : Int) -> Unit {
  self.fake.reads.push({ view, req: -req, offset: 0.0, length: 0 })
  self.fake.wants = true
}

///|
/// What the app gave view `view`'s player for its reads answered to their end, in the order they ended: (the read's
/// number, how many bytes in all its answers, the whole's length as the app last said it, -1 unknown).
pub fn Tester::view_answers(self : Tester, view : Int) -> Array[(Int, Int, Double)] {
  let given : Map[Int, Int] = {}
  let ended = []
  for a in self.fake.read_answers {
    if a.0 == view {
      let n = given.get(a.1).unwrap_or(0) + a.2
      given[a.1] = n
      if !a.4 {
        ended.push((a.1, n, a.3))
      }
    }
  }
  ended
}

///|
/// How far into its file view `view`'s player has had its bytes: the furthest any of its reads has come with what the
/// app gave it (where the read is from, and the bytes given it), 0 none.
pub fn Tester::view_read_to(self : Tester, view : Int) -> Double {
  let given : Map[Int, Int] = {}
  for a in self.fake.read_answers {
    if a.0 == view {
      given[a.1] = given.get(a.1).unwrap_or(0) + a.2
    }
  }
  let mut most = 0.0
  for req, n in given {
    match self.fake.read_from.get((view, req)) {
      Some(from) if from + n.to_double() > most => most = from + n.to_double()
      _ => ()
    }
  }
  most
}

///|
/// How many bytes the app has given view `view`'s player for its read `req` so far, and whether that read has had its
/// last answer.
pub fn Tester::view_given(self : Tester, view : Int, req : Int) -> (Int, Bool) {
  let mut n = 0
  let mut ended = false
  for a in self.fake.read_answers {
    if a.0 == view && a.1 == req {
      n += a.2
      ended = ended || !a.4
    }
  }
  (n, ended)
}

///|
/// Native view `view`'s player as it stands from the next frame (what view_info says: NativeView::duration, position,
/// playing, natural, shown, buffering, buffered, ended); what is not given stays as it was (at first: 10 s long, at
/// 0, paused, 640 × 360, its first frame shown).
pub fn Tester::set_player(
  self : Tester,
  view : Int,
  duration? : Double,
  position? : Double,
  playing? : Bool,
  natural? : (Double, Double),
  shown? : Bool,
  buffering? : Bool,
  buffered? : Double,
  ended? : Bool,
) -> Unit {
  let p = match self.fake.players.get(view) {
    Some(p) => p
    None => {
      let p = FixedArray::make(10, 0.0)
      p[0] = 10000.0
      p[3] = 640.0
      p[4] = 360.0
      p[6] = 1.0
      self.fake.players[view] = p
      p
    }
  }
  let on = fn(b : Bool) { if b { 1.0 } else { 0.0 } }
  if duration is Some(d) {
    p[0] = d
  }
  if position is Some(x) {
    p[1] = x
  }
  if playing is Some(b) {
    p[2] = on(b)
  }
  if natural is Some((w, h)) {
    p[3] = w
    p[4] = h
  }
  if shown is Some(b) {
    p[6] = on(b)
  }
  if buffering is Some(b) {
    p[7] = on(b)
  }
  if buffered is Some(x) {
    p[8] = x
  }
  if ended is Some(b) {
    p[9] = on(b)
  }
  // (as a host tells it: how it stands changed, a frame asked for by the app as it hears it)
  on_outside(outside_stood, view, 0)
}

///|
/// A file's kind by its name, as a system says what is shared (its type).
fn mime_of(name : String) -> String {
  let lower = name.to_lower()
  let ends = fn(s : String) { lower.has_suffix(s) }
  if ends(".png") {
    "image/png"
  } else if ends(".jpg") || ends(".jpeg") {
    "image/jpeg"
  } else if ends(".gif") {
    "image/gif"
  } else if ends(".webp") {
    "image/webp"
  } else if ends(".heic") {
    "image/heic"
  } else if ends(".pdf") {
    "application/pdf"
  } else if ends(".mp4") {
    "video/mp4"
  } else if ends(".mov") {
    "video/quicktime"
  } else if ends(".mp3") {
    "audio/mpeg"
  } else if ends(".txt") || ends(".md") {
    "text/plain"
  } else {
    "application/octet-stream"
  }
}

///|
/// Another app shares `text` (titled `title`) and `files` (their names and bytes) into this one, as Android's
/// ACTION_SEND does: shared_in says it from the next frame, once.
pub fn Tester::share_in(
  self : Tester,
  text : String,
  title? : String = "",
  files? : Array[(String, Bytes)] = [],
) -> Unit {
  let m : Map[String, Json] = { "text": Json::string(text), "title": Json::string(title) }
  if files.length() > 0 {
    m["files"] = Json::array(
      files.map(fn(f) {
        Json::object({
          "name": Json::string(f.0),
          "type": Json::string(mime_of(f.0)),
          "size": Json::number(f.1.length().to_double()),
        })
      }),
    )
  }
  self.fake.share = Some((Json::object(m).stringify(), g().frame_no))
  self.fake.share_files.clear()
  for f in files {
    self.fake.share_files.push(f.1)
  }
  self.fake.wants = true
}

///|
/// What another app shared into this one since last asked (@hostapi.shared_in: JSON text `{"text","title","files"}`, each
/// file `{"name","type","size"}`), "" when nothing was. Under a Tester, what the test shared in (Tester::share_in).
pub fn shared_in() -> String {
  match fake.val {
    Some(f) =>
      match f.share {
        Some((said, frame)) if g().frame_no > frame => {
          f.share = None
          said
        }
        _ => ""
      }
    None => @hostapi.shared_in()
  }
}

///|
/// The i-th of the files shared in (`shared_in`'s `files`), taken once: empty after, or where there is none.
pub fn shared_in_file(i : Int) -> Bytes {
  match fake.val {
    Some(f) =>
      if i >= 0 && i < f.share_files.length() {
        let b = f.share_files[i]
        f.share_files[i] = b""
        b
      } else {
        b""
      }
    None => @hostapi.shared_in_file(i)
  }
}

///|
/// Marks being drawn onto an image (@hostapi.MarkedImage).
pub struct MarkedImage {
  priv host : @hostapi.MarkedImage?
  priv fake : Int
}

///|
/// A PNG of one clear pixel: what a Tester's host gives for an image with marks drawn on it (it draws none).
let marked_png : Bytes = b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1F\x15\xC4\x89\x00\x00\x00\x0A\x49\x44\x41\x54\x78\x9C\x63\x00\x01\x00\x00\x05\x00\x01\x0D\x0A\x2D\xB4\x00\x00\x00\x00\x49\x45\x4E\x44\xAE\x42\x60\x82"

///|
/// `image` with `marks` drawn on it (@hostapi.draw_marks: their JSON as marks.mbt says it), None where the host cannot.
/// Under a Tester the marks are kept (Tester::marks_drawn) and a PNG is made by the next frame.
pub fn draw_marks(image : Bytes, marks : String) -> MarkedImage? {
  match fake.val {
    Some(f) => {
      ignore(image)
      f.marks.push((marks, g().frame_no))
      f.marks_out.push(f.marks_next.unwrap_or(marked_png))
      f.marks_next = None
      f.wants = true
      let m : MarkedImage = { host: None, fake: f.marks.length() - 1 }
      outside_start(outside_marks, m.outside_id(), "marks drawn \{m.outside_id()}")
      Some(m)
    }
    None =>
      match @hostapi.draw_marks(image, marks) {
        Some(h) => {
          let m : MarkedImage = { host: Some(h), fake: -1 }
          outside_start(outside_marks, m.outside_id(), "marks drawn \{m.outside_id()}")
          Some(m)
        }
        None => None
      }
  }
}

///|
/// Its id as the host's event names it (outside_marks), a Tester's its place, from 1.
fn MarkedImage::outside_id(self : MarkedImage) -> Int {
  match self.host {
    Some(h) => h.id()
    None => self.fake + 1
  }
}

///|
/// The PNG once drawn (Some(empty): it could not be), None while it is drawn; taken once.
pub fn MarkedImage::made(self : MarkedImage) -> Bytes? {
  if !answer_here(outside_marks, self.outside_id()) {
    return None
  }
  let got = self.png()
  if got is Some(_) {
    answer_taken(outside_marks, self.outside_id())
    outside_end(outside_marks, self.outside_id())
  }
  got
}

///|
fn MarkedImage::png(self : MarkedImage) -> Bytes? {
  match self.host {
    Some(m) => m.made()
    None =>
      match fake.val {
        Some(f) if self.fake >= 0 && self.fake < f.marks.length() =>
          if g().frame_no > f.marks[self.fake].1 {
            Some(f.marks_out[self.fake])
          } else {
            None
          }
        _ => Some(b"")
      }
  }
}

///|
/// What the next drawing of marks gives as its PNG (draw_marks, made): `png`, the bytes a run's host gave (as large,
/// its header as wide and tall, as the run's upload says), in place of one clear pixel; the one after, one clear pixel
/// again.
pub fn Tester::marks_make(self : Tester, png : Bytes) -> Unit {
  self.fake.marks_next = Some(png)
}

///|
/// The marks the app had drawn onto images (draw_marks' JSON), oldest first.
pub fn Tester::marks_drawn(self : Tester) -> Array[String] {
  self.fake.marks.map(fn(m) { m.0 })
}

///|
/// Words (`text`), or a file of `data` named `name` (`mime`), handed to another app through the system's share sheet
/// (@hostapi.share): false where there is none. Under a Tester the sheet takes it, kept for the test (Tester::shared_out).
pub fn share(text : String, name : String, mime : String, data : Bytes) -> Bool {
  match fake.val {
    Some(f) => {
      f.shares.push((text, name, mime, data))
      true
    }
    None => @hostapi.share(text, name, mime, data)
  }
}

///|
/// What the app handed to the system's share sheet, oldest first: (its words, a file's name, its kind, its bytes).
pub fn Tester::shared_out(self : Tester) -> Array[(String, String, String, Bytes)] {
  self.fake.shares
}

///|
/// What a real host said of a native view as a run recorded it (@ui.trace_views' line, as JSON), said again by the
/// fake host from now on: how it stands (`{"info":{"view":N,"state":S,"at":[…]}}`: what view_info answers until it is
/// said again, over the fake host's own player), a video's frames' times or a grab's state (`{"view":{"view":N,"what":W,"text":T}}`: what
/// view_text answers until it is said again), or a frame grabbed (`{"still":{"view":N},"b":HEX}`: its grab ready, the
/// bytes what the next view_still gives); of a site view, what its page asked of its host (`{"site":{"view":N,"event":E}}`:
/// taken on the next frame, as Tester::site_says), the body of a request it made (`{"sitebody":{"view":N,"req":R},"b":HEX}`)
/// and where its page is (`{"sitestate":{"view":N,"state":S}}`: what view_site_state answers until it is said again);
/// of a stream, an event its host told (`{"stream":{"id":N,"e":E}}`: taken at the next frame, as Tester::stream_shows).
/// What is not said is not known (NativeView::frames None, no frame grabbed). False for a line that is none of these.
pub fn Tester::view_said(self : Tester, line : String) -> Bool {
  // (what the host says of its views comes from outside: frame_watch.mbt)
  outside_counted()
  fake_view_said(self.fake, line)
}

///|
fn fake_view_said(f : FakeHost, line : String) -> Bool {
  let j : Json = @json.parse(line) catch { _ => return false }
  let num = fn(o : Map[String, Json], k : String) -> Int? {
    match o.get(k) {
      Some(Number(n, ..)) => Some(n.to_int())
      _ => None
    }
  }
  match j {
    Object(m) if m.get("site") is Some(Object(v)) =>
      match (num(v, "view"), v.get("event")) {
        (Some(id), Some(e)) => {
          fake_site_push(f, id, match e {
            String(s) => s
            _ => e.stringify()
          })
          true
        }
        _ => false
      }
    Object(m) if m.get("sitebody") is Some(Object(v)) =>
      match (num(v, "view"), num(v, "req"), m.get("b")) {
        (Some(id), Some(req), Some(String(hex))) => {
          f.site_bodies[(id, req)] = @codec.from_hex(hex)
          true
        }
        _ => false
      }
    Object(m) if m.get("sitestate") is Some(Object(v)) =>
      match (num(v, "view"), v.get("state")) {
        (Some(id), Some(st)) => {
          f.site_states[id] = match st {
            String(s) => s
            _ => st.stringify()
          }
          // (a page that starts loading is not there for scripts until it is: loaded, or said something)
          match st {
            Object(o) if o.get("loading") is Some(True) => f.page_there[id] = false
            _ => ()
          }
          f.wants = true
          true
        }
        _ => false
      }
    Object(m) if m.get("stream") is Some(Object(v)) => fake_stream_said(f, v)
    // a run's player's read (or one it let go of), asked again: the app takes it at the next frame
    Object(m) if m.get("read") is Some(Object(v)) => {
      let offset = match v.get("offset") {
        Some(Number(n, ..)) => n
        _ => 0.0
      }
      match (num(v, "view"), num(v, "req"), num(v, "gone")) {
        (Some(id), Some(req), _) if req > 0 => {
          f.reads.push({ view: id, req, offset, length: num(v, "length").unwrap_or(0) })
          f.wants = true
          true
        }
        (Some(id), _, Some(gone)) if gone > 0 => {
          f.reads.push({ view: id, req: -gone, offset: 0.0, length: 0 })
          f.wants = true
          true
        }
        _ => false
      }
    }
    Object(m) if m.get("info") is Some(Object(v)) =>
      match (num(v, "view"), num(v, "state"), v.get("at")) {
        (Some(id), Some(state), Some(Array(xs))) if xs.length() == 10 => {
          let at = FixedArray::make(10, 0.0)
          for i, x in xs {
            at[i] = match x {
              Number(n, ..) => n
              _ => 0.0
            }
          }
          f.view_infos[id] = (state, at)
          // (as the host told it: how it stands changed, a frame asked for by the app as it hears it)
          on_outside(outside_stood, id, 0)
          true
        }
        _ => false
      }
    Object(m) =>
      match (m.get("view"), m.get("still")) {
        (Some(Object(v)), _) =>
          match (num(v, "view"), num(v, "what"), v.get("text")) {
            (Some(id), Some(what), Some(String(text))) => {
              f.view_texts[(id, what)] = text
              f.wants = true
              true
            }
            _ => false
          }
        (_, Some(Object(v))) =>
          match (num(v, "view"), m.get("b")) {
            (Some(id), Some(String(hex))) => {
              let q = match f.view_stills.get(id) {
                Some(q) => q
                None => {
                  let q = []
                  f.view_stills[id] = q
                  q
                }
              }
              q.push(@codec.from_hex(hex))
              f.view_texts[(id, 2)] = "2"
              f.wants = true
              true
            }
            _ => false
          }
        _ => false
      }
    _ => false
  }
}

