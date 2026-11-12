// How a node of the window's tree is said to be laid out, read for a Tester's checks of room run short (ui's
// squeeze.mbt, which puts the tree's nodes among an old view's: Ctx::with_tree_nodes), as Tree::allows_ellipsis is.
// Only what the node already has, as it is now: nothing of it is kept, nothing laid out, drawn or found by it, and it is
// read only where a check asks for it.
//
// How narrow a node may come to along its row (the squeeze's `least`, what Ctx::gives_beside reads) is what the layout
// itself takes it to be, read off what is said, nothing measured: flex has no least of its own making for what says
// none (fit_needs, row_item_min: a min-width not said is none, the item giving way down to its padding), so `min_w` NaN
// is a least of its padding across, as the layout has it, not a guess; `min_w` said within (`min_within`) is no more
// than the room what holds it gives. What never gives way (shrink 0) is as wide as it is laid out. What is never narrower than what it holds
// (`keeps`) is measured by the layout as it lays its line out (row_item_min's size_node), which is not read here; the
// squeeze reads no least of it (Ctx::gives_beside and Ctx::squeeze_gives pass over what keeps its width), so none is
// guessed.

///|
/// How node `id` lays out what it holds and is laid out in what holds it, as said (Tree::laid_facts).
pub(all) struct LaidFacts {
  /// what it holds goes across (View::row), and from its end (a flex direction reversed)
  row : Bool
  reverse : Bool
  /// a row going on in lines where what it holds has not the room on one (View::wraps)
  wraps : Bool
  /// the room inside its edges and round it (left, top, right, bottom: View::padding, View::margin)
  pad : (Double, Double, Double, Double)
  margin : (Double, Double, Double, Double)
  /// its width said in points (View::width), or as a share of what holds it (View::width_share)
  width_points : Bool
  width_share : Bool
  /// its height said in points (View::height): as high as that whatever it holds (a least, View::min_height, is not)
  height_points : Bool
  /// how much it grows into the room along a row and gives way where that is short (as laid out now: View::grow,
  /// View::shrink, or what it is makes it, Tree::give_way_applied)
  grow : Double
  shrink : Double
  /// never narrower along its row than what it holds needs (View::keeps_held)
  keeps : Bool
  /// how narrow it may be, said in points (View::min_width; NaN: not so said), and whether no more than the room what
  /// holds it gives (View::min_width's `within`)
  min_w : Double
  min_within : Bool
  /// how wide it may be at most, said by the app (View::max_width, `within` too; infinite: not said). The bound the
  /// framework puts on one line of words in a column (Tree::capped_applied's) is no such say: not here.
  max_w : Double
  /// out of the flow of what holds it: 0 in it; 1 laid over what holds it, filling it (View::over); 2 placed beside
  /// another (View::beside); 3 put where its insets say otherwise
  apart : Int
  /// drawn off where it is laid out, now: by its offset (View::offset), by what moves it (View::moved_by)
  off : (Double, Double)
  /// where it is drawn is its own to say: its offset bound to what moves it (View::offset said `By`), or what moves it
  /// said (View::moved_by), whatever either comes to now (0 at rest too)
  moves_own : Bool
  /// how it scrolls what it holds (View::scrolls): 0 not, 1 up and down, 2 across
  scrolls : Int
  /// left out of its row where the row has not the room (View::drops: k > 0, -1 its ⋯; 0 always there)
  drop : Int
  /// the shorter ways it says its words where they have not the room on their line (View::shorter)
  shorter : Array[String]
}

///|
/// How node `id` is said to be laid out now (LaidFacts), none where it is let go.
pub fn Tree::laid_facts(self : Tree, id : NodeId) -> LaidFacts? {
  guard self.alive_id(id) else { return None }
  let n = self.nodes[id.at]
  let st = n.flex.style
  let max_w = match n.max_w_said {
    Some(Some(w)) => w
    _ => @double.infinity
  }
  let apart = if st.position != @flex.PositionType::Absolute {
    0
  } else if n.beside is Some(_) {
    2
  } else if st.get_inset_left() == Pt(0.0) &&
    st.get_inset_top() == Pt(0.0) &&
    st.get_inset_right() == Pt(0.0) &&
    st.get_inset_bottom() == Pt(0.0) {
    1
  } else {
    3
  }
  Some({
    row: st.direction is (Row | RowReverse),
    reverse: st.direction is (RowReverse | ColumnReverse),
    wraps: !(st.wrap is NoWrap),
    pad: (st.padding_left_value(), st.padding_top_value(), st.padding_right_value(), st.padding_bottom_value()),
    margin: (st.margin_left_value(), st.margin_top_value(), st.margin_right_value(), st.margin_bottom_value()),
    width_points: st.width_kind() == @flex.LEN_PT,
    width_share: st.width_kind() == @flex.LEN_PCT,
    height_points: st.height_kind() == @flex.LEN_PT,
    grow: st.grow,
    shrink: st.shrink,
    keeps: st.min_held,
    min_w: match n.min_w_said {
      Some(Some(w)) => w
      _ => @double.not_a_number
    },
    min_within: n.min_w_within,
    max_w,
    apart,
    off: (n.look.dx + n.moved.0, n.look.dy + n.moved.1),
    // (a binding of its offset is kept among its properties while it is bound: View::bind's `props`)
    moves_own: n.props.contains(Prop::Offset.ord()) || n.moved_by is Some(_),
    scrolls: if n.scroll_held < 0 {
      0
    } else if n.scroll_across {
      2
    } else {
      1
    },
    drop: st.drop,
    shorter: n.shorter,
  })
}
