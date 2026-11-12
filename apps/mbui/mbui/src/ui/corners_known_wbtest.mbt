// Faults of the corner rule a test knows and keeps (Tester::corners_known): the same part, the rule's same words,
// passed over by Tester::hold_corners wherever it stands on the window (a list scrolled); any other not.

///|
test "corners a test knows: the same part in the same corner, said by the rule's same words, passed over wherever it stands and whichever node it is; another size, another corner, the rule's other words, not" {
  let t = tree_card(fn(v) { v.ground(Is(0xEEEEEEFFL)).radius(Is(20.0)) |> ignore }, corners_held=false)
  let faults = t.corner_faults()
  let top_left = faults.filter(fn(f) { f.contains(" in the top left of ") })
  assert_eq((faults.length(), top_left.length()), (4, 1), msg=faults.join("\n"))
  let said = top_left[0]
  // (the same, the card and what is in it standing elsewhere, other nodes of the frame)
  let elsewhere = said
    .replace(old="(at 6,6 ", new="(at 50,170 ")
    .replace(old="(at 0,0 ", new="(at 44,164 ")
    .replace(old="node 3)", new="node 31)")
    .replace(old="node 2)", new="node 30)")
  assert_true(elsewhere != said, msg=said)
  t.corners_known([elsewhere])
  let left = corners_unknown(faults)
  assert_eq((left.length(), left.contains(said)), (3, false), msg=left.join("\n"))
  // (what it names another size, the rule's words other: not that one)
  for other in [said.replace(old="188×108", new="188×107"), said.replace(old="wants corner", new="wants a corner")] {
    assert_true(other != said, msg=said)
    t.corners_known([other])
    assert_eq(corners_unknown(faults).length(), 4, msg=other)
  }
  // (none known: all of them)
  t.corners_known([])
  assert_eq(corners_unknown(faults), faults)
}
