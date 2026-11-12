// What a halt prints is its words and its caller's line (said: what it stops with, @halt.saying).

///|
#callsite(autofill(loc))
fn here(loc~ : SourceLoc) -> SourceLoc {
  loc
}

///|
test "a halt says its words and the line that said them" {
  let at = here()
  let words = @halt.said("flow: nothing in the run holds 「x」 to drop", at)
  assert_true(words.has_prefix("flow: nothing in the run holds 「x」 to drop\n  at "))
  assert_true(words.contains("halt_test.mbt:"))
  assert_true(words.has_suffix(at.to_string()))
}
