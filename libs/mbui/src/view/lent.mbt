// What a node lends what it holds (View::lends): a value of a kind (a Lent), found by any node under it however late
// it is made (shown by a structure's binding long after what made the lender returned), from itself up (View::lent):
// the nearest lender's. Nothing global said round a making and taken back after it: what is made later is under the
// same nodes, and finds the same. Of a node's making, not followed: what changes is a signal's, read through it.

///|
/// A kind of value nodes lend what they hold (View::lends), each lender's kept by it till it is let go.
pub struct Lent[T] {
  /// the lenders, each by the node that lends (its tree, its index and its making)
  priv lenders : Array[(View, T)]
}

///|
/// A kind of value lent, none lent yet.
pub fn[T] Lent::new() -> Lent[T] {
  { lenders: [] }
}

///|
/// It lends `value` of kind `key` to what it holds, made now or later, and to itself: kept till it is let go. A value
/// given as it is made, followed by nothing: what changes in it is a signal's to say (a reading of one lent), a lender
/// whose value is another made again (View::pick); lent again, those made before read the new one only as they read
/// it again.
pub fn[T] View::lends(self : View, key : Lent[T], value : T) -> View {
  guard self.alive() else { return self }
  match key.lenders.search_by(fn(e) { e.0.same(self) }) {
    Some(i) => key.lenders[i] = (self, value)
    None => {
      key.lenders.push((self, value))
      self.owns(fn() {
        match key.lenders.search_by(fn(e) { e.0.same(self) }) {
          Some(i) => key.lenders.remove(i) |> ignore
          None => ()
        }
      })
      |> ignore
    }
  }
  self
}

///|
/// What of kind `key` is lent to it: its own, else the nearest of what holds it that lends one; None where none does.
pub fn[T] View::lent(self : View, key : Lent[T]) -> T? {
  guard key.lenders.length() > 0 else { return None }
  let mut at : View? = Some(self)
  while at is Some(v) {
    match key.lenders.search_by(fn(e) { e.0.same(v) }) {
      Some(i) => return Some(key.lenders[i].1)
      None => at = v.parent()
    }
  }
  None
}

///|
/// Whether it is the same node as `other` (of the same tree, the same making).
fn View::same(self : View, other : View) -> Bool {
  physical_equal(self.tree, other.tree) && self.at == other.at && self.gen == other.gen
}

///|
/// What its innermost parts that show words or a drawing (words, a picture, shapes, lines) span across, in the window
/// (left, right), of those within its own box: none of them laid out nowhere (View::laid_nowhere, left out of its
/// row: View::drops; or what holds them so), none clear (alpha 0), none within `but`; None where none shows. As things are at the moment it is read (Tree::laid_now: what changed since the last frame laid out with it,
/// as an event finds them), not as the last frame drew them. The old view's Ctx::shown_across for a node of the tree,
/// of these parts alone (an old view hosted in it, a field, a native view: none counted). Read where its cause asks it
/// (as a sidebar is shown a while), not each frame.
pub fn View::shown_across(self : View, but? : View) -> (Double, Double)? {
  // (held by no node from the root (put by: View::park): nothing of it shows)
  guard self.alive() && self.tree.held_from_root(self.at) else { return None }
  // (laid out as of the moment it is read, what changed since the last frame with it: where an event finds things)
  self.tree.laid_now()
  let (left, top, w0, h0) = self.rect()
  let right = left + w0
  let foot = top + h0
  let lo = Ref(1.0e9)
  let hi = Ref(-1.0e9)
  fn walk(at : Int) -> Unit {
    let v = self.tree.handle(at)
    let n = self.tree.nodes[at]
    if !n.live || n.out || n.look.alpha <= 0.0 {
      return
    }
    match but {
      Some(b) if b.same(v) => return
      _ => ()
    }
    for k in n.kids {
      walk(k)
    }
    let shows = n.look.words != "" ||
      n.look.runs.length() > 0 ||
      n.look.shapes.length() > 0 ||
      n.look.lines.length() > 0 ||
      n.look.image is Some(_) ||
      n.look.picture is Some(_)
    guard shows else { return }
    let (x, y, w, h) = v.rect()
    if w <= 0.0 || h <= 0.0 || y + h <= top || y >= foot || x + w <= left || x >= right {
      return
    }
    if x < lo.val {
      lo.val = x
    }
    if x + w > hi.val {
      hi.val = x + w
    }
  }

  // (it laid out nowhere, or what holds it: nothing of it shows)
  if self.tree.out_at(self.at) {
    return None
  }
  for k in self.tree.nodes[self.at].kids {
    walk(k)
  }
  if hi.val < lo.val {
    None
  } else {
    Some((lo.val, hi.val))
  }
}

///|
/// The node `id` names, while it lives (that making of it); None let go.
pub fn Tree::view_of(self : Tree, id : NodeId) -> View? {
  if id.at < 0 || id.at >= self.nodes.length() {
    return None
  }
  let v = self.handle(id.at)
  if v.gen == id.gen && v.alive() {
    Some(v)
  } else {
    None
  }
}

///|
/// What of the window node `id` can be seen in as what holds it cuts it (View::clips: each that does, as it was last
/// placed, its scale with it): x0, y0, x1, y1 in the window, its own box not cut by itself.
pub fn Tree::seen_bounds(self : Tree, id : NodeId) -> (Double, Double, Double, Double) {
  let mut b = (-1.0e9, -1.0e9, 1.0e9, 1.0e9)
  if id.at < 0 || id.at >= self.nodes.length() {
    return b
  }
  let mut i = self.nodes[id.at].parent
  while i >= 0 {
    let n = self.nodes[i]
    if n.look.clips {
      let (x, y, sc) = self.placed(i)
      let (x1, y1) = (x + n.flex.width * sc, y + n.flex.height * sc)
      b = (dmax(b.0, x), dmax(b.1, y), dmin(b.2, x1), dmin(b.3, y1))
    }
    i = n.parent
  }
  b
}

///|
/// Laid out as of the logic's moment, what the change under way set so far counted (Tree::laid_now): where an event
/// finds things, for what reads where they are then (what words a press picks).
pub fn Tree::laid_as_now(self : Tree) -> Unit {
  self.laid_now()
}

///|
/// The node that scrolls by it now (View::scrolls: its column, its row), while it does; None where none does (not said
/// yet, or let go).
pub fn Scroll::shown_by(self : Scroll) -> View? {
  match self.host {
    Some(v) if v.alive() => Some(v)
    _ => None
  }
}

///|
/// Whether it is laid out nowhere, or what holds it is (View::laid_nowhere, left out of its row: View::drops; a page
/// of a stack not shown), or it is held by no node from the root (put by: View::park): nothing of it shows, its place
/// none.
pub fn View::shown_nowhere(self : View) -> Bool {
  !self.alive() || !self.tree.held_from_root(self.at) || self.tree.out_at(self.at)
}
