// The system's pickers and the files the app keeps on the device (as @hostapi's pick.mbt and keep.mbt have them), through
// the framework. Under a Tester the system is the test's (its fake host's pk_* and kp_*, fake_host.mbt): its pickers
// give what the test said (Tester::picks) and what the app keeps is kept by the test (Tester::kept), each answer at the
// next frame, as a host's event comes at a frame's boundary.

///|
/// An ask of the system's pickers under way (@hostapi.Pick): one of the host's, or (photos of the gallery picked
/// together: pick_photos) one for each, answered as one once all of them are, in their order.
pub struct Pick {
  priv hosts : Array[@hostapi.Pick]
  /// what each of `hosts` answered (taken from the host as its event says it did: Pick::take)
  priv got : Array[Array[@hostapi.Picked]?]
  /// all of it, once all of `hosts` answered: what reads it is told then (Pick::files)
  priv said : @signals.Signal[Array[@hostapi.Picked]?]
}

///|
/// Asks the system for files of `kind` (@hostapi.pick; `hold`: one too big to be read whole may be held by the host):
/// None when this host cannot. `on_got`: given what was picked once (empty: called off), in the event that takes the
/// answer, outside any tracking, to write state where no node waits on `Pick::files`.
pub fn pick(
  kind : @hostapi.PickKind,
  hold? : Bool = false,
  on_got? : (Array[@hostapi.Picked]) -> Unit,
) -> Pick? {
  match @hostapi.pick(kind, hold~) {
    Some(h) => Some(Pick::waits([h], "a pick", on_got?))
    None => None
  }
}

///|
/// An ask of `hosts`, waited on until the system answers each (hostcall.mbt's outside, by its id as the host's event
/// names it: outside_pick), each taken as its event comes (outside_takes).
fn Pick::waits(
  hosts : Array[@hostapi.Pick],
  what : String,
  on_got? : (Array[@hostapi.Picked]) -> Unit,
) -> Pick {
  let p : Pick = { hosts, got: hosts.map(fn(_) { None }), said: @signals.signal(None) }
  for i, h in hosts {
    outside_start(outside_pick, h.id(), what + " \{h.id()}")
    outside_takes(outside_pick, h.id(), fn() { p.take(i, on_got) })
  }
  p
}

///|
/// Photos of the gallery (`srcs`) read whole, as one pick of them in that order (@hostapi.pick_photo, each): None
/// where the host has no gallery. `on_got`: given all of them once in `srcs`'s order, as the last is answered.
pub fn pick_photos(
  srcs : Array[String],
  on_got? : (Array[@hostapi.Picked]) -> Unit,
) -> Pick? {
  let hosts = []
  for src in srcs {
    match @hostapi.pick_photo(src) {
      Some(h) => hosts.push(h)
      None => ()
    }
  }
  if hosts.is_empty() {
    None
  } else {
    Some(Pick::waits(hosts, "a gallery photo read", on_got?))
  }
}

///|
/// The host's answer for `hosts[i]` taken, as its event says it came (or, a host answering by the frame, as a frame
/// begins): what it gave kept, the ask's wait over; all of them answered, what was picked said (Pick::files) and given
/// to `on_got`. Whether it was there to take.
fn Pick::take(
  self : Pick,
  i : Int,
  on_got : ((Array[@hostapi.Picked]) -> Unit)?,
) -> Bool {
  let h = self.hosts[i]
  guard self.got[i] is None && h.files() is Some(files) else { return false }
  self.got[i] = Some(files)
  outside_end(outside_pick, h.id(), wake=false)
  let out = []
  for got in self.got {
    match got {
      Some(files) => out.push_iter(files.iter())
      None => return true
    }
  }
  self.said.set(Some(out))
  match on_got {
    Some(f) => @signals.untracked(fn() { f(out) })
    None => ()
  }
  true
}

///|
/// What was picked, once the system has answered (empty: called off); None while it asks. A signal's read: what reads
/// it (a binding, a `reacts`, an old view's build) is told as the answer comes, and reads the same however often.
pub fn Pick::files(self : Pick) -> Array[@hostapi.Picked]? {
  self.said.get()
}

///|
/// What the system's pickers give from now on, whatever is asked (as MBUI_PICK_FILES does a host's), each ask answered
/// at its moment, told as a host's event (after the event that asked, before the clock moves on): `files` (their names
/// and bytes); none: the person calls the picker off.
pub fn Tester::picks(self : Tester, files : Array[(String, Bytes)]) -> Unit {
  self.fake.picks.clear()
  for f in files {
    self.fake.picks.push({ name: f.0, bytes: f.1, held: 0, size: f.1.length().to_double(), src: "" })
  }
}

