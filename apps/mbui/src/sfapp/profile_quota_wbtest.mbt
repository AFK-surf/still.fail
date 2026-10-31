// A profile in the sidebar, with its station offline and three allowance windows.

///|
fn profile_quota_tester(
  platform : Int,
  maximum? : Bool = false,
  wider_digits? : Double = 0.0,
  two? : Bool = false,
  fourth? : Bool = false,
) -> (@ui.Tester, @signals.Signal[Bool]) {
  new_run()
  let base = fixture("settings")
  let online = @signals.signal(false)
  let windows : Array[Json] = [
    { "mark": "5H", "left": Json::number(if maximum { 100.0 } else { 62.0 }), "level": "ok" },
    { "mark": "W", "left": Json::number(if maximum { 100.0 } else { 19.0 }), "level": "ok" },
    { "mark": "M", "left": Json::number(if maximum { 100.0 } else { 97.0 }), "level": "ok" },
  ]
  if fourth {
    windows.push({ "mark": "2D", "left": Json::number(100.0), "level": "ok" })
  }
  if two {
    windows.pop() |> ignore
  }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "profiles" {
        { value: Some({
          "items": [{
            "key": "ws1/st1/open-code",
            "group": "open-code",
            "groupTitle": "OpenCode Go 订阅",
            "title": "lin@example.com",
            "station": "ws1/st1",
            "usable": Json::boolean(online.get()),
            "state": if online.get() { Json::null() } else { { "text": "Studio 离线", "tone": "red" } },
            "where": "Studio 可用",
            "profile": {
              "id": "open-code",
              "runtime": "opencode",
              "quota": {
                "state": "ok",
                "windows": Json::array(windows),
              },
            },
          }],
          "wait": { "reading": false, "failing": [], "empty": false },
        }), error: None, version: if online.get() { 2 } else { 1 } }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform~)
  // The fake host's digits are narrower than the Mac's; also exercise a width comparable to the real digits.
  t.tabular_wider(wider_digits)
  app.nav.replace(Place("profiles"))
  t.run_for(@ui.move_most_ms)
  (t, online)
}

///|
test "two allowance windows keep their marks beside their figures when they fit" {
  let (t, _) = profile_quota_tester(2, wider_digits=0.3, two=true)
  @sfdesk.wide.side_w.set(@sfdesk.side_min)
  t.draw()
  let runs = t.text_runs().filter(fn(r) { r.x0 < 300.0 })
  let shown = runs.map(fn(r) { r.text })
  for words in ["5H", "62%", "W", "19%"] {
    assert_true(shown.contains(words), msg="\{words}: \{shown}")
  }
  let chip_words = runs.filter(fn(r) { ["5H", "62%", "W", "19%"].contains(r.text) })
  assert_true(chip_words.iter().all(fn(r) { r.top == chip_words[0].top }), msg="\{chip_words}")
  assert_eq(t.squeeze_faults(), [])
}

///|
test "three full allowance windows still fit in the narrowest sidebar" {
  for (platform, digits) in [(0, 0.0), (2, 0.0), (2, 0.3)] {
    let (t, _) = profile_quota_tester(platform, maximum=true, wider_digits=digits)
    @sfdesk.wide.side_w.set(@sfdesk.side_min)
    t.draw()
    let runs = t.text_runs().filter(fn(r) { r.x0 < 300.0 })
    let shown = runs.map(fn(r) { r.text })
    assert_eq(shown.filter(fn(s) { s == "100%" }).length(), 3, msg="\{platform}, \{digits}: \{shown}")
    for mark in ["5H", "W", "M"] {
      assert_true(shown.contains(mark), msg="\{platform}, \{digits}: \{shown}")
    }
    // A short line must not leave one window stranded below the others. In a compact arrangement the marks may be
    // above the figures, but the figures themselves stay in one aligned row.
    let values = runs.filter(fn(r) { r.text == "100%" })
    assert_true(values.iter().all(fn(r) { r.top == values[0].top }), msg="\{platform}, \{digits}: \{values}")
    assert_eq(t.squeeze_faults(), [])
  }
}

///|
test "four allowance windows stay readable in the narrowest sidebar" {
  let (t, _) = profile_quota_tester(2, maximum=true, wider_digits=0.3, fourth=true)
  @sfdesk.wide.side_w.set(@sfdesk.side_min)
  t.draw()
  let runs = t.text_runs().filter(fn(r) { r.x0 < 300.0 })
  let shown = runs.map(fn(r) { r.text })
  for mark in ["5H", "W", "M", "2D"] {
    assert_true(shown.contains(mark), msg="\{mark}: \{shown}")
  }
  assert_eq(shown.filter(fn(s) { s == "100%" }).length(), 4, msg="\{shown}")
  let values = runs.filter(fn(r) { r.text == "100%" })
  assert_true(values[0].top == values[1].top && values[2].top == values[3].top && values[0].top < values[2].top)
  assert_eq(t.squeeze_faults(), [])
}

///|
test "a profile's offline state and its three allowance windows each have room to read" {
  for platform in [0, 2] {
    let (t, online) = profile_quota_tester(platform)
    // Read the lines actually drawn in the sidebar. The alternative placements of the chips are built too, but only
    // one is drawn; looking up the first text node could inspect an alternative that was left out.
    let sidebar_runs = fn() { t.text_runs().filter(fn(r) { r.x0 < 300.0 }) }
    let whole = fn(phase : String) raise {
      let shown = sidebar_runs().map(fn(r) { r.text })
      for words in ["5H", "62%", "W", "19%", "M", "97%"] {
        assert_true(shown.contains(words), msg="\{platform}: \{phase}: \{words}: \{shown}")
      }
    }
    whole("offline")
    // The state is not beside the figures: even a long station name cannot squeeze the three chips.
    let state = sidebar_runs().filter(fn(r) { r.text == "Studio 离线" })[0]
    let first = sidebar_runs().filter(fn(r) { r.text == "5H" })[0]
    assert_true(first.top >= state.bottom, msg="state \{state}, first chip \{first}")
    assert_eq(t.squeeze_faults(), [])
    // Coming back changes the state line to where the account can be used; the allowance stays in place.
    online.set(true)
    t.draw()
    assert_true(sidebar_runs().iter().any(fn(r) { r.text == "Studio 可用" }))
    whole("online")
    assert_eq(sidebar_runs().filter(fn(r) { r.text == "5H" })[0].top, first.top)
    // The person's narrowest sidebar still keeps all three windows whole.
    @sfdesk.wide.side_w.set(@sfdesk.side_min)
    t.draw()
    whole("narrow")
    assert_eq(t.squeeze_faults(), [])
  }
}
