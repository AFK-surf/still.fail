// The files whose Testers still show faults of how what moves goes at 60 and 120 a second (mbui's tester.mbt,
// motion_counted: what CI's runs count, `scripts/motion_said.sh`): only counted there; every other file is judged, a
// fault failing its test. Only shrinks: a file mended to none leaves the list.

///|
fn init {
  @ui.motion_counted([
    "src/motion/motion_test.mbt",
  ])
}
