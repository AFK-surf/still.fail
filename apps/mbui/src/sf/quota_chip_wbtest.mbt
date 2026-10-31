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
    assert_true(way is Some(_), msg="\{room}: \{shown}")
    assert_eq(t.squeeze_faults(), [], msg=room.to_string())
    said.push(way.unwrap())
  }
  // as much as fits: wide, every word of it; narrow, the marks
  assert_eq(said[0], 0)
  assert_eq(said[3], 2)
  set_words(fn(key, _) { key })
}
