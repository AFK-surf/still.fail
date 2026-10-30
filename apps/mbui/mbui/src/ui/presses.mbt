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
/// Once a frame is painted, under a Tester: each box's presses said to be another's are that one's to take, where the
/// box is (Ctx::presses_to): the area drawn as a hit target over some of the box.
fn Ctx::check_press_owners(self : Ctx) -> Unit {
  if fake.val is None {
    return
  }
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
      let s = "Ctx::presses_to: area \{area}, said at \{loc}, takes no presses where its box is (\{n.x.to_int()},\{n.y.to_int()} \{n.fw.to_int()}x\{n.fh.to_int()})"
      println(s)
      abort(s)
    }
  }
}
