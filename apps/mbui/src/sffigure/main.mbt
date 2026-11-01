// Render a named share graphic to a PNG through mbui's offscreen renderer. See docs/figures.md.

///|
fn main {
  let name = @film.arg("MBUI_FIGURE")
  let path = @film.arg("MBUI_FIGURE_OUT")
  let font = @film.arg("MBUI_FIGURE_FONT")
  if (name != "wrap" && name != "align") || path == "" {
    @film.say("figure: MBUI_FIGURE=wrap|align MBUI_FIGURE_OUT=<out.png> [MBUI_FIGURE_FONT=<font.ttf>]")
    @film.exit(2)
    return
  }
  // Tester resets the app's theme and faces when it starts. Give them after that reset, before the first view reads
  // either, just as sffilm's source gives the app its faces. The closure is built once for this picture.
  let initialized = Ref(false)
  // The alignment graphic highlights its card's lines where its first frame drew their letters.
  let runs : Ref[Array[@ui.TextRun]] = Ref([])
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
    if name == "wrap" { @sfgraphic.wrap_figure(c) } else { @sfgraphic.alignment_figure(c, runs=runs.val) }
  }
  let ok = @film.picture(
    view,
    path~,
    w=960.0,
    h=540.0,
    scale=2.5,
    corner_faults_ok=fn(faults) {
      if name == "align" { @sfgraphic.alignment_corner_faults_ok(faults) } else { faults.is_empty() }
    },
    settle=fn(t) {
      if name != "align" {
        return false
      }
      runs.val = t.text_runs()
      true
    },
  )
  @film.exit(if ok { 0 } else { 1 })
}
