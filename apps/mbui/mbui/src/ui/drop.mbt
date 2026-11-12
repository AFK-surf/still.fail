// Files dragged in from outside the app (Finder, Explorer) and let go on its window: the host says where they are held
// as they move and, once let go, the pick their reading is (macOS's MBView, Windows' drop target in win_files.h: their
// `mbui.drop` messages, {"type":"over","x","y"},
// {"type":"left"}, {"type":"drop","x","y","pick"}). A box follows them as the host says them, outside any build
// (Ctx::on_files): told where they are held over it, and taking them as they are let go on it, their files read as a
// pick's are (Pick::files: a folder's by their way down, each folder itself named with a "/" at its end). Under a
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
// field). Either way they are not read. A drop of files is read only as a box takes it (Ctx::on_files); one that
// nothing takes as it comes is let go, unread: at once, or, let go with its paths, as the frame that could take them so
// ends (drops_frame_end).

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
#derive(Eq, Debug)
pub(all) struct DroppedPath {
  path : String
  dir : Bool
  size : Double
}

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
/// Words from outside let go on no field, the frame they came in (the hit target and what holds it, what they say, the
/// frame's number); files let go with their paths that no box took as files: that frame's build may take them
/// (Ctx::words_into, Ctx::paths_into), none after it.
priv struct Dropping {
  mut words : (Array[Int], String, Int)?
  mut paths : PathsLetGo?
}

///|
let dropping : Dropping = { words: None, paths: None }

