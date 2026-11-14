// 引用 over words a mouse picked in a message, as a host builds the frames: the page's view kept where nothing it
// read changed, the message's row telling the pick as it is built (sfbase's pick.mbt, pick_pop).

///|
/// A mouse pressed at (x0, y0), dragged to (x1, y1) and let go there, as a host hands it on: each event between the
/// display's frames, the frames the app asks for drawn after it (no Tester::drag, whose draw tells it as from outside).
fn mouse_dragged(t : @ui.Tester, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  t.touch(0, x0, y0)
  t.frames_owed()
  // (its moves as Tester::drag's: inputs, each drawn as a host draws what it asks)
  let drag_moves = 10
  for i in 1..=drag_moves {
    let f = i.to_double() / drag_moves.to_double()
    t.frame(ms=@ui.input_step_ms)
    t.touch(1, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
    t.frames_owed()
  }
  t.frame(ms=@ui.input_step_ms)
  t.touch(2, x1, y1)
  t.frames_owed()
}

///|
/// A mouse's click at (x, y), as a host hands it on.
fn mouse_clicked(t : @ui.Tester, x : Double, y : Double) -> Unit {
  t.touch(0, x, y)
  t.frames_owed()
  t.frame(ms=@ui.input_step_ms)
  t.touch(2, x, y)
  t.frames_owed()
}

///|
/// Where 引用 is drawn over the line `y` is on (within 60 over it), if it is.
fn pill_over(t : @ui.Tester, y : Double) -> (Double, Double)? {
  match t.words().filter(fn(w) { w.0 == "引用" && w.2 < y && w.2 > y - 60.0 }) {
    [w, ..] => Some((w.1, w.2))
    _ => None
  }
}

///|
test "大屏, built as a host builds: words a mouse picked in a message have 引用 over where it let go in the frame it let go in, there after a while and a move, gone after a press" {
  // (this form alone shows it: a default Tester builds the frame again keeping nothing and shows the pill whatever
  // the page's view read, and a run_for(500) after the scroll brings it by a read of its own)
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.check_looks(false)
  for _ in 0..<12 {
    match t.run_rects("做了什么") {
      [(_, y, _, _), ..] if y > 100.0 && y < 500.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (hx, hy, _, hh) = words_rect(t, "做了什么")
  let (ix, iy, iw, ih) = words_rect(t, "滚动位置记成")
  mouse_dragged(t, hx + 1.0, hy + hh / 2.0, ix + iw - 1.0, iy + ih / 2.0)
  assert_true(t.ctx().selected_text().has_suffix("滚动位置记成"), msg=t.ctx().selected_text())
  match pill_over(t, iy) {
    Some((qx, _)) => assert_true((qx - (ix + iw)).abs() < 40.0, msg="引用 at \{qx}")
    None => fail("no 引用 over where the pointer let go, in the frame it let go in")
  }
  t.run_for(@ui.move_most_ms)
  assert_true(pill_over(t, iy) is Some(_), msg="引用 gone once all the let-go set off is over")
  t.touch(1, ix + iw + 30.0, iy + 40.0)
  t.frames_owed()
  assert_true(pill_over(t, iy) is Some(_), msg="引用 gone after the pointer moved")
  // (a click of its own, not a second of the press that picked: a double click's picks a word)
  t.run_for(@ui.double_click_ms)
  mouse_clicked(t, hx + 1.0, hy + hh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(t.words().filter(fn(w) { w.0 == "引用" }).is_empty(), msg="引用 still there after a press")
}

///|
/// A chat ending with a long agent reply like the reported selection: a wrapped list item, followed by another item.
fn pick_list_tester(calls : Array[Made], w? : Double = 1280.0) -> @ui.Tester {
  new_run()
  let text = "好，表 14 保持现状，不加说明。\n\n通读找到的问题里，还剩这些没定（编号沿用之前的）：\n- **7–12**：数字和单位前后不统一。两组 A1/b1 配置；同一批 400 项，系统统计数写成了 218/219/220 三个数；运行预算 20 和 50 分钟；501 和 509 s；sample 数 2,100 和 2,220；表 17 的列没标清楚。\n- **19–21**：可选。摘要补\"than the official Example evaluation\"；表 18 填上 115 s；写明 App 0.8.0b64。\n\n你点编号我就改；都不改的话，就可以收尾合并 #123 了。"
  let md : Json = [
    ["p", ["好，表 14 保持现状，不加说明。"]],
    ["p", ["通读找到的问题里，还剩这些没定（编号沿用之前的）："]],
    ["list", [
      ["li", [["b", ["7–12"]], "：数字和单位前后不统一。两组 A1/b1 配置；同一批 400 项，系统统计数写成了 218/219/220 三个数；运行预算 20 和 50 分钟；501 和 509 s；sample 数 2,100 和 2,220；表 17 的列没标清楚。"]],
      ["li", [["b", ["19–21"]], "：可选。摘要补\"than the official Example evaluation\"；表 18 填上 115 s；写明 App 0.8.0b64。"]],
    ]],
    ["p", ["你点编号我就改；都不改的话，就可以收尾合并 #123 了。"]],
  ]
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
    topic_read: fn(name, params) {
      let tp = base.topic(name, params).get().snapshot()
      match (name, tp.value) {
        ("chat", Some(Object(o))) => {
          let messages = match o.get("messages") {
            Some(Array(a)) => a.copy()
            _ => []
          }
          match messages.last() {
            Some(Object(m)) => {
              let m = m.copy()
              m["text"] = Json::string(text)
              m["md"] = md
              messages[messages.length() - 1] = Json::object(m)
            }
            _ => ()
          }
          let o = o.copy()
          o["messages"] = Json::array(messages)
          { ..tp, value: Some(Json::object(o)) }
        }
        _ => tp
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "大屏, a mouse picks across two list items of one message and quotes the passage" {
  let calls : Array[Made] = []
  let t = pick_list_tester(calls)
  t.check_looks(false)
  let before = t.audit()
  let (ax, ay, _, ah) = words_rect(t, "字和单位前后不统一")
  let (bx, by, bw, bh) = words_rect(t, "表 18")
  mouse_dragged(t, ax + 1.0, ay + ah / 2.0, bx + bw - 1.0, by + bh / 2.0)
  let picked = t.ctx().selected_text()
  assert_true(picked.has_prefix("字和单位前后不统一") && picked.has_suffix("表 18"), msg=picked)
  guard pill_over(t, by) is Some(_) else {
    fail("no 引用 over list items: box=\{Repr(t.ctx().selection_box())}, picked=\{Repr(@sfbase.picked.get())}")
  }
  assert_eq(t.audit().filter(fn(f) { !before.contains(f) }), [])
  // The same passage picked upwards has the pill at the other end.
  t.run_for(@ui.double_click_ms)
  mouse_dragged(t, bx + bw - 1.0, by + bh / 2.0, ax + 1.0, ay + ah / 2.0)
  assert_eq(t.ctx().selected_text(), picked)
  guard pill_over(t, ay) is Some(_) else { fail("no 引用 over the start when picked upwards") }
  t.run_for(@ui.double_click_ms)
  guard t.words().filter(fn(w) { w.0 == "引用" && w.2 < ay && w.2 > ay - 60.0 }) is [(_, qx, qy, qw, qh, _), ..] else {
    fail("no 引用 to press")
  }
  mouse_clicked(t, qx + qw / 2.0, qy + qh / 2.0)
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  let q = field(Some(quoted[0].params), "quote")
  assert_eq((text(q, "text"), text(q, "ts"), text(q, "role")), (picked, "ts11", "agent"))
  assert_eq(t.ctx().selected_text(), "")
}

///|
test "大屏, a mouse picking across two messages is not offered 引用" {
  let calls : Array[Made] = []
  let t = pick_list_tester(calls)
  t.check_looks(false)
  let (ax, ay, _, ah) = words_rect(t, "推送截图前要先登录")
  let (bx, by, bw, bh) = words_rect(t, "好，表 14 保持现状")
  // A previously quotable selection must not keep its pill once the next drag crosses messages.
  mouse_dragged(t, bx + 1.0, by + bh / 2.0, bx + bw - 1.0, by + bh / 2.0)
  assert_true(pill_over(t, by) is Some(_))
  t.run_for(@ui.double_click_ms)
  mouse_dragged(t, ax + 1.0, ay + ah / 2.0, bx + bw - 1.0, by + bh / 2.0)
  let picked = t.ctx().selected_text()
  assert_true(picked.has_prefix("推送截图前要先登录") && picked.has_suffix("好，表 14 保持现状"), msg=picked)
  assert_true(pill_over(t, by) is None, msg="引用 over words from different messages")
  assert_eq(named(calls, "composer.quote").length(), 0)
}

///|
test "中屏's tape, built as a host builds: words a mouse picked in a message have 引用 over them in the frame it let go in, there after a while and a move, gone after a press" {
  // (this form alone shows it: a default Tester builds the frame again keeping nothing and shows the pill whatever
  // the page's view read)
  let t = tape_chat(0, 690.0, 840.0, width="medium", height="medium")
  t.check_looks(false)
  page_over(t, 690.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  mouse_dragged(t, mx, my, mx + 300.0, my)
  assert_true(t.ctx().selected_text() != "")
  assert_true(pill_over(t, my) is Some(_), msg="no 引用 over what is picked, in the frame it let go in")
  t.run_for(@ui.move_most_ms)
  assert_true(pill_over(t, my) is Some(_), msg="引用 gone once all the let-go set off is over")
  t.touch(1, mx + 320.0, my + 40.0)
  t.frames_owed()
  assert_true(pill_over(t, my) is Some(_), msg="引用 gone after the pointer moved")
  // (a click of its own, not a second of the press that picked: a double click's picks a word)
  t.run_for(@ui.double_click_ms)
  mouse_clicked(t, mx, my)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(t.words().filter(fn(w) { w.0 == "引用" }).is_empty(), msg="引用 still there after a press")
}
