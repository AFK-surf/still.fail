// A list's row kept as the nodes its build made (docs/incremental.md, the way there's 5): a row built and laid out is a
// value, its nodes as laid out and what its build said of the frame besides them. It is built under a watch of its own
// (what it reads of signals and of time, the frames' clock and the moments it shows changing at, followed by it alone:
// kept_part.mbt's KeptClock), and is not built again while nothing it read changed, nothing it was built from changed
// (what built its list read nothing that changed: the frame was not built anew for it, nodes_run's `fresh`) and its
// list gives it the same room: its nodes are put back into the frame's where its build would make them, moved to where
// it is laid now, and what it said of the frame that its nodes do not hold is said again there (said.mbt's build
// lists, what it marked used this frame, what it read of the layout, read back as it read it; what takes the focus,
// what is read out, its corners, what scrolls, its words, its looks and what it showed of what moves are its nodes':
// docs/retained.md, the way there's 1).
// Its layout is kept with it; what lays out its list places it, and it is painted as what is built is.
//
// What is said of the frame in no way that is said again here (a layer it opened over the page, how a list stands, a
// list, a field or a native view of its own: kept_census) builds it every frame. Where a Tester runs, each pass of a
// frame's build that kept a row is built once more keeping none, and the two must build the same nodes, laid out the
// same, and say the same of the frame (rows_check_begin): every test holds every row kept.

///|
/// A list's row kept as its nodes: what its build made and said, where it is in the frame's nodes, what it was built
/// from (its list's room and what built the list), and whether it may be kept at all (`ok`; `why` not).
priv struct RowNodes {
  /// its list's id, its item
  list : Int
  item : Int
  watch : @signals.Watch
  /// the pass of a frame's build it was last laid in (NodesRun's `pass`)
  laid_pass : Ref[Int]
  /// its nodes, out of the frame's from as each frame is built till they are put back (`in_pool`: in the frame's, from
  /// `base`, `n` of them); spare nodes of the frame's while they are there
  store : Array[Node]
  mut n : Int
  mut base : Int
  mut in_pool : Bool
  /// where its root was as its build laid it (`said_base`: the frame's nodes it said what it said of the frame of)
  mut said_base : Int
  /// how tall its slot is
  mut h : Double
  /// what it was built from: its list's width, rows, scope, theme's direction, layer, picking; the layout's epoch and
  /// scale; whether it was read out
  mut iw : Double
  mut count : Int
  mut seed : Int
  mut owner : Int
  mut bones : Int64
  mut sel : Bool
  mut layer : Int
  mut direction : Direction
  mut epoch : Int
  mut scale : Double
  mut reads_out : Bool
  mut lit_all : Bool
  /// whether it was built in a list whose rows show only what they read (Ctx::list's `rows_read`), and the theme it
  /// was built in there (its colours and sizes, what it may have taken of them as it was built)
  mut reads_all : Bool
  /// a part put where it is by what is made once (made_island): what the frame built anew does not build it
  mut own : Bool
  mut theme : Theme?
  mut ok : Bool
  mut why : String
  /// what its build said of the frame: said.mbt's build lists; what it marked used this frame
  said : Array[&SaidAgain]
  marks : Array[Int]
  /// what it read of how lists stand (Ctx::list_info_as, read back)
  info : Array[(String, () -> Bool)]
  used : Array[() -> Unit]
  again : Array[(Int) -> Unit]
  /// what it read of the layout as it was built, and what it read (Ctx::laid_rect, laid_size, left_out): read back once
  /// the frame is laid out, kept or built
  laid : Array[LaidRead]
  /// what of its nodes is worked out once the frame is laid out, as its build left it (how opaque each is, its corners:
  /// what is left out of a row with no room for it, corners.mbt's `Inner`), for that to be worked out from again
  laid_looks : Array[(Double, Double, FixedArray[Double]?, Bool)]
  /// how its nodes hold each other as built, from its first (-1: none of its own: what holds its root, a list's rows), and
  /// the lists it holds by their ids (a part's), laid out each frame
  links : Array[(Int, Int, Int, Int)]
  lists : Array[Int]
  /// a part's: what its caller builds it from (Ctx::kept_part's `key`), and whether it is read out
  mut key : String
  mut read : Bool
  /// the frame and the moment it was last built (said where it parts from it built whole: rows_check_end)
  mut built_frame : Int
  mut built_at : Double
  /// the frame it was last laid in
  mut shown : Int
  /// the row or part whose build put it among its own nodes (an island in an island), if one did: told as it is, as
  /// though it had read what it read itself
  holder : Ref[RowNodes?]
  /// the parts kept as their nodes among its own, where among them (from its first): their nodes theirs, out of its
  /// own as it is taken out of the frame's and put back with them as it is put back; and those put among them by the
  /// build going on, and where it began
  mut inner : Array[(RowNodes, Int)]
  inner_now : Array[RowNodes]
  mut building_at : Int
}

///|
/// The rows kept, by list and item.
// kept across runs: let go of as a run begins (nodes_forget) and as each frame ends for those it did not lay
let kept_nodes : Map[(Int, Int), RowNodes] = {}

///|
/// Nodes no row nor the frame holds, for a row's to be swapped with.
// kept across runs: only spares
let spare_nodes : Array[Node] = []

///|
/// The rows as this frame lays them: whether what built their lists may have built them otherwise (`fresh`: the frame
/// built anew, none kept); whether what a row read changed since it was built (`told`: the next frame lays out again);
/// the row being built (none: what is built is no row's); how many rows this frame kept and built; whether rows are
/// kept at all (`on`: a Tester's frame built whole after one that kept rows keeps none).
priv struct NodesRun {
  mut fresh : Bool
  /// what is no signal yet came for this frame: the hand's discrete events (a press, a key), an event from outside (a
  /// message, a host's answer, a test's draw: outside_came), a test's step; what reads them reads them as it is built,
  /// and not all of it reads them as signals yet: a part kept whatever else the frame built anew (`own`) is built anew
  /// for them all the same
  mut evented : Bool
  /// where what came is the hand's alone and went to one old view (view_host.mbt), that one's part (its id): a part kept
  /// for another is no part it came to (-1: it came to all)
  mut evented_only : Int
  /// built keeping none at all (a run's start, a Tester's build to compare with): a list whose rows show only what
  /// they read builds them anew too
  mut whole : Bool
  /// a part being built for what it read, or as it is new (Ctx::part_nodes): its lists' rows built anew
  mut part_fresh : Bool
  mut told : Bool
  /// (the row told last, list and item: what says why a frame is asked for, Tester::assert_idle)
  mut told_by : (Int, Int)
  /// the passes of frames' builds so far, and the frames' starts (rows_frame_start, Ctx::rows_detach): a row told in
  /// one before it is laid in it reads anew as it is
  mut pass : Int
  mut building : RowNodes?
  mut aside : Int
  mut kept : Int
  mut built : Int
  /// how many rows of lists that show only what they read were built since the run began (a test's:
  /// Tester::rows_read_built)
  mut built_read : Int
  kept_at : Array[(Int, Int)]
  mut on : Bool
}

