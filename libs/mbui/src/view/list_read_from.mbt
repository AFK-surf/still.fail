// Where what is read in a page's list's block starts (View::read_from): the node its page marks in it, a message's words
// under the room and the head line over them. The list (View::scrolls_window) holds what shows by the first of its keys
// whose start so marked is at or under what covers its top (Scroll::top_covered) and over its pinned foot's top, by
// where that start is: the room over it (a key over it grown or closing on a way, keys come before it, the gap over its
// own words) gives and takes its room upward, its own growth goes down from its start. Its place in its block is read
// in the fill that lays the list out, at that fill's width and as each way has it then (Tree::start_in), for the block
// held alone (and its stand-ins), never for all that show. A list none of whose blocks marks one is held by the block
// the top of what shows lies in, by its top, as ever (the owner's principle: what the reader has before their eyes does
// not move, in every frame; the coordinator of the migration, 2026-11-14).

///|
/// This node is where what is read in the block of a page's list it is made in starts: that list holds what shows by
/// the first block whose start so marked is in sight under what covers its top, by where the start is
/// (View::scrolls_window). In anything else it says nothing; let go with the node.
pub fn View::read_from(self : View) -> View {
  match self.scroll_holding() {
    Some(s) => (s.read_from_said)(self)
    None => ()
  }
  self
}

///|
/// How far under the top of block `block` node `mark`, in it, starts as the block is laid out `w` across: what lies
/// over it down each column holding it (each measured at that width, Tree::height_in; one on its way as tall as its way
/// has it at the moment read, as the list's over_h reads it), their margins and the columns' gaps, and the padding,
/// borders and margins on the way down from the block to it. A row holding it lays it at its top. `laying`: read as the
/// list is laid out (a way at the moment that layout lays it out), else at `t`. None where `mark` is not in it.
fn Tree::start_in(self : Tree, mark : Int, block : Int, w : Double, laying : Bool, t : Double) -> Double? {
  let pt = fn(k : Int, x : Double) { if k == @flex.LEN_PT { x } else { 0.0 } }
  let tall = fn(k : Int) {
    let st = self.nodes[k].flex.style
    if st.come_at == st.come_at && st.come_to == st.come_to {
      let whole = if st.come_goal == st.come_goal && st.come_to > 0.0 {
        st.come_goal / st.come_to
      } else {
        self.height_in(k, block, w)
      }
      let at = if laying && st.come_now == st.come_now { st.come_now } else { t }
      @flex.come_tall_at(st, whole, at)
    } else {
      self.height_in(k, block, w)
    }
  }
  guard mark >= 0 && mark < self.nodes.length() && self.nodes[mark].live else { return None }
  let mut off = 0.0
  let mut i = mark
  while i != block {
    // (its own margin over it, each on the way up as the mark's)
    if !self.nodes[i].slot {
      let ms = self.nodes[i].flex.style
      off = off + pt(ms.margin_top_kind(), ms.margin_top_value())
    }
    let mut p = self.nodes[i].parent
    while p >= 0 && p != block && self.nodes[p].slot {
      p = self.nodes[p].parent
    }
    guard p >= 0 else { return None }
    let st = self.nodes[p].flex.style
    if !self.nodes[p].slot {
      off = off +
        pt(st.padding_top_kind(), st.padding_top_value()) +
        pt(st.border_top_kind(), st.border_top_value())
    }
    if st.direction is Column {
      let gap = pt(st.gap_row_kind(), st.gap_row_value())
      for k in self.column_items(p) {
        if k == i {
          break
        }
        let ks = self.nodes[k].flex.style
        guard self.nodes[k].live &&
          ks.display != @flex.Display::DisplayNone &&
          !(ks.position is @flex.PositionType::Absolute) else {
          continue
        }
        off = off +
          pt(ks.margin_top_kind(), ks.margin_top_value()) +
          tall(k) +
          pt(ks.margin_bottom_kind(), ks.margin_bottom_value()) +
          gap
      }
    }
    i = p
  }
  Some(off)
}

///|
/// How far under the top of block `block` node `mark`, in it, started as the tree was last laid out: each holder's place
/// in what holds it as laid out then (as Tree::laid_origin goes up), from `mark` to the block. None where `mark` is not
/// in it or was not laid out in it yet.
fn Tree::start_laid(self : Tree, mark : Int, block : Int) -> Double? {
  guard mark >= 0 && mark < self.nodes.length() && self.nodes[mark].live else { return None }
  let mut y = 0.0
  let mut i = mark
  while i != block {
    guard i >= 0 else { return None }
    let n = self.nodes[i]
    if !n.slot {
      y = y + n.flex.top
    }
    i = n.parent
  }
  Some(y)
}
