///|
/// The last seq an Int holds: what is set next is set there.
let last_seq : Int = 2147483647

///|
/// A frame's time, after the runtime's start.
let frame_ms : Int64 = 16L

///|
/// A task made ready between frames with the last seq an Int holds, no timer set: the next frame runs it, once, and
/// nothing is left (no seq stands for "no timer", whatever seq a task has).
test "a task made ready between frames at the last seq, no timer: the frame runs it once" {
  let rt = Runtime::new()
  rt.seq = last_seq - 1
  let ran : Array[Int64] = []
  rt.fork(fn() { ran.push(now()) }) |> ignore
  // (said before the frame: a run killed after it hung in the frame, not in building)
  println("seq edge: the frame starts")
  rt.frame(frame_ms)
  assert_eq(ran, [0L])
  assert_true(rt.idle())
}
