// Shared station facts follow the station and the current device's connection, and own exactly their own topic.

///|
fn facts_station(id : String, online : Bool, summary : String, running : Int, meters : Array[Json]) -> Json? {
  Some({
    "station": Json::string(id), "online": Json::boolean(online), "summary": Json::string(summary),
    "overview": { "counts": { "running": Json::number(running.to_double()) } },
    "host": { "meters": Json::array(meters) },
  })
}

///|
fn facts_meter(level : String, big : String) -> Json {
  { "short": "CPU", "label": "CPU", "level": Json::string(level), "left": 40,
    "value": "60%", "big": Json::string(big), "unit": "%", "remaining": "idle" }
}

///|
test "station state nodes follow presence, running agents, theme and screen reader status" {
  @sf.set_words(@sfbase.fill)
  let station = @signals.signal(facts_station("one", true, "yesterday", 2, []), same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    station_state_node(root, fn() { station.get() })
  })
  t.draw()
  assert_true(t.find(@sf.t("web-pages.stations.page.runningShort", args=[("n", "2")])) is Some(_))
  assert_true(t.semantics().any(fn(s) { !s.hidden && s.label == @sf.t("web-pages.stations.online") }))
  let light = t.drawn_instances()
  @sf.set_dark(Some(true))
  t.draw()
  assert_true(light != t.drawn_instances())
  station.set(facts_station("one", false, "yesterday", 0, []))
  t.draw()
  assert_true(t.find("yesterday") is Some(_))
  assert_true(t.semantics().any(fn(s) { !s.hidden && s.label == @sf.t("web-pages.stations.offline") }))
  station.set(facts_station("one", true, "yesterday", 0, []))
  t.draw()
  assert_true(t.find("yesterday") is None)
  assert_true(t.find(@sf.t("web-pages.stations.page.runningShort", args=[("n", "2")])) is None)
  @sf.set_dark(None)
}

///|
test "station figures keep two lines online and follow and release the current station network" {
  @sf.set_words(@sfbase.fill)
  let station = @signals.signal(facts_station("one", true, "yesterday", 0, [facts_meter("ok", "40")]), same=fn(a, b) { a == b })
  let net : @signals.Signal[Json?] = @signals.signal(Some({ "path": "direct", "rtt": { "text": "12 ms" } }), same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let left : Array[String] = []
  let read : Array[String] = []
  let made = @sfbase.made_source()
  let src : Source = {
    ..made,
    topic: fn(name, params) {
      if name == "stationNet" {
        read.push(params.get("station").unwrap().as_string().unwrap())
        { value: net.get(), error: None, version: 1 }
      } else { (made.topic)(name, params) }
    },
    leave: fn(name, params) {
      if name == "stationNet" { left.push(params.get("station").unwrap().as_string().unwrap()) }
    },
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(column) {
      column.width(Is(Some(300.0))) |> ignore
      column.show(fn() { shown.get() }, fn(slot) { station_figures_node(slot, src, fn() { station.get() }) })
      column.box(fn(after) { after.words(Is("after")) |> ignore }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(read.contains("one"))
  assert_true(t.find("40%") is Some(_) && t.find("direct · 12 ms") is Some(_), msg=t.drawn_text())
  guard t.rect_of("after") is Some((_, online_y, _, _)) else { fail("no following line") }
  net.set(None)
  station.set(facts_station("one", true, "yesterday", 0, []))
  t.draw()
  assert_true(t.find(@sf.t("web-pages.stations.netNone")) is Some(_))
  guard t.rect_of("after") is Some((_, empty_y, _, _)) else { fail("no following line") }
  assert_eq(empty_y, online_y, msg="empty meters and no connection keep both lines")
  net.set(Some({ "path": "relay", "rtt": { "text": "" } }))
  station.set(facts_station("two", true, "yesterday", 0, [facts_meter("red", "3")]))
  t.draw()
  assert_true(read.contains("two") && left.contains("one"), msg="read=\{read}, left=\{left}")
  assert_true(t.find("3%") is Some(_) && t.find("relay") is Some(_), msg=t.drawn_text())
  station.set(facts_station("two", false, "yesterday", 0, []))
  t.draw()
  assert_true(left.contains("two"))
  guard t.rect_of("after") is Some((_, offline_y, _, _)) else { fail("no following line") }
  assert_true(offline_y < online_y, msg="the caller owns any offline placeholder")
  station.set(facts_station("three", true, "", 0, []))
  t.draw()
  shown.set(false)
  t.draw()
  assert_true(left.contains("three"), msg="the topic is left when the node is removed")
}

///|
test "station facts inside a named button remain readable and keep the button's keyboard action" {
  @sf.set_words(@sfbase.fill)
  let station = @signals.signal(facts_station("one", true, "yesterday", 2, [facts_meter("amber", "40")]), same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let selected = Ref(0)
  let src = @sfbase.made_source(topic=fn(name, _) {
    if name == "stationNet" { Some({ "path": "direct", "rtt": { "text": "12 ms" } }) } else { None }
  })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.show(fn() { shown.get() }, fn(row) {
      row.width(Is(Some(300.0))).says(Is(Some(@view.said(Button, label="Station one")))) |> ignore
      @sf.presses_node(row, fn() { selected.val += 1 })
      station_state_node(row, fn() { station.get() })
      station_figures_node(row, src, fn() { station.get() })
    })
  })
  t.draw()
  let said = fn(label : String) { t.semantics().any(fn(s) { !s.hidden && s.label == label }) }
  assert_true(said("Station one") && said(@sf.t("web-pages.stations.online")), msg=t.semantics_dump())
  assert_true(said(@sf.t("web-pages.stations.page.runningShort", args=[("n", "2")])), msg=t.semantics_dump())
  assert_true(said("CPU 40% · CPU 60%") && said("direct · 12 ms"), msg=t.semantics_dump())
  t.key(@ui.key_tab)
  t.key(@ui.key_code_enter)
  assert_eq(selected.val, 1)
  station.set(facts_station("one", false, "yesterday", 0, []))
  t.draw()
  assert_true(said(@sf.t("web-pages.stations.offline")) && said("yesterday"), msg=t.semantics_dump())
  assert_false(said("CPU 40% · CPU 60%") || said("direct · 12 ms"))
  shown.set(false)
  t.draw()
}