///|
fn drop_reset() -> Unit {
  tree_drops.clear()
  files_on.clear()
  files_on_held.val = 0
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
/// What of the window's tree did with what was let go from outside at a point (tree_words_at, tree_paths_at).
#derive(Eq)
priv enum TreeDropped {
  /// a node of it took it
  Took
  /// what of it is drawn there is under a modal layer it is not in: nobody's
  Shut
  /// none of it took it: the old view's ways, as before there was a tree
  Not
}

///|
/// Words from outside let go at (`x`, `y`) on the window's tree: on a field of it, in where they were let go; beside one
/// on a node of it, or what holds that, that takes them for it (words_into), there at once at that field's caret.
fn tree_words_at(c : Ctx, x : Double, y : Double, words : String) -> TreeDropped {
  match tree_drop_at(x, y) {
    Some((Some(st), _)) => {
      place_caret_at(st, x, y, h_now())
      tree_words_into(c, st, words)
      Took
    }
    Some((None, Some(at))) =>
      match tree_drops_on(at, fn(d) { d.words is Some(_) }) {
        Some({ words: Some(f), .. }) => {
          tree_words_into(c, f.st, words)
          Took
        }
        _ => Not
      }
    Some((_, None)) => Shut
    None => Not
  }
}

///|
/// Files of drop `pick` let go at (`x`, `y`) with their paths on the window's tree: taken at once, not read, by the
/// innermost of the node there and what holds it that takes them by their paths (paths_into: on its field, or beside
/// any); on a field, else, their paths in where they were let go; beside any on one that takes words for its field
/// (words_into), their paths there at its caret. Taken or shut, the drop let go unread.
fn tree_paths_at(c : Ctx, x : Double, y : Double, paths : Array[DroppedPath], pick : Int) -> TreeDropped {
  guard !paths.is_empty() else {
    return match tree_drop_at(x, y) {
      Some((_, None)) => {
        forget_drop(pick)
        Shut
      }
      _ => Not
    }
  }
  let took = match tree_drop_at(x, y) {
    Some((_, None)) => Shut
    Some((on, Some(at))) => {
      let on_field = fn(f : Field) { match on { Some(st) => physical_equal(st, f.st); None => true } }
      match tree_drops_on(at, fn(d) { d.paths is Some((f, _, takes)) && on_field(f) && takes() }) {
        Some({ paths: Some((_, take, _)), .. }) => {
          take(paths)
          Took
        }
        _ =>
          match on {
            Some(st) => {
              place_caret_at(st, x, y, h_now())
              tree_words_into(c, st, paths_words(paths))
              Took
            }
            None =>
              match tree_drops_on(at, fn(d) { d.words is Some(_) }) {
                Some({ words: Some(f), .. }) => {
                  tree_words_into(c, f.st, paths_words(paths))
                  Took
                }
                _ => Not
              }
          }
      }
    }
    None => Not
  }
  if took != Not {
    forget_drop(pick)
  }
  took
}

///|
/// Words from outside let go at (`x`, `y`): the window's tree's first (tree_words_at); where none of it took them, on an
/// old view's field (what a press there reaches), put in where they were let go as a paste's are (a step of their own
/// to undo; as many as its paste_limit or more handed to the app as a paste's are, EditorResult::pasted), the field
/// taking the focus; elsewhere left for this frame's build (Ctx::words_into).
fn words_let_go(x : Double, y : Double, words : String) -> Unit {
  // (the window's tree as of when they are let go: what is there then, view_host.mbt)
  old_input_brought()
  let c = g()
  dropping.words = None
  if tree_words_at(c, x, y, words) is Not {
    let target = hit_in(c.hit_ids, c.hit_rects, x, y)
    match c.editors.get(target) {
      Some(st) => {
        c.focus_visible = false
        c.focus_moved(target)
        place_caret_at(st, x, y, h_now())
        st.text_input(text_paste, words, 0, 0, h_now())
      }
      None => dropping.words = Some((drop_within(c, x, y), words, c.frame_no))
    }
  }
  // (taken as the frame begins: what reads what the hand did is built again in it, the field's words, a box that takes
  // them for its field)
  hand_event()
}

///|
/// Files of drop `pick` let go at (`x`, `y`) with their paths, none of the window's tree taking them and no old view's
/// box taking them as files (Ctx::on_files): left for this frame's build, a box that takes them by their paths
/// (Ctx::paths_into) or as words for its field (Ctx::words_into); taken by none, the field they were let go on puts
/// their paths in as it ends (drops_frame_end).
fn paths_let_go(x : Double, y : Double, paths : Array[DroppedPath], pick : Int) -> Unit {
  let c = g()
  let target = hit_in(c.hit_ids, c.hit_rects, x, y)
  dropping.paths = Some({ within: drop_within(c, x, y), target, x, y, paths, frame: c.frame_no, pick })
  hand_event()
}

///|
/// What a node of the window's tree takes of what is let go on it from outside beside any field in it: words for field
/// `words` (words_into), files with their paths for `paths`' field and its taker (paths_into).
priv struct TreeDrops {
  mut words : Field?
  mut paths : (Field, (Array[DroppedPath]) -> Unit, () -> Bool)?
}

///|
/// What each node of the tree's takes of what is let go on it (TreeDrops), by its node.
// kept across runs: each let go with its node; a run's start clears it (drop_reset)
let tree_drops : Map[@view.NodeId, TreeDrops] = Map([])

///|
/// What node `v` takes, made as it is first said, let go with it.
fn tree_drops_of(v : @view.View) -> TreeDrops {
  let id = v.id()
  match tree_drops.get(id) {
    Some(d) => d
    None => {
      let d : TreeDrops = { words: None, paths: None }
      tree_drops[id] = d
      v.owns(fn() { tree_drops.remove(id) }) |> ignore
      d
    }
  }
}

///|
/// What of the window's tree something let go at (`x`, `y`) in the window lands on (@view.Tree::drop_at): the node drawn
/// there, whether or not it takes a press (a page's words: what holds them asked after them, tree_drops_on), not one
/// hosting an old view; the field's state where it is a field, and the node. Some with no node: the tree's, taking
/// nothing there now (under a modal layer it is not in). None: not the tree's (an old view's, where nothing of
/// the tree's is over it, or nothing's).
fn tree_drop_at(x : Double, y : Double) -> (EditorState?, @view.NodeId?)? {
  guard view_app.val is Some(tree) else { return None }
  match tree.drop_at(x, y) {
    Some(OnNode(id)) => Some((tree_fields.get(id).map(fn(tf) { tf.st }), Some(id)))
    Some(Shut(_)) => Some((None, None))
    Some(OnOld(_)) | None => None
  }
}

///|
/// The innermost of node `at` of the window's tree and what holds it whose drops `takes` says take what is let go
/// there; None: none of them.
fn tree_drops_on(at : @view.NodeId, takes : (TreeDrops) -> Bool) -> TreeDrops? {
  guard view_app.val is Some(tree) else { return None }
  let mut v = tree.view_of(at)
  while v is Some(n) {
    match tree_drops.get(n.id()) {
      Some(d) if takes(d) => return Some(d)
      _ => ()
    }
    v = n.parent()
  }
  None
}

///|
/// Words let go in the field of the window's tree `st` holds (beside it, on what takes them for it: at its caret; on it,
/// where they were let go): put in there as a paste's, the field taking the focus (Ctx::words_into's).
fn tree_words_into(c : Ctx, st : EditorState, words : String) -> Unit {
  st.text_input(text_paste, words, 0, 0, h_now())
  c.focus_visible = false
  c.focus_field(Field::{ st, })
  tree_field_redraw()
}

///|
/// Words from outside let go on node `v` or what it holds beside any field (one let go on a field the field took, where
/// it was let go): put in `field` at its caret, as a paste's, at the moment they are let go, the field taking the focus,
/// as a press on `v` is its field's (a composer's capsule: its padding, its buttons); files let go there with their paths
/// that nothing takes by their paths (paths_into), their paths so, a line each, not read. What holds a node of the tree's
/// takes what it holds does not (the innermost first); an old view's box, Ctx::words_into. `v`.
pub fn words_into(v : @view.View, field : Field) -> @view.View {
  tree_drops_of(v).words = Some(field)
  v
}

///|
/// Files from outside let go with their paths (the Finder's) on node `v` or what it holds, on `field` or beside any field
/// (one let go on another field is that field's): given to `take` at the moment they are let go, as where they are,
/// not read (a chat's composer naming them by the station they are on). The innermost of what takes them first; an old
/// view's box, Ctx::paths_into. Only while `takes` says so, asked as they are let go (a chat's page takes them by where
/// they are only where this machine is a station): where it does not, they are what holds it's, or its words
/// (words_into: their paths, a line each), as were this not said. `v`.
pub fn paths_into(
  v : @view.View,
  field : Field,
  take : (Array[DroppedPath]) -> Unit,
  takes? : () -> Bool = fn() { true },
) -> @view.View {
  tree_drops_of(v).paths = Some((field, take, takes))
  v
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
          forget_drop(d.pick)
          if d.target == field {
            place_caret_at(st, d.x, d.y, self.clock)
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
  forget_drop(d.pick)
  Some(d.paths)
}

///|
/// As the frame ends (its builds over): files let go with their paths that no box took, put in as their paths on the
/// field they were let go on, as a paste's words, the field taking the focus (shown by the frame after); either way
/// let go, unread.
fn drops_frame_end(c : Ctx) -> Unit {
  if dropping.paths is Some(d) {
    dropping.paths = None
    forget_drop(d.pick)
    match c.editors.get(d.target) {
      Some(st) if d.frame == c.frame_no => {
        c.focus_visible = false
        c.focus_moved(d.target)
        place_caret_at(st, d.x, d.y, c.clock)
        st.text_input(text_paste, paths_words(d.paths), 0, 0, c.clock)
        hand_event()
        c.owe_next()
      }
      _ => ()
    }
  }
}

///|
/// A drop of files no box took: its reading never begun, or let go.
fn forget_drop(id : Int) -> Unit {
  @hostapi.forget_dropped(id)
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
      "over" => files_held_at(Some((num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val)))
      "drop" => {
        files_held_at(None)
        let id = num("pick").to_int()
        let (x, y) = (num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val)
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
        // (the window's tree's first, by their paths (tree_paths_at); where none of it took them, taken as they are let
        // go by what of an old view takes them there, Ctx::on_files: not those let go on a field with their paths, which
        // are the field's)
        old_input_brought()
        let c = g()
        if tree_paths_at(c, x, y, paths, id) is Not {
          let on_field = !paths.is_empty() && c.editors.contains(hit_in(c.hit_ids, c.hit_rects, x, y))
          match (if on_field { None } else { files_take_at(x, y) }) {
            Some(take) => take(Pick::waits([@hostapi.dropped_pick(id)], "files dropped"))
            // (taken by none as files: left to what takes them by their paths, else let go now)
            None =>
              if paths.is_empty() {
                forget_drop(id)
              } else {
                paths_let_go(x, y, paths, id)
              }
          }
        } else {
          hand_event()
        }
      }
      "words" => {
        files_held_at(None)
        match v {
          Object(m) =>
            match m.get("text") {
              Some(String(s)) if s != "" => words_let_go(num("x") / window_zoom_drawn.val, num("y") / window_zoom_drawn.val, s)
              _ => ()
            }
          _ => ()
        }
      }
      _ => files_held_at(None)
    }
  })
}

