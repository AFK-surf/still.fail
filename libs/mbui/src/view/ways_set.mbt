// What ways the tree set out as it was told, each where what goes was made (src/view/source.mbt's places): for a Tester
// to read what came or went with a way in a stretch it walks (the coordinator of the migration, 2026-11-13: a way is
// set out only for a cause, a person's act, the core telling something new, a moment said; never for an answer first
// come, nor a part waking). Kept only where the tree keeps sources; elsewhere nothing is kept.

///|
/// A way set out: what it is (`comes`, `closes` down its column or along its row: View::comes; `fades`: a structure's
/// leaving faded over its time, View::leave), its cause's moment, where what goes was made and where the innermost part it is in was asked
/// for (Tree::source_of).
#derive(Eq, Debug)
pub(all) struct WaySet {
  kind : String
  at : Double
  made : String
  part : String
}

///|
/// Node `at` set out on a way of `kind` at `t`: kept where the tree keeps sources.
fn Tree::way_set(self : Tree, at : Int, kind : String, t : Double) -> Unit {
  guard at >= 0 && at < self.nodes.length() && self.nodes[at].source is Some(_) else { return }
  let (made, part) = self.source_of({ at, gen: self.nodes[at].gen })
  // (none read for long: the oldest half let go of, so what is kept stays small)
  if self.ways_set.length() >= 4096 {
    let keep = self.ways_set[2048:].to_owned()
    self.ways_set.clear()
    self.ways_set.push_iter(keep.iter())
  }
  self.ways_set.push({ kind, at: t, made, part })
}

///|
/// The ways set out since this was last asked (Tree::way_set), in the order they set out; none kept after.
pub fn Tree::ways_set_out(self : Tree) -> Array[WaySet] {
  let out = self.ways_set.copy()
  self.ways_set.clear()
  out
}
