// The window's tree drawn as a scene kept by layer (docs/retained.md rules 4 and 15): each layer (@view.Tree::
// starts_layer: the root, a page, a sheet, a row, an old view, what moves as it is drawn) keeps what it drew, where it
// is among the frame's instances, what it was cut and faded by as it began, and what its drawing read (a watch of its
// own). A frame makes again only the layers something of changed, as the tree tells it at its cause (what was made
// again, placed or faded otherwise, let go: Tree::take_changed, take_placed, take_removed) or as what a layer's
// drawing read changed (an image decoded, a field's words); every other is the same instances it was, copied where it
// is put (a frame the old frame paints) or left where it lies (a frame of the tree alone). Where the window changed is
// worked out of the same causes: each node that changed drawn again where its drawing reached before and where it
// reaches now (@damage.Parts), never by comparing frames. The renderers take the frame's instances whole
// (h_present): that is an adapter, said to be one, and no step here is done because of it.

///|
/// A layer of the scene, as the frame that last drew it left it.
priv struct SceneLayer {
  id : @view.NodeId
  /// where its instances are among the frame's (first, how many), and its shapes' pieces among the frame's (first,
  /// how many): -1 where it is no longer where it was drawn (raised apart in pieces: drawn again whole each time)
  mut start : Int
  mut count : Int
  mut seg_from : Int
  mut seg_count : Int
  /// its bands of shapes (kind 11), from its first instance: their first piece told again where it is copied
  bands : Array[Int]
  /// the host's controls put where it draws them (View::native_anchor): each one's number (native_anchor_number) and
  /// its instance, from its first; while it is drawn, the instance's place among the frame's (scene_anchor_drawn)
  anchors : Array[(Int, Int)]
  /// the layers it holds, at once below it: moved with it where it is copied; and the layer it is in at once
  inner : Array[@view.NodeId]
  mut outer : @view.NodeId?
  /// what it was drawn in as it began: the clip it was cut by (clip_stack's level, whether it is the window's, its
  /// outer apart from it), the fades, stretches and glyph looks of what holds it, and where its node is drawn (where,
  /// how opaque, how big, where were nothing grown or shrunk)
  mut clip : FixedArray[Double]
  mut clip_window : Bool
  mut clip_apart : Bool
  mut fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))]
  mut stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)]
  mut glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))]
  mut held : (Double, Double, Double, Double, Double, Double)
  /// whether the old frame had a scrim up as it was drawn: what of it is drawn over a scrim is raised over it then
  /// (View::over_scrim), drawn otherwise
  mut scrim : Bool
  /// as far as all it draws reaches (@damage's reach), as last drawn
  mut reach : (Double, Double, Double, Double)
  /// what its drawing read: told, it is drawn again (`told`)
  mut watch : @signals.Watch?
  mut told : Bool
  /// it holds something drawn otherwise than by the tree alone as it is drawn: an old view, what is raised over a
  /// scrim, glass and what captures for it, a native view, the old frame's layers under it. Never copied, and never
  /// drawn again by the tree alone (scene_alone).
  mut own_only : Bool
  /// what it holds is drawn again each frame that draws what holds it (a field: its caret, its words picked, as its
  /// editor has them): never copied, never drawn again alone
  mut each : Bool
  /// the glyphs' plots it draws from, held in their atlas while it is in the scene (colour or not, the plot)
  plots : Array[(Bool, Int)]
  /// the pictures it shows, each as asked (source, pixels): asked again where it is copied, kept as shown
  images : Array[(String, Double)]
  /// its drawing read the clock (an image fading in): drawn again each frame the clock goes
  mut reads_clock : Bool
  /// the frame that last drew it (Scene's `frame`)
  mut seen : Int
  /// how it is drawn, as the tree was last gone through for it (Ctx::tree_walk), and how opaque and how big its node was
  /// drawn then: drawn again as it keeps it wherever it is put, the tree not gone through, while nothing of it changes
  /// (scene_entries_kept)
  mut entries : Array[SceneEntry]?
  mut entries_as : (Double, Double)
  /// all it drew as it was last drawn, what it holds with it: its instances, its shapes' pieces (and the number of the
  /// first of them then), who drew each where that is kept. What it is copied from where it is kept: its own, never
  /// where another frame had it
  mut block : FixedArray[Double]
  mut block_n : Int
  block_segs : Array[Double]
  mut block_seg_base : Int
  mut block_owners : OwnersRun?
  /// where in its block each layer it holds goes (its instance and its piece there), and which: its block its own
  /// drawing alone, what it holds each by its own block (Ctx::scene_emitted)
  block_refs : Array[(Int, Int, @view.NodeId)]
}

///|
/// One of how a layer is drawn (Ctx::tree_walk), as the tree was gone through for it, in the order it is drawn: a node
/// it draws, or a layer it holds (`layer`: drawn as that one is kept, where it is in this one then); how deep it is under
/// the layer's node (0); and, of a node it draws, where it is in it (its node at 0, 0), how opaque, how big, and where
/// were nothing grown or shrunk. A layer drawn where it is put now goes through these, not the tree, each node's own
/// drawing read as the tree has it then (its content, its looks), as a walk of the tree reads it: where each is in the
/// window its layer's place and its own in it, added, either way.
///
/// Of a node, too, what else of the tree its drawing reads (SceneEntry::read), read as the tree was gone through: none
/// of it changes unsaid but where its node begins the layer (a place property bound begins one: Tree::starts_layer;
/// what else changes it makes its node again or places it, its layer marked), so a layer drawn as it keeps how it is
/// drawn asks the tree again only of its own node; its instances as made where it is its own (view_blocks'), composed
/// again wherever it is drawn; and how far it and what it holds reached as last drawn (scene's `reach`). So a layer
/// placed otherwise is drawn where it is put by going through these alone: nothing made, nothing looked up.
priv struct SceneEntry {
  c : @view.Content
  depth : Int
  /// (of a layer it holds, where that is in it as it was last drawn: worked out again as it is placed otherwise)
  mut x : Double
  mut y : Double
  mut a : Double
  mut s : Double
  mut ux : Double
  mut uy : Double
  layer : Bool
  /// the looks its glyphs and those of all it holds are drawn by (Tree::glyphs_of), whether it is drawn over the scrim,
  /// how it is turned, where its ground is drawn off and bigger, how what it holds fades towards its edges (its soft cut's
  /// where it cuts softly), how what it holds is stretched, and whether it has a field of its own
  mut glyphs : ((Double, @view.GlyphAt) -> @view.GlyphLook)?
  mut over_scrim : Bool
  mut turn : Double
  mut turn_drawn : Bool
  mut ground_x : Double
  mut ground_y : Double
  mut ground_w : Double
  mut ground_h : Double
  mut fade_start : Double
  mut fade_top : Double
  mut fade_end : Double
  mut fade_foot : Double
  mut stretch : Double
  mut field : Bool
  /// its instances as made where it is its own, as last drawn (none: not made, out of sight as it was drawn)
  mut block : ViewBlock?
  /// how far it and what it holds reached as last drawn; whether what it holds is drawn anew with it in the frame being
  /// drawn (TreePaint's `open`); how many instances its edge drawn after what it holds is
  reach : @damage.Rect
  mut moved : Bool
  mut ring_n : Int
  /// of a layer it holds: left out of its row since (Tree::placed_in, none), drawn nowhere
  mut gone : Bool
}

///|
/// An entry of how a layer is drawn, as the walk of the tree finds it: what else of the tree its drawing reads not read
/// yet (SceneEntry::read).
fn scene_entry(
  c : @view.Content,
  depth : Int,
  x : Double,
  y : Double,
  a : Double,
  s : Double,
  ux : Double,
  uy : Double,
  layer : Bool,
) -> SceneEntry {
  {
    c,
    depth,
    x,
    y,
    a,
    s,
    ux,
    uy,
    layer,
    glyphs: None,
    over_scrim: false,
    turn: 0.0,
    turn_drawn: false,
    ground_x: 0.0,
    ground_y: 0.0,
    ground_w: 0.0,
    ground_h: 0.0,
    fade_start: 0.0,
    fade_top: 0.0,
    fade_end: 0.0,
    fade_foot: 0.0,
    stretch: 0.0,
    field: false,
    block: None,
    reach: @damage.Rect::none(),
    moved: false,
    ring_n: 0,
    gone: false,
  }
}

///|
/// What else of the tree node entry `e`'s drawing reads read, as the tree has it now (SceneEntry).
fn SceneEntry::read(self : SceneEntry, tree : @view.Tree) -> Unit {
  let id = self.c.id
  self.glyphs = tree.glyphs_of(id)
  self.over_scrim = tree.over_scrim_of(id)
  let (turn, about_drawn) = tree.turn_of(id)
  self.turn = turn
  self.turn_drawn = about_drawn
  let (gx, gy, gw, gh) = tree.ground_drawn_of(id)
  self.ground_x = gx
  self.ground_y = gy
  self.ground_w = gw
  self.ground_h = gh
  // (what it holds past its top and foot faded towards them, as far as it reaches past, no further than half of what
  // shows: View::cuts_softly; else as far before its edges as it says, View::fades)
  let (start, top, end, foot) = match tree.cut_soft_of(id) {
    Some((over_top, over_foot, h)) => (0.0, cut_soft(over_top, h / 2.0), 0.0, cut_soft(over_foot, h / 2.0))
    None => tree.fades_of(id)
  }
  self.fade_start = start
  self.fade_top = top
  self.fade_end = end
  self.fade_foot = foot
  self.stretch = tree.stretch_of(id)
  self.field = tree_fields.contains(id)
}

