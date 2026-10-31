// Files dragged in from outside the app (Finder, Explorer) and let go on its window: the host says where they are held
// as they move and, once let go, the pick their reading is (macOS's MBView, Windows' drop target in win_files.h: their
// `mbui.drop` messages, {"type":"over","x","y"},
// {"type":"left"}, {"type":"drop","x","y","pick"}), taken as any message is, at a frame's start. A view asks where they
// are held now (files_held: what it would take them shows so) and takes each drop once (take_drop), its files read as
// a pick's are (Pick::files: a folder's by their way down, each folder itself named with a "/" at its end). Under a
// Tester: Tester::hold_files, Tester::drop_files.
//
// Words dragged in from outside (another app's text, a browser page's) are said only as they are let go, with what they
// say ({"type":"words","x","y","text"}: macOS's MBView): on a field (what a press there reaches) they go into it where
// they were let go, as a paste's words do, the field taking the focus; let go beside one on a box that is its field's
// (a composer's capsule), the view puts them in that field (Ctx::words_into); elsewhere nothing takes them. Under a
// Tester: Tester::drop_words.
//
// Files from the Finder (a host that knows where they are says so: {"type":"drop",…,"paths":[{"path","dir","size"}]})
// may be taken as where they are instead of read: by a box that takes them so (Ctx::paths_into: a chat's composer,
// naming them by the station they are on); let go on a field no such box holds, as their paths, a line each, as a
// Mac's text fields take files from the Finder (on a box that takes words for its field, Ctx::words_into, into that
// field). Either way they are not read. A drop of files is read only as a view takes it (take_drop); one that nothing
// takes in the frame it came is let go, unread, as that frame ends (drops_frame_end).

///|
/// Whether files can be dragged in from outside and let go on the window here: the hosts that say so (macOS's and
/// Windows': `mbui.drop`), what a setting of how they are taken is shown for.
pub fn takes_drops() -> Bool {
  let p = platform()
  p == 0 || p == 3
}

///|
/// A file or folder let go on the window from outside, where its host says where it is (the Finder's): its path,
/// whether it is a folder, how many bytes it has (a folder: 0).
pub(all) struct DroppedPath {
  path : String
  dir : Bool
  size : Double
} derive(Eq, Show, Debug)

///|
/// Files from outside let go where they are said by their paths (DroppedPath), the frame they came in: what holds where
/// they were let go (the hit target and what holds it), the target itself (a field, if one), where, the paths, the
/// frame's number, the pick their reading would be.
priv struct PathsLetGo {
  within : Array[Int]
  target : Int
  x : Double
  y : Double
  paths : Array[DroppedPath]
  frame : Int
  pick : Int
}

///|
/// Where files from outside are held over the window now, and the drops not taken yet (where each was let go, the
/// pick their reading is, by the host's number, the frame's number); words from outside let go on no field, the frame
/// they came in (the hit target and what holds it, what they say, the frame's number); files let go with their paths:
/// that frame's build may take them (Ctx::words_into, Ctx::paths_into, take_drop), none after it.
priv struct Dropping {
  mut held : (Double, Double)?
  drops : Array[(Double, Double, Int, Int)]
  mut words : (Array[Int], String, Int)?
  mut paths : PathsLetGo?
}

///|
let dropping : Dropping = { held: None, drops: [], words: None, paths: None }

///|
fn drop_reset() -> Unit {
  dropping.held = None
  dropping.drops.clear()
  dropping.words = None
  dropping.paths = None
}

///|
/// What was shown at (`x`, `y`), and what holds it: not a page merely underneath a dialog or popover. Boxes only
/// pointed at too (a chat's page): they can take what is let go there without taking a press from their contents.
fn drop_within(c : Ctx, x : Double, y : Double) -> Array[Int] {
  let k = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y)
  let within : Array[Int] = []
  c.holders(k, within)
  if k >= 0 {
    within.push(c.hit_ids[k])
  }
  within
}

///|
/// Words from outside let go at (`x`, `y`): on a field (what a press there reaches), put in where they were let go as
/// a paste's are (a step of their own to undo; as many as its paste_limit or more handed to the app as a paste's are,
/// EditorResult::pasted), the field taking the focus; elsewhere left for this frame's build (Ctx::words_into).
fn words_let_go(x : Double, y : Double, words : String) -> Unit {
  // (the window's tree as of when they are let go: what is there then, view_host.mbt)
  old_input_brought()
  let c = g()
  dropping.words = None
  let target = hit_in(c.hit_ids, c.hit_rects, x, y)
  match c.editors.get(target) {
    Some(st) => {
      c.focus_visible = false
      c.focus_moved(target)
      place_caret(st, x, y, h_now())
      st.text_input(text_paste, words, 0, 0, h_now())
    }
    None => dropping.words = Some((drop_within(c, x, y), words, c.frame_no))
  }
  // (taken as the frame begins: what reads what the hand did is built again in it, the field's words, a box that takes
  // them for its field)
  hand_event()
}

