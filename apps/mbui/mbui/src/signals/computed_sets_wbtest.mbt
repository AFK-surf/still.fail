// A computed whose getter sets a signal as it is worked out (its own bookkeeping: what changed since it was last read,
// taken): what that set tells runs once the computed is worked out, never in the middle of it, so that what follows the
// computed sees it changed (2026-11-05: a chat's page's list, following a chat's view kept as a computed, was told the
// view had not changed as the core's answer came, run while the view was being worked out, and never told again).

///|
test "a computed that sets a signal as it is worked out: what follows it is told it changed, whoever read it first" {
  let s = signal(0)
  let taken = signal(0)
  let c = computed(fn(_) {
    let v = s.get()
    // (its bookkeeping, set as it is worked out)
    taken.set(v)
    v
  })
  // (one that reads it first, as the queue has it: what works it out again)
  let first : Ref[Int] = Ref(-1)
  let stop_first = effect(fn() { first.val = c.get() })
  // (one that follows what it set)
  let bookkept : Ref[Int] = Ref(-1)
  let stop_kept = effect(fn() { bookkept.val = taken.get() })
  // (and one that follows it after: told as it changes)
  let seen : Ref[Int] = Ref(-1)
  let stop_seen = effect(fn() { seen.val = c.get() })
  s.set(1)
  assert_eq((first.val, bookkept.val, seen.val), (1, 1, 1))
  s.set(2)
  assert_eq((first.val, bookkept.val, seen.val), (2, 2, 2))
  stop_first()
  stop_kept()
  stop_seen()
}

///|
test "the same with watches, as the window's tree reads: each told, read again, sees it changed" {
  let s = signal(0)
  let taken = signal(0)
  let c = computed(fn(_) {
    let v = s.get()
    taken.set(v)
    v
  })
  let seen : Array[Int] = [-1, -1]
  let ws : Array[Watch] = []
  for k in 0..<2 {
    let w = watch(fn() { seen[k] = ws[k].read(fn() { c.get() }) })
    ws.push(w)
    seen[k] = w.read(fn() { c.get() })
  }
  let kept = watch(fn() {  })
  kept.read(fn() { taken.get() }) |> ignore
  s.set(1)
  assert_eq(seen, [1, 1])
  s.set(2)
  assert_eq(seen, [2, 2])
  for w in ws {
    w.stop()
  }
  kept.stop()
}
