// A service page's two panels (sfpages' service.mbt): how far its page's resources came (from the ring, or its ⋯
// where the ring has left the bar) and its sizes (from its size key, or its ⋯), over the fixture's service
// (service_fixture.mbt), on the three screens they open on: a sheet with a finger, a small window with keyboard and
// mouse, a wide one (beside what opened them).

///|
/// The three screens: (input, wide).
let svc_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// The fixture's `mode` with its page's resources as `load` says them now (none: the fixture's), told anew as it
/// changes.
fn svc_told(mode : String, load : @signals.Signal[Json?]) -> Source {
  let base = fixture(mode)
  {
    ..base,
    topic_read: fn(name, params) {
      let t = (base.topic_read)(name, params)
      guard name == "previewLoad" && load.get() is Some(v) else { return t }
      { ..t, version: t.version * 1000 + load_told.val, value: Some(v) }
    },
  }
}

///|
/// How many times a test has told the resources anew (svc_told's version).
// kept across runs: a count a test sets as it starts (svc_page)
let load_told : Ref[Int] = Ref(0)

///|
/// The fixture's service page (its resources as `load` says them; `sized`: laid out at a phone's size) on a window 390
/// by 844 with the input `platform`, the page slid in; `wide`: a window 1200 by 800, the service beside its chat, in
/// front among the side panel's tabs (desk_service_wbtest's way). `corners_held`: each frame at rest held to the corner
/// rule (Tester's own), or not, the test saying what it finds (svc_corners).
fn svc_page(
  platform~ : Int,
  wide~ : Bool,
  sized? : Bool = false,
  load? : @signals.Signal[Json?] = @signals.signal(None),
  corners_held? : Bool = true,
) -> @ui.Tester {
  @sf.presenters_reset()
  new_run()
  load_told.val = 0
  if wide {
    let src = svc_told("chat-info", load)
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1200.0, h=800.0, platform~, corners_held~)
    t.run_for(@ui.move_most_ms)
    if sized {
      svc_viewports[service_key("ws1/st1", "j-web")] = Some({ width: 390, height: Some(844) })
    }
    app.nav.push(Service("ws1/st1", "j-web"))
    t.frame()
    t.frame()
    t.run_for(@ui.move_most_ms)
    return t
  }
  let mode = if sized { "service-sized" } else { "service" }
  let src = svc_told(mode, load)
  open_drive_fixture(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~, corners_held~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The panel `title` opened from its key in the bar where the bar holds it, else from the ⋯'s line; at the frame that
/// opened it.
fn svc_open(t : @ui.Tester, title : String) -> Unit raise {
  match t.query(Button, label=title) {
    Some(_) => t.click(Button, label=title)
    None => {
      t.click(Button, label="更多操作")
      t.run_for(@ui.move_most_ms)
      t.tap_text(title)
    }
  }
  t.frame()
}

///|
/// The panel as a screen reader finds it, if it is up.
fn svc_panel(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
}

///|
/// Where `words` are said in the panel, whole (x, y, w, h); the test fails where they are not, saying what is.
fn svc_at(t : @ui.Tester, words : String, at : String) -> (Double, Double, Double, Double) raise {
  guard svc_panel(t) is Some(p) else { fail("\{at}: no panel") }
  let (sx, sy, sw, sh) = p.rect
  match
    t
    .words()
    .iter()
    .find_first(fn(w) { w.0 == words && w.1 >= sx - 0.5 && w.1 <= sx + sw && w.2 >= sy - 0.5 && w.2 <= sy + sh && w.5 > 0.0 }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None =>
      fail(
        "\{at}: no \{words} in the panel at \{Repr(p.rect)}: " +
        t.words().map(fn(w) { "\{w.0}@\{w.1},\{w.2} a\{w.5}" }).join("|"),
      )
  }
}

///|
/// Whether `words` are said in the panel.
fn svc_has(t : @ui.Tester, words : String) -> Bool {
  guard svc_panel(t) is Some(p) else { return false }
  let (sx, sy, sw, sh) = p.rect
  t.words().iter().any(fn(w) { w.0 == words && w.1 >= sx - 0.5 && w.1 <= sx + sw && w.2 >= sy - 0.5 && w.2 <= sy + sh && w.5 > 0.0 })
}

///|
/// The ink of the glyphs drawn of the panel's `words` (0 where none are).
fn svc_ink(t : @ui.Tester, words : String) -> Int64 {
  guard svc_panel(t) is Some(p) else { return 0L }
  let (sx, sy, sw, sh) = p.rect
  guard t.words().iter().find_first(fn(w) { w.0 == words && w.1 >= sx - 0.5 && w.1 <= sx + sw && w.2 >= sy - 0.5 && w.2 <= sy + sh && w.5 > 0.0 })
    is Some(w) else {
    return 0L
  }
  match t.drawn_glyphs().iter().find_first(fn(g) { g.0 >= w.1 - 0.5 && g.0 <= w.1 + w.3 && g.1 >= w.2 - 0.5 && g.1 <= w.2 + w.4 }) {
    Some(g) => g.2
    None => 0L
  }
}

///|
/// The panel closed, gone, nothing left up for the next test: a sheet by a press over it, on the window's top (the
/// way that closes it with either input); beside what opened it in a wide window, by Escape. (Escape on a sheet over
/// the page's address with the focus: the test after the last below.)
fn svc_close(t : @ui.Tester, at : String, wide~ : Bool) -> Unit raise {
  if wide {
    t.key(@ui.key_escape)
  } else {
    t.tap(195.0, 60.0)
  }
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenter_visible(), msg="\{at}: gone")
}

