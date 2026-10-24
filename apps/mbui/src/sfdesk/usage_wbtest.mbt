// 用量's days (usage.mbt usage_chart, the web's Usage.tsx DaysChart): the day tapped (the last at first) said over them, each
// day's bar in the middle of its day over its date, standing on the days' foot as high as its share of the scale's top,
// split by who it was for 1 apart, and with several people what each spent that day under them.

///|
/// A week's days, the last today, `parts` spent on each by each person (one person: one each), on the scale the core
/// works out for them (views/usage.ts scale: the most 80, its top 100 in two steps).
fn usage_week(parts : Array[Array[Double]]) -> Json {
  let daily : Array[Json] = []
  let mut max = 0.0
  for i, ps in parts {
    let mut cost = 0.0
    for p in ps {
      cost += p
    }
    daily.push({
      "day": Json::string("2026-10-\{17 + i}"),
      "label": Json::string("10/\{17 + i}"),
      "today": Json::boolean(i == parts.length() - 1),
      // (what the core says of it: views/usage.ts)
      "name": Json::string(if i == parts.length() - 1 { "今天" } else { "10/\{17 + i}" }),
      "tick": Json::string(if i == parts.length() - 1 { "今天" } else { "10/\{17 + i}" }),
      "shares": Json::array(ps.map(fn(p) { Json::number(if cost > 0.0 { p / cost } else { 0.0 }) })),
      "cost": Json::number(cost),
      "parts": Json::array(ps.map(fn(p) { Json::number(p) })),
      "partsText": Json::array(ps.map(fn(p) { Json::string("$\{p.to_int()}") })),
      "costText": Json::string("$\{cost.to_int()}"),
      "callsText": Json::string("\{(cost * 10.0).to_int()} 次调用"),
    })
    max = if cost > max { cost } else { max }
  }
  let series : Array[Json] = if parts.length() > 0 && parts[0].length() > 1 {
    [{ "key": "a", "name": "Ann" }, { "key": "b", "name": "Bo" }]
  } else {
    [{ "key": "a", "name": "Ann" }]
  }
  {
    "daily": Json::array(daily),
    "series": Json::array(series),
    "max": Json::number(max),
    "top": Json::number(100.0),
    "ticks": [{ "value": 50.0, "label": "50" }, { "value": 100.0, "label": "100" }],
  }
}

///|
/// usage_chart over `v` in a card's width (282: a phone's 346 less the page's 12 and the card's 20 each side).
fn days_tester(v : Json) -> @ui.Tester {
  usage_reset()
  let t = @ui.Tester::new(fn(c) {
    c.box(align=AStart, fn() { c.box(w=Px(282.0), fn() { usage_chart(c, Some(v)) }) |> ignore }) |> ignore
  }, platform=2)
  t.draw()
  t
}

///|
test "usage: each day's bar 16 wide in the middle of its day, over its date, on the days' foot, as high as its share of the top" {
  let costs = [20.0, 16.0, 48.0, 80.0, 32.0, 24.0, 8.0]
  let t = days_tester(usage_week(costs.map(fn(c) { [c] })))
  let bars = t.drawn_rects().filter(fn(r) { r.4 == @sf.usage_series(0) && r.2 == 16.0 })
  assert_eq(bars.length(), 7)
  // the most spent 120 high (80 of 100), its foot the days' (its part the corner longer, cut there)
  let (_, top3, _, _, _) = bars[3]
  let foot = top3 + 120.0
  for i, b in bars {
    let (x, y, w, h, _) = b
    let high = 150.0 * costs[i] / 100.0
    assert_eq(w, 16.0)
    assert_true((y - (foot - high)).abs() < 0.01)
    assert_true((h - (high + 4.0)).abs() < 0.01)
    if i < 6 {
      match t.rect_of("10/\{17 + i}") {
        Some((lx, _, lw, _)) => assert_true((lx + lw / 2.0 - (x + w / 2.0)).abs() < 0.5)
        None => fail("no date \{i}")
      }
    }
  }
  // the day picked at first, the last: its cost and calls over the bars; the scale's lines said
  assert_true(t.rect_of("$8") is Some(_))
  assert_true(t.rect_of("80 次调用") is Some(_))
  assert_true(t.rect_of("50") is Some(_) && t.rect_of("100") is Some(_))
}

///|
test "usage: a day split by its people 1 apart, the first at the foot; each of them, what they spent that day, under the days" {
  let parts = [[12.0, 8.0], [10.0, 6.0], [30.0, 18.0], [40.0, 40.0], [20.0, 12.0], [16.0, 8.0], [6.0, 2.0]]
  let t = days_tester(usage_week(parts))
  let ann = t.drawn_rects().filter(fn(r) { r.4 == @sf.usage_series(0) && r.2 == 16.0 })
  let bo = t.drawn_rects().filter(fn(r) { r.4 == @sf.usage_series(1) && r.2 == 16.0 })
  assert_eq((ann.length(), bo.length()), (7, 7))
  // the most spent: Bo's part over Ann's, 1 apart; the two (and the gap) its 120
  let (_, ay, _, ah, _) = ann[3]
  let (_, by, _, bh, _) = bo[3]
  assert_true((by + bh + 1.0 - ay).abs() < 0.01)
  assert_true((ah - 4.0 + bh + 1.0 - 120.0).abs() < 0.01)
  assert_true((bh - 59.5).abs() < 0.01)
  // today's people under the days, each with what they spent
  assert_true(t.rect_of("Ann") is Some(_) && t.rect_of("$6") is Some(_))
  assert_true(t.rect_of("Bo") is Some(_) && t.rect_of("$2") is Some(_))
}