///|
/// Layer `id`, where how it keeps it is drawn still stands for its node drawn where `place` says (its `entries`):
/// nothing of it changed since (no node of it made again, placed, let go nor added, nothing its drawing read: it would
/// be marked or told), its node as opaque and as big as it was then; none where the frame draws all of it anew (a
/// check's, nothing kept to copy). None: the tree gone through for it.
fn scene_entries_kept(id : @view.NodeId, place : (Double, Double, Double, Double, Double, Double)) -> SceneLayer? {
  guard !scene.fresh && !scene_checking() else { return None }
  match scene.layers.get(id) {
    Some(l) if l.entries is Some(_) &&
      !l.told &&
      !scene.marked.contains(id) &&
      // (holding one drawn again: how it was drawn holds that one as it was, walked anew)
      !scene.holding.contains(id) &&
      l.entries_as.0 == place.2 &&
      l.entries_as.1 == place.3 => Some(l)
    _ => None
  }
}

///|
/// How layer `l` was drawn now (`entries`, its node where `place` says) kept with it.
fn scene_entries_keep(
  l : SceneLayer,
  entries : Array[SceneEntry],
  place : (Double, Double, Double, Double, Double, Double),
) -> Unit {
  l.entries = Some(entries)
  l.entries_as = (place.2, place.3)
}

///|
/// The scene of the window's tree, kept across frames.
priv struct Scene {
  layers : Map[@view.NodeId, SceneLayer]
  /// each node drawn, its entry in how its layer is drawn: as far as it, and all it holds, reaches (as last drawn, each
  /// time its layer is: SceneEntry's `reach`); and the layer it was drawn in
  reach : Map[@view.NodeId, SceneEntry]
  drawn_in : Map[@view.NodeId, @view.NodeId]
  /// what changed since the frame before, at its causes: each node drawn again where it reached (said already) and
  /// where it reaches once drawn (said as the frame ends: `due`); the layers to draw again (`marked`); the nodes all of
  /// whose drawing is drawn again with them (placed, or cutting, fading or setting the glyphs of what they hold:
  /// `moved`)
  due : Array[@view.NodeId]
  marked : Map[@view.NodeId, Bool]
  /// the layers holding one marked: not copied whole (what they hold is drawn again in them)
  holding : Map[@view.NodeId, Bool]
  moved : Map[@view.NodeId, Bool]
  /// the layers kept placed otherwise, nothing of them changed (scene_moved_layer): each drawn where it is put now, as
  /// it keeps how it is drawn; what holds it not copied whole
  moved_layers : Map[@view.NodeId, Bool]
  /// nodes let go since the frame before, and of them those drawn in no layer kept (what the tree alone cannot draw
  /// again without: scene_alone_may)
  mut removed : Int
  mut removed_unkept : Int
  /// where the window changed, said by the causes
  parts : @damage.Parts
  /// the last frame's instances and pieces (what a frame the old frame paints copies the layers kept from), and the
  /// numbers of the frame now (Scene::flip)
  mut prev : FixedArray[Double]
  mut prev_n : Int
  mut prev_segs : Array[Double]
  /// what a layer kept is copied from now, its pieces, and the frame that drew what is kept there (the last frame's,
  /// as the old frame paints; the frame's own, as a layer is drawn again alone)
  mut src : FixedArray[Double]
  mut src_n : Int
  mut src_segs : Array[Double]
  mut src_seen : Int
  /// where the frame's pieces begin among its instances (emit_segs: after every instance drawn), and how many it drew
  mut seg_tail : Int
  mut last_n : Int
  /// frames composed: a layer's `seen`
  mut frame : Int
  /// what the whole was drawn by (the window, its scale, its ground, the atlas): another, drawn whole, nothing kept
  mut drawn_by : DrawnBy
  /// the captures of glass in the frame (@damage.capture_of: each group's together), and its instances showing a
  /// stream's picture (drawn again each frame: their reach)
  captures : Array[(Double, (Double, Double, Double, Double))]
  streams : Array[(Double, Double, Double, Double)]
  /// what the old frame drew, by the old view it is in (the old frame's own: none), as far as it reaches: the frame
  /// before's and this one's
  old_before : Map[@view.NodeId?, (Double, Double, Double, Double)]
  old_now : Map[@view.NodeId?, (Double, Double, Double, Double)]
  /// and its instances themselves, as it drew them the last time it painted and as it paints now (its numbers, in
  /// order): compared where it is painted again, what differs drawn again (the old frame says nothing of what changed in
  /// it: Parts::add_changed, an adapter)
  old_insts_before : Map[@view.NodeId?, (FixedArray[Double], Int)]
  old_insts_now : Map[@view.NodeId?, Array[Double]]
  /// whether what the old frame draws may have changed this frame (built or painted for it: frame_drawn)
  mut old_due : Bool
  /// nothing kept to be copied this frame (a check drawing it anew, a picture at another size, who drew what kept)
  mut fresh : Bool
  /// the frame drawn again as a check (Ctx::scene_check): the tree drawn as it is, not brought on
  mut checking : Bool
  /// the layer being drawn now, and whether something of it is drawn otherwise than by the tree alone
  mut drawing : SceneLayer?
  /// who drew the last frame's instances, where who drew what is kept (a Tester's: inst_owners_kept)
  mut owners : OwnersRun?
  /// why the last frame the tree was to draw alone was not, and why the first layer the last frame could not copy was
  /// not (a test's to say)
  mut alone_why : String
  mut copy_why : String
  /// why the frames the old frame painted were (the first few told apart), for a test to say
  full_whys : Array[String]
  /// layers to draw again the frame after this (a glyph of theirs there was no room for in the atlas)
  again : Array[@view.NodeId]
  /// the buffers layers are drawn again alone into, kept from frame to frame (one for each drawn in a frame)
  scratch : Array[FixedArray[Double]]
  /// the parts the last frame presented was drawn again in (h_present), for a test or a bench to read
  mut told_parts : Array[(Double, Double, Double, Double)]
  /// the moments a layer's drawing asked to be woken at, each the layer's: drawn again then
  wakes : Array[(Double, @view.NodeId)]
  /// a layer drawn this frame read the clock: the next frame asked for as the clock goes
  mut clock_read : Bool
  /// what an old view's paint read changed (an old view's layer's watch told): the old frame painted again
  mut old_told : Bool
  /// where the old frame's cycles by the clock drew what they move as last applied (Ctx::cycle_looks)
  cycled : Array[(Double, Double, Double, Double)]
  /// where what of the tree is drawn over the old frame's scrim was drawn as last kept clear of what comes up over it,
  /// and whether it was this frame
  mut over_scrim : (Double, Double, Double, Double)
  mut over_scrim_said : Bool
}

///|
// kept across runs: put back as a run begins (scene_forget)
let scene : Scene = {
  layers: Map([]),
  reach: Map([]),
  drawn_in: Map([]),
  due: [],
  marked: Map([]),
  holding: Map([]),
  moved: Map([]),
  moved_layers: Map([]),
  removed: 0,
  removed_unkept: 0,
  parts: @damage.Parts::new(),
  prev: FixedArray::make(0, 0.0),
  prev_n: 0,
  prev_segs: [],
  src: FixedArray::make(0, 0.0),
  src_n: 0,
  src_segs: [],
  src_seen: -1,
  seg_tail: 0,
  last_n: 0,
  frame: 0,
  drawn_by: drawn_by_none,
  captures: [],
  streams: [],
  old_before: Map([]),
  old_now: Map([]),
  old_insts_before: Map([]),
  old_insts_now: Map([]),
  old_due: true,
  fresh: false,
  checking: false,
  drawing: None,
  owners: None,
  alone_why: "",
  copy_why: "",
  full_whys: [],
  again: [],
  scratch: [],
  told_parts: [],
  wakes: [],
  clock_read: false,
  old_told: false,
  cycled: [],
  over_scrim: (1.0e18, 1.0e18, -1.0e18, -1.0e18),
  over_scrim_said: false,
}

///|
/// What drawing the window's tree did, counted from its making (rule 14: a frame's cost is what changed): layers drawn
/// and their instances made into the frame (`recorded`), layers and instances kept, copied where they are put
/// (`copied`, `copied_insts`), frames of the tree alone (`alone`) and frames the old frame painted (`full`), and how much saying where the window changed took
/// (@damage.Parts::work).
pub(all) struct SceneWork {
  mut layers : Int
  mut recorded : Int
  mut copied : Int
  mut copied_insts : Int
  mut alone : Int
  mut full : Int
  mut parts : Int
  /// of it, what the frames of the tree alone drew (`alone_recorded`) and worked out of where the window changed
  /// (`alone_parts`)
  mut alone_recorded : Int
  mut alone_parts : Int
} derive(Eq, Debug, Show)

///|
// kept across runs: counts on
let scene_work : SceneWork = {
  layers: 0,
  recorded: 0,
  copied: 0,
  copied_insts: 0,
  alone: 0,
  full: 0,
  parts: 0,
  alone_recorded: 0,
  alone_parts: 0,
}

///|
/// The instances the frames of the tree alone moved to another place in the frame, as they were: put after a layer
/// drawn again that grew or shrank (Ctx::scene_spliced).
// kept across runs: counts on
let scene_moved_insts : Ref[Int] = Ref(0)

///|
/// What drawing the window's tree did so far (SceneWork), for a test to count what a frame does.
pub fn scene_done() -> SceneWork {
  { ..scene_work, parts: scene.parts.work() }
}

