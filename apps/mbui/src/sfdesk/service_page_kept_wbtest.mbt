// Page and tab handoffs use the same service page, even when core replies arrive in a different order.

///|
fn service_test_prefs(entries : Array[(ChatRef, Array[String])]) -> Json {
  let chats : Map[String, Json] = Map([])
  for (r, tabs) in entries {
    chats[tabs_key(r)] = { "tabs": Json::array(tabs.map(fn(tab) { Json::string(tab) })) }
  }
  { "chatTabs": Json::object(chats) }
}

///|
test "service page: a background tab is followed and released without another frame" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  tabs_kept["ws place/chats"] = [Chat(r)]
  let job = "file:s1\nwork/s1/report.html"
  let tab = file_tab("s1", "work/s1/report.html", "report.html")
  let key = service_key(r.station, job)
  let prefs : @signals.Signal[Json?] = @signals.signal(Some(service_test_prefs([])))
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) { { value: if name == "prefs" { prefs.get() } else { None }, error: None, version: 1 } },
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; sv_sweep(c, src) }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  let opening = service_tab_asking(src, r, tab, true).unwrap()
  service_tab_answered(src, r, tab, opening, true)
  service_page_drop(src, r.station, job)
  assert_true(service_pages.contains(key), msg="the successful open waits for its topic")
  prefs.set(Some(service_test_prefs([(r, [tab])])))
  assert_true(service_tab_changes.is_empty(), msg="the topic adopted the tab without a frame")
  assert_true(service_pages.contains(key), msg="the background tab still owns the page")
  prefs.set(Some(service_test_prefs([])))
  assert_false(service_pages.contains(key), msg="the last owner left without another frame")
  assert_true(service_ownership_stop.val is None, msg="the preference watch is stopped")
  tabs_kept.clear()
}

///|
test "service page: excluding one tab keeps another chat's tab for the same file" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let a : ChatRef = { station: "ws/st", session: "a", title: "", station_name: "" }
  let b : ChatRef = { station: "ws/st", session: "b", title: "", station_name: "" }
  tabs_kept["ws place/chats"] = [Chat(a)]
  tabs_kept["ws place/files"] = [Chat(b)]
  let job = "file:agent\nwork/agent/report.html"
  let first = file_tab("agent", "work/agent/report.html", "report.html")
  let second = file_tab("agent", "work/agent/report.html", "renamed.html")
  let prefs : @signals.Signal[Json?] = @signals.signal(Some(service_test_prefs([(a, [first]), (b, [second])])))
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) { { value: if name == "prefs" { prefs.get() } else { None }, error: None, version: 1 } },
  }
  assert_true(service_page_kept(src, a.station, job, excluding=Some((a, first))))
  prefs.set(Some(service_test_prefs([(a, [first])])))
  assert_false(service_page_kept(src, a.station, job, excluding=Some((a, first))))
  tabs_kept.clear()
}

///|
test "service page: a historical chat's saved tab is not a live owner" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let r : ChatRef = { station: "ws/st", session: "old", title: "", station_name: "" }
  let tab = file_tab("agent", "work/agent/report.html", "report.html")
  let job = "file:agent\nwork/agent/report.html"
  let key = service_key(r.station, job)
  let saved = service_test_prefs([(r, [tab])])
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) { { value: if name == "prefs" { Some(saved) } else { None }, error: None, version: 1 } },
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  service_page_drop(src, r.station, job)
  assert_false(service_pages.contains(key), msg="old saved tabs do not retain this run's site")
}

///|
test "service page: a live chat keeps its file while prefs catches up" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let tab = file_tab("agent", "work/agent/report.html", "report.html")
  let job = "file:agent\nwork/agent/report.html"
  let key = service_key(r.station, job)
  let chat : @signals.Signal[Json?] = @signals.signal(Some({ "tabs": { "open": [Json::string(tab)] } }))
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) {
      { value: if name == "prefs" { Some(service_test_prefs([])) } else if name == "chat" { chat.get() } else { None }, error: None, version: 1 }
    },
  }
  app.nav.push(Chat(r))
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; side_now(src, r) |> ignore }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  service_page_drop(src, r.station, job)
  assert_true(service_pages.contains(key), msg="the live chat view still holds the file")
  chat.set(Some({ "tabs": { "open": [] } }))
  assert_false(service_pages.contains(key), msg="its topic lets the last owner go without another frame")
}

///|
test "service page: a filtered service tab cannot retain a site after a successful open" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let tab = "service:missing-job"
  let key = service_key(r.station, "missing-job")
  let prefs : @signals.Signal[Json?] = @signals.signal(Some(service_test_prefs([])))
  let chat : Json = { "agents": [{ "session": { "key": "agent" }, "jobs": [{ "id": "other-job" }] }], "tabs": { "open": [] } }
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) {
      { value: if name == "prefs" { prefs.get() } else if name == "chat" { Some(chat) } else { None }, error: None, version: 1 }
    },
  }
  app.nav.push(Chat(r))
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; side_now(src, r) |> ignore }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, "missing-job") |> ignore
  let opening = service_tab_asking(src, r, tab, true).unwrap()
  service_page_drop(src, r.station, "missing-job")
  prefs.set(Some(service_test_prefs([(r, [tab])])))
  service_tab_answered(src, r, tab, opening, true)
  assert_false(service_pages.contains(key), msg="the core filtered this service out of the live chat")
  assert_true(service_ownership_stop.val is None)
}

