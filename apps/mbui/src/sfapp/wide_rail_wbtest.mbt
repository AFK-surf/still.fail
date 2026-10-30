// The wide frame's rail and its sidebar as the web's (Rail.tsx, brand.tsx, shell.css.ts dock): folded, the rail a bar
// of its own and the list shown a while as the pointer comes onto it; each sidebar's width and folding kept on the
// device; the lit place pressed again folds or opens; ⌃1 … ⌃9 the workspaces; a row's menu relays it.

///|
/// The latest `prefs.set` that said this of the sidebars, by `<workspace>\n<group>` (folded or not) or `\n<group>` (its
/// width, every workspace's).
fn sidebar_kept(calls : Array[Made], key : String) -> Json? {
  let mut out : Json? = None
  for m in calls {
    if m.name == "prefs.set" {
      match field(field(Some(m.params), "sidebars"), key) {
        Some(v) => out = Some(v)
        None => ()
      }
    }
  }
  out
}

///|
test "wide: ⌘\\ folds the sidebar to the rail's bar of its own; the pointer on it shows the list a while over the page, folded again 400 ms after it left; kept (prefs.set sidebars)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(t.find("新建对话") is Some(_))
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is None, msg="folded")
  assert_eq(sidebar_kept(calls, "ws1\nchats"), Some(Json::string("closed")))
  // the bar's rail, 6 from the window's edge: its places 2 in
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  assert_eq(rx, @sfdesk.closed_bar_in + 2.0)
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is Some(_), msg="shown a while")
  // off it: still there for a moment, then folded again
  t.move(1000.0, 400.0)
  t.frame()
  assert_true(@sfdesk.wide.peeking.get())
  t.run_for(@sfdesk.peek_leave_ms)
  t.frame()
  assert_false(@sfdesk.wide.peeking.get())
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is None)
  // ⌘\ again: open, kept so
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is Some(_))
  assert_eq(sidebar_kept(calls, "ws1\nchats"), Some(Json::null()))
}

///|
/// The ground (30, Rail.css.ts item's) of the rail's place at `rect` (its 38 to press): its box as laid out.
fn rail_ground_at(t : @ui.Tester, rect : (Double, Double, Double, Double)) -> @ui.Laid {
  let (x, y, w, h) = rect
  t
  .boxes()
  .iter()
  .find_first(fn(b) {
    b.kind != "text" && b.w == 30.0 && b.h == 30.0 && b.x >= x && b.y >= y && b.x + b.w <= x + w && b.y + b.h <= y + h
  })
  .unwrap()
}

///|
test "wide on a Mac: the closed bar, shown a while, one corner all round, the window's less its 6; its places' grounds one corner, concentric with it" {
  let calls : Array[Made] = []
  // (a Mac's window: its corners 16, its buttons in the app's top row)
  let t = wide_tester(calls, window_corner=16.0, window_inset=true)
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  let follow = @ui.concentric(16.0, @sfdesk.closed_bar_in)
  // folded, and shown a while: no corner of the bar a pane's 34 (each frame held to the corner rule: corners_held)
  for peek in [false, true] {
    let gear = t.query(Button, label=@sf.t("web-pages.settings.title")).unwrap().rect
    if peek {
      t.move(gear.0 + gear.2 / 2.0, gear.1 + gear.3 / 2.0)
      t.run_for(@ui.move_most_ms)
      assert_true(t.find("新建对话") is Some(_), msg="shown a while")
    }
    let bar = t
      .boxes()
      .iter()
      .find_first(fn(b) { b.x == @sfdesk.closed_bar_in && b.radius > 0.0 && b.h > 400.0 && b.bg != 0L })
      .unwrap()
    assert_eq(bar.radii, (follow, follow, follow, follow))
    // the settings' ground at the bar's foot, 6 from its left and its foot, concentric with the bar's corner there
    // (6.4), all round alike; a place's in the middle the same, one layer, one corner
    let inner = @ui.concentric(follow, 6.0)
    let g = rail_ground_at(t, gear)
    assert_eq(g.radii, (inner, inner, inner, inner))
    let files = rail_ground_at(t, t.query(Button, label="文件").unwrap().rect)
    assert_eq(files.radii, (inner, inner, inner, inner))
    assert_eq(t.corner_faults(), [])
    // shown a while: the filter in the bar's top right corner, linked to that corner: 6 from its top and side, its
    // ground under the pointer concentric with it there (the corner rule holds a linked box to its link)
    if peek {
      let named = @sf.t("web-main.filter.chats.named", args=[("named", @sf.t("web-main.filter.all"))])
      let (fx, fy, fw, fh) = t.query(Button, label=named).unwrap().rect
      t.move(fx + fw / 2.0, fy + fh / 2.0)
      t.run_for(@ui.move_most_ms)
      let filter = t
        .boxes()
        .iter()
        .find_first(fn(b) { b.kind != "text" && b.w == fw && b.h == fh && b.x == fx && b.y == fy && b.bg != 0L })
        .unwrap()
      assert_eq(filter.radii, (inner, inner, inner, inner))
      assert_eq((bar.x + bar.w - (filter.x + filter.w), filter.y - bar.y), (6.0, 6.0))
      assert_eq(t.corner_faults(), [])
    }
  }
}