///|
// kept across runs: put back as a run begins (nodes_forget), its counts as each frame does
let nodes_run : NodesRun = {
  fresh: true,
  evented: false,
  evented_only: -1,
  whole: true,
  part_fresh: false,
  told: false,
  told_by: (0, 0),
  pass: 0,
  building: None,
  aside: 0,
  kept: 0,
  built: 0,
  built_read: 0,
  kept_at: [],
  on: true,
}

///|
/// Whether rows are kept as their nodes this frame.
fn Ctx::nodes_keep(self : Ctx) -> Bool {
  nodes_run.on && !nodes_run.fresh && !inst_owners.on && !self.lit_every
}

///|
/// Whether the rows of list `st` are kept as their nodes this frame: what built it built it from what had not changed
/// (ListState's `fresh`: the frame built anew, or the part it is in built again for what it read, builds them anew).
fn Ctx::nodes_keep_in(self : Ctx, st : ListState) -> Bool {
  nodes_run.on && !st.fresh && !inst_owners.on && !self.lit_every
}

///|
/// What is built now said something of itself that a package keeps outside ui's frame, by what is built (the motion
/// package's entries, by node): a list's row being built is built every frame (kept_nodes.mbt's head).
pub fn built_aside(why? : String = "") -> Unit {
  nodes_run.aside = nodes_run.aside + 1
  aside_why.val = why
}

///|
/// What was said last of what is built now that a package keeps outside ui's frame (built_aside), where it said: why
/// a row or a part is built every frame, said by rows_unkept.
// kept across runs: written as it is said
let aside_why : Ref[String] = Ref("")

///|
/// What the build marked used this frame (`f` marks it so again: a picture, a timer held, what asks to be lit, a
/// package's motion kept by its key): a list's row being built marks it again each frame it is kept.
pub fn built_used(f : () -> Unit) -> Unit {
  match nodes_run.building {
    Some(rn) => rn.used.push(f)
    None => ()
  }
}

///|
/// What the build said of a node that a package keeps by its node (the motion package's entries): `f` says it again of
/// the node `by` on from it, each frame a list's row being built is kept (its nodes put back elsewhere among the
/// frame's: kept_nodes.mbt's head).
pub fn built_again(f : (Int) -> Unit) -> Unit {
  match nodes_run.building {
    Some(rn) => rn.again.push(f)
    None => ()
  }
}

///|
/// As each pass of a frame's build begins (frame_build): the rows' nodes out of the frame's, their places in it taken
/// by spares, for the build to make its own; a row kept is put back where its list lays it (Ctx::row_laid). As the
/// frame begins, nothing built is a row's.
fn Ctx::rows_detach(self : Ctx) -> Unit {
  nodes_run.building = None
  nodes_run.pass = nodes_run.pass + 1
  for _, rn in kept_nodes {
    if !rn.in_pool {
      continue
    }
    // (built anew, none kept: a row's nodes taken out of the frame's all the same, for its build to make again in
    // them where its list lays it (Ctx::row_laid), as laid out before where it is the same, whatever was built before
    // it in the frame: left where they were, a node more or less built before them (a bar's in a motion) put another
    // node in each of their places, all of them laid out anew; a part's left there, for it to make again in its place.
    // But a row that shows only what it read, unless none is kept at all)
    if nodes_run.whole || (nodes_run.fresh && !rn.reads_all && (!rn.own || evented_for(rn.list))) {
      if rn.item >= 0 {
        self.row_nodes_out(rn)
      }
      rn.in_pool = false
      rn.n = 0
      rn.ok = false
      continue
    }
    self.row_nodes_out(rn)
    rn.in_pool = false
  }
}

///|
/// Row or part `rn`'s nodes out of the frame's, into its own (`store`), their places taken by those it held, or by
/// spares.
fn Ctx::row_nodes_out(self : Ctx, rn : RowNodes) -> Unit {
  for j in 0..<rn.n {
    let i = rn.base + j
    let o = self.nodes[i]
    if j < rn.store.length() {
      self.nodes[i] = rn.store[j]
      rn.store[j] = o
    } else {
      self.nodes[i] = match spare_nodes.pop() {
        Some(s) => s
        None => Node::new()
      }
      rn.store.push(o)
    }
    // (where each is, as who it is is found by it: Ctx::node_known)
    self.nodes[i].slot = i
    o.slot = -1
  }
  inner_out(rn)
}

///|
/// The parts kept among row or part `rn`'s nodes (an island in an island), out of its own (`store`) into theirs, spares
/// in their places: each one's own, never two's.
fn inner_out(rn : RowNodes) -> Unit {
  for p in rn.inner {
    let (i, off) = p
    for j in 0..<i.n {
      if j >= i.store.length() {
        i.store.push(
          match spare_nodes.pop() {
            Some(s) => s
            None => Node::new()
          },
        )
      }
      let o = rn.store[off + j]
      rn.store[off + j] = i.store[j]
      i.store[j] = o
    }
    inner_out(i)
  }
}

///|
/// The parts kept among the nodes of row or part `rn`, put back from `at` among the frame's: theirs in their places,
/// where they are now, laid this frame.
fn Ctx::inner_in(self : Ctx, rn : RowNodes, at : Int) -> Unit {
  for p in rn.inner {
    let (i, off) = p
    for j in 0..<i.n {
      let k = at + off + j
      let o = self.nodes[k]
      self.nodes[k] = i.store[j]
      i.store[j] = o
      self.nodes[k].slot = k
      o.slot = -1
    }
    i.base = at + off
    i.in_pool = false
    i.shown = self.frame_no
    i.laid_pass.val = nodes_run.pass
    self.inner_in(i, at + off)
  }
}

