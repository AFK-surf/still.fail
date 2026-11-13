// The time of day for what is shown of it (wall.mbt): a Tester's as its test sets it, on with its frames' clock.

///|
test "a Tester's time of day: its own day at its start, on with its frames' clock, set by the test" {
  let minute = 60000.0
  // 3 minutes 20 seconds before the Tester's day begins
  let since = tester_wall - 3.0 * minute - 20000.0
  let shown : Ref[String] = Ref("")
  let t = Tester::new(fn(c) {
    let ago = ((wall_ms() - since) / minute).floor().to_int()
    shown.val = "\{ago} 分钟前"
    c.text(shown.val, wrap=false) |> ignore
    // its words change as the minute since `since` comes: a wake at it, counted from `since` (the wall's minute,
    // not the frames' clock's), where it is on the frames' clock
    c.every(minute, from=clock_at_wall(since)) |> ignore
  })
  // a Tester's clock starts at 1000 (Tester::new's `time`): its day's at that moment
  let start = 1000.0
  assert_eq(wall_ms(), tester_wall - start + t.time())
  assert_eq(shown.val, "3 分钟前")
  // the minute turns at since + 4 minutes: the display's frame before it still says 3, its first frame at or past
  // it says 4
  let turn = since + 4.0 * minute - (tester_wall - start)
  let first = t.display_frame(turn)
  let before = first - frame_period_default
  t.run_for(before - t.time())
  assert_eq(t.time(), before)
  assert_eq(shown.val, "3 分钟前")
  assert_eq(wall_ms(), tester_wall - start + t.time())
  t.run_for(first - t.time())
  assert_eq(t.time(), first)
  assert_eq(shown.val, "4 分钟前")
  // set by the test: from then on
  t.set_wall(since + 10.0 * minute)
  assert_eq(wall_ms(), since + 10.0 * minute)
  t.draw()
  assert_eq(shown.val, "10 分钟前")
}

///|
test "the time of day set otherwise: what shows it built again, kept as drawn or not" {
  let since = tester_wall - 20000.0
  let t = Tester::new(fn(c) {
    // its seconds since `since`, shown in the frame and in a part kept as it was drawn (kept_part.mbt)
    let s = ((wall_ms() - since) / 1000.0).floor().to_int()
    c.text("\{s}s", wrap=false) |> ignore
    c.every(1000.0, from=clock_at_wall(since)) |> ignore
    c.kept_part(c.id("part"), "", fn() {
      let k = ((wall_ms() - since) / 1000.0).floor().to_int()
      c.text("part \{k}s", wrap=false) |> ignore
      c.every(1000.0, from=clock_at_wall(since)) |> ignore
    })
  })
  t.run_for(wall_first_ms)
  assert_true(t.find("part 20s") is Some(_))
  // set back a second and a half, between two of the clock's steps (a replayed run's step, at its own time of day): the next
  // frame says so, nothing else asking for it (a frame of its looks alone drew the second of before: frame_watch.mbt)
  t.set_wall(wall_ms() - 1500.0)
  t.run_for(frame_period_default)
  assert_true(t.find("20s") is None)
  assert_true(t.find("part 18s") is Some(_))
}

///|
/// How long the clock runs before the time of day is set otherwise: within its first second.
let wall_first_ms : Double = 100.0
