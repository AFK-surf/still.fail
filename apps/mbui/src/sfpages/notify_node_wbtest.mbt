// 通知 made once (notify_node) over a made-up core whose `notify` and `workspaceMarks` say
// what a test sets and whose calls wait to be answered: what is chosen shown at once and kept till the core says the
// same (or taken back where it fails), the system's permission in each state, its settings read the first time.

///|
/// A core over `base` whose `notify` (and, where set, `workspaceMarks`) is what `notify` (`marks`) holds, `notify`
/// None while it is read the first time; its calls of `held` kept in `calls` unanswered, to be answered by the test.
fn notify_over(
  base : Source,
  notify : @signals.Signal[Json?],
  marks : @signals.Signal[Json?],
  calls : Array[(String, Json, (Result[Json, Json]) -> Unit)],
  held? : Array[String] = ["notify.set", "prefs.set"],
) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "notify" => { value: notify.get(), error: None, version: 1 }
        "workspaceMarks" if marks.get() is Some(_) => { value: marks.get(), error: None, version: 1 }
        _ => base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      if held.contains(name) {
        calls.push((name, params, done))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
}

///|
/// The made-up core's `notify` (the settings' fixture's), its `field` set to `value`.
fn notify_with(base : Json?, changes : Array[(String, Json)]) -> Json? {
  let o = match base {
    Some(Object(m)) => m.copy()
    _ => {}
  }
  for c in changes {
    o[c.0] = c.1
  }
  Some(Json::object(o))
}

///|
/// `notify`'s kind `kind` set to `value` (the core saying a choice back).
fn notify_kind_set(notify : @signals.Signal[Json?], kind : String, value : Json) -> Unit {
  let now = notify.get()
  let kinds = match field(now, "kinds") {
    Some(Object(m)) => m.copy()
    _ => {}
  }
  kinds[kind] = value
  notify.set(notify_with(now, [("kinds", Json::object(kinds))]))
}

///|
/// The switch named `label` read out: on, off, or none.
fn switch_said(t : @ui.Tester, label : String) -> @view.Check? {
  match t.all(Switch, label~) {
    [s, ..] => s.check
    [] => None
  }
}

///|
test "通知 made once: a kind's banner turned shows at once, kept till the core says the same, then the core's again as it changes; failing, the core's back and the failure said" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let marks : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(Notifications, w, platform~, h=2400.0, over=fn(base) {
      notify.set(base.topic("notify", Map::new()).get().value)
      notify_over(base, notify, marks, calls)
    })
    let banner = @sf.t("web-pages.notifications.ways.banner")
    t.click(Button, label=@sf.t("web-pages.notifications.kinds.wait"))
    t.draw()
    assert_eq(switch_said(t, banner), Some(On), msg=at)
    t.click(Switch, label=banner)
    t.draw()
    // shown at once, asked of the core once
    assert_eq(switch_said(t, banner), Some(Off), msg=at)
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(field(field(Some(calls[0].1), "kinds"), "wait"), Some(Json::boolean(false)), msg=at)
    // answered, the core not yet saying it: still as chosen
    (calls[0].2)(Ok(Json::object({})))
    t.draw()
    assert_eq(switch_said(t, banner), Some(Off), msg=at)
    // the core says the same: its word from then on (another device turning it back on, shown)
    notify_kind_set(notify, "wait", Json::boolean(false))
    t.draw()
    assert_eq(kinds_chosen.get("wait"), None, msg=at)
    notify_kind_set(notify, "wait", Json::boolean(true))
    t.draw()
    assert_eq(switch_said(t, banner), Some(On), msg=at)
    // failing: as the core has it again, and said
    t.click(Switch, label=banner)
    t.draw()
    assert_eq(switch_said(t, banner), Some(Off), msg=at)
    (calls[1].2)(Err(Json::object({ "message": Json::string("boom") })))
    t.draw()
    assert_eq(switch_said(t, banner), Some(On), msg=at)
    assert_true(app.toast.get().words.contains("boom"), msg="\{at}: \{app.toast.get().words}")
  }
}

