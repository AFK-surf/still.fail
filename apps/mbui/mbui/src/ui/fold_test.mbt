// The window's size classes and the device's hinge as the host says them (@hostapi.system_channel `size_class`,
// `fold`): kept as they come, none until the host says them, and given again as they were when a run is replayed.

///|
/// A page that says what the system said of the window's room and the hinge.
fn pose_view(c : @ui.Ctx) -> Unit {
  let room = match @ui.system_size_class() {
    Some({ width: Regular, height: Regular }) => "regular"
    Some({ width: Regular, height: Compact }) => "wide"
    Some({ width: Compact, .. }) => "compact"
    None => "unsaid"
  }
  let pose = match @ui.system_tabletop() {
    Some((top, foot)) => "tabletop \{top} \{foot}"
    None => "hinge \{@ui.system_fold().hinge}"
  }
  c.column(fn() {
    c.text(room, wrap=false) |> ignore
    c.text(pose, wrap=false) |> ignore
  })
  |> ignore
}

///|
test "size classes and the hinge: none until the host says them" {
  let t = @ui.Tester::new(pose_view)
  t.frame()
  assert_true(t.find("unsaid") is Some(_), msg="\{t.drawn_text()}")
  assert_true(t.find("hinge NoHinge") is Some(_), msg="\{t.drawn_text()}")
}

///|
test "an iPhone Duo opened, then half open on its back half: regular both ways, the fold across the view" {
  let t = @ui.Tester::new(pose_view, w=626.0, h=890.0)
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}")
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"open\",\"divisions\":[{\"x\":0,\"y\":430,\"w\":626,\"h\":30}]}}")
  t.frame()
  assert_true(t.find("regular") is Some(_), msg="\{t.drawn_text()}")
  // open flat: the fold is there, nothing to keep off it
  assert_true(t.find("hinge Open") is Some(_), msg="\{t.drawn_text()}")
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":0,\"y\":430,\"w\":626,\"h\":30}]}}")
  t.frame()
  assert_true(t.find("tabletop 430 460") is Some(_), msg="\{t.drawn_text()}")
}

///|
test "half open as a book (the fold upright, two halves side by side): no tabletop" {
  let t = @ui.Tester::new(pose_view, w=890.0, h=626.0)
  t.post(@hostapi.system_channel, "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":430,\"y\":0,\"w\":30,\"h\":626}]}}")
  t.frame()
  assert_true(t.find("hinge Half") is Some(_), msg="\{t.drawn_text()}")
}

///|
test "the outer screen of a folded phone: compact, no fold in the window" {
  let t = @ui.Tester::new(pose_view, w=466.0, h=678.0)
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"compact\",\"height\":\"regular\"},\"fold\":{\"hinge\":\"none\",\"divisions\":[]}}")
  t.frame()
  assert_true(t.find("compact") is Some(_), msg="\{t.drawn_text()}")
  assert_true(t.find("hinge NoHinge") is Some(_), msg="\{t.drawn_text()}")
}

///|
test "what the system said of the window and the hinge is given again where it came when a run is replayed" {
  let t = @ui.Tester::new(pose_view, w=626.0, h=890.0)
  t.start_tape()
  let begun = t.time()
  t.frame()
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"},\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":0,\"y\":430,\"w\":626,\"h\":30}]}}")
  t.frame()
  let tape = t.tape()
  let u = @ui.Tester::new(pose_view, w=626.0, h=890.0, time=begun, run=tape)
  // each frame of the run drawn again as it was: the second after what the system said
  for f in u.replay_frames(tape) {
    assert_eq(f.1, f.2, msg="frame \{f.0}")
  }
  assert_true(u.find("regular") is Some(_), msg="\{u.drawn_text()}")
  assert_true(u.find("tabletop 430 460") is Some(_), msg="\{u.drawn_text()}")
}
