// A height change declared makes its way (View::resizes): said on a node in a handler, its coming out another height
// in the change that handler commits is for that change's cause. From as tall as it was laid out last (or as tall as
// its way had it then, on a way already: its place and speed going on) to as tall as it comes out, that change's
// layout's to say, as what comes is (View::comes, from as tall as one in its place was, to all of it): one member of
// its column's one way (flex's ComeGroup, Tree::come_group_join), in a page's list's foot the list's; alone, as its
// spec says, else a Move by how far. Come out the same height, nothing, nothing kept: the declaration is of that one
// commit, dropped by the change's layout whatever came of it. Not declared, a height change is at once, as ever. What
// it holds is laid out at the size it comes to from the start, shown through it as it goes; what draws a ground by how
// tall it shows is given that where it is drawn (View::shown_by).

///|
/// In the change the handler it is said in commits, this node coming out another height is for that change's cause:
/// its way from as tall as it was to as tall as it comes out (`spec`: how long, ms, and on what curve, the share of the
/// way gone for the share of its time gone; none, a Move by how far; in a group with others, the group's). Nothing
/// where it comes out the same height, nor in a change that lays nothing of it out: nothing kept after it. `foot`:
/// what it holds keeps to its foot all the way, its bottom the node's bottom, cut at the node's top (a composer that
/// grows from its foot, the messages over it going up with it as one: the owner's 2026-10-30, 「以底部为 origin」);
/// else to its top, cut at its foot, as ever.
pub fn View::resizes(self : View, spec? : (Double, (Double) -> Double), foot? : Bool = false) -> View {
  guard self.live() is Some(n) else { return self }
  let tree = self.tree
  let st = n.flex.style
  // (as tall as it was laid out last: where a way it is on has it now, View::comes takes that)
  let from = n.flex.height
  // (its way and its foot said with it: told outside a change, what comes is measured and its end fixed in
  // View::comes itself)
  guard self.comes(self, from, 1.0, spec?, foot~) else { return self }
  let at = st.come_at
  // (once the change is told whole and laid out (View::comes' wait, which measures it, and its column's group then):
  // come out as tall as it was, from rest, nothing of it goes)
  @signals.after_flush(fn() {
    @signals.after_flush(fn() {
      guard self.live() is Some(m) && m.coming && st.come_at == at else { return }
      if st.come_v == 0.0 && st.come_goal == st.come_goal && (st.come_goal - st.come_from).abs() < 1.0e-9 {
        (m.come_off)()
        come_done(tree, self, m)
      }
    })
  })
  self
}

///|
/// What draws this node's ground given, where it is drawn, how tall node `of` (this one or one holding it) shows then,
/// on its way or at rest (its height as it is laid out at that frame): `f` given that height, its ground as it draws it
/// (GroundShape, View::ground_drawn's), worked out again at each frame `of` is laid out on its way, nothing of it read
/// by a build. Till this node goes.
pub fn View::shown_by(self : View, of : View, f : (Double) -> GroundShape) -> View {
  guard self.live() is Some(_) && of.live() is Some(_) else { return self }
  let tree = self.tree
  let me = self.at
  let them = of.at
  tree.shown_bys[me] = (of.id(), f)
  let fs = match tree.shown_followers.get(them) {
    Some(fs) => fs
    None => {
      let fs = []
      tree.shown_followers[them] = fs
      fs
    }
  }
  fs.push(me)
  self.owns(fn() {
    tree.shown_bys.remove(me)
    match tree.shown_followers.get(them) {
      Some(fs) => {
        let left = fs.filter(fn(f) { f != me })
        if left.is_empty() {
          tree.shown_followers.remove(them)
        } else {
          fs.clear()
          fs.append(left)
        }
      }
      None => ()
    }
  })
  |> ignore
  tree.place_marked_at(me)
  self
}

///|
/// Whether what node `id` holds keeps to its foot now, its height on a way said so (View::resizes `foot`): an old view
/// hosted in it is placed from its foot, cut at its top, as a node's children are (flex's come_keep_foot).
pub fn Tree::holds_to_foot(self : Tree, id : NodeId) -> Bool {
  guard self.alive_id(id) else { return false }
  let n = self.nodes[id.at]
  n.coming && n.flex.style.come_foot
}
