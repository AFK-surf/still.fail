// still.fail measured offscreen (mbui's film bench, mbui/src/film/bench.mbt): sffix's made-up chats (MBUI_FIXTURE)
// in a Tester of this Mac's text and pictures, a scene's scripted run over them (MBUI_BENCH_DRIVE: one of
// scripts/bench's), what each frame drawn did and how long it took said as one APPBENCH line. No window:
// scripts/appbench.sh runs every scene and keeps what they said.

///|
fn main {
  // no core here: the real core's answers to its pure calls, kept (src/sfkept), as sffix's
  @sf.kept_call.val = Some(@sfkept.answer)
  let mode = @film.arg("MBUI_FIXTURE")
  let dark = @film.arg("MBUI_DARK") == "1"
  // (the app made as sffix makes it, at the Tester's first frame: the code face it carries given then, to the
  // Tester's text, which is this Mac's)
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  @film.run_bench(fn(c) {
    let s = match src.val {
      Some(s) => s
      None => {
        // MBUI_STORY=<story.json>: a told story over the first row's chat (MBUI_FIXTURE=chat-story), as sffilm's
        if @film.arg("MBUI_STORY") != "" {
          @sffixture.fix_story.val = Some(
            @json.parse(@film.read_text(@film.arg("MBUI_STORY"))) catch { _ => abort("MBUI_STORY does not parse") },
          )
        }
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