///|
test "wide: the lit place pressed again folds its sidebar, shown a while (the pointer is on the rail); its width dragged is kept" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="对话").unwrap().rect
  t.tap(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded)
  assert_true(@sfdesk.wide.peeking.get())
  // pressed in the bar: open again
  let (bx, by, bw, bh) = t.query(Button, label="对话").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.wide.folded)
  // its edge dragged 60 to the right: 300, kept once let go
  let edge = @sfdesk.rail_w + 240.0
  t.drag(edge, 400.0, edge + 60.0, 400.0)
  t.frame()
  // (as far as the pointer went from where it was pressed: the library's edge, @sf.handle_drag)
  assert_eq(@sfdesk.wide.side_w, 300.0)
  assert_eq(sidebar_kept(calls, "\nchats"), Some(Json::string(@sfdesk.wide.side_w.round().to_int().to_string())))
}

///|
test "wide: each place's sidebar as it was left: 对话's folded at its width, 文件's open; back on 对话 from the rail, folded, shown a while with the pointer on it and folded again as it leaves" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let press = fn(label : String) {
    let (x, y, w, h) = t.query(Button, label~).unwrap().rect
    t.move(x + w / 2.0, y + h / 2.0)
    t.tap(x + w / 2.0, y + h / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  // 对话's dragged to 300, then folded
  let edge = @sfdesk.rail_w + 240.0
  t.drag(edge, 400.0, edge + 60.0, 400.0)
  t.frame()
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded)
  // 文件 pressed from the bar: its own, never folded, open at its own width
  press("文件")
  assert_false(@sfdesk.wide.folded)
  assert_eq(@sfdesk.wide.side_w, 240.0)
  // 对话 pressed: its sidebar as it was left, folded, 300 wide, shown a while (the pointer is on the rail)
  press("对话")
  assert_true(@sfdesk.wide.folded && @sfdesk.wide.peeking.get())
  assert_eq(@sfdesk.wide.side_w, 300.0)
  assert_true(t.find("新建对话") is Some(_))
  // the pointer off it: folded again a moment after
  t.move(1000.0, 400.0)
  t.run_for(@sfdesk.peek_leave_ms)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.wide.peeking.get())
  assert_true(t.find("新建对话") is None)
}

///|
test "wide: the sidebar's edge is pressed and shows its ↔ 6 either side of its line, as the web's; a drag from wherever it shows sets its width" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let edge = @sfdesk.rail_w + 240.0
  let offsets = [-16.0, -12.0, -8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 5.0, 6.0, 8.0, 12.0, 16.0]
  for y in [400.0, 700.0, 780.0] {
    let shown : Array[Double] = []
    for dx in offsets {
      let x = edge + dx
      t.move(x, y)
      if t.cursor() != ResizeX {
        continue
      }
      shown.push(dx)
      t.drag(x, y, x + 30.0, y)
      assert_eq(@sfdesk.wide.side_w, 270.0)
      t.drag(x + 30.0, y, x, y)
      assert_eq(@sfdesk.wide.side_w, 240.0)
    }
    // (over a row and over none alike: the strip its line is in the middle of, no room grown round it)
    assert_eq(shown, [-6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 5.0], msg="at \{y}")
  }
}

