// The bottom bar, the sheets and a new chat over the fixture (newchat_fixture.mbt), 390 × 844.

///|
/// The bar's places' middles in the window with the notch open (the chats' pages), and its middle's height.
fn bar_places_at() -> (Array[Double], Double) {
  (bar_centres(390.0 - 44.0, 1.0, 4).map(fn(x) { x + 22.0 }), 844.0 - 22.0 - 28.0)
}

///|
test "the bar: 文件 tapped is its page in place of the chats', back is the chats again" {
  let t = tester("home")
  t.draw()
  let (xs, y) = bar_places_at()
  t.tap(xs[1], y)
  assert_eq(app.nav.depth(), 1)
  assert_true(app.nav.top() == Files)
  t.run_for(switch_side_ms)
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("整理发布清单") is None)
  // back goes to the chats, in place
  t.back()
  assert_true(app.nav.top() == Home)
  t.run_for(switch_side_ms)
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "the bar: drawn up, the panel of the other bar; let go on its first place, that bar and 奏" {
  let t = tester("home")
  t.draw()
  let (xs, y) = bar_places_at()
  t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
  // the panel on its way open, to where it rests
  t.run_for(bar.o.end() - t.time())
  // let go over the rows before the panel was all the way open: it stays open
  if app.nav.top() == Home {
    assert_true(bar.mode)
    // the row of the other bar: its first place
    t.tap(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  }
  assert_true(app.nav.top() == Decisions)
  assert_true(t.find("奏") is Some(_))
  match bars_picked.val {
    Some((_, cur)) => assert_eq(cur, 1)
    None => fail("no bar picked")
  }
}

///|
test "the bar: hidden under a page pushed, back as it comes back" {
  let t = tester("home")
  t.draw()
  assert_true(bar.vis.value > 0.99)
  t.tap_text("夜里的构建又失败了")
  t.run_for(bar_hide_ms)
  assert_true(bar.vis.value < 0.01)
  t.back()
  t.run_for(bar_show_ms)
  assert_true(bar.vis.value > 0.99)
}

///|
test "the workspaces' sheet: drawn up to 94%, dragged down past 30% it closes" {
  let t = tester("home")
  t.draw()
  t.tap_text("星火工作室")
  t.settle(unsettled_ok=true) |> ignore
  assert_true((t.get(@ui.Dialog).rect.3 - 844.0 * 0.7).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y - 200.0)
  t.settle(unsettled_ok=true) |> ignore
  assert_true((t.get(@ui.Dialog).rect.3 - 844.0 * 0.94).abs() < 1.0)
  // a tap on the grabber: half
  let (x, y) = t.find("切换 workspace").unwrap()
  t.tap(x, y - 30.0)
  t.settle(unsettled_ok=true) |> ignore
  assert_true((t.get(@ui.Dialog).rect.3 - 844.0 * 0.55).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y + 300.0)
  t.settle(unsettled_ok=true) |> ignore
  assert_true(t.find("切换 workspace") is None)
  assert_true(!sheet_open())
}

///|
test "a sheet takes the drags on it: the list under it does not scroll" {
  let t = tester("home")
  t.draw()
  let before = t.list_offset()
  t.tap_text("星火工作室")
  t.settle(unsettled_ok=true) |> ignore
  t.drag(195.0, 700.0, 195.0, 400.0)
  assert_eq(t.list_offset(), before)
  assert_true(sheet_open())
}

///|
test "a new chat: 令 raises it; the first message makes the chat and the page becomes it" {
  let t = tester("home")
  t.draw()
  let (_, y) = bar_places_at()
  // 令 stands over the bar's middle
  t.tap(195.0, y - 28.0 - 4.0)
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.risen())
  t.run_for(@ui.nav_rise_ms)
  assert_true(t.find("想让 agent 做什么？") is Some(_))
  assert_true(t.find("Opus 5.5 · high") is Some(_))
  t.tap_text("做任何事")
  t.type_text("把发布说明写一下")
  tap_send(t)
  // the page is the chat now, in place: no new page pushed, sideways back from it
  assert_eq(app.nav.depth(), 2)
  assert_true(!app.nav.risen())
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "new:1")
    _ => fail("not the chat")
  }
  t.run_for(new_leave_ms)
  assert_true(t.find("想让 agent 做什么？") is None)
  assert_true(t.find("把发布说明写一下") is Some(_))
}

