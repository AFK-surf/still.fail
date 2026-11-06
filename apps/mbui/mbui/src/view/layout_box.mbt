// A box whose children it lays out itself (View::layout_box): which it makes, measures and places, and in what order,
// in its own layout (a list from its anchor: the rows it needs alone, made as it comes to them); what it measures given
// back to it there, never told as a signal of its own. Its place reads what it took before it (`content`) and its
// constraints, no other; a row it makes is made as any view is (the build's guard), one it measures measured as flex
// measures one (the layout's).

///|
pub struct Layout {
  width : Double
  height : Double
  priv owner : View
  priv origin : (Double, Double)
  priv live : Ref[Bool]
  priv keyed : Map[String, View]
  priv used : Array[String]
  priv seen : Set[String]
  /// the children placed, by their nodes, in the order they were last placed: the order the keyed are drawn and hit in
  priv placed : Array[Int]
  /// how tall what it holds is, as `place` says (Layout::size_to): a box sized by what it holds is as tall as that
  priv said_h : Ref[Double]
  /// the children measured in this layout (Layout::measure, fit): what Layout::reported reads of, none else
  priv measured : Set[Int]
}

///|
/// How tall what it holds is, said by `place` (as tall as the children it measured and placed go): the box's own height
/// where it was laid out sized by them (View::layout_box's `sized`), given its width alone, in the same layout, as a
/// leaf's measure says its height. Its `height` is then infinite: none is given.
pub fn Layout::size_to(self : Layout, h : Double) -> Unit {
  self.said_h.val = h
}

///|
fn Layout::check(self : Layout, child : View) -> Unit {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  guard physical_equal(child.tree, self.owner.tree) && child.alive() &&
    child.tree.nodes[child.at].parent == self.owner.at else {
    abort("a layout can only measure or place its own direct children")
  }
}

///|
/// Its child by `key`, made by `make` the first time it is asked for (a build, under the build's guard), the same one
/// while it is asked for in each of its layouts; one not asked for in one let go. One asked for and not placed is kept
/// (what is selected in it, what moves in it), drawn and pressed nowhere.
pub fn Layout::child(self : Layout, key : String, make : (View) -> Unit) -> View {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let child = match self.keyed.get(key) {
    Some(v) if v.alive() => v
    _ => {
      let guard_before = @signals.set_access_guard(@signals.phase_guard(Build))
      let v = self.owner.box(make)
      @signals.set_access_guard(guard_before) |> ignore
      v.tree.nodes[v.at].flex.line = -1
      self.keyed[key] = v
      v
    }
  }
  if !self.seen.contains(key) {
    self.seen.add(key)
    self.used.push(key)
  }
  child
}

///|
/// The child measured `width` wide (`height` tall, where said) now, before another that needs its height: as flex
/// measures one (the layout's guard, what measuring reads (a font's theme) read as ever), the same one at the same
/// constraints not measured again; no other layout of the tree begun, nothing told. `foot`: how much room to leave under
/// what it holds and how much of its foot is covered (a list under a composer: the composer measured first), given it
/// as a constraint of this layout, as its own `foot_room` and `foot_cover` (View::scrolls_anchored, Layout::given_foot):
/// what it holds laid out again where that changed, in the same layout.
pub fn Layout::measure(
  self : Layout,
  child : View,
  width : Double,
  height? : Double,
  foot? : (Double, Double),
) -> (Double, Double) {
  self.check(child)
  child.tree.anchors_due(self.owner.at, child.at)
  match foot {
    Some(f) => {
      let tree = child.tree
      if tree.feet.get(child.at) != Some(f) {
        tree.feet[child.at] = f
        // (what reads it laid out again, in this layout: Layout::given_foot)
        match tree.foot_readers.get(child.at) {
          Some(rs) =>
            for r in rs {
              if tree.nodes[r.at].live && tree.nodes[r.at].gen == r.gen {
                tree.layout_marked_at(r.at)
              }
            }
          None => ()
        }
      }
    }
    None => ()
  }
  // (the tree's layout owner still this box: what the child does to another branch aborted)
  let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
  let size = @flex.layout_child(child.tree.nodes[child.at].flex, width, height?, containing_height=self.height)
  self.measured.add(child.at)
  child.tree.box_measured.add(child.at)
  child.tree.box_stale.remove(child.at)
  @signals.set_access_guard(guard_before) |> ignore
  size
}

