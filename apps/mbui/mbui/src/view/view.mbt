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
/// A property's value: set once (`Is`), or worked out (`By`), tracked, and set again as what it read changes.
pub(all) enum Live[T] {
  Is(T)
  By(() -> T)
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
  /// how its words are set (View::words: their size, weight, line and whether they wrap)
  mut words_look : WordsLook
  /// the shadow it casts under its ground (blur, how far down, colour; 0 blur: none): View::shadow
  mut shadow : (Double, Double, Int64)
  /// the shapes it draws over its ground (their outlines, as said: what they come to drawn kept by them), and the one
  /// colour they are drawn in where it is not 0 (their own where it is): View::shapes, View::tint
  mut shapes : Array[@paint.Shape]
  mut tint : Int64
  /// how round its corners are (its ground's, its glass's), and the glass it is drawn as under what it draws (None: none):
  /// View::radius, View::glass
  mut radius : Double
  mut glass : @paint.Glass?
  /// the line drawn round its edge inside it, how wide and in what colour (0 wide: none): View::border
  mut border : Double
  mut border_ink : Int64
  mut alpha : Double
  mut dx : Double
  mut dy : Double
  /// and how far besides, in its own widths and heights as it is laid out (a page slid off by its width)
  mut sx : Double
  mut sy : Double
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
  words_look : WordsLook
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  tint : Int64
  radius : Double
  glass : @paint.Glass?
  /// the line round its edge, inside it (View::border)
  border : Double
  border_ink : Int64
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
} derive(Eq, Debug)

///|
/// Whether it draws anything of its own: a ground, words, shapes, glass, or what hosts it (the one place that says what
/// a node draws, for what asks whether it draws nothing: Tree::alone).
pub fn Content::draws(self : Content) -> Bool {
  self.ground != 0L ||
  self.words != "" ||
  !self.shapes.is_empty() ||
  self.glass is Some(_) ||
  self.border > 0.0 ||
  self.shadow.0 > 0.0 ||
  self.hosted
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
  shadow : (Double, Double, Int64)
  shapes : Array[@paint.Shape]
  tint : Int64
  radius : Double
  glass : @paint.Glass?
  border : Double
  border_ink : Int64
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
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
  /// bindings looked at as something asked at once (Tree::pull): those marked, each once
  mut pulled : Int
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
  kids : Array[Int]
  /// its scope (what it was made with, and what is set on it, owned), and what stops it
  mut owner : @signals.ReactiveNode?
  mut stop : (() -> Unit)?
  /// what else goes with it (View::owns, its structure's binding), run once as it is let go
  drops : Map[Int, () -> Unit]
  /// the key the next of them is kept by
  mut drop_next : Int
  /// its properties' bindings, by property: what stops each
  props : Map[Int, () -> Unit]
  mut on_press : (() -> Unit)?
  /// what the pointer's secondary button pressed on it asks for (View::on_menu)
  mut on_menu : ((Menu) -> Unit)?
  /// what a wheel turned over it does (View::on_wheel)
  mut on_wheel : ((Wheel) -> Unit)?
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
  /// whether it takes input now as what reads it reads it (View::takes_input): made as first read, let go with it
  mut input_cell : @signals.Signal[Bool]?
  /// whether it can take the keyboard's focus, which of Enter (1) and Space (2) press it as it has it (View::focusable;
  /// none: it takes the focus all the same, pressed by no key), and its cells of whether it has it and it shows (View::focused, View::focus_shown): made as first read, let go
  /// with it
  mut focusable : Bool
  /// the pointer's shape over it, said (View::cursor; none: as it is shown without being told, Tree::cursor_of)
  mut cursor : Cursor?
  /// what it is placed beside (View::beside: its anchor, the side, how along it), placed so as the tree is placed
  mut beside : Beside?
  mut focus_keys : Int
  mut focused_cell : @signals.Signal[Bool]?
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
  /// drawn by what hosts the tree (View::hosted)
  mut hosted : Bool
  /// what it says it is, read out (View::says); None nothing
  mut said : Said?
  /// what it and all it holds are kept from what is read out (View::hides)
  mut said_hidden : Bool
  /// its instance to be made again (its look changed); its place (and what it holds) to be worked out again
  mut look_due : Bool
  mut place_due : Bool
  /// where it is in what holds it (its layout's place and its own offset), how opaque of itself, how big: worked out
  /// once it is placed
  mut placed : Bool
  mut lx : Double
  mut ly : Double
  mut la : Double
  mut lw : Double
  mut lh : Double
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
  /// it is a modal layer while this holds (View::modal): what it does not hold takes no input
  mut modal : Bool
}

