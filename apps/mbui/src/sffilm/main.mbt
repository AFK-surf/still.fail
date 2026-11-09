// still.fail filmed offscreen with the same application fixture as the Wasm still renderer.
// MBUI_FIXTURE, MBUI_DARK, MBUI_WINDOW, MBUI_CORE_MS, MBUI_HOLD, MBUI_FAILED, MBUI_FAILED_WHY, MBUI_SAID,
// MBUI_UPDATE, MBUI_UPDATES_MS, MBUI_FILM_AUTOFILL and MBUI_FILM_OP select the fixture and its answers.
///|
fn main {
  let source = @sffilmscene.source(@film.arg)
  @film.run(fn(c) { @sfapp.view(c, source()) }, tree=fn(root) { @sfapp.app_tree(source())(root) })
}