///|
/// Row `rn`'s own nodes (`store`: those it was last built in) put in the frame's where the next are made, for its
/// build to make again; those there its own instead.
fn Ctx::row_nodes_lent(self : Ctx, rn : RowNodes) -> Unit {
  let c0 = self.count
  let n = rn.store.length()
  while self.nodes.length() < c0 + n {
    self.nodes.push(
      match spare_nodes.pop() {
        Some(s) => s
        None => Node::new()
      },
    )
  }
  for j in 0..<n {
    let o = self.nodes[c0 + j]
    self.nodes[c0 + j] = rn.store[j]
    rn.store[j] = o
    self.nodes[c0 + j].slot = c0 + j
    o.slot = -1
  }
}

///|
/// The frame is built (parts_frame_end): the rows it did not lay let go, what they read no longer followed, their nodes
/// spares.
fn rows_nodes_end(c : Ctx) -> Unit {
  if kept_nodes.is_empty() {
    return
  }
  let gone = []
  for key, rn in kept_nodes {
    if rn.shown != c.frame_no {
      gone.push(key)
    }
  }
  for key in gone {
    match kept_nodes.get(key) {
      Some(rn) => {
        rn.watch.stop()
        // (its nodes not in the frame's: its own, at the end of the frame's now, each found there by who it is as what
        // it was is built again (a page covered a while, back: Ctx::node_known), so far as there is room, else spares;
        // in it, the frame's, and what it holds of the frame's)
        for o in rn.store {
          if c.nodes.length() < 2 * known_made.val + known_room {
            o.slot = c.nodes.length()
            c.nodes.push(o)
          } else {
            o.slot = -1
            spare_nodes.push(o)
          }
        }
      }
      None => ()
    }
    kept_nodes.remove(key)
  }
}

///|
/// Put back as a run begins (reset_globals): no row kept, what they read let go.
fn nodes_forget() -> Unit {
  for _, rn in kept_nodes {
    rn.watch.stop()
  }
  kept_nodes.clear()
  spare_nodes.clear()
  known_nodes.clear()
  nodes_run.fresh = true
  nodes_run.whole = true
  nodes_run.told = false
  nodes_run.building = None
  nodes_run.kept = 0
  nodes_run.built = 0
  nodes_run.built_read = 0
  nodes_run.kept_at.clear()
  nodes_run.on = true
}

///|
/// As a frame is built (frame_body): no row kept nor built yet, none laid in it (what a row read told from here on,
/// before it is laid in the frame, it reads anew as it is: what came for the frame taken, row_nodes_new).
fn rows_frame_start() -> Unit {
  nodes_run.pass = nodes_run.pass + 1
  nodes_run.kept = 0
  nodes_run.built = 0
  nodes_run.kept_at.clear()
}

///|
/// A row of list `list`, item `item`, not built yet.
fn row_nodes_new(list : Int, item : Int) -> RowNodes {
  // (the pass it was last laid in: told in a pass before it is laid in it, it reads anew as it is)
  let laid_pass = Ref(-1)
  let holder : Ref[RowNodes?] = Ref(None)
  let watch = @signals.watch(fn() {
    // (among another's nodes: that one built again for it, it with it)
    match holder.val {
      Some(o) => o.watch.touch()
      None => ()
    }
    if frame_running.val && frame_built.val && laid_pass.val != nodes_run.pass {
      return
    }
    nodes_run.told = true
    nodes_run.told_by = (list, item)
    // (between frames: one owed; in one, the next asked for as it ends: on_frame)
    if !frame_running.val {
      h_frame_owed()
    }
  })
  {
    list,
    item,
    watch,
    laid_pass,
    store: [],
    n: 0,
    base: 0,
    in_pool: false,
    said_base: 0,
    h: 0.0,
    iw: 0.0,
    count: 0,
    seed: 0,
    owner: 0,
    bones: 0L,
    sel: false,
    layer: 0,
    direction: Ltr,
    epoch: 0,
    scale: 0.0,
    reads_out: false,
    lit_all: false,
    reads_all: false,
    own: false,
    theme: None,
    ok: false,
    why: "",
    said: [],
    marks: [],
    info: [],
    used: [],
    again: [],
    laid: [],
    laid_looks: [],
    links: [],
    lists: [],
    key: "",
    read: false,
    built_frame: -1,
    built_at: -1.0,
    shown: -1,
    holder,
    inner: [],
    inner_now: [],
    building_at: 0,
  }
}

///|
/// How far each of what a build may say of the frame in no way said again here stands (kept_census_names, in order):
/// one that grew as a row was built makes it a row built every frame.
fn Ctx::kept_census(self : Ctx, into : Array[Int]) -> Unit {
  into.clear()
  into.push(self.layers.length())
  into.push(self.layers_opened.length())
  into.push(self.cover_asks.length())
  into.push(self.place_reads.length())
  into.push(self.row_reads.length())
  into.push(self.words_reads.length())
  into.push(self.words_shape_reads.length())
  into.push(self.shown_watch.length())
  into.push(self.move_runs.length())
  into.push(self.asked_actions.length())
  into.push(self.told.length())
  into.push(self.shots.length())
  into.push(self.dismissals.length())
  into.push(self.layer_return.length())
  into.push(self.lists.length())
  into.push(self.editors.length())
  into.push(self.owned.length())
  into.push(self.groups.length())
  into.push(self.covers.length())
  into.push(self.springs.length())
  into.push(native_nodes.length())
  into.push(picture_at.length())
  into.push(stream_nodes.length())
  into.push(dr.overlay.length())
  into.push(dr.raised.length())
  into.push(dr.scrims.length())
  into.push(desk.next_sels.length())
  into.push(nodes_run.aside)
}

///|
/// What kept_census counts, by name, in its order.
// kept across runs: a table, never written
let kept_census_names : Array[String] = [
  "a layer opened", "a layer opened as laid out",
  "a cover", "a list's place read back", "a row read back", "words read back",
  "words' shape read back", "what shows across read back",
  "a move", "an action asked", "what it tells outside", "a shot", "what dismisses",
  "where the focus returns", "a list of its own", "a field of its own", "what it owns", "a focus group", "a cover",
  "a spring", "a native view", "a picture at a rect", "a stream", "what is drawn over", "what is raised", "a scrim",
  "words to pick", "what a package keeps of it",
]

