// Native mbui declarative visualizations (.mbui) and sandboxed Wasm 1.0 mini-programs (.wasm) in chat messages,
// full-screen layer, and chat-to-image export.

///|
fn mbui_viz_faults(t : @ui.Tester) -> Array[String] {
  t.audit().filter(fn(f) {
    f.contains("viz_mbui_node") || f.contains("viz_chart_node")
  })
}

///|
test "a placed .mbui file with embedded Wasm renders natively in its message on frame 1 with zero WebViews" {
  let t = chat_tester("chat-mbui")
  t.frame()
  assert_eq(opened_views(t, 2).length(), 0, msg="no WebView opened for .mbui widget")
  assert_eq(viz_frames.length(), 0, msg="no viz_frame state allocated for .mbui widget")
  assert_true(t.find("0.25.0 发布与性能看板") is Some(_), msg="widget title rendered on frame 1")
  assert_true(t.find("首帧布局耗时") is Some(_), msg="stat card rendered")
  assert_true(t.find("各端每日构建通过次数") is Some(_), msg="bar chart rendered")
  assert_true(t.find("灰度 100%") is Some(_), msg="initial Wasm mbui_update computed rollout_pct=100")
  assert_true(t.find("mbui 节点树") is Some(_), msg="flow diagram rendered")
  assert_eq(mbui_viz_faults(t), [])
}

///|
test "interactive tabs, Wasm controller state computation, persistence and follow_up composer drafting in a .mbui widget" {
  let t = chat_tester("chat-mbui")
  t.frame()
  // Trigger Wasm `bench_step` via the "Wasm 复核" button: increments `runs` (1 -> 2) and updates `gate_pass` (94 -> 96)
  t.tap_text("Wasm 复核")
  t.frame()
  assert_true(t.find("第 2 轮") is Some(_), msg="Wasm bench_step updated runs=2 in flow node")
  assert_true(t.find("门禁 96%") is Some(_), msg="Wasm bench_step updated gate_pass=96")
  // Switch to the second tab ("发版检查单")
  t.tap_text("发版检查单")
  t.frame()
  assert_true(t.find("发版前门禁检查") is Some(_), msg="progress inside second tab rendered")
  assert_true(t.find("96 / 100") is Some(_), msg="progress bar reflects Wasm-computed gate_pass=96")
  assert_true(t.find("列表首帧高度同步") is Some(_), msg="table inside second tab rendered")
  assert_eq(mbui_viz_faults(t), [])
  // Toggle the switch ("仅向 Canary 渠道灰度推送"): triggers Wasm `mbui_update` which sets `rollout_pct` = 10
  t.click(Switch, label="仅向 Canary 渠道灰度推送")
  t.frame()
  assert_true(t.find("灰度 10%") is Some(_), msg="Wasm mbui_update recomputed rollout_pct=10 on switch toggle")
  let l = viz_loads.get(viz_id("ws1/st1", "s-c1", "work/s-c1/release.mbui")).unwrap()
  match l.state.get() {
    Some(Object(m)) => {
      assert_eq(m.get("canary_only"), Some(Json::boolean(true)))
      assert_eq(m.get("rollout_pct"), Some(Json::number(10.0)))
      assert_eq(m.get("gate_pass"), Some(Json::number(96.0)))
    }
    other => fail("expected persisted state object, got \{Repr(other)}")
  }
  // Tap the follow-up button ("填入跟进结论") and verify state interpolation into the chat composer
  t.tap_text("填入跟进结论")
  t.frame()
  t.frame()
  let d = @sfbase.writings.get("ws1/st1:s-c1").unwrap()
  assert_eq(d.field.text(), "0.25.0 看板已确认（视图：checklist），开始发版")
  t.frame()
  assert_true(t.find("已添加到输入框，确认后发送") is Some(_))
}

