// A profile's page (accounts.mbt, the web's Accounts.tsx AccountView) alone over the settings' fixture: Studio's
// (ws1/st1) Claude subscription and its API key, wide; the step right after a profile is added and a profile's models,
// one page each in every frame, at each width with either hand, over ChatGPT 团队.

///|
test "a profile's page, wide: who it is and whether it works, then its allowance, what it spent, who uses it, how it runs, sharing" {
  let t = setting_tester(Profile("ws1/st1", "cc"), 1280.0)
  // its head: its name, what it is (the core's words), its last check
  assert_true(t.find("Claude 主账号") is Some(_))
  assert_true(t.find("订阅账号") is Some(_), msg="what it is")
  assert_true(t.find("订阅有效") is Some(_), msg="its check in a line")
  // what is left of its allowance, a dial each
  assert_true(t.find("额度") is Some(_))
  assert_true(t.find("5 小时") is Some(_) && t.find("本周") is Some(_), msg="its windows")
  // who uses it, how it runs, whom it is shared with
  scrolled_to(t, 1280.0, "使用它的连接")
  assert_true(t.find("使用它的连接") is Some(_))
  scrolled_to(t, 1280.0, "默认 Fast")
  assert_true(t.find("默认 Fast") is Some(_))
  scrolled_to(t, 1280.0, "分享给其他 station")
  assert_true(t.find("分享给其他 station") is Some(_), msg="sharing")
}

///|
test "a key's profile's page, wide: its key masked, a new one asked for from its row" {
  let t = setting_tester(Profile("ws1/st1", "k2"), 1280.0)
  assert_true(t.find("备用 key") is Some(_))
  scrolled_to(t, 1280.0, "sk-…a41f")
  assert_true(t.find("sk-…a41f") is Some(_), msg="its key masked")
  // (the row's own: its trouble's 更换 key may be drawn above, out of sight)
  tap_words(t, "更换")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新的 API key") is Some(_), msg="a new key asked for")
}

///|
test "a profile's page, wide: a profile one of the station's lists no more says so" {
  let t = setting_tester(Profile("ws1/st1", "gone"), 1280.0)
  assert_true(t.find("找不到 ID 为 gone 的 Profile") is Some(_))
}

///|
test "a profile just added, at each width and with either hand: its models to choose; 跳过 goes on to its page in this one's place" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(PickModels("ws1/st1", "cx"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("选择模型") is Some(_), msg=at)
    assert_true(t.find("ChatGPT 团队") is Some(_), msg=at)
    // its list, by the core's series
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("完成") is Some(_), msg=at)
    tap_words(t, "跳过")
    t.run_for(@ui.move_most_ms)
    // (in this one's place: none of it left under its page)
    assert_true(app.nav.top() == Setting(Profile("ws1/st1", "cx")), msg=at)
    assert_false(app.nav.pages().contains(Setting(PickModels("ws1/st1", "cx"))), msg=at)
  }
}

///|
test "a profile's models, at each width and with either hand: how many are on, each to tick" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(ProfileModels("ws1/st1", "cx"), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已选 1 项") is Some(_), msg=at)
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("GPT-5.5") is Some(_), msg=at)
    // read again, at the title's end
    assert_true(t.find("刷新模型") is Some(_), msg=at)
  }
}

///|
test "a profile's models, wide with a mouse: the series side by side, a model's id right under its name" {
  let t = setting_tester(ProfileModels("ws1/st1", "cx"), 1280.0)
  // the third of GPT-6 and of GPT-5.5 on one line, the second series beside the first
  match (t.find("GPT-6-NANO"), t.find("GPT-5.5-CODEX")) {
    (Some((x6, y6)), Some((x55, y55))) => {
      assert_true((y6 - y55).abs() < 1.0, msg="side by side")
      assert_true(x55 > x6, msg="the newer first")
    }
    _ => abort("no GPT-6-NANO or GPT-5.5-CODEX")
  }
  // its id under the pointer, under its own words (not under the middle of the page)
  let (nx, ny) = t.find("O9-MINI").unwrap()
  t.move(nx, ny)
  t.run_for(@sf.tip_delay_ms + 200.0)
  match t.find("o9-mini") {
    Some((tx, ty)) => {
      assert_true((tx - nx).abs() < 40.0, msg="under its name: \{tx} for \{nx}")
      assert_true(ty > ny, msg="under it")
    }
    None => abort("no tip")
  }
  t.leave()
  t.run_for(@kit.tooltip_delay_ms)
}

///|
test "a profile's page, wide: its models other profiles could have are given to those ticked in a dialog" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 1280.0)
  // on the page only the press that opens them, with how many could be given
  scrolled_to(t, 1280.0, "加到其他 profile（2）")
  assert_true(t.find("团队 key") is None, msg="not on the page")
  t.tap_text("加到其他 profile（2）")
  t.run_for(@kit.presence_in_ms)
  assert_true(@sf.presenting(), msg="a dialog")
  assert_true(t.find("GPT-6-MINI") is Some(_))
  assert_true(t.find("备用 key") is Some(_) && t.find("团队 key") is Some(_))
  // none ticked: nothing to add yet; one ticked, added to it alone
  tap_words(t, "备用 key")
  t.frame()
  tap_words(t, "添加")
  t.frame()
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("加到其他 profile（1）") is Some(_), msg="团队 key still offered")
}