///|
test "通知 made once: the badge's tile turned shows at once and its kinds' switches follow it, kept till the core's marks say the same" {
  // (where the system shows the app's number: a Mac's Dock)
  for w in [390.0, 1000.0] {
    let at = "\{w}"
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let marks : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(Notifications, w, platform=0, h=2400.0, over=fn(base) {
      notify.set(base.topic("notify", Map::new()).get().value)
      marks.set(base.topic("workspaceMarks", { "workspace": Json::string("ws1") }).get().value)
      notify_over(base, notify, marks, calls)
    })
    let badge = @sf.t("web-pages.notifications.ways.badge")
    let in_badge = @sf.t("web-pages.notifications.inBadge")
    t.click(Button, label=@sf.t("web-pages.notifications.kinds.wait"))
    t.draw()
    let tile_on = fn() raise { t.get(Button, label=badge).pressed }
    let first = tile_on()
    let counted = t.get(Switch, label=in_badge)
    assert_eq(counted.disabled, first != Some(true), msg=at)
    t.click(Button, label=badge)
    t.draw()
    assert_eq(tile_on(), Some(first != Some(true)), msg=at)
    assert_eq(t.get(Switch, label=in_badge).disabled, first == Some(true), msg=at)
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].0, "prefs.set", msg=at)
    // the core's marks say the same: its word from then on
    let kinds = match field(marks.get(), "badgeKinds") {
      Some(Object(m)) => m.copy()
      _ => {}
    }
    kinds["on"] = Json::boolean(first != Some(true))
    marks.set(notify_with(marks.get(), [("badgeKinds", Json::object(kinds))]))
    t.draw()
    assert_eq(badge_chosen.get("on"), None, msg=at)
    assert_eq(tile_on(), Some(first != Some(true)), msg=at)
  }
}

///|
test "通知 made once: the banner's tile turned while that is on its way: a spinner in its place, turned again nothing asked; answered, as the core says" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let marks : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(Notifications, w, platform~, h=2400.0, over=fn(base) {
      notify.set(base.topic("notify", Map::new()).get().value)
      notify_over(base, notify, marks, calls)
    })
    let banner = @sf.t("web-pages.notifications.ways.banner")
    assert_eq(t.get(Button, label=banner).pressed, Some(true), msg=at)
    t.click(Button, label=banner)
    t.draw()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(field(Some(calls[0].1), "on"), Some(Json::boolean(false)), msg=at)
    // (its state's words gone for the spinner)
    let tile = t.get(Button, label=banner).rect
    let in_tile = fn(s : String) {
      t.words().iter().any(fn(x) { x.0 == s && x.1 >= tile.0 && x.1 < tile.0 + tile.2 && x.2 >= tile.1 && x.2 < tile.1 + tile.3 })
    }
    assert_true(!in_tile(@sf.t("web-pages.notifications.on")) && !in_tile(@sf.t("web-pages.notifications.off")), msg=at)
    t.click(Button, label=banner)
    t.draw()
    assert_eq(calls.length(), 1, msg="\{at}: turned again while on its way")
    notify.set(notify_with(notify.get(), [("on", Json::boolean(false))]))
    (calls[0].2)(Ok(Json::object({})))
    t.draw()
    assert_eq(t.get(Button, label=banner).pressed, Some(false), msg=at)
    assert_true(in_tile(@sf.t("web-pages.notifications.off")), msg=at)
  }
}