///|
/// Row `k` of list node `li` (`st`) laid at (`ix`, `y`), `iw` wide (Ctx::place_list): kept where nothing it shows
/// changed (kept_nodes.mbt's head), else built and laid out there, under its own watch; its node and how tall its slot
/// is.
fn Ctx::row_laid(
  self : Ctx,
  li : Int,
  st : ListState,
  k : Int,
  ix : Double,
  y : Double,
  iw : Double,
) -> (Int, Double) {
  let nan = 0.0 / 0.0
  // (a row in a row's build: what holds it is built every frame, kept_census)
  if nodes_run.building is Some(_) {
    let r = self.build_row(li, st, k)
    return (r, self.row_slot(r, self.layout(r, ix, y, iw, nan)))
  }
  let key = (self.nodes[li].id, k)
  let rn = match kept_nodes.get(key) {
    Some(rn) => rn
    None => {
      let rn = row_nodes_new(key.0, key.1)
      kept_nodes[key] = rn
      rn
    }
  }
  rn.shown = self.frame_no
  rn.laid_pass.val = nodes_run.pass
  if self.nodes_keep_in(st) &&
    rn.ok &&
    !rn.in_pool &&
    rn.n > 0 &&
    !rn.watch.is_stale() &&
    rn.iw == iw &&
    rn.reads_all == st.rows_read &&
    // (one that shows only what it read kept however its list is built: but not in another theme, light or dark, the
    // one its list is built in the same while nothing of it changed: what is no signal of its own)
    (!st.rows_read || (rn.theme is Some(th) && physical_equal(th, st.theme))) &&
    (st.rows_read || rn.count == st.count) &&
    rn.seed == st.seed &&
    rn.owner == st.owner &&
    rn.bones == st.bones &&
    rn.sel == st.sel &&
    rn.layer == st.layer &&
    rn.direction == st.direction &&
    rn.epoch == self.epoch &&
    rn.scale == self.scale &&
    rn.reads_out == self.reads_out &&
    rn.lit_all == self.lit_all {
    // (what is worked out again of it as it is put back, its places by its size and what it marks used, read as its
    // build read it: followed by its watch, not by what lays out its list)
    return @signals.untracked(fn() { self.row_splice(li, rn, ix, y) })
  }
  // built: in the nodes it was built in before, where its build makes them (what lays them out keeps what it worked
  // out of them where they are the same); what it says of the frame from where each list stands
  self.row_nodes_lent(rn)
  let b = self.nodes_begin(rn)
  nodes_run.building = Some(rn)
  let (r, h) = rn.watch.read(fn() {
    let r = self.build_row(li, st, k)
    (r, self.row_slot(r, self.layout(r, ix, y, iw, nan)))
  })
  nodes_run.building = None
  rn.h = h
  rn.iw = iw
  rn.count = st.count
  rn.reads_all = st.rows_read
  rn.theme = if st.rows_read { Some(st.theme) } else { None }
  rn.seed = st.seed
  rn.owner = st.owner
  rn.bones = st.bones
  rn.sel = st.sel
  rn.layer = st.layer
  rn.direction = st.direction
  self.nodes_end(rn, r, b, part=false)
  (r, h)
}

///|
/// Where what the frame's builds say stood as a row or a part began being built (Ctx::nodes_begin): what it said is
/// taken from there as it is over (Ctx::nodes_end).
priv struct NodesBegun {
  census : Array[Int]
  info : Int
  drawn : Int
}

///|
/// Row or part `rn` about to be built: where what the frame's builds say stands.
fn Ctx::nodes_begin(self : Ctx, rn : RowNodes) -> NodesBegun {
  let census : Array[Int] = []
  self.kept_census(census)
  self.build_marks(rn.marks)
  rn.used.clear()
  rn.again.clear()
  rn.laid.clear()
  rn.inner_now.clear()
  rn.building_at = self.count
  {
    census,
    info: self.info_reads.length(),
    drawn: dr.entries.length(),
  }
}

///|
/// Row or part `rn` built, its nodes from `r` (`b`: what the builds said stood as it began): its nodes and what it
/// said of the frame kept with it, and whether it may be kept (it said nothing of the frame that is not said again, its
/// nodes all its own and none of a kind built each frame; a part may hold lists, laid out each frame).
fn Ctx::nodes_end(self : Ctx, rn : RowNodes, r : Int, b : NodesBegun, part~ : Bool) -> Unit {
  nodes_run.built = nodes_run.built + 1
  if !part && rn.reads_all {
    nodes_run.built_read = nodes_run.built_read + 1
  }
  rn.built_frame = self.frame_no
  rn.built_at = self.clock
  rn.base = r
  rn.said_base = r
  rn.n = self.count - r
  rn.in_pool = true
  // (the parts kept among its nodes, where among them)
  rn.inner = rn.inner_now.map(fn(i) { (i, i.base - r) })
  rn.inner_now.clear()
  rn.epoch = self.epoch
  rn.scale = self.scale
  rn.reads_out = self.reads_out
  rn.lit_all = self.lit_all
  self.build_take(rn.marks, rn.said, cut=false)
  rn.info.clear()
  for j in b.info..<self.info_reads.length() {
    rn.info.push(self.info_reads[j])
  }
  let census_after : Array[Int] = []
  self.kept_census(census_after)
  rn.why = ""
  for j in 0..<census_after.length() {
    if rn.why == "" && census_after[j] != b.census[j] && !(part && kept_census_names[j] == "a list of its own") {
      rn.why = if kept_census_names[j] == "what a package keeps of it" && aside_why.val != "" {
        aside_why.val
      } else {
        kept_census_names[j]
      }
    }
  }
  if rn.why == "" {
    rn.why = self.row_nodes_why(r, rn.n, part~)
  }
  // (an entry of draw.mbt's of a node not its own: what holds it drawn otherwise for it)
  for j in b.drawn..<dr.entries.length() {
    let e = dr.entries[j]
    if rn.why == "" && (e.node < r || e.node >= r + rn.n || (e.keep_rel >= 0 && e.keep_rel < r)) {
      rn.why = "a look of what holds it"
    }
  }
  rn.ok = rn.why == ""
  rn.laid_looks.clear()
  rn.links.clear()
  rn.lists.clear()
  if rn.ok {
    for j in 0..<rn.n {
      let nd = self.nodes[r + j]
      rn.laid_looks.push((nd.opacity, nd.radius, nd.radii.map(fn(a) { a.copy() }), nd.corners_worked))
      // (how its nodes hold each other as it built them, from its first: what holds its root is where it is put back;
      // a list's rows are its layout's, none as built)
      let at = fn(i : Int) { if i >= r && i < r + rn.n { i - r } else { -1 } }
      rn.links.push((at(nd.parent), at(nd.first), at(nd.last), at(nd.next)))
      if nd.kind == kind_list {
        rn.lists.push(nd.id)
      }
    }
  }
}