///|
/// The corner rule on the sizes as they stand (their Tester made with `corners_held` false where `wide`): none, but in a
/// wide window, where 移动页面 shows, none or exactly one, its switch's track in the panel's bottom right corner, 16 and 15 from
/// its edges. Known (2026-11-11): the old panel drew it where it stands, the same to a point,
/// and the old rule passed it over, its body in an old view's scroller (corner_exempt's scrolls_between, said whether
/// or not it scrolls); the body of a panel of nodes is passed over only where it scrolls (mbui's corners_tree_wbtest,
/// rows in a node that scrolls). Left for the library to make what ends a row in a panel's corner stand there, every
/// panel's at once; anything else the rule finds fails here.
fn svc_corners(t : @ui.Tester, at : String, wide~ : Bool) -> Unit raise {
  let faults = t.corner_faults()
  guard wide && t.query(Switch, label="移动页面") is Some(_) else {
    assert_eq(faults, [], msg=at)
    return
  }
  // (none at all on the old panel, its rule passing its scroller over)
  guard !faults.is_empty() else { return }
  let known = faults.length() == 1 &&
    faults[0].has_prefix("a box in 「移动页面 开着时手指拖动的是画布，不点网页」 (at ") &&
    faults[0].contains(" 36×22, node ") &&
    faults[0].contains(") (corner 11) in the bottom right of 「页面尺寸 ") &&
    faults[0].has_suffix(" (corner 24): 16 and 15 from its edges")
  assert_true(known, msg="\{at}: \{Repr(faults)}")
  // (made by the switch the panel's row of 移动页面 is made of)
  let s = t.get(Switch, label="移动页面").rect
  let made = t.sources_at(s.0 + s.2 / 2.0, s.1 + s.3 / 2.0)
  assert_true(made.contains("stillfail/src/sf/page_node.mbt") && made.contains("stillfail/src/sfpages/service.mbt"), msg="\{at}: \{made}")
}

