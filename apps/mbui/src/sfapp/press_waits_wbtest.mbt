// A press that waits for the core to open something (sfbase's press_wait.mbt: a chat list row's menu, its swipe's
// question and its 归档 key waiting for the chat's whole row; the chat page's "…"; a new chat's model panel) waits only
// while what it was pressed in stays as it was: over a core answering 1 s late, the chat left, the workspace switched
// or something else put up meanwhile, nothing opens when the answer comes, and what was asked is let go of.

///|
/// The app over made-up core `mode`, each chat's whole row (`chatRow`) answered `late` ms after it is asked and the
/// rest at once, in a window `w` by `h` on `platform`'s hand, at rest on Home; the calls in `calls`, what the client
/// sends in `sent`.
fn waits_tester(calls : Array[Made], sent : Array[String], mode : String, w : Double, h : Double, platform : Int, late : Double) -> (@ui.Tester, Source) {
  new_run()
  let base = fixture(mode)
  let made : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let src = round_trip_again(made, 0.0, heard=fn(m) { if m.has_prefix("out ") { sent.push(m) } }, late=fn(name, _) {
    if name == "chatRow" {
      late
    } else {
      0.0
    }
  })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.draw()
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
/// The ids the client asked topic `topic` by in `sent`, and those it let go of.
fn asked_and_gone(sent : Array[String], topic : String) -> (Array[Int], Array[Int]) {
  let asked : Array[Int] = []
  let gone : Array[Int] = []
  for m in sent {
    let j = @json.parse(m[4:].to_owned()) catch { _ => continue }
    match j {
      Object(o) =>
        match (o.get("id"), o.get("subscribe"), o.get("unsubscribe")) {
          (Some(Number(n, ..)), Some(Object(t)), _) if t.get("topic") == Some(Json::string(topic)) => asked.push(n.to_int())
          (Some(Number(n, ..)), _, Some(True)) => gone.push(n.to_int())
          _ => ()
        }
      _ => ()
    }
  }
  (asked, gone)
}

///|
/// How long each step before the late answer is given to run: a few frames, so the steps of a test, all of them,
/// are well within the 1 s the core takes to answer (shorter than `@ui.move_most_ms`, which would let it come first).
let press_step_ms : Double = 100.0

///|
/// How late the core answers a chat's whole row (`chatRow`) here.
let row_late_ms : Double = 1000.0

///|
/// How long after the late answer what it would open is given to come (a menu's or a question's coming, and more).
let come_ms : Double = 400.0

///|
/// Something else put up over the screen, as a press elsewhere puts it up: a menu of its own.
fn put_up_other(t : @ui.Tester) -> Unit {
  @ui.view_tree().unwrap().event(t.time(), fn() {
    @sf.menu([Some(@sf.menu_item_of("别的菜单", fn() {  }))], from=@sf.at_point(20.0, 20.0))
  })
  t.run_for(press_step_ms)
}

///|
/// The screens and hands a press is tried with: 小屏 with a finger, 中屏 and 大屏 with a mouse.
let wait_screens : Array[(String, Double, Double, Int)] = [("小屏", 390.0, 844.0, 2), ("中屏", 720.0, 800.0, 0), ("大屏", 1280.0, 800.0, 0)]

///|
test "a row's menu waiting for its whole row 1 s late, something else put up meanwhile: on 小屏 (held), 中屏 and 大屏 (right clicked) the row's menu does not open over it when the row comes" {
  let late = row_late_ms
  let faults : Array[String] = []
  for s in wait_screens {
    let (name, w, h, platform) = s
    let calls : Array[Made] = []
    let sent : Array[String] = []
    let (t, _) = waits_tester(calls, sent, "home-pins", w, h, platform, late)
    guard t.find("整理发布清单") is Some((x, y)) else {
      faults.push(name + ": no row")
      continue
    }
    if platform == 2 {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms + press_step_ms)
      t.release(x, y)
    } else {
      t.right_click(x, y)
    }
    t.run_for(press_step_ms)
    if t.find("重命名") is Some(_) {
      faults.push(name + ": opened before it was answered")
    }
    put_up_other(t)
    t.run_for(late + come_ms)
    if t.find("重命名") is Some(_) {
      faults.push(name + ": the row's menu opened over it")
    }
    if t.find("别的菜单") is None {
      faults.push(name + ": what was put up is gone")
    }
  }
  assert_eq(faults, [])
}

