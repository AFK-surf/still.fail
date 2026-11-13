// An allowance's chips (quota_chip.mbt): what they say short of room.

///|
/// OpenCode Go's three windows, worded (a profile's row on a phone), in a line `room` wide.
fn worded_tester(room : Double) -> @ui.Tester {
  let q = Json::object({
    "state": "ok",
    "windows": [
      { "label": "5 小时", "mark": "5H", "left": 62.0, "level": "ok" },
      { "label": "每周", "mark": "W", "left": 95.0, "level": "ok" },
      { "label": "每月", "mark": "M", "left": 97.0, "level": "ok" },
    ],
  })
  // (the catalog's words for it, as the app says them)
  set_words(fn(key, args) {
    let said = if key == "web-main.quota.figure" { "剩 {left}%" } else { key }
    args.fold(init=said, fn(said, a) { said.replace_all(old="{" + a.0 + "}", new=a.1) })
  })
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() { c.box(w=Px(room), fn() { quota_chips(c, Some(q), worded=true) }) |> ignore })
    },
    w=640.0,
    h=200.0,
    platform=2,
  )
  t.draw()
  t
}

///|
test "an allowance's windows in words: one way for them all, the longest that fits, each chip whole" {
  // (a phone's row: 326 was what cut all three to 5 小时剩…, 每周剩余…, 每月剩余…, 2026-10-31)
  let ways = [
    ["5 小时", "剩 62%", "每周", "剩 95%", "每月", "剩 97%"],
    ["5 小时", "62%", "每周", "95%", "每月", "97%"],
    ["5H", "62%", "W", "95%", "M", "97%"],
  ]
  let said = []
  for room in [600.0, 326.0, 240.0, 170.0] {
    let t = worded_tester(room)
    // (the words drawn: the way the line says it, the others laid out nowhere)
    let shown = t.words().filter(fn(w) { w.5 > 0.5 }).map(fn(w) { w.0 })
    let way = ways.search(shown)
    assert_true(way is Some(_), msg="\{room}: \{Repr(shown)}")
    assert_eq(t.squeeze_faults(), [], msg=room.to_string())
    said.push(way.unwrap())
  }
  // as much as fits: wide, every word of it; narrow, the marks
  assert_eq(said[0], 0)
  assert_eq(said[3], 2)
  set_words(fn(key, _) { key })
}

///|
/// A Claude subscription's windows with its models' own weeks (present.ts: each its `scope`), in a line `room` wide:
/// worded (a profile's row), or by their marks on a line of their own (`lines`: a station's account).
fn own_tester(room : Double, worded : Bool) -> @ui.Tester {
  let q = Json::object({
    "state": "ok",
    "windows": [
      { "label": "5 小时", "mark": "5H", "left": 62.0, "level": "ok" },
      { "label": "每周", "mark": "W", "left": 19.0, "level": "amber" },
      { "label": "每周 · Fable", "mark": "Fable", "scope": "Fable", "left": 46.0, "level": "ok" },
      { "label": "每周 · Opus", "mark": "Opus", "scope": "Opus", "left": 8.0, "level": "red" },
      { "label": "每周 · Sonnet", "mark": "Sonnet", "scope": "Sonnet", "left": 100.0, "level": "ok" },
    ],
  })
  set_words(fn(key, args) {
    let said = if key == "web-main.quota.figure" { "剩 {left}%" } else { key }
    args.fold(init=said, fn(said, a) { said.replace_all(old="{" + a.0 + "}", new=a.1) })
  })
  let t = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(w=Px(room), fn() { quota_chips(c, Some(q), worded~, lines=!worded, small=!worded) }) |> ignore
      })
    },
    w=900.0,
    h=300.0,
    platform=2,
  )
  t.draw()
  t
}

///|
test "an account's windows and its models' own, five: where no line holds them the account's a line and its models' under it, every chip whole" {
  // (a phone's row cut all five to 5H …, W 1…, … …; a station's account's the same, 2026-11-10)
  for worded in [true, false] {
    let mut lined = 0
    for room in [900.0, 420.0, 342.0, 300.0, 240.0, 180.0, 130.0] {
      let t = own_tester(room, worded)
      let shown = t.words().filter(fn(w) { w.5 > 0.5 })
      // (the one of `words` it is said by, there once)
      let at = fn(words : Array[String]) {
        match shown.filter(fn(w) { words.contains(w.0) }) {
          [w] => w
          found => @halt.saying("\{room}: one of \{Repr(words)}: \{Repr(found)} in \{Repr(shown.map(fn(w) { w.0 }))}")
        }
      }
      // every window said once, whole, within the line's room
      let week = at(["每周", "W"])
      let fable = at(["每周 · Fable", "Fable"])
      let sonnet = at(["每周 · Sonnet", "Sonnet"])
      assert_eq(t.squeeze_faults(), [], msg="\{worded} \{room}")
      assert_true(shown.iter().all(fn(w) { w.1 + w.3 <= room + 0.01 }), msg="\{worded} \{room}: past the line's end: \{Repr(shown)}")
      if fable.2 > week.2 {
        // (in lines: its models' own by the model, under the account's; the account's by their names where worded)
        lined += 1
        assert_eq([fable.0, sonnet.0, week.0], ["Fable", "Sonnet", if worded { "每周" } else { "W" }], msg="\{worded} \{room}")
        assert_true(sonnet.2 >= fable.2)
      } else {
        assert_true(sonnet.2 == week.2, msg="\{worded} \{room}: one line")
      }
    }
    assert_true(lined >= 2 && lined < 7, msg="\{worded}: in a line where it has the room, in lines where not: \{lined}")
  }
  set_words(fn(key, _) { key })
}

