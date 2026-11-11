// What a piece of the window thread's work went on, by part, for the hangs found in it (mbui's src/ui/journal.mbt): a
// part of the app or of mbui that may take long (a message of the core's taken, a kept part or an old view built again)
// runs under work_part, which times it on the journal's clock and tells the journal what it was where it took
// `work_noted_ms` or more (many short ones of a kind make a piece long: a burst of the core's messages, each a few
// tenths of a ms; what took less is not named, as naming every part of every frame is work of its own); nothing where
// no journal listens (a program that keeps none). Only where it was made and how long: no words, no message's contents.

///|
/// The journal's clock and what it is told (`what`, ms), as it begins to listen (ui's journal_reset); none: nobody.
// kept across runs: set as a run begins, by the journal
let work_noting : Ref[(() -> Double, (String, Double) -> Unit)?] = Ref(None)

///|
/// The journal listening, on its clock (`now`), told each part at least `work_noted_ms` long (`note`); None, none.
pub fn work_noted_by(by : (() -> Double, (String, Double) -> Unit)?) -> Unit {
  work_noting.val = by
}

///|
/// The shortest part the journal is told of (ms).
let work_noted_ms : Double = 0.1

///|
/// `f` run, and where it took `work_noted_ms` or more on the journal's clock, the journal told it was `what` (worked
/// out only then) and how long: what the hang it was in went on.
pub fn[T] work_part(what : () -> String, f : () -> T) -> T {
  match work_noting.val {
    None => f()
    Some((now, note)) => {
      let t0 = now()
      let r = f()
      let ms = now() - t0
      if ms >= work_noted_ms {
        note(what(), ms)
      }
      r
    }
  }
}

///|
/// A part timed by whoever runs it begins: the journal's clock now, below 0 where no journal listens (nothing timed).
pub fn work_began() -> Double {
  match work_noting.val {
    Some((now, _)) => now()
    None => -1.0
  }
}

///|
/// A part took `ms` on the journal's clock (work_began's), in one piece or in all of many (the words measured in a
/// layout): the journal told it was `what` where that is `work_noted_ms` or more.
pub fn work_took(what : String, ms : Double) -> Unit {
  if ms >= work_noted_ms && work_noting.val is Some((_, note)) {
    note(what, ms)
  }
}