///|
/// `f` done as a check's (a frame drawn anew to be compared: looks_check, Ctx::scene_check), what it draws counted
/// nowhere: no frame of the app's.
fn scene_unrecorded(f : () -> Unit) -> Unit {
  let was = { ..scene_work }
  let moved = scene_moved_insts.val
  let parts = scene.parts.work()
  f()
  scene_moved_insts.val = moved
  scene_work.layers = was.layers
  scene_work.recorded = was.recorded
  scene_work.copied = was.copied
  scene_work.copied_insts = was.copied_insts
  scene_work.alone = was.alone
  scene_work.full = was.full
  scene_work.alone_recorded = was.alone_recorded
  scene_work.alone_parts = was.alone_parts
  scene.parts.work_back(parts)
}

///|
/// The parts the last frame presented that drew anything again was drawn again in (in points: (x, y, w, h); one with
/// w < 0, all of it): what the scene said changed (h_present).
pub fn scene_parts() -> Array[(Double, Double, Double, Double)] {
  scene.told_parts.copy()
}

///|
/// Why the last frame the tree was to draw alone was not ("" where it was), and the first layer the last frame the old
/// frame painted did not copy, for a test to say.
pub fn scene_alone_why() -> String {
  "alone: \{scene.alone_why}; copied: \{scene.copy_why}; painted whole for: \{scene.full_whys}"
}

///|
/// As a run begins, or as the window's tree is let go: nothing kept, the next frame drawn whole.
fn scene_forget() -> Unit {
  scene_drop_all()
  scene.reach.clear()
  scene.drawn_in.clear()
  scene.due.clear()
  scene.marked.clear()
  scene.holding.clear()
  scene.moved.clear()
  scene.moved_layers.clear()
  scene.removed = 0
  scene.removed_unkept = 0
  scene.prev_n = 0
  scene.prev_segs.clear()
  scene.seg_tail = 0
  scene.last_n = 0
  scene.drawn_by = drawn_by_none
  scene.captures.clear()
  scene.streams.clear()
  scene.old_before.clear()
  scene.old_now.clear()
  scene.old_insts_before.clear()
  scene.old_insts_now.clear()
  scene.old_due = true
  scene.fresh = false
  scene.drawing = None
  scene.told_parts.clear()
  scene.wakes.clear()
  scene.clock_read = false
  scene.old_told = false
  scene.cycled.clear()
  scene.over_scrim = @damage.nowhere
  scene.holding.clear()
  scene.again.clear()
  scene.owners = None
  scene.src_n = 0
  scene.src_seen = -1
  scene.src_segs.clear()
  scene.checking = false
  scene.alone_why = ""
  scene.copy_why = ""
  scene.full_whys.clear()
  scene.over_scrim_said = false
  tree_alone_drawn.val = false
  scene.parts.whole(1)
}

///|
/// Every layer let go: its watch stopped, its plots let go (where the atlas they are in is still the one held).
fn scene_drop_all() -> Unit {
  for _, l in scene.layers {
    scene_layer_gone(l)
  }
  scene.layers.clear()
}

///|
/// Layer `l` no longer in the scene: what it read no longer followed.
fn scene_layer_gone(l : SceneLayer) -> Unit {
  match l.watch {
    Some(w) => w.stop()
    None => ()
  }
  l.watch = None
  l.plots.clear()
}

///|
/// As a frame the old frame paints begins, before anything of it places a glyph: the plots of the atlas each layer kept
/// draws from said drawn from in this frame (Atlas::drawn: never emptied for another while it is), as the glyphs an
/// old view draws are as it draws them; a layer copied draws from them still.
fn scene_plots_drawn() -> Unit {
  for _, l in scene.layers {
    for p in l.plots {
      let (a, _) = atlas_for(p.0)
      if a.sized() {
        a.drawn(p.1)
      }
    }
  }
}

///|
/// What the tree changed since it was last taken, told the scene at its causes (view_changes_taken): each node made
/// again, placed otherwise or let go drawn again where it reached, and once drawn where it reaches; its layer drawn
/// again; where it was placed, or cuts, fades or sets the glyphs of what it holds, all of that drawn again with it.
/// `ordered`: the nodes what each holds is drawn in another order (Tree::take_ordered), the layer each is drawn in drawn
/// again in it.
fn scene_told(
  tree : @view.Tree,
  changed : Array[@view.NodeId],
  placed : Array[@view.NodeId],
  removed : Array[@view.NodeId],
  ordered? : Array[@view.NodeId] = [],
) -> Unit {
  // (the layer the scene keeps that each layer is drawn in, found once for all those told at once: a page made, each
  // of its thousands of nodes told, goes up through the same layers, none of them kept yet)
  let kept_in : Map[@view.NodeId, @view.NodeId?] = {}
  fn kept_of(at : @view.NodeId?) -> @view.NodeId? {
    guard at is Some(l) else { return None }
    if scene.layers.contains(l) {
      return Some(l)
    }
    match kept_in.get(l) {
      Some(k) => k
      None => {
        let k = kept_of(tree.holder_of(l).bind(fn(h) { tree.layer_of(h) }))
        kept_in[l] = k
        k
      }
    }
  }
  let tell = fn(id : @view.NodeId, moved : Bool, placed : Bool) {
    match scene.reach.get(id) {
      Some(e) => scene.parts.add(e.reach.rect())
      None => ()
    }
    scene.due.push(id)
    if moved {
      scene.moved[id] = true
    }
    // (the layer it is drawn in: itself where it begins one, else the nearest holding it the scene keeps; a layer kept
    // placed otherwise, nothing of it made again, drawn where it is put now as it keeps how it is drawn)
    let at = kept_of(tree.layer_of(id))
    match at {
      Some(l) if placed && l == id =>
        match scene.layers.get(l) {
          // (drawn in the frame kept: in how what holds it is drawn, as that keeps it)
          Some(x) if x.seen == scene.frame => scene_moved_layer(l)
          // (not drawn then (left out of its row as it was drawn): in none of how what holds it is drawn, that drawn
          // again to find it)
          _ =>
            match kept_of(tree.holder_of(l).bind(fn(h) { tree.layer_of(h) })) {
              Some(o) => scene_mark(o)
              None => ()
            }
        }
      Some(l) => scene_mark(l)
      None => ()
    }
  }
  for id in changed {
    tell(id, tree.draws_round(id), false)
  }
  for id in ordered {
    tell(id, false, false)
  }
  for id in placed {
    tell(id, true, true)
    // (what holds it fading what it holds by how far that reaches past it (View::cuts_softly): drawn again with it)
    let mut h = tree.holder_of(id)
    while h is Some(o) {
      if tree.cuts_softly(o) {
        tell(o, true, true)
        break
      }
      h = tree.holder_of(o)
    }
  }
  for id in removed {
    match scene.reach.get(id) {
      Some(e) => scene.parts.add(e.reach.rect())
      None => ()
    }
    scene.reach.remove(id)
    // (the layer it was drawn in, what holds that, drawn again without it; none kept that drew it, where it drew: the
    // tree cannot draw the frame alone without it, scene_alone_may)
    let kept = match scene.drawn_in.get(id) {
      Some(l) if l != id =>
        if scene.layers.contains(l) {
          scene_mark(l)
          true
        } else {
          false
        }
      _ =>
        match scene.layers.get(id) {
          // (a layer: what drew it drawn again without it; where its instances are not among that one's (a layer raised
          // over the window, drawn in its stack), drawing that again leaves them, and the tree cannot draw the frame alone)
          Some(x) =>
            match x.outer {
              Some(o) if scene.layers.get(o) is Some(ol) => {
                scene_mark(o)
                scene_holds_all(ol, x)
              }
              _ => false
            }
          // (drawn in no layer kept, nor one itself: nothing of it in what the scene keeps)
          None => scene.drawn_in.get(id) is None
        }
    }
    if !kept {
      scene.removed_unkept = scene.removed_unkept + 1
    }
    scene.drawn_in.remove(id)
    match scene.layers.get(id) {
      Some(l) => {
        scene_layer_gone(l)
        scene.layers.remove(id)
      }
      None => ()
    }
    scene.removed = scene.removed + 1
  }
}

///|
/// Layer `id` to be drawn again, what holds it with it not copied whole.
fn scene_mark(id : @view.NodeId) -> Unit {
  scene.marked[id] = true
  let mut at = match scene.layers.get(id) {
    Some(l) => l.outer
    None => None
  }
  while at is Some(o) && !scene.holding.contains(o) {
    scene.holding[o] = true
    at = match scene.layers.get(o) {
      Some(l) => l.outer
      None => None
    }
  }
}

///|
/// Layer `id` placed otherwise (moved, faded, turned in what holds it), nothing of it made again: drawn where it is put
/// now as it keeps how it is drawn (scene_entries_kept, where its node is as opaque and as big as it was), what holds it
/// not copied whole (it is elsewhere in it).
fn scene_moved_layer(id : @view.NodeId) -> Unit {
  scene.moved_layers[id] = true
  let mut at = match scene.layers.get(id) {
    Some(l) => l.outer
    None => None
  }
  while at is Some(o) && !scene.holding.contains(o) {
    scene.holding[o] = true
    at = match scene.layers.get(o) {
      Some(l) => l.outer
      None => None
    }
  }
}

///|
/// Whether the frame being drawn is a check's (drawn anew to be compared: Ctx::scene_check, looks_check's frame built
/// whole): the tree as it is, nothing told it taken.
fn scene_checking() -> Bool {
  scene.checking || looks_rebuilt.val
}

///|
/// Why a frame the old frame painted was (the first six since a test cleared them, for it to say: scene_alone_why),
/// worked out only while they are kept.
fn scene_full_for(why : () -> String) -> Unit {
  if scene.full_whys.length() < 6 {
    scene.full_whys.push(why())
  }
}

///|
/// Whether the tree changed since the frame before (or a layer's drawing read what changed): a frame is to draw it.
fn scene_wanted() -> Bool {
  !scene.due.is_empty() || !scene.marked.is_empty() || scene.removed > 0
}

