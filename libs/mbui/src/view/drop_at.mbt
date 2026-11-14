// What is let go on the window from outside (files, words: ui's drop.mbt) is the node's drawn where it is let go, and
// what holds it's, not what a press there would reach: a page's words take no press, and a drop on them is the page's
// all the same (a chat's messages; the files tab's row dragged over a chat on 大屏). Under what covers it (a modal layer,
// a page or panel drawn over it), the one drawn there decides; one under a modal layer it is not in takes none, nor
// lets it through; what takes no press of itself (said to take none, a button's icon, leaving: Tree::pressless_own_at)
// is passed over as a press passes over it. An old view hosted takes it only where nothing of the tree's is drawn over
// it there and it says the point is its own (View::hosted_takes), its own modal layers its own to say.

///|
/// Where something let go from outside lands in the window's tree.
#derive(Eq, Debug)
pub(all) enum DropOn {
  /// a node of the tree's: the topmost drawn there, or taking a press there (what holds it asked after it)
  OnNode(NodeId)
  /// the old view hosted in this node, where it says the point is its own and nothing of the tree's is over it
  OnOld(NodeId)
  /// what is drawn there is under a modal layer it is not in (the tree's; for a node of its own, an old frame's too):
  /// neither it, what holds it, nor what is under it takes it
  Shut(NodeId)
}

///|
/// What something let go at (x, y) in the window lands on (DropOn): the topmost node drawn there (by the order drawn,
/// where the scene composed draws it, seen, within what bounds its input: View::bounds_input), whether or not it takes
/// a press, or one taking a press there that draws nothing of its own (a field, a box round what it holds); an old
/// view's node only where it says the point is its own; what takes no press of itself passed over (Tree::pressless_own_at);
/// Shut where the one there is under a modal layer it is not in. None where nothing is.
pub fn Tree::drop_at(self : Tree, x : Double, y : Double) -> DropOn? {
  let at = self.logic_said()
  let found : Ref[DropOn?] = Ref(None)
  self.each_drawn_scaled(fn(c, cx, cy, a, s) {
    if a <= 0.01 || x < cx || y < cy || x >= cx + c.w * s || y >= cy + c.h * s {
      return
    }
    let (bx0, by0, bx1, by1) = self.input_bounds(c.id)
    if x < bx0 || y < by0 || x >= bx1 || y >= by1 {
      return
    }
    let n = self.nodes[c.id.at]
    // (a gesture answering a hold alone, or what takes no press of itself (said to take none, a button's icon, a page
    // going back; leaving; not laid out; in its bones): as were it not there, as for a press, what is under it found)
    if n.hold_only is Some(_) || self.pressless_own_at(c.id.at) {
      return
    }
    if n.hosted {
      // (an old view's own modal layers are its own to say, as it says the point is its own: only the tree's keep it)
      let (lx, ly) = ((x - cx) / s, (y - cy) / s)
      if !self.allows_at(c.id.at, held=false) {
        found.val = Some(Shut(c.id))
      } else if @signals.untracked(fn() { self.takes_here(n, lx, ly, c.w, c.h, at) }) {
        found.val = Some(OnOld(c.id))
      }
    } else if c.draws() || n.on_press is Some(_) || n.on_drag is Some(_) {
      found.val = Some(if self.allows_at(c.id.at) { OnNode(c.id) } else { Shut(c.id) })
    }
  })
  found.val
}
