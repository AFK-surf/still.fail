// A single allowance window in the tree: its own live data, size and tip, inside a row that keeps its press.

///|
priv struct QuotaNodeRig {
  t : @ui.Tester
  at : @signals.Signal[Int]
  there : @signals.Signal[Bool]
  spoken : @signals.Signal[String]
  layer : Ref[@view.View?]
  presses : Ref[Int]
  windows : Array[Json]
}

///|
fn quota_node_rig(small : Bool, compact : Bool, marked : Bool, custom : Bool) -> QuotaNodeRig {
  let windows = [
    Json::object({ "mark": "5H", "label": "Five hours", "left": 62.0, "level": "ok", "refills": "Tomorrow" }),
    Json::object({ "mark": "W", "label": "Week", "left": 15.0, "level": "amber", "refills": "Monday" }),
    Json::object({ "mark": "M", "label": "Month", "left": 140.0, "level": "red" }),
    Json::object({ "mark": "D", "label": "Day", "left": -5.0, "level": "red" }),
  ]
  let at = @signals.signal(0)
  let there = @signals.signal(true)
  let spoken = @signals.signal("First detail")
  let layer : Ref[@view.View?] = Ref(None)
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(row) {
      row.row(Is(true)).lines_up(Is(Some(Start)))
      .width(Is(Some(200.0))).height(Is(Some(80.0))).padding(Is((20.0, 20.0, 0.0, 0.0)))
      .presses(Is(true)).focusable(Is(true)).says(Is(Some(@view.said(Button, label="Row"))))
      .on_press(fn() { presses.val += 1 }) |> ignore
      row.show(fn() { there.get() }, fn(b) {
        let w = fn() { if at.get() == windows.length() { None } else { Some(windows[at.get()]) } }
        if custom {
          quota_chip_node(b, w, small~, compact~, marked~, said=fn() { spoken.get() }, tips~) |> ignore
        } else {
          quota_chip_node(b, w, small~, compact~, marked~, tips~) |> ignore
        }
      })
    }) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  { t, at, there, spoken, layer, presses, windows }
}

///|
fn quota_words() -> Array[String] {
  @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words != "" }).map(fn(d) { d.words })
}

///|
fn quota_pointer(t : @ui.Tester, words : String) -> Unit raise {
  let drawn = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == words })
  assert_true(drawn.length() > 0, msg="missing \{words}")
  let d = drawn[0]
  t.move(d.x + d.w / 2.0, d.y + d.h / 2.0)
}

///|
fn quota_tip_shown(t : @ui.Tester, label : String) -> Bool {
  t.semantics().any(fn(s) { s.role == Tooltip && s.label == label && !s.hidden })
}

///|
test "a quota window node follows its mark, clamped figure and level, and can omit the mark" {
  let q = quota_node_rig(true, false, true, false)
  assert_true(quota_words().contains("5H"))
  assert_true(quota_words().contains("62%"))
  q.at.set(1)
  q.t.draw()
  assert_true(quota_words().contains("W"))
  assert_true(quota_words().contains("15%"))
  assert_true(!quota_words().contains("5H"))
  assert_true(@ui.view_tree().unwrap().drawn().any(fn(d) { d.ground == alpha(level_color("amber"), chip_fill_share) }))
  q.at.set(2)
  q.t.draw()
  assert_true(quota_words().contains("100%"))
  assert_true(@ui.view_tree().unwrap().drawn().any(fn(d) { d.ground == alpha(level_color("red"), chip_fill_share) }))
  q.at.set(3)
  q.t.draw()
  assert_true(quota_words().contains("0%"))
  assert_true(!@ui.view_tree().unwrap().drawn().any(fn(d) { d.ground == alpha(level_color("red"), chip_fill_share) }))
  q.at.set(q.windows.length())
  q.t.draw()
  assert_true(quota_words().contains("0%"))
  assert_true(!quota_words().contains("D"))
  let plain = quota_node_rig(true, true, false, false)
  assert_true(quota_words().contains("62%"))
  assert_true(!quota_words().contains("5H"))
  plain.t.draw()
}

