// The components' gallery (docs/components.md): a page of components (MBUI_SCREEN=<page>, `foundation` by default),
// every one in its states, the light theme beside the dark one. Live where it can be (pressed, focused by Tab), and
// each state also drawn by its look as it is (pointed at, held, focused, disabled), for screenshots
// (scripts/shots.sh kit).

///|
fn main {
  @hostapi.window_setup(720.0, 520.0, 960.0, 720.0)
  let page = @ui.env("MBUI_SCREEN")
  // MBUI_TEXTCHECK=NAME: the kept run NAME's text asked of this host again (textcheck.mbt), in place of the gallery
  let check = @ui.env("MBUI_TEXTCHECK")
  // MBUI_MARKS (with MBUI_MARKS_IMAGE): marks drawn by the host onto a picture, the PNG on the log (markscheck.mbt)
  let marked = @ui.env("MBUI_MARKS")
  // MBUI_VIEWCHECK=1: a native view placed between pixels, where the host put it on the log (viewcheck.mbt); =hold:
  // left on the screen once placed (VIEWCHECK placed), for a picture of its round corners
  let viewed = @ui.env("MBUI_VIEWCHECK") == "1" || @ui.env("MBUI_VIEWCHECK") == "hold"
  // MBUI_SITECHECK=1: a site's page and a page speaking with the app, each step on the log (sitecheck.mbt)
  let sited = @ui.env("MBUI_SITECHECK") == "1"
  @ui.run("mbui kit", fn(c) {
    if sited {
      @gallery.site_check_run(c)
    } else if viewed {
      @gallery.view_check_run(c)
    } else if marked != "" {
      @gallery.marks_run(c, marked, @ui.env("MBUI_MARKS_IMAGE"))
    } else if check != "" {
      @gallery.text_check_run(c, check)
    } else {
      @gallery.gallery(c, if page == "" { "foundation" } else { page })
    }
  })
}