// A profile's quota reset and its models (Accounts.tsx QuotaSection, ModelPool) over ChatGPT 团队: a reset used once
// asked, its models chosen in place (ModelChecklist): a model named by hand, a filter over the many.

///|
test "a profile's quota, a narrow page with a mouse: 重置额度 asks first, then uses one of the resets left" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 390.0)
  scrolled_to(t, 390.0, "还可重置 2 次")
  t.tap_text("重置额度")
  t.frame()
  assert_true(@sf.presenting(), msg="asked first")
  assert_true(t.find("重置额度？") is Some(_))
  assert_true(t.find("将使用「ChatGPT 团队」的 1 次额度重置，剩余 2 次") is Some(_))
  // (with a mouse: the web's confirm, come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("使用一次重置")
  t.frame()
  t.frame()
  assert_true(t.find("还可重置 1 次") is Some(_))
}

///|
test "a profile's models, a narrow page with a mouse: chosen in place, one named by hand is added, the filter leaves what has its words" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 390.0)
  // on its page, 模型's 选择模型 (how many of how many on) opens the whole list there
  scrolled_to(t, 390.0, "选择模型（1 / 12）")
  t.tap_text("选择模型（1 / 12）")
  t.draw()
  assert_true(t.find("收起") is Some(_))
  scrolled_to(t, 390.0, "筛选模型")
  assert_true(t.find("O9-MINI") is Some(_))
  // a name typed, then 添加
  scrolled_to(t, 390.0, "按名称添加模型")
  t.tap_text("按名称添加模型")
  t.type_text("my-model")
  t.frame()
  // (添加 alone: the field's placeholder has the word too)
  tap_words(t, "添加")
  t.frame()
  t.frame()
  scrolled_to(t, 390.0, "MY-MODEL")
  assert_true(t.find("MY-MODEL") is Some(_), msg="the model named, among the rest")
  // a filter: 全选 / 取消 say they are of what it leaves
  scrolled_to(t, 390.0, "筛选模型")
  t.tap_text("筛选模型")
  t.type_text("codex")
  t.frame()
  assert_true(t.find("GPT-6-CODEX") is Some(_))
  assert_true(t.find("O9-MINI") is None)
  assert_true(t.find("全选筛选结果") is Some(_))
  assert_true(t.find("取消选择筛选结果") is Some(_))
}

///|
/// The fixture's Claude subscription as android 0.1.6389 showed one (2026-10-31): named by its long address, four
/// models on, its last 7 days' figures large.
fn long_profile(s : Source) -> Source {
  fn shaped(v : Json) -> Json {
    match v {
      Object(o) if o.get("id") == Some(Json::string("cc")) && o.contains("available") => {
        let p = o.copy()
        let ms : Array[Json] = ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5", "claude-haiku-5"]
        p["name"] = "claude5@jimmfly.example.com"
        p["models"] = Json::array(ms)
        p["available"] = Json::array(ms)
        p["names"] = { "claude-fable-5-1": "Fable 5.1", "claude-opus-5-5": "Opus 5.5", "claude-sonnet-5": "Sonnet 5", "claude-haiku-5": "Haiku 5" }
        p["series"] = [{ "name": "Claude", "models": Json::array(ms) }]
        Json::object(p)
      }
      Object(o) => {
        let p = o.copy()
        for k, x in o {
          p[k] = shaped(x)
        }
        if o.contains("lists") && o.contains("tiles") {
          let lists = match o.get("lists") { Some(Array(a)) => a.copy(); _ => [] }
          lists.push({ "key": "profiles", "items": [{ "key": "ws1/st1/cc", "costText": "$1,735", "shareText": "64%", "callsText": "2.2 万", "tokensText": "49.7 亿", "topModel": "最多 Opus 5.5" }] })
          p["lists"] = Json::array(lists)
        }
        Json::object(p)
      }
      Array(a) => Json::array(a.map(shaped))
      _ => v
    }
  }
  {
    ..s,
    topic: fn(name, params) {
      let v = (s.topic)(name, params)
      match v.value {
        Some(x) => { ..v, value: Some(shaped(x)) }
        None => v
      }
    },
  }
}

///|
test "a profile's page on a phone: its long name, its figures on one line and its models' names whole, nothing squeezed" {
  // (326, the page android 0.1.6389 cut its name, its Tokens figure and its models' names on, 2026-10-31)
  for w in [326.0, 390.0] {
    let t = setting_tester(Profile("ws1/st1", "cc"), w, platform=2, over=long_profile, h=2400.0)
    // (its switches' words, beside their switches, are another's)
    let faults = t.squeeze_faults().filter(fn(f) { !f.contains("for what shares their row") })
    assert_eq(faults, [], msg=w.to_string() + faults.join("; "))
    assert_true(t.find("模型请求次数") is None && t.find("输入、缓存和输出") is None, msg="\{w}: no calls, nor what tokens are")
    for f in ["$1,735", "49.7 亿", "最多 Opus 5.5", "Fable 5.1", "Opus 5.5", "Sonnet 5", "Haiku 5"] {
      assert_true(t.find(f) is Some(_), msg="\{w}: \{f}")
    }
    // its figures side by side
    let (_, y1, _, _) = t.rect_of("$1,735").unwrap()
    let (x3, y3, w3, _) = t.rect_of("49.7 亿").unwrap()
    assert_eq(y3, y1, msg="\{w}: one line")
    assert_true(x3 + w3 <= w, msg="\{w}: inside the page")
  }
}
