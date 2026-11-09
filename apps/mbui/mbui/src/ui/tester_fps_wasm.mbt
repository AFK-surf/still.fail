///|
/// No run at a frame rate here (test_frames_between, tester_fps.mbt): a Wasm program run by mbui's native shell (a
/// bench, scripts/instrbench.sh), whose shell gives it no environment of its own to read, as fps_check.sh's runs are
/// native and wasm-gc ones.
fn test_frames_between() -> Double {
  0.0
}
