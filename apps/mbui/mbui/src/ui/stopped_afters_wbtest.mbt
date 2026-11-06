// A run stopped with what waits for its change told whole (after_flush, after_all_flushed) not yet done: in a batch, and
// in a layout holding it back (afters_held). A Tester started after it lets go what the stopped run's own steps asked
// for and what an effect of its own asked for (stopped with it), never done, neither as it begins (after the stopped
// run's tree is let go, what it would act on is no more) nor as the new run sets; what an effect kept from it asked
// for as it ran there is done as the Tester begins, as the change it told is; that effect still told, what it asks as
// it runs after done, and what the new run asks done. In this order, in one program, as a package's tests run
// (wasm-gc's: on native and LLVM moon's test driver skips a panic test, and the tests after each see nothing of it).

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
// kept across runs: as af_word, each stopped run below, as it reached its abort (what waited in it asked for)
let af_reached : Array[String] = []

///|
// kept across runs: what the second stopped run below sets in the layout it stops in
let af_held_word : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_held_word, what an effect made in the second stopped run and owned by none of it asked to
// wait for its change told whole as it ran, done (what it read then)
let af_kept_held : Array[Int] = []

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
  af_reached.push("batch")
  abort("stopped")
}

///|
test "a Tester started after a run stopped in a batch: what waited there never done, the kept effect still told" {
  af_stopped(["batch"])
  af_next() |> ignore
  af_kept_told()
}

///|
test "panic: a run stopped in a layout holding back what waits for its change told whole" {
  af_run()
  // (an effect owned by none of the run: kept)
  @signals.effect(fn() {
    let v = af_held_word.get()
    @signals.after_flush(fn() { af_kept_held.push(v) })
  })
  |> ignore
  // (an effect of the run's own, let go as a run begins, on_reset)
  let own = @signals.effect(fn() {
    if af_held_word.get() > 0 {
      @signals.after_flush(fn() { af_note("the stopped run's own effect's after_flush, held") })
    }
  })
  on_reset(own)
  @signals.afters_held(fn() {
    @signals.after_flush(fn() { af_note("after_flush, held") })
    @signals.after_all_flushed(fn() { af_note("after_all_flushed, held") })
    // (both effects run now, what they ask held back by the layout)
    af_held_word.set(1)
    af_reached.push("held")
    abort("stopped")
  })
}

