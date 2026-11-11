// A submenu row in a dialog in the middle of the window (sub_panel, Unanchored: submenu_row_node_wbtest.mbt), its menu
// pressed open, its row going (its room closing on a Move) and called back a frame on: the dialog's height as the row
// turns back, judged frame by frame on the default run (sizes_steady): on from as fast as it closed, not from rest
// (flex's come_way; before, 255 → 250.39 → 250.98, stopped dead), and where the menu stands once the row is back (the
// pointer resting on the row all along: open again; moved off the panel to the window's corner first: closed, then
// pointed at: open).

///|
/// The dialog's row 甲's menu pressed open, the row going and called back a frame on, the pointer moved off the
/// panel to the window's corner first where `away`: the Tester as the row is back and its Move over.
fn sub_back_a_frame_on(away : Bool) -> @ui.Tester raise {
  let shown = @signals.signal(true)
  let t = sub_panel(false, Unanchored, [], shown)
  let (x, y) = sub_mid(t, "甲")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(sub_has(t, "甲一"), msg="open")
  shown.set(false)
  t.frame()
  assert_true(t.query(MenuItem, label="甲一") is None, msg="out of reach as it goes")
  if away {
    t.move_to(4.0, 4.0)
  }
  // (shown again before its Move is over: the same row, back)
  shown.set(true)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a submenu row in a dialog called back a frame after it starts going, the pointer resting on it: steady, its menu open again" {
  let t = sub_back_a_frame_on(false)
  assert_true(sub_has(t, "甲") && sub_has(t, "甲一"), msg="back, open again: \{Repr(sub_at(t, ["甲", "甲一"]))}")
}

///|
test "a submenu row in a dialog called back a frame after it starts going, the pointer moved off it first: steady, its menu closed; pointed at, open" {
  let t = sub_back_a_frame_on(true)
  assert_true(sub_has(t, "甲") && !sub_has(t, "甲一"), msg="back, closed: \{Repr(sub_at(t, ["甲", "甲一"]))}")
  let (x, y) = sub_mid(t, "甲")
  t.move_to(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(sub_has(t, "甲一"), msg="pointed at, open")
}
