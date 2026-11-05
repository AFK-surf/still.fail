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
  mut bands : Array[Int]
  /// the host's controls put where it draws them (View::native_anchor): each one's number (native_anchor_number) and
  /// its instance, from its first; while it is drawn, the instance's place among the frame's (scene_anchor_drawn)
  mut anchors : Array[(Int, Int)]
  /// the layers it holds, at once below it: moved with it where it is copied; and the layer it is in at once
  mut inner : Array[@view.NodeId]
  mut outer : @view.NodeId?
  /// what it was drawn in as it began: the clip it was cut by (clip_stack's level, whether it is the window's, its
  /// outer apart from it), the fades, stretches and glyph looks of what holds it, and where what holds it is drawn
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
  mut plots : Array[(Bool, Int)]
  /// the pictures it shows, each as asked (source, pixels): asked again where it is copied, kept as shown
  mut images : Array[(String, Double)]
  /// its drawing read the clock (an image fading in): drawn again each frame the clock goes
  mut reads_clock : Bool
  /// the frame that last drew it (Scene's `frame`)
  mut seen : Int
}

///|
/// The scene of the window's tree, kept across frames.
priv struct Scene {
  layers : Map[@view.NodeId, SceneLayer]
  /// as far as each node drawn, and all it holds, reaches (as last drawn), and the layer it was drawn in
  reach : Map[@view.NodeId, (Double, Double, Double, Double)]
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
  /// while the tree tries to draw a frame alone (scene_alone): each layer drawn or moved, as it was before, put back
  /// where it cannot (where it is, what it holds: what the frame the old frame paints then copies by)
  mut trying : Bool
  undo : Array[(SceneLayer, SceneLayer)]
  /// layers to draw again the frame after this (a glyph of theirs there was no room for in the atlas)
  again : Array[@view.NodeId]
  /// where what the last frame of the tree alone drew again reaches now (a test's to say)
  mut alone_reach : (Double, Double, Double, Double)
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
  trying: false,
  undo: [],
  again: [],
  alone_reach: (1.0e18, 1.0e18, -1.0e18, -1.0e18),
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
  scene.undo.clear()
  scene.trying = false
  scene.owners = None
  scene.src_n = 0
  scene.src_seen = -1
  scene.alone_reach = @damage.nowhere
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
fn scene_told(
  tree : @view.Tree,
  changed : Array[@view.NodeId],
  placed : Array[@view.NodeId],
  removed : Array[@view.NodeId],
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
  let tell = fn(id : @view.NodeId, moved : Bool) {
    match scene.reach.get(id) {
      Some(r) => scene.parts.add(r)
      None => ()
    }
    scene.due.push(id)
    if moved {
      scene.moved[id] = true
    }
    // (the layer it is drawn in: itself where it begins one, else the nearest holding it the scene keeps)
    let at = kept_of(tree.layer_of(id))
    match at {
      Some(l) => scene_mark(l)
      None => ()
    }
  }
  for id in changed {
    tell(id, tree.draws_round(id))
  }
  for id in placed {
    tell(id, true)
    // (what holds it fading what it holds by how far that reaches past it (View::cuts_softly): drawn again with it)
    let mut h = tree.holder_of(id)
    while h is Some(o) {
      if tree.cuts_softly(o) {
        tell(o, true)
        break
      }
      h = tree.holder_of(o)
    }
  }
  for id in removed {
    match scene.reach.get(id) {
      Some(r) => scene.parts.add(r)
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
/// What the frame is drawn by, as one line: another than the last's, the frame drawn whole and nothing kept copied.
fn scene_drawn_by(c : Ctx) -> DrawnBy {
  {
    w: c.window_w,
    h: c.window_h,
    scale: c.scale,
    ground: c.clear,
    atlas: h_atlas_generation(),
    solid: glass_paint.solid,
    zoom: words_zoom.val,
  }
}

///|
/// What every instance kept was drawn for (scene_drawn_by): the window's size, its scale, its ground, the atlas, glass
/// drawn solid or not, the words' zoom.
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
    // (another window, scale or ground, the atlas made anew: drawn whole, nothing kept; what held the atlas's plots
    // holds nothing of one made anew)
    let atlas_anew = scene.drawn_by.atlas != by.atlas
    if atlas_anew {
      for _, l in scene.layers {
        l.plots.clear()
      }
    }
    scene_drop_all()
    scene.drawn_by = by
    scene.parts.whole(if scene.prev_n == 0 { 1 } else if atlas_anew { 4 } else { 3 })
  }
  // (who drew what kept, a shot at another size: everything drawn anew)
  scene.fresh = scene.fresh || looks_rebuilt.val || inst_owners.on || words_zoom.val != 1.0
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
        Some(r) => scene.parts.add(r)
        None => ()
      }
    }
    scene.due.clear()
    scene.marked.clear()
    scene.holding.clear()
    scene.moved.clear()
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
      l.start = -1
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
/// Layer `id` kept as it was drawn last frame and copied into this one where it is put now, all it holds with it, at
/// the frame's end: whether it was (it is in the scene, nothing of it changed, nothing it is drawn in changed, and it
/// is no layer drawn otherwise than by the tree alone). `forced`: what holds it was drawn again whole.
fn Ctx::scene_copied(
  self : Ctx,
  id : @view.NodeId,
  forced : Bool,
  held : (Double, Double, Double, Double, Double, Double),
  fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))],
  stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)],
  glyphing : Array[(@view.NodeId, (Double, @view.GlyphAt) -> @view.GlyphLook, (Double, Double))],
) -> Bool {
  let not = fn(why : String) {
    if scene.copy_why == "" {
      scene.copy_why = "\{id.at}: \{why}"
    }
    false
  }
  guard !scene.fresh else { return not("nothing kept") }
  guard !forced else { return not("what holds it drawn whole") }
  guard scene.layers.get(id) is Some(l) else { return not("not kept") }
  guard l.seen == scene.src_seen else { return not("seen \{l.seen}, kept of \{scene.src_seen}") }
  guard l.start >= 0 && l.start + l.count <= scene.src_n else {
    return not("at \{l.start} for \{l.count} of \{scene.src_n}")
  }
  guard !l.own_only else { return not("own only") }
  guard !l.each else { return not("drawn each frame") }
  guard !inst_owners_kept() || scene.owners is Some(_) else {
    return not("who drew it not kept")
  }
  guard !l.told && !scene.marked.contains(id) else { return not("marked, told \{l.told}") }
  guard !scene.holding.contains(id) else { return not("holds one marked") }
  // (what it was drawn in, as it is drawn in now: its key; another, drawn anew)
  guard scene_began_same(l, held, fading, stretching, glyphing) else { return not("drawn in otherwise") }
  let n = l.count
  while (self.ninst + n + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let at = self.ninst
  scene.src.blit_to(self.inst, len=n * inst_size, src_offset=l.start * inst_size, dst_offset=at * inst_size)
  let seg0 = self.segs.length() / 4
  for q in (l.seg_from * 4)..<((l.seg_from + l.seg_count) * 4) {
    self.segs.push(scene.src_segs[q])
  }
  let dseg = (seg0 - l.seg_from).to_double()
  for b in l.bands {
    let o = (at + b) * inst_size
    self.inst[o + 12] = self.inst[o + 12] + dseg
  }
  self.ninst = at + n
  match scene.owners {
    Some(o) if inst_owners_kept() =>
      owners_put(
        {
          owner: o.owner[l.start:l.start + n].to_owned(),
          cell: o.cell[l.start:l.start + n].to_owned(),
          tree: o.tree[l.start:l.start + n].to_owned(),
          mark: o.mark[l.start:l.start + n].to_owned(),
          bone: o.bone[l.start:l.start + n].to_owned(),
        },
        at,
      )
    _ => ()
  }
  scene_moved_to(l, at, seg0)
  // (its pictures kept as shown this frame: asked again, decoded as they were)
  for i in l.images {
    @signals.untracked(fn() { self.image_for(i.0, i.1) |> ignore })
  }
  scene_work.copied = scene_work.copied + 1
  scene_work.copied_insts = scene_work.copied_insts + n
  true
}

///|
/// Layer `l` as it is now kept to be put back, while the tree tries to draw a frame alone (scene_undo).
fn scene_keep_undo(l : SceneLayer) -> Unit {
  if scene.trying && !scene.undo.iter().any(fn(u) { physical_equal(u.0, l) }) {
    // (all of it as it was: where it is, what it holds, what it was drawn in (a failed try drew it in another), whether
    // it was told; its tables as they are, drawn again into new ones while trying: scene_drawn)
    scene.undo.push((l, { ..l }))
  }
}

///|
/// What the try to draw the frame alone did to the layers kept, put back.
fn scene_undo() -> Unit {
  for u in scene.undo {
    let (l, was) = u
    l.start = was.start
    l.count = was.count
    l.seg_from = was.seg_from
    l.seg_count = was.seg_count
    l.bands = was.bands
    l.anchors = was.anchors
    l.inner = was.inner
    l.outer = was.outer
    l.clip = was.clip
    l.clip_window = was.clip_window
    l.clip_apart = was.clip_apart
    l.fading = was.fading
    l.stretching = was.stretching
    l.glyphing = was.glyphing
    l.held = was.held
    l.scrim = was.scrim
    l.reach = was.reach
    l.told = was.told
    l.own_only = was.own_only
    l.each = was.each
    l.plots = was.plots
    l.images = was.images
    l.reads_clock = was.reads_clock
    l.seen = was.seen
  }
  scene.undo.clear()
}

///|
/// Whether layer `l` is drawn in now what it was drawn in as it began (the clip painted in, the fades, stretches and
/// glyph looks of what holds it, where that is drawn): what its kept instances were made in, the key they are kept by.
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
/// Where what holds node `id` and draws is drawn now (Tree::walk_scene's `held` for a walk from it), found up what holds
/// it.
fn scene_holder_at(tree : @view.Tree, id : @view.NodeId) -> (Double, Double, Double, Double, Double, Double)? {
  let mut h = tree.holder_of(id)
  while h is Some(n) {
    match tree.placed_of(n) {
      Some((x, y, a, s, ux, uy, _, _)) => return Some((x, y, a, s, ux, uy))
      None => h = tree.holder_of(n)
    }
  }
  None
}

///|
/// Layer `l`, and all it holds, put with its first instance at `at` and its first piece at `seg`, as this frame has
/// it.
fn scene_moved_to(l : SceneLayer, at : Int, seg : Int) -> Unit {
  let d = at - l.start
  let ds = seg - l.seg_from
  let go = fn(l : SceneLayer) {
    l.start = l.start + d
    l.seg_from = l.seg_from + ds
    l.seen = scene.frame
  }
  let todo = [l]
  while todo.pop() is Some(x) {
    scene_keep_undo(x)
    go(x)
    for i in x.inner {
      match scene.layers.get(i) {
        Some(y) => todo.push(y)
        None => ()
      }
    }
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
  let (clip, window, apart) = clip_kept()
  let l = match scene.layers.get(id) {
    Some(l) => l
    None => {
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
      }
      scene.layers[id] = l
      l
    }
  }
  scene_keep_undo(l)
  l.clip = clip
  l.clip_window = window
  l.clip_apart = apart
  l.fading = fading.copy()
  l.stretching = stretching.copy()
  l.glyphing = glyphing.copy()
  l.held = held
  l.scrim = !dr.scrims.is_empty()
  l.own_only = false
  l.each = false
  l.told = false
  // (drawn again into new tables while the frame is tried alone: those it had kept as they were, put back where the try
  // does not come to be, scene_keep_undo)
  if scene.trying {
    l.inner = []
    l.images = []
    l.plots = []
    l.bands = []
    l.anchors = []
  } else {
    l.inner.clear()
    l.anchors.clear()
  }
  // (drawn again alone, from what it began in: what holds it as it was)
  match outer {
    Some(o) => l.outer = Some(o.id)
    None => if l.id.at == 0 { l.outer = None }
  }
  l.images.clear()
  l.reads_clock = false
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
  if l.reads_clock {
    scene.clock_read = true
  }
  // (what holds it: as own only as anything it holds, and what it holds below it)
  match outer {
    Some(o) => {
      o.inner.push(id)
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
  // (the host's controls it drew, each by its instance from its first: where it is put, the same)
  for i, a in l.anchors {
    l.anchors[i] = (a.0, a.1 - k0)
  }
  anchors_layer_said(l)
  l.bands.clear()
  for k in k0..<self.ninst {
    if self.inst[k * inst_size + 5] == 11.0 {
      l.bands.push(k - k0)
    }
  }
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
  l
}

///|
/// Whether the frame may be drawn by the tree alone (scene_alone): nothing the old frame draws changed, nothing let
/// go, and each layer to be drawn again one drawn by the tree alone, kept where it was.
fn scene_alone_may() -> Bool {
  // (what was let go drawn in a layer kept: that one drawn again without it, marked; one drawn in none, the old frame
  // paints the frame)
  scene.alone_why = if scene.removed_unkept > 0 {
    "\{scene.removed_unkept} let go of what no layer kept"
  } else if old_placed_said() != old_painted_at.val {
    // (an old view laid out elsewhere than the old frame last painted it (what grew above it in the tree moved it):
    // the old frame paints it where it is now)
    "an old view placed otherwise than painted"
  } else if tree_picking() {
    // (words picked in the tree: what marks them the old frame's paint, worked out of where the tree lays them out as
    // it paints; what changed of the tree may have moved them)
    "words picked over the tree"
  } else if scene.fresh {
    "nothing kept"
  } else if scene.marked.is_empty() {
    "no layer marked"
  } else if scene.parts.whole_said() {
    "drawn whole"
  } else {
    ""
  }
  if scene.alone_why != "" {
    return false
  }
  for id, _ in scene.marked {
    match scene.layers.get(id) {
      Some(l) if l.seen == scene.frame && l.start >= 0 && !l.own_only && !l.each => ()
      Some(l) => {
        scene.alone_why = "layer \{id.at} seen \{l.seen} of \{scene.frame}, at \{l.start}, own \{l.own_only}"
        return false
      }
      // (one let go since it was marked: what held it is drawn again without it, marked as it went, scene_told)
      None => ()
    }
  }
  true
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
/// The frame drawn by the tree alone (alone_frame): each layer to be drawn again drawn where it is in what was kept,
/// into a buffer of its own from what it was drawn in as it began, and, where each comes to as many instances and
/// shapes' pieces as it was, put in its place; nothing else of the frame gone through. False (nothing changed of what
/// was kept) where one does not: the old frame paints it.
fn Ctx::scene_alone(self : Ctx, tree : @view.Tree, before_old? : Bool = false) -> Bool {
  guard scene_alone_may() else { return false }
  // (each drawn where what holds it is drawn now, as it was drawn in: else the old frame paints it, all it is in gone
  // through)
  // (one whose holder is drawn elsewhere now (a list's row as the list scrolls): the layer round it drawn again in its
  // place, out to one drawn where it was, what it holds with it)
  let mut again = true
  while again {
    again = false
    let moved_out : Array[(@view.NodeId, @view.NodeId)] = []
    for id, _ in scene.marked {
      match scene.layers.get(id) {
        Some(l) if l.id.at != 0 && scene_holder_at(tree, l.id) != Some(l.held) =>
          match l.outer {
            // (what drew it, where its instances are among that one's: else drawing that again leaves them)
            Some(o) if scene.layers.get(o) is Some(x) &&
              x.seen == scene.frame &&
              x.start >= 0 &&
              !x.own_only &&
              !x.each &&
              scene_holds_all(x, l) => moved_out.push((id, o))
            _ => {
              scene.alone_why = "layer \{id.at}: what holds it drawn elsewhere"
              return false
            }
          }
        _ => ()
      }
    }
    for m in moved_out {
      scene.marked.remove(m.0)
      scene_mark(m.1)
      again = true
    }
  }
  let (recorded0, parts0) = (scene_work.recorded, scene.parts.work())
  // (those held by none other drawn again: each draws what it holds)
  let todo : Array[SceneLayer] = []
  for id, _ in scene.marked {
    let mut under = false
    let mut h = tree.holder_of(id)
    while h is Some(n) && !under {
      if scene.marked.contains(n) && scene.layers.contains(n) {
        under = true
      }
      h = tree.holder_of(n)
    }
    if !under {
      match scene.layers.get(id) {
        Some(l) => todo.push(l)
        // (let go since it was marked: what held it drawn again without it)
        None => ()
      }
    }
  }
  // (and those whose instances lie within another's drawn again, held by it in the frame though not in the tree (a
  // layer raised over the window, drawn in its stack): drawn again with it, once)
  // (what drew it, out to the window: one of those drawn again draws it again)
  let drawn_by = fn(l : SceneLayer, o : SceneLayer) {
    let mut at = l.outer
    let mut found = false
    let mut steps = 0
    while at is Some(id) && !found && steps < 256 {
      found = id == o.id
      at = scene.layers.get(id).bind(fn(x) { x.outer })
      steps = steps + 1
    }
    found
  }
  let todo = todo.filter(fn(l) {
    !todo.iter().any(fn(o) {
      !physical_equal(o, l) && (drawn_by(l, o) || (l.count > 0 && o.count > l.count && scene_holds_all(o, l)))
    })
  })
  // (two that share instances, neither holding the other's all: no frame put together round them)
  let spans = todo.map(fn(l) { (l.start, l.start + l.count) })
  spans.sort()
  let mut end = -1
  for s in spans {
    if s.0 < end {
      scene.alone_why = "layers drawn again share instances"
      return false
    }
    if s.1 > end {
      end = s.1
    }
  }
  let drawn : Array[(SceneLayer, Int, Int, FixedArray[Double], Array[Double], OwnersRun?, Int, Int, Int)] = []
  scene.trying = true
  scene.undo.clear()
  // (the frame's glass as it stood: a try that drew glass and failed told none of its captures)
  let glass_was = { ..glass_paint }
  for l in todo {
    let (start, seg_from, count, seg_count) = (l.start, l.seg_from, l.count, l.seg_count)
    let (inst, n, segs, owners) = self.scene_redrawn(tree, l, before_old~, into=drawn.length())
    // (one come to another number of instances or of pieces: the frame's put together anew round it, scene_spliced;
    // not before the old frame paints)
    let other = n != count || segs.length() / 4 != seg_count
    if l.own_only || l.each || (other && (before_old || start < 0)) {
      scene.alone_why = "layer \{l.id.at} came to \{n} of \{count}, \{segs.length() / 4} pieces of \{seg_count}, own \{l.own_only}"
      scene.trying = false
      scene_undo()
      glass_put_back(glass_was)
      return false
    }
    drawn.push((l, start, seg_from, inst, segs, owners, n, count, seg_count))
  }
  scene.trying = false
  scene.undo.clear()
  // (put where each was: into what the frame is shown from, the base the old frame's cycles are applied over where
  // it has them (what is copied from as the old frame paints after, too: scene_begin); one come to another number of
  // instances or pieces, the frame put together anew round it, each where it now is: scene_spliced)
  if drawn.iter().any(fn(d) { d.6 != d.7 || d.4.length() / 4 != d.8 }) {
    self.scene_spliced(drawn)
  } else {
    let into = if looks_base.looks { looks_base.inst } else { self.inst }
    for d in drawn {
      let (l, start, seg_from, inst, segs, owners, n, _, _) = d
      match owners {
        Some(o) => owners_put(o, start)
        None => ()
      }
      for b in l.bands {
        inst[b * inst_size + 12] = inst[b * inst_size + 12] + seg_from.to_double()
      }
      inst.blit_to(into, len=n * inst_size, dst_offset=start * inst_size)
      // (the frame's pieces: as the old frame paints, those it keeps of the last frame's, scene_segs_kept)
      let pieces = if before_old { scene.prev_segs } else { self.segs }
      for q in 0..<segs.length() {
        pieces[seg_from * 4 + q] = segs[q]
      }
      // (its pieces where the frame keeps them, after every instance drawn: shape.mbt's emit_segs)
      for i in 0..<(segs.length() / 4) {
        let piece = seg_from + i
        let o = (scene.seg_tail + piece / 6) * inst_size + seg_slots[piece % 6] * 4
        into[o] = segs[4 * i]
        into[o + 1] = segs[4 * i + 1]
        into[o + 2] = segs[4 * i + 2]
        into[o + 3] = segs[4 * i + 3]
      }
      scene_moved_to(l, start, seg_from)
    }
  }
  scene.alone_reach = @damage.nowhere
  for id in scene.due {
    match scene.reach.get(id) {
      Some(r) => {
        scene.parts.add(r)
        scene.alone_reach = @damage.union(scene.alone_reach, r)
      }
      None => ()
    }
  }
  scene.due.clear()
  scene.marked.clear()
  scene.holding.clear()
  scene.moved.clear()
  scene.removed = 0
  scene.removed_unkept = 0
  scene_again()
  if !before_old {
    scene_work.alone = scene_work.alone + 1
    scene_work.alone_recorded = scene_work.alone_recorded + (scene_work.recorded - recorded0)
    scene_work.alone_parts = scene_work.alone_parts + (scene.parts.work() - parts0)
  }
  true
}

///|
/// The frame put together anew from what it held and the layers `drawn` drawn again, some come to another number of
/// instances or of shapes' pieces (a list's rows come into it and gone out of it as it scrolls): what lies between and
/// after them, the old frame's and the tree's, moved along as far as those before it grew or shrank, each layer kept
/// where it now is, the bands of shapes after them pointing to their pieces where those now are, the pieces put after
/// every instance as the frame keeps them (shape.mbt's emit_segs). Once over the frame's instances, nothing drawn
/// again of what was not drawn again (a list scrolled: drawn by the tree alone, not painted whole for each row in or
/// out, 2026-11-05).
fn Ctx::scene_spliced(self : Ctx, drawn : Array[(SceneLayer, Int, Int, FixedArray[Double], Array[Double], OwnersRun?, Int, Int, Int)]) -> Unit {
  let looks = looks_base.looks
  let from = if looks { looks_base.inst } else { self.inst }
  let total = if looks { looks_base.n } else { self.ninst }
  let tail = scene.seg_tail
  let old_segs = self.segs
  let order = drawn.copy()
  // (by where each was, one that drew nothing before one that drew from the same place)
  order.sort_by(fn(a, b) { (a.1, a.7).compare((b.1, b.7)) })
  // (the frame's instances before its pieces, and its pieces, put together anew: what is between the layers drawn
  // again copied as it was)
  let mut grown = 0
  let mut grown_segs = 0
  for d in order {
    grown = grown + d.6 - d.7
    grown_segs = grown_segs + d.4.length() / 4 - d.8
  }
  let new_tail = tail + grown
  let pieces = old_segs.length() / 4 + grown_segs
  let new_total = new_tail + (pieces + 5) / 6
  let out = FixedArray::make(imax(new_total, total) * inst_size + inst_size, 0.0)
  let segs : Array[Double] = []
  // (where an instance of the frame's, and a piece, as they were, are now: moved on by those drawn again before it)
  let at_moves : Array[(Int, Int)] = []
  let seg_moves : Array[(Int, Int)] = []
  let mut i = 0
  let mut j = 0
  let mut k = 0
  // (who drew what, where that is kept (a check's): each run where it now is, put once all are taken)
  let owned = inst_owners_kept()
  let runs : Array[(OwnersRun, Int)] = []
  for d in order {
    let (l, start, seg_from, inst, ls, owners, n, count, seg_count) = d
    // (what lies before it, as it was, moved on)
    if owned {
      runs.push((owners_run(i, start), j))
    }
    from.blit_to(out, len=(start - i) * inst_size, src_offset=i * inst_size, dst_offset=j * inst_size)
    if j != i {
      scene_moved_insts.val = scene_moved_insts.val + (start - i)
    }
    j = j + (start - i)
    for q in (k * 4)..<(seg_from * 4) {
      segs.push(old_segs[q])
    }
    let new_seg = segs.length() / 4
    for b in l.bands {
      inst[b * inst_size + 12] = inst[b * inst_size + 12] + new_seg.to_double()
    }
    inst.blit_to(out, len=n * inst_size, dst_offset=j * inst_size)
    match owners {
      Some(o) => runs.push((o, j))
      None => ()
    }
    for q in 0..<ls.length() {
      segs.push(ls[q])
    }
    at_moves.push((start + count, j + n - (start + count)))
    seg_moves.push((seg_from + seg_count, new_seg + ls.length() / 4 - (seg_from + seg_count)))
    scene_moved_to(l, j, new_seg)
    j = j + n
    i = start + count
    k = seg_from + seg_count
  }
  if owned {
    runs.push((owners_run(i, tail), j))
  }
  from.blit_to(out, len=(tail - i) * inst_size, src_offset=i * inst_size, dst_offset=j * inst_size)
  if j != i {
    scene_moved_insts.val = scene_moved_insts.val + (tail - i)
  }
  for r in runs {
    owners_put(r.0, r.1)
  }
  if owned {
    owners_cut(new_tail)
  }
  for q in (k * 4)..<old_segs.length() {
    segs.push(old_segs[q])
  }
  // (how far what was at `at` moved: as far as the last drawn again before it grew)
  // (`edge` of a layer, its start or its end: moved as what is before it moved; where it is just where one drawn
  // again ends (one that drew nothing begins there too), moved with it only if it lies after it: a start of one not
  // holding it, an end of one holding it)
  let holds_drawn = fn(l : SceneLayer, k : Int) {
    let mut at = order[k].0.outer
    let mut steps = 0
    let mut found = false
    while at is Some(id) && !found && steps < 256 {
      found = id == l.id
      at = scene.layers.get(id).bind(fn(x) { x.outer })
      steps = steps + 1
    }
    found
  }
  // (a piece as far as what is before it moved)
  let pieces_moved_by = fn(at : Int) {
    let mut by = 0
    for m in seg_moves {
      if at >= m.0 {
        by = m.1
      }
    }
    by
  }
  let moved_by = fn(moves : Array[(Int, Int)], at : Int, l : SceneLayer, is_end : Bool) {
    let mut by = 0
    for k, m in moves {
      if at > m.0 || (at == m.0 && holds_drawn(l, k) == is_end) {
        by = m.1
      }
    }
    by
  }
  // (the layers not drawn again, each where it now is; the bands of shapes of what was copied pointing to their
  // pieces where those now are)
  let redrawn : Map[@view.NodeId, Bool] = {}
  for d in order {
    let todo = [d.0]
    while todo.pop() is Some(x) {
      redrawn[x.id] = true
      for c in x.inner {
        match scene.layers.get(c) {
          Some(y) => todo.push(y)
          None => ()
        }
      }
    }
  }
  // (one holding a layer drawn again as large as it now is: its end moved on as far as what is before it grew, its
  // bands found where they now are in it)
  let holders : Array[SceneLayer] = []
  for id, l in scene.layers {
    if !redrawn.contains(id) && l.start >= 0 && l.seen == scene.frame {
      let (end, seg_end, count) = (l.start + l.count, l.seg_from + l.seg_count, l.count)
      // (one that holds nothing (none drawn again in it) moves whole, its end with its start)
      let mut holds_any = false
      for k in 0..<order.length() {
        if holds_drawn(l, k) {
          holds_any = true
        }
      }
      let empty = count == 0 && !holds_any
      let by = moved_by(at_moves, l.start, l, false)
      let end_by = moved_by(at_moves, end, l, true)
      l.start = l.start + by
      l.count = end + (if empty { by } else { end_by }) - l.start
      let seg_by = moved_by(seg_moves, l.seg_from, l, false)
      let seg_end_by = moved_by(seg_moves, seg_end, l, true)
      l.seg_from = l.seg_from + seg_by
      l.seg_count = seg_end + (if l.seg_count == 0 && !holds_any { seg_by } else { seg_end_by }) - l.seg_from
      if l.count != count {
        holders.push(l)
      }
    }
  }
  for x in 0..<new_tail {
    let b = x * inst_size
    if out[b + 5] == 11.0 && !redrawn_at(order, x) {
      let piece = out[b + 12].to_int()
      out[b + 12] = out[b + 12] + pieces_moved_by(piece).to_double()
    }
  }
  for l in holders {
    l.bands.clear()
    for x in l.start..<(l.start + l.count) {
      if out[x * inst_size + 5] == 11.0 {
        l.bands.push(x - l.start)
      }
    }
  }
  // (the pieces after every instance, six to one, as emit_segs puts them)
  for r in 0..<((pieces + 5) / 6) {
    let b = (new_tail + r) * inst_size
    for z in 0..<inst_size {
      out[b + z] = 0.0
    }
    out[b + 5] = 12.0
    for s in 0..<6 {
      let p = r * 6 + s
      if p < pieces {
        let o = b + seg_slots[s] * 4
        out[o] = segs[4 * p]
        out[o + 1] = segs[4 * p + 1]
        out[o + 2] = segs[4 * p + 2]
        out[o + 3] = segs[4 * p + 3]
      }
    }
  }
  scene.seg_tail = new_tail
  self.segs = segs
  scene.last_n = new_total
  if looks {
    looks_base.inst = out
    looks_base.n = new_total
    while new_total * inst_size > self.inst.length() {
      self.grow()
    }
  } else {
    self.inst = out
    self.ninst = new_total
  }
}

///|
/// Whether instance `x` of the frame put together anew (scene_spliced) is one of the layers drawn again (`order`,
/// each where it now is).
fn redrawn_at(order : Array[(SceneLayer, Int, Int, FixedArray[Double], Array[Double], OwnersRun?, Int, Int, Int)], x : Int) -> Bool {
  for d in order {
    if x >= d.0.start && x < d.0.start + d.6 {
      return true
    }
  }
  false
}

///|
/// Layer `l` drawn again alone, from what it was drawn in as it began (its clip, the fades, stretches and glyph looks of
/// what holds it, where that is drawn), into a buffer of its own: its instances, how many, and its shapes' pieces.
fn Ctx::scene_redrawn(
  self : Ctx,
  tree : @view.Tree,
  l : SceneLayer,
  before_old? : Bool = false,
  into? : Int = 0,
) -> (FixedArray[Double], Int, Array[Double], OwnersRun?) {
  let (inst, ninst, segs) = (self.inst, self.ninst, self.segs)
  // (who drew what, where it is kept: the frame's as it was, all of it, what the layers it holds kept are copied with,
  // and what drawing it apart from 0 writes over put back after)
  let kept = if inst_owners_kept() { Some(owners_run(0, scene.seg_tail)) } else { None }
  let owners_was = scene.owners
  scene.owners = kept
  // (what it holds that is kept copied from the frame as it is)
  scene.src = if looks_base.looks { looks_base.inst } else { inst }
  scene.src_n = scene.seg_tail
  scene.src_segs = if before_old { scene.prev_segs } else { segs }
  scene.src_seen = scene.frame
  // (the buffer kept for it, grown where it is short: none made each frame)
  while scene.scratch.length() <= into {
    scene.scratch.push(FixedArray::make(64 * inst_size, 0.0))
  }
  if scene.scratch[into].length() < (l.count + 8) * inst_size {
    scene.scratch[into] = FixedArray::make((l.count + 8) * 2 * inst_size, 0.0)
  }
  self.inst = scene.scratch[into]
  self.ninst = 0
  self.segs = []
  clip_put_back(l.clip, l.clip_window, l.clip_apart)
  let p = TreePaint::new(tree, -1, true)
  p.fading.append(l.fading)
  p.stretching.append(l.stretching)
  p.glyphing.append(l.glyphing)
  let outer = scene.drawing
  scene.drawing = None
  self.scene_drawn(l.id, None, l.held, l.fading, l.stretching, l.glyphing, fn() {
    self.tree_walk(p, Some(l.id.at), l.held)
  })
  |> ignore
  scene.drawing = outer
  pop_clip()
  scene.owners = owners_was
  let mine = match kept {
    Some(k) => {
      let m = owners_run(0, self.ninst)
      owners_put(k, 0)
      Some(m)
    }
    None => None
  }
  // (grown as it was drawn: kept so)
  scene.scratch[into] = self.inst
  let out = (self.inst, self.ninst, self.segs, mine)
  self.inst = inst
  self.ninst = ninst
  self.segs = segs
  out
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

