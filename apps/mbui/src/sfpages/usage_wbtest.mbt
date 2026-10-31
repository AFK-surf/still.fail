// 用量's days (usage.mbt usage_chart, the web's Usage.tsx DaysChart): each day's bar in the middle of its day over its
// date, standing on the days' foot as high as its share of the scale's top; all in full until a day is picked, then
// the others faded, the day pressed again let go. And the page: what someone opening it wants to know, most first.

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
/// Whether a drawn rect is in `ink`, faded or not (the days but the one shown are drawn faded).
fn usage_inked(r : (Double, Double, Double, Double, Int64), ink : Int64) -> Bool {
  r.4 >> 8 == ink >> 8
}

///|
/// usage_chart over `v` in a card's width (282: a phone's 346 less the page's 12 and the card's 20 each side).
fn days_tester(v : Json) -> @ui.Tester {
  usage_reset()
  let t = @ui.Tester::new(fn(c) {
    c.box(align=AStart, fn() { c.box(w=Px(282.0), fn() { usage_chart(c, Some(v)) |> ignore }) |> ignore }) |> ignore
  }, platform=2)
  t.draw()
  t
}

///|
test "usage: each day's bar 16 wide in the middle of its day, over its date, on the days' foot, as high as its share of the top" {
  let costs = [20.0, 16.0, 48.0, 80.0, 32.0, 24.0, 8.0]
  let t = days_tester(usage_week(costs.map(fn(c) { [c] })))
  let bars = t.drawn_rects().filter(fn(r) { usage_inked(r, @sf.usage_series(0)) && r.2 == 16.0 })
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
  // none picked at first: every day's bar in full; the scale's lines said
  assert_eq(bars.filter(fn(r) { r.4 == @sf.usage_series(0) }).length(), 7)
  assert_eq(usage_pick.day.get(), "")
  assert_true(t.rect_of("50") is Some(_) && t.rect_of("100") is Some(_))
}

///|
test "usage: a finger slid across the days lets go on a day: it stays, the others faded; a day tapped, then tapped again, let go" {
  let costs = [20.0, 16.0, 48.0, 80.0, 32.0, 24.0, 8.0]
  let t = days_tester(usage_week(costs.map(fn(c) { [c] })))
  let at = fn(label : String) -> (Double, Double) {
    let (x, y, w, h) = t.rect_of(label).unwrap()
    (x + w / 2.0, y + h / 2.0)
  }
  let full = fn() {
    t.drawn_rects().filter(fn(r) { usage_inked(r, @sf.usage_series(0)) && r.2 == 16.0 && r.4 == @sf.usage_series(0) })
  }
  // slid from over 10/19's bar across to 10/21's date and let go there: it stays
  let (x2, y2) = at("10/19")
  let (x4, y4) = at("10/21")
  t.drag(x2, y2 - 60.0, x4, y4)
  t.draw()
  assert_eq(usage_pick.day.get(), "2026-10-21")
  assert_eq(full().length(), 1)
  // a tap on a date picks its day: its bar alone in full, the first
  let (x0, y0) = at("10/17")
  t.tap(x0, y0)
  t.draw()
  assert_eq(usage_pick.day.get(), "2026-10-17")
  assert_eq(full().length(), 1)
  assert_eq(full()[0].0, t.drawn_rects().filter(fn(r) { usage_inked(r, @sf.usage_series(0)) && r.2 == 16.0 })[0].0)
  // tapped again: let go, every day in full
  t.tap(x0, y0)
  t.draw()
  assert_eq(usage_pick.day.get(), "")
  assert_eq(full().length(), 7)
}

///|
test "用量, at each width and with either hand: the cost and its change, what it is made of, the allowance, the chats, the makeup, the days, the calls; a day picked, then let go; 30 天 picked" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Usage, w, platform~)
    let at = "\{w} platform \{platform}"
    // the cost, its change, and who spent it under it
    assert_true(t.find("$118") is Some(_) && t.find("↑18%") is Some(_) && t.find("比前 7 天") is Some(_), msg=at)
    assert_true(t.find("$80") is Some(_), msg=at)
    // the subscription's allowance beside what it spent
    assert_true(t.find("lin@example.com") is Some(_) && t.find("折合 $84") is Some(_), msg=at)
    // the chats that cost the most, each with who and which model
    assert_true(t.find("整理发布清单") is Some(_) && t.find("林 · Opus 5.5 · Studio") is Some(_), msg=at)
    // the people, the models and the accounts at once
    assert_true(t.find("按人") is Some(_) && t.find("按模型") is Some(_) && t.find("按账号") is Some(_), msg=at)
    assert_true(t.find("GPT-6") is Some(_) && t.find("Codex 团队") is Some(_), msg=at)
    // the calls and tokens, under the rest
    assert_true(t.find("1,416 次") is Some(_), msg=at)
    // a day picked (the days far down: scrolled to): everything of it, said over it, its chip back to all the days
    t.scroll_to_end()
    t.draw()
    t.tap_text("10/3")
    t.draw()
    t.scroll_to(0)
    t.draw()
    assert_true(t.find("折合费用 · 10/3") is Some(_) && t.find("$20") is Some(_), msg=at)
    t.tap_text("只看 10/3")
    t.draw()
    assert_true(t.find("折合费用 · 近 7 天") is Some(_) && t.find("$118") is Some(_), msg=at)
    t.tap_text("30 天")
    t.draw()
    assert_true(t.find("$486") is Some(_), msg=at)
    // 30 days: a date a week under the bars (the core's `tick`), today's among them
    assert_true(t.find("10/23") is Some(_), msg=at)
    assert_true(t.find("10/24") is None, msg=at)
  }
}

///|
test "价目表, at each width and with either hand: each station's card, its note, its models and rates; none said where it has none" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(UsagePrices(7), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("价目表") is Some(_), msg=at)
    assert_true(t.find("每百万 token 的美元价格") is Some(_), msg=at)
    assert_true(t.find("Opus 5.5") is Some(_), msg=at)
    assert_true(t.find("$25") is Some(_), msg=at)
    assert_true(t.find("读不到它的价格表") is Some(_), msg=at)
  }
}
