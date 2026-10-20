// The gallery's own state (what its live controls keep: controls.mbt and the other pages) as the app starts with it:
// a kept run's test starts from it (textrec_NAME_wbtest.mbt), as the host's run did, whatever a test before it tapped.
// detlint's `globals` (src/kitdemo is among its roots) fails a global this does not put back.

///|
fn reset() -> Unit {
  sw_on.val = true
  view_check_view.val = None
  view_check_page.val = None
  cb.val = On
  size.val = "m"
  bold.val = true
  align.val = ["left"]
  marks.val = ["b", "u"]
  level.val = 40.0
  shown.val = false
  for h in 0..<2 {
    folds[h] = ["b"]
    more[h] = false
    tab[h] = "account"
    tried[h] = false
    fruit[h] = ""
    bookmarks[h] = true
    file_open[h] = false
    dialog_open[h] = false
    alert_open[h] = false
    pop_open[h] = false
    toasts[h] = []
  }
  toasts_made.val = 0
  opened_env.val = false
  text_checked.val = false
  marks_job.val = None
  marks_started.val = false
}
