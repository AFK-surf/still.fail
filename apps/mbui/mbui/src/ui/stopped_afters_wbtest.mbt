// A run stopped with what waits for its change told whole (after_flush, after_all_flushed) not yet done: in a batch, and
// in a layout holding it back (afters_held). A Tester started after it lets that go with the stopped run, never done,
// neither as it begins (after the stopped run's tree is let go, what it would act on is no more) nor as the new run
// sets; an effect kept from the stopped run still told, what it asks to wait as it runs done, and what the new run asks
// done. In this order, in one program, as a package's tests run (wasm-gc's: on native and LLVM moon's test driver skips
// a panic test, and the tests after each see nothing of it).

///|
// kept across runs: what the stopped runs below read and set, the runs after them set
let af_word : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_word, the node each stopped run below made
let af_made : Ref[Made?] = Ref(None)

///|
// kept across runs: as af_word, what waited in each stopped run when it was done, and whether its node was let go then
let af_done : Array[String] = []

///|
// kept across runs: as af_word, what an effect made in the first stopped run and owned by none of it read, each time
// it ran
let af_kept : Array[Int] = []

///|
// kept across runs: as af_kept, what that effect asked to wait for its change told whole as it ran, done
let af_kept_after : Array[Int] = []

///|
fn af_note(what : String) -> Unit {
  let gone = match af_made.val {
    Some(m) => m.watch.gone()
    None => false
  }
  af_done.push("\{what} (its node let go: \{gone})")
}

///|
/// A Tester whose node reads af_word, drawn
fn af_run() -> Unit {
  let t = Tester::new(
    fn(c) {
      c.made("af", fn() { made_box(fn(c) { c.text("af \{af_word.get()}") |> ignore }) })
    },
    w=200.0,
    h=100.0,
  )
  t.draw()
  for _, m in made_roots {
    af_made.val = Some(m)
  }
}

///|
/// A Tester started after a stopped run: nothing of what waited in it done, as it begins or as the new run sets; what
/// the new run asks to wait done as its change is told whole
fn af_next() -> Tester raise {
  let t = Tester::new(fn(c) { c.text("new") |> ignore }, w=200.0, h=100.0)
  assert_eq(af_done, [], msg="what waited in the stopped run: let go with it, not done as a run begins")
  t.draw()
  af_word.set(af_word.get() + 10)
  assert_eq(af_done, [], msg="nor as the new run sets")
  let mine : Array[String] = []
  @signals.start_batch()
  @signals.after_flush(fn() { mine.push("after") })
  @signals.after_all_flushed(fn() { mine.push("last") })
  af_word.set(af_word.get() + 1)
  @signals.end_batch()
  assert_eq(mine, ["after", "last"], msg="what the new run asks: done as its change is told whole")
  assert_eq(af_done, [])
  t.draw()
  assert_true(t.find("new") is Some(_))
  t
}

///|
test "panic: a run stopped in a batch, with what waits for its change told whole" {
  af_run()
  @signals.effect(fn() {
    let v = af_word.get()
    af_kept.push(v)
    @signals.after_flush(fn() { af_kept_after.push(v) })
  })
  |> ignore
  @signals.start_batch()
  @signals.after_flush(fn() { af_note("after_flush") })
  @signals.after_all_flushed(fn() { af_note("after_all_flushed") })
  af_word.set(1)
  abort("stopped")
}

///|
test "a Tester started after a run stopped in a batch: what waited there never done, the kept effect still told" {
  af_next() |> ignore
  af_kept_told()
}

///|
test "panic: a run stopped in a layout holding back what waits for its change told whole" {
  af_run()
  @signals.afters_held(fn() {
    @signals.after_flush(fn() { af_note("after_flush, held") })
    @signals.after_all_flushed(fn() { af_note("after_all_flushed, held") })
    abort("stopped")
  })
}

///|
test "a Tester started after a run stopped in a layout holding back what waits: none of it done" {
  af_next() |> ignore
}

///|
/// Where moon's test driver runs a panic test in the program of the others (wasm-gc, as run here; Wasm and JS by its
/// driver): the effect kept from the stopped run ran as it was made, as the Tester began (what the batch set), and as
/// af_word was set twice after; what it asked to wait each time, done.
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_kept_told() -> Unit raise {
  assert_eq(af_kept, [0, 1, 11, 12], msg="the kept effect: run as made, then what the stopped batch set, then each set")
  assert_eq(af_kept_after, [0, 1, 11, 12], msg="what it asked to wait as it ran: done each time")
}

///|
/// Native and LLVM: moon's test driver skips a panic test there (MOONBIT_TEST_DRIVER_INTERNAL_IS_NATIVE): no stopped
/// run here, no effect of it.
#cfg(any(target="native", target="llvm"))
fn af_kept_told() -> Unit raise {
  assert_eq(af_kept, [])
  assert_eq(af_kept_after, [])
}