///|
/// The child measured and laid out as wide as it asks, `most` at most, as Layout::measure measures it.
pub fn Layout::fit(self : Layout, child : View, most : Double) -> (Double, Double) {
  self.check(child)
  child.tree.anchors_due(self.owner.at, child.at)
  let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
  let size = @flex.layout_child_fitted(child.tree.nodes[child.at].flex, most, containing_height=self.height)
  self.measured.add(child.at)
  child.tree.box_measured.add(child.at)
  child.tree.box_stale.remove(child.at)
  @signals.set_access_guard(guard_before) |> ignore
  size
}

///|
/// The child, measured, put at (`x`, `y`) in the box's content; one asked for and not placed in a layout is hidden.
pub fn Layout::place(self : Layout, child : View, x : Double, y : Double) -> Unit {
  self.check(child)
  let n = child.tree.nodes[child.at].flex
  n.left = self.origin.0 + x
  n.top = self.origin.1 + y
  n.line = 0
  // (placed again: where this placing has it, the last)
  match self.placed.search(child.at) {
    Some(i) => self.placed.remove(i) |> ignore
    None => ()
  }
  self.placed.push(child.at)
}

///|
/// The box's children laid out by `place` (a box of a bound size, or `sized`: given its width alone, as tall as `place`
/// says, Layout::size_to, a list of files or a card as tall as its words, in the same layout): what it reads taken by `content` before its layout,
/// `place` given that and its constraints alone (any other read aborts), making the children it asks for
/// (Layout::child), measuring and placing them in the order it needs; another branch changed or a geometry told from
/// it aborts. Laid out again as its content, its constraints or a child it measured changes; nothing done else.
pub fn[K : Eq] View::layout_box(
  self : View,
  content : Live[K],
  place : (Layout, K) -> Unit,
  sized? : Bool = false,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.flex.sized_by_children = sized
  let value : Ref[K?] = Ref(None)
  let keyed : Map[String, View] = {}
  n.flex.layout_children = Some(fn(width, height, x, y) {
    let was_owner = self.tree.layout_owner
    self.tree.layout_owner = self.at
    // (the children measured in this layout, and those of them changed after and not measured since: its own, apart
    // from those of a box it lays out inside it)
    let was_measured = self.tree.box_measured
    let was_stale = self.tree.box_stale
    self.tree.box_measured = Set::new()
    self.tree.box_stale = Set::new()
    // (sized by what it holds, given no height: as tall as `place` says)
    let unbounded = height != height
    let ctx : Layout = {
      width,
      height: if unbounded { @double.infinity } else { height },
      owner: self,
      origin: (x, y),
      live: Ref(true),
      keyed,
      used: [],
      seen: Set::new(),
      placed: [],
      said_h: Ref(0.0 / 0.0),
      measured: Set::new(),
    }
    // Only the final state is published by Tree::walk, so a child kept hidden and then placed never disappears.
    for at in n.kids { self.tree.nodes[at].flex.line = -1 }
    // (what it reports said anew by this layout: Layout::report; the foot it reads read anew, Layout::given_foot)
    self.tree.reports.remove(self.at)
    self.tree.foot_unread(self.at)
    self.tree.anchor_unread(self.at)
    self.tree.layouts.push(ctx)
    match value.val {
      Some(v) => {
        let guard_before = @signals.set_access_guard(Some("layout_box node \{self.at} must use content and constraints"))
        @signals.untracked(fn() { place(ctx, v) })
        @signals.set_access_guard(guard_before) |> ignore
      }
      None => ()
    }
    self.tree.layouts.pop() |> ignore
    let gone = []
    for k, child in keyed {
      if !ctx.seen.contains(k) { gone.push((k, child)) }
    }
    for (k, child) in gone {
      keyed.remove(k)
      self.drop(child)
    }
    // Fixed children keep their order; the keyed part is drawn and hit in the order this layout placed it (a list's
    // rows top to bottom, whichever it measured first), then those kept hidden, as they were requested. Changing keys'
    // order must change paint and hit order without rebuilding those keys' nodes.
    let keyed_at : Set[Int] = Set::new()
    for _, child in keyed { keyed_at.add(child.at) }
    let ordered = n.kids.filter(fn(at) { !keyed_at.contains(at) })
    for at in ctx.placed {
      if keyed_at.contains(at) { ordered.push(at) }
    }
    for k in ctx.used {
      let at = keyed[k].at
      if !ctx.placed.contains(at) { ordered.push(at) }
    }
    if ordered != n.kids {
      n.kids.clear()
      n.kids.append(ordered)
      self.boxes_again()
    }
    // (a child measured, then changed in this same layout (what it is laid out by set after, what those it let go did
    // as they went counted), and not measured again: what was placed by is not what it is; a fault, saying which)
    if !self.tree.box_stale.is_empty() {
      let stale = self.tree.box_stale.iter().collect()
      fault("layout_box node \{self.at}: children \{stale} changed after they were measured in its layout, not measured again")
    }
    self.tree.box_measured = was_measured
    self.tree.box_stale = was_stale
    ctx.live.val = false
    self.tree.layout_owner = was_owner
    let said = ctx.said_h.val
    if unbounded && said != said {
      abort("layout_box node \{self.at}, sized by what it holds and given no height, said none: Layout::size_to")
    }
    said
  })
  self.bind(LayoutBox, content, Layout, fn(v) { value.val = Some(v) })
  self.owns(fn() {
    keyed.clear()
    value.val = None
    n.flex.layout_children = None
    n.flex.sized_by_children = false
  }) |> ignore
  self
}

