// Intrinsic measurements form a layout graph. Expressions contain geometry and
// captured numeric inputs, never a callback that can publish a model change.
// This is the first actual-app integration of the independent frame experiment.

///|
pub enum Height {
  Constant(Double)
  Natural(View, Double)
  Plus(Height, Height)
  Minus(Height, Height)
  Maximum(Height, Height)
}

///|
pub fn height(value : Double) -> Height { Constant(value) }

///|
/// An intrinsic height at an explicit width, evaluated only by layout. This does
/// not read or publish the last layout result, and cannot advance the tree.
pub fn View::natural_height(self : View, width : Double) -> Height {
  Natural(self, width)
}

///|
pub fn Height::plus(self : Height, other : Height) -> Height { Plus(self, other) }

///|
pub fn Height::minus(self : Height, other : Height) -> Height { Minus(self, other) }

///|
pub fn Height::maximum(self : Height, other : Height) -> Height { Maximum(self, other) }

///|
impl Eq for Height with equal(a, b) {
  match (a, b) {
    (Constant(x), Constant(y)) => x == y
    (Natural(x, w), Natural(y, v)) => physical_equal(x.tree, y.tree) && x.id() == y.id() && w == v
    (Plus(a, b), Plus(c, d)) | (Minus(a, b), Minus(c, d)) | (Maximum(a, b), Maximum(c, d)) => a == c && b == d
    _ => false
  }
}

///|
fn Height::sources(self : Height, tree : Tree, out : Set[NodeId]) -> Unit {
  match self {
    Constant(_) => ()
    Natural(v, _) => {
      guard physical_equal(v.tree, tree) else { abort("a height expression belongs to one tree") }
      out.add(v.id())
    }
    Plus(a, b) | Minus(a, b) | Maximum(a, b) => { a.sources(tree, out); b.sources(tree, out) }
  }
}

///|
fn Height::value(self : Height) -> Double {
  match self {
    Constant(h) => h
    Natural(v, width) => match v.live() {
      Some(n) => @flex.measured_height(n.flex, width)
      None => 0.0
    }
    Plus(a, b) => a.value() + b.value()
    Minus(a, b) => a.value() - b.value()
    Maximum(a, b) => { let x = a.value(); let y = b.value(); if x > y { x } else { y } }
  }
}

///|
// A source's intrinsic size depends on its children and their measurement
// sources. Reject that graph reaching its own consumer before installing it.
fn Tree::height_cycle(self : Tree, target : NodeId, sources : Array[NodeId]) -> Bool {
  let todo = sources.copy()
  let seen : Set[NodeId] = Set::new()
  while todo.length() > 0 {
    let id = todo.pop().unwrap()
    if id == target { return true }
    if seen.contains(id) || !self.alive_id(id) { continue }
    seen.add(id)
    for child in self.nodes[id.at].kids {
      let n = self.nodes[child]
      if n.live { todo.push({ at: child, gen: n.gen }) }
    }
    match self.height_sources.get(id) {
      Some(deps) => todo.append(deps)
      None => ()
    }
  }
  false
}

///|
fn Tree::height_unlink(self : Tree, target : NodeId) -> Unit {
  match self.height_sources.get(target) {
    Some(sources) => for source in sources {
      match self.height_users.get(source) {
        Some(users) => {
          users.remove(target)
          if users.is_empty() { self.height_users.remove(source) }
        }
        None => ()
      }
    }
    None => ()
  }
  self.height_sources.remove(target)
}

///|
fn Tree::height_dirty(self : Tree, at : Int) -> Unit {
  // Ordinary nodes pay the original ancestor walk when there are no queries.
  if self.height_users.is_empty() {
    let mut i = at
    while i >= 0 { self.nodes[i].flex.dirty = true; i = self.nodes[i].parent }
    return
  }
  let todo = [at]
  let seen : Set[Int] = Set::new()
  while todo.length() > 0 {
    let mut i = todo.pop().unwrap()
    while i >= 0 && !seen.contains(i) {
      seen.add(i)
      let n = self.nodes[i]
      n.flex.dirty = true
      match self.height_users.get({ at: i, gen: n.gen }) {
        Some(users) => for id in users {
          if self.alive_id(id) { todo.push(id.at) }
        }
        None => ()
      }
      i = n.parent
    }
  }
}

///|
/// A leaf's height as an intrinsic expression, in the same layout calculation.
/// The binding captures model inputs; layout evaluates numeric geometry only.
/// The sources must not contain the leaf or depend on it through another query.
pub fn View::height_measured(self : View, expression : Live[Height]) -> View {
  guard self.live() is Some(n) else { return self }
  let tree = self.tree
  let target = self.id()
  let current : Ref[Height] = Ref(Constant(0.0))
  n.flex.measure = Some(fn(w, _, _, _) {
    tree.work.measured += 1
    let h = current.val.value()
    guard h >= 0.0 && !h.is_inf() else { abort("a height expression must be finite and nonnegative") }
    (w, h)
  })
  self.bind(Measured, expression, Layout, fn(expr) {
    let ids : Set[NodeId] = Set::new()
    expr.sources(tree, ids)
    let sources = ids.iter().collect()
    let old = tree.height_sources.get(target).unwrap_or([])
    if sources != old {
      guard !tree.height_cycle(target, sources) else { abort("intrinsic height dependency cycle") }
      tree.height_unlink(target)
      tree.height_sources[target] = sources
      for source in sources {
        let users = match tree.height_users.get(source) {
          Some(users) => users
          None => { let users : Set[NodeId] = Set::new(); tree.height_users[source] = users; users }
        }
        users.add(target)
      }
    }
    current.val = expr
  })
  self.owns(fn() { tree.height_unlink(target); current.val = Constant(0.0) }) |> ignore
  self
}