///|
test "standalone .wasm mini-program builds its native UI tree in mbui_init and drives interactive events + follow_up in mbui_event" {
  let standalone_b64 =
    "AGFzbQEAAAABFgRgAn9/AGADf39/AX9gA39/fwBgAAACTAQEbWJ1aQhzZXRfdHJlZQAABG1idWkNc3RhdGVfZ2V0X2kzMgABBG1idWkNc3RhdGVfc2V0X2kzMgACBG1idWkJZm9sbG93X3VwAAADAwIDAwUDAQABBxoCCW1idWlfaW5pdAAECm1idWlfZXZlbnQABQpoAi4AQQBBBkEAQQZBARABEAJBEEEDQegHQQBBBkEBEAFB+ABsahACQYABQfwCEAALNwEBf0EAQQZBARABQQFqIQBBAEEGIAAQAkEQQQNB6AcgAEH4AGxqEAIgAEEETgRAQSBBKxADCwsLxwMEAEEACwZyb3VuZHMAQRALA3FwcwBBIAsrV2FzbSDljovmtYvlrozmiJDvvJrlkJ7lkJDlt7Lovr4gMTQ4MCByZXEvcwBBgAEL/AJ7InRpdGxlIjoiV2FzbSDmspnnrrHlsI/nqIvluo8iLCJyb290Ijp7InR5cGUiOiJjYXJkIiwidGl0bGUiOiJXYXNtIOWunuaXtuWOi+a1i+WZqCIsInN1YnRpdGxlIjoi57qv5a2X6IqC56CB6Kej6YeKIMK3IDEwMCDkuIcgR2FzIOmXqOmZkCIsImJhZGdlIjoi6L2u5qyhICR7cm91bmRzfSIsImJhZGdlX3RvbmUiOiJhY2NlbnQiLCJjaGlsZHJlbiI6W3sidHlwZSI6InN0YXQiLCJsYWJlbCI6IumHh+agt+WQnuWQkCIsInZhbHVlIjoiJHtxcHN9IiwidW5pdCI6InJlcS9zIiwiZGVsdGEiOiIrMTIwL+i9riIsInRvbmUiOiJvayJ9LHsidHlwZSI6ImJ1dHRvbiIsImlkIjoic3RlcCIsImxhYmVsIjoi5omn6KGM5LiA6L2u5Y6L5rWLIiwidG9uZSI6InByaW1hcnkifV19fQ=="
  let widget = @sfbase.viz_mbui_parse("bench.wasm", "wasm:base64:" + standalone_b64).unwrap()
  let kept_state : Ref[Json] = Ref(Json::null())
  let drafted : Ref[String] = Ref("")
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sf.begin(c) |> ignore },
    tree=fn(root) {
      @sfbase.viz_mbui_node(
        root,
        "test:standalone:wasm",
        widget,
        fn() { kept_state.val },
        {
          keep: Some(fn(s) { kept_state.val = s }),
          failed: None,
          follow_up: Some(fn(p) {
            drafted.val = p
            true
          }),
        },
      )
    },
    w=420.0,
    h=600.0,
  )
  t.frame()
  assert_true(t.find("Wasm 实时压测器") is Some(_), msg="standalone .wasm emitted root tree via mbui.set_tree")
  assert_true(t.find("轮次 1") is Some(_), msg="initial rounds=1")
  assert_true(t.find("1120") is Some(_), msg="initial qps=1120")
  assert_eq(mbui_viz_faults(t), [])
  // Click "执行一轮压测" 3 times (rounds: 1 -> 2 -> 3 -> 4; at round 4 Wasm calls mbui.follow_up)
  t.tap_text("执行一轮压测")
  t.frame()
  assert_true(t.find("轮次 2") is Some(_))
  assert_true(t.find("1240") is Some(_))
  t.tap_text("执行一轮压测")
  t.frame()
  assert_true(t.find("轮次 3") is Some(_))
  assert_true(t.find("1360") is Some(_))
  assert_eq(drafted.val, "")
  t.tap_text("执行一轮压测")
  t.frame()
  assert_true(t.find("轮次 4") is Some(_))
  assert_true(t.find("1480") is Some(_))
  assert_eq(drafted.val, "Wasm 压测完成：吞吐已达 1480 req/s")
  match kept_state.val {
    Object(m) => {
      assert_eq(m.get("rounds"), Some(Json::number(4.0)))
      assert_eq(m.get("qps"), Some(Json::number(1480.0)))
    }
    other => fail("expected persisted state from standalone .wasm, got \{Repr(other)}")
  }
}

