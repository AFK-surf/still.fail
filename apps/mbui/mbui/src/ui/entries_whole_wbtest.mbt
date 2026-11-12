// What comes in from outside the frame's builds is each one change (as a press's handler, a tree's event or a moment
// on its timeline is): what a message's handler (messages.mbt hand_on), a build's tell (Ctx::tell) or what it says
// to do after (Ctx::after_build), both once the frame's builds are over, writes is told once all of it is written.
// What reads two things it writes sees them as they were and then as it left them, never one written and the other
// not yet.

///|
/// Two signals and what a reaction reading both saw, each pair where it differs from the one before.
fn two_seen() -> (@signals.Signal[Int], @signals.Signal[Int], Array[(Int, Int)]) {
  let a = @signals.signal(0)
  let b = @signals.signal(0)
  let seen : Array[(Int, Int)] = []
  let owner = @signals.set_owner(None)
  @signals.effect(fn() {
    let now = (a.get(), b.get())
    if seen.last() != Some(now) {
      seen.push(now)
    }
  })
  |> ignore
  @signals.set_owner(owner) |> ignore
  (a, b, seen)
}

///|
test "a message's handler writing two things: what reads both sees them before and after, never one of them written" {
  let (a, b, seen) = two_seen()
  on_message("test.two", fn(_j, _) {
    a.set(1)
    b.set(1)
  })
  let t = Tester::new(fn(c) { c.text("x") |> ignore }, w=100.0, h=100.0)
  t.post("test.two", "{}")
  t.frame(ms=0.0)
  assert_eq(seen, [(0, 0), (1, 1)])
}

///|
test "a build's tell writing two things: what reads both sees them before and after, never one of them written" {
  let (a, b, seen) = two_seen()
  let ask = Ref(false)
  let t = Tester::new(
    fn(c) {
      if ask.val {
        ask.val = false
        c.tell("two", fn() {
          a.set(1)
          b.set(1)
        })
      }
      c.text("x") |> ignore
    },
    w=100.0,
    h=100.0,
  )
  ask.val = true
  t.frame(ms=0.0)
  assert_eq(seen, [(0, 0), (1, 1)])
}

///|
test "what a build says to do after the frame's builds writing two things: what reads both sees them before and after, never one of them written" {
  let (a, b, seen) = two_seen()
  let ask = Ref(false)
  let t = Tester::new(
    fn(c) {
      if ask.val {
        ask.val = false
        c.after_build("two", fn() {
          a.set(1)
          b.set(1)
        })
      }
      c.text("x") |> ignore
    },
    w=100.0,
    h=100.0,
  )
  ask.val = true
  t.frame(ms=0.0)
  assert_eq(seen, [(0, 0), (1, 1)])
}