///|
test "通知 made once, as the system has notifications: not asked yet, asked of it; refused, its settings; given, turned here; the banner never said on till given" {
  for case in page_cases {
    let (w, platform) = case
    for state in ["default", "denied", "granted"] {
      let at = "\{w} platform \{platform} \{state}"
      let notify : @signals.Signal[Json?] = @signals.signal(None)
      let marks : @signals.Signal[Json?] = @signals.signal(None)
      let calls = []
      let over = fn(base : Source) {
        notify.set(notify_with(base.topic("notify", Map::new()).get().value, [("permission", Json::string(state))]))
        notify_over(base, notify, marks, calls)
      }
      // (the device's system as the core says it: asked of it only where it has not been)
      let host = fn(t : @ui.Tester) { t.set_notice_permission(state) }
      let t = setting_tester(Notifications, w, platform~, h=2400.0, over~, host~)
      let banner = @sf.t("web-pages.notifications.ways.banner")
      // (on as the core keeps it, the system's word wanting: not said on)
      assert_eq(t.get(Button, label=banner).pressed, Some(state == "granted"), msg=at)
      let asks = t.notice_asks()
      t.click(Button, label=banner)
      t.draw()
      assert_eq(t.notice_asks() - asks, if state == "default" { 1 } else { 0 }, msg=at)
      assert_eq(t.notice_settings_opened(), if state == "denied" { 1 } else { 0 }, msg=at)
      assert_eq(calls.length(), if state == "granted" { 1 } else { 0 }, msg=at)
    }
  }
}

///|
test "通知 made once, its settings read the first time: their cards in their bones, none of them found; then the page" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let marks : @signals.Signal[Json?] = @signals.signal(None)
    let kept : Ref[Json?] = Ref(None)
    let t = setting_tester(Notifications, w, platform~, over=fn(base) {
      kept.val = base.topic("notify", Map::new()).get().value
      notify_over(base, notify, marks, [])
    })
    assert_true(t.find(@sf.t("web-pages.notifications.ways.title")) is None, msg=at)
    assert_true(t.find(@sf.t("web-pages.notifications.kinds.wait")) is None, msg=at)
    notify.set(kept.val)
    t.draw()
    assert_true(t.find(@sf.t("web-pages.notifications.ways.title")) is Some(_), msg=at)
    assert_true(t.find(@sf.t("web-pages.notifications.kinds.wait")) is Some(_), msg=at)
  }
}

///|
test "通知 made once: each workspace's switch turns it; notifications off, they and the preview's are off, a kind's banner too" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let notify : @signals.Signal[Json?] = @signals.signal(None)
    let marks : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(Notifications, w, platform~, h=2400.0, over=fn(base) {
      notify.set(base.topic("notify", Map::new()).get().value)
      notify_over(base, notify, marks, calls)
    })
    assert_eq(switch_said(t, "个人"), Some(Off), msg=at)
    t.click(Switch, label="个人")
    t.draw()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(field(field(Some(calls[0].1), "workspaces"), "ws2"), Some(Json::boolean(true)), msg=at)
    notify.set(notify_with(notify.get(), [("on", Json::boolean(false))]))
    t.click(Button, label=@sf.t("web-pages.notifications.kinds.wait"))
    t.draw()
    for s in ["个人", "星火工作室", @sf.t("web-pages.notifications.preview"), @sf.t("web-pages.notifications.ways.banner")] {
      assert_true(t.get(Switch, label=s).disabled, msg="\{at}: \{s}")
    }
    t.click(Switch, label="星火工作室")
    t.draw()
    assert_eq(calls.length(), 1, msg="\{at}: a switch that is off turned")
  }
}

///|
test "通知 made once: a kind opened shows its ways and the preview its banner; opened again, shut" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Notifications, w, platform~, h=2400.0)
    let failed = @sf.t("web-pages.notifications.kinds.failed")
    t.click(Button, label=failed)
    t.draw()
    assert_eq(t.get(Button, label=failed).expanded, Some(true), msg=at)
    assert_true(t.find(@sf.t("web-pages.notifications.sample.failed")) is Some(_), msg=at)
    t.click(Button, label=failed)
    t.draw()
    assert_eq(t.get(Button, label=failed).expanded, Some(false), msg=at)
    assert_true(t.all(Switch, label=@sf.t("web-pages.notifications.ways.banner")).is_empty(), msg=at)
  }
}
