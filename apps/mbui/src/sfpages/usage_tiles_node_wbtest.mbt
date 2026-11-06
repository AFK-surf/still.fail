// Usage tiles follow the card and the context action as they change, and keep their node while those values change.

///|
fn usage_tiles_test_card() -> Json? {
  Some({
    "cost": "$0.47",
    "cache": { "text": "67%" },
    "context": { "percent": 81.6, "text": "81,600 / 100,000", "level": "amber", "unknown": false },
  })
}

///|
fn usage_tiles_tester(
  card : @signals.Signal[Json?],
  busy : @signals.Signal[Bool],
  compacts : @signals.Signal[Bool],
  can_open : @signals.Signal[Bool],
  shown : @signals.Signal[Bool],
  pressed : Ref[Array[Int]],
  width : Double,
  platform : Int,
) -> @ui.Tester {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=500.0, h=300.0, platform~, stable=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.show(fn() { shown.get() }, fn(box) {
      box.offset(Is((20.0, 40.0))).width(Is(Some(width))) |> ignore
      usage_tiles_node(box, fn() { card.get() }, fn() { busy.get() }, fn() { compacts.get() },
        fn() { can_open.get() }, fn(tile) { pressed.val.push(tile.id()) })
    })
  })
  t.draw()
  t
}

///|
test "usage tiles follow figures, availability and context level without replacing the context action" {
  let card = @signals.signal(usage_tiles_test_card())
  let busy = @signals.signal(false)
  let compacts = @signals.signal(true)
  let can_open = @signals.signal(true)
  let shown = @signals.signal(true)
  let pressed : Ref[Array[Int]] = Ref([])
  for width in [288.0, 420.0] {
    let t = usage_tiles_tester(card, busy, compacts, can_open, shown, pressed, width, 0)
    let cost = t.find("$0.47").unwrap()
    let cache = t.find("67%").unwrap()
    let context = t.find("82%").unwrap()
    assert_true(cost.0 < cache.0 && cache.0 < context.0, msg="cost, cache and context share a row")
    assert_eq(cost.1, cache.1)
    assert_eq(cache.1, context.1)
    let action = t.get(Button, label=@sf.t("web-pages.chat.contextActions"))
    assert_true(t.find(@sf.t("web-mobile.agent.contextCompactable")) is Some(_))
    card.set(Some({ "cost": "$1.23", "context": { "percent": 20.4, "text": "20,400 / 100,000", "level": "", "unknown": false } }))
    t.draw()
    assert_true(t.find("$1.23") is Some(_) && t.find("67%") is None && t.find("20%") is Some(_))
    assert_true(t.find(@sf.t("web-main.chat.agentCard.context")) is Some(_))
    assert_eq(t.get(Button, label=@sf.t("web-pages.chat.contextActions")).id, action.id)
    card.set(Some({ "context": { "unknown": true, "text": "Unknown", "level": "red" } }))
    t.draw()
    assert_true(t.find("Unknown") is Some(_))
    assert_true(t.find(@sf.t("web-mobile.agent.contextCompactable")) is None)
    assert_eq(t.get(Button, label=@sf.t("web-pages.chat.contextActions")).id, action.id)
    card.set(None)
    t.draw()
    assert_true(t.query(Button, label=@sf.t("web-pages.chat.contextActions")) is None)
    card.set(usage_tiles_test_card())
  }
}

///|
test "usage context opens on mouse, touch, keyboard and accessibility activation, and stays disabled while busy" {
  let card = @signals.signal(usage_tiles_test_card())
  let busy = @signals.signal(false)
  let compacts = @signals.signal(true)
  let can_open = @signals.signal(true)
  let shown = @signals.signal(true)
  let pressed : Ref[Array[Int]] = Ref([])
  let t = usage_tiles_tester(card, busy, compacts, can_open, shown, pressed, 288.0, 0)
  let action = t.get(Button, label=@sf.t("web-pages.chat.contextActions"))
  let (x, y) = (action.rect.0 + action.rect.2 / 2.0, action.rect.1 + action.rect.3 / 2.0)
  t.touch(0, x, y); t.touch(2, x, y)
  t.touch_raw(0, 1, x, y, t.time()); t.touch_raw(2, 1, x, y, t.time())
  t.key_told(@ui.key_tab, 0, t.time())
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.ctx().ask_action(action.id, Activate)
  assert_eq(pressed.val, [action.id, action.id, action.id, action.id])
  busy.set(true)
  t.draw()
  assert_true(t.get(Button, label=@sf.t("web-pages.chat.contextActions")).disabled)
  t.touch(0, x, y); t.touch(2, x, y)
  t.key_told(@ui.key_code_enter, 0, t.time())
  t.ctx().ask_action(action.id, Activate)
  assert_eq(pressed.val.length(), 4)
  busy.set(false)
  t.draw()
  assert_eq(t.get(Button, label=@sf.t("web-pages.chat.contextActions")).id, action.id)
  t.ctx().ask_action(action.id, Activate)
  assert_eq(pressed.val.length(), 5)
  shown.set(false)
  t.draw()
  t.ctx().ask_action(action.id, Activate)
  assert_eq(pressed.val.length(), 5, msg="a removed tile cannot be activated")
}

///|
test "usage context without actions reveals its full value by pointer and a finger's hold" {
  for platform in [0, 1] {
    let card = @signals.signal(usage_tiles_test_card())
    let busy = @signals.signal(false)
    let compacts = @signals.signal(false)
    let can_open = @signals.signal(false)
    let shown = @signals.signal(true)
    let pressed : Ref[Array[Int]] = Ref([])
    let t = usage_tiles_tester(card, busy, compacts, can_open, shown, pressed, 288.0, platform)
    let info = t.get(Text, label=@sf.t("web-main.chat.agentCard.context") + ": 81,600 / 100,000")
    let (x, y) = (info.rect.0 + info.rect.2 / 2.0, info.rect.1 + info.rect.3 / 2.0)
    if platform == 0 {
      t.move(x, y)
      t.run_for(@sf.tip_delay_ms + 150.0)
    } else {
      t.touch(0, x, y)
      t.run_for(@ui.long_press_ms + 150.0)
    }
    assert_true(t.query(Tooltip, label="81,600 / 100,000") is Some(_), msg="platform \{platform}")
    assert_eq(pressed.val.length(), 0)
    shown.set(false)
    t.draw()
    assert_true(t.query(Tooltip, label="81,600 / 100,000") is None, msg="tip leaves with its tile")
  }
}
