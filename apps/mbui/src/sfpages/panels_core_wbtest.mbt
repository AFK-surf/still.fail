// The core the settings' panels draw with where nothing at hand gives one (settings' panels_core: a station's card
// from a chat) is each run's own: a Tester begun after another of the same workspace reads its own core, not the one
// before it's (the same workspace's core is told to none again, so only a run's beginning lets the last go).

///|
/// The fixture's chat's source, its station ws1/st1 named `name` (the workspace's stations' row).
fn core_run_src(name : String) -> Source {
  let base = @sffixture.fixture("chat")
  {
    ..base,
    topic_read: fn(topic, params) {
      let got = (base.topic_read)(topic, params)
      match (topic, got.value) {
        ("stations", Some(Array(rows))) =>
          {
            ..got,
            value: Some(
              Json::array(
                rows.map(fn(r) {
                  match r {
                    Object(m) if text(Some(r), "station") == "ws1/st1" => {
                      let o = m.copy()
                      o["name"] = Json::string(name)
                      Json::object(o)
                    }
                    _ => r
                  }
                }),
              ),
            ),
          }
        _ => got
      }
    },
  }
}

///|
/// A run of the app's frame saying `src`'s core for its workspace each frame (as the app's does: panels_frame), what
/// is presented drawn over it, a phone's window; the station's card opened over it, come in.
fn core_run(src : Source) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(_c) {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(@sfbase.settings_core(src, w), w.id)
        None => ()
      }
    },
    tree=fn(root) {
      @sf.set_words(@sfbase.fill)
      @sf.presented_nodes(root)
    },
    w=390.0,
    h=844.0,
    platform=2,
    env=[("MBUI_LOCALE", "zh")],
  )
  @sf.presenters_reset()
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "two runs one after the other, the same workspace, each its own core: the station's card of each titled by its own core's name, not the run's before it" {
  let first = core_run(core_run_src("Willow 甲"))
  assert_true(first.find("Willow 甲") is Some(_), msg="the first run: its own name")
  let second = core_run(core_run_src("Willow 乙"))
  assert_true(second.find("Willow 乙") is Some(_), msg="the second run: its own name")
  assert_true(second.find("Willow 甲") is None, msg="the second run: not the first's")
  @sf.presenters_reset()
}
