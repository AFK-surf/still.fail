// What takes the presses landing on a box that takes none itself (Ctx::presses_to): a surface over several things,
// reading where a press lands (a bar's glass over its places, a sheet's top over its title), said by each of them. A
// fact of the screen: the box is pressed, through it. What asks whether a finger reaches something reads it (a
// scripted run's taps, drive.mbt; a screen reader, the same).

///|
/// Presses landing on the box this is said in are `area`'s (a drag area, Ctx::drag_on, or a box with an id taking
/// presses), which reads where they land: the box, and what is in it, is pressed through it. `area` taking no presses
/// where the box is laid out (none drawn with that id, or not over it): a Tester fails, saying where it was said.
#callsite(autofill(loc))
pub fn Ctx::presses_to(self : Ctx, area : Int, loc~ : SourceLoc) -> Unit {
  if self.cur >= 0 {
    self.nodes[self.cur].press_owner = Some((area, loc))
  }
}

///|
/// What the box being built shows is pressed through node `node` of the window's tree over it (drawn here, a finger on
/// it that node's: the bottom bar's places, its glass's): where a press there reaches is the tree's to say (drive.mbt
/// reach_point).
pub fn Ctx::presses_to_node(self : Ctx, node : @view.NodeId) -> Unit {
  if self.cur >= 0 {
    self.nodes[self.cur].press_node = Some(node)
  }
}

///|
/// Once a frame is painted (a Tester's, after each frame it draws): each box's presses said to be another's are that
/// one's to take, where the box is (Ctx::presses_to): the area drawn as a hit target over some of the box. One that is
/// not stops the test with its words (Ctx::presses_unheld's: the two are one checking), unless its Tester was made not
/// to hold it (presses_held=false: a test that says one wrong on purpose, to find it).
fn Ctx::check_press_owners(self : Ctx) -> Unit {
  guard presses_hold.val else { return }
  match self.presses_unheld().get(0) {
    Some(s) => @halt.saying(s)
    None => ()
  }
}

///|
/// Each box's presses said to be an area's that takes none where the box is (Ctx::check_press_owners), said: where it
/// was said and where the box is. The words check_press_owners stops with.
fn Ctx::presses_unheld(self : Ctx) -> Array[String] {
  let out = []
  for i in 0..<self.count {
    let n = self.nodes[i]
    guard n.press_owner is Some((area, loc)) else { continue }
    let mut over = false
    let mut k = self.hit_ids.length() - 1
    while k >= 0 && !over {
      if self.hit_ids[k] == area {
        let r = k * 4
        over = self.hit_rects[r] < n.x + n.fw &&
          n.x < self.hit_rects[r + 2] &&
          self.hit_rects[r + 1] < n.y + n.fh &&
          n.y < self.hit_rects[r + 3]
      }
      k = k - 1
    }
    if !over {
      out.push(
        "Ctx::presses_to: area \{area}, said at \{loc}, takes no presses where its box is (\{n.x.to_int()},\{n.y.to_int()} \{n.fw.to_int()}x\{n.fh.to_int()})",
      )
    }
  }
  out
}

///|
/// The presses said to be an area's that takes none where they are, in the frame drawn last (Ctx::presses_unheld): what
/// a Tester made with presses_held=false finds in place of stopping on it.
pub fn Tester::presses_unheld(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  g().presses_unheld()
}

///|
/// Whether a Tester stops on presses said to be an area's that takes none (Tester::new's presses_held).
// kept across runs: put back as each Tester starts (reset_globals), set by its presses_held
let presses_hold : Ref[Bool] = Ref(true)
