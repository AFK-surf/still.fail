// Whether the hand is on a node that takes no press from a mouse (a bar's tag whose press is a finger's alone, a mouse's
// there what holds it's: a bar dragging the window), as c.lit lit an old view's box with an id there.

///|
/// Whether the hand is on `v` as lit_node says it, a mouse's pointer within it as it is placed (View::pointer_within)
/// counting where `v` takes no press of a mouse's itself (what is under the pointer there is what holds it). Not where
/// the pointer is on `yields_to` or on what it holds (View::pointed_in): what beside `v` reaches over it (a key's room
/// over a tag beside it, a press there that key's) answers there alone.
pub fn lit_within_node(v : @view.View, yields_to? : @view.View) -> Bool {
  v.focus_shown() ||
  (match @ui.pointing() {
    Mouse => (v.pointed_in() && !yielded(yields_to)) || v.pressed()
    Finger => v.pressed()
  })
}

///|
/// Whether the pointer is on `to` or on what it holds (View::pointed_in), none where it is not said.
fn yielded(to : @view.View?) -> Bool {
  match to {
    Some(o) => o.pointed_in()
    None => false
  }
}
