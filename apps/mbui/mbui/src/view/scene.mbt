// What the tree tells the scene that draws it (src/ui/scene_layers.mbt, docs/retained.md rules 4 and 15): which nodes
// begin a layer of it, kept as one and made again only as something of it changes, and what changed of where things are
// drawn, at its cause.

///|
/// The nodes placed, faded, turned, cut or drawn off otherwise since this was last asked (a place property set: its
/// offset, opacity, scale, turn, fades, stretch; laid out elsewhere; what the root holds drawn over one another
/// otherwise, the root), each as told at its cause: what the scene draws again of each, all it holds with it. Taken:
/// asked again, only those since.
pub fn Tree::take_placed(self : Tree) -> Array[NodeId] {
  let out = self.placed_pending.copy()
  self.placed_pending.clear()
  out
}

///|
/// Whether node `id` begins a layer of the scene: what it and all it holds draw is kept as one, made again only where
/// something of it changed, the rest of the window left as it was. The window's root; what the root holds (its pages,
/// what is over them); what a `show`, `pick` or `each` made (a page, a sheet, a row); a list's rows; an old view; what
/// is drawn over all or over the scrim; and what moves as it is drawn (a place property bound: a spinner turning, a row
/// sliding, a fade), so that its motion makes nothing else again.
pub fn Tree::starts_layer(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  self.starts_layer_at(id.at)
}

///|
fn Tree::starts_layer_at(self : Tree, at : Int) -> Bool {
  if at == 0 {
    return true
  }
  let n = self.nodes[at]
  if n.slot {
    return false
  }
  if n.hosted || n.over_all || n.over_scrim || n.stack >= 0 || n.each_row {
    return true
  }
  let p = n.parent
  if p == 0 || (p > 0 && (self.nodes[p].slot || self.nodes[p].list_rows)) {
    return true
  }
  n.props.contains(Alpha) ||
  n.props.contains(Offset) ||
  n.props.contains(Shift) ||
  n.props.contains(Turn) ||
  n.props.contains(Scale) ||
  n.props.contains(Fades) ||
  n.props.contains(Stretch) ||
  n.props.contains(CutsSoftly) ||
  n.props.contains(DrawnOff) ||
  n.props.contains(GroundDrawn) ||
  n.props.contains(Glyphs)
}

///|
/// The layer node `id` is drawn in: itself where it begins one, else the nearest that holds it and does (none: let
/// go).
pub fn Tree::layer_of(self : Tree, id : NodeId) -> NodeId? {
  guard self.alive_id(id) else { return None }
  let mut at = id.at
  while at > 0 && !self.starts_layer_at(at) {
    at = self.nodes[at].parent
  }
  if at < 0 {
    return None
  }
  Some({ at, gen: self.nodes[at].gen })
}

///|
/// What holds node `id` (none: the root, or let go): slots and all.
pub fn Tree::holder_of(self : Tree, id : NodeId) -> NodeId? {
  guard self.alive_id(id) else { return None }
  let p = self.nodes[id.at].parent
  if p < 0 {
    return None
  }
  Some({ at: p, gen: self.nodes[p].gen })
}

///|
/// Whether a change of node `id`'s own drawing changes what it holds is drawn (where they are cut, faded, stretched,
/// their glyphs' looks): what it holds is drawn again with it.
pub fn Tree::draws_round(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let l = self.nodes[id.at].look
  l.clips || l.glyphs_at is Some(_) || l.stretch != 0.0 || l.cut_soft || l.fades != (0.0, 0.0, 0.0, 0.0)
}

///|
/// The root's id: the window's.
pub fn Tree::root_id(self : Tree) -> NodeId {
  { at: 0, gen: if self.nodes.length() > 0 { self.nodes[0].gen } else { 0 } }
}

///|
/// Whether node `at` (by its place: one alive there now) holds `inner` (or is it).
pub fn Tree::holds_at(self : Tree, at : Int, inner : NodeId) -> Bool {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { return false }
  self.holds({ at, gen: self.nodes[at].gen }, inner)
}

///|
/// The scene gone through as it is drawn (Tree::walk_drawn): `f` given each node that draws, its place among those
/// gone through (from 0) and that of the innermost that holds it and draws (-1: none), where it is drawn, how opaque,
/// how big and where were nothing grown or shrunk; `enter` whether what node `at` holds is gone into (what the scene
/// keeps copied skipped whole). `from`, `held`: one layer gone through again alone, what holds it composed as `held`
/// says.
pub fn Tree::walk_scene(
  self : Tree,
  f : (Int, Int, Content, Double, Double, Double, Double, Double, Double) -> Unit,
  enter~ : (Int, Double, Double, Double, Bool) -> Bool,
  from? : Int = 0,
  held? : (Double, Double, Double, Double, Double, Double) = (0.0, 0.0, 1.0, 1.0, 0.0, 0.0),
) -> Unit {
  self.walk_drawn(f, drawing=true, enter~, from~, held~)
}

///|
/// Whether node `id` fades what it holds towards its edges by how far that reaches past them (View::cuts_softly): what
/// it holds moved, it is drawn again with it.
pub fn Tree::cuts_softly(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  self.nodes[id.at].look.cut_soft
}

///|
/// Where node `id` is drawn as the scene goes through it (Tree::walk_scene's): where, how opaque, how big, where were
/// nothing grown or shrunk nor drawn off, and how big its content is; None where it draws nothing (let go, left out,
/// held by what is). Worked out up the nodes that hold it, none else gone through.
pub fn Tree::placed_of(self : Tree, id : NodeId) -> (Double, Double, Double, Double, Double, Double, Double, Double)? {
  guard self.alive_id(id) && !self.out_at(id.at) else { return None }
  guard self.nodes[id.at].content is Some(c) else { return None }
  let chain = []
  let mut i = id.at
  while i >= 0 {
    if !self.nodes[i].slot {
      chain.push(i)
    }
    i = self.nodes[i].parent
  }
  let g = self.pixel_grid
  let mut x = 0.0
  let mut y = 0.0
  let mut a = 1.0
  let mut s = 1.0
  let mut ux = 0.0
  let mut uy = 0.0
  for k = chain.length() - 1; k >= 0; k = k - 1 {
    let n = self.nodes[chain[k]]
    let (ox, oy) = n.look.drawn_off
    let (ox, oy) = if g > 0.0 && (ox != 0.0 || oy != 0.0) { ((ox * g).round() / g, (oy * g).round() / g) } else { (ox, oy) }
    x = x + s * (n.lx + ox + (1.0 - n.ls) * n.lpx)
    y = y + s * (n.ly + oy + (1.0 - n.ls) * n.lpy)
    a = a * n.la
    s = s * n.ls
    ux = ux + n.lx
    uy = uy + n.ly
  }
  Some((x, y, a, s, ux, uy, c.w, c.h))
}

///|
/// Whether anything was told the scene since it last took what changed (Tree::take_changed, take_placed,
/// take_removed): a node made again, placed otherwise or let go, not yet taken.
pub fn Tree::scene_told_since(self : Tree) -> Bool {
  !self.pending.is_empty() || !self.placed_pending.is_empty() || !self.removed.is_empty()
}
