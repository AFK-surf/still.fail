// A long chat entered: its list works out the rooms of the rows that show alone, as a chat of its last 30 does (the
// user's phone, 2026-11-05: entering a chat of 3000 froze 474 ms, most of it the list going through all its rows).

///|
/// How many times a row's room was worked out entering chat `mode` at `w` × `h`, and how many rows show then.
fn rooms_entering(mode : String, w : Double, h : Double) -> (Int, Int) {
  let t = wide_tester([], mode~, w~, h~, platform=if w > 600.0 { 0 } else { 2 })
  t.run_for(@ui.move_most_ms)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  let (first, last) = t.visible()
  (rd.rows.rooms_worked(), last - first + 1)
}

///|
test "a chat of 3000 entered works out the rooms of the rows that show, as many as for its last 30, on a phone and a desktop" {
  for size in [(390.0, 844.0), (1280.0, 800.0)] {
    let (w, h) = size
    let (long, shown) = rooms_entering("chat-long", w, h)
    let (short, _) = rooms_entering("chat-long-30", w, h)
    // (each row that shows a few times over as the page opens, its rooms opening: never a row out of sight)
    assert_true(long <= short, msg="at \{w}: 3000 worked out \{long} rooms, 30 \{short}")
    assert_true(long <= shown * 20, msg="at \{w}: \{long} rooms for \{shown} rows in sight")
  }
}