///|
test "wide: the sidebar's edge let go a little past where the last frame drew it: there at once, nothing moving after" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let edge = @sfdesk.rail_w + 240.0
  // (its line in the middle of its strip)
  let edge_at = fn() { t.query(Button, label="调整侧边栏宽度 · 收起侧边栏").unwrap().rect.0 + @sfdesk.edge_half }
  t.hold_drag(edge, 400.0, edge + 60.0, 400.0)
  assert_eq(edge_at(), @sfdesk.rail_w + 300.0)
  // let go 6 further on, before a frame drew it there (the hand ahead of what is drawn): the frame that sees it let
  // go has the sidebar as wide as the hand left it, not moving the rest of the way after it (the block's move)
  t.release(edge + 66.0, 400.0)
  assert_eq(@sfdesk.wide.side_w, 306.0)
  assert_eq(edge_at(), @sfdesk.rail_w + 306.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(edge_at(), @sfdesk.rail_w + 306.0)
  assert_eq(sidebar_kept(calls, "\nchats"), Some(Json::string("306")))
}

///|
test "wide: a sidebar's width the person's, the same in another workspace; folded or not each workspace's own" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  // 对话's dragged to 300 and folded in the first workspace
  let edge = @sfdesk.rail_w + 240.0
  t.drag(edge, 400.0, edge + 60.0, 400.0)
  t.frame()
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded)
  assert_eq(sidebar_kept(calls, "\nchats"), Some(Json::string("300")))
  assert_eq(sidebar_kept(calls, "ws1\nchats"), Some(Json::string("closed")))
  // the second: open, 300 wide
  t.key(@ui.key_of_char('2'), mods=@ui.mod_ctrl)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws2")
  assert_false(@sfdesk.wide.folded)
  assert_eq(@sfdesk.wide.side_w, 300.0)
  // back in the first: folded as it was left, 300 wide
  t.key(@ui.key_of_char('1'), mods=@ui.mod_ctrl)
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws1")
  assert_true(@sfdesk.wide.folded)
  assert_eq(@sfdesk.wide.side_w, 300.0)
}

///|
test "wide: ⌃2 goes to the second workspace (prefs.set workspace)" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('2'), mods=@ui.mod_ctrl)
  t.frame()
  assert_eq(app.picked.get(), "ws2")
  assert_true(named(calls, "prefs.set").iter().any(fn(m) { text(Some(m.params), "workspace") == "ws2" }))
}

///|
test "wide: a row's menu has 接力到频道… for a chat with an agent" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (x, y) = t.find("整理发布清单").unwrap()
  t.right_click(x, y)
  t.frame()
  assert_true(t.find("接力到频道…") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
test "wide: 已归档 one of the sidebar's lists, slid to: its rows under its field, the newest open beside it; 恢复 puts one back (chat.archive, archived false)" {
  let calls : Array[Made] = []
  reset()
  let base = fixture("home")
  let row = fn(id : String, title : String) -> Json {
    {
      "station": "ws1/st1",
      "id": id,
      "session": "s-" + id,
      "thread": 2,
      "title": title,
      "last": "说完了",
      "at": 0,
      "clock": "14:05",
      "how": "手动归档",
      "deletable": true,
    }
  }
  let archive : Json = { "days": [{ "label": "今天", "items": [row("a1", "整理上个月的发票"), row("a2", "试一下新的图标尺寸")] }] }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "archive" {
        { value: Some(archive), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
  t.frame()
  app.nav.push(Archived)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("搜索归档") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("试一下新的图标尺寸") is Some(_))
  // the newest beside the list
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "s-a1")
    _ => fail("the newest not open")
  }
  // pointed at, 恢复
  let (x, y) = t.find("试一下新的图标尺寸").unwrap()
  t.move(x, y)
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="恢复「试一下新的图标尺寸」").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  assert_true(
    calls.iter().any(fn(m) {
      m.name == "chat.archive" && text(Some(m.params), "session") == "s-a2" && field(Some(m.params), "archived") == Some(Json::boolean(false))
    }),
  )
  // right clicked (held, by a finger: its keys never drawn for one), its menu: 恢复到列表 and 删除
  let (x, y) = t.find("整理上个月的发票").unwrap()
  t.right_click(x, y)
  t.frame()
  assert_true(t.find("删除") is Some(_))
  t.tap_text("恢复到列表")
  t.frame()
  assert_true(
    calls.iter().any(fn(m) {
      m.name == "chat.archive" && text(Some(m.params), "session") == "s-a1" && field(Some(m.params), "archived") == Some(Json::boolean(false))
    }),
  )
}