///|
/// What it holds chosen by the room it is given (its holder's constraints, as it is laid out) and by `content` (what
/// else the choice reads: the words, the theme, the system's words' size, taken before the layout as layout_box's is):
/// `pick` says which of its arrangements that room calls for (it may measure words, as layout measures them; anything
/// else it reads is in `content`, which is followed: read in `pick` it is not) (窄排法 or 宽排法, a segment's words as they fit its track), the child of that
/// arrangement made by `make` and laid out filling it, in the same layout: nothing of its size read back and set. A
/// layout_box of one child; it is as big as its holder lays it out (grown, a share, over all of it), not as its child.
/// The child of an arrangement not picked in a layout is let go (a cache of the picture: it keeps nothing of the app's).
pub fn[C : Eq, K : Show] View::by_room(
  self : View,
  content : Live[C],
  pick : (C, Double, Double) -> K,
  make : (View, K) -> Unit,
  sized? : Bool = false,
) -> View {
  self.layout_box(content, sized~, fn(l, c) {
    // (what it measures as it picks read as measuring reads it, Layout::measure's: a font's theme read as ever)
    let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
    let k = pick(c, l.width, l.height)
    @signals.set_access_guard(guard_before) |> ignore
    let child = l.child(k.to_string(), fn(v) { make(v, k) })
    // (sized by it: as tall as the child picked, given the width; else filling the room)
    if l.height == @double.infinity {
      l.size_to(l.measure(child, l.width).1)
    } else {
      l.measure(child, l.width, height=l.height) |> ignore
    }
    l.place(child, 0.0, 0.0)
  })
}

///|
/// Its child by `key`, asked for in this layout (Layout::child), let go as it ends unless asked for again: one made only
/// to be measured (a row a scroll went past), kept by nothing.
pub fn Layout::let_go(self : Layout, key : String) -> Unit {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  self.seen.remove(key)
  match self.used.search(key) {
    Some(i) => self.used.remove(i) |> ignore
    None => ()
  }
}