///|
/// The system's pickers from now on answered as the test says (Tester::pick_answer), as a person takes their while,
/// not at each ask.
pub fn Tester::picks_by_hand(self : Tester) -> Unit {
  self.fake.picks_by_hand = true
}

///|
/// The person answers ask `n` (from 1, in the order asked: Tester::pick_asks) now, with what the pickers give
/// (Tester::picks): told at this moment, as a host's event (after what is going on, before the clock moves on or an
/// input comes).
pub fn Tester::pick_answer(self : Tester, n : Int) -> Unit {
  let f = self.fake
  f.due(f.time, "a pick answered", fn() { fake_pick_said(f, n) })
}

///|
/// What the app asked of the system's pickers, oldest first.
pub fn Tester::pick_asks(self : Tester) -> Array[@hostapi.PickKind] {
  self.fake.pick_asks.map(fn(a) { a.kind })
}

///|
/// A file being kept on the device (@hostapi.Keep).
pub struct Keep {
  priv host : @hostapi.Keep
}

///|
/// A file named `name` (`mime`, "" when unknown) to keep on the device, its bytes to come (@hostapi.keep_begin): None
/// when this host keeps none.
pub fn keep_begin(name : String, mime : String, way? : @hostapi.KeepWay = Downloads) -> Keep? {
  match @hostapi.keep_begin(name, mime, way~) {
    Some(k) => Some({ host: k })
    None => None
  }
}

///|
/// The next of its bytes; false when they could not be written.
pub fn Keep::append(self : Keep, data : Bytes) -> Bool {
  self.host.append(data)
}

///|
/// All of it is here: the host puts it in its place.
pub fn Keep::finish(self : Keep) -> Unit {
  self.host.finish()
}

///|
/// How it stands.
pub fn Keep::kept(self : Keep) -> @hostapi.Kept {
  self.host.kept()
}

///|
/// Let go of: one not finished is called off.
pub fn Keep::end(self : Keep) -> Unit {
  self.host.end()
}

///|
/// `data`, all here, kept as a file named `name` (@hostapi.keep): None when this host keeps none.
pub fn keep(name : String, mime : String, data : Bytes, way? : @hostapi.KeepWay = Downloads) -> Keep? {
  match keep_begin(name, mime, way~) {
    Some(k) => {
      if k.append(data) {
        k.finish()
      }
      Some(k)
    }
    None => None
  }
}

///|
/// The files the app kept on the device (finished), oldest first: their names, kinds and bytes.
pub fn Tester::kept(self : Tester) -> Array[(String, String, Bytes)] {
  self.fake.keeps.filter(fn(k) { k.finished >= 0 }).map(fn(k) { (k.name, k.mime, Bytes::from_array(k.data)) })
}

///|
/// The same, their names and how each was kept (where downloads go, where the person chose, the photo album).
pub fn Tester::kept_ways(self : Tester) -> Array[(String, @hostapi.KeepWay)] {
  self.fake.keeps.filter(fn(k) { k.finished >= 0 }).map(fn(k) { (k.name, k.way) })
}

///|
/// The device's gallery being read (@hostapi.GalleryRead), waited on until its photos are taken.
pub struct GalleryRead {
  priv host : @hostapi.GalleryRead
}

///|
/// The gallery's photos read (@hostapi.gallery_read): None where there is no gallery. A Tester's is what the test says
/// it is (Tester::gallery), read as a host reads it, from the next frame.
pub fn gallery_read() -> GalleryRead? {
  match @hostapi.gallery_read() {
    Some(h) => {
      outside_start(outside_gallery, h.id(), "the gallery read \{h.id()}")
      Some({ host: h })
    }
    None => None
  }
}

///|
/// A read of a Tester's gallery (its fake host's ga_read): its rows as a host writes them, the frame it was asked in
/// (read from the next on), whether it was let go of.
priv struct FakeGalleryRead {
  rows : String
  frame : Int
  mut ended : Bool
}

///|
/// The device's gallery from now on, as `photos` (Tester::new's has none, the app not let read one): all of it the app
/// may read, each read of it what it is when asked, from the next frame, as a host reads it off the app's thread.
pub fn Tester::gallery(self : Tester, photos : Array[@hostapi.GalleryPhoto]) -> Unit {
  self.fake.gallery = Some(photos.copy())
}