///|
test "a row swiped on 小屏 waiting for its whole row 1 s late, something else put up meanwhile: no question asked and nothing archived when the row comes, the row back where it rests" {
  let late = row_late_ms
  for what in ["someone else's", "one's own"] {
    let title = if what == "one's own" { "首页的列表改成按天分组" } else { "和 Ana 一起看新版的引导页" }
    let calls : Array[Made] = []
    let sent : Array[String] = []
    let (t, _) = waits_tester(calls, sent, "home", 390.0, 844.0, 2, late)
    let (x, y) = t.find(title).unwrap()
    t.drag(x + 190.0, y, x + 10.0, y)
    t.run_for(press_step_ms)
    put_up_other(t)
    t.run_for(late + come_ms)
    assert_true(t.find("归档「" + title + "」？") is None, msg="\{what}: asked")
    assert_eq(named(calls, "chat.archive").length(), 0, msg="\{what}: archived")
    // (back where it rests: its title where it was)
    let (x2, _) = t.find(title).unwrap()
    assert_true((x2 - x).abs() < 1.0, msg="\{what}: left at \{x2}, not \{x}")
  }
}

///|
test "a row's 归档 key pressed wide over a whole row 1 s late, something else put up meanwhile: nothing archived when the row comes" {
  let late = row_late_ms
  for s in wait_screens[1:] {
    let (name, w, h, platform) = s
    let calls : Array[Made] = []
    let sent : Array[String] = []
    let (t, _) = waits_tester(calls, sent, "home", w, h, platform, late)
    let (x, y) = t.find("首页的列表改成按天分组").unwrap()
    t.move_to(x, y)
    t.run_for(press_step_ms)
    t.click(Button, label="归档「首页的列表改成按天分组」")
    t.run_for(press_step_ms)
    put_up_other(t)
    t.run_for(late + come_ms)
    assert_eq(named(calls, "chat.archive").length(), 0, msg="\{name} \{Repr(calls.map(fn(c) { c.name }))}")
  }
}

///|
/// What leaves the chat's page while its "…" waits: the chat left (back), the workspace switched, something else put up.
let chat_menu_leaves : Array[String] = ["chat left", "workspace switched", "something else put up"]

///|
test "the chat's … waiting for its whole row 1 s late, then the chat left, the workspace switched or something else put up: on 小屏, 中屏 and 大屏 it does not open when the row comes, and the chat left, what it read is let go of" {
  let late = row_late_ms
  let faults : Array[String] = []
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  for s in wait_screens {
    let (name, w, h, platform) = s
    for what in chat_menu_leaves {
      let at = name + " " + what
      let calls : Array[Made] = []
      let sent : Array[String] = []
      let (t, src) = waits_tester(calls, sent, "home-pins", w, h, platform, late)
      @ui.view_tree().unwrap().event(t.time(), fn() { open_page(Chat(r)) })
      t.frame()
      // (its "…" pressed when a hand can: once the chat's page has come in (a Move, move_most_ms at the most), its row
      // still not answered then. Pressed a frame after the page was pushed, it was pressed on 小屏 with the page still
      // off the screen, where no hand can, and the leave 100 ms on turned back the bottom bar still going down for the
      // page: no part of what this test is about, at a moment no hand comes to by this way)
      t.run_for(@ui.move_most_ms)
      @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.open_chat_menu(src, "ws1", r, [], from=@sf.at_point(w / 2.0, h / 2.0)) })
      t.run_for(press_step_ms)
      if t.find("重命名") is Some(_) {
        faults.push(at + ": opened before the row came, at \{t.time()}")
      }
      match what {
        "chat left" => @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.close_page(Chat(r)) |> ignore })
        "workspace switched" => @ui.view_tree().unwrap().event(t.time(), fn() { @sfpages.switch_workspace(src, "ws2") })
        _ => put_up_other(t)
      }
      t.run_for(late + come_ms)
      if t.find("重命名") is Some(_) {
        faults.push(at + ": opened when the row came \{Repr(t.words().filter(fn(w) { w.0 == "重命名" || w.0 == "固定" || w.0 == "别的菜单" }))}")
      }
      if what != "something else put up" {
        let (asked, gone) = asked_and_gone(sent, "chatRow")
        if !asked.iter().all(fn(id) { gone.contains(id) }) {
          faults.push(at + ": chatRow held on: asked \{Repr(asked)}, let go of \{Repr(gone)}")
        }
      }
    }
  }
  assert_eq(faults, [])
}