///|
test "wasm sandbox traps infinite loops deterministically by gas_limit and rejects disallowed host imports" {
  // 1. Disallowed host import (`wasi_snapshot_preview1.fd_write`) is rejected at instantiation time
  let bad_imp_bytes = @sfbase.viz_base64_decode(
    "AGFzbQEAAAABBAFgAAACIwEWd2FzaV9zbmFwc2hvdF9wcmV2aWV3MQhmZF93cml0ZQAA",
  ).unwrap()
  match @sfbase.viz_wasm_instantiate(bad_imp_bytes, Map([])) {
    Ok(_) => fail("expected disallowed import to be rejected")
    Err(e) => assert_true(e.contains("disallowed wasm import module"), msg=e)
  }
  // 2. Infinite loop `loop { br 0 }` is terminated deterministically by instruction gas metering
  let loop_b64 = "AGFzbQEAAAABBAFgAAADAgEABw4BCm1idWlfZXZlbnQAAAoJAQcAA0AMAAsL"
  let loop_raw =
    "{\"title\":\"死循环防护验证\",\"gas_limit\":2000,\"wasm\":\"" +
    loop_b64 +
    "\",\"root\":{\"type\":\"card\",\"title\":\"沙箱测试\",\"children\":[{\"type\":\"button\",\"label\":\"触发死循环\"}]}}"
  let widget = @sfbase.viz_mbui_parse("loop.mbui", loop_raw).unwrap()
  new_run()
  let t = @ui.Tester::new(
    fn(c) { @sf.begin(c) |> ignore },
    tree=fn(root) {
      @sfbase.viz_mbui_node(
        root,
        "test:loop:trap",
        widget,
        fn() { Json::null() },
        { keep: None, failed: None, follow_up: None },
      )
    },
    w=420.0,
    h=400.0,
  )
  t.frame()
  assert_true(t.find("Wasm 沙箱拦截") is None)
  t.tap_text("触发死循环")
  t.frame()
  assert_true(t.find("Wasm 沙箱拦截: wasm gas limit exceeded") is Some(_))
  assert_eq(mbui_viz_faults(t), [])
}

///|
test "opening a .mbui widget full screen renders natively without a WebView and closes on back" {
  let t = chat_tester("chat-mbui")
  t.frame()
  viz_open_full("release.mbui", "ws1/st1", "s-c1", "work/s-c1/release.mbui", "s-c1")
  t.frame()
  t.frame()
  assert_eq(opened_views(t, 2).length(), 0, msg="full screen .mbui uses no WebView")
  assert_true(t.find("release.mbui") is Some(_))
  assert_true(t.find("0.25.0 发布与性能看板") is Some(_))
  assert_eq(mbui_viz_faults(t), [])
  t.back()
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(@sfbase.viz_full.get() is None)
}

