// A code field in the tree: its input, once-only completion, asynchronous clearing, focus and narrow layout.

///|
fn code_node_case(
  code : CodeField,
  handed : Array[String],
  shown : @signals.Signal[Bool],
  enabled : @signals.Signal[Bool],
  wrong : @signals.Signal[Bool],
  w? : Double = 390.0,
  platform? : Int = 2,
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w~, h=250.0, platform~)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(s) {
      code_field_node(s, code, fn(value) { handed.push(value) }, wrong=fn() { wrong.get() }, enabled=fn() { enabled.get() }) |> ignore
    })
  })
  t.draw()
  t
}

///|
test "a tree code field takes digits, hands a completed code on once and accepts a rejected code again" {
  for platform in [0, 2] {
    let code = CodeField::new()
    let handed : Array[String] = []
    let shown = @signals.signal(true)
    let enabled = @signals.signal(true)
    let wrong = @signals.signal(false)
    let t = code_node_case(code, handed, shown, enabled, wrong, platform~)
    assert_true(t.ime().0)
    assert_eq(t.ime_action(), @hostapi.ime_action_number)
    t.type_text("12-3 4567")
    assert_eq(code.text(), "123456")
    assert_eq(handed, ["123456"])
    t.draw()
    t.draw()
    assert_eq(handed, ["123456"])
    enabled.set(false)
    t.type_text("9")
    assert_eq(code.text(), "123456")
    // A refusal arrives between frames, even if the doing topic still says it is checking.
    wrong.set(true)
    code.clear()
    assert_eq(code.text(), "")
    enabled.set(true)
    t.type_text("123456")
    assert_eq(handed, ["123456", "123456"])
    assert_true(t.ime().0)
    shown.set(false)
    t.draw()
    assert_false(t.ime().0)
  }
}

///|
test "a tree code field scales its six boxes before wrapping them into two rows" {
  for width in [390.0, 270.0, 200.0] {
    let code = CodeField::new()
    let t = code_node_case(code, [], @signals.signal(true), @signals.signal(true), @signals.signal(false), w=width)
    t.draw()
    let boxes = view_tree().unwrap().drawn_held().map(fn(e) { e.0 }).filter(fn(d) { d.edge.0 > 0.0 })
    assert_eq(boxes.length(), 6, msg=width.to_string())
    assert_true(boxes.iter().all(fn(b) { b.x >= -0.01 && b.x + b.w <= width + 0.01 }), msg=width.to_string())
    if width == 200.0 {
      assert_true(boxes[0].y == boxes[2].y && boxes[3].y > boxes[0].y)
    } else {
      assert_true(boxes.iter().all(fn(b) { b.y == boxes[0].y }), msg=width.to_string())
    }
  }
}
