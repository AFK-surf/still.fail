// A view made once (docs/retained.md, the model; the way there's 2). Each node is made when it first shows and stays
// until what holds it lets it go; what of it changes is a binding of one property, run as what it read changes, and
// that property alone is set again: a layout property marks the node (and what holds it) to be laid out, a paint
// property the node's look to be worked out again. What comes and goes is a node of its own (`show`, `pick`, `each`),
// whose nodes it makes, keeps and lets go, and each node's bindings go with it. Acting is a callback run outside any
// tracking. Time is a signal (Tree::now), read where it is used: a look worked out from it is painted again as it goes,
// nothing else done.
//
// A frame (Tree::frame) does what was marked: lays out the nodes marked (flex's reuse: those not marked keep where they
// were), works out again the looks marked, and draws every node from what it keeps.

///|
/// A property's value: set once (`Is`), or worked out (`By`), tracked, and set again as what it read changes.
pub(all) enum Live[T] {
  Is(T)
  By(() -> T)
}

///|
/// What a node is drawn as, kept by the node: its ground (0: none), its words and their ink, how opaque, and how far it
/// is drawn off where it is laid out.
pub(all) struct Look {
  mut ground : Int64
  mut ink : Int64
  mut words : String
  mut alpha : Double
  mut dx : Double
  mut dy : Double
} derive(Eq, Debug)

///|
/// A node as a frame draws it: which, where (in the window, its look's offset in), how big, and its look.
pub(all) struct Drawn {
  id : Int
  x : Double
  y : Double
  w : Double
  h : Double
  look : Look
} derive(Eq, Debug)

///|
/// What the tree did, counted from its making: nodes made and let go, bindings run, nodes laid out, looks worked out,
/// structure bindings run (show, pick, each). For a test to say what work a change did, not how long it took.
pub(all) struct Work {
  mut made : Int
  mut let_go : Int
  mut bound : Int
  mut computes : Int
  mut laid : Int
  mut looks : Int
  mut structure : Int
} derive(Eq, Debug)

///|
/// A node made once.
pub struct View {
  /// who it is: never another node's while it lives
  id : Int
  tree : Tree
  /// how it is laid out (flex's node: kept, reused while not marked)
  flex : @flex.Node
  /// its look as last worked out, and whether it is marked to be worked out again
  look : Look
  /// what holds it and what it holds, in order
  mutable_parent : Ref[View?]
  kids : Array[View]
  /// what stops its bindings (each one's effect), run as it is let go
  stops : Array[() -> Unit]
  /// what a press on it does (run outside any tracking)
  mut on_press : (() -> Unit)?
  mut alive : Bool
  /// a slot (show, pick, each): no box of its own, what it holds laid out as its holder's own
  mut slot : Bool
  /// marked for its look to be worked out again this frame
  mut look_due : Bool
}

///|
/// The nodes made once of a window, its clock and what it did.
pub struct Tree {
  /// the frames' clock (ms): what reads it is told as it goes
  clock : @signals.Signal[Double]
  /// how words are measured: (words, width offered) -> (width, height)
  measure : (String, Double) -> (Double, Double)
  /// the nodes whose look is to be worked out again, and whether any node is to be laid out
  looks_due : Array[View]
  mut layout_due : Bool
  mut last_w : Double
  mut last_h : Double
  mut ids : Int
  work : Work
  mut root : View?
}

