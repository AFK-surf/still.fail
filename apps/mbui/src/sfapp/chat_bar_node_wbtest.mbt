// Adaptive Small-screen chat top bar title (chat_bar_node.mbt):
// 1. Whole title fits on Row 1 -> single 50pt bar, people drop first, title not toggleable.
// 2. Overflows Row 1 with >= max(44pt, width("一二三…")) left -> Row 1 truncated with ellipsis, tap expands
//    smoothly (280ms) to Row 2 full width keeping Row 1 controls horizontally locked; tap Row 2 collapses (260ms).
// 3. Overflows Row 1 with < max(44pt, width("一二三…")) left -> auto-expanded immediately to Row 2, non-collapsible.

///|
fn chat_bar_node_tester(
  title : String,
  extra_agents? : Int = 0,
  archivable? : Bool = false,
  has_jobs? : Bool = false,
  font_scale? : Double = 1.0,
  w? : Double = 390.0,
  h? : Double = 844.0,
  msg_count? : Int = 0,
) -> (@ui.Tester, @signals.Signal[String]) {
  new_run()
  @sfbase.chat_page_nodes.set(true)
  let base = fixture("chat")
  let title_sig = @signals.signal(title, same=fn(a, b) { a == b })
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      if name == "chatJobs" && has_jobs {
        let jobs : Map[String, Json] = match got.value {
          Some(Object(m)) => m.copy()
          _ => Map([])
        }
        jobs["hasJobs"] = Json::boolean(true)
        return { ..got, value: Some(Json::object(jobs)) }
      }
      guard name == "chat" && got.value is Some(Object(chat)) else { return got }
      let changed = chat.copy()
      changed["title"] = Json::string(title_sig.get())
      changed["archivable"] = Json::boolean(archivable)
      changed["archived"] = Json::boolean(false)
      if extra_agents > 0 {
        let agents = items(got.value, "agents").copy()
        for idx in 0..<extra_agents {
          agents.push({
            "session": {
              "key": "s-extra-\{idx}",
              "runtime": "codex",
              "maker": { "id": "openai", "name": "OpenAI" },
              "agentText": "Codex",
              "statusText": "未开始",
              "tone": "neutral",
            },
            "status": "idle",
          })
        }
        changed["agents"] = Json::array(agents)
      }
      if msg_count > 0 {
        let msgs = items(got.value, "messages")
        if msgs.length() > 0 && msgs[msgs.length() - 1] is Object(last) {
          let base_seq = number(Some(msgs[msgs.length() - 1]), "seq")
          let built : Array[Json] = []
          for idx in 0..<msg_count {
            let m = last.copy()
            m.remove("attachments")
            m.remove("placed")
            m["seq"] = Json::number(base_seq + idx.to_double())
            m["ts"] = Json::string("ts\{idx + 1}")
            m["id"] = Json::string("m-\{idx + 1}")
            built.push(Json::object(m))
          }
          changed["messages"] = Json::array(built)
        }
      }
      { ..got, value: Some(Json::object(changed)) }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title, station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=2)
  if font_scale != 1.0 {
    t.set_font_scale(font_scale)
  }
  t.run_for(@ui.move_most_ms)
  (t, title_sig)
}

///|
fn bar_node_audit(t : @ui.Tester) -> Array[String] {
  t.audit().filter(fn(f) { f.contains("chat_bar_node") })
}

///|
fn bar_agent_x(t : @ui.Tester) -> Double? {
  for s in t.semantics() {
    if s.role == @ui.Role::Button && s.label.contains("Willow") && s.rect.1 < 50.0 {
      return Some(s.rect.0)
    }
  }
  None
}