///|
/// A read of the fake host's gallery begun (its id, from 1; 0 none: no gallery given).
fn FakeHost::gallery_read(self : FakeHost) -> Int {
  match self.gallery {
    Some(photos) => {
      // (rows as a host writes them: id, src, added, modified, taken, video, a tab between)
      let rows = StringBuilder()
      for p in photos {
        rows.write_string(
          "\{p.id}\t\{p.src}\t\{p.added}\t\{p.modified}\t\{p.taken}\t\{if p.video { 1 } else { 0 }}\n",
        )
      }
      self.gallery_reads.push({ rows: rows.to_string(), frame: g().frame_no, ended: false })
      self.wants = true
      self.gallery_reads.length()
    }
    None => 0
  }
}

///|
/// How read `id` goes, as a host says it: 0 reading (until the frame after it was asked), 1 read, -1 let go of or none.
fn FakeHost::gallery_read_state(self : FakeHost, id : Int) -> Int {
  match self.gallery_reads.get(id - 1) {
    Some(r) if !r.ended => if g().frame_no <= r.frame { 0 } else { 1 }
    _ => -1
  }
}

///|
fn FakeHost::gallery_read_rows(self : FakeHost, id : Int) -> String {
  match self.gallery_reads.get(id - 1) {
    Some(r) if !r.ended => r.rows
    _ => ""
  }
}

///|
fn FakeHost::gallery_read_end(self : FakeHost, id : Int) -> Unit {
  match self.gallery_reads.get(id - 1) {
    Some(r) => r.ended = true
    None => ()
  }
}

///|
/// Its photos once read (empty: none, or not allowed), None while it reads; taken once (@hostapi.GalleryRead::photos).
pub fn GalleryRead::photos(self : GalleryRead) -> Array[@hostapi.GalleryPhoto]? {
  if !answer_here(outside_gallery, self.host.id()) {
    return None
  }
  let got = self.host.photos()
  if got is Some(_) {
    answer_taken(outside_gallery, self.host.id())
    outside_end(outside_gallery, self.host.id())
  }
  got
}

///|
/// A newer build downloaded and made ready (@hostapi.update_fetch): how it goes, `update_state`, and the host's word as
/// it changes (hostcall.mbt's outside_update). What the host says as it takes it (downloading, waiting) is read at
/// once, not on its event a frame or more later: until then it said nothing was under way, and what shows how it goes
/// went from nothing to 下载中 a frame late (the update dialog's bar gone and back, its sheet shorter and taller
/// again, 2026-10-28).
/// `delta`: "" or a delta to make the build of (@hostapi.update_fetch's).
pub fn update_fetch(
  url : String,
  sha256 : String,
  size : Double,
  name : String,
  now : Bool,
  delta : String,
) -> Unit {
  @hostapi.update_fetch(url, sha256, size, name, now, delta)
  update_told.set(@hostapi.update_state())
}

///|
/// The build made ready put in this app's place now (@hostapi.update_apply), as update_fetch.
pub fn update_apply(said : String) -> Unit {
  @hostapi.update_apply(said)
  update_told.set(@hostapi.update_state())
}

///|
/// What the app asked of the host's updates under a Tester ("fetch <name> <now>", with " delta <json>" where it gave
/// one; "apply"), in order.
pub fn Tester::update_asked(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  update_asked.copy()
}

///|
// kept across runs: a Tester's alone, emptied as one begins (update_told's put back with it)
let update_asked : Array[String] = []

///|
/// How an update goes (@hostapi.update_state's JSON), "" where there is none (a Tester's, a host that does not update
/// itself, nothing told yet): as the host last told it, a signal (each change the host's event, hostcall.mbt's
/// on_outside, which sets it), so what reads it follows it, a part kept as it was drawn or a computed of it alike.
pub fn update_state() -> String {
  update_told.get()
}

///|
/// The host tells how an update goes (@hostapi.update_state's JSON, `{"phase","percent","error"}`), as a host's event
/// does (hostcall.mbt's on_outside): what reads it follows it.
pub fn Tester::tells_update(self : Tester, state : String) -> Unit {
  ignore(self)
  update_told.set(state)
}

///|
/// How an update goes, said as a host would (@hostapi.update_state's JSON) where there is none to say it: a made-up
/// run's pictures of it (still.fail's fixtures).
pub fn update_told_as(state : String) -> Unit {
  update_told.set(state)
}

///|
/// How an update goes as the host last told it ("" before it has told anything: nothing under way).
// kept across runs: set by the host's events (a Tester's host tells none: Tester::tells_update), put back by each Tester
let update_told : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