///|
/// A tree whose root `make` makes (as the root's own: its bindings, its nodes), its words measured by `measure`.
pub fn Tree::new(make : (View) -> Unit, measure? : (String, Double) -> (Double, Double) = words_measure) -> Tree {
  let t : Tree = {
    clock: @signals.signal(0.0, same=fn(a, b) { a == b }),
    measure,
    looks_due: [],
    layout_due: true,
    last_w: -1.0,
    last_h: -1.0,
    ids: 0,
    work: { made: 0, let_go: 0, bound: 0, computes: 0, laid: 0, looks: 0, structure: 0 },
    root: None,
  }
  let root = t.made(None)
  t.root = Some(root)
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
fn Tree::made(self : Tree, parent : View?) -> View {
  self.ids = self.ids + 1
  self.work.made = self.work.made + 1
  let v : View = {
    id: self.ids,
    tree: self,
    flex: @flex.Node::new(),
    look: { ground: 0L, ink: 0L, words: "", alpha: 1.0, dx: 0.0, dy: 0.0 },
    mutable_parent: Ref(parent),
    kids: [],
    stops: [],
    on_press: None,
    alive: true,
    slot: false,
    look_due: true,
  }
  self.looks_due.push(v)
  v
}

///|
pub fn Tree::root(self : Tree) -> View {
  self.root.unwrap()
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
/// A node made in `self`, after what it holds already, made by `make` as its own.
pub fn View::box(self : View, make : (View) -> Unit) -> View {
  let v = self.tree.made(Some(self))
  self.kids.push(v)
  self.boxes_again()
  make(v)
  v
}

///|
/// What holds it, if anything does.
pub fn View::parent(self : View) -> View? {
  self.mutable_parent.val
}

///|
/// The nodes it holds, in order.
pub fn View::kids(self : View) -> Array[View] {
  self.kids
}

///|
/// Whether it lives (not let go).
pub fn View::alive(self : View) -> Bool {
  self.alive
}

///|
/// Its id.
pub fn View::id(self : View) -> Int {
  self.id
}

///|
/// Where it was last laid out, in the window, and how big.
pub fn View::rect(self : View) -> (Double, Double, Double, Double) {
  let mut x = self.flex.left
  let mut y = self.flex.top
  let mut at = self.parent()
  while at is Some(p) {
    x = x + p.flex.left
    y = y + p.flex.top
    at = p.parent()
  }
  (x, y, self.flex.width, self.flex.height)
}

///|
/// Its layout to be done again (what holds it with it: its size may change theirs).
fn View::layout_marked(self : View) -> Unit {
  self.tree.layout_due = true
  self.flex.dirty = true
  let mut at = self.parent()
  // (every one up to the root: one marked before and not laid out since, its holder's layout reused, is no sign the
  // rest are)
  while at is Some(p) {
    p.flex.dirty = true
    at = p.parent()
  }
}

///|
/// Its look to be worked out again.
fn View::look_marked(self : View) -> Unit {
  if !self.look_due {
    self.look_due = true
    self.tree.looks_due.push(self)
  }
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
/// it works the value out, not as it is set), marking what its phase does again.
pub fn[T] View::bind(self : View, live : Live[T], phase : Phase, apply : (T) -> Unit) -> Unit {
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
      let stop = @signals.effect(fn() {
        let v = f()
        @signals.untracked(fn() {
          if self.alive {
            self.tree.work.bound = self.tree.work.bound + 1
            apply(v)
            marked()
          }
        })
      })
      self.stops.push(stop)
    }
  }
}

///|
/// Its width (points; None: as its content and its holder make it).
pub fn View::width(self : View, w : Live[Double?]) -> View {
  self.bind(w, Layout, fn(w) {
    self.flex.style.set_width(match w {
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
    self.flex.style.set_height(match h {
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
    let s = self.flex.style
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
  self.bind(across, Layout, fn(a) { self.flex.style.direction = if a { Row } else { Column } })
  self
}

///|
/// How much of the room left it takes.
pub fn View::grow(self : View, g : Live[Double]) -> View {
  self.bind(g, Layout, fn(g) { self.flex.style.grow = g })
  self
}

///|
/// Its ground (0: none): paint's.
pub fn View::ground(self : View, ink : Live[Int64]) -> View {
  self.bind(ink, Paint, fn(k) { self.look.ground = k })
  self
}

///|
/// How opaque it is drawn: paint's.
pub fn View::alpha(self : View, a : Live[Double]) -> View {
  self.bind(a, Paint, fn(a) { self.look.alpha = a })
  self
}

///|
/// How far it is drawn off where it is laid out: paint's (a move on the compositor: never laid out again).
pub fn View::offset(self : View, d : Live[(Double, Double)]) -> View {
  self.bind(d, Paint, fn(d) {
    self.look.dx = d.0
    self.look.dy = d.1
  })
  self
}

///|
/// The words it shows: layout's (their size) and paint's.
pub fn View::words(self : View, words : Live[String], ink? : Int64 = 0xFF000000L) -> View {
  self.look.ink = ink
  let tree = self.tree
  self.flex.measure = Some(fn(w, wm, _h, _hm) {
    let offered = match wm {
      Exactly | AtMost => w
      Undefined => -1.0
    }
    let (mw, mh) = (tree.measure)(self.look.words, offered)
    match wm {
      Exactly => (w, mh)
      _ => (mw, mh)
    }
  })
  self.bind(words, Both, fn(s) { self.look.words = s })
  self
}

///|
/// What a press on it does: run outside any tracking, as one change (what it writes told once it is done).
pub fn View::on_press(self : View, f : () -> Unit) -> View {
  self.on_press = Some(f)
  self
}

///|
/// Lets it go: what it holds first, then its bindings stopped, out of what held it.
fn View::let_go(self : View) -> Unit {
  if !self.alive {
    return
  }
  for k in self.kids {
    k.let_go()
  }
  self.alive = false
  for stop in self.stops {
    stop()
  }
  self.stops.clear()
  self.tree.work.let_go = self.tree.work.let_go + 1
}

///|
/// A node holding what comes and goes (show, pick, each): laid out as though what it holds were its holder's own.
fn View::slot(self : View) -> View {
  let v = self.tree.made(Some(self))
  v.slot = true
  self.kids.push(v)
  v
}

///|
/// The boxes it lays out as its own, in order: its own, or a slot's, those of what it holds.
fn View::boxes(self : View, into : Array[@flex.Node]) -> Unit {
  if self.slot {
    for k in self.kids {
      k.boxes(into)
    }
  } else {
    into.push(self.flex)
  }
}

///|
/// What it holds changed (made, let go, moved): the boxes of the node that lays them out (itself, or the first not a
/// slot holding it) put again in order, it marked to be laid out.
fn View::boxes_again(self : View) -> Unit {
  let mut at = self
  while at.slot {
    match at.parent() {
      Some(p) => at = p
      None => break
    }
  }
  let all : Array[@flex.Node] = []
  for k in at.kids {
    k.boxes(all)
  }
  at.flex.children.clear()
  for b in all {
    at.flex.children.push(b)
  }
  at.layout_marked()
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
  slot.stops.push(stop)
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
  slot.stops.push(stop)
}

///|
/// Node `v` let go and taken out of what it holds.
fn View::drop(self : View, v : View) -> Unit {
  v.let_go()
  match self.kids.search_by(fn(k) { physical_equal(k, v) }) {
    Some(i) => {
      self.kids.remove(i) |> ignore
    }
    None => ()
  }
  self.boxes_again()
}

///|
/// A node for each of `items` by its key, made as its key comes, kept while it stays (given its item as a signal of
/// its own: what it shows of it set again, the node not made again), moved as the order changes, let go as it goes.
pub fn[T, K : Hash + Eq] View::each(
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
      let order : Array[View] = []
      for it in all {
        let k = key(it)
        seen[k] = true
        match rows.get(k) {
          Some((v, item)) => {
            item.set(it)
            order.push(v)
          }
          None => {
            let item = @signals.signal(it)
            let v = slot.box(fn(v) { row(v, item) })
            rows[k] = (v, item)
            order.push(v)
          }
        }
      }
      // gone: let go
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
      // in the order given
      let moved = order.length() != slot.kids.length() ||
        order.mapi(fn(i, v) { !physical_equal(slot.kids[i], v) }).contains(true)
      if moved {
        slot.kids.clear()
        for v in order {
          slot.kids.push(v)
        }
        slot.boxes_again()
      }
    })
  })
  slot.stops.push(stop)
}

///|
/// A frame of `w` by `h` at the clock's time: the nodes marked laid out, the looks marked worked out again, every node
/// drawn from what it keeps, in order.
pub fn Tree::frame(self : Tree, w : Double, h : Double) -> Array[Drawn] {
  let root = self.root()
  if w != self.last_w || h != self.last_h {
    self.last_w = w
    self.last_h = h
    root.flex.style.set_width(Pt(w))
    root.flex.style.set_height(Pt(h))
    root.flex.dirty = true
    self.layout_due = true
  }
  if self.layout_due {
    self.layout_due = false
    self.work.computes = self.work.computes + 1
    let gen = @flex.computes()
    @flex.compute(root.flex, width=w, height=h, round=false, reuse=true)
    count_laid(root, gen + 1, self.work)
  }
  // (each look marked once, however many of its properties changed)
  for v in self.looks_due {
    if v.alive {
      self.work.looks = self.work.looks + 1
    }
    v.look_due = false
  }
  self.looks_due.clear()
  let out : Array[Drawn] = []
  draw_into(root, 0.0, 0.0, out)
  out
}

///|
/// The nodes the compute laid out again (not reusing their layout), counted.
fn count_laid(v : View, gen : Int, work : Work) -> Unit {
  if v.flex.laid_out_at() == gen {
    work.laid = work.laid + 1
  }
  for k in v.kids {
    count_laid(k, gen, work)
  }
}

///|
fn draw_into(v : View, ox : Double, oy : Double, out : Array[Drawn]) -> Unit {
  let x = ox + v.flex.left
  let y = oy + v.flex.top
  if !v.slot {
    out.push({ id: v.id, x: x + v.look.dx, y: y + v.look.dy, w: v.flex.width, h: v.flex.height, look: { ..v.look } })
  }
  // (what a slot holds is laid out in its holder's place)
  let (cx, cy) = if v.slot { (ox, oy) } else { (x, y) }
  for k in v.kids {
    draw_into(k, cx, cy, out)
  }
}

///|
/// A press at (x, y): the topmost node there that does something when pressed does it, outside any tracking, as one
/// change. True if one did.
pub fn Tree::press(self : Tree, x : Double, y : Double) -> Bool {
  match hit(self.root(), 0.0, 0.0, x, y) {
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
fn hit(v : View, ox : Double, oy : Double, x : Double, y : Double) -> (() -> Unit)? {
  let contents = v.slot
  let bx = if contents { ox } else { ox + v.flex.left }
  let by = if contents { oy } else { oy + v.flex.top }
  // (the last drawn over the others: looked for first)
  for i = v.kids.length() - 1; i >= 0; i = i - 1 {
    match hit(v.kids[i], bx, by, x, y) {
      Some(f) => return Some(f)
      None => ()
    }
  }
  if !contents && x >= bx && y >= by && x < bx + v.flex.width && y < by + v.flex.height {
    v.on_press
  } else {
    None
  }
}

///|
/// The clock now (Tree::now), for what a node works out from the time.
pub fn View::now(self : View) -> Double {
  self.tree.now()
}
