///|
/// How far apart the frames run_for draws on its way are (ms), or 0, none (run_for goes straight to its end, the
/// default): MBUI_TEST_FPS (frames a second) that rate's, a run of the tests at a frame rate, which must come out the
/// same (scripts/fps_check.sh). The test program's own environment, not the app's (the fake host's, a Tester's `env`):
/// asked of the fake, it was never set, and every run at a frame rate went straight to its ends as the default's did.
fn test_frames_between() -> Double {
  let fps = @env.get_env_var("MBUI_TEST_FPS").unwrap_or("")
  match (try Some(@json.parse(fps)) catch { _ => None }) {
    Some(Number(n, ..)) if n > 0.0 => 1000.0 / n
    _ => 0.0
  }
}
