// The way back to the newest is offered after the reader has gone far enough from the end, not as soon as the first
// point is scrolled. These slow drags are the same with the original and the retained chat page.

///|
fn jump_visibility_tester() -> @ui.Tester {
  new_run()
  @sf.kept_call.val = Some(@sfkept.answer)
  let src = fixture_app("chat-long")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(1000.0)
  t
}

///|
fn jump_visibility_drag(t : @ui.Tester, points : Double) -> Unit {
  t.touch_at(0, 195.0, 200.0, t.time())
  for i in 1..=10 {
    t.advance(50.0)
    t.touch_at(1, 195.0, 200.0 + points * i.to_double() / 10.0, t.time())
    t.frame_at(t.next_frame_time())
  }
}

///|
fn jump_visible(t : @ui.Tester) -> Bool {
  t.query(Button, label=@sf.t("web-main.chat.toLatest")) is Some(_)
}

///|
test "a small scroll from the end does not offer the way to latest" {
  for points in [60.0, 120.0] {
    let t = jump_visibility_tester()
    assert_false(jump_visible(t), msg="at the end")
    jump_visibility_drag(t, points)
    assert_false(jump_visible(t), msg="a \{points}-point drag held near the end")
    t.touch_at(2, 195.0, 200.0 + points, t.time())
    t.frame_at(t.next_frame_time())
    t.run_for(2000.0)
    assert_false(jump_visible(t), msg="the same drag released near the end")
  }
}

///|
test "farther from the end a slow drag offers the way to latest" {
  let t = jump_visibility_tester()
  jump_visibility_drag(t, 300.0)
  t.touch_at(2, 195.0, 500.0, t.time())
  t.run_for(2000.0)
  assert_true(jump_visible(t), msg="a 300-point drag away from the end")
}

///|
test "a page short of the newest still offers the way to latest at its end" {
  let calls : Array[Made] = []
  let t = fake_core(calls, over=fn(name, topic) {
    match (name, topic.value) {
      ("chat", Some(Object(fields))) => {
        let changed = fields.copy()
        changed["newer"] = Json::boolean(true)
        { ..topic, value: Some(Json::object(changed)) }
      }
      _ => topic
    }
  })
  assert_true(jump_visible(t), msg="newer pages are available")
}

///|
test "the way to latest fades in and fades out without taking another press" {
  let t = jump_visibility_tester()
  t.touch_at(0, 195.0, 200.0, t.time())
  let mut first_alpha = -1.0
  for i in 1..=10 {
    t.advance(50.0)
    t.touch_at(1, 195.0, 200.0 + 30.0 * i.to_double(), t.time())
    t.frame_at(t.next_frame_time())
    if first_alpha < 0.0 && jump_visible(t) {
      let tree = @ui.view_tree().unwrap()
      let button = tree.said_order().iter().find_first(fn(n) {
        !n.hidden && n.said is Some(s) && s.role == Button && s.label == @sf.t("web-main.chat.toLatest")
      }).unwrap()
      first_alpha = tree.drawn_of(button.id).unwrap().alpha
    }
  }
  t.touch_at(2, 195.0, 500.0, t.time())
  assert_true(first_alpha >= 0.0 && first_alpha < 1.0, msg="the arriving button's first alpha was \{first_alpha}")
  t.run_for(2000.0)
  let tree = @ui.view_tree().unwrap()
  let button = tree.said_order().iter().find_first(fn(n) {
    !n.hidden && n.said is Some(s) && s.role == Button && s.label == @sf.t("web-main.chat.toLatest")
  }).unwrap()
  assert_eq(tree.drawn_of(button.id).unwrap().alpha, 1.0)
  t.click(Button, label=@sf.t("web-main.chat.toLatest"))
  t.draw()
  assert_false(jump_visible(t), msg="a leaving button cannot be pressed")
  assert_true(tree.drawn_of(button.id) is Some(_), msg="the departing button stays for its fade")
  t.run_for(200.0)
  assert_true(tree.drawn_of(button.id) is None, msg="the fade has finished")
}
