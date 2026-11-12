// A made-up core tells its changes as the core does (src/core Sub.changes): where they are made, never as a topic is
// read. What reads a topic follows it whenever it began to: a reader that read it first and one that read it after
// are told alike.

///|
/// The words of the made-up chat's agent's step (chat-working's `live`), as `src` has them by now: none till it came.
fn live_step(src : Source) -> String? {
  match src.topic("live", { "station": "ws1/st1", "key": "s-c1" }).get().value {
    Some(v) => opt_text(field(field(Some(v), "activity"), "now"), "text")
    None => None
  }
}

///|
test "a made-up topic answered late: told once to the reader that read it first and to the one that read it after, again as it changes, not as it is set the same" {
  fresh_app()
  let clock = Ref(0.0)
  fix_clock.val = Some(fn() { clock.val })
  let src = @sffixture.round_trip(fixture("chat-working"), 100.0)
  let step = @signals.computed(fn(_) { live_step(src) })
  let told = [0, 0]
  let early = @signals.watch(fn() { told[0] += 1 })
  let late = @signals.watch(fn() { told[1] += 1 })
  // the first reads it before its answer: none yet; the second after the first, the same
  assert_eq(early.read(fn() { step.get() }), None)
  assert_eq(late.read(fn() { step.get() }), None)
  // its answer comes late: both told, once
  fix_clock_set(clock, 100.0)
  assert_eq(told, [1, 1])
  let first = early.read(fn() { step.get() })
  assert_true(first is Some(_))
  assert_eq(late.read(fn() { step.get() }), first)
  // it changes again: both told again
  @sffixture.fix_now(fn() { @sffixture.fix_working_now.val = ("call:2", "整理下一步") })
  assert_eq(told, [2, 2])
  assert_eq(early.read(fn() { step.get() }), Some("整理下一步"))
  assert_eq(late.read(fn() { step.get() }), Some("整理下一步"))
  // set as it was: the made-up core says it changed, what was made of it is the same, neither told
  @sffixture.fix_now(fn() { @sffixture.fix_working_now.val = ("call:2", "整理下一步") })
  assert_eq(told, [2, 2])
  early.stop()
  late.stop()
  step.dispose()
  fix_clock.val = None
}
