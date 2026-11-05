///|
test "batches closed by independent watchers finish before the next queued watcher runs" {
  let value = signal(0)
  let nested = Ref(0)
  let deepest = Ref(0)
  let completed = Ref(0)
  let watches : Array[Watch] = []
  for _ in 0..<32 {
    let w = watch(fn() {
      nested.val += 1
      if nested.val > deepest.val { deepest.val = nested.val }
      start_batch()
      end_batch()
      nested.val -= 1
      completed.val += 1
    })
    w.read(fn() { value.get() }) |> ignore
    watches.push(w)
  }
  defer { for w in watches { w.stop() } }
  value.set(1)
  assert_eq(completed.val, 32)
  assert_eq(deepest.val, 1)
}