///|
test "wide: 自定义侧边条 from the rail's menu: what can be added beside the rail, by kind; one pressed is put in (prefs.set rails); Esc ends it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.right_click(rx + rw / 2.0, ry + rh / 2.0)
  t.frame()
  let (mx, my) = t.find("自定义侧边条").unwrap()
  t.tap(mx, my)
  t.frame()
  assert_true(@sfdesk.wide.editing)
  assert_true(t.find("对话列表") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  let (ax, ay) = t.find("我参与的").unwrap()
  t.tap(ax, ay)
  t.frame()
  match field(field(Some(named(calls, "prefs.set").last().unwrap().params), "rails"), "ws1") {
    Some(Array(a)) => assert_true(a.contains(Json::string("mine")))
    _ => fail("no rails kept")
  }
  t.key(@ui.key_escape)
  t.frame()
  assert_false(@sfdesk.wide.editing)
}

///|
/// The wide frame over the home fixture with what the core would say of `changed` topics, the prefs set kept as the
/// core keeps them (a `trouble` set: there at once).
fn wide_with(calls : Array[Made], changed : Map[String, Json]) -> @ui.Tester {
  reset()
  let base = fixture("home")
  let kept : Map[String, Json] = {}
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match changed.get(name) {
        Some(v) => { value: Some(v), error: None, version: 1 }
        None if name == "prefs" =>
          match (base.topic)(name, params).value {
            Some(Object(m)) => {
              let p = m.copy()
              p["trouble"] = Json::object(kept)
              { value: Some(Json::object(p)), error: None, version: 2 + kept.length() }
            }
            v => { value: v, error: None, version: 1 }
          }
        None => (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      if name == "prefs.set" {
        match field(Some(params), "trouble") {
          Some(Object(t)) =>
            for k, v in t {
              if v == Json::null() {
                kept.remove(k)
              } else {
                kept[k] = v
              }
            }
          _ => ()
        }
      }
      (base.call)(name, params, done)
    },
  }
  @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, platform=0)
}

///|
/// The home fixture's chats of ws1 with what is wrong with its stations.
fn chats_in_trouble() -> Json {
  match (fixture("home").topic)("chats", { "scope": Json::string("ws1"), "mine": Json::boolean(false) }).value {
    Some(Object(m)) => {
      let v = m.copy()
      v["trouble"] = { "text": "MBA 连不上了", "state": "error" }
      Json::object(v)
    }
    _ => Json::null()
  }
}