///|
/// Why the `n` nodes from `r` (a row or a part just built) may not be kept: one held elsewhere, or of a kind built each
/// frame (a list of a row's own: a part lays its lists out each frame; a native view, a pager's page, a layer, a
/// shot); "" none. (What is placed by the clock (Ctx::moved_by: a page sliding) is kept with what moves it, its node's
/// own, placed again as each frame is laid out and painted. A field is kept as the rest: what changes what it holds is
/// an event, which builds the frame anew, and one with the focus is built each frame: Ctx::editor.)
fn Ctx::row_nodes_why(self : Ctx, r : Int, n : Int, part~ : Bool) -> String {
  for j in 0..<n {
    let nd = self.nodes[r + j]
    if j > 0 && (nd.parent < r || nd.parent >= r + n) {
      return "a node of it held elsewhere"
    }
    if nd.kind == kind_list && !part {
      return "a list of its own"
    }
    if nd.kind == kind_scroll {
      return "what scrolls in it"
    }
    if nd.kind == kind_native {
      return "a native view"
    }
    if nd.pager != 0 || nd.kind == kind_page {
      return "a pager's page"
    }
    if nd.portal || nd.shot {
      return "a layer"
    }
  }
  ""
}

///|
/// Row `rn` kept: its nodes put back into the frame's where its build would make them (under list node `li`), moved to
/// where its list lays it now (`ix`, `y`), what its build said of the frame said again; its node and how tall its slot
/// is.
fn Ctx::row_splice(self : Ctx, li : Int, rn : RowNodes, ix : Double, y : Double) -> (Int, Double) {
  let c0 = self.nodes_put_back(rn, li)
  // where its list lays it now: placed as laying it out there places it, from what its layout worked out (Ctx::replace,
  // as layout.mbt's commit places what it did not lay out anew), on the same numbers as building it there
  self.replace(c0, ix, y)
  self.nodes_said_again(rn)
  (c0, rn.h)
}

///|
/// The nodes of row or part `rn` put back into the frame's at its end, as its build made them, its root under node
/// `parent` after what is there (as Ctx::alloc puts one): how they hold each other as built, from where they are now,
/// and what the layout works out of them as their build left it. Their first.
fn Ctx::nodes_put_back(self : Ctx, rn : RowNodes, parent : Int) -> Int {
  let c0 = self.count
  let n = rn.n
  while self.nodes.length() < c0 + n {
    self.nodes.push(
      match spare_nodes.pop() {
        Some(s) => s
        None => Node::new()
      },
    )
  }
  for j in 0..<n {
    let o = self.nodes[c0 + j]
    self.nodes[c0 + j] = rn.store[j]
    rn.store[j] = o
    self.nodes[c0 + j].slot = c0 + j
    o.slot = -1
  }
  self.inner_in(rn, c0)
  let at = fn(k : Int) { if k >= 0 { c0 + k } else { -1 } }
  for j in 0..<n {
    let nd = self.nodes[c0 + j]
    let (opacity, radius, radii, worked) = rn.laid_looks[j]
    nd.opacity = opacity
    nd.radius = radius
    nd.radii = radii.map(fn(a) { a.copy() })
    nd.corners_worked = worked
    let (up, first, last, next) = rn.links[j]
    nd.parent = if j == 0 { parent } else { at(up) }
    nd.first = at(first)
    nd.last = at(last)
    nd.next = at(next)
  }
  let p = self.nodes[parent]
  if p.last >= 0 {
    self.nodes[p.last].next = c0
  } else {
    p.first = c0
  }
  p.last = c0
  // (counted among what its parent holds with no id, as made: what is built after it there is who it was)
  if n > 0 && self.nodes[c0].keyless {
    p.kids = p.kids + 1
  }
  self.count = c0 + n
  rn.base = c0
  rn.in_pool = true
  c0
}

///|
/// What row or part `rn`'s build said of the frame, said again of its nodes where they are now.
fn Ctx::nodes_said_again(self : Ctx, rn : RowNodes) -> Unit {
  let by = rn.base - rn.said_base
  self.say_again(rn.said, { ..unmoved, by: by })
  for f in rn.used {
    f()
  }
  for f in rn.again {
    f(by)
  }
  for l in rn.laid {
    self.laid_said_again(l)
  }
  // (the lists it holds built this frame, as built, from nothing changed: laid out from where they stand, their rows
  // kept, Ctx::place_list)
  for id in rn.lists {
    match self.lists.get(id) {
      Some(st) => {
        st.built = self.frame_no
        st.fresh = false
      }
      None => ()
    }
  }
  for r in rn.info {
    self.info_reads.push(r)
  }
  self.moves_said_again(rn.base, rn.base + rn.n)
  self.ticks_said_again(rn.base, rn.base + rn.n)
  nodes_run.kept = nodes_run.kept + 1
  nodes_run.kept_at.push((rn.list, rn.item))
}

///|
/// What `body` builds, kept as its nodes (Ctx::part_nodes) whether parts are drawn again as recorded or not
/// (Tester::keep_parts, kept_part.mbt's way, kept by tests alone): a part over the others whose build says what floats
/// over them (Ctx::floats_over), said again with its nodes, so what scrolls under it keeps clear of it kept or not.
pub fn Ctx::kept_as_nodes(self : Ctx, id : Int, key : String, body : () -> Unit, read_out? : Bool = false) -> Unit {
  self.part_nodes(id, key, body, read_out)
}

