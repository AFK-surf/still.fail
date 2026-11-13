// What a structure said `at_once` (View::show, View::pick) made or let go by a change, not as it was first made: a
// node there in that frame whole, or gone from it whole, with no way, so what holds it comes out another size in that
// frame by as much. Kept by the structure's slot, the last of each (one note a slot, let go with it), for what reads a
// frame against the one before (a Tester's judges of how what moves goes): what committed at once, when, and by how
// much. Kept only where the tree keeps sources (a Tester's), as the ways it sets out are (ways_set.mbt): nothing on a
// device.

///|
/// One commit of a structure said `at_once`: which of the tree's it is (counted from 1: Tree::at_once_said_count), its
/// moment (the cause it was committed by), the height of what it let go as it went (0 where it let none go), and the
/// node it made in its place (none: it made none).
pub(all) struct AtOnceSaid {
  count : Int
  moment : Double
  gave : Double
  made : NodeId?
}

///|
/// Noted by the slot of a structure said `at_once`, as it commits: what it let go was `gave` tall, and it made `made`
/// (the slot itself where it made none).
fn View::at_once_said(self : View, gave : Double, made : View) -> Unit {
  let tree = self.tree
  let at = self.at
  guard tree.nodes[at].source is Some(_) else { return }
  if !tree.at_once_said.contains(at) {
    self.owns(fn() { tree.at_once_said.remove(at) }) |> ignore
  }
  tree.at_once_count += 1
  tree.at_once_said[at] = {
    count: tree.at_once_count,
    moment: tree.cause_now(),
    gave,
    made: if made.at == at { None } else { Some(made.id()) },
  }
}

///|
/// How many structures said `at_once` committed so far in the tree: what reads a frame against the one before keeps it
/// as it reads, and asks next for those after it (Tree::at_once_said_since).
pub fn Tree::at_once_said_count(self : Tree) -> Int {
  self.at_once_count
}

///|
/// The commits of structures said `at_once` after the `after`th (Tree::at_once_said_count), each as its slot (a node of
/// the tree), its moment, and how much taller what it holds came out by it down its column (wider, along a row it makes
/// its way along): what it made as it is laid out now, less what it let go as it was then. A slot's last alone.
pub fn Tree::at_once_said_since(self : Tree, after : Int) -> Array[(Int, Double, Double)] {
  let out = []
  self.at_once_said.each(fn(at, n) {
    guard n.count > after && at < self.nodes.length() && self.nodes[at].live else { return }
    let took = match n.made {
      Some(id) if id.at < self.nodes.length() &&
        self.nodes[id.at].live &&
        self.nodes[id.at].gen == id.gen &&
        self.makes_way(id.at) =>
        self.along_now(id.at, n.moment)
      _ => 0.0
    }
    out.push((at, n.moment, took - n.gave))
  })
  out
}
