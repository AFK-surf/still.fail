// What a made-up core answers at once (a fixture's call, a replay's kept answer) as a computed works its value out (a
// page's read that asked the core: the client's chats.window before a chat's topic) is given once that read is over,
// as a device's core is heard only between what the app runs (answered_from_outside, @signals.after_computing). Given
// in the getter, what it told (outside_said) ran what reads that computed, which read it again half made: alien-signals'
// unwrap of nothing, silent on wasm-gc, the batch and the read left open (a sweep's 已归档 press on the screens' round,
// 2026-11-14).

///|
/// How long the test runs before it reads, and after (past what a frame drawn for it needs, at the slowest rate).
let read_before : Double = 100.0

///|
let read_after : Double = 400.0

///|
test "a made-up core answering as a getter runs: given once the read is over, nothing read half made, at any rate" {
  let answer : @signals.Signal[String] = @signals.signal("asking")
  let asked = Ref(false)
  let working = Ref(false)
  let given_while_working = Ref(false)
  // (a page's read: asks the made-up core the first time it is worked out, which answers at once)
  let read : @signals.Computed[String] = @signals.computed(fn(_) {
    working.val = true
    if !asked.val {
      asked.val = true
      answered_from_outside(fn() {
        given_while_working.val = working.val
        answer.set("told")
      })
    }
    working.val = false
    "read"
  })
  let t = Tester::new(fn(_c) {  })
  set_view_app(fn(root) { root.box(fn(n) { n.words(By(fn() { answer.get() })) |> ignore }) |> ignore })
  t.run_for(read_before)
  assert_true(t.find("asking") is Some(_))
  // (what reads it again as anything comes from outside, as sfapp's check of its first page did)
  let armed = Ref(false)
  let reread : Array[String] = []
  let stop = @signals.effect(fn() {
    outside_said.get() |> ignore
    if armed.val {
      reread.push(read.get())
    }
  })
  armed.val = true
  let events = outside_events.val
  // read between frames, as the first page's check reads
  assert_eq(@signals.untracked(fn() { read.get() }), "read")
  // given after the getter, not in it: told once, what reads it reading it whole
  assert_false(given_while_working.val)
  assert_eq(outside_events.val, events + 1)
  assert_eq(reread, ["read"])
  assert_eq(answer.get(), "told")
  assert_eq(@signals.batch_depth(), 0)
  t.run_for(read_after)
  assert_true(t.find("told") is Some(_))
  stop()
  t.assert_idle()
}

///|
test "a made-up core answering outside any getter: given at once, as before" {
  let given = Ref(false)
  let events = outside_events.val
  answered_from_outside(fn() { given.val = true })
  assert_true(given.val)
  assert_eq(outside_events.val, events + 1)
  // (one whose answer changes only signals: given, nothing told from outside)
  answered_from_outside(fn() {  }, told=false)
  assert_eq(outside_events.val, events + 1)
}