///|
/// The watch a layer's drawing is read under: told, the layer is drawn again, and a frame asked for it.
fn scene_watch(id : @view.NodeId) -> @signals.Watch {
  @signals.watch(fn() {
    match scene.layers.get(id) {
      Some(l) => {
        l.told = true
        // (what an old view's paint read: the old frame's to paint again, frame_drawn)
        if l.own_only {
          scene.old_told = true
        }
      }
      None => ()
    }
    scene_mark(id)
    if !in_frame.val {
      h_frame_owed()
    }
  })
}

///|
/// Node `id` drawn now: in the layer being drawn (scene_told marks it where `id` is let go).
fn scene_node_drawn(id : @view.NodeId) -> Unit {
  match scene.drawing {
    Some(l) => scene.drawn_in[id] = l.id
    None => ()
  }
}

///|
/// Something drawn now otherwise than by the tree alone (an old view, glass, a native view, the old frame's layers):
/// the layer being drawn is never copied nor drawn again alone.
fn scene_own_only() -> Unit {
  match scene.drawing {
    Some(l) => l.own_only = true
    None => ()
  }
}

///|
/// A glyph of what is being drawn now that there was no room for in the atlas (drawn without it): the layer drawn again
/// by the next frame (text.mbt's glyph).
fn scene_glyph_wanted() -> Unit {
  match scene.drawing {
    Some(l) => if !scene.again.contains(l.id) { scene.again.push(l.id) }
    None => ()
  }
}

///|
/// The layers that wanted a glyph drawn again from here on (scene_glyph_wanted).
fn scene_again() -> Unit {
  let again = scene.again.copy()
  scene.again.clear()
  for id in again {
    if scene.layers.contains(id) {
      scene_mark(id)
    }
  }
}

///|
/// Something drawn now that is drawn again each frame what holds it is (a field's caret and words, as its editor has
/// them): the layer being drawn never copied nor drawn again alone.
fn scene_drawn_each() -> Unit {
  match scene.drawing {
    Some(l) => l.each = true
    None => ()
  }
}

///|
/// Glyph plot `plot` (in the colour atlas or not) drawn from by what is being drawn now: held with the layer.
fn scene_plot_drawn(colour : Bool, plot : Int) -> Unit {
  match scene.drawing {
    Some(l) => if !l.plots.iter().any(fn(p) { p.0 == colour && p.1 == plot }) { l.plots.push((colour, plot)) }
    None => ()
  }
}

///|
/// Picture `src` asked for at `px` pixels by what is being drawn now: asked for again wherever the layer is copied.
fn scene_image_asked(src : String, px : Double) -> Unit {
  match scene.drawing {
    Some(l) => if !l.images.iter().any(fn(i) { i.0 == src && i.1 == px }) { l.images.push((src, px)) }
    None => ()
  }
}

///|
/// As the old frame's paint begins (frame_paint): the last frame's shapes' pieces kept (what is copied of its scene
/// takes its pieces from them), the frame's own begun anew in the other.
fn scene_segs_kept(c : Ctx) -> Unit {
  let spare = scene.prev_segs
  scene.prev_segs = c.segs
  spare.clear()
  c.segs = spare
}

///|
/// What the frame is drawn by, as one line: another than the last's, the frame drawn whole, and nothing kept copied but
/// where only the window's size is another (Ctx::scene_begin).
fn scene_drawn_by(c : Ctx) -> DrawnBy {
  {
    w: c.window_w,
    h: c.window_h,
    scale: c.scale,
    ground: c.clear,
    atlas: atlas_now(),
    solid: glass_paint.solid,
    zoom: words_zoom.val,
  }
}

///|
/// What every instance kept was drawn for (scene_drawn_by): the window's scale, its ground, the atlas, glass drawn solid
/// or not, the words' zoom; and the window's size, which draws nothing kept otherwise (its edges cut what reaches past
/// them where each frame draws it), the window drawn whole for it.
priv struct DrawnBy {
  w : Double
  h : Double
  scale : Double
  ground : (Double, Double, Double)
  atlas : Int
  solid : Bool
  zoom : Double
} derive(Eq)

///|
let drawn_by_none : DrawnBy = {
  w: -1.0,
  h: -1.0,
  scale: 0.0,
  ground: (0.0, 0.0, 0.0),
  atlas: -1,
  solid: false,
  zoom: 0.0,
}

///|
/// As a frame the old frame paints begins (view_paint): the last frame's instances kept to copy from, this frame's
/// into the other buffer; drawn whole where what draws it changed.
fn Ctx::scene_begin(self : Ctx) -> Unit {
  scene.frame = scene.frame + 1
  scene_work.full = scene_work.full + 1
  scene.copy_why = ""
  if !scene_checking() {
    scene_full_for(fn() {
      "due \{scene.due.length()} marked \{scene.marked.length()}: " +
      scene.due.iter().take(6).map(fn(d) { "\{d.at}" }).collect().join(",")
    })
  }
  // (the last frame's, kept: what is copied of it; the frame's own drawn into the other)
  let was = self.inst
  self.inst = if scene.prev.length() >= was.length() { scene.prev } else { FixedArray::make(was.length(), 0.0) }
  scene.prev = was
  // (as many as the last frame drew: frame_paint begins again from none before it is gone through)
  scene.prev_n = scene.last_n
  self.ninst = 0
  // (as it was drawn: where the old frame's looks by the clock were applied over it after, the base they were applied
  // over (looks_keep), what is copied of it moved by them again as they are applied to this frame)
  scene.src = if looks_base.looks && looks_base.n >= scene.prev_n { looks_base.inst } else { scene.prev }
  scene.src_n = scene.prev_n
  scene.src_segs = scene.prev_segs
  scene.src_seen = scene.frame - 1
  let by = scene_drawn_by(self)
  if by != scene.drawn_by {
    // (the window's size alone another: nothing kept drawn otherwise for it (what its edges cut is cut where each frame
    // draws it, what the window's size moves told where it is laid out), the window drawn whole)
    let sized = { ..by, w: scene.drawn_by.w, h: scene.drawn_by.h } == scene.drawn_by
    // (another scale or ground, the atlas made anew: drawn whole, nothing kept; what held the atlas's plots holds
    // nothing of one made anew)
    let atlas_anew = scene.drawn_by.atlas != by.atlas
    if atlas_anew {
      for _, l in scene.layers {
        l.plots.clear()
      }
    }
    if !sized {
      scene_drop_all()
    }
    scene.drawn_by = by
    scene.parts.whole(if scene.prev_n == 0 { 1 } else if atlas_anew { 4 } else { 3 })
  }
  // (a shot at another size: everything drawn anew; who drew what kept with each layer's block, Ctx::scene_block_kept)
  scene.fresh = scene.fresh || looks_rebuilt.val || words_zoom.val != 1.0
  // (what is kept draws from the atlas still: said so before anything of this frame places a glyph)
  if !scene.fresh {
    scene_plots_drawn()
  }
  // (who drew the last frame's, where that is kept: put with what is copied of it)
  scene.owners = if inst_owners_kept() && !scene.fresh { Some(owners_run(0, scene.prev_n)) } else { None }
  scene.old_now.clear()
}

///|
/// The frame drawn (view_paint and what the old frame paints after it, frame_paint): what was said of it to change
/// drawn where it reaches now; what of the old frame may have changed drawn where it was and where it is; layers no
/// longer in it let go; its captures of glass and its streams found.
fn Ctx::scene_end(self : Ctx) -> Unit {
  scene.last_n = self.ninst
  scene.fresh = false
  // (a check's frame: what was told since is the next frame's, nothing of it said or taken here)
  if !scene_checking() {
    for id in scene.due {
      match scene.reach.get(id) {
        Some(e) => scene.parts.add(e.reach.rect())
        None => ()
      }
    }
    scene.due.clear()
    scene.marked.clear()
    scene.holding.clear()
    scene.moved.clear()
    scene.moved_layers.clear()
    scene.removed = 0
    scene.removed_unkept = 0
    scene_again()
    // (nothing kept clear over the scrim this frame: where it was drawn so, drawn again)
    if !scene.over_scrim_said {
      scene_over_scrim(@damage.nowhere)
    }
  }
  scene.over_scrim_said = false
  if scene.old_due {
    // (each old view's drawn again where what it draws differs from what it drew the last time: it says nothing of
    // what changed in it, Parts::add_changed; one drawn first, or no longer drawn, where all of it is or was)
    for k, r in scene.old_now {
      match (scene.old_insts_before.get(k), scene.old_insts_now.get(k)) {
        (Some((b, nb)), Some(a)) => {
          let now = FixedArray::from_array(a)
          scene.parts.add_changed(b, nb, now, a.length() / inst_size)
        }
        _ => {
          scene.parts.add(r)
          match scene.old_before.get(k) {
            Some(b) => scene.parts.add(b)
            None => ()
          }
        }
      }
    }
    for k, b in scene.old_before {
      if !scene.old_now.contains(k) {
        scene.parts.add(b)
      }
    }
  }
  scene.old_before.clear()
  for k, r in scene.old_now {
    scene.old_before[k] = r
  }
  // (what each drew, kept as it drew it now; where the old frame was painted, one it no longer draws let go)
  for k, a in scene.old_insts_now {
    scene.old_insts_before[k] = (FixedArray::from_array(a), a.length() / inst_size)
  }
  if scene.old_due {
    let gone = []
    for k, _ in scene.old_insts_before {
      if !scene.old_insts_now.contains(k) {
        gone.push(k)
      }
    }
    for k in gone {
      scene.old_insts_before.remove(k)
    }
  }
  scene.old_insts_now.clear()
  // (what is no longer drawn let go)
  let gone = []
  for id, l in scene.layers {
    if l.seen != scene.frame {
      gone.push(id)
    }
  }
  for id in gone {
    match scene.layers.get(id) {
      Some(l) => scene_layer_gone(l)
      None => ()
    }
    scene.layers.remove(id)
  }
  // (the captures of glass and the streams, found once as the old frame paints all of it: neither is in a layer the
  // tree draws again alone)
  scene.captures.clear()
  scene.streams.clear()
  let a = self.inst
  for k in 0..<scene.seg_tail {
    match @damage.capture_of(a, k) {
      Some((id, r)) =>
        match scene.captures.search_by(fn(c) { c.0 == id }) {
          Some(j) => scene.captures[j] = (id, @damage.union(scene.captures[j].1, r))
          None => scene.captures.push((id, r))
        }
      None => ()
    }
    if @damage.shows_stream(a, k) {
      scene.streams.push(scene.parts.reach_of(a, k, k + 1))
    }
  }
}