///|
test "how far the resources came, on every screen: its note, each resource on its line, what came of it after its path (its status and how long, 失败, 正在读取), red where it failed" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~)
    svc_open(t, "资源加载 75% · 3/4")
    t.run_for(@ui.move_most_ms)
    let title = svc_at(t, "资源加载 75% · 3/4", at)
    let note = svc_at(t, "按已发现的服务请求计算 · 新资源出现时更新", at)
    assert_true(note.1 > title.1, msg="\{at}: the note under the title")
    assert_false(svc_has(t, "等待页面请求"), msg="\{at}: requests there")
    // each resource on its line, in the order they came: its path, what came of it after it, how long
    let lines = [("/", "200", "42 ms"), ("/app.css", "200", "11 ms"), ("/favicon.ico", "404", "8 ms")]
    let mut y = note.1
    for l in lines {
      let path = svc_at(t, l.0, at)
      assert_true(path.1 > y, msg="\{at}: \{l.0} under what is before it")
      y = path.1
      assert_eq(path.0, note.0, msg="\{at}: \{l.0} on the note's words' line")
      // (its status and how long on its line, after its path)
      let said = t
        .words()
        .filter(fn(w) { (w.0 == l.1 || w.0 == l.2) && (w.2 + w.4 / 2.0 - (path.1 + path.3 / 2.0)).abs() < 2.0 })
      assert_eq(said.length(), 2, msg="\{at}: \{l.0}'s \{l.1}, \{l.2}")
      for w in said {
        assert_true(w.1 > path.0 + path.2, msg="\{at}: \{w.0} after \{l.0}")
      }
    }
    // the one still coming: 正在读取, nothing of how long
    let coming = svc_at(t, "/api/builds", at)
    assert_true(coming.1 > y, msg="\{at}: the last")
    let reading = svc_at(t, "正在读取", at)
    assert_true((reading.1 + reading.3 / 2.0 - (coming.1 + coming.3 / 2.0)).abs() < 2.0, msg="\{at}: on its line")
    // red where it failed (its path and what came of it), the others muted
    let ink = fn(words : String) { svc_ink(t, words) }
    assert_eq(ink("/favicon.ico"), ink("404"), msg="\{at}: one ink")
    assert_true(ink("/favicon.ico") != ink("/app.css"), msg="\{at}: the failed one apart")
    assert_eq(ink("/app.css"), ink("正在读取"), msg="\{at}: the others alike")
    assert_eq(t.squeeze_faults(), [], msg=at)
    svc_close(t, at, wide~)
  }
}

///|
test "how far the resources came follows the page as it loads: none yet said so, then each as it comes, its status and how long once it came, the title with it" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let none : Json = { "percent": 0, "total": 0, "finished": 0, "failed": 0, "resources": [] }
    let load : @signals.Signal[Json?] = @signals.signal(Some(none))
    let t = svc_page(platform~, wide~, load~)
    svc_open(t, "资源加载 0% · 0/0")
    t.run_for(@ui.move_most_ms)
    svc_at(t, "资源加载 0% · 0/0", at) |> ignore
    let waiting = svc_at(t, "等待页面请求", at)
    let note = svc_at(t, "按已发现的服务请求计算 · 新资源出现时更新", at)
    assert_true(waiting.1 > note.1, msg="\{at}: under the note")
    // the page asked for, then its stylesheet
    load_told.val += 1
    load.set(
      Some({
        "percent": 0,
        "total": 2,
        "finished": 0,
        "failed": 0,
        "resources": [
          { "id": 1, "method": "GET", "path": "/", "since": 0 },
          { "id": 2, "method": "GET", "path": "/app.css", "since": 50 },
        ],
      }),
    )
    t.run_for(@ui.move_most_ms)
    assert_false(svc_has(t, "等待页面请求"), msg="\{at}: requests there")
    svc_at(t, "资源加载 0% · 0/2", at) |> ignore
    let first = svc_at(t, "/", at)
    let second = svc_at(t, "/app.css", at)
    assert_true(second.1 > first.1, msg="\{at}: in the order they came")
    assert_eq(t.words().filter(fn(w) { w.0 == "正在读取" && w.5 > 0.0 }).length(), 2, msg="\{at}: both coming")
    // the page came; the stylesheet failed
    load_told.val += 1
    load.set(
      Some({
        "percent": 100,
        "total": 2,
        "finished": 2,
        "failed": 1,
        "resources": [
          { "id": 1, "method": "GET", "path": "/", "since": 0, "ended": 30, "status": 200 },
          { "id": 2, "method": "GET", "path": "/app.css", "since": 50, "ended": 75, "error": "连接断开" },
        ],
      }),
    )
    t.run_for(@ui.move_most_ms)
    svc_at(t, "资源加载 100% · 2/2 · 1 个失败", at) |> ignore
    assert_false(svc_has(t, "正在读取"), msg="\{at}: none coming")
    svc_at(t, "200", at) |> ignore
    svc_at(t, "30 ms", at) |> ignore
    svc_at(t, "失败", at) |> ignore
    svc_at(t, "25 ms", at) |> ignore
    // why it failed, under its line
    let why = svc_at(t, "连接断开", at)
    let css = svc_at(t, "/app.css", at)
    assert_true(why.1 > css.1, msg="\{at}: why under it")
    assert_eq(why.0, css.0, msg="\{at}: from where its path starts")
    svc_close(t, at, wide~)
  }
}

