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
  // (made once, as the window's tree is made in the Tester, after its text is set, or as its first frame begins)
  let source = fn() {
    match src.val {
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
  }
  // (the window a tree made once, as src/stillfail's: its shell's nodes, the old views in them)
  @film.run_bench(fn(c) { @sfapp.view(c, source()) }, tree=fn(root) { @sfapp.app_tree(source())(root) })
}
