// A profile's page (accounts.mbt, the web's Accounts.tsx AccountView) alone over the settings' fixture: Studio's
// (ws1/st1) Claude subscription and its API key, wide; ChatGPT 团队's.

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
test "a shared subscription's main switch and its station details remain usable at each width" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Profile("ws1/st1", "cc"), w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) {
          calls.push((name, params))
          if name == "profile.share" { done(Ok(obj([]))) } else { (s.call)(name, params, done) }
        } }
    })
    let at = "\{w} platform \{platform}"
    scrolled_to(t, w, "分享给其他 station")
    assert_eq(t.get(Switch, label="分享给其他 station").check, Some(On), msg=at)
    assert_true(t.find("登录在") is Some(_) && t.find("可用的 station") is Some(_), msg=at)
    assert_true(t.find("使用中：MBA") is Some(_), msg=at)
    t.tap_text("登录在")
    t.run_for(@kit.presence_in_ms)
    assert_true(t.find("选择登录的 station") is Some(_), msg=at)
    @sf.presenters_reset()
    t.frame()
    t.tap_text("可用的 station")
    t.run_for(@kit.presence_in_ms)
    assert_true(t.find("以后新加的 station 也能用") is Some(_), msg=at)
    @sf.presenters_reset()
    t.frame()
    t.click(Switch, label="分享给其他 station")
    t.frame()
    let asked = calls.filter(fn(c) { c.0 == "profile.share" })
    assert_eq(asked.length(), 1, msg=at)
    assert_false(flag(Some(asked[0].1), "on"), msg=at)
  }
}

///|
test "a profile's workspace row shows its own mark, but no repeated initial without one" {
  for (w, platform) in page_cases {
    for (emoji, icon) in [("", ""), ("🌱", ""), ("", "glyph:star")] {
      let t = setting_tester(Profile("ws1/st1", "cc"), w, platform~, h=2400.0, over=fn(base) {
        {
          ..base,
          topic: fn(name, params) {
            if name == "memberships" {
              {
                value: Some({
                  "manages": true,
                  "workspaces": [{ "workspace": "ws2", "name": "个人", "home": false, "emoji": Json::string(emoji), "icon": Json::string(icon) }],
                }),
                error: None,
                version: 1,
              }
            } else {
              (base.topic)(name, params)
            }
          },
        }
      })
      let at = "\{w} platform \{platform}, emoji \{emoji}, icon \{icon}"
      assert_true(t.get(Switch, label="个人").check is Some(_), msg=at)
      assert_true(t.boxes().filter(fn(b) { b.text == "个" }).is_empty(), msg=at)
      assert_eq(t.boxes().iter().any(fn(b) { b.text == "🌱" }), emoji != "", msg=at)
      assert_eq(t.shape_boxes().iter().any(fn(b) { b.0.has_prefix("sf/pic/glyph/star/") }), icon != "", msg=at)
    }
  }
}

///|
/// The fixture's Claude subscription before it is shared.
fn unshared_claude(s : Source) -> Source {
  fn without_share(v : Json) -> Json {
    match v {
      Object(o) => {
        let p = o.copy()
        for k, x in o {
          p[k] = without_share(x)
        }
        if o.get("id") == Some(Json::string("cc")) && o.contains("available") {
          p.remove("share")
        }
        Json::object(p)
      }
      Array(a) => Json::array(a.map(without_share))
      _ => v
    }
  }
  {
    ..s,
    topic: fn(name, params) {
      let v = (s.topic)(name, params)
      match v.value {
        Some(x) => { ..v, value: Some(without_share(x)) }
        None => v
      }
    },
  }
}