///|
test "小屏顶栏：短标题稳居第 1 行，点击不展开，零 audit 告警" {
  let (t, _) = chat_bar_node_tester("梳理发布清单")
  let bar_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: "梳理发布清单", station_name: "Willow" }
  assert_eq(bar_extra_target(bar_ref), 0.0)
  let hits = t.words().filter(fn(w) { w.0 == "梳理发布清单" && w.5 > 0.5 })
  assert_eq(hits.length(), 1, msg="\{Repr(hits)}")
  assert_true(hits[0].2 < 50.0, msg="short title on Row 1: \{Repr(hits[0])}")
  assert_eq(bar_node_audit(t), [])
  // Tapping short title must NOT expand Row 2
  t.tap(hits[0].1 + hits[0].3 / 2.0, hits[0].2 + hits[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(bar_extra_target(bar_ref), 0.0)
  let hits_after = t.words().filter(fn(w) { w.0 == "梳理发布清单" && w.5 > 0.5 })
  assert_eq(hits_after.length(), 1)
  assert_true(hits_after[0].2 < 50.0)
  assert_eq(bar_node_audit(t), [])
}

///|
fn first_msg_top(t : @ui.Tester, text : String) -> Double? {
  let ys = t.words().filter(fn(w) { w.0 == text && w.5 > 0.5 }).map(fn(w) { w.2 })
  if ys.length() == 0 {
    None
  } else {
    Some(ys.fold(init=ys[0], fn(a, b) { if b < a { b } else { a } }))
  }
}

///|
test "小屏顶栏：放得下 3 字+省略号的长标题点击平滑展开到第 2 行、第 1 行控件横坐标锁定、再点收起，全过程零 audit 告警" {
  let long_title = "重新设计手机端小屏顶部栏标题展开与收起动画节奏验证"
  let (t, _) = chat_bar_node_tester(long_title, msg_count=14)
  t.move_to(195.0, 400.0)
  t.wheel(195.0, 400.0, -10000.0)
  t.run_for(@ui.move_most_ms)
  let bar_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: long_title, station_name: "Willow" }
  let r2_ref = "做完了：列表、跳到最新的按钮、加载更早的消息都好了，截图也换了。"
  // Collapsed baseline
  assert_eq(bar_extra_target(bar_ref), 0.0)
  assert_eq(bar_node_audit(t), [], msg="collapsed audit: \{Repr(bar_node_audit(t))}")
  guard bar_agent_x(t) is Some(agent_x0) else { fail("missing Row 1 agent mark") }
  guard first_msg_top(t, r2_ref) is Some(msg_y0) else {
    fail("missing top message: \{Repr(t.words().filter(fn(w) { w.2 < 300.0 }))}")
  }
  assert_true(msg_y0 >= 60.0 && msg_y0 < 160.0, msg="top message anchored under bar: \{msg_y0}")
  // Row 1 has truncated words in the top 50pt
  let row1_words = t.words().filter(fn(w) { w.2 < 50.0 && w.1 > 44.0 && w.5 > 0.5 && w.0 == long_title })
  assert_true(row1_words.length() > 0, msg="Row 1 title expected: \{Repr(t.words().filter(fn(w) { w.2 < 60.0 }))}")
  let tap_x = row1_words[0].1 + 20.0
  let tap_y = 25.0
  // Tap Row 1 title to expand (280ms)
  t.tap(tap_x, tap_y)
  t.run_for(chat_bar_expand_ms / 2.0)
  assert_eq(bar_node_audit(t), [], msg="mid-expand audit: \{Repr(bar_node_audit(t))}")
  guard bar_agent_x(t) is Some(agent_x_mid) else { fail("missing Row 1 agent mid-expand") }
  assert_true((agent_x_mid - agent_x0).abs() < 0.2, msg="agent X jumped mid-expand: \{agent_x0} vs \{agent_x_mid}")
  guard first_msg_top(t, r2_ref) is Some(msg_y_mid) else { fail("missing message mid-expand") }
  assert_true(msg_y_mid > msg_y0 + 10.0, msg="message list should move smoothly downward mid-expand: \{msg_y0} -> \{msg_y_mid}")
  t.run_for(chat_bar_expand_ms)
  assert_eq(bar_node_audit(t), [], msg="expanded audit: \{Repr(bar_node_audit(t))}")
  assert_true(bar_extra_target(bar_ref) >= 50.0, msg="expanded Row 2 height >= 50pt")
  guard bar_agent_x(t) is Some(agent_x_exp) else { fail("missing Row 1 agent expanded") }
  assert_true((agent_x_exp - agent_x0).abs() < 0.2, msg="agent X jumped expanded: \{agent_x0} vs \{agent_x_exp}")
  // Row 1 title is laid_nowhere once settled expanded; Row 2 shows full title below 50pt
  let row1_after = t.words().filter(fn(w) { w.2 < 48.0 && w.0 == long_title && w.5 > 0.0 })
  assert_eq(row1_after.length(), 0, msg="Row 1 title hidden when settled expanded")
  let row2_hits = t.words().filter(fn(w) { w.2 >= 48.0 && w.0 == long_title && w.5 > 0.5 })
  assert_eq(row2_hits.length(), 1, msg="Row 2 shows full title: \{Repr(row2_hits)}")
  guard first_msg_top(t, r2_ref) is Some(msg_y_exp) else { fail("missing message expanded") }
  assert_true(msg_y_exp >= msg_y0 + 50.0 - 0.5, msg="message list pushed down by Row 2 height: \{msg_y0} -> \{msg_y_exp}")
  // Tap Row 2 title to collapse (260ms)
  t.tap(row2_hits[0].1 + row2_hits[0].3 / 2.0, row2_hits[0].2 + row2_hits[0].4 / 2.0)
  t.run_for(chat_bar_collapse_ms / 2.0)
  assert_eq(bar_node_audit(t), [], msg="mid-collapse audit: \{Repr(bar_node_audit(t))}")
  t.run_for(chat_bar_collapse_ms)
  assert_eq(bar_node_audit(t), [], msg="collapsed-back audit: \{Repr(bar_node_audit(t))}")
  assert_eq(bar_extra_target(bar_ref), 0.0)
  guard bar_agent_x(t) is Some(agent_x_end) else { fail("missing Row 1 agent collapsed back") }
  assert_true((agent_x_end - agent_x0).abs() < 0.2, msg="agent X jumped after collapse")
  guard first_msg_top(t, r2_ref) is Some(msg_y_end) else { fail("missing message after collapse") }
  assert_true((msg_y_end - msg_y0).abs() < 0.5, msg="message list returned to baseline: \{msg_y0} vs \{msg_y_end}")
}

