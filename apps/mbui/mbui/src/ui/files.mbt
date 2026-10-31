// The system's pickers and the files the app keeps on the device (as @hostapi's pick.mbt and keep.mbt have them), through
// the framework, so that under a Tester the system is the test's: its pickers give what the test said (Tester::picks)
// and what the app keeps is kept by the test (Tester::kept), each answer at the next frame, as a host's event comes at
// a frame's boundary.

///|
/// An ask of the system's pickers under way (@hostapi.Pick): one of the host's, or (photos of the gallery picked
/// together: pick_photos) one for each, answered as one once all of them are, in their order.
pub struct Pick {
  priv hosts : Array[@hostapi.Pick]
  /// what each of `hosts` answered (taken from the host as it does)
  priv got : Array[Array[@hostapi.Picked]?]
  priv fake : Int
}

///|
priv struct FakePick {
  kind : @hostapi.PickKind
  /// the frame it was asked in: answered from the next on
  frame : Int
  mut taken : Bool
}

///|
/// Asks the system for files of `kind` (@hostapi.pick; `hold`: one too big to be read whole may be held by the host):
/// None when this host cannot. Under a Tester, what the test said the pickers give (Tester::picks), from the next frame.
pub fn pick(kind : @hostapi.PickKind, hold? : Bool = false) -> Pick? {
  match fake.val {
    Some(f) => {
      f.pick_asks.push({ kind, frame: g().frame_no, taken: false })
      f.wants = true
      let p : Pick = { hosts: [], got: [], fake: f.pick_asks.length() - 1 }
      p.wait("a pick")
      Some(p)
    }
    None =>
      match @hostapi.pick(kind, hold~) {
        Some(h) => {
          let p : Pick = { hosts: [h], got: [None], fake: -1 }
          p.wait("a pick")
          Some(p)
        }
        None => None
      }
  }
}

///|
/// Waited on until the system answers and the answer is taken (hostcall.mbt's outside): each ask of the host's by its
/// id as the host's event names it (outside_pick), a Tester's by its ask's place, from 1.
fn Pick::wait(self : Pick, what : String) -> Unit {
  if self.hosts.is_empty() {
    outside_start(outside_pick, self.fake + 1, what + " \{self.fake + 1}")
  }
  for h in self.hosts {
    outside_start(outside_pick, h.id(), what + " \{h.id()}")
  }
}

///|
/// Photos of the gallery (`srcs`) read whole, as one pick of them in that order (@hostapi.pick_photo, each): None
/// where the host has no gallery (a Tester's has none).
pub fn pick_photos(srcs : Array[String]) -> Pick? {
  match fake.val {
    Some(_) => None
    None => {
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
        let p : Pick = { hosts, got: hosts.map(fn(_) { None }), fake: -1 }
        p.wait("a gallery photo read")
        Some(p)
      }
    }
  }
}

///|
/// What was picked, once the system has answered (empty: called off); None while it asks. Taken once.
pub fn Pick::files(self : Pick) -> Array[@hostapi.Picked]? {
  if self.hosts.is_empty() {
    answer_here(outside_pick, self.fake + 1) |> ignore
    let got = self.faked()
    if got is Some(_) {
      outside_end(outside_pick, self.fake + 1)
    }
    return got
  }
  for i, h in self.hosts {
    if self.got[i] is None && answer_here(outside_pick, h.id()) {
      match h.files() {
        Some(files) => {
          self.got[i] = Some(files)
          answer_taken(outside_pick, h.id())
          outside_end(outside_pick, h.id())
        }
        None => ()
      }
    }
  }
  let out = []
  for got in self.got {
    match got {
      Some(files) => out.push_iter(files.iter())
      None => return None
    }
  }
  // (taken: asked again, nothing)
  for i in 0..<self.got.length() {
    self.got[i] = Some([])
  }
  Some(out)
}

///|
/// A Tester's answer: what the test said the pickers give, from the frame after it was asked.
fn Pick::faked(self : Pick) -> Array[@hostapi.Picked]? {
  match fake.val {
    Some(f) if self.fake >= 0 && self.fake < f.pick_asks.length() => {
      let a = f.pick_asks[self.fake]
      if a.taken {
        Some([])
      } else if g().frame_no <= a.frame {
        None
      } else {
        a.taken = true
        Some(f.picks.copy())
      }
    }
    _ => Some([])
  }
}

///|
/// What the system's pickers give from now on, whatever is asked (as MBUI_PICK_FILES does a host's): `files` (their
/// names and bytes); none: the person calls the picker off.
pub fn Tester::picks(self : Tester, files : Array[(String, Bytes)]) -> Unit {
  self.fake.picks.clear()
  for f in files {
    self.fake.picks.push({ name: f.0, bytes: f.1, held: 0, size: f.1.length().to_double(), src: "" })
  }
}

