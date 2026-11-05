///|
fn retained_flight_at_half(steps : Int, carried? : Bool = false, row_off? : Double = 0.0) -> Array[Array[Double]] raise {
  reset()
  let text = "一段从输入框飞到消息里的文字，换行的位置也一起保留。"
  let field = @ui.Field::new(text~)
  let row = @signals.signal(false)
  // A chat lays its sent words at the same width as the editor, with its bubble's padding around them.
  let wide = @signals.signal(358.0)
  let y = @signals.signal(45.0)
  let stamp : Ref[@view.View?] = Ref(None)
  let landings : @sf.LiveMap[String, (@view.View, @view.View)] = @sf.LiveMap::new()
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=600.0, platform=2, stable=false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(viewport) {
      viewport.height(Is(Some(180.0))).clips(Is(true)) |> ignore
      viewport.drawn_off(Placed(fn() { (0.0, row_off + send_list_rise(viewport, "chat", fn(_) { landings.get("row").map(fn(l) { l.0 }) })) })) |> ignore
      viewport.show(fn() { row.get() }, fn(bubble) {
        bubble.width(By(fn() { Some(wide.get()) })).offset(By(fn() { (18.0, y.get()) }))
        .padding(Is((14.0, 8.0, 14.0, 8.0))).radius(Is(18.0)).ground(By(fn() { @ui.tree_theme().color(Neutral) })) |> ignore
        let words = bubble.box(fn(w) {
          w.words_runs(Is([@ui.plain(text)])).words_look(By(fn() { @ui.style_words(@sf.theme().t.words) }))
          .ink(By(fn() { @ui.style_ink(@sf.theme().t.words) })).runs_look(Is({ ..@view.runs_plain, words: true })) |> ignore
        })
        landings["row"] = (bubble, words)
        bubble.owns(fn() { landings.remove("row") }) |> ignore
      })
    }) |> ignore
    root.box(fn(input) {
      input.over(Is(true)).width(Is(Some(330.0))).height(Is(Some(100.0))).offset(Is((20.0, 400.0))) |> ignore
      @ui.field(input, field, max_lines=4, line=24.75, color=@sf.theme().p.text) |> ignore
    }) |> ignore
    root.box(fn(layer) {
      layer.over(Is(true)) |> ignore
      send_flight_node(layer, "chat", fn(_) { landings.get("row") })
    }) |> ignore
    stamp.val = Some(root.box(fn(time) {
      time.over(Is(true)).offset(Is((20.0, 300.0))).words_runs(Is([@ui.plain("刚刚")])) |> ignore
      send_time_node(time, fn() { "chat" }, fn() { "row" })
    }))
  })
  t.draw()
  let source = field.lines().unwrap()
  flight_start_from(t.ctx(), "chat", "chat", "row", text, 100.0, [], Some(source), hold=fn(_) {  }, desk=false)
  if carried {
    let first = send_flight.get().unwrap()
    send_flight.set(Some({ ..first, carried: true, lines: None, ms: flight_carry_ms, from_top: first.from_y - 8.0 }))
  }
  field.set("")
  t.draw()
  let f = send_flight.get().unwrap()
  assert_false(f.placed)
  assert_true(t.glyphs_seen().length() > 10)
  row.set(true)
  t.draw()
  assert_true(f.placed)
  let start = f.set_out
  let end = f.way.ends()
  let half = (end - start) / 2.0
  for i in 1..<(steps + 1) {
    t.run_for(start + half * i.to_double() / steps.to_double() - t.time())
  }
  t.run_for(start + half - t.time())
  let mid = t.drawn_instances().map(fn(i) { i.map(fn(x) { (x * 100.0).round() / 100.0 }) })
  // The tester snaps a moment within a millionth of a millisecond to its display frame.
  assert_true((t.time() - start - half).abs() < 1.0e-6)
  assert_eq(@ui.view_tree().unwrap().drawn_of(landings.get("row").unwrap().0.id()).unwrap().alpha, 0.0)
  assert_eq(@ui.view_tree().unwrap().drawn_of(stamp.val.unwrap().id()).unwrap().alpha, 0.0)
  // The landing can move or wrap on this path, but neither change is another send or a new timeline.
  wide.set(338.0)
  y.set(20.0)
  t.draw()
  assert_eq((f.set_out, f.way.ends()), (start, end))
  assert_true(t.glyphs_seen().length() > 10)
  if row_off != 0.0 {
    t.run_for(end - 1.0 - t.time())
    let landing = @ui.view_tree().unwrap().drawn_of(landings.get("row").unwrap().1.id()).unwrap()
    let seen = t.words().filter(fn(w) { w.0 == text && w.5 > 0.9 })
    assert_true(seen.iter().any(fn(w) { (w.2 - landing.y).abs() < 1.0 }),
      msg="the words must meet their drawn row before its copy is released: target=\{landing.y}, words=\{seen}")
  }
  t.run_for(end - t.time())
  assert_true(send_flight.get() is None)
  assert_eq(@ui.view_tree().unwrap().drawn_of(landings.get("row").unwrap().0.id()).unwrap().alpha, 1.0)
  assert_true(t.find(text) is Some(_))
  // Releasing the flying copy keeps the time's entrance on the same declared landing, at either cadence.
  assert_eq(@ui.view_tree().unwrap().drawn_of(stamp.val.unwrap().id()).unwrap().alpha, 0.0)
  t.run_for(@sf.enter_ms / 2.0)
  let time_alpha = @ui.view_tree().unwrap().drawn_of(stamp.val.unwrap().id()).unwrap().alpha
  assert_true(time_alpha > 0.0 && time_alpha < 1.0)
  t.run_for(@sf.enter_ms / 2.0)
  assert_eq(@ui.view_tree().unwrap().drawn_of(stamp.val.unwrap().id()).unwrap().alpha, 1.0)
  mid
}

