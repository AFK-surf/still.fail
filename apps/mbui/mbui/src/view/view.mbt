// A view made once (docs/retained.md, the model; the way there's 2). Each node is made when it first shows and stays
// until what holds it lets it go; what of it changes is a binding of one property, run as what it read changes, and
// that property alone is set again, and only if it came out otherwise: a layout property marks the node (and what
// holds it) to be laid out, a paint property the node's instance to be made again. What comes and goes is a node of
// its own (`show`, `pick`, `each`), whose nodes it makes, keeps and lets go, and each node's bindings, callbacks and
// measure go with it. Acting is a callback run outside any tracking. Time is a signal (Tree::now), read where it is
// used.
//
// Nodes are a pool by index (retained.md: no pointer cycles under reference counting): a node holds what holds it and
// what it holds as indexes, and a `View` is a handle (the tree, the index, the node's making there). What a node
// holds that holds the tree back (its bindings' effects, its callback, its measure) is dropped as it is let go, and
// every node's as the tree is disposed (Tree::dispose).
//
// A frame (Tree::frame) does what was marked: lays out the nodes marked (flex's reuse), makes again the instances of
// the nodes whose look changed or that layout moved, and gives the host the frame's instances only if any was made.
//
// What this package is not yet (the way there's 2 and 3): no host wakes it, its words are measured by a function given
// to it (not the text package), its instances are `Drawn` records (not the renderer's), and no app runs on it.

///|
/// A property's value: set once (`Is`), or worked out (`By`), tracked, and set again as what it read changes.
pub(all) enum Live[T] {
  Is(T)
  By(() -> T)
}

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
  id : Int
  x : Double
  y : Double
  w : Double
  h : Double
  alpha : Double
  ground : Int64
  ink : Int64
  words : String
} derive(Eq, Debug)

///|
/// What the tree did, counted from its making: nodes made and let go; bindings run, and of them those whose value came
/// out the same (nothing set, nothing marked); computes of the layout and nodes it laid out again; words measured;
/// instances made again; frames whose instances went to the host; structure bindings run (show, pick, each). For a
/// test to say what work a change did, not how long it took.
pub(all) struct Work {
  mut made : Int
  mut let_go : Int
  mut bound : Int
  mut same : Int
  mut computes : Int
  mut laid : Int
  mut measured : Int
  mut instances : Int
  mut given : Int
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
  /// what stops its bindings (each one's effect): run and dropped as it is let go
  stops : Array[() -> Unit]
  mut on_press : (() -> Unit)?
  /// a slot (show, pick, each): no box of its own, what it holds laid out as its holder's own
  mut slot : Bool
  /// its instance to be made again, and where in the frame's instances it last was (-1: none)
  mut look_due : Bool
  mut drawn_at : Int
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
  /// the nodes whose instance is to be made again, and whether any node is to be laid out
  looks_due : Array[Int]
  mut layout_due : Bool
  mut last_w : Double
  mut last_h : Double
  /// the frame's instances as last given to the host
  mut drawn : Array[Drawn]
  work : Work
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
    layout_due: true,
    last_w: -1.0,
    last_h: -1.0,
    drawn: [],
    work: {
      made: 0,
      let_go: 0,
      bound: 0,
      same: 0,
      computes: 0,
      laid: 0,
      measured: 0,
      instances: 0,
      given: 0,
      structure: 0,
    },
  }
  let root = t.made(-1)
  make(root)
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
      n.look_due = false
      n.drawn_at = -1
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
        stops: [],
        on_press: None,
        slot: false,
        look_due: false,
        drawn_at: -1,
      })
      self.nodes.length() - 1
    }
  }
  let v = { tree: self, at, gen: self.nodes[at].gen }
  v.look_marked()
  v
}

///|
fn View::node(self : View) -> Node {
  self.tree.nodes[self.at]
}

