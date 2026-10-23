// The usage page's days (usage.mbt usage_days, Usage.kt Days): each day's bar in the middle of its day, over its date,
// standing on the days' foot as high as its share of the most spent.

///|
/// A week's days, the last today, `costs` spent on each by one person.
fn usage_week(costs : Array[Double]) -> Json {
  let daily : Array[Json] = []
  let mut max = 0.0
  for i, cost in costs {
    daily.push({
      "day": Json::string("2026-10-\{17 + i}"),
      "label": Json::string("10/\{17 + i}"),
      "today": Json::boolean(i == costs.length() - 1),
      "cost": Json::number(cost),
      "parts": [Json::number(cost)],
      "costText": Json::string("$\{cost}"),
      "callsText": Json::string("1"),
    })
    max = if cost > max { cost } else { max }
  }
  { "daily": Json::array(daily), "series": [{ "key": "a", "name": "A" }], "max": Json::number(max) }
}

///|
test "usage: each day's bar in the middle of its day, over its date, on the days' foot" {
  usage_state.day = ""
  let costs = [20.0, 16.0, 48.0, 80.0, 32.0, 24.0, 8.0]
  let v = usage_week(costs)
  // seven days 38 wide, 6 apart
  let t = @ui.Tester::new(fn(c) {
    c.box(align=AStart, fn() { c.box(w=Px(302.0), fn() { usage_days(c, Some(v)) }) |> ignore }) |> ignore
  })
  t.draw()
  let bars = t.drawn_rects().filter(fn(r) { r.4 == usage_light[0] })
  assert_eq(bars.length(), 7)
  // the most spent from the days' top to their foot, 150 down
  let (x0, top, _, _, _) = bars[3]
  let x0 = x0 - 3.0 * 44.0
  for i, b in bars {
    let (x, y, w, h, _) = b
    assert_eq((x - x0, w), (i.to_double() * 44.0, 28.0))
    assert_eq((y + h, h), (top + 150.0, 150.0 * costs[i] / 80.0))
    if i < 6 {
      match t.rect_of("10/\{17 + i}") {
        Some((lx, _, lw, _)) => assert_true((lx + lw / 2.0 - (x + w / 2.0)).abs() < 0.5)
        None => fail("no date \{i}")
      }
    }
  }
}