///|
test "sharing a Claude subscription asks about requests on the target stations before enabling it" {
  for case in page_cases {
    let (w, platform) = case
    let asked : Array[Json] = []
    let t = setting_tester(Profile("ws1/st1", "cc"), w, platform~, over=fn(base) {
      let s = unshared_claude(base)
      { ..s, call: fn(name, params, done) {
        if name == "profile.share" { asked.push(params) }
        (s.call)(name, params, done)
      } }
    })
    let at = "\{w} platform \{platform}"
    scrolled_to(t, w, "分享给其他 station")
    assert_eq(t.get(Switch, label="分享给其他 station").check, Some(Off), msg=at)
    t.click(Switch, label="分享给其他 station")
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_eq(asked.length(), 0, msg="\{at}: not shared before confirmation")
    presented_in(t)
    assert_true(t.find("其他 station 会借用此账号的登录凭证，在各自的机器上直接向 Claude 发送请求") is Some(_), msg=at)
    assert_true(t.find("请自行确保目标 station 能安全访问 Claude") is Some(_), msg=at)
    t.click(Button, label="取消")
    t.run_for(@kit.presence_out_ms)
    assert_eq(asked.length(), 0, msg="\{at}: cancellation does not share")
    assert_eq(t.get(Switch, label="分享给其他 station").check, Some(Off), msg=at)
    t.click(Switch, label="分享给其他 station")
    presented_in(t)
    t.click(Button, label="已了解，分享账号")
    t.frame()
    assert_eq(asked.length(), 1, msg="\{at}: shared after confirmation")
    assert_eq(text(Some(asked[0]), "station"), "ws1/st1", msg=at)
    assert_eq(text(Some(asked[0]), "id"), "cc", msg=at)
    assert_eq(field(Some(asked[0]), "on"), Some(Json::boolean(true)), msg=at)
  }
}

///|
test "sharing other accounts explains how they are used on target stations" {
  for profile in ["cx", "k2"] {
    for case in page_cases {
      let (w, platform) = case
      let asked : Array[Json] = []
      let t = setting_tester(Profile("ws1/st1", profile), w, platform~, over=fn(s) {
        { ..s, call: fn(name, params, done) {
          if name == "profile.share" { asked.push(params) }
          (s.call)(name, params, done)
        } }
      })
      let at = "\{profile} \{w} platform \{platform}"
      scrolled_to(t, w, "分享给其他 station")
      assert_eq(t.get(Switch, label="分享给其他 station").check, Some(Off), msg=at)
      t.click(Switch, label="分享给其他 station")
      t.frame()
      assert_true(@sf.presenting(), msg=at)
      assert_eq(asked.length(), 0, msg=at)
      presented_in(t)
      let body = if profile == "cx" { "借用此账号的登录凭证" } else { "账号配置及其中的密钥会同步" }
      assert_true(t.find(body) is Some(_), msg=at)
      assert_true(t.find("在各自的机器上发送请求") is Some(_), msg=at)
      assert_true(t.find("安全访问 Claude") is None, msg=at)
      t.click(Button, label="取消")
      t.run_for(@kit.presence_out_ms)
      assert_eq(asked.length(), 0, msg=at)
      assert_eq(t.get(Switch, label="分享给其他 station").check, Some(Off), msg=at)
      t.click(Switch, label="分享给其他 station")
      presented_in(t)
      t.click(Button, label="分享账号")
      t.frame()
      assert_eq(asked.length(), 1, msg=at)
      assert_eq(text(Some(asked[0]), "id"), profile, msg=at)
      assert_eq(field(Some(asked[0]), "on"), Some(Json::boolean(true)), msg=at)
    }
  }
}

///|
test "stopping a share does not ask for confirmation" {
  let asked : Array[Json] = []
  let t = setting_tester(Profile("ws1/st1", "cc"), 1280.0, over=fn(s) {
    { ..s, call: fn(name, params, done) {
      if name == "profile.share" { asked.push(params) }
      (s.call)(name, params, done)
    } }
  })
  scrolled_to(t, 1280.0, "分享给其他 station")
  t.click(Switch, label="分享给其他 station")
  t.frame()
  assert_false(@sf.presenting())
  assert_eq(asked.length(), 1)
  assert_eq(field(Some(asked[0]), "on"), Some(Json::boolean(false)))
}

///|
test "a subscription's tier is shown on its page at every width" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Profile("ws1/st1", "cc"), w, platform~)
    assert_true(t.find("订阅账号 · Ultra") is Some(_), msg="tier at width \{w} platform \{platform}")
  }
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

// A profile's quota reset and its models (Accounts.tsx QuotaSection) over ChatGPT 团队: a reset used once asked, its
// models all listed, one named by hand and taken off again.