///|
/// The neutral box around the chip, in the tree's draw list.
fn quota_box() -> (Double, Double) raise {
  let boxes = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.ground == @ui.tree_theme().neutral })
  assert_true(!boxes.is_empty(), msg="the chip's ground is drawn")
  (boxes[0].w, boxes[0].h)
}

///|
test "small and compact quota windows have their established height and padding" {
  let _regular = quota_node_rig(false, false, false, false)
  let (_, regular_h) = quota_box()
  let _small = quota_node_rig(true, false, false, false)
  let (small_w, small_h) = quota_box()
  let _compact = quota_node_rig(true, true, false, false)
  let (compact_w, compact_h) = quota_box()
  assert_eq((regular_h, small_h, compact_h), (22.0, 16.0, 16.0))
  assert_eq(small_w - compact_w, 2.0, msg="one point less on each side")
}

///|
test "a quota window changes its level tint with the theme after it is made" {
  set_dark(Some(false))
  let q = quota_node_rig(true, false, true, false)
  q.at.set(1)
  q.t.draw()
  let light = alpha(level_color("amber"), chip_fill_share)
  let has_light = @ui.view_tree().unwrap().drawn().any(fn(d) { d.ground == light })
  set_dark(Some(true))
  q.t.draw()
  let dark = alpha(level_color("amber"), chip_fill_share)
  let has_dark = @ui.view_tree().unwrap().drawn().any(fn(d) { d.ground == dark })
  set_dark(None)
  assert_true(light != dark, msg="the themes have different amber fills")
  assert_true(has_light && has_dark, msg="the node follows the theme")
}

///|
test "a standalone quota window's mark and figure are read as text" {
  let w = Json::object({ "mark": "W", "left": 15.0, "level": "amber" })
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=100.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    quota_chip_node(root, fn() { Some(w) }, small=true) |> ignore
  })
  t.draw()
  assert_true(t.semantics().any(fn(s) { s.role == Text && s.label == "W" && !s.hidden }))
  assert_true(t.semantics().any(fn(s) { s.role == Text && s.label == "15%" && !s.hidden }))
}

///|
test "a quota window's tip follows its data, the row keeps its press, and the tip is let go with the chip" {
  let q = quota_node_rig(true, false, true, false)
  quota_pointer(q.t, "5H")
  q.t.run_for(tip_delay_ms + @kit.pop_out_ms * 2.0)
  assert_true(quota_tip_shown(q.t, quota_said(Some(q.windows[0]))))
  q.at.set(1)
  q.t.draw()
  assert_true(quota_tip_shown(q.t, quota_said(Some(q.windows[1]))))
  let word = @ui.view_tree().unwrap().drawn().filter(fn(d) { d.words == "W" })[0]
  let (x, y) = (word.x + word.w / 2.0, word.y + word.h / 2.0)
  q.t.touch(0, x, y)
  q.t.touch(2, x, y)
  assert_eq(q.presses.val, 1, msg="the row takes a click on its chip")
  q.t.act(Button, Focus, label="Row")
  q.t.enter()
  assert_eq(q.presses.val, 2, msg="the row remains keyboard accessible")
  q.there.set(false)
  q.t.draw()
  assert_eq(q.layer.val.unwrap().kids().length(), 0, msg="the tip's holder is let go with the chip")
}

///|
test "a quota window's supplied tip follows its own words" {
  let q = quota_node_rig(false, false, true, true)
  quota_pointer(q.t, "5H")
  q.t.run_for(tip_delay_ms + @kit.pop_out_ms * 2.0)
  assert_true(quota_tip_shown(q.t, "First detail"))
  q.spoken.set("Another detail")
  q.t.draw()
  assert_true(quota_tip_shown(q.t, "Another detail"))
}