///|
/// Box `at` no longer a reader of the foot it read last (Layout::given_foot): laid out again (it reads it anew, if it
/// still does), or its place made again for another.
fn Tree::foot_unread(self : Tree, at : Int) -> Unit {
  match self.foot_read.get(at) {
    Some(foot) => {
      self.foot_read.remove(at)
      match self.foot_readers.get(foot) {
        Some(rs) => {
          rs.retain(fn(r) { r.at != at })
          if rs.is_empty() {
            self.foot_readers.remove(foot)
          }
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
/// The room under what it holds and how much of its foot is covered, as what holds it (or a holder of that) gave it as
/// it measured it (Layout::measure's `foot`), in this layout: None where none did. Read so, it is laid out again as
/// that changes.
pub fn Layout::given_foot(self : Layout) -> (Double, Double)? {
  let tree = self.owner.tree
  let mut i = self.owner.at
  while i >= 0 {
    match tree.feet.get(i) {
      Some(f) => {
        let me = self.owner.id()
        if tree.foot_read.get(me.at) != Some(i) {
          tree.foot_unread(me.at)
          tree.foot_read[me.at] = i
        }
        match tree.foot_readers.get(i) {
          Some(rs) => if !rs.contains(me) { rs.push(me) }
          None => tree.foot_readers[i] = [me]
        }
        return Some(f)
      }
      None => ()
    }
    i = tree.nodes[i].parent
  }
  None
}

///|
/// A number this box's layout says of what it laid out (`name`: a composer's cap, how tall its words' first line sits),
/// for what holds it to read as it measures it in the same layout (Layout::reported): no signal, nothing told; said
/// again by each layout of it, what it does not say again gone.
pub fn Layout::report(self : Layout, name : String, v : Double) -> Unit {
  self.report_span(name, (v, v))
}

///|
/// A span this box's layout says of what it laid out (`name`: where the words a quote names lie in a row, their top and
/// their foot), as Layout::report says a number.
pub fn Layout::report_span(self : Layout, name : String, v : (Double, Double)) -> Unit {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let tree = self.owner.tree
  match tree.reports.get(self.owner.at) {
    Some(m) => m[name] = v
    None => {
      let m : Map[String, (Double, Double)] = {}
      m[name] = v
      tree.reports[self.owner.at] = m
    }
  }
}

///|
/// What `child` (a child of this box, measured in this layout: Layout::measure, fit) or the box of a layout of its own
/// it holds reported by `name` as it was laid out (Layout::report), the nearest such: read by what holds it alone. None
/// where it said none.
pub fn Layout::reported(self : Layout, child : View, name : String) -> Double? {
  self.reported_span(child, name).map(fn(s) { s.0 })
}

///|
/// The span `child` reported by `name` (Layout::report_span), as Layout::reported reads a number.
pub fn Layout::reported_span(self : Layout, child : View, name : String) -> (Double, Double)? {
  self.check(child)
  // (what it said in this layout, measured here first: never what a layout before said, read before it is measured)
  guard self.measured.contains(child.at) else {
    abort("Layout::reported: a child is read only after it is measured in the same layout (Layout::measure, fit)")
  }
  let tree = child.tree
  // (the nearest of it and what it holds that says it, from it down)
  let todo = [child.at]
  let mut i = 0
  while i < todo.length() {
    let at = todo[i]
    i = i + 1
    match tree.reports.get(at).bind(fn(m) { m.get(name) }) {
      Some(v) => return Some(v)
      None => ()
    }
    todo.append(tree.nodes[at].kids)
  }
  None
}

///|
/// One box's read of how big an anchor was laid out (Layout::anchor), under the box laying out both: as big as it read
/// it, None where it was laid out to nothing.
struct AnchorRead {
  reader : NodeId
  target : NodeId
  seen : (Double, Double)?
}

///|
fn Tree::anchor_unread(self : Tree, at : Int) -> Unit {
  match self.anchor_read.get(at) {
    Some(holder) => {
      self.anchor_read.remove(at)
      match self.anchor_readers.get(holder) {
        Some(rs) => {
          rs.retain(fn(r) { r.reader.at != at })
          if rs.is_empty() {
            self.anchor_readers.remove(holder)
          }
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
/// The child of `holder` that `at` is in (itself, or one that holds it), -1 where it is not in `holder`.
fn Tree::child_under(self : Tree, at : Int, holder : Int) -> Int {
  let mut c = at
  while c >= 0 && self.nodes[c].parent != holder {
    c = self.nodes[c].parent
  }
  c
}

///|
/// How big `target` is laid out, as its last layout left it: None where it is gone, laid out to nothing, or it or what
/// holds it, up to `holder`, was left out of its row (View::drops) or kept unplaced by the box laying it out
/// (Layout::place).
fn Tree::anchor_size(self : Tree, target : NodeId, holder : Int) -> (Double, Double)? {
  guard target.at < self.nodes.length() &&
    self.nodes[target.at].live &&
    self.nodes[target.at].gen == target.gen else {
    return None
  }
  let mut i = target.at
  while i >= 0 && i != holder {
    let m = self.nodes[i]
    if m.out || m.flex.line == -1 {
      return None
    }
    i = m.parent
  }
  let n = self.nodes[target.at].flex
  if n.width > 0.0 && n.height > 0.0 { Some((n.width, n.height)) } else { None }
}

///|
/// As `holder` measures its child `child`: each box in that child whose last layout read an anchor `holder` laid out
/// before it (Layout::anchor) laid out again where that anchor is laid out otherwise than it read it, in this layout
/// (marked by the framework inside the layout of `holder`, what it lays out: no fault).
fn Tree::anchors_due(self : Tree, holder : Int, child : Int) -> Unit {
  guard self.anchor_readers.get(holder) is Some(rs) else { return }
  let due = []
  for r in rs {
    let n = self.nodes[r.reader.at]
    if n.live && n.gen == r.reader.gen && self.child_under(r.reader.at, holder) == child &&
      self.anchor_size(r.target, holder) != r.seen {
      due.push(r.reader.at)
    }
  }
  for at in due {
    self.layout_marked_at(at)
  }
}

///|
/// How big `target` is laid out in this layout, for this box to lay out what it holds by (what flies over a list as big
/// as the row it lands on, its words as wide as that row's): a node of another branch that the box laying out both
/// (the nearest that holds both, a View::layout_box) has measured before the child this box is in, or whose layout is
/// done as this box is laid out (what is over others: flex lays it out once all else is), as CSS lays out what is
/// placed by an anchor after the anchor (anchor-size()). Read so, this box is laid out again in that
/// box's layout as the anchor is laid out otherwise (it measures this one's branch after the anchor's: nothing told,
/// no layout more, no frame late). None while the anchor is laid out to nothing (a row the list has not laid out):
/// laid out again as it comes to be. An anchor not laid out before this box in a layout holding both is a fault.
pub fn Layout::anchor(self : Layout, target : View) -> (Double, Double)? {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let tree = self.owner.tree
  guard physical_equal(target.tree, tree) else { abort("Layout::anchor: a node of another tree") }
  guard target.alive() else { return None }
  let me = self.owner.at
  // (the nearest that holds both: a box laying out what it holds (View::layout_box), its layout under way and the
  // anchor's child measured in it, or its layout done (what is placed over others, laid out once all else is: flex's
  // absolute boxes, after what they stand over))
  let mut holder = tree.nodes[me].parent
  while holder >= 0 && tree.child_under(target.at, holder) < 0 {
    holder = tree.nodes[holder].parent
  }
  guard holder >= 0 && tree.nodes[holder].flex.layout_children is Some(_) else {
    fault("layout_box node \{me}: anchor node \{target.at} held with it by no box laying out both (View::layout_box)")
    return None
  }
  let tk = tree.child_under(target.at, holder)
  let rk = tree.child_under(me, holder)
  let under_way = tree.layouts.iter().find_first(fn(l) { l.owner.at == holder })
  match under_way {
    Some(p) if !p.measured.contains(tk) || tk == rk => {
      fault(
        "layout_box node \{me}: anchor node \{target.at} not laid out before it by node \{holder}, which lays out both (its node \{tk}, then its node \{rk})",
      )
      return None
    }
    _ => ()
  }
  let seen = tree.anchor_size(target.id(), holder)
  match tree.anchor_read.get(me) {
    Some(h) if h != holder => {
      fault("layout_box node \{me}: anchors read under node \{h} and node \{holder} in one layout")
      return seen
    }
    _ => ()
  }
  tree.anchor_read[me] = holder
  match tree.anchor_readers.get(holder) {
    Some(rs) => rs.push({ reader: self.owner.id(), target: target.id(), seen })
    None => tree.anchor_readers[holder] = [{ reader: self.owner.id(), target: target.id(), seen }]
  }
  seen
}

///|
/// `f` done as this layout measures what it lays out (Layout::measure): what measuring reads (a font's theme, how
/// words are set) read as ever, laid out again as that changes (Tree::words_again), nothing else of the app's: words
/// laid out as wide as an anchor (Layout::anchor) by the same measure that lays out the anchor's.
pub fn[T] Layout::as_measured(self : Layout, f : () -> T) -> T {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
  let v = f()
  @signals.set_access_guard(guard_before) |> ignore
  v
}
