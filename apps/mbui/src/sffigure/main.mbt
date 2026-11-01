// Render a named share graphic to a PNG through mbui's offscreen renderer. See docs/figures.md.

///|
fn main {
  let name = @film.arg("MBUI_FIGURE")
  let path = @film.arg("MBUI_FIGURE_OUT")
  let font = @film.arg("MBUI_FIGURE_FONT")
  let single = name == "wrap-normal" || name == "wrap-reverse" || name == "align-edge" || name == "align-text"
  if (name != "wrap" && name != "align" && !single) || path == "" {
    @film.say("figure: MBUI_FIGURE=wrap|align|wrap-normal|wrap-reverse|align-edge|align-text MBUI_FIGURE_OUT=<out.png> [MBUI_FIGURE_FONT=<font.ttf>]")
    @film.exit(2)
    return
  }
  // Tester resets the app's theme and faces when it starts. Give them after that reset, before the first view reads
  // either, just as sffilm's source gives the app its faces. The closure is built once for this picture.
  let initialized = Ref(false)
  let view = fn(c : @ui.Ctx) {
    if !initialized.val {
      let font_ok = if font == "" {
        match @sfbase.bundled_ui_face() {
          Some(bytes) => @ui.face_add_bytes(@hostapi.face_ui, bytes)
          None => false
        }
      } else {
        @ui.face_add(@hostapi.face_ui, font)
      }
      if !font_ok {
        @film.say(if font == "" { "figure: could not load the bundled UI face" } else { "figure: could not load font \{font}" })
        @film.exit(1)
      }
      @sf.set_dark(Some(true))
      initialized.val = true
    }
    match name {
      "wrap" => @sfgraphic.wrap_figure(c)
      "align" => @sfgraphic.alignment_figure(c)
      "wrap-normal" => @sfgraphic.wrap_card_figure(c, false)
      "wrap-reverse" => @sfgraphic.wrap_card_figure(c, true)
      "align-edge" => @sfgraphic.alignment_card_figure(c, false)
      _ => @sfgraphic.alignment_card_figure(c, true)
    }
  }
  let ok = @film.picture(view, path~, w=if single { 480.0 } else { 960.0 }, h=if single { 270.0 } else { 540.0 }, scale=if single { 5.0 } else { 2.5 }, corner_faults_ok=fn(faults) {
    if name == "align" || name == "align-edge" { @sfgraphic.alignment_corner_faults_ok(faults) } else { faults.is_empty() }
  })
  @film.exit(if ok { 0 } else { 1 })
}
