// Steps whose cost is counted by the instructions they run (scripts/instr.sh: each test its own process, counted
// whole, so nothing of how the app does it is asked): each page at a small and a large size, opened alone and opened
// then the step taken. What a step costs is the second less the first; at the large size it is to cost what it costs
// at the small one, and no more than the build it is held to.

///|
fn instr_open(mode : String, w : Double, platform : Int) -> @ui.Tester {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode~, w~, h=if w < 600.0 { 844.0 } else { 800.0 }, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn instr_type(t : @ui.Tester, keys : Int) -> Unit {
  match t.find("发消息") {
    Some((x, y)) => t.tap(x, y)
    None => ()
  }
  t.run_for(@ui.move_most_ms)
  for i in 0..<keys {
    t.text_told(if i % 2 == 0 { "看" } else { "一" }, t.time())
    t.run_for(50.0)
  }
}

///|
fn instr_scroll(t : @ui.Tester, w : Double, platform : Int) -> Unit {
  for _ in 0..<10 {
    if platform == 0 { t.wheel(w * 0.6, 400.0, -300.0) } else { t.drag(w / 2.0, 600.0, w / 2.0, 300.0, steps=6) }
    t.run_for(200.0)
  }
}

///|
fn instr_switch(t : @ui.Tester) -> Unit {
  for name in ["夜里的构建又失败了", "整理发布清单", "夜里的构建又失败了", "整理发布清单"] {
    match t.find(name) {
      Some((x, y)) => t.tap(x, y)
      None => ()
    }
    t.run_for(@ui.move_most_ms)
  }
}

///|
test "instr|chat|small|1280|opened" { ignore(instr_open("chat-long-30", 1280.0, 0)) }

///|
test "instr|chat|small|1280|typed" { instr_type(instr_open("chat-long-30", 1280.0, 0), 20) }

///|
test "instr|chat|small|1280|scrolled" { instr_scroll(instr_open("chat-long-30", 1280.0, 0), 1280.0, 0) }

///|
test "instr|chat|small|1280|switched" { instr_switch(instr_open("chat-long-30", 1280.0, 0)) }

///|
test "instr|chat|large|1280|opened" { ignore(instr_open("chat-long", 1280.0, 0)) }

///|
test "instr|chat|large|1280|typed" { instr_type(instr_open("chat-long", 1280.0, 0), 20) }

///|
test "instr|chat|large|1280|scrolled" { instr_scroll(instr_open("chat-long", 1280.0, 0), 1280.0, 0) }

///|
test "instr|chat|large|1280|switched" { instr_switch(instr_open("chat-long", 1280.0, 0)) }

///|
test "instr|chat|small|390|opened" { ignore(instr_open("chat-long-30", 390.0, 2)) }

///|
test "instr|chat|small|390|typed" { instr_type(instr_open("chat-long-30", 390.0, 2), 20) }

///|
test "instr|chat|small|390|scrolled" { instr_scroll(instr_open("chat-long-30", 390.0, 2), 390.0, 2) }

///|
test "instr|chat|large|390|opened" { ignore(instr_open("chat-long", 390.0, 2)) }

///|
test "instr|chat|large|390|typed" { instr_type(instr_open("chat-long", 390.0, 2), 20) }

///|
test "instr|chat|large|390|scrolled" { instr_scroll(instr_open("chat-long", 390.0, 2), 390.0, 2) }

///|
test "instr|home|small|390|opened" { ignore(instr_open("home", 390.0, 2)) }

///|
test "instr|home|small|390|scrolled" { instr_scroll(instr_open("home", 390.0, 2), 390.0, 2) }

///|
test "instr|home|large|390|opened" { ignore(instr_open("long", 390.0, 2)) }

///|
test "instr|home|large|390|scrolled" { instr_scroll(instr_open("long", 390.0, 2), 390.0, 2) }

///|
test "instr|home|small|1280|opened" { ignore(instr_open("home", 1280.0, 0)) }

///|
test "instr|home|small|1280|scrolled" { instr_scroll(instr_open("home", 1280.0, 0), 1280.0, 0) }

///|
test "instr|home|large|1280|opened" { ignore(instr_open("long", 1280.0, 0)) }

///|
test "instr|home|large|1280|scrolled" { instr_scroll(instr_open("long", 1280.0, 0), 1280.0, 0) }
