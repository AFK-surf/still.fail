// A host draws its next frame where the app asks (Tester::wanted_after: the display's next, or its wake) and a test
// walking a host's frames puts each at Tester::display_frame of that wake. A wake a few last bits after one of the
// display's frames (a clock's next second worked out from its start and the seconds gone, sfbase's each_second) is
// within the grid's hair of that frame: display_frame gave the frame itself, the wake had not come at it, the app asked
// for the same wake again and the frames never went on (emit_kept_wbtest, idle_steps_wbtest: CI's five minutes).

///|
/// The rounds of a host's frames, each where the app asks, that a wake two last bits after the display's next frame
/// takes to come, and what is not so once it came (the clock at the wake to the bit, the display's next frame the one
/// on its grid after it); where it has not come in `most` rounds, the round and its moments said.
fn display_frame_rounds(most : Int) -> (Int, String) {
  let wake : Ref[Double] = Ref(-1.0)
  let t = Tester::new(
    fn(c) {
      c.text("x", wrap=false) |> ignore
      if c.clock < wake.val {
        c.wake_at_time(wake.val, later=true)
      }
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  let frame = t.next_frame_time()
  let w = (frame.reinterpret_as_int64() + 2L).reinterpret_as_double()
  wake.val = w
  let grid_next = t.tick_after(frame)
  t.stepped()
  t.draw()
  let mut rounds = 0
  while t.time() < w {
    let asked = t.wanted_after()
    let at = if asked <= t.time() { t.next_frame_time() } else { t.display_frame(asked) }
    if rounds == most {
      return (
        rounds,
        "after \{rounds} rounds at \{t.time()}: the app asks for \{asked} (\{t.wanted_why()}), its display frame \{at}",
      )
    }
    t.frame_at(at)
    rounds += 1
  }
  if t.time().reinterpret_as_int64() != w.reinterpret_as_int64() {
    return (rounds, "the wake \{w} drawn at \{t.time()}")
  }
  if t.next_frame_time().reinterpret_as_int64() != grid_next.reinterpret_as_int64() {
    return (rounds, "the display's next frame \{t.next_frame_time()}, not \{grid_next}")
  }
  (rounds, "")
}

///|
test "a host's frames put where the app asks come to a wake a hair after a frame of the display's, and go on" {
  let (rounds, wrong) = display_frame_rounds(10)
  assert_eq(wrong, "")
  // (to the frame the wake is a hair after, then to the wake itself: two at most)
  assert_true(rounds <= 2, msg="\{rounds} rounds")
}

///|
test "a frame drawn at a moment a hair after the display's is that moment, never the frame before it" {
  let t = Tester::new(fn(c) { c.text("x", wrap=false) |> ignore }, w=200.0, h=200.0)
  t.draw()
  let frame = t.next_frame_time()
  let w = (frame.reinterpret_as_int64() + 2L).reinterpret_as_double()
  // (a moment a hair short of a frame is that frame, a moment a hair after it is itself)
  let short = (frame.reinterpret_as_int64() - 2L).reinterpret_as_double()
  assert_eq(t.display_frame(short).reinterpret_as_int64(), frame.reinterpret_as_int64())
  assert_eq(t.display_frame(frame).reinterpret_as_int64(), frame.reinterpret_as_int64())
  assert_eq(t.display_frame(w).reinterpret_as_int64(), w.reinterpret_as_int64())
}

///|
/// How far on the view of frame_at_said's test asks to be woken: a wake later than the frames it draws, never come to.
let later_wake_ms : Double = 4000.0

///|
test "frames one after another at one moment, the app waiting for a later one, are said" {
  let t = Tester::new(
    fn(c) {
      c.text("x", wrap=false) |> ignore
      c.wake_at_time(c.clock + later_wake_ms, later=true)
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  // (a moment no frame was drawn at yet: the frames drawn at the Tester's own count none of these)
  let at = t.time() + 1.0
  for _ in 1..<frames_at_one_most {
    assert_eq(t.frame_at_said(at), None)
  }
  match t.frame_at_said(at) {
    Some(s) =>
      assert_true(
        s.has_prefix("Tester::frame_at: \{frames_at_one_most} frames one after another at \{at}"),
        msg=s,
      )
    None => fail("no words at the \{frames_at_one_most}th frame")
  }
  // (a frame at another moment starts the count again)
  assert_eq(t.frame_at_said(at + 1.0), None)
  assert_eq(t.frame_at_said(at + 1.0), None)
  frames_at_one.val = (-1.0, 0)
}
