// What is pressed in a column that scrolls stays where it was pressed (the user, 2026-11-12: 「所有点击展开的控件，展开和
// 收起前后点击的元素位置不能变化」, every list's): what the press opens or shuts round it, over it or under it, moves it
// none. A press (View::on_press, a screen reader's, a gesture's tap) of what says it opens or shuts (View::says,
// `expanded`) asks the column round it to hold it.
// A page's list (View::scrolls_window) holds its block: as what lies over the pressed node in the block (what comes
// before it, or before what holds it, down a column) is taller or shorter each layout on the way (what of it is on its
// way in or out as tall as its way has it then, flex's come_tall_at, as Places reads a block; the rest measured), the
// block's top goes that much the other way. A plain column (View::scrolls) is scrolled that much the same way (all of
// it measured). Room is kept under the foot where what is round it shrinks there, gone as it is scrolled off. Till the
// hand moves it, or what was pressed is let go, or all the press set off has ended: in a page's list at the latest end
// declared by what was set coming or going in it at the press's moment (its keys' ways, what its blocks hold: Tree's
// list_inner, a way turned back too), at a Move's longest (flex's move_most_ms) where none declares one; in a plain
// column at a Move's longest.

///|
/// What a press of node `id` does in the column that scrolls round it (Scroll's pressed_said), said before the press is done:
/// what to do once it is.
fn Tree::press_stays(self : Tree, id : NodeId) -> () -> Unit {
  guard self.view_of(id) is Some(v) else { return fn() {  } }
  // (only what opens or shuts, as it says (expanded or not): a press that does something else (goes to a page, sends,
  // deletes) moves what it is in as that says, the column's own anchor holding it)
  guard self.nodes[id.at].said is Some(said) && said.expanded is Some(_) else { return fn() {  } }
  match v.scroll_holding() {
    Some(s) => (s.pressed_said)(v)
    None => fn() {  }
  }
}