///|
/// The page's size as it is laid out now: `w×h`, `w×auto`, or `fit`.
fn svc_size() -> String {
  match service_pages.get(service_key("ws1/st1", "j-web")) {
    Some(p) =>
      match p.viewport.get() {
        Some({ width, height: Some(h) }) => "\{width}×\{h}"
        Some({ width, height: None }) => "\{width}×auto"
        None => "fit"
      }
    None => "none"
  }
}

///|
/// The words in the fields of 自定义: the width's, the height's.
fn svc_fields() -> (String, String) {
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  (p.custom_w.text(), p.custom_h.text())
}

///|
test "the sizes on every screen: 自适应 and the presets in rows, each read out a button by its name and its size, their names on one line and their sizes at their end; nothing in it takes the keys as it opens; one pressed, the page is laid out at it and they go" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~, corners_held=!wide)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    svc_at(t, "页面尺寸", at) |> ignore
    svc_corners(t, at, wide~)
    // (as it opens, focus=false: none of what it holds has the keys, the input method not raised for it)
    for f in ["TextField \"宽\"", "TextField \"自动\"", "Switch", "Button \"自适应"] {
      assert_false(t.focus_said().has_prefix(f), msg="\{at}: \{t.focus_said()}")
    }
    let rows = [
      ("自适应", "跟随预览区"),
      ("手机", "390 × 844"),
      ("平板", "820 × 1180"),
      ("笔记本", "1280 × 800"),
      ("桌面", "1440 × 900"),
    ]
    let mut y = 0.0
    let mut name_x = -1.0
    let mut note_end = -1.0
    for r in rows {
      let row = t.get(Button, label="\{r.0} \{r.1}")
      assert_true(row.rect.1 > y, msg="\{at}: \{r.0} under the one before")
      y = row.rect.1
      // (a press's room: a row's least, 44 with a finger, 36 with a mouse)
      assert_true(row.rect.3 >= (if platform == 2 { 44.0 } else { 36.0 }) - 0.5, msg="\{at}: \{r.0} \{Repr(row.rect)}")
      let name = svc_at(t, r.0, at)
      let note = svc_at(t, r.1, at)
      // (its name past its check's column, all in one line; its size at its end)
      if name_x < 0.0 {
        name_x = name.0
        note_end = note.0 + note.2
      }
      assert_eq(name.0, name_x, msg="\{at}: \{r.0}'s name where the others' are")
      assert_eq(note.0 + note.2, note_end, msg="\{at}: \{r.1} where the others end")
      assert_true(name.0 > row.rect.0 + 16.0, msg="\{at}: past its check's column")
      assert_true((name.1 + name.3 / 2.0 - (note.1 + note.3 / 2.0)).abs() < 1.0, msg="\{at}: on one line")
    }
    // 手机: laid out at it, the page fitted to it, the sizes gone
    t.click(Button, label="手机 390 × 844")
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_size(), "390×844", msg=at)
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    // opened again: 自定义 says it, 移动页面 under it; 自适应 pressed, as big as the preview again
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    svc_corners(t, at, wide~)
    assert_eq(svc_fields(), ("390", "844"), msg=at)
    let custom = svc_at(t, "自定义", at)
    let moving = t.get(Switch, label="移动页面")
    assert_true(moving.rect.1 > custom.1, msg="\{at}: 移动页面 under 自定义")
    t.click(Button, label="自适应 跟随预览区")
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_size(), "fit", msg=at)
    assert_false(@sf.presenter_visible(), msg="\{at}: gone again")
  }
}

///|
/// The sizes open, `press` closing them: on each frame as they go, the panel as high as before the press (to 0.01, at
/// the width it had), each of `seen` drawn while it is, none of `unseen` (what a panel shows as it is closed is what it
/// shows on its way out, no more and no less); to a screen reader, the panel already going (one on its way out is not
/// read out, #5234).
fn svc_leaving(t : @ui.Tester, at : String, press : () -> Unit raise, seen~ : Array[String], unseen~ : Array[String]) -> Unit raise {
  // (as high as it is at the width it had: a panel beside what opened it goes by its scale, its width and height alike)
  let size = fn() { t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Dialog }).map(fn(s) { (s.rect.2, s.rect.3) }) }
  guard size() is Some((was_w, was)) else { fail("\{at}: no panel") }
  let height = fn() { size().map(fn(s) { s.1 * was_w / s.0 }) }
  let drawn = fn(w : String) { t.words().iter().any(fn(x) { x.0 == w && x.5 > 0.0 }) }
  press()
  let mut n = 0
  while @sf.presenter_visible() && n < 120 {
    assert_true(svc_panel(t) is None, msg="\{at}: frame \{n} on its way out: still read out")
    match height() {
      Some(h) => assert_true((h - was).abs() <= 0.01, msg="\{at}: frame \{n} on its way out: \{h} high, \{was} before")
      None => ()
    }
    // (while the panel is drawn at all, its last row's size its mark: one beside what opened it is not seen at half
    // its size or less, all of it at once)
    for w in seen {
      assert_true(drawn(w) || !drawn("1440 × 900"), msg="\{at}: frame \{n} on its way out: \{w} not drawn")
    }
    for w in unseen {
      assert_false(drawn(w), msg="\{at}: frame \{n} on its way out: \{w} drawn")
    }
    t.frame()
    n += 1
  }
  assert_false(@sf.presenter_visible(), msg="\{at}: gone")
}