///|
/// What `body` builds, in a box of its own filling the one being built, read out or not (Ctx::kept_part's), kept as
/// its nodes (kept_nodes.mbt's head): built again where something it read changed, or what builds it may build it
/// otherwise (the frame built anew), or it is built elsewhere (`key`, its id's scope, its owner, its layer, ...); else
/// its nodes put back as its build made them and what it said of the frame said again there, laid out with the rest.
fn Ctx::part_nodes(
  self : Ctx,
  id : Int,
  key : String,
  body : () -> Unit,
  read_out : Bool,
  own? : Bool = false,
) -> Unit {
  let build = fn() {
    self.box(left=0.0, top=0.0, right=0.0, bottom=0.0, fn() {
      if read_out {
        body()
      } else {
        self.hidden_from_semantics(body)
      }
    })
    |> ignore
  }
  // (a part in a row's or a part's build: kept as its nodes among that one's, which is built again as it is told
  // (RowNodes' `holder`), and put back with them)
  let outer = nodes_run.building
  let rn = match kept_nodes.get((id, -1)) {
    Some(rn) => rn
    None => {
      let rn = row_nodes_new(id, -1)
      kept_nodes[(id, -1)] = rn
      rn
    }
  }
  rn.shown = self.frame_no
  rn.laid_pass.val = nodes_run.pass
  rn.own = own
  rn.holder.val = outer
  // (`own`: what puts it here is made once (made.mbt's made_island), so what it is built from is its key and what it
  // read alone, whatever else the frame built anew)
  let may_keep = if own {
    nodes_run.on && !nodes_run.whole && !evented_for(id) && !inst_owners.on && !self.lit_every
  } else {
    self.nodes_keep()
  }
  if may_keep &&
    rn.ok &&
    !rn.in_pool &&
    rn.n > 0 &&
    !rn.watch.is_stale() &&
    rn.key == key &&
    rn.read == read_out &&
    rn.seed == self.id_seed &&
    rn.owner == self.owner &&
    rn.bones == self.bones &&
    rn.sel == desk.selecting &&
    rn.layer == self.layer_cur &&
    rn.direction == self.direction &&
    rn.epoch == self.epoch &&
    rn.scale == self.scale &&
    rn.reads_out == self.reads_out &&
    rn.lit_all == self.lit_all {
    // (what is worked out again of it as it is put back, what it marks used, read as its build read it: followed by its
    // watch, not by what builds it)
    @signals.untracked(fn() {
      self.nodes_put_back(rn, self.cur) |> ignore
      self.nodes_said_again(rn)
    })
    self.held_by(outer, rn)
    return
  }
  // (built for what it read, or as it is new or built elsewhere: what it builds its lists from may be otherwise, their
  // rows built anew; built only as it may not be kept, nothing it read changed: its lists' rows kept)
  let fresh = (nodes_run.fresh && (!own || evented_for(id))) ||
    rn.n == 0 ||
    rn.watch.is_stale() ||
    rn.key != key ||
    rn.read != read_out ||
    rn.seed != self.id_seed ||
    rn.owner != self.owner
  // (its nodes of before out of the frame's, as a part not built a while (a page covered) has them: put where its
  // build makes them, for each to be known as who it is (Ctx::node_known), laid out as before; left in the frame's
  // (a frame built anew), found there)
  if rn.store.length() > 0 {
    let r0 = rn.store[0]
    match known_nodes.get(r0.ident) {
      Some(o) if physical_equal(o, r0) => self.row_nodes_lent(rn)
      _ => ()
    }
  }
  let b = self.nodes_begin(rn)
  let r = self.count
  nodes_run.building = Some(rn)
  let was = nodes_run.part_fresh
  nodes_run.part_fresh = fresh
  rn.watch.read(build)
  nodes_run.part_fresh = was
  nodes_run.building = outer
  rn.key = key
  rn.read = read_out
  rn.seed = self.id_seed
  rn.owner = self.owner
  rn.bones = self.bones
  rn.sel = desk.selecting
  rn.layer = self.layer_cur
  rn.direction = self.direction
  self.nodes_end(rn, r, b, part=true)
  self.held_by(outer, rn)
}

///|
/// Part `rn`, just put among the frame's nodes, put among those of the row or part being built (`outer`) if one is:
/// its nodes theirs till they are taken out of the frame's, what it said again besides them said again with them.
fn Ctx::held_by(self : Ctx, outer : RowNodes?, rn : RowNodes) -> Unit {
  ignore(self)
  match outer {
    Some(o) => {
      rn.in_pool = false
      o.inner_now.push(rn)
      for f in rn.used {
        o.used.push(f)
      }
      for l in rn.laid {
        o.laid.push(l)
      }
      // (what it says again where its nodes are moved to, from where they are among the frame's now: moved as that
      // one's are)
      let d = rn.base - rn.said_base
      for f in rn.again {
        o.again.push(fn(by) { f(by + d) })
      }
    }
    None => ()
  }
}

///|
/// How many rows the last frame kept as their nodes, and how many it built (a test's, a bench's).
pub fn Tester::rows_as_nodes(self : Tester) -> (Int, Int) {
  ignore(self)
  (nodes_run.kept, nodes_run.built)
}

///|
/// How many rows of lists that show only what they read (Ctx::list's `rows_read`) were built since the run began,
/// every frame's added up: those built again keeping none to hold a frame that kept some among them, where the Tester
/// checks so (check_looks).
pub fn Tester::rows_read_built(self : Tester) -> Int {
  ignore(self)
  nodes_run.built_read
}

///|
/// Why the rows and the parts of the last frame that may not be kept may not (a part's said so), each reason once with
/// how many (a test's, a bench's).
pub fn rows_unkept() -> Array[(String, Int)] {
  let by : Map[String, Int] = {}
  for _, rn in kept_nodes {
    if !rn.ok && rn.why != "" {
      let why = if rn.item < 0 { "a part: " + rn.why } else { rn.why }
      by[why] = by.get(why).unwrap_or(0) + 1
    }
  }
  let out = []
  for k, v in by {
    out.push((k, v))
  }
  out
}

// ── held by the tests ───────────────────────────────────────────────────

