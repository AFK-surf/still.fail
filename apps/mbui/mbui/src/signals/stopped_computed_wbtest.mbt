// A run stopped in a computed's getter, worked out for an effect reading it: what it was worked out for (asked_for,
// what its getter asks for is asked by) left as the getter stopped, never put back; a run beginning
// (reset_globals) puts it back, nothing of the stopped run held by it. In this order, in one program, as a package's
// tests run (wasm-gc's: on native and LLVM moon's test driver skips a panic test, and the second sees nothing of it).

///|
// kept across runs: whether the stopped run's getter was worked out, as far as its abort
let stopped_getter : Ref[Bool] = Ref(false)

///|
test "panic: a run stopped in a computed's getter, worked out for an effect reading it" {
  let c : Computed[Int] = computed(fn(_) {
    stopped_getter.val = true
    abort("stopped")
  })
  effect(fn() { c.get() |> ignore }) |> ignore
}

///|
test "a run beginning after a run stopped in a computed's getter: what it was worked out for put back" {
  getter_stopped()
  reset_globals()
  run_told()
  assert_true(run.asked_for is None, msg="what the stopped getter was worked out for: put back as a run begins")
  // (a computed worked out in the new run, for nothing reading: what its getter asks done, by none)
  let done : Array[Int] = []
  let n = signal(0)
  let c = computed(fn(_) {
    let v = n.get()
    after_flush(fn() { done.push(v) })
    v
  })
  start_batch()
  c.get() |> ignore
  end_batch()
  assert_eq(done, [0])
  assert_true(run.asked_for is None)
}

///|
/// wasm-gc, Wasm, JS: the stopped run's getter worked out as far as its abort, for the effect reading it, left so
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn getter_stopped() -> Unit raise {
  assert_true(stopped_getter.val, msg="the stopped run's getter: worked out as far as its abort")
  assert_true(run.asked_for is Some(_), msg="what it was worked out for: left as it stopped")
}

///|
/// Native and LLVM: no stopped run here
#cfg(any(target="native", target="llvm"))
fn getter_stopped() -> Unit raise {
  assert_false(stopped_getter.val)
  assert_true(run.asked_for is None)
}