///|
test "a Tester started after a run stopped in a layout holding back what waits: what a kept effect asked done, none else" {
  af_stopped(["batch", "held"])
  af_next() |> ignore
  af_kept_held_told()
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

///|
// kept across runs: what the third stopped run below sets in the layout it stops in
let af_watched : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_watched, what a watch made in the third stopped run and owned by none of it asked to wait
// for its change told whole as it was told, done
let af_kept_watch : Array[String] = []

///|
test "panic: a run stopped in a layout, a kept watch and one of its own told in it" {
  af_run()
  // (a watch owned by none of the run: kept; told, it asks to wait for the change told whole, both ways)
  let kept = @signals.watch(fn() {
    @signals.after_flush(fn() { af_kept_watch.push("after_flush") })
    @signals.after_all_flushed(fn() { af_kept_watch.push("after_all_flushed") })
  })
  kept.read(fn() { af_watched.get() }) |> ignore
  // (the run's own, let go as a run begins, on_reset)
  let own = @signals.watch(fn() {
    @signals.after_flush(fn() { af_note("the stopped run's own watch's after_flush, held") })
    @signals.after_all_flushed(fn() { af_note("the stopped run's own watch's after_all_flushed, held") })
  })
  own.read(fn() { af_watched.get() }) |> ignore
  on_reset(fn() { own.stop() })
  @signals.afters_held(fn() {
    // (both watches told now, what they ask held back by the layout)
    af_watched.set(1)
    af_reached.push("watched")
    abort("stopped")
  })
}

///|
test "a Tester started after a run stopped in a layout: what a kept watch asked as it was told done, none of its own" {
  af_stopped(["batch", "held", "watched"])
  af_next() |> ignore
  af_kept_watch_told()
}

///|
/// wasm-gc, Wasm, JS: what the watch kept from the stopped layout asked as it was told there, done as the Tester began
/// (owned by it, kept), in the order of each way
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_kept_watch_told() -> Unit raise {
  assert_eq(
    af_kept_watch,
    ["after_flush", "after_all_flushed"],
    msg="the kept watch's, asked as it was told in the stopped layout: done as the run began",
  )
}

///|
/// Native and LLVM: no stopped run here, no watch of it
#cfg(any(target="native", target="llvm"))
fn af_kept_watch_told() -> Unit raise {
  assert_eq(af_kept_watch, [])
}

///|
// kept across runs: what the fourth stopped run below's watches read and set again as they read
let af_self : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_self, what sets an effect made in the fourth stopped run going
let af_trigger : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_self, what a watch made in the fourth stopped run and owned by none of it asked as it was
// told at the end of its read (what it read set again as it read), done
let af_kept_self : Array[String] = []

///|
test "panic: a run stopped in a layout, watches told as they read what they set, one read in a kept effect" {
  af_run()
  // (a watch owned by none of the run: kept; what it reads set again as it reads: told as its read ends)
  let kept = @signals.watch(fn() {
    @signals.after_flush(fn() { af_kept_self.push("after_flush") })
    @signals.after_all_flushed(fn() { af_kept_self.push("after_all_flushed") })
  })
  // (the run's own, let go as a run begins, on_reset; read in an effect kept from the run: told as that effect runs)
  let own = @signals.watch(fn() {
    @signals.after_flush(fn() { af_note("the stopped run's own watch's after_flush, told as it read") })
    @signals.after_all_flushed(fn() { af_note("the stopped run's own watch's after_all_flushed, told as it read") })
  })
  on_reset(fn() { own.stop() })
  @signals.effect(fn() {
    if af_trigger.get() > 0 {
      own.read(fn() { af_self.set(af_self.get() + 1) }) |> ignore
    }
  })
  |> ignore
  @signals.afters_held(fn() {
    kept.read(fn() { af_self.set(af_self.get() + 1) }) |> ignore
    af_trigger.set(1)
    af_reached.push("told as read")
    abort("stopped")
  })
}

///|
test "a Tester started after a run stopped in a layout: what a kept watch asked as its read ended done, none of its own" {
  af_stopped(["batch", "held", "watched", "told as read"])
  af_next() |> ignore
  af_kept_self_told()
}

///|
/// wasm-gc, Wasm, JS: what the watch kept from the stopped layout asked as its read there ended, done as the Tester
/// began (its own, kept), in the order of each way
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_kept_self_told() -> Unit raise {
  assert_eq(
    af_kept_self,
    ["after_flush", "after_all_flushed"],
    msg="the kept watch's, asked as its read in the stopped layout ended: done as the run began",
  )
}

///|
/// Native and LLVM: no stopped run here, no watch of it
#cfg(any(target="native", target="llvm"))
fn af_kept_self_told() -> Unit raise {
  assert_eq(af_kept_self, [])
}

///|
/// wasm-gc, Wasm, JS: each stopped run before, reached as far as its abort (what waited in it asked for), in order
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_stopped(runs : Array[String]) -> Unit raise {
  assert_eq(af_reached, runs, msg="the stopped runs before this, each as far as its abort")
}

///|
/// Native and LLVM: no stopped run here
#cfg(any(target="native", target="llvm"))
fn af_stopped(_runs : Array[String]) -> Unit raise {
  assert_eq(af_reached, [])
}

///|
/// wasm-gc, Wasm, JS: what the effect kept from the stopped layout asked as it was made, done then; what it asked as it
/// ran in the layout, done as the Tester began (owned by it, kept); what it asks after, done
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_kept_held_told() -> Unit raise {
  assert_eq(af_kept_held, [0, 1], msg="the kept effect's, asked in the stopped layout: done as the run began")
  af_held_word.set(2)
  assert_eq(af_kept_held, [0, 1, 2], msg="and as it runs after")
}

///|
/// Native and LLVM: no stopped run here, no effect of it
#cfg(any(target="native", target="llvm"))
fn af_kept_held_told() -> Unit raise {
  assert_eq(af_kept_held, [])
}

///|
// kept across runs: what sets an effect made in the fifth stopped run below and owned by none of it going (that
// effect sets what the run's watches read)
let af_go : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_go, what sets an effect of the fifth stopped run's own going (it sets the same)
let af_go_own : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_go, what the fifth stopped run's watches read, set by those effects as they run
let af_set_in : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_go, what those watches read as they are told
let af_probe : @signals.Signal[Int] = @signals.signal(0)

///|
// kept across runs: as af_go, which of those effects set what the watches read, as it sets it
let af_setter : Ref[String] = Ref("")

///|
// kept across runs: as af_go, each run of the kept effect
let af_go_runs : Ref[Int] = Ref(0)

///|
// kept across runs: as af_go, what a watch made in the fifth stopped run and owned by none of it asked as it was told
// (in the run of the effect that set what it read), done: which way, and which effect set it
let af_kept_set_in : Array[String] = []

///|
test "panic: a run stopped in a layout, watches told as an effect running sets what they read" {
  af_run()
  // (a watch owned by none of the run: kept; told, it asks to wait for the change told whole, both ways, and reads)
  let kept = @signals.watch(fn() {
    let by = af_setter.val
    @signals.after_flush(fn() { af_kept_set_in.push("after_flush, set by the \{by}") })
    @signals.after_all_flushed(fn() { af_kept_set_in.push("after_all_flushed, set by the \{by}") })
    af_probe.get() |> ignore
  })
  // (the run's own, let go as a run begins, on_reset)
  let own = @signals.watch(fn() {
    let by = af_setter.val
    @signals.after_flush(fn() { af_note("the stopped run's own watch's after_flush, set by the \{by}") })
    @signals.after_all_flushed(fn() { af_note("the stopped run's own watch's after_all_flushed, set by the \{by}") })
    af_probe.get() |> ignore
  })
  on_reset(fn() { own.stop() })
  let read = fn() {
    kept.read(fn() { af_set_in.get() }) |> ignore
    own.read(fn() { af_set_in.get() }) |> ignore
  }
  // (an effect owned by none of the run, kept; one of the run's own, on_reset: each, set going, sets what the watches
  // read, as it runs: they are told there and then, in a flush inside its run)
  @signals.effect(fn() {
    af_go_runs.val += 1
    if af_go.get() > 0 {
      af_setter.val = "kept effect"
      af_set_in.set(af_go.get())
    }
  })
  |> ignore
  let own_effect = @signals.effect(fn() {
    if af_go_own.get() > 0 {
      af_setter.val = "stopped run's own effect"
      af_set_in.set(100 + af_go_own.get())
    }
  })
  on_reset(own_effect)
  @signals.afters_held(fn() {
    read()
    af_go.set(1)
    read()
    af_go_own.set(1)
    af_reached.push("told in an effect's set")
    abort("stopped")
  })
}

///|
test "a Tester started after a run stopped in a layout: what a kept watch asked as an effect's set told it done, none of its own" {
  af_stopped(["batch", "held", "watched", "told as read", "told in an effect's set"])
  af_next() |> ignore
  af_kept_set_in_told()
}

///|
/// wasm-gc, Wasm, JS: what the watch kept from the stopped layout asked as each effect's set told it there, done as
/// the Tester began (its own, kept, whichever effect set it), in the order of each way; what it read as it was told
/// followed by neither effect (the kept one not run again as it is set)
#cfg(any(target="wasm-gc", target="wasm", target="js"))
fn af_kept_set_in_told() -> Unit raise {
  assert_eq(
    af_kept_set_in,
    [
      "after_flush, set by the kept effect", "after_flush, set by the stopped run's own effect", "after_all_flushed, set by the kept effect",
      "after_all_flushed, set by the stopped run's own effect",
    ],
    msg="the kept watch's, asked as an effect's set told it in the stopped layout: done as the run began",
  )
  let runs = af_go_runs.val
  af_probe.set(1)
  assert_eq(af_go_runs.val, runs, msg="what the watches read as they were told: not followed by the effect that set what they read")
}

///|
/// Native and LLVM: no stopped run here, no watch of it
#cfg(any(target="native", target="llvm"))
fn af_kept_set_in_told() -> Unit raise {
  assert_eq(af_kept_set_in, [])
  assert_eq(af_go_runs.val, 0)
}
