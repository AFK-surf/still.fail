// The same quoted passage and input events on the old and retained chat pages.

///|
fn quote_test_press(t : @ui.Tester, x : Double, y : Double, hold : Double) -> Unit {
  t.touch_at(0, x, y, t.time())
  t.run_for(hold)
  t.touch_at(2, x, y, t.time())
}

///|
fn quote_test_rect(t : @ui.Tester, needle : String, h : Double, last? : Bool = false) -> (Double, Double, Double, Double)? {
  let mut found = None
  for (s, x, y, w, ht, alpha) in t.words() {
    if alpha > 0.5 && s.contains(needle) && y + ht > 0.0 && y < h {
      found = Some((x, y, w, ht))
      if !last { return found }
    }
  }
  found
}

///|
fn quote_test_button(n : @ui.SemNode) -> Bool {
  if !n.actions.is_empty() { return true }
  ["Button", "Link", "TextField", "MenuItem", "Tab", "CheckBox", "Switch", "ListItem"].contains("\{n.role}")
}

///|
fn quote_test_send(t : @ui.Tester, w : Double, h : Double) -> Unit raise {
  for n in t.semantics() {
    let (x, y, bw, bh) = n.rect
    if !n.hidden && quote_test_button(n) && n.label == "发送" {
      quote_test_press(t, x + bw / 2.0, y + bh / 2.0, 80.0)
      return
    }
  }
  for n in t.semantics() {
    let (x, y, bw, bh) = n.rect
    if !n.hidden && quote_test_button(n) && n.label == "" && bw <= 48.0 && x > w - 80.0 && y > h - 80.0 {
      quote_test_press(t, x + bw / 2.0, y + bh / 2.0, 80.0)
      return
    }
  }
  fail("the send button is available")
}

///|
fn quote_test_sent(w : Double, h : Double, platform : Int) -> @ui.Tester raise {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", w~, h~, platform~)
  let touch = platform != 0
  t.set_frame_period(if touch { 1000.0 / 120.0 } else { 1000.0 / 60.0 })
  t.run_for(@ui.move_most_ms * 2.0)
  if w >= 600.0 && w < 1000.0 {
    quote_test_press(t, w - 28.0, h / 2.0, 80.0)
    t.run_for(@ui.move_most_ms * 2.0)
  }
  let mid = if w >= 1000.0 { w * 0.62 } else if w >= 600.0 { w * 0.72 } else { w / 2.0 }
  let mut k = 0
  while k < 30 {
    let rect = quote_test_rect(t, "有问题随时说", h)
    match rect {
      Some((_, y, _, _)) if y > h * 0.2 && y < h * 0.7 => break
      _ => ()
    }
    let below = match rect { Some((_, y, _, _)) => y >= h * 0.7; None => false }
    if touch {
      if below { t.drag(mid, h * 0.6, mid, h * 0.45, steps=10) }
      else { t.drag(mid, h * 0.4, mid, h * 0.6, steps=10) }
    } else {
      t.wheel(mid, h / 2.0, if below { 100.0 } else { -150.0 })
    }
    t.run_for(@ui.move_most_ms * 0.8)
    k += 1
  }
  t.run_for(@ui.move_most_ms * 3.0)
  let (x, y, rw, rh) = match quote_test_rect(t, "有问题随时说", h) {
    Some(rect) => rect
    None => fail("the passage to quote is visible")
  }
  if touch {
    quote_test_press(t, x + (if rw < 120.0 { rw } else { 120.0 }) / 2.0, y + (if rh < 30.0 { rh } else { 30.0 }) / 2.0, 700.0)
  } else {
    t.drag(x + 1.0, y + rh / 2.0, x + rw - 1.0, y + rh / 2.0)
  }
  t.run_for(@ui.move_most_ms * 2.4)
  assert_true(quote_test_rect(t, "引用", h) is Some(_), msg="the selected passage can be quoted")
  t.tap_text("引用")
  t.run_for(@ui.move_most_ms * 2.0)
  println("QUOTE before-send width=\{w} platform=\{platform} field=\{t.ctx().field_focused()} focus=\{t.focused()}")
  quote_test_send(t, w, h)
  t.run_for(@ui.move_most_ms * 5.0)
  assert_eq(named(calls, "chat.send").length(), 1, msg="the quote was sent once")
  println("QUOTE sent width=\{w} platform=\{platform} field=\{t.ctx().field_focused()} focus=\{t.focused()} hint=\{quote_test_rect(t, "按空格输入", h)} placeholder=\{quote_test_rect(t, "发消息", h)} fifteen=\{quote_test_rect(t, "15 分钟前", h)}")
  t
}

