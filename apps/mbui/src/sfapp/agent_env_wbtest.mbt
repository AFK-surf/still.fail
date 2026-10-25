// A station's variables (src/sfdesk station_page.mbt station_env_editor, in its page's 设置): the field shows the
// core's draft as it changes while nothing typed here waits on it.

///|
test "the variables' field follows the core's text that comes after the page opened" {
  reset()
  let env : Ref[(String, Int)] = Ref(("", 1))
  let base = fixture("settings")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "agentEnvForm" {
        let (words, v) = env.val
        {
          value: Some(
            Json::object({
              "text": Json::string(words),
              "lines": Json::array([]),
              "errors": Json::number(0.0),
              "dirty": Json::boolean(false),
              "pending": Json::boolean(false),
            }),
          ),
          error: None,
          version: v,
        }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  // in the page's 设置, its variables' editor in it (a manager's), the page tall enough for all of it
  @settings.station_parts["ws1/st1"] = "settings"
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0, platform=2)
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Station("ws1/st1")))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  // opened on the text before a save the core tells a moment later
  assert_false(t.dump().contains("\"E2E_A=1\""))
  env.val = ("E2E_A=1", 2)
  t.draw()
  t.draw()
  // (the field's words: the drawn tree's editor holds them)
  assert_true(t.dump().contains("\"E2E_A=1\""), msg="the core's text, come after the page opened, in the field")
}
