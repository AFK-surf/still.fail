// What a structure makes or lets go along a row (View::show, pick, each said `along_row=true`): its way across, as
// down a column it makes its way down (View::comes), the same way on its width (flex's Style::come_across). Only where
// it is said, for now (the coordinator of the migration, 2026-11-11): the rows' structures said otherwise are looked at
// one by one before it is every row's. What makes its way is cut to itself as it goes, its own words too
// (Content::clips_self).

///|
/// Slot `slot` of a structure (`kind`, asked for at `loc`) said `along_row`: marked so, a fault where `at_once` is said
/// with it, and, once the change making it is told whole (the direction of what lays it out said by then), where what
/// lays it out is no row.
fn View::along_row_said(
  slot : View,
  along_row : Bool,
  at_once : Bool,
  kind : String,
  loc : SourceLoc,
) -> Unit {
  guard along_row && slot.live() is Some(n) else { return }
  if at_once {
    slot.fault("View::\{kind} at \{loc}: along_row=true and at_once=true said together (along a row it makes its way; at once it makes none)")
    return
  }
  n.along_row = true
  @signals.after_flush(fn() {
    guard slot.live() is Some(_) else { return }
    let p = slot.tree.column_of(slot.at)
    guard p >= 0 else { return }
    let st = slot.tree.nodes[p].flex.style
    if st.direction != @flex.FlexDirection::Row {
      slot.fault("View::\{kind} at \{loc}: along_row=true where what lays it out is no row")
    }
  })
}

///|
/// Whether node `at` makes its way along the row laying it out (Style's come_across): its structure said `along_row`
/// (its slot's), it is laid out in its turn (not over what holds it, not grown), the row does not wrap (a way there
/// would put what follows it on another line at a width, no way of its own), and something else of the row takes room
/// (alone in its row, its way is the row's height in its column, not its width: at once, as were it said nothing).
fn Tree::along_row_at(self : Tree, at : Int) -> Bool {
  let n = self.nodes[at]
  let s = n.parent
  guard s >= 0 && self.nodes[s].slot && self.nodes[s].along_row else { return false }
  if n.flex.style.position == @flex.PositionType::Absolute || n.flex.style.grow > 0.0 {
    return false
  }
  let p = self.column_of(at)
  guard p >= 0 else { return false }
  let ps = self.nodes[p].flex.style
  guard ps.direction == @flex.FlexDirection::Row && ps.wrap == @flex.FlexWrap::NoWrap else { return false }
  // (the row's own item holding it: the slot holding it there, or it)
  let mut item = at
  while item >= 0 && self.nodes[item].parent != p {
    item = self.nodes[item].parent
  }
  for k in self.nodes[p].kids {
    if k != item && self.takes_room(k) {
      return true
    }
  }
  false
}

///|
/// Whether node `at` makes its way as it comes or goes: down a column (Tree::in_column), or along a row where its
/// structure said so (Tree::along_row_at).
fn Tree::makes_way(self : Tree, at : Int) -> Bool {
  self.in_column(at) || self.along_row_at(at)
}

///|
/// How long node `at` is along what lays it out at moment `at_ms`: on its way in or out, where that way has it then
/// (flex's come_state), whether a frame has laid it out since the way was said or not; else as it was laid out last,
/// its width along a row it makes its way along, else its height.
fn Tree::along_now(self : Tree, at : Int, at_ms : Double) -> Double {
  let n = self.nodes[at]
  match (n.coming, @flex.come_state(n.flex.style, at_ms)) {
    (true, Some((h, _))) => h
    _ => if self.along_row_at(at) { n.flex.width } else { n.flex.height }
  }
}