///|
test "after sending a quote by touch the messages land in the same place" {
  let failures : Array[String] = []
  for (w, h, want) in [(740.0, 1000.0, 408.5), (1280.0, 800.0, 182.5)] {
    let t = quote_test_sent(w, h, 2)
    let y = quote_test_rect(t, "15 分钟前", h).map(fn(rect) { rect.1 })
    if !y.map_or(false, fn(y) { (y - want).abs() < 1.0 }) {
      failures.push("\{w}: \{y} expected \{want}")
    }
  }
  assert_eq(failures, [], msg="the message above the sent quote stands in its place")
}

///|
/// The original message's timestamp in the chat pane near the top, not a time in a neighbouring pane.
fn quote_test_target_y(t : @ui.Tester, w : Double) -> Double? {
  let left = if w >= 1000.0 { 350.0 } else if w >= 600.0 { 100.0 } else { 35.0 }
  for (s, x, y, _, _, a) in t.words() {
    if s == "2 小时前" && a > 0.5 && x >= left && y >= 40.0 && y < 200.0 { return Some(y) }
  }
  None
}

///|
fn quote_test_existing(w : Double, h : Double, platform : Int) -> @ui.Tester raise {
  let t = wide_tester([], mode="chat", w~, h~, platform~)
  let touch = platform != 0
  t.set_frame_period(if touch { 1000.0 / 120.0 } else { 1000.0 / 60.0 })
  t.run_for(@ui.move_most_ms * 2.0)
  if w >= 600.0 && w < 1000.0 {
    quote_test_press(t, w - 28.0, h / 2.0, 80.0)
    t.run_for(@ui.move_most_ms * 2.0)
  }
  let mid = if w >= 1000.0 { w * 0.62 } else if w >= 600.0 { w * 0.72 } else { w / 2.0 }
  if touch { t.drag(mid, h * 0.2, mid, h * 0.2 + 500.0, steps=30) }
  else { t.wheel(mid, h / 2.0, -500.0) }
  t.run_for(@ui.move_most_ms * 3.0)
  let card = "Claude：其余的行按估计"
  let mut k = 0
  while k < 30 {
    let rect = quote_test_rect(t, card, h)
    match rect {
      Some((_, y, _, _)) if y > h * 0.2 && y < h * 0.7 => break
      _ => ()
    }
    let below = match rect { Some((_, y, _, _)) => y >= h * 0.7; None => false }
    if touch {
      if below { t.drag(mid, h * 0.6, mid, h * 0.45, steps=10) }
      else { t.drag(mid, h * 0.4, mid, h * 0.6, steps=10) }
    } else { t.wheel(mid, h / 2.0, if below { 100.0 } else { -150.0 }) }
    t.run_for(@ui.move_most_ms * 0.8)
    k += 1
  }
  t.run_for(@ui.move_most_ms * 3.0)
  let (x, y, rw, rh) = match quote_test_rect(t, card, h) {
    Some(rect) => rect
    None => fail("the existing quote card is visible")
  }
  quote_test_press(t, x + (if rw < 120.0 { rw } else { 120.0 }) / 2.0, y + (if rh < 30.0 { rh } else { 30.0 }) / 2.0, 80.0)
  t.run_for(@ui.move_most_ms * 4.0)
  t
}

///|
test "both existing and newly sent quotes reach the original at each screen width and input" {
  let failures : Array[String] = []
  for (w, h, platform, want) in [
    (390.0, 844.0, 0, 93.0), (740.0, 1000.0, 0, 124.0), (1280.0, 800.0, 0, 106.0),
    (390.0, 844.0, 2, 87.0), (740.0, 1000.0, 2, 118.0), (1280.0, 800.0, 2, 100.0),
  ] {
    let existing = quote_test_existing(w, h, platform)
    let y = quote_test_target_y(existing, w)
    println("QUOTE landing existing width=\{w} platform=\{platform} y=\{y} want=\{want}")
    if !y.map_or(false, fn(y) { (y - want).abs() < 1.0 }) { failures.push("existing \{w}/\{platform}: \{y} expected \{want}") }
    let sent = quote_test_sent(w, h, platform)
    let (x, py, rw, rh) = match quote_test_rect(sent, "Claude：", h, last=true) {
      Some(rect) => rect
      None => fail("the sent quote card is visible")
    }
    quote_test_press(sent, x + (if rw < 120.0 { rw } else { 120.0 }) / 2.0, py + (if rh < 30.0 { rh } else { 30.0 }) / 2.0, 80.0)
    sent.run_for(@ui.move_most_ms * 5.0)
    let sy = quote_test_target_y(sent, w)
    println("QUOTE landing sent width=\{w} platform=\{platform} y=\{sy} want=\{want}")
    if !sy.map_or(false, fn(y) { (y - want).abs() < 1.0 }) { failures.push("sent \{w}/\{platform}: \{sy} expected \{want}") }
  }
  assert_eq(failures, [], msg="quotes reach the same place")
}
