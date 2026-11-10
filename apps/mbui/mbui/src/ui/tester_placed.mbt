// What a frame draws was placed by the layout it draws by: every node of the window's tree the frame just drawn draws
// was placed (Tree::place) as big as it is laid out now. One laid out and never placed by that layout is drawn where
// and as big as it stood before, or nowhere (0 by 0): a page whose layout ran outside a frame and was then not placed
// by the frame after it (2026-11-10: a profile's page pushed straight from Home on a phone, every word of it 0 by 0,
// only what changed after it laid out again; a layout of all of it begun inside another, its frame placing from the
// one begun inside: Tree::measured_now). Held on every frame a Tester draws, as the corner rule is.

///|
/// What of the frame just drawn was drawn not as it is laid out: each node, where it was made, as it was placed and as
/// it is laid out.
pub fn Tester::placed_faults(self : Tester) -> Array[String] {
  ignore(self)
  guard view_tree() is Some(tree) else { return [] }
  let out : Array[String] = []
  for d in tree.drawn() {
    match tree.placed_against_laid(d.id) {
      Some(stands) =>
        match placed_fault(d.id.at, stands) {
          Some(f) => out.push(f + ": " + source_said(d.id))
          None => ()
        }
      None => ()
    }
  }
  out
}

///|
/// What is wrong with node `at` drawn as it stands (Tree::placed_against_laid: placed, as big as placed, as big as laid
/// out), if anything: never placed, or placed another size than it is laid out (half a point either way its own).
fn placed_fault(at : Int, stands : (Bool, Double, Double, Double, Double)) -> String? {
  let (placed, pw, ph, lw, lh) = stands
  if !placed {
    Some("node \{at} drawn, never placed (laid out \{lw}×\{lh})")
  } else if (pw - lw).abs() > 0.5 || (ph - lh).abs() > 0.5 {
    Some("node \{at} drawn as placed \{pw}×\{ph}, laid out \{lw}×\{lh}")
  } else {
    None
  }
}

///|
/// The rule held on the frame just drawn (Tester's frame end, as hold_corners is).
fn Tester::hold_placed(self : Tester) -> Unit {
  let faults = self.placed_faults()
  if faults.is_empty() {
    return
  }
  let said = "drawn not as laid out (tester_placed.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
    faults.length().to_string() +
    " nodes\n" +
    faults[0:(if faults.length() < 8 { faults.length() } else { 8 })].join("\n")
  println(said)
  abort(said)
}