///|
/// Instances `ranges` (in order, apart) of the `count` drawn moved after all the rest (Ctx::raise_ranges): the layers
/// drawn this frame where they are now; one cut apart, no longer where it was drawn (drawn again whole each time).
fn scene_raised(ranges : Array[(Int, Int)], count : Int) -> Unit {
  if ranges.is_empty() {
    return
  }
  let raised = ranges.fold(init=0, fn(n, r) { n + r.1 - r.0 })
  let moved_to = fn(k : Int) -> Int {
    let mut before = 0
    let mut j = 0
    while j < ranges.length() {
      let (r0, r1) = ranges[j]
      if k < r0 {
        return k - before
      }
      if k < r1 {
        return count - raised + before + (k - r0)
      }
      before = before + (r1 - r0)
      j = j + 1
    }
    k - before
  }
  for _, l in scene.layers {
    if l.seen != scene.frame || l.start < 0 || l.count == 0 {
      continue
    }
    let s = moved_to(l.start)
    let e = moved_to(l.start + l.count - 1)
    if e - s == l.count - 1 {
      l.start = s
    } else {
      // (parted by it: no block of its own in the frame's order, nor of what holds it; drawn each frame, as what is
      // moved after it is drawn is, scene_shifted)
      l.start = -1
      let mut at : SceneLayer? = Some(l)
      while at is Some(x) {
        x.each = true
        at = match x.outer {
          Some(o) => scene.layers.get(o)
          None => None
        }
      }
    }
  }
}

///|
/// What the old frame draws from instance `from` on, as the frame is drawn now (an old view's, `island`; the old frame's
/// own, none): as far as it reaches, what of the old frame may change where the old frame is painted again.
fn Ctx::scene_old_drawn(self : Ctx, island : @view.NodeId?, from : Int) -> Unit {
  if self.ninst <= from {
    return
  }
  let r = scene.parts.reach_of(self.inst, from, self.ninst)
  scene.old_now[island] = match scene.old_now.get(island) {
    Some(b) => @damage.union(b, r)
    None => r
  }
  let kept = match scene.old_insts_now.get(island) {
    Some(a) => a
    None => {
      let a = []
      scene.old_insts_now[island] = a
      a
    }
  }
  for j in (from * inst_size)..<(self.ninst * inst_size) {
    kept.push(self.inst[j])
  }
}

///|
/// The clip painted in now, kept (clip_stack's level, whether it is the window's, its outer apart).
fn clip_kept() -> (FixedArray[Double], Bool, Bool) {
  let k = clip_top()
  let level = FixedArray::make(clip_n, 0.0)
  for j in 0..<clip_n {
    level[j] = clip_stack[k + j]
  }
  (level, clip_is_window(k), clip_is_apart(k))
}

///|
/// A clip kept (clip_kept) pushed as it was: what is painted till it is popped cut as it was then.
fn clip_put_back(level : FixedArray[Double], window : Bool, apart : Bool) -> Unit {
  for j in 0..<clip_n {
    clip_stack.push(level[j])
  }
  clip_say_apart(apart)
  clip_say_window(window)
}

///|
/// Layer `id` not copied, for `why` (the first of the frame's said: scene_alone_why).
fn copy_not(id : @view.NodeId, why : String) -> Bool {
  if scene.copy_why == "" {
    scene.copy_why = "\{id.at}: \{why}"
  }
  false
}

///|
/// Layer `id` kept as it was drawn last frame and copied into this one where it is put now, all it holds with it, at
/// the frame's end: whether it was (it is in the scene, nothing of it changed, nothing it is drawn in changed, and it
/// is no layer drawn otherwise than by the tree alone). `forced`: what holds it was drawn again whole.
fn Ctx::scene_copied(
  self : Ctx,
  p : TreePaint,
  id : @view.NodeId,
  forced : Bool,
  held : (Double, Double, Double, Double, Double, Double),
  fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))],
  stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)],
  glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))],
) -> Bool {
  guard !scene.fresh else { return copy_not(id, "nothing kept") }
  guard !forced else { return copy_not(id, "what holds it drawn whole") }
  guard scene.layers.get(id) is Some(l) else { return copy_not(id, "not kept") }
  guard l.seen >= 0 && l.seen >= scene.frame - 1 else { return copy_not(id, "seen \{l.seen}, of \{scene.frame}") }
  guard !l.own_only else { return copy_not(id, "own only") }
  guard !l.each else { return copy_not(id, "drawn each frame") }
  guard !inst_owners_kept() || l.block_owners is Some(_) else {
    return copy_not(id, "who drew it not kept")
  }
  guard !l.told && !scene.marked.contains(id) else { return copy_not(id, "marked, told \{l.told}") }
  // (placed otherwise: what its node's place draws of it (turned, its ground drawn in a box of its own, what it holds
  // faded, stretched, glyphed by it) may be another where it is drawn in the same place; drawn as it keeps how it is
  // drawn, its node's place as it is now)
  guard !scene.moved_layers.contains(id) else { return copy_not(id, "placed otherwise") }
  // (what it was drawn in, as it is drawn in now: its key; another, drawn anew)
  guard scene_began_same(l, held, fading, stretching, glyphing) else { return copy_not(id, "drawn in otherwise") }
  // (from its own block and those of what it holds, each by its reference: Ctx::scene_emitted; its pictures kept as
  // shown, asked again)
  self.scene_emitted(p, l)
  let n = l.count
  scene_work.copied = scene_work.copied + 1
  scene_work.copied_insts = scene_work.copied_insts + n
  true
}

///|
/// Whether layer `l` is drawn in now what it was drawn in as it began (the clip painted in, the fades, stretches and
/// glyph looks of what holds it, where its node is drawn): what its kept instances were made in, the key they are kept
/// by.
fn scene_began_same(
  l : SceneLayer,
  held : (Double, Double, Double, Double, Double, Double),
  fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))],
  stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)],
  glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))],
) -> Bool {
  if l.held != held || l.scrim != !dr.scrims.is_empty() || l.fading != fading || l.stretching != stretching || l.glyphing.length() != glyphing.length() {
    return false
  }
  for i, g in glyphing {
    if g.0 != l.glyphing[i].0 || g.2 != l.glyphing[i].2 {
      return false
    }
  }
  let k = clip_top()
  for j in 0..<clip_n {
    if clip_stack[k + j] != l.clip[j] {
      return false
    }
  }
  clip_is_window(k) == l.clip_window && clip_is_apart(k) == l.clip_apart
}

///|
/// Where layer `l`'s node is drawn now, as the layer that holds it was last drawn (where that one's node was, and where
/// this one is in it as the tree has it now, composed as the paint composes it: Tree::placed_in); the root where the
/// tree says. None where what holds it is no longer kept, or no longer holds it.
fn scene_place_now(tree : @view.Tree, l : SceneLayer) -> (Double, Double, Double, Double, Double, Double)? {
  if l.id.at == 0 {
    return Some(tree.root_place())
  }
  guard l.outer is Some(o) && scene.layers.get(o) is Some(ol) else { return None }
  // (what holds it where the tree has it now, out to the root: never where that was last drawn, which it may have been
  // placed away from since without being drawn)
  guard scene_place_now(tree, ol) is Some((ox, oy, oa, os, oux, ouy)) else { return None }
  match tree.placed_in(l.id, o.at, oa, os) {
    Some((x, y, a, s, ux, uy)) => Some((ox + x, oy + y, a, s, oux + ux, ouy + uy))
    None => None
  }
}

///|
/// Layer `id` drawn by `draw` (it draws it and all it holds, the layers in it each copied or drawn in turn), what it
/// reads followed by its own watch: kept as this frame has it, its glyphs' plots held, what is drawn of it told where
/// it reaches. `inner_of`: the layer drawn round it (none: the root).
fn Ctx::scene_drawn(
  self : Ctx,
  id : @view.NodeId,
  outer : SceneLayer?,
  held : (Double, Double, Double, Double, Double, Double),
  fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))],
  stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)],
  glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))],
  watched? : Bool = true,
  draw : () -> Unit,
) -> SceneLayer {
  let l = match scene.layers.get(id) {
    Some(l) => l
    None => {
      let (clip, window, apart) = clip_kept()
      let l : SceneLayer = {
        id,
        start: 0,
        count: 0,
        seg_from: 0,
        seg_count: 0,
        bands: [],
        anchors: [],
        inner: [],
        outer: None,
        clip,
        clip_window: window,
        clip_apart: apart,
        fading: [],
        stretching: [],
        glyphing: [],
        held,
        scrim: false,
        reach: @damage.nowhere,
        watch: None,
        told: false,
        own_only: false,
        each: false,
        plots: [],
        images: [],
        reads_clock: false,
        seen: -1,
        entries: None,
        entries_as: (1.0, 1.0),
        block: FixedArray::make(0, 0.0),
        block_n: 0,
        block_segs: [],
        block_seg_base: 0,
        block_owners: None,
        block_refs: [],
      }
      scene.layers[id] = l
      l
    }
  }
  scene_drawn_begin(l, outer, held, fading, stretching, glyphing, false)
  // (the glyphs' plots it draws from held anew as it draws them)
  l.plots.clear()
  let k0 = self.ninst
  let s0 = self.segs.length() / 4
  let was = scene.drawing
  scene.drawing = Some(l)
  if watched {
    let w = match l.watch {
      Some(w) => w
      None => {
        let w = scene_watch(id)
        l.watch = Some(w)
        w
      }
    }
    w.read(draw)
  } else {
    // (what it reads followed by what draws it: the root's, by the old frame's paint)
    draw()
  }
  scene.drawing = was
  self.scene_drawn_end(l, outer, k0, s0)
  l
}

