// A place in a panel's foot that comes and goes (a button there only in some of what the panel shows), as nodes: at a
// sheet's foot its share of the foot's width, as each button standing there has (foot_fills_lent: the old foot's
// buttons, each Fill there, whichever of them it drew that frame). A share is counted from each one's flex basis, which
// is never under its own padding (flex's layout: a button standing in the foot counts from its padding at its sides,
// button_padx each); the place has none of its own, so it counts from a button's, else a button in it would be given
// less than one beside it (155 and 187 of a phone's sheet's 350, where the old foot gives 171 each).
//
// What that takes: what stands beside it in the foot is button_node's (each counting from 2 × button_padx), as every
// panel's foot is. What the place holds may be anything: the place is given its share whatever it holds, and what grows
// along it (button_node does at a sheet's foot) is as wide as it. Two ways that would not say button_padx here were
// weighed and left: the place laid out as what it holds alone (CSS's display: contents, flex's Display::Contents) is
// not one a View can say, and would be the framework's to give; the place's floor said as its own padding is the same
// button_padx, and what it holds would then need as much of a margin out again to be as wide as it.

///|
/// A place in a panel's foot `foot` while `when()`, what it holds made by `make` (a button_node, …) as it comes: a row
/// of what it holds; at a sheet's foot its share of the foot's width, as a button_node standing in the foot itself has,
/// whatever it holds (what grows along it, a button_node there, as wide as it). Along the foot's row it comes and goes
/// at once, what is beside it taking the room as it goes (a row's way, View::show's).
#callsite(autofill(loc))
pub fn foot_place_node(foot : @view.View, when : () -> Bool, make : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  foot.show(loc~, when, fn(place) {
    place.made_for(loc).row(Is(true)) |> ignore
    if place.lent(foot_fills_lent).unwrap_or(false) {
      // (counted from as much as a button_node beside it is: its padding at its sides)
      // (never narrower than what it holds needs, as a button standing in the foot: keeps_held)
      place.grow(Is(1.0)).basis(Is(Some(2.0 * button_padx))).keeps_held(Is(true)) |> ignore
    }
    make(place)
  })
}
