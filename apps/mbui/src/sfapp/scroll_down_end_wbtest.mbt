// A chat's messages scrolled up and back down come to rest at their end as they opened: the last message whole above
// the composer, the room under it as at first (the user, 0.1.7336: 往下滑不了; main's frame comes back to it, arch/next's
// stopped 72 pt short, the last message's foot hidden under the composer however far it was dragged or flung).

///|
/// How much room there is between the lowest words drawn above the composer and the composer's top (its placeholder's).
fn end_room(t : @ui.Tester, h : Double) -> Double {
  let mut top = h
  for w in t.words() {
    let (s, _, y, _, wh, a) = w
    if a > 0.5 && y > h - 140.0 && y + wh <= h && s.contains("发消息") && y < top {
      top = y
    }
  }
  let mut foot = -1.0e9
  for w in t.words() {
    let (_, _, y, _, wh, a) = w
    if a > 0.5 && y + wh <= top - 2.0 && y + wh > foot {
      foot = y + wh
    }
  }
  top - foot
}

///|
test "the long chat dragged up three screens and down four comes back to its end: the room under its last message as it opened" {
  let calls : Array[Made] = []
  let (w, h) = (390.0, 844.0)
  let t = wide_tester(calls, mode="chat-long", w~, h~, platform=2)
  // (the moments it is looked at: a drag's own end let go, the list come to rest after drags, a fling's run out)
  let between_drags = 200.0
  let rested = 1500.0
  let flung_out = 2500.0
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(rested)
  let opened = end_room(t, h)
  for _ in 0..<3 {
    t.drag(w / 2.0, h * 0.25, w / 2.0, h * 0.75, steps=20)
    t.run_for(between_drags)
  }
  t.run_for(rested)
  for _ in 0..<4 {
    t.drag(w / 2.0, h * 0.75, w / 2.0, h * 0.25, steps=20)
    t.run_for(between_drags)
  }
  t.run_for(rested)
  assert_eq(end_room(t, h), opened, msg="the room under the last message: \{end_room(t, h)}, as it opened \{opened}")
  // (and flung down once more: still there)
  t.drag(w / 2.0, h * 0.25, w / 2.0, h * 0.75, steps=20)
  t.run_for(between_drags)
  t.drag(w / 2.0, h * 0.75, w / 2.0, h * 0.2, steps=4)
  t.run_for(flung_out)
  assert_eq(end_room(t, h), opened, msg="flung down: \{end_room(t, h)}, as it opened \{opened}")
}
