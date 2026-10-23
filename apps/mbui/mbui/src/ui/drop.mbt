// Files dragged in from outside the app (Finder) and let go on its window: the host says where they are held as they
// move and, once let go, the pick their reading is (macOS's MBView: its `mbui.drop` messages, {"type":"over","x","y"},
// {"type":"left"}, {"type":"drop","x","y","pick"}), taken as any message is, at a frame's start. A view asks where they
// are held now (files_held: what it would take them shows so) and takes each drop once (take_drop), its files read as
// a pick's are (Pick::files: a folder's by their way down, each folder itself named with a "/" at its end). Under a
// Tester: Tester::hold_files, Tester::drop_files.

///|
/// Where files from outside are held over the window now, and the drops not taken yet (where each was let go, its pick).
priv struct Dropping {
  mut held : (Double, Double)?
  drops : Array[(Double, Double, Pick)]
}

///|
let dropping : Dropping = { held: None, drops: [] }

///|
fn drop_reset() -> Unit {
  dropping.held = None
  dropping.drops.clear()
}

///|
fn init {
  on_message("mbui.drop", fn(json, _) {
    let v = @json.parse(json) catch { _ => Json::null() }
    let num = fn(key : String) {
      match v {
        Object(m) =>
          match m.get(key) {
            Some(Number(n, ..)) => n
            _ => 0.0
          }
        _ => 0.0
      }
    }
    let kind = match v {
      Object(m) =>
        match m.get("type") {
          Some(String(s)) => s
          _ => ""
        }
      _ => ""
    }
    match kind {
      "over" => dropping.held = Some((num("x"), num("y")))
      "drop" => {
        dropping.held = None
        let id = num("pick").to_int()
        let p : Pick = match fake.val {
          // (a Tester's: the ask Tester::drop_files made, from 1)
          Some(_) => { host: None, fake: id - 1 }
          None => { host: Some(@hostapi.dropped_pick(id)), fake: -1 }
        }
        p.wait("files dropped")
        dropping.drops.push((num("x"), num("y"), p))
      }
      _ => dropping.held = None
    }
  })
}

///|
/// Where files from outside the app are held over the window now (x, y), None when none are.
pub fn files_held() -> (Double, Double)? {
  dropping.held
}

///|
/// The oldest drop of files from outside not taken yet: where they were let go, and the pick their reading is (its
/// `files` None until they are read). Each is taken once.
pub fn take_drop() -> (Double, Double, Pick)? {
  if dropping.drops.is_empty() {
    None
  } else {
    Some(dropping.drops.remove(0))
  }
}

///|
/// Files from outside held over the window at (x, y), as a host says while they are dragged (None: taken away).
pub fn Tester::hold_files(self : Tester, at : (Double, Double)?) -> Unit {
  match at {
    Some((x, y)) => self.post("mbui.drop", "{\"type\":\"over\",\"x\":\{x},\"y\":\{y}}")
    None => self.post("mbui.drop", "{\"type\":\"left\"}")
  }
}

///|
/// `files` (their names, a folder's by their way down and a folder itself with a "/" at its end, and bytes) let go on
/// the window at (x, y), as a host says; read by the frame after the one that takes the drop, as a pick is.
pub fn Tester::drop_files(self : Tester, x : Double, y : Double, files : Array[(String, Bytes)]) -> Unit {
  self.picks(files)
  self.fake.pick_asks.push({ kind: Files, frame: g().frame_no, taken: false })
  let id = self.fake.pick_asks.length()
  self.post("mbui.drop", "{\"type\":\"drop\",\"x\":\{x},\"y\":\{y},\"pick\":\{id}}")
}
