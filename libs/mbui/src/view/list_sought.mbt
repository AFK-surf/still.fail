// What a go-to brings in a page's list's block (View::sought): the piece of a node in it that is what was meant (a
// search's match, a quoted passage), marked by the node as it is made. Asked to bring the block with it
// (ListPlace::bring's `sought`), the list puts the block's top where it is asked and, where that piece lies low in what
// shows (its middle past 80% of the room between what covers its top and its pinned foot), the piece's middle at the
// middle of that room instead, in the same fill, so the list goes there once from the cause and the place within a
// long block is before the eyes, not only its top (an old view's list scrolled there a frame later: sfpages'
// passage_centre and found_centre; the owner's sixth principle of a chat: going to something brings it before the
// eyes and shows what was meant). Where the piece lies is read as the fill lays the list out, at its width and as
// each way has it then (Tree::start_in for the node's top, Tree::width_in for how wide it is given), before the
// block is laid out in the window.

///|
/// This node holds what a go-to to the block of a page's list it is made in brings (ListPlace::bring's `sought`):
/// `piece`, read as the list is laid out, its part of it now as View::beside's `piece` is (in its own terms, laid out as
/// wide and tall as it is given), None where it holds nothing of it now. The first of a block's that has one is what
/// is brought. In anything else it says nothing; let go with the node.
pub fn View::sought(self : View, piece : () -> ((Double, Double) -> (Double, Double, Double, Double)?)?) -> View {
  match self.scroll_holding() {
    Some(s) => (s.sought_said)(self, piece)
    None => ()
  }
  self
}

///|
/// How wide node `at`, in block `top`, is given to be as the block is laid out `w` across: down from the block, each
/// in a column as wide as what holds it leaves it (its margins aside; its own width or most said in points bounding
/// it), each in a row as wide as it is where it does not grow, else what the row leaves it beside the others as wide as
/// they are, its gaps aside. A guess of the layout to come, as Tree::height_in's is, for where a piece of words lies.
fn Tree::width_in(self : Tree, at : Int, top : Int, w : Double) -> Double {
  let pt = fn(k : Int, x : Double) { if k == @flex.LEN_PT { x } else { 0.0 } }
  let chain : Array[Int] = []
  let mut i = at
  while i >= 0 && i != top {
    if !self.nodes[i].slot {
      chain.push(i)
    }
    i = self.nodes[i].parent
  }
  guard i == top else { return w }
  let side = fn(k : Int) {
    let s = self.nodes[k].flex.style
    pt(s.margin_left_kind(), s.margin_left_value()) + pt(s.margin_right_kind(), s.margin_right_value())
  }
  let inside = fn(k : Int) {
    let s = self.nodes[k].flex.style
    pt(s.padding_left_kind(), s.padding_left_value()) +
    pt(s.padding_right_kind(), s.padding_right_value()) +
    pt(s.border_left_kind(), s.border_left_value()) +
    pt(s.border_right_kind(), s.border_right_value())
  }
  // (what the block's content is given: the block as Tree::height_in has it)
  let mut room = w
  let mut holder = top
  for j = chain.length() - 1; j >= 0; j = j - 1 {
    let k = chain[j]
    let ps = self.nodes[holder].flex.style
    let ks = self.nodes[k].flex.style
    let mut kw = if ps.direction is (Row | RowReverse) {
      if ks.grow > 0.0 {
        let items = self.column_items(holder).filter(fn(o) {
          let os = self.nodes[o].flex.style
          self.nodes[o].live &&
          os.display != @flex.Display::DisplayNone &&
          !(os.position is @flex.PositionType::Absolute)
        })
        let mut others = 0.0
        for o in items {
          if o != k {
            others = others + @flex.measured_width(self.nodes[o].flex, 0.0 / 0.0) + side(o)
          }
        }
        let gaps = pt(ps.gap_col_kind(), ps.gap_col_value()) * (items.length() - 1).to_double()
        room - others - gaps - side(k)
      } else {
        dmin(@flex.measured_width(self.nodes[k].flex, 0.0 / 0.0), room - side(k))
      }
    } else {
      room - side(k)
    }
    if ks.width_kind() == @flex.LEN_PT {
      kw = ks.width_value()
    }
    if ks.max_width_kind() == @flex.LEN_PT {
      kw = dmin(kw, ks.max_width_value())
    }
    kw = dmax(0.0, kw)
    if j == 0 {
      return kw
    }
    room = dmax(0.0, kw - inside(k))
    holder = k
  }
  room
}

///|
/// Where what node `mark` holds of what a go-to brings (`piece`, View::sought's) lies under the top of block `block`
/// as it is laid out `w` across, its top and its foot: the node's start in it (Tree::start_in, `laying` and `t` as
/// it takes them) and the piece's place in the node as wide as it is given there (Tree::width_in) and as tall as it
/// comes to. None where the node is not in it or holds none of it.
fn Tree::sought_in(
  self : Tree,
  mark : Int,
  block : Int,
  w : Double,
  laying : Bool,
  t : Double,
  piece : (Double, Double) -> (Double, Double, Double, Double)?,
) -> (Double, Double)? {
  guard self.start_in(mark, block, w, laying, t) is Some(start) else { return None }
  let nw = self.width_in(mark, block, w)
  let nh = @flex.measured_height(self.nodes[mark].flex, nw)
  match piece(nw, nh) {
    Some((_, y, _, h)) => Some((start + y, start + y + h))
    None => None
  }
}
