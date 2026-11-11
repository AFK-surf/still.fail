// The time of day, for what is shown of it only ("3 分钟前", a message's date): the host's (its machine's clock), a
// Tester's as the test sets it (Tester::set_wall), going on with its frames' clock. Never for when something happens
// or how far a motion is: those are the frames' clock's (a motion's, a timer's declared length; detlint's wall-clock
// lets it be read only as a source's `now`).

///|
/// How far a Tester's time of day is ahead of its frames' clock (its fake host's `wall`, Tester::set_wall: a run
/// replayed at the time it was made, as each of its steps was taken), read by what reads the time of day as it is
/// built: built again as it is set otherwise, kept as it was drawn (a list's row, a part: kept_part.mbt) or not.
/// (Unread, what showed it drew the time of day of before: a clock's second, its row's width, until something else
/// built it again.) A host's own never changes it.
// kept across runs: said as each Tester begins (Tester::new) and as its test sets it
let wall_ahead : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })

///|
/// What a Tester's time of day is at its start, unless the test sets it: 2026-09-21 14:13:20 UTC.
pub let tester_wall : Double = 1790000000000.0

///|
/// The time of day now, in ms since 1970 (UTC): to show how long ago something was, or its date. A Tester's is what
/// its test set (Tester::set_wall, by default tester_wall at its start), on as its frames' clock goes. What shows the
/// time since `t` changes as its unit comes, counted from `t`, not from the frames' clock's 0:
///
///   c.every(60000.0, elapsed=@ui.wall_ms() - t)   // its minutes' words change at each minute since t
pub fn wall_ms() -> Double {
  // (read as a view is built: said where a frame of its looks alone parts from it built whole, frame_watch.mbt)
  if @signals.active_sub() is Some(_) {
    wall_read.val = true
    wall_ahead.get() |> ignore
  }
  h_wall_ms()
}

///|
/// The moment of the frames' clock the time of day is (or was) `ms`: where a count of the time of day since `ms` starts
/// on that clock (Ctx::every's `from`), so that the frame its next unit is due at is the one that reads it come.
/// (Counted as `elapsed=wall_ms() - ms` instead, two numbers of some 1.8e12 ms apart, the next unit's moment is a
/// hair off what the time of day reads at that frame: the frame due then drawn without it.) A Tester's alone for now:
/// a host's time of day and its frames' clock are read apart, at two moments, and the clock stops while the machine
/// sleeps; the time of day at the clock's 0 kept by the host, taken again only as it tells it changed, is to come first.
#warnings("-unused_value")
fn clock_at_wall(ms : Double) -> Double {
  // (read as a view is built: what reads it reads the time of day, as wall_ms)
  if @signals.active_sub() is Some(_) {
    wall_read.val = true
    wall_ahead.get() |> ignore
  }
  h_clock_at_wall(ms)
}

///|
/// How far the local time of day is ahead of UTC at `at_ms` (ms since 1970), in minutes (the machine's zone and its
/// summer time then): to show a date or a time of day. A Tester's is UTC's, 0.
pub fn utc_offset_min(at_ms : Double) -> Int {
  h_utc_offset_min(at_ms)
}

///|
/// The time of day, as @ui.wall_ms says it, is `ms` now (and goes on from it with the frames' clock): a run replayed
/// at the time it was made, a date the test shows.
pub fn Tester::set_wall(self : Tester, ms : Double) -> Unit {
  let wall = ms - self.fake.time
  // (what shows the time of day built again where it changed: a clock's words, a list's row kept as drawn too)
  self.fake.wall = wall
  wall_ahead.set(wall)
}
