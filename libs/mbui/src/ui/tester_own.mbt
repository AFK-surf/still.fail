// A Tester's frame is the process's: what it reads (its words, what it drew, its semantics, where things are, an
// audit) is read of the frame of the Tester made last, never one of its own. So a Tester read after another was made
// reads the other's frame, and says nothing of it (two views compared, the old one read after the new one was made:
// what was read as the old was the new, a message's file cards, 2026-11-11). Each of its reading calls asks first whether it is
// the one made last (Tester::reads_own) and stops, saying why, where it is not.

///|
/// What is wrong with reading Tester `self` now: "" where it is the one made last and its run not ended (what it reads
/// is its own frame); else why what it would read is not its own.
pub fn Tester::own_read_said(self : Tester) -> String {
  match fake.val {
    Some(f) if physical_equal(f, self.fake) => ""
    Some(_) =>
      "a Tester read after another was made: what it reads is the frame of the one made after it, not its own; read all of it before making the next"
    None => "a Tester read after its run was ended (Tester::end_run): what it would read is no frame of its own"
  }
}

///|
/// Tester `self`'s reading calls ask this first: stopped, saying why, where what it would read is not its own frame
/// (Tester::own_read_said).
fn Tester::reads_own(self : Tester) -> Unit {
  let said = self.own_read_said()
  if said != "" {
    @halt.saying(said)
  }
}