///|
test "service page: a failed close retains the tab and later releases its page" {
  @sfbase.reset()
  sv_reset()
  tabs_kept.clear()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  tabs_kept["ws place/chats"] = [Chat(r)]
  let tab = file_tab("agent", "work/agent/report.html", "report.html")
  let job = "file:agent\nwork/agent/report.html"
  let key = service_key(r.station, job)
  let prefs : @signals.Signal[Json?] = @signals.signal(Some(service_test_prefs([(r, [tab])])))
  let src = {
    ..@sfbase.made_source(),
    topic: fn(name, _) { { value: if name == "prefs" { prefs.get() } else { None }, error: None, version: 1 } },
  }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  service_page_drop(src, r.station, job)
  let closing = service_tab_asking(src, r, tab, false, was_open=true).unwrap()
  tab_let_go(src, r, tab)
  service_tab_answered(src, r, tab, closing, false)
  assert_true(service_pages.contains(key), msg="the failed close leaves the tab as an owner")
  prefs.set(Some(service_test_prefs([])))
  assert_false(service_pages.contains(key), msg="the saved release is retried when the tab really leaves")
  tabs_kept.clear()
}

///|
test "service page: a stack kept behind the system's other tab is an owner" {
  @sfbase.reset()
  sv_reset()
  let src = @sfbase.made_source()
  let station = "ws/st"
  let job = "file:s1\nwork/s1/report.html"
  let key = service_key(station, job)
  tabs_kept["ws place/chats"] = [PreviewFile(station, "s1", "work/s1/report.html", "report.html")]
  service_page_for(station, job) |> ignore
  service_page_drop(src, station, job)
  assert_true(service_pages.contains(key))
  tabs_kept.clear()
  service_release_pending(src, station, job)
  assert_false(service_pages.contains(key))
}

///|
test "service page: a pending open and close hold the page until both replies arrive" {
  @sfbase.reset()
  sv_reset()
  let src = @sfbase.made_source()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let job = "file:s1\nwork/s1/report.html"
  let tab = file_tab("s1", "work/s1/report.html", "report.html")
  let key = service_key(r.station, job)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; sv_sweep(c, src) }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  let opening = service_tab_asking(src, r, tab, true).unwrap()
  service_page_drop(src, r.station, job)
  assert_true(service_pages.contains(key))
  let closing = service_tab_asking(src, r, tab, false).unwrap()
  service_tab_answered(src, r, tab, closing, true)
  assert_true(service_pages.contains(key), msg="an older open is still awaiting its answer")
  service_tab_answered(src, r, tab, opening, true)
  assert_false(service_pages.contains(key), msg="the confirmed close releases the last owner")
}

///|
test "service page: a failed reopen does not cancel a confirmed close" {
  @sfbase.reset()
  sv_reset()
  let src = @sfbase.made_source()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let job = "file:s1\nwork/s1/report.html"
  let tab = file_tab("s1", "work/s1/report.html", "report.html")
  let key = service_key(r.station, job)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; sv_sweep(c, src) }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  let closing = service_tab_asking(src, r, tab, false).unwrap()
  service_page_drop(src, r.station, job)
  let reopening = service_tab_asking(src, r, tab, true).unwrap()
  tab_kept(r, tab)
  service_tab_answered(src, r, tab, closing, true)
  assert_true(service_pages.contains(key))
  service_tab_answered(src, r, tab, reopening, false)
  assert_false(service_pages.contains(key), msg="the failed reopen leaves the confirmed close in effect")
}

///|
test "service page: failed open and close replies release the abandoned page" {
  @sfbase.reset()
  sv_reset()
  let src = @sfbase.made_source()
  let r : ChatRef = { station: "ws/st", session: "s1", title: "", station_name: "" }
  let job = "file:s1\nwork/s1/report.html"
  let tab = file_tab("s1", "work/s1/report.html", "report.html")
  let key = service_key(r.station, job)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore; sv_sweep(c, src) }, w=500.0, h=500.0)
  t.draw()
  service_page_for(r.station, job) |> ignore
  let opening = service_tab_asking(src, r, tab, true).unwrap()
  let closing = service_tab_asking(src, r, tab, false).unwrap()
  service_page_drop(src, r.station, job)
  service_tab_answered(src, r, tab, opening, false)
  assert_true(service_pages.contains(key), msg="the close is still waiting")
  service_tab_answered(src, r, tab, closing, false)
  assert_false(service_pages.contains(key), msg="neither failed request opened a tab")
}
