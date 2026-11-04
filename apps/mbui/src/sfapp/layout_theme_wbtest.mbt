// The app's theme is an input to the window tree, including when the system changes it between frames.

///|
test "the window follows the system theme before its layout" {
  for dark in [false, true] {
    new_run()
    let base = fixture("settings")
    let appearance = @signals.signal("system")
    let src : Source = {
      ..base,
      topic: fn(name, params) {
        let p = (base.topic)(name, params)
        if name == "prefs" {
          match p.value {
            Some(Object(m)) => {
              let o : Map[String, Json] = {}
              for k, v in m { o[k] = v }
              o["appearance"] = Json::string(appearance.get())
              { ..p, value: Some(Json::object(o)) }
            }
            _ => p
          }
        } else {
          p
        }
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, dark~)
    t.frame()
    assert_eq(@sf.theme().dark, dark)
    let tree = @ui.view_tree().unwrap()
    let before = tree.work().computes
    t.set_dark(!dark)
    t.frame()
    assert_eq(@sf.theme().dark, !dark)
    assert_true(tree.work().computes - before <= 1, msg="a system theme change lays out at most once")
    let before = tree.work().computes
    t.set_dark(dark)
    t.frame()
    assert_eq(@sf.theme().dark, dark)
    assert_true(tree.work().computes - before <= 1, msg="returning to the system theme lays out at most once")
    appearance.set("dark")
    t.set_dark(false)
    t.frame()
    assert_true(@sf.theme().dark, msg="an explicitly chosen theme takes precedence over the system")
    appearance.set("system")
    t.frame()
    assert_false(@sf.theme().dark, msg="following the system can be chosen again")
  }
}
