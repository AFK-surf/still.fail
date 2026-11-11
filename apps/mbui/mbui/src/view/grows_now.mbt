// How tall a node is laid out at a change's moment, and how fast that height goes then (View::grows_now): what sets
// off from where something stands as it changes sets off as fast as it goes there, not from rest (the coordinator of
// the migration, 2026-11-11: a sheet closed while what it holds grows or shrinks sinks on from as fast as its top went).
// Worked out of the layout itself, no rule of its own beside it: all of it laid out at that moment and a little after,
// what comes or goes there by its way (flex's come_*, a function of the time) and what is bound to a way following the
// clock (View::drawn_while) worked out at each, so whatever the layout makes of them (a column's sum, a row's tallest,
// what a most holds, words wrapped, a room's fill) is what it says. Then laid out again as the frame had it.

///|
/// How far on the second layout is, in ms: a Move's speed, its turn's too, within a thousandth of a point a ms.
let grows_step : Double = 0.01

///|
/// How tall it is laid out as of the logic's moment, and how fast that height goes then (points a ms): all of it laid
/// out at that moment and grows_step after, what comes or goes in it and what follows the clock as it is then; at once
/// (0 a ms, nothing laid out more) where nothing follows the clock. Read where a
/// change is taken (a handler, what reacts to a change, what is due once a change is told whole), as
/// View::laid_window_now is; a binding reading it fails its test (said where its node was made). (0, 0) where it is let
/// go.
pub fn View::grows_now(self : View) -> (Double, Double) {
  let tree = self.tree
  tree.grows_read_in_binding()
  guard self.live() is Some(n) else { return (0.0, 0.0) }
  // (nothing following the clock (no way under way says how tall a node is, no binding follows a way: each reads the
  // clock while it goes, View::comes's, View::drawn_while): as tall as it is laid out, going nowhere; laid out again
  // only where a change told since asks it, nothing more for it)
  let still = !tree.clock.watched()
  if still && !tree.layout_due {
    return (n.flex.height, 0.0)
  }
  tree.measured_now()
  guard tree.last_w > 0.0 && !tree.measuring && !still else { return (n.flex.height, 0.0) }
  let at = tree.logic_said()
  let shown = tree.clock.untracked()
  // (what comes or goes in it, as it was drawn: its way's moment set to each, and back; what is not in it laid out as
  // it stands)
  let coming : Array[(Int, Double)] = []
  let walk : Ref[(Int) -> Unit] = Ref(fn(_) {  })
  walk.val = fn(k : Int) {
    let m = tree.nodes[k]
    guard m.live else { return }
    let st = m.flex.style
    if m.coming && st.come_now == st.come_now {
      coming.push((k, st.come_now))
    }
    for c in m.kids {
      (walk.val)(c)
    }
  }
  (walk.val)(self.at)
  let laid_at = fn(t : Double, back : Bool) {
    tree.bound_at(t)
    for c in coming {
      let (k, was) = c
      let m = tree.nodes[k]
      m.flex.style.come_now = if back { was } else { t }
      let mut j = k
      while j >= 0 {
        tree.nodes[j].flex.dirty = true
        j = tree.nodes[j].parent
      }
    }
    tree.laids = tree.laids + 1
    @flex.compute(tree.nodes[0].flex, width=tree.last_w, height=tree.last_h, round=false, reuse=true)
    n.flex.height
  }
  let first = @flex.computes() + 1
  let was_standing = tree.standing
  tree.standing = true
  let (h0, h1) = @signals.untracked(fn() {
    let h0 = laid_at(at, false)
    let h1 = laid_at(at + grows_step, false)
    // (as the frame had it: what is placed next is that)
    laid_at(shown, true) |> ignore
    (h0, h1)
  })
  tree.standing = was_standing
  tree.measured_gen = @flex.computes()
  if tree.walk_from < 0 || first < tree.walk_from {
    tree.walk_from = first
  }
  (h0, (h1 - h0) / grows_step)
}

///|
/// View::grows_now read in a binding: what it says is of a change's moment, no property of a node's to follow (as a
/// way's going is read in a binding: View::goes_now). A fault, failing the test that runs it, said where the node was
/// made; nothing where the tree keeps no sources (a device's).
fn Tree::grows_read_in_binding(self : Tree) -> Unit {
  let at = self.binding_reading
  guard at >= 0 && at < self.nodes.length() else { return }
  let n = self.nodes[at]
  guard n.source is Some(_) else { return }
  let made = match self.sources_of({ at, gen: n.gen }).get(0) {
    Some(s) => s.made
    None => "?"
  }
  let said = "GROWSNOW grows_now read in a binding: \{made}"
  @halt.saying(said)
}
