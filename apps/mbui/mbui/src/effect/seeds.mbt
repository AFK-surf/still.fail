///|
/// The seeds a simulated test runs: 1 to `count`, or only `SEED` when the
/// environment says one (a failure names its seed; `SEED=<n>` replays it).
pub fn seeds(count? : Int = 20) -> Array[Int] {
  match @env.get_env_var("SEED") {
    Some(s) if s != "" =>
      try [@string.parse_int(s)] catch {
        _ => abort("SEED is no number: \{s}")
      }
    _ => Array::makei(count, i => i + 1)
  }
}

///|
/// Runs `run` once per seed (`seeds`); a failure says its seed and how to
/// replay it.
pub fn for_seeds(count? : Int = 20, run : (Int) -> Unit raise) -> Unit raise {
  for s in seeds(count~) {
    run(s) catch {
      e => fail("seed \{s}: \{e}\n  replay: SEED=\{s} (the same run, step for step)")
    }
  }
}
