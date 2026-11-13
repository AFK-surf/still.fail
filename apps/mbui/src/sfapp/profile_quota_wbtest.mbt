// A profile in the sidebar, with its station offline and three allowance windows.

///|
fn profile_quota_tester(
  platform : Int,
  maximum? : Bool = false,
  wider_digits? : Double = 0.0,
  two? : Bool = false,
  fourth? : Bool = false,
  own? : Bool = false,
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
  // (a model's own week in the month's place: marked by the model, wider than a length's mark)
  if own {
    windows[2] = { "mark": "Fable", "scope": "Fable", "left": Json::number(if maximum { 100.0 } else { 46.0 }), "level": "ok" }
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "profiles" {
        { value: Some({
          "items": [{
            "key": "ws1/st1/open-code",
            "group": "open-code",
            "groupTitle": "OpenCode Go 订阅",
            "title": "lin@example.com",
            "station": "ws1/st1",
            "usable": Json::boolean(online.get()),
            "state": if online.get() { Json::null() } else { { "text": "Willow 离线", "tone": "red" } },
            "where": "Willow 可用",
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
        base.topic(name, params).get().snapshot()
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
    assert_true(shown.contains(words), msg="\{words}: \{Repr(shown)}")
  }
  let chip_words = runs.filter(fn(r) { ["5H", "62%", "W", "19%"].contains(r.text) })
  assert_true(chip_words.iter().all(fn(r) { r.top == chip_words[0].top }), msg="\{Repr(chip_words)}")
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
    assert_eq(shown.filter(fn(s) { s == "100%" }).length(), 3, msg="\{platform}, \{digits}: \{Repr(shown)}")
    let marks = ["5H", "W", "M"]
    for mark in marks {
      assert_true(shown.contains(mark), msg="\{platform}, \{digits}: \{Repr(shown)}")
    }
    // Every window keeps its mark beside its figure in a standard capsule, wrapping to a second line when the
    // narrowest sidebar cannot hold all three on one line.
    let mks = runs.filter(fn(r) { marks.contains(r.text) })
    let values = runs.filter(fn(r) { r.text == "100%" })
    for i in 0..<3 {
      assert_eq(mks[i].top, values[i].top, msg="\{platform}, \{digits}: \{Repr(mks)} \{Repr(values)}")
    }
    assert_true(values[0].top == values[1].top && values[0].top <= values[2].top, msg="\{platform}, \{digits}: \{Repr(values)}")
    assert_eq(t.squeeze_faults(), [])
  }
}

///|
test "a model's own week, marked by the model, still fits beside the account's windows in the narrowest sidebar" {
  for (platform, digits) in [(0, 0.0), (2, 0.0), (2, 0.3)] {
    let (t, _) = profile_quota_tester(platform, maximum=true, wider_digits=digits, own=true)
    @sfdesk.wide.side_w.set(@sfdesk.side_min)
    t.draw()
    let runs = t.text_runs().filter(fn(r) { r.x0 < 300.0 })
    let shown = runs.map(fn(r) { r.text })
    let marks = ["5H", "W", "Fable"]
    for mark in marks {
      assert_eq(shown.filter(fn(s) { s == mark }).length(), 1, msg="\{platform}, \{digits}: \{mark}: \{Repr(shown)}")
    }
    let mks = runs.filter(fn(r) { marks.contains(r.text) })
    let values = runs.filter(fn(r) { r.text == "100%" })
    assert_eq(values.length(), 3, msg="\{platform}, \{digits}: \{Repr(shown)}")
    for i in 0..<3 {
      assert_eq(mks[i].top, values[i].top, msg="\{platform}, \{digits}: \{Repr(mks)} \{Repr(values)}")
    }
    assert_true(values[0].top == values[1].top && values[0].top < values[2].top, msg="\{platform}, \{digits}: \{Repr(values)}")
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
    assert_true(shown.contains(mark), msg="\{mark}: \{Repr(shown)}")
  }
  assert_eq(shown.filter(fn(s) { s == "100%" }).length(), 4, msg="\{Repr(shown)}")
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
        assert_true(shown.contains(words), msg="\{platform}: \{phase}: \{words}: \{Repr(shown)}")
      }
    }
    whole("offline")
    // The state is not beside the figures: even a long station name cannot squeeze the three chips.
    let state = sidebar_runs().filter(fn(r) { r.text == "Willow 离线" })[0]
    let first = sidebar_runs().filter(fn(r) { r.text == "5H" })[0]
    assert_true(first.top >= state.bottom, msg="state \{Repr(state)}, first chip \{Repr(first)}")
    assert_eq(t.squeeze_faults(), [])
    // Coming back changes the state line to where the account can be used; the allowance stays in place.
    online.set(true)
    t.draw()
    assert_true(sidebar_runs().iter().any(fn(r) { r.text == "Willow 可用" }))
    whole("online")
    assert_eq(sidebar_runs().filter(fn(r) { r.text == "5H" })[0].top, first.top)
    // The person's narrowest sidebar still keeps all three windows whole.
    @sfdesk.wide.side_w.set(@sfdesk.side_min)
    t.draw()
    whole("narrow")
    assert_eq(t.squeeze_faults(), [])
  }
}

///|
/// The Profile sidebar of settings-profiles-several (five Claude accounts, the report's figures), on 大屏; `row`'s
/// figures all `left` where given (another account's spent so far, the rest as they were); `agy` adds a four-window
/// Antigravity CLI account after ChatGPT.
fn several_tester(platform : Int, digits : Double, row? : String = "", left? : Int = 0, agy? : Bool = false) -> @ui.Tester {
  new_run()
  @settings.fixture_page("settings-profiles-several") |> ignore
  let base = fixture("settings")
  // (one field of an object made anew by `f`)
  let put = fn(v : Json, name : String, f : (Json) -> Json) {
    match v {
      Object(m) => {
        let m = m.copy()
        m[name] = f(m.get(name).unwrap_or(Json::null()))
        Json::object(m)
      }
      _ => v
    }
  }
  let figures = fn(w : Json) {
    let w = put(w, "left", fn(_) { Json::number(left.to_double()) })
    put(w, "usedPercent", fn(_) { Json::number((100 - left).to_double()) })
  }
  let agy_item : Json = {
    "key": "ws1/st1/agy",
    "group": "agy",
    "groupTitle": "Antigravity CLI 订阅",
    "title": "agy@example.com",
    "station": "ws1/st1",
    "usable": true,
    "state": Json::null(),
    "where": "Willow 可用",
    "profile": {
      "id": "agy",
      "name": "agy@example.com",
      "runtime": "agy",
      "quota": {
        "state": "ok",
        "windows": [
          { "mark": "Gemini 5H", "scope": "Gemini", "left": 100.0, "level": "ok" },
          { "mark": "Gemini W", "scope": "Gemini", "left": 83.0, "level": "ok" },
          { "mark": "Claude / GPT 5H", "scope": "Claude / GPT", "left": 65.0, "level": "ok" },
          { "mark": "Claude / GPT W", "scope": "Claude / GPT", "left": 10.0, "level": "red" },
        ],
      },
    },
  }
  let reshape = fn(v : Json) {
    put(v, "items", fn(items) {
      guard items is Array(a) else { return items }
      let a = a.map(fn(e) {
        guard row != "" && e is Object(m) && m.get("key") == Some(Json::string(row)) else { return e }
        put(e, "profile", fn(p) {
          put(p, "quota", fn(q) {
            put(q, "windows", fn(ws) {
              guard ws is Array(ws) else { return Json::null() }
              Json::array(ws.map(figures))
            })
          })
        })
      })
      if agy {
        let out : Array[Json] = []
        for e in a {
          if e is Object(m) && m.get("group") == Some(Json::string("key")) {
            out.push(agy_item)
          }
          out.push(e)
        }
        Json::array(out)
      } else {
        Json::array(a)
      }
    })
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let read = base.topic(name, params).get().snapshot()
      if name == "profiles" && (row != "" || agy) {
        { ..read, value: read.value.map(reshape) }
      } else {
        read
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform~)
  t.tabular_wider(digits)
  app.nav.replace(Place("profiles"))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Each row with an allowance in the sidebar of several_tester, from the top: where its first capsule starts (its box,
/// none where it has none) and how tall it is; the words of every chip drawn in those rows; where the titles start; where
/// each row's line under its title starts; the widest room between two capsules side by side in each row.
fn several_rows(t : @ui.Tester) -> (Array[Double?], Array[Double], Array[String], Double, Array[Double], Array[Double]) raise {
  let titles = [
    "claude1@example.com", "claude2@example.com", "claude3@example.com", "claude4@example.com", "claude5@example.com",
    "ChatGPT 团队", "备用 key",
  ]
  let runs = t.text_runs()
  // (the sidebar's: the title furthest left, a page beside it may say it again; whole, or cut to … where narrow)
  // (the last, 备用 key, only where the row above it ends: under the window's foot where the rows above are tall)
  let titled = fn(title : String) {
    runs.filter(fn(r) {
      r.text == title ||
      (r.text.has_suffix("…") && r.text.length() > 4 && title.has_prefix(r.text[:r.text.length() - 1].to_owned()))
    })
  }
  // (where the sidebar's titles start: the first's furthest left; a page beside drawing one again is not the sidebar's)
  let side_x = titled(titles[0]).fold(init=@double.infinity, fn(a, r) { if r.x0 < a { r.x0 } else { a } })
  let title_runs = titles.mapi(fn(i, title) {
    let found = titled(title).filter(fn(r) { (r.x0 - side_x).abs() < 0.5 })
    if found.length() == 0 && i == titles.length() - 1 {
      return None
    }
    guard found.length() > 0 else { @halt.saying("no \{title} in \{Repr(runs.map(fn(r) { r.text }))}") }
    Some(found.fold(init=found[0], fn(a, r) { if r.x0 < a.x0 { r } else { a } }))
  })
  let tops = title_runs.map(fn(r) {
    match r {
      Some(r) => r.top
      None => t.h
    }
  })
  let first_title = title_runs[0].unwrap()
  let right = first_title.x0 + @sfdesk.wide.side_w.get() - 30.0
  let boxes = t.boxes()
  let starts : Array[Double?] = []
  let heights : Array[Double] = []
  let words : Array[String] = []
  let lines_x : Array[Double] = []
  let gaps : Array[Double] = []
  for k in 0..<(titles.length() - 1) {
    let (top, next) = (tops[k], tops[k + 1])
    heights.push(next - top)
    let in_row = runs.filter(fn(r) { r.top > top && r.top < next && r.x1 < right })
    // (the chips' words: under its line of facts, which may end in … as it will, and not the next group's heading)
    let facts = in_row.fold(init=next, fn(a, r) { if r.top < a { r.top } else { a } })
    lines_x.push(in_row.filter(fn(r) { r.top == facts }).fold(init=@double.infinity, fn(a, r) { if r.x0 < a { r.x0 } else { a } }))
    for r in in_row {
      if r.top > facts && !["ChatGPT 订阅", "API key"].contains(r.text) {
        words.push(r.text)
      }
    }
    let mut first : Double? = None
    let capsules : Array[(Double, Double, Double)] = []
    for r in in_row.filter(fn(r) { r.text.has_suffix("%") }) {
      // (its capsule: the narrowest round box of a chip's height round it, not its fill's square parts)
      let middle = (r.top + r.bottom) / 2.0
      let around = boxes.filter(fn(b) {
        (b.h - @sf.fill_chip_small_h).abs() < 0.01 &&
        b.radius > 0.0 &&
        b.x <= r.x0 &&
        b.x + b.w >= r.x1 &&
        b.y <= middle &&
        b.y + b.h >= middle
      })
      guard around.length() > 0 else { fail("\{titles[k]}: \{r.text} in no capsule") }
      let capsule = around.fold(init=around[0], fn(a, b) { if b.w < a.w { b } else { a } })
      let x = capsule.x
      capsules.push((capsule.y, capsule.x, capsule.x + capsule.w))
      first = Some(match first {
        Some(f) => if x < f { x } else { f }
        None => x
      })
    }
    starts.push(first)
    // (the widest room between two capsules side by side in a line of the row)
    capsules.sort_by(fn(a, b) { if a.0 != b.0 { a.0.compare(b.0) } else { a.1.compare(b.1) } })
    let mut widest = 0.0
    for i in 1..<capsules.length() {
      if capsules[i].0 == capsules[i - 1].0 {
        widest = dmax(widest, capsules[i].1 - capsules[i - 1].2)
      }
    }
    gaps.push(widest)
  }
  (starts, heights, words, first_title.x0, lines_x, gaps)
}

///|
test "a list of five accounts' allowances: every row's chips start where its mark does, at each sidebar width, whatever is spent" {
  for case in [(0, 0.0), (2, 0.3)] {
    let (platform, digits) = case
    let t = several_tester(platform, digits)
    let own = @sfdesk.wide.side_w.get()
    // (what a person can drag it to, side_min to side_max)
    let widths = [own, (own + @sfdesk.side_min) / 2.0, @sfdesk.side_min, own + 60.0, @sfdesk.side_max]
    let seen : Array[(Array[Double?], Array[Double])] = []
    for side in widths {
      @sfdesk.wide.side_w.set(side)
      t.draw()
      let (starts, heights, words, text_x, lines_x, gaps) = several_rows(t)
      let at = "\{platform} \{digits} \{side}"
      // (a) the five Claude accounts' and ChatGPT's: one start, the mark's
      let shown = starts.filter_map(fn(s) { s })
      assert_eq(shown.length(), 6, msg="\{at}: \{Repr(starts)}")
      assert_true(shown.iter().all(fn(s) { (s - shown[0]).abs() < 0.01 }), msg="\{at}: first capsules start at \{Repr(starts)}")
      // (the mark's left edge: the text is the mark and the row's gap, S2, in from it)
      let mark_x = text_x - @sf.nav_mark_side - @ui.Space::S2.px()
      assert_true((shown[0] - mark_x).abs() < 0.01, msg="\{at}: first capsules start at \{Repr(starts)}, the mark at \{mark_x}")
      // (one way for a list's rows: claude1 and claude2 have three windows, claude3 and claude4 two, each pair as tall)
      assert_true(heights[0] == heights[1] && heights[2] == heights[3], msg="\{at}: rows \{Repr(heights)}")
      // (each way of a row's chips from the start, never spread to the row's ends: no more room between two side by
      // side than a mark wider than its chip leaves)
      assert_true(gaps.iter().all(fn(g) { g < 16.0 }), msg="\{at}: room between capsules \{Repr(gaps)}")
      // (and each row's line under its title, its facts: from the mark's edge too)
      assert_true(lines_x.iter().all(fn(x) { (x - mark_x).abs() < 0.01 }), msg="\{at}: lines under the titles start at \{Repr(lines_x)}, the mark at \{mark_x}")
      // (b) every chip whole
      assert_true(words.iter().all(fn(w) { !w.has_suffix("…") }), msg="\{at}: \{Repr(words)}")
      assert_eq(t.squeeze_faults(), [], msg=at)
      seen.push((starts, heights))
    }
    // (c) an account's figures all spent or all left: every row still starts where it did, at each width, and the
    // list's rows still take one way (each pair of as many windows as tall)
    for change in [(0, "ws1/st1/cc", 100), (0, "ws1/st1/cc", 0), (2, "ws1/st1/claude-3", 100), (4, "ws1/st1/claude-5", 0)] {
      let (_, row, left) = change
      let t = several_tester(platform, digits, row~, left~)
      for i, side in widths {
        @sfdesk.wide.side_w.set(side)
        t.draw()
        let (starts, heights, _, _, _, _) = several_rows(t)
        let at = "\{platform} \{digits} \{side}: \{row} all \{left}"
        assert_eq(starts, seen[i].0, msg=at)
        assert_true(heights[0] == heights[1] && heights[2] == heights[3], msg="\{at}: rows \{Repr(heights)}")
      }
    }
  }
}

///|
test "allowance layout is chosen per provider: a four-window vendor does not shrink another vendor's rows" {
  let t = several_tester(2, 0.3, agy=true)
  let row_in_line = fn(from_title : String, to_title : String, marks : Array[String]) -> Bool raise {
    let runs = t.text_runs().filter(fn(r) { r.x0 < @sfdesk.wide.side_w.get() })
    let find_top = fn(title : String) -> Double? {
      let found = runs.filter(fn(r) {
        r.text == title ||
        (r.text.has_suffix("…") && r.text.length() > 4 && title.has_prefix(r.text[:r.text.length() - 1].to_owned()))
      })
      if found.length() == 0 {
        None
      } else {
        Some(found.fold(init=found[0], fn(a, r) { if r.x0 < a.x0 { r } else { a } }).top)
      }
    }
    guard find_top(from_title) is Some(top) else { fail("no \{from_title}") }
    let next = find_top(to_title).unwrap_or(t.h)
    let in_row = runs.filter(fn(r) { r.top > top && r.top < next })
    let figs = in_row.filter(fn(r) { r.text.has_suffix("%") })
    let mks = in_row.filter(fn(r) { marks.contains(r.text) })
    guard figs.length() > 0 && mks.length() == marks.length() else {
      fail("\{from_title}: figs=\{Repr(figs)} mks=\{Repr(mks)}")
    }
    mks.iter().all(fn(m) { m.top == figs[0].top })
  }
  // At the default sidebar width, an Antigravity CLI row with four wide windows wraps its two model pools onto two
  // lines, while the five Claude rows (both three-window and two-window) and ChatGPT keep their marks beside their
  // figures on one line.
  assert_true(row_in_line("claude1@example.com", "claude2@example.com", ["5H", "W", "Fable"]))
  assert_true(row_in_line("claude3@example.com", "claude4@example.com", ["W", "Fable"]))
  assert_true(row_in_line("ChatGPT 团队", "agy@example.com", ["5H", "W"]))
  assert_false(row_in_line("agy@example.com", "备用 key", ["Gemini 5H", "Gemini W", "Claude / GPT 5H", "Claude / GPT W"]))
  assert_eq(t.squeeze_faults(), [])
  // At the narrowest sidebar width, Claude's three-window rows switch all Claude rows (including two-window claude3)
  // to two lines of standard capsules, while ChatGPT's two-window row still keeps its marks beside its figures on one line.
  @sfdesk.wide.side_w.set(@sfdesk.side_min)
  t.draw()
  assert_false(row_in_line("claude1@example.com", "claude2@example.com", ["5H", "W", "Fable"]))
  assert_false(row_in_line("claude3@example.com", "claude4@example.com", ["W", "Fable"]))
  assert_true(row_in_line("ChatGPT 团队", "agy@example.com", ["5H", "W"]))
  assert_eq(t.squeeze_faults(), [])
}
