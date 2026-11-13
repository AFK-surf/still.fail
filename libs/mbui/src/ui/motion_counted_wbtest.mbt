// The files whose Testers still show faults of how what moves goes at 60 and 120 a second (mbui's tester.mbt,
// motion_counted: what CI's runs count, `scripts/motion_said.sh`): only counted there; every other file is judged, a
// fault failing its test. Only shrinks: a file mended to none leaves the list.

///|
fn init {
  motion_counted([
    "src/ui/layout_wbtest.mbt",
    "src/ui/list_retained_paint_wbtest.mbt",
    "src/ui/old_gives_wbtest.mbt",
    "src/ui/scroll_node_wbtest.mbt",
  ])
}