///|
/// The nodes made once of a window, its clock and what it did.
pub struct Tree {
  /// the moment what is drawn is drawn at (a frame's, to be shown then), a signal a look follows (Tree::drawn_at); the
  /// logic follows no clock (its moment `logic`, what is due on its timeline said once: Tree::advance)
  clock : @signals.Signal[Double]
  /// the time now, as a change is told (the host's: an event's moment, before a frame takes it); none: the clock's
  time : (() -> Double)?
  /// the moment the change a queued binding works out was told, while it is (-1: none)
  mut cause_at : Double
  /// how words are measured: (words, how they are set, width offered) -> (width, height)
  measure : (String, WordsLook, Double) -> (Double, Double)
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
  /// what is due being done (Tree::advance)
  mut advancing : Bool
  /// where its logic stands: what is due by then done (Tree::advance), what is said from then on said as of then at the
  /// earliest
  mut logic : Double
  /// the bindings whose reads changed, to run as the frame begins (Tree::queued)
  bindings_due : Array[Bound]
  /// every binding's watch and what runs it, by a number of its own, while it lives (let go as it stops): what is asked
  /// at once (View::laid_size, Tree::bring_to) pulls those whose reads changed by then, told or not
  pulls : Map[Int, (@signals.Watch, Bound)]
  mut pulls_made : Int
  /// those marked as what they read changed, since they last ran (Tree::pull)
  pulls_marked : Array[Int]
  mut layout_due : Bool
  mut order_due : Bool
  mut due : Bool
  mut last_w : Double
  mut last_h : Double
  /// the window's size, as its frames give it: what is laid out by it (which frame a window's width calls for) follows it
  room : @signals.Signal[(Double, Double)]
  /// the nodes drawn, in the order they are drawn (no slot), and where in it what holds each is (-1: the window)
  order : Array[Int]
  order_holder : Array[Int]
  /// the node hosting the old view, if any (View::hosted)
  mut hosting : Int
  /// the nodes said to be modal layers (View::modal, on), living: which is topmost asked of where each is among what
  /// holds it (Tree::modal_top)
  modals : Array[Int]
  /// how deep in a change being committed (Tree::at_cause, an event) it is now, and whether what a modal layer said is to
  /// be told as all of it is committed (Tree::modals_told): what a change does in between (a row put after the rest,
  /// then put in its place) never seen half done
  mut committing : Int
  mut modals_due : Bool
  /// the node a finger is held on (View::on_drag), from its down till it is let go, called off or the node goes
  mut held : NodeId?
  /// a finger held on a node a still hold of which is what lies under it's (View::holds_through): what lies there, as it
  /// was found as the finger went down, its hold's moment set going
  mut through : Through?
  /// what hosts the tree told of a hold handed to what it hosts (Tree::on_through), and asked whether what it hosts
  /// takes a press at a point (Tree::hosts_at)
  mut on_through : (Target, Double, Double, Double) -> Unit
  mut hosts_at : (NodeId, Double, Double) -> Int?
  /// the node a finger or the pointer is held on, and the one the pointer is over (of those that take a press): each
  /// node's own cell told as it comes or goes (View::pressed, View::pointed)
  mut pressing : NodeId?
  mut pointed : NodeId?
  /// the node with the keyboard's focus, and whether it shows (it came by the keyboard): its cells told as it comes or
  /// goes (View::focused); what hosts the tree told as it is let go of at a cause (the node let go, leaving, taking
  /// no press, under a modal layer: Tree::on_focus_lost)
  /// the node a back gesture is held by, as it said it then (Tree::back_step): from its start till it is let go,
  /// called off or the node goes
  mut backing : (NodeId, Int)?
  mut focused : NodeId?
  mut focus_visible : Bool
  mut on_focus_lost : (NodeId) -> Unit
  /// what follows what is under the pointer, while it is over the window (Tree::point_at)
  mut point_stop : (() -> Unit)?
  /// let go (Tree::dispose): what is made for it after stops at once
  mut gone : Bool
  /// the nodes said to go beside another (View::beside), as said (each let go is passed over, and dropped as placed)
  besides_at : Array[Int]
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
  mut drawn_due : Bool
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
/// A tree whose root `make` makes (as the root's own: its bindings, its nodes), its words measured by `measure`.
pub fn Tree::new(
  make : (View) -> Unit,
  measure? : (String, WordsLook, Double) -> (Double, Double) = words_measure,
  time? : () -> Double,
) -> Tree {
  // (the moment it is made, taken once: its logic and what it draws start there, and what it is made with is of then)
  let start = match time {
    Some(f) => f()
    None => 0.0
  }
  let t : Tree = {
    clock: @signals.signal(start, same=fn(a, b) { a == b }),
    room: @signals.signal((0.0, 0.0), same=fn(a, b) { a == b }),
    time,
    cause_at: -1.0,
    measure,
    nodes: [],
    free: [],
    looks_due: [],
    places_due: [],
    bindings_due: [],
    pulls: {},
    pulls_made: 0,
    pulls_marked: [],
    timeline: [],
    told: 0,
    advancing: false,
    logic: start,
    layout_due: true,
    order_due: true,
    due: true,
    last_w: -1.0,
    last_h: -1.0,
    order: [],
    order_holder: [],
    hosting: -1,
    modals: [],
    committing: 0,
    modals_due: false,
    held: None,
    through: None,
    on_through: fn(_, _, _, _) {  },
    hosts_at: fn(_, _, _) { None },
    pressing: None,
    pointed: None,
    backing: None,
    focused: None,
    focus_visible: false,
    on_focus_lost: fn(_) {  },
    point_stop: None,
    gone: false,
    besides_at: [],
    inputs_at: [],
    point_said: 0,
    hits: 0,
    downs: [],
    changed: [],
    composed: [],
    removed: [],
    pending: [],
    drawn_due: false,
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
      pulled: 0,
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
      n.flex = @flex.Node::new()
      n.look.ground = 0L
      n.look.ink = 0L
      n.look.words = ""
      n.look.shapes = []
      n.look.tint = 0L
      n.look.radius = 0.0
      n.look.glass = None
      n.look.border = 0.0
      n.look.border_ink = 0L
      n.look.words_look = words_plain
      n.look.shadow = (0.0, 0.0, 0L)
      n.said = None
      n.said_hidden = false
      n.look.alpha = 1.0
      n.look.dx = 0.0
      n.look.dy = 0.0
      n.look.sx = 0.0
      n.look.sy = 0.0
      n.parent = parent
      n.slot = false
      n.hosted = false
      n.on_press = None
      n.on_menu = None
      n.on_wheel = None
      n.on_key = None
      n.on_back = None
      n.on_back_step = None
      n.pressed_cell = None
      n.pointed_cell = None
      n.focusable = false
      n.focus_keys = 0
      n.input_cell = None
      n.cursor = None
      n.beside = None
      n.focused_cell = None
      n.focus_shown_cell = None
      n.key_said = 0
      n.on_drag = None
      n.takes = None
      n.takes_units = []
      n.takes_ver = None
      n.drag_end = None
      n.look_due = false
      n.place_due = false
      n.placed = false
      n.content = None
      n.left_at = -1.0
      n.span = 0.0
      n.back_at = -1.0
      n.back_from = 0.0
      n.going = None
      n.inert = false
      n.modal = false
      i
    }
    None => {
      self.nodes.push({
        gen: 0,
        live: true,
        flex: @flex.Node::new(),
        look: { ground: 0L, ink: 0L, words: "", words_look: words_plain, shadow: (0.0, 0.0, 0L), shapes: [], tint: 0L, radius: 0.0, glass: None, border: 0.0, border_ink: 0L, alpha: 1.0, dx: 0.0, dy: 0.0, sx: 0.0, sy: 0.0 },
        parent,
        kids: [],
        owner: None,
        stop: None,
        drops: {},
        drop_next: 0,
        props: {},
        on_press: None,
        on_menu: None,
        on_wheel: None,
        on_key: None,
        key_said: 0,
        on_back: None,
        on_back_step: None,
        back_said: 0,
        pressed_cell: None,
        pointed_cell: None,
        focusable: false,
        input_cell: None,
        cursor: None,
        beside: None,
        focus_keys: 0,
        focused_cell: None,
        focus_shown_cell: None,
        on_drag: None,
        fingers: 1,
        drag_said: 0,
        takes: None,
        takes_units: [],
        takes_ver: None,
        drag_end: None,
        slot: false,
        hosted: false,
        said: None,
        said_hidden: false,
        look_due: false,
        place_due: false,
        placed: false,
        lx: 0.0,
        ly: 0.0,
        la: 1.0,
        lw: 0.0,
        lh: 0.0,
        content: None,
        left_at: -1.0,
        span: 0.0,
        back_at: -1.0,
        back_from: 0.0,
        going: None,
        inert: false,
        modal: false,
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
/// The clock set to `ms` (a frame's time).
pub fn Tree::at(self : Tree, ms : Double) -> Unit {
  self.clock.set(ms)
}

///|
/// What it did so far.
pub fn Tree::work(self : Tree) -> Work {
  { ..self.work }
}

///|
/// How many nodes live.
pub fn Tree::alive(self : Tree) -> Int {
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
  self.looks_due.clear()
  self.places_due.clear()
  self.bindings_due.clear()
  self.pulls.clear()
  self.pulls_marked.clear()
  self.timeline.clear()
  self.order.clear()
  self.order_holder.clear()
  self.changed.clear()
  self.composed.clear()
  self.hosting = -1
  self.modals.clear()
}

///|
/// A node made in `self`, after what it holds already, made by `make` as its own (in its scope).
pub fn View::box(self : View, make : (View) -> Unit) -> View {
  guard self.live() is Some(n) else { return self.tree.none() }
  let v = self.tree.made(self.at)
  n.kids.push(v.at)
  self.boxes_again()
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
/// Where it is drawn, in the window (what holds it drawn off with it, its own offset with it), and how big: where a
/// press finds it as where it is drawn.
pub fn View::rect(self : View) -> (Double, Double, Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0, 0.0, 0.0) }
  let (x, y, _) = self.tree.placed(self.at)
  (x, y, n.flex.width, n.flex.height)
}

///|
/// Where node `at` is drawn in the window and how opaque, from the root down: its holders' places, offsets and
/// opacities with its own (a slot adds nothing of its own).
fn Tree::placed(self : Tree, at : Int) -> (Double, Double, Double) {
  let chain : Array[Int] = []
  let mut i = at
  while i >= 0 {
    chain.push(i)
    i = self.nodes[i].parent
  }
  let mut x = 0.0
  let mut y = 0.0
  let mut a = 1.0
  for k = chain.length() - 1; k >= 0; k = k - 1 {
    let n = self.nodes[chain[k]]
    if !n.slot {
      x = x + n.flex.left + n.look.dx + n.look.sx * n.flex.width
      y = y + n.flex.top + n.look.dy + n.look.sy * n.flex.height
      a = a * n.look.alpha
    }
  }
  (x, y, a)
}

///|
/// Something for a frame to do: what hosts it told as there first is.
fn Tree::marked(self : Tree) -> Unit {
  if !self.due {
    self.due = true
    (self.on_due)()
  }
}

///|
/// Its layout to be done again: itself and every node up to the root (one marked before and not laid out since, its
/// holder's layout reused, is no sign the rest are).
fn Tree::layout_marked_at(self : Tree, at : Int) -> Unit {
  self.layout_due = true
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
/// Its instance to be made again.
fn Tree::look_marked_at(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.look_due {
    n.look_due = true
    self.looks_due.push(at)
    self.marked()
  }
}

///|
/// Its place (how far it is drawn off, how opaque) to be worked out again, what it holds with it.
fn Tree::place_marked_at(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.place_due {
    n.place_due = true
    self.places_due.push(at)
    self.hits = self.hits + 1
    self.marked()
  }
}

///|
/// The order the nodes are drawn in to be made again (one made, let go or moved among its siblings).
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
  // (its one state, every way it is run read from it: queued for a frame (told as a change ended), marked as what it
  // read changed (in a change's batch too: what asks at once pulls it), live; run once it is due, by any of them, and
  // done with all of them)
  let b : Bound = { queued: false, marked: false, live: true, run: fn() {  } }
  // (when what it read was told changed: its cause's moment, whatever frame works it out)
  let told_at = Ref(-1.0)
  let k = self.pulls_made
  self.pulls_made = k + 1
  let w = @signals.watch(fn() {
    if b.live && !b.queued {
      b.queued = true
      told_at.val = match self.time {
        Some(f) => f()
        None => self.logic
      }
      self.bindings_due.push(b)
      self.marked()
    }
  })
  w.on_marked(fn() {
    if b.live && !b.marked {
      b.marked = true
      self.pulls_marked.push(k)
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
  self.pulls[k] = (w, b)
  fn() {
    b.live = false
    b.run = fn() {  }
    self.pulls.remove(k)
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
    for k in marked {
      match self.pulls.get(k) {
        Some((w, b)) if b.marked => {
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
  self.pulls.length()
}

///|
/// A structure's binding (what shows, which is picked, which rows): `read` worked out as what it read changes, and
/// where it came out otherwise, `then` done then (the structure's change committed with the change that caused it, at
/// that change's moment: what it makes reads the state as it is then, what leaves starts leaving then), what had left
/// by that moment let go first. Layout, words and paint of what it makes wait for the frame. Run now with the target
/// it starts at. What stops it.
fn[T : Eq] Tree::structured(self : Tree, read : () -> T, then : (T) -> Unit) -> () -> Unit {
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
    match self.time {
      Some(now) => now()
      None => self.logic
    }
  }
  self.advance(at)
  let was = self.cause_at
  self.cause_at = at
  self.committing += 1
  // (one change, as an event is: what it writes told once all of it is written, never what follows it running
  // between two of its writes and seeing half of it)
  @signals.start_batch()
  let changed = f()
  @signals.end_batch()
  self.committing -= 1
  self.modals_settled()
  self.cause_at = was
  if changed {
    self.marked()
  }
}

///|
/// Property `prop` of the node (its one binding: one bound before is let go), set by `apply`: once, or as what it
/// reads changes (Tree::queued: as the frame takes it), set again only if it came out otherwise than it last did,
/// marking what its phase does again.
fn[T : Eq] View::bind(self : View, prop : Int, live : Live[T], phase : Phase, apply : (T) -> Unit) -> Unit {
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
  }
}

///|
/// Its width (points; None: as its content and its holder make it).
pub fn View::width(self : View, w : Live[Double?]) -> View {
  self.bind(0, w, Layout, fn(w) {
    self.tree.nodes[self.at].flex.style.set_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
  })
  self
}

///|
/// Its height (points; None: as its content and its holder make it).
pub fn View::height(self : View, h : Live[Double?]) -> View {
  self.bind(1, h, Layout, fn(h) {
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
  self.bind(2, p, Layout, fn(p) {
    let s = self.tree.nodes[self.at].flex.style
    s.set_padding_left(Pt(p.0))
    s.set_padding_top(Pt(p.1))
    s.set_padding_right(Pt(p.2))
    s.set_padding_bottom(Pt(p.3))
  })
  self
}

///|
/// Room inside it, the same on every side (its padding).
pub fn View::pad(self : View, p : Live[Double]) -> View {
  self.padding(
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
pub fn View::sides(self : View, lr : Live[(Double, Double)]) -> View {
  self.padding(
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
pub fn View::row(self : View, across : Live[Bool]) -> View {
  self.bind(3, across, Layout, fn(a) { self.tree.nodes[self.at].flex.style.direction = if a { Row } else { Column } })
  self
}

///|
/// How much of the room left it takes.
pub fn View::grow(self : View, g : Live[Double]) -> View {
  self.bind(4, g, Layout, fn(g) { self.tree.nodes[self.at].flex.style.grow = g })
  self
}

///|
/// How big it is laid out as of the logic's moment (Tree::logic_at): what was told before it laid out first (what an event
/// changed before it asks, laid out as a frame would), as of the window's size its last frame gave (0 by 0 before the
/// first). For what is said at a moment by how big a thing is then (how long a slide across it takes), never followed.
pub fn View::laid_size(self : View) -> (Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0) }
  // (laid out as of the logic's moment, what the change under way set so far counted, nothing of the logic run)
  self.tree.laid_now()
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
  self.bind(9, on, Layout, fn(on) {
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
/// Its ground (0: none): paint's.
pub fn View::ground(self : View, ink : Live[Int64]) -> View {
  self.bind(5, ink, Paint, fn(k) { self.tree.nodes[self.at].look.ground = k })
  self
}

///|
/// The shapes it draws over its ground, in its own terms from its top left (@paint.Shape: outlines filled and stroked):
/// paint's. What they come to as they are drawn is worked out once for the shapes said (their outlines), whatever colour
/// they are drawn in (View::tint).
pub fn View::shapes(self : View, shapes : Live[Array[@paint.Shape]]) -> View {
  self.bind(13, shapes, Paint, fn(s) { self.tree.nodes[self.at].look.shapes = s })
  self
}

///|
/// The one colour its shapes are drawn in (0: each its own): paint's; a change of it draws them again in it, nothing of
/// their outlines worked out again.
pub fn View::tint(self : View, ink : Live[Int64]) -> View {
  self.bind(14, ink, Paint, fn(k) { self.tree.nodes[self.at].look.tint = k })
  self
}

///|
/// The line drawn round its edge, inside it, in its corners (`width` wide, in `ink`; 0 wide: none), as it changes:
/// paint's. What draws it is its own, a ground or none under it.
pub fn View::border(self : View, line : Live[(Double, Int64)]) -> View {
  self.bind(21, line, Paint, fn(l) {
    let n = self.tree.nodes[self.at]
    n.look.border = l.0
    n.look.border_ink = l.1
  })
  self
}

///|
/// How round its corners are (its ground's and its glass's; a linked corner's as worked out where it is said): paint's.
pub fn View::radius(self : View, r : Live[Double]) -> View {
  self.bind(15, r, Paint, fn(r) { self.tree.nodes[self.at].look.radius = r })
  self
}

///|
/// The glass it is drawn as, under its ground and what it draws (@paint.Glass: frosted or liquid; None: none): paint's.
/// What it frosts is what the frame drew under it, wherever it is composed (its capture told as the frame is).
pub fn View::glass(self : View, g : Live[@paint.Glass?]) -> View {
  self.bind(16, g, Paint, fn(g) { self.tree.nodes[self.at].look.glass = g })
  self
}

///|
/// How opaque it is drawn, what it holds with it: its place's.
pub fn View::alpha(self : View, a : Live[Double]) -> View {
  self.bind(6, a, Place, fn(a) { self.tree.nodes[self.at].look.alpha = a })
  self
}

///|
/// How far it is drawn off where it is laid out, what it holds with it: its place's (a move on the compositor: never
/// laid out again).
pub fn View::offset(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(7, d, Place, fn(d) {
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
  self.bind(10, d, Place, fn(d) {
    let n = self.tree.nodes[self.at]
    n.look.sx = d.0
    n.look.sy = d.1
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
  match n.props.get(11) {
    Some(stop) => {
      n.props.remove(11)
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
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[11] = stop
      })
  }
  self
}

///|
/// A modal layer while `on` holds (said at the moment it changes, as whether it takes presses is: View::presses): the
/// topmost such of the tree's (by the order it is drawn in) takes all input; what it does not hold, drawn under it,
/// takes none (no press, no finger, no menu, no wheel: Tree::allows, and what a host asks of it: an old view's keys,
/// its stops for Tab, what of it is read out). Its turning off is at once, as it is said (a viewer closing gives the
/// pages their input back as it begins to go, whatever is still drawn of it).
pub fn View::modal(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(12) {
    Some(stop) => {
      n.props.remove(12)
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
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[12] = stop
      })
  }
  self
}

///|
/// A modal layer said on or off, or where what is drawn is among what holds it changed (one made, let go, moved, back
/// from leaving): a finger held on what the topmost no longer lets take input called off, and what hosts the tree told
/// (Tree::on_modals), once the change doing it is committed whole, at that change's moment (Tree::modals_settled).
fn Tree::modals_told(self : Tree) -> Unit {
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
}

///|
fn Tree::modals_now(self : Tree) -> Unit {
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
      Some((b, _)) if !self.allows(b) => self.back_lost_in(0)
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
    guard self.path_of(at) is Some(path) else { continue }
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
fn Tree::allows_at(self : Tree, at : Int) -> Bool {
  match self.modal_top() {
    None => true
    Some(m) => {
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
    let (mw, mh) = (tree.measure)(tree.nodes[at].look.words, tree.nodes[at].look.words_look, offered)
    match wm {
      Exactly => (w, mh)
      _ => (mw, mh)
    }
  })
  self.bind(8, words, Both, fn(s) { tree.nodes[at].look.words = s })
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
  n.on_wheel = Some(f)
  self
}

///|
/// A wheel turned at (x, y) in the window at `at` (`dx`, `dy`, `mods` as the host says them): where the topmost node
/// drawn there that takes a press takes the wheel (View::on_wheel), it is that node's, as one event of that moment;
/// true then. None where the topmost is one that does not (or hosts the old view, or nothing is there).
pub fn Tree::wheel_at(
  self : Tree,
  x : Double,
  y : Double,
  dx : Double,
  dy : Double,
  mods : Int,
  at : Double,
) -> Bool {
  self.asked_at(x, y, at, fn(n) { n.on_wheel is Some(_) }, fn(n, lx, ly, t) {
    match n.on_wheel {
      Some(f) => f({ x: lx, y: ly, wx: x, wy: y, dx, dy, mods, at: t })
      None => ()
    }
  })
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
/// takes it, as one event of that moment (the tree brought there first where it is in none). True where one took it.
pub fn Tree::key_at(self : Tree, code : Int, mods : Int, at : Double) -> Bool {
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
    self.each_drawn(fn(c, cx, cy, _) {
      if x >= cx && y >= cy && x < cx + c.w && y < cy + c.h && !self.pressless_at(c.id.at) {
        let n = self.nodes[c.id.at]
        let here = @signals.untracked(fn() { self.takes_here(n, x - cx, y - cy, c.w, c.h, now) })
        if here && (takes(n) || n.on_drag is Some(_) || n.on_press is Some(_) || n.hosted) {
          found.val = Some(c.id)
        }
      }
    })
    match found.val {
      Some(id) => {
        let n = self.nodes[id.at]
        if takes(n) {
          asked.val = true
          let (nx, ny, _) = self.placed(id.at)
          then(n, x - nx, y - ny, t)
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
/// What its on_drag set going ended (said anew, let go).
fn View::drag_ended(self : View) -> Unit {
  let n = self.tree.nodes[self.at]
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
          f({ kind: Off, x: 0.0, y: 0.0, at: t, wx: 0.0, wy: 0.0, ox: 0.0, oy: 0.0, finger: g, since: t })
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
  @signals.untracked(fn() {
    self.clock.set(at)
    self.pull()
    self.laid_out(at)
  })
  if shown != at {
    @signals.untracked(fn() { self.clock.set(shown) })
  }
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
        let (nx, ny, _) = self.placed(id.at)
        let told = fn(kind : DragIs, finger : Int) {
          f({ kind, x: x - nx, y: y - ny, at: t, wx: x, wy: y, ox: x - nx, oy: y - ny, finger, since: t })
        }
        // (called off, all of it: the hold and the fingers let go of first, then each finger down told so while the node
        // and this on_drag are still its: what one told let go of hears no more)
        let said = n.drag_said
        let off = fn() {
          self.held_to(None)
          let fingers = self.fingers_off()
          for g in fingers {
            guard bound_still(n, id, said) else { break }
            told(Off, g)
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
              told(Down, finger)
            } else {
              // (one more than it takes: the hold called off)
              off()
            }
          Down => {
            self.held_to(Some(id))
            self.downs.clear()
            self.downs.push(finger)
            took.val = true
            told(Down, finger)
          }
          Moved => {
            took.val = true
            told(Moved, finger)
          }
          Up => {
            self.downs.retain(fn(g) { g != finger })
            if self.downs.is_empty() {
              self.held_to(None)
            }
            took.val = true
            told(Up, finger)
          }
          Off => off()
        }
      }
    }
  })
  took.val
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
/// found as the finger went down (through.mbt): its own told Off then, the finger that one's.
pub fn View::gesture(
  self : View,
  slop : Double,
  press? : (Drag) -> Unit,
  tap? : (Drag) -> Unit,
  hold? : (Double, (Drag) -> Unit),
  drag? : (Drag) -> Unit,
  through? : Double,
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
              (cancel_hold.val)()
              cancel_hold.val = fn() {  }
              match drag {
                Some(f) => word(f, { ..d, kind: Down }, o)
                None => ()
              }
            } else if moved.val {
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
        let was = down.val
        let went = moved.val
        let was_held = held.val
        over()
        match was {
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
          Some(o) =>
            match tap {
              Some(f) => word(f, d, o)
              None => ()
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
  for k in n.kids {
    self.tree.handle(k).let_go()
  }
  n.kids.clear()
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
  n.pressed_cell = None
  n.pointed_cell = None
  // (the focus on it: let go of with it, what has it told so)
  self.tree.focus_lost_in(self.at)
  n.focusable = false
  n.focus_keys = 0
  n.input_cell = None
  n.cursor = None
  n.beside = None
  n.focused_cell = None
  n.focus_shown_cell = None
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
  v
}

///|
/// The boxes node `at` lays out as its own, in order: its own, or a slot's, those of what it holds.
fn Tree::boxes(self : Tree, at : Int, into : Array[@flex.Node]) -> Unit {
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
/// What it holds changed (made, let go, moved): the boxes of the node that lays them out (itself, or the first not a
/// slot holding it) put again in order, it marked to be laid out, the order to be made again.
fn View::boxes_again(self : View) -> Unit {
  let mut at = self.at
  while self.tree.nodes[at].slot && self.tree.nodes[at].parent >= 0 {
    at = self.tree.nodes[at].parent
  }
  let n = self.tree.nodes[at]
  let all : Array[@flex.Node] = []
  for k in n.kids {
    self.tree.boxes(k, all)
  }
  n.flex.children.clear()
  for b in all {
    n.flex.children.push(b)
  }
  self.tree.layout_marked_at(at)
  self.tree.order_marked()
  // (what is drawn over what, among what holds it, changed: whether a modal layer is over what is held)
  self.tree.modals_told()
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
  self.boxes_again()
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
              let v = slot.box(fn(v) { row(v, item) })
              rows[k] = (v, item)
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
        slot.leave(r.0, leave)
        if leave > 0.0 {
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
/// Whether it is leaving, or what holds it is: no longer pressed.
pub fn View::leaving(self : View) -> Bool {
  guard self.live() is Some(_) else { return true }
  self.tree.leaving_at(self.at)
}

///|
/// Whether node `at` takes no press: it, or what holds it, leaving or said to take none (View::presses).
fn Tree::pressless_at(self : Tree, at : Int) -> Bool {
  // (under the topmost modal layer, not in it: none)
  !self.allows_at(at) || self.pressless_own_at(at)
}

///|
/// Whether node `at` or what holds it is leaving or said to take no press (whatever a modal layer says of it).
fn Tree::pressless_own_at(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i >= 0 {
    if self.nodes[i].left_at >= 0.0 || self.nodes[i].inert {
      return true
    }
    i = self.nodes[i].parent
  }
  false
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
  self.cause_at = was
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
  if upto > @signals.untracked(fn() { self.clock.get() }) {
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
  let drawn = self.drawn_due
  self.drawn_due = false
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
  self.clock.set(at)
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
  // what is due by now done (and the logic at `upto`, nothing due or not: what is said next is of then)
  self.advance(upto)
  self.laid_out(upto)
}

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
  let still = self.pulls_marked.filter(fn(k) {
    match self.pulls.get(k) {
      Some((_, b)) => b.marked
      None => false
    }
  })
  self.pulls_marked.clear()
  self.pulls_marked.append(still)
  // (what goes beside another placed by it only where anything was laid out or placed again: View::beside)
  let placing = self.layout_due || !self.places_due.is_empty()
  if self.layout_due {
    self.layout_due = false
    self.work.computes = self.work.computes + 1
    let gen = @flex.computes() + 1
    @flex.compute(self.nodes[0].flex, width=w, height=h, round=false, reuse=true)
    self.walk(0, gen, true)
  }
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
    self.order.clear()
    self.order_holder.clear()
    self.ordered(0, -1)
    self.work.orders = self.work.orders + 1
  }
  self.work.changes = self.work.changes + self.changed.length() + self.composed.length()
  self.due = false
  if ordered || self.changed.length() > 0 || self.composed.length() > 0 {
    self.drawn_due = true
  }
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
  let laid = n.flex.laid_out_at() == gen
  if laid {
    self.work.laid = self.work.laid + 1
  }
  self.place(at)
  if laid {
    for k in n.kids {
      self.walk(k, gen, laid)
    }
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
  let y = n.flex.top + n.look.dy + n.look.sy * n.flex.height
  let a = n.look.alpha
  let w = n.flex.width
  let h = n.flex.height
  let went = !n.placed || x != n.lx || y != n.ly || a != n.la
  let sized = !n.placed || w != n.lw || h != n.lh
  n.placed = true
  n.lx = x
  n.ly = y
  n.la = a
  n.lw = w
  n.lh = h
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
    shapes: n.look.shapes,
    tint: n.look.tint,
    radius: n.look.radius,
    glass: n.look.glass,
    border: n.look.border,
    border_ink: n.look.border_ink,
    words_look: n.look.words_look,
    shadow: n.look.shadow,
    hosted: n.hosted,
  })
  self.changed.push(id)
  self.pending.push(id)
}

///|
/// The order the nodes are drawn in from node `at` down (no slot: what it holds in its place), what holds it at
/// `holder` in it.
fn Tree::ordered(self : Tree, at : Int, holder : Int) -> Unit {
  let n = self.nodes[at]
  if n.slot {
    for k in n.kids {
      self.ordered(k, holder)
    }
    return
  }
  self.order.push(at)
  self.order_holder.push(holder)
  let me = self.order.length() - 1
  for k in n.kids {
    self.ordered(k, me)
  }
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
/// window draws it and how opaque, composed as it goes from what holds it (none for a node not yet placed).
pub fn Tree::each_drawn(self : Tree, f : (Content, Double, Double, Double) -> Unit) -> Unit {
  let wx : Array[Double] = Array::make(self.order.length(), 0.0)
  let wy : Array[Double] = Array::make(self.order.length(), 0.0)
  let wa : Array[Double] = Array::make(self.order.length(), 1.0)
  for i, at in self.order {
    let n = self.nodes[at]
    let h = self.order_holder[i]
    let (bx, by, ba) = if h < 0 { (0.0, 0.0, 1.0) } else { (wx[h], wy[h], wa[h]) }
    wx[i] = bx + n.lx
    wy[i] = by + n.ly
    wa[i] = ba * n.la
    match n.content {
      Some(c) => f(c, wx[i], wy[i], wa[i])
      None => ()
    }
  }
}

///|
/// A node's content unfolded where the window draws it.
fn unfolded(c : Content, x : Double, y : Double, a : Double) -> Drawn {
  {
    id: c.id,
    x,
    y,
    w: c.w,
    h: c.h,
    alpha: a,
    ground: c.ground,
    ink: c.ink,
    words: c.words,
    shapes: c.shapes,
    tint: c.tint,
    radius: c.radius,
    glass: c.glass,
    border: c.border,
    border_ink: c.border_ink,
    words_look: c.words_look,
    shadow: c.shadow,
    hosted: c.hosted,
  }
}

///|
/// The scene unfolded, in order (a new array: for a test, or a host taking the window whole).
pub fn Tree::drawn(self : Tree) -> Array[Drawn] {
  let out = []
  self.each_drawn(fn(c, x, y, a) { out.push(unfolded(c, x, y, a)) })
  out
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
/// Node `id` unfolded where the window draws it, where it lives and has been placed.
pub fn Tree::drawn_of(self : Tree, id : NodeId) -> Drawn? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  guard n.live && n.gen == id.gen && n.content is Some(c) else { return None }
  let mut x = 0.0
  let mut y = 0.0
  let mut a = 1.0
  let mut i = id.at
  while i >= 0 {
    let m = self.nodes[i]
    if !m.slot {
      x = x + m.lx
      y = y + m.ly
      a = a * m.la
    }
    i = m.parent
  }
  Some(unfolded(c, x, y, a))
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
      if c.draws() || n.on_press is Some(_) || n.on_drag is Some(_) {
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
pub(all) enum Target {
  Pressed(NodeId)
  Dragged(NodeId)
  Hosted(NodeId)
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
  guard self.alive_id(id) && !self.pressless_at(id.at) && self.drawn_of(id) is Some(d) else { return none }
  let n = self.nodes[id.at]
  self.areas_of(n, d.x, d.y, d.w, d.h)
}

///|
fn Tree::areas_of(self : Tree, n : Node, x : Double, y : Double, w : Double, h : Double) -> FingerAreas {
  self.takes_said(n)
  match n.takes {
    Some(Areas(_)) => {
      // (read by what the node owns for it: Tree::takes_rects)
      let rs = self.takes_rects(n, w, h, self.logic_at())
      InWindow(
        rs
        .iter()
        .filter_map(fn(r) {
          let x0 = x + (if r.0 > 0.0 { r.0 } else { 0.0 })
          let y0 = y + (if r.1 > 0.0 { r.1 } else { 0.0 })
          let x1 = x + (if r.2 < w { r.2 } else { w })
          let y1 = y + (if r.3 < h { r.3 } else { h })
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
    None => if n.hosted { AsItHosts } else { InWindow([(x, y, x + w, y + h)]) }
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
  self.each_drawn(fn(c, cx, cy, _) {
    if c.id == id {
      past.val = true
      return
    }
    if !past.val || self.pressless_at(c.id.at) {
      return
    }
    let n = self.nodes[c.id.at]
    if n.hosted || (n.on_press is None && n.on_drag is None) {
      return
    }
    match self.areas_of(n, cx, cy, c.w, c.h) {
      InWindow(rs) => out.append(rs)
      AsItHosts => ()
    }
  })
  out
}

///|
/// What a press at (x, y) is for: the topmost node drawn there (by the order drawn, where the scene composed draws it:
/// the same places as what is drawn) that is held (View::on_drag), does something when pressed or hosts the old view.
pub fn Tree::target_at(self : Tree, x : Double, y : Double) -> Target {
  self.target_in(x, y, tracked=false)
}

///|
/// The same, what decides where a node takes it (View::takes) read `tracked` (followed by what asks it: Tree::point_at)
/// or not.
fn Tree::target_in(self : Tree, x : Double, y : Double, tracked~ : Bool) -> Target {
  // (the logic's moment, what is where taken as of then: View::takes)
  let at = self.logic_at()
  let found : Array[Target] = []
  self.each_drawn(fn(c, cx, cy, _) {
    // (what is leaving or said to take no press, or held by what is, pressed no more)
    if x >= cx && y >= cy && x < cx + c.w && y < cy + c.h && !self.pressless_at(c.id.at) {
      let n = self.nodes[c.id.at]
      let here = if tracked {
        self.takes_here(n, x - cx, y - cy, c.w, c.h, at)
      } else {
        @signals.untracked(fn() { self.takes_here(n, x - cx, y - cy, c.w, c.h, at) })
      }
      if !here {
        ()
      } else if n.on_drag is Some(_) {
        found.push(Dragged(c.id))
      } else if n.on_press is Some(_) {
        found.push(Pressed(c.id))
      } else if n.hosted {
        found.push(Hosted(c.id))
      }
    }
  })
  match found.last() {
    Some(t) => t
    None => Nothing
  }
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
  if !self.alive_id(id) || !self.allows(id) {
    return false
  }
  let mut i = id.at
  while i >= 0 {
    if self.nodes[i].said_hidden {
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
    if self.nodes[i].said_hidden {
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
    if !n.live || n.gen != id.gen || self.leaving_at(id.at) {
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
/// the clock. The node's: not done once it is let go, or once what it returns is called.
pub fn View::at_moment(self : View, when : Double, f : () -> Unit) -> () -> Unit {
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
  tree.timeline.push(Once({ at: when, f: done, live }, tree.told))
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
    Some(s) => s.set(on)
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
      let s = @signals.signal(self.tree.pressing == Some(self.id()), same=fn(a, b) { a == b })
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
      let s = @signals.signal(self.tree.pointed == Some(self.id()), same=fn(a, b) { a == b })
      n.pointed_cell = Some(s)
      s
    }
  }
  s.get()
}

///|
/// The pointer at (x, y) in the window (a mouse's: a finger points at nothing), as of now: what takes a press there, the
/// topmost, is pointed at (View::pointed), nothing else; none where (x, y) is none (the pointer gone). The one it was
/// over and the one it is over now told, nothing else.
pub fn Tree::point_at(self : Tree, x : Double, y : Double) -> Unit {
  // (none: nothing followed, nothing pointed at from now)
  if x < 0.0 || y < 0.0 {
    self.point_stopped()
    self.pointed_to(None)
    return
  }
  self.follow_point(x, y, fn(t) {
    self.pointed_to(
      match t {
        Pressed(id) | Dragged(id) => Some(id)
        _ => None
      },
    )
  })
}

///|
/// What is at (x, y) followed (Tree::target_at, what decides where a node takes it (View::takes) read so): `then` told
/// it now and as it changes, whatever it is (a node's, the old view's, nothing), till the next point is followed, or
/// none (x or y below 0: nothing told, nothing followed), or the tree is let go. What is where, as the layout or the
/// order changes, is followed by being said again (Tree::hits_said).
pub fn Tree::follow_point(self : Tree, x : Double, y : Double, then : (Target) -> Unit) -> Unit {
  self.point_stopped()
  if x < 0.0 || y < 0.0 {
    return
  }
  // (this one the one followed from now: what it is first told may let it go (another point, none, the tree let go),
  // which this one's number then no longer is)
  let mine = self.point_said
  let stop = self.queued(fn() { self.target_in(x, y, tracked=true) }, then)
  if self.gone || self.point_said != mine {
    stop()
  } else {
    self.point_stop = Some(stop)
  }
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
  match (self.path_of(a.at), self.path_of(b.at)) {
    (Some(pa), Some(pb)) => drawn_after(pa, pb)
    _ => false
  }
}

///|
fn Tree::alive_id(self : Tree, id : NodeId) -> Bool {
  id.at >= 0 && id.at < self.nodes.length() && self.nodes[id.at].live && self.nodes[id.at].gen == id.gen
}
