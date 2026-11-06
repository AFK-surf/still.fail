// A view made once (docs/retained.md, the model; the way there's 2). Each node is made when it first shows and stays
// until what holds it lets it go; what of it changes is a binding of one property (one a property: bound again, the
// one before is let go), marked as what it read changes and worked out again as the next frame begins (Tree::queued:
// however often it changed meanwhile, once; nothing is laid out or drawn as a value is set), and that property alone
// is set again, and only if it came out otherwise: a layout property marks the node (and what
// holds it) to be laid out, a paint property the node's instance to be made again, a place property (how far it is
// drawn off, how opaque) its instance and those of what it holds. What comes and goes is a node of its own (`show`,
// `pick`, `each`), whose nodes it makes, keeps and lets go. Acting is a callback run outside any tracking. Time is a
// signal (Tree::drawn_at: what is drawn by the clock samples it), read where it is used.
//
// Each node owns what it is made with: its making runs in a scope of its own (a node's, owned by nothing else), so what
// it makes there (its bindings, any effect, effect_cleanup or effect of its own, what it says to let go with it:
// View::owns) is stopped as the node is let go, its cleanups run once; a binding set on it later is made in that scope
// too. The scope of a node made by a structure's binding (what `show` shows) is its own, not that binding's: the
// binding running again leaves it be.
//
// Nodes are a pool by index (retained.md: no pointer cycles under reference counting): a node holds what holds it and
// what it holds as indexes, and a `View` is a handle (the tree, the index, the node's making there). A handle on a node
// let go does nothing (View::live, where every handle's use begins): its index made again since is another node.
//
// A frame (Tree::frame) does what was marked and nothing else: runs the bindings told, lays out the nodes marked
// (flex's reuse) and visits the nodes it laid out again and what they hold, a node whose place or look changed alone.
// What a node draws (Content) is kept where it is its own and made again only as its look or size changes; where it is
// in what holds it and how opaque are its composition, set again alone as it moves or fades, what it holds left as it
// is; the window's places are worked out as the scene is gone through (Tree::each_drawn), for drawing and hitting
// alike. What a frame changed (Tree::changed, Tree::composed) is for the host to take.
//
// What this package is not yet (the way there's 3): its words are measured by a function given to it, its instances
// are `Drawn` records the host turns into its own.

///|
/// A property's value: set once (`Is`), or worked out (`By`), tracked, and set again as what it read changes; or, of a
/// place or a look alone, worked out as the frame is painted (`Painted`), after its one layout, from where things were
/// laid out in it (`Laid`): what it reads of layout read there and nowhere else (retained.md, "Layout read back"); or,
/// of what layout reads, worked out as it is laid out from how big a node holding it is laid out (`Roomed`: its width
/// and height as its holder lays it out, else the room it is given, in the same layout: a title no wider than a share of
/// its page, a field's lines as many as fit a share of its page's height), what else it reads followed.
pub(all) enum Live[T] {
  Is(T)
  By(() -> T)
  Painted((Laid) -> T)
  Roomed(View, (Double, Double) -> T)
}

///|
/// Where things were laid out in the frame being painted, as a `Painted` property reads it: a node's place in the window
/// and its size, as this frame laid it out (its holders' places and offsets counted, nothing it is drawn off by).
pub struct Laid {
  priv tree : Tree
}

///|
/// Where `v` is in the window as this frame laid it out, and how big; None: let go, or laid out nowhere.
pub fn Laid::rect(self : Laid, v : View) -> (Double, Double, Double, Double)? {
  guard physical_equal(v.tree, self.tree) && v.live() is Some(n) else { return None }
  if self.tree.out_at(v.at) {
    return None
  }
  let mut x = 0.0
  let mut y = 0.0
  let mut i = v.at
  while i >= 0 {
    let m = self.tree.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
    }
    i = m.parent
  }
  Some((x, y, n.lw, n.lh))
}

///|
/// How big `v` is as this frame laid it out; None: let go, or laid out nowhere.
pub fn Laid::size(self : Laid, v : View) -> (Double, Double)? {
  self.rect(v).map(fn(r) { (r.2, r.3) })
}

///|
/// Where `v` is drawn in the window this frame, and how big: as Laid::rect, with what it and its holders are drawn off by
/// (View::drawn_off: a list's rows on their way as it glides) and how big they are drawn (View::scale), the value
/// View::drawn_window_told tells, read here as it is painted and never told (what flies to a row as that row is drawn).
/// Each `Painted` reads what was placed before it: the layout's, and the `Painted` said before it; one said after it,
/// none of it. None: let go, or laid out nowhere.
pub fn Laid::drawn(self : Laid, v : View) -> (Double, Double, Double, Double)? {
  guard physical_equal(v.tree, self.tree) && v.live() is Some(n) else { return None }
  if self.tree.out_at(v.at) {
    return None
  }
  let (x, y, _, s) = self.tree.projected(v.at, drawing=true)
  Some((x, y, n.lw * s, n.lh * s))
}

///|
/// The moment this frame is drawn at (Tree::drawn_at), followed: what is worked out from the time as it is painted (a
/// flight's place on its way) worked out again as it goes.
pub fn Laid::at(self : Laid) -> Double {
  self.tree.drawn_at()
}

///|
/// What reads it abort here: a property `Painted` is a place's or a look's, worked out as the frame is painted.
fn[T] not_painted(what : String) -> T {
  abort("View: \{what} is no place nor look: a Painted value is worked out only as the frame is painted")
}

///|
/// What reads it abort here: a property `Roomed` is one layout reads, worked out as what holds it is laid out.
fn[T] not_roomed() -> T {
  abort("View: what is said here is not laid out: a Roomed value is worked out only as what holds it is laid out")
}

///|
/// What node `at` (made `gen`) works out of how big `of` is laid out (Live's Roomed), told as `of` is (its flex node's
/// on_room), each in the order said; and at once where `of` was sized already (a node made under it as it is laid out,
/// a list's row, after it was told its room: the room it was told then, in the same layout).
fn Tree::roomed_add(self : Tree, of : Int, at : Int, gen : Int, run : (Double, Double) -> Unit) -> Unit {
  match self.nodes[of].flex.room_now() {
    Some((w, h)) => run(w, h)
    None => ()
  }
  match self.roomed.get(of) {
    Some(all) => all.push((at, gen, run))
    None => {
      let all = [(at, gen, run)]
      self.roomed[of] = all
      self.nodes[of].flex.on_room = Some(fn(w, h) {
        for e in all.copy() {
          (e.2)(w, h)
        }
      })
    }
  }
}

///|
/// What node `at` (made `gen`) worked out of how big `of` is laid out, let go.
fn Tree::roomed_drop(self : Tree, of : Int, at : Int, gen : Int) -> Unit {
  match self.roomed.get(of) {
    Some(all) => {
      all.retain(fn(e) { e.0 != at || e.1 != gen })
      if all.is_empty() {
        self.roomed.remove(of)
        self.nodes[of].flex.on_room = None
      }
    }
    None => ()
  }
}

///|
/// Who a node is: its index and its making there (an index made again is another node).
pub(all) struct NodeId {
  at : Int
  gen : Int
} derive(Eq, Hash, Debug)

///|
/// What a node is drawn as, kept by the node: its ground (0: none), its words and their ink, how opaque, and how far it
/// is drawn off where it is laid out (what it holds drawn off with it).
pub(all) struct Look {
  mut ground : Int64
  mut ink : Int64
  mut words : String
  /// what is drawn of its words where they have not the room on their line and it says shorter ones (View::shorter;
  /// None: its words): read out, found and measured as its words, drawn as this
  mut words_drawn : String?
  /// how its words are set (View::words: their size, weight, line and whether they wrap)
  mut words_look : WordsLook
  /// its words in pieces set their own way (View::words_runs: a run's own look; none: all of them as words_look says)
  mut runs : Array[@text.Run]
  /// how its pieces are set where they say nothing of it themselves (View::runs_look: a link's ink, code's, faces)
  mut runs_look : RunsLook
  /// the link of its pieces held, by its first piece (-1 none): its pressed ground under it (View::runs_pressed)
  mut runs_pressed : Int
  /// what of its words is picked with the pointer, from until (none: the same): its pieces' (View::runs_picked)
  mut runs_picked : (Int, Int)
  /// a passage of its words on a ground of its own, from until, its colour, how round at its two ends (none where from
  /// and until are the same): its pieces' (View::runs_lit)
  mut runs_lit : (Int, Int, Int64, Double)
  /// the shadow it casts under its ground (blur, how far down, colour; 0 blur: none): View::shadow
  mut shadow : (Double, Double, Int64)
  /// the shapes it draws over its ground (their outlines, as said: what they come to drawn kept by them), and the one
  /// colour they are drawn in where it is not 0 (their own where it is): View::shapes, View::tint
  mut shapes : Array[@paint.Shape]
  mut tint : Int64
  /// the lines it draws over its shapes (round-capped strokes through points, each in its own colour): View::lines
  mut lines : Array[@paint.Line]
  /// the edge drawn round its ground, inside it (how wide, its colour; 0 wide: none): View::edge
  mut edge : (Double, Int64)
  mut edge_dashed : Bool
  /// the notch cut into its top (where its circle's middle is below the top, its radius, its fillets'; a radius of 0:
  /// none): its ground's, its glass's and its edge's, as an old view's box's (Ctx::box `notch_*`): View::notch
  mut notch : (Double, Double, Double)
  /// its shadow cast outside its outline only (none under it), as an old view's box's `shadow_out`: View::shadow_outside
  mut shadow_out : Bool
  /// where across it cuts what it holds (from, to, in its own terms; None: all of it), as it is painted, where it clips
  /// (View::clips): View::cut_across
  mut cut_across : (Double, Double)?
  /// the rect it cuts what it holds to (x, y, w, h, in its own terms; None: none of its own), as it is painted, whether
  /// or not it clips to itself: View::clip_drawn
  mut clip_drawn : (Double, Double, Double, Double)?
  /// the picture it shows over its ground, all of it filled (its source as what hosts the tree keeps pictures by, what
  /// stands in for it till it is decoded at the size it is drawn ("" none), the most pixels it is asked at), drawn as
  /// what hosts the tree draws one (None: none): View::image
  mut image : (String, String, Int)?
  /// the room its picture is judged ready for (its whole picture shown, not what stands in for it, once decoded for
  /// that room; (0, 0): where it is drawn), as what a picture on its way somewhere is judged by where it goes:
  /// View::image_for
  mut image_for : (Double, Double)
  /// its picture covering it, cut where it is not as wide for as tall (View::image_covers); else filling it
  mut image_cover : Bool
  /// its picture fading in as it is decoded (View::image_fades); else there at once
  mut image_fade : Bool
  /// where in it its picture lies (x, y, w, h, in its own terms) and the matte filling the rest of it, drawn with the
  /// picture in one (its edge cut once, its corners its own): View::image_in; None, the picture fills it
  mut image_in : ((Double, Double, Double, Double), Int64)?
  /// how round its corners are (its ground's, its glass's), and the glass it is drawn as under what it draws (None: none):
  /// View::radius, View::glass
  mut radius : Double
  /// its corners each (top left, then round it), where it says them, in its radius's place (None: all as its radius):
  /// View::corners
  mut corners : (Double, Double, Double, Double)?
  mut glass : @paint.Glass?
  mut alpha : Double
  mut dx : Double
  mut dy : Double
  /// and how far besides, in its own widths and heights as it is laid out (a page slid off by its width)
  mut sx : Double
  mut sy : Double
  /// how big it is drawn, what it holds with it (1: as laid out), about which point of it (shares of its width and
  /// height): View::scale
  mut scale : Double
  mut pivot : Pivot
  /// how far what it draws itself is turned (radians; not what it holds), and whether about the middle of what it draws
  /// (else its own): View::turn
  mut turn : Double
  mut turn_drawn : Bool
  /// how far before its edges what it holds fades out towards them (start, top, end, foot; 0 none): View::fades
  mut fades : (Double, Double, Double, Double)
  /// Android's stretch of what it holds (View::stretches): from its top positive, from its foot negative; 0 none
  mut stretch : Double
  /// how far it and what it holds are drawn off where they are laid out, drawn only (View::drawn_off); how far its own
  /// ground is drawn off and how much bigger than it is laid out (View::ground_drawn)
  mut drawn_off : (Double, Double)
  mut ground_drawn : (Double, Double, Double, Double)
  /// whether what it holds past its edges fades out towards them softly, by how far it reaches past (View::cuts_softly)
  mut cut_soft : Bool
  /// what it draws called by name, as what finds it on screen calls it (an icon's: View::drawn_as)
  mut drawn_as : String
  /// whether what it holds is cut to it, its corners round as its own (View::clips)
  mut clips : Bool
  /// whether its words' lines each stand in the middle of its width (View::words_centered)
  mut words_center : Bool
  /// whether its words' ellipsis, one line cut short past it, is drawn past its box (View::ellipsis_past)
  mut ellipsis_past : Bool
  /// the picture it draws as wide as it is laid out, its curves cut for the pixels it is drawn at (View::picture)
  mut picture : @pixels.Vector?
  /// the moment its glyphs, and those of all it holds, are drawn as View::glyphs_by works out for (None: as laid out)
  mut glyphs_at : Double?
  /// where the host puts a control of its own, by this name, wherever this node is drawn (View::native_anchor; "": none)
  mut native_anchor : String
} derive(Eq, Debug)

///|
/// What a node draws, where it is its own (its origin its top left, as opaque as itself): which node, how big, its
/// ground, its words. Made again only as one of these changes; where it is and how opaque it is drawn are its place's
/// and its holders' (composed as the scene is gone through: Tree::each_drawn).
pub(all) struct Content {
  id : NodeId
  w : Double
  h : Double
  ground : Int64
  ink : Int64
  words : String
  /// what is drawn of its words (Look's words_drawn: shorter ones in their place; None: its words)
  words_drawn : String?
  words_look : WordsLook
  runs : Array[@text.Run]
  runs_look : RunsLook
  runs_pressed : Int
  runs_picked : (Int, Int)
  runs_lit : (Int, Int, Int64, Double)
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  lines : Array[@paint.Line]
  tint : Int64
  radius : Double
  /// its corners each, where it says them (View::corners)
  corners : (Double, Double, Double, Double)?
  /// the edge round its ground (View::edge)
  edge : (Double, Int64)
  edge_dashed : Bool
  /// the notch cut into its top (View::notch)
  notch : (Double, Double, Double)
  /// its shadow outside its outline only (View::shadow_outside)
  shadow_out : Bool
  /// where across it cuts what it holds (View::cut_across)
  cut_across : (Double, Double)?
  /// the rect it cuts what it holds to (View::clip_drawn)
  clip_drawn : (Double, Double, Double, Double)?
  /// the picture it shows, all of it filled (View::image)
  image : (String, String, Int)?
  /// the room its picture is judged ready for (View::image_for)
  image_for : (Double, Double)
  /// its picture covering it, not stretched to it (View::image_covers)
  image_cover : Bool
  /// its picture fading in as it is decoded (View::image_fades)
  image_fade : Bool
  /// where in it its picture lies and the matte round it (View::image_in)
  image_in : ((Double, Double, Double, Double), Int64)?
  glass : @paint.Glass?
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
  /// what it holds cut to it, its corners round as its own (View::clips)
  clips : Bool
  /// its words' lines each in the middle of its width (View::words_centered)
  words_center : Bool
  /// its words' ellipsis drawn past its box where it has not the room for it (View::ellipsis_past)
  ellipsis_past : Bool
  /// the picture it draws as wide as it is (View::picture)
  picture : @pixels.Vector?
  /// what it is drawn in as its bones, its own or what holds it's (View::bones): 0 none
  bones : Int64
  /// in its bones, how: drawn as its words, shapes and grounds are (0), one piece of its own box (1: View::bone_whole),
  /// or nothing, in one drawn whole (2)
  bone_as : Int
  /// the name of the host's control put where it is drawn (View::native_anchor; "": none)
  native_anchor : String
} derive(Eq, Debug)

///|
/// Whether it draws anything of its own: a ground, words, shapes, lines, a picture, glass, or what hosts it (the one place that says what
/// a node draws, for what asks whether it draws nothing: Tree::alone).
pub fn Content::draws(self : Content) -> Bool {
  // (a ground of no opacity draws nothing: ui's paint of it, an old view's box's grounded)
  (self.ground & 0xFFL) != 0L ||
  (self.edge.0 > 0.0 && (self.edge.1 & 0xFFL) != 0L) ||
  self.image is Some(_) ||
  self.words != "" ||
  !self.shapes.is_empty() ||
  !self.lines.is_empty() ||
  self.picture is Some(_) ||
  self.glass is Some(_) ||
  self.shadow.0 > 0.0 ||
  self.hosted ||
  self.native_anchor != ""
}

///|
/// A node's content unfolded where the window draws it (what holds it drawn off and faded with it): for a test, or a
/// host that takes the window whole.
pub(all) struct Drawn {
  id : NodeId
  x : Double
  y : Double
  w : Double
  h : Double
  alpha : Double
  ground : Int64
  ink : Int64
  words : String
  words_look : WordsLook
  runs : Array[@text.Run]
  runs_look : RunsLook
  runs_pressed : Int
  runs_picked : (Int, Int)
  runs_lit : (Int, Int, Int64, Double)
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  lines : Array[@paint.Line]
  tint : Int64
  radius : Double
  /// its corners each, where it says them (View::corners)
  corners : (Double, Double, Double, Double)?
  /// the edge round its ground (View::edge)
  edge : (Double, Int64)
  edge_dashed : Bool
  /// the notch cut into its top (View::notch)
  notch : (Double, Double, Double)
  /// its shadow outside its outline only (View::shadow_outside)
  shadow_out : Bool
  /// where across it cuts what it holds (View::cut_across)
  cut_across : (Double, Double)?
  /// the rect it cuts what it holds to (View::clip_drawn)
  clip_drawn : (Double, Double, Double, Double)?
  /// the picture it shows, all of it filled (View::image)
  image : (String, String, Int)?
  /// the room its picture is judged ready for (View::image_for)
  image_for : (Double, Double)
  /// its picture covering it, not stretched to it (View::image_covers)
  image_cover : Bool
  /// its picture fading in as it is decoded (View::image_fades)
  image_fade : Bool
  /// where in it its picture lies and the matte round it (View::image_in)
  image_in : ((Double, Double, Double, Double), Int64)?
  glass : @paint.Glass?
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
  /// what it holds cut to it, its corners round as its own (View::clips)
  clips : Bool
  /// its words' lines each in the middle of its width (View::words_centered)
  words_center : Bool
  /// its words' ellipsis drawn past its box where it has not the room for it (View::ellipsis_past)
  ellipsis_past : Bool
  /// the picture it draws as wide as it is (View::picture)
  picture : @pixels.Vector?
  /// what it is drawn in as its bones (Content's): 0 none; nothing of its words found as words then
  bones : Int64
  /// in its bones, how (Content's)
  bone_as : Int
} derive(Eq, Debug)

///|
/// What the tree did, counted from its making: nodes made and let go; bindings run, and of them those whose value came
/// out the same (nothing set, nothing marked); computes of the layout and nodes it laid out again; nodes a frame visited
/// (laid out, placed, looked at); words measured; instances made again; instances handed to the host as changed;
/// orders made again; structure bindings run (show, pick, each). For a test to say what work a change did, not how long
/// it took.
pub(all) struct Work {
  /// what goes beside another placed by it (View::beside: each worked out)
  mut besides : Int
  mut made : Int
  mut let_go : Int
  mut bound : Int
  mut same : Int
  mut computes : Int
  mut laid : Int
  mut visited : Int
  mut measured : Int
  mut instances : Int
  mut composed : Int
  mut changes : Int
  mut orders : Int
  mut structure : Int
  /// nodes gone through to find what a point is on (a press, the pointer, a wheel: Tree::walk_taken), and nodes asked
  /// for a key (Tree::key_at): what shows where it is and what holds the focus, never the whole tree
  mut hit_visited : Int
  mut keys_asked : Int
  /// bindings looked at as something asked at once (Tree::pull): those marked, each once
  mut pulled : Int
  /// the boxes round what a node and what it holds draw worked out afresh (View::scale's Drawn: Tree::drawn_box_of)
  mut drawn_boxes : Int
  /// where things stand laid out and placed once a change was told whole (Tree::settle_now: View::laid_before_causes)
  mut settles : Int
  /// the keys of a list laid out from its anchor gone through, all of them, as they changed or its rows were measured
  /// otherwise (View::scrolls_anchored: those gone forgotten, the rows measured counted again): none while none of its
  /// rows is named or measured, as its first keys are
  mut keys_swept : Int
} derive(Eq, Debug)

///|
/// A node of the pool.
struct Node {
  /// which making of this index it is (a handle on an earlier one finds it let go)
  mut gen : Int
  mut live : Bool
  mut flex : @flex.Node
  look : Look
  mut parent : Int
  /// A last-resort ellipsis in its own words was deliberately allowed, without changing their sizing.
  mut allow_ellipsis : Bool
  kids : Array[Int]
  /// its scope (what it was made with, and what is set on it, owned), and what stops it
  mut owner : @signals.ReactiveNode?
  mut stop : (() -> Unit)?
  /// what else goes with it (View::owns, its structure's binding), run once as it is let go
  drops : Map[Int, () -> Unit]
  /// the key the next of them is kept by
  mut drop_next : Int
  /// its properties' bindings, by property: what stops each
  props : Map[Prop, () -> Unit]
  mut on_press : (() -> Unit)?
  /// whether it is a top row of the app's own (View::moves_window: a press on it its own), and whether a press on it
  /// moves the window now
  mut top_row : Bool
  mut moves_window : Bool
  /// what the pointer's secondary button pressed on it asks for (View::on_menu)
  mut on_menu : ((Menu) -> Unit)?
  /// what a wheel turned over it does (View::on_wheel, View::on_wheel_moves): true where it took it
  mut on_wheel : ((Wheel) -> Bool)?
  /// how many times what a wheel does to it was said: a wheel asked of it as it was said then, asked only while it
  /// still is so (Tree::wheel_at)
  mut wheel_said : Int
  /// what a key does to it (View::on_key): true where it took the key
  mut on_key : ((Key) -> Bool)?
  /// the keys (a code, the modifiers held) its on_key is told of while a field has the focus too, as the field takes them
  /// (View::keys_in_fields)
  mut keys_in_fields : Array[(Int, Int)]
  /// how many times what a key does to it was said (View::on_key): a key asked of it as it was said then, asked only
  /// while it still is so (Tree::key_at)
  mut key_said : Int
  /// what back does to it, once done (View::takes_back) or step by step (View::follows_back), and how many times it
  /// was said (a gesture held by one saying of it goes to that one alone: Tree::back_step)
  mut on_back : (() -> Unit)?
  mut on_back_step : ((BackStep) -> Unit)?
  mut back_said : Int
  /// whether it is held, and pointed at, as what reads it reads it (View::pressed, View::pointed): made as first read,
  /// let go with it
  mut pressed_cell : @signals.Signal[Bool]?
  mut pointed_cell : @signals.Signal[Bool]?
  /// what it does as the pointer moves onto it or over it (View::on_pointer_moved): the pointer's own moving, not a
  /// layout putting it under a still pointer
  mut on_pointer_moved : (() -> Unit)?
  /// whether what the pointer is over is it or held by it, made as first read (View::pointed_in)
  mut pointed_in_cell : @signals.Signal[Bool]?
  /// whether the pointer is within it as it was last placed, made as first read (View::pointer_within)
  mut within_cell : @signals.Signal[Bool]?
  /// where the pointer is in its own terms as it was last placed, made as first read (View::pointer_here_told)
  mut here_cell : @signals.Signal[(Double, Double)?]?
  /// how many times how its words are set was said (their words, pieces, look: View::words_said), made as first read
  mut said_cell : @signals.Signal[Int]?
  /// a row of a list made by its key (View::each): the same while its key is there, whatever is made in it anew
  mut each_row : Bool
  /// what that row is known by where it is made anew for the same key (View::row_known_as: a windowed list's block,
  /// its slot let go as it leaves the window): what is picked in it found in it again as it comes back
  mut row_id : NodeId?
  /// A virtual row's position among all its siblings, including those outside the window.
  mut row_index : Int?
  /// whether it takes input now as what reads it reads it (View::takes_input): made as first read, let go with it
  mut input_cell : @signals.Signal[Bool]?
  /// whether it can take the keyboard's focus, which of Enter (1) and Space (2) press it as it has it (View::focusable;
  /// none: it takes the focus all the same, pressed by no key), and its cells of whether it has it and it shows (View::focused, View::focus_shown): made as first read, let go
  /// with it
  mut focusable : Bool
  /// an editor: a modal layer's leaves_typing keeps its existing focus for text input alone
  mut focus_typing : Bool
  /// the pointer's shape over it, said (View::cursor; none: as it is shown without being told, Tree::cursor_of)
  mut cursor : Cursor?
  /// what it is placed beside (View::beside: its anchor, the side, how along it), placed so as the tree is placed
  mut beside : Beside?
  /// the side it went on beside its anchor, as it was last placed there (none: not placed beside one yet)
  mut went : Side?
  /// where it was last placed beside its anchor (its place in what holds it, and the point it is drawn bigger or
  /// smaller about): where it stays once it is leaving or its anchor is drawn nowhere (View::beside)
  mut beside_last : (Double, Double, Double, Double)?
  /// the point of its anchor the pointer was last at, in the anchor's own terms (View::beside's `at_pointer`)
  mut beside_point : (Double, Double)?
  mut focus_keys : Int
  /// whether Tab stops on it as it takes the focus (View::focusable's `tab`)
  mut focus_tab : Bool
  /// whether Tab's stop on it is said by View::tab_stop (the last saying of it), not by View::focusable's `tab`
  mut tab_by_stop : Bool
  mut focused_cell : @signals.Signal[Bool]?
  /// how big it was laid out, told once all of the layout is done (View::laid_size_told: none till then); made as
  /// first read
  mut size_cell : @signals.Signal[(Double, Double)?]?
  /// its placed rectangle in the window, without drawing transforms, told after placement to an attached overlay
  mut rect_cell : @signals.Signal[(Double, Double, Double, Double)?]?
  /// its rectangle where it is drawn, including its holders' drawing transforms, followed by a detached overlay
  mut drawn_rect_cell : @signals.Signal[(Double, Double, Double, Double)?]?
  /// the side it went on beside its anchor, told once all of the layout is done (View::went_told: none till then); made
  /// as first read
  mut went_cell : @signals.Signal[Side?]?
  /// what it holds is found by a finger or the pointer within it alone (View::bounds_input)
  mut bounds_input : Bool
  /// a wheel turned over it what is drawn under it's, its presses still its own (View::wheel_through)
  mut wheel_through : Bool
  /// what it and what it holds are drawn clear of the fading and stretching of (View::drawn_clear_of)
  mut drawn_clear : NodeId?
  /// how far in from its right edge the pointer brings its bar out (View::bar_near; 0 none), and whether it does now
  mut bar_near : Double
  /// whether its bar is along its foot (View::bar_near's `across`: a row that scrolls sideways), not its right
  mut bar_across : Bool
  /// whether the pointer over it, or over what it holds that takes it not, is over it (View::points): pointed at,
  /// never pressed nor held
  mut points : Bool
  mut bar_near_cell : @signals.Signal[Bool]?
  /// what brings a part of what it holds into its sight (View::shows): given where that is in its own terms (its top,
  /// its foot), how far it moved what it holds to
  mut shows : ((Double, Double) -> Double)?
  /// whether what it brings into sight it brings across (View::shows' `across`): a row that scrolls sideways
  mut shows_across : Bool
  /// whether it takes over a hold that began on what it holds, moved so far from where it went down (View::claims)
  mut claims : ((Double, Double) -> Bool)?
  /// where a hold it takes over may have gone down, in its own terms (View::claims' `from`): none, anywhere
  mut claims_from : ((Double, Double) -> Bool)?
  /// how many times it was said to take over holds (View::claims): a hold asks it as it was said as it went down
  mut claims_said : Int
  /// a hold on it is one what holds it may take over as it moves (View::claims), the hold not its own yet: a gesture
  /// waiting on a tap, a hold of the finger or its own slop (View::gesture)
  mut yields : Bool
  /// how far apart the lines of a row that wraps are laid out (View::wraps; None: as its gap says, or none wraps)
  mut line_gap : Double?
  /// where it wraps, its later lines go above its first, which stays at its foot (View::wraps_up)
  mut wraps_up : Bool
  /// what it says in place of its words, in order, where they have not the room on their line (View::shorter; none:
  /// none)
  mut shorter : Array[String]
  /// how much it gives way and how narrow it may be as said of it (View::shrink, View::min_width; None: not said, as
  /// what it is makes them: Tree::give_way_applied)
  mut shrink_said : Double?
  mut min_w_said : Double??
  /// how wide it may be at most as said of it (View::max_width; None: not said, as what it is makes it:
  /// Tree::capped_applied)
  mut max_w_said : Double??
  /// the least and the most width said as so many points or all of what holds it where that is less (View::min_width_within,
  /// max_width_within: a card 360 to 560 within its room)
  mut min_w_within : Bool
  mut max_w_within : Bool
  /// what it takes over holds for is scrolling what it holds (View::claims' `scrolls`)
  mut claims_scroll : Bool
  /// where it scrolls what it holds up and down (View::scrolls): the node holding that, whose height less its own is how
  /// far it can go (Scroll's room); -1 for one that does not
  mut scroll_held : Int
  /// whether what it scrolls it scrolls across (View::scrolls with Scroll::across): which way Tree::scrolls_now asks
  /// whether it can go
  mut scroll_across : Bool
  /// whether it holds a page's list's rows (Scroll::list's, up and down): on a host that sets them on its pixels
  /// (Tree::set_rows_grid), each laid out as tall as whole pixels (@flex.Style's rows_grid) and all moved alike so the
  /// first one's top is on one, as an old view's list's are (ui's Ctx::row_slot, Ctx::rows_on_pixels)
  mut list_rows : Bool
  mut focus_shown_cell : @signals.Signal[Bool]?
  /// what a finger or the pointer held on it does as it goes (View::on_drag)
  mut on_drag : ((Drag) -> Unit)?
  /// how many fingers held on it at once it takes (View::on_drag's `fingers`): one more calls the hold off
  mut fingers : Int
  /// which saying of its on_drag it is (each said anew, or let go, another): what was told by one is that one's alone
  mut drag_said : Int
  /// where in it a finger is taken at a moment (View::takes, View::hosted_takes; none: all of it)
  mut takes : Takes?
  /// what reads where it takes a finger (View::takes) for what asks, one for each size and moment asked of: each worked
  /// out again as what it read changes, following nothing once nothing follows it (let go as another is asked for), all
  /// let go as it is said anew or let go (Tree::takes_rects); what asks follows them, never what they read
  mut takes_units : Array[(@signals.Computed[Array[(Double, Double, Double, Double)]], Double, Double, Double)]
  /// told as where it takes a finger is said anew or it is let go: what asks follows it too
  mut takes_ver : @signals.Signal[Int]?
  /// what ends what its on_drag set going (a gesture's: its hold's moment, its dispatch), as it is said anew or let go
  mut drag_end : (() -> Unit)?
  /// a slot (show, pick, each): no box of its own, what it holds laid out as its holder's own
  mut slot : Bool
  /// a boundary's (View::boundary): told of a fault under it
  mut fault_to : ((String) -> Unit)?
  /// drawn by what hosts the tree (View::hosted)
  mut hosted : Bool
  /// the hosted content needs its node's clip in addition to any clip explicitly set on the node
  mut hosted_clips : Bool
  /// what it says it is, read out (View::says); None nothing
  mut said : Said?
  /// what it and all it holds are kept from what is read out (View::hides)
  mut said_hidden : Bool
  /// what it and all it holds are drawn in, as their bones (View::bones): 0 none
  mut bones : Int64
  /// drawn in its bones as one piece of its own box, nothing in it drawn (View::bone_whole)
  mut bone_whole : Bool
  /// its words cut short across where what holds it has not the room (View::cuts)
  mut cut : Bool
  /// its instance to be made again (its look changed); its place (and what it holds) to be worked out again
  mut look_due : Bool
  mut place_due : Bool
  /// where it is in what holds it (its layout's place and its own offset), how opaque of itself, how big: worked out
  /// once it is placed
  mut placed : Bool
  /// left out of its row as it was last laid out (View::drops): laid out nowhere, what it holds with it; none of it drawn,
  /// pressed or read out
  mut out : Bool
  mut lx : Double
  mut ly : Double
  mut la : Double
  mut lw : Double
  mut lh : Double
  /// how big it is drawn, about which point of it (in points, where it is its own)
  mut ls : Double
  mut lpx : Double
  mut lpy : Double
  /// the box round what it and what it holds draw, where it is its own (View::scale's Drawn): worked out again once
  /// something of it changed (`drawn_stale`: what draws, where, how big), kept while nothing did
  mut drawn_box : (Double, Double, Double, Double)
  mut drawn_stale : Bool
  /// whether it draws, and where it is drawn off (its offset and shift), as last told: what the box round what draws in
  /// each that holds it changes by (Tree::drawn_box_of), nothing else of it
  mut drew : Bool
  mut drawn_off : (Double, Double, Double, Double)
  /// what it draws, as last made
  mut content : Content?
  /// leaving (View::going): since when it goes as from its start (-1: not leaving), how long all of it takes; coming
  /// back (shown again as it left): since when, from how far gone (-1: not coming back); what reads how far it is gone
  /// told as either starts or ends
  mut left_at : Double
  mut span : Double
  mut back_at : Double
  mut back_from : Double
  mut going : @signals.Signal[Int]?
  /// it, and what it holds, take no press (View::presses)
  mut inert : Bool
  /// turned off (View::turned_off): where it is drawn it takes a press and does nothing with it, what lies under it not
  /// reached, the pointer an arrow over it (a send button with nothing to send, a picture with nothing to open)
  mut turned_off : Bool
  /// it is a modal layer while this holds (View::modal): what it does not hold takes no input
  mut modal : Bool
  /// as a modal layer, a back gesture under way as it comes over what holds it goes on to that (View::held_back_goes_on)
  mut back_goes_on : Bool
  /// as a modal layer, what is typed still the field of an old view under it that has the focus as it comes over it
  /// (View::leaves_typing)
  mut leaves_typing : Bool
  /// it, and what it holds, are over all else of the window while this holds (View::over_all)
  mut over_all : Bool
  /// drawn, with what it holds, over the scrim of a modal layer of the old frame's up (View::over_scrim)
  mut over_scrim : Bool
  /// where it is in the window's stack of layers, the old frame's among them (View::stacked); -1 none
  mut stack : Int
}

///|
/// The nodes made once of a window, its clock and what it did.
pub struct Tree {
  /// which node a row made anew for its key is now, by the name it is known by (View::row_known_as: one of
  /// Tree::row_name's, never a node's own)
  rows_known : Map[NodeId, Int]
  /// how many such names were given (Tree::row_name)
  mut rows_named : Int
  /// the moment what is drawn is drawn at (a frame's, to be shown then), a signal a look follows (Tree::drawn_at); the
  /// logic follows no clock (its moment `logic`, what is due on its timeline said once: Tree::advance)
  clock : @signals.Signal[Double]
  /// the same moment, for what draws a wait by it (a cycle: View::cycle): what never ends, read apart from what moves
  beat : @signals.Signal[Double]
  /// what works out each glyph's look where a node says one (View::glyphs_by), by its index and making
  glyph_looks : Map[Int, (Int, (Double, GlyphAt) -> GlyphLook)]
  /// the same moment on the resident clock's steps (resident_step_ms): for an endless decoration drawn by it
  /// (View::cycle_resident), told only as a step is passed
  resident : @signals.Signal[Double]
  /// the nodes that read it (View::cycle_resident), each with its making and the step it last read: one reading it now
  /// has read the step it is on (each reading it is worked out again as it passes a step); its steps woken for only
  /// while one such is drawn
  resident_readers : Map[Int, (Int, Double)]
  /// told each time what the root holds is put at another place in the window's stack of layers (View::stacked,
  /// View::over_all): what orders things by those places as it is built (an old frame's layers opened in its nodes:
  /// Tree::places_read) built again
  places : @signals.Signal[Int]
  /// the time now, as a change is told (the host's: an event's moment, before a frame takes it); none: the clock's
  time : (() -> Double)?
  /// the moment the change a queued binding works out was told, while it is (-1: none)
  mut cause_at : Double
  // The moment a frame or the clock brings the tree to while it does (Tree::brought, Tree::at), -1 outside one: what
  // is told meanwhile (a size laid out otherwise, a moment come) is of it
  mut bringing_at : Double
  // The layout pass under way in one (Tree::laid_out), 0 outside one; what it told otherwise, where noted
  // (Tree::told_noted)
  mut laid_passes : Int
  told_otherwise : Array[String]
  // where what marked it to be laid out again came from, in the layout pass under way: said with passes that never stop
  mut laid_marked_at : String
  /// how words are measured: (words, how they are set, width offered) -> (width, height)
  measure : (String, WordsLook, Double) -> (Double, Double)
  /// and words in pieces set their own way (View::words_runs): (the pieces, how the words are set, width offered)
  measure_runs : (Array[@text.Run], WordsLook, RunsLook, Double) -> (Double, Double)
  /// how wide words too wide for a width on one line are drawn where they say shorter ways (View::shorter): the first of
  /// those that fits, else the last cut with an ellipsis, as the host lays them out
  measure_shorter : (String, Array[String], WordsLook, Double) -> Double
  nodes : Array[Node]
  free : Array[Int]
  /// what a frame is to do: the nodes whose look changed, those whose place changed; whether any is to be laid out,
  /// whether the order is to be made again; whether any of it is (what hosts it told as it first is)
  looks_due : Array[Int]
  places_due : Array[Int]
  /// the properties said `Painted`, each worked out again as each frame is painted (Tree::painted_now): its node and
  /// making, and what works it out and sets it where it came out otherwise
  painted : Array[(Int, Int, () -> Unit)]
  /// what is told once the frame is painted (Tree::take_after_paint: the host's side runs it then): a list's rows
  /// sighted, a node first drawn
  after_paint : Array[() -> Unit]
  /// what a layout found to tell of its moment, told as it is done (Tree::said_after_laid): a windowed list's blocks
  /// come in sight
  after_laid : Array[() -> Unit]
  /// the nodes waiting to be first drawn (View::on_first_drawn): node, making, what is then told
  first_drawn : Array[(Int, Int, () -> Unit)]
  /// what is due at a moment of its own, in the order told (Tree::advance): a node leaving or coming back ending, a
  /// step of what goes by steps (View::steps); and how many were ever told (each one's place among those due together)
  timeline : Array[Due]
  mut told : Int
  /// what is due being done (Tree::advance)
  mut advancing : Bool
  /// where its logic stands: what is due by then done (Tree::advance), what is said from then on said as of then at the
  /// earliest
  mut logic : Double
  /// the bindings whose reads changed, to run as the frame begins (Tree::queued)
  bindings_due : Array[Bound]
  /// how many bindings live: what is asked at once (View::laid_size, Tree::bring_to) pulls those whose reads changed
  mut pulls_held : Int
  /// those marked as what they read changed, since they last ran (Tree::pull)
  pulls_marked : Array[Bound]
  /// Layout child lists changed during a keyed removal, to reconcile before layout reads them.
  mut boxes_deferred : BoxesBatch?
  /// Flex may call back into the tree. Removals in that call must update its child lists immediately.
  mut layouts_active : Int
  mut layout_due : Bool
  /// the node whose own layout (View::layout_box) is running now, building and measuring its children (-1 none)
  mut layout_owner : Int
  mut order_due : Bool
  mut due : Bool
  /// the host is being told that a frame is due (Tree::marked)
  mut telling_due : Bool
  /// the host took a frame while being told (Tree::frame)
  mut due_frame_taken : Bool
  mut last_w : Double
  mut last_h : Double
  /// the window's size, as its frames give it: what is laid out by it (which frame a window's width calls for) follows it
  room : @signals.Signal[(Double, Double)]
  /// Each window press, with its number and window coordinates (Tree::went_down).
  pressed_anywhere : @signals.Signal[(Int, Double, Double)]
  /// how many taps there have been anywhere in the window, as the host tells each (Tree::tapped): what a tap anywhere
  /// lets go of follows it
  tapped_anywhere : @signals.Signal[Int]
  /// how many times its words were measured anew for all of them (Tree::words_again: the system's size of words)
  words_redone : @signals.Signal[Int]
  /// how many times what its rows left out changed, as it was laid out (View::left_out)
  outs_said : @signals.Signal[Int]
  /// what its rows left out changed in this layout, to be told as it is done
  mut outs_changed : Bool
  /// the nodes whose size is followed (View::laid_size_told), told as all of the layout is done
  sized : Array[Int]
  /// what is to be brought into sight once laid out (Tree::show_in_sight): a node, and where in it (its own terms, asked
  /// then; none: all of it)
  shows_due : Array[(NodeId, () -> (Double, Double)?)]
  /// the nodes left out in this layout, what they held, their focus and their back to be let go of as it is done
  outs_gone : Array[Int]
  /// the node hosting the old view, if any (View::hosted)
  mut hosting : Int
  /// where in the window's stack of layers the topmost modal layer of what hosts it is (an old frame's: Tree::hold_under;
  /// -1 in none of it, over only what is in none), -2 none: what of it is not over that takes no input; as told each
  /// frame (what is told to follow it), and as it is as asked (`held_under_of`: Tree::held_under_by)
  mut held_under : Int
  mut held_under_of : (() -> Int)?
  /// the nodes said to be modal layers (View::modal, on), living: which is topmost asked of where each is among what
  /// holds it (Tree::modal_top)
  modals : Array[Int]
  /// how deep in a change being committed (Tree::at_cause, an event) it is now, and whether what a modal layer said is to
  /// be told as all of it is committed (Tree::modals_told): what a change does in between (a row put after the rest,
  /// then put in its place) never seen half done
  mut committing : Int
  // what is to be done once the event being taken is committed whole (Tree::after_event), in order
  afters : Array[() -> Unit]
  mut modals_due : Bool
  /// the node a finger is held on (View::on_drag), from its down till it is let go, called off or the node goes
  mut held : NodeId?
  /// whether a gesture's finger let go was its tap (View::gesture: not moved past its slop, not held, not called off),
  /// as the event being taken told it: the host's, to tell the window's taps by (Tree::tapped)
  mut gesture_tapped : Bool
  /// a finger let go now taps nothing: it only lets go of what it picked (the host's, said as it lets go: a gesture's
  /// tap told the tree, not what it does)
  mut taps_withheld : Bool
  /// each finger holding what is held, by its own id: where it went across and down by its own events' times (Drag's
  /// `vx`, `vy`)
  held_tracks : Map[Int, (Tracker, Tracker)]
  /// a finger held on a node a still hold of which is what lies under it's (View::holds_through): what lies there, as it
  /// was found as the finger went down, its hold's moment set going
  mut through : Through?
  /// what hosts the tree told of a hold handed to what it hosts (Tree::on_through), and asked whether what it hosts
  /// takes a press at a point (Tree::hosts_at)
  mut on_through : (Target, Double, Double, Double, Handed) -> Unit
  mut hosts_at : (NodeId, Double, Double) -> Int?
  /// what the host says takes a finger at a point instead of what the tree found there (Tree::on_target), given what
  /// takes it there in the order they are drawn
  mut retarget : (Target, Array[Target], Double, Double) -> Target
  /// how far across each way a press's room is at least (the host's, by how it is pointed at: a finger's 44, a pointer's
  /// 36): what is drawn smaller than that is reached from round it (Tree::target_in); 0, by what is drawn alone
  mut press_least : Double
  /// what hosts the tree is told as a column it holds glides on by itself, let go (Tree::on_glides): which column and
  /// when its glide ends as it is asked (none: at rest); and as that column is let go
  mut glides : (Int, () -> Double?) -> Unit
  mut glides_gone : (Int) -> Unit
  /// how a page's list moves where it is drawn, and how many pixels a point is there (Tree::lists_feel)
  mut list_feel : () -> (ListFeel, Double)
  /// what waits on all of it laid out as it is next, whatever came out otherwise (Tree::once_laid_out)
  laid_waits : Array[() -> Unit]
  /// the node a finger or the pointer is held on, and the one the pointer is over (of those that take a press): each
  /// node's own cell told as it comes or goes (View::pressed, View::pointed)
  mut pressing : NodeId?
  mut pointed : NodeId?
  /// every node read as pointed at and pressed (Tree::lit_all), for what measures what the hand changes, at the moment
  /// of the frame before it (ui's hand_moves.mbt): not the hand's, nothing of it changed
  mut lit_every : Bool
  // where the pointer is in the window, as it is said (Tree::point_at; (-1, -1) none): what goes beside it is placed
  // by (View::beside's `at_pointer`)
  mut pointer_xy : (Double, Double)
  /// what the pointer is over of what says it is pointed at alone (View::points), where that is over all that takes
  /// it there (Tree::points_over)
  mut points_hover : NodeId?
  /// what scrolls in each node that does (View::scrolls), by the node: what it holds finds it (View::scroll_holding)
  scrolls_at : Map[Int, Scroll]
  /// the columns that scroll whose bars come out where the pointer is along their edge (View::bar_near), and which
  /// the pointer is along now (told as withins are: Tree::bars_near_told)
  bar_cols : Array[(Int, Int)]
  /// what follows whether what is drawn is drawn at or past a moment (View::drawn_past): its node, the moment, and
  /// what is told as that comes to be so or not
  drawn_marks : Array[(NodeId, Double, @signals.Signal[Bool])]
  /// a column's bar said anew to come out or not (View::bar_near): which the pointer is along to be told anew
  mut bars_due : Bool
  /// the node with the keyboard's focus, and whether it shows (it came by the keyboard): its cells told as it comes or
  /// goes (View::focused); what hosts the tree told as it is let go of at a cause (the node let go, leaving, taking
  /// no press, under a modal layer: Tree::on_focus_lost)
  /// the node a back gesture is held by, as it said it then (Tree::back_step): from its start till it is let go,
  /// called off or the node goes
  mut backing : (NodeId, Int)?
  /// the nodes said to take back (View::takes_back, View::follows_back), each once: those of them that take it still
  /// gone over to find what takes it (Tree::back_taker), never the whole tree; one let go, or said anew to take it no
  /// more, dropped then
  back_said_at : Array[Int]
  /// the nodes said to take keys (View::on_key), each once: what the focus is not in asked of them alone
  /// (Tree::key_at), never the whole tree; one let go, or another made at its index, dropped as keys are asked
  keys_said_at : Set[Int]
  mut focused : NodeId?
  mut focus_visible : Bool
  /// the node that had the focus as it was laid out nowhere (and whether it showed), given it back as it is laid out again
  /// where nothing has taken it meanwhile (Tree::outs_told), as an old view's focus waits for its node
  mut focus_parked : (NodeId, Bool)?
  mut on_focus_lost : (NodeId) -> Unit
  /// what hosts it gives a node of its asking for the focus (Tree::on_focus_asked: its own focus moved there, told
  /// back), none where nothing hosts it (View::ask_focus: the tree's alone)
  mut on_focus_asked : ((NodeId, Bool) -> Unit)?
  /// the layers that give the focus as they open (View::focus_opens) opened and gone since what a modal layer said was
  /// last told (Tree::modals_now), each with the node it gives it to; and what hosts the tree is told of them
  /// (Tree::on_layers_focus)
  focus_opened : Array[(NodeId, NodeId?)]
  focus_gone : Array[NodeId]
  /// the layers that give the focus to the first of what they hold that takes it as they open (View::focus_opens_first)
  focus_firsts : Set[NodeId]
  /// the layers that give the focus back as they go to a node said, not to what had it as they opened
  /// (View::returns_focus_to)
  focus_backs : Map[NodeId, NodeId]
  /// the room under what it holds and its foot covered, given each node measured so (Layout::measure's `foot`), and
  /// the box that reads it under it (Layout::given_foot)
  feet : Map[Int, (Double, Double)]
  foot_readers : Map[Int, Int]
  /// what each box's layout reported of what it laid out, by name (Layout::report)
  reports : Map[Int, Map[String, (Double, Double)]]
  /// what each node works out of how big a node holding it is laid out, by that node (Live's Roomed)
  roomed : Map[Int, Array[(Int, Int, (Double, Double) -> Unit)]]
  mut on_layers_focus : (Array[NodeId], Array[(NodeId, NodeId?)]) -> Unit
  /// what follows what is under the pointer, while it is over the window (Tree::point_at)
  mut point_stop : (() -> Unit)?
  /// let go (Tree::dispose): what is made for it after stops at once
  mut gone : Bool
  /// the nodes said to go beside another (View::beside), as said (each let go is passed over, and dropped as placed)
  besides_at : Array[Int]
  /// the nodes whose being under the pointer is read (View::pointer_within: their cells), each as it was made (its
  /// index and generation), told again as the pointer moves and as what is placed changes
  withins_at : Array[(Int, Int)]
  /// pointer geometry waiting for the whole signal change to be committed
  mut withins_asked : Bool
  /// whether a frame's laying out is telling what is under the pointer (Tree::laid_out): what it lays out then not again
  mut withins_passing : Bool
  /// the nodes whose taking input is read (View::takes_input), as first read
  inputs_at : Array[Int]
  /// which following of the point is the one now (Tree::follow_point): each said, and each let go, another
  mut point_said : Int
  /// how many times what a point would hit may have changed (a layout, a place, the order, a node made or let go, what
  /// takes presses or holds a layer): what is pointed at worked out again only past one (Tree::hits_said)
  mut hits : Int
  /// the fingers down on it (each by its id: Drag's `finger`), in the order they went down
  downs : Array[Int]
  /// what the last frame changed: the nodes whose content it made again, those placed or faded otherwise
  changed : Array[NodeId]
  composed : Array[NodeId]
  /// the nodes let go since the host last took them (Tree::take_removed): what it keeps for them to let go too
  removed : Array[NodeId]
  /// the nodes whose content was made again since the host last took them (Tree::take_changed), and whether anything
  /// drawn changed since the last frame
  pending : Array[NodeId]
  /// the nodes placed, faded, turned or cut otherwise since the host last took them (Tree::take_placed)
  placed_pending : Array[NodeId]
  /// the nodes what each holds is drawn in another order since the host last took them (Tree::take_ordered)
  ordered_pending : Array[NodeId]
  mut drawn_due : Bool
  /// how many ask for where things stand as each change comes, before it is taken (View::laid_before_causes): what is
  /// laid out otherwise by a change before it laid out and placed as that one comes, whether a frame came or not
  mut before_causes : Int
  /// laying out where things stand before a change (Tree::stand_before_cause): not again inside it
  mut standing : Bool
  /// asked to be laid out and placed once the change under way is told whole (Tree::settle_after_change)
  mut settle_asked : Bool
  mut settle_at : Double
  /// what the layout last came to where it was laid out to be read (Tree::measured_now) and not yet placed by: its
  /// compute's number (-1: none): placed by that once a frame or a change's end places things, nothing laid out anew
  mut measured_gen : Int
  /// the first compute laid out to be read since things were last placed (-1: none): what a later layout places by too
  mut walk_from : Int
  /// how many device pixels a point what hosts it draws at (0: none said): what is drawn off where it is laid out drawn
  /// off by whole pixels (View::drawn_off), as an old view's look is
  mut pixel_grid : Double
  /// how many device pixels a point a page's list's rows are set on (0: anywhere): its host's, where it sets them so, as
  /// it does an old view's (Tree::set_rows_grid)
  mut rows_grid : Double
  /// the nodes holding such a list's rows (Node's list_rows), let go or not
  rows_lists : Array[Int]
  /// the thumbs of its columns' bars (View::scroll_bar), by their places: what a node over one yields to (ui's
  /// yield_thumbs, Tree::thumb_at)
  thumbs : Map[Int, NodeId]
  /// rows_grid, followed (Tree::rows_slot)
  rows_grid_said : @signals.Signal[Double]
  work : Work
  /// told as there is first something for a frame to do: what hosts it asks for a frame
  mut on_due : () -> Unit
  /// what hosts the tree told as what may take input changes (a modal layer said on, what is drawn over what, a node
  /// let go, leaving, said to take no press): what it holds of its own, an old view's press, to ask whether that may
  /// still take input (Tree::takes_presses)
  mut on_modals : () -> Unit
}

///|
/// A property's binding as it stands (Tree::queued): queued for a frame, marked as what it read changed, live, and what
/// runs it.
struct Bound {
  mut queued : Bool
  mut marked : Bool
  mut live : Bool
  mut watch : @signals.Watch?
  mut run : () -> Unit
}

///|
/// The child lists dirtied while a single keyed slot lets rows go.
struct BoxesBatch {
  slot : NodeId
  pending : Set[NodeId]
}

///|
/// A handle on a node made once: the tree, its index, its making there.
pub struct View {
  tree : Tree
  at : Int
  gen : Int
}

///|
/// A tree whose root `make` makes (as the root's own: its bindings, its nodes), its words measured by `measure` (in
/// pieces set their own way: `measure_runs`; said a shorter way where too wide: `measure_shorter`).
pub fn Tree::new(
  make : (View) -> Unit,
  measure? : (String, WordsLook, Double) -> (Double, Double) = words_measure,
  measure_runs? : (Array[@text.Run], WordsLook, RunsLook, Double) -> (Double, Double) = runs_measure,
  measure_shorter? : (String, Array[String], WordsLook, Double) -> Double,
  time? : () -> Double,
) -> Tree {
  // (the moment it is made, taken once: its logic and what it draws start there, and what it is made with is of then)
  let start = match time {
    Some(f) => f()
    None => 0.0
  }
  let t : Tree = {
    clock: @signals.signal(start, same=fn(a, b) { a == b }),
    beat: @signals.signal(start, same=fn(a, b) { a == b }),
    glyph_looks: {},
    resident: @signals.signal(resident_of(start), same=fn(a, b) { a == b }),
    resident_readers: {},
    places: @signals.signal(0),
    room: @signals.signal((0.0, 0.0), same=fn(a, b) { a == b }),
    pressed_anywhere: @signals.signal((0, -1.0, -1.0), same=fn(a, b) { a == b }),
    tapped_anywhere: @signals.signal(0, same=fn(a, b) { a == b }),
    words_redone: @signals.signal(0, same=fn(a, b) { a == b }),
    outs_said: @signals.signal(0, same=fn(a, b) { a == b }),
    outs_changed: false,
    sized: [],
    shows_due: [],
    outs_gone: [],
    time,
    cause_at: -1.0,
    bringing_at: -1.0,
    laid_passes: 0,
    laid_marked_at: "",
    told_otherwise: [],
    measure,
    measure_runs,
    measure_shorter: match measure_shorter {
      Some(f) => f
      None => fn(words, shorter, look, room) { shorter_w_by(measure, words, shorter, look, room) }
    },
    rows_known: {},
    rows_named: 0,
    nodes: [],
    free: [],
    looks_due: [],
    places_due: [],
    painted: [],
    after_paint: [],
    after_laid: [],
    first_drawn: [],
    bindings_due: [],
    pulls_held: 0,
    pulls_marked: [],
    boxes_deferred: None,
    layouts_active: 0,
    timeline: [],
    told: 0,
    advancing: false,
    logic: start,
    layout_due: true,
    layout_owner: -1,
    order_due: true,
    due: true,
    telling_due: false,
    due_frame_taken: false,
    last_w: -1.0,
    last_h: -1.0,
    hosting: -1,
    held_under: -2,
    held_under_of: None,
    modals: [],
    committing: 0,
    afters: [],
    modals_due: false,
    held: None,
    gesture_tapped: false,
    taps_withheld: false,
    held_tracks: {},
    through: None,
    on_through: fn(_, _, _, _, _) {  },
    hosts_at: fn(_, _, _) { None },
    retarget: fn(t, _, _, _) { t },
    press_least: 0.0,
    glides: fn(_, _) {  },
    glides_gone: fn(_) {  },
    list_feel: fn() { (Desktop, 1.0) },
    laid_waits: [],
    pressing: None,
    pointed: None,
    lit_every: false,
    pointer_xy: (-1.0, -1.0),
    points_hover: None,
    scrolls_at: {},
    bar_cols: [],
    drawn_marks: [],
    bars_due: false,
    backing: None,
    back_said_at: [],
    keys_said_at: Set::new(),
    focused: None,
    focus_parked: None,
    focus_visible: false,
    on_focus_lost: fn(_) {  },
    on_focus_asked: None,
    focus_opened: [],
    focus_gone: [],
    focus_firsts: Set::new(),
    focus_backs: {},
    feet: {},
    foot_readers: {},
    reports: {},
    roomed: {},
    on_layers_focus: fn(_, _) {  },
    point_stop: None,
    gone: false,
    besides_at: [],
    withins_at: [],
    withins_asked: false,
    withins_passing: false,
    inputs_at: [],
    point_said: 0,
    hits: 0,
    downs: [],
    changed: [],
    composed: [],
    removed: [],
    pending: [],
    placed_pending: [],
    ordered_pending: [],
    drawn_due: false,
    before_causes: 0,
    standing: false,
    settle_asked: false,
    settle_at: 0.0,
    measured_gen: -1,
    walk_from: -1,
    pixel_grid: 0.0,
    rows_grid: 0.0,
    rows_lists: [],
    thumbs: {},
    rows_grid_said: @signals.signal(0.0),
    on_due: fn() {  },
    on_modals: fn() {  },
    work: {
      besides: 0,
      made: 0,
      let_go: 0,
      bound: 0,
      same: 0,
      computes: 0,
      laid: 0,
      visited: 0,
      measured: 0,
      instances: 0,
      composed: 0,
      changes: 0,
      orders: 0,
      structure: 0,
      hit_visited: 0,
      keys_asked: 0,
      pulled: 0,
      drawn_boxes: 0,
      settles: 0,
      keys_swept: 0,
    },
  }
  let root = t.made(-1)
  root.owning(fn() { make(root) })
  t
}

///|
/// Words measured as a test's are: 7 a character, 18 a line, wrapped to the width offered.
pub fn words_measure(words : String, _look : WordsLook, width : Double) -> (Double, Double) {
  let full = words.length().to_double() * 7.0
  if full <= 0.0 {
    return (0.0, 0.0)
  }
  let w = if width > 0.0 && width < full { width } else { full }
  let lines = if w > 0.0 { (full / w).ceil() } else { 1.0 }
  (w, lines * 18.0)
}

///|
/// A node made in `parent` (-1: the root), its scope its own (made with nothing reading: owned by nothing else).
fn Tree::made(self : Tree, parent : Int) -> View {
  self.work.made = self.work.made + 1
  self.hits = self.hits + 1
  let at = match self.free.pop() {
    Some(i) => {
      let n = self.nodes[i]
      n.gen = n.gen + 1
      n.live = true
      // (what was given the one at this place before (Layout::measure's `foot`), none of its own)
      self.feet.remove(i)
      self.foot_readers.remove(i)
      self.reports.remove(i)
      self.roomed.remove(i)
      n.flex = @flex.Node::new()
      n.look.ground = 0L
      n.look.ink = 0L
      n.look.words = ""
      n.look.words_drawn = None
      n.shorter = []
      n.shrink_said = None
      n.min_w_said = None
      n.max_w_said = None
      n.min_w_within = false
      n.max_w_within = false
      n.look.runs = []
      n.look.runs_look = runs_plain
      n.look.runs_pressed = -1
      n.look.runs_picked = (0, 0)
      n.look.runs_lit = (0, 0, 0L, 0.0)
      n.look.shapes = []
      n.look.tint = 0L
      n.look.radius = 0.0
      n.look.corners = None
      n.look.edge = (0.0, 0L)
      n.look.edge_dashed = false
      n.look.notch = (0.0, 0.0, 0.0)
      n.look.shadow_out = false
      n.look.cut_across = None
      n.look.clip_drawn = None
      n.look.image = None
      n.look.image_for = (0.0, 0.0)
      n.look.image_cover = false
      n.look.image_fade = false
      n.look.image_in = None
      n.look.glass = None
      n.look.words_look = words_plain
      n.look.shadow = (0.0, 0.0, 0L)
      n.said = None
      n.said_hidden = false
      n.bones = 0L
      n.bone_whole = false
      n.cut = false
      n.look.alpha = 1.0
      n.look.dx = 0.0
      n.look.dy = 0.0
      n.look.sx = 0.0
      n.look.sy = 0.0
      n.look.scale = 1.0
      n.look.pivot = At(0.5, 0.5)
      n.look.drawn_as = ""
      n.look.clips = false
      n.look.words_center = false
      n.look.ellipsis_past = false
      n.look.picture = None
      n.look.glyphs_at = None
      n.look.turn = 0.0
      n.look.turn_drawn = false
      n.look.fades = (0.0, 0.0, 0.0, 0.0)
      n.look.stretch = 0.0
      n.look.drawn_off = (0.0, 0.0)
      n.look.ground_drawn = (0.0, 0.0, 0.0, 0.0)
      n.look.cut_soft = false
      n.look.lines = []
      n.drew = false
      n.drawn_off = (0.0, 0.0, 0.0, 0.0)
      n.went = None
      n.parent = parent
      n.allow_ellipsis = false
      n.slot = false
      n.fault_to = None
      n.hosted = false
      n.hosted_clips = false
      n.on_press = None
      n.top_row = false
      n.moves_window = false
      n.on_menu = None
      n.on_wheel = None
      n.on_key = None
      n.keys_in_fields = []
      n.on_back = None
      n.on_back_step = None
      n.pressed_cell = None
      n.pointed_cell = None
      n.on_pointer_moved = None
      n.pointed_in_cell = None
      n.within_cell = None
      n.here_cell = None
      n.said_cell = None
      n.each_row = false
      n.row_id = None
      n.row_index = None
      n.focusable = false
      n.focus_typing = false
      n.focus_keys = 0
      n.focus_tab = true
      n.tab_by_stop = false
      n.input_cell = None
      n.cursor = None
      n.beside = None
      n.beside_last = None
      n.beside_point = None
      n.focused_cell = None
      n.size_cell = None
      n.rect_cell = None
      n.drawn_rect_cell = None
      n.went_cell = None
      n.bounds_input = false
      n.wheel_through = false
      n.drawn_clear = None
      n.bar_near = 0.0
      n.bar_across = false
      n.points = false
      n.bar_near_cell = None
      n.shows = None
      n.shows_across = false
      n.claims = None
      n.claims_from = None
      n.claims_said = 0
      n.yields = false
      n.line_gap = None
      n.wraps_up = false
      n.claims_scroll = false
      n.scroll_held = -1
      n.scroll_across = false
      n.list_rows = false
      n.focus_shown_cell = None
      n.key_said = 0
      n.wheel_said = 0
      n.on_drag = None
      n.takes = None
      n.takes_units = []
      n.takes_ver = None
      n.drag_end = None
      n.look_due = false
      n.place_due = false
      n.placed = false
      n.out = false
      n.content = None
      n.left_at = -1.0
      n.span = 0.0
      n.back_at = -1.0
      n.back_from = 0.0
      n.going = None
      n.inert = false
      n.turned_off = false
      n.modal = false
      n.back_goes_on = false
      n.leaves_typing = false
      n.over_all = false
      n.over_scrim = false
      n.stack = -1
      i
    }
    None => {
      self.nodes.push({
        gen: 0,
        live: true,
        flex: @flex.Node::new(),
        look: { ground: 0L, ink: 0L, words: "", words_drawn: None, words_look: words_plain, runs: [], runs_look: runs_plain, runs_pressed: -1, runs_picked: (0, 0), runs_lit: (0, 0, 0L, 0.0), shadow: (0.0, 0.0, 0L), shapes: [], tint: 0L, lines: [], edge: (0.0, 0L), edge_dashed: false, notch: (0.0, 0.0, 0.0), shadow_out: false, cut_across: None, clip_drawn: None, image: None, image_for: (0.0, 0.0), image_cover: false, image_fade: false, stretch: 0.0, image_in: None, radius: 0.0, corners: None, glass: None, alpha: 1.0, dx: 0.0, dy: 0.0, sx: 0.0, sy: 0.0, scale: 1.0, pivot: At(0.5, 0.5), turn: 0.0, turn_drawn: false, fades: (0.0, 0.0, 0.0, 0.0), drawn_off: (0.0, 0.0), ground_drawn: (0.0, 0.0, 0.0, 0.0), cut_soft: false, drawn_as: "", clips: false, words_center: false, ellipsis_past: false, picture: None, glyphs_at: None, native_anchor: "" },
        parent,
        allow_ellipsis: false,
        kids: [],
        owner: None,
        stop: None,
        drops: {},
        drop_next: 0,
        props: {},
        on_press: None,
        top_row: false,
        moves_window: false,
        on_menu: None,
        on_wheel: None,
        on_key: None,
        keys_in_fields: [],
        key_said: 0,
        wheel_said: 0,
        on_back: None,
        on_back_step: None,
        back_said: 0,
        pressed_cell: None,
        pointed_cell: None,
        on_pointer_moved: None,
        pointed_in_cell: None,
        within_cell: None,
        here_cell: None,
        said_cell: None,
        each_row: false,
        row_id: None,
        row_index: None,
        focusable: false,
        focus_typing: false,
        input_cell: None,
        cursor: None,
        beside: None,
        went: None,
        beside_last: None,
        beside_point: None,
        focus_keys: 0,
        focus_tab: true,
        tab_by_stop: false,
        focused_cell: None,
        size_cell: None,
        rect_cell: None,
        drawn_rect_cell: None,
        went_cell: None,
        bounds_input: false,
        wheel_through: false,
        drawn_clear: None,
        bar_near: 0.0,
        bar_across: false,
        points: false,
        bar_near_cell: None,
        shows: None,
        shows_across: false,
        claims: None,
        claims_from: None,
        claims_said: 0,
        yields: false,
        line_gap: None,
        wraps_up: false,
        shrink_said: None,
        min_w_said: None,
        max_w_said: None,
        min_w_within: false,
        max_w_within: false,
        shorter: [],
        claims_scroll: false,
        scroll_held: -1,
        scroll_across: false,
        list_rows: false,
        focus_shown_cell: None,
        on_drag: None,
        fingers: 1,
        drag_said: 0,
        takes: None,
        takes_units: [],
        takes_ver: None,
        drag_end: None,
        slot: false,
        fault_to: None,
        hosted: false,
        hosted_clips: false,
        said: None,
        said_hidden: false,
        bones: 0L,
        bone_whole: false,
        cut: false,
        look_due: false,
        place_due: false,
        placed: false,
        out: false,
        lx: 0.0,
        ly: 0.0,
        la: 1.0,
        lw: 0.0,
        lh: 0.0,
        ls: 1.0,
        lpx: 0.0,
        lpy: 0.0,
        drawn_box: (0.0, 0.0, 0.0, 0.0),
        drawn_stale: true,
        drew: false,
        drawn_off: (0.0, 0.0, 0.0, 0.0),
        content: None,
        left_at: -1.0,
        span: 0.0,
        back_at: -1.0,
        back_from: 0.0,
        going: None,
        inert: false,
        turned_off: false,
        modal: false,
        back_goes_on: false,
        leaves_typing: false,
        over_all: false,
        over_scrim: false,
        stack: -1,
      })
      self.nodes.length() - 1
    }
  }
  let n = self.nodes[at]
  let was = @signals.set_active_sub(None)
  let was_owner = @signals.set_owner(None)
  n.stop = Some(@signals.effect_scope(fn() { n.owner = @signals.active_sub() }))
  @signals.set_active_sub(was) |> ignore
  @signals.set_owner(was_owner) |> ignore
  self.order_marked()
  self.handle(at)
}

///|
/// The node, where the handle is on one that lives (not let go, its index not made again since): where every use of a
/// handle begins, so that one on a node let go does nothing.
fn View::live(self : View) -> Node? {
  if self.at < 0 || self.at >= self.tree.nodes.length() {
    return None
  }
  let n = self.tree.nodes[self.at]
  if n.live && n.gen == self.gen {
    Some(n)
  } else {
    None
  }
}

///|
/// `f` run owned by the node's scope (what it makes, tracked or not, let go with the node), nothing it reads followed,
/// where the node lives.
fn View::owning(self : View, f : () -> Unit) -> Unit {
  guard self.live() is Some(n) else { return }
  let was = @signals.set_active_sub(None)
  let was_owner = @signals.set_owner(n.owner)
  f()
  @signals.set_active_sub(was) |> ignore
  @signals.set_owner(was_owner) |> ignore
}

///|
fn Tree::handle(self : Tree, at : Int) -> View {
  { tree: self, at, gen: self.nodes[at].gen }
}

///|
/// A handle on no node (what a handle on a node let go makes): it does nothing.
fn Tree::none(self : Tree) -> View {
  { tree: self, at: -1, gen: -1 }
}

///|
/// The root.
pub fn Tree::root(self : Tree) -> View {
  self.handle(0)
}

///|
/// The moment the logic is at, for what is done (an event's, a step's, something due's while it is done; else the
/// moment its logic has come to): followed by nothing; what is to happen at a moment is said once, on the timeline
/// (View::at_moment, View::steps), never found by watching the clock. For a look, Tree::drawn_at.
pub fn Tree::logic_at(self : Tree) -> Double {
  if self.cause_at >= 0.0 {
    self.cause_at
  } else {
    self.logic
  }
}

///|
/// The moment what is drawn is drawn at (a frame's, to be shown then; an input's, as it is pressed), followed: for a
/// look worked out from the time (a fade, a place by the time), worked out again as it goes. Never for what is done.
pub fn Tree::drawn_at(self : Tree) -> Double {
  self.clock.get()
}

///|
/// Where a cycle of `period` ms is as what is drawn is drawn (0 to 1, from moment 0 on), followed: for a wait drawn by
/// it as long as it shows (a spinner's turn, a band of progress not known), which never ends and is no motion
/// (Tree::cycle_read); as Ctx::cycle is an old view's.
pub fn View::cycle(self : View, period : Double) -> Double {
  let t = self.tree.beat.get()
  if period <= 0.0 {
    return 0.0
  }
  let p = t / period
  p - p.floor()
}

///|
/// How far apart the resident clock's steps are (an old view's cycle_step_ms): an endless decoration drawn by it
/// (View::cycle_resident) is drawn anew at each, never between.
pub let resident_step_ms : Double = 100.0

///|
/// Moment `ms` on the resident clock: the step it is in.
fn resident_of(ms : Double) -> Double {
  (ms / resident_step_ms).floor() * resident_step_ms
}

///|
/// A frame's moment told (beat's), and on the resident clock's steps (resident's): a frame's alone, never the moment an
/// input or the logic is worked out at for a while (what is drawn at the resident clock's step is what the frames show).
fn Tree::beat_set(self : Tree, ms : Double) -> Unit {
  self.beat.set(ms)
  self.resident.set(resident_of(ms))
}

///|
/// Where a cycle of `period` ms is on the resident clock's steps (0 to 1, from moment 0 on), followed: for an endless
/// decoration (a working mark's spokes, a waiting mark's breath) drawn anew only at each step, as an old view's resident
/// cycle is (Ctx::cycle's `resident`): what hosts the tree wakes for its next step, said `later` (Tree::resident_next),
/// not a frame after each frame.
pub fn View::cycle_resident(self : View, period : Double) -> Double {
  let t = self.tree.resident.get()
  self.tree.resident_readers[self.at] = (self.gen, t)
  if period <= 0.0 {
    return 0.0
  }
  let p = t / period
  p - p.floor()
}

///|
/// Whether an endless decoration reads the resident clock (View::cycle_resident) where it is drawn now (one under a page
/// over it, or left out, draws no step: none woken for it): what hosts the tree wakes for its next step then.
pub fn Tree::resident_read(self : Tree) -> Bool {
  if !self.resident.watched() {
    return false
  }
  // (those let go, or no longer reading it (the step they last read not this one: a mark that stopped), dropped)
  let now = @signals.untracked(fn() { self.resident.get() })
  let gone = []
  for at, r in self.resident_readers {
    let (gen, read) = r
    if !self.alive_id(({ at, gen } : NodeId)) || read != now {
      gone.push(at)
    }
  }
  for at in gone {
    self.resident_readers.remove(at)
  }
  // (one of them drawn: it or what it holds draws, nothing of it left out; each asked by itself, never the whole scene)
  for at, _ in self.resident_readers {
    if self.drawn_in(at) {
      return true
    }
  }
  false
}

///|
/// Whether node `at` or what it holds is in the scene (Tree::walk_drawn's): held by the root, nothing from the root to
/// it left out of its row (a slot adds nothing of its own), and it or something under it, none of that left out,
/// drawing.
fn Tree::drawn_in(self : Tree, at : Int) -> Bool {
  guard self.held_by_root(at) else { return false }
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    if n.out && !n.slot {
      return false
    }
    i = n.parent
  }
  fn draws(k : Int) -> Bool {
    let n = self.nodes[k]
    if !n.slot && (n.out || n.content is Some(_)) {
      return !n.out
    }
    n.kids.iter().any(draws)
  }

  draws(at)
}

///|
/// The resident clock's next step after `now`, the moment a frame draws: the frame's own, not the tree's clock, which a
/// frame of the looks alone does not move (a step found from the moment built last was one already drawn, woken for at
/// once again and again).
pub fn Tree::resident_next(self : Tree, now : Double) -> Double {
  ignore(self)
  resident_of(now) + resident_step_ms
}

///|
/// Whether a wait reads the clock (View::cycle): what hosts the tree draws its frames one after another as an old view's
/// cycle has them drawn, a wait, not a motion (Tree::clock_read).
pub fn Tree::cycle_read(self : Tree) -> Bool {
  self.beat.watched()
}

///|
/// The clock set to `ms` (a frame's time).
pub fn Tree::at(self : Tree, ms : Double) -> Unit {
  // (what the clock set so tells, of its moment: Tree::brought)
  let was = self.bringing_at
  self.bringing_at = ms
  self.clock_to(ms)
  self.beat_set(ms)
  self.bringing_at = was
}

///|
/// The moment what is drawn is drawn at set to `ms` (a frame's, an input's, the logic's for a while and back): what
/// follows whether it is at or past a moment told so, as it comes to be so or not (View::drawn_past), each still read
/// by what reads it and its node living, the rest let go; told of what was followed as this began, what is followed
/// anew meanwhile kept for the next.
fn Tree::clock_to(self : Tree, ms : Double) -> Unit {
  // (the moment and whether it is past each followed, told as one: no reader sees the one without the other)
  @signals.start_batch()
  self.clock.set(ms)
  if self.drawn_marks.length() > 0 {
    let keep = []
    for m in self.drawn_marks {
      if self.alive_id(m.0) && m.2.watched() {
        keep.push(m)
      }
    }
    self.drawn_marks.clear()
    self.drawn_marks.append(keep)
    for m in keep {
      m.2.set(ms >= m.1)
    }
  }
  @signals.end_batch()
}

///|
/// Whether what is drawn is drawn at or past moment `t` (Tree::drawn_at's: a frame's moment, an input's, the logic's
/// while it lays out), followed: told only as that comes to be so or not, never as the clock goes otherwise (a look that
/// changes at a moment, as it stands till then: a bar shown full till it starts to go, drawn as of the frame's own
/// moment, whatever the logic's is). The node's: one for each moment, let go with it or once nothing reads it.
pub fn View::drawn_past(self : View, t : Double) -> Bool {
  guard self.live() is Some(_) else { return false }
  let id = self.id()
  let cell = match self.tree.drawn_marks.iter().find_first(fn(m) { m.0 == id && m.1 == t }) {
    Some(m) => m.2
    None => {
      let now = @signals.untracked(fn() { self.tree.clock.get() })
      let c = @signals.signal(now >= t, same=fn(a, b) { a == b })
      self.tree.drawn_marks.push((id, t, c))
      c
    }
  }
  cell.get()
}

///|
/// What it did so far.
pub fn Tree::work(self : Tree) -> Work {
  { ..self.work }
}

///|
/// How many nodes live.
pub fn Tree::alive(self : Tree) -> Int {
  // (let go: none, its root kept to answer none)
  if self.gone {
    return 0
  }
  self.nodes.length() - self.free.length()
}

///|
/// The whole tree let go: every node's scope stopped, what goes with it run, callbacks and measures dropped.
pub fn Tree::dispose(self : Tree) -> Unit {
  if self.gone { return }
  self.gone = true
  // A child's cleanup may change state read by its parent or siblings. Publish those changes only once
  // every scope in this tree has stopped, as one removal; no observer may rebuild a half-disposed tree.
  @signals.start_batch()
  // (what follows the pointer held by nothing of the tree's nodes: let go with it, told nothing more)
  self.point_stopped()
  if self.nodes.length() > 0 && self.nodes[0].live {
    self.root().let_go()
  }
  self.drawn_marks.clear()
  self.looks_due.clear()
  self.places_due.clear()
  self.bindings_due.clear()
  self.pulls_held = 0
  self.pulls_marked.clear()
  self.boxes_deferred = None
  self.timeline.clear()
  self.changed.clear()
  self.composed.clear()
  self.after_laid.clear()
  self.hosting = -1
  self.modals.clear()
  self.back_said_at.clear()
  self.keys_said_at.clear()
  // (its nodes but the root and what they keep dropped, their room given back: the tree itself may never be let go of,
  // held by what its arrays were emptied of (moonc's native backend, moonbitlang/core#4611), each Tester's left with
  // all it held; its root kept, holding nothing and let go, for what is asked of it after: it answers none)
  self.nodes.truncate(1)
  self.nodes.shrink_to_fit()
  if self.nodes.length() > 0 {
    self.nodes[0].kids.clear()
  }
  self.free.clear()
  self.free.shrink_to_fit()
  self.scrolls_at.clear()
  self.shows_due.clear()
  self.laid_waits.clear()
  self.afters.clear()
  self.held_tracks.clear()
  self.thumbs.clear()
  @signals.end_batch()
}

///|
/// A node made in `self`, after what it holds already, made by `make` as its own (in its scope).
pub fn View::box(self : View, make : (View) -> Unit) -> View {
  guard self.live() is Some(n) else { return self.tree.none() }
  let v = self.tree.made(self.at)
  n.kids.push(v.at)
  if self.at == 0 {
    self.tree.top_last()
  }
  self.box_appended(v.at)
  v.owning(fn() { make(v) })
  v
}

///|
/// What holds it, if anything does.
pub fn View::parent(self : View) -> View? {
  guard self.live() is Some(n) && n.parent >= 0 else { return None }
  Some(self.tree.handle(n.parent))
}

///|
/// The nodes it holds, in order.
pub fn View::kids(self : View) -> Array[View] {
  guard self.live() is Some(n) else { return [] }
  n.kids.map(fn(k) { self.tree.handle(k) })
}

///|
/// Whether it lives (not let go, its index not made again since).
pub fn View::alive(self : View) -> Bool {
  self.live() is Some(_)
}

///|
/// Who it is.
pub fn View::id(self : View) -> NodeId {
  { at: self.at, gen: self.gen }
}

///|
/// The moment of the change being made (an event's, a due thing's: Tree::cause_now; none, the logic's): where what it
/// tells starts, the same whatever frame takes it.
pub fn View::cause_at(self : View) -> Double {
  self.tree.cause_now()
}

///|
/// The moment the logic is at (Tree::logic_at), for what a node works out from the time.
pub fn View::logic_at(self : View) -> Double {
  self.tree.logic_at()
}

///|
/// The moment what is drawn is drawn at (Tree::drawn_at), for a look worked out from the time.
pub fn View::drawn_at(self : View) -> Double {
  self.tree.drawn_at()
}

///|
/// Where it is drawn, in the window (what holds it drawn off with it, its own offset with it), and how big (as big as
/// it and what holds it are drawn: View::scale): where a press finds it as where it is drawn.
pub fn View::rect(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  let (x, y, s) = self.tree.placed(self.at)
  (x, y, n.flex.width * s, n.flex.height * s)
}

///|
/// Where node `at` is drawn in the window and how big (its scale and its holders'), from the root down (Tree::projected):
/// a point of the window in its own terms is (x - its x) / its scale.
fn Tree::placed(self : Tree, at : Int) -> (Double, Double, Double) {
  let (x, y, _, s) = self.projected(at)
  (x, y, s)
}

///|
/// Something for a frame to do: what hosts it told as there first is. Where it was marked from in a layout pass, kept
/// (said with passes that never stop: Tree::laid_out).
#callsite(autofill(loc))
fn Tree::marked(self : Tree, loc~ : SourceLoc) -> Unit {
  if self.laid_passes > 0 && !self.due {
    self.laid_marked_at = "\{loc}, last set at \{@signals.last_set_at()}"
  }
  if !self.due {
    self.due = true
    // (the host is already being told: it will ask for a frame for everything marked by that telling too. Laying out
    // during the telling can clear `due` and mark it again; telling the host recursively would repeat that layout.)
    if !self.telling_due {
      self.telling_due = true
      while true {
        self.due_frame_taken = false
        (self.on_due)()
        // (a host that took a frame synchronously needs to hear of work left after that frame; a layout alone is not
        // a frame and does not consume the notification)
        if !self.due_frame_taken || !self.due {
          break
        }
      }
      self.telling_due = false
    }
  }
}

///|
/// Its layout to be done again: itself and every node up to the root (one marked before and not laid out since, its
/// holder's layout reused, is no sign the rest are).
fn Tree::layout_marked_at(self : Tree, at : Int) -> Unit {
  if self.layout_owner >= 0 {
    // A layout callback is building its own children before measuring them. Nothing outside that layout is dirty.
    let mut i = at
    while i >= 0 && i != self.layout_owner {
      let flex = self.nodes[i].flex
      flex.dirty = true
      // The child may already have been probed in this compute. Its previous measurements no longer describe
      // the style the owning layout has just assigned, even though it was touched in the current generation.
      flex.cache_n = 0
      flex.p_ok = false
      i = self.nodes[i].parent
    }
    return
  }
  self.layout_due = true
  // (what was laid out to be read no more where it stands)
  self.measured_gen = -1
  self.hits = self.hits + 1
  self.marked()
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    n.flex.dirty = true
    i = n.parent
  }
}

///|
/// Node `at` changed what of it is drawn, or where (from itself on up): each that holds it, or it, grown about the
/// middle of what it draws (View::scale's Drawn) to work that out again and be placed again by it.
fn Tree::drawn_stale_from(self : Tree, at : Int) -> Unit {
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    if n.look.pivot is Drawn && !n.drawn_stale {
      n.drawn_stale = true
      self.place_marked_at(i)
    }
    i = n.parent
  }
}

///|
/// Its instance to be made again.
fn Tree::look_marked_at(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.look_due {
    n.look_due = true
    self.looks_due.push(at)
    self.marked()
  }
  // (whether it draws, as it changes: the middle of what each that holds it draws, it too)
  let draws = draws_of(n)
  if n.drew != draws {
    n.drew = draws
    self.drawn_stale_from(at)
  }
}

///|
/// Its place (how far it is drawn off, how opaque) to be worked out again, what it holds with it.
fn Tree::place_marked_at(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.place_due {
    n.place_due = true
    self.places_due.push(at)
    // (where it is drawn may change: what the scene draws again of it, at this cause, Tree::take_placed)
    self.placed_pending.push({ at, gen: n.gen })
    self.hits = self.hits + 1
    self.marked()
  }
  // (where it is drawn off in what holds it, as it changes, whatever else of its place was told before: the middle of
  // what each that holds it draws, not its own)
  let off = (n.look.dx, n.look.dy, n.look.sx, n.look.sy)
  if n.drawn_off != off {
    n.drawn_off = off
    self.drawn_stale_from(n.parent)
  }
}

///|
/// The order the nodes are drawn in changed (one made, let go or moved among its siblings): drawn again.
fn Tree::order_marked(self : Tree) -> Unit {
  self.order_due = true
  self.hits = self.hits + 1
  self.marked()
}

///|
/// What a property is: what of the node it sets (as its own: a layout property, a paint property, a place property, or
/// words: layout's and paint's). Each property's own (View::width, View::ground...), not its caller's.
priv enum Phase {
  Layout
  Paint
  Place
  Both
  /// what it says it is (View::says): read out as asked, nothing laid out, placed or drawn again for it
  Said
}

///|
/// A binding's work out of `read`, followed: run now, and as what it read changes, marked stale and queued for the
/// next frame (Tree::frame runs the queue first), however often it changed meanwhile; there it is read anew and its
/// value handed to `then`. What stops it (it follows nothing, runs no more, and lets go of what it holds).
fn[T] Tree::queued(self : Tree, read : () -> T, then : (T) -> Unit) -> () -> Unit {
  // (a node's own read, of what is laid out too, as told last: wherever a write set it off, reads_own)
  let read = fn() { reads_own(read) }
  // (its one state, every way it is run read from it: queued for a frame (told as a change ended), marked as what it
  // read changed (in a change's batch too: what asks at once pulls it), live; run once it is due, by any of them, and
  // done with all of them)
  let b : Bound = { queued: false, marked: false, live: true, watch: None, run: fn() {  } }
  // (when what it read was told changed: its cause's moment, whatever frame works it out)
  let told_at = Ref(-1.0)
  let w = @signals.watch(fn() {
    if b.live && !b.queued {
      b.queued = true
      told_at.val = self.time_now()
      self.bindings_due.push(b)
      self.marked()
      // (where things stand once the change that told it is told whole, a frame drawn after or none: placed then, where
      // something asks, View::laid_before_causes)
      self.settle_after_change(told_at.val)
    }
  })
  w.on_marked(fn() {
    if b.live && !b.marked {
      b.marked = true
      self.pulls_marked.push(b)
    }
  })
  b.run = fn() {
    b.queued = false
    b.marked = false
    if !b.live {
      return
    }
    let v = w.read(read)
    let was = self.cause_at
    self.cause_at = told_at.val
    told_at.val = -1.0
    @signals.untracked(fn() { then(v) })
    self.cause_at = was
  }
  (b.run)()
  b.watch = Some(w)
  self.pulls_held += 1
  fn() {
    if !b.live { return }
    b.live = false
    b.run = fn() {  }
    b.watch = None
    self.pulls_held -= 1
    w.stop()
  }
}

///|
/// The bindings marked since (what they read changed, told or not: a change under way, in its batch, tells them as it
/// ends) worked out now, each once, where what they read did change (a computed read the same, not): what is asked at
/// once (View::laid_size, Tree::bring_to). Nothing else run: what shows, which is picked and what effects do wait for
/// the change's end; those not marked are not looked at.
fn Tree::pull(self : Tree) -> Unit {
  while self.pulls_marked.length() > 0 {
    let marked = self.pulls_marked.copy()
    self.pulls_marked.clear()
    for b in marked {
      match b.watch {
        Some(w) if b.live && b.marked => {
          self.work.pulled = self.work.pulled + 1
          if w.changed_now() {
            (b.run)()
          } else {
            b.marked = false
          }
        }
        _ => ()
      }
    }
  }
}

///|
/// How many bindings the tree holds (each property bound By, while its node lives): for a test to see what is let go.
pub fn Tree::bindings_held(self : Tree) -> Int {
  self.pulls_held
}

///|
/// A structure's binding (what shows, which is picked, which rows): `read` worked out as what it read changes, and
/// where it came out otherwise, `then` done then (the structure's change committed with the change that caused it, at
/// that change's moment: what it makes reads the state as it is then, what leaves starts leaving then), what had left
/// by that moment let go first. Layout, words and paint of what it makes wait for the frame. Run now with the target
/// it starts at. What stops it.
fn[T : Eq] Tree::structured(self : Tree, read : () -> T, then : (T) -> Unit) -> () -> Unit {
  // (a node's own, what it reads and what it does as that changes, of what is laid out too, as told last: wherever a
  // write set it off, reads_own)
  let read = fn() { reads_own(read) }
  let then = fn(v : T) { reads_own(fn() { then(v) }) }
  let live = Ref(true)
  let last : Ref[T?] = Ref(None)
  // (the watch reads anew as it is told; let go as it stops)
  let watch : Ref[@signals.Watch?] = Ref(None)
  let w = @signals.watch(fn() {
    guard live.val && watch.val is Some(w) else { return }
    // (read and done as of one moment, the change's that told it: what the read works out at the cause's moment is
    // of the same moment the change is committed at)
    self.at_cause(fn() {
      // (still bound once what was due by then is settled: one let go then reads nothing more, follows nothing again)
      guard live.val else { return false }
      let v = w.read(read)
      if last.val != Some(v) {
        last.val = Some(v)
        if live.val {
          @signals.untracked(fn() { then(v) })
        }
        true
      } else {
        false
      }
    })
  })
  watch.val = Some(w)
  let v = w.read(read)
  last.val = Some(v)
  // (one change, as each after it is: Tree::at_cause)
  self.committing += 1
  @signals.start_batch()
  @signals.untracked(fn() { then(v) })
  @signals.end_batch()
  self.committing -= 1
  self.modals_settled()
  fn() {
    live.val = false
    watch.val = None
    w.stop()
  }
}

///|
/// A structure's change `f` committed now, as of the moment of the change that caused it (the one being committed, else
/// the host's now): what had left by then let go first, `f` done with that moment as its cause's, nothing it reads
/// followed by what is reading.
fn Tree::committed(self : Tree, f : () -> Unit) -> Unit {
  self.at_cause(fn() {
    @signals.untracked(f)
    true
  })
}

///|
/// `f` done as of the moment of the change being committed (the one being committed, else the host's now): the tree
/// brought there first (what had left by then let go), that moment its cause's for all `f` reads and does; what is
/// marked taken where `f` says it changed something.
fn Tree::at_cause(self : Tree, f : () -> Bool) -> Unit {
  let at = if self.cause_at >= 0.0 {
    self.cause_at
  } else {
    self.time_now()
  }
  self.advance_logic(at)
  // What was due has finished. Advancing the drawing clock can notify bindings too: tell it with the structure's
  // change, so a child already queued by the new data cannot run before its parent has had the chance to let it go.
  @signals.start_batch()
  self.advance_clock(at)
  let was = self.cause_at
  self.cause_at = at
  self.committing += 1
  // (one change, as an event is: what it writes told once all of it is written, never what follows it running
  // between two of its writes and seeing half of it)
  let changed = f()
  @signals.end_batch()
  self.committing -= 1
  self.modals_settled()
  self.cause_at = was
  if changed {
    self.marked()
  }
  // (where things stand once the change it is of is told whole, for the next: Tree::settle_after_change)
  self.settle_after_change(at)
}

///|
/// A property of a node bound to what says it (View::bind: its one binding, one bound again let go of first), by name:
/// two that set the same thing two ways one binding (Width: View::width in points, View::width_share as a share;
/// Words: View::words, View::words_runs), any other its own, so that one bound never lets go of another's.
priv enum Prop {
  ClipDrawn
  CutAcross
  Notch
  ShadowOut
  Width
  Height
  Padding
  Margin
  Row
  Grow
  Ground
  Alpha
  Offset
  Words
  RunsSet
  RunsInk
  RunsPressed
  RunsPicked
  RunsLit
  Over
  Shift
  Presses
  TurnedOff
  Modal
  Shapes
  Tint
  Radius
  Glass
  Glyphs
  Says
  Hides
  Focusable
  TabStop
  Cursor
  Basis
  Ink
  Shadow
  MaxWidth
  MaxHeight
  WordsLook
  AllowEllipsis
  Shrink
  Gap
  Wraps
  WrapsLeast
  WrapsUp
  Shorter
  MinWidth
  LinesUp
  LiesAlong
  Scale
  DrawnAs
  OverAll
  Stacked
  MovesWindow
  KeepsHeld
  Clips
  HostedClips
  BoundsInput
  WheelThrough
  OverScrim
  Measured
  LayoutBox
  WordsCentered
  EllipsisPast
  Points
  Picture
  Drop
  Fits
  Turn
  Lines
  Fades
  Stretch
  Opens
  OpensAcross
  CutsSoftly
  DrawnOff
  GroundDrawn
  MinHeight
  Aspect
  Nowhere
  Edge
  EdgeDashed
  NativeAnchor
  Image
  ImageFor
  ImageCover
  ImageFade
  ImageIn
  Corners
  Bones
  BoneWhole
} derive(Eq, Hash)

///|
/// Property `prop` of the node (its one binding: one bound before is let go), set by `apply`: once, or as what it
/// reads changes (Tree::queued: as the frame takes it), set again only if it came out otherwise than it last did,
/// marking what its phase does again.
fn[T : Eq] View::bind(self : View, prop : Prop, live : Live[T], phase : Phase, apply : (T) -> Unit) -> Unit {
  guard self.live() is Some(n) else { return }
  let tree = self.tree
  let at = self.at
  let marked = fn() {
    match phase {
      Layout => tree.layout_marked_at(at)
      Paint => tree.look_marked_at(at)
      Place => tree.place_marked_at(at)
      Both => {
        tree.layout_marked_at(at)
        tree.look_marked_at(at)
      }
      Said => tree.marked()
    }
  }
  match n.props.get(prop) {
    Some(stop) => {
      n.props.remove(prop)
      stop()
    }
    None => ()
  }
  match live {
    Is(v) => {
      apply(v)
      marked()
    }
    By(f) => {
      let last : Ref[T?] = Ref(None)
      let gen = self.gen
    let stop = tree.queued(
      f,
      fn(v) {
        let n = tree.nodes[at]
        if !n.live || n.gen != gen {
          return
        }
        let work = tree.work
        work.bound = work.bound + 1
        if last.val == Some(v) {
          work.same = work.same + 1
          return
        }
        last.val = Some(v)
        apply(v)
        marked()
      })
      n.props[prop] = stop
    }
    Roomed(of, f) => {
      match phase {
        Layout => ()
        _ => abort("view: Roomed is for what layout reads alone; what is drawn or placed by layout is Painted")
      }
      // (by what holds it: worked out as that is laid out, before it is)
      let mut i = n.parent
      while i >= 0 && i != of.at {
        i = tree.nodes[i].parent
      }
      guard physical_equal(of.tree, tree) && i == of.at && of.alive() else {
        abort("view: Roomed by a node that does not hold it")
      }
      let last : Ref[T?] = Ref(None)
      let gen = self.gen
      // (what else it reads, followed: changed, what holds it laid out again)
      let watch = @signals.watch(fn() { tree.layout_marked_at(at) })
      let run = fn(w : Double, h : Double) {
        let n = tree.nodes[at]
        if !n.live || n.gen != gen {
          return
        }
        // (its own binding: what it reads laid out as told last, wherever its holder is laid out from, as By's: reads_own)
        let v = reads_own(fn() { watch.read(fn() { f(w, h) }) })
        if last.val != Some(v) {
          last.val = Some(v)
          apply(v)
          // (laid out otherwise in this layout: what it is found to be, and what holds it up to `of`, found again)
          let mut j = at
          while j >= 0 && j != of.at {
            let fl = tree.nodes[j].flex
            fl.dirty = true
            fl.cache_n = 0
            fl.p_ok = false
            j = tree.nodes[j].parent
          }
        }
      }
      tree.roomed_add(of.at, at, gen, run)
      tree.layout_marked_at(at)
      n.props[prop] = fn() {
        watch.stop()
        tree.roomed_drop(of.at, at, gen)
      }
    }
    Painted(f) => {
      match phase {
        Paint | Place => ()
        _ => not_painted("a property layout reads")
      }
      let last : Ref[T?] = Ref(None)
      let gen = self.gen
      // (what it reads of signals, followed: changed, its node is to be painted again, a frame asked for)
      let watch = @signals.watch(fn() { marked() })
      let run = fn() {
        let n = tree.nodes[at]
        if !n.live || n.gen != gen {
          return
        }
        let v = watch.read(fn() { f({ tree, }) })
        if last.val != Some(v) {
          last.val = Some(v)
          apply(v)
          marked()
        }
      }
      // (first worked out as the frame it is said in is painted, after its layout: Tree::painted_now; a frame owed)
      tree.painted.push((at, gen, run))
      marked()
      n.props[prop] = fn() {
        watch.stop()
        match tree.painted.search_by(fn(e) { e.0 == at && e.1 == gen }) {
          Some(i) => tree.painted.remove(i) |> ignore
          None => ()
        }
      }
    }
  }
}

///|
/// Its width (points; None: as its content and its holder make it).
pub fn View::width(self : View, w : Live[Double?]) -> View {
  self.bind(Width, w, Layout, fn(w) {
    self.tree.nodes[self.at].flex.style.set_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
    // (words as wide as said: not held to their column's width)
    self.tree.capped_applied(self.at)
  })
  self
}

///|
/// Its height (points; None: as its content and its holder make it).
pub fn View::height(self : View, h : Live[Double?]) -> View {
  self.bind(Height, h, Layout, fn(h) {
    self.tree.nodes[self.at].flex.style.set_height(match h {
      Some(h) => Pt(h)
      None => Auto
    })
  })
  self
}

///|
/// Room inside it, at its left, top, right and bottom: one property (pad and sides say it too, the last said its one
/// binding).
pub fn View::padding(self : View, p : Live[(Double, Double, Double, Double)]) -> View {
  self.bind(Padding, p, Layout, fn(p) {
    let s = self.tree.nodes[self.at].flex.style
    s.set_padding_left(Pt(p.0))
    s.set_padding_top(Pt(p.1))
    s.set_padding_right(Pt(p.2))
    s.set_padding_bottom(Pt(p.3))
  })
  self
}

///|
/// Room outside it (left, top, right, bottom), as CSS's margin: negative, it reaches past where it would stand into
/// what is round it (a small panel's last row into the panel's padding at its foot), what holds it laid out as though it
/// were that much smaller (or bigger).
pub fn View::margin(self : View, m : Live[(Double, Double, Double, Double)]) -> View {
  self.bind(Margin, m, Layout, fn(m) {
    let s = self.tree.nodes[self.at].flex.style
    s.set_margin_left(Pt(m.0))
    s.set_margin_top(Pt(m.1))
    s.set_margin_right(Pt(m.2))
    s.set_margin_bottom(Pt(m.3))
  })
  self
}

///|
/// Room inside it, the same on every side (its padding).
pub fn View::pad(self : View, p : Live[Double]) -> View {
  self.padding(
    match p {
      Is(v) => Is((v, v, v, v))
      Painted(_) => not_painted("what is said here")
      Roomed(_, _) => not_roomed()
      By(f) =>
        By(fn() {
          let v = f()
          (v, v, v, v)
        })
    },
  )
}

///|
/// Room inside it at its left and its right, none at its top and bottom (its padding: what it holds laid out between,
/// the window's sides beside the system's bars).
pub fn View::sides(self : View, lr : Live[(Double, Double)]) -> View {
  self.padding(
    match lr {
      Is(v) => Is((v.0, 0.0, v.1, 0.0))
      Painted(_) => not_painted("what is said here")
      Roomed(_, _) => not_roomed()
      By(f) =>
        By(fn() {
          let v = f()
          (v.0, 0.0, v.1, 0.0)
        })
    },
  )
}

///|
/// What it holds laid out across (true) or down.
pub fn View::row(self : View, across : Live[Bool]) -> View {
  self.bind(Row, across, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.direction = if a { Row } else { Column }
    // (what it holds cut short gives way along it only where it is a row: View::cuts)
    self.tree.cuts_under(self.at)
  })
  self
}

///|
/// How much of the room left it takes.
pub fn View::grow(self : View, g : Live[Double]) -> View {
  self.bind(Grow, g, Layout, fn(g) { self.tree.nodes[self.at].flex.style.grow = g })
  self
}

///|
/// Whether it is never narrower, in a row, than what it holds needs (the old views' `keep`: a bar's tools kept whole),
/// whatever its basis and least width say, as it changes: what is beside it gives way first; what it holds changing
/// (its words, their face, its parts, their gaps) lays it out so again. Layout's.
pub fn View::keeps_held(self : View, on : Live[Bool]) -> View {
  self.bind(KeepsHeld, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.min_held = on })
  self
}

///|
/// How wide (in a row; tall, in a column) it is before the room left is shared out (View::grow), as it changes: None as
/// what it holds is; Some(0.0) none, so that those that grow alike are alike however much each holds (the old views'
/// Fill). It says nothing of how narrow it may come to: that is its least width's (View::min_width) or, never narrower
/// than what it holds, View::keeps_held's. Layout's.
pub fn View::basis(self : View, b : Live[Double?]) -> View {
  self.bind(Basis, b, Layout, fn(b) {
    self.tree.nodes[self.at].flex.style.set_basis(
      match b {
        Some(v) => Pt(v)
        None => Auto
      },
    )
  })
  self
}

///|
/// How big it is laid out as of the logic's moment (Tree::logic_at): what was told before it laid out first (what an event
/// changed before it asks, laid out as a frame would), as of the window's size its last frame gave (0 by 0 before the
/// first). For what is said at a moment by how big a thing is then (how long a slide across it takes), never followed.
pub fn View::laid_size(self : View) -> (Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0) }
  // (laid out as of the logic's moment, what the change under way set so far counted, nothing of the logic run; read,
  // not placed by: each node where it stood till the change is placed, Tree::measured_now)
  self.tree.measured_now()
  (n.flex.width, n.flex.height)
}

///|
/// The window's size, as its frames give it (0 by 0 before the first), followed: what is made by it (which frame its
/// width calls for) made again as it changes.
pub fn View::window(self : View) -> (Double, Double) {
  self.tree.room.get()
}

///|
/// Laid out over what holds it (true), filling all of its room whatever else it holds, or in its turn among them: what
/// lies one over another (a stack's pages, what floats over them) said so, drawn in the order they are held.
pub fn View::over(self : View, on : Live[Bool]) -> View {
  self.bind(Over, on, Layout, fn(on) {
    let s = self.tree.nodes[self.at].flex.style
    let inset : @flex.Dim = if on { Pt(0.0) } else { Auto }
    s.position = if on { Absolute } else { Relative }
    s.set_inset_left(inset)
    s.set_inset_top(inset)
    s.set_inset_right(inset)
    s.set_inset_bottom(inset)
  })
  self
}

///|
/// Whether what it holds is cut to it, its corners round as its own (View::radius), as an old view's box that clips is
/// (a progress bar's track cutting its part at its round ends), as it changes: paint's. How it is drawn only: where a
/// finger or the pointer is taken is as it was (what is past it still takes them), unlike an old view's clip.
pub fn View::clips(self : View, on : Live[Bool]) -> View {
  self.bind(Clips, on, Paint, fn(on) { self.tree.nodes[self.at].look.clips = on })
  self
}

///|
/// Where across it cuts what it holds, where it clips (View::clips), as it changes (from and to in its own terms, met by
/// its own cut; none left between them: nothing of what it holds drawn; None: all of it), as an old view's
/// Ctx::cut_across_by: paint's. Its cut is another, so what it holds is drawn again, all of it.
pub fn View::cut_across(self : View, across : Live[(Double, Double)?]) -> View {
  self.bind(CutAcross, across, Paint, fn(a) { self.tree.nodes[self.at].look.cut_across = a })
  self
}

///|
/// The rect it cuts what it holds to, as it changes (x, y, w, h in its own terms, anywhere of it or beyond it; None: none
/// of its own), whether or not it clips to itself (View::clips: both, where it does): what shows of a thing on its way
/// cut as each frame is painted (a picture flying out of its thumbnail, cut where the list it was in leaves it seen),
/// nothing laid out for it; its corners round as its own are (View::radius, View::corners); what it cuts away pressed
/// nowhere. Paint's: what it holds drawn again, all of it.
pub fn View::clip_drawn(self : View, rect : Live[(Double, Double, Double, Double)?]) -> View {
  self.bind(ClipDrawn, rect, Paint, fn(r) { self.tree.nodes[self.at].look.clip_drawn = r })
  self
}

///|
/// Whether hosted content needs the node's clip, independently of a clip the node's caller sets.
pub fn View::hosted_clips(self : View, on : Live[Bool]) -> View {
  if self.live() is Some(n) && !n.hosted {
    abort("hosted_clips of a node hosting nothing")
  }
  self.bind(HostedClips, on, Paint, fn(on) { self.tree.nodes[self.at].hosted_clips = on })
  self
}

///|
/// Whether a wheel turned over it (down or across, a mouse's or a trackpad's) is what is drawn under it's, as it
/// changes: its presses, drags and menus still its own, and the pointer over it still over it (View::pointed), not over
/// what it covers. Not found by a wheel (Tree::wheel_at), what it holds found as ever. For a cover that takes a tap over
/// what it covers but leaves its scrolling to it: a panel not in use on the tape (still.fail's tape_cover), a tap
/// bringing it over, the wheel scrolling the page under it where it shows, as it would were nothing over it. Which of a
/// press held long goes through is the gesture's `through` (through.mbt).
pub fn View::wheel_through(self : View, on : Live[Bool]) -> View {
  self.bind(WheelThrough, on, Paint, fn(on) { self.tree.nodes[self.at].wheel_through = on })
  self
}

///|
/// Whether what it holds is found by a finger or the pointer within it alone, as it changes (a column that scrolls in
/// it: what is scrolled out of it takes nothing there, as an old view's clip; an old view hosted in what it holds found
/// so too, what it takes asked only there: Tree::input_bounds). Where they are found only: how it is drawn is View::clips'.
pub fn View::bounds_input(self : View, on : Live[Bool]) -> View {
  self.bind(BoundsInput, on, Paint, fn(on) {
    let n = self.tree.nodes[self.at]
    if n.bounds_input != on {
      n.bounds_input = on
      self.tree.hits = self.tree.hits + 1
    }
  })
  self
}

///|
/// Drawn, with what it holds, over the scrim of the modal layer the old frame has up while `on` says so (a row held for
/// its menu, lifted toward the finger: an old view's Stratum OverScrim), under what that layer holds; where no scrim is
/// up, in its place. Cut as where it is; found by a press as ever (the scrim's layer takes what lands on it). Paint's.
pub fn View::over_scrim(self : View, on : Live[Bool]) -> View {
  self.bind(OverScrim, on, Paint, fn(on) { self.tree.nodes[self.at].over_scrim = on })
  self
}

///|
/// Whether node `id` is drawn over the old frame's scrim (View::over_scrim).
pub fn Tree::over_scrim_of(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].over_scrim
}

///|
/// Whether it takes over a hold that began on what it holds (a finger or the pointer down on one of them that takes a
/// press, on an old view hosted in it, on nothing that takes one): asked as the hold moves, given how far from where it
/// went down (dx, dy, in the window's points), the innermost that holds what it went down on first (Tree::claimer_of);
/// taken over, what had it is called off and the rest of it is this one's (View::on_drag: down where it is then).
/// One that does takes none at its own down. `scrolls`: what it takes them over for is scrolling what it holds (what
/// hosts the tree lets go of the keyboard for that, as a finger scrolling a list does: Tree::claims_scroll). `from`:
/// whether it may take over a hold that went down there (in its own terms, as it was drawn then): one that went down
/// elsewhere it is not asked of (a stack's page taking a swipe back from its edge alone); none, from anywhere.
pub fn View::claims(
  self : View,
  f : (Double, Double) -> Bool,
  scrolls? : Bool = false,
  from? : (Double, Double) -> Bool,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.claims = Some(f)
  n.claims_from = from
  n.claims_scroll = scrolls
  n.claims_said = n.claims_said + 1
  self.tree.hits = self.tree.hits + 1
  self
}

///|
/// What may take over a hold that goes down at (x, y) now (View::claims), as a press finds what it is on (the topmost
/// drawn there that takes a press, is held, hosts an old view or takes over holds: Tree::target_at's): it and what holds
/// it that take over holds, the innermost first, each as it is said now. `from`: that one instead of what is found
/// there (an old view a press goes on to under an empty one over it); `there`: whether one hosting an old view has
/// something of its own there (one with nothing there passed, as though it were not there: Tree::wheel_at's). Asked
/// again as the hold moves (Tree::claimer_of).
/// Whether the hold on node `id` may be taken over by what holds it as it moves (a gesture of its waiting on a tap, a
/// hold or its own slop: View::gesture), as a press of a node's may (Tree::claimer_of); one of its own (its drag begun,
/// a hold come; a node's raw on_drag: a slider, a picture zoomed, words picked), not.
pub fn Tree::yields(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].yields
}

///|
pub fn Tree::claimers_at(
  self : Tree,
  x : Double,
  y : Double,
  from? : NodeId,
  there? : (NodeId) -> Bool = fn(_) { true },
) -> Array[(NodeId, Int)] {
  let out = []
  let start = match from {
    Some(id) => Some(id)
    None => {
      let found : Ref[NodeId?] = Ref(None)
      let at = self.logic_at()
      self.walk_taken(x, y, fn(c, cx, cy, _, s) {
        if self.finger_on(c, cx, cy, s, x, y, at, tracked=false) {
          let n = self.nodes[c.id.at]
          if n.on_drag is Some(_) ||
            n.on_press is Some(_) ||
            n.top_row ||
            n.claims is Some(_) ||
            (n.hosted && @signals.untracked(fn() { there(c.id) })) {
            found.val = Some(c.id)
          }
        }
      })
      found.val
    }
  }
  guard start is Some(id) && self.alive_id(id) else { return out }
  let mut i = id.at
  while i >= 0 {
    let n = self.nodes[i]
    // (one taking over only holds that went down where it says: asked where this one went down, in its terms)
    let there = match n.claims_from {
      Some(f) => {
        let (nx, ny, _, s) = self.projected(i)
        @signals.untracked(fn() { f((x - nx) / dmax(s, 1.0e-6), (y - ny) / dmax(s, 1.0e-6)) })
      }
      None => true
    }
    if n.claims is Some(_) && there {
      out.push(({ at: i, gen: n.gen }, n.claims_said))
    }
    i = n.parent
  }
  out
}

///|
/// Whether node `id` takes over holds to scroll what it holds (View::claims' `scrolls`).
pub fn Tree::claims_scroll(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].claims_scroll
}

///|
/// What of `chain` (Tree::claimers_at, as the hold went down) takes it over now it has moved (dx, dy) in the window's
/// points since: the first, innermost first, still as it was then (living, the same node, said to take over holds as it
/// was then), taking input, that says it does; none, none.
pub fn Tree::claimer_of(self : Tree, chain : Array[(NodeId, Int)], dx : Double, dy : Double) -> NodeId? {
  for e in chain {
    let (id, said) = e
    guard self.nodes.length() > 0 && self.nodes[0].live else { return None }
    guard self.alive_id(id) && !self.pressless_at(id.at) else { continue }
    let n = self.nodes[id.at]
    match n.claims {
      Some(f) if n.claims_said == said && @signals.untracked(fn() { f(dx, dy) }) => return Some(id)
      _ => ()
    }
  }
  None
}

///|
/// It, and what it holds, drawn clear of how `by` (what holds it) draws what it holds: fading it out towards its edges
/// (View::fades, View::cuts_softly), stretching it (View::stretches); and of that alone: what lies over what is so drawn
/// and is no part of it (a column's bar over what it holds, faded at its ends, stretched past them), drawn as ever by
/// what holds both. Paint's.
pub fn View::drawn_clear_of(self : View, by : View) -> View {
  guard self.live() is Some(n) else { return self }
  n.drawn_clear = Some(by.id())
  self.tree.marked()
  self
}

///|
/// Whether node `id` is drawn clear of how node `by` draws what it holds (View::drawn_clear_of: it, or what holds it
/// under `by`, said clear of `by`'s).
pub fn Tree::drawn_clear_of(self : Tree, id : NodeId, by : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let mut i = id.at
  while i >= 0 && i != by.at {
    if self.nodes[i].drawn_clear == Some(by) {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// Where in the window what node `id` holds is found by a finger or the pointer, as what holds it bounds it
/// (View::bounds_input): (x0, y0, x1, y1), the window where nothing does (or it is gone).
pub fn Tree::input_bounds(self : Tree, id : NodeId) -> (Double, Double, Double, Double) {
  let mut b = (-1.0e9, -1.0e9, 1.0e9, 1.0e9)
  guard self.alive_id(id) else { return b }
  let mut i = self.nodes[id.at].parent
  while i >= 0 {
    let n = self.nodes[i]
    if n.bounds_input {
      let (x, y, sc) = self.placed(i)
      let (x1, y1) = (x + n.flex.width * sc, y + n.flex.height * sc)
      b = (dmax(b.0, x), dmax(b.1, y), dmin(b.2, x1), dmin(b.3, y1))
    }
    i = n.parent
  }
  b
}

///|
/// Whether its words' lines each stand in the middle of its width (as wide as it is as it is drawn: a line wrapped,
/// each part of it), as an old view's centred words do (Ctx::text's `center`): how they are drawn only, measured and
/// wrapped as ever, a change of it drawn again, nothing laid out again.
pub fn View::words_centered(self : View, on : Live[Bool]) -> View {
  self.bind(WordsCentered, on, Paint, fn(on) {
    self.tree.nodes[self.at].look.words_center = on
    self.words_told()
  })
  self
}

///|
/// Whether its words, on one line cut short where even their ellipsis has not the room in its box, have that ellipsis
/// drawn past its box (true), as an old view's words cut short (`w=Cut`) are, or cut to its box (false, by default: no
/// glyph of them past it, the room beside it kept). What holds it that clips cuts it either way. How they are drawn
/// only, their words and runs alike: measured, laid out, found by a press and read out as ever, a change of it drawn
/// again, nothing laid out again; not View::clips.
pub fn View::ellipsis_past(self : View, on : Live[Bool]) -> View {
  self.bind(EllipsisPast, on, Paint, fn(on) { self.tree.nodes[self.at].look.ellipsis_past = on })
  self
}

///|
/// The picture it draws over its ground (None: none), after its shapes, as wide as it is laid out (its height for that
/// width given it as its own: View::height): its curves cut fine enough for the pixels the window is
/// drawn at (its screen's, at the zoom it is drawn at), cut again as those or its width change, kept while they do not.
/// In its tint where it has one (View::tint), each of its paths keeping its own opacity; a tint changed draws it again
/// in it, its curves not cut again. Paint's.
pub fn View::picture(self : View, picture : Live[@pixels.Vector?]) -> View {
  self.bind(Picture, picture, Paint, fn(p) { self.tree.nodes[self.at].look.picture = p })
  self
}

///|
/// Its ground (0: none): paint's.
pub fn View::ground(self : View, ink : Live[Int64]) -> View {
  self.bind(Ground, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ground = k })
  self
}

///|
/// Where the host puts a control of its own named `name` ("": none), as it changes: wherever this node is drawn in a
/// frame, as big and as cut as it is drawn there (what holds it moved, grown, cut), handed the host as the frame ends
/// (@ui.native_anchors); where it is not drawn (cut out of sight, laid out nowhere, its layer not drawn), not handed,
/// and the host hides its control. Drawn as nothing of its own, and no change of where it is drawn draws anything again.
/// Paint's.
pub fn View::native_anchor(self : View, name : Live[String]) -> View {
  self.bind(NativeAnchor, name, Paint, fn(a) { self.tree.nodes[self.at].look.native_anchor = a })
  self
}

///|
/// The shapes it draws over its ground, in its own terms from its top left (@paint.Shape: outlines filled and stroked):
/// paint's. What they come to as they are drawn is worked out once for the shapes said (their outlines), whatever colour
/// they are drawn in (View::tint).
pub fn View::shapes(self : View, shapes : Live[Array[@paint.Shape]]) -> View {
  self.bind(Shapes, shapes, Paint, fn(s) { self.tree.nodes[self.at].look.shapes = s })
  self
}

///|
/// The one colour its shapes are drawn in (0: each its own): paint's; a change of it draws them again in it, nothing of
/// their outlines worked out again.
pub fn View::tint(self : View, ink : Live[Int64]) -> View {
  self.bind(Tint, ink, Paint, fn(k) { self.tree.nodes[self.at].look.tint = k })
  self
}


///|
/// How round its corners are (its ground's and its glass's; a linked corner's as worked out where it is said): paint's.
pub fn View::radius(self : View, r : Live[Double]) -> View {
  self.bind(Radius, r, Paint, fn(r) { self.tree.nodes[self.at].look.radius = r })
  self
}

///|
/// Its corners each (top left, then round it; None: all as its radius, View::radius), as an old view's box's radius
/// may be four (@ui.Radius::Corners): its ground's, its glass's, its edge's and its cut's (View::clips): paint's.
pub fn View::corners(self : View, corners : Live[(Double, Double, Double, Double)?]) -> View {
  self.bind(Corners, corners, Paint, fn(k) { self.tree.nodes[self.at].look.corners = k })
  self
}

///|
/// The edge drawn round its ground, inside it (how wide, its colour; 0 wide: none), as an old view's box's border is
/// drawn with its ground (one rect, filled and edged), its corners its ground's: paint's.
pub fn View::edge(self : View, e : Live[(Double, Int64)]) -> View {
  self.bind(Edge, e, Paint, fn(e) { self.tree.nodes[self.at].look.edge = e })
  self
}

///|
/// The notch cut into its top, as it changes: a circle about the middle of its top, its middle `y` below the edge
/// (above it when negative), of radius `r`, met by the edge through fillets of `f` (a radius of 0: none); its ground,
/// its glass and its edge cut alike, as an old view's box's (Ctx::box `notch_y`, `notch_r`, `notch_fillet`): paint's.
pub fn View::notch(self : View, notch : Live[(Double, Double, Double)]) -> View {
  self.bind(Notch, notch, Paint, fn(n) { self.tree.nodes[self.at].look.notch = n })
  self
}

///|
/// Whether its edge is dashed, as an old view's dashed border. Its width, colour and corner stay the edge's;
/// painting only, no measured geometry read back by the page.
pub fn View::edge_dashed(self : View, on : Live[Bool]) -> View {
  self.bind(EdgeDashed, on, Paint, fn(on) { self.tree.nodes[self.at].look.edge_dashed = on })
  self
}

///|
/// The picture it shows over its ground (its source as what hosts the tree keeps pictures by, what stands in for it
/// till it is decoded at the size it is drawn ("" none), the most pixels it is asked at; None: none), all of it filled,
/// its corners its ground's: drawn by what hosts the tree as the frame composes it where it is drawn and as big, each
/// frame, its decode the one for that size, asked for and followed as an old view's is (ui's draw_image: a decode said
/// done draws the frame again), which of the two decided then: paint's.
pub fn View::image(self : View, image : Live[(String, String, Int)?]) -> View {
  self.bind(Image, image, Paint, fn(i) { self.tree.nodes[self.at].look.image = i })
  self
}

///|
/// Its picture (View::image) covering it as it changes, its middle shown and what is past it cut where it is not as wide
/// for as tall (an old view's FitCover: a face, a mark put up); else, as said none, filling it; paint's.
pub fn View::image_covers(self : View, on : Live[Bool]) -> View {
  self.bind(ImageCover, on, Paint, fn(on) { self.tree.nodes[self.at].look.image_cover = on })
  self
}

///|
/// Its picture (View::image) fading in over image_fade_ms as it is decoded (an old view's picture's way by default:
/// Ctx::image's `fade`), as it changes; else, as said none, there at once once it is; paint's.
pub fn View::image_fades(self : View, on : Live[Bool]) -> View {
  self.bind(ImageFade, on, Paint, fn(on) { self.tree.nodes[self.at].look.image_fade = on })
  self
}

///|
/// The room its picture is judged ready for (View::image): its whole picture shown, not what stands in for it, once it is
/// decoded for that room ((0, 0): for where it is drawn), as a picture on its way somewhere (a flight) is judged by
/// where it goes, its decode for that room asked for as it sets out; paint's.
pub fn View::image_for(self : View, room : Live[(Double, Double)]) -> View {
  self.bind(ImageFor, room, Paint, fn(r) { self.tree.nodes[self.at].look.image_for = r })
  self
}

///|
/// Where in it its picture lies (View::image: x, y, w, h, in its own terms) and the colour filling the rest of it, as
/// changes: its picture and that matte drawn as one instance (its edge cut once, its corners its own), the matte alone
/// over its box till the picture is decoded, as an old view's picture at a rect of its own in a matte (Ctx::picture's
/// `matte`); None, the picture filling it. Paint's.
pub fn View::image_in(self : View, at : Live[((Double, Double, Double, Double), Int64)?]) -> View {
  self.bind(ImageIn, at, Paint, fn(i) { self.tree.nodes[self.at].look.image_in = i })
  self
}

///|
/// The glass it is drawn as, under its ground and what it draws (@paint.Glass: frosted or liquid; None: none): paint's.
/// What it frosts is what the frame drew under it, wherever it is composed (its capture told as the frame is).
pub fn View::glass(self : View, g : Live[@paint.Glass?]) -> View {
  self.bind(Glass, g, Paint, fn(g) { self.tree.nodes[self.at].look.glass = g })
  self
}

///|
/// How opaque it is drawn, what it holds with it: its place's.
pub fn View::alpha(self : View, a : Live[Double]) -> View {
  self.bind(Alpha, a, Place, fn(a) { self.tree.nodes[self.at].look.alpha = a })
  self
}

///|
/// How far it is drawn off where it is laid out, what it holds with it: its place's (a move on the compositor: never
/// laid out again).
pub fn View::offset(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(Offset, d, Place, fn(d) {
    let n = self.tree.nodes[self.at]
    n.look.dx = d.0
    n.look.dy = d.1
  })
  self
}

///|
/// How far it is drawn off where it is laid out in its own widths and heights, what it holds with it: its place's, as
/// big as it is laid out in the frame drawing it (a page slid off by its width moves with its room as that changes).
pub fn View::shift(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(Shift, d, Place, fn(d) {
    let n = self.tree.nodes[self.at]
    n.look.sx = d.0
    n.look.sy = d.1
  })
  self
}

///|
/// The lines it draws over its shapes (@paint.Line: round-capped strokes through points from its top left, each in its
/// own colour, as far along as it says), as an old view's box draws them (Ctx::lines): paint's.
pub fn View::lines(self : View, lines : Live[Array[@paint.Line]]) -> View {
  self.bind(Lines, lines, Paint, fn(l) { self.tree.nodes[self.at].look.lines = l })
  self
}

///|
/// How far what it draws itself is turned (radians), as it changes: about its middle, or where `drawn` about the middle
/// of what it draws (the box round its pieces as they are made, worked out as they are, not as it turns: a ring of
/// line pieces turned as an old view's cycle turns it, Ctx::cycle_look). Where it is drawn, not what it is (nothing of
/// it made again), nor where it takes a press, nor what it holds (a spinner's ring turning by the clock, View::cycle).
/// Place's.
pub fn View::turn(self : View, r : Live[Double], drawn? : Bool = false) -> View {
  self.bind(Turn, r, Place, fn(r) {
    let n = self.tree.nodes[self.at]
    n.look.turn = r
    n.look.turn_drawn = drawn
  })
  self
}

///|
/// How far before its edges what it holds fades out towards them, each pixel by where it is (its start, top, end and
/// foot; 0: up to it whole), as it changes: not its own drawing, what it holds where it goes on past what shows of it
/// (a room opening on what comes, cut softly at both ends: as an old view's Ctx::fade_to). Where it is drawn, nothing
/// of it made again. Place's.
pub fn View::fades(self : View, f : Live[(Double, Double, Double, Double)]) -> View {
  self.bind(Fades, f, Place, fn(f) { self.tree.nodes[self.at].look.fades = f })
  self
}

///|
/// What it holds drawn stretched as Android's list is at an end as that changes (EdgeEffect's intensity `ov`, from its
/// top positive, from its foot negative; 0 none: HWUI's StretchEffect, each point of it where @view.stretch_map puts
/// it, its clips and fades inside it with it), as what draws it says; placement's (a scrolling page's list's:
/// Scroll::list).
pub fn View::stretches(self : View, ov : Live[Double]) -> View {
  self.bind(Stretch, ov, Place, fn(ov) { self.tree.nodes[self.at].look.stretch = ov })
  self
}

///|
/// How node `id` draws what it holds stretched (View::stretches; 0 for one let go).
pub fn Tree::stretch_of(self : Tree, id : NodeId) -> Double {
  if self.alive_id(id) {
    self.nodes[id.at].look.stretch
  } else {
    0.0
  }
}

///|
/// How far before its edges what node `id` holds fades out towards them (View::fades; none for one let go).
pub fn Tree::fades_of(self : Tree, id : NodeId) -> (Double, Double, Double, Double) {
  if self.alive_id(id) {
    self.nodes[id.at].look.fades
  } else {
    (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// Where node `at` is drawn bigger or smaller about, laid out `w` by `h` (View::scale's pivot): the middle of what it
/// and what it holds draw where it says `Drawn`, as laid out now.
fn Tree::pivot_of(self : Tree, at : Int, w : Double, h : Double) -> (Double, Double) {
  let n = self.nodes[at]
  guard n.look.pivot is Drawn else { return n.pivot_at(w, h) }
  if n.drawn_stale {
    n.drawn_box = self.drawn_box_of(at)
    n.drawn_stale = false
  }
  let (x0, y0, x1, y1) = n.drawn_box
  if x1 < x0 {
    (w / 2.0, h / 2.0)
  } else {
    ((x0 + x1) / 2.0, (y0 + y1) / 2.0)
  }
}

///|
/// Whether node `n` draws something of its own: a ground, words, shapes, lines, a picture, or an old view it hosts.
fn draws_of(n : Node) -> Bool {
  let l = n.look
  // (a ground of no opacity draws nothing: ui's paint of it, an old view's box's grounded)
  (l.ground & 0xFFL) != 0L ||
  (l.edge.0 > 0.0 && (l.edge.1 & 0xFFL) != 0L) ||
  l.image is Some(_) ||
  l.words != "" ||
  !l.runs.is_empty() ||
  !l.shapes.is_empty() ||
  !l.lines.is_empty() ||
  l.picture is Some(_) ||
  n.hosted
}

///|
/// The box round what node `at` and what it holds draw, where it is its own: the boxes of those with a ground or an
/// edge, words, shapes, lines, a picture or an old view of their own, each where it is laid out and drawn off
/// (View::offset, View::shift); none (its left past its right) where nothing does.
fn Tree::drawn_box_of(self : Tree, at : Int) -> (Double, Double, Double, Double) {
  self.work.drawn_boxes = self.work.drawn_boxes + 1
  let box = [1.0e30, 1.0e30, -1.0e30, -1.0e30]
  fn take(i : Int, ox : Double, oy : Double) -> Unit {
    let m = self.nodes[i]
    if !m.live {
      return
    }
    let draws = draws_of(m)
    m.drew = draws
    m.drawn_off = (m.look.dx, m.look.dy, m.look.sx, m.look.sy)
    if draws && m.flex.width > 0.0 && m.flex.height > 0.0 {
      box[0] = if ox < box[0] { ox } else { box[0] }
      box[1] = if oy < box[1] { oy } else { box[1] }
      box[2] = if ox + m.flex.width > box[2] { ox + m.flex.width } else { box[2] }
      box[3] = if oy + m.flex.height > box[3] { oy + m.flex.height } else { box[3] }
    }
    for k in m.kids {
      let c = self.nodes[k]
      // (a slot lays out nothing of its own: what it holds is placed in this one, as Tree::place places it)
      if c.slot {
        take(k, ox, oy)
      } else {
        take(
          k,
          ox + c.flex.left + c.look.dx + c.look.sx * c.flex.width,
          oy + c.flex.top + c.look.dy + c.look.sy * c.flex.height,
        )
      }
    }
  }
  take(at, 0.0, 0.0)
  (box[0], box[1], box[2], box[3])
}

///|
/// A room opening on what it holds (`share` of it open, 0 … 1; None: as tall as what it holds, or as said), as it
/// changes: as tall as that share of what it holds comes to at its width, what it holds laid out whole in its middle
/// (past it at both ends as it is not all open), its height and what it holds's of the same layout, whatever that
/// comes to as it opens (its words or its width changed meanwhile). Layout's.
pub fn View::opens(self : View, share : Live[Double?]) -> View {
  self.bind(Opens, share, Layout, fn(k) {
    let st = self.tree.nodes[self.at].flex.style
    match k {
      Some(k) => {
        st.content_share = k
        st.justify = Center
      }
      None => {
        st.content_share = 0.0 / 0.0
        st.justify = FlexStart
      }
    }
  })
  self
}

///|
/// A room opening across what it holds (`share` of it open, 0 … 1; None: as wide as what it holds, or as said), as it
/// changes: as wide as that share of what it holds comes to, what it holds laid out at its whole width from its start
/// (past its end as it is not all open: cut where it clips, View::clips), in the same layout, whatever that comes to as
/// it opens (an activity's words and its time folding into a row's end). Layout's.
pub fn View::opens_across(self : View, share : Live[Double?]) -> View {
  self.bind(OpensAcross, share, Layout, fn(k) {
    self.tree.nodes[self.at].flex.style.content_share_across = match k {
      Some(k) => k
      None => 0.0 / 0.0
    }
  })
  self
}

///|
/// Whether what it holds past its edges fades out towards them, each pixel by where it is (View::fades), as far before
/// each as it reaches past it and no further than half of what shows (an old view's cut_soft), worked out where it is
/// laid out as it is composed: a room opening on what it holds cut softly at both ends. Place's.
pub fn View::cuts_softly(self : View, on : Live[Bool]) -> View {
  self.bind(CutsSoftly, on, Place, fn(on) { self.tree.nodes[self.at].look.cut_soft = on })
  self
}

///|
/// What node `id` holds past its top and its foot as it is laid out, and how tall it is (where it cuts softly:
/// View::cuts_softly; None where it does not, or is let go).
pub fn Tree::cut_soft_of(self : Tree, id : NodeId) -> (Double, Double, Double)? {
  guard self.alive_id(id) && self.nodes[id.at].look.cut_soft else { return None }
  let h = self.nodes[id.at].flex.height
  // (the top and foot of what it holds, as laid out in it)
  let (top, foot) = (Ref(0.0), Ref(h))
  fn reach(i : Int, oy : Double) -> Unit {
    for k in self.nodes[i].kids {
      let c = self.nodes[k]
      if !c.live {
        continue
      }
      if c.slot {
        reach(k, oy)
      } else {
        let y = oy + c.flex.top
        if y < top.val {
          top.val = y
        }
        if y + c.flex.height > foot.val {
          foot.val = y + c.flex.height
        }
      }
    }
  }
  reach(id.at, 0.0)
  Some((-top.val, foot.val - h, h))
}

///|
/// How far it, and what it holds with it, is drawn off where it is laid out (points), as it changes: where it is drawn
/// only, pressed and found where it is laid out (a thing on its way from where its cause found it to where it is laid
/// out now: @motion's moves_together). Place's: nothing of it laid out or made again.
pub fn View::drawn_off(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(DrawnOff, d, Place, fn(d) { self.tree.nodes[self.at].look.drawn_off = d })
  self
}

///|
/// How far its own ground is drawn off where it is laid out and how much wider and taller (points; from its top left),
/// as it changes: all of its ground (its shadow, its glass, its fill, its edge, as round as said), as a rect going on
/// its own; not what it holds, which is where its layout puts it (each said to go itself); pressed where it is laid
/// out (a thing changing shape for its cause: @motion's moves_together). Place's: nothing of it made again.
pub fn View::ground_drawn(self : View, d : Live[(Double, Double, Double, Double)]) -> View {
  self.bind(GroundDrawn, d, Place, fn(d) { self.tree.nodes[self.at].look.ground_drawn = d })
  self
}

///|
/// How far node `id` draws its own ground off where it is laid out, and how much bigger (View::ground_drawn; none for
/// one let go).
pub fn Tree::ground_drawn_of(self : Tree, id : NodeId) -> (Double, Double, Double, Double) {
  if self.alive_id(id) {
    self.nodes[id.at].look.ground_drawn
  } else {
    (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// What hosts the tree draws it at `g` device pixels a point (0: none said): what is drawn off where it is laid out is
/// drawn off by whole pixels (View::drawn_off).
pub fn Tree::set_pixel_grid(self : Tree, g : Double) -> Unit {
  self.pixel_grid = g
}

///|
/// The thumbs of its columns' bars living now (View::scroll_bar's), for a test: where each takes the pointer is
/// Tree::input_bounds'.
pub fn Tree::thumbs_now(self : Tree) -> Array[NodeId] {
  self.thumbs.values().filter(fn(id) { self.is_thumb(id) }).collect()
}

///|
/// Whether node `id` is the thumb of one of its columns' bars (View::scroll_bar's), living.
pub fn Tree::is_thumb(self : Tree, id : NodeId) -> Bool {
  self.thumbs.get(id.at) == Some(id) && self.nodes[id.at].live
}

///|
/// How many device pixels a point its host sets a page's list's rows on (0: anywhere: a Tester's, unless it says
/// otherwise; ui's Ctx::rows_on_grid), said as each frame begins, before anything of it is laid out: each such list's
/// rows (View::scrolls with Scroll::list, up and down) laid out as tall as whole pixels (@flex.Style's rows_grid: what
/// is laid out, read and scrolled by all that reads it), and moved alike so the first one's top is on one (rows_placed),
/// as an old view's list's are (ui's Ctx::row_slot, Ctx::rows_on_pixels). Changed, each such list laid out and placed
/// again, and what reads how tall its rows are (rows_slot) told.
pub fn Tree::set_rows_grid(self : Tree, g : Double) -> Unit {
  if self.rows_grid == g {
    return
  }
  self.rows_grid = g
  for at in self.rows_lists {
    if self.nodes[at].live && self.nodes[at].list_rows {
      self.nodes[at].flex.style.rows_grid = g
      self.layout_marked_at(at)
      self.place_marked_at(at)
    }
  }
  self.rows_grid_said.set(g)
}

///|
/// How tall a row `h` laid out as tall is laid out in a page's list (Tree::set_rows_grid): as tall as whole pixels where
/// its host sets its rows on them, else as it is; followed, told as that changes.
pub fn Tree::rows_slot(self : Tree, h : Double) -> Double {
  let g = self.rows_grid_said.get()
  if g > 0.0 {
    (h * g - 0.000001).ceil() / g
  } else {
    h
  }
}

///|
/// Node `at` a page's list's rows' holder (Tree::set_rows_grid), its rows laid out on the grid there is; those let go
/// since no more counted.
fn Tree::rows_list(self : Tree, at : Int) -> Unit {
  let keep = self.rows_lists.filter(fn(i) { i != at && self.nodes[i].live && self.nodes[i].list_rows })
  self.rows_lists.clear()
  self.rows_lists.append(keep)
  self.rows_lists.push(at)
  self.nodes[at].list_rows = true
  self.nodes[at].flex.style.rows_grid = self.rows_grid
  self.layout_marked_at(at)
}

///|
/// The first row of the list node `at` holds: what it holds first, through any slot, not left out of its row (-1: none).
fn Tree::first_row(self : Tree, at : Int) -> Int {
  for k in self.nodes[at].kids {
    let m = self.nodes[k]
    if m.slot {
      let r = self.first_row(k)
      if r >= 0 {
        return r
      }
    } else if !m.flex.left_out() {
      return k
    }
  }
  -1
}

///|
/// Where node `at` is laid out down the window, each that holds it where it is laid out, those a column scrolls moved
/// as far as it scrolls them, nothing drawn off (an old view's place in its layout, an old list's scrolled).
fn Tree::rows_laid_y(self : Tree, at : Int) -> Double {
  let mut y = 0.0
  let mut i = at
  while i >= 0 {
    let m = self.nodes[i]
    if !m.slot {
      y = y + m.flex.top
      if m.parent >= 0 && self.nodes[m.parent].scroll_held == i {
        y = y + m.look.dy
      }
    }
    i = m.parent
  }
  y
}

///|
/// Node `at` placed `y` down in what holds it, as a page's list's rows are (Tree::set_rows_grid): such a list moved less
/// than a pixel so its first row's top is on the grid, that row where it is laid out, the list where it is scrolled to
/// (ui's Ctx::rows_on_pixels); else where it is.
fn Tree::rows_placed(self : Tree, at : Int, y : Double) -> Double {
  let n = self.nodes[at]
  let g = self.rows_grid
  guard n.list_rows && g > 0.0 else { return y }
  let first = self.first_row(at)
  guard first >= 0 else { return y }
  let top = self.rows_laid_y(n.parent) + y + self.nodes[first].flex.top
  y + (top * g).round() / g - top
}


///|
/// Each change told the tree from now on (a signal set outside or a batch of them, an event, a moment come on the
/// timeline) laid out and placed once it is told whole (a frame drawn after or none): where things stand as the next
/// comes is where that one left them (View::placed_window_now), for what moves from there for its cause. As long as
/// this node lives.
pub fn View::laid_before_causes(self : View) -> Unit {
  guard self.alive() else { return }
  self.tree.before_causes = self.tree.before_causes + 1
  self.owns(fn() { self.tree.before_causes = self.tree.before_causes - 1 }) |> ignore
}

///|
/// Where it was last placed in the window, and how big (each that holds it where it was placed too: its layout's place
/// and its offset), drawn off and grown or shrunk by nothing: as it stood before a change told now is laid out, in the
/// terms of laid_window_now (for what moves from there for that change's cause, said once at that moment).
pub fn View::placed_window_now(self : View) -> (Double, Double, Double, Double) {
  layout_read("placed_window_now")
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  let mut x = 0.0
  let mut y = 0.0
  let mut i = self.at
  while i >= 0 {
    let m = self.tree.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
    }
    i = m.parent
  }
  (x, y, n.lw, n.lh)
}

///|
/// What was told worked out and laid out as of the logic's moment, nothing placed by it (each node where it was placed
/// till a frame or a change's end places things, by this same layout): where a change under way lays things out, read
/// by what goes from where they stood to there for its cause (View::laid_window_now), the same for all that read it in
/// that change.
fn Tree::measured_now(self : Tree) -> Unit {
  if self.last_w <= 0.0 {
    return
  }
  let at = self.logic_at()
  let shown = @signals.untracked(fn() { self.clock.get() })
  // (its clock set to the moment and back: what that tells is no change of its own to settle after)
  let was_standing = self.standing
  self.standing = true
  @signals.untracked(fn() {
    self.clock_to(at)
    self.beat.set(at)
    self.pull()
    let mut i = 0
    while i < self.bindings_due.length() {
      let b = self.bindings_due[i]
      if b.queued {
        (b.run)()
      }
      i = i + 1
    }
    self.bindings_due.clear()
    if self.layout_due && self.measured_gen < 0 {
      self.laid_out_now(0, self.last_w, self.last_h, fn(g) {
        self.measured_gen = g
        // (placed by once things are placed, whatever is laid out again before that)
        if self.walk_from < 0 {
          self.walk_from = g
        }
      })
    }
  })
  if shown != at {
    @signals.untracked(fn() {
      self.clock_to(shown)
      self.beat.set(shown)
    })
  }
  self.standing = was_standing
}

///|
/// Where it is laid out in the window as of the logic's moment, and how big (as laid_place_now, each that holds it where
/// it is laid out too, drawn off and grown or shrunk by nothing): where a change told now puts it, said once at that
/// moment, never followed.
pub fn View::laid_window_now(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  self.tree.measured_now()
  let mut x = 0.0
  let mut y = 0.0
  let mut i = self.at
  while i >= 0 {
    let m = self.tree.nodes[i]
    // (a slot lays out nothing of its own: what it holds is placed in the one that holds it)
    if !m.slot {
      x = x + m.flex.left + m.look.dx + m.look.sx * m.flex.width
      y = y + m.flex.top + m.look.dy + m.look.sy * m.flex.height
    }
    i = m.parent
  }
  (x, y, n.flex.width, n.flex.height)
}

///|
/// Where it was last placed in what holds it, and how big (its layout's place and its offset: the frame's, or a
/// change's brought to its moment), drawn off nothing: as it stood before a change told now is laid out (for what moves
/// from there for that change's cause, said once at that moment, never followed).
pub fn View::placed_now(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  (n.lx, n.ly, n.lw, n.lh)
}

///|
/// Where it is laid out in what holds it as of the logic's moment, and how big (what the change under way set so far
/// counted, as a frame would lay it out; its offset with it): where it goes for that change's cause, said once at that
/// moment (View::laid_size's terms), never followed.
pub fn View::laid_place_now(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  self.tree.measured_now()
  (
    n.flex.left + n.look.dx + n.look.sx * n.flex.width,
    n.flex.top + n.look.dy + n.look.sy * n.flex.height,
    n.flex.width,
    n.flex.height,
  )
}

///|
/// How far node `id` turns what it draws itself, and whether about the middle of what it draws (View::turn; 0 for one
/// let go).
pub fn Tree::turn_of(self : Tree, id : NodeId) -> (Double, Bool) {
  if self.alive_id(id) {
    (self.nodes[id.at].look.turn, self.nodes[id.at].look.turn_drawn)
  } else {
    (0.0, false)
  }
}

///|
/// How big it is drawn, what it holds with it, as it changes (1: as it is laid out), about the point of it `about` says
/// (Pivot: At, shares of its width and height, (0.5, 0.5) its middle; FromBeside, the edge it goes out from beside
/// its anchor, on the side it went to, lined up as it is: a popover's, grown from what opened it): its place's. Drawn,
/// pressed, taken (View::takes, what a host under it is told covers it) and read out where it is drawn, as big: one
/// projection of it and its holders (Tree::projected); laid out as before. Where what it holds cuts them, cut as far
/// in; its words, its shapes and its corners drawn as big. An old view it holds (View::hosted) laid out as big as its
/// node, drawn, pressed, typed into and read out as big where it is drawn, by what hosts the tree (ui's island_proj).
pub fn View::scale(self : View, s : Live[Double], about? : Pivot = At(0.5, 0.5)) -> View {
  self.bind(Scale, s, Place, fn(s) {
    let n = self.tree.nodes[self.at]
    n.look.scale = s
    // (grown about another point: what it draws worked out afresh for the middle of it, where it says so)
    if n.look.pivot != about {
      n.drawn_stale = true
    }
    n.look.pivot = about
  })
  self
}

///|
/// Whether it, and what it holds, take presses (false: drawn only, as a page going back or one covered as another comes
/// in): what the tree finds at a point passes over it, as of the moment of the press.
pub fn View::presses(self : View, on : Live[Bool]) -> View {
  // (whether it takes input is the logic's: said at the moment it changes, as a structure's change is, a finger held on
  // it or in it let go of then; said anew, what was said before let go of, as any property's binding is)
  guard self.live() is Some(n) else { return self }
  match n.props.get(Presses) {
    Some(stop) => {
      n.props.remove(Presses)
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.inert = !on
    self.tree.hits = self.tree.hits + 1
    if !on {
      self.tree.hold_lost_in(self.at)
      self.tree.focus_lost_in(self.at)
      self.tree.back_lost_in(self.at)
    }
    // (what hosts it holds in it told, at this cause, once the change is committed whole: Tree::on_modals)
    self.tree.modals_told()
  }
  match on {
    Is(v) => set(v)
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Presses] = stop
      })
  }
  self
}

///|
/// Over all else of the window while `on` holds (a toast's), where it is one of what the root holds (elsewhere, nothing):
/// it and what it holds the window's top, after all else the root holds whatever was made after it (the root's own
/// that are kept in the order they were made, after the rest), what an old frame hosted in the tree puts over all of
/// it at its root (its menus, sheets, dialogs) under it; so drawn, found by a press, the pointer and the wheel, read out
/// and gone to by Tab, the tree's and the old frame's in that one order: no modal layer under it keeping input from it.
/// A modal layer of its own holds the rest of it, as any. Said at the moment it changes, as whether a layer is modal is.
pub fn View::over_all(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(OverAll) {
    Some(stop) => {
      n.props.remove(OverAll)
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.over_all = on
    self.tree.top_last()
    self.tree.places_told()
    self.tree.hits = self.tree.hits + 1
    self.tree.modals_told()
  }
  match on {
    Is(v) => set(v)
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[OverAll] = stop
      })
  }
  self
}

///|
/// Whether node `id` is over all else of the window (in what the root holds that says so: View::over_all). One let go,
/// not.
pub fn Tree::over_all(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.over_all_at(id.at)
}

///|
/// (Whether what of the root's holds node `at`, or is it, says it is over all else: View::over_all.)
fn Tree::over_all_at(self : Tree, at : Int) -> Bool {
  let top = self.top_of(at)
  top >= 0 && self.nodes[top].over_all
}

///|
/// (The node of the root's that node `at` is, or is in: the outermost that is a node of its own, what holds it up to
/// the root slots alone (show, pick, each); -1 where it is held by no such one.)
fn Tree::top_of(self : Tree, at : Int) -> Int {
  let mut i = at
  let mut top = -1
  while i > 0 {
    if !self.nodes[i].slot {
      top = i
    }
    i = self.nodes[i].parent
  }
  if i == 0 {
    top
  } else {
    -1
  }
}

///|
/// At `stack` in the window's stack of layers while `on` says so, where it is one of what the root holds, or in a slot of
/// its (show, pick, each) alone (elsewhere,
/// nothing): over what the root holds that is in none, with the old frame's layers at their places in it
/// (Ctx::stacked), one over another by their places, under what is over all else (View::over_all); so drawn, found by a
/// press and the pointer, read out, gone to by Tab and given the keys; the topmost modal one, the tree's or the old
/// frame's, holding all under it. -1: in none.
pub fn View::stacked(self : View, stack : Live[Int]) -> View {
  self.bind(Stacked, stack, Layout, fn(k) {
    self.tree.nodes[self.at].stack = k
    self.tree.top_last()
    self.tree.places_told()
    self.tree.hits = self.tree.hits + 1
    self.tree.modals_told()
  })
  self
}

///|
/// Whether node `id` is one the root holds (its own, not in another).
pub fn Tree::root_holds(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.top_of(id.at) == id.at
}

///|
/// Where in the window's stack of layers its topmost modal layer is (View::stacked; -1 in none), -2 none: what of what
/// hosts it is under that takes no input.
pub fn Tree::modal_stack(self : Tree) -> Int {
  match self.modal_top() {
    Some(m) => self.stack_at(m.at)
    None => -2
  }
}

///|
/// Where in the window's stack of layers what takes a finger at (x, y) is (Tree::target_at's; -1 in none), -2 nothing
/// of the tree's taking it.
pub fn Tree::stack_takes(self : Tree, x : Double, y : Double) -> Int {
  match self.target_at(x, y) {
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) | Off(id) => self.stack_at(id.at)
    Nothing => -2
  }
}

///|
/// How what hosts it says where its own topmost modal layer is in the window's stack of layers as it is, whenever it is
/// asked (an input's moment: one it dismissed at that moment holding nothing from then; Tree::hold_under says it as each
/// frame ends, what follows it told then).
pub fn Tree::held_under_by(self : Tree, f : () -> Int) -> Unit {
  self.held_under_of = Some(f)
}

///|
/// What hosts it says where in the window's stack of layers its own topmost modal layer is (an old frame's, built at
/// `stack` there: Ctx::stacked; -1 at none, over what is in none alone), -2 none: what of the tree is not over that takes no press, focus or key, and is read
/// out hidden, as under a modal layer of its own (Tree::allows). Said as it changes, each frame.
pub fn Tree::hold_under(self : Tree, stack : Int) -> Unit {
  if self.held_under != stack {
    self.held_under = stack
    self.hits = self.hits + 1
    self.modals_told()
  }
}

///|
/// Where node `id` is in the window's stack of layers (what of the root's holds it, or is it, says: View::stacked,
/// View::over_all): -1 in none, Int's most over all else. One let go, -1.
pub fn Tree::stack_of(self : Tree, id : NodeId) -> Int {
  guard self.alive_id(id) else { return -1 }
  self.stack_at(id.at)
}

///|
fn Tree::stack_at(self : Tree, at : Int) -> Int {
  let top = self.top_of(at)
  if top < 0 {
    return -1
  }
  let n = self.nodes[top]
  if n.over_all {
    2147483647
  } else {
    n.stack
  }
}

///|
/// What the root holds ordered again by its places in the window's stack of layers (View::stacked, View::over_all:
/// Tree::root_layers), as one says it or is made.
fn Tree::top_last(self : Tree) -> Unit {
  // (the order they are drawn, found and read out in is worked out again: Tree::root_layers)
  self.order_marked()
  // (what is drawn over what in the window changed: all of it drawn again where the scene keeps it, Tree::take_placed)
  self.placed_pending.push({ at: 0, gen: self.nodes[0].gen })
}

///|
/// What the root holds put at another place in the window's stack of layers: told to what read where they are
/// (Tree::places_read).
fn Tree::places_told(self : Tree) -> Unit {
  self.places.set(@signals.untracked(fn() { self.places.get() }) + 1)
}

///|
/// Where what the root holds is in the window's stack of layers (Tree::stack_of) followed by what reads it here: told
/// as any is put at another place (View::stacked, View::over_all).
pub fn Tree::places_read(self : Tree) -> Unit {
  self.places.get() |> ignore
}

///|
/// Whether what takes a finger at (x, y) is over all else of the window (Tree::target_at's, View::over_all): what of
/// the old frame's is put over all of it there under it, taking none of it.
pub fn Tree::over_all_takes(self : Tree, x : Double, y : Double) -> Bool {
  match self.target_at(x, y) {
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) | Off(id) => self.over_all_at(id.at)
    Nothing => false
  }
}

///|
/// A modal layer while `on` holds (said at the moment it changes, as whether it takes presses is: View::presses): the
/// topmost such of the tree's (by the order it is drawn in) takes all input; what it does not hold, drawn under it,
/// takes none (no press, no finger, no menu, no wheel: Tree::allows, and what a host asks of it: an old view's keys,
/// its stops for Tab, what of it is read out). Its turning off is at once, as it is said (a viewer closing gives the
/// pages their input back as it begins to go, whatever is still drawn of it).
pub fn View::modal(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(Modal) {
    Some(stop) => {
      n.props.remove(Modal)
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.modal = on
    self.tree.hits = self.tree.hits + 1
    match self.tree.modals.search(self.at) {
      Some(i) if !on => self.tree.modals.remove(i) |> ignore
      None if on => self.tree.modals.push(self.at)
      _ => ()
    }
    self.tree.modals_told()
  }
  match on {
    Is(v) => set(v)
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Modal] = stop
      })
  }
  self
}

///|
/// A modal layer said on or off, or where what is drawn is among what holds it changed (one made, let go, moved, back
/// from leaving): a finger held on what the topmost no longer lets take input called off, and what hosts the tree told
/// (Tree::on_modals), once the change doing it is committed whole, at that change's moment (Tree::modals_settled).
fn Tree::modals_told(self : Tree) -> Unit {
  // (what takes input changed: which column's bar the pointer is along told anew too, at this change's end)
  if !self.bar_cols.is_empty() {
    self.bars_due = true
  }
  if self.committing > 0 {
    self.modals_due = true
    return
  }
  self.modals_now()
}

///|
/// A change committed whole (the outermost Tree::at_cause or event ending, its moment still the cause's): what a modal
/// layer said in it told now.
fn Tree::modals_settled(self : Tree) -> Unit {
  if self.committing == 0 && self.modals_due {
    self.modals_due = false
    self.modals_now()
  }
  self.withins_settled()
}

///|
/// A change committed whole (outside any other being committed): where what is under the pointer is read
/// (View::pointer_within) and the change laid out or placed anything again, laid out now as of the change's moment
/// (Tree::laid_now: what it told pulled in, laid out, placed; what is under the pointer told then, laid_out's), so what
/// reads it has it as the change left it, no frame waited for. Nothing laid out where nothing reads it.
fn Tree::withins_settled(self : Tree) -> Unit {
  if self.committing > 0 || self.standing || self.withins_passing || self.withins_asked { return }
  // One structural reader can finish before the other readers of the same signal change. Placing here would
  // overwrite the old positions before a movement group has captured them. Pointer geometry follows the whole
  // change, just as settle_after_change does, after every reader has seen its cause.
  self.withins_asked = true
  @signals.after_flush(fn() {
    self.withins_asked = false
    self.withins_ready()
  })
}

///|
fn Tree::withins_ready(self : Tree) -> Unit {
  // A clock reaction can commit another structure while an immediate layout is standing. That layout will finish
  // the work; entering it again here can alternate the drawn clock and exhaust the stack.
  if self.committing == 0 &&
    !self.standing &&
    !self.withins_passing &&
    (!self.withins_at.is_empty() || !self.bar_cols.is_empty()) &&
    (self.layout_due || !self.places_due.is_empty() || !self.bindings_due.is_empty() || !self.pulls_marked.is_empty()) {
    self.laid_now()
    self.withins_restored()
  }
  // (what takes input changed with nothing else to lay out: which column's bar the pointer is along told now, at the
  // change's end)
  if self.committing == 0 && !self.standing && !self.withins_passing && self.bars_due {
    self.withins_passing = true
    self.bars_near_told() |> ignore
    self.withins_passing = false
  }
}

///|
/// Finish pointer work told as an immediate layout restored the drawn clock. The original layout was needed at the
/// change's moment; this pass uses the restored clock without switching it back and recursively entering that layout.
fn Tree::withins_restored(self : Tree) -> Unit {
  if self.committing != 0 || self.withins_passing || self.last_w <= 0.0 {
    return
  }
  if (!self.withins_at.is_empty() || !self.bar_cols.is_empty()) &&
    (self.layout_due || !self.places_due.is_empty() || !self.bindings_due.is_empty() || !self.pulls_marked.is_empty()) {
    let was_standing = self.standing
    self.standing = true
    @signals.untracked(fn() {
      self.pull()
      self.laid_out(self.clock.get())
    })
    self.standing = was_standing
  }
  if !self.withins_passing && self.bars_due {
    self.withins_passing = true
    self.bars_near_told() |> ignore
    self.withins_passing = false
  }
}

///|
fn Tree::modals_now(self : Tree) -> Unit {
  // (the layers that give the focus: given back from those gone, then to the topmost of those opened, what had it kept
  // first, before what a modal layer keeps from the focus lets it go)
  self.layers_focus_told()
  if !self.modals.is_empty() {
    match self.held {
      Some(h) if !self.allows(h) => self.hold_lost_in(0)
      _ => ()
    }
    match self.focused {
      Some(h) if !self.allows(h) && !self.typing_kept(h) => self.focus_lost_in(0)
      _ => ()
    }
    match self.backing {
      // (one the topmost modal layer over it lets go on: View::held_back_goes_on)
      Some((b, _)) if !self.allows(b) && !(self.modal_top_lets_back() && self.presses_here(b)) => self.back_lost_in(0)
      _ => ()
    }
  }
  // (whether each node asked takes input now told it, at this cause: View::takes_input)
  self.inputs_told()
  // (what hosts it holds of its own, asked whether it may still take input, whatever changed it: a modal layer, a node
  // let go, leaving, said to take no press)
  (self.on_modals)()
}

///|
/// Whether the topmost modal layer now leaves what is typed to the field under it that has the focus
/// (View::leaves_typing).
pub fn Tree::typing_left_under(self : Tree) -> Bool {
  match self.modal_top() {
    Some(m) => self.nodes[m.at].leaves_typing
    None => false
  }
}

///|
/// Whether the topmost modal layer now lets a back gesture under way go on (View::held_back_goes_on).
pub fn Tree::modal_top_lets_back(self : Tree) -> Bool {
  match self.modal_top() {
    Some(m) => self.nodes[m.at].back_goes_on
    None => false
  }
}

///|
/// The topmost modal layer now (View::modal: on, living, not leaving), if one is: of those, the one drawn last, by
/// where each is among what holds it as the tree is now (as Tree::ordered makes the order the next frame draws in),
/// whether a frame made that order since or not.
pub fn Tree::modal_top(self : Tree) -> NodeId? {
  let mut top = -1
  let mut top_path : Array[Int] = []
  for at in self.modals {
    let n = self.nodes[at]
    if !n.live || !n.modal || self.leaving_at(at) {
      continue
    }
    guard self.layer_path(at) is Some(path) else { continue }
    if top < 0 || drawn_after(path, top_path) {
      top = at
      top_path = path
    }
  }
  if top < 0 {
    None
  } else {
    Some({ at: top, gen: self.nodes[top].gen })
  }
}

///|
/// Where node `at` is in the tree: each node's index among what holds it, from the root's down to it; none where it is
/// held by nothing the root holds (made, not yet put in what holds it).
fn Tree::path_of(self : Tree, at : Int) -> Array[Int]? {
  let path : Array[Int] = []
  let mut i = at
  while self.nodes[i].parent >= 0 {
    let p = self.nodes[i].parent
    guard self.nodes[p].kids.search(i) is Some(k) else { return None }
    path.push(k)
    i = p
  }
  if i != 0 {
    return None
  }
  path.rev_in_place()
  Some(path)
}

///|
/// Whether the node at `a` (a path: Tree::path_of) is drawn after the one at `b`: after what it is held by, after what
/// is before it among what holds them both.
fn drawn_after(a : Array[Int], b : Array[Int]) -> Bool {
  for i in 0..<a.length() {
    if i >= b.length() {
      return true
    }
    if a[i] != b[i] {
      return a[i] > b[i]
    }
  }
  false
}

///|
/// Whether node `id` may take input now: it lives, and no modal layer is on, or the topmost holds it (or is it). One
/// let go (its index free or made another's since) takes none.
pub fn Tree::allows(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  if !n.live || n.gen != id.gen {
    return false
  }
  self.allows_at(id.at)
}

///|
fn Tree::allows_at(self : Tree, at : Int, held? : Bool = true) -> Bool {
  // (an old frame's modal layer over it in the window's stack of layers: Tree::held_under)
  // (as it is as asked where what hosts it said how to ask it, else as last told)
  let under = if !held {
    -2
  } else {
    match self.held_under_of {
      Some(f) => f()
      None => self.held_under
    }
  }
  if under > -2 && self.stack_at(at) <= under {
    return false
  }
  match self.modal_top() {
    None => true
    Some(m) => {
      // (over it in the window's stack of layers, over all else among them: View::stacked, View::over_all)
      if self.stack_at(at) > self.stack_at(m.at) {
        return true
      }
      let mut i = at
      while i >= 0 {
        if i == m.at {
          return true
        }
        i = self.nodes[i].parent
      }
      false
    }
  }
}

///|
/// Whether node `id` is where presses are taken, a modal layer over it or not: it lives, and neither it nor what holds
/// it is leaving or said to take none (where an old view's hits are placed: whether a modal layer lets them take the
/// input is asked as it comes, Tree::allows).
pub fn Tree::presses_here(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  n.live && n.gen == id.gen && !self.pressless_own_at(id.at)
}

///|
/// Whether node `id` takes presses now: it lives, and neither it nor what holds it is leaving or said to take none.
///|
/// Whether a modal layer of the tree's own over node `id` keeps it from input (Tree::allows, whatever an old frame's
/// modal layer over it says: what the old frame keeps itself, its focus on a field under a menu it opened, asks this).
pub fn Tree::allows_as_its_own(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  n.live && n.gen == id.gen && self.allows_at(id.at, held=false)
}

///|
/// Whether node `id` takes presses now as the tree's own modal layers have it, whatever an old frame's modal layer over
/// it says (Tree::held_under): what the old frame orders itself (its back, said in the old view the node hosts, after
/// what its layer said or under it: the old frame's own chain) asks this, not Tree::takes_presses.
pub fn Tree::takes_presses_as_its_own(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  n.live && n.gen == id.gen && self.allows_at(id.at, held=false) && !self.pressless_own_at(id.at)
}

///|
pub fn Tree::takes_presses(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  n.live && n.gen == id.gen && !self.pressless_at(id.at)
}

///|
/// The words it shows: layout's (their size) and paint's, in `ink` (View::ink as it changes), set as `look` says.
pub fn View::words(
  self : View,
  words : Live[String],
  ink? : Int64 = 0x000000FFL,
  look? : WordsLook = words_plain,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.look.ink = ink
  n.look.words_look = look
  let tree = self.tree
  let at = self.at
  // (it measures what the node holds now, by its index: dropped as it is let go)
  n.flex.measure = Some(fn(w, wm, _h, _hm) {
    let offered = match wm {
      Exactly | AtMost => w
      Undefined => -1.0
    }
    tree.work.measured = tree.work.measured + 1
    let nd = tree.nodes[at]
    let look = nd.look
    let (mw, mh) = if look.runs.is_empty() {
      (tree.measure)(look.words, look.words_look, offered)
    } else {
      (tree.measure_runs)(look.runs, look.words_look, look.runs_look, offered)
    }
    // (on one line wider than it may be, saying shorter ones: as wide as what of them would be drawn there, as an old
    // view's leaf_size has it; what is drawn chosen once it is laid out, Tree::shorter_in, not by this)
    let mw = if look.runs.is_empty() &&
      !look.words_look.wrap &&
      nd.shorter.length() > 0 &&
      wm == AtMost &&
      mw > offered + 0.5 {
      (tree.measure_shorter)(look.words, nd.shorter, look.words_look, offered)
    } else {
      mw
    }
    match wm {
      Exactly => (w, mh)
      _ => (mw, mh)
    }
  })
  self.bind(Words, words, Both, fn(s) {
    tree.nodes[at].look.words = s
    tree.nodes[at].look.runs = []
    // (on one line in a column: no wider than it, Tree::capped_applied)
    tree.capped_applied(at)
    // (words alone again: whether its shorter words hold, how it gives way with them, as they do now)
    if tree.nodes[at].shorter.length() > 0 {
      tree.give_way_applied(at)
    }
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  self
}

///|
/// What it says in place of its words (View::words), in order, where they have not the room on their line: the first
/// of these that has, else the last ("": nothing), chosen as it is laid out, as an old view's text's `shorter`; its own
/// words where they have the room. Saying them, it gives way along a row (not down a column) down to the last of them,
/// as its words look now, where how it gives way and how narrow it may be are not said of it (View::shrink,
/// View::cuts, View::min_width: theirs where said, whichever is said first); saying none, as ever. As it changes:
/// layout's.
pub fn View::shorter(self : View, alts : Live[Array[String]]) -> View {
  let at = self.at
  let tree = self.tree
  // (how narrow it may be follows how its words look as the system's size of words changes: worked out again then)
  if self.live() is Some(n) && n.props.get(Shorter) is None {
    self.reacts(fn() { self.words_redone() }, fn(_) { tree.give_way_applied(at) })
  }
  self.bind(Shorter, alts, Layout, fn(a) {
    tree.nodes[at].shorter = a
    tree.give_way_applied(at)
  })
  self
}
///|
/// Left out of its row where the row has not the room for all it holds (`k` > 0: the k-th to go, the last in the row
/// first of the same k; -1: there only while something of its row is left out, its ⋯; 0: always there), as it
/// changes: laid out nowhere while it is, none of it drawn, pressed or read out; back where it was as the room comes.
/// Its row says it lets them go so (View::fits). Layout's.
pub fn View::drops(self : View, k : Live[Int]) -> View {
  self.bind(Drop, k, Layout, fn(k) { self.tree.nodes[self.at].flex.style.drop = k })
  self
}

///|
/// A row that leaves out of what it holds what has not the room (View::drops), as it changes. Layout's.
pub fn View::fits(self : View, on : Live[Bool]) -> View {
  self.bind(Fits, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.fits = on })
  self
}

///|
/// Whether its row left it out as it was last laid out (View::drops), followed: told once all of the layout is done, as
/// one change of all its rows left out.
pub fn View::left_out(self : View) -> Bool {
  self.tree.outs_said.get() |> ignore
  match self.live() {
    Some(n) => n.out
    None => false
  }
}

///|
/// How big it is as what it hosts (the node View::hosted made: nothing of the tree's own in it) is laid out, as `content` says what
/// that is as it changes: `size` given it and the width it is offered (None: none offered, as wide as it comes to),
/// answering how wide and tall; offered exactly a width, as wide as that. `size` reads nothing that changes but what
/// `content` gives it (run with nothing followed): measured again only as `content` comes out otherwise, as the room
/// offered changes, or as all words are measured anew (Tree::words_again). Laid out by what holds it as words are.
pub fn[K : Eq] View::measured(self : View, content : Live[K], size : (K, Double?) -> (Double, Double)) -> View {
  guard self.live() is Some(n) else { return self }
  let tree = self.tree
  let k : Ref[K?] = Ref(None)
  n.flex.measure = Some(fn(w, wm, _h, _hm) {
    tree.work.measured = tree.work.measured + 1
    match k.val {
      Some(v) => {
        let (mw, mh) = @signals.untracked(fn() {
          size(v, match wm {
            Exactly | AtMost => Some(w)
            Undefined => None
          })
        })
        match wm {
          Exactly => (w, mh)
          _ => (mw, mh)
        }
      }
      None => (0.0, 0.0)
    }
  })
  self.bind(Measured, content, Layout, fn(v) { k.val = Some(v) })
  self
}

///|
/// The words it shows in pieces, each set its own way (a weight, an ink: @text.Run), one paragraph laid out as one
/// (View::words otherwise: read out, found and measured as the pieces' words one after another), as they change.
pub fn View::words_runs(
  self : View,
  runs : Live[Array[@text.Run]],
  ink? : Int64 = 0x000000FFL,
  look? : WordsLook = words_plain,
) -> View {
  let tree = self.tree
  let at = self.at
  self.words(Is(""), ink~, look~) |> ignore
  self.bind(Words, runs, Both, fn(rs) {
    let words = StringBuilder()
    for r in rs {
      words.write_string(r.text)
    }
    tree.nodes[at].look.words = words.to_string()
    tree.nodes[at].look.runs = rs
    tree.capped_applied(at)
    // (in pieces: its shorter words hold of words alone, how it gives way without them, as now)
    if tree.nodes[at].shorter.length() > 0 {
      tree.give_way_applied(at)
    }
    // (how its words are set said: what follows it told, once this is)
    self.words_told()
  })
  // (what of them is picked with the pointer, where what holds it says so: View::runs_picker's)
  match self.lent(runs_picker) {
    Some(f) => self.runs_picked(f(self)) |> ignore
    None => ()
  }
  // (a passage of them on its own ground, where what holds it says so: View::runs_liter's)
  match self.lent(runs_liter) {
    Some(f) => self.runs_lit(f(self)) |> ignore
    None => ()
  }
  self
}

///|
/// Where the pointer's secondary button was pressed on a node (View::on_menu): in its own terms as it is drawn then, in
/// the window's, and when (the event's own moment).
pub(all) struct Menu {
  x : Double
  y : Double
  wx : Double
  wy : Double
  at : Double
} derive(Eq, Show, Debug)

///|
/// What the pointer's secondary button pressed on it asks for (its menu, where it was pressed): run as one change at
/// the press's moment, outside any tracking. Its primary press and a finger are its on_press's and on_drag's, as ever.
pub fn View::on_menu(self : View, f : (Menu) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_menu = Some(f)
  self
}

///|
/// The pointer's secondary button pressed at (x, y) in the window at `at`: where the topmost node drawn there that takes
/// a press asks for a menu (View::on_menu), its menu asked for, as one event of that moment; true then. None asks where
/// the topmost is one that does not (or hosts the old view, or nothing is there).
pub fn Tree::menu_at(self : Tree, x : Double, y : Double, at : Double) -> Bool {
  self.asked_at(x, y, at, fn(n) { n.on_menu is Some(_) }, fn(n, lx, ly, t) {
    match n.on_menu {
      Some(f) => f({ x: lx, y: ly, wx: x, wy: y, at: t })
      None => ()
    }
  })
}

///|
/// A wheel turned over a node at (x, y): how far across and down (`dx`, `dy`, as the host says it), what was held
/// with it (`mods`, the host's wheel_mod_*), in the node's own terms as it is drawn then, in the window's, and when.
pub(all) struct Wheel {
  x : Double
  y : Double
  wx : Double
  wy : Double
  dx : Double
  dy : Double
  mods : Int
  at : Double
} derive(Eq, Show, Debug)

///|
/// What a wheel turned over it does (its own, at the wheel's moment, as one change outside any tracking): what is
/// under it sees none of it.
pub fn View::on_wheel(self : View, f : (Wheel) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_wheel = Some(fn(w) {
    f(w)
    true
  })
  n.wheel_said = n.wheel_said + 1
  self
}

///|
/// What a wheel turned over it moves (its own, at the wheel's moment, as one change outside any tracking): true where it
/// moved it; false where it is at its end that way (or moves nothing by it), the wheel going on to what holds it, as a
/// column scrolled to its end leaves the wheel to the one it is in (Tree::wheel_at).
pub fn View::on_wheel_moves(self : View, f : (Wheel) -> Bool) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_wheel = Some(f)
  n.wheel_said = n.wheel_said + 1
  self
}

///|
/// A wheel turned at (x, y) in the window at `at` (`dx`, `dy`, `mods` as the host says them), as one event of that
/// moment: asked of the topmost node drawn there that takes a press or the wheel (or hosts an old view with something of
/// its own there, `there` says: one with nothing there is passed, as though it were not there), then of what holds it,
/// each in turn, till one takes it (View::on_wheel: all of it; View::on_wheel_moves: where it moved what it
/// moves, not at its end that way); where one hosts an old view, `old` of it first (whether what of that old view's is
/// there took it: a list of its own not at its end). Each asked as it was when the wheel came, what holds it then, as
/// it was said then, only while it still is so (one asked before may have let it go, said anew, or its index another's
/// since). True where it was the tree's: one was asked (took it, or none did: nothing moves by it, nothing under what
/// is drawn there asked); none where none was (nothing there takes the wheel, nor hosts an old view: what is under it
/// the old frame's, as ever; or the tree is gone).
pub fn Tree::wheel_at(
  self : Tree,
  x : Double,
  y : Double,
  dx : Double,
  dy : Double,
  mods : Int,
  at : Double,
  old? : (NodeId) -> Bool = fn(_) { false },
  there? : (NodeId) -> Bool = fn(_) { true },
) -> Bool {
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let theirs = Ref(false)
  self.event(t, fn() {
    // (where things are as of then, what the change under way set before it counted: Tree::asked_at's)
    self.laid_now()
    let found : Ref[NodeId?] = Ref(None)
    let now = self.logic_at()
    self.walk_taken(x, y, fn(c, cx, cy, _, s) {
      if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
        let n = self.nodes[c.id.at]
        if n.wheel_through {
          return
        }
        if n.on_wheel is Some(_) ||
          n.on_drag is Some(_) ||
          n.on_press is Some(_) ||
          n.top_row ||
          (n.hosted && @signals.untracked(fn() { there(c.id) })) {
          found.val = Some(c.id)
        }
      }
    })
    guard found.val is Some(id) && self.nodes[0].live else { return }
    // (from it up through what holds it as of then, the innermost first: each node, whether it hosted an old view, and
    // how many times what a wheel does to it was said then)
    let chain : Array[(NodeId, Bool, Int)] = []
    let mut i = id.at
    while i >= 0 {
      let n = self.nodes[i]
      chain.push(({ at: i, gen: n.gen }, n.hosted, n.wheel_said))
      i = n.parent
    }
    for e in chain {
      let (id, hosted, said) = e
      guard self.nodes[0].live else { break }
      let n = self.nodes[id.at]
      guard n.live && n.gen == id.gen && !self.pressless_at(id.at) else { continue }
      if hosted && n.hosted {
        theirs.val = true
        if @signals.untracked(fn() { old(id) }) {
          break
        }
      }
      guard n.wheel_said == said && n.on_wheel is Some(f) else { continue }
      theirs.val = true
      let (nx, ny, ns) = self.placed(id.at)
      if @signals.untracked(fn() { f({ x: (x - nx) / ns, y: (y - ny) / ns, wx: x, wy: y, dx, dy, mods, at: t }) }) {
        break
      }
    }
  })
  theirs.val
}

///|
/// A key, as a node is told it (View::on_key): its code and the modifiers held (the host's, as an old view reads them:
/// ui's key codes), at its moment.
pub(all) struct Key {
  code : Int
  mods : Int
  at : Double
} derive(Eq, Show, Debug)

///|
/// What a key does to it, while it takes input (living, not leaving nor said to take none, no modal layer over it that
/// does not hold it): run at the key's moment, as one change outside any tracking; true where it took the key, which
/// nothing else is told of then. Asked from what has the focus up through what holds it, then the rest topmost first
/// (Tree::key_at).
pub fn View::on_key(self : View, f : (Key) -> Bool) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_key = Some(f)
  n.key_said = n.key_said + 1
  self.tree.keys_said_at.add(self.at)
  self
}

///|
/// The keys (`keys`: a code and the modifiers held) what a key does to it (View::on_key) is told of while a field has the
/// focus too, at the key's moment, as the field takes them as its own (an arrow its caret moves by): a shortcut that
/// goes on in a field (⌥↑ to the chat before, the field's caret moved by it as well), as the old frame's keys read
/// with `in_field`. Only those said; any other key a field takes is the field's alone.
pub fn View::keys_in_fields(self : View, keys : Array[(Int, Int)]) -> View {
  guard self.live() is Some(n) else { return self }
  n.keys_in_fields = keys
  self.tree.keys_said_at.add(self.at)
  self
}

///|
/// A key (`code`, `mods` held) at `at` that a field with the focus takes as its own, told also those that said it goes on
/// in a field (View::keys_in_fields), the topmost first, till one takes it, as one event of that moment (the tree
/// brought there first where it is in none). True where one did; the field takes it either way.
pub fn Tree::key_in_field(self : Tree, code : Int, mods : Int, at : Double) -> Bool {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return false
  }
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let took = Ref(false)
  self.event(t, fn() {
    let said : Array[Int] = []
    for i in self.keys_said_at {
      let n = self.nodes[i]
      if n.live && n.on_key is Some(_) && self.held_by_root(i) && n.keys_in_fields.contains((code, mods)) {
        said.push(i)
      }
    }
    said.sort_by(fn(a, b) { if a == b { 0 } else if self.topmost_before(a, b) { -1 } else { 1 } })
    for i in said {
      let n = self.nodes[i]
      guard n.live && !self.pressless_at(i) && self.allows_at(i) else { continue }
      match n.on_key {
        Some(f) =>
          if @signals.untracked(fn() { f({ code, mods, at: t }) }) {
            took.val = true
            break
          }
        None => ()
      }
    }
  })
  took.val
}

///|
/// A key (`code`, `mods` held) at `at`: asked of the nodes that take keys (View::on_key) that may take input now, each in
/// turn till one takes it, as one event of that moment (the tree brought there first where it is in none): the node with
/// the focus and what holds it, the innermost first (the DOM's bubbling), then the rest of those said to take keys, the
/// one drawn last first (Tree::topmost_before: by the window's stack of layers, then after what holds it, after what is
/// before it among what holds them both), as a window's own listeners are told last. `above`, only what is over that in
/// the window's stack of layers (View::stacked: the old frame's layer under it taking the keys); `within`, a field with
/// the focus (the tree's, or an old view's hosted in it): what is in a layer over its in the window's stack first (what was
/// opened over the page has Escape before the page; not what is drawn after it in its own), then that node and what
/// holds it, nothing else. Nothing of the tree gone through but what holds
/// the focus and those said (Work's keys_asked). True where one took it.
pub fn Tree::key_at(
  self : Tree,
  code : Int,
  mods : Int,
  at : Double,
  above? : Int = -3,
  within? : NodeId? = None,
) -> Bool {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return false
  }
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let took = Ref(false)
  self.event(t, fn() {
    // (where it starts: what holds the focus, the tree's or an old view's field's node (`within`); from there up through
    // what holds it, the innermost first, as the DOM's keys bubble)
    let start = match within {
      Some(w) => Some(w)
      None => self.focused
    }
    let chain : Array[Int] = []
    let focus_at = Ref(-1)
    match start {
      Some(id) if self.alive_id(id) && self.held_by_root(id.at) => {
        focus_at.val = id.at
        let mut i = id.at
        while i >= 0 {
          self.work.keys_asked = self.work.keys_asked + 1
          if self.nodes[i].on_key is Some(_) {
            chain.push(i)
          }
          i = self.nodes[i].parent
        }
      }
      _ => ()
    }
    // (what else says what a key does to it, never the whole tree gone through (those said, Tree::keys_said_at), the
    // topmost first: what is drawn over what has the focus (a tip, a menu over it: the window's stack of layers, and
    // what is drawn after it) before it, as the topmost layer takes back; what is under it after what holds it, as the
    // window's own listeners are told after what the focus is in. A field holding the focus (`within`): what is in a
    // layer over its, then its, nothing else)
    {
      let rest : Array[Int] = []
      let gone : Array[Int] = []
      for i in self.keys_said_at {
        self.work.keys_asked = self.work.keys_asked + 1
        let n = self.nodes[i]
        if !n.live || n.on_key is None {
          gone.push(i)
        } else if self.held_by_root(i) && !chain.contains(i) {
          rest.push(i)
        }
      }
      for i in gone {
        self.keys_said_at.remove(i)
      }
      rest.sort_by(fn(a, b) { if a == b { 0 } else if self.topmost_before(a, b) { -1 } else { 1 } })
      match (if focus_at.val >= 0 { Some(focus_at.val) } else { None }) {
        Some(f) => {
          // (a field's (`within`): of what is drawn over it, only what is in a layer over its in the window's stack (what
          // the shell or a presenter opened over the page), never what is drawn after it in its own (a button or a
          // bubble over the field), which would take what the field is to have)
          let over = match within {
            None => rest.filter(fn(i) { self.topmost_before(i, f) })
            Some(_) => {
              let own = self.stack_at(f)
              rest.filter(fn(i) { self.stack_at(i) > own })
            }
          }
          let under = rest.filter(fn(i) { !self.topmost_before(i, f) })
          over.append(chain)
          if within is None {
            over.append(under)
          }
          chain.clear()
          chain.append(over)
        }
        None => if within is None { chain.append(rest) }
      }
    }
    // (`above`: of what is over that in the window's stack of layers alone, View::stacked)
    let found = if above > -3 { chain.filter(fn(i) { self.stack_at(i) > above }) } else { chain }
    // (each as it was asked: its node and what it said then, asked only while both are still so as its turn comes (one
    // above it may have let it go, its index another's since, or said anew), the tree still there)
    let asked = found.filter_map(fn(i) {
      let n = self.nodes[i]
      match n.on_key {
        Some(f) => Some(({ at: i, gen: n.gen }, n.key_said, f))
        None => None
      }
    })
    for e in asked {
      let (id, said, f) = e
      guard self.nodes[0].live else { break }
      let n = self.nodes[id.at]
      guard n.live && n.gen == id.gen && n.key_said == said && !self.pressless_at(id.at) else {
        continue
      }
      if @signals.untracked(fn() { f({ code, mods, at: t }) }) {
        took.val = true
        break
      }
    }
  })
  took.val
}

///|
/// What the pointer does at (x, y) at `at` (a secondary press, a wheel), asked of the topmost node drawn there that takes
/// a press: where it is one that `takes` it, `then` with it, where in it and when, as one event of that moment (the
/// moment of the event it is in, the tree brought there first where it is in none; where things are as of then, as a
/// drag's: Tree::drag_at); true then.
fn Tree::asked_at(
  self : Tree,
  x : Double,
  y : Double,
  at : Double,
  takes : (Node) -> Bool,
  then : (Node, Double, Double, Double) -> Unit,
) -> Bool {
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let asked = Ref(false)
  self.event(t, fn() {
    // (where things are as of then, what the change under way set before it counted)
    self.laid_now()
    let found : Ref[NodeId?] = Ref(None)
    let now = self.logic_at()
    self.walk_taken(x, y, fn(c, cx, cy, _, s) {
      if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
        let n = self.nodes[c.id.at]
        if takes(n) || n.on_drag is Some(_) || n.on_press is Some(_) || n.top_row || n.hosted {
          found.val = Some(c.id)
        }
      }
    })
    match found.val {
      Some(id) => {
        let n = self.nodes[id.at]
        if takes(n) {
          asked.val = true
          let (nx, ny, ns) = self.placed(id.at)
          then(n, (x - nx) / ns, (y - ny) / ns, t)
        }
      }
      None => ()
    }
  })
  asked.val
}

///|
/// What a press on it does: run outside any tracking, as one change (what it writes told once it is done).
pub fn View::on_press(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_press = Some(f)
  self.tree.hits = self.tree.hits + 1
  self
}

///|
/// A top row of the app's own (Ctx::window_drag's): a press on it, where nothing over it takes the press, is its own,
/// nothing under it taking it; while `on` holds, it moves the window (and a double click on it zooms it), as the
/// system's title bar does, in a window with none of the system's (a window gone full screen has the system's again).
/// Taken so where it takes presses (View::presses). Said at the moment it changes, as whether it takes presses is.
pub fn View::moves_window(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  n.top_row = true
  self.tree.hits = self.tree.hits + 1
  match n.props.get(MovesWindow) {
    Some(stop) => {
      n.props.remove(MovesWindow)
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.moves_window = on
  }
  match on {
    Is(v) => set(v)
    Painted(_) => not_painted("what is said here")
    Roomed(_, _) => not_roomed()
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[MovesWindow] = stop
      })
  }
  self
}

///|
/// A finger or the pointer held on a node (View::on_drag): put down, moved, let go or called off (the host took it:
/// a gesture of the system's), where (in the node's own terms: from its top left as it is drawn then) and when (the
/// event's own moment).
pub(all) enum DragIs {
  Down
  Moved
  Up
  Off
} derive(Eq, Show, Debug)

///|
pub(all) struct Drag {
  kind : DragIs
  /// where, in the node's own terms then (where it is drawn as of `at`)
  x : Double
  y : Double
  at : Double
  /// where, in the window's: how far the finger itself went, whatever moved the node meanwhile
  wx : Double
  wy : Double
  /// where it went down, in the node's own terms as of then (a gesture's words: View::gesture; a raw event's: where it
  /// is)
  ox : Double
  oy : Double
  /// which finger: the same one from its down to its end, whichever others went down or were let go meanwhile (the
  /// first of a hold 0, the next 1 and on)
  finger : Int
  /// when the finger went down: a hold another node held first and handed it (Tree::hand_through) keeps the moment it
  /// began, what it counts how long it is held from
  since : Double
  /// how wide and how tall the node is laid out as of then, in its own terms (what `x` and `y` are within: a press's
  /// ripple as big as what it ripples, nothing of its layout read back for it; nothing, called off)
  w : Double
  h : Double
  /// how fast the finger goes as of this event (the window's points a ms, across and down), from its own events since
  /// it went down by their own times (Tracker: Compose's VelocityTracker, a pause cutting it, as an old view's list
  /// flings at): 0 where it cannot tell
  vx : Double
  vy : Double
} derive(Eq, Show, Debug)

///|
/// What a finger or the pointer held on it does as it goes: put down on it, it is the node's till it is let go or
/// called off (moved anywhere meanwhile), each event handled at its own moment as one change (Tree::event), outside
/// any tracking. One let go meanwhile is told nothing more. Up to `fingers` held on it at once, each told by its own
/// events (Drag's `finger`); one more down calls the hold off (each of those down told Off), the rest of it nobody's.
pub fn View::on_drag(self : View, f : (Drag) -> Unit, fingers? : Int = 1) -> View {
  guard self.live() is Some(n) else { return self }
  n.fingers = if fingers < 1 { 1 } else { fingers }
  n.drag_said = n.drag_said + 1
  self.drag_ended()
  // (said anew: a finger held on it now is the one before's, ended)
  match self.tree.held {
    Some(h) if h.at == self.at && h.gen == self.gen => self.tree.held_to(None)
    _ => ()
  }
  n.on_drag = Some(f)
  self.tree.hits = self.tree.hits + 1
  self
}

///|
/// Where in a node a finger is taken at a moment, the rest passed to what is under it as though it were not there.
pub(all) enum Takes {
  /// rects of it (x0, y0, x1, y1, in its own terms), given how big it is and the moment: what a finger finds, and what
  /// a host drawing under it is told covers what it draws (Tree::finger_areas)
  Areas((Double, Double, Double) -> Array[(Double, Double, Double, Double)])
  /// a node hosting another's (View::hosted): where what it hosts takes it, asked of the point (in its own terms) and
  /// the moment; what it hosts tells a host its own targets
  AsHosted((Double, Double, Double) -> Bool)
}

///|
/// Whether a finger at (x, y) in node `n`, `w` by `h` (in its own terms), is taken at `at` (View::takes; all of it where
/// it says nothing).
fn Tree::takes_here(self : Tree, n : Node, x : Double, y : Double, w : Double, h : Double, at : Double) -> Bool {
  self.takes_said(n)
  match n.takes {
    Some(Areas(_)) => self.takes_rects(n, w, h, at).iter().any(fn(r) { x >= r.0 && y >= r.1 && x < r.2 && y < r.3 })
    Some(AsHosted(f)) => f(x, y, at)
    None => true
  }
}

///|
/// Where node `n`, `w` by `h`, takes a finger at `at` as it says (View::takes): rects of it in its own terms. What asks,
/// where it follows what it reads (a point followed, a frame painted), follows the node's reading of it for that size and
/// moment (takes_units: what it says and what it read for it from one reading, worked out again as what it read
/// changes, following nothing once nothing follows it) and its telling (takes_ver: said anew, let go), never what it
/// read: one node's let go lets go of what that read alone. What asks following nothing, read as it is.
fn Tree::takes_rects(
  self : Tree,
  n : Node,
  w : Double,
  h : Double,
  at : Double,
) -> Array[(Double, Double, Double, Double)] {
  ignore(self)
  guard n.takes is Some(Areas(f)) else { return [] }
  if @signals.active_sub() is None {
    return f(w, h, at)
  }
  // (those nothing follows let go of, what they read with them; the one of this size and moment, else one made)
  let unit : Ref[@signals.Computed[Array[(Double, Double, Double, Double)]]?] = Ref(None)
  n.takes_units = n.takes_units.filter(fn(e) {
    let (u, uw, uh, uat) = e
    if uw == w && uh == h && uat == at {
      unit.val = Some(u)
      true
    } else if u.watched() {
      true
    } else {
      u.dispose()
      false
    }
  })
  let u = match unit.val {
    Some(u) => u
    None => {
      let u = @signals.computed(fn(_) { f(w, h, at) })
      n.takes_units.push((u, w, h, at))
      u
    }
  }
  u.get()
}

///|
/// Where in it a finger is taken, as of a moment (`areas` given how big it is and the logic's moment as a finger comes:
/// Tree::target_at): what it draws there then, as rects of it in its own terms (x0, y0, x1, y1), the rest passed to
/// what is under it as though it were not there. Of the same state what draws it is drawn by, worked out at that
/// moment; a host drawing under it told the same (Tree::finger_areas).
pub fn View::takes(
  self : View,
  areas : (Double, Double, Double) -> Array[(Double, Double, Double, Double)],
) -> View {
  self.takes_so(Areas(areas))
}

///|
/// A node hosting another's (View::hosted): where in it a finger is taken, as what it hosts finds it (`f` given where in
/// it, in its own terms, and the logic's moment), the rest passed to what is under it. What it hosts tells a host
/// drawing under it its own targets.
pub fn View::hosted_takes(self : View, f : (Double, Double, Double) -> Bool) -> View {
  // (a node of the tree's own says where it takes one as rects, View::takes: what a host under it is told the same)
  if self.live() is Some(n) && !n.hosted {
    abort("hosted_takes of a node hosting nothing: View::takes")
  }
  self.takes_so(AsHosted(f))
}

///|
fn View::takes_so(self : View, t : Takes) -> View {
  guard self.live() is Some(n) else { return self }
  // (said, then what read the one said before let go of and what asked told, one change: told, it asks the new)
  n.takes = Some(t)
  self.tree.takes_off(n)
  self
}

///|
/// What reads where node `n` takes a finger, following what it reads (a point followed, a frame painted), follows how
/// it is said (takes_ver: said anew, whichever way, from none on; let go), at every way of saying it: all of it where it
/// says none, as it hosts, by rects (theirs to read by the node's reading: Tree::takes_rects).
fn Tree::takes_said(self : Tree, n : Node) -> Unit {
  ignore(self)
  if @signals.active_sub() is None {
    return
  }
  let v = match n.takes_ver {
    Some(v) => v
    None => {
      let v = @signals.signal(0, same=fn(a, b) { a == b })
      n.takes_ver = Some(v)
      v
    }
  }
  v.get() |> ignore
}

///|
/// Where node `n` takes a finger said anew, or it let go: its reading of it let go (what that read followed no more, at
/// once), what asked told (takes_ver), what is pointed at worked out again.
fn Tree::takes_off(self : Tree, n : Node) -> Unit {
  for e in n.takes_units {
    e.0.dispose()
  }
  n.takes_units = []
  self.hits = self.hits + 1
  match n.takes_ver {
    Some(v) => v.set(@signals.untracked(fn() { v.get() }) + 1)
    None => ()
  }
}

///|
/// What its on_drag set going ended (said anew, let go): a hold on it its own again (Tree::yields), whatever said it.
fn View::drag_ended(self : View) -> Unit {
  let n = self.tree.nodes[self.at]
  n.yields = false
  match n.drag_end {
    Some(end) => {
      n.drag_end = None
      end()
    }
    None => ()
  }
}

///|
/// A finger put down on node `id` to press it (Tree::target_at's Pressed): the hold its till let go (Tree::press_held:
/// whether it still is), called off as any hold is (Tree::hold_lost_in), never handed to another.
pub fn Tree::hold_press(self : Tree, id : NodeId) -> Unit {
  self.held_to(Some(id))
}

///|
/// Whether the hold is still node `id`'s (let go as it is asked: a press let go then is its only if so).
pub fn Tree::press_held(self : Tree, id : NodeId) -> Bool {
  let still = match self.held {
    Some(h) => h == id
    None => false
  }
  if still {
    self.held_to(None)
  }
  still
}

///|
/// The hold (a finger held on a node: Tree::held) called off where that node is `at` or in it, at the moment of what
/// called it off (taking no input from then: leaving, said to take none; the window no longer in front): told so once
/// (Off), at once, whatever frames come; what it set going for the hold (a hold's moment) let go with it.
pub fn Tree::hold_lost_in(self : Tree, at : Int) -> Unit {
  guard self.held is Some(h) else { return }
  let mut i = h.at
  let mut under = false
  while i >= 0 && i < self.nodes.length() {
    if i == at {
      under = true
      break
    }
    i = self.nodes[i].parent
  }
  if !under {
    return
  }
  self.held_to(None)
  let n = self.nodes[h.at]
  if !n.live || n.gen != h.gen {
    return
  }
  match n.on_drag {
    Some(f) => {
      let t = self.cause_now()
      let fingers = self.fingers_off()
      let said = n.drag_said
      @signals.untracked(fn() {
        for g in fingers {
          // (each told only while the node and this on_drag are still its: what one told let go of hears no more)
          guard bound_still(n, h, said) else { break }
          f({
            kind: Off,
            x: 0.0,
            y: 0.0,
            at: t,
            wx: 0.0,
            wy: 0.0,
            ox: 0.0,
            oy: 0.0,
            finger: g,
            since: t,
            w: 0.0,
            h: 0.0,
            vx: 0.0,
            vy: 0.0,
          })
        }
      })
    }
    None => ()
  }
}

///|
/// Laid out as of the logic's moment (Tree::logic_at), what the change under way set so far pulled into its properties (as a
/// computed read in a batch is: nothing told, no structure or effect run before the change ends), the clock put back
/// where it was drawn at: for where things are as an event finds them (View::laid_size, Tree::drag_at).
fn Tree::laid_now(self : Tree) -> Unit {
  if self.last_w <= 0.0 {
    return
  }
  let at = self.logic_at()
  let shown = @signals.untracked(fn() { self.clock.get() })
  // (its clock set to the moment and back: what that tells is no change of its own to settle after)
  let was_standing = self.standing
  self.standing = true
  @signals.untracked(fn() {
    self.clock_to(at)
    self.beat.set(at)
    self.pull()
    self.laid_out(at)
  })
  if shown != at {
    @signals.untracked(fn() {
      self.clock_to(shown)
      self.beat.set(shown)
    })
  }
  self.standing = was_standing
}

///|
/// Node `id` held: `kind` at (x, y) in the window, at `at` (in an event already: that one's moment), as one event of that
/// moment (Tree::event: what had ended by then settled first, where things are brought to then), handed to its on_drag
/// where it is in its own terms then. A down takes the hold; anything else goes only to the node holding it. Where that
/// one takes no press by then (leaving, or what holds it said to take none) the hold is called off, told so once (Off),
/// and nothing more goes to it; let go (View::let_go), it is told nothing. Whether it took the event.
pub fn Tree::drag_at(
  self : Tree,
  id : NodeId,
  kind : DragIs,
  x : Double,
  y : Double,
  at : Double,
  finger? : Int = 0,
  track? : Array[(Double, Double, Double)] = [],
) -> Bool {
  // (one moment for all of it: an event's own, or the one it is told in)
  let t = if self.cause_at >= 0.0 { self.cause_at } else { at }
  if self.cause_at < 0.0 {
    self.bring_to(t)
  }
  let took = Ref(false)
  self.event(t, fn() {
    // (where things are as of then, what the change under way set before it counted: an event inside another too)
    self.laid_now()
    let holding = match self.held {
      Some(h) => h == id
      None => false
    }
    if kind != Down && !holding {
      return
    }
    // (a finger not down on it: none of its)
    if kind != Down && kind != Off && !self.downs.contains(finger) {
      took.val = true
      return
    }
    if id.at < 0 || id.at >= self.nodes.length() {
      self.held_to(None)
      return
    }
    let n = self.nodes[id.at]
    if !n.live || n.gen != id.gen {
      self.held_to(None)
      return
    }
    match n.on_drag {
      None => self.held_to(None)
      Some(f) => {
        let (nx, ny, ns) = self.placed(id.at)
        // (this finger's own events by their own times, from where it went down, each counted once it is taken:
        // `track` its events before this one's, a hold taken over as it moved; a new hold, none of another's)
        let track_now = fn(down : Bool) { self.tracked(finger, down, track, t, x, y) }
        let told = fn(kind : DragIs, finger : Int, v : (Double, Double)) {
          let (vx, vy) = v
          f({
            kind,
            x: (x - nx) / ns,
            y: (y - ny) / ns,
            at: t,
            wx: x,
            wy: y,
            ox: (x - nx) / ns,
            oy: (y - ny) / ns,
            finger,
            since: t,
            w: n.flex.width,
            h: n.flex.height,
            vx,
            vy,
          })
        }
        // (called off, all of it: the hold and the fingers let go of first, then each finger down told so while the node
        // and this on_drag are still its: what one told let go of hears no more)
        let said = n.drag_said
        let off = fn() {
          self.held_to(None)
          let fingers = self.fingers_off()
          for g in fingers {
            guard bound_still(n, id, said) else { break }
            told(Off, g, (0.0, 0.0))
          }
        }
        if self.pressless_at(id.at) {
          if holding {
            off()
          }
          return
        }
        match kind {
          Down if holding =>
            if self.downs.contains(finger) {
              took.val = true
            } else if self.downs.length() < n.fingers {
              // (another finger, as many as it takes)
              self.downs.push(finger)
              took.val = true
              told(Down, finger, track_now(true))
            } else {
              // (one more than it takes: the hold called off)
              off()
            }
          Down => {
            self.held_to(Some(id))
            self.downs.clear()
            self.downs.push(finger)
            took.val = true
            self.held_tracks.clear()
            told(Down, finger, track_now(true))
          }
          Moved => {
            took.val = true
            told(Moved, finger, track_now(false))
          }
          Up => {
            let v = self.tracked(finger, false, track, t, x, y, up=true)
            self.held_tracks.remove(finger)
            self.downs.retain(fn(g) { g != finger })
            if self.downs.is_empty() {
              self.held_to(None)
            }
            took.val = true
            told(Up, finger, v)
          }
          Off => off()
        }
      }
    }
  })
  took.val
}

///|
/// Finger `finger`'s event at `t` at (x, y) in the window counted with its own before it (`down`: it goes down, `track`
/// what it did before this from where it went down, by their own times (this one where it went down among them), else
/// from here): how fast it goes as of it (across, down, points a ms; Tracker::velocity_at). `up`: it goes up there, no
/// sample where it says the last place again (Tracker::up).
fn Tree::tracked(
  self : Tree,
  finger : Int,
  down : Bool,
  track : Array[(Double, Double, Double)],
  t : Double,
  x : Double,
  y : Double,
  up? : Bool = false,
) -> (Double, Double) {
  let (tx, ty) = match self.held_tracks.get(finger) {
    Some(p) if !down => p
    _ => {
      let p = (Tracker::new(), Tracker::new())
      self.held_tracks[finger] = p
      for e in track {
        p.0.add(e.0, e.1)
        p.1.add(e.0, e.2)
      }
      p
    }
  }
  // (down with what it did before: those its events, this one where it went down among them)
  if up {
    tx.up(t, x)
    ty.up(t, y)
  } else if !(down && track.length() > 0) {
    tx.add(t, x)
    ty.add(t, y)
  }
  (tx.velocity_at(t), ty.velocity_at(t))
}

///|
/// Whether node `n` is still `id` and its on_drag still the saying `said` (not let go, not said anew: even with the same
/// function, a saying of its own).
fn bound_still(n : Node, id : NodeId, said : Int) -> Bool {
  n.live && n.gen == id.gen && n.on_drag is Some(_) && n.drag_said == said
}

///|
/// The fingers down on what is held, in the order they went down (none told: the first's), let go of.
fn Tree::fingers_off(self : Tree) -> Array[Int] {
  let was = if self.downs.is_empty() { [0] } else { self.downs.copy() }
  self.downs.clear()
  was
}

///|
/// What a finger held on a node comes to (View::gesture), worked out of its raw events (View::on_drag) alone, each at
/// its own moment: pressed (as it goes down), a tap (let go where it went down, not held long: where it is let go), a
/// hold (still where it went down for so long: at that moment, on the tree's timeline, whatever frames come), or a drag
/// (moved past the slop: begun (Down) where the finger is then, its moves from there, and how it ends: let go, Up;
/// called off, Off). Called off before it was a drag, or let go after a hold, `drag` is told so too; let go past the
/// slop with no move told before, `drag` is told its end alone (Up). One word an event, each with where the finger went
/// down (`ox`, `oy`): what a word does (letting the node go, saying another on_drag) is done before the next event is
/// told, never in the middle of one. `through`: a hold of that long is no hold of its own but what lies under it's, as
/// found as the finger went down (through.mbt): its own told Off then, the finger that one's. `held_first`, asked as a
/// finger goes down: whether it drags this node only once held (its `hold`'s while): moved past the slop before that,
/// it is what lies under it's, as found as it went down, handed on as a hold going through is (its own told Off, the
/// finger that one's where it is then; nothing there to take it, no drag of this one's either).
pub fn View::gesture(
  self : View,
  slop : Double,
  press? : (Drag) -> Unit,
  tap? : (Drag) -> Unit,
  hold? : (Double, (Drag) -> Unit),
  drag? : (Drag) -> Unit,
  through? : Double,
  held_first? : (Drag) -> Bool,
) -> View {
  // (a hold told, or handed through: one way of a hold, its moment the one recognizer's)
  let hold_ms = match (hold, through) {
    (Some((ms, _)), None) | (None, Some(ms)) => Some(ms)
    (None, None) => None
    _ => abort("a gesture's hold told or handed through, not both")
  }
  // (where the finger is, within the slop: where a hold handed through is handed)
  let last = Ref((0.0, 0.0))
  // (what this finger has come to so far: where it went down, whether it moved past the slop, whether held; whether
  // this gesture is over for good (its node's on_drag said anew, the node let go): nothing more told from it)
  let down : Ref[Drag?] = Ref(None)
  let moved = Ref(false)
  let held = Ref(false)
  // (this finger drags it only once held (`held_first`); moved before that and not handed on: none of it its)
  let first = Ref(false)
  let passed = Ref(false)
  let dead = Ref(false)
  let cancel_hold : Ref[() -> Unit] = Ref(fn() {  })
  let over = fn() {
    (cancel_hold.val)()
    cancel_hold.val = fn() {  }
    down.val = None
  }
  let id = self.id()
  // (one word an event, each with where it went down: what a word does is done before the next event is told, so no
  // event is told in two words, and what one word ends ends there)
  let word = fn(f : (Drag) -> Unit, d : Drag, o : Drag) { f({ ..d, ox: o.x, oy: o.y }) }
  self.on_drag(fn(d) {
    if dead.val {
      return
    }
    match d.kind {
      Down => {
        over()
        down.val = Some(d)
        last.val = (d.wx, d.wy)
        moved.val = false
        held.val = false
        passed.val = false
        first.val = match held_first {
          Some(f) => hold_ms is Some(_) && f(d)
          None => false
        }
        // (waiting on a tap, a hold or its own slop: the hold what holds it may take over as it moves, as a press's:
        // Tree::yields; its own once it is a drag or a hold)
        match self.live() {
          Some(n) => n.yields = true
          None => ()
        }
        match press {
          Some(f) => word(f, d, d)
          None => ()
        }
        // (what pressing it did may have ended it: its node let go, said to take no press)
        let still = !dead.val &&
          (match self.tree.held {
            Some(h) => h == id
            None => false
          })
        if !still {
          return
        }
        // (going through: what lies under it found now, kept by who it is)
        if through is Some(_) || first.val {
          self.tree.through_found(id, d.wx, d.wy, d.since, d.finger)
        }
        match hold_ms {
          Some(ms) => {
            // (as long since the finger went down (a hold handed on from what held it first counts from then), never
            // before this down: one handed on later than that is held now, at the moment it was handed)
            let due = if d.since + ms > d.at { d.since + ms } else { d.at }
            cancel_hold.val = self.at_moment(due, fn() {
              let holding = match self.tree.held {
                Some(h) => h == id
                None => false
              }
              if !dead.val && holding && down.val is Some(o) && !moved.val {
                match hold {
                  Some((_, f)) => {
                    held.val = true
                    // (held: the hold its own from now)
                    match self.live() {
                      Some(n) => n.yields = false
                      None => ()
                    }
                    word(f, { ..o, at: due }, o)
                  }
                  // (handed through: its own hold ended by it, Off, the finger what lies under it's; nothing there to take
                  // it then, a hold still, no tap)
                  None => if !self.tree.hand_through(id, last.val.0, last.val.1) { held.val = true }
                }
              }
            })
          }
          None => ()
        }
      }
      Moved =>
        match down.val {
          Some(o) => {
            // (past the slop by how far the finger itself went: the drag begins where it is now)
            if !moved.val && ((d.wx - o.wx).abs() > slop || (d.wy - o.wy).abs() > slop) {
              moved.val = true
              match self.live() {
                Some(n) => n.yields = false
                None => ()
              }
              (cancel_hold.val)()
              cancel_hold.val = fn() {  }
              // (dragging it only once held, moved before: its press called off, once (Off), then what lies under it's,
              // handed on now; nothing there to take it, none of what follows this one's)
              if first.val && !held.val {
                passed.val = true
                match drag {
                  Some(f) => word(f, { ..d, kind: Off }, o)
                  None => ()
                }
                self.tree.hand_through(id, d.wx, d.wy, moved=true) |> ignore
                return
              }
              match drag {
                Some(f) => word(f, { ..d, kind: Down }, o)
                None => ()
              }
            } else if moved.val && !passed.val {
              match drag {
                Some(f) => word(f, d, o)
                None => ()
              }
            } else {
              last.val = (d.wx, d.wy)
            }
          }
          None => ()
        }
      Up | Off => {
        match self.live() {
          Some(n) => n.yields = false
          None => ()
        }
        let was = down.val
        let went = moved.val
        let was_held = held.val
        let was_passed = passed.val
        let was_first = first.val
        over()
        passed.val = false
        match was {
          // (moved before it was held, when it drags only so: called off then, none of what follows this one's)
          Some(_) if was_passed => ()
          // (let go past the slop with no move told, before the hold of one it drags only once held: its press called
          // off, no drag of it, no tap)
          Some(o) if was_first &&
            !was_held &&
            d.kind == Up &&
            ((d.wx - o.wx).abs() > slop || (d.wy - o.wy).abs() > slop) =>
            match drag {
              Some(f) => word(f, { ..d, kind: Off }, o)
              None => ()
            }
          // (let go, or called off, after a drag or a hold: its end, where it went down said with it)
          Some(o) if went || was_held || d.kind == Off =>
            match drag {
              Some(f) => word(f, d, o)
              None => ()
            }
          // (let go past the slop with no move said before: a drag that ends as it is told, in one word: its end, where
          // it went down with it, how far the finger went theirs to work out)
          Some(o) if (d.wx - o.wx).abs() > slop || (d.wy - o.wy).abs() > slop =>
            match drag {
              Some(f) => word(f, d, o)
              None => ()
            }
          Some(o) => {
            // (a tap: told the tree, after what it does, for the window's taps: Tree::gesture_tapped)
            match tap {
              Some(f) if !self.tree.taps_withheld => word(f, d, o)
              _ => ()
            }
            self.tree.gesture_tapped = true
          }
          None => ()
        }
      }
    }
  })
  |> ignore
  // (said anew or let go: its hold's moment let go, nothing more told)
  guard self.live() is Some(n) else { return self }
  n.drag_end = Some(fn() {
    dead.val = true
    over()
  })
  self
}

///|
/// `f` run once as it is let go (what it holds that is no effect: a computed to dispose, a resource to close).
pub fn View::owns(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.drops[n.drop_next] = f
  n.drop_next = n.drop_next + 1
  self
}

///|
/// `stop` kept as one it lets go of as it goes (View::owns), and what lets go of that keeping again: for what ends
/// before it does (a moment's work done or called off), nothing of it kept by it after.
fn View::owns_while(self : View, stop : () -> Unit) -> () -> Unit {
  guard self.live() is Some(n) else { return fn() {  } }
  let key = n.drop_next
  n.drop_next = n.drop_next + 1
  n.drops[key] = stop
  let tree = self.tree
  let at = self.at
  let gen = self.gen
  fn() {
    let m = tree.nodes[at]
    if m.gen == gen {
      m.drops.remove(key)
    }
  }
}

///|
/// How many things it lets go of as it goes are kept now (View::owns, a moment's work said, a stretch of steps).
pub fn View::owned_count(self : View) -> Int {
  match self.live() {
    Some(n) => n.drops.length()
    None => 0
  }
}

///|
/// Lets it go: what it holds first, then its scope stopped (what it was made with: its bindings, its effects, their
/// cleanups run), what goes with it run, its callback and measure dropped, its index free.
fn View::let_go(self : View) -> Unit {
  guard self.live() is Some(n) else { return }
  // (what the pointer is over let go of, it or one it holds: pointed at no more, what holds it told so while it is
  // still held by them, View::pointed_in; what it is over then the host's to find again, as what takes it changed)
  if self.tree.pointed_within_at(self.at) {
    self.tree.pointed_to(None)
  }
  // (what it holds as this begins, each by its handle: one's going may take another out of it (View::lives_with, the
  // tip of a row held beside it in one layer), which is then let go already, its handle on nothing)
  let kids = n.kids.map(fn(k) { self.tree.handle(k) })
  n.kids.clear()
  for k in kids {
    k.let_go()
  }
  n.live = false
  match self.tree.modals.search(self.at) {
    Some(i) => self.tree.modals.remove(i) |> ignore
    None => ()
  }
  match n.stop {
    Some(stop) => stop()
    None => ()
  }
  n.stop = None
  n.owner = None
  // (where it takes a finger let go of with it: what read it told at once, following what it read no more)
  n.takes = None
  self.tree.takes_off(n)
  n.takes_ver = None
  let props = n.props.values().collect()
  n.props.clear()
  for stop in props {
    stop()
  }
  let drops = n.drops.values().collect()
  n.drops.clear()
  for f in drops {
    f()
  }
  n.on_press = None
  n.top_row = false
  n.moves_window = false
  n.on_menu = None
  n.on_wheel = None
  n.on_key = None
  n.on_back = None
  n.on_back_step = None
  // (a back gesture it held: let go of with it, nothing more told it)
  match self.tree.backing {
    Some((b, _)) if b.at == self.at && b.gen == self.gen => self.tree.backing = None
    _ => ()
  }
  n.said = None
  n.said_hidden = false
  n.bones = 0L
  n.bone_whole = false
  n.cut = false
  n.pressed_cell = None
  n.pointed_cell = None
  n.on_pointer_moved = None
  n.pointed_in_cell = None
  // (the focus on it: let go of with it, what has it told so)
  self.tree.focus_lost_in(self.at)
  n.focusable = false
  n.focus_typing = false
  n.focus_keys = 0
  n.focus_tab = true
  n.tab_by_stop = false
  n.input_cell = None
  n.cursor = None
  n.beside = None
  n.beside_last = None
  n.beside_point = None
  n.focused_cell = None
  n.focus_shown_cell = None
  n.size_cell = None
  n.rect_cell = None
  n.drawn_rect_cell = None
  n.went_cell = None
  n.shows = None
  n.shows_across = false
  n.claims = None
  n.claims_from = None
  n.bounds_input = false
  n.drawn_clear = None
  n.bar_near = 0.0
  n.bar_across = false
  n.points = false
  n.bar_near_cell = None
  self.drag_ended()
  n.on_drag = None
  n.drag_said = n.drag_said + 1
  n.takes = None
  // (held: let go of with it, nothing more told it, nothing of it handed to what is made in its place)
  match self.tree.held {
    Some(h) if h.at == self.at && h.gen == self.gen => self.tree.held_to(None)
    _ => ()
  }
  n.flex.measure = None
  n.flex.children.clear()
  n.parent = -1
  n.content = None
  if self.tree.hosting == self.at {
    self.tree.hosting = -1
  }
  self.tree.removed.push({ at: self.at, gen: self.gen })
  // (a row known by a name for its key no longer this node: the name to none till its next is made, View::row_known_as)
  match self.tree.nodes[self.at].row_id {
    Some(id) if self.tree.rows_known.get(id) == Some(self.at) => self.tree.rows_known.remove(id)
    _ => ()
  }
  self.tree.free.push(self.at)
  self.tree.order_marked()
  self.tree.work.let_go = self.tree.work.let_go + 1
  self.tree.hits = self.tree.hits + 1
}

///|
/// A node holding what comes and goes (show, pick, each), with no box of its own.
fn View::slot(self : View) -> View {
  guard self.live() is Some(n) else { return self.tree.none() }
  let v = self.tree.made(self.at)
  self.tree.nodes[v.at].slot = true
  n.kids.push(v.at)
  if self.at == 0 {
    self.tree.top_last()
  }
  v
}

///|
/// The boxes node `at` lays out as its own, in order: its own, or a slot's, those of what it holds.
fn Tree::boxes(self : Tree, at : Int, into : Array[@flex.Node]) -> Unit {
  let n = self.nodes[at]
  // (one as wide as what it goes beside laid out alone, after its anchor: none of what holds it lays it out, View::beside)
  if n.beside is Some(b) && b.as_wide {
    return
  }
  if n.slot {
    for k in n.kids {
      self.boxes(k, into)
    }
  } else {
    into.push(n.flex)
  }
}

///|
/// A newly made box follows what its parent holds. Through slots, it follows all of the layout parent's boxes only if
/// every slot is last among its siblings; otherwise their order is found again.
fn View::box_appended(self : View, child : Int) -> Unit {
  // The root tells the host before linking its new box. That telling may synchronously make another box.
  if self.at == 0 {
    self.boxes_again()
    return
  }
  let mut at = self.at
  while self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
    let n = self.tree.nodes[at]
    let parent = n.parent
    let siblings = self.tree.nodes[parent].kids
    // Tree::boxes omits a slot made as wide as its anchor, along with everything it holds.
    if (n.beside is Some(b) && b.as_wide) ||
      parent == 0 ||
      siblings.length() == 0 ||
      siblings[siblings.length() - 1] != at {
      self.boxes_again()
      return
    }
    at = parent
  }
  if self.tree.boxes_deferred is Some(batch) && batch.pending.contains(self.tree.handle(at).id()) {
    self.boxes_again()
    return
  }
  self.tree.nodes[at].flex.children.push(self.tree.nodes[child].flex)
  self.tree.layout_marked_at(at)
  self.tree.order_marked()
  self.tree.modals_told()
}

///|
/// Put the layout boxes held by a node in the tree's order.
fn Tree::boxes_now(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  let all : Array[@flex.Node] = []
  for k in n.kids {
    self.boxes(k, all)
  }
  n.flex.children.clear()
  for b in all {
    n.flex.children.push(b)
  }
}

///|
/// Reconcile child lists before anything measures them; the changes have already marked layout and order.
fn Tree::boxes_flush(self : Tree) -> Unit {
  match self.boxes_deferred {
    Some(batch) => {
      let ids = batch.pending.iter().collect()
      batch.pending.clear()
      for id in ids {
        if self.alive_id(id) { self.boxes_now(id.at) }
      }
    }
    None => ()
  }
}

///|
/// The node that lays out what `self` holds (itself, or the first node above its slots).
fn View::boxes_owner(self : View) -> Int {
  let mut at = self.at
  while self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
    at = self.tree.nodes[at].parent
  }
  at
}

///|
/// What it holds changed (made, let go, moved): its layout boxes put in order and layout and order marked.
fn View::boxes_again(self : View) -> Unit {
  let at = self.boxes_owner()
  match self.tree.boxes_deferred {
    Some(batch) => batch.pending.remove(self.tree.handle(at).id())
    None => ()
  }
  self.tree.boxes_now(at)
  self.tree.layout_marked_at(at)
  self.tree.order_marked()
  // (what is drawn over what, among what holds it, changed: whether a modal layer is over what is held)
  self.tree.modals_told()
}

///|
/// A removal during a keyed update: keep callbacks and layout marks at their usual moments, and put the layout list
/// together before it is next read. Each individual removal remains visible through the tree itself.
fn View::boxes_removed(self : View) -> Unit {
  match self.tree.boxes_deferred {
    Some(batch) if self.tree.layouts_active == 0 && batch.slot == self.id() => {
      let at = self.boxes_owner()
      batch.pending.add(self.tree.handle(at).id())
      self.tree.layout_marked_at(at)
      self.tree.order_marked()
      self.tree.modals_told()
    }
    _ => self.boxes_again()
  }
}

///|
/// What node `at` holds put in another order: drawn so, told the scene that draws it (Tree::take_ordered) as the node
/// that holds them in its order (itself, or the first not a slot holding it).
fn Tree::ordered_at(self : Tree, at : Int) -> Unit {
  let mut at = at
  while self.nodes[at].slot && self.nodes[at].parent >= 0 {
    at = self.nodes[at].parent
  }
  let id = { at, gen: self.nodes[at].gen }
  if !self.ordered_pending.contains(id) {
    self.ordered_pending.push(id)
  }
}

///|
/// Node `v` let go and taken out of what it holds.
fn View::drop(self : View, v : View) -> Unit {
  v.let_go()
  guard self.live() is Some(n) else { return }
  match n.kids.search(v.at) {
    Some(i) => n.kids.remove(i) |> ignore
    None => ()
  }
  self.boxes_removed()
}

///|
/// `then`'s node while `when` holds, made as it comes to and let go as it stops (what it made with it too: its scope).
pub fn View::show(self : View, when : () -> Bool, then : (View) -> Unit, leave? : Double = 0.0) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot()
  let had : Ref[View?] = Ref(None)
  // (the one leaving, shown again as it leaves: the same node, come back)
  let gone : Ref[View?] = Ref(None)
  let stop = slot.tree.structured(when, fn(on) {
    guard slot.alive() else { return }
    match (on, had.val) {
      (true, None) => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        match gone.val {
          Some(g) if g.alive() && slot.tree.nodes[g.at].left_at >= 0.0 => {
            slot.come_back(g)
            had.val = Some(g)
          }
          _ => had.val = Some(slot.box(then))
        }
        gone.val = None
      }
      (false, Some(v)) => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        slot.leave(v, leave)
        had.val = None
        gone.val = if leave > 0.0 { Some(v) } else { None }
      }
      _ => ()
    }
  })
  slot.owns(stop) |> ignore
}

///|
/// A node made by `make` for what `which` is, made anew (the one before let go) as that changes, kept as it does not.
pub fn[K : Eq] View::pick(self : View, which : () -> K, make : (View, K) -> Unit) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot()
  let had : Ref[(K, View)?] = Ref(None)
  let stop = slot.tree.structured(which, fn(k) {
    guard slot.alive() else { return }
    match had.val {
      Some((was, _)) if was == k => ()
      _ => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        match had.val {
          Some((_, v)) => slot.drop(v)
          None => ()
        }
        let v = slot.box(fn(v) { make(v, k) })
        had.val = Some((k, v))
      }
    }
  })
  slot.owns(stop) |> ignore
}

///|
/// A node for each of `items` by its key, made as its key comes, kept while it stays, moved as the order changes, let
/// go as it goes. Each is given its item as a signal of its own, set again only as the item comes out otherwise (by
/// its data, not by which object it is): a row whose item is the same runs nothing.
pub fn[T : Eq, K : Hash + Eq] View::each(
  self : View,
  items : () -> Array[T],
  key : (T) -> K,
  row : (View, @signals.Signal[T]) -> Unit,
  leave? : Double = 0.0,
) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot()
  let rows : Map[K, (View, @signals.Signal[T])] = Map([])
  // (the rows leaving, by key: one whose key comes back as it leaves is the same row, come back)
  let gone_rows : Map[K, (View, @signals.Signal[T])] = Map([])
  let stop = slot.tree.structured(items, fn(all) {
    guard slot.live() is Some(sn) else { return }
    slot.tree.work.structure = slot.tree.work.structure + 1
    let seen : Map[K, Bool] = Map([])
    let order : Array[Int] = []
    @signals.start_batch()
    for it in all {
      let k = key(it)
      seen[k] = true
      match rows.get(k) {
        Some((v, item)) => {
          item.set(it)
          order.push(v.at)
        }
        None =>
          match gone_rows.get(k) {
            Some((v, item)) if v.alive() && slot.tree.nodes[v.at].left_at >= 0.0 => {
              gone_rows.remove(k)
              slot.come_back(v)
              item.set(it)
              rows[k] = (v, item)
              order.push(v.at)
            }
            _ => {
              gone_rows.remove(k)
              let item = @signals.signal(it, same=fn(a, b) { a == b })
              let v = slot.box(fn(v) {
                // (a row by its key: what is made in it known by it, View::row_place)
                v.tree.nodes[v.at].each_row = true
                row(v, item)
              })
              rows[k] = (v, item)
              order.push(v.at)
            }
          }
      }
    }
    @signals.end_batch()
    let gone : Array[K] = []
    let mut owns_boxes = false
    for k, r in rows {
      if !seen.contains(k) {
        if leave <= 0.0 && slot.tree.layouts_active == 0 && slot.tree.boxes_deferred is None {
          slot.tree.boxes_deferred = Some({ slot: slot.id(), pending: Set::new() })
          owns_boxes = true
        }
        gone.push(k)
        slot.leave(r.0, leave)
        if leave > 0.0 {
          gone_rows[k] = r
        }
      }
    }
    if leave <= 0.0 && gone.length() > 0 {
      slot.tree.boxes_flush()
    }
    if owns_boxes {
      slot.tree.boxes_deferred = None
    }
    for k in gone {
      rows.remove(k)
    }
    // (those whose leaving ended, let go: forgotten)
    let ended = gone_rows.iter().filter(fn(e) { !e.1.0.alive() }).map(fn(e) { e.0 }).collect()
    for k in ended {
      gone_rows.remove(k)
    }
    // (what is leaving kept where it was, after what was before it)
    let tree = slot.tree
    for j, at in sn.kids {
      let m = tree.nodes[at]
      if m.live && m.left_at >= 0.0 && m.parent == slot.at {
        let before = if j == 0 { None } else { order.search(sn.kids[j - 1]) }
        match before {
          Some(i) => order.insert(i + 1, at)
          None => order.insert(0, at)
        }
      }
    }
    let kids = sn.kids
    let moved = order.length() != kids.length() || order.mapi(fn(i, v) { kids[i] != v }).contains(true)
    if moved {
      kids.clear()
      for v in order {
        kids.push(v)
      }
      slot.boxes_again()
      tree.ordered_at(slot.at)
    }
  })
  slot.owns(stop) |> ignore
}

///|
/// The moment the change being made now was told (Tree::queued: as its cause set it, whatever frame takes it), else
/// the clock's now: where what it sets going starts.
fn Tree::cause_now(self : Tree) -> Double {
  if self.cause_at >= 0.0 {
    self.cause_at
  } else {
    self.logic
  }
}

///|
/// What reads how far node `n` is gone told (it started or stopped leaving or coming back).
fn told_going(n : Node) -> Unit {
  match n.going {
    Some(s) => s.set(@signals.untracked(fn() { s.get() }) + 1)
    None => ()
  }
}

///|
/// How far node `n` is gone at `now` (0 to 1), as it leaves or comes back.
fn gone_at(n : Node, now : Double) -> Double {
  let f = if n.left_at >= 0.0 {
    if n.span <= 0.0 {
      1.0
    } else {
      (now - n.left_at) / n.span
    }
  } else if n.back_at >= 0.0 && n.span > 0.0 {
    n.back_from - (now - n.back_at) / n.span
  } else {
    0.0
  }
  if f < 0.0 {
    0.0
  } else if f > 1.0 {
    1.0
  } else {
    f
  }
}

///|
/// Node `v` (one this holds) going: leaving for `ms` from its cause's moment (still drawn and laid out, no longer
/// pressed; what reads how far it is gone told: View::going), let go as that ends (Tree::frame); let go at once where
/// `ms` is 0. One coming back as it goes leaves from as far as it came back to.
fn View::leave(self : View, v : View, ms : Double) -> Unit {
  if ms <= 0.0 {
    self.drop(v)
    return
  }
  guard v.live() is Some(n) else { return }
  let now = self.tree.cause_now()
  let p = gone_at(n, now)
  n.span = ms
  n.left_at = now - p * ms
  n.back_at = -1.0
  told_going(n)
  // (leaving, it takes no input: a finger held on it or in it let go of now)
  self.tree.hold_lost_in(v.at)
  self.tree.focus_lost_in(v.at)
  self.tree.back_lost_in(v.at)
  self.tree.modals_told()
  self.tree.due_leaving(v.id())
  self.tree.marked()
}

///|
/// Node `v`, leaving, shown again: the same node, here again (pressed again) from its cause's moment, how far it is gone
/// going back to 0 as fast as it went.
fn View::come_back(self : View, v : View) -> Unit {
  guard v.live() is Some(n) && n.left_at >= 0.0 else { return }
  let now = self.tree.cause_now()
  n.back_from = gone_at(n, now)
  n.back_at = now
  n.left_at = -1.0
  told_going(n)
  // (beside its anchor again, where that is now: View::beside)
  if n.beside is Some(_) {
    self.tree.place_marked_at(v.at)
  }
  // (a modal layer back: over what is held again)
  self.tree.modals_told()
  self.tree.marked()
}

///|
/// How far it is gone, from 0 (here) to 1 (its leaving over): what reads it is told as it starts or stops leaving or
/// coming back, and goes with the clock while it does (a look fading it out, a place taking it away), from the moment
/// its cause set it going, whatever frames come between.
pub fn View::going(self : View) -> Double {
  guard self.live() is Some(n) else { return 1.0 }
  let s = match n.going {
    Some(s) => s
    None => {
      let s = @signals.signal(0, same=fn(a, b) { a == b })
      n.going = Some(s)
      s
    }
  }
  s.get() |> ignore
  if n.left_at < 0.0 && n.back_at < 0.0 {
    return 0.0
  }
  gone_at(n, self.tree.drawn_at())
}

///|
/// When its own leaving ends, as it was told to leave (View::leave: let go then), -1 where it is not leaving.
pub fn View::leaves_at(self : View) -> Double {
  guard self.live() is Some(n) else { return -1.0 }
  if n.left_at >= 0.0 {
    leave_ends(n)
  } else {
    -1.0
  }
}

///|
/// Whether it is leaving, or what holds it is: no longer pressed. Followed: what reads it told as it or what holds it
/// starts leaving and as it comes back (what View::going reads, and not the clock: a reaction on it runs then, not as
/// the frames come).
pub fn View::leaving(self : View) -> Bool {
  guard self.live() is Some(_) else { return true }
  let mut i = self.at
  while i >= 0 {
    let n = self.tree.nodes[i]
    let s = match n.going {
      Some(s) => s
      None => {
        let s = @signals.signal(0, same=fn(a, b) { a == b })
        n.going = Some(s)
        s
      }
    }
    s.get() |> ignore
    i = n.parent
  }
  self.tree.leaving_at(self.at)
}

///|
/// Whether node `at` takes no press: it, or what holds it, leaving or said to take none (View::presses).
fn Tree::pressless_at(self : Tree, at : Int) -> Bool {
  // (under the topmost modal layer, not in it: none)
  !self.allows_at(at) || self.pressless_own_at(at)
}

///|
/// Whether node `at` or what holds it is leaving, said to take no press or left out of its row (View::drops: laid out
/// nowhere), whatever a modal layer says of it.
fn Tree::pressless_own_at(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    // (in its bones: not there yet, View::bones)
    if self.nodes[i].left_at >= 0.0 || self.nodes[i].inert || self.nodes[i].out || self.nodes[i].bones != 0L {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
///|
/// Whether node `at` or what holds it is left out of its row as it was last laid out (View::drops): none of it in the
/// scene, nothing of it drawn, pressed, read out or found where it is.
fn Tree::out_at(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    if self.nodes[i].out {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// Whether node `id` is leaving, or what holds it is (drawn on its way out, pressed no more: View::leaving), as the
/// tree is now; a node let go of, not.
pub fn Tree::leaving(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  n.live && n.gen == id.gen && self.leaving_at(id.at)
}

///|
fn Tree::leaving_at(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    if self.nodes[i].left_at >= 0.0 {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// When node `n`'s leaving or coming back ends (-1: neither).
fn leave_ends(n : Node) -> Double {
  if n.left_at >= 0.0 {
    n.left_at + n.span
  } else if n.back_at >= 0.0 {
    n.back_at + n.back_from * n.span
  } else {
    -1.0
  }
}

///|
/// Whether anything reads the clock (a look by the time, a node leaving whose look reads how far it is gone): each
/// frame draws something new as the clock goes, so what hosts the tree draws them one after another; else nothing
/// moves, and at most a moment is waited for (Tree::wake).
pub fn Tree::clock_read(self : Tree) -> Bool {
  // (what goes by steps asks for no frames of its own: its next step is a moment woken for, Tree::wake; what it
  // changes that shows asks as any change does)
  self.clock.watched()
}

///|
/// The soonest moment anything is due (a leaving or coming back ending, a step), if anything is: what hosts the tree
/// has a frame drawn then.
pub fn Tree::wake(self : Tree) -> Double? {
  let mut soonest : Double? = None
  for d in self.timeline {
    let at = self.due_at(d)
    if at >= 0.0 {
      soonest = match soonest {
        Some(s) if s <= at => Some(s)
        _ => Some(at)
      }
    }
  }
  soonest
}

///|
/// The soonest moment what is yet to be done is done with, if anything is: a leaving or coming back ending, a moment's
/// `f` not said `later` (View::at_moment), what goes by steps at its last step (View::steps: a stretch, its steps all
/// done by then; Tree::wake still each step's). What a test's run goes on to and is not idle before (an old view's wake,
/// Ctx::wake_in, as it is). Not what is said `later`, nor a wait drawn by a cycle (View::cycle: no end of its own).
pub fn Tree::wake_waited(self : Tree) -> Double? {
  let mut soonest : Double? = None
  for d in self.timeline {
    let at = match d {
      Steps(s, _) => if s.live.val && s.k < s.count { stepped_at(s, s.count - 1) } else { -1.0 }
      Once(o, _) if o.later => -1.0
      _ => self.due_at(d)
    }
    if at >= 0.0 {
      soonest = match soonest {
        Some(s) if s <= at => Some(s)
        _ => Some(at)
      }
    }
  }
  soonest
}

///|
/// The moment of the event being handled (Tree::event), if one is: what it does is of that moment, taken once.
pub fn Tree::moment(self : Tree) -> Double? {
  if self.cause_at >= 0.0 {
    Some(self.cause_at)
  } else {
    None
  }
}

///|
/// The time now, as a change is told: the moment a frame or the clock brings the tree to while it does (what is told
/// then is of it, Tree::brought), else the host's, else the clock's. The one place the host's clock is read.
fn Tree::time_now(self : Tree) -> Double {
  if self.bringing_at >= 0.0 {
    return self.bringing_at
  }
  match self.time {
    Some(f) => f()
    None => self.logic
  }
}

///|
/// An event from outside handled at `at` (its own time) by `f`: what had ended by then settled first, `f` run outside
/// any tracking as one change with `at` as its cause's moment (what it shows or lets go, it does as of then).
pub fn Tree::event(self : Tree, at : Double, f : () -> Unit) -> Unit {
  self.event_said(at, fn() {  }, f)
}

///|
/// One event at `at` whose own facts (`said`: what it came by, as a host says it) are so as of its moment: what was due
/// by then done first (seeing what was so before it), then `said` committed and told (what follows it brought to it,
/// the event's moment their cause), then `f` taken as Tree::event takes it, finding things as they are with it. Inside
/// another event, both in that one's, as one change.
pub fn Tree::event_said(self : Tree, at : Double, said : () -> Unit, f : () -> Unit) -> Unit {
  // (in an event already: its moment, settled as it began)
  if self.cause_at >= 0.0 {
    @signals.start_batch()
    @signals.untracked(said)
    @signals.untracked(f)
    @signals.end_batch()
    return
  }
  self.settle(at)
  let was = self.cause_at
  self.cause_at = at
  self.committing += 1
  // (its facts told before it is taken: what is bound to them so as it is found)
  @signals.start_batch()
  @signals.untracked(said)
  @signals.end_batch()
  @signals.start_batch()
  @signals.untracked(f)
  @signals.end_batch()
  self.committing -= 1
  self.modals_settled()
  // (what waits for it committed whole, each a change of its own of this moment, in order)
  while self.afters.length() > 0 {
    let next = self.afters.remove(0)
    self.committing += 1
    @signals.start_batch()
    @signals.untracked(next)
    @signals.end_batch()
    self.committing -= 1
    self.modals_settled()
  }
  self.cause_at = was
  // (where things stand once it is told whole, for the next change: Tree::settle_after_change)
  if was < 0.0 {
    self.settle_now(at)
  }
}

///|
/// Once the change under way is told whole (a signal set outside, a batch of them, an event, a moment come on the
/// timeline): where things stand then laid out and placed, where something asks (View::laid_before_causes), so that
/// the next change, whenever it comes and whether a frame is drawn first or not, finds them placed as this one left
/// them: what moves from there for that change's cause goes from there. Asked once for each change.
fn Tree::settle_after_change(self : Tree, at : Double) -> Unit {
  // (what laying out and placing things itself tells, its clock set to the change's moment and back, no change of its
  // own to settle after)
  if self.before_causes <= 0 || self.standing {
    return
  }
  // (of the change's own moment: the latest told in it)
  self.settle_at = if self.settle_asked && self.settle_at > at { self.settle_at } else { at }
  if self.settle_asked {
    return
  }
  self.settle_asked = true
  // (once all that waits for the change is done too: what it set going measures where things stand, and what that
  // pulls is told then, View::laid_before_causes's own way (moves_together); the same one change settled once,
  // whichever order its effects ran in)
  @signals.after_all_flushed(fn() {
    self.settle_asked = false
    // (inside an event or a moment's change: done as that one ends, Tree::event_said, Tree::advance_loop)
    if self.committing > 0 || self.cause_at >= 0.0 || self.standing {
      return
    }
    self.settle_now(self.settle_at)
  })
}

///|
/// Where things stand as of `at` laid out and placed now, where something asks (View::laid_before_causes): what was told
/// worked out, laid out and placed as a frame would, nothing drawn.
fn Tree::settle_now(self : Tree, at : Double) -> Unit {
  if self.before_causes <= 0 || self.standing || self.last_w <= 0.0 {
    return
  }
  if !(self.layout_due || !self.places_due.is_empty() || !self.bindings_due.is_empty() || !self.pulls_marked.is_empty()) {
    return
  }
  self.standing = true
  self.work.settles = self.work.settles + 1
  let shown = @signals.untracked(fn() { self.clock.get() })
  // (a change told by what a frame's layout told (a size, a place), settled within that layout: at the frame's moment,
  // as that layout places all of it, never at the change's own between its passes, the clock set back and forth: what
  // is placed by the clock (a page sliding in) told at the one moment and then the other, pass after pass)
  let at = if self.laid_passes > 0 && at < shown { shown } else { at }
  // A due change settles at its own moment, before the outer advance reaches its destination. Its looks must
  // see that same logical moment when they decide whether a finished way still needs the drawing clock.
  let cause = self.cause_at
  self.cause_at = at
  @signals.untracked(fn() {
    self.clock_to(at)
    self.beat.set(at)
    self.pull()
    self.laid_out(at)
  })
  self.cause_at = cause
  if shown != at {
    @signals.untracked(fn() {
      self.clock_to(shown)
      self.beat.set(shown)
    })
  }
  self.standing = false
  self.withins_restored()
}

///|
/// `f` done once the event being taken now is committed whole (what it told brought about: nodes shown, gone, made anew,
/// a modal layer opened), as a change of its own of that moment; taken in none, now.
fn Tree::after_event(self : Tree, f : () -> Unit) -> Unit {
  if self.cause_at >= 0.0 {
    self.afters.push(f)
  } else {
    f()
  }
}

///|
/// An event from outside about to be handled at `at` (its own time): the tree advanced to it first (Tree::advance).
pub fn Tree::settle(self : Tree, at : Double) -> Unit {
  self.advance(at)
}

///|
/// What is due at a moment of its own (Tree::advance): a node's leaving or coming back ending; a step of what goes by
/// steps. Each with its place in the order told.
enum Due {
  Leaves(NodeId, Int)
  Steps(Stepper, Int)
  Once(Once, Int)
}

///|
/// Something to be done once at a moment (View::at_moment): `f`, at `at`, if still `live`.
struct Once {
  at : Double
  f : () -> Unit
  live : Ref[Bool]
  /// not waited for (View::at_moment's `later`)
  later : Bool
}

///|
/// What goes by steps (View::steps): `step` run with each step's number and moment, at the one clock's ticks at
/// `per_second` from tick `first`, `count` of them, `k` taken; stopped (`live`), no more.
struct Stepper {
  /// the tick of the one clock its first step is at (its rate's ticks from the clock's 0, which a host's monotonic
  /// clock puts hours back: Int64; the first after its cause)
  first : Int64
  per_second : Int
  count : Int
  mut k : Int
  step : (Int, Double) -> Unit
  live : Ref[Bool]
}

///|
/// When `d` is due (-1: no more: let go, stopped, done).
fn Tree::due_at(self : Tree, d : Due) -> Double {
  match d {
    Leaves(id, _) => {
      let n = self.nodes[id.at]
      if n.live && n.gen == id.gen {
        leave_ends(n)
      } else {
        -1.0
      }
    }
    Steps(s, _) =>
      if s.live.val && s.k < s.count {
        stepped_at(s, s.k)
      } else {
        -1.0
      }
    Once(o, _) => if o.live.val { o.at } else { -1.0 }
  }
}

///|
/// What was due by `live` (View::at_moment, View::steps), called off or run out: taken off the timeline at once, what
/// it would have done let go with it (nothing of it held till the clock next comes by).
fn Tree::unschedule(self : Tree, live : Ref[Bool]) -> Unit {
  self.timeline.retain(fn(d) {
    match d {
      Steps(s, _) => !physical_equal(s.live, live)
      Once(o, _) => !physical_equal(o.live, live)
      Leaves(_, _) => true
    }
  })
}

///|
/// How many things are due on its timeline (each held till it is done or called off).
pub fn Tree::due_count(self : Tree) -> Int {
  self.timeline.length()
}

///|
/// Node `id`'s leaving or coming back ending, due in its turn (once).
fn Tree::due_leaving(self : Tree, id : NodeId) -> Unit {
  for d in self.timeline {
    if d is Leaves(i, _) && i == id {
      return
    }
  }
  self.timeline.push(Leaves(id, self.told))
  self.told = self.told + 1
}

///|
/// The tree's logic advanced to `upto`: what is due by then done one at a time, in the order of the moments it is due
/// at (of those due together, the first told first), each as of its moment (its cause's, for what it does): a leaving
/// over let go, a coming back done, a step of what goes by steps taken (each of them, none skipped, none run as a
/// larger one). What one does that is due by `upto` too (a cleanup setting another leaving, a step's count) is done in
/// its turn. Frames, inputs and the host's calls each advance it to their moment and no further: how often they come
/// changes nothing of what it does.
pub fn Tree::advance(self : Tree, upto : Double) -> Unit {
  self.advance_logic(upto)
  self.advance_clock(upto)
}

///|
/// What was due before a new change, committed before that change reads or writes anything. The drawing clock is
/// told separately so a structure can tell it together with its own change (Tree::at_cause).
fn Tree::advance_logic(self : Tree, upto : Double) -> Unit {
  // (one thing due at a time, all it does committed before the next is chosen: asked again while one is being done (a
  // structure it changed committing), the loop doing it goes on from where it is once that one is done)
  if self.advancing {
    return
  }
  self.advancing = true
  self.advance_loop(upto)
  self.advancing = false
  // (where its logic now stands: what is said next is of this moment, not of the last frame; what is drawn is drawn
  // at no moment before it)
  if upto > self.logic {
    self.logic = upto
  }
}

///|
fn Tree::advance_clock(self : Tree, upto : Double) -> Unit {
  if !self.advancing && upto > @signals.untracked(fn() { self.clock.get() }) {
    self.at(upto)
  }
}

///|
fn Tree::advance_loop(self : Tree, upto : Double) -> Unit {
  while true {
    let mut next = -1
    let mut next_at = 0.0
    let mut next_seq = 0
    let mut i = 0
    while i < self.timeline.length() {
      let d = self.timeline[i]
      let at = self.due_at(d)
      if at < 0.0 {
        self.timeline.remove(i) |> ignore
        continue
      }
      let seq = match d {
        Leaves(_, s) => s
        Steps(_, s) => s
        Once(_, s) => s
      }
      if at <= upto && (next < 0 || at < next_at || (at == next_at && seq < next_seq)) {
        next = i
        next_at = at
        next_seq = seq
      }
      i = i + 1
    }
    if next < 0 {
      return
    }
    let d = self.timeline[next]
    let was = self.cause_at
    self.cause_at = next_at

    // (one change, committed whole at its moment before what it said of modal layers is told: Tree::modals_settled)
    self.committing += 1
    match d {
      Leaves(id, _) => {
        self.timeline.remove(next) |> ignore
        let n = self.nodes[id.at]
        if n.left_at >= 0.0 {
          if n.parent >= 0 {
            @signals.untracked(fn() { self.handle(n.parent).drop({ tree: self, at: id.at, gen: id.gen }) })
          }
        } else {
          n.back_at = -1.0
          told_going(n)
        }
      }
      Once(o, _) => {
        self.timeline.remove(next) |> ignore
        o.live.val = false
        @signals.start_batch()
        @signals.untracked(fn() { (o.f)() })
        @signals.end_batch()
      }
      Steps(s, _) => {
        let k = s.k
        s.k = s.k + 1
        @signals.start_batch()
        @signals.untracked(fn() { (s.step)(k, next_at) })
        @signals.end_batch()
      }
    }
    self.committing -= 1
    self.modals_settled()
    self.cause_at = was
    // (where things stand once it is told whole, as of its moment, for the next change: Tree::settle_after_change)
    if was < 0.0 {
      self.settle_now(next_at)
    }
  }
}

///|
/// When step `k` (from 0) of `s` is due: a tick of the one clock at its rate, by its number alone (a second's
/// `per_second` ticks end at the second, exactly: no step's length added up; what steps at one rate steps at the same
/// moments, whenever each began).
fn stepped_at(s : Stepper, k : Int) -> Double {
  tick_at(s.first + k.to_int64(), s.per_second)
}

///|
/// The moment of tick `n` at `per_second` a second on the one clock (its number alone: no step's length added up).
fn tick_at(n : Int64, per_second : Int) -> Double {
  (n * 1000L).to_double() / per_second.to_double()
}

///|
/// The first tick at `per_second` after `at` on the one clock: the one whose moment (tick_at, as every step's is worked
/// out) is later than `at`, none before it later too (a tick at `at` itself, worked out the same way, is not after it).
fn tick_after(at : Double, per_second : Int) -> Int64 {
  let mut n = (at * per_second.to_double() / 1000.0).floor().to_int64()
  while tick_at(n, per_second) <= at {
    n = n + 1L
  }
  while tick_at(n - 1L, per_second) > at {
    n = n - 1L
  }
  n
}

///|
/// What adds up step by step, said for a stretch from its cause's moment on the one clock (the tree's: there is no
/// clock of its own; it only asks that the clock not jump its steps in that stretch): `step` given each step's number
/// (from 0) and its moment, the clock's ticks at `per_second` a second (the first after its cause), `count` of them
/// (what it adds up is its own, kept by `step`): as the tree's logic advances (Tree::advance), each in
/// its turn, whatever frames are drawn. For what moves by adding up step after step (what a value is worked out of the
/// steps before it); a motion that is a function of the time needs none. The node's: stopped with it, or by what it
/// returns.
pub fn View::steps(self : View, per_second : Int, count : Int, step : (Int, Double) -> Unit) -> () -> Unit {
  guard self.live() is Some(_) && per_second > 0 && count > 0 else { return fn() {  } }
  let live = Ref(true)
  let tree = self.tree
  // (kept by the node while it goes: let go of as it ends, as it is called off, as the node goes, once)
  let unkeep : Ref[() -> Unit] = Ref(fn() {  })
  let stop = fn() {
    if live.val {
      live.val = false
      (unkeep.val)()
      tree.unschedule(live)
    }
  }
  unkeep.val = self.owns_while(stop)
  let last = fn(i : Int, at : Double) {
    step(i, at)
    if i == count - 1 && live.val {
      live.val = false
      (unkeep.val)()
      tree.unschedule(live)
    }
  }
  tree.timeline.push(Steps({ first: tick_after(tree.cause_now(), per_second), per_second, count, k: 0, step: last, live }, tree.told))
  tree.told = tree.told + 1
  tree.marked()
  stop
}

///|
/// A frame of `w` by `h` at the clock's time, doing what was marked: the bindings whose reads changed worked out; the
/// nodes marked laid out, and visited of them only those laid out again and what they hold (placed anew by them); the
/// nodes whose place changed (offset, opacity), each alone; the nodes whose look changed, each alone. A node's content
/// made again only as what it draws changed (its look, its size: Tree::changed); one placed or faded otherwise is
/// composed again, what it holds left as it is (Tree::composed); the order made again where what is drawn was made,
/// let go or moved among its siblings. Whether anything drawn changed.
pub fn Tree::frame(self : Tree, w : Double, h : Double, now? : Double) -> Bool {
  // (its logic advanced to `now`, what the host has come to (the clock its drawing is sampled at may be a moment ahead:
  // when the frame is to be shown, Tree::at); none given, the clock's)
  let upto = match now {
    Some(n) => n
    None => @signals.untracked(fn() { self.clock.get() })
  }
  self.changed.clear()
  self.composed.clear()
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return false
  }
  if w != self.last_w || h != self.last_h {
    self.last_w = w
    self.last_h = h
    let s = self.nodes[0].flex.style
    s.set_width(Pt(w))
    s.set_height(Pt(h))
    self.layout_marked_at(0)
    // (what follows it changed as of the frame's moment, before it is laid out)
    self.room.set((w, h))
  }
  self.brought(upto)
  self.first_drawn_now()
  let drawn = self.drawn_due
  self.drawn_due = false
  if self.telling_due {
    self.due_frame_taken = true
  }
  drawn
}

///|
/// The tree brought to `at` (an event's moment, before it is handled: what is pressed, where things are, is the
/// tree's as of then, whatever frame came before): the clock set there, what ended by then settled, the bindings told
/// worked out, what is marked laid out, placed and looked at, the order made, as a frame does all of it (what it
/// changed for the host to draw taken by the next frame's host as its own: Tree::take_changed). Nothing laid out before
/// the tree has a size (its first frame).
pub fn Tree::bring_to(self : Tree, at : Double) -> Unit {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return
  }
  // (its logic first, to the moment, then what it draws drawn as of it (a frame to be shown later drawn ahead of it:
  // drawn again as of now, for where a press finds things), then what it marked)
  self.advance(at)
  self.clock_to(at)
  // (what the change under way set so far, and the clock, pulled into its properties: an input in a change's batch
  // finds things where they are then, nothing else told before the change ends)
  self.pull()
  if self.last_w >= 0.0 {
    self.brought(at)
  }
}

///|
/// What was marked done, at the clock's now (Tree::frame, Tree::bring_to).
fn Tree::brought(self : Tree, upto : Double) -> Unit {
  // (what it tells as it is laid out, and what that changes, of the frame's moment: no change told so has a moment of
  // its own to ask the host for. Asked, the host's clock had gone on: each size it told set what moves a little
  // further, laid out otherwise, told again, laid out again inside the pass before, till the move ended: thousands
  // deep as a chat was left on an emulator, its GL thread out of stack, 2026-11-05)
  let was = self.bringing_at
  self.bringing_at = upto
  // what is due by now done (and the logic at `upto`, nothing due or not: what is said next is of then)
  self.advance(upto)
  self.laid_out(upto)
  // (what that layout found to tell, told now, of this moment, whether a frame is painted before what comes next or
  // not: once, by the outermost)
  if was < 0.0 {
    self.tell_laid()
  }
  self.bringing_at = was
}

///|
/// What was marked laid out and drawn at `upto`, the logic not moved: no moment's work done, nothing due run (for where
/// things are as an event finds them in the middle of its change: Tree::laid_now).
fn Tree::laid_pass(self : Tree, upto : Double) -> (Bool, Bool) {
  let w = self.last_w
  let h = self.last_h
  // the bindings whose reads changed since, each once, in the order they were told (what they make runs its own now,
  // what they set again marks what it marks)
  let mut i = 0
  while i < self.bindings_due.length() {
    // (one run already, pulled as something asked at once: not again)
    let b = self.bindings_due[i]
    if b.queued {
      (b.run)()
    }
    i = i + 1
  }
  self.bindings_due.clear()
  // (those marked that ran so, no longer to be pulled; one marked in a change not ended yet still is)
  let still = self.pulls_marked.filter(fn(b) {
    b.live && b.watch is Some(_) && b.marked
  })
  self.pulls_marked.clear()
  self.pulls_marked.append(still)
  // (what goes beside another placed by it only where anything was laid out or placed again: View::beside)
  let placing = self.layout_due || !self.places_due.is_empty()
  if self.layout_due {
    self.layout_due = false
    // (laid out already to be read, nothing marked since: placed by that; else laid out now, what was laid out to be
    // read before it and not placed by yet placed too, Tree::measured_now)
    if self.measured_gen >= 0 {
      let gen = if self.walk_from >= 0 { self.walk_from } else { self.measured_gen }
      self.measured_gen = -1
      self.walk_from = -1
      self.walk(0, gen, true)
    } else {
      self.laid_out_now(0, w, h, fn(g) {
        let gen = if self.walk_from >= 0 && self.walk_from < g { self.walk_from } else { g }
        self.measured_gen = -1
        self.walk_from = -1
        self.walk(0, gen, true)
      })
    }
  }
  // (placed or faded by its own: it alone composed again)
  let places_done = fn() {
    for at in self.places_due {
      let n = self.nodes[at]
      if n.live && n.place_due {
        self.work.visited = self.work.visited + 1
        self.place(at)
      }
    }
    self.places_due.clear()
  }
  places_done()
  // (what is worked out as the frame is painted, from where this layout and what moved by its own put things (each
  // reading where the one said before it put its own: Laid::drawn): its place or its look set, then placed or drawn
  // again with the rest)
  self.painted_now()
  places_done()
  if placing {
    // (a page's list's first row on the pixels from where it is now laid out, whatever moved: Tree::rows_placed)
    if self.rows_grid > 0.0 {
      for at in self.rows_lists {
        if self.nodes[at].live && self.nodes[at].list_rows {
          self.place(at)
        }
      }
    }
    // (what one laid out as wide as its anchor set off done once it is placed beside it too: Tree::laid_out_now)
    @signals.afters_held(fn() { self.besides_placed() })
  }
  // (what changed of its look alone: its content, nothing else)
  for at in self.looks_due {
    let n = self.nodes[at]
    if n.live && n.look_due {
      self.work.visited = self.work.visited + 1
      self.made_again(at)
    }
  }
  self.looks_due.clear()
  // (the order changed: drawn again, nothing kept of it to make again: what is drawn is gone through down the tree,
  // Tree::walk_drawn)
  let ordered = self.order_due
  if ordered {
    self.order_due = false
    self.work.orders = self.work.orders + 1
  }
  self.work.changes = self.work.changes + self.changed.length() + self.composed.length()
  self.due = false
  // (what its rows left out told once all of it is laid out, and what that tells (a ⋯ saying how many) laid out in this
  // same pass: one result, the frame drawing all of it)
  if self.outs_changed {
    self.outs_told()
    if self.due {
      return (placing, ordered)
    }
  }
  // (the sizes followed told once all of it is laid out, and what that tells laid out in this same pass)
  if self.sized.length() > 0 && self.sizes_told() && self.due {
    return (placing, ordered)
  }
  // (what waited on all of it laid out, told once now, whether any size it follows came out otherwise or not; what that
  // tells laid out in this same pass)
  if self.laid_waits.length() > 0 {
    let waits = self.laid_waits.copy()
    self.laid_waits.clear()
    for f in waits {
      @signals.untracked(f)
    }
    if self.due {
      return (placing, ordered)
    }
  }
  // (what is to be brought into sight, where all of it is laid out, before it is drawn; what that moves laid out in
  // this same pass)
  if self.shows_due.length() > 0 {
    self.shown_now()
    if self.due {
      return (placing, ordered)
    }
  }
  (placing, ordered)
}

///|
/// Node `at` and what it holds laid out `width` by `height` now, with `then` (what is placed from it: walked,
/// Tree::walk), the generation of that layout given `then`: what a child made in it sets off after a flush (a move
/// from a composer handed over measuring where it lands) waits till it is laid out and placed (@signals.afters_held;
/// its effects run as ever), never between its making and its measuring. Every layout of the tree goes through here (a frame's, one a change asks for: Tree::measured_now,
/// what goes beside another as wide as it: Tree::besides_placed).  A layout a change asks for to read sizes (placed as the
/// frame is): what it sets off done as it ends, reading where it is laid out (View::laid_window_now: from the layout,
/// not from where it is placed).
fn Tree::laid_out_now(
  self : Tree,
  at : Int,
  width : Double,
  height : Double,
  then : (Int) -> Unit,
) -> Unit {
  self.boxes_flush()
  self.work.computes = self.work.computes + 1
  let g = @flex.computes() + 1
  @signals.afters_held(fn() {
    self.layouts_active += 1
    @flex.compute(self.nodes[at].flex, width~, height~, round=false, reuse=true)
    then(g)
    self.layouts_active -= 1
  })
}

///|
/// How many layout passes one may take (each what the one before told marking more: opening a long chat, 19; a quoted
/// picture's card flown to its message, its rows placed a few points on in each, more than 32): a guard against passes
/// that never stop, not a budget.
pub let laid_passes_most : Int = 64

///|
/// Each layout pass's sizes told otherwise said (a switch for finding why passes go on: what was told, from what to
/// what), else only those of the passes past laid_passes_most.
pub let laid_passes_traced : Ref[Bool] = Ref(false)

///|
/// Where a pass's sizes told otherwise are said while laid_passes_traced is on.
pub let laid_passes_trace : Ref[(String) -> Unit] = Ref(fn(s) { println(s) })

///|
/// Node `at`'s `what` told otherwise in this pass, from `was` to `now`: noted where it is asked for (the trace on, or
/// the last passes before laid_passes_most).
fn Tree::told_noted(self : Tree, at : Int, what : String, was : () -> String, now : () -> String) -> Unit {
  if laid_passes_traced.val {
    (laid_passes_trace.val)("view: layout pass \{self.laid_passes}: node \{at} \{what} \{was()} -> \{now()}")
  }
  if self.laid_passes >= laid_passes_most && self.told_otherwise.length() < 8 {
    self.told_otherwise.push("node \{at} \{what} \{was()} -> \{now()}")
  }
}

///|
/// What was marked laid out and drawn at `upto`, the logic not moved: no moment's work done, nothing due run (for where
/// things are as an event finds them in the middle of its change: Tree::laid_now). Pass after pass while what one tells
/// marks more to do, each from the start, in a loop: once it ran in itself, as deep as passes came, and a frame whose
/// passes never stopped (what it told taken at the host's clock, gone on: Tree::brought) ran the stack out, 2000 deep.
fn Tree::laid_out(self : Tree, upto : Double) -> Unit {
  if !self.due {
    return
  }
  let mut placing = false
  let mut ordered = false
  let mut passes = 0
  while self.due {
    passes += 1
    self.laid_passes = passes
    if passes > laid_passes_most {
      let said = "view: \{passes - 1} layout passes in one, each telling what marks another; told otherwise in the last: \{self.told_otherwise}; marked again from \{self.laid_marked_at}"
      println(said)
      fault(said)
      self.due = false
      break
    }
    self.told_otherwise.clear()
    let (p, o) = self.laid_pass(upto)
    placing = placing || p
    ordered = ordered || o
  }
  self.laid_passes = 0
  if ordered || self.changed.length() > 0 || self.composed.length() > 0 {
    self.drawn_due = true
  }
  // (what is under the pointer as it is placed now, View::pointer_within: told once all of it is placed, and what that
  // told marked done in this same pass, again till nothing it tells is told otherwise: what it marked all done, as one
  // change's whole)
  if placing && !self.withins_passing {
    self.withins_passing = true
    while self.withins_told() && self.due {
      self.laid_out(upto)
    }
    self.withins_passing = false
  } else if !self.withins_passing && self.bar_cols.length() > 0 && (ordered || self.changed.length() > 0 || self.bars_due) {
    // (which column's bar the pointer is along told anew as what is drawn or found there changes without anything
    // placed: an order, what bounds input, what takes it; in this same pass)
    self.withins_passing = true
    while self.bars_near_told() && self.due {
      self.laid_out(upto)
    }
    self.withins_passing = false
  }
}

///|
/// The sizes followed (View::laid_size_told), all of it laid out, told as one change: whether any was told otherwise.
/// The tree's own telling of what it laid out, wherever its layout runs (a hand-off's change brought to its moment
/// too): reads what is laid out as its own (reads_own), never as the hand-off's code.
fn Tree::sizes_told(self : Tree) -> Bool {
  reads_own(fn() { self.sizes_told_now() })
}

///|
/// What Tree::sizes_told does.
fn Tree::sizes_told_now(self : Tree) -> Bool {
  let keep = []
  // (each once, however often it was asked: a set, not the array gone through for each)
  let kept : Set[Int] = Set::new()
  let told = Ref(false)
  @signals.start_batch()
  for at in self.sized {
    let n = self.nodes[at]
    guard n.live && (n.size_cell is Some(_) || n.rect_cell is Some(_) || n.drawn_rect_cell is Some(_) || n.went_cell is Some(_)) else { continue }
    if !kept.contains(at) {
      kept.add(at)
      keep.push(at)
      match n.rect_cell {
        Some(cell) => {
          let rect = if self.out_at(at) { None } else { Some(self.handle(at).placed_window_now()) }
          if @signals.untracked(fn() { cell.get() }) != rect {
            told.val = true
            self.told_noted(at, "place", fn() { @signals.untracked(fn() { cell.get() }).to_string() }, fn() { rect.to_string() })
            cell.set(rect)
          }
        }
        None => ()
      }
      match n.drawn_rect_cell {
        Some(cell) => {
          let rect = if self.out_at(at) { None } else {
            let (x, y, _, s) = self.projected(at, drawing=true)
            Some((x, y, n.lw * s, n.lh * s))
          }
          if @signals.untracked(fn() { cell.get() }) != rect {
            told.val = true
            self.told_noted(at, "place", fn() { @signals.untracked(fn() { cell.get() }).to_string() }, fn() { rect.to_string() })
            cell.set(rect)
          }
        }
        None => ()
      }
      // (laid out nowhere, it or what holds it (View::laid_nowhere, left out of its row): no size of its own to tell
      // this time, the one it had kept, still followed, till it is laid out somewhere again, as what reads it (how far a
      // column scrolls) keeps its own)
      if self.out_at(at) {
        continue
      }
      match n.size_cell {
        Some(cell) => {
          let size = Some((n.flex.width, n.flex.height))
          if @signals.untracked(fn() { cell.get() }) != size {
            told.val = true
            self.told_noted(at, "size", fn() { @signals.untracked(fn() { cell.get() }).to_string() }, fn() { size.to_string() })
            cell.set(size)
          }
        }
        None => ()
      }
      // (and the side it went on beside its anchor, where that is followed: View::went_told)
      match n.went_cell {
        Some(cell) =>
          if @signals.untracked(fn() { cell.get() }) != n.went {
            told.val = true
            self.told_noted(at, "side", fn() { "" }, fn() { "" })
            cell.set(n.went)
          }
        None => ()
      }
    }
  }
  // (what was first asked as what was told was read: a node made as it was, its size followed from then on, told the
  // next time all is laid out, not forgotten)
  let n = self.sized.length()
  @signals.end_batch()
  let asked = self.sized[n:].to_array()
  self.sized.clear()
  self.sized.append(keep)
  self.sized.append(asked)
  told.val
}

///|
/// Node `id` (`within`: that part of it, its top and its foot in its own terms, asked once all is laid out; none there,
/// all of it) brought into sight by what holds it that shows what it holds (View::shows: a column that scrolls), once
/// all of it is laid out as it is next, before that is drawn: the innermost first, each that holds it then told where
/// it is as the ones inside it moved it. Once, at this cause (the focus come to it): nothing brings it back of itself
/// after.
pub fn Tree::show_in_sight(self : Tree, id : NodeId, within? : () -> (Double, Double)?) -> Unit {
  // (a list that keeps itself holding it told now, at this cause: it lays it out in sight, Scroll's `reveal`)
  if self.alive_id(id) {
    // (what part of it, as it is now: its top and its foot in its own terms)
    let part = match within {
      Some(f) => @signals.untracked(f)
      None => None
    }
    let mut i = self.nodes[id.at].parent
    while i >= 0 {
      match self.scrolls_at.get(i) {
        Some(s) => (s.reveal)(id, part)
        None => ()
      }
      i = self.nodes[i].parent
    }
  }
  self.shows_due.push((id, within.unwrap_or(fn() { None })))
  self.marked()
}

///|
/// What is to be brought into sight (Tree::show_in_sight), all of it laid out: each in turn, as one change.
fn Tree::shown_now(self : Tree) -> Unit {
  let due = self.shows_due.copy()
  self.shows_due.clear()
  @signals.start_batch()
  for e in due {
    let (id, within) = e
    guard self.alive_id(id) else { continue }
    let (tx, ty, ts) = self.placed(id.at)
    let (a, b) = match within() {
      Some(w) => w
      None => (0.0, self.nodes[id.at].flex.height)
    }
    // (where it is in the window, down and across: each that holds it moving it one way or the other, View::shows'
    // `across`)
    let mut y0 = ty + a * ts
    let mut y1 = ty + b * ts
    let mut x0 = tx
    let mut x1 = tx + self.nodes[id.at].flex.width * ts
    let mut i = self.nodes[id.at].parent
    while i >= 0 {
      let n = self.nodes[i]
      match n.shows {
        Some(f) => {
          let (vx, vy, vs) = self.placed(i)
          if n.shows_across {
            let moved = @signals.untracked(fn() { f((x0 - vx) / vs, (x1 - vx) / vs) })
            x0 = x0 - moved * vs
            x1 = x1 - moved * vs
          } else {
            let moved = @signals.untracked(fn() { f((y0 - vy) / vs, (y1 - vy) / vs) })
            y0 = y0 - moved * vs
            y1 = y1 - moved * vs
          }
        }
        None => ()
      }
      i = n.parent
    }
  }
  @signals.end_batch()
}

///|
/// How big it was laid out (its own terms: View::laid_size's), followed: told once all of the layout is done, as one
/// change of all those followed (what holds a column that scrolls in it, how far it can go: View::scrolls); none till
/// the first layout after it is first asked has been done (not measured yet: no size of nothing). Never a motion's
/// target.
pub fn View::laid_size_told(self : View) -> (Double, Double)? {
  layout_read("laid_size_told")
  guard self.live() is Some(n) else { return None }
  let cell = match n.size_cell {
    Some(c) => c
    None => {
      let c : @signals.Signal[(Double, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })
      n.size_cell = Some(c)
      self.tree.sized.push(self.at)
      self.tree.marked()
      c
    }
  }
  cell.get()
}

///|
/// Where it is placed in the window, followed by an overlay outside its scroll or clip. Told after all placement,
/// including scrolling and anchoring, in the same layout pass. None before that first pass or while laid out nowhere.
/// Drawing transforms are excluded, as in placed_window_now. This describes geometry; it never starts or retimes a
/// motion. A flight declares its way once for the send and uses this only to locate its destination on that way.
pub fn View::laid_window_told(self : View) -> (Double, Double, Double, Double)? {
  layout_read("laid_window_told")
  guard self.live() is Some(n) else { return None }
  let cell = match n.rect_cell {
    Some(c) => c
    None => {
      let c : @signals.Signal[(Double, Double, Double, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })
      n.rect_cell = Some(c)
      self.tree.sized.push(self.at)
      self.tree.marked()
      c
    }
  }
  cell.get()
}

///|
/// Its whole rectangle where the window draws it, followed by an overlay outside its holders. Includes drawing
/// offsets and scaling, even while its own opacity is zero; clipping does not shorten the rectangle. Told after
/// placement in the same pass, or None before that pass and while laid out nowhere. Unlike laid_window_told, this
/// follows a landing on its way; it must not be used to define that landing's own motion.
pub fn View::drawn_window_told(self : View) -> (Double, Double, Double, Double)? {
  guard self.live() is Some(n) else { return None }
  let cell = match n.drawn_rect_cell {
    Some(c) => c
    None => {
      let c : @signals.Signal[(Double, Double, Double, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })
      n.drawn_rect_cell = Some(c)
      self.tree.sized.push(self.at)
      self.tree.marked()
      c
    }
  }
  cell.get()
}

///|
/// What its rows left out, all of it laid out, told as one (as one said to take presses no more is, View::presses, at
/// the change's end): where a finger is found; of each left out, what was held in it, its focus and its back let go of;
/// what follows whether each takes input, what hosts it, and what reads which are left out (View::left_out) told
/// once, none seeing half of it.
fn Tree::outs_told(self : Tree) -> Unit {
  self.outs_changed = false
  let gone = self.outs_gone.copy()
  self.outs_gone.clear()
  self.hits = self.hits + 1
  @signals.start_batch()
  for at in gone {
    if self.nodes[at].live && self.nodes[at].out {
      match self.focused {
        Some(f) => {
          let mut q = f.at
          while q >= 0 && q != at {
            q = self.nodes[q].parent
          }
          if q == at {
            self.focus_parked = Some((f, self.focus_visible))
          }
        }
        None => ()
      }
      self.hold_lost_in(at)
      self.focus_lost_in(at)
      self.back_lost_in(at)
    }
  }
  // (laid out again, what had the focus as it went nowhere, where nothing took it meanwhile: given it back)
  match self.focus_parked {
    Some((p, v)) if self.focused is None && self.alive_id(p) && !self.out_at(p.at) && self.can_focus(p) => {
      self.focus_parked = None
      match self.on_focus_asked {
        Some(f) => f(p, v)
        None => self.focus_set(Some(p), v)
      }
    }
    _ => ()
  }
  self.modals_told()
  self.outs_said.set(@signals.untracked(fn() { self.outs_said.get() }) + 1)
  @signals.end_batch()
}

///|
/// Node `at` after a compute numbered `gen`: placed again, and what it holds where it was laid out again (each placed
/// anew by it, looked at); below what was not laid out again, nothing is visited (what holds a node moved, its place in
/// it is the same).
fn Tree::walk(self : Tree, at : Int, gen : Int, holder_laid : Bool) -> Unit {
  let n = self.nodes[at]
  self.work.visited = self.work.visited + 1
  if n.slot {
    if holder_laid {
      for k in n.kids {
        self.walk(k, gen, holder_laid)
      }
    }
    return
  }
  // (laid out by this compute, or one before it not yet placed by: Tree::measured_now)
  let laid = n.flex.laid_out_at() >= gen
  if laid {
    self.work.laid = self.work.laid + 1
    // (laid out anew: what it holds may be laid out otherwise, the middle of what it draws with it)
    if n.look.pivot is Drawn {
      n.drawn_stale = true
    }
  }
  // (where it says shorter words, or drew some: what it draws decided anew, its own where it says none now)
  if laid && (n.shorter.length() > 0 || n.look.words_drawn is Some(_)) {
    self.shorter_in(at)
  }
  self.place(at)
  if laid {
    for k in n.kids {
      self.walk(k, gen, laid)
    }
  }
}

///|
/// How wide node `at` may be at most, of what is said of it (View::max_width) and what it is, as an old view's box is
/// (ui/layout.mbt's `capped`): words on one line (not wrapped, plain or in pieces) in a column (past any slot), no width
/// said of them (View::width), no wider than the column (all of its width; what is said, where the column has less:
/// Within), cut short there; else what is said, else none.
fn Tree::capped_applied(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  guard n.live else { return }
  let mut p = n.parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  let in_column = p >= 0 && !(self.nodes[p].flex.style.direction is (Row | RowReverse))
  let st = n.flex.style
  let one_line = (n.look.words != "" || !n.look.runs.is_empty()) && !n.look.words_look.wrap
  let said = match n.max_w_said {
    Some(Some(w)) => Some(w)
    _ => None
  }
  let max : @flex.Dim = if one_line && in_column && st.width_kind() == @flex.LEN_AUTO {
    match said {
      Some(w) => Within(w)
      None => Pct(100.0)
    }
  } else {
    match said {
      Some(w) => if n.max_w_within { Within(w) } else { Pt(w) }
      None => Auto
    }
  }
  if st.get_max_width() != max {
    st.set_max_width(max)
    self.layout_marked_at(at)
  }
}

///|
/// How node `at` gives way and how narrow it may be, of what is said of it (View::shrink, View::min_width) and what
/// its words say (View::shorter): what is said its own; else, saying shorter words on one line, giving way along a row
/// down to the last of them as its words look now (an old view's one-line words said shorter ways, their least
/// one_line_least_w's); else as a node gives way of itself (none, as narrow as nothing). Cut short (View::cuts):
/// how it gives way its own (Tree::cut_applied).
fn Tree::give_way_applied(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  guard n.live else { return }
  let shorter = n.shorter.length() > 0 && n.look.runs.is_empty() && !n.look.words_look.wrap
  let mut p = n.parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  let along = p >= 0 && self.nodes[p].flex.style.direction is (Row | RowReverse)
  let st = n.flex.style
  if !n.cut {
    let s = match n.shrink_said {
      Some(s) => s
      None => if shorter && along { 1.0 } else { 0.0 }
    }
    if st.shrink != s {
      st.shrink = s
      self.layout_marked_at(at)
    }
  }
  let min : @flex.Dim = match n.min_w_said {
    Some(Some(w)) => if n.min_w_within { Within(w) } else { Pt(w) }
    Some(None) => Auto
    // (along a row alone, as an old view's least of one-line words is: in a column, cut to the column's width)
    None =>
      if shorter && along {
        Pt((self.measure)(n.shorter[n.shorter.length() - 1], n.look.words_look, -1.0).0)
      } else {
        Auto
      }
  }
  if st.get_min_width() != min {
    st.set_min_width(min)
    self.layout_marked_at(at)
  }
}

///|
/// How wide what is drawn of words too wide for `room` on one line is where they say `shorter` ways, without a host's
/// own layout of them (a tree made with none: words_measure's): the first of those that fits, else the last cut, by
/// its characters, where it and an ellipsis fit (no space left before it); measured by `measure`.
fn shorter_w_by(
  measure : (String, WordsLook, Double) -> (Double, Double),
  words : String,
  shorter : Array[String],
  look : WordsLook,
  room : Double,
) -> Double {
  ignore(words)
  let wide = fn(s : String) { measure(s, look, -1.0).0 }
  for alt in shorter {
    if wide(alt) <= room + 0.5 {
      return wide(alt)
    }
  }
  let chars = shorter[shorter.length() - 1].to_array()
  let mut end = chars.length()
  while end > 0 {
    let mut e = end
    while e > 0 && chars[e - 1] == ' ' {
      e = e - 1
    }
    let cut = String::from_array(chars[:e].to_array()) + "…"
    if wide(cut) <= room + 0.5 {
      return wide(cut)
    }
    end = end - 1
  }
  wide("…")
}

///|
/// What node `at` shows where it says shorter words (View::shorter), as it is laid out: its words where they have the
/// room it is laid out in, else the first of the shorter ones that has, else the last (cut short there where it lets
/// its words be: View::allow_ellipsis), as an old view's one-line words are (said_in): drawn so, read out, found and
/// measured as its words.
fn Tree::shorter_in(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  let w = n.flex.width
  let fits = fn(s : String) { (self.measure)(s, n.look.words_look, -1.0).0 <= w + 0.5 }
  let mut shown : String? = None
  // (one line's words alone, saying shorter ones: words that wrap have the room of their lines, as an old view's do;
  // none said now, its own)
  if n.look.runs.is_empty() && !n.look.words_look.wrap && n.shorter.length() > 0 && !fits(n.look.words) {
    shown = Some(n.shorter[n.shorter.length() - 1])
    for alt in n.shorter {
      if fits(alt) {
        shown = Some(alt)
        break
      }
    }
  }
  if shown != n.look.words_drawn {
    n.look.words_drawn = shown
    self.look_marked_at(at)
  }
}

///|
/// Node `at` placed where it is in what holds it (its layout's place, its offset), as opaque as itself, as big as it is
/// laid out: composed again where it is placed or faded otherwise, its content made again where its size (or its look)
/// changed.
fn Tree::place(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  n.place_due = false
  let x = n.flex.left + n.look.dx + n.look.sx * n.flex.width
  // (a page's list's first row on the host's pixels where it sets them so: Tree::rows_placed)
  let y = self.rows_placed(at, n.flex.top + n.look.dy + n.look.sy * n.flex.height)
  let a = n.look.alpha
  let w = n.flex.width
  let h = n.flex.height
  let s = n.look.scale
  let (px, py) = self.pivot_of(at, w, h)
  // (left out of its row: laid out nowhere; told once all of it is laid out, View::left_out)
  let out = n.flex.left_out()
  let went = !n.placed || x != n.lx || y != n.ly || a != n.la || s != n.ls || px != n.lpx || py != n.lpy || out != n.out
  if out != n.out {
    n.out = out
    self.outs_changed = true
    // (what of it is let go of told once all of the layout is done: Tree::outs_told)
    if out {
      self.outs_gone.push(at)
    }
  }
  let sized = !n.placed || w != n.lw || h != n.lh
  n.placed = true
  n.lx = x
  n.ly = y
  n.la = a
  n.lw = w
  n.lh = h
  n.ls = s
  n.lpx = px
  n.lpy = py
  if went {
    self.composed_again(at)
  }
  if sized || n.look_due {
    self.made_again(at)
  }
}

///|
/// Node `at` composed elsewhere than it was in what holds it (placed again, or beside what it goes beside:
/// Tree::besides_placed): composed again there, and the scene told so at this cause, what it draws drawn where it is now
/// (Tree::take_placed), however it came to be there.
fn Tree::composed_again(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  self.work.composed = self.work.composed + 1
  self.composed.push({ at, gen: n.gen })
  self.placed_pending.push({ at, gen: n.gen })
}

///|
/// Node `at`'s content made again, as it looks now and as big as it is: one of the frame's changes.
fn Tree::made_again(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  n.look_due = false
  let id = { at, gen: n.gen }
  self.work.instances = self.work.instances + 1
  n.content = Some({
    id,
    w: n.lw,
    h: n.lh,
    ground: n.look.ground,
    ink: n.look.ink,
    words: n.look.words,
    words_drawn: n.look.words_drawn,
    shapes: n.look.shapes,
    lines: n.look.lines,
    tint: n.look.tint,
    radius: n.look.radius,
    corners: n.look.corners,
    edge: n.look.edge,
    edge_dashed: n.look.edge_dashed,
    notch: n.look.notch,
    shadow_out: n.look.shadow_out,
    cut_across: n.look.cut_across,
    clip_drawn: n.look.clip_drawn,
    image: n.look.image,
    image_for: n.look.image_for,
    image_cover: n.look.image_cover,
    image_fade: n.look.image_fade,
    image_in: n.look.image_in,
    glass: n.look.glass,
    words_look: n.look.words_look,
    runs: n.look.runs,
    runs_look: n.look.runs_look,
    runs_pressed: n.look.runs_pressed,
    runs_picked: n.look.runs_picked,
    runs_lit: n.look.runs_lit,
    shadow: n.look.shadow,
    hosted: n.hosted,
    clips: n.look.clips || n.hosted_clips,
    words_center: n.look.words_center,
    ellipsis_past: n.look.ellipsis_past,
    picture: n.look.picture,
    bones: self.bones_of_at(at),
    bone_as: self.bone_as_at(at),
    native_anchor: n.look.native_anchor,
  })
  self.changed.push(id)
  self.pending.push(id)
}

///|
/// What node `at` holds in the order it is drawn, found, read out and gone to by Tab in: its kids as they are; the
/// root's each by its place in the window's stack of layers (Tree::root_layers), what is in a slot of its (show, pick,
/// each) each its own, those of the same place in their order.
fn Tree::kids_in_order(self : Tree, at : Int) -> Array[Int] {
  if at == 0 {
    self.root_layers()
  } else {
    self.nodes[at].kids
  }
}

///|
/// What the root holds, each a node of its own (what is in a slot of its (show, pick, each) its own, the slot left
/// out), in the order of their places in the window's stack of layers (in none first, then by their places, then
/// what is over all else; those of the same place in the order they are held in).
fn Tree::root_layers(self : Tree) -> Array[Int] {
  let tops : Array[Int] = []
  fn flat(k : Int) -> Unit {
    let n = self.nodes[k]
    if n.slot {
      for c in n.kids {
        flat(c)
      }
    } else {
      tops.push(k)
    }
  }
  for k in self.nodes[0].kids {
    flat(k)
  }
  let place = fn(k : Int) {
    let n = self.nodes[k]
    if n.over_all {
      2147483647
    } else {
      n.stack
    }
  }
  let out : Array[Int] = []
  for k in tops {
    let p = place(k)
    let mut j = out.length()
    while j > 0 && place(out[j - 1]) > p {
      j = j - 1
    }
    out.insert(j, k)
  }
  out
}

///|
/// Where node `at` is drawn among the rest (Tree::path_of), what the root holds counted in their order in the window's
/// stack of layers (Tree::root_layers): what is over what, of two.
fn Tree::layer_path(self : Tree, at : Int) -> Array[Int]? {
  let top = self.top_of(at)
  guard top >= 0 else { return None }
  guard self.root_layers().search(top) is Some(rank) else { return None }
  let path : Array[Int] = []
  let mut i = at
  while i != top {
    let p = self.nodes[i].parent
    guard p >= 0 && self.nodes[p].kids.search(i) is Some(k) else { return None }
    path.push(k)
    i = p
  }
  path.push(rank)
  path.rev_in_place()
  Some(path)
}

///|
/// What the last frame made again: the nodes whose content changed.
pub fn Tree::changed(self : Tree) -> Array[NodeId] {
  self.changed
}

///|
/// The nodes whose content was made again since this was last asked (by frames, by an event bringing the tree to its
/// moment): what the host keeps of each made again. Taken: asked again, only those since.
pub fn Tree::take_changed(self : Tree) -> Array[NodeId] {
  let out = self.pending.copy()
  self.pending.clear()
  out
}

///|
/// The nodes let go since this was last asked (by a frame's structure, a leaving ended, the tree disposed): what the
/// host keeps for each (its drawing, a texture, a native view) is let go with it. Taken: asked again, only those since.
pub fn Tree::take_removed(self : Tree) -> Array[NodeId] {
  let out = self.removed.copy()
  self.removed.clear()
  out
}

///|
/// What the last frame composed again: the nodes placed or faded otherwise (what they hold left as it was).
pub fn Tree::composed(self : Tree) -> Array[NodeId] {
  self.composed
}

///|
/// The scene gone through in the order it is drawn: `f` given each node's content (where it is its own) and where the
/// window draws it and how opaque, composed as it goes from what holds it (none for a node not yet placed); drawn as
/// big as it is laid out (each_drawn_scaled: how big besides).
pub fn Tree::each_drawn(self : Tree, f : (Content, Double, Double, Double) -> Unit) -> Unit {
  self.each_drawn_scaled(fn(c, x, y, a, _) { f(c, x, y, a) })
}

///|
/// The scene gone through as each_drawn goes through it, `f` given besides how big each is drawn (its own scale and its
/// holders', View::scale: what it draws as big about where the window draws its origin).
pub fn Tree::each_drawn_scaled(self : Tree, f : (Content, Double, Double, Double, Double) -> Unit) -> Unit {
  self.each_drawn_in_order(fn(_, _, c, x, y, a, s, _, _) { f(c, x, y, a, s) })
}

///|
/// The same scene's input places, as projected and said_order read them: offsets and scales composed, with no
/// draw-only displacement from a layout motion (View::drawn_off). Every kind of pointing uses these places.
fn Tree::each_taken(self : Tree, f : (Content, Double, Double, Double, Double) -> Unit) -> Unit {
  self.each_drawn_in_order(fn(_, _, c, x, y, a, s, _, _) { f(c, x, y, a, s) }, drawing=false)
}

///|
/// The scene gone through as each_drawn_scaled goes through it, `f` given besides where each would be drawn were
/// nothing in its way grown or shrunk (View::scale: where it is laid out and drawn off, what holds it so): where what
/// it draws is set on the pixels before it is drawn as big as it is, about that place (as an old view's are, painted
/// where they are laid out, then its looks).
pub fn Tree::each_drawn_laid(self : Tree, f : (Content, Double, Double, Double, Double, Double, Double) -> Unit) -> Unit {
  self.each_drawn_in_order(fn(_, _, c, x, y, a, s, ux, uy) { f(c, x, y, a, s, ux, uy) })
}

///|
/// Each of the nodes `ids` names as Tree::walk_drawn finds it (where it is drawn, as opaque and as big as it is, and
/// where it would be were nothing grown or shrunk: each_drawn_laid's), those it would find none of (let go, laid out
/// nowhere, in one that is, drawing nothing of their own) left out, in the order it goes through them: what reads a few
/// nodes of the scene (the old views hosted in it) reads them so, the tree not gone through for them. Each composed from
/// the root down as the walk composes it.
pub fn Tree::drawn_each(
  self : Tree,
  ids : Array[NodeId],
  drawing? : Bool = true,
) -> Array[(Content, Double, Double, Double, Double, Double, Double)] {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return []
  }
  let roots = self.root_layers()
  let found : Array[(Array[Int], (Content, Double, Double, Double, Double, Double, Double))] = []
  for id in ids {
    guard self.alive_id(id) && self.nodes[id.at].content is Some(c) else { continue }
    // (what holds it, from the root down)
    let chain : Array[Int] = []
    let mut i = id.at
    while i >= 0 {
      chain.push(i)
      i = self.nodes[i].parent
    }
    chain.rev_in_place()
    // (where it is gone through: by its place among what the root holds in the window's stack of layers, then among
    // what each that holds it holds)
    let key : Array[Int] = []
    let mut ok = true
    let mut ux = 0.0
    let mut uy = 0.0
    // (the first of its own the root holds it in: what is in a slot the root holds is the root's own, Tree::root_layers)
    let mut top = -1
    for k, at in chain {
      let n = self.nodes[at]
      if k > 0 && top < 0 && !n.slot {
        top = k
        match roots.search(at) {
          Some(j) => key.push(j)
          None => ok = false
        }
      } else if top >= 0 {
        match self.nodes[chain[k - 1]].kids.search(at) {
          Some(j) => key.push(j)
          None => ok = false
        }
      }
      if !n.slot {
        ux = ux + n.lx
        uy = uy + n.ly
      }
    }
    // (where it is drawn composed as the walk composes it, the one way: Tree::projected)
    if ok && !self.out_at(id.at) {
      let (x, y, a, s) = self.projected(id.at, drawing~)
      found.push((key, (c, x, y, a, s, ux, uy)))
    }
  }
  // (as the walk goes: by each place in turn, one that holds another before it, never by how deep)
  found.sort_by(fn(p, q) {
    let (a, b) = (p.0, q.0)
    let n = if a.length() < b.length() { a.length() } else { b.length() }
    for i in 0..<n {
      if a[i] != b[i] {
        return a[i].compare(b[i])
      }
    }
    a.length().compare(b.length())
  })
  found.map(fn(f) { f.1 })
}

///|
/// The scene gone through as each_drawn_laid goes through it, `f` given besides each one's place among what is drawn
/// (counted from 0 as each that draws is gone through) and that of the innermost of what holds it that draws (-1:
/// none).
fn Tree::each_drawn_in_order(
  self : Tree,
  f : (Int, Int, Content, Double, Double, Double, Double, Double, Double) -> Unit,
  drawing? : Bool = true,
) -> Unit {
  self.walk_drawn(f, drawing~, enter=fn(_, _, _, _, _) { true })
}

///|
/// The scene gone through down the tree in the order it is drawn (a node, then what it holds, its earlier kids before
/// its later; what the root holds by its place in the window's stack of layers: Tree::kids_in_order), each node of its
/// own composed from what holds it as it is gone into (a slot adds nothing of its own); none of a node left out of its
/// row (View::drops) nor of what it holds. `enter`: whether what node `at` holds is gone into, given where the node is
/// (x, y) and how big (s): what it says no to skipped whole, none of it visited. No order of every node is kept: what
/// is gone through is what is there (retained.md rule 13). `from`: that node's subtree alone, what holds it composed as
/// `held` says (where what holds it is in the window, how opaque, how big, and where it would be were nothing grown or
/// shrunk nor drawn off), as one layer is gone through again. `own`: `from` itself where `held` says (its own place,
/// opacity and size: at 0, 0 for a layer gone through in its own terms, Tree::placed_in), not composed from it.
fn Tree::walk_drawn(
  self : Tree,
  f : (Int, Int, Content, Double, Double, Double, Double, Double, Double) -> Unit,
  drawing~ : Bool,
  enter~ : (Int, Double, Double, Double, Bool) -> Bool,
  from? : Int = 0,
  held? : (Double, Double, Double, Double, Double, Double) = (0.0, 0.0, 1.0, 1.0, 0.0, 0.0),
  own? : Bool = false,
) -> Unit {
  if self.nodes.length() == 0 || !self.nodes[0].live || from < 0 || from >= self.nodes.length() || !self.nodes[from].live {
    return
  }
  let count = Ref(0)
  let g = self.pixel_grid
  fn go(
    at : Int,
    holder : Int,
    bx : Double,
    by : Double,
    ba : Double,
    bs : Double,
    hx : Double,
    hy : Double,
  ) -> Unit {
    let n = self.nodes[at]
    if n.slot {
      // (what holds it holds what it holds, in its place; asked of it as of a node where it bounds them)
      if enter(at, bx, by, bs, true) {
        for k in n.kids {
          go(k, holder, bx, by, ba, bs, hx, hy)
        }
      }
      return
    }
    if n.out {
      return
    }
    // (where it is in what holds it, drawn as big as that is; its own scale about its point: its origin drawn in as far
    // as that leaves it)
    // (drawn off where it is laid out, drawn only, by whole pixels where the host says how many a point: View::drawn_off)
    let (ox, oy) = if drawing { n.look.drawn_off } else { (0.0, 0.0) }
    // (whole pixels of the host's, in its own terms, as an old view's look's dx is before what holds it is drawn
    // bigger or smaller: draw.mbt's on_pixels(look.dx, scale))
    let (ox, oy) = if g > 0.0 && (ox != 0.0 || oy != 0.0) {
      ((ox * g).round() / g, (oy * g).round() / g)
    } else {
      (ox, oy)
    }
    let mine = own && at == from
    let x = if mine { bx } else { bx + bs * (n.lx + ox + (1.0 - n.ls) * n.lpx) }
    let y = if mine { by } else { by + bs * (n.ly + oy + (1.0 - n.ls) * n.lpy) }
    let a = if mine { ba } else { ba * n.la }
    let s = if mine { bs } else { bs * n.ls }
    // (and were nothing grown or shrunk nor drawn off: its words set on the pixels there, then drawn off by whole pixels,
    // as an old view's are painted where they are laid out and then moved by its look)
    let ux = if mine { hx } else { hx + n.lx }
    let uy = if mine { hy } else { hy + n.ly }
    let held = match n.content {
      Some(c) => {
        let i = count.val
        count.val = i + 1
        f(i, holder, c, x, y, a, s, ux, uy)
        i
      }
      None => holder
    }
    if enter(at, x, y, s, false) {
      // (what the root holds, each by its place in the window's stack of layers: Tree::kids_in_order)
      for k in self.kids_in_order(at) {
        go(k, held, x, y, a, s, ux, uy)
      }
    }
  }

  let (bx, by, ba, bs, hx, hy) = held
  go(from, -1, bx, by, ba, bs, hx, hy)
}

///|
/// The scene's input places gone through as Tree::each_taken goes through them, only where a finger or the pointer at
/// (x, y) may be found: what a node that bounds what it holds to itself (View::bounds_input) holds where the point is
/// past it, and what a node that takes no press of itself or what it holds (leaving, said to take none, in its bones:
/// Tree::pressless_own_at) holds, skipped whole. What it skips none of would take the point (Tree::finger_on: within
/// each of what bounds it, taking presses), so what it finds is what going through all of it found; what it goes
/// through is what is under the point, not the whole tree (retained.md rule 13). Counted (Work's hit_visited).
fn Tree::walk_taken(
  self : Tree,
  x : Double,
  y : Double,
  f : (Content, Double, Double, Double, Double) -> Unit,
) -> Unit {
  self.walk_drawn(
    fn(_, _, c, cx, cy, a, s, _, _) { f(c, cx, cy, a, s) },
    drawing=false,
    enter=fn(at, nx, ny, s, slot) {
      let n = self.nodes[at]
      self.work.hit_visited = self.work.hit_visited + 1
      if n.left_at >= 0.0 || n.inert || n.bones != 0L || (slot && n.out) {
        return false
      }
      if n.bounds_input {
        let (x1, y1) = (nx + n.flex.width * s, ny + n.flex.height * s)
        if x < nx || y < ny || x >= x1 || y >= y1 {
          return false
        }
      }
      // (what it cuts away as it is painted is not seen: nothing of it pressed there, View::clip_drawn)
      match n.look.clip_drawn {
        Some((cx, cy, cw, ch)) => {
          let (x0, y0) = (nx + cx * s, ny + cy * s)
          if x < x0 || y < y0 || x >= x0 + cw * s || y >= y0 + ch * s {
            return false
          }
        }
        None => ()
      }
      true
    },
  )
}

///|
/// A node's content unfolded where the window draws it, as big as it is drawn.
fn unfolded(c : Content, x : Double, y : Double, a : Double, s : Double) -> Drawn {
  {
    id: c.id,
    x,
    y,
    w: c.w * s,
    h: c.h * s,
    alpha: a,
    ground: c.ground,
    ink: c.ink,
    words: c.words,
    shapes: c.shapes,
    lines: c.lines,
    tint: c.tint,
    radius: c.radius,
    corners: c.corners,
    edge: c.edge,
    edge_dashed: c.edge_dashed,
    notch: c.notch,
    shadow_out: c.shadow_out,
    cut_across: c.cut_across,
    clip_drawn: c.clip_drawn,
    image: c.image,
    image_for: c.image_for,
    image_cover: c.image_cover,
    image_fade: c.image_fade,
    image_in: c.image_in,
    glass: c.glass,
    words_look: c.words_look,
    runs: c.runs,
    runs_look: c.runs_look,
    runs_pressed: c.runs_pressed,
    runs_picked: c.runs_picked,
    runs_lit: c.runs_lit,
    shadow: c.shadow,
    hosted: c.hosted,
    clips: c.clips,
    words_center: c.words_center,
    ellipsis_past: c.ellipsis_past,
    picture: c.picture,
    bones: c.bones,
    bone_as: c.bone_as,
  }
}

///|
/// The scene unfolded, in order (a new array: for a test, or a host taking the window whole).
pub fn Tree::drawn(self : Tree) -> Array[Drawn] {
  let out = []
  self.each_drawn_scaled(fn(c, x, y, a, s) { out.push(unfolded(c, x, y, a, s)) })
  out
}

///|
/// The scene unfolded as Tree::drawn has it, its corners as big as it is drawn too, each with what holds it as drawn (its index in the same array, -1: none
/// drawn round it) and whether it takes a press (View::on_press): for a check of where things stand in what holds them
/// (ui's corner rule).
pub fn Tree::drawn_held(self : Tree) -> Array[(Drawn, Int, Bool)] {
  let out : Array[(Drawn, Int, Bool)] = []
  // (each where it is among what is drawn, what holds it as drawn too)
  self.each_drawn_in_order(fn(_, h, c, x, y, a, s, _, _) {
    // (its corners as big as it is drawn, as its size is: where the window draws it, in the window's points)
    let d = {
      ..unfolded(c, x, y, a, s),
      radius: c.radius * s,
      corners: c.corners.map(fn(k) { (k.0 * s, k.1 * s, k.2 * s, k.3 * s) }),
    }
    out.push((d, h, self.nodes[c.id.at].on_press is Some(_)))
  })
  out
}

///|
/// The scene as Tree::drawn_held has it, but each where it is laid out (Tree::laid_origin) as big as it is laid out, its
/// corner too: where an old view hosted in it is laid out, as the old frame lays it out (view_host.mbt's old_place),
/// what it holds worked out against it before it is drawn (ui's corners said Inner).
pub fn Tree::laid_held(self : Tree) -> Array[(Drawn, Int, Bool)] {
  let out : Array[(Drawn, Int, Bool)] = []
  self.each_drawn_in_order(fn(_, h, c, x, y, a, _, _, _) {
    let (lx, ly) = self.laid_origin(c.id).unwrap_or((x, y))
    out.push((unfolded(c, lx, ly, a, 1.0), h, self.nodes[c.id.at].on_press is Some(_)))
  })
  out
}

///|
/// Whether this child supplies a box to the scene. Slots have no box of their own: look through them for what they
/// hold, and leave an empty slot out just as an absent child is.
fn Tree::child_drawn(self : Tree, at : Int) -> Bool {
  let child = self.nodes[at]
  if !child.live || child.out {
    false
  } else if child.slot {
    child.kids.iter().any(fn(k) { self.child_drawn(k) })
  } else {
    true
  }
}

///|
/// Whether node `id` holds a node of its own in the scene now (one living, not left out of its row): what is drawn over
/// its ground, under the edge round it (an old view's box's border_over: drawn after what it holds).
pub fn Tree::holds_drawn(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  self.nodes[id.at].kids.iter().any(fn(k) { self.child_drawn(k) })
}

///|
/// Whether node `inner` is `outer` or held by it (both alive as they are named): what it draws drawn in it.
pub fn Tree::holds(self : Tree, outer : NodeId, inner : NodeId) -> Bool {
  let alive = fn(id : NodeId) {
    id.at >= 0 && id.at < self.nodes.length() && self.nodes[id.at].live && self.nodes[id.at].gen == id.gen
  }
  if !alive(outer) || !alive(inner) {
    return false
  }
  let mut q = inner.at
  while q >= 0 {
    if q == outer.at {
      return true
    }
    q = self.nodes[q].parent
  }
  false
}

///|
/// Whether `id` is laid over its holder, and its own offset from where it is laid out (including its shift in its
/// own widths and heights). The provenance of its place, for checks that distinguish a mark on a small slot from
/// something standing in the corner of the larger box round it; not its composed position in the window.
pub fn Tree::own_placement(self : Tree, id : NodeId) -> (Bool, Double, Double) {
  guard self.alive_id(id) else { return (false, 0.0, 0.0) }
  let n = self.nodes[id.at]
  (n.flex.style.position == Absolute, n.look.dx + n.look.sx * n.flex.width, n.look.dy + n.look.sy * n.flex.height)
}

///|
/// Node `id` unfolded where the window draws it, where it lives and has been placed.
pub fn Tree::drawn_of(self : Tree, id : NodeId) -> Drawn? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  guard n.live && n.gen == id.gen && n.content is Some(c) && !self.out_at(id.at) else { return None }
  let (x, y, a, s) = self.projected(id.at, drawing=true)
  Some(unfolded(c, x, y, a, s))
}

///|
/// Where node `at` is drawn in the window, how opaque and how big (its scale and its holders'), as it was last placed:
/// composed from the window down as each_drawn_scaled composes it (a slot adds nothing of its own). The one way the
/// window's terms and a node's are told apart: where it is drawn, where it takes a finger, where it is read out.
fn Tree::projected(self : Tree, at : Int, drawing? : Bool = false) -> (Double, Double, Double, Double) {
  let chain = []
  let mut i = at
  while i >= 0 {
    if !self.nodes[i].slot {
      chain.push(i)
    }
    i = self.nodes[i].parent
  }
  let mut x = 0.0
  let mut y = 0.0
  let mut a = 1.0
  let mut s = 1.0
  for k = chain.length() - 1; k >= 0; k = k - 1 {
    let m = self.nodes[chain[k]]
    let (dx, dy) = if drawing { m.look.drawn_off } else { (0.0, 0.0) }
    let g = self.pixel_grid
    let (dx, dy) = if g > 0.0 { ((dx * g).round() / g, (dy * g).round() / g) } else { (dx, dy) }
    x = x + s * (m.lx + dx + (1.0 - m.ls) * m.lpx)
    y = y + s * (m.ly + dy + (1.0 - m.ls) * m.lpy)
    a = a * m.la
    s = s * m.ls
  }
  (x, y, a, s)
}

///|
/// Where node `id` is laid out in the window by its layout alone, as each_drawn_scaled goes down to it (a slot adds
/// nothing of its own): each holder's place in what holds it as laid out, with no offset (View::offset, a page slid
/// by its width), no scale, and none of what places one beside another (View::beside) — so what moves or fades it, or
/// what holds it, leaves it where it is, and only its layout moves it. Where what draws it as it is laid out (an old
/// view, hosted) is laid out once, and moved to where it is drawn (Tree::projected) as it is painted. None for one let go.
pub fn Tree::laid_origin(self : Tree, id : NodeId) -> (Double, Double)? {
  guard self.alive_id(id) else { return None }
  let mut x = 0.0
  let mut y = 0.0
  let mut i = id.at
  while i >= 0 {
    let n = self.nodes[i]
    if !n.slot {
      x = x + n.flex.left
      y = y + n.flex.top
    }
    i = n.parent
  }
  Some((x, y))
}

///|
/// A press at (x, y): the topmost node drawn there that does something when pressed does it, outside any tracking, as
/// one change. True if one did. Found where it is drawn (its holders' offsets with its own: View::rect).
pub fn Tree::press(self : Tree, x : Double, y : Double) -> Bool {
  // (one moment for all of it: what is where then, whatever frame came before)
  let at = self.time_now()
  self.bring_to(at)
  match self.target_at(x, y) {
    Pressed(id) => self.run_press_at(id, at)
    _ => false
  }
}

///|
/// What hosts the tree told as there is first something for a frame to do (it asks for a frame).
pub fn Tree::on_due(self : Tree, f : () -> Unit) -> Unit {
  self.on_due = f
}

///|
/// What hosts the tree told as what may take input changes (a modal layer said on, what is drawn over what, a node let
/// go, leaving, said to take no press), once the change doing it is committed whole: what it holds of its own (a press
/// held on an old view, a back gesture) asks whether it may still take input (Tree::takes_presses), at that cause.
pub fn Tree::on_modals(self : Tree, f : () -> Unit) -> Unit {
  self.on_modals = f
}

///|
/// A node drawn by what hosts the tree (the old view, built its own way, in this node's place, as it is laid out, drawn
/// off and drawn in order: retained.md's way there, 3), made by `make` as any node is (its size, its place; by default
/// the room its holder leaves it).
pub fn View::hosted(self : View, make? : (View) -> Unit = fn(v) { v.grow(Is(1.0)) |> ignore }) -> View {
  let tree = self.tree
  self.box(fn(v) {
    tree.nodes[v.at].hosted = true
    tree.hosting = v.at
    make(v)
  })
}

///|
/// Whether node `id` is all the tree draws or presses: every other node it draws (the window's aside) shows nothing and
/// takes no press (boxes that only lay out what they hold).
pub fn Tree::alone(self : Tree, id : NodeId) -> Bool {
  let mut alone = true
  self.each_drawn(fn(c, _, _, _) {
    if c.id != id && c.id.at != 0 {
      let n = self.nodes[c.id.at]
      if c.draws() || n.on_press is Some(_) || n.on_drag is Some(_) || n.top_row {
        alone = false
      }
    }
  })
  alone
}

///|
/// Whether something was told since it was last brought (a binding's read changed, a structure, a look): what hosts it
/// brings it before it draws (Tree::frame), whatever told it as the frame went (a message taken in it).
pub fn Tree::told_since(self : Tree) -> Bool {
  // A cause may already have laid out and placed its changes (laid_before_causes), clearing `due`. The host still
  // has to take that scene: its hosted views' positions and its kept instances belong to the preceding frame.
  self.due || self.drawn_due
}

///|
/// The node hosting the old view, where there is one.
pub fn Tree::hosting(self : Tree) -> NodeId? {
  if self.hosting < 0 {
    None
  } else {
    Some({ at: self.hosting, gen: self.nodes[self.hosting].gen })
  }
}

///|
/// What a press at a point is for: a node that does something when pressed, the old view in the node hosting it, or
/// nothing of the tree's.
pub(all) enum Target {
  Pressed(NodeId)
  Dragged(NodeId)
  Hosted(NodeId)
  /// a top row of the app's own, what moves the window (View::moves_window)
  TopRow(NodeId)
  /// a control said to take no press itself (View::presses: turned off), what holds it taking them: the press its, and
  /// nothing done with it; what lies under it not reached
  Off(NodeId)
  Nothing
} derive(Eq, Debug)

///|
/// Where a node takes a finger as it is drawn now (Tree::finger_areas).
pub(all) enum FingerAreas {
  /// rects of the window (x0, y0, x1, y1): none where it takes none
  InWindow(Array[(Double, Double, Double, Double)])
  /// all of it drawn, where what it hosts takes one (View::hosted_takes; a hosted node saying nothing of it)
  AsItHosts
} derive(Eq, Show, Debug)

///|
/// Where in the window node `id` takes a finger as it is drawn now, at the logic's moment (Tree::target_at's): none where
/// it is not drawn, or takes none (it or what holds it leaving or said to take none, a modal layer over it that it is
/// not in); where it hosts another's and says nothing else of it, as that finds it; else its box, or what it says it
/// takes of it (View::takes).
pub fn Tree::finger_areas(self : Tree, id : NodeId) -> FingerAreas {
  let none = InWindow([])
  guard self.alive_id(id) && !self.pressless_at(id.at) && self.nodes[id.at].content is Some(c) else { return none }
  let n = self.nodes[id.at]
  let (x, y, _, s) = self.projected(id.at)
  self.areas_of(n, x, y, c.w, c.h, s)
}

///|
/// (Node `n`, `w` by `h` in its own terms, drawn at (x, y) in the window `s` as big: where it takes a finger there.)
fn Tree::areas_of(self : Tree, n : Node, x : Double, y : Double, w : Double, h : Double, s : Double) -> FingerAreas {
  self.takes_said(n)
  match n.takes {
    Some(Areas(_)) => {
      // (read by what the node owns for it: Tree::takes_rects)
      let rs = self.takes_rects(n, w, h, self.logic_at())
      InWindow(
        rs
        .iter()
        .filter_map(fn(r) {
          let x0 = x + s * (if r.0 > 0.0 { r.0 } else { 0.0 })
          let y0 = y + s * (if r.1 > 0.0 { r.1 } else { 0.0 })
          let x1 = x + s * (if r.2 < w { r.2 } else { w })
          let y1 = y + s * (if r.3 < h { r.3 } else { h })
          if x1 > x0 && y1 > y0 {
            Some((x0, y0, x1, y1))
          } else {
            None
          }
        })
        .collect(),
      )
    }
    Some(AsHosted(_)) => AsItHosts
    None => if n.hosted { AsItHosts } else { InWindow([(x, y, x + w * s, y + h * s)]) }
  }
}

///|
/// Where in the window what of the tree's own is drawn over node `id` takes a finger now (a press or a hold: nodes drawn
/// after it, those it holds too, taking presses, each where it takes one: Tree::finger_areas), what it hosts not of
/// it: rects of the window (x0, y0, x1, y1). What a host drawing in it is told covers what it draws, with what is over
/// it of what it hosts.
pub fn Tree::taken_over(self : Tree, id : NodeId) -> Array[(Double, Double, Double, Double)] {
  let out = []
  guard self.alive_id(id) else { return out }
  let past = Ref(false)
  self.each_taken(fn(c, cx, cy, _, s) {
    if c.id == id {
      past.val = true
      return
    }
    if !past.val || self.pressless_at(c.id.at) {
      return
    }
    let n = self.nodes[c.id.at]
    if n.hosted || (n.on_press is None && n.on_drag is None && !n.top_row) {
      return
    }
    match self.areas_of(n, cx, cy, c.w, c.h, s) {
      InWindow(rs) => out.append(rs)
      AsItHosts => ()
    }
  })
  out
}

///|
/// Whether a press on node `id` moves the window now (View::moves_window).
pub fn Tree::moves_window(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].moves_window
}

///|
/// What a press at (x, y) is for: the topmost node drawn there (by the order drawn, where the scene composed draws it:
/// the same places as what is drawn) that is held (View::on_drag), does something when pressed or hosts the old view.
pub fn Tree::target_at(self : Tree, x : Double, y : Double) -> Target {
  self.target_in(x, y, tracked=false)
}

///|
/// The nodes drawn at (x, y) that would take a finger there (Tree::finger_on: within what bounds them, taking presses,
/// where they take it in their own terms), in the order drawn, the topmost last; as of the logic's moment (an event's,
/// Tree::bring_to): what is under what is let go there, whatever of them does anything with a press.
pub fn Tree::under(self : Tree, x : Double, y : Double) -> Array[NodeId] {
  let at = self.logic_at()
  let out : Array[NodeId] = []
  self.walk_taken(x, y, fn(c, cx, cy, _, s) {
    if self.finger_on(c, cx, cy, s, x, y, at, tracked=false) {
      out.push(c.id)
    }
  })
  out
}

///|
/// Whether a finger at (x, y) in the window is on what content `c` draws (drawn at (cx, cy), `s` as big: as the scene is
/// composed, Tree::projected) and is taken there: it is drawn there, takes presses (neither leaving nor held by what
/// is, nor said to take none), and takes it where it is in its own terms (View::takes, read `tracked` or not, as of
/// `at`).
fn Tree::finger_on(
  self : Tree,
  c : Content,
  cx : Double,
  cy : Double,
  s : Double,
  x : Double,
  y : Double,
  at : Double,
  tracked~ : Bool,
) -> Bool {
  if x < cx || y < cy || x >= cx + c.w * s || y >= cy + c.h * s || self.pressless_at(c.id.at) {
    return false
  }
  // (within what holds it bounds it to: View::bounds_input)
  let (bx0, by0, bx1, by1) = self.input_bounds(c.id)
  if x < bx0 || y < by0 || x >= bx1 || y >= by1 {
    return false
  }
  let n = self.nodes[c.id.at]
  let (lx, ly) = ((x - cx) / s, (y - cy) / s)
  if tracked {
    self.takes_here(n, lx, ly, c.w, c.h, at)
  } else {
    @signals.untracked(fn() { self.takes_here(n, lx, ly, c.w, c.h, at) })
  }
}

///|
/// The same, what decides where a node takes it (View::takes) read `tracked` (followed by what asks it: Tree::point_at)
/// or not.
fn Tree::target_in(self : Tree, x : Double, y : Double, tracked~ : Bool) -> Target {
  // (the logic's moment, what is where taken as of then: View::takes)
  let at = self.logic_at()
  let found : Array[Target] = []
  // (where the topmost found is drawn, and in what order of all gone through; what is drawn smaller than a press's
  // room that takes a press, each with its order and where it is drawn: reached from round it)
  let top_rect : Ref[(Double, Double, Double, Double)?] = Ref(None)
  let top_order = Ref(-1)
  let small : Array[(Int, Target, (Double, Double, Double, Double))] = []
  let order = Ref(0)
  let least = self.press_least
  self.walk_taken(x, y, fn(c, cx, cy, _, s) {
    order.val = order.val + 1
    let n = self.nodes[c.id.at]
    let target = if n.on_drag is Some(_) && n.claims is None {
      // (one that takes over holds (View::claims) takes none at its own down: it is found as it moves)
      Some(Dragged(c.id))
    } else if n.on_press is Some(_) {
      Some(Pressed(c.id))
    } else if n.hosted {
      Some(Hosted(c.id))
    } else if n.top_row {
      Some(TopRow(c.id))
    } else {
      None
    }
    // (one turned off (View::turned_off), what holds it taking presses: where it is drawn it takes the point and does
    // nothing with it, what lies under it not reached, as an old view's turned off control is; what holds it said to take
    // none (a page), none of it)
    if n.turned_off && self.blocks_at(c, cx, cy, s, x, y) {
      found.push(Off(c.id))
      top_rect.val = Some((cx, cy, cx + c.w * s, cy + c.h * s))
      top_order.val = order.val
      return
    }
    guard target is Some(t) else { return }
    if self.finger_on(c, cx, cy, s, x, y, at, tracked~) {
      found.push(t)
      top_rect.val = Some((cx, cy, cx + c.w * s, cy + c.h * s))
      top_order.val = order.val
    } else if least > 0.0 &&
      // (what a press does something with: not what is only held (a sheet's grip, a slider's track), as the old frame's
      // press_reach reaches only what takes a press)
      t is Pressed(_) &&
      n.takes is None &&
      (c.w * s < least || c.h * s < least) &&
      c.w > 0.0 &&
      c.h > 0.0 &&
      !self.pressless_at(c.id.at) {
      small.push((order.val, t, (cx, cy, cx + c.w * s, cy + c.h * s)))
    }
  })
  match self.reached(small, top_rect.val, top_order.val, x, y) {
    Some(t) => t
    None => self.chosen(found, x, y)
  }
}

///|
/// Of what takes a press drawn smaller than a press's room (`small`: each one's order among what was gone through, what
/// it is, where it is drawn), the one whose room holds (x, y): drawn over what (x, y) is on (`top`, in the order after
/// it) and within it, its room as wide and as tall as `press_least` about it, moved in from what it lies along (the
/// window, what bounds input to it) and cut to what it is on; the nearest of several (where rooms meet, each has the
/// part nearer it): a row's small button reached from round it, not the row's neighbour's, a pointer lit and a press
/// taken the same (the old frame's press_reach). None: what is drawn there takes it.
fn Tree::reached(
  self : Tree,
  small : Array[(Int, Target, (Double, Double, Double, Double))],
  top : (Double, Double, Double, Double)?,
  top_order : Int,
  x : Double,
  y : Double,
) -> Target? {
  let least = self.press_least
  if least <= 0.0 || small.is_empty() {
    return None
  }
  let (ww, wh) = (self.last_w, self.last_h)
  let room = fn(lo : Double, hi : Double, clo : Double, chi : Double, elo : Double, ehi : Double) {
    let mut a = lo
    let mut b = hi
    if hi - lo < least {
      let mid = (lo + hi) / 2.0
      a = mid - least / 2.0
      b = mid + least / 2.0
      // (moved in from an edge it passes, not cut short at it)
      if a < elo {
        b = b + (elo - a)
        a = elo
      }
      if b > ehi {
        a = a - (b - ehi)
        b = ehi
      }
    }
    (dmax(a, dmax(clo, elo)), dmin(b, dmin(chi, ehi)))
  }
  let mut best : Target? = None
  let mut best_d = 1.0e18
  for e in small {
    let (k, t, (x0, y0, x1, y1)) = e
    if k <= top_order {
      continue
    }
    let cut = match top {
      Some((t0, t1, t2, t3)) => {
        if x0 < t0 || y0 < t1 || x1 > t2 || y1 > t3 {
          continue
        }
        (t0, t1, t2, t3)
      }
      None => (0.0, 0.0, ww, wh)
    }
    let id = match t {
      Pressed(id) | Dragged(id) => id
      _ => continue
    }
    let (bx0, by0, bx1, by1) = self.input_bounds(id)
    let (rx0, rx1) = room(x0, x1, cut.0, cut.2, dmax(0.0, bx0), dmin(ww, bx1))
    let (ry0, ry1) = room(y0, y1, cut.1, cut.3, dmax(0.0, by0), dmin(wh, by1))
    if x < rx0 || x >= rx1 || y < ry0 || y >= ry1 {
      continue
    }
    let dx = dmax(0.0, dmax(x0 - x, x - x1))
    let dy = dmax(0.0, dmax(y0 - y, y - y1))
    let d = dx * dx + dy * dy
    if d < best_d {
      best_d = d
      best = Some(t)
    }
  }
  best
}

///|
/// What is pointed at (View::pointed) where the pointer followed (Tree::follow_point) is over `t`, the one way the tree
/// and what hosts it say it: what says it is pointed at alone over all that takes it there (View::points); else what
/// takes a press or a hold there; else nothing.
pub fn Tree::pointed_of(self : Tree, t : Target) -> NodeId? {
  match self.points_hover {
    Some(id) => Some(id)
    None =>
      match t {
        Pressed(id) | Dragged(id) => Some(id)
        _ => None
      }
  }
}

///|
/// What says it is pointed at alone (View::points) the pointer followed (Tree::follow_point) is over, where that is over
/// all that takes the pointer there: what is lit there and shapes the pointer (View::cursor), whatever is under it; none,
/// what takes it there does (Tree::pointed_of).
pub fn Tree::points_now(self : Tree) -> NodeId? {
  self.points_hover
}

///|
/// What says it is pointed at alone (View::points) the pointer at (x, y) is over, where that is drawn over all that
/// takes it there (what target_in finds: what presses, what is held, an old view, a top row): followed, as target_in.
fn Tree::points_over(self : Tree, x : Double, y : Double) -> NodeId? {
  let at = self.logic_at()
  let found : Ref[NodeId?] = Ref(None)
  self.walk_taken(x, y, fn(c, cx, cy, _, s) {
    if self.finger_on(c, cx, cy, s, x, y, at, tracked=true) {
      let n = self.nodes[c.id.at]
      if n.points {
        found.val = Some(c.id)
      } else if (n.on_drag is Some(_) && n.claims is None) || n.on_press is Some(_) || n.hosted || n.top_row {
        found.val = None
      }
    }
  })
  found.val
}

///|
/// What takes a finger at (x, y) of `found` (all that takes it there, in the order they are drawn): the topmost, unless
/// the host says another of them does (Tree::on_target); none, nothing. Only one of `found`, whatever the host says.
fn Tree::chosen(self : Tree, found : Array[Target], x : Double, y : Double) -> Target {
  match found.last() {
    Some(t) => {
      let said = (self.retarget)(t, found, x, y)
      if found.contains(said) {
        said
      } else {
        t
      }
    }
    None => Nothing
  }
}

///|
/// What hosts the tree tells what it found takes a finger at (x, y) in the window (the topmost of `found`, all that
/// takes it there in the order they are drawn), and asks what takes it instead (one of `found`): for what one node
/// hosted said of another (that it yields a point to what that one hosts takes there). Not said: what was found.
pub fn Tree::on_target(self : Tree, f : (Target, Array[Target], Double, Double) -> Target) -> Unit {
  self.retarget = f
}

///|
/// What hosts the tree is told as a column of it gliding on by itself sets out (View::scrolls' fling: let go at a
/// speed), `glides`: which column (its own number) and how to ask when its glide ends as it is then (none: at rest,
/// held again, stopped), what waits on what moves (a test's run to rest) reading it as an old view's list's glide; and,
/// `gone`, as that column is let go.
pub fn Tree::on_glides(self : Tree, glides : (Int, () -> Double?) -> Unit, gone : (Int) -> Unit) -> Unit {
  self.glides = glides
  self.glides_gone = gone
}

///|
/// `f` done once all of it is laid out as it is next (sizes told: View::laid_size_told), as one with that layout, whether
/// anything it follows came out otherwise or not: what waits on where a change it made leaves things (a page's list's
/// fling toward its foot as what is above it grew, Scroll::grew_above).
fn Tree::once_laid_out(self : Tree, f : () -> Unit) -> Unit {
  self.laid_waits.push(f)
  self.marked()
}

///|
/// `f` done once all of it is laid out as it is next (Tree::once_laid_out: every pass over, the sizes told), the node's:
/// not done where the node is let go before. What is to be done where things are once laid out (a menu put beside what
/// it was opened from, a list scrolled to what it is to show), never as the frame is built or what the host says comes.
/// What `f` reads of the layout told (View::laid_size_told, laid_window_told) is this layout's, where it was asked once
/// before: a told value is followed only from its first asking, none till a layout after that.
pub fn View::once_laid_out(self : View, f : () -> Unit) -> Unit {
  guard self.alive() else { return }
  self.tree.once_laid_out(fn() {
    if self.alive() {
      f()
    }
  })
}

///|
/// How a page's list (Scroll::list) moves where what hosts the tree draws it, as it is asked (as the platform's own
/// lists: an old view's list's way there), and how many pixels a point is there (Android's fling and stretch are in
/// them); none said, the desktop's, at 1.
pub fn Tree::lists_feel(self : Tree, f : () -> (ListFeel, Double)) -> Unit {
  self.list_feel = f
}

///|
/// Node `id` pressed (Tree::target_at's): its callback run outside any tracking, as one change, if it lives.
pub fn Tree::run_press(self : Tree, id : NodeId) -> Bool {
  self.run_press_at(id, self.time_now())
}

///|
/// Node `id` pressed as a screen reader asks it, at `at`: as one event of that moment, what had ended by then settled
/// first, what it says worked out as of then, then asked whether it is read out so (it says what it is, nothing over it
/// hides it: Tree::said_now), whether it takes a press now as a finger's would be taken (it lives, takes presses, is
/// held by no modal layer it is not in) and has something done by one; only then its press. Whether it was.
pub fn Tree::activate_at(self : Tree, id : NodeId, at : Double) -> Bool {
  let pressed = Ref(false)
  self.event(at, fn() {
    // (what it says as of then: its bindings marked worked out first, Tree::pull)
    self.pull()
    if !self.takes_presses(id) || !self.allows(id) || self.leaving_at(id.at) || !self.said_now(id.at) ||
      self.nodes[id.at].turned_off {
      return
    }
    match self.nodes[id.at].on_press {
      Some(f) => {
        pressed.val = true
        f()
      }
      None => ()
    }
  })
  pressed.val
}

///|
/// Whether node `id` lives (this making of its index).
pub fn Tree::lives(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id)
}

///|
/// Whether what node `id` holds may be read out and acted on as a screen reader asks, as the tree is now (its bindings
/// marked worked out first): it lives, no modal layer it is not in is over it, neither it nor what holds it is kept
/// from what is read out (View::hides). What an old view hosted in it says, read so.
pub fn Tree::reads_out(self : Tree, id : NodeId) -> Bool {
  self.pull()
  // (left out of its row, or held by what is: nothing of it read out, Tree::out_at)
  if !self.alive_id(id) || !self.allows(id) || self.out_at(id.at) {
    return false
  }
  let mut i = id.at
  while i >= 0 {
    // (nor in its bones: View::bones)
    if self.nodes[i].said_hidden || self.nodes[i].bones != 0L {
      return false
    }
    i = self.nodes[i].parent
  }
  true
}

///|
/// Whether what node `id` holds may be acted on as a screen reader asks, as the tree is now: read out (Tree::reads_out),
/// taking presses (View::presses: neither it nor what holds it off), not leaving.
pub fn Tree::acts_on(self : Tree, id : NodeId) -> Bool {
  self.reads_out(id) && self.takes_presses(id) && !self.leaving_at(id.at)
}

///|
/// Whether node `at` is read out as it is now: it says what it is, and neither it nor what holds it is kept from what is
/// read out (View::hides).
fn Tree::said_now(self : Tree, at : Int) -> Bool {
  if self.nodes[at].said is None {
    return false
  }
  let mut i = at
  while i >= 0 {
    // (nor in its bones: View::bones)
    if self.nodes[i].said_hidden || self.nodes[i].bones != 0L {
      return false
    }
    i = self.nodes[i].parent
  }
  true
}

///|
/// Whether node `id` has something done by a press (View::on_press), whatever it takes now.
pub fn Tree::presses_do(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].on_press is Some(_)
}

///|
/// Node `id` pressed at `at`: as one event of that moment (Tree::event), what had ended by then settled first, and only
/// then is it looked for (one let go by then presses nothing) and its callback run.
pub fn Tree::run_press_at(self : Tree, id : NodeId, at : Double) -> Bool {
  let pressed = Ref(false)
  self.event(at, fn() {
    if id.at < 0 || id.at >= self.nodes.length() {
      return
    }
    let n = self.nodes[id.at]
    // (as a press there would be: what takes none, under a modal layer, left out of its row, none: Tree::takes_presses;
    // as of then: what closes a room under it, called at that moment, leaves nothing in it to press)
    if !n.live || n.gen != id.gen || self.leaving_at(id.at) || !self.takes_presses(id) || !self.allows(id) {
      return
    }
    match n.on_press {
      Some(f) => {
        pressed.val = true
        f()
      }
      None => ()
    }
  })
  pressed.val
}

///|
/// `f` done with what `read` gives (as it is now, then as of each change of it: at its cause's moment, committed as a
/// structure's change is), whatever frames are drawn: what is to be done as a state comes to hold, said so, never found
/// by watching it frame by frame. The node's: done no more once it is let go.
pub fn[T : Eq] View::reacts(self : View, read : () -> T, f : (T) -> Unit) -> Unit {
  // (made, and done each time, owned by the node's scope: what it makes let go with the node, its watch none of what
  // was running as it was said, whose running again would let it go)
  self.owning(fn() {
    let stop = self.tree.structured(read, fn(v) { self.owning(fn() { f(v) }) })
    self.owns(stop) |> ignore
  })
}

///|
/// `f` done once at the moment `when` of the one clock (its timeline: in its turn among what is due, as of then;
/// Tree::advance), whatever frames are drawn: what is to show, go or be done at a moment said so, never found by watching
/// the clock. The node's: not done once it is let go, or once what it returns is called. What is to be done is waited
/// for, as what has yet to happen (Tree::wake_waited: a test's run goes on to it, and is not idle before it); `later`,
/// not: a time what is shown does not wait for (a toast's time on screen), as an old view's wake said `later` is.
pub fn View::at_moment(self : View, when : Double, f : () -> Unit, later? : Bool = false) -> () -> Unit {
  guard self.live() is Some(_) else { return fn() {  } }
  let live = Ref(true)
  let tree = self.tree
  // (kept by the node till done, called off, or the node goes: once, whichever comes first)
  let unkeep : Ref[() -> Unit] = Ref(fn() {  })
  let stop = fn() {
    if live.val {
      live.val = false
      (unkeep.val)()
      tree.unschedule(live)
    }
  }
  unkeep.val = self.owns_while(stop)
  let done = fn() {
    live.val = false
    (unkeep.val)()
    f()
  }
  tree.timeline.push(Once({ at: when, f: done, live, later }, tree.told))
  tree.told = tree.told + 1
  tree.marked()
  stop
}

///|
/// The node held now (`h`, none): the one it was on and the one it is on now told, each by its own cell (View::pressed),
/// nothing else.
fn Tree::held_to(self : Tree, h : NodeId?) -> Unit {
  let was = self.held
  self.held = h
  // (held by another, or by none: what a still hold of the one before was to hand on, no more)
  match self.through {
    Some(th) if h != Some(th.cover) => self.through = None
    _ => ()
  }
  if was != h {
    self.pressing = h
    self.hand_told(was, fn(n) { n.pressed_cell }, false)
    self.hand_told(h, fn(n) { n.pressed_cell }, true)
  }
}

///|
/// Node `id`'s cell (`cell` of it, where one was made: something reads it) told `on`, where it lives.
fn Tree::hand_told(self : Tree, id : NodeId?, cell : (Node) -> @signals.Signal[Bool]?, on : Bool) -> Unit {
  guard id is Some(i) && self.alive_id(i) else { return }
  match cell(self.nodes[i.at]) {
    // (every node lit for what measures the hand: Tree::lit_all)
    Some(s) => s.set(on || self.lit_every)
    None => ()
  }
}

///|
/// Whether a finger or the pointer is held on it now (from its down till it is let go or called off): what reads it
/// told only as that comes or goes. Its cell made as first read, let go with it.
pub fn View::pressed(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.pressed_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.lit_every || self.tree.pressing == Some(self.id()), same=fn(a, b) { a == b })
      n.pressed_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// Whether the pointer is over it now, of what takes a press there the topmost (Tree::point_at): what reads it told only
/// as the pointer comes over it or leaves it. Its cell made as first read, let go with it.
pub fn View::pointed(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.pointed_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.lit_every || self.tree.pointed == Some(self.id()), same=fn(a, b) { a == b })
      n.pointed_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// Whether the pointer is over it or over what it holds now, of what takes a press there the topmost (View::pointed: the
/// topmost that takes it, it or one in it; not where something else over it takes it, nor where it is only within its
/// box), as an old view's `hovered` is of what its target holds: what reads it told only as that comes and goes. Its cell
/// made as first read, let go with it.
pub fn View::pointed_in(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.pointed_in_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.lit_every || self.tree.pointed_within_at(self.at), same=fn(a, b) { a == b })
      n.pointed_in_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// (Whether what the pointer is over, of what takes a press, is node `at` or held by it.)
fn Tree::pointed_within_at(self : Tree, at : Int) -> Bool {
  guard self.pointed is Some(p) && self.alive_id(p) else { return false }
  let mut i = p.at
  while i >= 0 {
    if i == at {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// The pointer at (x, y) in the window (a mouse's: a finger points at nothing), as of now: what takes a press there, the
/// topmost, is pointed at (View::pointed), nothing else; none where (x, y) is none (the pointer gone). The one it was
/// over and the one it is over now told, nothing else.
pub fn Tree::point_at(self : Tree, x : Double, y : Double) -> Unit {
  // (none: nothing followed, nothing pointed at from now)
  if x < 0.0 || y < 0.0 {
    self.pointer_now(x, y)
    self.point_stopped()
    self.pointed_to(None)
    return
  }
  self.follow_point(x, y, fn(t) { self.pointed_to(self.pointed_of(t)) })
}

///|
/// What it does as the pointer moves onto it or over it (a mouse's, as it is pointed at: View::pointed), at that
/// moment: the pointer's own moving alone, never the layout or the order putting it under a pointer that stays still.
pub fn View::on_pointer_moved(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_pointer_moved = Some(f)
  self
}

///|
/// What is at (x, y) followed (Tree::target_at, what decides where a node takes it (View::takes) read so): `then` told
/// it now and as it changes, whatever it is (a node's, the old view's, nothing), till the next point is followed, or
/// none (x or y below 0: nothing told, nothing followed), or the tree is let go. What is where, as the layout or the
/// order changes, is followed by being said again (Tree::hits_said).
pub fn Tree::follow_point(self : Tree, x : Double, y : Double, then : (Target) -> Unit) -> Unit {
  // (the pointer moved: what it is over as this is first told told so after `then`, View::on_pointer_moved, whoever
  // follows it (Tree::point_at, what hosts the tree); what comes under it after as the layout or the order changes, or
  // the same point followed again, not)
  let moved = Ref(x >= 0.0 && y >= 0.0 && self.pointer_xy != (x, y))
  let then = fn(t : Target) {
    then(t)
    if moved.val {
      moved.val = false
      // (to what is pointed at there, the one way it is said: what is pointed at alone over all else there, else what
      // takes a press or a hold there, Tree::pointed_of)
      match self.pointed_of(t) {
        Some(id) if self.alive_id(id) =>
          match self.nodes[id.at].on_pointer_moved {
            Some(f) => @signals.untracked(f)
            None => ()
          }
        _ => ()
      }
    }
  }
  self.pointer_now(x, y)
  self.point_stopped()
  // (what it was over, said anew as it is found)
  self.points_hover = None
  if x < 0.0 || y < 0.0 {
    return
  }
  // (this one the one followed from now: what it is first told may let it go (another point, none, the tree let go),
  // which this one's number then no longer is)
  let mine = self.point_said
  let stop = self.queued(fn() { (self.target_in(x, y, tracked=true), self.points_over(x, y)) }, fn(found) {
    self.points_hover = found.1
    then(found.0)
  })
  if self.gone || self.point_said != mine {
    stop()
  } else {
    self.point_stop = Some(stop)
  }
}

///|
/// The pointer at (x, y) in the window as it is said (none: below 0), what is followed there (Tree::follow_point, the
/// host's way and Tree::point_at's): where it is kept, and only where it moved, what goes beside its point placed again
/// (View::beside's `at_pointer`: its place alone, nothing laid out again).
fn Tree::pointer_now(self : Tree, x : Double, y : Double) -> Unit {
  let p = if x < 0.0 || y < 0.0 { (-1.0, -1.0) } else { (x, y) }
  if self.pointer_xy == p {
    return
  }
  self.pointer_xy = p
  self.withins_told() |> ignore
  for at in self.besides_at {
    match self.nodes[at].beside {
      Some(b) if b.at_pointer && self.nodes[at].live => self.place_marked_at(at)
      _ => ()
    }
  }
}

///|
/// Whether the pointer (a mouse's: a finger points at nothing) is within it as it was last placed (where it is drawn,
/// as big as it is laid out, its holders' place and scale with it), whatever is over it there and whether it takes
/// presses (View::pointed: only what takes them, the topmost), followed: what reads it told as the pointer comes in or
/// goes out, by its moving or by what is placed moving under it (Tree::withins_told: at the pointer's each move and
/// as the frame places what changed). A bar shown while the pointer is along the top, under the bar as it shows.
pub fn View::pointer_within(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  let s = match n.within_cell {
    Some(s) => s
    None => {
      let s = @signals.signal(self.tree.within(self.at), same=fn(a, b) { a == b })
      n.within_cell = Some(s)
      // (once for both it and where the pointer is in it: View::pointer_here_told)
      if n.here_cell is None {
        self.tree.withins_at.push((self.at, n.gen))
      }
      s
    }
  }
  s.get()
}

///|
/// Whether the pointer is within node `at` as it was last placed (none placed yet: not).
fn Tree::within(self : Tree, at : Int) -> Bool {
  let (px, py) = self.pointer_xy
  if px < 0.0 || py < 0.0 || self.nodes.length() == 0 || self.last_w <= 0.0 {
    return false
  }
  let n = self.nodes[at]
  let (x, y, s) = self.placed(at)
  px >= x && px < x + n.lw * s && py >= y && py < y + n.lh * s
}

///|
/// Each node whose being under the pointer is read told it again, as it is now (the pointer moved, or what is placed):
/// those let go dropped. Whether any was told otherwise.
fn Tree::withins_told(self : Tree) -> Bool {
  let keep = []
  let mut changed = self.bars_near_told()
  for w in self.withins_at {
    let (at, gen) = w
    let n = self.nodes[at]
    if !n.live || n.gen != gen {
      continue
    }
    match n.within_cell {
      Some(cell) => {
        let now = self.within(at)
        if @signals.untracked(fn() { cell.get() }) != now {
          changed = true
          cell.set(now)
        }
      }
      None => ()
    }
    match n.here_cell {
      Some(cell) => {
        let now = self.pointer_in(at)
        if @signals.untracked(fn() { cell.get() }) != now {
          changed = true
          cell.set(now)
        }
      }
      None => ()
    }
    if n.within_cell is Some(_) || n.here_cell is Some(_) {
      keep.push(w)
    }
  }
  self.withins_at.clear()
  self.withins_at.append(keep)
  changed
}

///|
/// Whether the pointer is along its right edge, `near` in from it (0: it has no bar to come out now, nothing to scroll),
/// as what scrolls the bar of comes out there (a column that scrolls, its bar: scroll_bar.mbt), followed: of all those, the last drawn the pointer is in (the innermost of
/// those holding one another, the upper of those over one another; where what holds it lets it be found, taking input:
/// Tree::input_bounds), if the pointer is along its edge; none where that one's is not (as an old view's bar_near_at
/// takes the innermost box that scrolls there). Told as the pointer moves, as the frame places what changed, and as
/// what is drawn or found there changes otherwise.
pub fn View::bar_near(self : View, near : Double, across? : Bool = false) -> Bool {
  guard self.live() is Some(n) else { return false }
  // (said anew, none where it has no bar now (nothing to scroll: 0): which one the pointer is along told anew too)
  if n.bar_near != near || n.bar_across != across {
    n.bar_near = near
    n.bar_across = across
    self.tree.bars_due = true
    self.tree.marked()
  }
  let cell = match n.bar_near_cell {
    Some(c) => c
    None => {
      let c = @signals.signal(self.tree.bar_near_at() == Some(self.at), same=fn(a, b) { a == b })
      n.bar_near_cell = Some(c)
      self.tree.bar_cols.push((self.at, self.gen))
      c
    }
  }
  cell.get()
}

///|
/// The column whose bar the pointer is along now (View::bar_near): of those, the last drawn the pointer is in (found
/// there within what holds it, taking input), if the pointer is along its edge.
fn Tree::bar_near_at(self : Tree) -> Int? {
  let (px, py) = self.pointer_xy
  guard px >= 0.0 && self.nodes.length() > 0 else { return None }
  // (of the columns whose bars come out so, the last drawn the pointer is in, found there within what holds it and
  // taking input: the innermost of those holding one another, the upper of those over one another; nothing else drawn
  // counts, its bar's own room over it none of it)
  let top : Ref[Int] = Ref(-1)
  self.walk_taken(px, py, fn(c, cx, cy, _, s) {
    let n = self.nodes[c.id.at]
    if n.bar_near > 0.0 &&
      n.bar_near_cell is Some(_) &&
      !self.pressless_at(c.id.at) &&
      px >= cx &&
      py >= cy &&
      px < cx + c.w * s &&
      py < cy + c.h * s {
      let (bx0, by0, bx1, by1) = self.input_bounds(c.id)
      if px >= bx0 && py >= by0 && px < bx1 && py < by1 {
        top.val = c.id.at
      }
    }
  })
  let i = top.val
  if i >= 0 {
    let n = self.nodes[i]
    let (x, y, sc) = self.placed(i)
    // (how near its edge in the window's points, the hand's, whatever it is drawn as big as: its right, or its foot
    // where its bar is along that, View::bar_near's `across`)
    if n.bar_across {
      let foot = y + n.flex.height * sc
      return if py >= foot - n.bar_near && py < foot { Some(i) } else { None }
    }
    let right = x + n.flex.width * sc
    return if px >= right - n.bar_near && px < right { Some(i) } else { None }
  }
  None
}

///|
/// Which column's bar the pointer is along (View::bar_near) told anew, each that follows it: whether any was told
/// otherwise.
fn Tree::bars_near_told(self : Tree) -> Bool {
  self.bars_due = false
  guard self.bar_cols.length() > 0 else { return false }
  let at = self.bar_near_at()
  let keep = []
  let mut changed = false
  for e in self.bar_cols {
    let (i, gen) = e
    let n = self.nodes[i]
    match n.bar_near_cell {
      Some(cell) if n.live && n.gen == gen => {
        let now = at == Some(i)
        if @signals.untracked(fn() { cell.get() }) != now {
          changed = true
          cell.set(now)
        }
        keep.push(e)
      }
      _ => ()
    }
  }
  self.bar_cols.clear()
  self.bar_cols.append(keep)
  changed
}

///|
/// The pointer at (x, y) in the window, where it is and nothing followed there (none: below 0): what is under the
/// pointer by where it is told so (View::pointer_within), whatever is over it then that takes it (an old view's layer
/// over all of it: what it points at the old view's), as only the pointer's going or a finger's coming says none.
pub fn Tree::pointer_is(self : Tree, x : Double, y : Double) -> Unit {
  self.pointer_now(x, y)
}

///|
/// What is at the pointer followed no more (Tree::follow_point), its place kept as it is: over what an old view's layer
/// over all of it takes, the pointer still where it is (Tree::pointer_is).
pub fn Tree::unfollow(self : Tree) -> Unit {
  self.point_stopped()
}

///|
/// What follows the point let go (Tree::follow_point): told nothing more.
fn Tree::point_stopped(self : Tree) -> Unit {
  // (what is being made to follow one no longer the one: Tree::follow_point)
  self.point_said = self.point_said + 1
  match self.point_stop {
    Some(stop) => stop()
    None => ()
  }
  self.point_stop = None
}

///|
/// What the pointer is over now `now`, of what takes a press there (View::pointed): the one it was over and the one it
/// is over told, as they change.
pub fn Tree::pointed_to(self : Tree, now : NodeId?) -> Unit {
  let was = self.pointed
  if was != now {
    self.pointed = now
    self.hand_told(was, fn(n) { n.pointed_cell }, false)
    self.hand_told(now, fn(n) { n.pointed_cell }, true)
    // (and what holds either, as what it is over comes into it or leaves it: View::pointed_in)
    for id in [was, now] {
      guard id is Some(i) && self.alive_id(i) else { continue }
      let mut at = i.at
      while at >= 0 {
        match self.nodes[at].pointed_in_cell {
          Some(c) => c.set(self.lit_every || self.pointed_within_at(at))
          None => ()
        }
        at = self.nodes[at].parent
      }
    }
  }
}

///|
/// How many times what a point hits may have changed so far (Tree's `hits`): what is pointed at by a still pointer
/// is worked out again past one, not every frame.
pub fn Tree::hits_said(self : Tree) -> Int {
  self.hits
}

///|
/// What the pointer is over now, of what takes a press there (Tree::point_at), None nothing.
pub fn Tree::pointed_now(self : Tree) -> NodeId? {
  self.pointed
}

///|
/// Whether node `a` is drawn after node `b` as the tree is now (after what holds it, after what is before it among what
/// holds them both: Tree::path_of): what is over what, of two that take the same input. False where either is held by
/// nothing the root holds.
pub fn Tree::drawn_later(self : Tree, a : NodeId, b : NodeId) -> Bool {
  guard self.alive_id(a) && self.alive_id(b) else { return false }
  match (self.layer_path(a.at), self.layer_path(b.at)) {
    (Some(pa), Some(pb)) => drawn_after(pa, pb)
    _ => false
  }
}

///|
/// The rows of its lists made by their keys (View::each) that live now, each by its node: what a test reads to tell
/// rows kept as their nodes from rows made anew.
pub fn Tree::rows_alive(self : Tree) -> Array[NodeId] {
  let out = []
  for i, n in self.nodes {
    if n.live && n.each_row {
      out.push({ at: i, gen: n.gen })
    }
  }
  out
}

///|
fn Tree::alive_id(self : Tree, id : NodeId) -> Bool {
  id.at >= 0 && id.at < self.nodes.length() && self.nodes[id.at].live && self.nodes[id.at].gen == id.gen
}

///|
/// Where what is laid out may not be read now (what the host has once handed on, before anything is laid out:
/// @ui.on_host_said): why. None: it may be read.
let layout_reads_shut : Ref[String?] = Ref(None)

///|
/// What a run leaves here forgotten (a Tester starting): what was shut around a hand-off is put back as it ends, but a
/// run stopped in one (a test that aborts there, as it should) leaves it shut, and every run after it faults where it
/// reads what is laid out.
pub fn reset_globals() -> Unit {
  layout_reads_shut.val = None
  laid_passes_traced.val = false
  laid_passes_trace.val = fn(s) { println(s) }
  // (what a node lends, let go with it: one a stopped run made is never let go)
  windowed_room.lenders.clear()
  runs_liter.lenders.clear()
  runs_picker.lenders.clear()
}

///|
/// From now on what is laid out may not be read (`why`: where), until it is put back with what this gives (None: it may
/// be read). Only ui's hand-off of what the host has once (host_said_arrive) says it; an app never does. What is shut is
/// what this frame has yet to lay out, read as if it were: where it was placed (placed_window_now) and the sizes and
/// places told (laid_size_told, laid_window_told). A read that lays it out there and then, as of the logic's moment
/// (laid_size, laid_window_now: how big a thing is at a change, a slide's length said by it), is not of them: it may
/// be read.
pub fn shut_layout_reads(why : String?) -> String? {
  let was = layout_reads_shut.val
  layout_reads_shut.val = why
  was
}

///|
/// `g` done as one of a node's own reads, what is laid out open to it, shut again after it as it was. The boundary of
/// shut_layout_reads (@ui.on_host_said's): every node's own binding (Tree::queued: a property said By) and structure
/// (Tree::structured: show, pick, each, View::reacts) reads what is laid out as told last, wherever it runs, a hand-off's
/// write having set it off or a node made in it; what is shut is the hand-off's own code alone, what it reads itself.
fn[T] reads_own(g : () -> T) -> T {
  let was = layout_reads_shut.val
  layout_reads_shut.val = None
  let r = g()
  layout_reads_shut.val = was
  r
}

///|
/// A read of what is laid out (`what`), where none may be: a fault (stopped in a test's run, told the host once).
fn layout_read(what : String) -> Unit {
  match layout_reads_shut.val {
    Some(why) => fault("View::\{what} read in \{why}: nothing is laid out yet there")
    None => ()
  }
}

///|
/// The properties said `Painted` worked out, from where the frame's layout put things (Laid): each set where it came out
/// otherwise, its node placed or drawn again as any property of its phase is.
fn Tree::painted_now(self : Tree) -> Unit {
  if self.painted.is_empty() {
    return
  }
  for e in self.painted.copy() {
    (e.2)()
  }
}

///|
/// Where it is in the window and how big, as the tree last placed it (the frame on screen, or brought to an event's
/// moment: where a press finds things): for an input event's handler and a hit test (a menu opened beside what was
/// pressed, where a row was for a jump), never followed. None: let go, or laid out nowhere.
pub fn View::shown_rect(self : View) -> (Double, Double, Double, Double)? {
  { tree: self.tree }.rect(self)
}

///|
/// How big it is as the tree last placed it (View::shown_rect's terms). None: let go, or laid out nowhere.
pub fn View::shown_size(self : View) -> (Double, Double)? {
  { tree: self.tree }.size(self)
}

///|
/// `f` told once the frame being made is painted (Tree::take_after_paint).
fn Tree::said_after_paint(self : Tree, f : () -> Unit) -> Unit {
  self.after_paint.push(f)
}

///|
/// What was said to be told once the frame is painted, taken: the host's side runs each, in order, after it paints the
/// frame (a list's rows sighted, View::scrolls_anchored's `sighted`; a node first drawn, View::on_first_drawn). Events
/// of that frame's moment: what they ask the host for (a picture, the keyboard) they ask; they set nothing the frame read.
pub fn Tree::take_after_paint(self : Tree) -> Array[() -> Unit] {
  let out = self.after_paint.copy()
  self.after_paint.clear()
  out
}

///|
/// `f` told as the layout being done is done, of its moment (Tree::brought: a frame's, an input's), before anything
/// after it is handled, whether a frame is painted between or not: what starts a page's own work (a windowed list's
/// blocks come in sight, View::scrolls_window's `seen`), never what asks the host for something only once it is drawn
/// (Tree::said_after_paint).
fn Tree::said_after_laid(self : Tree, f : () -> Unit) -> Unit {
  self.after_laid.push(f)
}

///|
/// What layouts said to tell of their moments (Tree::said_after_laid), told, in order; what that telling says so told
/// too.
fn Tree::tell_laid(self : Tree) -> Unit {
  while !self.after_laid.is_empty() {
    let now = self.after_laid.copy()
    self.after_laid.clear()
    for f in now {
      f()
    }
  }
}

///|
/// `f` told once, after the first frame that draws it is painted (laid out somewhere, not left out): what asks the host
/// for something only once there is a node for it in the window (the keyboard for a field, a native view over it). It
/// sets nothing a build or a layout reads: what waits for a node to be laid out waits for nothing of the tree's
/// (retained.md, "Layout read back").
pub fn View::on_first_drawn(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(_) else { return self }
  self.tree.first_drawn.push((self.at, self.gen, f))
  self.tree.marked()
  self
}

///|
/// Those waiting to be first drawn that this frame laid out somewhere: told after it is painted; those let go dropped.
fn Tree::first_drawn_now(self : Tree) -> Unit {
  if self.first_drawn.is_empty() {
    return
  }
  let waiting = []
  for e in self.first_drawn {
    let n = self.nodes[e.0]
    if !n.live || n.gen != e.1 {
      continue
    }
    if self.out_at(e.0) {
      waiting.push(e)
    } else {
      self.after_paint.push(e.2)
    }
  }
  self.first_drawn.clear()
  self.first_drawn.append(waiting)
}

///|
/// How far across each way a press's room is at least, said by the host (a finger's 44, a pointer's 36): what takes a
/// press drawn smaller is reached from round it (Tree::target_in); 0, by what is drawn alone.
pub fn Tree::set_press_least(self : Tree, least : Double) -> Unit {
  self.press_least = least
}

///|
/// Whether (x, y) is on content `c` (drawn at (cx, cy), `s` as big), said to take no press itself, and within what
/// bounds input to it, what holds it taking presses (none leaving, none said to take none, under no modal layer it is
/// not in): a control turned off there (Tree::target_in).
fn Tree::blocks_at(self : Tree, c : Content, cx : Double, cy : Double, s : Double, x : Double, y : Double) -> Bool {
  if x < cx || y < cy || x >= cx + c.w * s || y >= cy + c.h * s {
    return false
  }
  let n = self.nodes[c.id.at]
  if n.parent >= 0 && self.pressless_at(n.parent) {
    return false
  }
  if !self.allows_at(c.id.at) || n.left_at >= 0.0 || n.out || n.bones != 0L {
    return false
  }
  let (bx0, by0, bx1, by1) = self.input_bounds(c.id)
  x >= bx0 && y >= by0 && x < bx1 && y < by1
}

///|
/// Turned off while `on` holds (a send button with nothing to send, a picture with nothing to open, a file card that
/// cannot be opened): where it is drawn it takes a press and does nothing with it, what lies under it (a field's
/// ground) not reached, the pointer an arrow over it, as an old view's control turned off is (its target kept, its
/// press taking nothing). Unlike View::presses(false), which lets presses through to what lies under it (a page laid
/// over another, a part that is only shown). Read out as turned off (disabled), a screen reader's press of it
/// refused; what it holds that takes presses of its own (a retry on a card) read and pressed as ever. Said at the
/// moment it changes. Input's: nothing laid out or drawn again.
pub fn View::turned_off(self : View, on : Live[Bool]) -> View {
  self.bind(TurnedOff, on, Said, fn(on) { self.tree.nodes[self.at].turned_off = on })
  self
}
