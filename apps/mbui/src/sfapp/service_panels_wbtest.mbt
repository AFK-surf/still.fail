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
/// front among the side panel's tabs (desk_service_wbtest's way).
fn svc_page(
  platform~ : Int,
  wide~ : Bool,
  sized? : Bool = false,
  load? : @signals.Signal[Json?] = @signals.signal(None),
) -> @ui.Tester {
  @sf.presenters_reset()
  new_run()
  load_told.val = 0
  if wide {
    let src = svc_told("chat-info", load)
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1200.0, h=800.0, platform~)
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
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
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
        "\{at}: no \{words} in the panel at \{p.rect}: " +
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
/// way that closes it with either input); beside what opened it in a wide window, by Escape. (Escape is not said of
/// the sheet: with keyboard and mouse the service page's old field keeps the focus under it, and the window's tree
/// asks only what holds that field for a key it does not take, so a sheet of nodes is not told it; the old sheet's
/// layer took it. The framework's to mend, 2026-11-10.)
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
