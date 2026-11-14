// The component library's parts (src/sf), each on its own beside its states, for people to look at and press: a list of
// them at the side, the one chosen in the middle, in light or dark, at a width. No core: the
// real core's answers to its pure calls, kept (src/sfkept). Built for the browser by scripts/kit-web.sh and served
// at kit.monoid.zone (cloud/wrangler.kit.jsonc). ?STORY=<key> (MBUI_ env on the native hosts) opens that part first;
// MBUI_DARK=1 the dark theme; MBUI_PLATFORM=android|ios started as a phone's, touch its native input.

///|
fn main {
  @sf.kept_call.val = Some(@sfkept.answer)
  if @ui.env("MBUI_DARK") == "1" {
    @sf.set_dark(Some(true))
  }
  match @ui.env("MBUI_PLATFORM") {
    "android" => @ui.set_platform(Some(2))
    "ios" => @ui.set_platform(Some(1))
    _ => ()
  }
  @sf.give_faces()
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0)
  // (the old frame round the tree: on 小屏 the library's menus, picks and questions are its, as the app's frame has them)
  @ui.run(
    "still.fail 组件",
    fn(c) {
      @ui.old_views_here(c)
      @sf.presented(c)
    },
    tree=stories_tree,
  )
}
