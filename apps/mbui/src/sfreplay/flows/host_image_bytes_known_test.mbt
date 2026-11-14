// The most bytes handed over for decodes (image_load_bytes) a Tester made in each file has its host hold at once
// (mbui's fake_host.mbt, host_image_bytes_known): a phone's Java side kept a GIF's every frame's, 140 MB of a 256 MB
// heap, and the app was killed (#5301). Counted on CI's runs of every test at every rate, 2026-11-11; each only falls:
// a change that hands over less brings its file's number down, and a file at 4096 or less leaves the list.

///|
fn init {
  @ui.host_image_bytes_known([
    ("src/sfreplay/flows/notify_off_test.mbt", 10862),
    ("src/sfreplay/flows/share_files_test.mbt", 33156),
    ("src/sfreplay/flows/share_new_chat_test.mbt", 33156),
    ("src/sfreplay/flows/video_frames_test.mbt", 26649),
    ("src/sfreplay/flows/viewer_test.mbt", 130305),
  ])
}
