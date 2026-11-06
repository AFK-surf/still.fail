// A run stopped inside a batch with what its tree made told in it and not yet run (a node's fill read what the batch
// set: its watch told; a watch of the run's, let go as a run begins, on_reset, told too): a Tester started after it
// lets the stopped run's go before it runs what was told, so none of it runs in the new run, nor after as what it
// read is set again; what the new run makes is told as it is set. In this order, in one program, as a package's tests
// run (wasm-gc's: on native and LLVM moon's test driver skips a panic test, and the second below sees nothing of it).

///|
// kept across runs: what the first test below makes, the next one reads
let tree_word : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as tree_word, each fill of the stopped run's node, what it read
let tree_fills : Array[Int] = []

///|
// kept across runs: as tree_word, the stopped run's node
let tree_made : Ref[Made?] = Ref(None)

///|
// kept across runs: as tree_word, each time the stopped run's own watch was told, what it read
let tree_told : Array[Int] = []

///|
// kept across runs: as tree_word, what an effect made in the stopped run and owned by none of it read, each time it ran
let kept_runs : Array[Int] = []

///|
test "panic: a run stopped in a batch, its tree's watches told in it" {
  let t = Tester::new(
    fn(c) {
      c.made("word", fn() {
        made_box(fn(c) {
          tree_fills.push(tree_word.get())
          c.text("word \{tree_word.get()}") |> ignore
        })
      })
    },
    w=200.0,
    h=100.0,
  )
  t.draw()
  for _, m in made_roots {
    tree_made.val = Some(m)
  }
  // (a watch of the run's own, let go as a run begins: as a package over ui keeps one, on_reset)
  let w = @signals.watch(fn() { tree_told.push(tree_word.get()) })
  w.read(fn() { tree_word.get() }) |> ignore
  on_reset(fn() { w.stop() })
  // (an effect made in it and owned by none of it: kept)
  @signals.effect(fn() { kept_runs.push(tree_word.get()) }) |> ignore
  @signals.start_batch()
  tree_word.set(1)
  abort("stopped")
}

///|
test "a Tester started after a run stopped in a batch lets its tree go before what was told runs: none of it runs" {
  let fills = tree_fills.length()
  let t = Tester::new(fn(c) { c.text("new") |> ignore }, w=200.0, h=100.0)
  stopped_tree_let_go()
  // (what was told of the stopped run's own: let go before it ran)
  assert_eq(tree_told, [], msg="the stopped run's own watch: let go before it was told")
  assert_false(nodes_run.told, msg="nothing of the stopped run's tree told in the new run")
  kept_told()
  t.draw()
  assert_eq(tree_fills.length(), fills)
  // (what it read set again: nothing of it told)
  tree_word.set(2)
  assert_eq(tree_told, [])
  kept_told_again()
  assert_false(nodes_run.told)
  assert_eq(tree_fills.length(), fills)
  // (what the new run makes, told as it is set)
  let n = @signals.signal(0)
  let seen = Ref(-1)
  let stop = @signals.effect(fn() { seen.val = n.get() })
  n.set(1)
  assert_eq(seen.val, 1)
  stop()
  t.draw()
  assert_true(t.find("new") is Some(_))
}

///|
/// Where moon's test driver runs a panic test in the program of the others (wasm-gc, as run here; Wasm and JS by its
/// driver): the stopped run's node drawn once, its watch let go as the Tester began.
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn stopped_tree_let_go() -> Unit raise {
  assert_eq(tree_fills, [0], msg="the stopped run's node filled once, as it was drawn")
  assert_true(tree_made.val.unwrap().watch.gone(), msg="its watch let go")
}

///|
/// Native and LLVM: moon's test driver skips a panic test there (MOONBIT_TEST_DRIVER_INTERNAL_IS_NATIVE): no stopped
/// run here, nothing of it made.
#cfg(any(target="native", target="llvm"))
fn stopped_tree_let_go() -> Unit raise {
  assert_eq(tree_fills, [])
  assert_true(tree_made.val is None)
}

///|
/// wasm-gc, Wasm, JS: the effect kept from the stopped run, made before its batch, ran as it was made and as the
/// Tester began (what the batch set), and runs as what it read is set after.
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn kept_told() -> Unit raise {
  assert_eq(kept_runs, [0, 1], msg="the kept effect: run as made, then what the stopped batch set")
}

///|
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn kept_told_again() -> Unit raise {
  assert_eq(kept_runs, [0, 1, 2], msg="the kept effect: told as what it read is set after")
}

///|
/// Native and LLVM: no stopped run here, no effect of it.
#cfg(any(target="native", target="llvm"))
fn kept_told() -> Unit raise {
  assert_eq(kept_runs, [])
}

///|
#cfg(any(target="native", target="llvm"))
fn kept_told_again() -> Unit raise {
  assert_eq(kept_runs, [])
}