///|
test "wide: with the bell in the rail, the stations' trouble is in 待处理's panel, not under the list, until it has been looked at: kept as it opens (prefs.set trouble seen), listed while open, not the next time" {
  let calls : Array[Made] = []
  let t = wide_with(calls, { "chats": chats_in_trouble() })
  t.frame()
  assert_true(t.find("MBA 连不上了") is None, msg="not in the lists' foot")
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  let (x, y) = t.find("MBA 连不上了").unwrap()
  // 10 past the bell
  assert_true(x >= bx + bw + 10.0, msg=x.to_string())
  assert_eq(trouble_said(calls, "ws1\nseen"), Some(Json::string("MBA 连不上了")))
  // nothing to let it go with: looked at, it goes by itself
  t.move(x, y)
  t.frame()
  assert_true(t.find("忽略") is None)
  t.key(@ui.key_escape)
  t.frame()
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  assert_true(t.find("MBA 连不上了") is None, msg="looked at")
  assert_true(t.find("暂无待处理") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
}

///|
/// The latest `prefs.set` of the stations' trouble's `key`.
fn trouble_said(calls : Array[Made], key : String) -> Json? {
  let mut out : Json? = None
  for m in calls {
    if m.name == "prefs.set" {
      match field(field(Some(m.params), "trouble"), key) {
        Some(v) => out = Some(v)
        None => ()
      }
    }
  }
  out
}

///|
test "wide: 待处理's panel lists a chat that waits on the viewer; 忽略 on its row pointed at lets it go (decision.dismiss), gone from the panel at once; one gone wrong has none" {
  let calls : Array[Made] = []
  let marks : Json = {
    "badge": 1,
    "workspaces": {
      "ws1": {
        "items": [
          {
            "station": "ws1/st1",
            "session": "s-c1",
            "thread": 12,
            "seq": 5,
            "title": "整理发布清单",
            "kind": "wait",
            "text": "要你帮忙：选一个发布日期",
            "what": "选一个发布日期",
            "workspaceName": "Acme",
          },
          {
            "station": "ws1/st2",
            "session": "s-c3",
            "thread": 13,
            "seq": 7,
            "title": "夜里的构建又失败了",
            "kind": "alert",
            "text": "出问题：磁盘满了",
            "what": "磁盘满了",
            "workspaceName": "Acme",
          },
        ],
      },
    },
  }
  let t = wide_with(calls, { "workspaceMarks": marks })
  t.frame()
  let (bx, by, bw, bh) = t.query(Button, label="待处理").unwrap().rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.frame()
  // one gone wrong is not let go from here (Attention.tsx: 忽略 for what waits on the viewer)
  let (ax, ay) = t.find("磁盘满了").unwrap()
  t.move(ax, ay)
  t.frame()
  assert_true(t.find("忽略") is None)
  let (x, y) = t.find("选一个发布日期").unwrap()
  t.move(x, y)
  t.frame()
  let (dx, dy) = t.find("忽略").unwrap()
  t.tap(dx, dy)
  t.frame()
  let d = named(calls, "decision.dismiss")
  assert_eq(d.length(), 1)
  assert_eq(field(Some(d[0].params), "thread"), Some(Json::number(12.0)))
  assert_eq(field(Some(d[0].params), "seq"), Some(Json::number(5.0)))
  assert_true(t.find("选一个发布日期") is None)
}

///|
test "wide: the rail's menu beside the place right clicked, 8 past it; a place's ＋ there puts it in the rail (prefs.set rails) and the rail is changed from there" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.right_click(rx + rw / 2.0, ry + rh / 2.0)
  t.frame()
  let (mx, my) = t.find("我参与的").unwrap()
  assert_true(mx > rx + rw + 8.0, msg=mx.to_string())
  t.move(mx, my)
  t.frame()
  let (px, py, pw, ph) = t.query(Button, label="将我参与的添加到侧边条").unwrap().rect
  t.tap(px + pw / 2.0, py + ph / 2.0)
  t.frame()
  match field(field(Some(named(calls, "prefs.set").last().unwrap().params), "rails"), "ws1") {
    Some(Array(a)) => assert_true(a.contains(Json::string("mine")))
    _ => fail("not put in")
  }
  assert_true(@sfdesk.wide.editing)
}

///|
test "wide: 已归档 from the lists' filter: its place at the rail's foot while it is shown, lit; the filter in the accent's ground" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  assert_true(t.query(Button, label="已归档") is None)
  app.nav.push(Archived)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="已归档") is Some(_))
}

///|
test "wide: folding moves the block as the web's: the list where it was as the block's edges close round it; folded, the edge between the bar and the page; shown a while, at the sidebar's edge, the page moved aside" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (x0, y0, _, _) = t.rect_of("新建对话").unwrap()
  let (ex, _, _, _) = t.query(Button, label="调整侧边栏宽度 · 收起侧边栏").unwrap().rect
  // (its line in the middle of its strip)
  assert_eq(ex + @sfdesk.edge_half, @sfdesk.rail_w + @sfdesk.wide.side_w)
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  // halfway: the edge on its way with the block, the list not moved across, the block's edges round it (its top row's
  // 8 giving way to the bar's 6 above)
  t.run_for(@ui.move_most_ms / 2.0)
  let (hx, _, _, _) = t.query(Button, label="展开侧边栏").unwrap().rect
  assert_true(hx > @sfdesk.closed_edge && hx < ex, msg=hx.to_string())
  let (x1, y1, _, _) = t.rect_of("新建对话").unwrap()
  assert_eq(x1, x0)
  assert_true((y1 - y0).abs() <= 2.0, msg=y1.to_string())
  t.run_for(@ui.move_most_ms)
  let (fx, _, _, _) = t.query(Button, label="展开侧边栏").unwrap().rect
  assert_eq(fx, @sfdesk.closed_edge)
  // the pointer on the bar: shown a while, its edge at the sidebar's
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  let (px, _, _, _) = t.query(Button, label="展开侧边栏").unwrap().rect
  // (its line in the middle of its strip)
  assert_eq(px + @sfdesk.edge_half, @sfdesk.closed_edge + @sfdesk.wide.side_w + @sfdesk.edge_half)
  assert_true(@sfdesk.wide.bar_mr >= 0.0)
}

