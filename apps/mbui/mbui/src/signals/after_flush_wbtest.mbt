// What waits for a change told whole (after_flush): done once every effect the change set going has run, never in the
// middle of one; a batch's, once its outermost end is over; in the order asked, one at a time, what one of them sets
// told whole before the next is done; one asked while they are done, after them; none under way, at once.

///|
test "after a set: done once every effect it set going has run" {
  let a = signal(0)
  let log : Array[String] = []
  effect(fn() {
    let v = a.get()
    log.push("first \{v}")
    if v > 0 {
      after_flush(fn() { log.push("after \{a.get()}") })
    }
  })
  |> ignore
  effect(fn() { log.push("second \{a.get()}") }) |> ignore
  a.set(1)
  assert_eq(log, ["first 0", "second 0", "first 1", "second 1", "after 1"])
}

///|
test "in a batch, and one inside it: done once the outermost ends, seeing all of it" {
  let a = signal(0)
  let b = signal(0)
  let log : Array[String] = []
  effect(fn() {
    let (x, y) = (a.get(), b.get())
    if x > 0 {
      after_flush(fn() { log.push("after \{a.get()} \{b.get()}") })
    }
    log.push("run \{x} \{y}")
  })
  |> ignore
  start_batch()
  a.set(1)
  start_batch()
  b.set(2)
  end_batch()
  log.push("inner ended")
  end_batch()
  assert_eq(log, ["run 0 0", "inner ended", "run 1 2", "after 1 2"])
}

///|
test "one of them setting a signal: what that sets going runs, the rest after it in order; one asked meanwhile, last" {
  let a = signal(0)
  let c = signal(0)
  let log : Array[String] = []
  effect(fn() { log.push("c is \{c.get()}") }) |> ignore
  effect(fn() {
    if a.get() > 0 {
      after_flush(fn() {
        log.push("A")
        c.set(1)
        after_flush(fn() { log.push("D") })
        log.push("A done")
      })
      after_flush(fn() { log.push("B") })
      after_flush(fn() { log.push("C") })
    }
  })
  |> ignore
  a.set(1)
  assert_eq(log, ["c is 0", "A", "c is 1", "A done", "B", "C", "D"])
}

///|
test "none under way: done at once" {
  let log : Array[String] = []
  after_flush(fn() { log.push("now") })
  log.push("then")
  assert_eq(log, ["now", "then"])
}
