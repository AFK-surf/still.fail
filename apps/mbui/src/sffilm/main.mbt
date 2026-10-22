// still.fail filmed offscreen (mbui's film, mbui/src/film): sffix's made-up chats (MBUI_FIXTURE: its modes, MBUI_DARK=1
// the dark theme) in a Tester of this Mac's text and pictures, a scripted run over them (MBUI_FILM_DRIVE: one of
// scripts/motion's), each frame drawn offscreen and written into MBUI_FILM, an MP4. No window: scripts/film.sh.

///|
fn main {
  let mode = @film.arg("MBUI_FIXTURE")
  let dark = @film.arg("MBUI_DARK") == "1"
  // (the app made as sffix makes it, at the Tester's first frame: the code face it carries given then, to the
  // Tester's text, which is this Mac's)
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  @film.run(fn(c) {
    let s = match src.val {
      Some(s) => s
      None => {
        let s = @sfapp.fixture_app(mode)
        if dark {
          @sf.set_dark(Some(true))
        }
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
    @sfapp.view(c, s)
  })
}
