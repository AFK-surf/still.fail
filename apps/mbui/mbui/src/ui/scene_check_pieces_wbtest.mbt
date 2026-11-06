// The scene's check of the shapes' pieces (bands_pieces_differ): a band compared by the pieces it says are its, each,
// wherever they are among the frame's; past them on either side told as such.

///|
/// One band (kind 11) whose pieces begin at `first`, `count` of them.
fn check_band(first : Int, count : Int) -> FixedArray[Double] {
  let a = FixedArray::make(inst_size, 0.0)
  a[5] = 11.0
  a[12] = first.to_double()
  a[13] = count.to_double()
  a
}

///|
/// `n` pieces of nothing, then `pieces`.
fn check_pieces(n : Int, pieces : Array[Double]) -> Array[Double] {
  let out = Array::make(n * 4, 7.0)
  out.append(pieces)
  out
}

///|
test "a band's pieces compared by what they are: the same where they are elsewhere, told where they differ or lie past" {
  let mine = [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0]
  let no = FixedArray::make(1, false)
  // (the same pieces, three others before them on one side and none on the other: the same)
  assert_eq(bands_pieces_differ(check_band(3, 2), check_pieces(3, mine), check_band(0, 2), check_pieces(0, mine), 1, no), None)
  // (one number of one piece otherwise: told, that piece)
  let other = [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.5]
  assert_true(
    bands_pieces_differ(check_band(3, 2), check_pieces(3, mine), check_band(0, 2), check_pieces(0, other), 1, no)
    is Some(s) &&
    s.contains("piece 1 differs"),
  )
  // (past the kept pieces; past those drawn anew; past both: each told, the kept first)
  let past_kept = bands_pieces_differ(check_band(1, 2), check_pieces(0, mine), check_band(0, 2), check_pieces(0, mine), 1, no)
  assert_true(past_kept is Some(s) && s.contains("past the 2 kept"), msg="\{past_kept}")
  let past_anew = bands_pieces_differ(check_band(0, 2), check_pieces(0, mine), check_band(1, 2), check_pieces(0, mine), 1, no)
  assert_true(past_anew is Some(s) && s.contains("drawn anew"), msg="\{past_anew}")
  let past_both = bands_pieces_differ(check_band(5, 2), check_pieces(0, mine), check_band(5, 2), check_pieces(0, mine), 1, no)
  assert_true(past_both is Some(s) && s.contains("kept"), msg="\{past_both}")
  // (one an old view's own: not the scene's to compare)
  assert_eq(bands_pieces_differ(check_band(1, 2), check_pieces(0, mine), check_band(0, 2), check_pieces(0, other), 1, FixedArray::make(1, true)), None)
}
