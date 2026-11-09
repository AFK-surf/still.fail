// What a piece of the window thread's work went on, by part, for the hangs found in it (mbui's src/ui/journal.mbt): a
// part of the app or of mbui that may take long (a message of the core's taken, a kept part or an old view built again)
// runs under work_part, which times it on the journal's clock and tells the journal what it was, however short (many
// short ones of a kind make a piece long: a burst of the core's messages); nothing where no journal listens (a program
// that keeps none). Only where it was made and how long: no words, no message's contents.

///|
/// The journal's clock and what it is told (`what`, ms), as it begins to listen (ui's journal_reset); none: nobody.
// kept across runs: set as a run begins, by the journal
let work_noting : Ref[(() -> Double, (String, Double) -> Unit)?] = Ref(None)

///|
/// The journal listening, on its clock (`now`), told each part (`note`); None, none.
pub fn work_noted_by(by : (() -> Double, (String, Double) -> Unit)?) -> Unit {
  work_noting.val = by
}

///|
/// `f` run, and the journal told it was `what` (worked out only where one listens) and how long it took on its clock:
/// what the hang it was in went on.
pub fn[T] work_part(what : () -> String, f : () -> T) -> T {
  match work_noting.val {
    None => f()
    Some((now, note)) => {
      let t0 = now()
      let r = f()
      note(what(), now() - t0)
      r
    }
  }
}
