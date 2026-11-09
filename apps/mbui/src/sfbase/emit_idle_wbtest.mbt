// A chat with no answer flying does not need to follow the sending flight. While an answer is flying, it does:
// sent_first_wbtest exercises their actual handoff.

///|
test "a sending flight is read only while an answer can be held by it" {
  let reads = Ref(0)
  let em = emits_of("idle-flight-check")
  em.watched = true
  let turns = turns_of("idle-flight-check")
  let t = @ui.Tester::new(fn(c) {
    emit_step(c, em, turns, fn() {
      reads.val += 1
      -1.0
    })
  })
  assert_eq(reads.val, 0)
  em.current = Some({
    seq: 1.0,
    agent: "agent",
    pose: Fold,
    from: None,
    clock: pose_clock(t.ctx(), Fold.ms(), Some(t.time())),
    span: Fold.ms(),
    warp: None,
  })
  t.draw()
  assert_true(reads.val > 0)
}