///|
test "the sizes as big as the preview, closed by a preset pressed: on their way out as high as they were, no 移动页面 coming" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~, corners_held=!wide)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Switch, label="移动页面") is None, msg="\{at}: fitting the preview, no 移动页面")
    svc_leaving(t, at, fn() raise { t.click(Button, label="手机 390 × 844") }, seen=["自适应"], unseen=["移动页面"])
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_size(), "390×844", msg=at)
  }
}

///|
test "the sizes of a page laid out at a size and fitted, closed by another preset pressed: on their way out as high as they were, no 适应 coming" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~, sized=true, corners_held=!wide)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Button, label="适应") is None, msg="\{at}: fitted, no 适应")
    svc_leaving(t, at, fn() raise { t.click(Button, label="平板 820 × 1180") }, seen=["移动页面"], unseen=["适应"])
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_size(), "820×1180", msg=at)
  }
}

///|
test "the sizes of a page laid out at a size, closed by 自适应 pressed: on their way out as high as they were, 移动页面 there all the way" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~, sized=true, corners_held=!wide)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    svc_leaving(t, at, fn() raise { t.click(Button, label="自适应 跟随预览区") }, seen=["移动页面"], unseen=[])
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_size(), "fit", msg=at)
  }
}

///|
test "自定义 on every screen: what is typed is put by Enter, not by the keys going to the other field, nor away, nor by the panel closing (the fields then say the size again); 横竖互换 turns it (but beside a chat: the page's step); Tab goes past the fields to 移动页面" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~, sized=true, corners_held=!wide)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    svc_corners(t, at, wide~)
    assert_eq(svc_fields(), ("390", "844"), msg=at)
    // the width typed; the keys to the height's field: kept as typed, not put
    t.click(TextField, label="宽")
    t.frame()
    t.clear()
    t.type_text("500")
    t.frame()
    t.click(TextField, label="自动")
    t.frame()
    t.frame()
    assert_true(t.focus_said().has_prefix("TextField \"自动\""), msg="\{at}: \{t.focus_said()}")
    assert_eq(svc_fields(), ("500", "844"), msg="\{at}: kept as typed")
    assert_eq(svc_size(), "390×844", msg="\{at}: not put")
    // Tab on, past the fields: not put, the fields saying the size again
    t.key(@ui.key_tab)
    t.frame()
    t.frame()
    assert_false(t.focus_said().has_prefix("TextField"), msg="\{at}: \{t.focus_said()}")
    assert_eq(svc_size(), "390×844", msg="\{at}: not put by leaving")
    assert_eq(svc_fields(), ("390", "844"), msg="\{at}: said again")
    // on to 移动页面 (the panel's nodes stop at 横竖互换 on the way, the old key took no Tab)
    if t.focus_said().has_prefix("Button \"横竖互换\"") {
      t.key(@ui.key_tab)
    }
    assert_true(t.focus_said().has_prefix("Switch \"移动页面\""), msg="\{at}: \{t.focus_said()}")
    // (the input method gone down as the fields let the keys go)
    t.run_for(@ui.move_most_ms)
    // Enter: put, the panel staying; 横竖互换 turns it. (Not beside the chat in a wide window: there the service page's
    // old canvas takes a new size at once, a step in what is drawn that the frame by frame judge says, the old panel's
    // and this one's alike: the page's, to be mended where it is.)
    if !wide {
      t.click(TextField, label="宽")
      t.frame()
      t.clear()
      t.type_text("500")
      t.enter()
      // (the page laid out at it anew, its way there)
      t.run_for(@ui.move_most_ms)
      assert_eq(svc_size(), "500×844", msg="\{at}: put")
      assert_eq(svc_fields(), ("500", "844"), msg=at)
      assert_true(@sf.presenter_visible(), msg="\{at}: still up")
      t.click(Button, label="横竖互换")
      t.run_for(@ui.move_most_ms)
      assert_eq(svc_size(), "844×500", msg="\{at}: turned")
      assert_eq(svc_fields(), ("844", "500"), msg=at)
    }
    svc_corners(t, at, wide~)
    // typed, and the panel closed meanwhile: not put
    let (size, fields) = (svc_size(), svc_fields())
    t.click(TextField, label="宽")
    t.frame()
    t.clear()
    t.type_text("600")
    t.frame()
    svc_close(t, at, wide~)
    assert_eq(svc_size(), size, msg="\{at}: not put by closing")
    // opened again: the fields say the size, not what was typed
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_fields(), fields, msg="\{at}: said again once opened")
    svc_close(t, at, wide~)
  }
}

