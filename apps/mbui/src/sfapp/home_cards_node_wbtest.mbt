// Home's cards at its lists' top and foot (what the last update brought, what the update wants, what is left up long:
// news_node.mbt, open_jobs_node.mbt) are nodes of the window's tree: shown, they host no old view, on a small screen and
// a large one.

///|
test "Home's news, update and long jobs' cards host no old view, on a small screen and a large one" {
  let wrong : Array[String] = []
  for win in [("phone", 360.0, 740.0, 2, ""), ("wide", 1280.0, 800.0, 0, "")] {
    let bare = screen_in("home", win, "zh").old_views_hosted()
    for mode in ["home-news", "home-update", "home-jobs"] {
      let n = screen_in(mode, win, "zh").old_views_hosted()
      if n != bare {
        wrong.push("\{win.0} \{mode}: \{n} old views hosted, \{bare} on Home without it")
      }
    }
  }
  assert_eq(wrong, [])
}
