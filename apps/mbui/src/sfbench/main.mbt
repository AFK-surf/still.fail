// still.fail measured offscreen (mbui's film bench, mbui/src/film/bench.mbt): sffix's made-up chats (MBUI_FIXTURE)
// in a Tester of this Mac's text and pictures, a scene's scripted run over them (MBUI_BENCH_DRIVE: one of
// scripts/bench's), what each frame drawn did and how long it took said as one APPBENCH line. No window:
// scripts/appbench.sh runs every scene and keeps what they said.

///|
fn main {
  // no core here: the real core's answers to its pure calls, kept (src/sfkept), as sffix's
  @sf.kept_call.val = Some(@sfkept.answer)
  let mode = @film.arg("MBUI_FIXTURE")
  // (a page's list alone, its keys 30 or 1,500: list_scene.mbt)
  if mode.has_prefix("list:") {
    @film.run_bench(fn(_) {  }, tree=fn(root) { list_scene(root, list_scene_keys(mode)) })
    return
  }
  // (the same list, what it has in sight told to a handler: list_scene.mbt)
  if mode.has_prefix("list-sight:") {
    @film.run_bench(fn(_) {  }, tree=fn(root) { list_scene(root, list_scene_keys(mode), sight=true) })
    return
  }
  // (a plain column alone, its rows 17 or 170: col_scene.mbt)
  if mode.has_prefix("col:") {
    @film.run_bench(fn(_) {  }, tree=fn(root) { col_scene(root, col_scene_rows(mode)) })
    return
  }
  let dark = @film.arg("MBUI_DARK") == "1"
  // (the app made as sffix makes it, at the Tester's first frame: the code face it carries given then, to the
  // Tester's text, which is this Mac's)
  let src : Ref[@sfapp.Source?] = Ref(None)
  // (made once, as the window's tree is made in the Tester, after its text is set, or as its first frame begins)
  let source = fn() {
    match src.val {
      Some(s) => s
      None => {
        // (switch-real:<ms>: a workspace picked over a late core, switch_scene.mbt)
        let s = if mode.has_prefix("switch-real") { switch_real_source(mode) } else { @sfapp.fixture_app(mode) }
        // MBUI_FIX_PACE, MBUI_FIX_CORE: the made-up station's pace (@sffixture.fix_pace_said), said in APPBENCH below
        @sffixture.fix_pace_said(@film.arg("MBUI_FIX_PACE"), @film.arg("MBUI_FIX_CORE"))
        if dark {
          @sf.set_dark(Some(true))
        }
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
  }
  let pace = @film.arg("MBUI_FIX_PACE")
  let core = @film.arg("MBUI_FIX_CORE")
  // (the window a tree made once, as src/stillfail's: its shell's nodes, the old views in them)
  @film.run_bench(
    fn(c) { @sfapp.view(c, source()) },
    tree=fn(root) { @sfapp.app_tree(source())(root) },
    settings?=if pace != "" || core != "" {
      Some({ "fix_pace": Json::string(pace), "fix_core": Json::string(core) })
    } else {
      None
    },
  )
}
