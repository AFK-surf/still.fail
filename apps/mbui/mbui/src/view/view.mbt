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
// A frame (Tree::frame) does what was marked and nothing else: lays out the nodes marked (flex's reuse) and visits the
// nodes it laid out again and what it moved, the nodes whose place changed and what they hold, the nodes whose look
// changed alone; it makes again the instance of each of them that came out otherwise, kept by its node, and orders the
// instances again only as what is made, let go or moved among its siblings changed. What it changed is the frame's
// (Tree::changed), for the host to take.
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
} derive(Eq, Debug)

///|
/// A node's instance as a frame draws it: which node, where in the window (what holds it drawn off with it), how big,
/// how opaque (as opaque as what holds it is, with its own), its ground, its words.
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
  mut changes : Int
  mut orders : Int
  mut structure : Int
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
  /// where it was last drawn (in the window), how opaque, how big: worked out once it is placed
  mut placed : Bool
  mut ax : Double
  mut ay : Double
  mut aa : Double
  mut aw : Double
  mut ah : Double
  /// its instance as last made
  mut drawn : Drawn?
}

///|
/// The nodes made once of a window, its clock and what it did.
pub struct Tree {
  /// the frames' clock (ms): what reads it is told as it goes
  clock : @signals.Signal[Double]
  /// how words are measured: (words, width offered) -> (width, height)
  measure : (String, Double) -> (Double, Double)
  nodes : Array[Node]
  free : Array[Int]
  /// what a frame is to do: the nodes whose look changed, those whose place changed; whether any is to be laid out,
  /// whether the order is to be made again; whether any of it is (what hosts it told as it first is)
  looks_due : Array[Int]
  places_due : Array[Int]
  /// the bindings whose reads changed, to run as the frame begins (Tree::queued)
  bindings_due : Array[() -> Unit]
  mut layout_due : Bool
  mut order_due : Bool
  mut due : Bool
  mut last_w : Double
  mut last_h : Double
  /// the nodes drawn, in the order they are drawn (no slot)
  order : Array[Int]
  /// the node hosting the old view, if any (View::hosted)
  mut hosting : Int
  /// what the last frame changed: the nodes whose instance it made again
  changed : Array[NodeId]
  work : Work
  /// told as there is first something for a frame to do: what hosts it asks for a frame
  mut on_due : () -> Unit
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
pub fn Tree::new(make : (View) -> Unit, measure? : (String, Double) -> (Double, Double) = words_measure) -> Tree {
  let t : Tree = {
    clock: @signals.signal(0.0, same=fn(a, b) { a == b }),
    measure,
    nodes: [],
    free: [],
    looks_due: [],
    places_due: [],
    bindings_due: [],
    layout_due: true,
    order_due: true,
    due: true,
    last_w: -1.0,
    last_h: -1.0,
    order: [],
    hosting: -1,
    changed: [],
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
      changes: 0,
      orders: 0,
      structure: 0,
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
      n.parent = parent
      n.slot = false
      n.hosted = false
      n.look_due = false
      n.place_due = false
      n.placed = false
      n.drawn = None
      i
    }
    None => {
      self.nodes.push({
        gen: 0,
        live: true,
        flex: @flex.Node::new(),
        look: { ground: 0L, ink: 0L, words: "", alpha: 1.0, dx: 0.0, dy: 0.0 },
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
        ax: 0.0,
        ay: 0.0,
        aa: 1.0,
        aw: 0.0,
        ah: 0.0,
        drawn: None,
      })
      self.nodes.length() - 1
    }
  }
  let n = self.nodes[at]
  let was = @signals.set_active_sub(None)
  n.stop = Some(@signals.effect_scope(fn() { n.owner = @signals.active_sub() }))
  @signals.set_active_sub(was) |> ignore
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
/// `f` run in the node's scope (what it makes owned by the node), where the node lives.
fn View::owning(self : View, f : () -> Unit) -> Unit {
  guard self.live() is Some(n) else { return }
  let was = @signals.set_active_sub(n.owner)
  f()
  @signals.set_active_sub(was) |> ignore
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
/// The clock now: what reads it (a look worked out from the time) is told as it goes.
pub fn Tree::now(self : Tree) -> Double {
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
  self.order.clear()
  self.changed.clear()
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
      x = x + n.flex.left + n.look.dx
      y = y + n.flex.top + n.look.dy
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
  let queued = Ref(false)
  // (what it runs, let go as it stops: the watch and what runs it hold each other)
  let run : Ref[(() -> Unit)?] = Ref(None)
  let w = @signals.watch(fn() {
    match run.val {
      Some(r) if !queued.val => {
        queued.val = true
        self.bindings_due.push(r)
        self.marked()
      }
      _ => ()
    }
  })
  run.val = Some(fn() {
    queued.val = false
    let v = w.read(read)
    @signals.untracked(fn() { then(v) })
  })
  (run.val.unwrap())()
  fn() {
    run.val = None
    w.stop()
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
      let stop = tree.queued(f, fn(v) {
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
  n.drawn = None
  if self.tree.hosting == self.at {
    self.tree.hosting = -1
  }
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
pub fn View::show(self : View, when : () -> Bool, then : (View) -> Unit) -> Unit {
  let slot = self.slot()
  let had : Ref[View?] = Ref(None)
  let stop = slot.tree.queued(when, fn(on) {
    guard slot.alive() else { return }
    match (on, had.val) {
      (true, None) => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        had.val = Some(slot.box(then))
      }
      (false, Some(v)) => {
        slot.tree.work.structure = slot.tree.work.structure + 1
        slot.drop(v)
        had.val = None
      }
      _ => ()
    }
  })
  slot.owns(stop) |> ignore
}

///|
/// A node made by `make` for what `which` is, made anew (the one before let go) as that changes, kept as it does not.
pub fn[K : Eq] View::pick(self : View, which : () -> K, make : (View, K) -> Unit) -> Unit {
  let slot = self.slot()
  let had : Ref[(K, View)?] = Ref(None)
  let stop = slot.tree.queued(which, fn(k) {
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
) -> Unit {
  let slot = self.slot()
  let rows : Map[K, (View, @signals.Signal[T])] = Map([])
  let stop = slot.tree.queued(items, fn(all) {
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
        None => {
          let item = @signals.signal(it, same=fn(a, b) { a == b })
          let v = slot.box(fn(v) { row(v, item) })
          rows[k] = (v, item)
          order.push(v.at)
        }
      }
    }
    @signals.end_batch()
    let gone : Array[K] = []
    for k, r in rows {
      if !seen.contains(k) {
        gone.push(k)
        r.0.let_go()
      }
    }
    for k in gone {
      rows.remove(k)
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
/// A frame of `w` by `h` at the clock's time, doing what was marked: the nodes marked laid out, and visited of them
/// only those laid out again and what moved with them; the nodes whose place changed, what they hold with them; the
/// nodes whose look changed alone. Each instance that came out otherwise made again (Tree::changed); the order made
/// again where what is drawn was made, let go or moved among its siblings. Whether anything drawn changed.
pub fn Tree::frame(self : Tree, w : Double, h : Double) -> Bool {
  self.changed.clear()
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
  }
  if !self.due {
    return false
  }
  // the bindings whose reads changed since, each once, in the order they were told (what they make runs its own now,
  // what they set again marks what it marks)
  let mut i = 0
  while i < self.bindings_due.length() {
    (self.bindings_due[i])()
    i = i + 1
  }
  self.bindings_due.clear()
  if self.layout_due {
    self.layout_due = false
    self.work.computes = self.work.computes + 1
    let gen = @flex.computes() + 1
    @flex.compute(self.nodes[0].flex, width=w, height=h, round=false, reuse=true)
    self.walk(0, 0.0, 0.0, 1.0, gen, false, true)
  }
  // (what moved by its own place, what it holds with it: from where what holds it is now)
  for at in self.places_due {
    let n = self.nodes[at]
    if n.live && n.place_due {
      let (ox, oy, oa) = self.holder_place(at)
      self.work.visited = self.work.visited + 1
      if self.place(at, ox, oy, oa) {
        for k in n.kids {
          self.walk(k, n.ax, n.ay, n.aa, -1, true, false)
        }
      }
    }
  }
  self.places_due.clear()
  // (what changed of its look alone: its instance, nothing else)
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
    self.ordered(0)
    self.work.orders = self.work.orders + 1
  }
  self.work.changes = self.work.changes + self.changed.length()
  self.due = false
  ordered || self.changed.length() > 0
}

///|
/// Node `at` after a compute numbered `gen` (or what moved it: `moved`), what holds it drawn at (ox, oy) as opaque as
/// `oa`: placed again, and what it holds where it was laid out again (what it holds placed anew by it, each looked at)
/// or moved (all of it with it); below what was neither laid out again nor moved, nothing is visited.
fn Tree::walk(
  self : Tree,
  at : Int,
  ox : Double,
  oy : Double,
  oa : Double,
  gen : Int,
  moved : Bool,
  holder_laid : Bool,
) -> Unit {
  let n = self.nodes[at]
  self.work.visited = self.work.visited + 1
  if n.slot {
    for k in n.kids {
      if moved || holder_laid {
        self.walk(k, ox, oy, oa, gen, moved, holder_laid)
      }
    }
    return
  }
  let laid = n.flex.laid_out_at() == gen
  if laid {
    self.work.laid = self.work.laid + 1
  }
  let went = self.place(at, ox, oy, oa)
  for k in n.kids {
    if went || laid {
      self.walk(k, n.ax, n.ay, n.aa, gen, went, laid)
    }
  }
}

///|
/// Where what holds node `at` (the first not a slot) is drawn and how opaque: the window's for the root's.
fn Tree::holder_place(self : Tree, at : Int) -> (Double, Double, Double) {
  let mut p = self.nodes[at].parent
  while p >= 0 && self.nodes[p].slot {
    p = self.nodes[p].parent
  }
  if p < 0 {
    (0.0, 0.0, 1.0)
  } else {
    let h = self.nodes[p]
    (h.ax, h.ay, h.aa)
  }
}

///|
/// Node `at` placed, what holds it at (ox, oy) as opaque as `oa`: its instance made again if it is drawn otherwise (or
/// its look changed). Whether what it holds is drawn elsewhere with it (it moved, or it is drawn otherwise opaque).
fn Tree::place(self : Tree, at : Int, ox : Double, oy : Double, oa : Double) -> Bool {
  let n = self.nodes[at]
  n.place_due = false
  let x = ox + n.flex.left + n.look.dx
  let y = oy + n.flex.top + n.look.dy
  let a = oa * n.look.alpha
  let w = n.flex.width
  let h = n.flex.height
  let went = !n.placed || x != n.ax || y != n.ay || a != n.aa
  let sized = !n.placed || w != n.aw || h != n.ah
  n.placed = true
  n.ax = x
  n.ay = y
  n.aa = a
  n.aw = w
  n.ah = h
  if went || sized || n.look_due {
    self.made_again(at)
  }
  went
}

///|
/// Node `at`'s instance made again, as it is placed and looks now: one of the frame's changes.
fn Tree::made_again(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  n.look_due = false
  let id = { at, gen: n.gen }
  self.work.instances = self.work.instances + 1
  n.drawn = Some({
    id,
    x: n.ax,
    y: n.ay,
    w: n.aw,
    h: n.ah,
    alpha: n.aa,
    ground: n.look.ground,
    ink: n.look.ink,
    words: n.look.words,
    hosted: n.hosted,
  })
  self.changed.push(id)
}

///|
/// The order the nodes are drawn in from node `at` down (no slot: what it holds in its place).
fn Tree::ordered(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.slot {
    self.order.push(at)
  }
  for k in n.kids {
    self.ordered(k)
  }
}

///|
/// What the last frame made again: the nodes whose instance changed.
pub fn Tree::changed(self : Tree) -> Array[NodeId] {
  self.changed
}

///|
/// The nodes drawn, in order: `f` given each one's instance as last made (none for a node not yet placed).
pub fn Tree::each_drawn(self : Tree, f : (Drawn) -> Unit) -> Unit {
  for at in self.order {
    match self.nodes[at].drawn {
      Some(d) => f(d)
      None => ()
    }
  }
}

///|
/// The instances drawn, in order (a new array: for a test, or a host taking them all).
pub fn Tree::drawn(self : Tree) -> Array[Drawn] {
  let out = []
  self.each_drawn(fn(d) { out.push(d) })
  out
}

///|
/// Node `id`'s instance as last made, where it lives.
pub fn Tree::drawn_of(self : Tree, id : NodeId) -> Drawn? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let n = self.nodes[id.at]
  if n.live && n.gen == id.gen {
    n.drawn
  } else {
    None
  }
}

///|
/// A press at (x, y): the topmost node drawn there that does something when pressed does it, outside any tracking, as
/// one change. True if one did. Found where it is drawn (its holders' offsets with its own: View::rect).
pub fn Tree::press(self : Tree, x : Double, y : Double) -> Bool {
  match self.target_at(x, y) {
    Pressed(id) => self.run_press(id)
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
/// What a press at (x, y) is for: the topmost node drawn there (by the order drawn, where it was last drawn) that does
/// something when pressed or hosts the old view.
pub fn Tree::target_at(self : Tree, x : Double, y : Double) -> Target {
  for i = self.order.length() - 1; i >= 0; i = i - 1 {
    let n = self.nodes[self.order[i]]
    guard n.live && n.drawn is Some(d) else { continue }
    if x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h {
      if n.on_press is Some(_) {
        return Pressed(d.id)
      }
      if n.hosted {
        return Hosted(d.id)
      }
    }
  }
  Nothing
}

///|
/// Node `id` pressed (Tree::target_at's): its callback run outside any tracking, as one change, if it lives.
pub fn Tree::run_press(self : Tree, id : NodeId) -> Bool {
  if id.at < 0 || id.at >= self.nodes.length() {
    return false
  }
  let n = self.nodes[id.at]
  if !n.live || n.gen != id.gen {
    return false
  }
  match n.on_press {
    Some(f) => {
      @signals.start_batch()
      @signals.untracked(fn() { f() })
      @signals.end_batch()
      true
    }
    None => false
  }
}
