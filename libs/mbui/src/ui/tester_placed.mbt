// What a frame draws was placed by the layout it draws by: every node of the window's tree the frame just drawn draws
// was placed (Tree::place) as big as it is laid out now. One laid out and never placed by that layout is drawn where
// and as big as it stood before, or nowhere (0 by 0): a page whose layout ran outside a frame and was then not placed
// by the frame after it (2026-11-10: a profile's page pushed straight from Home on a phone, every word of it 0 by 0,
// only what changed after it laid out again; a layout of all of it begun inside another, its frame placing from the
// one begun inside: Tree::measured_now). Held on every frame a Tester draws, as the corner rule is, as the frame stood
// the moment it was presented (FakeHost::present): what comes after that in the same frame (a scripted run's step,
// drive_frame, its handler laying out what it reads, Tree::measured_now) is laid out for the frame after it, which
// places it (2026-11-10: a finger dragging Home's list in still.fail's bench, a row's end let go of as it moved, its
// line laid out again after the frame was drawn and placed by the next: no frame drew it otherwise than laid out).

///|
/// What of the frame just drawn was drawn not as it is laid out: each node, where it was made, as it was placed and as
/// it is laid out.
pub fn Tester::placed_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  placed_faults_now()
}

///|
/// What of the window's tree is drawn now not as it is laid out (Tester::placed_faults).
fn placed_faults_now() -> Array[String] {
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
/// What the frame being drawn drew not as it was laid out, as it was presented (FakeHost::present), for the Tester's
/// frame end to hold (Tester::hold_placed): None where no frame was presented since it last held it.
let placed_presented : Ref[Array[String]?] = Ref(None)

///|
/// The frame presented now: what of it was drawn not as it is laid out, kept for the frame's end (Tester::hold_placed).
/// Not where a bench measures its frames (Tester::bench past its `log measure`): as the bench's other checks of a frame,
/// no work of the app's.
fn placed_at_present() -> Unit {
  if bench_measuring.val {
    return
  }
  placed_presented.val = Some(placed_faults_now())
}

///|
/// The rule held on the frame just drawn (Tester's frame end, as hold_corners is), as it was presented.
fn Tester::hold_placed(self : Tester) -> Unit {
  let faults = placed_presented.val.unwrap_or([])
  placed_presented.val = None
  if faults.is_empty() {
    return
  }
  let said = "drawn not as laid out (tester_placed.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
    faults.length().to_string() +
    " nodes\n" +
    faults[0:(if faults.length() < 8 { faults.length() } else { 8 })].join("\n")
  @halt.saying(said)
}