///|
test "multi-window model pools group each pool with a left group column and aligned short [5H] [W] capsules" {
  let q = Json::object({
    "state": "ok",
    "windows": [
      { "label": "5 小时 · Gemini", "mark": "Gemini 5H", "scope": "gemini", "left": 56.0, "level": "ok" },
      { "label": "每周 · Gemini", "mark": "Gemini W", "scope": "gemini", "left": 58.0, "level": "ok" },
      { "label": "5 小时 · Claude / GPT", "mark": "Claude / GPT 5H", "scope": "3p", "left": 100.0, "level": "ok" },
      { "label": "每周 · Claude / GPT", "mark": "Claude / GPT W", "scope": "3p", "left": 79.0, "level": "ok" },
    ],
  })
  for nav in [false, true] {
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          c.box(w=Px(224.0), fn() {
            if nav {
              nav_quota_chips(c, Some(q))
            } else {
              quota_chips(c, Some(q), lines=true, small=true)
            }
          })
          |> ignore
        })
      },
      w=640.0,
      h=200.0,
      platform=0,
    )
    t.draw()
    let shown = t.words().filter(fn(w) { w.5 > 0.5 })
    let find_all = fn(mark : String) { shown.filter(fn(w) { w.0 == mark }) }
    let gemini = find_all("Gemini")[0]
    let claude_gpt = find_all("Claude / GPT")[0]
    let fives = find_all("5H")
    let weeks = find_all("W")
    assert_eq(fives.length(), 2)
    assert_eq(weeks.length(), 2)
    // Both 5H capsules align at the exact same X coordinate after the left group column
    assert_eq(fives[0].1, fives[1].1)
    assert_eq(gemini.2, fives[0].2)
    assert_eq(fives[0].2, weeks[0].2)
    assert_eq(claude_gpt.2, fives[1].2)
    assert_eq(fives[1].2, weeks[1].2)
    assert_true(claude_gpt.2 > gemini.2)
    assert_eq(t.squeeze_faults(), [])
  }
  // Narrowest 180pt sidebar (row width 164pt): stacks the group title above the pair of short capsules
  let narrow = @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(w=Px(164.0), fn() { nav_quota_chips(c, Some(q)) }) |> ignore
      })
    },
    w=640.0,
    h=200.0,
    platform=0,
  )
  narrow.draw()
  let nshown = narrow.words().filter(fn(w) { w.5 > 0.5 })
  let nfind = fn(mark : String) { nshown.filter(fn(w) { w.0 == mark }) }
  let ng = nfind("Gemini")[0]
  let nfives = nfind("5H")
  let nweeks = nfind("W")
  assert_true(nfives[0].2 > ng.2)
  assert_eq(nfives[0].2, nweeks[0].2)
  assert_eq(narrow.squeeze_faults(), [])
}

///|
test "fill_chip_wide is the width a fill chip is laid out at: small and marked, small and compact, normal, joined" {
  let chips : Array[(String, String, Bool, Bool)] = [
    ("Fable", "52%", true, false),
    ("", "100%", true, true),
    ("5H", "62%", false, false),
    ("每周", "剩 95%", false, false),
  ]
  assert_true(chip_joined("每周", "剩 95%"))
  for platform in [0, 2] {
    let said : Array[Double] = chips.map(fn(_) { 0.0 })
    let t = @ui.Tester::new(
      fn(c) {
        begin(c) |> ignore
        c.with_theme(ui_theme(), fn() {
          for i, chip in chips {
            let (mark, words, small, compact) = chip
            said[i] = fill_chip_wide(c, mark, words, small~, compact~)
            // (each in a row of its own as wide as what it holds)
            c.box(dir=@ui.Dir::Row, name="chip-\{i}", fn() { fill_chip(c, 52, "ok", mark, words, small~, compact~) }) |> ignore
          }
        })
      },
      w=640.0,
      h=300.0,
      platform~,
    )
    t.draw()
    let boxes = t.boxes()
    for i, chip in chips {
      let holder = boxes.search_by(fn(b) { b.name == "chip-\{i}" }).unwrap()
      let laid = boxes.filter(fn(b) { b.parent == holder })
      assert_eq(laid.length(), 1, msg="\{platform} \{Repr(chip)}")
      assert_eq(said[i], laid[0].w, msg="\{platform} \{Repr(chip)}")
    }
  }
}
