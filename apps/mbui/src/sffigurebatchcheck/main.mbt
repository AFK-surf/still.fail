// Render two scenes in one process, including a scene following a failed write.
///|
fn main {
  let root = @film.arg("MBUI_BATCH_OUT")
  let bad = @film.arg("MBUI_BATCH_FIRST_BAD") == "1"
  let system_only = @film.arg("MBUI_BATCH_SYSTEM_ONLY") == "1"
  let first_face_only = @film.arg("MBUI_BATCH_FIRST_FACE_ONLY") == "1"
  if @film.arg("MBUI_BATCH_FAILED_FILM") == "1" {
    let made = @film.film(fn(_) { }, script="exit", prepare="no-such-step", out=root + "/failed.mp4", w=100.0, h=100.0, scale=1.0)
    if made {
      @film.exit(1)
      return
    }
  }
  for n in 1..=2 {
    let initialized = Ref(false)
    let view = fn(c : @ui.Ctx) {
      if !initialized.val {
        if !system_only && (!first_face_only || n == 1) {
          match @sfbase.bundled_ui_face() {
            Some(bytes) => ignore(@ui.face_add_bytes(@hostapi.face_ui, bytes))
            None => @film.exit(1)
          }
        }
        @sf.set_dark(Some(true))
        initialized.val = true
      }
      @sfgraphic.wrap_figure(c)
    }
    let path = if n == 1 && bad { root + "/missing/first.png" } else { root + "/\{n}.png" }
    let ok = @film.picture(view, path~, w=960.0, h=540.0, scale=2.5)
    if (n == 1 && bad && ok) || (!(n == 1 && bad) && !ok) {
      @film.exit(1)
      return
    }
  }
  @film.exit(0)
}
