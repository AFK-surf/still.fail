// 权限, 归档 and a station's own archiving (permissions.mbt) alone, at each width, with a finger and with a mouse: what
// each station does and each way to choose saves is the core's.

///|
test "权限, at each width and with either hand: notifications, what they are for and whether they are allowed, on a card" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Permissions, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("通知") is Some(_), msg=at)
    assert_true(t.find("已允许") is Some(_), msg=at)
  }
}

///|
test "permissions made once follow the system's permission and offer the right action" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let (w, platform) = case
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let t = setting_tester(Permissions, w, platform~, over=fn(base) {
      notify.set(notify_with((base.topic)("notify", Map::new()).value, [("permission", Json::string("default"))]))
      notify_over(base, notify, @signals.signal(None), [])
    }, host=fn(host) { host.set_notice_permission("default") })
    assert_true(t.find(@sf.t("web-pages.permissions.state.default")) is Some(_))
    let asks = t.notice_asks()
    t.click(Button, label=@sf.t("web-pages.permissions.allow"))
    t.draw()
    assert_eq(t.notice_asks() - asks, 1)
    notify.set(notify_with(notify.get(), [("permission", Json::string("denied"))]))
    t.draw()
    assert_true(t.find(@sf.t("web-pages.permissions.state.denied")) is Some(_))
    assert_true(t.all(Button, label=@sf.t("web-pages.permissions.allow")).length() == 0)
    t.click(Button, label=@sf.t("web-pages.permissions.open"))
    t.draw()
    assert_eq(t.notice_settings_opened(), 1)
    notify.set(notify_with(notify.get(), [("permission", Json::string("granted"))]))
    t.draw()
    assert_true(t.find(@sf.t("web-pages.permissions.state.granted")) is Some(_))
    assert_true(t.all(Button, label=@sf.t("web-pages.permissions.open")).length() == 0)
    notify.set(notify_with(notify.get(), [("permission", Json::string("unexpected"))]))
    t.draw()
    assert_true(t.find(@sf.t("web-pages.permissions.state.unknown")) is Some(_))
  }
}

///|
test "permissions keep the focused action through a page-width change" {
  let width = @signals.signal(700.0)
  let notify : @signals.Signal[Json?] = @signals.signal(None)
  let t = setting_tester(Permissions, 700.0, platform=0, layout_width=fn() { width.get() }, over=fn(base) {
    notify.set(notify_with((base.topic)("notify", Map::new()).value, [("permission", Json::string("default"))]))
    notify_over(base, notify, @signals.signal(None), [])
  }, host=fn(host) { host.set_notice_permission("default") })
  let allow = @sf.t("web-pages.permissions.allow")
  let open = @sf.t("web-pages.permissions.open")
  t.act(Button, Focus, label=allow)
  width.set(390.0)
  t.resize(390.0, 900.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some(allow))
  let asks = t.notice_asks()
  t.key(@ui.key_code_enter)
  assert_eq(t.notice_asks() - asks, 1)
  // A different action replacing the old one must not inherit its focus.
  notify.set(notify_with(notify.get(), [("permission", Json::string("denied"))]))
  t.draw()
  assert_true(t.focused().map(fn(s) { s.label }) != Some(open))
  t.act(Button, Focus, label=open)
  width.set(700.0)
  t.resize(700.0, 900.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some(open))
  t.key(@ui.key_space)
  assert_eq(t.notice_settings_opened(), 1)
}

///|
test "归档, at each width and with either hand: the hint, its three ways, each station a row saying how it archives; its row opens its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Archiving, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("提示归档") is Some(_), msg=at)
    assert_true(t.find("按模型判断") is Some(_), msg=at)
    assert_true(t.find("空闲就归档 · 1 天 · Slack：3 天") is Some(_), msg=at)
    t.tap_text("Willow")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(StationArchiving("ws1/st1")), msg=at)
  }
}

///|
test "a station's archiving, at each width and with either hand: its review, its way, how long idle, Slack's; a way chosen saves what the core says it saves" {
  for case in page_cases {
    let (w, platform) = case
    let saved : Array[Json] = []
    let keep = fn(base : Source) -> Source {
      {
        ..base,
        call: fn(name, params, done) {
          if name == "archiving.save" {
            saved.push(params)
          }
          (base.call)(name, params, done)
        },
      }
    }
    let t = setting_tester(StationArchiving("ws1/st1"), w, platform~, over=keep)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已开启 · GPT-6 mini") is Some(_), msg=at)
    assert_true(t.find("空闲多久") is Some(_), msg=at)
    assert_true(t.find("只在 Slack 里的对话") is Some(_), msg=at)
    // 按模型判断 chosen: the days kept, reviewed (the core's `modes`)
    t.tap_text("按模型判断")
    t.draw()
    t.draw()
    assert_eq(saved.length(), 1, msg=at)
    assert_eq(field(Some(saved[0]), "reviewed"), Some(Json::boolean(true)), msg=at)
    assert_eq(number(Some(saved[0]), "days"), 1.0, msg=at)
  }
}
