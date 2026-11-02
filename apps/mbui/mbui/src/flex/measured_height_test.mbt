// How tall a tree laid out in less than it asks would be with no bound (measured_height): its content's height, what
// was laid out standing as it was, and laid out again as asked before (reused) as a new tree laid out so is.

///|
/// A column 400 wide: a head 30 high, a list 300 high giving way (down to none), a foot 30 high.
fn gives_tree() -> (@flex.Node, Array[@flex.Node]) {
  let root = @flex.Node::new()
  let head = @flex.Node::new()
  head.style.set_height(Pt(30.0))
  root.add(head)
  let list = @flex.Node::new()
  list.style.set_height(Pt(300.0))
  list.style.shrink = 1.0
  list.style.set_min_height(Pt(0.0))
  root.add(list)
  let foot = @flex.Node::new()
  foot.style.set_height(Pt(30.0))
  root.add(foot)
  (root, [root, head, list, foot])
}

///|
/// Where each of `nodes` is laid out.
fn rects_of(nodes : Array[@flex.Node]) -> Array[(Double, Double, Double, Double)] {
  nodes.map(fn(n) { (n.left, n.top, n.width, n.height) })
}

///|
test "measured_height: laid out 200 high, asked with no bound: 360, what was laid out as it was; laid out 200 high again, as a new tree is" {
  let (root, nodes) = gives_tree()
  @flex.compute(root, width=400.0, height=200.0, round=false, reuse=true)
  let laid = rects_of(nodes)
  let asked = @flex.measured_height(root, 400.0)
  let after = rects_of(nodes)
  @flex.compute(root, width=400.0, height=200.0, round=false, reuse=true)
  let again = rects_of(nodes)
  let (fresh, fresh_nodes) = gives_tree()
  @flex.compute(fresh, width=400.0, height=200.0, round=false, reuse=true)
  assert_eq((asked, after == laid, again, rects_of(fresh_nodes)), (
    360.0,
    true,
    [(0.0, 0.0, 400.0, 200.0), (0.0, 0.0, 400.0, 30.0), (0.0, 30.0, 400.0, 140.0), (0.0, 170.0, 400.0, 30.0)],
    [(0.0, 0.0, 400.0, 200.0), (0.0, 0.0, 400.0, 30.0), (0.0, 30.0, 400.0, 140.0), (0.0, 170.0, 400.0, 30.0)],
  ))
}
