// 03-send-text (src/sfreplay/send_text) seen again twice in one process, back to back: the second run makes every ask
// the first made, takes every step as long, and draws the same frames once settled (a Tester's inputs its own alone:
// sfapp's reset as each starts, flow.mbt).

///|
/// One run of the flow: its drive's log, what it left of the trace, its frames once settled.
fn send_text_once() -> (Array[String], String, Array[Int64]) {
  let (r, t, log) = @sfreplay.run_flow(@sfreplay.trace_send_text, @sfreplay.drive_send_text, skip=["client.device"])
  t.settle() |> ignore
  let left = "\{r.left()} \{r.diverged()} \{r.fuzzy()} \{r.unmade().length()}"
  let frames = [t.frame_hash()] + t.frames(30)
  @core.Replay::detach()
  (log, left, frames)
}

///|
test "03-send-text twice in one process: the second as the first, step for step and frame for frame" {
  let (log1, left1, frames1) = send_text_once()
  let (log2, left2, frames2) = send_text_once()
  assert_true(log1.contains("DRIVE PASS"))
  assert_eq(left1, "0 [] [] 1")
  assert_eq(log2, log1)
  assert_eq(left2, left1)
  assert_eq(@ui.first_difference(frames1, frames2), None)
}