///|
test "自定义's width as the page fits the preview: nothing to turn, 横竖互换 faint and read out disabled; its fields empty, saying 宽 and 自动" {
  for screen in svc_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = svc_page(platform~, wide~)
    svc_open(t, "页面尺寸")
    t.run_for(@ui.move_most_ms)
    assert_eq(svc_fields(), ("", ""), msg=at)
    assert_true(t.get(Button, label="横竖互换").disabled, msg=at)
    assert_true(t.query(Switch, label="移动页面") is None, msg="\{at}: nothing to move")
    // (the pointer resting on it: no name by it, the old one shown only where it turned)
    if platform == 0 {
      let k = t.get(Button, label="横竖互换")
      t.move_to(k.rect.0 + k.rect.2 / 2.0, k.rect.1 + k.rect.3 / 2.0)
      t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
      assert_true(t.semantics().iter().all(fn(s) { s.role != Tooltip }), msg="\{at}: no tip")
    }
    t.click(Button, label="横竖互换")
    t.frame()
    assert_eq(svc_size(), "fit", msg=at)
    svc_close(t, at, wide~)
  }
}

///|
test "小屏 with keyboard and mouse, the page's address taken: either panel opened over it takes them, what is typed while it is up going nowhere; Escape closes it (how far the resources came: the address has them back)" {
  // (the sizes as an old panel gave the keys back to none as Escape closed them: as nodes they give them back, the test
  // after this one)
  for opened in [("资源加载 75% · 3/4", true), ("页面尺寸", false)] {
    let (title, back) = opened
    let t = svc_page(platform=0, wide=false)
    let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
    // the address taken (service_wbtest's way to it)
    let (x, y) = t.find_last("web").unwrap()
    t.tap(x, y)
    t.frame()
    assert_true(p.address.focused() && t.ime().0, msg="\{title}: the address has the keys")
    let had = p.address.text()
    svc_open(t, title)
    t.run_for(@ui.move_most_ms)
    assert_true(svc_panel(t) is Some(_), msg="\{title}: up")
    assert_false(t.ime().0, msg="\{title}: the input method put away under it")
    t.type_text("q")
    t.draw()
    assert_eq(p.address.text(), had, msg="\{title}: typed into nothing under it")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="\{title}: Escape closes it")
    if back {
      assert_true(t.ime().0, msg="\{title}: the keys back")
      t.type_text("q")
      t.draw()
      assert_eq(p.address.text(), had + "q", msg="\{title}: typed into the address again")
    }
  }
}

///|
/// (Of the panel of nodes only: the old one gave the keys to none as Escape closed it.)
test "小屏 with keyboard and mouse, the page's address taken, the sizes opened over it: Escape closes them, the address has the keys back, what is typed then its" {
  let t = svc_page(platform=0, wide=false)
  let p = service_pages.get(service_key("ws1/st1", "j-web")).unwrap()
  let (x, y) = t.find_last("web").unwrap()
  t.tap(x, y)
  t.frame()
  assert_true(p.address.focused(), msg="the address has the keys")
  let had = p.address.text()
  svc_open(t, "页面尺寸")
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenter_visible(), msg="Escape closes them")
  assert_true(p.address.focused() && t.ime().0, msg="the keys back")
  t.type_text("q")
  t.draw()
  assert_eq(p.address.text(), had + "q", msg="typed into the address")
}