///|
fn Tree::handle(self : Tree, at : Int) -> View {
  { tree: self, at, gen: self.nodes[at].gen }
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
/// The whole tree let go: every node's bindings stopped, callbacks and measures dropped.
pub fn Tree::dispose(self : Tree) -> Unit {
  if self.nodes.length() > 0 && self.nodes[0].live {
    self.root().let_go()
  }
  self.looks_due.clear()
  self.drawn = []
}

///|
/// A node made in `self`, after what it holds already, made by `make` as its own.
pub fn View::box(self : View, make : (View) -> Unit) -> View {
  let v = self.tree.made(self.at)
  self.node().kids.push(v.at)
  self.boxes_again()
  make(v)
  v
}

///|
/// What holds it, if anything does.
pub fn View::parent(self : View) -> View? {
  let p = self.node().parent
  if p < 0 {
    None
  } else {
    Some(self.tree.handle(p))
  }
}

///|
/// The nodes it holds, in order.
pub fn View::kids(self : View) -> Array[View] {
  self.node().kids.map(fn(k) { self.tree.handle(k) })
}

///|
/// Whether it lives (not let go, its index not made again since).
pub fn View::alive(self : View) -> Bool {
  let n = self.node()
  n.live && n.gen == self.gen
}

///|
/// Who it is: its index and its making there.
pub fn View::id(self : View) -> Int {
  self.at * 65536 + self.gen
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
  let (x, y, _) = self.tree.placed(self.at)
  let n = self.node()
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
/// Its layout to be done again: itself and every node up to the root (one marked before and not laid out since, its
/// holder's layout reused, is no sign the rest are).
fn View::layout_marked(self : View) -> Unit {
  self.tree.layout_due = true
  let mut i = self.at
  while i >= 0 {
    let n = self.tree.nodes[i]
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
  }
}

///|
fn View::look_marked(self : View) -> Unit {
  self.tree.look_marked_at(self.at)
}

///|
/// What a property is: what of the node it sets (as its own: a layout property or a paint property).
pub(all) enum Phase {
  Layout
  Paint
  Both
} derive(Eq, Debug)

///|
/// Property `live` of the node, set by `apply`: once, or as what it reads changes, by a binding of its own (tracked as
/// it works the value out, not as it is set); set again only if it came out otherwise than it last did, marking what
/// its phase does again.
pub fn[T : Eq] View::bind(self : View, live : Live[T], phase : Phase, apply : (T) -> Unit) -> Unit {
  let marked = fn() {
    match phase {
      Layout => self.layout_marked()
      Paint => self.look_marked()
      Both => {
        self.layout_marked()
        self.look_marked()
      }
    }
  }
  match live {
    Is(v) => {
      apply(v)
      marked()
    }
    By(f) => {
      let last : Ref[T?] = Ref(None)
      let stop = @signals.effect(fn() {
        let v = f()
        @signals.untracked(fn() {
          if !self.alive() {
            return
          }
          let work = self.tree.work
          work.bound = work.bound + 1
          if last.val == Some(v) {
            work.same = work.same + 1
            return
          }
          last.val = Some(v)
          apply(v)
          marked()
        })
      })
      self.node().stops.push(stop)
    }
  }
}

///|
/// Its width (points; None: as its content and its holder make it).
pub fn View::width(self : View, w : Live[Double?]) -> View {
  self.bind(w, Layout, fn(w) {
    self.node().flex.style.set_width(match w {
      Some(w) => Pt(w)
      None => Auto
    })
  })
  self
}

///|
/// Its height (points; None: as its content and its holder make it).
pub fn View::height(self : View, h : Live[Double?]) -> View {
  self.bind(h, Layout, fn(h) {
    self.node().flex.style.set_height(match h {
      Some(h) => Pt(h)
      None => Auto
    })
  })
  self
}

///|
/// Room inside it, the same on every side.
pub fn View::pad(self : View, p : Live[Double]) -> View {
  self.bind(p, Layout, fn(p) {
    let s = self.node().flex.style
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
  self.bind(across, Layout, fn(a) { self.node().flex.style.direction = if a { Row } else { Column } })
  self
}

///|
/// How much of the room left it takes.
pub fn View::grow(self : View, g : Live[Double]) -> View {
  self.bind(g, Layout, fn(g) { self.node().flex.style.grow = g })
  self
}

///|
/// Its ground (0: none): paint's.
pub fn View::ground(self : View, ink : Live[Int64]) -> View {
  self.bind(ink, Paint, fn(k) { self.node().look.ground = k })
  self
}

///|
/// How opaque it is drawn, what it holds with it: paint's.
pub fn View::alpha(self : View, a : Live[Double]) -> View {
  self.bind(a, Paint, fn(a) {
    // (what it holds made again as drawn otherwise: Tree::instances)
    self.node().look.alpha = a
  })
  self
}

///|
/// How far it is drawn off where it is laid out, what it holds with it: paint's (a move on the compositor: never laid
/// out again).
pub fn View::offset(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(d, Paint, fn(d) {
    let n = self.node()
    n.look.dx = d.0
    n.look.dy = d.1
  })
  self
}

///|
/// The words it shows: layout's (their size) and paint's.
pub fn View::words(self : View, words : Live[String], ink? : Int64 = 0xFF000000L) -> View {
  self.node().look.ink = ink
  let tree = self.tree
  let at = self.at
  // (it measures what the node holds now, by its index)
  self.node().flex.measure = Some(fn(w, wm, _h, _hm) {
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
  self.bind(words, Both, fn(s) { self.node().look.words = s })
  self
}

///|
/// What a press on it does: run outside any tracking, as one change (what it writes told once it is done).
pub fn View::on_press(self : View, f : () -> Unit) -> View {
  self.node().on_press = Some(f)
  self
}

///|
/// Lets it go: what it holds first, then its bindings stopped, its callback and measure dropped, its index free.
fn View::let_go(self : View) -> Unit {
  if !self.alive() {
    return
  }
  let n = self.node()
  for k in n.kids {
    self.tree.handle(k).let_go()
  }
  n.kids.clear()
  n.live = false
  for stop in n.stops {
    stop()
  }
  n.stops.clear()
  n.on_press = None
  n.flex.measure = None
  n.flex.children.clear()
  n.parent = -1
  n.drawn_at = -1
  self.tree.free.push(self.at)
  self.tree.work.let_go = self.tree.work.let_go + 1
}

///|
/// A node holding what comes and goes (show, pick, each), with no box of its own.
fn View::slot(self : View) -> View {
  let v = self.tree.made(self.at)
  v.node().slot = true
  self.node().kids.push(v.at)
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
/// slot holding it) put again in order, it marked to be laid out.
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
  self.tree.handle(at).layout_marked()
}

///|
/// Node `v` let go and taken out of what it holds.
fn View::drop(self : View, v : View) -> Unit {
  v.let_go()
  let kids = self.node().kids
  match kids.search(v.at) {
    Some(i) => kids.remove(i) |> ignore
    None => ()
  }
  self.boxes_again()
}

///|
/// `then`'s node while `when` holds, made as it comes to and let go as it stops.
pub fn View::show(self : View, when : () -> Bool, then : (View) -> Unit) -> Unit {
  let slot = self.slot()
  let had : Ref[View?] = Ref(None)
  let stop = @signals.effect(fn() {
    let on = when()
    @signals.untracked(fn() {
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
  })
  slot.node().stops.push(stop)
}

///|
/// A node made by `make` for what `which` is, made anew (the one before let go) as that changes, kept as it does not.
pub fn[K : Eq] View::pick(self : View, which : () -> K, make : (View, K) -> Unit) -> Unit {
  let slot = self.slot()
  let had : Ref[(K, View)?] = Ref(None)
  let stop = @signals.effect(fn() {
    let k = which()
    @signals.untracked(fn() {
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
  })
  slot.node().stops.push(stop)
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
  let stop = @signals.effect(fn() {
    let all = items()
    @signals.untracked(fn() {
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
      let kids = slot.node().kids
      let moved = order.length() != kids.length() || order.mapi(fn(i, v) { kids[i] != v }).contains(true)
      if moved {
        kids.clear()
        for v in order {
          kids.push(v)
        }
        slot.boxes_again()
      }
    })
  })
  slot.node().stops.push(stop)
}

///|
/// A frame of `w` by `h` at the clock's time: the nodes marked laid out, the instances of the nodes whose look changed
/// or that layout moved made again, and the frame's instances, if any was, given to the host (the same array as the
/// last frame's otherwise: nothing made, nothing given).
pub fn Tree::frame(self : Tree, w : Double, h : Double) -> Array[Drawn] {
  let root = self.root()
  if w != self.last_w || h != self.last_h {
    self.last_w = w
    self.last_h = h
    let s = root.node().flex.style
    s.set_width(Pt(w))
    s.set_height(Pt(h))
    root.layout_marked()
  }
  let mut laid = false
  if self.layout_due {
    self.layout_due = false
    self.work.computes = self.work.computes + 1
    let gen = @flex.computes()
    @flex.compute(root.node().flex, width=w, height=h, round=false, reuse=true)
    self.laid_count(0, gen + 1)
    laid = true
  }
  if !laid && self.looks_due.length() == 0 {
    return self.drawn
  }
  // the instances in order: made again where its look changed or where it is drawn changed (laid out elsewhere, or
  // what holds it drawn elsewhere), the others as the last frame had them
  let out : Array[Drawn] = []
  self.instances(0, 0.0, 0.0, 1.0, out)
  for i in self.looks_due {
    self.nodes[i].look_due = false
  }
  self.looks_due.clear()
  self.drawn = out
  self.work.given = self.work.given + 1
  out
}

///|
/// The nodes a compute numbered `gen` laid out again (not reusing their layout), counted.
fn Tree::laid_count(self : Tree, at : Int, gen : Int) -> Unit {
  let n = self.nodes[at]
  if !n.slot && n.flex.laid_out_at() == gen {
    self.work.laid = self.work.laid + 1
  }
  for k in n.kids {
    self.laid_count(k, gen)
  }
}

///|
/// Node `at`'s instance and what it holds, in order: made again if marked, else as the last frame had it.
fn Tree::instances(self : Tree, at : Int, ox : Double, oy : Double, oa : Double, out : Array[Drawn]) -> Unit {
  let n = self.nodes[at]
  let (cx, cy, ca) = if n.slot {
    (ox, oy, oa)
  } else {
    let x = ox + n.flex.left + n.look.dx
    let y = oy + n.flex.top + n.look.dy
    let a = oa * n.look.alpha
    let kept = if !n.look_due && n.drawn_at >= 0 && n.drawn_at < self.drawn.length() {
      let d = self.drawn[n.drawn_at]
      if d.x == x && d.y == y && d.w == n.flex.width && d.h == n.flex.height && d.alpha == a {
        Some(d)
      } else {
        None
      }
    } else {
      None
    }
    let d : Drawn = if kept is Some(d) {
      d
    } else {
      self.work.instances = self.work.instances + 1
      {
        id: at * 65536 + n.gen,
        x,
        y,
        w: n.flex.width,
        h: n.flex.height,
        alpha: a,
        ground: n.look.ground,
        ink: n.look.ink,
        words: n.look.words,
      }
    }
    n.drawn_at = out.length()
    out.push(d)
    (x, y, a)
  }
  for k in n.kids {
    self.instances(k, cx, cy, ca, out)
  }
}

///|
/// A press at (x, y): the topmost node drawn there that does something when pressed does it, outside any tracking, as
/// one change. True if one did. Found where it is drawn (its holders' offsets with its own: View::rect).
pub fn Tree::press(self : Tree, x : Double, y : Double) -> Bool {
  match self.hit(0, 0.0, 0.0, x, y) {
    Some(f) => {
      @signals.start_batch()
      @signals.untracked(fn() { f() })
      @signals.end_batch()
      true
    }
    None => false
  }
}

///|
fn Tree::hit(self : Tree, at : Int, ox : Double, oy : Double, x : Double, y : Double) -> (() -> Unit)? {
  let n = self.nodes[at]
  let (bx, by) = if n.slot { (ox, oy) } else { (ox + n.flex.left + n.look.dx, oy + n.flex.top + n.look.dy) }
  // (the last drawn over the others: looked for first)
  for i = n.kids.length() - 1; i >= 0; i = i - 1 {
    match self.hit(n.kids[i], bx, by, x, y) {
      Some(f) => return Some(f)
      None => ()
    }
  }
  if !n.slot && x >= bx && y >= by && x < bx + n.flex.width && y < by + n.flex.height {
    n.on_press
  } else {
    None
  }
}
