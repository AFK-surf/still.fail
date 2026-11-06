// Shared security parts: responsive rows and the checkbox's input and accessibility contract.

///|
test "a checkbox node follows its value, takes Space and Activate, and disables both input and focus" {
  for platform in [0, 2] {
    let check : @signals.Signal[@view.Check] = @signals.signal(Mixed)
    let disabled = @signals.signal(false)
    let presses = Ref(0)
    let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform~)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      root.box(fn(room) {
        room.padding(Is((30.0, 30.0, 30.0, 30.0))) |> ignore
        checkbox_node(room, fn() { "Device" }, fn() { check.get() }, fn() {
          presses.val += 1
          check.set(if check.get() is On { Off } else { On })
        }, disabled=fn() { disabled.get() }) |> ignore
      }) |> ignore
    })
    t.draw()
    assert_true(t.get(Checkbox, label="Device").check == Some(Mixed))
    t.act(Checkbox, Focus, label="Device")
    t.enter()
    assert_eq(presses.val, 0)
    t.key(@ui.key_space)
    assert_eq(presses.val, 1)
    assert_true(t.get(Checkbox, label="Device").check == Some(On))
    assert_true(t.focused().map(fn(s) { s.label }) == Some("Device"))
    t.act(Checkbox, Activate, label="Device")
    assert_eq(presses.val, 2)
    assert_true(t.get(Checkbox, label="Device").check == Some(Off))
    let (x, y, w, h) = t.get(Checkbox, label="Device").rect
    let reach = if platform == 2 { 44.0 } else { 36.0 }
    t.tap(x + w / 2.0 + reach / 2.0 - 1.0, y + h / 2.0)
    assert_eq(presses.val, 3)
    disabled.set(true)
    t.draw()
    assert_true(t.get(Checkbox, label="Device").disabled)
    assert_true(t.focused() is None)
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq(presses.val, 3)
  }
}

///|
/// A member and one device, in the given page arrangement. The four word centres are measured in one frame.
fn security_parts_positions(look : Look) -> ((Double, Double), (Double, Double), (Double, Double), (Double, Double)) {
  let t = @ui.Tester::new(fn(_c) {  }, w=500.0, h=500.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    look_lent(root, look)
    security_person_node(root, fn() { "Member" }, fn() { "Owner" })
    security_devices_node(root, fn(devices) {
      security_device_group_node(devices, fn() { "App" }, fn(group) {
        security_line_node(group, fn() { "Device" }, fn() { "Last used" }, indent=true, acts=fn(a) {
          security_action_node(a, fn() { "Remove" }, fn() {  })
        })
      })
    })
  })
  t.draw()
  (t.find("Member").unwrap(), t.find("Owner").unwrap(), t.find("Device").unwrap(), t.find("Remove").unwrap())
}

///|
test "security rows put a role at the end and device actions below when narrow, beside their words when wide" {
  let wide = security_parts_positions(Wide)
  let narrow = security_parts_positions(Narrow)
  assert_true(narrow.1.0 > wide.1.0)
  assert_true(wide.2.0 > wide.0.0)
  assert_true(narrow.2.0 > narrow.0.0)
  assert_true(narrow.3.1 > narrow.2.1)
  assert_true((wide.3.1 - wide.2.1).abs() < 10.0)
}

///|
test "a narrow device mark stays beside its words when its actions appear underneath" {
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    look_lent(root, Narrow)
    security_line_node(root, fn() { "Device" }, fn() { "Last used" }, indent=true, mark=fn(m) {
      m.box(fn(mark) {
        mark.width(Is(Some(16.0))).height(Is(Some(16.0))).says(Is(Some(@view.said(Group, label="Device mark")))) |> ignore
      }) |> ignore
    }, acts=fn(a) { security_action_node(a, fn() { "Remove" }, fn() {  }) })
  })
  t.draw()
  let (_, title_y) = t.find("Device").unwrap()
  let (_, note_y) = t.find("Last used").unwrap()
  let (_, mark_y, _, mark_h) = t.get(Group, label="Device mark").rect
  let (_, action_y) = t.find("Remove").unwrap()
  assert_true((mark_y + mark_h / 2.0 - (title_y + note_y) / 2.0).abs() < 6.0)
  assert_true(action_y > note_y)
}