///|
/// What takes files from outside over a box (Ctx::on_files): told where they are held over it, asked as they are let
/// go on it.
priv struct FilesOn {
  held : ((Double, Double)?) -> Unit
  take : (Double, Double) -> ((Pick) -> Unit)?
}

///|
/// What takes files from outside over each box (Ctx::on_files), by its id: what its last build said.
// kept across runs: said as each box is built, let go with its page (Ctx::forget); a run's start clears it (drop_reset)
let files_on : Map[Int, FilesOn] = Map([])

///|
/// The box that takes them that files from outside are held over now (Ctx::on_files; 0 none): told as they leave it.
// kept across runs: as the host says where they are held; a run's start clears it (drop_reset)
let files_on_held : Ref[Int] = Ref(0)

///|
/// Files from outside over box `id` (on it or on what it holds; the innermost of those that say so), followed as the
/// host says them, in its message, outside any build, as the last frame drew what is there: `held` told where they are
/// held over it (None: gone from over it: taken away, let go, or over another), `take` asked as they are let go on it
/// (not on a field, with their paths: those are the field's) whether it takes them there. `Some(f)` takes them: `f`
/// given the pick their reading is, begun now, and no build sees the drop (Ctx::paths_into); None leaves
/// them to what is further out, then to the frame's build as ever. Said as the box is built (what takes them is what
/// the last build said).
pub fn Ctx::on_files(
  self : Ctx,
  id : Int,
  held~ : ((Double, Double)?) -> Unit,
  take~ : (Double, Double) -> ((Pick) -> Unit)?,
) -> Unit {
  if id == 0 {
    return
  }
  files_on[id] = { held, take }
  self.own(id)
}