///|
/// A pass of a frame's build that kept rows, as laid out (frame_said_lines), and where the rows it kept were among its
/// nodes (list, item, first node, how many): compared once the frame is built again keeping none (rows_check_end).
priv struct RowsCheck {
  lines : Array[String]
  rows : Array[(Int, Int, Int, Int, Double)]
  /// where it parted from the first build keeping none: that build's lines and the first line apart; the second such
  /// build says whether they part because rows were kept or because what was built changed as it was built
  mut whole : Array[String]?
  mut at : Int
  /// what the pass that kept rows said to tell outside (Ctx::after_build): the frame's, told as it was said; a build
  /// to compare with tells nothing (what is told once, felt as a hold opened its menu, it does not tell again)
  tells : Array[(Int, () -> Unit)]
}

///|
// kept across runs: set and let go within a frame
let rows_checking : Ref[RowsCheck?] = Ref(None)

///|
/// A pass of the frame's build is over (frame_body), `kept0` the rows kept before it: where a Tester checks frames
/// (looks_check) and it kept rows, what it built and said is taken, and the frame built once more keeping none (true:
/// the caller builds it again), the two compared as that is laid out (rows_check_end). In the frame, before what its
/// builds tell outside and before it is painted: built again from the same state, it must come out the same, node for
/// node, and say the same of the frame; so it is painted the same.
fn Ctx::rows_check_begin(self : Ctx, kept0 : Int) -> Bool {
  if !looks_check.val || nodes_run.kept <= kept0 || rows_checking.val is Some(_) {
    return false
  }
  // (what it read changed as it was built or laid out, a measure taken as it was laid out: built again, it would build
  // otherwise, from what this pass left; the next frame builds it so)
  if nodes_run.told || layout_said.val != "" || watch_said.val != "" || frame_watch_of().changed_as_read() {
    return false
  }
  let rows = []
  for key, rn in kept_nodes {
    if rn.in_pool {
      rows.push((key.0, key.1, rn.base, rn.n, rn.built_at))
    }
  }
  rows_checking.val = Some({ lines: self.frame_said_lines(), rows, whole: None, at: -1, tells: self.tells.copy() })
  nodes_run.fresh = true
  nodes_run.whole = true
  // (one pass of the frame, as a host builds it: not counted, FramePerf's `passes`)
  perf_at[3] = perf_at[3] - 1
  true
}

///|
/// The frame built again keeping no row (rows_check_begin) is laid out: what it built and said must be what the pass
/// that kept rows built and said. Where it is not, it is built once more keeping none (true: the caller builds it
/// again): that coming out as the first such build did, the rows kept are what parts them, and the test fails, saying
/// the first line they part at and the row kept that holds it; coming out otherwise, what was built changed as it was
/// built (from what no signal says), kept rows or not, and the next frame builds it so.
fn Ctx::rows_check_end(self : Ctx) -> Bool {
  guard rows_checking.val is Some(was) else { return false }
  let now = self.frame_said_lines()
  match was.whole {
    None => {
      let at = lines_apart(was.lines, now)
      if at < 0 {
        rows_checking.val = None
        self.tells.clear()
        self.tells.append(was.tells)
        return false
      }
      // (apart: built once more keeping none, to know whether what parts them is the rows kept)
      was.whole = Some(now)
      was.at = at
      perf_at[3] = perf_at[3] - 1
      return true
    }
    Some(whole) => {
      rows_checking.val = None
      // (built again keeping none, it built otherwise again: what it built changed as it was built, from what it
      // read that no signal says, kept rows or not; the next frame builds it so)
      if lines_apart(whole, now) >= 0 {
        self.tells.clear()
        self.tells.append(was.tells)
        return false
      }
    }
  }
  let now = was.whole.unwrap()
  let at = was.at
  let line = fn(a : Array[String], j : Int) { if j < a.length() { a[j] } else { "none" } }
  // (the row kept that holds the node, where the line is a node's)
  let mut holder = "none of the rows kept"
  for r in was.rows {
    if at >= r.2 && at < r.2 + r.3 {
      // (and the words it holds as built now, to know it by)
      let words = []
      for j in r.2..<imin(r.2 + r.3, self.count) {
        let t = self.nodes[j]
        if (t.kind == kind_text || t.kind == kind_rich) && t.text != "" && words.length() < 6 {
          words.push(t.text)
        }
      }
      holder = "list \{r.0}'s row \{r.1} (its node \{at - r.2}; its words: \{words.join(" | ")}; built at \{r.4.to_int()} ms)"
      // (all of it, both ways, where the Tester's said log asks: MBUI_ROWS_PARTED=1)
      if @hostapi.env("MBUI_ROWS_PARTED") == "1" {
        for j in r.2..<(r.2 + r.3) {
          println("ROWS-PARTED kept  \{line(was.lines, j)}")
          println("ROWS-PARTED built \{line(now, j)}")
        }
      }
    }
  }
  // (every line the two part at, the first 40, each way: what was kept that building anew did not make)
  let parted = StringBuilder()
  let mut shown = 0
  for j in 0..<imax(was.lines.length(), now.length()) {
    let a = line(was.lines, j)
    let b = line(now, j)
    if a != b && shown < 40 {
      shown += 1
      parted.write_string("\nPARTED kept  " + a)
      parted.write_string("\nPARTED built " + b)
    }
  }
  looks_fail(
    "the frame at \{self.clock.to_int()} ms, built keeping \{was.rows.length()} rows, (\{built_why.val}), parts from it built keeping none at line \{at} (\{holder}): kept \{line(was.lines, at)} / \{line(was.lines, at + 1)}; built \{line(now, at)} / \{line(now, at + 1)}" + parted.to_string(),
  )
  false
}

///|
/// The first line where `a` and `b` part (-1: none).
fn lines_apart(a : Array[String], b : Array[String]) -> Int {
  let n = imin(a.length(), b.length())
  for j in 0..<n {
    if a[j] != b[j] {
      return j
    }
  }
  if a.length() != b.length() {
    n
  } else {
    -1
  }
}