///|
/// Layer `l` drawn where `place` says its node is, `depth` deep, in what holds it (`outer`), as it keeps how it is drawn
/// (scene_entries_kept): its entries gone through alone (Ctx::tree_walk), nothing of the tree gone through, nothing
/// made but what was out of sight as it was drawn and is not now, nothing of what draws a node asked of the tree again
/// but its own node's (SceneEntry). What it reads stays followed as its walk read it: its drawing reads nothing anew
/// that the walk did not (each node's instances as kept), so nothing of it is read under its watch again; but where
/// what it holds draws otherwise than by the tree alone, or each frame (an old view, glass, a field: what each reads
/// as it is drawn, read anew), its watch reads all it reads again, as its walk did. Kept as this frame has it, its
/// glyphs' plots held as they were, drawn from through this frame.
fn Ctx::scene_replayed(
  self : Ctx,
  p : TreePaint,
  l : SceneLayer,
  outer : SceneLayer?,
  place : (Double, Double, Double, Double, Double, Double),
  depth : Int,
) -> Unit {
  // (as last drawn: whether what it holds draws otherwise than by the tree alone (its plots not held then: an old
  // view's the old frame's), or each frame)
  let own = l.own_only
  let each = l.each
  scene_drawn_begin(l, outer, place, p.fading, p.stretching, p.glyphing, true)
  if !own {
    for pl in l.plots {
      let (a, _) = atlas_for(pl.0)
      if a.sized() {
        a.drawn(pl.1)
      }
    }
  }
  let k0 = self.ninst
  let s0 = self.segs.length() / 4
  let was = scene.drawing
  scene.drawing = Some(l)
  let was_held = scene_blocks_held.val
  scene_blocks_held.val = !own
  let entries = l.entries
  match l.watch {
    Some(w) if own || each => w.read(fn() { self.tree_walk(p, l.id.at, place, depth, entries) |> ignore })
    Some(_) => {
      let was_sub = @signals.set_active_sub(None)
      self.tree_walk(p, l.id.at, place, depth, entries) |> ignore
      @signals.set_active_sub(was_sub) |> ignore
    }
    // (what it reads followed by what draws it: an old view's, as its walk's was)
    None => self.tree_walk(p, l.id.at, place, depth, entries) |> ignore
  }
  scene_blocks_held.val = was_held
  scene.drawing = was
  self.scene_drawn_end(l, outer, k0, s0)
}

///|
/// Whether the layer drawn now, as it keeps how it is drawn (scene_replayed), holds the glyphs' plots its nodes'
/// instances draw from (SceneLayer's `plots`: not an old view's, whose are the old frame's): each node's instances as it
/// keeps them drawn from them, as a layer copied draws from them, none of their glyphs looked up again.
// kept across runs: set and put back within each layer drawn so
let scene_blocks_held : Ref[Bool] = Ref(false)

///|
/// As layer `l` is drawn (scene_drawn, scene_replayed): kept with what it is drawn in now (the clip painted in, the
/// fades, stretches and glyph looks of what holds it, where its node is drawn), what it holds told anew as it is drawn.
/// `kept`: drawn as it keeps how it is drawn, what it is drawn in kept as it was where it is the same (nothing made of
/// it).
fn scene_drawn_begin(
  l : SceneLayer,
  outer : SceneLayer?,
  held : (Double, Double, Double, Double, Double, Double),
  fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))],
  stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)],
  glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))],
  kept : Bool,
) -> Unit {
  if !kept || !scene_clip_same(l) {
    let (clip, window, apart) = clip_kept()
    l.clip = clip
    l.clip_window = window
    l.clip_apart = apart
  }
  if !kept || l.fading != fading {
    l.fading = fading.copy()
  }
  if !kept || l.stretching != stretching {
    l.stretching = stretching.copy()
  }
  // (the looks themselves no numbers to compare: taken as they are)
  if !kept || !glyphing.is_empty() || !l.glyphing.is_empty() {
    l.glyphing = glyphing.copy()
  }
  l.held = held
  l.scrim = !dr.scrims.is_empty()
  l.own_only = false
  l.each = false
  l.told = false
  l.inner.clear()
  l.anchors.clear()
  // (drawn again alone, from what it began in: what holds it as it was)
  match outer {
    Some(o) => l.outer = Some(o.id)
    None => if l.id.at == 0 { l.outer = None }
  }
  l.images.clear()
  l.reads_clock = false
}

///|
/// Whether the clip painted in now is the one layer `l` was drawn in as it began (its level, whether it is the
/// window's, its outer apart).
fn scene_clip_same(l : SceneLayer) -> Bool {
  let k = clip_top()
  for j in 0..<clip_n {
    if clip_stack[k + j] != l.clip[j] {
      return false
    }
  }
  clip_is_window(k) == l.clip_window && clip_is_apart(k) == l.clip_apart
}

///|
/// Layer `l` drawn (scene_drawn, scene_replayed), its instances from `k0` and its shapes' pieces from `s0`: kept as
/// this frame has it, told what holds it (`outer`).
fn Ctx::scene_drawn_end(self : Ctx, l : SceneLayer, outer : SceneLayer?, k0 : Int, s0 : Int) -> Unit {
  if l.reads_clock {
    scene.clock_read = true
  }
  // (what holds it: as own only as anything it holds, and what it holds below it)
  match outer {
    Some(o) => {
      o.inner.push(l.id)
      if l.own_only {
        o.own_only = true
      }
      if l.each {
        o.each = true
      }
    }
    None => ()
  }
  l.start = k0
  l.count = self.ninst - k0
  l.seg_from = s0
  l.seg_count = self.segs.length() / 4 - s0
  l.seen = scene.frame
  // (all it drew kept as its own, what it is copied from where it is kept)
  self.scene_block_kept(l, k0, s0)
  // (the host's controls it drew, each by its instance from its first: where it is put, the same)
  for i, a in l.anchors {
    l.anchors[i] = (a.0, a.1 - k0)
  }
  anchors_layer_said(l)
  // (an old view's plots the old frame's, drawn from each frame it paints)
  if l.own_only {
    l.plots.clear()
  }
  scene_work.layers = scene_work.layers + 1
  // (its own: what it holds that are layers counted as each is drawn or copied)
  let mut own = l.count
  for i in l.inner {
    match scene.layers.get(i) {
      Some(x) => own = own - x.count
      None => ()
    }
  }
  scene_work.recorded = scene_work.recorded + own
}

///|
/// The clock read where what reads it is followed (frame_watch.mbt clock_read): the layer being drawn, drawn again
/// each frame the clock goes (its watch told by the frame's clock), the frames asked for as it goes.
fn scene_clock_read_now() -> Unit {
  match scene.drawing {
    Some(l) => l.reads_clock = true
    None => ()
  }
}

///|
/// A wake at `t` asked as a layer is drawn (Ctx::wake_at_time, as the frame paints): that layer's, drawn again then;
/// whether it was one's (none: the old frame's paint's, frame_watch.mbt looks_wake).
fn scene_wake_said(t : Double) -> Bool {
  match scene.drawing {
    Some(l) if l.watch is Some(_) => {
      scene.wakes.push((t, l.id))
      true
    }
    _ => false
  }
}

///|
/// As a frame at `t` begins: the layers whose moments came by then drawn again; the soonest still to come woken for
/// (`c.wake_at`) as the frame ends.
fn Ctx::scene_wakes(self : Ctx, t : Double) -> Unit {
  let left = []
  for w in scene.wakes {
    if w.0 <= t {
      if scene.layers.contains(w.1) {
        scene_mark(w.1)
      }
    } else {
      left.push(w)
    }
  }
  scene.wakes.clear()
  scene.wakes.append(left)
  ignore(self)
}

///|
/// The soonest moment a layer's drawing waits for, put into what the frame wakes for (on_frame, as it ends).
fn Ctx::scene_wake_into(self : Ctx) -> Unit {
  for w in scene.wakes {
    if self.wake_at <= 0.0 || w.0 < self.wake_at {
      self.wake_at = w.0
    }
  }
  if scene.clock_read {
    // (a layer reads the clock: drawn again as it goes, on the host's next frame)
    self.motion_left = true
  }
  scene.clock_read = false
}

///|
/// What every layer drew is no longer what it shows (the glyphs forgotten, the atlas made anew: the same numbers over
/// other pixels): nothing kept, the next frame drawn whole. `atlas_gone`: the atlas its plots were held in is no more.
fn scene_anew(atlas_gone : Bool) -> Unit {
  if atlas_gone {
    for _, l in scene.layers {
      l.plots.clear()
    }
  }
  scene_drop_all()
  scene.parts.whole(4)
}