///|
test "a retained send waits at its source, flies outside the list clip on one declared path, and releases its landing at the same end at any cadence" {
  assert_eq(retained_flight_at_half(0), retained_flight_at_half(12))
}

///|
test "a new chat's first retained words and its list rise on the same path, independently of intervening frames" {
  assert_eq(retained_flight_at_half(0, carried=true), retained_flight_at_half(12, carried=true))
}

///|
test "sent words arrive at their row while its parent is still making way" {
  retained_flight_at_half(0, row_off=50.0) |> ignore
}

///|
fn sent_cut_frame(retained : Bool, up : Double) -> Array[Array[Double]] {
  reset()
  let from = (20.0, 400.0, 200.0, 100.0)
  let shown : @ui.DrawnState = { rect: from, grown: from, clip: (70.0, 420.0, 200.0, 475.0),
    alpha: 0.4, soft: (8.0, 8.0, 8.0, 8.0) }
  let t = @ui.Tester::new(fn(c) {
    if !retained {
      let tile = c.box(style=@ui.style(w=Fixed(160.0), h=Fixed(80.0), bg=Exact(0x335599FFL)), fn() {  })
      @motion.placed(c, tile, fn() {
        let r = c.node_rect(tile)
        @ui.look(alpha=flight_shown(c, tile, Some(shown), from, r.2, r.3, up), dx=100.0 - r.0, dy=110.0 - r.1)
      })
    }
  }, w=400.0, h=600.0)
  if retained {
    @ui.set_view_app(fn(root) {
      flight_visible_node(root, Some(shown), from, fn() { (100.0, 110.0) }, fn() { (160.0, 80.0) },
        fn() { up }, fn() { (0.0, 0.0, 400.0, 600.0) }).ground(Is(0x335599FFL)) |> ignore
    })
  }
  t.draw()
  t.drawn_instances().filter(fn(a) { a[5] == 0.0 }).map(fn(a) {
    // Geometry, opacity, hard cut and soft edges: the visible part of the same source on the same path.
    [0, 1, 2, 3, 11, 16, 17, 18, 19, 52, 53, 54, 55, 56, 57, 58, 59]
    .map(fn(i) { (a[i] * 1000000.0).round() / 1000000.0 })
  })
}

///|
test "a retained flight opens the source's partial visibility and opacity as the old flight does" {
  for up in [0.0, 0.4, 1.0] {
    let old = sent_cut_frame(false, up)
    assert_eq(old.length(), 1)
    assert_eq(sent_cut_frame(true, up), old, msg="up=\{up}")
  }
}