///|
/// What the frame built, as laid out, a line each: each node (what it is, where, how large, how it looks, what holds it
/// and what it holds, its look of draw.mbt's), then what it said of the frame (said.mbt's build lists, what is read out
/// and hidden from that, the corners worked out once laid out, the words kept, what asks to be lit).
fn Ctx::frame_said_lines(self : Ctx) -> Array[String] {
  let out = []
  // (in the tree's order, each node by where it is in it: what a frame is is its tree, not where in the frame's nodes
  // each was made, which a part kept as its nodes and the same built anew may make in another order)
  let order = self.tree_order()
  let at = Array::make(self.count, -1)
  for k, i in order {
    at[i] = k
  }
  let pos = fn(i : Int) { if i >= 0 && i < at.length() { at[i] } else { i } }
  for i in order {
    let nd = self.nodes[i]
    let drawn = match self.drawn_entry(i) {
      Some(e) =>
        " look \{e.look} z \{e.z} only \{e.only} cut \{e.top},\{e.bottom} ground \{e.ground} by \{e.look_by is Some(_)} cycle \{e.cycle is Some(_)}"
      None => ""
    }
    // (its words and their face where it has words: a box keeps what an earlier node of the slot held, unread)
    let words = if nd.kind == kind_image {
      " \"\{nd.text}\" still \{nd.still} fade \{nd.fade}"
    } else if nd.kind == kind_rich {
      " \"\{nd.text}\" \{nd.rl.map(fn(r) { (r.text, r.line_w, r.line_y) })}"
    } else if nd.kind != kind_text && nd.kind != kind_editor {
      ""
    } else {
      " \"\{nd.text}\" color \{nd.color} font \{nd.font_size} \{nd.weight} wrap \{nd.wrap} lines \{nd.max_lines}" +
      (if nd.kind == kind_text {
        " \{nd.tl.map(fn(t) { (t.text, t.w, t.h) })}"
      } else if nd.kind == kind_rich {
        " \{nd.rl.map(fn(r) { (r.text, r.line_w, r.line_y) })}"
      } else {
        ""
      })
    }
    out.push(
      "\{pos(i)} kind \{nd.kind} id \{nd.id} parent \{pos(nd.parent)} first \{pos(nd.first)} next \{pos(nd.next)} item \{nd.item} at \{said_at(nd.x)},\{said_at(nd.y)} \{said_at(nd.fw)}×\{said_at(nd.fh)} tx \{nd.tx},\{nd.ty} moved \{nd.moved_x},\{nd.moved_y} bg \{nd.bg} alpha \{nd.opacity} radius \{nd.radius} \{nd.radii} border \{nd.border_w} \{nd.border_c} shadow \{nd.shadow} \{nd.shadow_c} clip \{nd.clip} hit \{nd.hit} points \{nd.points} layer \{nd.layer} \{nd.portal} \{nd.portal_id} size \{size_said(nd.w)} \{size_said(nd.h)} placed \{nd.at_l},\{nd.at_t},\{nd.at_r},\{nd.at_b}" +
      words +
      drawn,
    )
  }
  let sb = StringBuilder()
  for l in build_lists {
    l.said_take(self, 0).said_show(sb)
  }
  for l in sb.to_string().split("\n") {
    out.push(l.to_string())
  }
  let sems = self.sems.map(fn(s) { (pos(s.node), "\{s.id} \{s.label} \{s.value} \{s.hidden}") })
  sems.sort_by(fn(a, b) { a.0.compare(b.0) })
  out.push("sems " + sems.map(fn(s) { "\{s.0} \{s.1}" }).join("; "))
  let corners = fn(a : Array[Int]) {
    let t = a.map(pos)
    t.sort()
    t
  }
  out.push("inners \{corners(self.inners)} \{corners(self.inners_or)} \{corners(self.arounds)}")
  let words = []
  words_kept.each(fn(k, w) { words.push("\{k}: \{w.text} \{w.pieces.map(fn(p) { (p.x, p.y, p.w, p.h) })}") })
  words.sort()
  out.push("words " + words.join("; "))
  let lit = self.lit_asked.iter().collect()
  lit.sort()
  let chooses = self.hand_chooses.iter().collect()
  chooses.sort()
  out.push("lit \{lit} \{chooses}")
  // (the ids said numbered as Tester::said numbers them: that numbering let go, it numbers its own)
  if !said_log.on {
    said_log.ids.clear()
  }
  out
}

///|
/// A length as compared (frame_said_lines): to a millionth of a point, what is drawn the same is (frame_watch.mbt's
/// drawn_same), however its sum was added up.
fn said_at(x : Double) -> Double {
  (x * 1.0e6).round() / 1.0e6
}

///|
/// A size as compared (frame_said_lines).
fn size_said(s : Size) -> String {
  match s {
    Auto => "auto"
    Px(p) => "\{p}px"
    Fill(k) => "fill \{k}"
    Cut => "cut"
    Pct(p) => "\{p}%"
  }
}

///|
/// What a row read of the layout as it was built (readback.mbt): a box's rect, its size, whether a row left it out;
/// what it read, and where.
priv enum LaidRead {
  Rect(Int, (Double, Double, Double, Double)?, SourceLoc)
  Size(Int, (Double, Double)?, SourceLoc)
  Left(Int, Bool, SourceLoc)
}

///|
/// What the row being built read of the layout (readback.mbt), kept with it.
fn row_read_laid(r : LaidRead) -> Unit {
  match nodes_run.building {
    Some(rn) => rn.laid.push(r)
    None => ()
  }
}

///|
/// What a row kept read of the layout as it was built, read again as it read it: read back once the frame is laid out,
/// laid out otherwise, the frame is built again (readback.mbt).
fn Ctx::laid_said_again(self : Ctx, r : LaidRead) -> Unit {
  match r {
    Rect(id, v, loc) => {
      self.laid_watch[id] = self.frame_no
      if !self.laid_reads.contains(id) {
        self.laid_reads[id] = (v, loc)
      }
    }
    Size(id, v, loc) => {
      self.laid_watch[id] = self.frame_no
      if !self.size_reads.contains(id) {
        self.size_reads[id] = (v, loc)
      }
    }
    Left(id, v, loc) => {
      if !self.left_reads.contains(id) {
        self.left_reads[id] = (v, loc)
      }
    }
  }
}


///|
/// Whether what came for this frame came to the part kept by `id` (Ctx::part_nodes): all of it does, but where it was
/// the hand's alone and went to one old view's part (NodesRun's evented_only), only that one.
fn evented_for(id : Int) -> Bool {
  nodes_run.evented && (nodes_run.evented_only < 0 || nodes_run.evented_only == id)
}