///|
test "a revoked Codex sign-in offers sign-in from the account check" {
  for (w, platform) in page_cases {
    let t = setting_tester(Profile("ws1/st1", "cx"), w, platform~, mode="settings-profile-quota-login")
    assert_true(t.find("需要登录") is Some(_))
    assert_true(t.find("ChatGPT 登录已失效，请重新登录") is Some(_))
    assert_true(t.find("订阅有效") is None, msg="the earlier account check must not contradict the expired login")
    assert_true(t.find("Studio 可用") is None, msg="this station must not be called usable after its login was refused")
    t.click(Button, label="登录")
    t.frame()
    assert_true(t.find("正在登录 ChatGPT") is Some(_), msg="the sign-in was started at width \{w}")
  }
}

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
test "reset credits show their separate expiry times at every page width" {
  for (w, platform) in page_cases {
    let t = setting_tester(Profile("ws1/st1", "cx"), w, platform~, mode="settings-profile-quota-expiry")
    let note = "剩余 2 次 · 6 小时 35 分钟后、3 天 19 小时后到期"
    scrolled_to(t, w, note)
    assert_true(t.find(note) is Some(_), msg="reset expiries at width \{w}")
    assert_true(t.find("重置额度") is Some(_), msg="reset action at width \{w}")
  }
}

///|
test "a profile's models, a narrow page with a mouse: how many in a row; all of them in a panel, each a box to star; one named by hand added there, then taken off by its ×" {
  let t = setting_tester(Profile("ws1/st1", "cx"), 390.0)
  scrolled_to(t, 390.0, "全部模型")
  assert_true(t.find("12 个模型") is Some(_), msg="how many")
  assert_true(t.find("GPT-6-MINI") is None, msg="not laid out on the page")
  t.tap_text("全部模型")
  t.run_for(@kit.presence_in_ms)
  assert_true(@sf.presenting(), msg="a panel")
  assert_true(t.find("GPT-6-MINI") is Some(_), msg="every one it runs")
  assert_true(t.query(Checkbox, label="喜欢 GPT-6-MINI") is Some(_), msg="its box")
  assert_true(t.query(Button, label="移除 GPT-6-MINI") is None, msg="one its provider lists: not taken off")
  // a name typed, then 添加
  t.tap_text("按名称添加模型")
  t.type_text("my-model")
  t.frame()
  // (添加 alone: the field's placeholder has the word too)
  tap_words(t, "添加")
  t.frame()
  t.frame()
  assert_true(t.query(Button, label="移除 MY-MODEL") is Some(_), msg="the model named, among the rest")
  // its × takes it off again
  t.click(Button, label="移除 MY-MODEL")
  t.frame()
  t.frame()
  assert_true(t.query(Button, label="移除 MY-MODEL") is None, msg="taken off")
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
        p["modelsText"] = "4 个模型"
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
          // (in place of the fixture's own accounts)
          let lists = match o.get("lists") { Some(Array(a)) => a.filter(fn(l) {
                match l {
                  Object(m) => !(m.get("key") is Some(String("profiles", ..)))
                  _ => true
                }
              }); _ => [] }
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
test "a profile's page on a phone: its long name, its figures on one line and how many models it runs, nothing squeezed" {
  // (326, the page android 0.1.6389 cut its name, its Tokens figure and its models' names on, 2026-10-31)
  for w in [326.0, 390.0] {
    let t = setting_tester(Profile("ws1/st1", "cc"), w, platform=2, over=long_profile, h=2400.0)
    // (its switches' words, beside their switches, are another's)
    let faults = t.squeeze_faults().filter(fn(f) { !f.contains("for what shares their row") })
    assert_eq(faults, [], msg=w.to_string() + faults.join("; "))
    assert_true(t.find("模型请求次数") is None && t.find("输入、缓存和输出") is None, msg="\{w}: no calls, nor what tokens are")
    for f in ["$1,735", "49.7 亿", "最多 Opus 5.5", "4 个模型"] {
      assert_true(t.find(f) is Some(_), msg="\{w}: \{f}")
    }
    // its figures side by side
    let (_, y1, _, _) = t.rect_of("$1,735").unwrap()
    let (x3, y3, w3, _) = t.rect_of("49.7 亿").unwrap()
    assert_eq(y3, y1, msg="\{w}: one line")
    assert_true(x3 + w3 <= w, msg="\{w}: inside the page")
  }
}