///|
/// Files of drop `pick` let go at (`x`, `y`) with their paths: left for this frame's build, a box that takes them by
/// their paths (Ctx::paths_into) or as words for its field (Ctx::words_into), or a view as files (take_drop); taken by
/// none, the field they were let go on puts their paths in as it ends (drops_frame_end).
fn paths_let_go(x : Double, y : Double, paths : Array[DroppedPath], pick : Int) -> Unit {
  old_input_brought()
  let c = g()
  let target = hit_in(c.hit_ids, c.hit_rects, x, y)
  dropping.paths = Some({ within: drop_within(c, x, y), target, x, y, paths, frame: c.frame_no, pick })
  hand_event()
}

///|
/// The paths let go this frame on box `id` (beside field `field`, or on it: one let go on another field is that field's),
/// not taken yet.
fn paths_on(c : Ctx, id : Int, field : Int) -> PathsLetGo? {
  match dropping.paths {
    Some(d) if d.frame == c.frame_no &&
      d.within.contains(id) &&
      (d.target == field || !c.editors.contains(d.target)) => Some(d)
    _ => None
  }
}

///|
/// Paths as words: a line each.
fn paths_words(paths : Array[DroppedPath]) -> String {
  paths.map(fn(p) { p.path }).join("\n")
}

///|
/// Words dragged in from outside and let go on box `id` this frame beside any field in it (one let go on a field the
/// field took, where it was let go): put in the field of editor `key` (built in this scope) at its caret, as a paste's,
/// the field taking the focus. For a box that is its field's, as a press on it is (a composer's capsule: its padding,
/// its buttons). A layer over the box takes the drop itself; the box underneath never sees it. Each is taken once.
/// Files let go there with their paths (one a box took by their paths not), their paths, a line each, where they were
/// let go on the field, else at its caret; then they are not read.
pub fn Ctx::words_into(self : Ctx, id : Int, key : String) -> Unit {
  hand_events_read()
  let field = self.id(key)
  guard self.editors.get(field) is Some(st) else { return }
  match dropping.words {
    Some((within, words, frame)) if frame == self.frame_no && within.contains(id) => {
      dropping.words = None
      st.text_input(text_paste, words, 0, 0, self.clock)
      self.focus_on(field)
    }
    _ =>
      match paths_on(self, id, field) {
        Some(d) => {
          dropping.paths = None
          drop_taken(d.pick)
          if d.target == field {
            place_caret(st, d.x, d.y, self.clock)
          }
          st.text_input(text_paste, paths_words(d.paths), 0, 0, self.clock)
          self.focus_on(field)
        }
        None => ()
      }
  }
}

///|
/// Files from outside let go this frame on box `id` (on it beside field `key`, its own, or on that field: one let go on
/// another field is that one's) with their paths, taken by their paths: then not read. A box that names them by where
/// they are (a chat's composer), asked before it takes words (Ctx::words_into). Each is taken once.
pub fn Ctx::paths_into(self : Ctx, id : Int, key : String) -> Array[DroppedPath]? {
  hand_events_read()
  guard paths_on(self, id, self.id(key)) is Some(d) else { return None }
  dropping.paths = None
  drop_taken(d.pick)
  Some(d.paths)
}

///|
/// Drop `pick` taken otherwise than as files (by their paths): let go, unread.
fn drop_taken(pick : Int) -> Unit {
  match dropping.drops.search_by(fn(d) { d.2 == pick }) {
    Some(i) => forget_drop(dropping.drops.remove(i).2)
    None => ()
  }
}

///|
/// As the frame ends (its builds over): files let go with their paths that no box took, put in as their paths on the
/// field they were let go on, as a paste's words, the field taking the focus (shown by the frame after); the drops none
/// took in it, let go, unread.
fn drops_frame_end(c : Ctx) -> Unit {
  if dropping.paths is Some(d) {
    dropping.paths = None
    match c.editors.get(d.target) {
      Some(st) if d.frame == c.frame_no => {
        c.focus_visible = false
        c.focus_moved(d.target)
        place_caret(st, d.x, d.y, c.clock)
        st.text_input(text_paste, paths_words(d.paths), 0, 0, c.clock)
        hand_event()
        c.owe_next()
      }
      _ => ()
    }
  }
  for d in dropping.drops {
    forget_drop(d.2)
  }
  dropping.drops.clear()
}

