// A view made once (docs/retained.md, the model; the way there's 2). Each node is made when it first shows and stays
// until what holds it lets it go; what of it changes is a binding of one property (one a property: bound again, the
// one before is let go), marked as what it read changes and worked out again as the next frame begins (Tree::queued:
// however often it changed meanwhile, once; nothing is laid out or drawn as a value is set), and that property alone
// is set again, and only if it came out otherwise: a layout property marks the node (and what
// holds it) to be laid out, a paint property the node's instance to be made again, a place property (how far it is
// drawn off, how opaque) its instance and those of what it holds. What comes and goes is a node of its own (`show`,
// `pick`, `each`), whose nodes it makes, keeps and lets go. Acting is a callback run outside any tracking. Time is a
// signal (Tree::now), read where it is used.
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
  /// drawn by what hosts it (View::hosted: the old view, built its own way, in its place)
  hosted : Bool
} derive(Eq, Debug)

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
  drops : Array[() -> Unit]
  /// its properties' bindings, by property: what stops each
  props : Map[Int, () -> Unit]
  mut on_press : (() -> Unit)?
  /// a slot (show, pick, each): no box of its own, what it holds laid out as its holder's own
  mut slot : Bool
  /// drawn by what hosts the tree (View::hosted)
  mut hosted : Bool
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
  /// how words are measured: (words, width offered) -> (width, height)
  measure : (String, Double) -> (Double, Double)
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
  measure? : (String, Double) -> (Double, Double) = words_measure,
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
    changed: [],
    composed: [],
    removed: [],
    pending: [],
    drawn_due: false,
    on_due: fn() {  },
    work: {
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
pub fn words_measure(words : String, width : Double) -> (Double, Double) {
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
  let at = match self.free.pop() {
    Some(i) => {
      let n = self.nodes[i]
      n.gen = n.gen + 1
      n.live = true
      n.flex = @flex.Node::new()
      n.look.ground = 0L
      n.look.ink = 0L
      n.look.words = ""
      n.look.alpha = 1.0
      n.look.dx = 0.0
      n.look.dy = 0.0
      n.look.sx = 0.0
      n.look.sy = 0.0
      n.parent = parent
      n.slot = false
      n.hosted = false
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
      i
    }
    None => {
      self.nodes.push({
        gen: 0,
        live: true,
        flex: @flex.Node::new(),
        look: { ground: 0L, ink: 0L, words: "", alpha: 1.0, dx: 0.0, dy: 0.0, sx: 0.0, sy: 0.0 },
        parent,
        kids: [],
        owner: None,
        stop: None,
        drops: [],
        props: {},
        on_press: None,
        slot: false,
        hosted: false,
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
pub fn Tree::now(self : Tree) -> Double {
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
/// The clock now (Tree::now), for what a node works out from the time.
pub fn View::now(self : View) -> Double {
  self.tree.now()
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
    self.marked()
  }
}

///|
/// The order the nodes are drawn in to be made again (one made, let go or moved among its siblings).
fn Tree::order_marked(self : Tree) -> Unit {
  self.order_due = true
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
    let v = w.read(read)
    if last.val != Some(v) {
      last.val = Some(v)
      self.committed(fn() {
        if live.val {
          then(v)
        }
      })
    }
  })
  watch.val = Some(w)
  let v = w.read(read)
  last.val = Some(v)
  @signals.untracked(fn() { then(v) })
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
  @signals.untracked(f)
  self.cause_at = was
  self.marked()
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
/// Room inside it, the same on every side.
pub fn View::pad(self : View, p : Live[Double]) -> View {
  self.bind(2, p, Layout, fn(p) {
    let s = self.tree.nodes[self.at].flex.style
    s.set_padding_left(Pt(p))
    s.set_padding_top(Pt(p))
    s.set_padding_right(Pt(p))
    s.set_padding_bottom(Pt(p))
  })
  self
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
/// How big it is laid out as of the logic's moment (Tree::now): what was told before it laid out first (what an event
/// changed before it asks, laid out as a frame would), as of the window's size its last frame gave (0 by 0 before the
/// first). For what is said at a moment by how big a thing is then (how long a slide across it takes), never followed.
pub fn View::laid_size(self : View) -> (Double, Double) {
  guard self.live() is Some(n) else { return (0.0, 0.0) }
  let tree = self.tree
  if tree.last_w <= 0.0 {
    return (n.flex.width, n.flex.height)
  }
  // (laid out as of the logic's moment, what follows the clock sampled there too, not at a frame's to be shown ahead
  // of it; then the clock put back where it was drawn at: what follows it worked out there again as it is next brought,
  // the frame's target kept)
  let at = tree.now()
  let shown = @signals.untracked(fn() { tree.clock.get() })
  // (what the change under way set so far pulled into its properties, as a computed read in a batch is: nothing told,
  // no structure or effect run before the change ends)
  @signals.untracked(fn() {
    tree.clock.set(at)
    tree.pull()
    tree.brought(at)
  })
  let size = (n.flex.width, n.flex.height)
  if shown != at {
    @signals.untracked(fn() { tree.clock.set(shown) })
  }
  size
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
  self.bind(11, on, Place, fn(on) { self.tree.nodes[self.at].inert = !on })
  self
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
/// The words it shows: layout's (their size) and paint's.
pub fn View::words(self : View, words : Live[String], ink? : Int64 = 0x000000FFL) -> View {
  guard self.live() is Some(n) else { return self }
  n.look.ink = ink
  let tree = self.tree
  let at = self.at
  // (it measures what the node holds now, by its index: dropped as it is let go)
  n.flex.measure = Some(fn(w, wm, _h, _hm) {
    let offered = match wm {
      Exactly | AtMost => w
      Undefined => -1.0
    }
    tree.work.measured = tree.work.measured + 1
    let (mw, mh) = (tree.measure)(tree.nodes[at].look.words, offered)
    match wm {
      Exactly => (w, mh)
      _ => (mw, mh)
    }
  })
  self.bind(8, words, Both, fn(s) { tree.nodes[at].look.words = s })
  self
}

///|
/// What a press on it does: run outside any tracking, as one change (what it writes told once it is done).
pub fn View::on_press(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_press = Some(f)
  self
}

///|
/// `f` run once as it is let go (what it holds that is no effect: a computed to dispose, a resource to close).
pub fn View::owns(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.drops.push(f)
  self
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
  match n.stop {
    Some(stop) => stop()
    None => ()
  }
  n.stop = None
  n.owner = None
  let props = n.props.values().collect()
  n.props.clear()
  for stop in props {
    stop()
  }
  let drops = n.drops.copy()
  n.drops.clear()
  for f in drops {
    f()
  }
  n.on_press = None
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
pub fn Tree::animating(self : Tree) -> Bool {
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
  // (in an event already: its moment, settled as it began)
  if self.cause_at >= 0.0 {
    @signals.start_batch()
    @signals.untracked(f)
    @signals.end_batch()
    return
  }
  self.settle(at)
  let was = self.cause_at
  self.cause_at = at
  @signals.start_batch()
  @signals.untracked(f)
  @signals.end_batch()
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
  guard self.live() is Some(n) && per_second > 0 && count > 0 else { return fn() {  } }
  let live = Ref(true)
  let tree = self.tree
  tree.timeline.push(Steps({ first: tick_after(tree.cause_now(), per_second), per_second, count, k: 0, step, live }, tree.told))
  tree.told = tree.told + 1
  tree.marked()
  let stop = fn() { live.val = false }
  n.drops.push(stop)
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
  let w = self.last_w
  let h = self.last_h
  // what is due by now done (and the logic at `upto`, nothing due or not: what is said next is of then)
  self.advance(upto)
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
  Hosted(NodeId)
  Nothing
} derive(Eq, Debug)

///|
/// What a press at (x, y) is for: the topmost node drawn there (by the order drawn, where the scene composed draws it:
/// the same places as what is drawn) that does something when pressed or hosts the old view.
pub fn Tree::target_at(self : Tree, x : Double, y : Double) -> Target {
  let found : Array[(NodeId, Bool)] = []
  self.each_drawn(fn(c, cx, cy, _) {
    // (what is leaving or said to take no press, or held by what is, pressed no more)
    if x >= cx && y >= cy && x < cx + c.w && y < cy + c.h && !self.pressless_at(c.id.at) {
      let n = self.nodes[c.id.at]
      if n.on_press is Some(_) {
        found.push((c.id, true))
      } else if n.hosted {
        found.push((c.id, false))
      }
    }
  })
  match found.last() {
    Some((id, true)) => Pressed(id)
    Some((id, false)) => Hosted(id)
    None => Nothing
  }
}

///|
/// Node `id` pressed (Tree::target_at's): its callback run outside any tracking, as one change, if it lives.
pub fn Tree::run_press(self : Tree, id : NodeId) -> Bool {
  self.run_press_at(id, self.time_now())
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
  guard self.live() is Some(n) else { return fn() {  } }
  let live = Ref(true)
  let tree = self.tree
  tree.timeline.push(Once({ at: when, f, live }, tree.told))
  tree.told = tree.told + 1
  tree.marked()
  let stop = fn() { live.val = false }
  n.drops.push(stop)
  stop
}
