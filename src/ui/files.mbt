// The system's pickers and the files the app keeps on the device (as @host's pick.mbt and keep.mbt have them), through
// the framework, so that under a Tester the system is the test's: its pickers give what the test said (Tester::picks)
// and what the app keeps is kept by the test (Tester::kept), each answer at the next frame, as a host's event comes at
// a frame's boundary.

///|
/// An ask of the system's pickers under way (@host.Pick).
pub struct Pick {
  priv host : @host.Pick?
  priv fake : Int
}

///|
priv struct FakePick {
  kind : @host.PickKind
  /// the frame it was asked in: answered from the next on
  frame : Int
  mut taken : Bool
}

///|
/// Asks the system for files of `kind` (@host.pick): None when this host cannot. Under a Tester, what the test said the
/// pickers give (Tester::picks), from the next frame.
pub fn pick(kind : @host.PickKind) -> Pick? {
  match fake.val {
    Some(f) => {
      f.pick_asks.push({ kind, frame: g().frame_no, taken: false })
      f.wants = true
      Some({ host: None, fake: f.pick_asks.length() - 1 })
    }
    None =>
      match @host.pick(kind) {
        Some(p) => Some({ host: Some(p), fake: -1 })
        None => None
      }
  }
}

///|
/// A photo of the gallery read whole, as a pick of it (@host.pick_photo): None where the host has no gallery (a
/// Tester's has none).
pub fn pick_photo(src : String) -> Pick? {
  match fake.val {
    Some(_) => None
    None =>
      match @host.pick_photo(src) {
        Some(p) => Some({ host: Some(p), fake: -1 })
        None => None
      }
  }
}

///|
/// What was picked, once the system has answered (empty: called off); None while it asks. Taken once.
pub fn Pick::files(self : Pick) -> Array[@host.Picked]? {
  match self.host {
    Some(p) => p.files()
    None =>
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
}

///|
/// What the system's pickers give from now on, whatever is asked (as MBUI_PICK_FILES does a host's): `files` (their
/// names and bytes); none: the person calls the picker off.
pub fn Tester::picks(self : Tester, files : Array[(String, Bytes)]) -> Unit {
  self.fake.picks.clear()
  for f in files {
    self.fake.picks.push({ name: f.0, bytes: f.1 })
  }
}

///|
/// What the app asked of the system's pickers, oldest first.
pub fn Tester::pick_asks(self : Tester) -> Array[@host.PickKind] {
  self.fake.pick_asks.map(fn(a) { a.kind })
}

///|
/// A file being kept on the device (@host.Keep).
pub struct Keep {
  priv host : @host.Keep?
  priv fake : Int
}

///|
priv struct FakeKeep {
  name : String
  mime : String
  way : @host.KeepWay
  data : Array[Byte]
  /// the frame it was finished in (-1: not yet): kept from the next on; let go of
  mut finished : Int
  mut ended : Bool
}

///|
/// A file named `name` (`mime`, "" when unknown) to keep on the device, its bytes to come (@host.keep_begin): None
/// when this host keeps none.
pub fn keep_begin(name : String, mime : String, way? : @host.KeepWay = Downloads) -> Keep? {
  match fake.val {
    Some(f) => {
      f.keeps.push({ name, mime, way, data: [], finished: -1, ended: false })
      Some({ host: None, fake: f.keeps.length() - 1 })
    }
    None =>
      match @host.keep_begin(name, mime, way~) {
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
/// ("Download/" and its name).
pub fn Keep::kept(self : Keep) -> @host.Kept {
  match self.host {
    Some(k) => k.kept()
    None =>
      match self.faked() {
        Some(k) if k.ended && k.finished < 0 => CalledOff
        Some(k) if k.finished >= 0 && g().frame_no > k.finished => KeptAt("Download/" + k.name)
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
/// `data`, all here, kept as a file named `name` (@host.keep): None when this host keeps none.
pub fn keep(name : String, mime : String, data : Bytes, way? : @host.KeepWay = Downloads) -> Keep? {
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
