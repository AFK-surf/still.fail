// The most bytes handed over for decodes (image_load_bytes) a Tester made in each file has its host hold at once
// (mbui's fake_host.mbt, host_image_bytes_known): a phone's Java side kept a GIF's every frame's, 140 MB of a 256 MB
// heap, and the app was killed (#5301). Counted on CI's runs of every test at every rate, 2026-11-11; each only falls:
// a change that hands over less brings its file's number down, and a file at 4096 or less leaves the list.

///|
fn init {
  @ui.host_image_bytes_known([
    ("src/sfpages/peek_pictures_wbtest.mbt", 89156),
    ("src/sfpages/peeks_file_node_wbtest.mbt", 31398),
    ("src/sfpages/screen_wbtest.mbt", 58572),
    ("src/sfpages/settings_rig_wbtest.mbt", 10862),
  ])
}
