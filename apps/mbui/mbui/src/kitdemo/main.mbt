// The components' gallery (docs/components.md): a page of components (MBUI_SCREEN=<page>, `foundation` by default),
// every one in its states, the light theme beside the dark one. Live where it can be (pressed, focused by Tab), and
// each state also drawn by its look as it is (pointed at, held, focused, disabled), for screenshots
// (scripts/shots.sh kit).

///|
fn main {
  @host.window_setup(720.0, 520.0, 960.0, 720.0)
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
      site_check_run(c)
    } else if viewed {
      view_check_run(c)
    } else if marked != "" {
      marks_run(c, marked, @ui.env("MBUI_MARKS_IMAGE"))
    } else if check != "" {
      text_check_run(c, check)
    } else {
      gallery(c, if page == "" { "foundation" } else { page })
    }
  })
}

///|
/// The page in both themes, side by side.
fn gallery(c : @ui.Ctx, page : String) -> Unit {
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
    half(c, @ui.Theme::light(), page)
    half(c, @ui.Theme::dark(), page)
  })
  |> ignore
}

///|
fn half(c : @ui.Ctx, t : @ui.Theme, page : String) -> Unit {
  c.with_theme(t, fn() {
    c.scope(if t.dark { 2 } else { 1 }, fn() {
      c.box(w=Fill(1.0), h=Fill(1.0), bg=t.bg, pad=24.0, gap=18.0, clip=true, fn() {
        c.text(if t.dark { "Dark" } else { "Light" }, size=t.font_sm, weight=600, color=t.muted) |> ignore
        match page {
          "foundation" => foundation(c)
          "controls" => controls(c)
          "overlays" => overlays(c)
          "menus" => menus(c)
          "disclosure" => disclosure(c)
          _ => c.text("No page \"\{page}\"") |> ignore
        }
      })
      |> ignore
    })
  })
}

///|
/// A part of a page: its name over what it shows.
fn section(c : @ui.Ctx, title : String, body : () -> Unit) -> Unit {
  let t = c.theme()
  c.box(gap=8.0, fn() {
    c.text(title, size=12.0, weight=600, color=t.muted, wrap=false) |> ignore
    body()
  })
  |> ignore
}

///|
/// A row of what a section shows.
fn line(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(dir=Row, gap=8.0, align=ACenter, body) |> ignore
}