///|
test "wide: shown a while, the page moves aside as far as what it shows is from clearing the sidebar 16 past its edge, as Rail.tsx peekShift works it out from the page folded" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.move(1000.0, 400.0)
  t.run_for(@ui.move_most_ms)
  // folded: what the page shows across (its bar left out), and where its field is
  let (left, right) = t.ctx().shown_across(t.ctx().id("main-page"), but="page-bar").unwrap()
  let (x0, _, _, _) = t.rect_of("发消息").unwrap()
  // the pointer on the bar: shown a while, the page moved aside as far as that needs, no further than the room on its
  // right or the sidebar's width
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  let reach = @sfdesk.closed_bar_in + @sfdesk.rail_closed_w + @sfdesk.wide.side_w + @sfdesk.peek_gap
  let room = 1280.0 - 2.0 * @sfdesk.peek_gap - right
  let want = dmax(0.0, dmin(@sfdesk.wide.side_w, dmin(room, reach - left))).round()
  assert_true(want > 0.0, msg="\{left} \{right}")
  let (x1, _, _, _) = t.rect_of("发消息").unwrap()
  assert_eq(x1 - x0, want)
}

///|
/// Where a chat's bar has its title (x, y): the first words of it built, the page's (built before the sidebar's list).
fn bar_title_at(t : @ui.Tester) -> (Double, Double) raise {
  let (x, y, _, _) = t.rect_of("整理发布清单").unwrap()
  assert_true(y < @sf.wide_bar_h, msg="not the bar's: \{y}")
  (x, y)
}

///|
test "wide: the sidebar shown a while pinned open by its place pressed again, and folded back to shown a while: a chat's bar moves with its page, its title on its way from where it was to where it ends, never off it, as far from the sidebar's edge either way" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let press_lit = fn() {
    let (rx, ry, rw, rh) = t.query(Button, label="对话").unwrap().rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
  }
  // folded with the pointer on the rail: shown a while
  press_lit()
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded && @sfdesk.wide.peeking.get())
  let (shown_x, _) = bar_title_at(t)
  // pressed again: open; halfway there, the title between where it was and where it ends
  press_lit()
  t.run_for(@ui.move_most_ms / 2.0)
  let (mid_x, _) = bar_title_at(t)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.wide.folded)
  let (open_x, _) = bar_title_at(t)
  assert_true(
    mid_x >= dmin(shown_x, open_x) && mid_x <= dmax(shown_x, open_x),
    msg="shown \{shown_x}, halfway \{mid_x}, open \{open_x}",
  )
  // as far from the sidebar's edge either way (shown a while, the closed bar's 6 from the window's edge and 8 from the
  // page: its edge 8 short of the open one's)
  let s = @sfdesk.wide.side_w
  assert_eq(shown_x - (@sfdesk.closed_bar_in + @sfdesk.rail_closed_w + s), open_x - (@sfdesk.rail_w + s))
  // pressed once more: folded, shown a while again, the same way back
  press_lit()
  t.run_for(@ui.move_most_ms / 2.0)
  let (back_x, _) = bar_title_at(t)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded && @sfdesk.wide.peeking.get())
  let (again_x, _) = bar_title_at(t)
  assert_true(
    back_x >= dmin(open_x, again_x) && back_x <= dmax(open_x, again_x),
    msg="open \{open_x}, halfway \{back_x}, shown \{again_x}",
  )
}