///|
test "sharing a chat with a placed .mbui widget draws it synchronously in the exported image without WebView grabs" {
  let file : Json = { "name": "release.mbui", "path": "work/s-c1/release.mbui", "size": 1200 }
  let preview = fn() -> Json {
    {
      "upto": 3,
      "title": "发布节奏",
      "list": [
        msg(3, "agent", @sffixture.by_agent("anthropic", "claude", "s-c1"), "这周的发布面板：\n\n[发布面板](release.mbui)\n", "", {
          "attachments": [file],
          "placed": ["release.mbui"],
          "md": [["p", [[0, 8]]], ["p", [["a", [[11, 15]], { "href": "release.mbui", "path": "release.mbui" }]]]],
          "time": { "createdAt": { "ago": "1 分钟前", "full": "10月15日 10:00" } },
        }),
      ],
      "messages": [],
      "files": [{ "k": "f0", "name": "release.mbui", "size": 1200, "sizeText": "1.2 KB", "type": "application/json", "n": 3, "file": file }],
      "hidden": 0,
    }
  }
  let calls : Array[Made] = []
  let t = publish_core(calls, preview~, menu=true)
  open_publish_page()
  t.frame()
  t.run_for(@sf.presented_rest() - t.time())
  t.run_for(@ui.move_most_ms)
  assert_true(!viz_frames.keys().any(fn(k) { k.has_prefix("publish/") }), msg="no publish WebView opened for .mbui")
  assert_true(t.find("0.25.0 发布与性能看板") is Some(_), msg="mbui widget drawn on publish preview")
  t.click(Button, label="保存到相册")
  t.run_for(@kit.presence_in_ms)
  assert_eq(t.shots().length(), 1, msg="picture taken immediately without waiting for WebView still")
  let words = t.shots()[0].join("|")
  assert_true(words.contains("0.25.0 发布与性能看板"), msg=words)
  assert_eq(t.kept().length(), 1)
}

///|
test "mbui widget charts (line, donut, scatter), svg, details and controls audit cleanly across frame rates" {
  let raw =
    #|{
    #|  "title": "全组件验证",
    #|  "state": { "checked": true },
    #|  "body": [
    #|    { "type": "chart", "chart": "line", "title": "趋势", "labels": ["T1", "T2", "T3"], "values": [10, 24, 18] },
    #|    { "type": "chart", "chart": "donut", "title": "占比", "center": "100%", "items": [{"label": "A", "value": 60, "tone": "green"}, {"label": "B", "value": 40, "tone": "blue"}] },
    #|    { "type": "chart", "chart": "scatter", "title": "分布", "x_unit": "ms", "unit": "MB", "series": [{"name": "S1", "tone": "purple", "points": [[1.0, 2.0, "P1"], [3.5, 4.2, "P2"]]}] },
    #|    { "type": "svg", "viewBox": "0 0 120 40", "height": 40, "svg": "<rect x=\"4\" y=\"4\" width=\"112\" height=\"32\" rx=\"6\" fill=\"var(--blue-bg)\" stroke=\"var(--blue)\" stroke-width=\"1.5\"/><circle cx=\"24\" cy=\"20\" r=\"8\" fill=\"var(--green)\"/><path d=\"M 44 26 L 64 14 L 84 22 L 104 12\" fill=\"none\" stroke=\"var(--primary)\" stroke-width=\"2\"/>" },
    #|    { "type": "progress", "label": "迁移完成度", "value": 85, "max": 100, "tone": "green" },
    #|    { "type": "check", "key": "checked", "label": "已核对回归结果", "note": "零闪烁" },
    #|    { "type": "details", "id": "d1", "title": "展开详情", "open": true, "body": [{ "type": "callout", "title": "提示", "text": "全部通过", "tone": "blue" }, { "type": "code", "text": "moon test" }] }
    #|  ]
    #|}
  let widget = @sfbase.viz_mbui_parse("test.mbui", raw).unwrap()
  for fps in [60, 120, 24, 7] {
    new_run()
    let t = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        @sfbase.viz_mbui_ctx(c, "test:all:\{fps}", widget, Json::null(), { keep: None, failed: None, follow_up: None })
      })
    }, w=420.0, h=1400.0)
    t.set_frame_period(1000.0 / fps.to_double())
    t.draw()
    assert_true(t.find("全组件验证") is Some(_))
    assert_true(t.find("100%") is Some(_))
    assert_true(t.find("全部通过") is Some(_))
    assert_eq(mbui_viz_faults(t), [], msg="fps=\{fps}")
  }
}
