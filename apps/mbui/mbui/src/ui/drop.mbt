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
// Files let go where words are taken go in as their paths, a line each, as a Mac's text fields take files from the
// Finder (a host that knows them says them: {"type":"drop",…,"paths"}): then they are not read. A drop of files is
// read only as a view takes it (take_drop), and one that nothing takes in the frame it came is let go, unread.

///|
/// Whether files can be dragged in from outside and let go on the window here: the hosts that say so (macOS's and
/// Windows': `mbui.drop`), what a setting of how they are taken is shown for.
pub fn takes_drops() -> Bool {
  let p = platform()
  p == 0 || p == 3
}

///|
/// Where files from outside are held over the window now, and the drops not taken yet (where each was let go, the
/// pick their reading is, by the host's number, the frame's number); words from outside let go on no field, the frame
/// they came in (the hit target and what holds it, what they say, the frame's number, the drop they are the paths of:
/// 0 none): that frame's build may take them (Ctx::words_into, take_drop), none after it.
priv struct Dropping {
  mut held : (Double, Double)?
  drops : Array[(Double, Double, Int, Int)]
  mut words : (Array[Int], String, Int, Int)?
}

///|
let dropping : Dropping = { held: None, drops: [], words: None }

///|
fn drop_reset() -> Unit {
  dropping.held = None
  dropping.drops.clear()
  dropping.words = None
}

///|
/// Words from outside let go at (`x`, `y`) (the paths of drop `files`, 0 none): on a field (what a press there
/// reaches), put in where they were let go as a paste's are (a step of their own to undo; as many as its paste_limit
/// or more handed to the app as a paste's are, EditorResult::pasted), the field taking the focus: whether one did;
/// elsewhere left for this frame's build (Ctx::words_into).
fn words_let_go(x : Double, y : Double, words : String, files? : Int = 0) -> Bool {
  let c = g()
  dropping.words = None
  let target = hit_in(c.hit_ids, c.hit_rects, x, y)
  // (taken as the frame begins: what reads what the hand did is built again in it, the field's words, a box that takes
  // them for its field)
  hand_event()
  match c.editors.get(target) {
    Some(st) => {
      c.focus_visible = false
      c.focus = target
      place_caret(st, x, y, h_now())
      st.text_input(text_paste, words, 0, 0, h_now())
      true
    }
    None => {
      // What was shown at the drop, and what holds it: not a page merely underneath a dialog or popover. Include
      // boxes only pointed at, too (a chat's page); they can receive words without taking a press from their contents.
      let k = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y)
      let within : Array[Int] = []
      c.holders(k, within)
      if k >= 0 {
        within.push(c.hit_ids[k])
      }
      dropping.words = Some((within, words, c.frame_no, files))
      false
    }
  }
}

///|
/// Words dragged in from outside and let go on box `id` this frame beside any field in it (one let go on a field the
/// field took, where it was let go): put in the field of editor `key` (built in this scope) at its caret, as a paste's,
/// the field taking the focus. For a box that is its field's, as a press on it is (a composer's capsule: its padding,
/// its buttons). A layer over the box takes the drop itself; the box underneath never sees it. Each is taken once.
pub fn Ctx::words_into(self : Ctx, id : Int, key : String) -> Unit {
  hand_events_read()
  guard dropping.words is Some((within, words, frame, files)) && frame == self.frame_no else { return }
  guard within.contains(id) else { return }
  let field = self.id(key)
  guard self.editors.get(field) is Some(st) else { return }
  dropping.words = None
  // (files taken as their paths: their drop let go, unread)
  if files != 0 {
    match dropping.drops.search_by(fn(d) { d.2 == files }) {
      Some(i) => forget_drop(dropping.drops.remove(i).2)
      None => ()
    }
  }
  st.text_input(text_paste, words, 0, 0, self.clock)
  self.focus_on(field)
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
      "over" => dropping.held = Some((num("x"), num("y")))
      "drop" => {
        dropping.held = None
        let id = num("pick").to_int()
        let (x, y) = (num("x"), num("y"))
        // (their paths, as the host says them: a field takes them so, unread)
        let paths = match v {
          Object(m) =>
            match m.get("paths") {
              Some(Array(ps)) =>
                ps.filter_map(fn(p) {
                  match p {
                    String(s) if s != "" => Some(s)
                    _ => None
                  }
                })
              _ => []
            }
          _ => []
        }
        if !paths.is_empty() && words_let_go(x, y, paths.join("\n"), files=id) {
          forget_drop(id)
        } else {
          dropping.drops.push((x, y, id, g().frame_no))
        }
      }
      "words" => {
        dropping.held = None
        match v {
          Object(m) =>
            match m.get("text") {
              Some(String(s)) if s != "" => words_let_go(num("x"), num("y"), s) |> ignore
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
/// The oldest drop of files from outside not taken yet, in the frame it came: where they were let go, and the pick
/// their reading is, begun now (its `files` None until they are read). Each is taken once; one of a frame before, which
/// no view took as it came, is let go unread.
pub fn take_drop() -> (Double, Double, Pick)? {
  let frame = g().frame_no
  while dropping.drops.length() > 0 && dropping.drops[0].3 != frame {
    forget_drop(dropping.drops.remove(0).2)
  }
  if dropping.drops.is_empty() {
    return None
  }
  let (x, y, id, _) = dropping.drops.remove(0)
  // (taken as files: not as their paths too)
  if dropping.words is Some((_, _, _, files)) && files == id {
    dropping.words = None
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
/// the window at (x, y), as a host says, with their `paths` where it says them (the Finder's); read by the frame after
/// the one that takes the drop, as a pick is.
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
    m["paths"] = Json::array(paths.map(Json::string))
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
