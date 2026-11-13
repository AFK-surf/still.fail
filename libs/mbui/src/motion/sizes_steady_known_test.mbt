// What draws and still steps or jolts in these tests (mbui's sizes_steady.mbt: a height or a place in one frame, a
// speed off the frames round it, a dead stop, a turn back again soon), a file at a time: how many a Tester made in
// it may show. Each only falls: a jolt mended takes its file's number down, and a file at 0 leaves the list.

///|
fn init {
  @ui.sizes_steady_known([
    ("src/motion/list_part_test.mbt", 6),
    ("src/motion/motion_test.mbt", 1),
  ])
}