///|
/// The parts the frame presented now is drawn again in, said by its causes (h_present): what showed a stream's picture
/// too (it changes under the same numbers), the captures of glass a part reaches taken in whole.
fn Ctx::scene_parts_taken(self : Ctx) -> Array[(Double, Double, Double, Double)] {
  for r in scene.streams {
    scene.parts.add(r)
  }
  let parts = scene.parts.take(self.window_w, self.window_h, scene.captures.map(fn(c) { c.1 }))
  if !parts.is_empty() {
    scene.told_parts = parts
  }
  parts
}

///|
/// The old frame's cycles by the clock applied (Ctx::cycle_looks): where each drew what it moves before and where it
/// draws it now, drawn again (`now`: each cycle's box as applied).
fn scene_cycled(now : Array[(Double, Double, Double, Double)]) -> Unit {
  for r in scene.cycled {
    scene.parts.add(r)
  }
  for r in now {
    scene.parts.add(r)
  }
  scene.cycled.clear()
  scene.cycled.append(now)
}

///|
/// What of the tree is drawn over the old frame's scrim kept clear of what comes up over it, reaching `now` (as far as
/// all of it reaches, moved): drawn again where it was and where it is.
fn scene_over_scrim(now : (Double, Double, Double, Double)) -> Unit {
  scene.parts.add(scene.over_scrim)
  scene.parts.add(now)
  scene.over_scrim = now
  scene.over_scrim_said = true
}

///|
/// Instances `ranges` of this frame's moved after they were drawn (what is over the scrim kept clear of what comes up
/// over it, Ctx::tree_over_scrim_clear): the layers drawn in them kept as moved, never copied nor drawn alone as kept (they
/// would be moved again), drawn each frame.
fn scene_shifted(ranges : Array[(Int, Int)]) -> Unit {
  for _, l in scene.layers {
    if l.seen != scene.frame || l.start < 0 || l.count == 0 {
      continue
    }
    if ranges.iter().any(fn(r) { l.start < r.1 && r.0 < l.start + l.count }) {
      l.each = true
    }
  }
}

///|
/// A Tester's check of every frame that copied a layer kept (looks_check: every test holds it): the frame painted again
/// with nothing kept, every layer drawn anew, must come out the same, instance for instance. One that parts from it is
/// a layer something of changed and nothing told (a read not followed, a cause not said): the test fails, saying where.
/// `copied`: the layers copied before the frame.
fn Ctx::scene_check(self : Ctx, copied : Int) -> Unit {
  guard frame_checked() &&
    (scene_work.copied > copied || tree_alone_drawn.val) &&
    view_app.val is Some(tree) &&
    // (told something since it was drawn (what the frame published after it painted: where an anchor is, what its
    // build asked): the tree is no longer what the frame drew, and the next frame draws what changed and is checked)
    !tree.told_since() &&
    !tree.scene_told_since() &&
    !scene_wanted() else {
    return
  }
  let n = self.ninst
  let kept = FixedArray::make(n * inst_size + 1, 0.0)
  self.inst.blit_to(kept, len=n * inst_size)
  let layers : Array[(@view.NodeId, Int, Int)] = []
  // (what a layer holding an old view draws of its own: the old frame's, never kept, painted where the old frame has
  // its views then (old_place), which the frame's end may have moved since; not the scene's to answer for)
  let theirs = FixedArray::make(n, false)
  let least_at = FixedArray::make(n, 2147483647)
  for id, l in scene.layers {
    if l.seen == scene.frame && l.start >= 0 {
      layers.push((id, l.start, l.count))
      for k in l.start..<(l.start + l.count) {
        if k < n && l.count < least_at[k] {
          least_at[k] = l.count
          theirs[k] = l.own_only
        }
      }
    }
  }
  scene.fresh = true
  scene.checking = true
  let was = scene.old_due
  scene.old_due = false
  scene_unrecorded(fn() { paint_watch_of().read(fn() { frame_paint(self, paint_base.root, alone=true) }) })
  scene.old_due = was
  scene.checking = false
  let differs = {
    let least = if self.ninst < n { self.ninst } else { n }
    let mut at = -1
    for q in 0..<(least * inst_size) {
      let (a, b) = (kept[q], self.inst[q])
      if a != b && !(a != a && b != b) && !theirs[q / inst_size] {
        at = q / inst_size
        break
      }
    }
    if at < 0 && self.ninst == n {
      None
    } else {
      let at = if at < 0 { least } else { at }
      // (the innermost layer it is in; none: the old frame's own)
      let mut who = "none (the old frame's)"
      let mut least_n = 2147483647
      for x in layers {
        let (id, s, k) = x
        if at >= s && at < s + k && k < least_n {
          least_n = k
          who = "\{id.at}.\{id.gen}"
        }
      }
      let slots = []
      if at < least {
        for j in 0..<inst_size {
          let (a, b) = (kept[at * inst_size + j], self.inst[at * inst_size + j])
          if a != b && !(a != a && b != b) {
            slots.push("\{j}: \{a} kept, \{b} anew")
          }
        }
      }
      let kind = if at < self.ninst { self.inst[at * inst_size + 5] } else { -1.0 }
      Some(
        "\{n} instances kept, \{self.ninst} drawn anew; instance \{at} (kind \{kind}) the first to differ, in the layer of node \{who}: \{slots.join(", ")}; the frame \{if tree_alone_drawn.val { "of the tree alone" } else { "the old frame painted" }}",
      )
    }
  }
  match differs {
    Some(said) => {
      let s = "the scene kept a layer something of changed unsaid: as kept and drawn anew, \{said}"
      println(s)
      abort(s)
    }
    None => ()
  }
}

///|
/// Who drew a run of instances (contrast.mbt's inst_owners: the node of the old view's, its glyph's cell, the node of
/// the tree's, what it is checked as, whether it is a bone), kept to go with them where they are put.
priv struct OwnersRun {
  owner : Array[Int]
  cell : Array[(Double, Double)]
  tree : Array[@view.NodeId?]
  mark : Array[Int]
  bone : Array[Bool]
}

///|
/// Who drew instances `from` until `to`, as kept now.
fn owners_run(from : Int, to : Int) -> OwnersRun {
  let o = inst_owners
  let at = fn(a : Array[Int], k : Int, none : Int) { if k < a.length() { a[k] } else { none } }
  {
    owner: Array::makei(to - from, fn(i) { at(o.owner, from + i, -1) }),
    cell: Array::makei(to - from, fn(i) { if from + i < o.cell.length() { o.cell[from + i] } else { (0.0, 1.0) } }),
    tree: Array::makei(to - from, fn(i) { if from + i < o.tree.length() { o.tree[from + i] } else { None } }),
    mark: Array::makei(to - from, fn(i) { at(o.mark, from + i, 0) }),
    bone: Array::makei(to - from, fn(i) { bone_insts.contains(from + i) }),
  }
}

///|
/// Who drew the instances from `n` on let go of: none of the frame's.
fn owners_cut(n : Int) -> Unit {
  let o = inst_owners
  if o.owner.length() > n {
    o.owner.truncate(n)
  }
  if o.cell.length() > n {
    o.cell.truncate(n)
  }
  if o.tree.length() > n {
    o.tree.truncate(n)
  }
  if o.mark.length() > n {
    o.mark.truncate(n)
  }
  let gone = bone_insts.iter().filter(fn(k) { k >= n }).collect()
  for k in gone {
    bone_insts.remove(k)
  }
}

///|
/// Who drew `run` said of the instances from `at` on, as it was of theirs.
fn owners_put(run : OwnersRun, at : Int) -> Unit {
  let (was, was_tree) = (inst_owners.painting, inst_owners.tree_painting)
  for i in 0..<run.owner.length() {
    let k = at + i
    inst_owners.painting = run.owner[i]
    inst_owners.tree_painting = run.tree[i]
    inst_owned(k)
    inst_owners.cell[k] = run.cell[i]
    inst_owners.mark[k] = run.mark[i]
    if run.bone[i] {
      bone_insts.add(k)
    } else {
      bone_insts.remove(k)
    }
  }
  inst_owners.painting = was
  inst_owners.tree_painting = was_tree
}

///|
/// Where the frame drawn has the layers of the window's tree drawn by it alone (not the old frame's: none drawn
/// otherwise), the outermost, in order: what the old frame's paint does not draw (frame_watch.mbt's looks_keep).
fn scene_tree_spans() -> Array[(Int, Int)] {
  let all : Array[(Int, Int)] = []
  for _, l in scene.layers {
    if l.seen == scene.frame && l.start >= 0 && l.count > 0 && !l.own_only {
      all.push((l.start, l.start + l.count))
    }
  }
  all.sort_by(fn(a, b) { a.0.compare(b.0) })
  let out : Array[(Int, Int)] = []
  for r in all {
    match out.last() {
      Some(o) if r.0 < o.1 => out[out.length() - 1] = (o.0, if r.1 > o.1 { r.1 } else { o.1 })
      _ => out.push(r)
    }
  }
  out
}

///|
/// Whether layer `o`'s instances, as the frame has them, hold all of layer `x`'s (what drawing `o` again draws again
/// of `x`: not where `o` draws it elsewhere, raised over the window in its stack).
fn scene_holds_all(o : SceneLayer, x : SceneLayer) -> Bool {
  o.start >= 0 && x.start >= o.start && x.start + x.count <= o.start + o.count
}