///|
test "a new chat: its station picked in the sheet, its model in the run picker" {
  let t = tester("newchat")
  open_mode("newchat")
  t.run_for(@ui.nav_rise_ms)
  assert_true(t.find("它会在 Studio 上") is Some(_))
  // the station's chooser, beside the model's
  let (_, cy) = t.find("Opus 5.5 · high").unwrap()
  t.tap(50.0, cy)
  assert_true(t.find("选择运行的 station") is Some(_))
  let (mx, my) = t.find_last("MBA").unwrap()
  t.tap(mx, my)
  assert_true(!sheet_open())
  assert_eq(new_fix.station, "st2")
  assert_true(t.find("它会在 MBA 上") is Some(_))
  t.tap_text("Opus 5.5 · high")
  assert_true(t.find("思考深度") is Some(_))
  let (gx, gy) = t.find_last("GPT-6").unwrap()
  t.tap(gx, gy)
  assert_true(t.find("确定") is Some(_))
  let (ox, oy) = t.find_last("确定").unwrap()
  t.tap(ox, oy)
  assert_true(!sheet_open())
  for l in t.dump().split("\n") {
    if l.contains("GPT") || l.contains("Opus") || l.contains("high") || l.contains("高") {
        }
  }
  assert_true(t.find("GPT-6 · high") is Some(_))
  // cancelled, it sinks back down
  t.tap_text("取消")
  assert_eq(app.nav.depth(), 1)
}

///|
test "the bar is glass of one capture: the bar with its notch, 令 and the ball frosting the page under them" {
  let t = tester("home")
  t.draw()
  let gs = t.drawn_glass().filter(fn(g) { g.1 > 844.0 - 22.0 - 56.0 - 40.0 })
  assert_true(gs.length() >= 3)
  let (_, _, _, _, _, run) = gs[0]
  assert_true(gs.iter().all(fn(g) { g.5 == run }))
  // the notch cut into the bar's glass: 令's 28 and 6 round it, 4 over the edge
  assert_true(t.drawn_notches().iter().any(fn(n) { n.0 == 5 && n.2 == -4.0 && n.3 == 34.0 && n.4 == 8.0 }))
}

///|
test "the notch's icon swaps with a short scale and fade while it stays open; closed, at once" {
  bar_reset()
  let face = Ref::new("ling")
  let out = Ref::new(true)
  let p = Ref::new(1.0)
  // as the bar has it: where it is by what it was told before this frame, then told
  let t = @ui.Tester::new(
    fn(c) { p.val = show_icon(c, face.val, out.val) },
    w=390.0,
    h=844.0,
  )
  t.draw()
  assert_eq(m_face.val, "ling")
  face.val = "plus"
  t.frame()
  t.frame()
  t.frame()
  assert_eq(m_face.val, "plus")
  assert_eq(bar.icon_was, "ling")
  assert_true(p.val > 0.0 && p.val < 1.0, msg="\{p.val}")
  t.run_for(icon_swap_ms)
  assert_eq(bar.icon_was, "")
  assert_true(p.val == 1.0)
  // the notch closed: nothing to see, at once
  out.val = false
  face.val = "ling"
  t.frame()
  assert_eq(m_face.val, "ling")
  assert_eq(bar.icon_was, "")
  t.assert_idle()
}

///|
test "the bar chosen in the panel slides down into the bar's place, its places laid out there from the first" {
  let t = tester("home")
  t.draw()
  let (xs, y) = bar_places_at()
  t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
  // let go over the rows before the panel was all the way open, it stays open: its row tapped
  if bar.swap is None {
    t.run_for(bar.o.end() - t.time())
    t.tap_once(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  }
  // chosen: the bar in view at once, the stack sliding down, a frame at a time to where it lands
  assert_true(app.nav.top() == Decisions)
  let mut seen = false
  let mut last = -1.0
  let lands = bar.o.end()
  while t.time() < lands {
    t.frame()
    match bar.swap {
      Some(s) => {
        let k = s.t(bar.o.x)
        assert_true(k >= last)
        last = k
        if k > 0.05 && k < 0.95 {
          seen = true
        }
      }
      None => ()
    }
  }
  assert_true(seen)
  assert_true(bar.swap is None)
  match bars_picked.val {
    Some((_, cur)) => assert_eq(cur, 1)
    None => fail("no bar picked")
  }
}