///|
test "小屏顶栏：放不下 3 字+省略号时默认直接展开到第 2 行，且不可点收起" {
  let tight_title = "极窄标题测试：当第 1 行连三个汉字加省略号都放不下时自动展开"
  // w=290 with 1 agent pill + jobs + info + more leaves ~30pt on Row 1 (< width("一二三…"))
  let (t, _) = chat_bar_node_tester(
    tight_title,
    extra_agents=0,
    archivable=false,
    has_jobs=true,
    w=290.0,
    msg_count=1,
  )
  let bar_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: tight_title, station_name: "Willow" }
  assert_true(bar_extra_target(bar_ref) > 30.0, msg="must auto-expand on mount")
  let row2_hits = t.words().filter(fn(w) { w.2 >= 48.0 && w.0 == tight_title && w.5 > 0.5 })
  assert_eq(row2_hits.length(), 1, msg="auto-expanded title shown on Row 2: \{Repr(row2_hits)}")
  assert_eq(bar_node_audit(t), [], msg="auto-expanded audit: \{Repr(bar_node_audit(t))}")
  // Tapping Row 2 must NOT collapse it back
  t.tap(row2_hits[0].1 + row2_hits[0].3 / 2.0, row2_hits[0].2 + row2_hits[0].4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(bar_extra_target(bar_ref) > 30.0, msg="non-collapsible when Row 1 cannot fit 3 chars")
  assert_eq(bar_node_audit(t), [])
}

///|
test "小屏顶栏：大字号(1.3x)且标题缩短为短标题时自动收起并保持 audit 通过" {
  let long_title = "大字号展开态动态变短收起测试标题内容很长会换行"
  let (t, title_sig) = chat_bar_node_tester(long_title, extra_agents=0, font_scale=1.3, msg_count=1)
  let bar_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: long_title, station_name: "Willow" }
  // Expand if in State 2 (or already auto-expanded in State 3)
  if bar_extra_target(bar_ref) == 0.0 {
    let row1_words = t.words().filter(fn(w) { w.2 < 50.0 && w.1 > 44.0 && w.5 > 0.5 && w.0 == long_title })
    assert_true(row1_words.length() > 0, msg="expected Row 1 word: \{Repr(t.words().filter(fn(w) { w.2 < 60.0 }))}")
    t.tap(row1_words[0].1 + 20.0, 25.0)
    t.run_for(chat_bar_expand_ms + @ui.move_most_ms)
  }
  assert_true(bar_extra_target(bar_ref) > 30.0)
  assert_eq(bar_node_audit(t), [])
  // Title shrinks to short title -> collapses smoothly to Row 1
  title_sig.set("短")
  t.run_for(chat_bar_collapse_ms + @ui.move_most_ms)
  assert_eq(bar_extra_target(bar_ref), 0.0)
  let short_hits = t.words().filter(fn(w) { w.0 == "短" && w.5 > 0.5 })
  assert_eq(short_hits.length(), 1)
  assert_true(short_hits[0].2 < 50.0)
  assert_eq(bar_node_audit(t), [])
}

///|
test "小屏顶栏：有状态栏且可点展开时，第 1 行标题自身高度不被内边距撑大，并与返回键/agent/更多垂直居中对齐" {
  let long_title = "研究执行历史页面结构与性能"
  let (t, _) = chat_bar_node_tester(long_title, msg_count=1)
  t.post(@hostapi.system_channel, "{\"over\":false,\"bars\":{\"top\":40,\"bottom\":0,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let bar_ref : ChatRef = { station: "ws1/st1", session: "s-c1", title: long_title, station_name: "Willow" }
  assert_eq(bar_extra_target(bar_ref), 0.0)
  let title_hits = t.words().filter(fn(w) { w.0 == long_title && w.5 > 0.5 })
  assert_eq(title_hits.length(), 1, msg="expected single Row 1 title: \{Repr(title_hits)}")
  let (_, _, ty, _, th, _) = title_hits[0]
  assert_true(th < 28.0, msg="words node height must not include vertical padding: h=\{th}")
  assert_true(ty >= 50.0, msg="title must stay clear of 40pt status bar: y=\{ty}")
  let title_mid = ty + th / 2.0
  for label in ["返回", "Claude · Willow", "对话信息", "更多"] {
    let found = t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Button && s.label == label })
    guard found is Some(s) else { fail("missing button \{label}") }
    let btn_mid = s.rect.1 + s.rect.3 / 2.0
    assert_true((title_mid - btn_mid).abs() < 0.5, msg="title mid \{title_mid} != \{label} mid \{btn_mid}")
  }
  assert_eq(bar_node_audit(t), [])
}

///|
test "小屏顶栏：对话有服务和后台任务时，打开它们的圆键有名字（读屏念得出、测试按名字找得到）" {
  let (t, _) = chat_bar_node_tester("短标题", has_jobs=true)
  let keys = t.all(Button, label="服务和后台任务")
  assert_eq(keys.length(), 1, msg="the jobs key, by its name")
}