///|
/// A drop of files no view took: its reading never begun, or let go (a Tester's: nothing to let go).
fn forget_drop(id : Int) -> Unit {
  if fake.val is None {
    @hostapi.forget_dropped(id)
  }
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
      "over" => dropping.held = Some((num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val))
      "drop" => {
        dropping.held = None
        let id = num("pick").to_int()
        let (x, y) = (num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val)
        dropping.drops.push((x, y, id, g().frame_no))
        // (where they are, as the host says: taken so, they are not read)
        let paths = match v {
          Object(m) =>
            match m.get("paths") {
              Some(Array(ps)) =>
                ps.filter_map(fn(p) {
                  match p {
                    Object(o) =>
                      match (o.get("path"), o.get("dir"), o.get("size")) {
                        (Some(String(path)), dir, size) if path != "" =>
                          Some({
                            path,
                            dir: dir is Some(True),
                            size: if size is Some(Number(n, ..)) { n } else { 0.0 },
                          })
                        _ => None
                      }
                    _ => None
                  }
                })
              _ => []
            }
          _ => []
        }
        if !paths.is_empty() {
          paths_let_go(x, y, paths, id)
        }
      }
      "words" => {
        dropping.held = None
        match v {
          Object(m) =>
            match m.get("text") {
              Some(String(s)) if s != "" => words_let_go(num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val, s)
              _ => ()
            }
          _ => ()
        }
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
/// The oldest drop of files from outside not taken yet, in the frame it came, let go where `over` says (by default
/// anywhere): where they were let go, and the pick their reading is, begun now (its `files` None until they are
/// read). Each is taken once, as files: not by its paths too (Ctx::paths_into). Those let go on a field with their
/// paths are the field's (or a box's that takes them for it), never taken so. One no view takes as it came is let go,
/// unread, as its frame ends.
pub fn take_drop(over? : (Double, Double) -> Bool = fn(_, _) { true }) -> (Double, Double, Pick)? {
  let c = g()
  let on_field = fn(id) { dropping.paths is Some(d) && d.pick == id && c.editors.contains(d.target) }
  guard dropping.drops.search_by(fn(d) { d.3 == c.frame_no && !on_field(d.2) && over(d.0, d.1) }) is Some(i) else {
    return None
  }
  let (x, y, id, _) = dropping.drops.remove(i)
  if dropping.paths is Some(d) && d.pick == id {
    dropping.paths = None
  }
  let p : Pick = match fake.val {
    // (a Tester's: the ask Tester::drop_files made, from 1)
    Some(_) => { hosts: [], got: [], fake: id - 1 }
    None => { hosts: [@hostapi.dropped_pick(id)], got: [None], fake: -1 }
  }
  p.wait("files dropped")
  Some((x, y, p))
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
/// the window at (x, y), as a host says, with their `paths` where it says them (the Finder's: one for each of `files`,
/// a folder as that file says, its size that file's bytes); read by the frame after the one that takes the drop, as a
/// pick is.
pub fn Tester::drop_files(
  self : Tester,
  x : Double,
  y : Double,
  files : Array[(String, Bytes)],
  paths? : Array[String] = [],
) -> Unit {
  self.picks(files)
  self.fake.pick_asks.push({ kind: Files, frame: g().frame_no, taken: false })
  let id = self.fake.pick_asks.length()
  let m : Map[String, Json] = {
    "type": Json::string("drop"),
    "x": Json::number(x),
    "y": Json::number(y),
    "pick": Json::number(id.to_double()),
  }
  if !paths.is_empty() {
    m["paths"] = Json::array(
      paths.mapi(fn(i, p) {
        let (name, bytes) = if i < files.length() { files[i] } else { ("", b"") }
        let o : Map[String, Json] = {
          "path": Json::string(p),
          "dir": Json::boolean(name.has_suffix("/")),
          "size": Json::number(bytes.length().to_double()),
        }
        Json::object(o)
      }),
    )
  }
  self.post("mbui.drop", Json::object(m).stringify())
}

///|
/// Words from outside (another app's text) let go on the window at (`x`, `y`), as a host says; taken by the frame that
/// takes the message.
pub fn Tester::drop_words(self : Tester, x : Double, y : Double, words : String) -> Unit {
  let m : Map[String, Json] = {
    "type": Json::string("words"),
    "x": Json::number(x),
    "y": Json::number(y),
    "text": Json::string(words),
  }
  self.post("mbui.drop", Json::object(m).stringify())
}