///|
/// What is drawn at (x, y) that takes files from outside (Ctx::on_files), the innermost first.
fn files_on_at(x : Double, y : Double) -> Array[Int] {
  let within = drop_within(g(), x, y)
  let out = []
  for i = within.length() - 1; i >= 0; i = i - 1 {
    if files_on.contains(within[i]) {
      out.push(within[i])
    }
  }
  out
}

///|
/// Files from outside held over the window at `at` (None: taken away or let go): told to the box that takes them they
/// are over (Ctx::on_files), and to the one they left.
fn files_held_at(at : (Double, Double)?) -> Unit {
  let id = match at {
    Some((x, y)) => files_on_at(x, y).get(0).unwrap_or(0)
    None => 0
  }
  let was = files_on_held.val
  files_on_held.val = id
  if was != 0 && was != id {
    match files_on.get(was) {
      Some(f) => (f.held)(None)
      None => ()
    }
  }
  match (files_on.get(id), at) {
    (Some(f), Some(p)) => (f.held)(Some(p))
    _ => ()
  }
}

///|
/// Files from outside let go at (x, y): what takes them there (Ctx::on_files), the innermost that does; None: none.
fn files_take_at(x : Double, y : Double) -> ((Pick) -> Unit)? {
  for id in files_on_at(x, y) {
    match files_on.get(id) {
      Some(f) =>
        match (f.take)(x, y) {
          Some(take) => return Some(take)
          None => ()
        }
      None => ()
    }
  }
  None
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
/// a folder as that file says, its size that file's bytes); taken as the frame that takes the message begins
/// (Ctx::on_files), what they hold told by the host's event after the message, at its moment (FakeHost::due), as a
/// pick's is.
pub fn Tester::drop_files(
  self : Tester,
  x : Double,
  y : Double,
  files : Array[(String, Bytes)],
  paths? : Array[String] = [],
) -> Unit {
  self.picks(files)
  self.fake.pick_asks.push({ kind: Files, said: false, taken: false })
  let id = self.fake.pick_asks.length()
  // (what they hold told after the message, at its moment; where the test answers the pickers itself, as it says:
  // Tester::pick_answer, the host's reading of them taking a while)
  let f = self.fake
  if !f.picks_by_hand {
    f.due(f.time, "files dropped", fn() { fake_pick_said(f, id) })
  }
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
