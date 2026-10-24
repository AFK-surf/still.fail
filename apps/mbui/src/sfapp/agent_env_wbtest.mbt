// A station's variables (settings/station_parts.mbt open_agent_env; Stations.kt AgentEnvSheet): the field shows the
// core's draft as it changes while nothing typed here waits on it.

///|
test "the variables' field follows the core's text that comes after the sheet opened" {
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  open_setting("station:ws1/st1")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  // in the page's 设置
  station_part(t, "设置")
  shown_on_page(t, "编辑变量")
  t.tap_text("编辑变量")
  t.run_for(@kit.sheet_rest("settings-sheet") - t.time())
  assert_true(@settings.sheet_up(), msg="the sheet up")
  // opened on the text before a save the core tells a moment later
  assert_false(t.dump().contains("\"E2E_A=1\""))
  env.val = ("E2E_A=1", 2)
  t.draw()
  t.draw()
  // (the field's words: the drawn tree's editor holds them)
  assert_true(t.dump().contains("\"E2E_A=1\""), msg="the core's text, come after the sheet opened, in the field")
}