///|
test "wide, the window's buttons in the app's top row: the sidebar shown a while is under their row, a chat's title stays beside them as folded; pinned open, it goes with the page past the sidebar, and back" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat", window_inset=true)
  let press_lit = fn() {
    let (rx, ry, rw, rh) = t.query(Button, label="对话").unwrap().rect
    t.tap(rx + rw / 2.0, ry + rh / 2.0)
  }
  // folded, the pointer off the rail: beside the window's buttons
  press_lit()
  t.move(1000.0, 400.0)
  t.run_for(@sfdesk.peek_leave_ms)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.folded && !@sfdesk.wide.peeking.get())
  let (folded_x, _) = bar_title_at(t)
  // the pointer on the rail: shown a while, the title where it was halfway and after
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms / 2.0)
  assert_true((bar_title_at(t).0 - folded_x).abs() < 0.01, msg="halfway at \{bar_title_at(t).0}, folded \{folded_x}")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.peeking.get())
  assert_true((bar_title_at(t).0 - folded_x).abs() < 0.01, msg="shown at \{bar_title_at(t).0}, folded \{folded_x}")
  // its place pressed: open, the title on its way past the sidebar with the page
  press_lit()
  t.run_for(@ui.move_most_ms / 2.0)
  let (mid_x, _) = bar_title_at(t)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.wide.folded)
  let (open_x, _) = bar_title_at(t)
  assert_true(open_x > @sfdesk.rail_w + @sfdesk.wide.side_w, msg="open at \{open_x}")
  assert_true(mid_x > folded_x && mid_x < open_x, msg="folded \{folded_x}, halfway \{mid_x}, open \{open_x}")
  // pressed again: shown a while, back beside the window's buttons
  press_lit()
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.peeking.get())
  assert_true((bar_title_at(t).0 - folded_x).abs() < 0.01, msg="back at \{bar_title_at(t).0}, folded \{folded_x}")
}

///|
test "wide: a newer build of the desktop app: 更新 the update key in the sidebar's first row before the filter, as large as it; folded, past the rail, the page bar's start clear of it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  update.available.set(Some({ "versionName": "0.1.9999" }))
  t.frame()
  t.frame()
  let (x, y, w, h) = t.query(Button, label="更新").unwrap().rect
  let (fx, fy, _, fh) = t.query(Button, label="筛选会话：全部").unwrap().rect
  assert_eq((y, h), (fy, fh))
  assert_true(x + w <= fx, msg="更新 to \{x + w}, the filter from \{fx}")
  // folded: 68 from the window's edge, the page bar's words clear of it (72 in)
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.move(1000.0, 400.0)
  t.run_for(@ui.move_most_ms)
  let (fx, _, _, _) = t.query(Button, label="更新").unwrap().rect
  assert_eq(fx, @sfdesk.update_closed_in)
  assert_eq(@sfdesk.wide.bar_pl, @sfdesk.bar_update_in)
  // shown a while: 更新 back in the sidebar's first row, the bar starting past the sidebar with its own 12
  let (rx, ry, rw, rh) = t.query(Button, label="文件").unwrap().rect
  t.move(rx + rw / 2.0, ry + rh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.peeking.get())
  assert_eq(@sfdesk.wide.bar_pl, @sfdesk.bar_in)
}

///|
test "wide: under a phone's status bar, 更新 below it (the bar takes what is pressed on it), in the sidebar's first row" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":32,\"bottom\":0,\"left\":0,\"right\":0}}")
  update.available.set(Some({ "versionName": "0.1.9999" }))
  t.frame()
  t.run_for(@ui.move_most_ms)
  let (_, y, _, h) = t.query(Button, label="更新").unwrap().rect
  assert_true(y >= 32.0, msg="\{y}")
  // in the sidebar's first row (新建对话's), on its line
  let (_, fy, _, fh) = t.query(Button, label="筛选会话：全部").unwrap().rect
  assert_eq((y, h), (fy, fh))
  // pressed, the newer build asked for (update_install: asked again first)
  update.source = Some({ check: fn(_, _, done) { done(Ok(Json::null())) }, url: fn(f) { f } })
  update_version.val = 1
  let (x, _, w, _) = t.query(Button, label="更新").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  assert_eq(update.available.get(), None)
}

