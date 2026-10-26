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
  // MBUI_UPDATECHECK=<url>|<sha256>|<size>|<name>: that build put in this one's place by the host (updatecheck.mbt)
  let updated = @ui.env("MBUI_UPDATECHECK")
  // MBUI_LINKCHECK=1: the links the system opens it with, said on the log (linkcheck.mbt)
  let linked = @ui.env("MBUI_LINKCHECK") == "1"
  // MBUI_NOTICECHECK=1: a notification shown, what the one clicked opens said on the log (noticecheck.mbt)
  let noticed = @ui.env("MBUI_NOTICECHECK") == "1"
  // MBUI_PDFCHECK=<a PDF, base64>: its pages read and drawn by the host, said on the log (pdfcheck.mbt)
  let pdf = @ui.env("MBUI_PDFCHECK")
  // MBUI_STATIONCHECK=read|stop: this machine's station as the host says it, and stopped (stationcheck.mbt)
  let station = @ui.env("MBUI_STATIONCHECK")
  // MBUI_BADGECHECK=<n>: the number on the app's icon set, for the desktop's side to be asked (badgecheck.mbt)
  let badge = @ui.env("MBUI_BADGECHECK")
  if linked {
    @ui.on_message(@hostapi.system_channel, fn(json, _) { @gallery.link_check_said(json) })
  }
  @ui.run("mbui kit", fn(c) {
    if updated != "" {
      @gallery.update_check_run(c, updated)
    } else if linked {
      @gallery.link_check_run(c)
    } else if noticed {
      @gallery.notice_check_run(c)
    } else if pdf != "" {
      @gallery.pdf_check_run(c, pdf)
    } else if station != "" {
      @gallery.station_check_run(c, station)
    } else if badge != "" {
      @gallery.badge_check_run(c, badge)
    } else if sited {
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

