// Text beyond the end of an activity line should not change what happens within that line.

///|
fn activity_extreme_clock_positions(
  before : String,
  next : String,
  two_agents? : Bool = false,
  w? : Double = 360.0,
  h? : Double = 740.0,
  platform? : Int = 2,
) -> Array[Double] raise {
  let base = fixture_app("chat-working")
  let src : Source = if two_agents {
    {
      ..base,
      topic: fn(name, params) {
        let got = (base.topic)(name, params)
        guard name == "chat" && got.value is Some(Object(chat)) else { return got }
        let agents = items(got.value, "agents").copy()
        agents.push({
          "session": {
            "key": "s-other",
            "runtime": "codex",
            "maker": { "id": "openai", "name": "OpenAI" },
            "agentText": "Codex",
            "statusText": "未开始",
            "tone": "neutral",
          },
          "status": "idle",
        })
        let changed = chat.copy()
        changed["agents"] = Json::array(agents)
        { ..got, value: Some(Json::object(changed)) }
      },
    }
  } else {
    base
  }
  @sffixture.fix_working_now.val = ("call:1", before)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=if two_agents { 0 } else { platform })
  t.run_for(squeeze_opening)
  if two_agents {
    let (x, y, _, h) = t.rect_of(before).unwrap()
    t.move(x + 2.0, y + h / 2.0)
    t.frame()
    assert_true(t.all(Button).iter().any(fn(s) { s.label == "停止 Claude" }), msg="the stop control is visible")
  }
  @sffixture.fix_due.push(fn() { @sffixture.fix_working_now.val = ("call:2", next) })
  @settings.fixture_changed()
  t.draw()
  t.run_for(@sfbase.glyph_change_in_ms)
  let positions : Array[Double] = []
  for _ in 0..=6 {
    guard t.rect_of("3m 20s") is Some((x, _, w, _)) else { fail("the activity clock is visible") }
    if two_agents {
      let stops = t.all(Button).filter(fn(s) { s.label == "停止 Claude" })
      assert_eq(stops.length(), 1, msg="the stop control stays visible")
      assert_true(x + w <= stops[0].rect.0 + 0.5, msg="the clock stays clear of the stop control")
    }
    positions.push(x)
    t.run_for(@ui.move_most_ms / 6.0)
  }
  positions
}

///|
fn activity_extreme_clock_does_not_follow_hidden_words(growing : Bool) -> Unit raise {
  let short = "看"
  let long = "正在检查项目并核对结果".repeat(8)
  let longer = "正在检查项目并核对结果".repeat(24)
  let a = if growing { activity_extreme_clock_positions(short, long) } else { activity_extreme_clock_positions(long, short) }
  let b = if growing { activity_extreme_clock_positions(short, longer) } else { activity_extreme_clock_positions(longer, short) }
  for i in 0..<a.length() {
    assert_true((a[i] - b[i]).abs() < 0.5, msg="invisible words moved the clock at frame \{i}: \{a} / \{b}")
  }
}

///|
test "activity: hidden words do not delay a long step changing to a short one" {
  activity_extreme_clock_does_not_follow_hidden_words(false)
}

///|
test "activity: hidden words do not rush a short step changing to a long one" {
  activity_extreme_clock_does_not_follow_hidden_words(true)
}

///|
fn activity_extreme_clock_moves_through_the_change(growing : Bool) -> Unit raise {
  let short = "看"
  let long = "正在检查项目并核对结果".repeat(8)
  let positions = if growing { activity_extreme_clock_positions(short, long) } else { activity_extreme_clock_positions(long, short) }
  let start = positions[0]
  let middle = positions[2]
  let end = positions[positions.length() - 1]
  let left = dmin(start, end)
  let right = dmax(start, end)
  assert_true(right - left > 2.0, msg="the two steps take different room: \{positions}")
  assert_true(middle > left + 0.5 && middle < right - 0.5, msg="the clock should move through the change: \{positions}")
  for i in 1..<positions.length() {
    let advanced = if growing { positions[i] - positions[i - 1] } else { positions[i - 1] - positions[i] }
    assert_true(advanced >= -0.5, msg="the clock should not jump back: \{positions}")
  }
}

///|
test "activity: the clock moves as a long step becomes short" {
  activity_extreme_clock_moves_through_the_change(false)
}

///|
test "activity: the clock moves as a short step becomes long" {
  activity_extreme_clock_moves_through_the_change(true)
}

///|
test "activity: a stop control keeps its room while a short step becomes long" {
  let short = "看"
  let long = "正在检查项目并核对结果".repeat(8)
  let longer = "正在检查项目并核对结果".repeat(24)
  let a = activity_extreme_clock_positions(short, long, two_agents=true)
  let b = activity_extreme_clock_positions(short, longer, two_agents=true)
  for i in 0..<a.length() {
    assert_true((a[i] - b[i]).abs() < 0.5, msg="invisible words moved the clock: \{a} / \{b}")
  }
}

///|
test "activity: a short step opens smoothly into a long one on a wide screen" {
  let short = "看"
  let long = "正在检查项目并核对结果".repeat(32)
  let longer = "正在检查项目并核对结果".repeat(64)
  let a = activity_extreme_clock_positions(short, long, w=1100.0, h=800.0, platform=0)
  let b = activity_extreme_clock_positions(short, longer, w=1100.0, h=800.0, platform=0)
  assert_true(a[2] > a[0] + 0.5 && a[2] < a[a.length() - 1] - 0.5, msg="the clock moves through the change: \{a}")
  for i in 0..<a.length() {
    assert_true((a[i] - b[i]).abs() < 0.5, msg="invisible words moved the clock: \{a} / \{b}")
    if i > 0 {
      assert_true(a[i] >= a[i - 1] - 0.5, msg="the clock should not jump back: \{a}")
    }
  }
}
