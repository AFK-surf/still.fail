// A run stopped says why, and where, before it stops.
//
// MoonBit's `abort(msg)` prints `msg` on native, but on wasm-gc (where the tests run on Studio and on a laptop) it is
// a trap: the test says `failed: Error` and a few lines of `at mbui/…@0.1.0` without a place, never the words. So
// nothing in mbui or an app calls `abort` itself: `@halt.saying(msg)` prints the words and the line that said them,
// then aborts (detlint's `abort-unsaid`). It is on the failing path alone: a caller's place is a constant handed in,
// and the words are worked out only once it is called, as an `abort`'s were.

///|
/// What a halt prints: the words, then where they were said.
pub fn said(msg : String, loc : SourceLoc) -> String {
  "\{msg}\n  at \{loc}"
}

///|
/// Stops the run, its words and the caller's place printed first (on wasm-gc an abort's own words are lost).
#callsite(autofill(loc))
pub fn[T] saying(msg : String, loc~ : SourceLoc) -> T {
  println(said(msg, loc))
  flush_out()
  abort(msg) // det-ok(abort-unsaid): the one abort, its words printed on the line above
}
