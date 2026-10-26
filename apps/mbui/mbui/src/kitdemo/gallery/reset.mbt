// The gallery's own state (what its live controls keep: controls.mbt and the other pages) as the app starts with it:
// a kept run's test starts from it (textrec_NAME_wbtest.mbt), as the host's run did, whatever a test before it tapped.
// detlint's `globals` (src/kitdemo is among its roots) fails a global this does not put back.

///|
fn reset() -> Unit {
  sw_on.val = true
  view_check_view.val = None
  view_check_placed.val = false
  view_check_page.val = None
  view_check_tall.val = None
  view_check_grow.val = None
  view_check_grown.val = false
  site_check_view.val = None
  site_check_page.val = None
  site_check_events.val = None
  site_check_grabbing.val = false
  update_check_asked.val = false
  update_check_said.val = ""
  link_check_ready.val = false
  notice_check_shown.val = false
  notice_check_opened.val = ""
  pdf_check_doc.val = 0
  pdf_check_images.val = []
  pdf_check_said.val = 0
  station_check_stopped.val = false
  badge_check_set.val = false
  secret_check_put.val = false
  a11y_check_box.val = Off
  font_scale_said.val = false
  a11y_check_field.set("")
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
