// Every run kept in this package (textrec_NAME.mbt), by its name: what MBUI_TEXTCHECK=NAME asks the host's
// text system again (textcheck.mbt). Made by scripts/textrec_test.py: not edited by hand.

///|
fn kept_run(name : String) -> String? {
  match name {
    "android_controls" => Some(run_android_controls)
    "drive_controls" => Some(run_drive_controls)
    "mini1_controls" => Some(run_mini1_controls)
    "mini1_disclosure" => Some(run_mini1_disclosure)
    "mini1_foundation" => Some(run_mini1_foundation)
    "mini1_menus" => Some(run_mini1_menus)
    "mini1_overlays" => Some(run_mini1_overlays)
    "web_controls" => Some(run_web_controls)
    "windows_controls" => Some(run_windows_controls)
    _ => None
  }
}
