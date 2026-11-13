// A Tester's look at the corners worked out once laid out (Ctx::corners_after_layout) by what is kept for them: the
// window's tree's walk to what holds an old view (Tree::laid_held_hosted), the nodes it is put among the frame's in
// (tree_laid_spare). The pass done so, then again with all of it worked out
// anew (Ctx::with_tree_nodes `fresh`), from the same frame, and what each wrote compared: what is kept failing the
// test where it is not what would be worked out now. Nothing of the app's frames asks it: the Tester does it in their
// place (corners_look). It changes nothing drawn or kept: the frame goes on with what the two came to, the same.

///|
/// What the corners' pass writes of the frame's own nodes (the first `count`), taken: which node each is, its corners,
/// whether they were worked out, where it is (an old view's nodes moved to where they are laid out and back:
/// Ctx::with_old_laid), what holds it (an old view's box held by the tree's node as it runs); and what is said of the
/// corners that could not be worked out (Ctx's inner_faults).
priv struct CornersTaken {
  count : Int
  nodes : Array[Node]
  radius : Array[Double]
  radii : Array[FixedArray[Double]?]
  worked : Array[Bool]
  x : Array[Double]
  y : Array[Double]
  parent : Array[Int]
  faults : Array[String]
}

///|
/// What the corners' pass writes of the frame's nodes, as they are now (CornersTaken).
fn Ctx::corners_taken(self : Ctx) -> CornersTaken {
  let count = self.count
  let taken : CornersTaken = {
    count,
    nodes: [],
    radius: [],
    radii: [],
    worked: [],
    x: [],
    y: [],
    parent: [],
    faults: self.inner_faults.copy(),
  }
  for i in 0..<count {
    let n = self.nodes[i]
    taken.nodes.push(n)
    taken.radius.push(n.radius)
    taken.radii.push(n.radii.map(fn(r) { r.copy() }))
    taken.worked.push(n.corners_worked)
    taken.x.push(n.x)
    taken.y.push(n.y)
    taken.parent.push(n.parent)
  }
  taken
}

///|
/// The frame's nodes put back as `taken` had them (CornersTaken), for the pass to be done again from there.
fn Ctx::corners_put_back(self : Ctx, taken : CornersTaken) -> Unit {
  for i in 0..<taken.count {
    let n = taken.nodes[i]
    self.nodes[i] = n
    n.radius = taken.radius[i]
    n.radii = taken.radii[i].map(fn(r) { r.copy() })
    n.corners_worked = taken.worked[i]
    n.x = taken.x[i]
    n.y = taken.y[i]
    n.parent = taken.parent[i]
  }
  self.inner_faults.clear()
  self.inner_faults.append(taken.faults)
}

///|
/// The corners worked out once laid out, where a Tester looks (corners_look): as a device works them out, with what is
/// kept (Ctx::corners_worked_out), then from the same frame anew, nothing kept (`fresh`), and the two compared: any
/// difference stops the test, saying the node, what of it and both.
fn corners_looked(c : Ctx) -> Unit {
  let before = c.corners_taken()
  c.corners_worked_out(fresh=false)
  let kept = c.corners_taken()
  c.corners_put_back(before)
  c.corners_worked_out(fresh=true)
  let anew = c.corners_taken()
  let fail = fn(what : String) -> Unit {
    let said = "corners kept not as worked out anew (tester_corners.mbt: Tree::laid_held_hosted, tree_laid_spare), the Tester made at \{looks_made_at.val}: " +
      what
    @halt.saying(said)
  }
  if kept.count != anew.count {
    fail("the frame's nodes: \{kept.count} kept, \{anew.count} anew")
  }
  for i in 0..<kept.count {
    let differs = fn(field : String, k : String, a : String) -> Unit {
      fail("\{c.named(i)}: \{field} \{k} kept, \{a} anew")
    }
    if !physical_equal(kept.nodes[i], anew.nodes[i]) {
      differs("node", "one", "another")
    }
    if kept.radius[i] != anew.radius[i] {
      differs("radius", kept.radius[i].to_string(), anew.radius[i].to_string())
    }
    let radii_said = fn(r : FixedArray[Double]?) -> String {
      match r {
        Some(r) => "[\{r[0]}, \{r[1]}, \{r[2]}, \{r[3]}]"
        None => "none"
      }
    }
    let same_radii = match (kept.radii[i], anew.radii[i]) {
      (None, None) => true
      (Some(a), Some(b)) => a.length() == b.length() && a.iter().zip(b.iter()).all(fn(p) { p.0 == p.1 })
      _ => false
    }
    if !same_radii {
      differs("radii", radii_said(kept.radii[i]), radii_said(anew.radii[i]))
    }
    if kept.worked[i] != anew.worked[i] {
      differs("corners_worked", kept.worked[i].to_string(), anew.worked[i].to_string())
    }
    if kept.x[i] != anew.x[i] || kept.y[i] != anew.y[i] {
      differs("place", "(\{kept.x[i]}, \{kept.y[i]})", "(\{anew.x[i]}, \{anew.y[i]})")
    }
    if kept.parent[i] != anew.parent[i] {
      differs("parent", kept.parent[i].to_string(), anew.parent[i].to_string())
    }
  }
  if kept.faults != anew.faults {
    fail("what is said of corners not worked out (inner_faults): \{Repr(kept.faults)} kept, \{Repr(anew.faults)} anew")
  }
}

///|
/// Whether each frame's corners worked out with what is kept are worked out anew as well and the two compared
/// (tester_corners.mbt; on in every Tester unless MBUI_CORNERS_LOOK=0): off for a run measured as a host runs it
/// (mbui/src/film's bench and its pictures).
pub fn Tester::corners_look(self : Tester, on : Bool) -> Unit {
  ignore(self)
  corners_look.val = if on { Some(corners_looked) } else { None }
}
