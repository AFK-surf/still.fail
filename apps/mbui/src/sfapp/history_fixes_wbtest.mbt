// Regression tests for the execution history UI fixes across narrow (`sfapp/history_node.mbt`, `sfapp/history.mbt`),
// wide (`sfdesk/history.mbt`), and shared step/markdown nodes (`sfpages/history_steps_node.mbt`, `sf/markdown_node.mbt`).

///|
/// A narrow chat source whose first agent is actively running (`status = "running"`) and warm (`process = "warm"`),
/// with optional `attention` alerts, paired with a caller-supplied `history` topic JSON.
fn history_fixes_src(
  history : Json,
  attention? : Array[Json] = [],
) -> (Source, ChatRef) {
  let base = fixture("chat")
  let base_chat = base.topic("chat", { "station": "ws1/st1", "session": "s-c1" }).get().value
  let chat_with_active : Json? = match base_chat {
    Some(Object(cm)) => {
      let co = cm.copy()
      co["agents"] = Json::array(
        items(base_chat, "agents").mapi(fn(idx, a) {
          if idx != 0 {
            return a
          }
          match a {
            Object(am) => {
              let w = am.copy()
              w["status"] = Json::string("running")
              if !attention.is_empty() {
                w["attention"] = Json::array(attention)
              }
              match field(Some(a), "session") {
                Some(Object(sm)) => {
                  let so = sm.copy()
                  so["process"] = Json::string("warm")
                  w["session"] = Json::object(so)
                }
                _ => ()
              }
              Json::object(w)
            }
            _ => a
          }
        }),
      )
      Some(Json::object(co))
    }
    _ => base_chat
  }
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "history" {
        { value: Some(history), error: None, version: 1 }
      } else if name == "chat" {
        { value: chat_with_active, error: None, version: 1 }
      } else {
        (base.topic_read)(name, params)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  (src, r)
}

///|
test "history tab switch preserves steps scroll and only-io filter toggles non-io steps" {
  new_run()
  let base_hist = fling_history(8)
  let marked_hist : Json = match base_hist {
    Object(hm) => {
      let ho = hm.copy()
      ho["items"] = Json::array(
        items(Some(base_hist), "items").map(fn(it) {
          if text(field(Some(it), "body"), "kind") == "group" {
            match it {
              Object(im) => {
                let io = im.copy()
                io["work"] = Json::boolean(true)
                Json::object(io)
              }
              _ => it
            }
          } else {
            it
          }
        }),
      )
      Json::object(ho)
    }
    _ => base_hist
  }
  let (src, r) = history_fixes_src(marked_hist)
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  // Scroll up away from the live tail so an older turn sits in the viewport.
  t.wheel(195.0, 440.0, -360.0)
  t.run_for(@ui.move_most_ms)
  let mut picked : (String, Double)? = None
  for k in 0..<8 {
    let label = "读了文件，跑了命令 第\{k}轮"
    match t.find(label) {
      Some((_, y)) if y > 220.0 && y < 700.0 => {
        picked = Some((label, y))
        break
      }
      _ => ()
    }
  }
  guard picked is Some((marker, y_before)) else { fail("expected a scrolled turn group visible") }
  // Switch to 详情 and back to 步骤: View::park retention must keep the steps scroll offset.
  let det = t.rect_of("详情").unwrap()
  t.tap(det.0 + det.2 / 2.0, det.1 + det.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let steps_tab = t.rect_of("步骤").unwrap()
  t.tap(steps_tab.0 + steps_tab.2 / 2.0, steps_tab.1 + steps_tab.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let y_after = t.find(marker).map(fn(p) { p.1 }).unwrap_or(-1.0)
  assert_true((y_after - y_before).abs() < 1.5, msg="scroll jumped: \{y_before} -> \{y_after}")
  // Flip 只看收发 on and off: non-io groups vanish while received/post remain.
  @sfpages.history_only_io_flip()
  t.draw()
  assert_true(t.find(marker) is None, msg="expected group hidden when only-io filter is active")
  @sfpages.history_only_io_flip()
  t.draw()
  assert_true(t.find(marker) is Some(_), msg="expected group restored when only-io filter turns off")
}

///|
test "history head with active stop and evict actions has sufficient touch room and attention wraps" {
  new_run()
  let notes : Array[Json] = [
    {
      "kind": "disk",
      "text": "这个工作区的磁盘空间只剩 1.2 GiB，建议先清理构建缓存目录再继续跑完整测试",
      "more": "",
    },
    {
      "kind": "quota",
      "text": "周额度提醒",
      "more": "本周已用 88%",
      "quota": { "left": 88, "level": "warn", "mark": "C" },
    },
  ]
  let post_with_code : Json = {
    "items": [
      {
        "key": "p-code",
        "entries": [1, 2],
        "body": {
          "kind": "post",
          "content": {
            "text": "运行命令：\n\n```sh\nmoon test --target wasm-gc --release\n```\n",
            "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
            "block": false,
            "failed": false,
          },
        },
      },
    ],
    "live": [],
    "usage": [],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
  let (src, r) = history_fixes_src(post_with_code, attention=notes)
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=740.0, platform=2)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  let head_rooms = t.room_faults().filter(fn(f) { f.contains("history_node.mbt") })
  assert_eq(head_rooms, [])
  let code_rooms = t.room_faults().filter(fn(f) { f.contains("markdown_node.mbt") })
  assert_eq(code_rooms, [])
  let note_squeeze = t
    .squeeze_faults()
    .filter(fn(f) { f.contains("sfapp/history.mbt") || f.contains("history_steps_node.mbt") })
  assert_eq(note_squeeze, [])
  assert_true(t.find("这个工作区的磁盘空间只剩") is Some(_))
}

///|
test "wide history details runtime and evict wrap without room or squeeze faults" {
  guard corner_windows.search_by(w => w.0 == "desk") is Some(i) else { fail("no desk window in corner_windows") }
  let win = corner_windows[i]
  for scale in [1.0, 1.3] {
    let t = screen_in("history", win, "zh", said=true, font_scale=scale)
    let room = t.room_faults().filter(fn(f) { f.contains("sfdesk/history.mbt") })
    assert_eq(room, [])
    let squeeze = t.squeeze_faults().filter(fn(f) { f.contains("sfdesk/history.mbt") })
    assert_eq(squeeze, [])
  }
}

///|
test "history steps at 1.3x: fold toggle room, task wrap, step meta and tool path extra stay uncrushed" {
  new_run()
  let long_lines = Array::makei(14, fn(i) { "第 \{i + 1} 行：验证放大字号下折叠行数预算与展开点击高度是否充足" }).join("\n")
  let rich_history : Json = {
    "items": [
      {
        "key": "r-task",
        "entries": [1, 1],
        "body": {
          "kind": "received",
          "content": {
            "tasks": [
              {
                "text": "构建任务失败：在编译与静态检查阶段遇到较长的错误说明文本，过去单行省略会丢失后半段原因，现在应当在窄屏下完整换行展示出来",
                "agent": true,
                "failed": true,
              },
            ],
            "messages": [],
          },
        },
      },
      {
        "key": "g-step",
        "entries": [2, 3],
        "body": {
          "kind": "group",
          "content": {
            "summary": "读取超长路径并执行验证脚本",
            "title": "读取",
            "failures": 1,
            "pending": 0,
            "rows": [
              {
                "kind": "step",
                "content": {
                  "name": "Read",
                  "hint": "apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt",
                  "meta": "12.3s · 退出码 1",
                  "failed": true,
                  "call": "{\"file_path\":\"/Users/lin/project/apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt\",\"offset\":80,\"limit\":40}",
                  "result": "pub fn history_steps_node() {}",
                  "entries": [2, 3],
                  "brief": false,
                },
              },
            ],
          },
        },
      },
      {
        "key": "p-fold",
        "entries": [4, 4],
        "body": {
          "kind": "post",
          "content": {
            "text": long_lines,
            "place": { "name": "整理发布清单", "surface": "ember", "session": "s-c1" },
            "block": false,
            "failed": false,
          },
        },
      },
    ],
    "live": [],
    "usage": [],
    "edge": "从 10/19 08:12 开始",
    "empty": false,
    "loaded": true,
    "more": false,
  }
  let (base_src, r) = history_fixes_src(rich_history)
  let src : Source = {
    ..base_src,
    call: fn(name, params, done) {
      if name == "history.tool" {
        done(
          Ok({
            "call": [
              {
                "kind": "path",
                "path": "/Users/lin/project/apps/mbui/src/sfpages/very/long/nested/directory/history_steps_node_implementation.mbt",
                "extra": "第 80-119 行",
              },
              {
                "kind": "facts",
                "items": [
                  { "key": "很长的参数键名称用于测试折行", "value": "非常长的参数值内容不会在宽度不足时把同排标签挤没" },
                ],
              },
            ],
            "result": [],
          }),
        )
      } else {
        (base_src.call)(name, params, done)
      }
    },
  }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.set_font_scale(1.3)
  t.run_for(@ui.move_most_ms)
  app.nav.push(History(r, "s-c1", None))
  t.run_for(@ui.move_most_ms)
  // Unwrapped task error wraps across multiple lines instead of clipping to one line.
  let task_rect = t.rect_of("构建任务失败").unwrap()
  assert_true(task_rect.3 > 25.0, msg="expected wrapped task height > 25, got \{Repr(task_rect)}")
  // Fold toggle button has >= 44px touch height under 1.3x font scale.
  let fold_btn = t.rect_of("展开 · 还有").unwrap()
  assert_true(fold_btn.3 >= @sf.row_least() - 0.5 || t.room_faults().filter(fn(f) { f.contains("history_steps_node.mbt") }).is_empty(), msg="fold toggle: \{Repr(fold_btn)}")
  // Open group and open Read step: step meta and tool path extra stay uncrushed, facts wrap cleanly.
  let grp = t.rect_of("读取超长路径并执行验证脚本").unwrap()
  t.tap(grp.0 + grp.2 / 2.0, grp.1 + grp.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let meta = t.rect_of("12.3s · 退出码 1").unwrap()
  assert_true(meta.2 > 40.0, msg="expected uncrushed step meta width > 40, got \{Repr(meta)}")
  t.tap(meta.0 - 20.0, meta.1 + meta.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let extra = t.rect_of("第 80-119 行").unwrap()
  assert_true(extra.2 > 40.0, msg="expected uncrushed path extra width > 40, got \{Repr(extra)}")
  let step_rooms = t.room_faults().filter(fn(f) { f.contains("history_steps_node.mbt") })
  assert_eq(step_rooms, [])
  let step_squeeze = t.squeeze_faults().filter(fn(f) { f.contains("history_steps_node.mbt") })
  assert_eq(step_squeeze, [])
}