///|
/// What the app asked of the system's pickers, oldest first.
pub fn Tester::pick_asks(self : Tester) -> Array[@hostapi.PickKind] {
  self.fake.pick_asks.map(fn(a) { a.kind })
}

///|
/// A file being kept on the device (@hostapi.Keep).
pub struct Keep {
  priv host : @hostapi.Keep?
  priv fake : Int
}

///|
priv struct FakeKeep {
  name : String
  mime : String
  way : @hostapi.KeepWay
  data : Array[Byte]
  /// the frame it was finished in (-1: not yet): kept from the next on; let go of
  mut finished : Int
  mut ended : Bool
}

///|
/// A file named `name` (`mime`, "" when unknown) to keep on the device, its bytes to come (@hostapi.keep_begin): None
/// when this host keeps none.
pub fn keep_begin(name : String, mime : String, way? : @hostapi.KeepWay = Downloads) -> Keep? {
  match fake.val {
    Some(f) => {
      f.keeps.push({ name, mime, way, data: [], finished: -1, ended: false })
      Some({ host: None, fake: f.keeps.length() - 1 })
    }
    None =>
      match @hostapi.keep_begin(name, mime, way~) {
        Some(k) => Some({ host: Some(k), fake: -1 })
        None => None
      }
  }
}

///|
fn Keep::faked(self : Keep) -> FakeKeep? {
  match fake.val {
    Some(f) if self.fake >= 0 && self.fake < f.keeps.length() => Some(f.keeps[self.fake])
    _ => None
  }
}

///|
/// The next of its bytes; false when they could not be written.
pub fn Keep::append(self : Keep, data : Bytes) -> Bool {
  match self.host {
    Some(k) => k.append(data)
    None =>
      match self.faked() {
        Some(k) if k.finished < 0 && !k.ended => {
          for b in data {
            k.data.push(b)
          }
          true
        }
        _ => false
      }
  }
}

///|
/// All of it is here: the host puts it in its place.
pub fn Keep::finish(self : Keep) -> Unit {
  match self.host {
    Some(k) => k.finish()
    None =>
      match self.faked() {
        Some(k) if k.finished < 0 => {
          k.finished = g().frame_no
          match fake.val {
            Some(f) => f.wants = true
            None => ()
          }
        }
        _ => ()
      }
  }
}

///|
/// How it stands: under a Tester, kept from the frame after it was finished, where the system keeps downloads
/// ("Download/" and its name; in MBUI_DOWNLOADS_DIR, as a scripted run's host keeps there, its path).
pub fn Keep::kept(self : Keep) -> @hostapi.Kept {
  match self.host {
    Some(k) => k.kept()
    None =>
      match self.faked() {
        Some(k) if k.ended && k.finished < 0 => CalledOff
        Some(k) if k.finished >= 0 && g().frame_no > k.finished =>
          KeptAt(
            match env("MBUI_DOWNLOADS_DIR") {
              "" => "Download/" + k.name
              dir => dir + "/" + k.name
            },
          )
        Some(_) => Keeping
        None => Failed
      }
  }
}

///|
/// Let go of: one not finished is called off.
pub fn Keep::end(self : Keep) -> Unit {
  match self.host {
    Some(k) => k.end()
    None =>
      match self.faked() {
        Some(k) => k.ended = true
        None => ()
      }
  }
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
      let rows = StringBuilder::new()
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
/// again, 2026-10-28). Under a Tester, kept as asked (Tester::update_asked).
pub fn update_fetch(url : String, sha256 : String, size : Double, name : String, now : Bool) -> Unit {
  match fake.val {
    Some(_) => update_asked.push("fetch \{name} \{now}")
    None => {
      @hostapi.update_fetch(url, sha256, size, name, now)
      update_told.set(@hostapi.update_state())
    }
  }
}

///|
/// The build made ready put in this app's place now (@hostapi.update_apply), as update_fetch. Under a Tester, kept as
/// asked.
pub fn update_apply(said : String) -> Unit {
  match fake.val {
    Some(_) => update_asked.push("apply")
    None => {
      @hostapi.update_apply(said)
      update_told.set(@hostapi.update_state())
    }
  }
}

///|
/// What the app asked of the host's updates under a Tester ("fetch <name> <now>", "apply"), in order.
pub fn Tester::update_asked(self : Tester) -> Array[String] {
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
// kept across runs: a real host's alone (a Tester's host tells no update), set by the host's events
let update_told : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })
