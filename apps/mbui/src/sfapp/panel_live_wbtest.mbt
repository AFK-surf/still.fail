// A panel of the presenters' whose title, step and what it says are as they are now (@sf.panel `live`): what it shows
// and is read out as, its head there or not as its title is, what it holds where it was; in the middle of the window,
// a share of it tall, and beside what opened it. The old contract, measured on main first.

///|
/// Where a live panel's parts are: its dialog and what it is read out as, its title, its step and what it says as
/// drawn, its close buttons, the first words it holds.
fn live_said(t : @ui.Tester) -> String {
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let dialog = t.query(Dialog).map(fn(s) { (s.label, tenth4(s.rect)) })
  let closes = t.all(Button, label="关闭").map(fn(s) { tenth4(s.rect) })
  "dialog \{@ui.some_text(dialog.map(fn(d) { "(\{d.0}, \{@ui.rect_text(d.1)})" }))} title \{@ui.list_text(w("任务").map(@ui.rect_text))} step \{@ui.list_text(w("第 1 步").map(@ui.rect_text))} says \{@ui.list_text(w("说的话").map(@ui.rect_text))} close \{@ui.list_text(closes.map(@ui.rect_text))} words \{@ui.list_text(w("面板里的话，长一些，好看它怎么折行").map(@ui.rect_text))}"
}

///|
test "panel live, 大屏 keyboard and mouse: in the middle, a share of the window tall, beside what opened it; its title, step and what it says from none to some and back (frames as the display draws them), drawn by the window's tree in the middle: as main has it" {
  let out = []
  let drawn = []
  for kind in ["middle", "tall", "beside"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let (title, step, says) = (@signals.signal(""), @signals.signal(""), @signals.signal(""))
    let live = fn() { (title.get(), step.get(), says.get()) }
    match kind {
      "middle" => @sf.panel("", panel_test_body([]), from=Unanchored, live~)
      "tall" => @sf.panel("", panel_test_body([]), from=Unanchored, tall=0.8, grows=true, live~)
      _ => @sf.panel("", panel_test_body([]), from=At(600.0, 100.0, 0.0, 0.0), live~)
    }
    t.run_for(@ui.move_most_ms)
    // (in the middle also a step alone and what it says alone: untitled only with neither title nor step; what it
    // says shown alone)
    let states = if kind == "middle" {
      [("", "", ""), ("任务", "", ""), ("任务", "第 1 步", "说的话"), ("", "第 1 步", ""), ("", "", "说的话"), ("", "", "")]
    } else {
      [("", "", ""), ("任务", "", ""), ("任务", "第 1 步", "说的话"), ("", "", "")]
    }
    for s in states {
      title.set(s.0)
      step.set(s.1)
      says.set(s.2)
      // (frames as the display draws them: nothing said changed but what it reads)
      live_frames(t, 30)
      out.push("\{kind} (\{s.0}, \{s.1}, \{s.2}): \{live_said(t)}")
      // (drawn by the window's tree: in the middle titled as it is now; beside what opened it, as it was presented,
      // read out by its title and what it holds as the host had it)
      drawn.push(tree_said(Dialog, if kind == "beside" { "" } else { s.0 }) is Some(_))
    }
  }
  // (as main has it)
  assert_eq(out, [
    "middle (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的 关闭, (380, 323, 520, 154))) title [] step [] says [] close [(842, 349, 32, 32)] words [(414, 381, 452, 22)]",
    "middle (任务, , ): dialog Some((任务, (380, 314.5, 520, 171))) title [(404, 340.5, 44, 30)] step [] says [] close [(842, 340.5, 32, 32)] words [(414, 389.5, 452, 22)]",
    "middle (任务, 第 1 步, 说的话): dialog Some((任务, (380, 301.5, 520, 197))) title [(404, 327.5, 44, 30)] step [(456, 337.5, 42, 20)] says [(404, 364.5, 472, 20)] close [(842, 327.5, 32, 32)] words [(414, 402.5, 452, 22)]",
    "middle (, 第 1 步, ): dialog Some((第 1 步 关闭 面板里的话，长一些，好看它怎么折行 好的, (380, 314.5, 520, 171))) title [] step [(412, 350.5, 42, 20)] says [] close [(842, 340.5, 32, 32)] words [(414, 389.5, 452, 22)]",
    "middle (, , 说的话): dialog Some((说的话 面板里的话，长一些，好看它怎么折行 好的 关闭, (380, 310, 520, 180))) title [] step [] says [(404, 340, 472, 20)] close [(842, 336, 32, 32)] words [(414, 394, 452, 22)]",
    "middle (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的 关闭, (380, 323, 520, 154))) title [] step [] says [] close [(842, 349, 32, 32)] words [(414, 381, 452, 22)]",
    "tall (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的 关闭, (380, 87, 520, 626))) title [] step [] says [] close [(842, 113, 32, 32)] words [(414, 145, 452, 22)]",
    "tall (任务, , ): dialog Some((任务, (380, 78.5, 520, 643))) title [(404, 104.5, 44, 30)] step [] says [] close [(842, 104.5, 32, 32)] words [(414, 153.5, 452, 22)]",
    "tall (任务, 第 1 步, 说的话): dialog Some((任务, (380, 65.5, 520, 669))) title [(404, 91.5, 44, 30)] step [(456, 101.5, 42, 20)] says [(404, 128.5, 472, 20)] close [(842, 91.5, 32, 32)] words [(414, 166.5, 452, 22)]",
    "tall (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的 关闭, (380, 87, 520, 626))) title [] step [] says [] close [(842, 113, 32, 32)] words [(414, 145, 452, 22)]",
    "beside (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 68))) title [] step [] says [] close [] words [(616, 112, 264, 22)]",
    "beside (任务, , ): dialog Some((任务 面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 98))) title [(616, 118, 264, 20)] step [] says [] close [] words [(616, 142, 264, 22)]",
    "beside (任务, 第 1 步, 说的话): dialog Some((任务 面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 98))) title [(616, 118, 264, 20)] step [] says [] close [] words [(616, 142, 264, 22)]",
    "beside (, , ): dialog Some((面板里的话，长一些，好看它怎么折行 好的, (600, 106, 296, 68))) title [] step [] says [] close [] words [(616, 112, 264, 22)]",
  ])
  assert_eq(drawn, [
    true, true, true, true, true, true, true, true, true, true, true, true, true, true,
  ])
}

///|
/// Frames as the display draws them, `n` of them, nothing said changed (no step of the test's: what is kept kept).
fn live_frames(t : @ui.Tester, n : Int) -> Unit {
  for _ in 0..<n {
    t.frame_at(t.next_frame_time())
  }
}

///|
/// The rows of a scrolled panel's body seen whole: each of their glyphs drawn (alpha) within the straight edges it is
/// cut to (its clip and its outer one), as panel_reach_said reads them: the first and the last.
fn rows_seen(t : @ui.Tester) -> (String?, String?) {
  let drawn = t.drawn_instances()
  let seen = t.words().filter(fn(x) {
    x.0.has_prefix("第") && {
      let glyphs = drawn.filter(fn(d) {
        d[5] == 1.0 && d[11] > 0.0 && d[0] >= x.1 - 0.01 && d[0] < x.1 + x.3 && d[1] >= x.2 - 0.01 && d[1] < x.2 + x.4
      })
      glyphs.length() > 0 &&
      glyphs.iter().all(fn(d) {
        let outer = d[44] > 0.0 || d[45] > 0.0 || d[46] > 0.0 || d[47] > 0.0
        let (y0, y1) = (dmax(d[17], if outer { d[41] } else { d[1] }), dmin(d[19], if outer { d[43] } else { d[1] + d[3] }))
        d[1] >= y0 - 0.01 && d[1] + d[3] <= y1 + 0.01
      })
    }
  })
  (seen.get(0).map(fn(x) { x.0 }), seen.last().map(fn(x) { x.0 }))
}

