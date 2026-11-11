// What a classic Wasm program runs, counted (the user, 2026-11-09: each kind of instruction apart, as each costs
// differently on each machine; numbers to weigh, never a verdict):
//
//   wasmgas profile IN.wasm OUT.wasm [APART...] [focus=NAME | callers=NAME]
//                                         IN made to count, every instruction it runs, by function and by kind
//                                         (profile.mbt says how); run as a bench by mbui's wasm shell with
//                                         MBUI_PROFILE_FILE (src/host/wasm_shell.c), the counts of each measured
//                                         frame written there. The functions whose names begin with one of APART (a
//                                         test's own: its stand-in for the host, what a device's host does in its own
//                                         code; its driver looking for what is on screen) counted apart, each call of
//                                         one of them one call of the host's. With focus=NAME, each function's
//                                         "all inside its calls" is what it ran where NAME called it itself (NAME's
//                                         calls looked into, a level at a time); with callers=NAME, what NAME ran
//                                         where each function called it itself
//   wasmgas report PROGRAM PROFILE [TOP]  that file said: a frame's instructions, each kind's and weighted, the TOP
//                                         functions (20) by their own and by all their calls ran; PROGRAM (as profiled
//                                         or before) names them
//   wasmgas compare PROGRAM_A PROFILE_A PROGRAM_B PROFILE_B [TOP]
//                                         two runs side by side, A before and B after: each kind's change and weighted,
//                                         the TOP functions whose own count changed the most (by their names)
//
// still.fail's scripts/instrbench.sh builds its scenes' program, profiles it, runs it and reports.

///|
fn top_of(args : ArrayView[String]) -> Int {
  match args {
    [t] => number(t).to_int()
    [] => 20
    _ => fail("TOP: a number")
  }
}

///|
fn main {
  let args = @env.args()[1:].to_owned()
  match args {
    ["profile", input, output, .. rest] => {
      // (focus=NAME: what each function ran where NAME called it itself, as its "all inside its calls"; callers=NAME:
      // what NAME ran where each called it itself)
      let looked = fn(a : String) { a.has_prefix("focus=") || a.has_prefix("callers=") }
      let (focus, callers) = match rest.iter().find_first(looked) {
        Some(a) if a.has_prefix("focus=") => (a.exact_view(start=6).to_owned(), false)
        Some(a) => (a.exact_view(start=8).to_owned(), true)
        None => ("", false)
      }
      let rest : Array[String] = rest.iter().filter(fn(a) { !looked(a) }).collect()
      let apart = fn(name : String) { rest.iter().any(fn(prefix) { name.has_prefix(prefix) }) }
      let data = match @sys.read_bytes(input) {
        Some(d) => d
        None => fail("\{input}: cannot be read")
      }
      if !@sys.write_bytes(output, profile(data, apart, focus~, callers~)) {
        fail("\{output}: cannot be written")
      }
    }
    ["report", program, prof, .. rest] => report(read_run(program, prof), top_of(rest))
    ["compare", pa, fa, pb, fb, .. rest] =>
      compare(read_run(pa, fa), read_run(pb, fb), top_of(rest))
    _ =>
      fail(
        "profile IN.wasm OUT.wasm [APART...] | report PROGRAM PROFILE [TOP] | compare PROGRAM_A PROFILE_A PROGRAM_B PROFILE_B [TOP]",
      )
  }
  @sys.exit(0)
}
