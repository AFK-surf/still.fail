// A view made once (the model; the way there's 2). Each node is made when it first shows and stays
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
// Nodes are a pool by index (no pointer cycles under reference counting): a node holds what holds it and
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
/// A property's value: set once (`Is`), or worked out (`By`), tracked, and set again as what it read changes.
pub(all) enum Live[T] {
  Is(T)
  By(() -> T)
}

///|
/// Who a node is: its index and its making there (an index made again is another node).
#derive(Eq, Hash, Debug)
pub(all) struct NodeId {
  at : Int
  gen : Int
}

///|
/// What a node is drawn as, kept by the node: its ground (0: none), its words and their ink, how opaque, and how far it
/// is drawn off where it is laid out (what it holds drawn off with it).
#derive(Eq, Debug)
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
  /// what of its words is marked under them, each part its own way (View::runs_marks: what is found, what is gone to)
  mut runs_marks : Array[RunsMark]
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
  /// its picture contained in it, all of it shown as wide for as tall as it is, in its middle (View::image_contains);
  /// else filling it (covering it said, covering it)
  mut image_contain : Bool
  /// its picture covering it from a side said along its height (0 its top, 1 its foot): cut where it is not as wide
  /// for as tall, as much of it as shows taken from there (View::image_covers_at); None as image_cover says
  mut image_cover_at : Double?
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
  /// ground is drawn off and how much bigger than it is laid out, and how round (View::ground_drawn)
  mut drawn_off : (Double, Double)
  mut ground_drawn : GroundShape
  /// whether what it holds past its edges fades out towards them softly, by how far it reaches past (View::cuts_softly)
  mut cut_soft : Bool
  /// what it draws called by name, as what finds it on screen calls it (an icon's: View::drawn_as)
  mut drawn_as : String
  /// whether what it holds is cut to it, its corners round as its own (View::clips)
  mut clips : Bool
  /// whether its words' lines each stand in the middle of its width (View::words_centered)
  mut words_center : Bool
  /// whether its words, not wrapped, keep their line breaks, each line as it is (View::words_breaks)
  mut words_breaks : Bool
  /// how many times what its glyphs are drawn by was said (View::glyphs_by): its words drawn again as it is
  mut glyphs_said : Int
  /// whether its words' ellipsis, one line cut short past it, is drawn past its box (View::ellipsis_past)
  mut ellipsis_past : Bool
  /// the picture it draws as wide as it is laid out, its curves cut for the pixels it is drawn at (View::picture)
  mut picture : @pixels.Vector?
}

///|
/// What a node draws, where it is its own (its origin its top left, as opaque as itself): which node, how big, its
/// ground, its words. Made again only as one of these changes; where it is and how opaque it is drawn are its place's
/// and its holders' (composed as the scene is gone through: Tree::each_drawn).
#derive(Eq, Debug)
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
  runs_marks : Array[RunsMark]
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  lines : Array[@paint.Line]
  tint : Int64
  radius : Double
  /// its corners each, where it says them (View::corners)
  corners : (Double, Double, Double, Double)?
  /// the edge round its ground (View::edge)
  edge : (Double, Int64)
  /// the picture it shows, all of it filled (View::image)
  image : (String, String, Int)?
  /// the room its picture is judged ready for (View::image_for)
  image_for : (Double, Double)
  /// its picture covering it, not stretched to it (View::image_covers)
  image_cover : Bool
  /// its picture contained in it, not stretched to it (View::image_contains)
  image_contain : Bool
  /// its picture covering it from a side along its height (View::image_covers_at)
  image_cover_at : Double?
  /// its picture fading in as it is decoded (View::image_fades)
  image_fade : Bool
  /// where in it its picture lies and the matte round it (View::image_in)
  image_in : ((Double, Double, Double, Double), Int64)?
  glass : @paint.Glass?
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
  /// what it holds cut to it, its corners round as its own (View::clips)
  clips : Bool
  /// on its way in or out (View::comes), cut to itself as well: its own words drawn within it, not past it over what
  /// is beside it, as what it holds is (clips with it, its way's while it goes)
  clips_self : Bool
  /// its words' lines each in the middle of its width (View::words_centered)
  words_center : Bool
  /// its words, not wrapped, on their lines as written (View::words_breaks)
  words_breaks : Bool
  /// how many times what its glyphs are drawn by was said (View::glyphs_by; Tree::glyphs_of)
  glyphs_said : Int
  /// its words' ellipsis drawn past its box where it has not the room for it (View::ellipsis_past)
  ellipsis_past : Bool
  /// the picture it draws as wide as it is (View::picture)
  picture : @pixels.Vector?
  /// what it is drawn in as its bones, its own or what holds it's (View::bones): 0 none
  bones : Int64
  /// in its bones, how: drawn as its words, shapes and grounds are (0), one piece of its own box (1: View::bone_whole),
  /// or nothing, in one drawn whole (2)
  bone_as : Int
  /// whether it draws anything of its own (Content::draws) or words of its own (its runs, what is drawn of its words),
  /// worked out once as it is made: what a walk of the scene asks of each in the order (ui's view_draws)
  draws_any : Bool
}

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
  self.hosted
}

///|
/// Whether what a node looks as draws anything of its own, as its content says it (Content::draws), or words of its own (its
/// runs, what is drawn of its words): Content's `draws_any`.
fn look_draws_any(l : Look, hosted : Bool) -> Bool {
  (l.ground & 0xFFL) != 0L ||
  (l.edge.0 > 0.0 && (l.edge.1 & 0xFFL) != 0L) ||
  l.image is Some(_) ||
  l.words != "" ||
  !l.shapes.is_empty() ||
  !l.lines.is_empty() ||
  l.picture is Some(_) ||
  l.glass is Some(_) ||
  l.shadow.0 > 0.0 ||
  hosted ||
  !l.runs.is_empty() ||
  l.words_drawn is Some(_)
}

///|
/// A node's content unfolded where the window draws it (what holds it drawn off and faded with it): for a test, or a
/// host that takes the window whole.
#derive(Eq, Debug)
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
  runs_marks : Array[RunsMark]
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  lines : Array[@paint.Line]
  tint : Int64
  radius : Double
  /// its corners each, where it says them (View::corners)
  corners : (Double, Double, Double, Double)?
  /// the edge round its ground (View::edge)
  edge : (Double, Int64)
  /// the picture it shows, all of it filled (View::image)
  image : (String, String, Int)?
  /// the room its picture is judged ready for (View::image_for)
  image_for : (Double, Double)
  /// its picture covering it, not stretched to it (View::image_covers)
  image_cover : Bool
  /// its picture contained in it, not stretched to it (View::image_contains)
  image_contain : Bool
  /// its picture covering it from a side along its height (View::image_covers_at)
  image_cover_at : Double?
  /// its picture fading in as it is decoded (View::image_fades)
  image_fade : Bool
  /// where in it its picture lies and the matte round it (View::image_in)
  image_in : ((Double, Double, Double, Double), Int64)?
  glass : @paint.Glass?
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
  /// what it holds cut to it, its corners round as its own (View::clips)
  clips : Bool
  /// on its way in or out (View::comes), cut to itself as well: its own words drawn within it, not past it over what
  /// is beside it, as what it holds is (clips with it, its way's while it goes)
  clips_self : Bool
  /// its words' lines each in the middle of its width (View::words_centered)
  words_center : Bool
  /// its words, not wrapped, on their lines as written (View::words_breaks)
  words_breaks : Bool
  /// how many times what its glyphs are drawn by was said (View::glyphs_by; Tree::glyphs_of)
  glyphs_said : Int
  /// its words' ellipsis drawn past its box where it has not the room for it (View::ellipsis_past)
  ellipsis_past : Bool
  /// the picture it draws as wide as it is (View::picture)
  picture : @pixels.Vector?
  /// what it is drawn in as its bones (Content's): 0 none; nothing of its words found as words then
  bones : Int64
  /// in its bones, how (Content's)
  bone_as : Int
}

///|
/// What the tree did, counted from its making: nodes made and let go; bindings run, and of them those whose value came
/// out the same (nothing set, nothing marked); computes of the layout and nodes it laid out again; nodes a frame visited
/// (laid out, placed, looked at); words measured; instances made again; instances handed to the host as changed;
/// orders made again; structure bindings run (show, pick, each). For a test to say what work a change did, not how long
/// it took.
#derive(Eq, Debug)
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
  /// nodes visited while putting a holder's boxes again in order (Tree::boxes)
  mut boxes_walked : Int
  mut structure : Int
  /// bindings looked at as something asked at once (Tree::pull): those marked, each once
  mut pulled : Int
  /// the boxes round what a node and what it holds draw worked out afresh (View::scale's Drawn: Tree::drawn_box_of)
  mut drawn_boxes : Int
  /// where things stand laid out and placed once a change was told whole (Tree::settle_now: View::laid_before_causes)
  mut settles : Int
  /// nodes a search for what a point is for went through (Tree::target_at's walk)
  mut found_walked : Int
  /// of them, those drawn smaller than a press's room near the point, kept to ask whether it reaches them (reach.mbt)
  mut near_kept : Int
  /// nodes told whether they take input, as what takes input is told anew (Tree::inputs_down, inputs_each)
  mut inputs_walked : Int
  /// entries of the drawing order put in it again as a run of it is made again, kept or worked out (Tree::order_from)
  mut order_copied : Int
}

///|
/// A node of the pool.
// state_rev is never read: Tree::said_pass does not go through a node again for its state
#warnings("-unused_field")
struct Node {
  /// which making of this index it is (a handle on an earlier one finds it let go)
  mut gen : Int
  mut live : Bool
  mut flex : @flex.Node
  look : Look
  mut parent : Int
  /// A last-resort ellipsis in its own words was deliberately allowed, without changing their sizing.
  mut allow_ellipsis : Bool
  /// its words, and all made in it, at the size they are said, whatever the system's size of words (View::box's
  /// `words_as_said`, taken from what it is made in as it is made: View::words_scale answers 1)
  mut words_as_said : Bool
  kids : Array[Int]
  /// its scope (what it was made with, and what is set on it, owned), and what stops it
  mut owner : @signals.ReactiveNode?
  mut stop : (() -> Unit)?
  /// what else goes with it (View::owns, its structure's binding), run once as it is let go
  drops : Map[Int, () -> Unit]
  /// the key the next of them is kept by
  mut drop_next : Int
  /// what it said to do as it starts leaving (View::on_leaving) and as it comes back from leaving (View::on_back), and
  /// whether its starting to leave has been told (Tree::tell_leaving: once, told anew once it has come back)
  leavings : Array[() -> Unit]
  backs : Array[() -> Unit]
  mut leave_told : Bool
  /// its properties' bindings, by property (Prop::ord): what stops each
  props : Map[Int, () -> Unit]
  mut on_press : (() -> Unit)?
  /// what the second of two presses of it does in place of its press (View::on_double_press)
  mut on_double_press : (() -> Unit)?
  /// what a step up (1) or down (-1) asked of it does (View::on_step: a slider's, as a screen reader moves it)
  mut on_step : ((Int) -> Unit)?
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
  /// where the tree keeps sources (a Tester's: source.mbt) and its ground (View::ground) is bound, what its ground, as
  /// last worked out, read of what shows it (ground_read_*: the hand on a node, the keyboard's focus): a ground seen in
  /// a state it is not in now, which the corner rule holds at rest as shown (ui's corners.mbt, Node::lit_ground). None
  /// kept elsewhere
  mut ground_read : Int
  /// what it does as the pointer moves onto it or over it (View::on_pointer_moved): the pointer's own moving, not a
  /// layout putting it under a still pointer
  mut on_pointer_moved : (() -> Unit)?
  /// whether what the pointer is over is it or held by it, made as first read (View::pointed_in)
  mut pointed_in_cell : @signals.Signal[Bool]?
  /// whether the pointer is within it as it was last placed, made as first read (View::pointer_within)
  mut within_cell : @signals.Signal[Bool]?
  /// which piece of it the pointer is over, by what says it from where the pointer is in its own terms, made as first read
  /// (View::pointer_piece)
  mut piece_cell : (@signals.Signal[Int], (Double, Double) -> Int)?
  /// how many times how its words are set was said (their words, pieces, look: View::words_said), made as first read
  mut said_cell : @signals.Signal[Int]?
  /// a row of a list made by its key (View::each; a page's list's slot and block, View::scrolls_window): the same while
  /// its key is there, whatever is made in it anew (read by View::row_place alone)
  mut each_row : Bool
  /// whether it takes input now as what reads it reads it (View::takes_input): made as first read, let go with it
  mut input_cell : @signals.Signal[Bool]?
  /// whether it can take the keyboard's focus, which of Enter (1) and Space (2) press it as it has it (View::focusable;
  /// none: it takes the focus all the same, pressed by no key), and its cells of whether it has it and it shows (View::focused, View::focus_shown): made as first read, let go
  /// with it
  mut focusable : Bool
  /// the pointer's shape over it, said (View::cursor; none: as it is shown without being told, Tree::cursor_of)
  mut cursor : Cursor?
  /// whether it is a ground, no control (View::as_ground): no room of its own to be pressed in, none it cuts
  mut as_ground : Bool
  /// what it is placed beside (View::beside: its anchor, the side, how along it), placed so as the tree is placed
  mut beside : Beside?
  /// the side it went on beside its anchor, as it was last placed there (none: not placed beside one yet)
  mut went : Side?
  /// where it was last placed beside its anchor (its place in what holds it, and the point it is drawn bigger or
  /// smaller about): where it stays once it is leaving or its anchor is drawn nowhere (View::beside)
  mut beside_last : (Double, Double, Double, Double)?
  /// the point of its anchor the pointer was last at, in the anchor's own terms (View::beside's `at_pointer`)
  mut beside_point : (Double, Double)?
  /// the piece of its anchor it goes beside (View::beside's `piece`: asked as it is placed, given how big the anchor is
  /// laid out; none: all of it)
  mut beside_piece : ((Double, Double) -> (Double, Double, Double, Double)?)?
  mut focus_keys : Int
  /// whether Tab stops on it as it takes the focus (View::focusable's `tab`)
  mut focus_tab : Bool
  /// whether Tab's stop on it is said by View::tab_stop (the last saying of it), not by View::focusable's `tab`
  mut tab_by_stop : Bool
  mut focused_cell : @signals.Signal[Bool]?
  /// how big it was laid out, told once all of the layout is done (View::laid_size_told: none till then); made as
  /// first read
  mut size_cell : @signals.Signal[(Double, Double)?]?
  /// what it holds is found by a finger or the pointer within it alone (View::bounds_input)
  mut bounds_input : Bool
  /// tucked over the top of what scrolls it (Scroll::tucks): that node, and how far down its top what covers it reaches
  /// (a bar): what of it lies there is out of sight, found by no finger nor pointer
  mut tucked_under : (Int, () -> Double)?
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
  /// whether it takes a finger or the pointer some way (pressed, held, hosting the old view, a top row, pointed at,
  /// taking holds over: Tree::inputs_own_said), and how many of what it holds, it with them, do: what finds what
  /// takes a point passes over what holds none (Tree::each_drawn_in_order's `inputs_only`)
  mut inputs_own : Bool
  mut inputs_in : Int
  /// what brings a part of what it holds into its sight (View::shows): given where that is in its own terms (its top,
  /// its foot), how far it moved what it holds to
  mut shows : ((Double, Double) -> Double)?
  /// whether what it brings into sight it brings across (View::shows' `across`): a row that scrolls sideways
  mut shows_across : Bool
  /// down a column, the room it shows what it holds in, as it is now (View::shows' `room`): how tall it is, and how
  /// much of that what lies over its top and its foot covers
  mut shows_room : (() -> (Double, Double, Double))?
  /// whether it takes over a hold that began on what it holds, moved so far from where it went down (View::claims)
  mut claims : ((Double, Double) -> Bool)?
  /// where a hold it takes over may have gone down, in its own terms (View::claims' `from`): none, anywhere
  mut claims_from : ((Double, Double) -> Bool)?
  /// how many times it was said to take over holds (View::claims): a hold asks it as it was said as it went down
  mut claims_said : Int
  /// a hold on it is one what holds it may take over as it moves (View::claims), the hold not its own yet: a gesture
  /// waiting on a tap, a hold of the finger or its own slop (View::gesture)
  mut yields : Bool
  /// a gesture that answers a hold alone (its moment, its slop: View::gesture): no target of a press or a drag of its
  /// own, held long the finger its (hold_in.mbt)
  mut hold_only : (Double, Double)?
  /// how far apart the lines of a row that wraps are laid out (View::wraps; None: as its gap says, or none wraps)
  mut line_gap : Double?
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
  /// whether what is said of how narrow and how wide it may be is no more than the width what holds it gives it
  /// (View::min_width's and View::max_width's `within`)
  mut min_w_within : Bool
  mut max_w_within : Bool
  /// what it takes over holds for is scrolling what it holds (View::claims' `scrolls`)
  mut claims_scroll : Bool
  /// where it scrolls what it holds up and down (View::scrolls): the node holding that, whose height less its own is how
  /// far it can go (Scroll's room); -1 for one that does not
  mut scroll_held : Int
  /// the tree's count of changes as it or anything it holds last changed how it is drawn in its place (Tree::touched):
  /// what is drawn of all of it is what it was then, wherever it is moved
  mut drawn_rev : Int
  /// the tree's count of what is read out as it, or anything it holds, last changed in any way (`said`), in its words or what
  /// says itself in it (`words`), in what of it is read out in what holds it (`kids`: the nearest that is read out, or
  /// the root, marked), and as it changed itself (`own`; `state`: whether it takes presses, what it is said to be):
  /// what is read out of it gone through again only where these are past the last pass (Tree::said_pass)
  mut said_rev : Int
  mut words_rev : Int
  mut kids_rev : Int
  mut own_rev : Int
  mut state_rev : Int
  /// whether what it scrolls it scrolls across (View::scrolls with Scroll::across): which way Tree::scrolls_now asks
  /// whether it can go
  mut scroll_across : Bool
  /// how far it is drawn off where it is placed by how far a column scrolls it at a moment (a page's list's held, a
  /// bar's thumb: View::scrolls), read at that moment as it is drawn, found or read out, never followed: no place of it
  /// or of what it holds changes as the column scrolls, what it holds drawn as it was, moved (none: nothing)
  mut scroll_off : ((Double) -> (Double, Double))?
  /// the node that scrolls it so (-1: none)
  mut scroll_by : Int
  /// whether it holds a page's list's rows (Scroll::list's, up and down): on a host that sets them on its pixels
  /// (Tree::set_rows_grid), each laid out as tall as whole pixels (@flex.Style's rows_grid) and all moved alike so the
  /// first one's top is on one, as an old view's list's are (ui's Ctx::row_slot, Ctx::rows_on_pixels)
  mut list_rows : Bool
  mut focus_shown_cell : @signals.Signal[Bool]?
  /// what a finger or the pointer held on it does as it goes (View::on_drag)
  mut on_drag : ((Drag) -> Unit)?
  /// how many fingers held on it at once it takes (View::on_drag's `fingers`): one more calls the hold off
  mut fingers : Int
  /// whether a drag anywhere on it is its own, whole (View::on_drag's `whole`): nothing drawn over it reached from round
  /// where it is drawn by a press on it (reach.mbt)
  mut drags_whole : Bool
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
  /// a slot whose structure said `along_row`: what it makes or lets go along the row laying it out makes its way
  /// across (View::comes, Tree::makes_way)
  mut along_row : Bool
  /// as big as what holds it says, whatever it holds (View::lays_out_alone): what changes under it laid out again from
  /// it alone, nothing above it
  mut alone : Bool
  /// its boxes to be put again in order as the change being made ends (Tree::boxes_held, View::boxes_again)
  mut boxes_due : Bool
  /// a boundary's (View::boundary): told of a fault under it
  mut fault_to : ((String) -> Unit)?
  /// drawn by what hosts the tree (View::hosted)
  mut hosted : Bool
  /// what it says it is, read out (View::says); None nothing
  mut said : Said?
  /// what it and all it holds are kept from what is read out (View::hides)
  mut said_hidden : Bool
  /// it and all it holds not in use, behind what is (View::in_use): the keyboard's focus none of theirs
  mut behind : Bool
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
  /// what moves it off where it is laid out from how big it is laid out (View::moved_by), and how far that last
  /// came to (as it was placed, or as what it reads changed)
  /// what each glyph of its words is drawn by, as its state is said now (View::glyphs_by)
  mut glyphs_fn : ((GlyphAt) -> GlyphLook)?
  mut moved_by : ((Double, Double, Double) -> (Double, Double))?
  mut moved : (Double, Double)
  /// when that move is over at the size it is laid out, where it holds what is leaving that holds it till then
  /// (View::moved_by's `holds_leaving`)
  mut moved_holds : ((Double, Double) -> Double)?
  /// when that move is over at a size (View::moved_by's `ends`), for View::moved_end
  mut moved_ends : ((Double, Double) -> Double)?
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
  /// making its way in or out of its column (View::comes: laid out as the clock goes, cut at its edges), told to what
  /// lays it out so as that starts or ends; when it is there called off; what it and what it holds bind woken, where
  /// they rest as it leaves so (none: none)
  mut coming : Bool
  mut come_said : @signals.Signal[Int]?
  mut come_off : () -> Unit
  mut come_wake : (() -> Unit)?
  /// whether it is said to cut what it draws at its edges (View::clips), as it is cut too while it makes its way
  mut clips_said : Bool
  /// it, and what it holds, take no press (View::presses)
  mut inert : Bool
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
  /// where in the source it was made and its properties said, where the tree keeps that (Tree::new's `sources`;
  /// None: it does not)
  mut source : Source?
  /// the id it is one thing by with another, and how it flies from that one (View::shared: shared.mbt); none, not
  mut share : String?
  mut share_flight : Flight?
  /// the end of a flight that stays where it is (View::shared's `stays`: a thumbnail), drawn nowhere while one of its
  /// id that moves lives
  mut share_stays : Bool
  /// one that moves that flies only from or to one of its id that stays (View::shared's `with_stays`)
  mut share_with_stays : Bool
  /// on a flight's way, drawn over the rest of its layer where the flight has it (shared.mbt); none, where it is
  mut lift : Lift?
}

///|
/// The nodes made once of a window, its clock and what it did.
pub struct Tree {
  /// the moment what is drawn is drawn at (a frame's, to be shown then), a signal a look follows (Tree::drawn_at); the
  /// logic follows no clock (its moment `logic`, what is due on its timeline said once: Tree::advance)
  clock : @signals.Signal[Double]
  /// the moment the last frame is drawn at (Tree::at), where the clock stands but while it is set to a change's
  /// moment and back (Tree::measured_now, a settling): what makes its way follows this one alone (View::comes)
  mut frame_ms : Double
  /// the same moment, for what draws a wait by it (a cycle: View::cycle): what never ends, read apart from what moves
  beat : @signals.Signal[Double]
  /// the same moment on the resident clock's steps (resident_step_ms): for an endless decoration drawn by it
  /// (View::cycle_resident), told only as a step is passed
  resident : @signals.Signal[Double]
  /// the nodes that read it (View::cycle_resident), each with its making and the step it last read: one reading it now
  /// has read the step it is on (each reading it is worked out again as it passes a step); its steps woken for only
  /// while one such is drawn
  resident_readers : Map[Int, (Int, Double)]
  /// what Tree::resident_read last said, and what it said it of: how many times the order or what is drawn changed
  /// (`draws_rev`), what is hit (`hits`: one left out of its row, or back), the step, and how many times a reader came
  /// or read another step (`resident_rev`): said again only past one of them
  priv mut resident_said : (Int, Int, Double, Int, Bool)
  priv mut resident_rev : Int
  /// its keymap, the contexts and actions its nodes say, and a sequence of keys under way (keymap.mbt)
  keyed : KeyBook
  /// told each time what the root holds is put at another place in the window's stack of layers (View::stacked,
  /// View::over_all): what orders things by those places as it is built (an old frame's layers opened in its nodes:
  /// Tree::places_read) built again
  places : @signals.Signal[Int]
  /// the time now, as a change is told (the host's: an event's moment, before a frame takes it); none: the clock's
  time : (() -> Double)?
  /// the moment the change a queued binding works out was told, while it is (-1: none)
  mut cause_at : Double
  /// how words are measured: (words, how they are set, width offered, the size of words they are at: their node's,
  /// Tree::words_scale_at) -> (width, height)
  measure : (String, WordsLook, Double, Double) -> (Double, Double)
  /// and words in pieces set their own way (View::words_runs): (the pieces, how the words are set, width offered, the
  /// size of words)
  measure_runs : (Array[@text.Run], WordsLook, RunsLook, Double, Double) -> (Double, Double)
  /// how wide words too wide for a width on one line are drawn where they say shorter ways (View::shorter): the first of
  /// those that fits, else the last cut with an ellipsis, as the host lays them out (at the size of words given last)
  measure_shorter : (String, Array[String], WordsLook, Double, Double) -> Double
  /// and words not wrapped that keep their line breaks (View::words_breaks), as `measure` and `measure_runs` take
  /// theirs (the same two where none is given)
  measure_kept : (String, WordsLook, Double, Double) -> (Double, Double)
  measure_runs_kept : (Array[@text.Run], WordsLook, RunsLook, Double, Double) -> (Double, Double)
  /// whether each node keeps where in the source it was made and its properties said (source.mbt): a Tester's tree
  sources : Bool
  nodes : Array[Node]
  free : Array[Int]
  /// what a frame is to do: the nodes whose look changed, those whose place changed; whether any is to be laid out,
  /// whether the order is to be made again; whether any of it is (what hosts it told as it first is)
  looks_due : Array[Int]
  places_due : Array[Int]
  /// what is due at a moment of its own, in the order told (Tree::advance): a node leaving or coming back ending, a
  /// step of what goes by steps (View::steps); and how many were ever told (each one's place among those due together)
  timeline : Array[Due]
  mut told : Int
  /// the nodes whose move holds what is leaving that holds them till it is over (View::moved_by's `holds_leaving`)
  leave_holders : Array[NodeId]
  /// what a show set making or closing its way down a column at the moment of the change being made (View::arrives,
  /// View::goes): one coming where another goes in the same column at the same moment is in its place (View::swapped)
  priv swaps : Array[Swap]
  /// what comes or goes down a column at one moment, with what was on its way there then: one way for all of it
  /// (flex's ComeGroup), and the nodes in it (Tree::come_group_join), by the column
  priv come_groups : Map[Int, (@flex.ComeGroup, Array[View])]
  /// the held columns of the page's lists, each with whether its blocks' insides make their way in the list's one way
  /// (View::scrolls_window, not said at once) and what in its blocks was set coming or going since: what is on its way
  /// in them as the list's group is said (Tree::come_group_settle), and how long what a press there set off goes
  /// (press_stays.mbt), none of their subtrees walked
  priv list_inner : Map[Int, (Bool, Array[View])]
  /// the places of the page's lists' feet (View::scrolls_window's `foot`, pinned on the list's own node, not under
  /// its held column), each with the held column whose one way what comes or goes or resizes in it goes in
  /// (Tree::come_group_join), where the list's blocks' insides join it
  priv list_feet : Map[Int, Int]
  /// the nodes whose ground is drawn by how tall another shows (View::shown_by), each with that one and how; and for
  /// each so followed, those that follow it: placed again as it is laid out on its way
  priv shown_bys : Map[Int, (NodeId, (Double) -> GroundShape)]
  priv shown_followers : Map[Int, Array[Int]]
  /// what is due being done (Tree::advance)
  mut advancing : Bool
  /// where its logic stands: what is due by then done (Tree::advance), what is said from then on said as of then at the
  /// earliest
  mut logic : Double
  /// the bindings whose reads changed, to run as the frame begins (Tree::queued)
  bindings_due : Array[Bound]
  /// how deep the passes given to the bindings a layout told are, one inside another (Tree::laid_out: at most
  /// `told_passes_most`)
  mut told_passes : Int
  /// how many runs through `bindings_due` are under way (Tree::laid_out, Tree::measured_now): while one is, a room's
  /// layout come of a binding it ran leaves the queue as it stands (Tree::room_bindings_run)
  mut draining : Int
  /// how many bindings it holds, while they live (let go as each stops)
  mut bindings : Int
  /// those marked as what they read changed, since they last ran: what is asked at once (View::laid_size,
  /// Tree::bring_to) pulls those whose reads changed by then, told or not (Tree::pull)
  pulls_marked : Array[Bound]
  mut layout_due : Bool
  mut order_due : Bool
  /// where what is held changed since the order was last worked out (Tree::order_marked_in): the order made again from
  /// what holds each there, the rest of it as it was; none, or `order_whole`, all of it (Tree::order_again)
  order_in : Array[Int]
  /// what the checks of what is kept against what is worked out whole (kept_checks.mbt) last saw of the work: the
  /// order made again, the structure changed (as the boxes', the order's and the inputs' looks each last saw it), what
  /// takes input told; and how many looks in a row found the order still due, and what takes input
  mut kept_seen : (Int, Int, Int, Int, Int)
  mut kept_waits : Int
  mut kept_inputs_waits : Int
  /// nodes made since the order was last worked out to be put in it by their own runs (Tree::order_put_in), each with
  /// what lays it out; and those let go to be taken out of it so, each with its making and what held it
  /// (Tree::order_taken_out): the rest of the order as it was, where nothing else changed in it (Tree::order_spliced)
  order_ins : Array[(Int, Int)]
  order_outs : Array[(Int, Int, Int)]
  /// the nodes being let go as they let go of what they hold (View::let_go): one held by them goes out of the order with
  /// them; anything else let go meanwhile (what one's scope owned, in another layer: a tip, View::lives_with) by itself
  letting : Array[Int]
  mut order_whole : Bool
  mut due : Bool
  /// the host is being told that a frame is due (Tree::marked)
  mut telling_due : Bool
  /// the host took a frame while being told (Tree::frame)
  mut due_frame_taken : Bool
  mut last_w : Double
  mut last_h : Double
  /// the window's size, as its frames give it: what is laid out by it (which frame a window's width calls for) follows it
  room : @signals.Signal[(Double, Double)]
  /// how far in from the window's top, right, foot and left the system's bars reach (Tree::clear_of): what goes beside
  /// another (View::beside) and what is laid out over the window (View::clear) keeps clear of it
  clear : @signals.Signal[(Double, Double, Double, Double)]
  /// Each window press, with its number and window coordinates (Tree::went_down).
  pressed_anywhere : @signals.Signal[(Int, Double, Double)]
  /// Whether a finger or a button is down anywhere in the window now (Tree::went_down, Tree::went_up).
  held_anywhere : @signals.Signal[Bool]
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
  /// whether a size followed may have come out otherwise since they were last told: something laid out or placed, one
  /// asked anew (Tree::sizes_told; nothing looked at where nothing was)
  mut sizes_due : Bool
  /// what is to be brought into sight once laid out (Tree::show_in_sight): a node, and where in it (its own terms, asked
  /// then; none: all of it)
  shows_due : Array[(NodeId, () -> (Double, Double)?, (() -> Bool)?)]
  /// what each column (its node) keeps in sight for the focus as its room changes (Tree::holds_now), since it brought
  /// it into sight for the focus
  focus_holds : Map[Int, (NodeId, () -> (Double, Double)?, () -> Bool, Ref[(Double, Double, Double)])]
  /// the nodes left out in this layout or back in, as it is done: what those left out held, their focus and their back
  /// let go of; whether what each holds takes input told anew
  outs_gone : Array[Int]
  /// the nodes drawn, in the order they are drawn (no slot), and where in it what holds each is (-1: the window)
  order : Array[Int]
  order_holder : Array[Int]
  /// where in the order what each holds ends (the next not in it): a node left out passed over whole
  order_end : Array[Int]
  /// by each node's index, where it is in the order as that was last worked out (-1: not in it): what holds what
  /// read there (Tree::holds_drawn_in)
  order_of : Array[Int]
  /// by each node's index, the node of the root's it is in as the order was last worked out (Tree::top_of's; -2: not
  /// known then): read while the order is not due again
  tops : Array[Int]
  /// by each node's index, which making of it the order last put in it (its `gen` then): what of the order is kept as it
  /// was, a run of it moved whole, is that node's, not one made at its index since (Tree::order_from)
  order_gen : Array[Int]
  /// by each node's index, where it was in the run of the order being made again (Tree::order_from), and whether
  /// something it holds changed in what it holds since (`order_stamp` as of the last change worked out: Tree::order_again)
  priv order_was : Array[Int]
  priv order_changed : Array[Int]
  priv mut order_stamp : Int
  /// a run of the order made again aside before it is put in its place (Tree::order_from), kept for the next
  priv order_new : Array[Int]
  priv order_new_holder : Array[Int]
  priv order_new_end : Array[Int]
  /// what each walk of the scene keeps as it goes, kept for the next (Tree::each_drawn_in_order), and how many walk now
  priv mut walks : Array[Walk]
  priv mut walking : Int
  /// how many times the order or a node's content changed; and how many times the order changed or a node came to
  /// draw something of its own or nothing (its content's `draws_any`, what a walk's `drawing` reads of the tree), and,
  /// as a walk last worked them out, the next in the order that draws from each on (Walk's `next_drawn`): kept with
  /// the count it was for and the walker's own (`drawing_rev`), not worked out again while neither changed
  priv mut draws_rev : Int
  priv mut draws_any_rev : Int
  priv mut drawn_next : FixedArray[Int]
  priv mut drawn_next_for : (Int, Int, Int)
  /// the way up from a node to the root's, in the order, kept for the next (Tree::drawn_one: worked out top down)
  priv drawn_path : Array[Int]
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
  /// How many living nodes take back: none means finding its taker needs no walk of the tree.
  mut backs : Int
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
  /// each finger holding what is held, by its own id: where it went across and down by its own events' times (Drag's
  /// `vx`, `vy`)
  held_tracks : Map[Int, (Tracker, Tracker)]
  /// a finger held on a node a still hold of which is what lies under it's (View::holds_through): what lies there, as it
  /// was found as the finger went down, its hold's moment set going
  mut through : Through?
  /// the node a finger is held on whose still hold is what lies under it's (View::gesture's `through`), as the finger
  /// went down on it: what a host's own hold on words under it asks (Tree::hold_goes_through)
  mut through_cover : NodeId?
  /// a hold waited for on a gesture that answers a hold alone, the finger another's till then (hold_in.mbt), and how
  /// its moment is called off
  mut hold_in : HoldIn?
  mut hold_in_off : () -> Unit
  /// what hosts the tree told of a hold handed to what it hosts (Tree::on_through), and asked whether what it hosts
  /// takes a press at a point (Tree::hosts_at)
  mut on_through : (Target, Double, Double, Double, Handed) -> Unit
  mut hosts_at : (NodeId, Double, Double) -> Int?
  /// what the host says takes a finger at a point instead of what the tree found there (Tree::on_target), given what
  /// takes it there in the order they are drawn
  mut retarget : (Target, Array[Target], Double, Double) -> Target
  /// what hosts the tree is told as a column it holds glides on by itself, let go (Tree::on_glides): which column and
  /// when its glide ends as it is asked (none: at rest); and as that column is let go
  mut glides : (Int, () -> Double?) -> Unit
  mut glides_gone : (Int) -> Unit
  /// what hosts the tree is told as a node says something of it moves (View::said_moving): its key, what it is, and
  /// when it is at rest as of a moment (Tree::on_moves)
  mut moves : (String, String, (Double) -> Double) -> Unit
  /// told as a column moves what it scrolls by its offset alone (Node's scroll_off: a page's list, its bar's thumb),
  /// which column: nothing placed or drawn anew for it, what hosts it moves what it drew (Tree::on_offset)
  mut offset_moved : (NodeId) -> Unit
  /// how a page's list moves where it is drawn, and how many pixels a point is there (Tree::lists_feel)
  mut list_feel : () -> (ListFeel, Double)
  /// whether the pointer now drags what scrolls up or down as a finger does (Tree::pointer_drags_scroll)
  mut drags_scroll : () -> Bool
  /// whether motion is reduced where what hosts the tree draws it (Tree::reduces_motion): what comes or goes there at
  /// once (View::comes)
  mut motion_reduced : () -> Bool
  /// how far across each way the room a press has is at least where what hosts the tree draws it (Tree::press_least):
  /// what is drawn smaller is reached from round it (reach.mbt)
  mut press_least : () -> Double
  /// how soon (ms) and how near (points) a press let go after one of the same node's is its second, by the hand as it
  /// is now (Tree::twice_within); and the last press let go that may be a first: its node, moment and place in the
  /// window's terms (twice.mbt)
  mut twice_feel : () -> (Double, Double)
  mut last_press : (NodeId, Double, Double, Double)?
  /// what its host tells its nodes of where they are drawn (env.mbt: Tree::drawn_by)
  env : Env
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
  /// whether an old view's list is under the pointer as a column's key comes, the focus in none of the tree's: the key
  /// that list's, as ever (Tree::on_old_scroll, scroll_keys.mbt)
  mut old_scroll_here : () -> Bool
  /// where the pointer, a mouse's or a finger's, last was (Tree::key_point_is; (-1, -1) none): where a column's key
  /// goes where nothing is hovered (a finger's), scroll_keys.mbt
  mut key_point : (Double, Double)
  /// whether the old view hosted in a node has something of its own at a point of the window (ui's old_wheel_there):
  /// one with nothing there passed, to what is under it, as a wheel passes it (scroll_keys.mbt)
  mut old_there : (NodeId, Double, Double) -> Bool
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
  mut focused : NodeId?
  mut focus_visible : Bool
  /// the page's list (View::scrolls_window) one of whose rows holds the node with the focus (none: in no row, a list's
  /// head or foot being in none), found as the focus is set (Tree::focus_set), and how many times the focus has come
  /// into a row so: what a list's fill holds what shows by while it is noted, a list with none noted paying a comparison
  /// (Tree::row_focus_holds)
  mut focus_row_list : NodeId?
  mut focus_row_n : Int
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
  /// of those, the ones that give it only to the first of them that says what `takes` holds (View::focus_opens_first's
  /// `takes`)
  focus_first_takes : Map[NodeId, (Said) -> Bool]
  /// what opened the layers in a node (View::opened_by), by that node: what they give the focus back to as they go
  layer_openers : Map[NodeId, Opener]
  mut on_layers_focus : (Array[NodeId], Array[(NodeId, NodeId?)]) -> Unit
  /// what follows what is under the pointer, while it is over the window (Tree::point_at)
  mut point_stop : (() -> Unit)?
  /// let go (Tree::dispose): what is made for it after stops at once
  mut gone : Bool
  /// the nodes said to go beside another (View::beside), as said (each let go is passed over, and dropped as placed)
  besides_at : Array[Int]
  /// how wide each of them that is as wide as its anchor was made, by its index (View::beside's `Anchor`:
  /// Tree::beside_widened): the layout's own, never read by a binding; only those so in it
  beside_widths : Map[Int, Double]
  /// the nodes whose being under the pointer is read (View::pointer_within: their cells), each as it was made (its
  /// index and generation), told again as the pointer moves and as what is placed changes
  withins_at : Array[(Int, Int)]
  /// whether a frame's laying out is telling what is under the pointer (Tree::laid_out): what it lays out then not again
  mut withins_passing : Bool
  /// the nodes whose taking input is read (View::takes_input), as first read
  inputs_at : Array[Int]
  /// what is to be told whether each node in it takes input as the change is committed (Tree::inputs_told): the nodes
  /// what changed is in, each with all it holds (`inputs_whole`: all of the tree's, a modal layer said, a layer's place
  /// in the stack or another's modal layer changed)
  inputs_in : Array[Int]
  mut inputs_whole : Bool
  /// which following of the point is the one now (Tree::follow_point): each said, and each let go, another
  mut point_said : Int
  /// how many times what a point would hit may have changed (a layout, a place, the order, a node made or let go, what
  /// takes presses or holds a layer): what is pointed at worked out again only past one (Tree::hits_said)
  mut hits : Int
  /// the clock being set (Tree::clock_to, a frame's beat): what it tells is told by the clock, not by a change
  mut ticking : Bool
  /// a frame's (or an input's) laying out and placing under way (Tree::laid_out): what that tells (sizes laid out, what
  /// is in view) is the frame's, as the clock's is, not a change
  mut laying : Bool
  /// bindings running now, one inside another (Tree::queued's run)
  mut binding_running : Int
  /// the binding running now was told by the clock (Bound's `by_clock`)
  mut bound_by_clock : Bool
  /// what a point hits changed in a change, or a way that may have moved something under it ended, and at which
  /// moment, not yet told to what follows the hand (Tree::on_hand); and that being told now
  mut hand_owed : Bool
  mut hand_owed_at : Double
  /// the page's lists telling handlers what they have in sight (ListPlace::on_sight), by the list's node, each there
  /// only once one is told it (none listening: nothing of it worked out or owed); owed to be told at the moments the hand is (list_sight.mbt): at the change of an input
  /// or of data as it is told whole, at a way's end, the window given another size, its first layout
  sight_tellers : Map[Int, () -> Unit]
  mut sight_owed : Bool
  mut sight_owed_at : Double
  mut sights_telling : Bool
  mut handing : Bool
  mut hand_at : Double
  /// the moments a way that may move something ends, each told once (Tree::hand_at_end)
  hand_ends : Set[Double]
  /// the latest of those moments done: an end at it or before is past, told already (a binding read again on the
  /// timeline's way, before its logic stands there, said it again: a loop at that moment)
  mut hand_ends_done : Double
  /// the binding running now sets how something looks alone (Prop::moves_hits not): a way it reads as it goes says no
  /// end of the hand's (View::hand_at_end)
  mut looks_reading : Bool
  mut hand : (Double) -> Unit
  /// how many of its nodes are drawn in their bones themselves (Node's `bones` not 0): none, and no node is in them,
  /// nothing walked to its root to learn it (Tree::bones_of_at)
  mut bones_set : Int
  /// how many nodes are said not in use (View::in_use): none, that not asked of what holds a node
  mut behind_set : Int
  /// the width each node that says it lays what it holds out at (View::lays_anew), by node: what a Tester's steadiness
  /// judges take a step of as that node's own, in the frame it steps
  laid_said : Map[Int, Double]
  /// the fingers down on it (each by its id: Drag's `finger`), in the order they went down
  downs : Array[Int]
  /// what the last frame changed: the nodes whose content it made again, those placed or faded otherwise
  changed : Array[NodeId]
  composed : Array[NodeId]
  /// whether what a node that scrolls holds was moved from where it was placed since this was last taken
  /// (Tree::take_scrolled)
  mut scrolled_now : Bool
  /// the nodes that scroll whose held moved since Tree::take_scrolled was last asked
  scrolled_ats : Array[NodeId]
  /// the count of changes to how its nodes are drawn, each node's drawn_rev one of them (Tree::touched)
  mut drawn_revs : Int
  /// the count of changes to where any of its nodes is drawn as the walk works it out but by the clock (placed, sized,
  /// left out, drawn off, on a flight's way or off it, the order, the pixels a point): Tree::places_rev
  priv mut places_rev : Int
  /// the count of changes to what is read out (each node's said_rev and the rest one of them: Tree::said_marked), the last
  /// pass's (Tree::said_pass), the modal layers it went through as (Tree::said_pass), and what it reads out again each
  /// pass: what names itself or holds by what hosts an old view (by index, its making), what moves as it scrolls
  mut said_revs : Int
  mut said_seen : Int
  mut said_modal : (Int, Int, Int, Int)
  said_again : Map[Int, Int]
  said_helds : Map[Int, Int]
  /// the nodes let go since the host last took them (Tree::take_removed): what it keeps for them to let go too
  removed : Array[NodeId]
  /// the nodes whose content was made again since the host last took them (Tree::take_changed), and whether anything
  /// drawn changed since the last frame
  pending : Array[NodeId]
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
  /// Whether a layout of all of it is under way as of the logic's moment (Tree::measured_now): what is made in it and
  /// reads how big it is laid out reads that layout as it stands, none begun inside it
  mut measuring : Bool
  /// the node whose property's binding is being worked out now (-1: none): what reads the time in it is said
  /// (Tree::clock_read_in_binding)
  mut binding_reading : Int
  /// what lays out alone (View::lays_out_alone) with something under it to be laid out again, nothing above it: laid
  /// out from it as the rest is (Tree::alone_laid_out)
  alone_due : Array[Int]
  /// those laid out so and not yet placed by, each with its compute's number
  alone_laid : Array[(Int, Int)]
  /// what is asked of one laid out alone once it is (View::scrolls_window's slots: whether what it shows came out
  /// another height, the column marked laid out again then, before the layout of all of it), by its index
  alone_asks : Map[Int, () -> Bool]
  /// a page's list's rows known by their keys (View::scrolls_window), by the index of the row's slot and of the block
  /// made in it (each marked each_row): whose list, the number its key has there (given as it is first asked, kept while
  /// the list lives; read as the key is read, so that what reads it reads it again as a block is taken for another key),
  /// and where it is among them now (View::row_place, View::row_order)
  rows_named : Map[Int, (NodeId, () -> Int, () -> Int)]
  /// a page's list's scroll by the node it scrolls in (View::scrolls): how far it was put for what came out another
  /// height over what shows, as what is drawn is held steady (Tree::scroll_corrected)
  lists_scrolled : Map[Int, Scroll]
  /// a page's list by its node (View::scrolls_window), what a test reads of it and asks of it (Tree::lists_seen)
  priv lists_asked : Map[Int, ListAsked]
  /// the node whose room is being told as it is laid out (View::by_room: -1, none), and how many of what it holds were
  /// marked laid out again meanwhile (Tree::room_marked_at)
  mut rooming : Int
  mut room_marks : Int
  /// what was marked outside a room as it was told (Tree::room_marked_at), marked once all of it is laid out
  room_spill : Array[Int]
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
  /// how many properties were said on its nodes so far (View::bind): a structure's box that had none said on it as it
  /// was made, and made no box in it, made nothing (Tree::made_none)
  mut said_count : Int
  /// who times its work by part (Tree::timed_by): the clock (below 0 while nobody listens) and who is told each part
  /// and its ms; none, nothing timed
  mut timed : (() -> Double, (String, Double) -> Unit)?
  /// the structures' changes being done now, one inside another: the outermost alone timed (Tree::structured)
  mut structuring : Int
  /// how long the words measured took since that was last told (Tree::laid_out), ms on that clock
  mut measured_ms : Double
  /// how deep in a change that makes or moves many nodes at once (Tree::holding_boxes): while above 0, a holder whose
  /// boxes changed is only marked (Node's boxes_due, in boxes_held_at), its boxes put again once as the change ends
  mut boxes_held : Int
  boxes_held_at : Array[Int]
  /// boxes put in or taken out one at a time in the change being made (Tree::box_put_in, box_taken_out): past a few,
  /// its holders put again whole as it ends instead, as many made at once are
  mut boxes_one_by_one : Int
  /// told as there is first something for a frame to do: what hosts it asks for a frame
  mut on_due : () -> Unit
  /// told as a node's pointer's shape is said anew (View::cursor): what hosts it shows the pointer's shape again, no frame
  /// asked for it (nothing is drawn for a shape)
  mut on_cursor : () -> Unit
  /// what hosts the tree told as what may take input changes (a modal layer said on, what is drawn over what, a node
  /// let go, leaving, said to take no press): what it holds of its own, an old view's press, to ask whether that may
  /// still take input (Tree::takes_presses)
  mut on_modals : () -> Unit
  /// how many living nodes have each id (View::shared), all of them; what was let go of and made with one in the change
  /// being committed, paired as it is committed whole (Tree::pairs_now: asked, `pairs_asked`); the flights under way;
  /// whether what flies is being put in the order over the rest of its layer (Tree::ordered_lifted): shared.mbt
  priv shared_live : Map[String, Int]
  priv mut shared_n : Int
  /// of those, how many with each id move (none said to stay: View::shared's `stays`), and those that stay, by id
  priv shared_moving : Map[String, Int]
  priv shared_stays : Map[String, Array[Int]]
  priv departures : Array[Departure]
  priv arrivals : Array[NodeId]
  priv mut pairs_asked : Bool
  /// the pictures asked for in a change or a frame's layout (View::image_ask), each by the node that asked: asked of
  /// what hosts the tree as that ends, where that node still stands (Tree::change_ended, Tree::brought)
  priv images_wanted : Array[(NodeId, String, Double)]
  priv flights : Array[Flying]
  priv mut lifting : Bool
  /// how many times its nodes' flex places were worked out (a layout of all of it, one laid out to be read, one laid
  /// out alone, one beside another): what Tree::laid_origin sums changes only with one of them
  priv mut laids : Int
  /// what Tree::laid_held_hosted last worked out, and what it was worked out of (draws_rev, places_rev, how long the
  /// order was, laids); and how many times it walked the tree to work it out (Tree::held_walked)
  priv mut held_kept : Array[(Drawn, Int, Bool)]
  priv mut held_kept_for : (Int, Int, Int, Int)
  priv mut held_walked : Int
}

///|
/// A property's binding as it stands (Tree::queued): queued for a frame, marked as what it read changed, live, and what
/// runs it.
struct Bound {
  /// the node it binds a property of (-1: none said)
  at : Int
  mut queued : Bool
  mut marked : Bool
  mut live : Bool
  /// when what it read was told changed (-1: not since it ran)
  mut told_at : Double
  /// whether the clock told it (a way followed as it goes), a frame's laying out or the hand worked out anew (what the
  /// pointer is over lights), not a change: what it does is no cause of the hand's (Tree::hits_bump)
  mut by_clock : Bool
  /// what follows what it read (none once let go)
  mut watch : @signals.Watch?
  mut run : () -> Unit
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
/// pieces set their own way: `measure_runs`; said a shorter way where too wide: `measure_shorter`), each told the size
/// of words of the node whose words they are (View::words_scale's), keeping where in the source each node was made
/// where `sources` (source.mbt).
pub fn Tree::new(
  make : (View) -> Unit,
  measure? : (String, WordsLook, Double, Double) -> (Double, Double) = words_measure,
  measure_runs? : (Array[@text.Run], WordsLook, RunsLook, Double, Double) -> (Double, Double) = runs_measure,
  measure_shorter? : (String, Array[String], WordsLook, Double, Double) -> Double,
  measure_kept? : (String, WordsLook, Double, Double) -> (Double, Double),
  measure_runs_kept? : (Array[@text.Run], WordsLook, RunsLook, Double, Double) -> (Double, Double),
  time? : () -> Double,
  sources? : Bool = false,
) -> Tree {
  // (the moment it is made, taken once: its logic and what it draws start there, and what it is made with is of then)
  let start = match time {
    Some(f) => f()
    None => 0.0
  }
  let t : Tree = {
    clock: @signals.signal(start, same=fn(a, b) { a == b }),
    frame_ms: start,
    beat: @signals.signal(start, same=fn(a, b) { a == b }),
    resident: @signals.signal(resident_of(start), same=fn(a, b) { a == b }),
    resident_readers: {},
    resident_said: (-1, -1, -1.0, -1, false),
    resident_rev: 0,
    keyed: KeyBook::new(),
    places: @signals.signal(0),
    room: @signals.signal((0.0, 0.0), same=fn(a, b) { a == b }),
    clear: @signals.signal((0.0, 0.0, 0.0, 0.0), same=fn(a, b) { a == b }),
    pressed_anywhere: @signals.signal((0, -1.0, -1.0), same=fn(a, b) { a == b }),
    held_anywhere: @signals.signal(false, same=fn(a, b) { a == b }),
    tapped_anywhere: @signals.signal(0, same=fn(a, b) { a == b }),
    words_redone: @signals.signal(0, same=fn(a, b) { a == b }),
    outs_said: @signals.signal(0, same=fn(a, b) { a == b }),
    outs_changed: false,
    sizes_due: false,
    sized: [],
    shows_due: [],
    focus_holds: Map([]),
    outs_gone: [],
    time,
    cause_at: -1.0,
    measure,
    measure_runs,
    measure_shorter: match measure_shorter {
      Some(f) => f
      None => fn(words, shorter, look, room, scale) { shorter_w_by(measure, words, shorter, look, room, scale) }
    },
    measure_kept: measure_kept.unwrap_or(measure),
    measure_runs_kept: measure_runs_kept.unwrap_or(measure_runs),
    sources,
    nodes: [],
    free: [],
    looks_due: [],
    places_due: [],
    bindings_due: [],
    told_passes: 0,
    draining: 0,
    bindings: 0,
    pulls_marked: [],
    timeline: [],
    leave_holders: [],
    swaps: [],
    come_groups: {},
    list_inner: {},
    list_feet: {},
    shown_bys: {},
    shown_followers: {},
    told: 0,
    advancing: false,
    logic: start,
    layout_due: true,
    order_due: true,
    order_in: [],
    kept_seen: (0, 0, 0, 0, 0),
    kept_waits: 0,
    kept_inputs_waits: 0,
    order_ins: [],
    order_outs: [],
    letting: [],
    order_whole: true,
    due: true,
    telling_due: false,
    due_frame_taken: false,
    last_w: -1.0,
    last_h: -1.0,
    order: [],
    order_holder: [],
    order_end: [],
    order_of: [],
    tops: [],
    order_gen: [],
    order_was: [],
    order_changed: [],
    order_stamp: 0,
    order_new: [],
    order_new_holder: [],
    order_new_end: [],
    walks: [],
    walking: 0,
    draws_rev: 0,
    draws_any_rev: 0,
    drawn_next: FixedArray::make(0, 0),
    drawn_next_for: (-1, -1, -1),
    drawn_path: [],
    hosting: -1,
    held_under: -2,
    held_under_of: None,
    modals: [],
    backs: 0,
    committing: 0,
    afters: [],
    modals_due: false,
    held: None,
    gesture_tapped: false,
    held_tracks: {},
    through: None,
    through_cover: None,
    hold_in: None,
    hold_in_off: fn() {  },
    on_through: fn(_, _, _, _, _) {  },
    hosts_at: fn(_, _, _) { None },
    retarget: fn(t, _, _, _) { t },
    glides: fn(_, _) {  },
    glides_gone: fn(_) {  },
    moves: fn(_, _, _) {  },
    offset_moved: fn(_) {  },
    list_feel: fn() { (Desktop, 1.0) },
    drags_scroll: fn() { true },
    motion_reduced: fn() { false },
    press_least: fn() { 0.0 },
    twice_feel: fn() { (double_press_ms, double_press_slop) },
    last_press: None,
    env: Env::new(),
    laid_waits: [],
    pressing: None,
    pointed: None,
    lit_every: false,
    pointer_xy: (-1.0, -1.0),
    old_scroll_here: fn() { false },
    key_point: (-1.0, -1.0),
    old_there: fn(_, _, _) { true },
    points_hover: None,
    scrolls_at: {},
    bar_cols: [],
    drawn_marks: [],
    bars_due: false,
    backing: None,
    focused: None,
    focus_row_list: None,
    focus_row_n: 0,
    focus_parked: None,
    focus_visible: false,
    on_focus_lost: fn(_) {  },
    on_focus_asked: None,
    focus_opened: [],
    focus_gone: [],
    focus_firsts: Set([]),
    focus_first_takes: {},
    layer_openers: {},
    on_layers_focus: fn(_, _) {  },
    point_stop: None,
    gone: false,
    besides_at: [],
    beside_widths: {},
    withins_at: [],
    withins_passing: false,
    inputs_at: [],
    inputs_in: [],
    inputs_whole: false,
    point_said: 0,
    hits: 0,
    ticking: false,
    laying: false,
    binding_running: 0,
    bound_by_clock: false,
    hand_owed: false,
    hand_owed_at: -1.0,
    sight_tellers: {},
    sight_owed: true,
    sight_owed_at: -1.0,
    sights_telling: false,
    handing: false,
    hand_at: -1.0,
    hand_ends: Set([]),
    hand_ends_done: -1.0,
    looks_reading: false,
    hand: fn(_) {  },
    bones_set: 0,
    behind_set: 0,
    laid_said: Map([]),
    downs: [],
    changed: [],
    composed: [],
    scrolled_now: false,
    scrolled_ats: [],
    drawn_revs: 1,
    places_rev: 0,
    said_revs: 1,
    said_seen: 0,
    said_modal: (-3, -3, -3, -3),
    said_again: {},
    said_helds: {},
    removed: [],
    pending: [],
    drawn_due: false,
    before_causes: 0,
    standing: false,
    settle_asked: false,
    settle_at: 0.0,
    measured_gen: -1,
    walk_from: -1,
    measuring: false,
    binding_reading: -1,
    alone_due: [],
    alone_laid: [],
    alone_asks: {},
    rows_named: {},
    lists_scrolled: {},
    lists_asked: {},
    rooming: -1,
    room_marks: 0,
    room_spill: [],
    pixel_grid: 0.0,
    rows_grid: 0.0,
    rows_lists: [],
    thumbs: {},
    rows_grid_said: @signals.signal(0.0),
    on_due: fn() {  },
    on_cursor: fn() {  },
    on_modals: fn() {  },
    shared_live: {},
    shared_n: 0,
    shared_moving: {},
    shared_stays: {},
    departures: [],
    arrivals: [],
    pairs_asked: false,
    images_wanted: [],
    flights: [],
    lifting: false,
    laids: 0,
    held_kept: [],
    held_kept_for: (-1, -1, -1, -1),
    held_walked: 0,
    boxes_held: 0,
    boxes_held_at: [],
    boxes_one_by_one: 0,
    timed: None,
    structuring: 0,
    measured_ms: 0.0,
    said_count: 0,
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
      boxes_walked: 0,
      structure: 0,
      pulled: 0,
      drawn_boxes: 0,
      settles: 0,
      found_walked: 0,
      near_kept: 0,
      inputs_walked: 0,
      order_copied: 0,
    },
  }
  // (the clock held while it is read, as a core's topic is: what reads it at rest (put by, View::park; rested in place,
  // View::rests) lets go of it, so the tree is not moving for a way nothing draws, and reads it anew as it wakes,
  // where the clock has it then: @signals.rest)
  t.clock.on_unwatched(fn() {  })
  let root = t.made(-1)
  root.owning(fn() { make(root) })
  t
}

///|
/// Words measured as a test's are: 7 a character, 18 a line, wrapped to the width offered, whatever the size of words.
pub fn words_measure(words : String, _look : WordsLook, width : Double, _scale : Double) -> (Double, Double) {
  let full = words.length().to_double() * 7.0
  if full <= 0.0 {
    return (0.0, 0.0)
  }
  let w = if width > 0.0 && width < full { width } else { full }
  let lines = if w > 0.0 { (full / w).ceil() } else { 1.0 }
  (w, lines * 18.0)
}

///|
/// A node made in `parent` (-1: the root), its scope its own (made with nothing reading: owned by nothing else),
/// made at `loc` in the source (kept where the tree keeps that: source.mbt), its words at the size they are said where
/// `words_as_said` (what it is made in's, or its own: View::box).
fn Tree::made(self : Tree, parent : Int, words_as_said? : Bool = false, loc? : SourceLoc) -> View {
  self.work.made = self.work.made + 1
  self.hits_bump()
  let at = match self.free.pop() {
    Some(i) => {
      let n = self.nodes[i]
      n.gen = n.gen + 1
      n.live = true
      n.flex = @flex.Node::new()
      n.look.ground = 0L
      n.look.ink = 0L
      n.look.words = ""
      n.look.words_drawn = None
      // (each array it holds empty made anew only where it is not: never changed in place, only set again)
      if n.shorter.length() > 0 {
        n.shorter = []
      }
      n.shrink_said = None
      n.min_w_said = None
      n.max_w_said = None
      n.min_w_within = false
      n.max_w_within = false
      if n.look.runs.length() > 0 {
        n.look.runs = []
      }
      n.look.runs_look = runs_plain
      n.look.runs_pressed = -1
      n.look.runs_picked = (0, 0)
      if n.look.runs_marks.length() > 0 {
        n.look.runs_marks = []
      }
      if n.look.shapes.length() > 0 {
        n.look.shapes = []
      }
      n.look.tint = 0L
      n.look.radius = 0.0
      n.look.corners = None
      n.look.edge = (0.0, 0L)
      n.look.image = None
      n.look.image_for = (0.0, 0.0)
      n.look.image_cover = false
      n.look.image_contain = false
      n.look.image_cover_at = None
      n.look.image_fade = false
      n.look.image_in = None
      n.look.glass = None
      n.look.words_look = words_plain
      n.look.shadow = (0.0, 0.0, 0L)
      n.said = None
      n.said_hidden = false
      if n.behind {
        self.behind_set -= 1
      }
      n.behind = false
      if n.bones != 0L {
        self.bones_set -= 1
      }
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
      n.look.words_breaks = false
      n.look.glyphs_said = 0
      n.look.ellipsis_past = false
      n.look.picture = None
      n.look.turn = 0.0
      n.look.turn_drawn = false
      n.look.fades = (0.0, 0.0, 0.0, 0.0)
      n.look.stretch = 0.0
      n.look.drawn_off = (0.0, 0.0)
      n.look.ground_drawn = ground_as_laid
      n.look.cut_soft = false
      if n.look.lines.length() > 0 {
        n.look.lines = []
      }
      n.drew = false
      n.drawn_off = (0.0, 0.0, 0.0, 0.0)
      n.glyphs_fn = None
      n.moved_by = None
      n.moved = (0.0, 0.0)
      n.moved_holds = None
      n.moved_ends = None
      n.went = None
      n.parent = parent
      n.allow_ellipsis = false
      n.words_as_said = words_as_said
      n.slot = false
      n.along_row = false
      n.alone = false
      n.boxes_due = false
      n.fault_to = None
      n.hosted = false
      n.on_press = None
      n.on_double_press = None
      n.on_step = None
      n.top_row = false
      n.moves_window = false
      n.on_menu = None
      n.on_wheel = None
      n.on_key = None
      n.on_back = None
      n.on_back_step = None
      n.pressed_cell = None
      n.pointed_cell = None
      n.ground_read = 0
      n.on_pointer_moved = None
      n.pointed_in_cell = None
      n.within_cell = None
      n.piece_cell = None
      n.said_cell = None
      n.each_row = false
      n.focusable = false
      n.focus_keys = 0
      n.focus_tab = true
      n.tab_by_stop = false
      n.input_cell = None
      n.cursor = None
      n.as_ground = false
      n.beside = None
      n.beside_last = None
      n.beside_point = None
      n.beside_piece = None
      n.focused_cell = None
      n.size_cell = None
      n.bounds_input = false
      n.tucked_under = None
      n.drawn_clear = None
      n.bar_near = 0.0
      n.bar_across = false
      n.points = false
      n.bar_near_cell = None
      n.inputs_own = false
      n.inputs_in = 0
      n.shows = None
      n.shows_across = false
      n.shows_room = None
      n.claims = None
      n.claims_from = None
      n.claims_said = 0
      n.yields = false
      n.hold_only = None
      n.line_gap = None
      n.claims_scroll = false
      n.scroll_held = -1
      n.drawn_rev = 0
      n.said_rev = 0
      n.words_rev = 0
      n.kids_rev = 0
      n.own_rev = 0
      n.state_rev = 0
      n.scroll_across = false
      n.scroll_off = None
      n.scroll_by = -1
      n.list_rows = false
      n.focus_shown_cell = None
      n.key_said = 0
      n.wheel_said = 0
      n.on_drag = None
      n.drags_whole = false
      n.takes = None
      if n.takes_units.length() > 0 {
        n.takes_units = []
      }
      n.takes_ver = None
      n.drag_end = None
      n.look_due = false
      n.place_due = false
      n.placed = false
      n.out = false
      n.content = None
      self.draws_rev = self.draws_rev + 1
      self.draws_any_rev = self.draws_any_rev + 1
      n.left_at = -1.0
      n.span = 0.0
      n.back_at = -1.0
      n.back_from = 0.0
      n.going = None
      n.leave_told = false
      n.coming = false
      n.come_said = None
      n.come_off = fn() {  }
      n.come_wake = None
      n.clips_said = false
      n.inert = false
      n.modal = false
      n.back_goes_on = false
      n.leaves_typing = false
      n.over_all = false
      n.over_scrim = false
      n.stack = -1
      n.source = None
      n.share = None
      n.share_flight = None
      n.share_stays = false
      n.share_with_stays = false
      n.lift = None
      i
    }
    None => {
      self.nodes.push({
        gen: 0,
        live: true,
        flex: @flex.Node::new(),
        look: { ground: 0L, ink: 0L, words: "", words_drawn: None, words_look: words_plain, runs: [], runs_look: runs_plain, runs_pressed: -1, runs_picked: (0, 0), runs_marks: [], shadow: (0.0, 0.0, 0L), shapes: [], tint: 0L, lines: [], edge: (0.0, 0L), image: None, image_for: (0.0, 0.0), image_cover: false, image_contain: false, image_cover_at: None, image_fade: false, stretch: 0.0, image_in: None, radius: 0.0, corners: None, glass: None, alpha: 1.0, dx: 0.0, dy: 0.0, sx: 0.0, sy: 0.0, scale: 1.0, pivot: At(0.5, 0.5), turn: 0.0, turn_drawn: false, fades: (0.0, 0.0, 0.0, 0.0), drawn_off: (0.0, 0.0), ground_drawn: ground_as_laid, cut_soft: false, drawn_as: "", clips: false, words_center: false, words_breaks: false, glyphs_said: 0, ellipsis_past: false, picture: None },
        parent,
        allow_ellipsis: false,
        words_as_said,
        kids: [],
        owner: None,
        stop: None,
        drops: {},
        drop_next: 0,
        leavings: [],
        backs: [],
        leave_told: false,
        props: {},
        on_press: None,
        on_double_press: None,
        on_step: None,
        top_row: false,
        moves_window: false,
        on_menu: None,
        on_wheel: None,
        on_key: None,
        key_said: 0,
        wheel_said: 0,
        on_back: None,
        on_back_step: None,
        back_said: 0,
        pressed_cell: None,
        pointed_cell: None,
        ground_read: 0,
        on_pointer_moved: None,
        pointed_in_cell: None,
        within_cell: None,
        piece_cell: None,
        said_cell: None,
        each_row: false,
        boxes_due: false,
        focusable: false,
        input_cell: None,
        cursor: None,
        as_ground: false,
        beside: None,
        went: None,
        beside_last: None,
        beside_point: None,
        beside_piece: None,
        focus_keys: 0,
        focus_tab: true,
        tab_by_stop: false,
        focused_cell: None,
        size_cell: None,
        bounds_input: false,
        tucked_under: None,
        drawn_clear: None,
        bar_near: 0.0,
        bar_across: false,
        points: false,
        bar_near_cell: None,
        inputs_own: false,
        inputs_in: 0,
        shows: None,
        shows_across: false,
        shows_room: None,
        claims: None,
        claims_from: None,
        claims_said: 0,
        yields: false,
        hold_only: None,
        line_gap: None,
        shrink_said: None,
        min_w_said: None,
        max_w_said: None,
        min_w_within: false,
        max_w_within: false,
        shorter: [],
        claims_scroll: false,
        scroll_held: -1,
        drawn_rev: 0,
        said_rev: 0,
        words_rev: 0,
        kids_rev: 0,
        own_rev: 0,
        state_rev: 0,
        scroll_across: false,
        scroll_off: None,
        scroll_by: -1,
        list_rows: false,
        focus_shown_cell: None,
        on_drag: None,
        fingers: 1,
        drags_whole: false,
        drag_said: 0,
        takes: None,
        takes_units: [],
        takes_ver: None,
        drag_end: None,
        slot: false,
        along_row: false,
        alone: false,
        fault_to: None,
        hosted: false,
        said: None,
        said_hidden: false,
        behind: false,
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
        glyphs_fn: None,
        moved_by: None,
        moved: (0.0, 0.0),
        moved_holds: None,
        moved_ends: None,
        content: None,
        left_at: -1.0,
        span: 0.0,
        back_at: -1.0,
        back_from: 0.0,
        going: None,
        coming: false,
        come_said: None,
        come_off: fn() {  },
        come_wake: None,
        clips_said: false,
        inert: false,
        modal: false,
        back_goes_on: false,
        leaves_typing: false,
        over_all: false,
        over_scrim: false,
        stack: -1,
        source: None,
        share: None,
        share_flight: None,
        share_stays: false,
        share_with_stays: false,
        lift: None,
      })
      self.nodes.length() - 1
    }
  }
  let n = self.nodes[at]
  n.source = match loc {
    Some(l) if self.sources => Some({ made: l, made_for: None, said: {} })
    _ => None
  }
  let was = @signals.set_active_sub(None)
  let was_owner = @signals.set_owner(None)
  n.stop = Some(@signals.effect_scope(fn() { n.owner = @signals.active_sub() }))
  @signals.set_active_sub(was) |> ignore
  @signals.set_owner(was_owner) |> ignore
  // (an index given back and made again: in no order yet, of no top, whatever the one let go of there was)
  if at < self.order_of.length() {
    self.order_of[at] = -1
    self.tops[at] = -2
  }
  // (put in the order by what holds it as it is laid out there: View::box_appended by its own run, View::slot from what
  // holds it)
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
  self.clock_read_in_binding("logic_at")
  self.logic_said()
}

///|
/// The logic's moment, as Tree::logic_at says it, not said to be read in a binding: the tree's own work's (a layout, a
/// scroll, what a pointer is over) and View::goes_now's.
fn Tree::logic_said(self : Tree) -> Double {
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
  self.clock_read_in_binding("drawn_at")
  self.clock.get()
}

///|
/// The moment what is drawn is drawn at, as Tree::drawn_at says it, followed, not said to be read in a binding: the
/// tree's own ways that follow the clock only while they go (a scroll on by itself, its bar coming and going), as
/// View::drawn_while's.
fn Tree::drawn_said(self : Tree) -> Double {
  self.clock.get()
}

///|
/// Whether what `goes` says of the logic's moment holds (a way that goes then: one way, or any of several), the clock
/// not followed: only true or false, never the moment itself. What a binding asks whether a way goes by
/// (`n.goes_now(way.goes_at)`), worked out again only as what says it changes. So its caller is told at both ends of
/// it, or it stands as it was: as the way is said (its signal read in the same binding) and at its declared end (a
/// moment of the timeline, View::at_moment, setting what the binding reads). The check of what reads the time in a
/// binding (clock_read.mbt) cannot see a caller told at neither; the tests of what reads it (motion's
/// node_way_goes_wbtest) hold it. The one place a binding asks with the logic's moment (View::drawn_while is built on it).
pub fn View::goes_now(self : View, goes : (Double) -> Bool) -> Bool {
  goes(self.tree.logic_said())
}

///|
/// The moment what is drawn is drawn at while what `goes` says of the logic's moment holds (View::goes_now), followed;
/// once it no longer does, past every end (+inf: a way read at it is where it went), the clock no longer followed. What
/// a binding reads a way by (`way.value_at(n.drawn_while(way.goes_at))`): worked out again as the clock goes while it
/// goes, and not after.
pub fn View::drawn_while(self : View, goes : (Double) -> Bool) -> Double {
  if self.goes_now(goes) {
    // (the clock followed, read so: what a way that goes is drawn by, not a read of the time of a binding's own)
    self.tree.clock.get()
  } else {
    @double.infinity
  }
}

///|
/// Where a cycle of `period` ms is as what is drawn is drawn (0 to 1, from moment 0 on), followed: for a wait drawn by
/// it as long as it shows (a spinner's turn, a band of progress not known), which never ends and is no motion
/// (Tree::cycle_read); as Ctx::cycle is an old view's.
pub fn View::cycle(self : View, period : Double) -> Double {
  self.tree.clock_read_in_binding("cycle")
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
  let ticking_was = self.ticking
  self.ticking = true
  self.beat.set(ms)
  self.resident.set(resident_of(ms))
  self.ticking = ticking_was
}

///|
/// Where a cycle of `period` ms is on the resident clock's steps (0 to 1, from moment 0 on), followed: for an endless
/// decoration (a working mark's spokes, a waiting mark's breath) drawn anew only at each step, as an old view's resident
/// cycle is (Ctx::cycle's `resident`): what hosts the tree wakes for its next step, said `later` (Tree::resident_next),
/// not a frame after each frame.
pub fn View::cycle_resident(self : View, period : Double) -> Double {
  let t = self.tree.resident.get()
  let read = (self.gen, t)
  if self.tree.resident_readers.get(self.at) != Some(read) {
    self.tree.resident_readers[self.at] = read
    self.tree.resident_rev = self.tree.resident_rev + 1
  }
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
  // (as last said, where nothing it reads changed since: the order, what is drawn, what is left out, the readers, the
  // step)
  let now = self.resident.untracked()
  let (dr, hits, step, rr, said) = self.resident_said
  if !self.order_due &&
    !self.outs_changed &&
    dr == self.draws_rev &&
    hits == self.hits &&
    step == now &&
    rr == self.resident_rev {
    return said
  }
  let said = self.resident_found(now)
  self.resident_said = (self.draws_rev, self.hits, now, self.resident_rev, said)
  said
}

///|
/// Whether an endless decoration reads the resident clock's step `now` where it is drawn now (Tree::resident_read),
/// found.
fn Tree::resident_found(self : Tree, now : Double) -> Bool {
  // (those let go, or no longer reading it (the step they last read not this one: a mark that stopped), dropped)
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
  if self.resident_readers.is_empty() {
    return false
  }
  // (each reader drawn where something of what it is, or holds, is drawn as the order goes (Tree::each_drawn_in_order):
  // none of what holds it in the order left out, nor itself, and content of its own or under it; each found by where it
  // is in the order, nothing else of the tree gone through. A reader not in the order itself (a slot's) found the long
  // way, as each drawn is found)
  let mut plain = true
  for at, _ in self.resident_readers {
    if at >= self.order_of.length() || self.order_of[at] < 0 {
      plain = false
    }
  }
  if plain {
    let len = self.order.length()
    for at, _ in self.resident_readers {
      let p = self.order_of[at]
      if p >= len || self.order[p] != at {
        plain = false
        break
      }
      let mut h = p
      let mut hidden = false
      while h >= 0 {
        if self.nodes[self.order[h]].out {
          hidden = true
          break
        }
        h = self.order_holder[h]
      }
      if hidden {
        continue
      }
      let mut i = p
      let end = self.order_end[p]
      while i < end && i < len {
        let n = self.nodes[self.order[i]]
        if n.out {
          i = self.order_end[i]
          continue
        }
        if n.content is Some(_) {
          return true
        }
        i = i + 1
      }
    }
    if plain {
      return false
    }
  }
  let mut seen = false
  // (what of the way up from each is known to hold no reader, by index: each looked at once, not for every node under it)
  let clear : Array[Bool] = Array::make(self.nodes.length(), false)
  self.each_drawn_scaled(fn(c, _, _, _, _) {
    let mut i = c.id.at
    while !seen && i >= 0 && !clear[i] {
      if self.resident_readers.contains(i) {
        seen = true
      }
      i = self.nodes[i].parent
    }
    if !seen {
      let mut j = c.id.at
      while j >= 0 && j != i {
        clear[j] = true
        j = self.nodes[j].parent
      }
    }
  })
  seen
}

///|
/// The resident clock's next step after the moment drawn now (Tree::drawn_at's).
pub fn Tree::resident_next(self : Tree) -> Double {
  resident_of(self.clock.untracked()) + resident_step_ms
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
  self.frame_ms = ms
  self.clock_to(ms)
  self.beat_set(ms)
}

///|
/// The moment what is drawn is drawn at set to `ms` (a frame's, an input's, the logic's for a while and back): what
/// follows whether it is at or past a moment told so, as it comes to be so or not (View::drawn_past), each still read
/// by what reads it and its node living, the rest let go; told of what was followed as this began, what is followed
/// anew meanwhile kept for the next.
fn Tree::clock_to(self : Tree, ms : Double) -> Unit {
  // (the moment and whether it is past each followed, told as one: no reader sees the one without the other)
  @signals.start_batch()
  let ticking_was = self.ticking
  self.ticking = true
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
  // (what it told, told as the batch ends: told by the clock)
  @signals.end_batch()
  self.ticking = ticking_was
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
      let now = self.tree.clock.untracked()
      let c = @signals.signal(now >= t, same=fn(a, b) { a == b })
      self.tree.drawn_marks.push((id, t, c))
      c
    }
  }
  cell.get()
}

///|
/// The tree's work timed by part, for whoever looks into a slow frame (mbui's ui: a hang's parts, journal.mbt): `now`
/// its clock (below 0 while nobody listens: nothing timed then) and `took` told each part and its ms. The parts: the
/// structures' changes done (what a show, a pick or a list's rows make and let go: the outermost of them, wherever it
/// runs, an input's handler or the frame), and of Tree::laid_out the bindings told, the layout, the placing with the
/// looks and the order, and the words measured (inside the layout's time, said apart). None: none timed.
pub fn Tree::timed_by(self : Tree, by : (() -> Double, (String, Double) -> Unit)?) -> Unit {
  self.timed = by
}

///|
/// A part of its work begins: the timing clock's now, below 0 where nothing is timed (Tree::part_ended).
fn Tree::part_began(self : Tree) -> Double {
  match self.timed {
    Some((now, _)) => now()
    None => -1.0
  }
}

///|
/// The part begun at `t0` (Tree::part_began) is done: who times it told it was `what` and how long.
fn Tree::part_ended(self : Tree, what : String, t0 : Double) -> Unit {
  guard t0 >= 0.0 else { return }
  if self.timed is Some((now, took)) {
    took(what, now() - t0)
  }
}

///|
/// `f`, a structure's change, done: timed as the tree's structures where it is the outermost.
fn Tree::structure_done(self : Tree, f : () -> Unit) -> Unit {
  let t0 = if self.structuring == 0 { self.part_began() } else { -1.0 }
  self.structuring += 1
  @signals.untracked(f)
  self.structuring -= 1
  self.part_ended("tree structures", t0)
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
  self.gone = true
  // (what follows the pointer held by nothing of the tree's nodes: let go with it, told nothing more)
  self.point_stopped()
  if self.nodes.length() > 0 && self.nodes[0].live {
    self.root().let_go()
  }
  self.drawn_marks.clear()
  self.looks_due.clear()
  self.places_due.clear()
  self.bindings_due.clear()
  self.bindings = 0
  self.pulls_marked.clear()
  self.timeline.clear()
  self.draws_rev = self.draws_rev + 1
  self.draws_any_rev = self.draws_any_rev + 1
  self.order.clear()
  self.order_holder.clear()
  self.order_end.clear()
  self.order_of.clear()
  self.tops.clear()
  self.order_in.clear()
  self.order_whole = true
  // (a walk going on keeps what it walks with till it ends; none kept for the next, its room given back with it)
  self.walks = []
  self.changed.clear()
  self.composed.clear()
  self.hosting = -1
  self.modals.clear()
  self.backs = 0
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
  self.focus_holds.clear()
  self.laid_waits.clear()
  self.afters.clear()
  self.held_tracks.clear()
  self.thumbs.clear()
}

///|
/// A node made in `self`, after what it holds already, made by `make` as its own (in its scope).
/// Made at `loc`, the place that asked for it; the outside of the part asked for at `made_for` where a library's part
/// makes it so (View::made_for, source.mbt).
/// Where `words_as_said`, its words and the words of all made in it are drawn and measured at the size they are said,
/// whatever the system's size of words (View::words_scale answers 1 there): words that are part of a mark drawn by its
/// points (a letter in a disc, a badge's `!`), as an icon is. Said as it is made, so all made in it after is made so
/// (what is made in it takes it from what it is made in); never said of a node made already.
#callsite(autofill(loc))
pub fn View::box(
  self : View,
  make : (View) -> Unit,
  made_for? : SourceLoc,
  words_as_said? : Bool = false,
  loc~ : SourceLoc,
) -> View {
  guard self.live() is Some(n) else { return self.tree.none() }
  let v = self.tree.made(self.at, words_as_said=words_as_said || n.words_as_said, loc~)
  match made_for {
    Some(l) => v.made_for(l) |> ignore
    None => ()
  }
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
/// it and what holds it are drawn: View::scale): where a press finds it as where it is drawn. Held by no node from the
/// root (put by: View::park), nowhere, of no size.
pub fn View::rect(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) && self.tree.held_from_root(self.at) else { return (0.0, 0.0, 0.0, 0.0) }
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
/// Something for a frame to do: what hosts it told as there first is.
fn Tree::marked(self : Tree) -> Unit {
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
/// holder's layout reused, is no sign the rest are). `within`: what it holds changed, not itself (its boxes put again),
/// so where it lays out alone it is laid out again from itself.
fn Tree::layout_marked_at(self : Tree, at : Int, within? : Bool = false) -> Unit {
  // (as a room is told, in its layout: in it alone, laid out there)
  if self.rooming >= 0 {
    self.room_marked_at(at)
    return
  }
  self.layout_due = true
  // (what was laid out to be read no more where it stands)
  self.measured_gen = -1
  self.hits_bump()
  self.marked()
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    n.flex.dirty = true
    // (in what lays out alone, laid out as big as it was asked before: laid out again from it, nothing above it)
    if (i != at || within) && n.alone && n.flex.laid_given() {
      self.alone_due.push(i)
      return
    }
    i = n.parent
  }
}

///|
/// Node `at` laid out alone, nothing above it, as the layout of all of it lays it out over the rest in node `holder`
/// (absolute in it: a width said of it since, Tree::beside_widened): @flex.absolute_relaid, so it comes out the same
/// whichever of the two lays it out. Which compute it was, for Tree::walk to place by.
fn Tree::laid_over_alone(self : Tree, at : Int, holder : Int) -> Int {
  self.work.computes = self.work.computes + 1
  self.laids = self.laids + 1
  @flex.absolute_relaid(self.nodes[holder].flex, self.nodes[at].flex)
}

///|
/// What lays out alone with something under it marked laid out again (Tree::layout_marked_at), laid out from it as it
/// was asked before (@flex.relayout), to be placed by as the rest is; before the layout of all of it, which keeps it as
/// it is unless what holds it asks it otherwise now.
fn Tree::alone_laid_out(self : Tree) -> Unit {
  // (by its index: one that what it holds asks to be laid out again (below) put after the rest, laid out in turn)
  let mut j = 0
  while j < self.alone_due.length() {
    let at = self.alone_due[j]
    j = j + 1
    let n = self.nodes[at]
    if n.live && n.flex.dirty && n.flex.laid_given() {
      self.work.computes = self.work.computes + 1
      self.laids = self.laids + 1
      @flex.relayout(n.flex)
      self.alone_laid.push((at, @flex.computes()))
      // (what it holds came out another size than it is counted: what holds it laid out again, from the nearest that
      // lays out alone above it as a change in it is (Tree::layout_marked_at), which measures it there)
      match self.alone_asks.get(at) {
        Some(ask) if ask() => {
          let mut i = n.parent
          while i >= 0 {
            let m = self.nodes[i]
            m.flex.dirty = true
            if m.alone && m.flex.laid_given() {
              self.alone_due.push(i)
              break
            }
            i = m.parent
          }
        }
        _ => ()
      }
    } else if n.live && n.flex.dirty {
      // (no longer as it was asked: laid out with what holds it, by the layout of all of it after this)
      let mut i = n.parent
      while i >= 0 {
        self.nodes[i].flex.dirty = true
        i = self.nodes[i].parent
      }
    }
  }
  self.alone_due.clear()
  // (what what was asked told meanwhile (a list's block measured as tall as it was counted, what shows under it worked
  // out by that) worked out once all of it is laid out, and laid out in this same pass)
  if !self.bindings_due.is_empty() {
    self.once_laid_out(fn() {  })
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
  self.touched(at)
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
  self.touched(at, words=false)
  if !n.place_due {
    n.place_due = true
    self.places_due.push(at)
    self.hits_bump()
    self.marked()
  }
  // (where it is drawn off in what holds it, as it changes, whatever else of its place was told before: the middle of
  // what each that holds it draws, not its own)
  let off = (n.look.dx + n.moved.0, n.look.dy + n.moved.1, n.look.sx, n.look.sy)
  if n.drawn_off != off {
    n.drawn_off = off
    self.drawn_stale_from(n.parent)
  }
}

///|
/// The order the nodes are drawn in to be made again (one made, let go or moved among its siblings).
fn Tree::order_marked(self : Tree) -> Unit {
  self.order_whole = true
  self.order_due = true
  self.hits_bump()
  self.marked()
}

///|
/// The order to be made again where node `at` holds something otherwise (one made in it, let go of, moved among what
/// it holds): from what holds it there (Tree::order_again), the rest as it is.
fn Tree::order_marked_in(self : Tree, at : Int) -> Unit {
  self.order_in.push(at)
  self.order_due = true
  self.hits_bump()
  self.marked()
}

///|
/// Node `at` (no slot) made in what node `h` lays out: put in the order by its own run where it goes, the rest of the
/// order as it was (Tree::order_spliced); else from `h` as any change there is (Tree::order_marked_in).
fn Tree::order_put_in(self : Tree, at : Int, h : Int) -> Unit {
  self.order_ins.push((at, h))
  self.order_due = true
  self.hits = self.hits + 1
  self.marked()
}

///|
/// Node `at` (of making `gen`) let go, held by `parent`: its run taken out of the order, the rest as it was
/// (Tree::order_spliced); else from what held it as any change there is.
fn Tree::order_taken_out(self : Tree, at : Int, gen : Int, parent : Int) -> Unit {
  self.order_outs.push((at, gen, parent))
  self.order_due = true
  self.hits = self.hits + 1
  self.marked()
}

///|
/// Whether node `at` is in the order as it is now, the node of that making there.
fn Tree::in_order(self : Tree, at : Int) -> Bool {
  let i = self.order_of[at]
  i >= 0 && i < self.order.length() && self.order[i] == at && self.order_gen[at] == self.nodes[at].gen
}

///|
/// Where the run of what node `at` holds in the order ends (it no slot, in the order; a slot, the last of what it holds
/// that is): none where none of it is.
fn Tree::order_run_end(self : Tree, at : Int) -> Int? {
  let n = self.nodes[at]
  if !n.slot {
    return if self.in_order(at) { Some(self.order_end[self.order_of[at]]) } else { None }
  }
  let mut i = n.kids.length() - 1
  while i >= 0 {
    match self.order_run_end(n.kids[i]) {
      Some(e) => return Some(e)
      None => ()
    }
    i = i - 1
  }
  None
}

///|
/// Where node `at`'s run goes in the order, and the place of what holds it there: after the run of what comes before it
/// in its slots, else just after what holds it. None where what holds it is the root (its children ordered by the
/// window's layers, Tree::kids_in_order) or not in the order.
fn Tree::order_place(self : Tree, at : Int) -> (Int, Int)? {
  let h = self.box_holder(at)
  guard h > 0 && self.in_order(h) else { return None }
  let mut c = at
  while true {
    let p = self.nodes[c].parent
    guard p >= 0 else { return None }
    let kids = self.nodes[p].kids
    let mut j = match kids.search(c) {
      Some(i) => i - 1
      None => return None
    }
    while j >= 0 {
      match self.order_run_end(kids[j]) {
        Some(e) => return Some((e, self.order_of[h]))
        None => ()
      }
      j = j - 1
    }
    if p == h {
      return Some((self.order_of[h] + 1, self.order_of[h]))
    }
    c = p
  }
  None
}

///|
/// The nodes made and let go since the order was last worked out put in it and taken out of it by their own runs, the
/// rest of the order moved past them as it was: no run of the order but theirs worked out, none copied. Whether it was
/// so: not where one let go is not in the order as its making, nor where one made has no place found in it (all of it
/// made again then).
fn Tree::order_spliced(self : Tree) -> Bool {
  // (a few alone: many made or let go at once (a page opened), what holds them made again once instead of each
  // splice moving all after it)
  guard self.order_ins.length() + self.order_outs.length() <= boxes_one_by_one_most else { return false }
  // (each made held by what is in the order, or by one made before it in this change: none by the root)
  for k, o in self.order_ins {
    let (at, _) = o
    guard self.nodes[at].live && !self.nodes[at].slot else { continue }
    let h = self.box_holder(at)
    let held_by_one_made = self.order_ins[:k].iter().any(fn(e) { e.0 == h })
    guard h > 0 && (self.in_order(h) || held_by_one_made) else { return false }
  }
  // (taken out first, each as it is in the order)
  for o in self.order_outs {
    let (at, gen, _) = o
    let i = self.order_of[at]
    guard i >= 0 && i < self.order.length() && self.order[i] == at && self.order_gen[at] == gen else { return false }
  }
  for o in self.order_outs {
    let (at, _, _) = o
    let p = self.order_of[at]
    let e = self.order_end[p]
    let d = e - p
    let hi = self.order_holder[p]
    for j in p..<e {
      let a = self.order[j]
      if self.order_of[a] == j {
        self.order_of[a] = -1
      }
    }
    let len = self.order.length()
    self.order_moved(e, len, 1, -d, e)
    self.order.truncate(len - d)
    self.order_holder.truncate(len - d)
    self.order_end.truncate(len - d)
    let mut j = hi
    while j >= 0 {
      self.order_end[j] = self.order_end[j] - d
      j = self.order_holder[j]
    }
  }
  // (then put in, each where it goes as what it is among is now; one made with another put in already with its run)
  for o in self.order_ins {
    let (at, _) = o
    guard self.nodes[at].live && !self.nodes[at].slot else { continue }
    if self.in_order(at) {
      continue
    }
    guard self.order_place(at) is Some((p, hi)) else {
      self.order_whole = true
      return true
    }
    let h = self.order[hi]
    self.order_new.clear()
    self.order_new_holder.clear()
    self.order_new_end.clear()
    self.ordered_keeping(at, hi, self.tops[h], p, p)
    let made = self.order_new.length()
    let len = self.order.length()
    for _ in 0..<made {
      self.order.push(-1)
      self.order_holder.push(-1)
      self.order_end.push(-1)
    }
    self.order_moved(len - 1, p - 1, -1, made, p)
    for k in 0..<made {
      self.order.unsafe_set(p + k, self.order_new.unsafe_get(k))
      self.order_holder.unsafe_set(p + k, self.order_new_holder.unsafe_get(k))
      self.order_end.unsafe_set(p + k, self.order_new_end.unsafe_get(k))
    }
    let mut j = hi
    while j >= 0 {
      self.order_end[j] = self.order_end[j] + made
      j = self.order_holder[j]
    }
  }
  true
}

///|
/// The order the nodes are drawn in made again (Tree::ordered): from each in it that holds what changed in it
/// (Tree::order_marked_in), what it holds put in its place and the rest moved past it, all of it where the root's
/// changed, where that is not known, or where more than a few did.
fn Tree::order_again(self : Tree) -> Unit {
  self.draws_rev = self.draws_rev + 1
  self.places_rev = self.places_rev + 1
  self.draws_any_rev = self.draws_any_rev + 1
  let n = self.nodes.length()
  while self.order_of.length() < n {
    self.order_of.push(-1)
    self.tops.push(-2)
    self.order_gen.push(-1)
    self.order_was.push(-1)
    self.order_changed.push(-1)
  }
  // (nodes made and let go by themselves, nothing else changed in it: their own runs put in and taken out, the rest as
  // it was, Tree::order_spliced; else what held each made again as any change there is)
  if !self.order_ins.is_empty() || !self.order_outs.is_empty() {
    let alone = !self.order_whole &&
      !self.order.is_empty() &&
      self.flights.length() == 0 &&
      self.order_in.is_empty()
    if alone && self.order_spliced() && !self.order_whole {
      self.order_ins.clear()
      self.order_outs.clear()
      return
    }
    for o in self.order_outs {
      self.order_in.push(o.2)
    }
    for o in self.order_ins {
      self.order_in.push(o.1)
    }
    self.order_ins.clear()
    self.order_outs.clear()
  }
  // (all of it while anything flies: what does drawn over the rest of its layer, out of what holds it, shared.mbt)
  let from = if self.order_whole || self.order.is_empty() || self.flights.length() > 0 {
    None
  } else {
    self.order_holders()
  }
  // (what holds each change, up to the root: what is not one of them, moved or not, holds what it held, its run of the
  // order kept as it was, Tree::order_from)
  if from is Some(_) {
    self.order_stamp = self.order_stamp + 1
    for r in self.order_in {
      let mut h = r
      while h >= 0 && h < n && self.order_changed[h] != self.order_stamp {
        self.order_changed[h] = self.order_stamp
        h = self.nodes[h].parent
      }
    }
  }
  self.order_whole = false
  self.order_in.clear()
  match from {
    Some(hs) => for h in hs {
      self.order_from(h)
    }
    None => {
      self.order.clear()
      self.order_holder.clear()
      self.order_end.clear()
      for i in 0..<n {
        self.tops[i] = -2
        self.order_of[i] = -1
      }
      self.ordered(0, -1, -1)
    }
  }
}

///|
/// What holds each change since the order was last worked out (Tree::order_in) there: the first of it in the order,
/// none held by another of them; none where that is the root's or more than a few (all of it again).
fn Tree::order_holders(self : Tree) -> Array[Int]? {
  let hs : Array[Int] = []
  for r in self.order_in {
    // (let go of since: its going said by what held it as it went)
    guard r >= 0 && r < self.nodes.length() && self.nodes[r].live else { continue }
    let mut h = r
    while h > 0 && (self.nodes[h].slot || self.order_of[h] < 0) {
      h = self.nodes[h].parent
    }
    // (held by nothing: in no order)
    guard h >= 0 else { continue }
    guard h > 0 && self.order_of[h] < self.order.length() && self.order[self.order_of[h]] == h else { return None }
    if !hs.contains(h) {
      hs.push(h)
    }
  }
  guard hs.length() <= 4 else { return None }
  let firsts = hs.filter(fn(h) {
    let i = self.order_of[h]
    !hs.iter().any(fn(g) {
      let o = self.order_of[g]
      g != h && i >= o && i < self.order_end[o]
    })
  })
  // (the last in the order first: what one made again let go of is gone from it before one made earlier in it moves
  // all after it, each where it is then, an index let go of there and made again in another taken for none of its)
  firsts.sort_by(fn(a, b) { self.order_of[b].compare(self.order_of[a]) })
  Some(firsts)
}

///|
/// The order made again from node `h` in it (Tree::order_again): what it holds worked out again in its place, what
/// comes after it moved by as many as that is longer or shorter, what holds it ending that much later.
fn Tree::order_from(self : Tree, h : Int) -> Unit {
  let p = self.order_of[h]
  let e = self.order_end[p]
  let holder = self.order_holder[p]
  for j in p..<e {
    let at = self.order.unsafe_get(j)
    // (one let go of here whose index is another's now, put in the order already where that holds it: left where it is)
    if self.order_of[at] == j {
      self.order_of[at] = -1
    }
    self.order_was[at] = j
  }
  // (its run made again aside (`order_new`, from `p`), what of it holds no change since copied from where it is now,
  // the order left as it is till then: no copy made of the run, nor of what comes after it, Tree::ordered_keeping)
  self.order_new.clear()
  self.order_new_holder.clear()
  self.order_new_end.clear()
  self.ordered_keeping(h, holder, self.tops[h], p, e)
  let len = self.order.length()
  let made = self.order_new.length()
  let d = p + made - e
  // (what comes after it moved by as many as its run is longer or shorter, in place, from the end it moves towards;
  // what holds it ending that much later)
  if d > 0 {
    for _ in 0..<d {
      self.order.push(-1)
      self.order_holder.push(-1)
      self.order_end.push(-1)
    }
    self.order_moved(len - 1, e - 1, -1, d, e)
  } else if d < 0 {
    self.order_moved(e, len, 1, d, e)
    self.order.truncate(len + d)
    self.order_holder.truncate(len + d)
    self.order_end.truncate(len + d)
  }
  // (its run put in its place)
  for k in 0..<made {
    self.order.unsafe_set(p + k, self.order_new.unsafe_get(k))
    self.order_holder.unsafe_set(p + k, self.order_new_holder.unsafe_get(k))
    self.order_end.unsafe_set(p + k, self.order_new_end.unsafe_get(k))
  }
  if d != 0 {
    let mut j = holder
    while j >= 0 {
      self.order_end[j] = self.order_end[j] + d
      j = self.order_holder[j]
    }
  }
}

///|
/// The order from `from` until `until`, one at a time `step` (from its end where it moves on), past the run made again
/// (it ended at `e`), moved `d` on (Tree::order_from): what holds each there too where that is past the run, where what
/// it holds ends with it. (Each read and written unchecked: within the order, as long as it is moved to, its three
/// arrays as long as one another, each node it names one of the tree's.)
fn Tree::order_moved(self : Tree, from : Int, until : Int, step : Int, d : Int, e : Int) -> Unit {
  let order = self.order
  let holders = self.order_holder
  let ends = self.order_end
  let of = self.order_of
  let mut j = from
  while j != until {
    let at = order.unsafe_get(j)
    let hd = holders.unsafe_get(j)
    of.unsafe_set(at, j + d)
    order.unsafe_set(j + d, at)
    holders.unsafe_set(j + d, if hd >= e { hd + d } else { hd })
    ends.unsafe_set(j + d, ends.unsafe_get(j) + d)
    j = j + step
  }
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
fn[T] Tree::queued(self : Tree, read : () -> T, then : (T) -> Unit, at? : Int = -1) -> () -> Unit {
  // (its one state, every way it is run read from it: queued for a frame (told as a change ended), marked as what it
  // read changed (in a change's batch too: what asks at once pulls it), live; run once it is due, by any of them, and
  // done with all of them. One object with its watch: a node's bindings are made and let go with it, each object more
  // an allocation and a free of every node)
  let b : Bound = { at, queued: false, marked: false, live: true, told_at: -1.0, by_clock: false, watch: None, run: bound_runs_not }
  let w = @signals.watch(fn() {
    if b.live && !b.queued {
      b.queued = true
      // (when what it read was told changed: its cause's moment, whatever frame works it out)
      b.told_at = if self.handing {
        // (what the hand worked out again tells, of the moment it was worked out at: Tree::hand_now)
        self.hand_at
      } else {
        match self.time {
          Some(f) => f()
          None => self.logic
        }
      }
      b.by_clock = self.ticking || self.laying || self.handing
      self.bindings_due.push(b)
      self.marked()
      // (where things stand once the change that told it is told whole, a frame drawn after or none: placed then, where
      // something asks, View::laid_before_causes)
      self.settle_after_change(b.told_at)
    }
  })
  w.on_marked(fn() {
    if b.live && !b.marked {
      if !b.queued {
        b.by_clock = self.ticking || self.laying || self.handing
      }
      b.marked = true
      self.pulls_marked.push(b)
    }
  })
  b.watch = Some(w)
  b.run = fn() {
    b.queued = false
    b.marked = false
    // (at rest since it was told: nothing of it worked out again till it wakes, told anew then (View::rests))
    if !b.live || w.resting() {
      return
    }
    let reading_was = self.binding_reading
    self.binding_reading = at
    let v = w.read(read)
    self.binding_reading = reading_was
    let was = self.cause_at
    self.cause_at = b.told_at
    b.told_at = -1.0
    let by_clock_was = self.bound_by_clock
    self.bound_by_clock = b.by_clock
    self.binding_running = self.binding_running + 1
    // (untracked: what it sets read by nothing that reads now)
    let was_sub = @signals.set_active_sub(None)
    then(v)
    @signals.set_active_sub(was_sub) |> ignore
    self.bound_by_clock = by_clock_was
    self.binding_running = self.binding_running - 1
    self.cause_at = was
    self.change_ended()
  }
  (b.run)()
  self.bindings = self.bindings + 1
  fn() {
    if b.live {
      b.live = false
      b.run = bound_runs_not
      b.watch = None
      self.bindings = self.bindings - 1
      w.stop()
    }
  }
}

///|
/// What a binding let go of runs: nothing.
let bound_runs_not : () -> Unit = fn() {  }

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
  self.bindings
}

///|
/// A structure's binding (what shows, which is picked, which rows): `read` worked out as what it read changes, and
/// where it came out otherwise, `then` done then (the structure's change committed with the change that caused it, at
/// that change's moment: what it makes reads the state as it is then, what leaves starts leaving then), what had left
/// by that moment let go first. Layout, words and paint of what it makes wait for the frame. Run now with the target
/// it starts at, unless not `at_start` (as of its changes alone). What stops it.
/// A frame asked for each change, unless not `draws` (what it sets draws nothing: a pointer's shape, View::cursor).
fn[T : Eq] Tree::structured(
  self : Tree,
  read : () -> T,
  then : (T) -> Unit,
  at_start? : Bool = true,
  draws? : Bool = true,
) -> () -> Unit {
  let live = Ref(true)
  let last : Ref[T?] = Ref(None)
  // (marked as a block is given another key: key_taken.mbt)
  let by_key = Ref(false)
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
      let taken = by_key.val || key_taking.val
      by_key.val = false
      if last.val != Some(v) {
        last.val = Some(v)
        if live.val {
          self.structure_done(fn() {
            let was = key_taken.val
            key_taken.val = taken
            then(v)
            key_taken.val = was
          })
        }
        draws
      } else {
        false
      }
    })
  })
  watch.val = Some(w)
  // (marked as it is told, whatever batch that is in: told by a block given another key, its change is that one's)
  w.on_marked(fn() {
    if key_taking.val {
      by_key.val = true
    }
  })
  let v = w.read(read)
  last.val = Some(v)
  let stop = fn() {
    live.val = false
    watch.val = None
    w.stop()
  }
  if !at_start {
    return stop
  }
  // (one change, as each after it is: Tree::at_cause)
  self.committing += 1
  let taking_was = key_taking.val
  @signals.start_batch()
  self.structure_done(fn() { then(v) })
  @signals.end_batch()
  key_taking.val = taking_was
  self.committing -= 1
  self.modals_settled()
  if self.committing == 0 && self.cause_at < 0.0 {
    self.pairs_after(self.logic)
  }
  self.change_ended()
  stop
}

///|
/// `f` done as of the moment of the change being committed (the one being committed, else the host's now): the tree
/// brought there first (what had left by then let go), that moment its cause's for all `f` reads and does; what is
/// marked taken where `f` says it changed something.
fn Tree::at_cause(self : Tree, f : () -> Bool) -> Unit {
  let at = if self.cause_at >= 0.0 {
    self.cause_at
  } else {
    match self.time {
      Some(now) => now()
      None => self.logic
    }
  }
  self.advance_logic(at)
  // What was due has finished. Advancing the drawing clock can notify bindings too: tell it with the structure's
  // change, so a child already queued by the new data cannot run before its parent has had the chance to let it go.
  let taking_was = key_taking.val
  @signals.start_batch()
  self.advance_clock(at)
  let was = self.cause_at
  self.cause_at = at
  self.committing += 1
  // (one change, as an event is: what it writes told once all of it is written, never what follows it running
  // between two of its writes and seeing half of it)
  let changed = f()
  // (committed inside another's commit, its flush under way: what this one told run by that flush in its turn, not in
  // one nested in it, so that the structures one change marks are as deep on the stack at 400 as at 2; that one's end
  // still comes once all of them are told, flush_nested_wbtest)
  let in_turn = self.committing > 1
  if in_turn {
    @signals.end_batch_in_turn()
  } else {
    @signals.end_batch()
  }
  // (a block given another key in it: told whole now, what that told made at once, key_taken.mbt; told in turn, not
  // yet: held till the flush telling it is over, as it was while that flush ran nested in this one. Known: put back
  // after what that flush's afters had asked before it (Tree::settle_after_change's settle_now), which ran with it put
  // back when nested; a structure changed in such a settle is taken as given another key, at once. No test meets it
  // yet; one that does wants a hook between the flush's loop and its afters, #5733)
  if in_turn && key_taking.val && !taking_was {
    @signals.after_flush(fn() { key_taking.val = false })
  } else {
    key_taking.val = taking_was
  }
  self.committing -= 1
  self.modals_settled()
  self.cause_at = was
  // (paired once all of the change it is of is committed: shared.mbt)
  self.change_ended()
  if was < 0.0 {
    self.pairs_after(at)
    self.hand_now()
    self.sights_now()
  }
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
  RunsMarks
  Over
  Shift
  MovedBy
  Presses
  Modal
  Shapes
  Tint
  Radius
  Glass
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
  BoundsInput
  OverScrim
  Measured
  WordsCentered
  EllipsisPast
  Points
  Picture
  Drop
  Fits
  OneOf
  FitWhole
  Turn
  Lines
  Fades
  Stretch
  Opens
  CutsSoftly
  DrawnOff
  GroundDrawn
  MinHeight
  Aspect
  Nowhere
  Edge
  Image
  ImageFor
  ImageCover
  ImageContain
  ImageCoverAt
  ImageFade
  ImageIn
  Corners
  Bones
  BoneWhole
  Comes
  GoneEmpty
  FillsAcross
  WordsBreaks
  GlyphsBy
  InUse
  LaysAnew
}

///|
/// A property by its name, as a node's sources say it (source.mbt): what `derive(Show)` wrote.
impl Show for Prop with output(self, logger) {
  logger.write_string(
    match self {
      Width => "Width"
      Height => "Height"
      Padding => "Padding"
      Margin => "Margin"
      Row => "Row"
      Grow => "Grow"
      Ground => "Ground"
      Alpha => "Alpha"
      Offset => "Offset"
      Words => "Words"
      RunsSet => "RunsSet"
      RunsInk => "RunsInk"
      RunsPressed => "RunsPressed"
      RunsPicked => "RunsPicked"
      RunsMarks => "RunsMarks"
      Over => "Over"
      Shift => "Shift"
      MovedBy => "MovedBy"
      Presses => "Presses"
      Modal => "Modal"
      Shapes => "Shapes"
      Tint => "Tint"
      Radius => "Radius"
      Glass => "Glass"
      Says => "Says"
      Hides => "Hides"
      Focusable => "Focusable"
      TabStop => "TabStop"
      Cursor => "Cursor"
      Basis => "Basis"
      Ink => "Ink"
      Shadow => "Shadow"
      MaxWidth => "MaxWidth"
      MaxHeight => "MaxHeight"
      WordsLook => "WordsLook"
      AllowEllipsis => "AllowEllipsis"
      Shrink => "Shrink"
      Gap => "Gap"
      Wraps => "Wraps"
      WrapsLeast => "WrapsLeast"
      Shorter => "Shorter"
      MinWidth => "MinWidth"
      LinesUp => "LinesUp"
      LiesAlong => "LiesAlong"
      Scale => "Scale"
      DrawnAs => "DrawnAs"
      OverAll => "OverAll"
      Stacked => "Stacked"
      MovesWindow => "MovesWindow"
      KeepsHeld => "KeepsHeld"
      Clips => "Clips"
      BoundsInput => "BoundsInput"
      OverScrim => "OverScrim"
      Measured => "Measured"
      WordsCentered => "WordsCentered"
      EllipsisPast => "EllipsisPast"
      Points => "Points"
      Picture => "Picture"
      Drop => "Drop"
      Fits => "Fits"
      OneOf => "OneOf"
      FitWhole => "FitWhole"
      Turn => "Turn"
      Lines => "Lines"
      Fades => "Fades"
      Stretch => "Stretch"
      Opens => "Opens"
      CutsSoftly => "CutsSoftly"
      DrawnOff => "DrawnOff"
      GroundDrawn => "GroundDrawn"
      MinHeight => "MinHeight"
      Aspect => "Aspect"
      Nowhere => "Nowhere"
      Edge => "Edge"
      Image => "Image"
      ImageFor => "ImageFor"
      ImageCover => "ImageCover"
      ImageContain => "ImageContain"
      ImageCoverAt => "ImageCoverAt"
      ImageFade => "ImageFade"
      ImageIn => "ImageIn"
      Corners => "Corners"
      Bones => "Bones"
      BoneWhole => "BoneWhole"
      Comes => "Comes"
      GoneEmpty => "GoneEmpty"
      FillsAcross => "FillsAcross"
      WordsBreaks => "WordsBreaks"
      GlyphsBy => "GlyphsBy"
      InUse => "InUse"
      LaysAnew => "LaysAnew"
    },
  )
}

///|
/// Whether what it sets (at `phase`) may change what a point lands on (Tree::target_in's walk of what takes input:
/// where each is laid out, placed, scaled and drawn off, what bounds input, what takes presses or keeps them from what
/// is under it): so a way it reads as it goes says its end a moment that is found again at (View::hand_at_end).
/// Every property laid out (`Layout`, `Both`: its size, its place in what holds it, whether it is laid out at all);
/// of the rest, Offset, Shift, MovedBy, Scale (where it is drawn and how big: n.lx, n.ly, n.ls), DrawnOff, BoundsInput,
/// Presses, Modal, OverAll, Stacked, MovesWindow. None of the others: how it looks alone, which the walk does not read
/// (Alpha, Fades, Turn, Stretch, CutsSoftly, GroundDrawn of `Place`: a turned or stretched node is found where it is
/// unturned and unstretched; every `Paint` one but BoundsInput, Clips among them: what bounds input is BoundsInput;
/// what is said, `Said`). So not by phase alone: `Place` holds both kinds, `Paint` one that moves hits.
fn Prop::moves_hits(self : Prop, phase : Phase) -> Bool {
  match phase {
    Layout | Both => true
    _ =>
      match self {
        Offset | Shift | MovedBy | Scale | DrawnOff | BoundsInput | Presses | Modal | OverAll | Stacked | MovesWindow =>
          true
        _ => false
      }
  }
}

///|
/// Its place among the properties: what the node's table of them keeps it by, an Int (its derived hash a Hasher made for
/// each look in it, and every binding said, Is or By, looks there).
fn Prop::ord(self : Prop) -> Int {
  match self {
    Width => 0
    Height => 1
    Padding => 2
    Margin => 3
    Row => 4
    Grow => 5
    Ground => 6
    Alpha => 7
    Offset => 8
    Words => 9
    RunsSet => 10
    RunsInk => 11
    RunsPressed => 12
    RunsPicked => 13
    Over => 14
    Shift => 15
    MovedBy => 16
    Presses => 17
    Modal => 18
    Shapes => 19
    Tint => 20
    Radius => 21
    Glass => 22
    Says => 23
    Hides => 24
    Focusable => 25
    TabStop => 26
    Cursor => 27
    Basis => 28
    Ink => 29
    Shadow => 30
    MaxWidth => 31
    MaxHeight => 32
    WordsLook => 33
    AllowEllipsis => 34
    Shrink => 35
    Gap => 36
    Wraps => 37
    WrapsLeast => 38
    Shorter => 39
    MinWidth => 40
    LinesUp => 41
    LiesAlong => 42
    Scale => 43
    DrawnAs => 44
    OverAll => 45
    Stacked => 46
    MovesWindow => 47
    KeepsHeld => 48
    Clips => 49
    BoundsInput => 50
    OverScrim => 51
    Measured => 52
    WordsCentered => 53
    GlyphsBy => 86
    InUse => 88
    LaysAnew => 89
    EllipsisPast => 54
    WordsBreaks => 87
    Points => 55
    Picture => 56
    Drop => 57
    Fits => 58
    FitWhole => 59
    Turn => 60
    Lines => 61
    Fades => 62
    Stretch => 63
    Opens => 64
    CutsSoftly => 65
    DrawnOff => 66
    GroundDrawn => 67
    MinHeight => 68
    Aspect => 69
    Nowhere => 70
    Edge => 71
    Image => 72
    ImageFor => 73
    ImageCover => 74
    ImageContain => 75
    ImageFade => 76
    ImageIn => 77
    ImageCoverAt => 85
    Corners => 78
    Bones => 79
    BoneWhole => 80
    Comes => 81
    GoneEmpty => 82
    FillsAcross => 83
    OneOf => 84
    RunsMarks => 89
  }
}

///|
/// Properties set together on one node (View::sets_together): each set as what sets them says it now (Is), all of them
/// set again in one binding as what that read changes; one bound again by another (By or Is) is theirs no more, and the
/// binding goes with the last of them. Which are theirs: a bit each, by its Prop::ord (two words: up to 128); which
/// were theirs and are no more (`gone_*`: never taken again).
priv struct SetsTogether {
  at : Int
  gen : Int
  /// whether it is setting them the first time (each it sets taken as its), else again (those still its, and one it
  /// sets for the first time that nothing else binds and that was never its)
  mut first : Bool
  mut owned_lo : Int64
  mut owned_hi : Int64
  mut gone_lo : Int64
  mut gone_hi : Int64
  mut left : Int
  mut stop : () -> Unit
}

///|
fn SetsTogether::owns(self : SetsTogether, k : Int) -> Bool {
  if k < 64 {
    (self.owned_lo & (1L << k)) != 0L
  } else {
    (self.owned_hi & (1L << (k - 64))) != 0L
  }
}

///|
/// Whether property `k` was its and is no more (bound by another).
fn SetsTogether::gone(self : SetsTogether, k : Int) -> Bool {
  if k < 64 {
    (self.gone_lo & (1L << k)) != 0L
  } else {
    (self.gone_hi & (1L << (k - 64))) != 0L
  }
}

///|
/// Property `k` its (set by it for the first time), or no more its (bound by another, or the node let go: never its
/// again): the binding stopped with the last of them.
fn SetsTogether::own(self : SetsTogether, k : Int, on : Bool) -> Unit {
  if on == self.owns(k) {
    return
  }
  if k < 64 {
    self.owned_lo = self.owned_lo ^ (1L << k)
    if !on {
      self.gone_lo = self.gone_lo | (1L << k)
    }
  } else {
    self.owned_hi = self.owned_hi ^ (1L << (k - 64))
    if !on {
      self.gone_hi = self.gone_hi | (1L << (k - 64))
    }
  }
  self.left = self.left + (if on { 1 } else { -1 })
  if !on && self.left == 0 {
    (self.stop)()
  }
}

///|
// kept across runs: set only while View::sets_together sets what it sets, put back as it ends
let setting_together : Ref[SetsTogether?] = Ref(None)

///|
/// What `set` sets on this node (its properties, each said Is: View::width and the like) out of what `read` says, set
/// together: now, and again, all of them, in the frame after what `read` read changed, where it came out otherwise
/// (Tree::queued): one binding for all, where each bound By is a binding of its own (a style: what it says changes with
/// the theme alone). One it sets for the first time only later is its from then as one set the first time is, where
/// nothing else binds it (By) and it was never its before; one set once by another with Is leaves nothing on the node,
/// so it is taken so too (the later said wins). One bound again afterwards, by another, is that one's and set by this
/// no more (By or Is: never taken again); one it sets no more stays as it last set it (what it is then is the caller's
/// to set). Once none is its (none set the first time, or all bound by others) the binding is let go. What `set` sets
/// on another node is set alone, once.
pub fn[T : Eq] View::sets_together(self : View, read : () -> T, set : (T) -> Unit) -> View {
  guard self.live() is Some(_) else { return self }
  let g : SetsTogether = {
    at: self.at,
    gen: self.gen,
    first: true,
    owned_lo: 0L,
    owned_hi: 0L,
    gone_lo: 0L,
    gone_hi: 0L,
    left: 0,
    stop: fn() {  },
  }
  let last : Ref[T?] = Ref(None)
  let stop = self.tree.queued(at=self.at, read, fn(v) {
    if last.val == Some(v) {
      return
    }
    last.val = Some(v)
    let n = self.tree.nodes[g.at]
    if !n.live || n.gen != g.gen {
      return
    }
    let was = setting_together.val
    setting_together.val = Some(g)
    set(v)
    setting_together.val = was
    g.first = false
  })
  if g.left == 0 {
    stop()
  } else {
    g.stop = stop
  }
  self
}

///|
/// Property `prop` of the node (its one binding: one bound before is let go), set by `apply`: once, or as what it
/// reads changes (Tree::queued: as the frame takes it), set again only if it came out otherwise than it last did,
/// marking what its phase does again. Said at `loc` (kept where the tree keeps that: source.mbt).
fn[T : Eq] View::bind(
  self : View,
  prop : Prop,
  live : Live[T],
  phase : Phase,
  apply : (T) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  guard self.live() is Some(n) else { return }
  match n.source {
    Some(s) => s.said[prop.ord()] = (prop, loc)
    None => ()
  }
  let tree = self.tree
  tree.said_count += 1
  let at = self.at
  // (set among others set together on this node, View::sets_together: again, only while it is theirs)
  let together = match (live, setting_together.val) {
    (Is(_), Some(g)) if g.at == at && g.gen == self.gen => Some(g)
    _ => None
  }
  match (together, live) {
    (Some(g), Is(v)) if !g.first => {
      if g.owns(prop.ord()) {
        apply(v)
        tree.bound_marked(at, phase)
        return
      }
      // (one it sets for the first time now: taken as one set the first time is, below, where nothing binds it and it
      // was never its; else left)
      if g.gone(prop.ord()) || n.props.get(prop.ord()) is Some(_) {
        return
      }
    }
    _ => ()
  }
  match n.props.get(prop.ord()) {
    Some(stop) => {
      n.props.remove(prop.ord())
      stop()
    }
    None => ()
  }
  match live {
    Is(v) => {
      apply(v)
      tree.bound_marked(at, phase)
      match together {
        Some(g) => {
          let k = prop.ord()
          g.own(k, true)
          n.props[k] = fn() { g.own(k, false) }
        }
        None => ()
      }
    }
    By(f) => {
      let last : Ref[T?] = Ref(None)
      let gen = self.gen
      // (read so that a way it reads as it goes says its end a moment what is under a still pointer is found again at
      // only where what it sets may move that: Prop::moves_hits)
      // (each binding says it for itself: one run inside another's run is its own)
      let looks = !prop.moves_hits(phase)
      let f = fn() {
        let was = tree.looks_reading
        tree.looks_reading = looks
        let v = f()
        tree.looks_reading = was
        v
      }
    let stop = tree.queued(
      at~,
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
        tree.bound_marked(at, phase)
      })
      n.props[prop.ord()] = stop
    }
  }
}

///|
/// What a property of node `at` set again marks, by its phase (View::bind).
fn Tree::bound_marked(self : Tree, at : Int, phase : Phase) -> Unit {
  match phase {
    Layout => self.layout_marked_at(at)
    Paint => self.look_marked_at(at)
    Place => self.place_marked_at(at)
    Both => {
      self.layout_marked_at(at)
      self.look_marked_at(at)
    }
    Said => {
      // (what it is, whether it is hidden: it read out again, and what holds it, as it may come or go from what is read
      // out there)
      self.said_marked(at, state=true, kids=true)
      self.marked()
    }
  }
}

///|
/// Its width (points; None: as its content and its holder make it).
#callsite(autofill(loc))
pub fn View::width(self : View, w : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Width, w, Layout, fn(w) {
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
#callsite(autofill(loc))
pub fn View::height(self : View, h : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Height, h, Layout, fn(h) {
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
#callsite(autofill(loc))
pub fn View::padding(self : View, p : Live[(Double, Double, Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Padding, p, Layout, fn(p) {
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
#callsite(autofill(loc))
pub fn View::margin(self : View, m : Live[(Double, Double, Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Margin, m, Layout, fn(m) {
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
#callsite(autofill(loc))
pub fn View::pad(self : View, p : Live[Double], loc~ : SourceLoc) -> View {
  self.padding(loc~,
    match p {
      Is(v) => Is((v, v, v, v))
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
#callsite(autofill(loc))
pub fn View::sides(self : View, lr : Live[(Double, Double)], loc~ : SourceLoc) -> View {
  self.padding(loc~,
    match lr {
      Is(v) => Is((v.0, 0.0, v.1, 0.0))
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
#callsite(autofill(loc))
pub fn View::row(self : View, across : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Row, across, Layout, fn(a) {
    self.tree.nodes[self.at].flex.style.direction = if a { Row } else { Column }
    // (what it holds cut short gives way along it only where it is a row: View::cuts)
    self.tree.cuts_under(self.at)
  })
  self
}

///|
/// How much of the room left it takes.
#callsite(autofill(loc))
pub fn View::grow(self : View, g : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Grow, g, Layout, fn(g) { self.tree.nodes[self.at].flex.style.grow = g })
  self
}

///|
/// Whether it is never narrower, in a row, than what it holds needs (the old views' `keep`: a bar's tools kept whole),
/// whatever its basis and least width say, as it changes: what is beside it gives way first; what it holds changing
/// (its words, their face, its parts, their gaps) lays it out so again. Layout's.
#callsite(autofill(loc))
pub fn View::keeps_held(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, KeepsHeld, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.min_held = on })
  self
}

///|
/// How wide (in a row; tall, in a column) it is before the room left is shared out (View::grow), as it changes: None as
/// what it holds is; Some(0.0) none, so that those that grow alike are alike however much each holds (the old views'
/// Fill). It says nothing of how narrow it may come to: that is its least width's (View::min_width) or, never narrower
/// than what it holds, View::keeps_held's. Layout's.
#callsite(autofill(loc))
pub fn View::basis(self : View, b : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Basis, b, Layout, fn(b) {
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
/// When the move it is drawn by (View::moved_by) is over, its `ends` at the size it is laid out as of the logic's
/// moment (as laid_size): the move's own end, said by its data at that size, not by the frame last drawn; -1 where none
/// is said. Read only by what a test asks of when a part stops (@sf.presented_rest), never by what runs. It lays the
/// tree out as of that moment first, so it is asked between frames and handlers, never as the tree lets go of what it
/// made (an `owns`' undoing, a layer let go): there `laid=false` reads it as it was last laid out, nothing laid out anew.
pub fn View::moved_end(self : View, laid? : Bool = true) -> Double {
  guard self.live() is Some(n) else { return -1.0 }
  guard n.moved_ends is Some(ends) else { return -1.0 }
  if laid {
    self.tree.measured_now()
  }
  ends(n.flex.width, n.flex.height)
}

///|
/// The latest of the ends the ways in and out of this node and of all it holds said as each was said (View::comes:
/// `come_ends`, in each way's own data, nothing measured or seen drawn), laid out as of the logic's moment as laid_size
/// is; -1 where none of it ever made its way. Read only by what a test asks of when a part stops (@sf.presented_rest, a
/// sheet's rest: a way in of what it holds grows it as surely as its own motion does), never by what runs. It lays the
/// tree out as of that moment first, so it is asked between frames and handlers, never as the tree lets go of what it
/// made (an `owns`' undoing, a layer let go): there `laid=false` reads the ways as they were last laid out.
pub fn View::comes_end(self : View, laid? : Bool = true) -> Double {
  guard self.live() is Some(_) else { return -1.0 }
  if laid {
    self.tree.measured_now()
  }
  self.tree.comes_end_in(self.at)
}

///|
fn Tree::comes_end_in(self : Tree, at : Int) -> Double {
  let n = self.nodes[at]
  let e = n.flex.style.come_ends
  let mut end = if e == e { e } else { -1.0 }
  for k in n.kids {
    let r = self.comes_end_in(k)
    if r > end {
      end = r
    }
  }
  end
}

///|
/// The window's size, as its frames give it (0 by 0 before the first), followed: what is made by it (which frame its
/// width calls for) made again as it changes.
pub fn View::window(self : View) -> (Double, Double) {
  self.tree.room.get()
}

///|
/// How far in from the window's top, right, foot and left the system's bars reach (its safe area: Tree::clear_of), followed:
/// what is laid out over the window (a dialog in its middle, a panel's most height) keeps clear of it.
pub fn View::clear(self : View) -> (Double, Double, Double, Double) {
  self.tree.clear.get()
}

///|
/// The system's bars reach `top`, `right`, `foot` and `left` in from the window's edges now (the host's safe area, as
/// its frames give the window's size): what goes beside another placed again by it, what reads it (View::clear) made
/// again.
pub fn Tree::clear_of(self : Tree, top : Double, right : Double, foot : Double, left : Double) -> Unit {
  let now = (top, right, foot, left)
  if self.clear.untracked() == now {
    return
  }
  self.clear.set(now)
  if self.nodes.length() > 0 && self.nodes[0].live {
    self.layout_marked_at(0)
  }
}

///|
/// Laid out over what holds it (true), filling all of its room whatever else it holds, or in its turn among them: what
/// lies one over another (a stack's pages, what floats over them) said so, drawn in the order they are held.
#callsite(autofill(loc))
pub fn View::over(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Over, on, Layout, fn(on) {
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
#callsite(autofill(loc))
pub fn View::clips(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Clips, on, Paint, fn(on) {
    let n = self.tree.nodes[self.at]
    n.clips_said = on
    n.look.clips = on || n.coming
  })
  self
}

///|
/// What it holds laid out as tall as it comes to along its main axis, whatever room it has itself (its most, what holds
/// it), as a column that scrolls has it (CSS's overflow scroll), it scrolling nothing. Layout's. (Bound, it is laid out
/// in that room, its words cut to it: one cut by its own most from what it holds then laid out that short is laid out
/// whole again and cut again, each pass, for ever.)
pub fn View::holds_whole(self : View) -> View {
  self.tree.nodes[self.at].flex.style.overflow = @flex.Overflow::Scroll
  self.tree.layout_marked_at(self.at)
  self
}

///|
/// Whether what it holds is found by a finger or the pointer within it alone, as it changes (a column that scrolls in
/// it: what is scrolled out of it takes nothing there, as an old view's clip; an old view hosted in what it holds found
/// so too, what it takes asked only there: Tree::input_bounds). Where they are found only: how it is drawn is View::clips'.
#callsite(autofill(loc))
pub fn View::bounds_input(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, BoundsInput, on, Paint, fn(on) {
    let n = self.tree.nodes[self.at]
    if n.bounds_input != on {
      n.bounds_input = on
      self.tree.hits_bump()
    }
  })
  self
}

///|
/// Drawn, with what it holds, over the scrim of the modal layer the old frame has up while `on` says so (a row held for
/// its menu, lifted toward the finger: an old view's Stratum OverScrim), under what that layer holds; where no scrim is
/// up, in its place. Cut as where it is; found by a press as ever (the scrim's layer takes what lands on it). Paint's.
#callsite(autofill(loc))
pub fn View::over_scrim(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, OverScrim, on, Paint, fn(on) { self.tree.nodes[self.at].over_scrim = on })
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
  self.tree.inputs_own_said(self.at)
  n.claims_from = from
  n.claims_scroll = scrolls
  n.claims_said = n.claims_said + 1
  self.tree.hits_bump()
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
      let found : Ref[(NodeId, Int, (Double, Double, Double, Double))?] = Ref(None)
      let at = self.logic_said()
      // (what is drawn small near it reached from round it, as a press there reaches it: Tree::target_at's)
      let least = self.least_now()
      let near : Array[Near] = []
      let order = Ref(0)
      // (the last drawn there that hides what is under it: Node::covers, as Tree::target_at)
      let covered = Ref(-1)
      self.each_drawn_scaled(fn(c, cx, cy, a, s) {
        let o = order.val
        order.val = o + 1
        let n = self.nodes[c.id.at]
        if self.finger_on(c, cx, cy, s, x, y, at, tracked=false) {
          if n.on_drag is Some(_) ||
            n.on_press is Some(_) ||
            n.top_row ||
            n.claims is Some(_) ||
            (n.hosted && @signals.untracked(fn() { there(c.id) })) {
            found.val = Some((c.id, o, (cx, cy, cx + c.w * s, cy + c.h * s)))
          } else if n.covers(a) {
            covered.val = o
          }
        } else {
          self.near_said(n, c, cx, cy, s, x, y, least, o, near)
        }
      }, inputs_only=true)
      match found.val {
        Some((id, o, box)) => {
          let n = self.nodes[id.at]
          let top = if n.hosted { Hosted(id) } else if n.on_drag is Some(_) { Dragged(id) } else { Pressed(id) }
          match self.reached(top, o, box, near, x, y, least, covered=covered.val) {
            Pressed(r) | Dragged(r) => Some(r)
            _ => Some(id)
          }
        }
        None =>
          match self.reached(Nothing, -1, (0.0, 0.0, 0.0, 0.0), near, x, y, least) {
            Pressed(r) | Dragged(r) => Some(r)
            _ => None
          }
      }
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
  let m = self.nodes[id.at]
  // (tucked out of sight over the top of what scrolls it, it or what holds it: found below what covers that alone,
  // Scroll::tucks)
  if m.tucked_under is Some(t) {
    b = self.tucked_bound(t, b)
  }
  // (on a flight's way, it or what holds it: bound by nothing that holds that, shared.mbt)
  let mut i = if m.lift is Some(_) { -1 } else { m.parent }
  while i >= 0 {
    let n = self.nodes[i]
    if n.tucked_under is Some(t) {
      b = self.tucked_bound(t, b)
    }
    if n.bounds_input {
      let (x, y, sc) = self.placed(i)
      let (x1, y1) = (x + n.flex.width * sc, y + n.flex.height * sc)
      b = (dmax(b.0, x), dmax(b.1, y), dmin(b.2, x1), dmin(b.3, y1))
    }
    if n.lift is Some(_) {
      break
    }
    i = n.parent
  }
  b
}

///|
/// `b` (x0, y0, x1, y1 in the window) cut, for a node tucked over the top of what scrolls it (Scroll::tucks: that node,
/// how far down its top what covers it reaches), to below what covers that top (a phone's top bar over Home's list):
/// what lies under it is out of sight, found by no finger nor pointer, as what is scrolled out of a list is not
/// (View::bounds_input). As placed now, nothing followed.
fn Tree::tucked_bound(
  self : Tree,
  tucked : (Int, () -> Double),
  b : (Double, Double, Double, Double),
) -> (Double, Double, Double, Double) {
  let (host, cover) = tucked
  let (_, hy, _) = self.placed(host)
  (b.0, dmax(b.1, hy + @signals.untracked(cover)), b.2, b.3)
}

///|
/// Whether its words' lines each stand in the middle of its width (as wide as it is as it is drawn: a line wrapped,
/// each part of it), as an old view's centred words do (Ctx::text's `center`): how they are drawn only, measured and
/// wrapped as ever, a change of it drawn again, nothing laid out again.
#callsite(autofill(loc))
pub fn View::words_centered(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, WordsCentered, on, Paint, fn(on) {
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
#callsite(autofill(loc))
pub fn View::ellipsis_past(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, EllipsisPast, on, Paint, fn(on) { self.tree.nodes[self.at].look.ellipsis_past = on })
  self
}

///|
/// The picture it draws over its ground (None: none), after its shapes, as wide as it is laid out (its height for that
/// width given it as its own: View::height): its curves cut fine enough for the pixels the window is
/// drawn at (its screen's, at the zoom it is drawn at), cut again as those or its width change, kept while they do not.
/// In its tint where it has one (View::tint), each of its paths keeping its own opacity; a tint changed draws it again
/// in it, its curves not cut again. Paint's.
#callsite(autofill(loc))
pub fn View::picture(self : View, picture : Live[@pixels.Vector?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Picture, picture, Paint, fn(p) { self.tree.nodes[self.at].look.picture = p })
  self
}

///|
/// Its ground (0: none): paint's.
#callsite(autofill(loc))
pub fn View::ground(self : View, ink : Live[Int64], loc~ : SourceLoc) -> View {
  // (where the tree keeps sources alone (a Tester's): what it reads of what shows it, each time it is worked out,
  // Node's ground_read; elsewhere bound as it is said)
  let ink = if self.tree.sources {
    match ink {
      By(f) => {
        let (at, gen) = (self.at, self.gen)
        By(fn() {
          let was = ground_reading.val
          ground_reading.val = 0
          let k = f()
          let n = self.tree.nodes[at]
          if n.live && n.gen == gen {
            n.ground_read = ground_reading.val
          }
          ground_reading.val = was
          k
        })
      }
      Is(_) => {
        match self.live() {
          Some(n) => n.ground_read = 0
          None => ()
        }
        ink
      }
    }
  } else {
    ink
  }
  self.bind(loc~, Ground, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ground = k })
  self
}

///|
/// What a ground being worked out read of what shows it (View::ground, where the tree keeps sources): set by what it
/// reads (Tree::ground_reads), asked and put back by View::ground.
// kept across runs: set only while a ground is worked out where the tree keeps sources, put back as it ends
let ground_reading : Ref[Int] = Ref(0)

///|
/// What node `id`'s ground read: the hand on a node (View::pointed, View::pressed, View::pointed_in).
pub let ground_read_hand : Int = 1

///|
/// What node `id`'s ground read: the keyboard's focus (View::focused, View::focus_shown).
pub let ground_read_focus : Int = 2

///|
/// (What reads `what` of what shows a ground, told where the tree keeps sources and a ground is being worked out.)
fn Tree::ground_reads(self : Tree, what : Int) -> Unit {
  if self.sources {
    ground_reading.val = ground_reading.val | what
  }
}

///|
/// What node `id`'s ground, as last worked out, read of what shows it (ground_read_hand, ground_read_focus), where the
/// tree keeps sources (a Tester's); 0 elsewhere.
pub fn Tree::ground_read(self : Tree, id : NodeId) -> Int {
  if self.alive_id(id) {
    self.nodes[id.at].ground_read
  } else {
    0
  }
}

///|
/// The shapes it draws over its ground, in its own terms from its top left (@paint.Shape: outlines filled and stroked):
/// paint's. What they come to as they are drawn is worked out once for the shapes said (their outlines), whatever colour
/// they are drawn in (View::tint).
#callsite(autofill(loc))
pub fn View::shapes(self : View, shapes : Live[Array[@paint.Shape]], loc~ : SourceLoc) -> View {
  self.bind(loc~, Shapes, shapes, Paint, fn(s) { self.tree.nodes[self.at].look.shapes = s })
  self
}

///|
/// The one colour its shapes are drawn in (0: each its own): paint's; a change of it draws them again in it, nothing of
/// their outlines worked out again.
#callsite(autofill(loc))
pub fn View::tint(self : View, ink : Live[Int64], loc~ : SourceLoc) -> View {
  self.bind(loc~, Tint, ink, Paint, fn(k) { self.tree.nodes[self.at].look.tint = k })
  self
}


///|
/// How round its corners are (its ground's and its glass's; a linked corner's as worked out where it is said): paint's.
#callsite(autofill(loc))
pub fn View::radius(self : View, r : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Radius, r, Paint, fn(r) { self.tree.nodes[self.at].look.radius = r })
  self
}

///|
/// Its corners each (top left, then round it; None: all as its radius, View::radius), as an old view's box's radius
/// may be four (@ui.Radius::Corners): its ground's, its glass's, its edge's and its cut's (View::clips): paint's.
#callsite(autofill(loc))
pub fn View::corners(self : View, corners : Live[(Double, Double, Double, Double)?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Corners, corners, Paint, fn(k) { self.tree.nodes[self.at].look.corners = k })
  self
}

///|
/// How round its corners are said to be now, each (top left, then round it; its radius at each where it says none
/// each: View::radius, View::corners), as what it is laid out to be is drawn: for what draws its ground on its way to
/// it, read as that is drawn.
pub fn View::corners_said(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  match n.look.corners {
    Some(k) => k
    None => (n.look.radius, n.look.radius, n.look.radius, n.look.radius)
  }
}

///|
/// How round its corners were drawn as it was last drawn, each (top left, then round it), as corners_said has them;
/// as they are said now where it was never drawn: what its ground goes from as a change told now sets it off, said
/// once at that moment.
pub fn View::corners_drawn(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  match n.content {
    Some({ corners: Some(k), .. }) => k
    Some({ radius, .. }) => (radius, radius, radius, radius)
    None => self.corners_said()
  }
}

///|
/// The edge drawn round its ground, inside it (how wide, its colour; 0 wide: none), as an old view's box's border is
/// drawn with its ground (one rect, filled and edged), its corners its ground's: paint's.
#callsite(autofill(loc))
pub fn View::edge(self : View, e : Live[(Double, Int64)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Edge, e, Paint, fn(e) { self.tree.nodes[self.at].look.edge = e })
  self
}

///|
/// The picture it shows over its ground (its source as what hosts the tree keeps pictures by, what stands in for it
/// till it is decoded at the size it is drawn ("" none), the most pixels it is asked at; None: none), all of it filled,
/// its corners its ground's: drawn by what hosts the tree as the frame composes it where it is drawn and as big, each
/// frame, its decode the one for that size, asked for and followed as an old view's is (ui's draw_image: a decode said
/// done draws the frame again), which of the two decided then: paint's.
#callsite(autofill(loc))
pub fn View::image(self : View, image : Live[(String, String, Int)?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Image, image, Paint, fn(i) { self.tree.nodes[self.at].look.image = i })
  self
}

///|
/// Its picture (View::image) covering it as it changes, its middle shown and what is past it cut where it is not as wide
/// for as tall (an old view's FitCover: a face, a mark put up); else, as said none, filling it; paint's.
#callsite(autofill(loc))
pub fn View::image_covers(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageCover, on, Paint, fn(on) { self.tree.nodes[self.at].look.image_cover = on })
  self
}

///|
/// Its picture (View::image) covering it as it changes, cut where it is not as wide for as tall, as much of it as shows
/// taken from `at` along its height (0: its top, as a long screenshot is shown from its start; 1: its foot; 0.5: its
/// middle, as covering it is) and across it from its middle (an old view's FitCoverAt): what the box shows of it, its
/// box the picture drawn; None, as View::image_covers says. Said, it covers it whatever else is said. Paint's.
#callsite(autofill(loc))
pub fn View::image_covers_at(self : View, at : Live[Double?], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageCoverAt, at, Paint, fn(at) { self.tree.nodes[self.at].look.image_cover_at = at })
  self
}

///|
/// Its picture (View::image) contained in it as it changes: all of it shown, as wide for as tall as it is, in its
/// middle, what it does not fill left bare (an old view's FitContain: a site's icon in its square); else, as said none,
/// filling it; covering it said too, covering it. Paint's.
#callsite(autofill(loc))
pub fn View::image_contains(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageContain, on, Paint, fn(on) { self.tree.nodes[self.at].look.image_contain = on })
  self
}

///|
/// Its picture (View::image) fading in over image_fade_ms as it is decoded (an old view's picture's way by default:
/// Ctx::image's `fade`), as it changes; else, as said none, there at once once it is; paint's.
#callsite(autofill(loc))
pub fn View::image_fades(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageFade, on, Paint, fn(on) { self.tree.nodes[self.at].look.image_fade = on })
  self
}

///|
/// The room its picture is judged ready for (View::image): its whole picture shown, not what stands in for it, once it is
/// decoded for that room ((0, 0): for where it is drawn), as a picture on its way somewhere (a flight) is judged by
/// where it goes, its decode for that room asked for as it sets out; paint's.
#callsite(autofill(loc))
pub fn View::image_for(self : View, room : Live[(Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageFor, room, Paint, fn(r) { self.tree.nodes[self.at].look.image_for = r })
  self
}

///|
/// Where in it its picture lies (View::image: x, y, w, h, in its own terms) and the colour filling the rest of it, as
/// changes: its picture and that matte drawn as one instance (its edge cut once, its corners its own), the matte alone
/// over its box till the picture is decoded, as an old view's picture at a rect of its own in a matte (Ctx::picture's
/// `matte`); None, the picture filling it. Paint's.
#callsite(autofill(loc))
pub fn View::image_in(self : View, at : Live[((Double, Double, Double, Double), Int64)?], loc~ : SourceLoc) -> View {
  self.bind(loc~, ImageIn, at, Paint, fn(i) { self.tree.nodes[self.at].look.image_in = i })
  self
}

///|
/// The glass it is drawn as, under its ground and what it draws (@paint.Glass: frosted or liquid; None: none): paint's.
/// What it frosts is what the frame drew under it, wherever it is composed (its capture told as the frame is).
#callsite(autofill(loc))
pub fn View::glass(self : View, g : Live[@paint.Glass?], loc~ : SourceLoc) -> View {
  self.bind(loc~, Glass, g, Paint, fn(g) { self.tree.nodes[self.at].look.glass = g })
  self
}

///|
/// How opaque it is drawn, what it holds with it: its place's.
#callsite(autofill(loc))
pub fn View::alpha(self : View, a : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Alpha, a, Place, fn(a) { self.tree.nodes[self.at].look.alpha = a })
  self
}

///|
/// How far it is drawn off where it is laid out, what it holds with it: its place's (a move on the compositor: never
/// laid out again).
#callsite(autofill(loc))
pub fn View::offset(self : View, d : Live[(Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Offset, d, Place, fn(d) {
    let n = self.tree.nodes[self.at]
    n.look.dx = d.0
    n.look.dy = d.1
  })
  self
}

///|
/// Moved off where it is laid out by what `f` gives from how big it is laid out and the moment it is drawn at (w, h, t),
/// what it holds with it: its place's, as big as it is laid out in the frame drawing it (a sheet rising by its own
/// height over a time its own height says). Asked as it is placed, nothing laid out again for it, and a frame laying
/// it out another size places it by that size. `ends`: the moment its move is over at that size (said, as a motion's
/// end is: Anim::over), worked out as `f` is; the clock followed till then, each frame drawn placing it again, and from
/// then on not (nothing to draw anew for it: what hosts the tree asks for no frames for it), `f` asked at the moment
/// drawn as what else it reads changes (a move said again: followed again till its own end). `holds_leaving`: what is
/// leaving that holds it (View::show's, View::leave) is let go no sooner than its move is over, `ends` asked at the
/// size it is laid out as that leaving's end is worked out (a sheet sinking away by its own height: its layer gone as
/// it is out of sight, however tall it is). `f` reads no clock
/// itself; it gives the same for the same state, time and size, however often asked. Ctx::moved_by's, a node's: what
/// that becomes once old views go.
#callsite(autofill(loc))
pub fn View::moved_by(
  self : View,
  f : (Double, Double, Double) -> (Double, Double),
  ends : (Double, Double) -> Double,
  holds_leaving? : Bool = false,
  loc~ : SourceLoc,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.moved_by = Some(f)
  // (what is leaving that holds it kept till its move is over, its end said: Tree::leave_ends)
  n.moved_holds = if holds_leaving { Some(ends) } else { None }
  n.moved_ends = Some(ends)
  if holds_leaving && !self.tree.leave_holders.contains(self.id()) {
    self.tree.leave_holders.push(self.id())
  }
  let tree = self.tree
  let at = self.at
  self.bind(loc~,
    MovedBy,
    // (followed at the size it is laid out, told as all of it is laid out and worked out again in that same pass
    // (Tree::sizes_told): what `f` and `ends` read at that size followed from the frame it comes to it; none laid out
    // yet, as nothing big. The clock followed only till its end, as that is drawn: View::drawn_past, told once then)
    By(fn() {
      let (w, h) = self.laid_size_told().unwrap_or((0.0, 0.0))
      // (a move's end: what is under a still pointer worked out again then, not as it goes)
      tree.hand_at_end(ends(w, h))
      let t = if self.drawn_past(ends(w, h)) {
        tree.clock.untracked()
      } else {
        tree.clock.get()
      }
      f(w, h, t)
    }),
    Place,
    fn(d) { tree.nodes[at].moved = d },
  )
  self
}

///|
/// How far node `n` of `tree` is moved by what moves it by how big it is laid out (View::moved_by), as laid out now, at
/// the moment drawn.
fn Tree::moved_of(self : Tree, n : Node) -> (Double, Double) {
  match n.moved_by {
    Some(f) => @signals.untracked(fn() { f(n.flex.width, n.flex.height, self.clock.get()) })
    None => (0.0, 0.0)
  }
}

///|
/// How far node `n` is drawn off where it is laid out across (off_y: down; each its own, no pair made for each node
/// placed): its offset, its shift by how big it is laid out, and how far what moves it by that moved it as it was
/// placed (View::moved_by).
fn off_x(n : Node) -> Double {
  n.look.dx + n.look.sx * n.flex.width + n.moved.0
}

///|
/// How far node `n` is drawn off where it is laid out down (off_x's other).
fn off_y(n : Node) -> Double {
  n.look.dy + n.look.sy * n.flex.height + n.moved.1
}

///|
/// How far node `n` is drawn off where it is laid out as it is laid out now (Tree::measured_now), what moves it by how
/// big it is asked at that size: where it goes, not where it was placed.
fn Tree::off_now(self : Tree, n : Node) -> (Double, Double) {
  let (mx, my) = self.moved_of(n)
  // (and as far as a column scrolls it now: Node's scroll_off)
  let (sx, sy) = self.scroll_off_now(n)
  (n.look.dx + n.look.sx * n.flex.width + mx + sx, n.look.dy + n.look.sy * n.flex.height + my + sy)
}

///|
/// How far it is drawn off where it is laid out in its own widths and heights, what it holds with it: its place's, as
/// big as it is laid out in the frame drawing it (a page slid off by its width moves with its room as that changes).
#callsite(autofill(loc))
pub fn View::shift(self : View, d : Live[(Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Shift, d, Place, fn(d) {
    let n = self.tree.nodes[self.at]
    n.look.sx = d.0
    n.look.sy = d.1
  })
  self
}

///|
/// The lines it draws over its shapes (@paint.Line: round-capped strokes through points from its top left, each in its
/// own colour, as far along as it says), as an old view's box draws them (Ctx::lines): paint's.
#callsite(autofill(loc))
pub fn View::lines(self : View, lines : Live[Array[@paint.Line]], loc~ : SourceLoc) -> View {
  self.bind(loc~, Lines, lines, Paint, fn(l) { self.tree.nodes[self.at].look.lines = l })
  self
}

///|
/// How far what it draws itself is turned (radians), as it changes: about its middle, or where `drawn` about the middle
/// of what it draws (the box round its pieces as they are made, worked out as they are, not as it turns: a ring of
/// line pieces turned as an old view's cycle turns it, Ctx::cycle_look). Where it is drawn, not what it is (nothing of
/// it made again), nor where it takes a press, nor what it holds (a spinner's ring turning by the clock, View::cycle).
/// Place's.
#callsite(autofill(loc))
pub fn View::turn(self : View, r : Live[Double], drawn? : Bool = false, loc~ : SourceLoc) -> View {
  self.bind(loc~, Turn, r, Place, fn(r) {
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
#callsite(autofill(loc))
pub fn View::fades(self : View, f : Live[(Double, Double, Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, Fades, f, Place, fn(f) { self.tree.nodes[self.at].look.fades = f })
  self
}

///|
/// What it holds drawn stretched as Android's list is at an end as that changes (EdgeEffect's intensity `ov`, from its
/// top positive, from its foot negative; 0 none: HWUI's StretchEffect, each point of it where @view.stretch_map puts
/// it, its clips and fades inside it with it), as what draws it says; placement's (a scrolling page's list's:
/// Scroll::list).
#callsite(autofill(loc))
pub fn View::stretches(self : View, ov : Live[Double], loc~ : SourceLoc) -> View {
  self.bind(loc~, Stretch, ov, Place, fn(ov) { self.tree.nodes[self.at].look.stretch = ov })
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
    m.drawn_off = (m.look.dx + m.moved.0, m.look.dy + m.moved.1, m.look.sx, m.look.sy)
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
        take(k, ox + c.flex.left + off_x(c), oy + c.flex.top + off_y(c))
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
/// comes to as it opens (its words or its width changed meanwhile); `from_foot`: what it holds laid out at its foot instead,
/// past its top (what stands on its foot stays as it opens and closes). Layout's.
#callsite(autofill(loc))
pub fn View::opens(self : View, share : Live[Double?], from_foot? : Bool = false, loc~ : SourceLoc) -> View {
  self.bind(loc~, Opens, share, Layout, fn(k) {
    let st = self.tree.nodes[self.at].flex.style
    match k {
      Some(k) => {
        st.content_share = k
        st.justify = if from_foot { FlexEnd } else { Center }
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
/// Whether what it holds past its edges fades out towards them, each pixel by where it is (View::fades), as far before
/// each as it reaches past it and no further than half of what shows (an old view's cut_soft), worked out where it is
/// laid out as it is composed: a room opening on what it holds cut softly at both ends. Place's.
#callsite(autofill(loc))
pub fn View::cuts_softly(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, CutsSoftly, on, Place, fn(on) { self.tree.nodes[self.at].look.cut_soft = on })
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
/// out now: @motion's Moves::moves_with). Place's: nothing of it laid out or made again.
#callsite(autofill(loc))
pub fn View::drawn_off(self : View, d : Live[(Double, Double)], loc~ : SourceLoc) -> View {
  self.bind(loc~, DrawnOff, d, Place, fn(d) {
    self.tree.nodes[self.at].look.drawn_off = d
    self.tree.places_rev = self.tree.places_rev + 1
  })
  self
}

///|
/// How a node's own ground is drawn other than as it is laid out (View::ground_drawn): how far off where it is laid out
/// across and down, how much wider and taller (points, from its top left), and how round its corners are drawn (top
/// left, then round it; None: as it says, View::radius and View::corners).
#derive(Eq, Debug)
pub(all) struct GroundShape {
  dx : Double
  dy : Double
  dw : Double
  dh : Double
  corners : (Double, Double, Double, Double)?
}

///|
/// A ground drawn as it is laid out: off by nothing, as big, as round as it says.
pub let ground_as_laid : GroundShape = { dx: 0.0, dy: 0.0, dw: 0.0, dh: 0.0, corners: None }

///|
/// Whether it says the ground is drawn other than as it is laid out.
pub fn GroundShape::reshaped(self : GroundShape) -> Bool {
  self.dx != 0.0 || self.dy != 0.0 || self.dw != 0.0 || self.dh != 0.0 || self.corners is Some(_)
}

///|
/// How its own ground is drawn other than as it is laid out (GroundShape: off, bigger, rounder; points, from its top
/// left), as it changes: all of its ground (its shadow, its glass, its fill, its edge), as a shape going on its own; not
/// what it holds, which is where its layout puts it (each said to go itself); pressed where it is laid out (a thing
/// changing shape for its cause: @motion's Moves::reshapes). Place's: nothing of it made again.
#callsite(autofill(loc))
pub fn View::ground_drawn(self : View, d : Live[GroundShape], loc~ : SourceLoc) -> View {
  self.bind(loc~, GroundDrawn, d, Place, fn(d) { self.tree.nodes[self.at].look.ground_drawn = d })
  self
}

///|
/// How node `id` draws its own ground other than as it is laid out (View::ground_drawn; as laid out for one let go).
pub fn Tree::ground_drawn_of(self : Tree, id : NodeId) -> GroundShape {
  if self.alive_id(id) {
    // (by how tall the one it follows shows, given it where it is drawn: View::shown_by)
    match self.shown_bys.get(id.at) {
      Some((of, f)) if self.alive_id(of) => return f(self.nodes[of.at].flex.height)
      _ => ()
    }
    self.nodes[id.at].look.ground_drawn
  } else {
    ground_as_laid
  }
}

///|
/// What hosts the tree draws it at `g` device pixels a point (0: none said): what is drawn off where it is laid out is
/// drawn off by whole pixels (View::drawn_off).
pub fn Tree::set_pixel_grid(self : Tree, g : Double) -> Unit {
  if g != self.pixel_grid {
    self.places_rev = self.places_rev + 1
  }
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
  rows_slot_on(h, self.rows_grid_said.get())
}

///|
/// The pixels a point where a page's list sets its rows on them (Tree::rows_slot's grid; 0: none), followed.
pub fn Tree::rows_grid_now(self : Tree) -> Double {
  self.rows_grid_said.get()
}

///|
/// How tall a row `h` laid out as tall is laid out on a grid of `g` pixels a point (Tree::rows_slot; 0: as it is).
pub fn rows_slot_on(h : Double, g : Double) -> Double {
  if g > 0.0 {
    (h * g - 0.000001).ceil() / g
  } else {
    h
  }
}

///|
/// Node `at` a page's list's rows' holder (Tree::set_rows_grid), its rows laid out on the grid there is; those let go
/// since no more counted. Made in a row of another such list, a fault (rows_list_nested_said).
fn Tree::rows_list(self : Tree, at : Int) -> Unit {
  let keep = self.rows_lists.filter(fn(i) { i != at && self.nodes[i].live && self.nodes[i].list_rows })
  self.rows_lists.clear()
  self.rows_lists.append(keep)
  self.rows_lists.push(at)
  self.nodes[at].list_rows = true
  self.nodes[at].flex.style.rows_grid = self.rows_grid
  self.layout_marked_at(at)
  match self.rows_list_nested_said(at) {
    Some(said) => self.fault({ at, gen: self.nodes[at].gen }, said)
    None => ()
  }
}

///|
/// Where node `at`, a page's list's rows' holder, is made in a row of another's, what is wrong said: which two lists
/// and the row, each where it was made (Tree::source_of). The walk puts a list's rows on its host's grid by the holder it
/// last came to (Tree::each_drawn_in_order's `rows_at`), so the outer's rows after the inner would be drawn where their
/// sums put them, not on the grid's own numbers; asked once, as the inner is made, never as a frame is drawn.
fn Tree::rows_list_nested_said(self : Tree, at : Int) -> String? {
  let mut row = at
  let mut p = self.nodes[at].parent
  while p >= 0 {
    if self.nodes[p].list_rows {
      let place = fn(i : Int) {
        let (made, part) = self.source_of({ at: i, gen: self.nodes[i].gen })
        if part == "" || part == made {
          made
        } else {
          "\{made} (in a part asked for at \{part})"
        }
      }
      let list_of = fn(i : Int) { if self.nodes[i].parent >= 0 { self.nodes[i].parent } else { i } }
      return Some(
        "a page's list made in a row of another page's list (View::scrolls_window in a row of one): the outer's rows after it would not be put on its host's grid; the inner made at \{place(list_of(at))}, in the row made at \{place(row)}, of the list made at \{place(list_of(p))}",
      )
    }
    if !self.nodes[p].slot {
      row = p
    }
    p = self.nodes[p].parent
  }
  None
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
        y = y + m.look.dy + self.scroll_off_now(m).1
      }
    }
    i = m.parent
  }
  y
}

///|
/// Where a page's list's row is drawn down the window, `y` as it was summed there, on its host's grid of `g` pixels a
/// point (Tree::set_rows_grid): the grid's own number for the pixel it is on. Its top is on one wherever it is scrolled
/// (Tree::rows_placed), but come to as a sum of where the list is, how far it is scrolled and where the row is laid
/// out in it, numbers each path to a state (scrolled there, asked there, made there) comes to otherwise, so its last
/// bits went by the path; put on the grid's own number after the last of the sum, the same however it came there
/// (list_three_paths_test).
pub fn row_on_grid(y : Double, g : Double) -> Double {
  (y * g).round() / g
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
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  let mut x = 0.0
  let mut y = 0.0
  let mut i = self.at
  while i >= 0 {
    let m = self.tree.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
      // (and as far as a column scrolls it now: Node's scroll_off)
      if m.scroll_off is Some(_) {
        let (sx, sy) = self.tree.scroll_off_now(m)
        x = x + sx
        y = y + sy
      }
    }
    i = m.parent
  }
  (x, y, n.lw, n.lh)
}

///|
/// Node `id` as it was last placed against how it is laid out now, for a Tester's check that what a frame draws was
/// placed by the layout it draws by (tester_placed.mbt): whether it was placed at all, how big it was placed, how big it
/// is laid out. None: no such node.
pub fn Tree::placed_against_laid(self : Tree, id : NodeId) -> (Bool, Double, Double, Double, Double)? {
  guard id.at >= 0 && id.at < self.nodes.length() else { return None }
  let n = self.nodes[id.at]
  guard n.live && n.gen == id.gen else { return None }
  Some((n.placed, n.lw, n.lh, n.flex.width, n.flex.height))
}

///|
/// The clock set to `ms` and what is bound to it worked out there (what follows a way: View::drawn_while), as the
/// layout at that moment asks (Tree::measured_now, View::grows_now); untracked, its caller's.
fn Tree::bound_at(self : Tree, ms : Double) -> Unit {
  self.clock_to(ms)
  self.beat.set(ms)
  self.pull()
  self.draining += 1
  let mut i = 0
  while i < self.bindings_due.length() {
    let b = self.bindings_due[i]
    if b.queued {
      (b.run)()
    }
    i = i + 1
  }
  self.draining -= 1
  self.bindings_due.clear()
}

///|
/// Whether it was ever placed: where it stood before a change told now (placed_window_now) is somewhere, not nowhere
/// (none of what is made for that change, or since the last was placed).
pub fn View::was_placed(self : View) -> Bool {
  guard self.live() is Some(n) else { return false }
  n.placed
}

///|
/// What was told worked out and laid out as of the logic's moment, nothing placed by it (each node where it was placed
/// till a frame or a change's end places things, by this same layout): where a change under way lays things out, read
/// by what goes from where they stood to there for its cause (View::laid_window_now), the same for all that read it in
/// that change.
fn Tree::measured_now(self : Tree) -> Unit {
  // (asked as that layout is under way, by what a room's fill makes in it reading how tall it is laid out as it is made
  // (reveal_node): that layout as it stands, none begun inside it, which would place what it lays out from its own
  // generation and leave what the one under way laid out unplaced)
  if self.last_w <= 0.0 || self.measuring {
    return
  }
  // (asked in a change holding its boxes: those put first)
  self.boxes_flushed()
  let at = self.logic_said()
  let shown = self.clock.untracked()
  // (its clock set to the moment and back: what that tells is no change of its own to settle after)
  let was_standing = self.standing
  self.standing = true
  @signals.untracked(fn() {
    self.bound_at(at)
    if self.layout_due && self.measured_gen < 0 {
      self.alone_laid_out()
      self.work.computes = self.work.computes + 1
      let g = @flex.computes() + 1
      self.measuring = true
      self.laids = self.laids + 1
      @flex.compute(self.nodes[0].flex, width=self.last_w, height=self.last_h, round=false, reuse=true)
      self.measuring = false
      self.measured_gen = g
      // (placed by once things are placed, whatever is laid out again before that: from the first of what was laid out
      // and not placed yet)
      if self.walk_from < 0 || g < self.walk_from {
        self.walk_from = g
      }
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
      let (dx, dy) = self.tree.off_now(m)
      x = x + m.flex.left + dx
      y = y + m.flex.top + dy
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
  let (dx, dy) = self.tree.off_now(n)
  (n.flex.left + dx, n.flex.top + dy, n.flex.width, n.flex.height)
}

///|
/// How far node `id` turns what it draws itself, and whether about the middle of what it draws (View::turn; 0 for one
/// let go).
pub fn Tree::turn_of(self : Tree, id : NodeId) -> (Double, Bool) {
  (self.turn_angle_of(id), self.turns_about_drawn(id))
}

///|
/// How far node `id` turns what it draws itself (View::turn; 0 for one let go): Tree::turn_of's first, read alone with
/// nothing made for it, as each node painted reads it.
pub fn Tree::turn_angle_of(self : Tree, id : NodeId) -> Double {
  if self.alive_id(id) {
    self.nodes[id.at].look.turn
  } else {
    0.0
  }
}

///|
/// Whether node `id` turns about the middle of what it draws, not of its box (View::turn; not for one let go).
pub fn Tree::turns_about_drawn(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.nodes[id.at].look.turn_drawn
}

///|
/// How big it is drawn, what it holds with it, as it changes (1: as it is laid out), about the point of it `about` says
/// (Pivot: At, shares of its width and height, (0.5, 0.5) its middle; FromBeside, the edge it goes out from beside
/// its anchor, on the side it went to, lined up as it is: a popover's, grown from what opened it): its place's. Drawn,
/// pressed, taken (View::takes, what a host under it is told covers it) and read out where it is drawn, as big: one
/// projection of it and its holders (Tree::projected); laid out as before. Where what it holds cuts them, cut as far
/// in; its words, its shapes and its corners drawn as big. An old view it holds (View::hosted) laid out as big as its
/// node, drawn, pressed, typed into and read out as big where it is drawn, by what hosts the tree (ui's island_proj).
#callsite(autofill(loc))
pub fn View::scale(self : View, s : Live[Double], about? : Pivot = At(0.5, 0.5), loc~ : SourceLoc) -> View {
  self.bind(loc~, Scale, s, Place, fn(s) {
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
  match n.props.get(Prop::Presses.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Presses.ord())
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.inert = !on
    self.tree.said_marked(self.at, words=false, state=true)
    self.tree.hits_bump()
    if !on {
      self.tree.hold_lost_in(self.at)
      self.tree.focus_lost_in(self.at)
      self.tree.back_lost_in(self.at)
    }
    // (what hosts it holds in it told, at this cause, once the change is committed whole: Tree::on_modals)
    self.tree.modals_told(within=self.at)
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::Presses.ord()] = stop
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
  match n.props.get(Prop::OverAll.ord()) {
    Some(stop) => {
      n.props.remove(Prop::OverAll.ord())
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.over_all = on
    self.tree.top_last()
    // (read out among the root's at its place, over what a modal layer holds or not: Tree::said_pass)
    self.tree.said_marked(self.at, words=false, state=true, kids=true)
    self.tree.places_told()
    self.tree.hits_bump()
    self.tree.modals_told()
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::OverAll.ord()] = stop
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
  // (as the order was last worked out, while it is not due again: Tree::ordered)
  if !self.order_due && at >= 0 && at < self.tops.length() && self.tops[at] != -2 {
    return self.tops[at]
  }
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
#callsite(autofill(loc))
pub fn View::stacked(self : View, stack : Live[Int], loc~ : SourceLoc) -> View {
  self.bind(loc~, Stacked, stack, Layout, fn(k) {
    self.tree.nodes[self.at].stack = k
    self.tree.top_last()
    // (read out among the root's at its place, over what a modal layer holds or not: Tree::said_pass)
    self.tree.said_marked(self.at, words=false, state=true, kids=true)
    self.tree.places_told()
    self.tree.hits_bump()
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
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) => self.stack_at(id.at)
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
    self.hits_bump()
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
}

///|
/// What the root holds put at another place in the window's stack of layers: told to what read where they are
/// (Tree::places_read).
fn Tree::places_told(self : Tree) -> Unit {
  self.places.set(self.places.untracked() + 1)
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
    Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) => self.over_all_at(id.at)
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
  match n.props.get(Prop::Modal.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Modal.ord())
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    n.modal = on
    self.tree.hits_bump()
    match self.tree.modals.search(self.at) {
      Some(i) if !on => self.tree.modals.remove(i) |> ignore
      None if on => self.tree.modals.push(self.at)
      _ => ()
    }
    self.tree.modals_told()
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::Modal.ord()] = stop
      })
  }
  self
}

///|
/// A modal layer said on or off, or where what is drawn is among what holds it changed (one made, let go, moved, back
/// from leaving): a finger held on what the topmost no longer lets take input called off, and what hosts the tree told
/// (Tree::on_modals), once the change doing it is committed whole, at that change's moment (Tree::modals_settled).
fn Tree::modals_told(self : Tree, within? : Int = -1) -> Unit {
  self.inputs_marked(within)
  self.modals_marked()
}

///|
/// What takes input to be told anew where the change is node `within` and what it holds (one made, moved, leaving, said
/// to take no press, left out of its row or back in it) alone: whether each else takes input reads only what holds it
/// and modal layers, none of which it changed while no modal layer is said, nor the old frame's moved; else (-1) all of
/// it (Tree::inputs_told).
fn Tree::inputs_marked(self : Tree, within : Int) -> Unit {
  if within < 0 || !self.modals.is_empty() || self.held_under_now() != self.held_under {
    self.inputs_whole = true
  } else if !self.inputs_whole && !self.inputs_in.contains(within) {
    self.inputs_in.push(within)
  }
}

///|
/// What a modal layer says, and what takes input where it was marked (Tree::inputs_marked), told: at once, or once the
/// change being committed is committed whole (Tree::modals_told).
fn Tree::modals_marked(self : Tree) -> Unit {
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
      Some(h) if !self.allows(h) => self.focus_lost_in(0)
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
/// Whether the topmost modal layer now leaves what is typed to the field of an old view under it that has the focus
/// (View::leaves_typing).
pub fn Tree::typing_left_under(self : Tree) -> Bool {
  match self.modal_top() {
    Some(m) => self.nodes[m.at].leaves_typing
    None => false
  }
}

///|
/// Whether layer `layer`, opened, takes the keyboard's focus from what under it has it (a modal layer's: one that leaves
/// what is typed to a field under it (View::leaves_typing) does not, nor one not modal).
pub fn Tree::takes_focus_under(self : Tree, layer : NodeId) -> Bool {
  self.alive_id(layer) && self.nodes[layer.at].modal && !self.nodes[layer.at].leaves_typing
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
/// Where the old frame's topmost modal layer is in the window's stack of layers (Tree::hold_under): as it is as asked
/// where what hosts it said how to ask it, else as last told.
fn Tree::held_under_now(self : Tree) -> Int {
  match self.held_under_of {
    Some(f) => f()
    None => self.held_under
  }
}

///|
fn Tree::allows_at(self : Tree, at : Int, held? : Bool = true) -> Bool {
  // (an old frame's modal layer over it in the window's stack of layers: Tree::held_under)
  let under = if !held { -2 } else { self.held_under_now() }
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
#callsite(autofill(loc))
pub fn View::words(
  self : View,
  words : Live[String],
  ink? : Int64 = 0x000000FFL,
  look? : WordsLook = words_plain,
  loc~ : SourceLoc,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.look.ink = ink
  n.look.words_look = look
  let tree = self.tree
  let at = self.at
  // (cut short as said before its words were: what of them is kept, as they look now)
  tree.cut_applied(at)
  // (it measures what the node holds now, by its index: dropped as it is let go)
  n.flex.measure = Some(fn(w, wm, _h, _hm) {
    let offered = match wm {
      Exactly | AtMost => w
      Undefined => -1.0
    }
    tree.work.measured = tree.work.measured + 1
    let nd = tree.nodes[at]
    let look = nd.look
    let t0 = tree.part_began()
    // (at its own size of words: View::words_scale's)
    let scale = if nd.words_as_said { 1.0 } else { (tree.env.words_scale)() }
    // (its line breaks kept where it says so, View::words_breaks: measured on their lines as written)
    let (mw, mh) = if look.runs.is_empty() {
      (if look.words_breaks { tree.measure_kept } else { tree.measure })(look.words, look.words_look, offered, scale)
    } else {
      (if look.words_breaks { tree.measure_runs_kept } else { tree.measure_runs })(
        look.runs,
        look.words_look,
        look.runs_look,
        offered,
        scale,
      )
    }
    if t0 >= 0.0 {
      let t1 = tree.part_began()
      if t1 > t0 {
        tree.measured_ms += t1 - t0
      }
    }
    // (on one line wider than it may be, saying shorter ones: as wide as what of them would be drawn there, as an old
    // view's leaf_size has it; what is drawn chosen once it is laid out, Tree::shorter_in, not by this)
    let mw = if look.runs.is_empty() &&
      !look.words_look.wrap &&
      nd.shorter.length() > 0 &&
      wm == AtMost &&
      mw > offered + 0.5 {
      (tree.measure_shorter)(look.words, nd.shorter, look.words_look, offered, scale)
    } else {
      mw
    }
    match wm {
      Exactly => (w, mh)
      _ => (mw, mh)
    }
  })
  self.bind(loc~, Words, words, Both, fn(s) {
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
#callsite(autofill(loc))
pub fn View::shorter(self : View, alts : Live[Array[String]], loc~ : SourceLoc) -> View {
  let at = self.at
  let tree = self.tree
  // (how narrow it may be follows how its words look as the system's size of words changes: worked out again then)
  if self.live() is Some(n) && n.props.get(Prop::Shorter.ord()) is None {
    self.reacts(fn() { self.words_redone() }, fn(_) { tree.give_way_applied(at) })
  }
  self.bind(loc~, Shorter, alts, Layout, fn(a) {
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
#callsite(autofill(loc))
pub fn View::drops(self : View, k : Live[Int], loc~ : SourceLoc) -> View {
  self.bind(loc~, Drop, k, Layout, fn(k) { self.tree.nodes[self.at].flex.style.drop = k })
  self
}

///|
/// A row that leaves out of what it holds what has not the room (View::drops), as it changes. Layout's.
#callsite(autofill(loc))
pub fn View::fits(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, Fits, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.fits = on })
  self
}

///|
/// A row of ways of saying one thing, each shorter than the one before (the old views' `one_of`, ui's node.mbt), as
/// it changes: of what it holds only the first that fits its room whole is laid out and drawn, the last where none
/// does; it needs at least what the last needs. Which it is, is worked out by the width the row is given as it is laid
/// out (flex's first_fit), told back to nothing: a width that changes makes it another at once (no coming or going: an
/// arrangement by the room, not something shown or hidden). Those not laid out are left out as a row that fits leaves
/// them (View::fits, which it says too, as the old views' does): drawn, pressed and read out nowhere. Layout's.
#callsite(autofill(loc))
pub fn View::one_of(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, OneOf, on, Layout, fn(on) {
    let n = self.tree.nodes[self.at]
    n.flex.style.one_of = on
    // (a row that fits as well, what it does not lay out left out; turned off, fits as View::fits says, none where it
    // says nothing)
    if on {
      n.flex.style.fits = true
    } else if n.props.get(Prop::Fits.ord()) is None {
      n.flex.style.fits = false
    }
  })
  self
}

///|
/// Kept whole in a row that leaves out what has not the room (View::fits): what may leave (View::drops) leaves for it
/// first; once nothing more may, it gives way as it otherwise would (its words cut short: View::cuts), as it changes.
/// The old views' `keep` on words cut short: a bar's title cut only after what is beside it has gone. Cut last, not
/// never: View::keeps_held is never narrower than what it holds, whatever the room, so its words are never cut. Layout's.
#callsite(autofill(loc))
pub fn View::fit_whole(self : View, on : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, FitWhole, on, Layout, fn(on) { self.tree.nodes[self.at].flex.style.fit_whole = on })
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
#callsite(autofill(loc))
pub fn[K : Eq] View::measured(
  self : View,
  content : Live[K],
  size : (K, Double?) -> (Double, Double),
  loc~ : SourceLoc,
) -> View {
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
  self.bind(loc~, Measured, content, Layout, fn(v) { k.val = Some(v) })
  self
}

///|
/// The words it shows in pieces, each set its own way (a weight, an ink: @text.Run), one paragraph laid out as one
/// (View::words otherwise: read out, found and measured as the pieces' words one after another), as they change.
#callsite(autofill(loc))
pub fn View::words_runs(
  self : View,
  runs : Live[Array[@text.Run]],
  ink? : Int64 = 0x000000FFL,
  look? : WordsLook = words_plain,
  loc~ : SourceLoc,
) -> View {
  let tree = self.tree
  let at = self.at
  self.words(loc~, Is(""), ink~, look~) |> ignore
  self.bind(loc~, Words, runs, Both, fn(rs) {
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
    Some(f) => self.runs_picked(loc~, f(self)) |> ignore
    None => ()
  }
  self
}

///|
/// Where the pointer's secondary button was pressed on a node (View::on_menu): in its own terms as it is drawn then, in
/// the window's, and when (the event's own moment).
#derive(Eq, Debug)
pub(all) struct Menu {
  x : Double
  y : Double
  wx : Double
  wy : Double
  at : Double
}

///|
/// What the pointer's secondary button pressed on it asks for (its menu, where it was pressed): run as one change at
/// the press's moment, outside any tracking. Its primary press and a finger are its on_press's and on_drag's, as ever.
pub fn View::on_menu(self : View, f : (Menu) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_menu = Some(f)
  self
}

///|
/// The pointer's secondary button pressed at (x, y) in the window at `at`: the menu of the topmost node drawn there that
/// takes a press, where it asks for one (View::on_menu), else of the first that holds it and does, out from it (a row's,
/// pressed on its name or a button in it), as one event of that moment; true then. None asks where none out to one
/// hosting the old view (its own), the edge of a modal layer or the root does, or nothing is there.
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
/// with it (`mods`, the host's wheel_mod_*), in the node's own terms as it is drawn then, in the window's, and when;
/// how wide and how tall the node is laid out as of then, in its own terms (`w`, `h`: a Drag's, what the wheel zooms or
/// pans within, nothing of its layout read back for it).
#derive(Eq, Debug)
pub(all) struct Wheel {
  x : Double
  y : Double
  wx : Double
  wy : Double
  dx : Double
  dy : Double
  mods : Int
  at : Double
  w : Double
  h : Double
}

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
///|
/// The last wheel a tree was asked of (Tree::wheel_at): the node found under it and the one that took it (its
/// `on_wheel`, or the old view it hosts), each by its place and generation (-1: none). What a scripted run says of its
/// `wheel` (ui's drive.mbt); nothing reads it to decide anything. Numbers written in place: a wheel turned on a
/// device makes nothing for it.
pub(all) struct WheelLast {
  mut found_at : Int
  mut found_gen : Int
  mut took_at : Int
  mut took_gen : Int
}

///|
// kept across runs: each wheel writes it anew
pub let wheel_last : WheelLast = { found_at: -1, found_gen: 0, took_at: -1, took_gen: 0 }

///|
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
  wheel_last.found_at = -1
  wheel_last.took_at = -1
  self.event(t, fn() {
    // (where things are as of then, what the change under way set before it counted: Tree::asked_at's)
    self.laid_now()
    let found : Ref[NodeId?] = Ref(None)
    let now = self.logic_said()
    self.each_drawn_scaled(fn(c, cx, cy, _, s) {
      if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
        let n = self.nodes[c.id.at]
        if n.on_wheel is Some(_) ||
          n.on_drag is Some(_) ||
          n.on_press is Some(_) ||
          n.top_row ||
          (n.hosted && @signals.untracked(fn() { there(c.id) })) {
          found.val = Some(c.id)
        }
      }
    })
    match found.val {
      Some(f) => {
        wheel_last.found_at = f.at
        wheel_last.found_gen = f.gen
      }
      None => ()
    }
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
          wheel_last.took_at = id.at
          wheel_last.took_gen = id.gen
          break
        }
      }
      guard n.wheel_said == said && n.on_wheel is Some(f) else { continue }
      theirs.val = true
      let (nx, ny, ns) = self.placed(id.at)
      if @signals.untracked(fn() {
          f({ x: (x - nx) / ns, y: (y - ny) / ns, wx: x, wy: y, dx, dy, mods, at: t, w: n.flex.width, h: n.flex.height })
        }) {
        wheel_last.took_at = id.at
          wheel_last.took_gen = id.gen
        break
      }
    }
  })
  theirs.val
}

///|
/// A key, as a node is told it (View::on_key): its code and the modifiers held (the host's, as an old view reads them:
/// ui's key codes), at its moment.
#derive(Eq, Debug)
pub(all) struct Key {
  code : Int
  mods : Int
  at : Double
}

///|
/// What a key does to it, while it takes input (living, not leaving nor said to take none, no modal layer over it that
/// does not hold it): run at the key's moment, as one change outside any tracking; true where it took the key, which
/// nothing else is told of then. Asked topmost first (Tree::key_at).
pub fn View::on_key(self : View, f : (Key) -> Bool) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_key = Some(f)
  n.key_said = n.key_said + 1
  self
}

///|
/// A key (`code`, `mods` held) at `at`: asked of the nodes that take keys (View::on_key) that may take input now, the
/// one drawn last first (after what holds it, after what is before it among what holds them both), each in turn till one
/// takes it, as one event of that moment (the tree brought there first where it is in none); `above`, only what is over
/// that in the window's stack of layers (View::stacked: the old frame's layer under it taking the keys); `within`, only what
/// holds that node (itself too). True where one took it.
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
    // (the topmost first: what a node holds after it, its later kids before its earlier)
    let found : Array[Int] = []
    self.topmost_from(0, fn(n) { n.on_key is Some(_) }, found)
    // (`above`: of what is over that in the window's stack of layers alone, View::stacked)
    let found = if above > -3 { found.filter(fn(i) { self.stack_at(i) > above }) } else { found }
    // (`within`: of what holds that alone, itself too: the node an old view's field with the focus is hosted in)
    let found = match within {
      Some(w) => found.filter(fn(i) { self.holds({ at: i, gen: self.nodes[i].gen }, w) })
      None => found
    }
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
/// The nodes from `at` down that `has` says of, the one drawn last first (after what holds it, its later kids before its
/// earlier): Tree::key_at's, back_taker's.
fn Tree::topmost_from(self : Tree, at : Int, has : (Node) -> Bool, out : Array[Int]) -> Unit {
  let n = self.nodes[at]
  let mut k = n.kids.length() - 1
  while k >= 0 {
    self.topmost_from(n.kids[k], has, out)
    k = k - 1
  }
  if has(n) {
    out.push(at)
  }
}

///|
/// What the pointer does at (x, y) at `at` (a secondary press), asked of the topmost node drawn there that takes a press,
/// or where that one does not `take` it, of the first that holds it and does, out from it (a button in a row that has a
/// menu: the row's), never past one hosting the old view (its own) nor out of a modal layer: `then` with it, where in it
/// and when, as one event of that moment (the moment of the event it is in, the tree brought there first where it is in
/// none; where things are as of then, as a drag's: Tree::drag_at); true then.
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
    let now = self.logic_said()
    self.each_drawn_scaled(fn(c, cx, cy, _, s) {
      if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
        let n = self.nodes[c.id.at]
        if takes(n) || n.on_drag is Some(_) || n.on_press is Some(_) || n.top_row || n.hosted {
          found.val = Some(c.id)
        }
      }
    })
    // (the topmost there, else the first that holds it and takes it, out from it: never past one hosting the old view
    // (the old view's own) nor out of a modal layer (what is under it takes none))
    let mut i = match found.val {
      Some(id) => id.at
      None => -1
    }
    while i >= 0 {
      let n = self.nodes[i]
      if takes(n) && !self.pressless_at(i) {
        asked.val = true
        let (nx, ny, ns) = self.placed(i)
        then(n, (x - nx) / ns, (y - ny) / ns, t)
        break
      }
      if n.hosted || n.modal {
        break
      }
      i = n.parent
    }
  })
  asked.val
}

///|
/// What a press on it does: run outside any tracking, as one change (what it writes told once it is done).
pub fn View::on_press(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_press = Some(f)
  self.tree.inputs_own_said(self.at)
  self.tree.said_marked(self.at, words=false, state=true)
  self.tree.hits_bump()
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
  self.tree.inputs_own_said(self.at)
  self.tree.hits_bump()
  match n.props.get(Prop::MovesWindow.ord()) {
    Some(stop) => {
      n.props.remove(Prop::MovesWindow.ord())
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
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::MovesWindow.ord()] = stop
      })
  }
  self
}

///|
/// How fast a finger goes as of one of its events (Drag's): known (none, called off), or its trackers as they were
/// then, worked out as it is asked.
#derive(Eq, Debug)
pub struct DragSpeed {
  priv across : TrackerSaid?
  priv down : TrackerSaid?
}

///|
/// No speed (a finger called off, or one that cannot tell).
let drag_still : DragSpeed = { across: None, down: None }

///|
/// How fast the finger goes as of this event, across (the window's points a ms), from its own events since it went down
/// by their own times (Tracker: Compose's VelocityTracker, a pause cutting it, as an old view's list flings at): 0 where
/// it cannot tell. Worked out as it is asked, of those events as they were then (a finger's moves come many a frame,
/// most never asked how fast).
pub fn Drag::vx(self : Drag) -> Double {
  match self.speed.across {
    Some(s) => s.velocity()
    None => 0.0
  }
}

///|
/// How fast the finger goes as of this event, down (Drag::vx's).
pub fn Drag::vy(self : Drag) -> Double {
  match self.speed.down {
    Some(s) => s.velocity()
    None => 0.0
  }
}

///|
/// A finger or the pointer held on a node (View::on_drag): put down, moved, let go or called off (the host took it:
/// a gesture of the system's), where (in the node's own terms: from its top left as it is drawn then) and when (the
/// event's own moment).
#derive(Eq, Debug)
pub(all) enum DragIs {
  Down
  Moved
  Up
  Off
}

///|
/// By its name, as tests write a drag's step: what `derive(Show)` wrote.
pub impl Show for DragIs with output(self, logger) {
  logger.write_string(
    match self {
      Down => "Down"
      Moved => "Moved"
      Up => "Up"
      Off => "Off"
    },
  )
}

///|
#derive(Eq, Debug)
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
  /// how fast the finger goes as of this event (Drag::vx, Drag::vy): its own events since it went down, kept as they
  /// were then, the speed worked out of them only where it is asked
  priv speed : DragSpeed
}

///|
/// What a finger or the pointer held on it does as it goes: put down on it, it is the node's till it is let go or
/// called off (moved anywhere meanwhile), each event handled at its own moment as one change (Tree::event), outside
/// any tracking. One let go meanwhile is told nothing more. Up to `fingers` held on it at once, each told by its own
/// events (Drag's `finger`); one more down calls the hold off (each of those down told Off), the rest of it nobody's.
/// `whole`: a drag anywhere on it is its own (a picture a drag pans, as the old view's `capture`): a press on it takes
/// nothing drawn over it smaller than its room from round where that is drawn (reach.mbt).
pub fn View::on_drag(self : View, f : (Drag) -> Unit, fingers? : Int = 1, whole? : Bool = false) -> View {
  guard self.live() is Some(n) else { return self }
  n.fingers = if fingers < 1 { 1 } else { fingers }
  n.drags_whole = whole
  n.drag_said = n.drag_said + 1
  // (a raw on_drag, or a gesture said anew: answering a hold alone only where the gesture says so after it)
  n.hold_only = None
  self.drag_ended()
  // (said anew: a finger held on it now is the one before's, ended)
  match self.tree.held {
    Some(h) if h.at == self.at && h.gen == self.gen => self.tree.held_to(None)
    _ => ()
  }
  n.on_drag = Some(f)
  self.tree.inputs_own_said(self.at)
  self.tree.hits_bump()
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
    @halt.saying("hosted_takes of a node hosting nothing: View::takes")
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
  self.hits_bump()
  match n.takes_ver {
    Some(v) => v.set(v.untracked() + 1)
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
            speed: drag_still,
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
  let at = self.logic_said()
  let shown = self.clock.untracked()
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
        let told = fn(kind : DragIs, finger : Int, speed : DragSpeed) {
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
            speed,
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
            told(Off, g, drag_still)
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
/// from here): how fast it goes as of it (across, down, points a ms; Tracker::velocity_at), kept to be worked out as it
/// is asked. `up`: it goes up there, no sample where it says the last place again (Tracker::up).
fn Tree::tracked(
  self : Tree,
  finger : Int,
  down : Bool,
  track : Array[(Double, Double, Double)],
  t : Double,
  x : Double,
  y : Double,
  up? : Bool = false,
) -> DragSpeed {
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
  { across: Some(tx.said_at(t)), down: Some(ty.said_at(t)) }
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
/// finger that one's where it is then; nothing there to take it, no drag of this one's either). A `hold` alone (no
/// `press`, `tap`, `drag`, `through` nor `held_first`): no press or drag of its own, a finger down on it the first's out
/// from it that takes one, as were it not there; held still within the slop as long as its hold, the finger its from
/// then, what had it told Off (no tap, no press of it), its hold told at once (hold_in.mbt). Not in a top row that moves
/// the window (the window's drag begins as the press goes down) nor over an old view: a finger held on it there is
/// theirs.
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
    _ => @halt.saying("a gesture's hold told or handed through, not both")
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
        if through is Some(_) {
          self.tree.through_cover = Some(id)
        }
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
              Some(f) => {
                // (what the tap presses held where it is, press_stays.mbt)
                let stays = self.tree.press_stays(id)
                word(f, d, o)
                stays()
              }
              None => ()
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
  // (a hold alone, nothing else: a press or a drag on it the first's out from it that takes one, held long its own)
  if hold is Some((ms, _)) && press is None && tap is None && drag is None && through is None && held_first is None {
    n.hold_only = Some((ms, slop))
  }
  self
}

///|
/// `f` done as it starts leaving: as the structure holding it, or what holds that, lets it go (closing its room on a
/// Move, at once, another picked in its place), at that moment, before what it binds rests (View::rests); outside any
/// tracking, so it may write state. Once; again only once it has come back (View::come_back) and starts leaving anew.
/// What is to be done as it is let go is View::owns's. It.
pub fn View::on_leaving(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.leavings.push(f)
  self
}

///|
/// `f` done as it comes back from leaving (View::come_back), it or what holds it, after its starting to leave was told
/// (View::on_leaving): at that moment, outside any tracking.
fn View::on_back(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.backs.push(f)
  self
}

///|
/// Node `at` and all it holds told they start leaving (View::on_leaving), each not told since it last came back.
fn Tree::tell_leaving(self : Tree, at : Int) -> Unit {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return }
  let n = self.nodes[at]
  if !n.leave_told {
    n.leave_told = true
    if n.leavings.length() > 0 {
      let fs = n.leavings.copy()
      @signals.untracked(fn() {
        for f in fs {
          f()
        }
      })
    }
  }
  for k in n.kids.copy() {
    self.tell_leaving(k)
  }
}

///|
/// Node `at` and all it holds told they are back from leaving (View::on_back), each told it started leaving.
fn Tree::tell_back(self : Tree, at : Int) -> Unit {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return }
  let n = self.nodes[at]
  if n.leave_told {
    n.leave_told = false
    if n.backs.length() > 0 {
      let fs = n.backs.copy()
      @signals.untracked(fn() {
        for f in fs {
          f()
        }
      })
    }
  }
  for k in n.kids.copy() {
    self.tell_back(k)
  }
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
pub fn View::owns_while(self : View, stop : () -> Unit) -> () -> Unit {
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
  // (on a flight's way, or one of an id: that flight over, its id counted no more, shared.mbt)
  self.tree.share_let_go(self.at)
  // (what the pointer is over let go of, it or one it holds: pointed at no more, what holds it told so while it is
  // still held by them, View::pointed_in; what it is over then the host's to find again, as what takes it changed)
  if self.tree.pointed_within_at(self.at) {
    self.tree.pointed_to(None)
  }
  // (what it holds as this begins, each by its handle: one's going may take another out of it (View::lives_with, the
  // tip of a row held beside it in one layer), which is then let go already, its handle on nothing)
  let kids = n.kids.map(fn(k) { self.tree.handle(k) })
  n.kids.clear()
  // (what it holds goes out of the order with it, its run whole: none of theirs taken out by itself)
  self.tree.letting.push(self.at)
  for k in kids {
    k.let_go()
  }
  self.tree.letting.pop() |> ignore
  n.live = false
  if n.on_back is Some(_) || n.on_back_step is Some(_) {
    self.tree.backs = self.tree.backs - 1
  }
  // (a modal layer let go: what it kept from taking input, wherever it is held, told anew, as its being said off does)
  match self.tree.modals.search(self.at) {
    Some(i) => {
      self.tree.modals.remove(i) |> ignore
      self.tree.modals_told()
    }
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
  n.leavings.clear()
  n.backs.clear()
  n.leave_told = false
  n.on_press = None
  n.on_double_press = None
  n.on_step = None
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
  if n.behind {
    self.tree.behind_set -= 1
  }
  n.behind = false
  if n.bones != 0L {
    self.tree.bones_set -= 1
  }
  n.bones = 0L
  n.bone_whole = false
  n.cut = false
  n.pressed_cell = None
  n.pointed_cell = None
  n.ground_read = 0
  n.on_pointer_moved = None
  n.pointed_in_cell = None
  // (the focus on it: let go of with it, what has it told so)
  self.tree.focus_lost_in(self.at)
  n.focusable = false
  n.focus_keys = 0
  n.focus_tab = true
  n.tab_by_stop = false
  n.input_cell = None
  n.cursor = None
  n.as_ground = false
  n.beside = None
  n.beside_last = None
  n.beside_point = None
  n.beside_piece = None
  n.focused_cell = None
  n.focus_shown_cell = None
  n.size_cell = None
  n.shows = None
  n.shows_across = false
  n.shows_room = None
  n.claims = None
  n.claims_from = None
  n.bounds_input = false
  n.tucked_under = None
  n.drawn_clear = None
  n.bar_near = 0.0
  n.bar_across = false
  n.points = false
  n.bar_near_cell = None
  self.drag_ended()
  n.on_drag = None
  n.drags_whole = false
  n.drag_said = n.drag_said + 1
  n.takes = None
  // (what holds it holds one taking a point the fewer: what it held let go of already, each so)
  if n.inputs_own {
    n.inputs_own = false
    self.tree.inputs_count(self.at, -1)
  }
  // (held: let go of with it, nothing more told it, nothing of it handed to what is made in its place)
  match self.tree.held {
    Some(h) if h.at == self.at && h.gen == self.gen => self.tree.held_to(None)
    _ => ()
  }
  n.flex.measure = None
  n.flex.room = false
  n.flex.children.clear()
  n.flex.holds_gone = false
  let parent = n.parent
  if parent >= 0 {
    self.tree.marked_up(parent, true, true, false, false, true)
  }
  n.parent = -1
  n.content = None
  self.tree.draws_rev = self.tree.draws_rev + 1
  self.tree.draws_any_rev = self.tree.draws_any_rev + 1
  if self.tree.hosting == self.at {
    self.tree.hosting = -1
  }
  self.tree.removed.push({ at: self.at, gen: self.gen })
  self.tree.free.push(self.at)
  // (its run taken out of the order by itself, the rest as it was; one held by what is being let go, none: its run goes
  // with that one's. Not by how deep in letting go this is: what a scope let go of as it stopped, in another layer, is
  // held by none of those and goes by itself)
  if !self.tree.letting.contains(parent) {
    self.tree.order_taken_out(self.at, self.gen, parent)
  }
  self.tree.work.let_go = self.tree.work.let_go + 1
  self.tree.hits_bump()
}

///|
/// It lays out alone: as big as what holds it says it is (its height said, its width what it is given), whatever it
/// holds, so what changes under it (a row of a list made as it comes to show) is laid out again from it, nothing above
/// it, as Flutter's relayout boundary. Only while it was last laid out given both, else with what holds it.
pub fn View::lays_out_alone(self : View) -> View {
  guard self.live() is Some(n) else { return self }
  n.alone = true
  self
}

///|
/// A node holding what comes and goes (show, pick, each), with no box of its own, made at `loc` (where the
/// structure was asked for).
fn View::slot(self : View, loc : SourceLoc) -> View {
  guard self.live() is Some(n) else { return self.tree.none() }
  let v = self.tree.made(self.at, words_as_said=n.words_as_said, loc~)
  self.tree.nodes[v.at].slot = true
  n.kids.push(v.at)
  self.tree.order_marked_in(self.at)
  if self.at == 0 {
    self.tree.top_last()
  }
  v
}

///|
/// The boxes node `at` lays out as its own, in order: its own, or a slot's, those of what it holds.
fn Tree::boxes(self : Tree, at : Int, into : Array[@flex.Node]) -> Unit {
  self.work.boxes_walked += 1
  let n = self.nodes[at]
  if n.slot {
    for k in n.kids {
      self.boxes(k, into)
    }
  } else {
    into.push(n.flex)
  }
}

///|
/// Node `child` made last in what it holds: its box follows its holder's when each slot between is the last of what
/// holds it (a list's rows made one after another), put after them; else all are put again in order (boxes_again).
fn View::box_appended(self : View, child : Int) -> Unit {
  // (telling the host of a new box of the root's can make another of the root's at once, before this one is put)
  if self.at == 0 {
    self.boxes_again()
    self.tree.modals_told(within=child)
    return
  }
  let mut at = self.at
  while self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
    let parent = self.tree.nodes[at].parent
    let siblings = self.tree.nodes[parent].kids
    if parent == 0 || siblings.length() == 0 || siblings[siblings.length() - 1] != at {
      // (its box put in where it goes among its holder's, not all of them put again: Tree::box_put_in)
      if !self.tree.box_put_in(child) {
        self.boxes_again()
      }
      // (whether it takes input told it alone: the others' is what holds each and the modal layers, none of them changed)
      self.tree.modals_told(within=child)
      return
    }
    at = parent
  }
  // (one due to be put again in order (Tree::holding_boxes) is put whole as that ends: what is pushed now is redone)
  self.tree.nodes[at].flex.add(self.tree.nodes[child].flex)
  // (what it holds changed, not what it asks of what holds it: where it lays out alone, laid out again from it, as
  // boxes_put does)
  self.tree.layout_marked_at(at, within=true)
  self.tree.order_put_in(child, at)
  self.tree.modals_told(within=child)
}

///|
/// What it holds changed (made, let go, moved): the boxes of the node that lays them out (itself, or the first not a
/// slot holding it) put again in order, it marked to be laid out, the order to be made again.
fn View::boxes_again(self : View) -> Unit {
  let mut at = self.at
  while self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
    at = self.tree.nodes[at].parent
  }
  if self.tree.boxes_held > 0 {
    // (a change making many at once, each_inner's: put again once as it ends, not once for each, n² for n rows)
    let n = self.tree.nodes[at]
    if !n.boxes_due {
      n.boxes_due = true
      self.tree.boxes_held_at.push(at)
    }
    return
  }
  self.tree.boxes_put(at)
}

///|
/// The boxes of node `at` (a holder, not a slot) put again in order, it marked to be laid out, the order to be made
/// again.
fn Tree::boxes_put(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  let all : Array[@flex.Node] = []
  for k in n.kids {
    self.boxes(k, all)
  }
  n.flex.children.clear()
  n.flex.holds_gone = false
  for b in all {
    n.flex.add(b)
  }
  self.layout_marked_at(at, within=true)
  self.order_marked_in(at)
  // (what is drawn over what, among what holds it, changed. The root's: its children are the window's layers, and one
  // come, gone or moved among them changes which modal layer is over what (Tree::pressless_at's allows_at), so all
  // that may take input is told again, as ever. Any other's: whether each it holds takes input is what holds it and the
  // modal layers say, none of which a child come, gone or moved among the others changes: one come is told by what made
  // it (View::box_appended, take_in), one leaving by View::leave, one let go needs none; not all it holds told again)
  if at == 0 {
    self.modals_told(within=0)
  } else {
    self.modals_marked()
  }
}

///|
/// `change` made with what it makes or moves (View::box, drop, each's order) put in its holders' boxes once, as it
/// ends, not as each is made: n rows made into a list's slot, each walking all the rows before it, were n² (a list of
/// thousands made at once, as a page comes, seconds in the press that opened it).
fn Tree::holding_boxes(self : Tree, change : () -> Unit) -> Unit {
  self.boxes_held = self.boxes_held + 1
  change()
  self.boxes_held = self.boxes_held - 1
  if self.boxes_held == 0 {
    self.boxes_one_by_one = 0
    self.boxes_flushed()
  }
}

///|
/// The holders due to be put again in order (Tree::holding_boxes) put, as the change ends or a frame is laid out in
/// it (a host drawing a frame at once as it is told there is one to draw).
fn Tree::boxes_flushed(self : Tree) -> Unit {
  let mut i = 0
  while i < self.boxes_held_at.length() {
    let at = self.boxes_held_at[i]
    i = i + 1
    let n = self.nodes[at]
    n.boxes_due = false
    if n.live {
      self.boxes_put(at)
    }
  }
  self.boxes_held_at.clear()
}

///|
/// The last box node `at` lays out among its holder's (its own; a slot's, the last of what it holds that lays one
/// out): none where it lays out none (an empty slot).
fn Tree::last_box(self : Tree, at : Int) -> @flex.Node? {
  let n = self.nodes[at]
  if !n.slot {
    return Some(n.flex)
  }
  let mut i = n.kids.length() - 1
  while i >= 0 {
    match self.last_box(n.kids[i]) {
      Some(b) => return Some(b)
      None => ()
    }
    i = i - 1
  }
  None
}

///|
/// The box laid out just before node `at`'s among the boxes of the node that lays it out (the first not a slot holding
/// it): the last box of what comes before it in its slots, as far up as that holder; none where it is the first.
fn Tree::box_before(self : Tree, at : Int) -> @flex.Node? {
  let mut c = at
  while true {
    let p = self.nodes[c].parent
    guard p >= 0 else { return None }
    let kids = self.nodes[p].kids
    let mut j = match kids.search(c) {
      Some(i) => i - 1
      None => return None
    }
    while j >= 0 {
      match self.last_box(kids[j]) {
        Some(b) => return Some(b)
        None => ()
      }
      j = j - 1
    }
    if !self.nodes[p].slot {
      return None
    }
    c = p
  }
  None
}

///|
/// The node that lays out node `at`'s box: the first not a slot holding it; none where none does.
fn Tree::box_holder(self : Tree, at : Int) -> Int {
  let mut h = self.nodes[at].parent
  while h >= 0 && self.nodes[h].slot {
    h = self.nodes[h].parent
  }
  h
}

///|
/// Whether one more box may be put in or taken out by itself in the change being made: any outside a change that
/// makes many (Tree::holding_boxes); in one, a few, then all of its holders put again whole once as it ends.
fn Tree::box_one_more(self : Tree) -> Bool {
  if self.boxes_held == 0 {
    return true
  }
  if self.boxes_one_by_one >= boxes_one_by_one_most {
    return false
  }
  self.boxes_one_by_one = self.boxes_one_by_one + 1
  true
}

///|
/// Node `at`'s box (it no slot, just held) put in among its holder's where it goes, not all of them put again; its
/// holder marked to be laid out, the order to be made again there. Whether it was: not where its holder is due to be
/// put again whole anyway, nor where the box before it is not among its holder's (all put again then).
fn Tree::box_put_in(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  guard !n.slot && n.parent >= 0 else { return false }
  let h = self.box_holder(at)
  guard h > 0 && !self.nodes[h].boxes_due else { return false }
  let children = self.nodes[h].flex.children
  let pos = match self.box_before(at) {
    None => 0
    Some(b) =>
      match children.search_by(fn(c) { physical_equal(c, b) }) {
        Some(i) => i + 1
        None => return false
      }
  }
  guard self.box_one_more() else { return false }
  children.insert(pos, n.flex)
  if n.flex.style.gone_empty {
    self.nodes[h].flex.holds_gone = true
  }
  self.layout_marked_at(h, within=true)
  self.order_put_in(at, h)
  true
}

///|
/// Box `b` (of a node no slot that its holder `h` laid out) taken out of `h`'s, not all of them put again; `h` marked to
/// be laid out, the order to be made again there. Whether it was: not where `h` is due to be put again whole anyway or
/// does not hold it.
fn Tree::box_taken_out(self : Tree, h : Int, b : @flex.Node) -> Bool {
  guard h > 0 && h < self.nodes.length() && self.nodes[h].live && !self.nodes[h].boxes_due else { return false }
  let children = self.nodes[h].flex.children
  let i = match children.search_by(fn(c) { physical_equal(c, b) }) {
    Some(i) => i
    None => return false
  }
  guard self.box_one_more() else { return false }
  children.remove(i) |> ignore
  self.layout_marked_at(h, within=true)
  self.modals_marked()
  true
}

///|
/// How many boxes a change that makes many (Tree::holding_boxes) puts in or takes out one at a time before its holders
/// are put again whole as it ends instead (each one a search of what its holder lays out). Why 8: one at a time is a
/// search of the holder's boxes each, putting all again one walk of them; a change of a list's own (a row come, gone,
/// a message or two) is one to a few, well under it, and a page made with its rows is tens to thousands, over it at
/// once, put whole once. Not measured to the row: past a few, the searches add up to the walk they save.
let boxes_one_by_one_most : Int = 8

///|
/// Node `v` let go and taken out of what it holds.
fn View::drop(self : View, v : View) -> Unit {
  // (one of an id in it, in a change: kept till the change is committed whole, flying from there or let go of then)
  if self.tree.departs(self, v) {
    return
  }
  // (its box, as it laid one out: taken out of its holder's by itself below, not all of them put again)
  let own = match v.live() {
    Some(m) if !m.slot => Some(m.flex)
    _ => None
  }
  v.let_go()
  guard self.live() is Some(n) else { return }
  match n.kids.search(v.at) {
    Some(i) => n.kids.remove(i) |> ignore
    None => ()
  }
  let h = if n.slot { self.tree.box_holder(self.at) } else { self.at }
  match own {
    Some(b) if self.tree.box_taken_out(h, b) => ()
    _ => self.boxes_again()
  }
}

///|
/// Node `v` (one this holds) taken out of it, not let go: held by nothing, so not laid out, placed, drawn or pressed,
/// to be held again by another (View::take_in) or let go (a list's block kept to be made another's:
/// View::scrolls_window's `reused`). What the hand or the focus had in it lets go, as it would were it let go. What it
/// and what it holds bind is at rest (@signals.rest): what is held while it is read (a core's topic) held for none of
/// them, and nothing of it worked out again meanwhile; what this gives wakes it as it is held again, each binding that
/// let go of what it read, or whose reads changed meanwhile, worked out anew.
fn View::park(self : View, v : View) -> () -> Unit {
  guard self.live() is Some(n) && v.live() is Some(m) else { return fn() {  } }
  let wakes : Array[() -> Unit] = []
  self.tree.rest_in(v.at, wakes)
  // (laid out nowhere while held by nothing: no size told, as one just made, till it is laid out where it is held next;
  // so what reads it there reads that one, not the one it had here)
  match m.size_cell {
    Some(c) => c.set(None)
    None => ()
  }
  if self.tree.pointed_within_at(v.at) {
    self.tree.pointed_to(None)
  }
  self.tree.hold_lost_in(v.at)
  self.tree.focus_lost_in(v.at)
  self.tree.back_lost_in(v.at)
  match n.kids.search(v.at) {
    Some(i) => n.kids.remove(i) |> ignore
    None => ()
  }
  // (what takes a point in it held by what held it no more)
  if m.inputs_in != 0 {
    self.tree.inputs_count(self.at, -m.inputs_in)
  }
  m.parent = -1
  self.tree.touched(self.at)
  self.tree.order_marked_in(self.at)
  self.boxes_again()
  self.tree.modals_told(within=v.at)
  fn() {
    for w in wakes {
      w()
    }
  }
}

///|
/// What this and what it holds bind at rest (@signals.rest), left where it is: nothing of it worked out again, what is
/// held while it is read held for none of it; what this gives wakes it, each binding that let go of what it read, or
/// whose reads changed meanwhile, worked out anew. For what is out of sight and kept to be another's (a list's block
/// put by: View::scrolls_window's `reused`).
fn View::rests(self : View) -> () -> Unit {
  guard self.alive() else { return fn() {  } }
  let wakes : Array[() -> Unit] = []
  self.tree.rest_in(self.at, wakes)
  fn() {
    for w in wakes {
      w()
    }
  }
}

///|
/// What node `at` and what it holds bind, at rest (View::park), each's waking added to `wakes`.
fn Tree::rest_in(self : Tree, at : Int, wakes : Array[() -> Unit]) -> Unit {
  let n = self.nodes[at]
  match n.owner {
    Some(o) => wakes.push(@signals.rest(o))
    None => ()
  }
  for k in n.kids {
    self.rest_in(k, wakes)
  }
}

///|
/// Node `v`, held by nothing (View::park), held by this, after what it holds already: laid out, placed and drawn again
/// in its place there.
fn View::take_in(self : View, v : View) -> Unit {
  guard self.live() is Some(n) && v.live() is Some(m) && m.parent < 0 else { return }
  m.parent = self.at
  n.kids.push(v.at)
  if m.inputs_in != 0 {
    self.tree.inputs_count(self.at, m.inputs_in)
  }
  self.box_appended(v.at)
  if m.size_cell is Some(_) {
    self.tree.sizes_due = true
  }
  self.tree.layout_marked_at(v.at)
  self.tree.place_marked_at(v.at)
  self.tree.touched(v.at)
}

///|
/// `then`'s node while `when` holds, made as it comes to and let go as it stops (what it made with it too: its scope).
/// `leave`: it leaves over that long first (View::leave), and no shorter than a move it holds that holds its leaving
/// is (View::moved_by's `holds_leaving`): its end what that move says it is, at the size it is laid out. Down a column
/// it makes its way in and closes it as it goes (View::comes, View::goes), but as it is made with what holds it, or
/// `at_once`, or where it is said to go over a time (`leave`: its coming and going its own); along a
/// row the same across where `along_row` is said (Tree::along_row_at; with `at_once`, or where no row lays it out, a
/// fault).
#callsite(autofill(loc))
pub fn View::show(
  self : View,
  when : () -> Bool,
  then : (View) -> Unit,
  leave? : Double = 0.0,
  at_once? : Bool = false,
  along_row? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot(loc)
  slot.along_row_said(along_row, at_once, "show", loc)
  let had : Ref[View?] = Ref(None)
  // (the one leaving, shown again as it leaves: the same node, come back)
  let gone : Ref[View?] = Ref(None)
  // (made with what holds it: there at once)
  let first = Ref(true)
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
          _ => {
            let said = slot.tree.said_count
            let v = slot.box(then, loc~)
            // (one that made nothing: no way to make)
            let none = slot.tree.structural(v, said)
            if !first.val && !at_once && leave <= 0.0 && !none {
              slot.arrives(v)
            }
            had.val = Some(v)
          }
        }
        gone.val = None
      }
      (false, Some(v)) => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        had.val = None
        gone.val = if slot.goes(v, leave, at_once || leave > 0.0, swaps=true) { Some(v) } else { None }
      }
      _ => ()
    }
  })
  first.val = false
  slot.owns(stop) |> ignore
}

///|
/// A node made by `make` for what `which` is, made anew (the one before let go) as that changes, kept as it does not.
/// Down a column the new one makes its way from as tall as the one before was to as tall as it comes to (View::comes),
/// but `at_once`; along a row, where `along_row` is said, from as wide as the one
/// before was (Tree::along_row_at). `leave`: what it showed stays over its place, fading out over that long, what it
/// shows now seen once that is gone and its place holds it whole, its place one node making its way (pick_leave.mbt).
#callsite(autofill(loc))
pub fn[K : Eq] View::pick(
  self : View,
  which : () -> K,
  make : (View, K) -> Unit,
  at_once? : Bool = false,
  along_row? : Bool = false,
  leave? : Double = 0.0,
  loc~ : SourceLoc,
) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot(loc)
  slot.along_row_said(along_row, at_once, "pick", loc)
  // (what it showed leaving over a time as what it shows now waits to be seen: pick_leave.mbt)
  if leave > 0.0 {
    slot.pick_leaving(which, make, at_once, leave, loc)
    return
  }
  let had : Ref[(K, View)?] = Ref(None)
  let stop = slot.tree.structured(which, fn(k) {
    guard slot.alive() else { return }
    match had.val {
      Some((was, _)) if was == k => ()
      _ => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        // (and whether the one before was on its way from nothing or to it: the new one goes on with that, a box taking
        // no room holding nothing following it still, Style's come_fill)
        let (tall, fill) = match had.val {
          Some((_, v)) => {
            // (one over what holds it, or along a row it makes no way along, took none of the column's room)
            let (tall, fill) = if v.live() is Some(n) && slot.tree.makes_way(v.at) {
              (slot.tree.along_now(v.at, slot.tree.cause_now()), n.coming && n.flex.style.come_fill)
            } else {
              (0.0, false)
            }
            // (going in another's place: what it holds told it starts leaving, then let go)
            slot.tree.tell_leaving(v.at)
            slot.drop(v)
            (tall, fill)
          }
          None => (0.0 / 0.0, false)
        }
        let said = slot.tree.said_count
        let v = slot.box(fn(v) { make(v, k) }, loc~)
        let none = slot.tree.structural(v, said)
        if tall == tall && !at_once {
          if none && tall >= 0.5 {
            // (one that made nothing: its way closes from as tall as the one before was to nothing, and stays there, a
            // box taking no room holding nothing closing its padding with it (flex's come_fill, nothing_made))
            slot.comes(v, tall, 0.0, stays=true) |> ignore
          } else {
            slot.comes(v, tall, 1.0, fill~) |> ignore
          }
        }
        had.val = Some((k, v))
      }
    }
  })
  slot.owns(stop) |> ignore
}

///|
/// A node for each of `items` by its key, made as its key comes, kept while it stays, moved as the order changes, let
/// go as it goes. Each is given its item as a signal of its own, set again only as the item comes out otherwise (by
/// its data, not by which object it is): a row whose item is the same runs nothing. Down a column a row makes its way
/// in as it comes and closes it as it goes (View::comes, View::goes), but those made with what holds them, or
/// `at_once`, or where they are said to go over a time (`leave`: their coming and going their own); along a
/// row the same across where `along_row` is said (Tree::along_row_at). `keeps`: the keys whose rows are kept as they
/// leave, put by at rest and taken in again as their keys come back, read with the items (each_kept.mbt).
#callsite(autofill(loc))
pub fn[T : Eq, K : Hash + Eq] View::each(
  self : View,
  items : () -> Array[T],
  key : (T) -> K,
  row : (View, @signals.Signal[T]) -> Unit,
  leave? : Double = 0.0,
  at_once? : Bool = false,
  along_row? : Bool = false,
  keeps? : () -> Array[K],
  loc~ : SourceLoc,
) -> Unit {
  self.each_by(items, key, row, leave~, at_once~, along_row~, keeps?, loc~)
}

///|
/// View::each, each row made or let go by a change making its way or not as `way_of` says of its key, the row, and
/// whether it comes (else goes), asked of it then (a page's list's own rules: View::scrolls_window); none, as the
/// each's `at_once` says of all of them. `from_of`: how tall a row that comes making its way sets out from (none: from
/// nothing), asked of its key and its row as it sets out (a page's list's room under its last block taken first by it).
#callsite(autofill(loc))
fn[T : Eq, K : Hash + Eq] View::each_by(
  self : View,
  items : () -> Array[T],
  key : (T) -> K,
  row : (View, @signals.Signal[T]) -> Unit,
  leave? : Double = 0.0,
  at_once? : Bool = false,
  along_row? : Bool = false,
  way_of? : (K, View, Bool) -> Bool,
  from_of? : (K, View) -> Double,
  keeps? : () -> Array[K],
  loc~ : SourceLoc,
) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot(loc)
  let from = match from_of {
    Some(f) => f
    None => fn(_, _) { 0.0 }
  }
  slot.along_row_said(along_row, at_once, "each", loc)
  let rows : Map[K, (View, @signals.Signal[T])] = Map([])
  // (the rows leaving, by key: one whose key comes back as it leaves is the same row, come back)
  let gone_rows : Map[K, (View, @signals.Signal[T])] = Map([])
  // (the rows made with what holds them: there at once)
  let way = Ref(false)
  let ways = fn(k : K, v : View, coming : Bool) {
    way.val &&
    (match way_of {
      Some(f) => f(k, v, coming)
      None => true
    })
  }
  let kept : EachKept[K, T]? = keeps.map(EachKept::new)
  let change = fn(all) {
    slot.tree.holding_boxes(fn() { each_change(slot, all, rows, gone_rows, key, row, leave, ways, from, loc, kept) })
  }
  let stop = match kept {
    None => slot.tree.structured(items, change)
    // (what is kept read where the items are: a change of it is a change of them)
    Some(e) =>
      slot.tree.structured(fn() { (items(), (e.keys_of)()) }, fn(both) {
        e.keys = both.1
        change(both.0)
      })
  }
  way.val = !at_once && leave <= 0.0
  slot.owns(stop) |> ignore
  // (what it put by let go with it: held by nothing, let go by nothing else)
  match kept {
    Some(e) => slot.owns(fn() { e.let_go_all() }) |> ignore
    None => ()
  }
}

///|
/// What View::each does as its items are `all`: rows made for keys come, kept for keys staying, let go for keys gone,
/// put in their order.
fn[T : Eq, K : Hash + Eq] each_change(
  slot : View,
  all : Array[T],
  rows : Map[K, (View, @signals.Signal[T])],
  gone_rows : Map[K, (View, @signals.Signal[T])],
  key : (T) -> K,
  row : (View, @signals.Signal[T]) -> Unit,
  leave : Double,
  way : (K, View, Bool) -> Bool,
  from : (K, View) -> Double,
  loc : SourceLoc,
  kept : EachKept[K, T]?,
) -> Unit {
  guard slot.live() is Some(sn) else { return }
  slot.tree.work.structure = slot.tree.work.structure + 1
  let seen : Map[K, Bool] = Map([])
  let order : Array[Int] = []
  // (the rows made by this change, each its own box put in where it goes: each_place)
  let made_now : Array[Int] = []
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
          // (put by as its key left, kept: taken in again, no way in: each_kept.mbt)
          _ if each_kept_takes(slot, kept, k, it) is Some(r) => {
            rows[k] = r
            order.push(r.0.at)
          }
          _ => {
            gone_rows.remove(k)
            let item = @signals.signal(it, same=fn(a, b) { a == b })
            let said = slot.tree.said_count
            let v = slot.box(fn(v) {
              // (a row by its key: what is made in it known by it, View::row_place)
              v.tree.nodes[v.at].each_row = true
              row(v, item)
            }, loc~)
            let none = slot.tree.structural(v, said)
            if !none && way(k, v, true) {
              slot.comes(v, from(k, v), 1.0) |> ignore
            }
            rows[k] = (v, item)
            made_now.push(v.at)
            order.push(v.at)
          }
        }
    }
  }
  @signals.end_batch()
  let gone : Array[K] = []
  for k, r in rows {
    if !seen.contains(k) {
      gone.push(k)
      if !each_kept_parks(slot, kept, k, r) && slot.goes(r.0, leave, !way(k, r.0, false)) {
        gone_rows[k] = r
      }
    }
  }
  for k in gone {
    rows.remove(k)
  }
  // (those whose leaving ended, let go: forgotten)
  let ended = gone_rows.iter().filter(fn(e) { !e.1.0.alive() }).map(fn(e) { e.0 }).collect()
  for k in ended {
    gone_rows.remove(k)
  }
  each_place(slot, sn, order, made=made_now)
  each_kept_settle(kept)
}

///|
/// Whether `order` is `kids` with only the nodes of `made` put elsewhere (the others in the same order among
/// themselves): one walk of both together, `made` asked only where the two differ.
fn made_alone_moved(kids : Array[Int], order : Array[Int], made : Array[Int]) -> Bool {
  let mut i = 0
  let mut j = 0
  while i < kids.length() && j < order.length() {
    if kids[i] == order[j] {
      i = i + 1
      j = j + 1
    } else if made.contains(order[j]) {
      j = j + 1
    } else if made.contains(kids[i]) {
      i = i + 1
    } else {
      return false
    }
  }
  while i < kids.length() {
    if !made.contains(kids[i]) {
      return false
    }
    i = i + 1
  }
  while j < order.length() {
    if !made.contains(order[j]) {
      return false
    }
    j = j + 1
  }
  true
}

///|
/// What View::each and View::each_of do last as their rows change: the rows in `order` (their nodes), what is leaving
/// kept where it was, after what was before it; the slot's nodes put in that order where it differs. Where only rows
/// made by this change (`made`) are out of their place, the others in theirs, each made one's box is taken out and put
/// in again where it goes (Tree::box_taken_out, box_put_in), not all of the holder's put again.
fn each_place(slot : View, sn : Node, order : Array[Int], made? : Array[Int] = []) -> Unit {
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
    // (the others keep their order among themselves: only the made ones come where they go. More made than are put in
    // one at a time (each_change is always inside Tree::holding_boxes, whose cap that is): all put again at once, the
    // others not compared)
    let few = made.length() > 0 &&
      made.length() <= boxes_one_by_one_most &&
      made_alone_moved(kids, order, made)
    kids.clear()
    tree.marked_up(slot.at, true, true, false, false, true)
    for v in order {
      kids.push(v)
    }
    let h = tree.box_holder(made.get(0).unwrap_or(slot.at))
    let one_by_one = few &&
      made.iter().all(fn(v) {
        let m = tree.nodes[v]
        !m.slot && tree.box_taken_out(h, m.flex) && tree.box_put_in(v)
      })
    if !one_by_one {
      slot.boxes_again()
    }
  }
}

///|
/// A node for each of `items`, by the item itself: one object, one row (two alike in what they hold are two rows), made
/// as it comes, kept while that object stays in the list, moved as the order changes, let go as it goes (over `leave`,
/// coming back where the same object comes back as it leaves). For a list whose items are the rows themselves (what is
/// being written, each its own fields), which own nothing to be keyed by: each's by a key, this by which object. Down a
/// column its rows make and close their way as each's do, but `at_once`.
#callsite(autofill(loc))
pub fn[T] View::each_of(
  self : View,
  items : () -> Array[T],
  row : (View, T) -> Unit,
  leave? : Double = 0.0,
  at_once? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  guard self.alive() else { return }
  let slot = self.slot(loc)
  let rows : Array[(T, View)] = []
  // (the rows leaving: one whose object comes back as it leaves is the same row, come back)
  let gone_rows : Array[(T, View)] = []
  // (the rows made with what holds them: there at once)
  let way = Ref(false)
  let stop = slot.tree.structured(fn() { TheseItems(items()) }, fn(all) {
    slot.tree.holding_boxes(fn() { each_of_change(slot, all.0, rows, gone_rows, row, leave, way.val, loc) })
  })
  way.val = !at_once && leave <= 0.0
  slot.owns(stop) |> ignore
}

///|
/// The items View::each_of lists, the same as others where they are the same objects in the same order (never by what
/// they hold: theirs need no Eq).
priv struct TheseItems[T](Array[T])

///|
impl[T] Eq for TheseItems[T] with equal(a, b) {
  guard a.0.length() == b.0.length() else { return false }
  for i in 0..<a.0.length() {
    if !physical_equal(a.0[i], b.0[i]) {
      return false
    }
  }
  true
}

///|
/// What View::each_of does as its items are `all`: rows made for objects come, kept for those staying, let go for those
/// gone, put in their order; an object found among `rows` by being it (physical_equal).
fn[T] each_of_change(
  slot : View,
  all : Array[T],
  rows : Array[(T, View)],
  gone_rows : Array[(T, View)],
  row : (View, T) -> Unit,
  leave : Double,
  way : Bool,
  loc : SourceLoc,
) -> Unit {
  guard slot.live() is Some(sn) else { return }
  slot.tree.work.structure = slot.tree.work.structure + 1
  let now : Array[(T, View)] = []
  let order : Array[Int] = []
  @signals.start_batch()
  for it in all {
    match rows.search_by(fn(r) { physical_equal(r.0, it) }) {
      Some(i) => {
        now.push(rows[i])
        order.push(rows[i].1.at)
        rows.remove(i) |> ignore
      }
      None =>
        match gone_rows.search_by(fn(r) { physical_equal(r.0, it) }) {
          Some(i) if gone_rows[i].1.alive() && slot.tree.nodes[gone_rows[i].1.at].left_at >= 0.0 => {
            let (_, v) = gone_rows.remove(i)
            slot.come_back(v)
            now.push((it, v))
            order.push(v.at)
          }
          found => {
            if found is Some(i) {
              gone_rows.remove(i) |> ignore
            }
            let v = slot.box(fn(v) {
              // (a row by its object: what is made in it known by it, View::row_place)
              v.tree.nodes[v.at].each_row = true
              row(v, it)
            }, loc~)
            if way {
              slot.comes(v, 0.0, 1.0) |> ignore
            }
            now.push((it, v))
            order.push(v.at)
          }
        }
    }
  }
  @signals.end_batch()
  // (what is left of the rows before: gone)
  for r in rows {
    if slot.goes(r.1, leave, !way) {
      gone_rows.push(r)
    }
  }
  rows.clear()
  for r in now {
    rows.push(r)
  }
  // (those whose leaving ended, let go: forgotten)
  let ended = gone_rows.filter(fn(r) { r.1.alive() })
  gone_rows.clear()
  for r in ended {
    gone_rows.push(r)
  }
  each_place(slot, sn, order)
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
    Some(s) => s.set(s.untracked() + 1)
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
  // (it and what it holds told it starts leaving, once: then let go at once, or leaving over `ms`)
  self.tree.tell_leaving(v.at)
  if ms <= 0.0 {
    self.drop(v)
    return
  }
  guard v.live() is Some(n) else { return }
  let now = self.tree.cause_now()
  let p = gone_at(n, now)
  n.span = ms
  n.left_at = now - p * ms
  self.tree.said_marked(v.at, words=false, state=true)
  n.back_at = -1.0
  told_going(n)
  // (leaving, it takes no input: a finger held on it or in it let go of now)
  self.tree.hold_lost_in(v.at)
  self.tree.focus_lost_in(v.at)
  self.tree.back_lost_in(v.at)
  self.tree.modals_told(within=v.at)
  self.tree.due_leaving(v.id())
  // (one of an id in it: what may fly from it as the change is committed whole, shared.mbt)
  self.tree.departs_leaving(v)
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
  // (it and what it holds told it is back: told anew as it next starts leaving)
  self.tree.tell_back(v.at)
  self.tree.said_marked(v.at, words=false, state=true)
  told_going(n)
  // (beside its anchor again, where that is now: View::beside)
  if n.beside is Some(_) {
    self.tree.place_marked_at(v.at)
  }
  // (a modal layer back: over what is held again)
  self.tree.modals_told(within=v.at)
  // (closing its way: what it binds woken, its way made again from as tall as it is)
  if n.coming {
    match n.come_wake {
      Some(wake) => {
        n.come_wake = None
        wake()
      }
      None => ()
    }
    self.comes(v, self.tree.along_now(v.at, now), 1.0) |> ignore
  }
  self.tree.marked()
}

///|
/// Node `v`, one this slot's show, pick or each makes or lets go, making its way from `from` tall (points) to `to` of
/// what it comes to (1: all of it; 0: none) from its cause's moment, on a Move's way as long as how far that is
/// (Style's come_*, flex's move.mbt): laid out so as the clock goes, cut at its edges, what is under it in its column
/// moved by as much and the gap before it opening with it, in the same layout (the user, 2026-11-09: what comes or goes
/// makes its way in or closes it, the framework's, not each page's). Only where it is laid out in its turn down a
/// column, or along a row where its structure said so (Tree::makes_way: its width's way, Style's come_across), the
/// tree has been drawn, motion is not reduced and nothing of it is shared by an id: elsewhere nothing, and
/// false. What scrolls in it makes its way as anything does, what it holds laid out once at the size it comes to (flex's
/// come_*: its room, how far it can go and the blocks a list makes in it as at rest all the way); a page or a pane,
/// grown to what the column leaves it, is not laid out in its turn (Tree::in_column), and comes at once. `stays`: closing to nothing, it stays there once its way
/// ends (a pick's case that made nothing), at rest. `fill`: on from the way of one before it in its place that was from
/// nothing or to it (Style's come_fill).
fn View::comes(
  self : View,
  v : View,
  from : Double,
  to : Double,
  stays? : Bool = false,
  fill? : Bool = false,
) -> Bool {
  let tree = self.tree
  // (what is shared by an id flies to its place instead: View::shared)
  guard self.alive() &&
    v.live() is Some(n) &&
    tree.last_w >= 0.0 &&
    !@signals.untracked(tree.motion_reduced) &&
    tree.makes_way(v.at) &&
    !tree.holds_shared(v.at) &&
    // (made or let go because its block was given another key: at once, as were the block made anew, key_taken.mbt)
    !key_taken.val else {
    return false
  }
  let st = n.flex.style
  let at = tree.cause_now()
  // (along a row its structure said so: its width's way, Style's come_across)
  st.come_across = !tree.in_column(v.at)
  // (set off again on its way: from where that way had it at this moment and as fast, not from rest, stopped dead as
  // it turned. Its end and how tall it goes to are known by then whether a frame was drawn since or not: going, it goes
  // to nothing, said with it (below); coming, it is measured as the change that said it is over (after_flush, below).
  // Only one said in this same change is not known yet: from where it was laid out last, at rest, as no frame can come
  // between them. Nothing is laid out or measured here, in the middle of a change: that leaves stale measures or
  // half-run bindings (the coordinator of the migration, 2026-11-10))
  let (from, speed) = match (n.coming, @flex.come_state(st, at)) {
    (true, Some((tall, speed))) => (tall, speed)
    _ => (from, 0.0)
  }
  // (from nothing or to nothing, or turned back on such a way: what a box taking no room holding nothing opens or
  // closes its padding by (flex's come_fill, Style's gone_empty); not one in another's place, from as tall as that was)
  st.come_fill = to <= 0.0 || from <= 0.0 || (n.coming && st.come_fill) || fill
  // (a structure's way a Move, whatever a height change declared said before: View::resizes says its own after)
  st.come_spec = None
  st.come_from = from
  st.come_v = speed
  st.come_to = to
  // (how tall it goes to: nothing, or what it comes to, its layout's)
  st.come_goal = if to <= 0.0 { 0.0 } else { 0.0 / 0.0 }
  st.come_at = at
  st.come_now = at
  // (going: as long as its way to nothing; coming, as far as what it comes to, the first time it is laid out)
  st.come_ends = if to <= 0.0 { at + @flex.come_way_ms(from, speed, 0.0) } else { 0.0 / 0.0 }
  st.come_plan = st.come_goal
  n.coming = true
  // (one way with what else comes or goes in its column at this moment and what is on its way there now)
  tree.come_group_join(v, st, at)
  n.look.clips = true
  (n.come_off)()
  n.come_off = fn() {  }
  let said = match n.come_said {
    Some(s) => s
    None => {
      let s = @signals.signal(0)
      n.come_said = Some(s)
      let gen = n.gen
      let vat = v.at
      // (the clock followed by the tree, not by what it holds: what rests as it closes its way does not rest this)
      let owner = @signals.set_owner(None)
      let stop = tree.queued(
        fn() {
          s.get() |> ignore
          if tree.nodes[vat].coming {
            Some(tree.drawn_at())
          } else {
            None
          }
        },
        fn(t) {
          let m = tree.nodes[vat]
          if !m.live || m.gen != gen {
            return
          }
          // (the clock set to a change's moment and back again as things are measured or settled then
          // (Tree::measured_now) moves no way: laid out where the frame has it, not again at that moment's and again
          // at the frame's, each laying out what reads it anew)
          match t {
            Some(t) if t != tree.frame_ms && m.flex.style.come_now == m.flex.style.come_now => return
            _ => ()
          }
          let was = m.flex.style.come_now
          let now = match t {
            Some(t) => t
            None => 0.0 / 0.0
          }
          if now == was || (now != now && was != was) {
            return
          }
          m.flex.style.come_now = now
          m.look.clips = m.clips_said || m.coming
          tree.layout_marked_at(vat)
          tree.look_marked_at(vat)
          // (what draws its ground by how tall this shows: drawn again by it, View::shown_by)
          match tree.shown_followers.get(vat) {
            Some(fs) =>
              for f in fs {
                tree.place_marked_at(f)
              }
            None => ()
          }
        },
      )
      @signals.set_owner(owner) |> ignore
      n.props[Comes.ord()] = stop
      s
    }
  }
  said.set(said.untracked() + 1)
  tree.layout_marked_at(v.at)
  tree.look_marked_at(v.at)
  if to >= 1.0 {
    // (there as its way, as long as a Move as far as it is laid out first, ends: Style's come_ends)
    @signals.after_flush(fn() {
      guard v.live() is Some(m) && m.coming && st.come_at == at && st.come_to >= 1.0 else { return }
      tree.measured_now()
      let ends = if st.come_ends == st.come_ends { st.come_ends } else { at + @flex.move_most_ms }
      m.come_off = v.at_moment(ends, fn() { come_done(tree, v, m) })
      tree.hand_at_end(ends)
    })
  } else if stays {
    // (closing to nothing and staying, a pick's case that made nothing: at rest there as its way ends)
    n.come_off = v.at_moment(st.come_ends, fn() { come_done(tree, v, n) })
    tree.hand_at_end(st.come_ends)
  }
  true
}

///|
/// Node `v` (its style `st`) set making or closing its way in its column at moment `at`: in the one way of what comes or
/// goes there at that moment (flex's ComeGroup, the user 2026-11-03 and 2026-11-09: what comes while others go goes with
/// what is left of theirs as one; 处理中 and the answer change places in one move). Only noted here: once the change is
/// made (Tree::come_group_settle) the group is said, or none is where it would hold one alone.
fn Tree::come_group_join(self : Tree, v : View, st : @flex.Style, at : Double) -> Unit {
  // (its own way from here, whatever group it went in before: a way said once is that way's alone)
  st.come_group = None
  let own = self.column_of(v.at)
  guard own >= 0 else { return }
  // (down a column inside a block of a page's list whose insides join it: the list's group, and kept among what is on
  // its way in its blocks till it is let go or its way ends; along a row, its row's own)
  let col = if st.come_across || self.list_inner.is_empty() {
    own
  } else {
    let list = self.list_of(own)
    match self.list_inner.get(list) {
      Some((joins, inner)) if list != own => {
        // (those let go or come to their way's end forgotten as one more is kept)
        let kept = inner.filter(fn(w) { w.live() is Some(m) && m.coming && w.at != v.at })
        inner.clear()
        inner.append(kept)
        inner.push(v)
        if joins {
          list
        } else {
          own
        }
      }
      _ => own
    }
  }
  let (_, views) = match self.come_groups.get(col) {
    Some((g, views)) if g.at == at && !g.set => (g, views)
    _ => {
      let g = @flex.ComeGroup::new(at)
      let views : Array[View] = []
      self.come_groups[col] = (g, views)
      @signals.after_flush(fn() { self.come_group_settle(col, g, views) })
      (g, views)
    }
  }
  if !views.iter().any(fn(w) { w.at == v.at }) {
    views.push(v)
  }
}

///|
/// The held column of the page's list whose way what comes or goes down column `col` joins: the one whose foot it is in
/// (Tree's list_feet), else the one whose blocks it is in (Tree::list_holding); `col` where none is (lists do not nest:
/// one at most).
fn Tree::list_of(self : Tree, col : Int) -> Int {
  // (in a list's foot: that list's held column, the foot being pinned on its node, not under it)
  if !self.list_feet.is_empty() {
    let mut p = col
    while p >= 0 {
      match self.list_feet.get(p) {
        Some(held) => return held
        None => ()
      }
      p = self.nodes[p].parent
    }
  }
  self.list_holding(col)
}

///|
/// The held column of the page's list (Tree's list_inner) that column `col` is or lies in; `col` where none is (lists
/// do not nest: one at most).
fn Tree::list_holding(self : Tree, col : Int) -> Int {
  let mut p = col
  while p >= 0 {
    if self.list_inner.contains(p) {
      return p
    }
    p = self.nodes[p].parent
  }
  col
}

///|
/// The held column `at` of a page's list (View::scrolls_window) keeping what its blocks hold set coming or going, and
/// where `joins`, joining it to its way, from now till `self` goes: what comes or goes down a column in one of them
/// goes in its group (Tree::come_group_join).
fn View::list_keeps_inner(self : View, at : Int, joins : Bool) -> Unit {
  let tree = self.tree
  tree.list_inner[at] = (joins, [])
  self.owns(fn() { tree.list_inner.remove(at) }) |> ignore
}

///|
/// What the blocks of the page's list held in `at` hold that was set coming or going at moment `at_ms`, and is still
/// on its way: none where it keeps none (Tree's list_inner).
fn Tree::list_inner_at(self : Tree, at : Int, at_ms : Double) -> Array[View] {
  match self.list_inner.get(at) {
    Some((_, inner)) => inner.filter(fn(w) { w.live() is Some(m) && m.coming && m.flex.style.come_at == at_ms })
    None => []
  }
}

///|
/// The nodes laid out in column `col` in their turn: what it holds, through the slots holding them.
fn Tree::column_items(self : Tree, col : Int) -> Array[Int] {
  let out = []
  let walk : Ref[(Int) -> Unit] = Ref(fn(_) {  })
  walk.val = fn(at : Int) {
    for k in self.nodes[at].kids {
      if self.nodes[k].slot {
        (walk.val)(k)
      } else {
        out.push(k)
      }
    }
  }
  (walk.val)(col)
  out
}

///|
/// Group `g` of column `col`, its change made: what was set off at its moment and is still coming or going (`views`),
/// and what was on its way down the column then, set off again from where its way had it and as fast; two or more, they
/// are measured at its moment and the group's way said (flex's come_group_set), each in it then resting and let go as
/// that way ends. One alone is left its own way, untouched. Set off as a layout is under way (by what a room's width
/// makes there, View::by_room), what comes is not measured till that layout lays it out: the group is said once it has,
/// in the same pass (`waited`), never of heights not known yet (each in it laid out none all the way, then all of it
/// at its end: a chat's rows' gaps picked by its list's width, 2026-11-12).
fn Tree::come_group_settle(
  self : Tree,
  col : Int,
  g : @flex.ComeGroup,
  views : Array[View],
  waited? : Bool = false,
) -> Unit {
  guard !g.set else { return }
  let at = g.at
  // (set off at its moment and not let go or set off again since: still of it)
  let live = views.filter(fn(w) {
    w.live() is Some(m) && m.coming && m.flex.style.come_at == at
  })
  // (what comes measured at the group's moment, how tall it goes to known: come_height's; in the middle of a layout,
  // none is, and the group waits for it)
  self.measured_now()
  if !waited &&
    live.iter().any(fn(w) {
      w.live() is Some(m) && m.flex.style.come_to > 0.0 && m.flex.style.come_goal != m.flex.style.come_goal
    }) {
    self.once_laid_out(fn() { self.come_group_settle(col, g, views, waited=true) })
    return
  }
  // (one coming still not measured once that layout is done (laid out nowhere: its room shut) left out of it, its own
  // way, its end worked out as it is first laid out: no group is said of a height that is no number)
  let live = live.filter(fn(w) {
    w.live() is Some(m) && !(m.flex.style.come_to > 0.0 && m.flex.style.come_goal != m.flex.style.come_goal)
  })
  match self.come_groups.get(col) {
    Some((h, _)) if physical_equal(h, g) => self.come_groups.remove(col)
    _ => ()
  }
  // (what is on its way down the column now, set off before: in it, and where it is a page's list's, in its blocks,
  // those of them let go or come to their way's end forgotten)
  let under_way = []
  let on_way = fn(k : Int) {
    if live.iter().any(fn(w) { w.at == k }) || under_way.contains(k) {
      return
    }
    let m = self.nodes[k]
    guard m.live && m.coming else { return }
    let ms = m.flex.style
    if ms.come_at < at && at < ms.come_ends {
      under_way.push(k)
    }
  }
  for k in self.column_items(col) {
    on_way(k)
  }
  match self.list_inner.get(col) {
    Some((true, inner)) => {
      let kept = inner.filter(fn(w) {
        w.live() is Some(m) &&
        m.coming &&
        !(m.flex.style.come_ends == m.flex.style.come_ends && m.flex.style.come_ends <= at)
      })
      inner.clear()
      inner.append(kept)
      for w in inner {
        on_way(w.at)
      }
    }
    _ => ()
  }
  // (one alone goes its own way, as it always did)
  if live.length() + under_way.length() < 2 {
    return
  }
  for k in under_way {
    let ms = self.nodes[k].flex.style
    guard @flex.come_state(ms, at) is Some((h, sp)) else { continue }
    ms.come_from = h
    ms.come_v = sp
    ms.come_at = at
    ms.come_now = at
    ms.come_plan = ms.come_goal
    ms.come_ends = at + @flex.come_way_ms(h, sp, ms.come_goal)
    ms.come_group = None
    live.push(self.handle(k))
  }
  g.members.clear()
  for w in live {
    if w.live() is Some(m) {
      g.members.push(m.flex.style)
    }
  }
  // (what comes measured at the group's moment, how tall it goes to known: come_height's)
  self.measured_now()
  @flex.come_group_set(g)
  guard g.set else { return }
  for w in live {
    guard w.live() is Some(m) else { continue }
    let st = m.flex.style
    if st.come_to >= 1.0 {
      (m.come_off)()
      m.come_off = w.at_moment(st.come_ends, fn() { come_done(self, w, m) })
      self.hand_at_end(st.come_ends)
    } else if m.left_at >= 0.0 {
      // (leaving as long as the group's way: let go as it ends)
      m.span = dmax(st.come_ends - m.left_at, 0.0)
    }
    self.layout_marked_at(w.at)
  }
}

///|
/// The way of node `m` (of `v`) there: laid out as it is, cut as it says, and what followed the clock for it let go.
fn come_done(tree : Tree, v : View, m : Node) -> Unit {
  let st = m.flex.style
  m.coming = false
  m.come_off = fn() {  }
  st.come_now = 0.0 / 0.0
  // (all of what it comes to, the gap before it whole: as its column lays it out from here, whether it is measured
  // again or laid out as it said it is)
  st.come_k = 1.0
  m.look.clips = m.clips_said
  m.come_said = None
  match m.props.get(Comes.ord()) {
    Some(stop) => {
      m.props.remove(Comes.ord())
      stop()
    }
    None => ()
  }
  tree.layout_marked_at(v.at)
  tree.look_marked_at(v.at)
}

///|
/// Node `v`, one this slot's show or each lets go: down a column (View::comes) closing its way as it leaves over as
/// long as that takes and no shorter than `ms` (View::leave), what it and what it holds bind at rest meanwhile where
/// nothing of it was said to go over a time (`ms` 0: drawn as it was, nothing of it worked out again); else, or
/// `at_once`, leaving over `ms`. Whether it is still there, leaving.
fn View::goes(self : View, v : View, ms : Double, at_once : Bool, swaps? : Bool = false) -> Bool {
  // (it and what it holds told it starts leaving before any of it is put to rest (View::rests, below))
  self.tree.tell_leaving(v.at)
  if !at_once && v.live() is Some(n) {
    // (as tall as it is at this moment: on its way, where that way has it (flex's come_state), whether a frame has laid
    // it out since or not; else as it was laid out last)
    let tall = self.tree.along_now(v.at, self.tree.cause_now())
    // (nothing tall, or wide along a row: nothing to close)
    if tall < 0.5 || !self.tree.makes_way(v.at) {
      self.leave(v, ms)
      return ms > 0.0
    }
    // (a show's, where another came in the same column at the same moment: that one in its place, from as tall as this)
    if swaps {
      match self.tree.swapped(v, false) {
        Some(w) =>
          if w.node.alive() {
            w.slot.comes(w.node, tall, 1.0) |> ignore
            self.leave(v, ms)
            return ms > 0.0
          }
        None => ()
      }
    }
    if self.comes(v, tall, 0.0) {
      // (as long as its way closing: on from as fast as it opened, where it was opening)
      let way = n.flex.style.come_ends - self.tree.cause_now()
      if ms <= 0.0 && n.come_wake is None {
        n.come_wake = Some(v.rests())
      }
      self.leave(v, if ms > way { ms } else { way })
      if swaps {
        self.tree.swaps.push({ slot: self, node: v, column: self.tree.column_of(v.at), at: self.tree.cause_now(), tall, going: true })
      }
      return true
    }
  }
  self.leave(v, ms)
  ms > 0.0
}

///|
/// Whether node `at` or what it holds is shared by an id (View::shared).
fn Tree::holds_shared(self : Tree, at : Int) -> Bool {
  // (none shared at all: nothing walked)
  if self.shared_live.is_empty() {
    return false
  }
  let n = self.nodes[at]
  n.share is Some(_) || n.kids.iter().any(fn(k) { self.holds_shared(k) })
}

///|
/// One a show set making or closing its way (Tree's swaps): the slot it is in, it, the column it is laid out in, the
/// moment, as tall as it was where it goes.
priv struct Swap {
  slot : View
  node : View
  column : Int
  at : Double
  tall : Double
  going : Bool
}

///|
/// The node laying out node `at` (past the slots holding it).
fn Tree::column_of(self : Tree, at : Int) -> Int {
  let mut p = self.nodes[at].parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  p
}

///|
/// The one set making or closing its way (`going`) in node `v`'s column at the moment of this change, taken from the
/// swaps; those of another moment forgotten.
fn Tree::swapped(self : Tree, v : View, going : Bool) -> Swap? {
  let now = self.cause_now()
  self.swaps.retain(fn(w) { w.at == now && w.node.alive() })
  let col = self.column_of(v.at)
  // (only one next to it: one with something laid out between them is in no place of its, each making its own way)
  match
    self.swaps.search_by(fn(w) {
      w.going == going && w.column == col && self.next_in_column(col, w.node.at, v.at)
    }) {
    Some(i) => Some(self.swaps.remove(i))
    None => None
  }
}

///|
/// Whether nodes `a` and `b`, laid out in column `col` (past the slots holding them), stand next to each other in it:
/// nothing of the column laid out between them that takes room (a box over what holds it, or a slot holding none such,
/// is none).
fn Tree::next_in_column(self : Tree, col : Int, a : Int, b : Int) -> Bool {
  // (each as the column's own item: the slot holding it there, or it)
  let item = fn(at : Int) {
    let mut q = at
    while q >= 0 && self.nodes[q].parent != col {
      q = self.nodes[q].parent
    }
    q
  }
  let (ia, ib) = (item(a), item(b))
  guard ia >= 0 && ib >= 0 else { return false }
  let kids = self.nodes[col].kids
  match (kids.search(ia), kids.search(ib)) {
    (Some(i), Some(j)) => {
      let (lo, hi) = if i < j { (i, j) } else { (j, i) }
      for k in (lo + 1)..<hi {
        if self.takes_room(kids[k]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Whether node `at` takes room in the column laying it out: a slot, as what it holds does; else unless it is over what
/// holds it.
fn Tree::takes_room(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  if !n.live {
    false
  } else if n.slot {
    n.kids.iter().any(fn(k) { self.takes_room(k) })
  } else {
    n.flex.style.position != @flex.PositionType::Absolute
  }
}

///|
/// Node `v`, made by this slot's show down a column: in the place of one closing its way in the same column at the
/// same moment (the other of a show and its opposite: what is shown in another's place), that one let go of at once and
/// this one's way from as tall as it was, as a pick's; else its way made from nothing.
fn View::arrives(self : View, v : View) -> Unit {
  match self.tree.swapped(v, true) {
    Some(w) => {
      w.slot.leave(w.node, 0.0)
      self.comes(v, w.tall, 1.0) |> ignore
    }
    None =>
      if self.comes(v, 0.0, 1.0) {
        self.tree.swaps.push({
          slot: self,
          node: v,
          column: self.tree.column_of(v.at),
          at: self.tree.cause_now(),
          tall: 0.0,
          going: false,
        })
      }
  }
}

///|
/// Whether node `at` is laid out in its turn down a column, as tall as it comes to: not over what holds it nor grown,
/// what lays it out (past the slots holding it) a column: in a page's list's block too (what the block holds makes its
/// way as anywhere; the blocks themselves come and go as the list scrolls, at once: View::scrolls_window).
fn Tree::in_column(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  // (over what holds it, or as tall as the column leaves it (grown): no way of its own to make)
  if n.flex.style.position == @flex.PositionType::Absolute || n.flex.style.grow > 0.0 {
    return false
  }
  let mut p = n.parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  p >= 0 && self.nodes[p].flex.style.direction == @flex.FlexDirection::Column
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
  // (the clock followed through the framework's entry while it goes (View::drawn_while: leaving, not all gone yet;
  // coming back, not all back), its end read once it is there: no read of the time of the binding's own)
  let t = self.drawn_while(fn(at) {
    let f = gone_at(n, at)
    if n.left_at >= 0.0 {
      f < 1.0
    } else {
      f > 0.0
    }
  })
  gone_at(n, t)
}

///|
/// When its own leaving ends, as it was told to leave (View::leave: let go then), -1 where it is not leaving.
pub fn View::leaves_at(self : View) -> Double {
  guard self.live() is Some(n) else { return -1.0 }
  if n.left_at >= 0.0 {
    self.tree.leave_ends(self.at)
  } else {
    -1.0
  }
}

///|
/// Whether node `holder` is node `at` or holds it.
fn Tree::holds_at(self : Tree, holder : Int, at : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    if i == holder {
      return true
    }
    i = self.nodes[i].parent
  }
  false
}

///|
/// Whether it is leaving, or what holds it is: no longer pressed. Its value true from the moment that starts, wherever
/// it is read (as it is drawn, in a handler). Followed by what reads it outside what is leaving (told as that starts
/// leaving and as it comes back: what View::going reads, not the clock); what is leaving down a column on a Move is at
/// rest (View::rests), what reads it there told nothing: what is to be done at that moment is View::on_leaving's.
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
/// Whether node `at` is held from the root down: it and each that holds it held by another up to the root. A node put by
/// (View::park) and what it holds are not, till it is taken in again (View::take_in): none of it is in the scene, laid
/// out, placed, drawn, pressed, focused or read out, by nothing but its not being reached from the root.
/// Nor is a shared node's old copy on its flight (Tree::paired takes it out of what held it): its flight draws it
/// where the flight is, and of the tree's it has no place to answer with.
fn Tree::held_from_root(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i > 0 {
    i = self.nodes[i].parent
  }
  i == 0
}

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
/// When node `at`'s leaving or coming back ends (-1: neither): its leaving no sooner than the moves it holds that hold
/// it are over (View::moved_by's `holds_leaving`), each as it ends at the size it is laid out.
fn Tree::leave_ends(self : Tree, at : Int) -> Double {
  let n = self.nodes[at]
  if n.left_at >= 0.0 {
    let mut end = n.left_at + n.span
    if self.leave_holders.length() > 0 {
      self.leave_holders.retain(fn(id) { self.alive_id(id) && self.nodes[id.at].moved_holds is Some(_) })
      for id in self.leave_holders {
        let m = self.nodes[id.at]
        guard m.moved_holds is Some(ends) && self.holds_at(at, id.at) else { continue }
        let e = @signals.untracked(fn() { ends(m.flex.width, m.flex.height) })
        if e > end {
          end = e
        }
      }
    }
    end
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
/// Which timer the soonest due is (Tree::wake_waited): where it was said, for a timer said once (View::at_moment's
/// caller); "" for the rest. What tells one that keeps saying itself again from others that each come once.
pub fn Tree::wake_waited_by(self : Tree) -> String {
  let mut soonest = -1.0
  let mut by = ""
  for d in self.timeline {
    let at = match d {
      Steps(s, _) => if s.live.val && s.k < s.count { stepped_at(s, s.count - 1) } else { -1.0 }
      Once(o, _) if o.later => -1.0
      Holds(h, _) if h.later => -1.0
      _ => self.due_at(d)
    }
    if at >= 0.0 && (soonest < 0.0 || at < soonest) {
      soonest = at
      by = match d {
        Once(o, _) => o.by
        _ => ""
      }
    }
  }
  by
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
      Holds(h, _) if h.later => -1.0
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
/// The time now, as a change is told (the host's, else the clock's).
fn Tree::time_now(self : Tree) -> Double {
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
/// An input from outside (a press, a wheel, a back gesture) handled at `at` by `f`, as Tree::event takes an event, the
/// tree brought to its moment first outside its batch (Tree::event_said's `brings`): what `f` reaches is where the frame
/// of that moment draws it.
pub fn Tree::input(self : Tree, at : Double, f : () -> Unit) -> Unit {
  self.event_said(at, fn() {  }, f, brings=true)
}

///|
/// One event at `at` whose own facts (`said`: what it came by, as a host says it) are so as of its moment: what was due
/// by then done first (seeing what was so before it), then `said` committed and told (what follows it brought to it,
/// the event's moment their cause), then `f` taken as Tree::event takes it, finding things as they are with it. Inside
/// another event, both in that one's, as one change.
///
/// An input (`brings`: a pointer's, a wheel's, a back gesture's; ui's view_event `input`) finds the tree brought to its
/// moment between `said` and `f`, outside both batches (Tree::bring_to), as a frame lays it out: what that layout tells
/// (a list's slots set, read by bindings through what is worked out of them) is told and laid out in it, not marked in
/// `f`'s batch and left there while `f` finds what it reaches (a row 120 lower than drawn, an input 88 ms after the
/// last frame, 2026-11-12). A key and words typed bring nothing of their own (press_stays_ways_test's Page Down).
pub fn Tree::event_said(self : Tree, at : Double, said : () -> Unit, f : () -> Unit, brings? : Bool = false) -> Unit {
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
  if brings {
    self.bring_to(at)
  }
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
  // (what was let go of and made in it with one id paired, as it is committed whole: shared.mbt)
  if was < 0.0 {
    self.pairs_now()
  }
  self.cause_at = was
  self.change_ended()
  // (where things stand once it is told whole, for the next change: Tree::settle_after_change)
  if was < 0.0 {
    self.settle_now(at)
    self.hand_now()
    // (what the page's lists have in sight owed as of this change, an input's or data's: not a binding's the clock or a
    // frame's laying out told (Tree::at_cause's), nor the one that tells it)
    if !self.sights_telling {
      self.sight_owe(at)
    }
    self.sights_now()
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
  @signals.after_flush(fn() {
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
  let shown = self.clock.untracked()
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
  self.standing = false
  self.withins_restored()
  // (what the bindings it ran asked for, a change told outside every event so ending: Tree::change_ended)
  self.change_ended()
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
  Holds(Hold, Int)
}

///|
/// What holds from each event till `ms` after it (View::holds_for): whether it holds now (`on`, told as it starts and
/// as it ends), the moment it ends (`until`, set again in place by each event: its one due on the timeline, there exactly
/// while it is not -1); `live` while its node is.
priv struct Hold {
  ms : Double
  on : @signals.Signal[Bool]
  mut until : Double
  live : Ref[Bool]
  /// not waited for (View::holds_for's `later`)
  later : Bool
}

///|
/// Something to be done once at a moment (View::at_moment): `f`, at `at`, if still `live`.
priv struct Once {
  at : Double
  f : () -> Unit
  live : Ref[Bool]
  /// not waited for (View::at_moment's `later`)
  later : Bool
  /// where it was said (View::at_moment's caller): which timer it is (Tree::wake_waited_by)
  by : String
}

///|
/// What goes by steps (View::steps): `step` run with each step's number and moment, at the one clock's ticks at
/// `per_second` from tick `first`, `count` of them, `k` taken; stopped (`live`), no more.
priv struct Stepper {
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
        self.leave_ends(id.at)
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
    Holds(h, _) => if h.live.val && h.until >= 0.0 { h.until } else { -1.0 }
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
      Holds(h, _) => !physical_equal(h.live, live)
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
  if !self.advancing && upto > self.clock.untracked() {
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
        Holds(_, s) => s
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
        // (a change at its moment (View::at_moment's): what the page's lists have in sight owed as of then)
        self.sight_owe(next_at)
      }
      Holds(h, _) => {
        self.timeline.remove(next) |> ignore
        h.until = -1.0
        @signals.start_batch()
        h.on.set(false)
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
    if was < 0.0 {
      self.pairs_now()
    }
    self.cause_at = was
    self.change_ended()
    // (where things stand once it is told whole, as of its moment, for the next change: Tree::settle_after_change)
    if was < 0.0 {
      self.settle_now(next_at)
      self.hand_now()
      self.sights_now()
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
    None => self.clock.untracked()
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
    // (the window's new size is the host's change, as of this frame: what a still pointer is over worked out again)
    if !self.hand_owed || upto > self.hand_owed_at {
      self.hand_owed_at = upto
    }
    self.hand_owed = true
    self.sight_owe(upto)
  }
  self.brought(upto)
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
    // (what that layout told in turn (a page's list's fill telling its blocks' heights to what places them), in the
    // change's batch: pulled and laid out again here, as a frame's passes lay out what its layout tells (its bindings
    // run as told there, told_passes_most of them one inside another); else a press found things where they stood
    // before it told: a block grown 154 since the frame, its slot as tall as counted then, the rows under it that much
    // higher than drawn, and the row four under the one pressed taken for it, 2026-11-12)
    let mut passes = 0
    while self.pulls_marked.length() > 0 && passes < told_passes_most {
      passes = passes + 1
      self.pull()
      self.brought(at)
    }
  }
}

///|
/// What was marked done, at the clock's now (Tree::frame, Tree::bring_to).
fn Tree::brought(self : Tree, upto : Double) -> Unit {
  // what is due by now done (and the logic at `upto`, nothing due or not: what is said next is of then)
  self.advance(upto)
  let laying_was = self.laying
  self.laying = true
  self.laid_out(upto)
  self.laying = laying_was
  // (what was asked for in its layout, where it still stands: View::image_ask; in a change, as it is committed)
  if !self.in_change() {
    self.images_asked_now()
  }
  // (a binding told and left for a frame nobody was asked for (told again by every layout of the passes it is given, or
  // told where no pass is made): a fault, never drawn a frame late or not at all, nor laid out again without end; a
  // frame asked for it where faults do not stop)
  if !self.due && !self.bindings_due.is_empty() {
    fault("a binding told as the window's tree was laid out, left with no frame asked for it: told again by each of the \{told_passes_most} passes given to what a layout tells, or where none is made")
    self.marked()
  }
  // (what a change told in this frame's bindings left under a still pointer, at that change's moment)
  self.hand_now()
  self.sights_now()
}

///|
/// How many passes, one inside another, the bindings a layout told are given (Tree::laid_out), each laid out
/// again by what they set: one is what a list's fill taking blocks needs; more, something told by every layout it is in.
let told_passes_most : Int = 4

///|
/// What was marked laid out and drawn at `upto`, the logic not moved: no moment's work done, nothing due run (for where
/// things are as an event finds them in the middle of its change: Tree::laid_now).
fn Tree::laid_out(self : Tree, upto : Double) -> Unit {
  let w = self.last_w
  let h = self.last_h
  if !self.due {
    return
  }
  // the bindings whose reads changed since, each once, in the order they were told (what they make runs its own now,
  // what they set again marks what it marks)
  let t_bound = self.part_began()
  self.draining += 1
  let mut i = 0
  while i < self.bindings_due.length() {
    // (one run already, pulled as something asked at once: not again)
    let b = self.bindings_due[i]
    if b.queued {
      (b.run)()
    }
    i = i + 1
  }
  self.draining -= 1
  self.bindings_due.clear()
  // (those marked that ran so, no longer to be pulled; one marked in a change not ended yet still is)
  let still = self.pulls_marked.filter(fn(b) { b.live && b.marked })
  self.pulls_marked.clear()
  self.pulls_marked.append(still)
  self.part_ended("tree bindings", t_bound)
  let t_laid = self.part_began()
  // (laid out in a change holding its boxes, a host drawing a frame at once as it is told of one: those put first)
  self.boxes_flushed()
  // (what goes beside another placed by it only where anything was laid out or placed again: View::beside)
  let placing = self.layout_due || !self.places_due.is_empty()
  if self.layout_due {
    // (what is laid out may come out another size: Tree::sizes_told)
    self.sizes_due = true
    self.layout_due = false
    // (laid out already to be read, nothing marked since: placed by that; else laid out now, what was laid out to be
    // read before it and not placed by yet placed too, Tree::measured_now)
    let gen = if self.measured_gen >= 0 {
      if self.walk_from >= 0 { self.walk_from } else { self.measured_gen }
    } else {
      self.alone_laid_out()
      self.work.computes = self.work.computes + 1
      let g = @flex.computes() + 1
      self.laids = self.laids + 1
      @flex.compute(self.nodes[0].flex, width=w, height=h, round=false, reuse=true)
      if self.walk_from >= 0 && self.walk_from < g {
        self.walk_from
      } else {
        g
      }
    }
    self.measured_gen = -1
    self.walk_from = -1
    self.walk(0, gen, true)
    // (what was laid out alone: placed by from it, what holds it laid out or not)
    for a in self.alone_laid {
      if self.nodes[a.0].live {
        self.walk(a.0, a.1, true)
      }
    }
    self.alone_laid.clear()
  }
  self.part_ended("tree layout", t_laid)
  // (the words measured since this was last said, in that layout or as something asked a size: how long in all)
  if self.measured_ms > 0.0 {
    if self.timed is Some((_, took)) {
      took("tree words measured", self.measured_ms)
    }
    self.measured_ms = 0.0
  }
  let t_placed = self.part_began()
  // (placed or faded by its own: it alone composed again)
  for at in self.places_due {
    let n = self.nodes[at]
    if n.live && n.place_due {
      self.work.visited = self.work.visited + 1
      self.place(at)
    }
  }
  self.places_due.clear()
  if placing {
    // (a page's list's first row on the pixels from where it is now laid out, whatever moved: Tree::rows_placed)
    if self.rows_grid > 0.0 {
      for at in self.rows_lists {
        if self.nodes[at].live && self.nodes[at].list_rows {
          self.place(at)
        }
      }
    }
    self.besides_placed()
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
  let ordered = self.order_due
  if ordered {
    self.order_due = false
    self.order_again()
    self.work.orders = self.work.orders + 1
  }
  self.work.changes = self.work.changes + self.changed.length() + self.composed.length()
  self.part_ended("tree placing", t_placed)
  self.due = false
  // (bindings told as it was laid out (a page's list's fill giving a block put by another key: what binds the key in
  // it), told as this pass was due already, so marked for no frame: worked out, and laid out by what they set, in this
  // same pass, as were they told before it; past `told_passes_most` of them one inside another, left queued, due no more,
  // for Tree::brought to tell)
  if !self.bindings_due.is_empty() && self.told_passes < told_passes_most {
    self.told_passes = self.told_passes + 1
    self.due = true
    self.laid_out(upto)
    self.told_passes = self.told_passes - 1
  }
  // (what its rows left out told once all of it is laid out, and what that tells (a ⋯ saying how many) laid out in this
  // same pass: one result, the frame drawing all of it)
  if self.outs_changed {
    self.outs_told()
    if self.due {
      self.laid_out(upto)
    }
  }
  // (the sizes followed told once all of it is laid out, and what that tells laid out in this same pass)
  if self.sizes_due && self.sized.length() > 0 && self.sizes_told() && self.due {
    self.laid_out(upto)
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
      self.laid_out(upto)
    }
  }
  // (what is to be brought into sight, where all of it is laid out, before it is drawn; what that moves laid out in
  // this same pass)
  if self.shows_due.length() > 0 {
    self.shown_now()
    if self.due {
      self.laid_out(upto)
    }
  }
  // (what the focus has kept in sight by the column it was brought into sight by, where that column's room came out
  // another: placed so it is, in this same pass)
  if self.focus_holds.length() > 0 && self.holds_now() && self.due {
    self.laid_out(upto)
  }
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
fn Tree::sizes_told(self : Tree) -> Bool {
  self.sizes_due = false
  let keep = []
  let told = Ref(false)
  @signals.start_batch()
  for at in self.sized {
    let n = self.nodes[at]
    guard n.live && n.size_cell is Some(_) else { continue }
    if !keep.contains(at) {
      keep.push(at)
      // (laid out nowhere, it or what holds it (View::laid_nowhere, left out of its row): no size of its own to tell
      // this time, the one it had kept, still followed, till it is laid out somewhere again, as what reads it (how far a
      // column scrolls) keeps its own)
      if self.out_at(at) {
        continue
      }
      match n.size_cell {
        Some(cell) => {
          let size = Some((n.flex.width, n.flex.height))
          if cell.untracked() != size {
            told.val = true
            cell.set(size)
          }
        }
        None => ()
      }
    }
  }
  // (what was first asked as what was told was read: a node made as it was, its size followed from then on, told the
  // next time all is laid out, not forgotten)
  let n = self.sized.length()
  @signals.end_batch()
  let asked = self.sized[n:].to_owned()
  self.sized.clear()
  self.sized.append(keep)
  self.sized.append(asked)
  told.val
}

///|
/// Node `id` (`within`: that part of it, its top and its foot in its own terms, asked once all is laid out; none there,
/// all of it) brought into sight by what holds it that shows what it holds (View::shows: a column that scrolls), once
/// all of it is laid out as it is next, before that is drawn: the innermost first, each that holds it then told where
/// it is as the ones inside it moved it; one that holds it pinned over what it scrolls (a page's list's foot) asked
/// nothing, it being in sight by that. Once, at this cause (the focus come to it): nothing brings it back of itself
/// after.
pub fn Tree::show_in_sight(
  self : Tree,
  id : NodeId,
  within? : () -> (Double, Double)?,
  holds? : () -> Bool,
) -> Unit {
  self.shows_due.push((id, within.unwrap_or(fn() { None }), holds))
  self.marked()
}

///|
/// What each column keeps in sight for the focus (Tree's focus_holds), where its room came out another than it last
/// kept it in (how tall it is, what lies over its top and its foot: the keyboard, its foot grown, the window), and then
/// only: the part, not whole between what covers its ends, brought into sight by the column, as little as does it, its
/// top winning, at once in this layout (no way of its own: what took the room is no motion of the column's). A column
/// whose rows come or go, its room the same, keeps nothing: at its foot it follows its foot, what is kept going up with
/// its rows. Let go of as the focus leaves the part, the part or the column is let go of, or the hand scrolls the
/// column (View::scrolls). Whether it moved any.
fn Tree::holds_now(self : Tree) -> Bool {
  let mut moved = false
  for col in self.focus_holds.keys().to_array() {
    // (the part brought into sight by it, where in it, whether the focus is still there, the room it last kept it in)
    let (part, within, still, kept) = match self.focus_holds.get(col) {
      Some(h) => h
      None => continue
    }
    let n = self.nodes[col]
    guard n.live &&
      self.alive_id(part) &&
      @signals.untracked(still) &&
      n.shows is Some(f) &&
      n.shows_room is Some(r) else {
      self.focus_holds.remove(col)
      continue
    }
    let room = @signals.untracked(r)
    if room == kept.val {
      continue
    }
    kept.val = room
    let (vh, top_cover, foot_cover) = room
    let (_, ty, ts) = self.placed(part.at)
    let (a, b) = match @signals.untracked(within) {
      Some(w) => w
      None => (0.0, self.nodes[part.at].flex.height)
    }
    let (_, vy, vs) = self.placed(col)
    let s = if vs > 0.0 { vs } else { 1.0 }
    let top = (ty + a * ts - vy) / s
    let foot = (ty + b * ts - vy) / s
    if top >= top_cover - 0.5 && foot <= vh - foot_cover + 0.5 {
      continue
    }
    if @signals.untracked(fn() { f(top, foot) }) != 0.0 {
      moved = true
    }
  }
  moved
}

///|
/// What is to be brought into sight (Tree::show_in_sight), all of it laid out: each in turn, as one change.
fn Tree::shown_now(self : Tree) -> Unit {
  let due = self.shows_due.copy()
  self.shows_due.clear()
  @signals.start_batch()
  for e in due {
    let (id, within, holds) = e
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
    // (the one it was reached from: what a column holds pinned over what it scrolls (a page's list's foot, its bar) is
    // in sight by being pinned, so nothing of the column is asked for it, its place kept (at its foot, following it))
    let mut came = id.at
    while i >= 0 {
      let n = self.nodes[i]
      match n.shows {
        Some(_) if n.scroll_held >= 0 && came != n.scroll_held => ()
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
            // (brought for the focus by a column down which it scrolls: kept in sight by it as its room changes, from
            // the room it is in now: Tree::holds_now)
            match (holds, n.shows_room) {
              (Some(still), Some(room)) if n.scroll_held >= 0 =>
                self.focus_holds[i] = (id, within, still, Ref(@signals.untracked(room)))
              _ => ()
            }
          }
        }
        None => ()
      }
      came = i
      i = n.parent
    }
  }
  @signals.end_batch()
}

///|
/// How big it was laid out (its own terms: View::laid_size's), followed: told once all of the layout is done, as one
/// change of all those followed; none till the first layout after it is first asked has been done (not measured yet:
/// no size of nothing). The tree's own alone (what moves it by its size, View::moved_by; what is tucked over a column's
/// top, Scroll::tucks): what is made is never made by what the layout came to, told back (what is made by its room is
/// made in it, View::by_room). Never a motion's target.
fn View::laid_size_told(self : View) -> (Double, Double)? {
  guard self.live() is Some(n) else { return None }
  let cell = match n.size_cell {
    Some(c) => c
    None => {
      let c : @signals.Signal[(Double, Double)?] = @signals.signal(None, same=fn(a, b) { a == b })
      n.size_cell = Some(c)
      self.tree.sized.push(self.at)
      self.tree.sizes_due = true
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
  self.hits_bump()
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
  // (what takes input told anew in what was left out or came back alone, not all of it: whether each takes input reads
  // what holds it, and only these changed of that)
  for at in gone {
    if self.nodes[at].live {
      self.inputs_marked(at)
    }
  }
  self.modals_marked()
  self.outs_said.set(self.outs_said.untracked() + 1)
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
  let max : @flex.Dim = if (one_line && in_column && st.width_kind() == @flex.LEN_AUTO) || n.max_w_within {
    match said {
      Some(w) => Within(w)
      None => Pct(100.0)
    }
  } else {
    match said {
      Some(w) => Pt(w)
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
        Pt((self.measure)(n.shorter[n.shorter.length() - 1], n.look.words_look, -1.0, self.words_scale_at(at)).0)
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
/// its characters, where it and an ellipsis fit (no space left before it); measured by `measure` at `scale`.
fn shorter_w_by(
  measure : (String, WordsLook, Double, Double) -> (Double, Double),
  words : String,
  shorter : Array[String],
  look : WordsLook,
  room : Double,
  scale : Double,
) -> Double {
  ignore(words)
  let wide = fn(s : String) { measure(s, look, -1.0, scale).0 }
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
    let cut = String::from_array(chars[:e].to_owned()) + "…"
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
  let fits = fn(s : String) { (self.measure)(s, n.look.words_look, -1.0, self.words_scale_at(at)).0 <= w + 0.5 }
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
  // (what moves it by how big it is laid out: by how big it is laid out now, Tree::place's own moment, View::moved_by)
  // (no pair made for each node placed where nothing moves it so, nor for its offset or its pivot: placed every time
  // anything about it is)
  match n.moved_by {
    Some(_) => n.moved = self.moved_of(n)
    None => if n.moved.0 != 0.0 || n.moved.1 != 0.0 { n.moved = (0.0, 0.0) }
  }
  let w = n.flex.width
  let h = n.flex.height
  let x = n.flex.left + n.look.dx + n.look.sx * w + n.moved.0
  // (a page's list's first row on the host's pixels where it sets them so: Tree::rows_placed)
  let y = self.rows_placed(at, n.flex.top + n.look.dy + n.look.sy * h + n.moved.1)
  let a = n.look.alpha
  let s = n.look.scale
  let mut px = 0.0
  let mut py = 0.0
  match n.look.pivot {
    At(fx, fy) => {
      px = fx * w
      py = fy * h
    }
    _ => {
      let p = self.pivot_of(at, w, h)
      px = p.0
      py = p.1
    }
  }
  // (left out of its row: laid out nowhere; told once all of it is laid out, View::left_out)
  let out = n.flex.left_out()
  let went = !n.placed || x != n.lx || y != n.ly || a != n.la || s != n.ls || px != n.lpx || py != n.lpy || out != n.out
  // (first placed, or left out of its row or back in it: what holds it reads out another set, what it holds takes presses
  // otherwise: Tree::said_marked)
  let came = !n.placed || out != n.out
  if out != n.out {
    n.out = out
    self.outs_changed = true
    self.sizes_due = true
    // (what of it is let go of, and whether what it holds takes input, told once all of the layout is done:
    // Tree::outs_told)
    self.outs_gone.push(at)
  }
  // (what a node that scrolls holds, moved from where it was placed: scrolled, Tree::take_scrolled; not one it moves
  // by its offset alone, which is drawn as it was wherever it is scrolled to: Node's scroll_off)
  if n.placed &&
    (x != n.lx || y != n.ly) &&
    n.scroll_off is None &&
    n.parent >= 0 &&
    self.nodes[n.parent].scroll_held == at {
    self.scrolled_now = true
    let p = self.nodes[n.parent]
    let id = { at: n.parent, gen: p.gen }
    if !self.scrolled_ats.contains(id) {
      self.scrolled_ats.push(id)
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
  if went || sized {
    self.places_rev = self.places_rev + 1
    self.touched(at, words=came, state=came, kids=came)
  }
  if went {
    self.work.composed = self.work.composed + 1
    self.composed.push({ at, gen: n.gen })
  }
  if sized || n.look_due {
    self.made_again(at)
  }
}

///|
/// Node `at`'s content made again, as it looks now and as big as it is: one of the frame's changes.
fn Tree::made_again(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  self.touched(at)
  n.look_due = false
  let id = { at, gen: n.gen }
  self.work.instances = self.work.instances + 1
  self.draws_rev = self.draws_rev + 1
  let drew = match n.content {
    Some(c) => Some(c.draws_any)
    None => None
  }
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
    image: n.look.image,
    image_for: n.look.image_for,
    image_cover: n.look.image_cover,
    image_contain: n.look.image_contain,
    image_cover_at: n.look.image_cover_at,
    image_fade: n.look.image_fade,
    image_in: n.look.image_in,
    glass: n.look.glass,
    words_look: n.look.words_look,
    runs: n.look.runs,
    runs_look: n.look.runs_look,
    runs_pressed: n.look.runs_pressed,
    runs_picked: n.look.runs_picked,
    runs_marks: n.look.runs_marks,
    shadow: n.look.shadow,
    hosted: n.hosted,
    clips: n.look.clips,
    clips_self: n.look.clips && n.coming,
    words_center: n.look.words_center,
    words_breaks: n.look.words_breaks,
    glyphs_said: n.look.glyphs_said,
    ellipsis_past: n.look.ellipsis_past,
    picture: n.look.picture,
    bones: self.bones_of_at(at),
    bone_as: self.bone_as_at(at),
    draws_any: look_draws_any(n.look, n.hosted),
  })
  // (on a flight's way: as big as it is drawn there, as it looks there, shared.mbt)
  match (n.lift, n.content) {
    (Some(l), Some(c)) => n.content = Some(self.lifted_content(n, l, c))
    _ => ()
  }
  // (whether it draws anything of its own told otherwise only where that changed: what a walk keeps of the order)
  match (drew, n.content) {
    (Some(d), Some(c)) if d == c.draws_any => ()
    _ => self.draws_any_rev = self.draws_any_rev + 1
  }
  self.changed.push(id)
  self.pending.push(id)
}

///|
/// The order the nodes are drawn in from node `at` down (no slot: what it holds in its place), what holds it at
/// `holder` in it.
fn Tree::ordered(self : Tree, at : Int, holder : Int, top : Int) -> Unit {
  let n = self.nodes[at]
  // (on a flight's way: drawn over the rest of its layer, put there as that ends, Tree::ordered_lifted)
  match n.lift {
    Some(l) if !self.lifting && l.top != at => {
      self.tops[at] = top
      return
    }
    _ => ()
  }
  self.lifting = false
  if n.slot {
    self.tops[at] = top
    for k in n.kids {
      self.ordered(k, holder, top)
    }
    return
  }
  self.order.push(at)
  self.order_holder.push(holder)
  self.order_end.push(-1)
  let me = self.order.length() - 1
  self.work.order_copied += 1
  self.order_of[at] = me
  self.order_gen[at] = n.gen
  // (the node of the root's it is in: itself where the root holds it, through its slots alone; Tree::top_of)
  let top = if at == 0 { -1 } else if top < 0 { at } else { top }
  self.tops[at] = top
  // (what the root holds, each by its place in the window's stack of layers: Tree::kids_in_order)
  for k in self.kids_in_order(at) {
    self.ordered(k, me, top)
  }
  if top == at && self.flights.length() > 0 {
    self.ordered_lifted(at, me)
  }
  self.order_end[me] = self.order.length()
}

///|
/// The order from node `at` down made again (Tree::order_from) as Tree::ordered makes it, aside (`order_new`, its first
/// at `p` in the order), where what holds no change since (Tree::order_again's `order_changed`) and was in the run made
/// again (the order from `p` till `e`, as it is till the run is put in its place) put back as it was there, whole,
/// moved: a row brought to another slot, those round it, as they were.
fn Tree::ordered_keeping(self : Tree, at : Int, holder : Int, top : Int, p : Int, e : Int) -> Unit {
  let n = self.nodes[at]
  if n.slot {
    self.tops[at] = top
    for k in n.kids {
      self.order_kept_or_made(k, holder, top, p, e)
    }
    return
  }
  let me = p + self.order_new.length()
  self.order_new.push(at)
  self.work.order_copied += 1
  self.order_new_holder.push(holder)
  self.order_new_end.push(-1)
  self.order_of[at] = me
  self.order_gen[at] = n.gen
  let top = if top < 0 { at } else { top }
  self.tops[at] = top
  for k in n.kids {
    self.order_kept_or_made(k, me, top, p, e)
  }
  self.order_new_end[me - p] = p + self.order_new.length()
}

///|
/// Node `k` put in the order next, what holds it at `holder` there (Tree::ordered_keeping): its run as it was where
/// nothing it holds changed since and it is the node that was there, else made again.
fn Tree::order_kept_or_made(self : Tree, k : Int, holder : Int, top : Int, p : Int, e : Int) -> Unit {
  let n = self.nodes[k]
  let w = self.order_was[k]
  if !n.slot &&
    self.order_changed[k] != self.order_stamp &&
    w >= p &&
    w < e &&
    self.order.unsafe_get(w) == k &&
    self.order_gen[k] == n.gen &&
    self.tops[k] == (if top < 0 { k } else { top }) {
    let base = p + self.order_new.length()
    let d = base - w
    let end = self.order_end.unsafe_get(w)
    self.work.order_copied += end - w
    for i in w..<end {
      let at = self.order.unsafe_get(i)
      self.order_of[at] = i + d
      self.order_new.push(at)
      self.order_new_holder.push(if i == w { holder } else { self.order_holder.unsafe_get(i) + d })
      self.order_new_end.push(self.order_end.unsafe_get(i) + d)
    }
  } else {
    self.ordered_keeping(k, holder, top, p, e)
  }
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
/// Whether anything it changed or let go of waits to be taken (take_changed, take_removed): what it was told is laid
/// out and placed, `due` no more, as a tree that lays itself out as each change is told whole does in the change's own
/// event (View::laid_before_causes), and not drawn yet.
pub fn Tree::changes_waiting(self : Tree) -> Bool {
  !self.pending.is_empty() || !self.removed.is_empty()
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
/// Whether what a node that scrolls holds (View::scrolls: its held, drawn off by how far it is scrolled) was moved from
/// where it was placed since this was last asked, by any frame or bringing of the tree since: something of it
/// scrolled. Asked once a paint (ui's view_paint), it is said no again till something scrolls again.
pub fn Tree::take_scrolled(self : Tree) -> Bool {
  let was = self.scrolled_now
  self.scrolled_now = false
  was
}

///|
/// The nodes that scroll whose held moved since this was last asked, as Tree::take_scrolled says whether any did: each
/// where it is drawn all drawn anew (ui's view_paint, what a host draws again).
pub fn Tree::take_scrolled_nodes(self : Tree) -> Array[NodeId] {
  let out = self.scrolled_ats.copy()
  self.scrolled_ats.clear()
  out
}

///|
/// Node `at` changed how it is drawn in its place (its content, where it is in what holds it, how opaque or big, what
/// it holds: one come, gone, moved among them): it and each that holds it marked with the count of changes now, what
/// is drawn of each no longer what it was (Tree::drawn_rev). And what is read out of it marked so (Tree::said_marked):
/// where it is alone (`words` false: moved or faded), else its words or what it holds too.
fn Tree::touched(
  self : Tree,
  at : Int,
  words? : Bool = true,
  state? : Bool = false,
  kids? : Bool = false,
) -> Unit {
  self.marked_up(at, true, words, state, kids, false)
}

///|
/// What is read out of node `at` changed (Tree::said_pass goes through it again): it and each that holds it marked
/// with the count of changes now, its words where `words` (what names what holds it), it itself, whether it takes
/// presses or what it says where `state` (what it holds read out so too), and where `kids` what of what holds it is read
/// out in the nearest of those that is read out (or the root): it come, gone, hidden or shown; `holds` the same of what
/// `at` holds (one let go of, moved among them), from `at` itself.
fn Tree::said_marked(
  self : Tree,
  at : Int,
  words? : Bool = true,
  state? : Bool = false,
  kids? : Bool = false,
  holds? : Bool = false,
) -> Unit {
  self.marked_up(at, false, words, state, kids, holds)
}

///|
/// Node `at` and each that holds it marked as Tree::touched (`drawn`) and Tree::said_marked say, in one way up: no
/// further than one marked so already with these counts (each that holds one marked is: what marks one marks all
/// above it, and a node never moves to another holder).
fn Tree::marked_up(
  self : Tree,
  at : Int,
  drawn : Bool,
  words : Bool,
  state : Bool,
  kids : Bool,
  holds : Bool,
) -> Unit {
  guard at >= 0 && at < self.nodes.length() else { return }
  let r = self.drawn_revs
  let sr = self.said_revs
  let me = self.nodes.unsafe_get(at)
  me.own_rev = sr
  if state {
    me.state_rev = sr
  }
  // (the nearest that is read out, or the root, marked as what of it is read out changed: none yet where none is)
  let mut seek = kids || holds
  let mut i = if holds { at } else { me.parent }
  if kids && !holds {
    // (it itself marked as below, the way up from what holds it)
    me.said_rev = sr
    if words {
      me.words_rev = sr
    }
    if drawn {
      me.drawn_rev = r
    }
  } else {
    i = at
  }
  while i >= 0 && i < self.nodes.length() {
    let n = self.nodes.unsafe_get(i)
    if seek && (i == 0 || self.said_entry_at(i)) {
      n.kids_rev = sr
      seek = false
    }
    if !seek &&
      n.said_rev == sr &&
      (!words || n.words_rev == sr) &&
      (!drawn || n.drawn_rev == r) {
      break
    }
    n.said_rev = sr
    if words {
      n.words_rev = sr
    }
    if drawn {
      n.drawn_rev = r
    }
    i = n.parent
  }
}

///|
/// The count of changes as node `id`, or anything it holds, last changed how it is drawn in its place (none for one let
/// go: -1): while it is no more than what was taken (Tree::drawn_rev_taken) as it was drawn, what it draws is what it
/// drew then, moved with it.
pub fn Tree::drawn_rev(self : Tree, id : NodeId) -> Int {
  guard self.alive_id(id) else { return -1 }
  self.nodes.unsafe_get(id.at).drawn_rev
}

///|
/// The count of changes to where any node is drawn as the walk works it out (Tree::each_drawn_in_order, drawn_one), but
/// by the clock: while it is what it was and no node from `id` to the root is drawn off by a column at a moment
/// (Tree::placed_by_clock), node `id` is drawn where it was.
pub fn Tree::places_rev(self : Tree) -> Int {
  self.places_rev
}

///|
/// Whether node `id`, or anything that holds it, is drawn off by how far a column scrolls it at a moment (Node's
/// `scroll_off`): where it is drawn read at that moment, never counted in Tree::places_rev.
pub fn Tree::placed_by_clock(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let mut i = id.at
  while i >= 0 {
    let n = self.nodes.unsafe_get(i)
    if n.scroll_off is Some(_) {
      return true
    }
    i = n.parent
  }
  false
}

///|
/// How many nodes node `id` holds in the order it is drawn in (Tree's `order`): none where it is in none.
pub fn Tree::held_count(self : Tree, id : NodeId) -> Int {
  guard self.alive_id(id) && id.at < self.order_of.length() else { return 0 }
  let i = self.order_of.unsafe_get(id.at)
  guard i >= 0 && i < self.order.length() else { return 0 }
  self.order_end.unsafe_get(i) - i - 1
}

///|
/// The count of changes now, taken by what draws the tree as it draws it: each change after it counted past it.
pub fn Tree::drawn_rev_taken(self : Tree) -> Int {
  let r = self.drawn_revs
  self.drawn_revs = r + 1
  r
}

///|
/// Whether node `id` is one of what a node that scrolls holds (View::scrolls), in it or in what comes and goes in it
/// (a slot's): one of a list's rows, drawn as it was wherever it is scrolled to.
pub fn Tree::rides_scroll(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let mut p = self.nodes.unsafe_get(id.at).parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  p >= 0 && {
    let s = self.nodes[p].parent
    s >= 0 && self.nodes[s].scroll_held == p
  }
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
/// `inputs_only`: what holds nothing that takes a finger or the pointer some way passed over whole (Node's `inputs_in`),
/// for what finds what takes a point.
pub fn Tree::each_drawn_scaled(
  self : Tree,
  f : (Content, Double, Double, Double, Double) -> Unit,
  inputs_only? : Bool = false,
) -> Unit {
  self.each_drawn_in_order(
    fn(_, c, x, y, a, s, _, _) {
      f(c, x, y, a, s)
      false
    },
    inputs_only~,
  )
}

///|
/// The scene gone through as each_drawn_scaled goes through it, `f` given besides where each would be drawn were
/// nothing in its way grown or shrunk (View::scale: where it is laid out and drawn off, what holds it so): where what
/// it draws is set on the pixels before it is drawn as big as it is, about that place (as an old view's are, painted
/// where they are laid out, then its looks).
pub fn Tree::each_drawn_laid(self : Tree, f : (Content, Double, Double, Double, Double, Double, Double) -> Unit) -> Unit {
  self.each_drawn_in_order(fn(_, c, x, y, a, s, ux, uy) {
    f(c, x, y, a, s, ux, uy)
    false
  })
}

///|
/// The scene gone through as each_drawn_laid goes through it, what a node holds passed over where `f` says so of it
/// (true: it draws all of it itself, as it was drawn before, Tree::drawn_rev). What holds nothing `draws` says draws
/// anything (a list's rows not made) passed over too, but what the window holds itself. `draws_rev`: how many times
/// what `draws` reads besides a node's content changed, where it says so (none: -1): what it said of each kept while
/// neither that nor the order nor whether any node draws anything of its own (its content's `draws_any`, all `draws`
/// reads of a content where it says one) changed, not asked again each walk.
pub fn Tree::each_drawn_laid_or_past(
  self : Tree,
  f : (Content, Double, Double, Double, Double, Double, Double) -> Bool,
  draws? : (Content) -> Bool,
  offsets? : (Content) -> Bool,
  draws_rev? : Int = -1,
) -> Unit {
  self.each_drawn_in_order(
    fn(_, c, x, y, a, s, ux, uy) { f(c, x, y, a, s, ux, uy) },
    drawing?=draws,
    offsets?,
    drawing_rev=draws_rev,
  )
}

///|
/// The scene gone through as each_drawn_laid goes through it, `f` given besides each one's place in the order (Tree's
/// `order`, what holds it there `order_holder`'s).
fn Tree::each_drawn_in_order(
  self : Tree,
  f : (Int, Content, Double, Double, Double, Double, Double, Double) -> Bool,
  drawing? : (Content) -> Bool,
  offsets? : (Content) -> Bool,
  drawing_rev? : Int = -1,
  inputs_only? : Bool = false,
) -> Unit {
  // (where each in the order is drawn, how opaque, how big, and where it would be were nothing grown, shrunk or drawn
  // off: kept for the next walk, one for each walk inside another's `f`; each place written
  // before what it holds reads it)
  let len = self.order.length()
  // (none kept past what the tree let go of: Tree::dispose, even from inside a walk)
  while self.walks.length() <= self.walking {
    self.walks.push(Walk::new())
  }
  let w = self.walks[self.walking]
  w.fit(len)
  self.walking = self.walking + 1
  let wx = w.x
  let wy = w.y
  let wa = w.a
  let ws = w.s
  let ux = w.ux
  let uy = w.uy
  // (`drawing`: whether a node draws anything, as the walker draws it: what holds nothing that does (a list's rows not
  // made, only as tall as they were) passed over whole, none of it given to `f`, but what the window holds itself (a
  // layer: what is under it painted first, as where it is in the window's stack says))
  // (as the last walk with the same `drawing_rev` worked it out, where neither the order nor whether any node draws
  // anything of its own changed since; a walk inside another's `f` its own)
  let cache = drawing_rev >= 0 && self.walking == 1
  let kept = cache && self.drawn_next_for == (self.draws_any_rev, drawing_rev, len)
  if cache && self.drawn_next.length() < len {
    self.drawn_next = FixedArray::make(len * 2, 0)
  }
  let nd = if cache { self.drawn_next } else { w.next_drawn }
  let passing = drawing is Some(_)
  if drawing is Some(draws) && !kept {
    let mut next = len
    for j = len - 1; j >= 0; j = j - 1 {
      match self.nodes.unsafe_get(self.order.unsafe_get(j)).content {
        Some(c) if draws(c) => next = j
        _ => ()
      }
      nd.unsafe_set(j, next)
    }
    if cache {
      self.drawn_next_for = (self.draws_any_rev, drawing_rev, len)
    }
  }
  let g = self.pixel_grid
  // (a page's list's rows on its host's grid (Tree::set_rows_grid): the place in the order of the holder of the rows
  // last come to (-1: none), what holds each of them there (a slot is in no order: its holder holds what it holds).
  // Found where what a column scrolls by its offset alone is, as every such holder is (View::scrolls), not looked for
  // at each node. A list's rows after a list of rows in one of them would not be put on the grid (what the walk would
  // ask at every node to know it is out of the inner again): such a list is a fault as it is made,
  // Tree::rows_list_nested_said.)
  let rg = self.rows_grid
  let mut rows_at = -1
  let mut i = 0
  while i < len {
    // (the tree let go of from inside `f`: nothing more of it walked, as it went before)
    if i >= self.order.length() {
      break
    }
    // (each read and written unchecked: `i` within the order (above), the order's three arrays as long as it, each
    // node it names one of the tree's, what holds it before it in the order, the walk's room fitted to `len`)
    let n = self.nodes.unsafe_get(self.order.unsafe_get(i))
    let h = self.order_holder.unsafe_get(i)
    // (left out: it and all it holds, the order's run of them passed over at once)
    if n.out || (inputs_only && n.inputs_in == 0) {
      i = self.order_end.unsafe_get(i)
      continue
    }
    if passing && h > 0 && nd.unsafe_get(i) >= self.order_end.unsafe_get(i) {
      i = self.order_end.unsafe_get(i)
      continue
    }
    // (where it is in what holds it, drawn as big as that is; its own scale about its point: its origin drawn in as far
    // as that leaves it)
    // (drawn off where it is laid out, drawn only, by whole pixels where the host says how many a point: View::drawn_off)
    let mut ox = n.look.drawn_off.0
    let mut oy = n.look.drawn_off.1
    // (whole pixels of the host's, in its own terms, as an old view's look's dx is before what holds it is drawn
    // bigger or smaller: draw.mbt's on_pixels(look.dx, scale))
    if g > 0.0 && (ox != 0.0 || oy != 0.0) {
      ox = (ox * g).round() / g
      oy = (oy * g).round() / g
    }
    // (numbers each its own, no tuple of them made for each node)
    let mut x = n.lx + ox + (1.0 - n.ls) * n.lpx
    let mut y = n.ly + oy + (1.0 - n.ls) * n.lpy
    let mut a = n.la
    let mut s = n.ls
    // (and were nothing grown or shrunk nor drawn off: its words set on the pixels there, then drawn off by whole
    // pixels, as an old view's are painted where they are laid out and then moved by its look)
    let mut lx = n.lx
    let mut ly = n.ly
    // (as far as a column scrolls it now (Node's scroll_off), but where `offsets` says it is not: what it holds drawn
    // as it is placed in it, it drawn off as a whole by what hosts it, a page's list's header)
    if n.scroll_off is Some(_) {
      if n.list_rows && rg > 0.0 {
        rows_at = i
      }
      if (match (offsets, n.content) {
          (Some(o), Some(c)) => o(c)
          _ => true
        }) {
        let (sx, sy) = self.scroll_off_now(n)
        x = x + sx
        y = y + sy
        lx = lx + sx
        ly = ly + sy
      }
    }
    if h >= 0 {
      let bs = ws.unsafe_get(h)
      x = wx.unsafe_get(h) + bs * x
      y = wy.unsafe_get(h) + bs * y
      a = wa.unsafe_get(h) * a
      s = bs * s
      lx = ux.unsafe_get(h) + lx
      ly = uy.unsafe_get(h) + ly
      // (a page's list's row on its host's pixels, drawn as big as it is laid out: its top the grid's own number for
      // where it is, however it was summed there: row_on_grid)
      if h == rows_at && s == 1.0 {
        y = row_on_grid(y, rg)
        ly = row_on_grid(ly, rg)
      }
    }
    // (on a flight's way: where the flight has it in the window, nothing that holds it counted, shared.mbt)
    match n.lift {
      Some(l) => {
        let (fx, fy, fa, fs) = self.lifted_place(n, l)
        x = fx
        y = fy
        a = fa
        s = fs
        lx = fx
        ly = fy
      }
      None => if n.share_stays && self.stays_hidden(n) { a = 0.0 }
    }
    wx.unsafe_set(i, x)
    wy.unsafe_set(i, y)
    wa.unsafe_set(i, a)
    ws.unsafe_set(i, s)
    ux.unsafe_set(i, lx)
    uy.unsafe_set(i, ly)
    match n.content {
      Some(c) => if f(i, c, x, y, a, s, lx, ly) {
        // (what it holds drawn by `f` as it was: passed over, as one left out is)
        i = self.order_end.unsafe_get(i)
        continue
      }
      None => ()
    }
    i = i + 1
  }
  self.walking = self.walking - 1
}

///|
/// Node `id` as the scene's walk finds it (Tree::each_drawn_laid), alone: its content, where the window draws it, how
/// opaque, how big and where it would be were nothing grown, shrunk or drawn off, worked out from the top down as the
/// walk works each out from what holds it, the same numbers; and its place in the order. None where the walk finds it
/// not: not in the order, left out (it or what holds it), or drawing nothing of its own.
pub fn Tree::drawn_one(
  self : Tree,
  id : NodeId,
) -> (Content, Double, Double, Double, Double, Double, Double, Int)? {
  guard self.alive_id(id) && id.at < self.order_of.length() else { return None }
  let i = self.order_of[id.at]
  guard i >= 0 && i < self.order.length() else { return None }
  guard self.nodes[id.at].content is Some(c) else { return None }
  let path = self.drawn_path
  path.clear()
  let mut j = i
  while j >= 0 {
    path.push(j)
    j = self.order_holder[j]
  }
  let g = self.pixel_grid
  let mut rows_kids = false
  let mut x = 0.0
  let mut y = 0.0
  let mut a = 1.0
  let mut s = 1.0
  let mut ux = 0.0
  let mut uy = 0.0
  for k = path.length() - 1; k >= 0; k = k - 1 {
    let n = self.nodes[self.order[path[k]]]
    if n.out {
      return None
    }
    // (each as Tree::each_drawn_in_order works it out: written the same, the same numbers)
    let mut ox = n.look.drawn_off.0
    let mut oy = n.look.drawn_off.1
    if g > 0.0 && (ox != 0.0 || oy != 0.0) {
      ox = (ox * g).round() / g
      oy = (oy * g).round() / g
    }
    let mut nx = n.lx + ox + (1.0 - n.ls) * n.lpx
    let mut ny = n.ly + oy + (1.0 - n.ls) * n.lpy
    let mut na = n.la
    let mut ns = n.ls
    let mut lx = n.lx
    let mut ly = n.ly
    if n.scroll_off is Some(_) {
      let (sx, sy) = self.scroll_off_now(n)
      nx = nx + sx
      ny = ny + sy
      lx = lx + sx
      ly = ly + sy
    }
    if k < path.length() - 1 {
      nx = x + s * nx
      ny = y + s * ny
      na = a * na
      ns = s * ns
      lx = ux + lx
      ly = uy + ly
      if rows_kids && ns == 1.0 {
        ny = row_on_grid(ny, self.rows_grid)
        ly = row_on_grid(ly, self.rows_grid)
      }
    }
    // (what it holds a page's list's rows on the grid, as the walk finds them (a slot is in no order: what it holds is
    // its holder's))
    rows_kids = n.list_rows && self.rows_grid > 0.0
    x = nx
    y = ny
    a = na
    s = ns
    ux = lx
    uy = ly
    match n.lift {
      Some(l) => {
        let (fx, fy, fa, fs) = self.lifted_place(n, l)
        x = fx
        y = fy
        a = fa
        s = fs
        ux = fx
        uy = fy
      }
      None => if n.share_stays && self.stays_hidden(n) { a = 0.0 }
    }
  }
  Some((c, x, y, a, s, ux, uy, i))
}

///|
/// What a walk of the scene keeps of each in the order as it goes (Tree::each_drawn_in_order), kept for the next.
priv struct Walk {
  mut x : FixedArray[Double]
  mut y : FixedArray[Double]
  mut a : FixedArray[Double]
  mut s : FixedArray[Double]
  mut ux : FixedArray[Double]
  mut uy : FixedArray[Double]
  // (from each in the order, the first at or past it that draws anything of its own: Tree::each_drawn_in_order's
  // `drawing`)
  mut next_drawn : FixedArray[Int]
}

///|
fn Walk::new() -> Walk {
  { x: [], y: [], a: [], s: [], ux: [], uy: [], next_drawn: [] }
}

///|
/// Room for `len` in the order, at least (grown by half again past it: the order grows a little at a time).
fn Walk::fit(self : Walk, len : Int) -> Unit {
  if self.x.length() >= len {
    return
  }
  let room = len + len / 2 + 16
  self.x = FixedArray::make(room, 0.0)
  self.y = FixedArray::make(room, 0.0)
  self.a = FixedArray::make(room, 1.0)
  self.s = FixedArray::make(room, 1.0)
  self.ux = FixedArray::make(room, 0.0)
  self.uy = FixedArray::make(room, 0.0)
  self.next_drawn = FixedArray::make(room, 0)
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
    image: c.image,
    image_for: c.image_for,
    image_cover: c.image_cover,
    image_contain: c.image_contain,
    image_cover_at: c.image_cover_at,
    image_fade: c.image_fade,
    image_in: c.image_in,
    glass: c.glass,
    words_look: c.words_look,
    runs: c.runs,
    runs_look: c.runs_look,
    runs_pressed: c.runs_pressed,
    runs_picked: c.runs_picked,
    runs_marks: c.runs_marks,
    shadow: c.shadow,
    hosted: c.hosted,
    clips: c.clips,
    clips_self: c.clips_self,
    words_center: c.words_center,
    words_breaks: c.words_breaks,
    glyphs_said: c.glyphs_said,
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
/// Whether node `at` is a press target as Tree::drawn_held and the rest say it: it has a press (View::on_press) and is
/// not `inert`. `inert` is written by what it says itself (View::presses(false)), cleared as a node is made again, and
/// set on the old copy a shared element leaves where it flies (Tree::paired: that copy drawn fading out on the flight's
/// way, taking nothing). Not what holds it, nor whether it is leaving, in its bones or under a modal layer: what reads
/// this runs in a running app too (ui's Ctx::corners_after_layout, by Tree::laid_held_hosted: as it walks the tree, and
/// of each it kept on every frame an old view builds, no count of changes raised by it: a row pressed whole is the
/// corner container of an old view's box said `Inner` in it), so it is one field read, and a row that starts to leave
/// stays that box's container all the way out, its corner not worked out against another halfway.
fn Tree::presses_said(self : Tree, at : Int) -> Bool {
  self.nodes[at].on_press is Some(_) && !self.nodes[at].inert
}

///|
/// The scene unfolded as Tree::drawn has it, its corners as big as it is drawn too, each with what holds it as drawn (its index in the same array, -1: none
/// drawn round it) and whether it is a press target (Tree::presses_said: not one that says it takes none): for a check of
/// where things stand in what holds them (ui's corner rule).
pub fn Tree::drawn_held(self : Tree) -> Array[(Drawn, Int, Bool)] {
  let out : Array[(Drawn, Int, Bool)] = []
  // (each in the order's place, where it is in what is drawn: -1 where it draws nothing)
  let at_out : Array[Int] = Array::make(self.order.length(), -1)
  self.each_drawn_in_order(fn(i, c, x, y, a, s, _, _) {
    let mut h = self.order_holder[i]
    while h >= 0 && at_out[h] < 0 {
      h = self.order_holder[h]
    }
    at_out[i] = out.length()
    // (its corners as big as it is drawn, as its size is: where the window draws it, in the window's points)
    let d = {
      ..unfolded(c, x, y, a, s),
      radius: c.radius * s,
      corners: c.corners.map(fn(k) { (k.0 * s, k.1 * s, k.2 * s, k.3 * s) }),
    }
    out.push((d, if h >= 0 { at_out[h] } else { -1 }, self.presses_said(c.id.at)))
    false
  })
  out
}

///|
/// The scene as Tree::drawn_held has it, but each where it is laid out (Tree::laid_origin) as big as it is laid out, its
/// corner too: where an old view hosted in it is laid out, as the old frame lays it out (view_host.mbt's old_place),
/// what it holds worked out against it before it is drawn (ui's corners said Inner).
pub fn Tree::laid_held(self : Tree) -> Array[(Drawn, Int, Bool)] {
  let out : Array[(Drawn, Int, Bool)] = []
  let at_out : Array[Int] = Array::make(self.order.length(), -1)
  self.each_drawn_in_order(fn(i, c, x, y, a, _, _, _) {
    let mut h = self.order_holder[i]
    while h >= 0 && at_out[h] < 0 {
      h = self.order_holder[h]
    }
    at_out[i] = out.length()
    let (lx, ly) = self.laid_origin(c.id).unwrap_or((x, y))
    out.push((unfolded(c, lx, ly, a, 1.0), if h >= 0 { at_out[h] } else { -1 }, self.presses_said(c.id.at)))
    false
  })
  out
}

///|
/// The scene as Tree::laid_held has it, but only what `wanted` names, what holds each, and what lies laid out where
/// one of those does, as big (what holds it so, a ground laid beside it as a layer): what is worked out of an old view
/// hosted in it against what holds it (ui's corners said Inner), not all of the tree made into nodes for the few.
pub fn Tree::laid_held_toward(self : Tree, wanted : (Content) -> Bool) -> Array[(Drawn, Int, Bool)] {
  let len = self.order.length()
  let keep : Array[Bool] = Array::make(len, false)
  for i in 0..<len {
    match self.nodes[self.order[i]].content {
      Some(c) if wanted(c) => {
        let mut j = i
        while j >= 0 && !keep[j] {
          keep[j] = true
          j = self.order_holder[j]
        }
      }
      _ => ()
    }
  }
  let out : Array[(Drawn, Int, Bool)] = []
  let at_out : Array[Int] = Array::make(len, -1)
  self.each_drawn_in_order(fn(i, c, x, y, a, _, _, _) {
    let h0 = self.order_holder[i]
    let (lx, ly) = if keep[i] || (h0 >= 0 && at_out[h0] >= 0) {
      self.laid_origin(c.id).unwrap_or((x, y))
    } else {
      return false
    }
    // (one not wanted nor holding one: kept only laid out as its holder is, kept, as big)
    if !keep[i] {
      let (hd, _, _) = out[at_out[h0]]
      if (hd.x - lx).abs() > 0.5 ||
        (hd.y - ly).abs() > 0.5 ||
        (hd.w - c.w).abs() > 0.5 ||
        (hd.h - c.h).abs() > 0.5 {
        return false
      }
    }
    let mut h = h0
    while h >= 0 && at_out[h] < 0 {
      h = self.order_holder[h]
    }
    at_out[i] = out.length()
    out.push((unfolded(c, lx, ly, a, 1.0), if h >= 0 { at_out[h] } else { -1 }, self.presses_said(c.id.at)))
    false
  })
  out
}

///|
/// What Tree::laid_held_toward gives of the nodes an old view is hosted in (Content's `hosted`), kept and given again,
/// the same array, while nothing it is worked out of changed: the order and each node's content (`draws_rev`: the order
/// made again, a node made, made again or let go), where each is placed, as opaque and whether left out (`places_rev`),
/// its flex place (`laids`: what Tree::laid_origin sums changes only as one is worked out, placed or not yet), the
/// order's length; never while the order is due to be made again (what holds a node changed before that) or anything
/// flies (the walk then takes what flies where its flight has it now); and each kept one's taking a press as it is said
/// now (Tree::presses_said, which no count says: one field read each, walked afresh where one differs). Nothing else
/// of it is worked out by the clock: a scroller's offset is not taken (each is where it is laid out, Tree::laid_origin),
/// and how opaque one is on a way is what Tree::place last placed it as, each frame of the way a place counted (ui's
/// corners read it: one as good as unseen is no container). It is the
/// tree's own: whoever reads it reads it only, never writing it nor anything in it. For ui's Ctx::corners_after_layout,
/// on every frame an old view builds.
pub fn Tree::laid_held_hosted(self : Tree) -> Array[(Drawn, Int, Bool)] {
  let key = (self.draws_rev, self.places_rev, self.order.length(), self.laids)
  if key == self.held_kept_for && !self.order_due && self.flights.is_empty() {
    let kept = self.held_kept
    let mut same = true
    for k in 0..<kept.length() {
      let (d, _, presses) = kept[k]
      if presses != self.presses_said(d.id.at) {
        same = false
        break
      }
    }
    if same {
      return kept
    }
  }
  self.held_walked = self.held_walked + 1
  let held = self.laid_held_toward(fn(c) { c.hosted })
  // (kept only where it can be said again: none while the order is due, or while anything flies)
  if !self.order_due && self.flights.is_empty() {
    self.held_kept = held
    self.held_kept_for = key
  } else {
    self.held_kept = []
    self.held_kept_for = (-1, -1, -1, -1)
  }
  held
}

///|
/// How many times Tree::laid_held_hosted walked the tree, not giving again what it kept: for a test of when it does.
pub fn Tree::held_walked(self : Tree) -> Int {
  self.held_walked
}

///|
/// Whether node `id` holds a node of its own in the scene now (one living, not left out of its row): what is drawn over
/// its ground, under the edge round it (an old view's box's border_over: drawn after what it holds).
pub fn Tree::holds_drawn(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  // (by its index: no iterator made, asked of each node drawn with an edge)
  let kids = self.nodes[id.at].kids
  for i in 0..<kids.length() {
    let k = self.nodes[kids[i]]
    if k.live && !k.out {
      return true
    }
  }
  false
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
/// Whether node `inner` is `outer` or held by it, as Tree::holds says, read off the order as it was last worked out
/// (where each is in it, and where what it holds ends there) for two drawn in it, not gone up to through what holds
/// `inner`: for what is asked of each drawn as the scene is gone through (ui's view_paint, each drawn asked of all
/// still open round it).
pub fn Tree::holds_in_order(self : Tree, outer : NodeId, inner : NodeId) -> Bool {
  guard !self.order_due &&
    self.alive_id(outer) &&
    self.alive_id(inner) &&
    outer.at < self.order_of.length() &&
    inner.at < self.order_of.length() else {
    return self.holds(outer, inner)
  }
  let o = self.order_of[outer.at]
  let i = self.order_of[inner.at]
  guard o >= 0 && i >= 0 else { return self.holds(outer, inner) }
  i >= o && i < self.order_end[o]
}

///|
/// Node `id` unfolded where the window draws it, where it lives and has been placed.
pub fn Tree::drawn_of(self : Tree, id : NodeId) -> Drawn? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  guard n.live && n.gen == id.gen && n.content is Some(c) && !self.out_at(id.at) else { return None }
  let (x, y, a, s) = self.projected(id.at)
  Some(unfolded(c, x, y, a, s))
}

///|
/// Where node `id` is drawn in the window (Tree::drawn_of's x and y), how opaque and how big (its scale and its
/// holders', Tree::drawn_scale), where it lives and has been placed: none of what it draws unfolded.
pub fn Tree::drawn_place(self : Tree, id : NodeId) -> (Double, Double, Double, Double)? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  guard n.live && n.gen == id.gen && n.content is Some(_) && !self.out_at(id.at) else { return None }
  Some(self.projected(id.at))
}

///|
/// Where node `at` is drawn in the window, how opaque and how big (its scale and its holders'), as it was last placed:
/// composed from the window down as each_drawn_scaled composes it (a slot adds nothing of its own). The one way the
/// window's terms and a node's are told apart: where it is drawn, where it takes a finger, where it is read out.
fn Tree::projected(self : Tree, at : Int) -> (Double, Double, Double, Double) {
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
    // (and as far as a column scrolls it now: Node's scroll_off)
    let (sx, sy) = self.scroll_off_now(m)
    x = x + s * (m.lx + sx + (1.0 - m.ls) * m.lpx)
    y = y + s * (m.ly + sy + (1.0 - m.ls) * m.lpy)
    a = a * m.la
    s = s * m.ls
    // (on a flight's way: where the flight has it, shared.mbt)
    match m.lift {
      Some(l) => {
        let (fx, fy, fa, fs) = self.lifted_place(m, l)
        x = fx
        y = fy
        a = fa
        s = fs
      }
      None => if m.share_stays && self.stays_hidden(m) { a = 0.0 }
    }
  }
  (x, y, a, s)
}

///|
/// The side the nearest that holds node `id` (it too) and goes beside another (View::beside) went on as it was placed
/// now (the side it was said to go on, or the other where it had not the room): for what hosts an old view in the tree
/// (@ui.old), which builds by where it is placed; none where nothing holding it goes beside another, or none was placed
/// yet.
pub fn Tree::went_over(self : Tree, id : NodeId) -> Side? {
  guard self.alive_id(id) else { return None }
  let mut i = id.at
  while i >= 0 {
    let n = self.nodes[i]
    if n.beside is Some(_) {
      return n.went
    }
    i = n.parent
  }
  None
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
    Pressed(id) => self.run_press_at(id, at, place=(x, y))
    _ => false
  }
}

///|
/// What hosts the tree told as there is first something for a frame to do (it asks for a frame).
pub fn Tree::on_due(self : Tree, f : () -> Unit) -> Unit {
  self.on_due = f
}

///|
/// What hosts the tree told as a node's pointer's shape is said anew (View::cursor), at that change: what shows the
/// pointer's shape again where that is the shape the pointer shows; no frame asked for it.
pub fn Tree::on_cursor(self : Tree, f : () -> Unit) -> Unit {
  self.on_cursor = f
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
/// off and drawn in order), made by `make` as any node is (its size, its place; by default
/// the room its holder leaves it).
pub fn View::hosted(self : View, make? : (View) -> Unit = fn(v) { v.grow(Is(1.0)) |> ignore }) -> View {
  let tree = self.tree
  self.box(fn(v) {
    tree.nodes[v.at].hosted = true
    tree.inputs_own_said(v.at)
    tree.said_marked(v.at, kids=true)
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
  self.due
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
#derive(Eq, Debug)
pub(all) enum Target {
  Pressed(NodeId)
  Dragged(NodeId)
  Hosted(NodeId)
  /// a top row of the app's own, what moves the window (View::moves_window)
  TopRow(NodeId)
  Nothing
}

///|
/// Where a node takes a finger as it is drawn now (Tree::finger_areas).
#derive(Eq, Debug)
pub(all) enum FingerAreas {
  /// rects of the window (x0, y0, x1, y1): none where it takes none
  InWindow(Array[(Double, Double, Double, Double)])
  /// all of it drawn, where what it hosts takes one (View::hosted_takes; a hosted node saying nothing of it)
  AsItHosts
}

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
      let rs = self.takes_rects(n, w, h, self.logic_said())
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
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
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
/// Whether node `at` takes a finger or the pointer some way, told anew as one of those it says changes: what holds it
/// counts it among those it holds (Node's `inputs_in`).
fn Tree::inputs_own_said(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  let own = n.on_press is Some(_) ||
    n.on_drag is Some(_) ||
    n.hosted ||
    n.top_row ||
    n.points ||
    n.claims is Some(_)
  if own != n.inputs_own {
    n.inputs_own = own
    self.inputs_count(at, if own { 1 } else { -1 })
  }
}

///|
/// Node `at` and each that holds it counting `d` more that take a point among what they hold.
fn Tree::inputs_count(self : Tree, at : Int, d : Int) -> Unit {
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    n.inputs_in = n.inputs_in + d
    i = n.parent
  }
}

///|
/// What a press at (x, y) is for: the topmost node drawn there (by the order drawn, where the scene composed draws it:
/// the same places as what is drawn) that is held (View::on_drag), does something when pressed or hosts the old view;
/// or one drawn over it smaller than a press's room whose room holds (x, y), the nearest (Tree::reached). The one
/// answer of what a point is for: a press down, its let go landing on what it went down on, the pointer lighting what
/// it is over (Tree::follow_point), View::finger_target.
pub fn Tree::target_at(self : Tree, x : Double, y : Double) -> Target {
  self.target_in(x, y, tracked=false)
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
  let at = self.logic_said()
  let least = self.least_now()
  let found : Array[Target] = []
  // (each found's place in the walk and its box; what is drawn small near (x, y), passed: Tree::near_said, found in
  // the same walk, none walked again)
  let orders : Array[Int] = []
  let boxes : Array[(Double, Double, Double, Double)] = []
  let near : Array[Near] = []
  let order = Ref(0)
  // (the last drawn there that hides what is under it: Node::covers)
  let covered = Ref(-1)
  self.each_drawn_scaled(fn(c, cx, cy, a, s) {
    let o = order.val
    order.val = o + 1
    self.work.found_walked = self.work.found_walked + 1
    let n = self.nodes[c.id.at]
    // (a gesture answering a hold alone takes no press nor drag: what is under it does, as were it not there)
    if n.hold_only is Some(_) {
      return
    }
    if self.finger_on(c, cx, cy, s, x, y, at, tracked~) {
      // (one that takes over holds (View::claims) takes none at its own down: it is found as it moves)
      let t = if n.on_drag is Some(_) && n.claims is None {
        Dragged(c.id)
      } else if n.on_press is Some(_) {
        Pressed(c.id)
      } else if n.hosted {
        Hosted(c.id)
      } else if n.top_row {
        TopRow(c.id)
      } else {
        if n.covers(a) {
          covered.val = o
        }
        return
      }
      found.push(t)
      orders.push(o)
      boxes.push((cx, cy, cx + c.w * s, cy + c.h * s))
    } else {
      self.near_said(n, c, cx, cy, s, x, y, least, o, near)
    }
  }, inputs_only=true)
  let top = self.chosen(found, x, y)
  let (top_order, top_box) = match found.search(top) {
    Some(i) => (orders[i], boxes[i])
    None => (-1, (0.0, 0.0, 0.0, 0.0))
  }
  self.reached(top, top_order, top_box, near, x, y, least, covered=covered.val)
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
  let at = self.logic_said()
  let found : Ref[NodeId?] = Ref(None)
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
    if self.finger_on(c, cx, cy, s, x, y, at, tracked=true) {
      let n = self.nodes[c.id.at]
      if n.points {
        found.val = Some(c.id)
      } else if (n.on_drag is Some(_) && n.claims is None) || n.on_press is Some(_) || n.hosted || n.top_row {
        found.val = None
      }
    }
  }, inputs_only=true)
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
/// What hosts the tree is told as a node says something of it moves (View::said_moving), `moves`: its key (the same
/// for what moves again), what it is and who told it, and when it is at rest as of a moment (-1 done), what waits on
/// what moves (a test's run to rest, Tester::moving, rest_of) reading it as an old view's motion.
pub fn Tree::on_moves(self : Tree, moves : (String, String, (Double) -> Double) -> Unit) -> Unit {
  self.moves = moves
}

///|
/// Says something of this node moves, set out now by its cause: `key` the same each time it is told to go again,
/// `what` what it is and who told it (what a test names it by: Tester::rest_of), `rest` when it is at rest as of a
/// moment (-1 done). Only what waits on what moves reads it; how it is drawn is the node's own (its look's moment).
pub fn View::said_moving(self : View, key : String, what : String, rest : (Double) -> Double) -> Unit {
  (self.tree.moves)(key, what, rest)
}

///|
/// What hosts the tree is told as a column of it moves what it scrolls by its offset alone (Node's scroll_off: a page's
/// list up and down, its bar's thumb), which column (`moved`): nothing of it placed or drawn anew, so nothing asks a
/// frame for it but this; where it moved, as of the moment drawn, is Tree::scroll_off_of's.
pub fn Tree::on_offset(self : Tree, moved : (NodeId) -> Unit) -> Unit {
  self.offset_moved = moved
}

///|
/// Column `at` (View::scrolls) moved what it scrolls by its offset alone (Node's scroll_off), at the logic's moment: what
/// the pointer is within told anew where it is a mouse's (Tree::withins_told: what is under it moved, the pointer not),
/// what goes beside one of what it holds placed again (View::beside: the popover of a row of it goes with it), and what
/// hosts the tree told (Tree::on_offset).
fn Tree::offset_told(self : Tree, at : Int) -> Unit {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return }
  let id = { at, gen: self.nodes[at].gen }
  if self.pointer_xy.0 >= 0.0 {
    self.withins_told() |> ignore
  }
  for b in self.besides_at {
    match self.nodes[b].beside {
      Some(s) if self.nodes[b].live && self.alive_id(s.anchor) && self.holds_at(at, s.anchor.at) =>
        self.place_marked_at(b)
      _ => ()
    }
  }
  (self.offset_moved)(id)
}

///|
/// How far node `n` is drawn off by the column that scrolls it (Node's scroll_off) at the moment what is drawn is drawn,
/// read once, nothing followed: what moves it says so (Tree::on_offset). Nothing where none does.
fn Tree::scroll_off_now(self : Tree, n : Node) -> (Double, Double) {
  match n.scroll_off {
    Some(f) => @signals.untracked(fn() { f(self.clock.get()) })
    None => (0.0, 0.0)
  }
}

///|
/// How far node `id` is drawn off at `t` by the column that scrolls it (Node's scroll_off: a page's list's held, its
/// bar's thumb), read once, nothing followed; none where nothing scrolls it so (or it is let go).
pub fn Tree::scroll_off_of(self : Tree, id : NodeId, t : Double) -> (Double, Double)? {
  guard self.alive_id(id) else { return None }
  match self.nodes[id.at].scroll_off {
    Some(f) => Some(@signals.untracked(fn() { f(t) }))
    None => None
  }
}

///|
/// The column that scrolls node `id` by its offset alone (Node's scroll_off): -1 where none does.
pub fn Tree::scroll_off_by(self : Tree, id : NodeId) -> Int {
  guard self.alive_id(id) else { return -1 }
  if self.nodes[id.at].scroll_off is Some(_) {
    self.nodes[id.at].scroll_by
  } else {
    -1
  }
}

///|
/// When what column `at` (View::scrolls) is on by itself ends as it is now (Scroll::glides_till: a fling, a wheel's
/// notches easing in, what shows past an end going back), nothing followed: none at rest, held, or where it scrolls
/// nothing.
pub fn Tree::glide_end_of(self : Tree, at : Int) -> Double? {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return None }
  match self.scrolls_at.get(at) {
    Some(s) => s.glides_till()
    None => None
  }
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
/// How a page's list (Scroll::list) moves where what hosts the tree draws it, as it is asked (as the platform's own
/// lists: an old view's list's way there), and how many pixels a point is there (Android's fling and stretch are in
/// them); none said, the desktop's, at 1.
pub fn Tree::lists_feel(self : Tree, f : () -> (ListFeel, Double)) -> Unit {
  self.list_feel = f
}

///|
/// Whether the pointer now drags what scrolls up or down (a page's list, a plain column) as a finger does, as it is
/// asked: not where a desktop's page says the mouse drags no list (the wheel and the trackpad scroll it, a drag is the
/// pointer's own: words picked), its column then taking over no hold to scroll (View::scrolls' `claims`); one scrolled
/// across (a code block, a table) still dragged along its row, as an old view's sideways box is. None said, it does.
/// The bridge of the old frames' saying (ui's Ctx::mouse_drags_lists, the last said holding): once the frames are
/// nodes, the tree's own.
pub fn Tree::pointer_drags_scroll(self : Tree, f : () -> Bool) -> Unit {
  self.drags_scroll = f
}

///|
/// Whether motion is reduced where what hosts the tree draws it, as it is asked: what a structure makes or lets go
/// there at once, no way made (View::comes); none said, not.
pub fn Tree::reduces_motion(self : Tree, f : () -> Bool) -> Unit {
  self.motion_reduced = f
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
    if !self.takes_presses(id) || !self.allows(id) || self.leaving_at(id.at) || !self.said_now(id.at) {
      return
    }
    match self.nodes[id.at].on_press {
      Some(f) => {
        pressed.val = true
        let held = self.press_stays(id)
        f()
        held()
      }
      None => ()
    }
  })
  pressed.val
}

///|
/// What a step up (`by` 1) or down (-1) asked of it does (a slider's, as a screen reader moves it: its Increment and
/// Decrement): run outside any tracking, as one change, as a press is (View::on_press).
pub fn View::on_step(self : View, f : (Int) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_step = Some(f)
  self.tree.said_marked(self.at, words=false, state=true)
  self
}

///|
/// A step `by` asked of node `id` at moment `at` (a screen reader's Increment, 1, or Decrement, -1), done as its
/// press would be (Tree::activate_at): where it takes it now. Whether it was taken.
pub fn Tree::step_at(self : Tree, id : NodeId, by : Int, at : Double) -> Bool {
  let stepped = Ref(false)
  self.event(at, fn() {
    self.pull()
    if !self.takes_presses(id) || !self.allows(id) || self.leaving_at(id.at) || !self.said_now(id.at) {
      return
    }
    match self.nodes[id.at].on_step {
      Some(f) => {
        stepped.val = true
        f(by)
      }
      None => ()
    }
  })
  stepped.val
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
/// then is it looked for (one let go by then presses nothing) and its callback run. Let go at `place` in the window (a
/// finger's or the pointer's), it may be the second of two (View::on_double_press: what that says done in its place);
/// pressed otherwise (a screen reader's), a press alone.
pub fn Tree::run_press_at(
  self : Tree,
  id : NodeId,
  at : Double,
  place? : (Double, Double),
) -> Bool {
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
    // (the second of two, where it says what that does: that in its place, and none the first of the next)
    let second = match place {
      Some((wx, wy)) => self.pressed_twice(id, at, wx, wy)
      None => false
    }
    match (second, n.on_double_press, n.on_press) {
      (true, Some(f), _) | (false, _, Some(f)) | (true, None, Some(f)) => {
        pressed.val = true
        let held = self.press_stays(id)
        f()
        held()
      }
      _ => ()
    }
  })
  pressed.val
}

///|
/// `f` done with what `read` gives (as it is now, then as of each change of it: at its cause's moment, committed as a
/// structure's change is), whatever frames are drawn: what is to be done as a state comes to hold, said so, never found
/// by watching it frame by frame. Not `at_start`: as of its changes alone, not as it is when said (a state's turning,
/// not its holding). The node's: done no more once it is let go.
pub fn[T : Eq] View::reacts(self : View, read : () -> T, f : (T) -> Unit, at_start? : Bool = true) -> Unit {
  // (made, and done each time, owned by the node's scope: what it makes let go with the node, its watch none of what
  // was running as it was said, whose running again would let it go)
  self.owning(fn() {
    let stop = self.tree.structured(read, fn(v) { self.owning(fn() { f(v) }) }, at_start~)
    self.owns(stop) |> ignore
  })
}

///|
/// `f` done once at the moment `when` of the one clock (its timeline: in its turn among what is due, as of then;
/// Tree::advance), whatever frames are drawn: what is to show, go or be done at a moment said so, never found by watching
/// the clock. The node's: not done once it is let go, or once what it returns is called. What is to be done is waited
/// for, as what has yet to happen (Tree::wake_waited: a test's run goes on to it, and is not idle before it); `later`,
/// not: a time what is shown does not wait for (a toast's time on screen), as an old view's wake said `later` is. A
/// `when` gone by as it is asked is done at the moment it is asked (Tree::cause_now then), never before it.
#callsite(autofill(loc))
pub fn View::at_moment(
  self : View,
  when : Double,
  f : () -> Unit,
  later? : Bool = false,
  loc~ : SourceLoc,
) -> () -> Unit {
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
  // (a moment gone by as it is asked (a way's end that never set out: 0) is done at the moment it is asked, its cause's
  // that one, never at the one gone by: what is committed with it is not told as of before what asked it; one between
  // two frames, at its own (the coordinator of the migration, 2026-11-12))
  let at = dmax(when, tree.cause_now())
  tree.timeline.push(Once({ at, f: done, live, later, by: loc.to_string() }, tree.told))
  tree.told = tree.told + 1
  tree.marked()
  stop
}

///|
/// What holds for `ms` from each event (a word said a moment once pressed: 已复制 for a while after each copy), owned by
/// the node: told (the first of what this returns) as an event is handled, it holds from that event's moment (its
/// cause's, View::cause_at) till that moment and `ms`; told again meanwhile, its end is set again from the new moment, the
/// one before taken off the timeline (its one due there, set again in place, as a leaving's end is: no count of events,
/// no handle kept by its caller). Whether it holds now is the second (what reads it followed: told as it starts and as it
/// ends, not as the clock goes). Its end is waited for (Tree::wake_waited: a test's run goes on to it) unless `later` (a
/// time what is shown does not wait for, as View::at_moment's). Let go with the node: its end taken off the timeline,
/// told no more.
pub fn View::holds_for(self : View, ms : Double, later? : Bool = false) -> (() -> Unit, () -> Bool) {
  let h : Hold = { ms, on: @signals.signal(false, same=fn(a, b) { a == b }), until: -1.0, live: Ref(true), later }
  let tree = self.tree
  guard self.live() is Some(_) else { return (fn() {  }, fn() { h.on.get() }) }
  let unkeep = self.owns_while(fn() {
    if h.live.val {
      h.live.val = false
      h.until = -1.0
      tree.unschedule(h.live)
    }
  })
  ignore(unkeep)
  let event = fn() {
    guard h.live.val else { return }
    if h.until < 0.0 {
      tree.timeline.push(Holds(h, tree.told))
      tree.told = tree.told + 1
    }
    h.until = tree.cause_now() + h.ms
    h.on.set(true)
    tree.marked()
  }
  (event, fn() { h.on.get() })
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
  self.tree.ground_reads(ground_read_hand)
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
  self.tree.ground_reads(ground_read_hand)
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
  self.tree.ground_reads(ground_read_hand)
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
      // (once for it and which piece of it the pointer is over: View::pointer_piece)
      if n.piece_cell is None {
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
        if cell.untracked() != now {
          changed = true
          cell.set(now)
        }
      }
      None => ()
    }
    match n.piece_cell {
      Some((cell, piece)) => {
        let now = self.piece_in(at, piece)
        if cell.untracked() != now {
          changed = true
          cell.set(now)
        }
      }
      None => ()
    }
    if n.within_cell is Some(_) || n.piece_cell is Some(_) {
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
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
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
        if cell.untracked() != now {
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
fn Tree::alive_id(self : Tree, id : NodeId) -> Bool {
  // (read unchecked once its index is known to be one of the nodes')
  id.at >= 0 &&
  id.at < self.nodes.length() && {
    let n = self.nodes.unsafe_get(id.at)
    n.live && n.gen == id.gen
  }
}

///|
/// The box `v` a structure made since `said` properties had been said (Tree::said_count): where it made nothing
/// (Tree::made_none), so said of its box (flex's Style structural: nothing to a box that takes no room holding nothing
/// while it holds no box). Whether it made nothing.
fn Tree::structural(self : Tree, v : View, said : Int) -> Bool {
  guard v.live() is Some(n) && self.made_none(v.at, said) else { return false }
  n.flex.style.structural = true
  true
}

///|
/// Whether node `at`, a structure's box made since `said` properties had been said (Tree::said_count), made nothing:
/// none said on what it made, and no box in it.
fn Tree::made_none(self : Tree, at : Int, said : Int) -> Bool {
  if self.said_count != said {
    return false
  }
  let into : Array[@flex.Node] = []
  for k in self.nodes[at].kids {
    self.boxes(k, into)
  }
  into.is_empty()
}

///|
/// What a point hits may have changed: told so (Tree::hits_said); in a change (an event, a moment's change, a binding a
/// change told, not the clock), what is under a still pointer owed to be worked out again at that change's moment
/// (Tree::hand_now). As a way goes, nothing: what moves under a still pointer is worked out once, at its end
/// (Tree::hand_at_end).
fn Tree::hits_bump(self : Tree) -> Unit {
  self.hits = self.hits + 1
  let in_change = if self.laying {
    // (a frame's laying out (its rooms, what it measures): its own, unless a binding a change told runs in it)
    self.binding_running > 0 && !self.bound_by_clock && self.cause_at >= 0.0
  } else {
    self.committing > 0 || (self.cause_at >= 0.0 && !self.bound_by_clock)
  }
  if !self.handing && in_change {
    let at = self.cause_now()
    if !self.hand_owed || at > self.hand_owed_at {
      self.hand_owed_at = at
    }
    self.hand_owed = true
  }
}

///|
/// A moment `at` a way that may move something under a still pointer ends (View::drawn_past's, a structure's way in or
/// out, a glide, a Way read as it goes): what is under it worked out again then, a moment of the timeline, once for each
/// moment, whatever frames are drawn; where another said ends later, at that one instead (once all of it is at rest).
pub fn Tree::hand_at_end(self : Tree, at : Double) -> Unit {
  if !(at > self.logic) || !(at > self.hand_ends_done) || at == @double.infinity || self.hand_ends.contains(at) {
    return
  }
  self.hand_ends.add(at)
  let live = Ref(true)
  self.timeline.push(
    Once(
      {
        at,
        f: fn() {
          self.hand_ends.remove(at)
          if at > self.hand_ends_done {
            self.hand_ends_done = at
          }
          // (worked out once all that goes then is at rest: a later end still to come does it then)
          if self.hand_ends.iter().any(fn(e) { e > at }) {
            return
          }
          self.hand_owed = true
          if at > self.hand_owed_at {
            self.hand_owed_at = at
          }
          self.sight_owe(at)
        },
        live,
        later: true,
        by: "",
      },
      self.told,
    ),
  )
  self.told = self.told + 1
  self.marked()
}

///|
/// The latest moment a way under way now ends, as the ways said it (Tree::hand_at_end: a Move, a way in or out, a
/// glide, a Way read as it goes): where all that moves now comes to rest; -1 where none is on its way (what a finger
/// drags has no end said: none). The Tester's to read (where the focus a key moved comes to rest:
/// ui's tester_focus_off.mbt), never an app's: what is built or done reads no motion's state (the app's AGENTS.md:
/// no logic reads whether a motion runs).
pub fn Tree::ways_end(self : Tree) -> Double {
  let mut end = -1.0
  for e in self.hand_ends {
    if e > end {
      end = e
    }
  }
  end
}

///|
/// What is under a still pointer told to what follows the hand (Tree::on_hand) where a change or a way's end owed it,
/// as the change is told whole: once, at its moment.
fn Tree::hand_now(self : Tree) -> Unit {
  // (not in the middle of what is due being done: as that ends, its change or the frame it is of tells it)
  if !self.hand_owed || self.handing || self.advancing || self.committing > 0 || self.cause_at >= 0.0 {
    return
  }
  self.hand_owed = false
  let at = self.hand_owed_at
  self.hand_owed_at = -1.0
  self.handing = true
  self.hand_at = at
  (self.hand)(at)
  self.handing = false
}

///|
/// The moment what is drawn was last drawn or brought to (a frame's, an input's), not followed: whether a moment is
/// ahead of where the tree was laid out.
pub fn Tree::brought_at(self : Tree) -> Double {
  self.clock.untracked()
}

///|
/// What hosts the tree is told as what a still pointer is over may have changed, at the moment it did (a change's, a
/// way's end): the hand worked out there, nowhere else but at an input (Tree::point_at, what hosts the tree).
pub fn Tree::on_hand(self : Tree, hand : (Double) -> Unit) -> Unit {
  self.hand = hand
}

///|
/// A way that may move something under a still pointer ends at `at` (Tree::hand_at_end): what a Way read as it goes
/// says (motion's Way::shown_on).
pub fn View::hand_at_end(self : View, at : Double) -> Unit {
  // (read for how something looks alone: its end moves nothing under the pointer)
  if self.tree.looks_reading {
    return
  }
  self.tree.hand_at_end(at)
}

///|
/// What the page's lists have in sight owed to be told as of moment `at` (list_sight.mbt): at the hand's moments alone.
fn Tree::sight_owe(self : Tree, at : Double) -> Unit {
  // (no list told it: nothing owed, nothing kept)
  if self.sight_tellers.is_empty() {
    return
  }
  if !self.sight_owed || at > self.sight_owed_at {
    self.sight_owed_at = at
  }
  self.sight_owed = true
}

///|
/// What the page's lists have in sight told to what is told it where that is owed, as the change or the way's end it
/// is owed for is told whole (where Tree::hand_now tells the hand): in a change of its own at that moment, read off
/// their blocks as they are counted and their scrolls, nothing laid out or measured for it; nothing where no list is
/// told it.
fn Tree::sights_now(self : Tree) -> Unit {
  if self.sight_tellers.is_empty() ||
    !self.sight_owed ||
    self.sights_telling ||
    self.handing ||
    self.advancing ||
    self.committing > 0 ||
    self.cause_at >= 0.0 {
    return
  }
  self.sight_owed = false
  let at = if self.sight_owed_at >= 0.0 { self.sight_owed_at } else { self.logic_said() }
  self.sight_owed_at = -1.0
  self.sights_telling = true
  self.event(at, fn() {
    for _, t in self.sight_tellers {
      t()
    }
  })
  self.sights_telling = false
}
