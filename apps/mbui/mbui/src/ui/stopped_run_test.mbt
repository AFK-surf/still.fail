// A run stopped inside a batch by an abort (what a test that expects it does), the batch never ended, and one stopped
// in a layout under way: a Tester started after them runs what the batch told, and tells each set as it is set, to what
// is made after it and to what was made before it and kept (@signals.reset_globals, as a run begins). In this order,
// in one program, as a package's tests run.

///|
// kept across runs: what the first test below makes, the next one reads (a signal and an effect a stopped run leaves)
let kept : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as kept
let kept_seen : Ref[Int] = Ref(-1)

///|
test "panic: a run stopped inside a batch, what it set told and not yet run" {
  @signals.effect(fn() { kept_seen.val = kept.get() }) |> ignore
  @signals.start_batch()
  kept.set(1)
  abort("stopped")
}

///|
// (here, not in view's tests: what it stops, a layout under way, is put back only as a run begins, a Tester's; a view
// test after it would run in it)
test "panic: a tree made in a layout box's callback reads under that layout's guard" {
  let on = @signals.signal(true)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page
      .width(Is(Some(100.0)))
      .height(Is(Some(100.0)))
      .layout_box(Is(()), fn(_l, _) {
        let inner = @view.Tree::new(fn(_r) {  })
        inner.dispose()
        on.get() |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(100.0, 100.0) |> ignore
}

///|
test "a Tester started after a run stopped in a batch runs what it told, then tells each set as it is set" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0)
  // (what was made before, told in the batch: run as the run begins)
  kept_still_told()
  // (what is made now)
  let n = @signals.signal(0)
  let seen = Ref(-1)
  let stop = @signals.effect(fn() { seen.val = n.get() })
  n.set(1)
  assert_eq(seen.val, 1)
  stop()
  t.draw()
}

///|
/// Where moon's test driver runs a panic test in the program of the others (wasm-gc, as run here; Wasm and JS by its
/// driver, a panic test not skipped there and each test called in turn in one instance or process): the batch the
/// first test stopped in is this program's, and kept's effect, made there, sees what it set once a run begins, and each
/// set after.
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn kept_still_told() -> Unit raise {
  assert_eq(kept_seen.val, 1, msg="kept's effect: what the stopped batch set, run as the run begins")
  kept.set(2)
  assert_eq(kept_seen.val, 2, msg="kept's effect: told as kept is set after")
}

///|
/// Native and LLVM: moon's test driver skips a panic test there (MOONBIT_TEST_DRIVER_INTERNAL_IS_NATIVE): no stopped
/// run here, kept's effect never made, nothing of it to see.
#cfg(any(target="native", target="llvm"))
fn kept_still_told() -> Unit raise {
  assert_eq(kept_seen.val, -1)
}