///|
test "panel live in the middle, 大屏 keyboard and mouse, in a short window: its title shown and gone again (frames as the display draws them after): its dialog and field the same nodes, what was typed kept, the rows seen" {
  let t = menu_tester(1280.0, 500.0, 0)
  let title = @signals.signal("")
  let pf = @ui.Field::new()
  @sf.panel(
    "",
    fn(c, close) {
      c.editor("live field", field=pf, placeholder="填一下") |> ignore
      for i in 0..<30 {
        @sf.panel_text(c, fn() { c.text("第\{i}行", style=@sf.paragraph) |> ignore })
      }
      panel_test_body([])(c, close)
    },
    from=Unanchored,
    field="live field",
    live=fn() { (title.get(), "", "") },
  )
  t.run_for(@ui.move_most_ms)
  t.type_text("甲")
  t.run_for(@ui.move_most_ms)
  // (who they are, before it is scrolled: then found by those among all it reads out, hidden or not)
  let dialog = t.get(Dialog).id
  let field = t.get(TextField, label="填一下").id
  let d = t.get(Dialog).rect
  t.wheel(d.0 + d.2 / 2.0, d.1 + d.3 / 2.0, 200.0)
  t.run_for(@ui.move_most_ms)
  let said = fn() {
    let ids = t.semantics().map(fn(s) { s.id })
    (ids.contains(dialog), ids.contains(field), t.query(Dialog).map(fn(s) { s.label }), pf.text(), rows_seen(t))
  }
  let before = said()
  title.set("任务")
  live_frames(t, 30)
  let titled = said()
  title.set("")
  live_frames(t, 30)
  let again = said()
  // (the same dialog and field, 甲 kept; untitled, what it holds starts under its close button, where a titled one's
  // starts under its head (#3806): row 2 the first seen, as titled; its body the shorter while its head is there, back
  // as it goes)
  let body_said = "填一下 第0行 第1行 第2行 第3行 第4行 第5行 第6行 第7行 第8行 第9行 第10行 第11行 第12行 第13行 第14行 第15行 第16行 第17行 第18行 第19行 第20行 第21行 第22行 第23行 第24行 第25行 第26行 第27行 第28行 第29行 面板里的话，长一些，好看它怎么折行 好的 关闭"
  assert_eq([before, titled, again], [
    (true, true, Some(body_said), "甲", (Some("第2行"), Some("第13行"))),
    (true, true, Some("任务"), "甲", (Some("第2行"), Some("第13行"))),
    (true, true, Some(body_said), "甲", (Some("第2行"), Some("第13行"))),
  ])
}

///|
test "names already where files go, two asked in turn, 大屏 keyboard and mouse: the first skipped, the dialog asks about the second in the frame after (frames as the display draws them): its title and what it holds the second's; the second skipped, what goes goes once and the dialog closes" {
  let win = ("wide", 1280.0, 800.0, 0, "")
  let t = screen_in("files-list", win, "zh")
  let done = Ref(0)
  let entry = fn(name : String) { dv_entry(@sffixture.fix_entry(name, false, 320, "10/01")) }
  @sfdesk.drag_ask({
    into: { station: "ws1/st1", root: Some(@sffixture.fix_docs), path: "会议记录" },
    into_name: "会议记录",
    total: 2,
    clashes: [
      { name: "甲.txt", dir: false, size: 2048.0, station: "Maple", there: entry("甲.txt") },
      { name: "乙.txt", dir: false, size: 1024.0, station: "Maple", there: entry("乙.txt") },
    ],
    answers: {},
    all: false,
    done: fn(_) { done.val = done.val + 1 },
  })
  t.run_for(@ui.move_most_ms)
  // (its title, and all its words: its title's, its body's (what comes: its size, where from) and its buttons')
  let said = fn() {
    match t.query(Dialog) {
      Some(s) => {
        let (x, y, w, h) = s.rect
        let inside = t.words().filter(fn(v) { v.1 >= x && v.1 < x + w && v.2 >= y && v.2 < y + h }).map(fn(v) { v.0 })
        "\{s.label} | \{@ui.list_text(inside)}"
      }
      None => "none"
    }
  }
  let first = said()
  t.click(Button, label="跳过")
  live_frames(t, 1)
  let next = said()
  t.click(Button, label="跳过")
  live_frames(t, 1)
  let answered = (done.val, @sf.presenting())
  live_frames(t, 30)
  let after = (done.val, @sf.presenting(), said())
  // (as main has it: the second asked about in the frame after the first is answered, its own size said; the last
  // answered, what goes goes once and the dialog closes in the frame after)
  let facts = fn(s : String, title : String, size : String) { s.has_prefix(title + " |") && s.contains(size + " · Maple") }
  assert_eq(
    (
      facts(first, "「会议记录」里已有「甲.txt」", "2 KB"),
      facts(next, "「会议记录」里已有「乙.txt」", "1 KB"),
      next.contains("2 KB"),
      answered,
      after,
    ),
    (true, true, false, (1, false), (1, false, "none")),
  )
}
