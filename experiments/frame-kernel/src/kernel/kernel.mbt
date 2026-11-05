// An independent vertical slice, not an adapter around view.Tree. Inputs own
// state changes; layout returns geometry; presentation only samples a trajectory.
// The existing flex engine and motion solver are reused without their scheduler.

///|
struct Row {
  height : Cell[Double]
}

///|
#derive(Eq, Debug)
enum Intrinsic {
  Fixed(Double)
  Editor(@ui.FieldLaid)
}

///|
fn Intrinsic::height(self : Intrinsic, width : Double) -> Double {
  match self {
    Fixed(height) => height
    Editor(field) => field.size(Some(width)).1
  }
}

///|
struct Box {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
struct Layout {
  composer : Box
  viewport : Box
  rows : Array[(Int, Box)]
} derive(Eq, Debug)

///|
struct Picture {
  logic_at : Double
  presented_at : Double
  layout : Layout
  offset : Double
  alive : Bool
} derive(Eq, Debug)

///|
struct Trajectory {
  from : Double
  velocity : Double
  target : Double
  starts : Double
  duration : Double
  spec : @motion.Spec
}

///|
fn Trajectory::still(value : Double) -> Trajectory {
  { from: value, velocity: 0.0, target: value, starts: 0.0, duration: 0.0, spec: Snap(0.0) }
}

///|
fn Trajectory::sample(self : Trajectory, at : Double) -> (Double, Double) {
  // The initial condition is exact. Re-evaluating a spring's analytic formula
  // at zero can round its velocity, breaking identity at an interruption.
  // A zero-duration transition is already at its target at its start.
  if at < self.starts || (at == self.starts && self.duration > 0.0) {
    return (self.from, self.velocity)
  }
  self.spec.value_at(at - self.starts, self.duration, self.from, self.target, self.velocity)
}

///|
fn Trajectory::toward(self : Trajectory, target : Double, at : Double, spec : @motion.Spec) -> Trajectory {
  let (from, velocity) = self.sample(at)
  { from, velocity, target, starts: at, duration: spec.duration(from, target, velocity), spec }
}

///|
struct Leaf {
  node : @flex.Node
  mut revision : Int
  mut width : Double
  mut height : Double
}

///|
struct Work {
  mut layouts : Int
  mut row_reads : Int
  mut measures : Int
  mut made : Int
  mut released : Int
}

///|
struct Kernel {
  // Only commit writes these. There is no clock provider, signal publication,
  // geometry notification, or general callback in the layout/presentation API.
  store : Store
  inputs : LayoutInputs
  placement : Query[(Double, Double), Layout]
  mut logic_at : Double
  mut page : Trajectory
  mut leaves_at : Double?
  mut alive : Bool
  mut owner_releases : Int
  mut owner_released_at : Double?
  work : Work
}

///|
// The query owns render resources only. It cannot own the Kernel that commits
// model changes, and row creation has no application callback or cleanup.
struct LayoutInputs {
  rows : Array[Row]
  composer_input : Cell[Intrinsic]
  anchor : Cell[Int]
  leaves : Map[Int, Leaf]
  composer : Leaf
  work : Work
}

///|
enum Change {
  Composer(Double)
  ComposerText(@ui.FieldLaid)
  RowHeight(Int, Double)
  Anchor(Int)
  Leave(Double, @motion.Spec)
  Return(@motion.Spec)
}

///|
fn Kernel::new(count : Int) -> Kernel {
  let store = Store::new()
  let work : Work = { layouts: 0, row_reads: 0, measures: 0, made: 0, released: 0 }
  let inputs : LayoutInputs = {
    rows: Array::makei(count, fn(_) { { height: store.cell(40.0, fn(a, b) { a == b }) } }),
    composer_input: store.cell(Fixed(60.0), fn(a, b) { a == b }),
    anchor: store.cell(count - 1, fn(a, b) { a == b }),
    leaves: {},
    composer: { node: @flex.Node::new(), revision: -1, width: -1.0, height: 0.0 },
    work,
  }
  {
    store,
    inputs,
    placement: store.query(fn(size) { inputs.layout(size.0, size.1) }),
    logic_at: 0.0,
    page: Trajectory::still(0.0),
    leaves_at: None,
    alive: true,
    owner_releases: 0,
    owner_released_at: None,
    work,
  }
}

///|
fn Kernel::advance(self : Kernel, at : Double) -> Unit {
  guard at >= self.logic_at else { abort("events must be delivered in logical order") }
  self.logic_at = at
  if self.leaves_at is Some(end) && at >= end && self.alive {
    self.alive = false
    self.leaves_at = None
    self.owner_releases += 1
    self.owner_released_at = Some(end)
    self.work.released += self.inputs.leaves.length()
    self.inputs.leaves.clear()
    self.placement.release()
  }
}

///|
fn Kernel::commit(self : Kernel, at : Double, change : Change) -> Unit {
  self.advance(at)
  guard self.alive else { return }
  self.store.commit(at, fn(tx) { match change {
    Composer(height) => {
      self.inputs.composer_input.set(tx, Fixed(height))
    }
    ComposerText(field) => {
      self.inputs.composer_input.set(tx, Editor(field))
    }
    RowHeight(i, height) => {
      if i >= 0 && i < self.inputs.rows.length() {
        self.inputs.rows[i].height.set(tx, height)
      }
    }
    Anchor(i) => {
      if i >= 0 && i < self.inputs.rows.length() {
        self.inputs.anchor.set(tx, i)
      }
    }
    Leave(distance, spec) => {
      self.page = self.page.toward(distance, at, spec)
      self.leaves_at = Some(at + self.page.duration)
    }
    Return(spec) => {
      self.page = self.page.toward(0.0, at, spec)
      self.leaves_at = None
    }
  } })
  // The input may create due work at its own timestamp (for example Snap(0)).
  // Its consequences belong to this input, before the next input can observe it.
  // This slice has one deadline; a general scheduler drains an ordered queue.
  self.advance(at)
}

///|
fn LayoutInputs::measure(self : LayoutInputs, leaf : Leaf, revision : Int, width : Double, input : Intrinsic) -> Double {
  if leaf.revision != revision || leaf.width != width {
    self.work.measures += 1
    let height = input.height(width)
    leaf.node.measure = Some(fn(w, _, _, _) { (w, height) })
    leaf.node.dirty = true
    @flex.compute(leaf.node, width~, round=false, reuse=true)
    leaf.revision = revision
    leaf.width = width
    leaf.height = height
  }
  leaf.node.height
}

///|
fn LayoutInputs::layout(self : LayoutInputs, width : Double, height : Double) -> Layout {
  self.work.layouts += 1
  // The common parent owns both measurements. The composer's result is a local
  // value passed straight to the list, never a signal sent back into structure.
  let composer_h = self.measure(self.composer, self.composer_input.revision, width, self.composer_input.get())
  let viewport_h = if height > composer_h { height - composer_h } else { 0.0 }
  let rows : Array[(Int, Box)] = []
  let used : Set[Int] = Set::new()
  let mut bottom = viewport_h
  let mut i = self.anchor.get()
  while i >= 0 && bottom > 0.0 {
    self.work.row_reads += 1
    let row = self.rows[i]
    let leaf = match self.leaves.get(i) {
      Some(leaf) => leaf
      None => {
        let leaf : Leaf = { node: @flex.Node::new(), revision: -1, width: -1.0, height: 0.0 }
        self.leaves[i] = leaf
        self.work.made += 1
        leaf
      }
    }
    let h = self.measure(leaf, row.height.revision, width, Fixed(row.height.get()))
    used.add(i)
    bottom -= h
    rows.push((i, { x: 0.0, y: bottom, width, height: h }))
    i -= 1
  }
  // Only previously visible leaves are visited here, never the source history.
  let gone = self.leaves.keys().filter(fn(i) { !used.contains(i) }).collect()
  for i in gone { self.leaves.remove(i); self.work.released += 1 }
  let layout : Layout = {
    composer: { x: 0.0, y: viewport_h, width, height: composer_h },
    viewport: { x: 0.0, y: 0.0, width, height: viewport_h },
    rows,
  }
  layout
}

///|
fn Kernel::frame(self : Kernel, now : Double, presented_at : Double, width : Double, height : Double) -> Picture {
  self.advance(now)
  let layout = if self.alive {
    self.placement.get((width, height))
  } else {
    { composer: { x: 0.0, y: 0.0, width: 0.0, height: 0.0 },
      viewport: { x: 0.0, y: 0.0, width, height }, rows: [] }
  }
  // Sampling ahead neither advances the model nor publishes reactive time.
  { logic_at: now, presented_at, layout, offset: self.page.sample(presented_at).0, alive: self.alive }
}

///|
fn Picture::row_at(self : Picture, x : Double, y : Double) -> Int? {
  if !self.alive { return None }
  let local_x = x - self.offset
  let clip = self.layout.viewport
  if local_x < 0.0 || local_x >= clip.width || y < 0.0 || y >= clip.height { return None }
  for (key, rect) in self.layout.rows {
    if y >= rect.y && y < rect.y + rect.height { return Some(key) }
  }
  None
}