///|
test "wide: the lists' filter (components.tsx MineFilter): its tip; its menu has the list shown checked, 已归档 its list, a filter back to the chats from it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let open_filter = fn() {
    let (fx, fy, fw, fh) = t.query(Button, label="筛选会话：全部").unwrap().rect
    t.tap(fx + fw / 2.0, fy + fh / 2.0)
    t.frame()
  }
  open_filter()
  assert_true(t.find("全部会话") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // 已归档: its list, the menu closed
  t.tap_text("已归档")
  t.frame()
  assert_eq(@sfdesk.side_place(), "archive")
  assert_false(@sf.presenting())
  // from 已归档, 我参与的: the chats, filtered (prefs.set listFilter)
  let (fx, fy, fw, fh) = t.query(Button, label="筛选会话：已归档").unwrap().rect
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.frame()
  t.tap_text("我参与的")
  t.frame()
  assert_eq(@sfdesk.lit_place(), "chats")
  assert_true(named(calls, "prefs.set").iter().any(fn(m) { field(field(Some(m.params), "listFilter"), "ws1") == Some(Json::string("mine")) }))
}

///|
test "wide: the lists slide in a window of their own (Sidebar.css.ts navSlider): the one left goes out at the sidebar's edge, never over the rail's places" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  let (fx, fy, fw, fh) = t.query(Button, label="筛选会话：全部").unwrap().rect
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.frame()
  t.tap_text("我参与的")
  // an eighth of the way: 全部's row (the first of the two lists drawn) moved left across the rail's places' edge,
  // nothing of it shown over them
  t.run_for(@ui.move_most_ms / 8.0)
  let row = "夜里的构建又失败了"
  let (rx, _, rw, _) = t.query(Button, label="文件").unwrap().rect
  let edge = rx + rw
  let (dx, _) = t.drawn_of(row).unwrap()
  let (_, _, w, _) = t.rect_of(row).unwrap()
  assert_true(dx < edge && dx + w > edge, msg="drawn \{dx} to \{dx + w}, the rail's places to \{edge}")
  let (sx, _, sw, _) = t.shown_of(row).unwrap()
  assert_true(sw == 0.0 || sx >= edge, msg="shown from \{sx}, \{sw} wide; the rail's places to \{edge}")
}

///|
test "wide: folded, the window made narrow enough for the tape: the sidebar on the tape at once, not moved for the window" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.key(@ui.key_of_char('\\'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("新建对话") is None, msg="folded")
  // the window's room changes nothing it was asked: the tape's sidebar where the tape has it from the first frame
  t.resize(@sf.large_from - 40.0, 800.0)
  t.draw()
  let at_once = t.rect_of("新建对话")
  assert_true(at_once is Some(_), msg="on the tape")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.rect_of("新建对话"), at_once)
}

///|
test "wide: Station's page picked in one workspace: in another, that one's first station shown, not the page before waiting; back, the one picked" {
  let calls : Array[Made] = []
  reset()
  let base = fixture("home")
  // (the second workspace's own station: the fixture's list is the first's)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let t = (base.topic)(name, params)
      match (name, params.get("scope")) {
        ("stations", Some(String("ws2"))) =>
          match ((base.topic)(name, { "scope": Json::string("ws1") }).value) {
            Some(Array(list)) =>
              match list[0] {
                Object(m) => {
                  let s = Map::from_iter(m.iter())
                  s["station"] = Json::string("ws2/st9")
                  s["id"] = Json::string("st9")
                  s["name"] = Json::string("家里的 mini")
                  topic_as_read(name, params, { ..t, value: Some(Json::array([Json::object(s)])) })
                }
                _ => t
              }
            _ => t
          }
        _ => t
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0)
  @sfbase.go_place("stations") |> ignore
  t.run_for(@ui.move_most_ms)
  t.tap_text("MBA")
  t.run_for(@ui.move_most_ms)
  @sfpages.switch_workspace(src, "ws2")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Place("stations"))
  // its row in the sidebar and its page beside it, its name over the page
  let named = t.words().filter(fn(w) { w.0 == "家里的 mini" }).length()
  assert_true(named >= 2, msg=t.words().map(fn(w) { w.0 }).join("|"))
  // back in the first: the one picked there still
  @sfpages.switch_workspace(src, "ws1")
  t.run_for(@ui.move_most_ms)
  let picked = t.words().filter(fn(w) { w.0 == "MBA" }).length()
  assert_true(picked >= 2, msg=t.words().map(fn(w) { w.0 }).join("|"))
}
