///|
/// No run at a frame rate here (test_frames_between, tester_fps.mbt): a Wasm program run by mbui's native shell (a
/// bench, scripts/instrbench.sh), whose shell gives it no environment of its own to read, as fps_check.sh's runs are
/// native and wasm-gc ones.
fn test_frames_between() -> Double {
  0.0
}

///|
/// (none either: test_motion_judged, tester_fps.mbt)
fn test_motion_judged(_loc : String) -> MotionJudged {
  Results
}

///|
/// (looked at, as the default: test_corners_looked, tester_fps.mbt; a bench says not, Tester::corners_look)
fn test_corners_looked() -> Bool {
  true
}

///|
/// (no run that counts or judges how what moves goes here either: motion_runs, tester_fps.mbt)
fn motion_runs() -> Bool {
  false
}

///|
/// (none said: motion_bars_said, tester_fps.mbt)
fn motion_bars_said(_check : String, _bars : Array[(String, Int)]) -> Unit {
  ()
}

///|
/// (none said: motion_known_said, tester_fps.mbt)
fn motion_known_said(_check : String, _file : String, _n : Int, _bar : Int, _what : String) -> Unit {
  ()
}
