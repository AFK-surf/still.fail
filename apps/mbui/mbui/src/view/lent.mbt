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
  guard self.alive() else { return None }
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
  // (a row's name for its key (Tree::row_name): the row it is now, made anew as that may be; none while it is not made)
  if id.at < -1 {
    return match self.rows_known.get(id) {
      Some(at) if self.nodes[at].live && self.nodes[at].row_id == Some(id) => Some(self.handle(at))
      _ => None
    }
  }
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
/// What of the window node `id` can be seen in as what holds it cuts it (View::clips, View::clip_drawn: each that does,
/// as it was last placed, its scale with it): x0, y0, x1, y1 in the window, its own box not cut by itself.
pub fn Tree::seen_bounds(self : Tree, id : NodeId, drawing? : Bool = false) -> (Double, Double, Double, Double) {
  let mut b = (-1.0e9, -1.0e9, 1.0e9, 1.0e9)
  if id.at < 0 || id.at >= self.nodes.length() {
    return b
  }
  let mut i = self.nodes[id.at].parent
  while i >= 0 {
    let n = self.nodes[i]
    if n.look.clips || n.hosted_clips {
      let (x, y, _, sc) = self.projected(i, drawing~)
      let (x1, y1) = (x + n.flex.width * sc, y + n.flex.height * sc)
      b = (dmax(b.0, x), dmax(b.1, y), dmin(b.2, x1), dmin(b.3, y1))
    }
    // (and to the rect it cuts to as it is painted, View::clip_drawn)
    match n.look.clip_drawn {
      Some((cx, cy, cw, ch)) => {
        let (x, y, _, sc) = self.projected(i, drawing~)
        let (x0, y0) = (x + cx * sc, y + cy * sc)
        b = (dmax(b.0, x0), dmax(b.1, y0), dmin(b.2, x0 + cw * sc), dmin(b.3, y0 + ch * sc))
      }
      None => ()
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
/// Finish `f` at this cause, outside any layout already under way. With none under way it runs now; a change told
/// by a layout finishes as that layout returns, before the next event, never by asking for another frame. This is
/// for a cause that must read placement: it may place once there, then read all of its endpoints without reentering
/// the layout that told it. A drawing sample's clock is not a new cause. The caller keeps its own lifetime guard.
pub fn Tree::outside_layout(self : Tree, f : () -> Unit) -> Unit {
  if self.laying == 0 && self.layouts_active == 0 {
    f()
    return
  }
  let at = self.logic_at()
  let done = fn() {
    let was = self.cause_at
    self.cause_at = at
    defer { self.cause_at = was }
    @signals.start_batch()
    @signals.untracked(f)
    @signals.end_batch()
    // The callback can change what the completed layout draws. Finish those marks in this same sample too;
    // neither another frame nor a second advance of the timeline is needed to see this cause's result.
    @signals.untracked(fn() {
      self.pull()
      self.laid_out(self.clock.get())
    })
  }
  if self.laying > 0 {
    self.said_after_laid(done)
  } else {
    // A standalone measurement has no outer laid_out to drain after_laid. laid_out_now holds these callbacks
    // through its compute and its `then`; the measurement completes in this change, without a frame.
    @signals.after_flush(done)
  }
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
/// of a stack not shown): nothing of it shows, its place none. Followed as the tree publishes the layout's omissions.
pub fn View::shown_nowhere(self : View) -> Bool {
  self.tree.outs_said.get() |> ignore
  !self.alive() || self.tree.out_at(self.at)
}

///|
/// Whether it or an ancestor is explicitly kept out by View::shown, as those declarations say now.
/// Followed at their causes, without laying out or reading a previous layout's omissions. A retained activity
/// uses this declaration, not shown_nowhere: laid_nowhere's sampled omission, a row squeezed out by drops, clipping and opacity
/// are layout or paint results and do not start or cancel that activity. A node let go is nowhere.
pub fn View::declared_nowhere(self : View) -> Bool {
  guard self.alive() else { return true }
  let mut i = self.at
  while i >= 0 {
    let n = self.tree.nodes[i]
    let said = match n.nowhere_said {
      Some(said) => said
      None => {
        let said = @signals.signal(0)
        n.nowhere_said = Some(said)
        said
      }
    }
    said.get() |> ignore
    if n.nowhere_by is Some(read) && read() {
      return true
    }
    i = n.parent
  }
  false
}