///|
/// Where layers drawn again are not where the frame kept them, said, by each one's (node, where its instances began
/// and how many there were, where its pieces began and how many, how many instances and pieces it drew now, how many
/// it drew them into): one before 0, one with fewer than none, one begun before the one before it ends, one past the
/// frame's `tail` instances or its `pieces`, one drawn into fewer than it says it drew; None where the frame can be put
/// together round them (scene_spliced).
fn scene_spans_wrong(spans : Array[(Int, Int, Int, Int, Int, Int, Int, Int)], tail : Int, pieces : Int) -> String? {
  let order = spans.copy()
  order.sort_by(fn(a, b) { (a.1, a.2).compare((b.1, b.2)) })
  let mut end = 0
  let mut seg_end = 0
  for s in order {
    let (at, start, count, seg_from, seg_count, n, segs_now, room) = s
    let what = "layer \{at} at \{start} for \{count} (now \{n}), pieces at \{seg_from} for \{seg_count} (now \{segs_now})"
    if start < 0 || count < 0 || seg_from < 0 || seg_count < 0 || n < 0 {
      return Some(what + ": less than none")
    }
    if start < end || seg_from < seg_end {
      return Some(what + ": begun before the one before it ends, at \{end}, pieces at \{seg_end}")
    }
    if start + count > tail || seg_from + seg_count > pieces {
      return Some(what + ": past the frame's \{tail} instances, \{pieces} pieces")
    }
    if room < n {
      return Some(what + ": drawn into \{room} instances")
    }
    end = start + count
    seg_end = seg_from + seg_count
  }
  None
}

///|
/// What layer `l` drew now (its instances from `k0`, its shapes' pieces from `s0`) kept as its own block: its own
/// drawing alone, each layer it holds put there by a reference (where it goes in the block, and which), never what
/// that one drew (Flutter's PaintingContext appending a child's layer, Android's drawRenderNode of a child's). Its bands
/// (kind 11) among its own instances, by where they are in the block, and who drew each of its own where that is kept.
fn Ctx::scene_block_kept(self : Ctx, l : SceneLayer, k0 : Int, s0 : Int) -> Unit {
  // (drawn each frame: never put in as kept, no block)
  if l.each {
    l.block_n = 0
    l.block_segs.clear()
    l.block_refs.clear()
    l.bands.clear()
    l.block_owners = None
    return
  }
  // (the layers it holds, as this frame has them in it, in the order drawn)
  let held : Array[SceneLayer] = []
  for i in l.inner {
    match scene.layers.get(i) {
      Some(c) if c.seen == scene.frame && c.start >= k0 && c.start + c.count <= self.ninst => held.push(c)
      // (what it holds is what was drawn into it this frame, its inner cleared as it began: one not so is a fault,
      // never its instances taken for the holder's own)
      Some(c) =>
        @view.fault(
          "layer \{l.id.at} holds \{i.at} not drawn in it: seen \{c.seen} of \{scene.frame}, \{c.start}+\{c.count} outside \{k0}..\{self.ninst}",
        )
      None => @view.fault("layer \{l.id.at} holds \{i.at}, no layer kept")
    }
  }
  held.sort_by(fn(a, b) { a.start.compare(b.start) })
  let own = self.ninst - k0 - held.fold(init=0, fn(n, c) { n + c.count })
  if l.block.length() < own * inst_size {
    l.block = FixedArray::make(own * inst_size * 2 + inst_size, 0.0)
  }
  l.block_n = 0
  l.block_segs.clear()
  l.block_refs.clear()
  l.bands.clear()
  let owners : OwnersRun? = if inst_owners_kept() {
    Some({ owner: [], cell: [], tree: [], mark: [], bone: [] })
  } else {
    None
  }
  let take = fn(from : Int, to : Int, sfrom : Int, sto : Int) {
    if to > from {
      self.inst.blit_to(l.block, len=(to - from) * inst_size, src_offset=from * inst_size, dst_offset=l.block_n * inst_size)
      for k in from..<to {
        if self.inst[k * inst_size + 5] == 11.0 {
          l.bands.push(l.block_n + k - from)
        }
      }
      match owners {
        Some(o) => {
          let r = owners_run(from, to)
          o.owner.append(r.owner)
          o.cell.append(r.cell)
          o.tree.append(r.tree)
          o.mark.append(r.mark)
          o.bone.append(r.bone)
        }
        None => ()
      }
      l.block_n = l.block_n + to - from
    }
    for q in (sfrom * 4)..<(sto * 4) {
      l.block_segs.push(self.segs[q])
    }
  }
  let mut at = k0
  let mut sat = s0
  for c in held {
    take(at, c.start, sat, c.seg_from)
    l.block_refs.push((l.block_n, l.block_segs.length() / 4, c.id))
    at = c.start + c.count
    sat = c.seg_from + c.seg_count
  }
  take(at, self.ninst, sat, self.segs.length() / 4)
  l.block_seg_base = s0
  l.block_owners = owners
}

///|
/// Layer `l` put into the frame from its own block and those of the layers it holds, each where its reference in the
/// block says, in the order drawn (Flutter's compositing a layer's children by their references): where each is in the
/// frame said by this, its bands' first pieces told where its pieces are now, who drew each where that is kept.
fn Ctx::scene_emitted(self : Ctx, p : TreePaint, l : SceneLayer) -> Unit {
  let at = self.ninst
  let seg0 = self.segs.length() / 4
  // (its own pieces in the frame as they were in it as it was drawn: the same in between what it holds)
  let dseg = (seg0 - l.block_seg_base).to_double()
  let ip = Ref(0)
  let sp = Ref(0)
  let band = Ref(0)
  let put = fn(to : Int, sto : Int) {
    let n = to - ip.val
    if n > 0 {
      while (self.ninst + n + 1) * inst_size > self.inst.length() {
        self.grow()
      }
      let k = self.ninst
      l.block.blit_to(self.inst, len=n * inst_size, src_offset=ip.val * inst_size, dst_offset=k * inst_size)
      while band.val < l.bands.length() && l.bands[band.val] < to {
        let o = (k + l.bands[band.val] - ip.val) * inst_size
        self.inst[o + 12] = self.inst[o + 12] + dseg
        band.val = band.val + 1
      }
      match l.block_owners {
        Some(o) if inst_owners_kept() =>
          owners_put(
            {
              owner: o.owner[ip.val:to].to_owned(),
              cell: o.cell[ip.val:to].to_owned(),
              tree: o.tree[ip.val:to].to_owned(),
              mark: o.mark[ip.val:to].to_owned(),
              bone: o.bone[ip.val:to].to_owned(),
            },
            k,
          )
        _ => ()
      }
      self.ninst = k + n
    }
    for q in (sp.val * 4)..<(sto * 4) {
      self.segs.push(l.block_segs[q])
    }
    ip.val = to
    sp.val = sto
  }
  for r in l.block_refs {
    let (ri, rs, cid) = r
    put(ri, rs)
    match scene.layers.get(cid) {
      // (as kept where nothing of it changed; else drawn anew where its reference is, the rest of what holds it as kept:
      // Flutter's repaint boundary recorded alone, its parent's picture composited as it was)
      Some(c) => if scene_copyable(c) { self.scene_emitted(p, c) } else { self.scene_redrawn_in(p, l, c) }
      None => ()
    }
  }
  put(l.block_n, l.block_segs.length() / 4)
  l.start = at
  l.count = self.ninst - at
  l.seg_from = seg0
  l.seg_count = self.segs.length() / 4 - seg0
  l.seen = scene.frame
  for i in l.images {
    @signals.untracked(fn() { self.image_for(i.0, i.1) |> ignore })
  }
}

///|
/// Whether layer `l`, held by one put into the frame as kept, is put in as kept too (what Ctx::scene_copied asks of a
/// layer the walk reaches, but what it is drawn in: as its holder kept it, its holder's own drawing kept).
fn scene_copyable(l : SceneLayer) -> Bool {
  !scene.fresh &&
  l.seen >= 0 &&
  l.seen >= scene.frame - 1 &&
  !l.own_only &&
  !l.each &&
  (!inst_owners_kept() || l.block_owners is Some(_)) &&
  !l.told &&
  !scene.marked.contains(l.id) &&
  !scene.moved_layers.contains(l.id)
}

///|
/// Layer `c`, held by `l` put into the frame as kept, drawn anew where its reference in `l`'s block is: where the tree
/// has its node now (scene_place_now), in the clip, fades, stretches and glyph looks it was drawn in (its holder's, as
/// kept), as it keeps how it is drawn where that stands, else by a walk of the tree from it. Where the tree no longer
/// has it in its holder, nothing (as the walk leaves out what is out of its row).
fn Ctx::scene_redrawn_in(self : Ctx, by : TreePaint, l : SceneLayer, c : SceneLayer) -> Unit {
  let tree = by.tree
  guard scene_place_now(tree, c) is Some(place) else { return }
  clip_put_back(c.clip, c.clip_window, c.clip_apart)
  // (in the frame's paint: the old frame's root, what an old view it holds is painted by)
  let p = TreePaint::new(tree, by.root, false)
  for f in c.fading {
    p.fading.push(f)
    p.fade_depth.push(-1)
  }
  for s in c.stretching {
    p.stretching.push(s)
    p.stretch_depth.push(-1)
  }
  for g in c.glyphing {
    p.glyphing.push(g)
    p.glyph_depth.push(-1)
  }
  let was = scene.drawing
  scene.drawing = Some(l)
  match scene_entries_kept(c.id, place) {
    Some(k) => self.scene_replayed(p, k, None, place, 0)
    None => {
      let entries : Ref[Array[SceneEntry]] = Ref([])
      let m = self.scene_drawn(c.id, None, place, c.fading, c.stretching, c.glyphing, fn() {
        entries.val = self.tree_walk(p, c.id.at, place, 0, None)
      })
      scene_entries_keep(m, entries.val, place)
    }
  }
  scene.drawing = was
  pop_clip()
  // (what holds it as own only, as drawn each frame, as it now is: put in as kept no more)
  if c.own_only {
    l.own_only = true
  }
  if c.each {
    l.each = true
  }
}
