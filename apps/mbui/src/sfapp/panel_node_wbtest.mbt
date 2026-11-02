// A panel of the presenters' (@sf.panel) on 中屏 and 大屏: the old contract, measured on main first (PANELSAID), what
// it does held whatever draws it.

///|
/// A panel's body: words, and a button at its foot that closes it, said into `said`.
fn panel_test_body(said : Array[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    @sf.panel_text(c, fn() { c.text("面板里的话，长一些，好看它怎么折行", style=@sf.paragraph) |> ignore })
    @sf.panel_foot(c, fn() {
      if @sf.panel_button(c, "ok", "好的", tone=Filled) {
        said.push("ok")
        close()
      }
    })
  }
}

///|
test "a panel's words, controls and surface fade out together" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", from=At(600.0, 300.0, 0.0, 0.0), fade_out_together=true, fn(c, _) {
    c.box(w=Px(12.0), h=Px(12.0), bg=0x23A1DFFFL, fn() {  }) |> ignore
    c.text("一起退场", color=0xB45A29FFL) |> ignore
  })
  t.run_for(@ui.move_most_ms)
  let original = t.drawn_rects().filter(fn(r) { r.0 == 600.0 && r.1 == 306.0 && r.2 > 200.0 })[0]
  t.key(@ui.key_escape)
  let mut previous = 255L
  for _ in 0..<5 {
    t.run_for(@kit.pop_out_ms / 6.0)
    let surface = t.drawn_rects().filter(fn(r) {
      r.4 >> 8 == original.4 >> 8 &&
      (r.0 - original.0).abs() < 10.0 && (r.1 - original.1).abs() < 10.0 &&
      r.2 > original.2 * 0.96 && r.3 > original.3 * 0.96
    })
    let mark = t.drawn_rects().filter(fn(r) { r.4 >> 8 == 0x23A1DFL })
    let glyphs = t.drawn_glyphs().filter(fn(g) { g.2 >> 8 == 0xB45A29L })
    assert_eq(surface.length(), 1, msg="the surface remains during its fade")
    assert_eq(mark.length(), 1, msg="the control remains during its fade")
    assert_true(!glyphs.is_empty(), msg="the words remain during their fade")
    let alpha = surface[0].4 & 0xFFL
    assert_true(alpha > 0L && alpha < previous, msg="the panel fades continuously")
    assert_eq(mark[0].4 & 0xFFL, alpha, msg="the control and surface fade together")
    assert_true(glyphs.iter().all(fn(g) { (g.2 & 0xFFL) == alpha }), msg="the words and surface fade together")
    previous = alpha
  }
  t.run_for(@kit.pop_out_ms)
  assert_false(@sf.presenter_visible())
}

///|
test "a panel closed while opening fades from its current appearance" {
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", from=At(600.0, 300.0, 0.0, 0.0), fade_out_together=true, fn(c, _) {
    c.box(w=Px(12.0), h=Px(12.0), bg=0x23A1DFFFL, fn() {  }) |> ignore
    c.text("一起退场", color=0xB45A29FFL) |> ignore
  })
  t.run_for(@kit.pop_ms / 2.0)
  let painted = fn() {
    (t.drawn_rects().filter(fn(r) { r.4 >> 8 == 0x23A1DFL }), t.drawn_glyphs().filter(fn(g) { g.2 >> 8 == 0xB45A29L }))
  }
  let before = painted()
  assert_true(!before.0.is_empty() && !before.1.is_empty())
  t.key(@ui.key_escape)
  assert_eq(painted(), before, msg="closing does not change the current appearance")
  t.run_for(@kit.pop_out_ms)
  assert_false(@sf.presenter_visible())
}

///|
/// Where what the panel shows is: its dialog, its title, its words, its button.
fn panel_said(t : @ui.Tester) -> String {
  let r = fn(role : @ui.Role, label : String) { t.query(role, label~).map(fn(s) { s.rect }) }
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { (x.1, x.2, x.3, x.4) }) }
  "dialog \{r(Dialog, "面板")} title \{w("面板")} words \{w("面板里的话，长一些，好看它怎么折行")} button \{r(Button, "好的")} focus \{t.focused().map(fn(s) { "\{s.role} \{s.label}" })}"
}

///|
test "panel, 大屏 keyboard and mouse: at a point, its title, words and button; the button: said, closed; another, Escape: closed unsaid, its gone told" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0))
  t.run_for(@ui.move_most_ms)
  println("PANELSAID point \{panel_said(t)}")
  let (x, y, w, h) = t.get(Button, label="好的").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  let pressed = (said.copy(), @sf.presenting())
  let gone = Ref(0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0), gone=fn() { gone.val = gone.val + 1 })
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_eq((pressed, said, @sf.presenting(), gone.val), ((["ok"], false), ["ok"], false, 1))
}

///|
test "panel, 大屏 keyboard and mouse: at a point, a press outside: closed, its gone told" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  let gone = Ref(0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0), gone=fn() { gone.val = gone.val + 1 })
  t.run_for(@ui.move_most_ms)
  t.tap(100.0, 700.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((said, @sf.presenting(), gone.val), ([], false, 1))
}

///|
test "panel, 大屏 keyboard and mouse: tall 0.5, fits, at a point; and unanchored, in the middle (measured)" {
  let said : Array[String] = []
  let out = []
  for kind in ["tall", "fits", "middle", "form"] {
    let t = menu_tester(1280.0, 800.0, 0)
    match kind {
      "tall" => @sf.panel("面板", panel_test_body(said), from=At(600.0, 100.0, 0.0, 0.0), tall=0.5)
      "fits" => @sf.panel("面板", panel_test_body(said), from=At(600.0, 100.0, 0.0, 0.0), fits=true, w=400.0)
      "middle" => @sf.panel("面板", panel_test_body(said), from=Unanchored, description="说明的话")
      _ => @sf.panel("面板", panel_test_body(said), from=At(600.0, 100.0, 0.0, 0.0), form=true)
    }
    t.run_for(@ui.move_most_ms)
    out.push("\{kind}: \{panel_said(t)}")
  }
  println("PANELSAID kinds \{out}")
}

///|
/// The panel's state at a moment of its way out: presenting, visible, its dialog where it is said, its words as drawn
/// (alpha), how many times its gone was told, what was said.
fn panel_out_said(t : @ui.Tester, gone : Ref[Int], said : Array[String]) -> String {
  let words = t.words().filter(fn(w) { w.0 == "好的" }).map(fn(w) { w.5 })
  "presenting \{@sf.presenting()} visible \{@sf.presenter_visible()} dialog \{t.query(Dialog, label="面板").map(fn(s) { s.rect })} button \{words} gone \{gone.val} said \{said}"
}

///|
test "panel, 大屏 keyboard and mouse: its way out, closed by Escape, by a press outside, by its button: at once, midway, at its end (measured)" {
  let out = []
  for how in ["escape", "outside", "button"] {
    let said : Array[String] = []
    let gone = Ref(0)
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0), gone=fn() { gone.val = gone.val + 1 })
    t.run_for(@ui.move_most_ms)
    let (bx, by, bw, bh) = t.get(Button, label="好的").rect
    match how {
      "escape" => t.key(@ui.key_escape)
      "outside" => t.tap(100.0, 700.0)
      _ => t.tap(bx + bw / 2.0, by + bh / 2.0)
    }
    let at_once = panel_out_said(t, gone, said)
    t.run_for(@kit.pop_out_ms / 2.0)
    let mid = panel_out_said(t, gone, said)
    // (pressed midway where its button was: what that does)
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    let mid_pressed = panel_out_said(t, gone, said)
    t.run_for(@kit.pop_out_ms)
    let end = panel_out_said(t, gone, said)
    out.push("\{how}: once {\{at_once}} mid {\{mid}} pressed {\{mid_pressed}} end {\{end}}")
  }
  println("PANELSAID out \{out}")
}

///|
/// `r` to a tenth.
fn tenth4(r : (Double, Double, Double, Double)) -> (Double, Double, Double, Double) {
  let f = fn(v : Double) { (v * 10.0).round() / 10.0 }
  (f(r.0), f(r.1), f(r.2), f(r.3))
}

///|
test "panel, 大屏 keyboard and mouse: at a point, where main has it: its dialog, title, words and button" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0))
  t.run_for(@ui.move_most_ms)
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  assert_eq(
    (tenth4(t.get(Dialog, label="面板").rect), w("面板"), w("面板里的话，长一些，好看它怎么折行"), tenth4(t.get(Button, label="好的").rect), t.focused().map(fn(s) { s.label })),
    ((600.0, 306.0, 280.0, 95.8), [(616.0, 318.0, 248.0, 20.0)], [(616.0, 342.0, 248.0, 22.0)], (826.2, 368.0, 44.0, 24.0), None),
  )
}

///|
test "panel, 大屏 keyboard and mouse: at a point, its way out as main has it: closed, presenting no more and out of what is read out at once, drawn till its way out is over, pressed no more; gone told once by Escape, never by its own close" {
  let out = []
  for how in ["escape", "outside", "button"] {
    let said : Array[String] = []
    let gone = Ref(0)
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0), gone=fn() { gone.val = gone.val + 1 })
    t.run_for(@ui.move_most_ms)
    let (bx, by, bw, bh) = t.get(Button, label="好的").rect
    match how {
      "escape" => t.key(@ui.key_escape)
      "outside" => t.tap(100.0, 700.0)
      _ => t.tap(bx + bw / 2.0, by + bh / 2.0)
    }
    // (its button's words as they are drawn: there, and how opaque)
    let drawn = fn() { t.words().filter(fn(w) { w.0 == "好的" }).length() }
    let once = (@sf.presenting(), @sf.presenter_visible(), t.query(Dialog, label="面板") is Some(_), gone.val, said.copy(), drawn())
    t.run_for(@kit.pop_out_ms / 2.0)
    let mid = (@sf.presenting(), @sf.presenter_visible(), gone.val, drawn())
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    let pressed = (said.copy(), gone.val)
    t.run_for(@kit.pop_out_ms)
    out.push((once, mid, pressed, (@sf.presenter_visible(), gone.val, drawn())))
  }
  assert_eq(out, [
    ((false, true, false, 1, [], 1), (false, true, 1, 1), ([], 1), (false, 1, 0)),
    ((false, true, false, 1, [], 1), (false, true, 1, 1), ([], 1), (false, 1, 0)),
    ((false, true, false, 0, ["ok"], 1), (false, true, 0, 1), (["ok"], 0), (false, 0, 0)),
  ])
}

///|
test "panel, 大屏 keyboard and mouse: at a point, drawn by the window's tree, a dialog titled so" {
  let said : Array[String] = []
  let _t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0))
  _t.run_for(@ui.move_most_ms)
  assert_true(tree_said(Dialog, "面板") is Some(_))
}

///|
/// What is drawn of the panel open at (600, 306), 280 by 95.8, as it is now: how many of its glyphs are drawn at each
/// final alpha (0-255; the window's under it there at 255 too), its ground's alpha, its button's ground (to a
/// thousandth), the first and last of its glyphs fading (to a thousandth).
fn panel_out_drawn(t : @ui.Tester) -> String {
  let (x, y, w, h) = (600.0, 306.0, 280.0, 95.8)
  let inside = fn(px : Double, py : Double) { px >= x - 1.0 && px <= x + w + 1.0 && py >= y - 1.0 && py <= y + h + 1.0 }
  let f = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let glyphs = t.drawn_glyphs().filter(fn(g) { inside(g.0, g.1) })
  let alphas : Map[Int, Int] = {}
  for g in glyphs {
    let a = (g.2 & 0xFF).to_int()
    alphas[a] = alphas.get(a).unwrap_or(0) + 1
  }
  let fading = glyphs.filter(fn(g) { (g.2 & 0xFF) != 0xFF }).map(fn(g) { (f(g.0), f(g.1)) })
  let rects = t.drawn_rects().filter(fn(q) { inside(q.0, q.1) })
  let ground = rects.filter(fn(q) { q.0 == x && q.1 == y && (q.4 & 0xFF) != 0 }).map(fn(q) { (q.4 & 0xFF).to_int() })
  let button = rects.filter(fn(q) { q.0 > 800.0 && q.2 > 40.0 && q.2 < 50.0 }).map(fn(q) { (f(q.0), f(q.1), f(q.2), f(q.3)) })
  "alphas \{alphas} ground \{ground} button \{button} fading \{fading.get(0)}..\{fading.last()}"
}

///|
test "panel, 大屏 keyboard and mouse: at a point, its way out drawn as main has it, closed by Escape, by a press outside, by its button: its words fading before its ground, shrunk into where it opened from, at once, a quarter, midway, three quarters and at its end" {
  let out = []
  for how in ["escape", "outside", "button"] {
    let said : Array[String] = []
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0))
    t.run_for(@ui.move_most_ms)
    let (bx, by, bw, bh) = t.get(Button, label="好的").rect
    match how {
      "escape" => t.key(@ui.key_escape)
      "outside" => t.tap(100.0, 700.0)
      _ => t.tap(bx + bw / 2.0, by + bh / 2.0)
    }
    let seen = [panel_out_drawn(t)]
    for _ in 0..<4 {
      t.run_for(@kit.pop_out_ms / 4.0)
      seen.push(panel_out_drawn(t))
    }
    out.push(seen)
  }
  // (as main has it, a4c845604: each way the same)
  let main = [
    "alphas {255: 45} ground [255] button [(826.192, 368, 44, 24)] fading None..None",
    "alphas {255: 24, 205: 21} ground [255] button [(825.523, 367.817, 43.87, 23.929)] fading Some((615.953, 320.956))..Some((847.266, 373.799))",
    "alphas {255: 24, 89: 21} ground [255] button [(823.988, 367.396, 43.571, 23.766)] fading Some((615.844, 320.854))..Some((845.583, 373.337))",
    "alphas {255: 24, 0: 21} ground [189] button [(821.916, 366.828, 43.168, 23.546)] fading Some((615.698, 320.716))..Some((843.312, 372.715))",
    "alphas {255: 24} ground [] button [] fading None..None",
  ]
  assert_eq(out, [main, main, main])
}

///|
/// Where the keyboard's focus is and what the host is told of it: what has the focus (its role and label), the field
/// the host is told of (active, its text, its selection).
fn panel_focus_said(t : @ui.Tester) -> String {
  "focused \{t.focused().map(fn(s) { "\{s.role} \{s.label}" })} ime \{t.ime()}"
}

///|
test "panel, 大屏 keyboard and mouse: at a point, the focus as it opens (focus, not focus, its field given it), typed into, closed by Escape, typed into again: as main has it" {
  let out = []
  for how in ["focus", "not focus", "field"] {
    let said : Array[String] = []
    let t = menu_tester(1280.0, 800.0, 0)
    let before = panel_focus_said(t)
    let pf = @ui.Field::new()
    let body = fn(c : @ui.Ctx, close : () -> Unit) {
      if how == "field" {
        c.editor("panel field", field=pf, placeholder="填一下") |> ignore
      }
      panel_test_body(said)(c, close)
    }
    match how {
      "not focus" => @sf.panel("面板", body, from=At(600.0, 300.0, 0.0, 0.0), focus=false)
      "field" => @sf.panel("面板", body, from=At(600.0, 300.0, 0.0, 0.0), field="panel field")
      _ => @sf.panel("面板", body, from=At(600.0, 300.0, 0.0, 0.0))
    }
    t.run_for(@ui.move_most_ms)
    let open = panel_focus_said(t)
    t.type_text("甲")
    t.run_for(@ui.move_most_ms)
    let typed = "\{panel_focus_said(t)} panel field \{pf.text()}"
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    let closed = panel_focus_said(t)
    t.type_text("乙")
    t.run_for(@ui.move_most_ms)
    let typed_after = "\{panel_focus_said(t)} panel field \{pf.text()} presenting \{@sf.presenting()}"
    out.push("\{how}: before {\{before}} open {\{open}} typed {\{typed}} closed {\{closed}} typed after {\{typed_after}}")
  }
  for o in out {
    println("PANELFOCUS \{o}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "focus: before {focused Some(TextField 发消息) ime (true, , 0, 0)} open {focused None ime (false, , 0, 0)} typed {focused None ime (false, , 0, 0) panel field } closed {focused Some(TextField 发消息) ime (true, , 0, 0)} typed after {focused Some(TextField 发消息) ime (true, 乙, 1, 1) panel field  presenting false}",
    "not focus: before {focused Some(TextField 发消息) ime (true, , 0, 0)} open {focused Some(TextField 发消息) ime (true, , 0, 0)} typed {focused Some(TextField 发消息) ime (true, 甲, 1, 1) panel field } closed {focused Some(TextField 发消息) ime (true, 甲, 1, 1)} typed after {focused Some(TextField 发消息) ime (true, 甲乙, 2, 2) panel field  presenting false}",
    "field: before {focused Some(TextField 发消息) ime (true, , 0, 0)} open {focused Some(TextField 填一下) ime (true, , 0, 0)} typed {focused Some(TextField 填一下) ime (true, 甲, 1, 1) panel field 甲} closed {focused Some(TextField 发消息) ime (true, , 0, 0)} typed after {focused Some(TextField 发消息) ime (true, 乙, 1, 1) panel field 甲 presenting false}",
  ])
}

///|
test "panel, 大屏 keyboard and mouse: at a point, its way in and its way out after Escape painted alone: what it holds not built again, its words fading in and out as they do, gone at its end" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  let built = Ref(0)
  let body = fn(c : @ui.Ctx, close : () -> Unit) {
    built.val = built.val + 1
    panel_test_body(said)(c, close)
  }
  // (its words' alpha as drawn: the panel's own glyphs (where it is open, but those of the window's under it there,
  // drawn whole), how many of them and theirs (-1: none fading, -2: not all as faded))
  let words = fn() {
    let (x, y, w, h) = (600.0, 306.0, 280.0, 95.8)
    let mine = t
      .drawn_glyphs()
      .filter(fn(g) { g.0 >= x - 1.0 && g.0 <= x + w + 1.0 && g.1 >= y - 1.0 && g.1 <= y + h + 1.0 })
    (mine.length(), mine.filter(fn(g) { (g.2 & 0xFF) != 0xFF }).map(fn(g) { (g.2 & 0xFF).to_int() }).fold(init=-1, fn(a, b) { if a < 0 || a == b { b } else { -2 } }))
  }
  // (the frames a host draws till `until`, each at the moment the app asks for it, however late (none once it asks for
  // none): what each was built for, its words as drawn and when)
  let frames_till = fn(until : Double) {
    let out = []
    while true {
      let w = t.wanted_after()
      if w == @double.infinity {
        break
      }
      let at = if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) }
      if at > until {
        break
      }
      t.frame_at(at)
      out.push((t.time(), t.built_why() != "", words()))
    }
    out
  }
  // (each frame built as a host builds it: none of the looks alone drawn whole after it as well, Tester::check_looks;
  // this test's alone)
  t.check_looks(false)
  let open_at = t.time()
  @sf.panel("面板", body, from=At(600.0, 300.0, 0.0, 0.0))
  // (the frame it opens in, and those after it of its own: then its way in, the clock alone, past its end)
  t.frames_owed()
  let opened = built.val
  let way_in = frames_till(open_at + @kit.pop_ms + 2.0 * t.frame_period())
  let after_in = built.val
  let close_at = t.time()
  t.key(@ui.key_escape)
  t.frames_owed()
  let closed = built.val
  let way_out = frames_till(close_at + @kit.pop_out_ms + 2.0 * t.frame_period())
  println("PANELBUILT in \{way_in} out \{way_out}")
  let alphas = fn(frames : Array[(Double, Bool, (Int, Int))]) { frames.map(fn(f) { f.2 }) }
  // (its way in: some frame of it drawn part way, its words whole by its end)
  let part_in = alphas(way_in).iter().any(fn(w) { w.0 == 45 && w.1 > 0 && w.1 < 255 })
  let whole_in = way_in.last().map(fn(f) { f.2 }) == Some((45, -1))
  // (its way out: its words no more opaque frame by frame, some frame part way, then gone, from the first frame at or
  // after its end, and gone thereafter)
  let out_a = alphas(way_out)
  let part_out = out_a.iter().any(fn(w) { w.0 == 45 && w.1 > 0 && w.1 < 255 })
  let fading = out_a.filter(fn(w) { w.0 == 45 }).map(fn(w) { if w.1 < 0 { 255 } else { w.1 } })
  let mut falls = true
  for i in 1..<fading.length() {
    falls = falls && fading[i] <= fading[i - 1]
  }
  let gone_from = out_a.search((24, -1)).unwrap_or(out_a.length())
  let gone_at = way_out.get(gone_from).map(fn(f) { f.0 - close_at })
  let gone_stays = out_a.iter().drop(gone_from).all(fn(w) { w == (24, -1) })
  let in_time = match gone_at {
    Some(ms) => ms >= @kit.pop_out_ms && ms < @kit.pop_out_ms + 2.0 * t.frame_period()
    None => false
  }
  // (what is built meanwhile, the page under it as what it reads says (its own motions), built none of it)
  assert_eq(
    (after_in - opened, built.val - closed, part_in, whole_in, part_out, falls, gone_stays, in_time),
    (0, 0, true, true, true, true, true, true),
    msg="in \{way_in}; out \{way_out}",
  )
}

///|
test "panel, 大屏 keyboard and mouse: at a point, back (the system's): closed as by Escape, gone told once, out of what is read out at once, the focus back as it goes: as main has it" {
  let out = []
  for focus in [true, false] {
    let said : Array[String] = []
    let gone = Ref(0)
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.panel("面板", panel_test_body(said), from=At(600.0, 300.0, 0.0, 0.0), focus~, gone=fn() { gone.val = gone.val + 1 })
    t.run_for(@ui.move_most_ms)
    t.back()
    let once = "\{panel_out_said(t, gone, said)} \{panel_focus_said(t)}"
    t.run_for(@ui.move_most_ms)
    out.push("focus \{focus}: once {\{once}} end {\{panel_out_said(t, gone, said)} \{panel_focus_said(t)}}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "focus true: once {presenting false visible true dialog None button [1] gone 1 said [] focused Some(TextField 按空格输入) ime (true, , 0, 0)} end {presenting false visible false dialog None button [] gone 1 said [] focused Some(TextField 发消息) ime (true, , 0, 0)}",
    "focus false: once {presenting false visible true dialog None button [1] gone 1 said [] focused Some(TextField 发消息) ime (true, , 0, 0)} end {presenting false visible false dialog None button [] gone 1 said [] focused Some(TextField 发消息) ime (true, , 0, 0)}",
  ])
}

///|
/// A panel's body of `n` rows of words, a button at its foot; what it was told of being held short (panel_held) as it
/// was drawn, into `held`.
fn panel_rows_body(n : Int, held : Array[Bool]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, close) {
    held.push(@sf.panel_held())
    for i in 0..<n {
      @sf.panel_text(c, fn() { c.text("第\{i}行", style=@sf.paragraph) |> ignore })
    }
    @sf.panel_foot(c, fn() {
      if @sf.panel_button(c, "ok", "好的", tone=Filled) {
        close()
      }
    })
  }
}

///|
test "panel, 大屏 keyboard and mouse: at a point, held short of what it holds by the window: what scrolls (out to its sides), where, how far, told held: as main has it" {
  let held : Array[Bool] = []
  let t = menu_tester(1280.0, 500.0, 0)
  @sf.panel("面板", panel_rows_body(40, held), from=At(600.0, 100.0, 0.0, 0.0))
  t.run_for(@ui.move_most_ms)
  let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let at = fn() { "title \{w("面板")} row0 \{w("第0行")} row10 \{w("第10行")} button \{t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) })}" }
  let (dx, dy, dw, dh) = t.get(Dialog, label="面板").rect
  let first = "dialog \{tenth4((dx, dy, dw, dh))} \{at()} held \{held.last()}"
  // (the wheel over its middle, then over its padding at its left side, then at its foot under its words)
  t.wheel(dx + dw / 2.0, dy + dh / 2.0, 120.0)
  t.run_for(@ui.move_most_ms)
  let middle = at()
  t.wheel(dx + 4.0, dy + dh / 2.0, 120.0)
  t.run_for(@ui.move_most_ms)
  let side = at()
  t.wheel(dx + dw / 2.0, dy + 6.0, 120.0)
  t.run_for(@ui.move_most_ms)
  let top = at()
  let said = "\{first} || wheel middle \{middle} || wheel side \{side} || wheel top padding \{top} || held \{held.last()}"
  println("PANELHELD \{said}")
  // (as main has it, a4c845604)
  assert_eq(
    said,
    "dialog (600, 8, 280, 484) title [(616, 20, 248, 20)] row0 [(616, 44, 248, 22)] row10 [(616, 264, 248, 22)] button Some((826.2, 928, 44, 24)) held Some(true) || wheel middle title [(616, 20, 248, 20)] row0 [(616, -76, 248, 22)] row10 [(616, 144, 248, 22)] button Some((826.2, 808, 44, 24)) || wheel side title [(616, 20, 248, 20)] row0 [(616, -196, 248, 22)] row10 [(616, 24, 248, 22)] button Some((826.2, 688, 44, 24)) || wheel top padding title [(616, 20, 248, 20)] row0 [(616, -196, 248, 22)] row10 [(616, 24, 248, 22)] button Some((826.2, 688, 44, 24)) || held Some(true)",
  )
}

///|
/// A panel's body: a column of its own (panel_column, 360 at most) of `rows()` rows of words; what it was told of being
/// held short as it was drawn, into `held`.
fn panel_column_body(rows : @signals.Signal[Int], held : Array[Bool]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _close) {
    held.push(@sf.panel_held())
    @sf.panel_column(c, "test/column", 360.0, @ui.css("w=Full"), fn() {
      for i in 0..<rows.get() {
        @sf.panel_text(c, fn() { c.text("第\{i}行", style=@sf.paragraph) |> ignore })
      }
    })
  }
}

///|
test "panel, 大屏 keyboard and mouse: at a point, a column of its own in it: in a tall window, in a short one then grown, its rows from many to few: where it is, what the wheel scrolls, told held: as main has it" {
  let w = fn(t : @ui.Tester, s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  // (where it is, then the wheel over its middle and where its rows are after)
  let said = fn(t : @ui.Tester, held : Array[Bool]) {
    let d = t.query(Dialog, label="面板").unwrap().rect
    let before = "dialog \{tenth4(d)} row0 \{w(t, "第0行")} row4 \{w(t, "第4行")} held \{held.last()}"
    t.wheel(d.0 + d.2 / 2.0, d.1 + d.3 / 2.0, 120.0)
    t.run_for(@ui.move_most_ms)
    let after = "row0 \{w(t, "第0行")} row4 \{w(t, "第4行")} held \{held.last()}"
    // (and back where it was)
    t.wheel(d.0 + d.2 / 2.0, d.1 + d.3 / 2.0, -240.0)
    t.run_for(@ui.move_most_ms)
    "\{before} | wheel: \{after}"
  }
  let out = []
  // (a tall window, 30 rows)
  let held : Array[Bool] = []
  let rows = @signals.signal(30)
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", panel_column_body(rows, held), from=At(600.0, 100.0, 0.0, 0.0))
  t.run_for(@ui.move_most_ms)
  out.push("tall: \{said(t, held)}")
  // (its rows from 30 to 4)
  rows.set(4)
  t.run_for(@ui.move_most_ms)
  out.push("tall, 4 rows: \{said(t, held)}")
  // (a short window, 30 rows; then grown)
  let held2 : Array[Bool] = []
  let rows2 = @signals.signal(30)
  let t2 = menu_tester(1280.0, 300.0, 0)
  @sf.panel("面板", panel_column_body(rows2, held2), from=At(600.0, 100.0, 0.0, 0.0))
  t2.run_for(@ui.move_most_ms)
  out.push("short: \{said(t2, held2)}")
  t2.resize(1280.0, 800.0)
  t2.run_for(@ui.move_most_ms)
  out.push("short, grown: \{said(t2, held2)}")
  rows2.set(4)
  t2.run_for(@ui.move_most_ms)
  out.push("short, grown, 4 rows: \{said(t2, held2)}")
  for o in out {
    println("PANELCOLUMN \{o}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "tall: dialog (600, 106, 280, 402) row0 [(616, 142, 248, 22)] row4 [(616, 230, 248, 22)] held Some(false) | wheel: row0 [(616, 22, 248, 22)] row4 [(616, 110, 248, 22)] held Some(false)",
    "tall, 4 rows: dialog (600, 106, 280, 130) row0 [(616, 142, 248, 22)] row4 [] held Some(false) | wheel: row0 [(616, 142, 248, 22)] row4 [] held Some(false)",
    "short: dialog (600, 8, 280, 284) row0 [(616, 44, 248, 22)] row4 [(616, 132, 248, 22)] held Some(true) | wheel: row0 [(616, -76, 248, 22)] row4 [(616, 12, 248, 22)] held Some(true)",
    "short, grown: dialog (600, 106, 280, 402) row0 [(616, 142, 248, 22)] row4 [(616, 230, 248, 22)] held Some(false) | wheel: row0 [(616, 22, 248, 22)] row4 [(616, 110, 248, 22)] held Some(false)",
    "short, grown, 4 rows: dialog (600, 106, 280, 130) row0 [(616, 142, 248, 22)] row4 [] held Some(false) | wheel: row0 [(616, 142, 248, 22)] row4 [] held Some(false)",
  ])
}

///|
test "panel, 大屏 keyboard and mouse: tall 0.5, at a point high and low in the window, its body a column that fills it and its rows: where it is, how tall, what the wheel scrolls: as main has it" {
  let out = []
  for at in [100.0, 500.0, 700.0] {
    let held : Array[Bool] = []
    let rows = @signals.signal(40)
    let t = menu_tester(1280.0, 800.0, 0)
    @sf.panel("面板", panel_column_body(rows, held), from=At(600.0, at, 0.0, 0.0), tall=0.5)
    t.run_for(@ui.move_most_ms)
    let w = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
    let d = t.query(Dialog, label="面板").map(fn(s) { tenth4(s.rect) })
    let before = "dialog \{d} row0 \{w("第0行")} held \{held.last()}"
    match d {
      Some((x, y, dw, dh)) => t.wheel(x + dw / 2.0, y + dh / 2.0, 120.0)
      None => ()
    }
    t.run_for(@ui.move_most_ms)
    out.push("at \{at}: \{before} | wheel: row0 \{w("第0行")}")
  }
  for o in out {
    println("PANELTALL \{o}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "at 100: dialog Some((600, 106, 280, 400)) row0 [(616, 142, 248, 22)] held Some(false) | wheel: row0 [(616, 22, 248, 22)]",
    "at 500: dialog Some((600, 94, 280, 400)) row0 [(616, 130, 248, 22)] held Some(false) | wheel: row0 [(616, 10, 248, 22)]",
    "at 700: dialog Some((600, 294, 280, 400)) row0 [(616, 330, 248, 22)] held Some(false) | wheel: row0 [(616, 210, 248, 22)]",
  ])
}

///|
test "panel, 大屏 keyboard and mouse: tall 0.5, at a point: its title, words and button where main has them, drawn by the window's tree" {
  let said : Array[String] = []
  let t = menu_tester(1280.0, 800.0, 0)
  @sf.panel("面板", panel_test_body(said), from=At(600.0, 100.0, 0.0, 0.0), tall=0.5)
  t.run_for(@ui.move_most_ms)
  // (as main has it, a4c845604: PANELSAID kinds' tall)
  assert_eq(
    (panel_said(t), tree_said(Dialog, "面板") is Some(_)),
    ("dialog Some((600, 106, 280, 400)) title [(616, 118, 248, 20)] words [(616, 142, 248, 22)] button Some((826.1918000000001, 168, 44, 24)) focus None", true),
  )
}

///|
test "panel, 大屏 keyboard and mouse: tall 0.5 with a foot of its own, its body a column: opened, the window made shorter and taller again, and opened at that height: where its body and foot are, what the wheel scrolls: as main has it" {
  let w = fn(t : @ui.Tester, s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { tenth4((x.1, x.2, x.3, x.4)) }) }
  let said = fn(t : @ui.Tester, held : Array[Bool]) {
    let d = t.query(Dialog, label="面板").unwrap().rect
    let foot = t.query(Button, label="好的").map(fn(s) { tenth4(s.rect) })
    let before = "dialog \{tenth4(d)} row0 \{w(t, "第0行")} foot \{foot} held \{held.last()}"
    // (the wheel over the middle of what it holds)
    t.wheel(d.0 + d.2 / 2.0, d.1 + 120.0, 120.0)
    t.run_for(@ui.move_most_ms)
    let after = "row0 \{w(t, "第0行")}"
    t.wheel(d.0 + d.2 / 2.0, d.1 + 120.0, -240.0)
    t.run_for(@ui.move_most_ms)
    "\{before} | wheel: \{after}"
  }
  let open = fn(held : Array[Bool]) {
    let rows = @signals.signal(40)
    @sf.panel(
      "面板",
      panel_column_body(rows, held),
      from=At(600.0, 100.0, 0.0, 0.0),
      tall=0.5,
      foot=fn(c, close) {
        if @sf.button(c, "好的", key="ok34", tone=Primary) {
          close()
        }
      },
    )
  }
  let out = []
  let held : Array[Bool] = []
  let t = menu_tester(1280.0, 800.0, 0)
  open(held)
  t.run_for(@ui.move_most_ms)
  out.push("800: \{said(t, held)}")
  t.resize(1280.0, 500.0)
  t.run_for(@ui.move_most_ms)
  out.push("800 to 500: \{said(t, held)}")
  t.resize(1280.0, 800.0)
  t.run_for(@ui.move_most_ms)
  out.push("500 to 800: \{said(t, held)}")
  let held2 : Array[Bool] = []
  let t2 = menu_tester(1280.0, 500.0, 0)
  open(held2)
  t2.run_for(@ui.move_most_ms)
  out.push("opened at 500: \{said(t2, held2)}")
  for o in out {
    println("PANELTALLFOOT \{o}")
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    "800: dialog (600, 106, 280, 400) row0 [(616, 142, 248, 22)] foot Some((817.2, 467.2, 58, 34)) held Some(false) | wheel: row0 [(616, 22, 248, 22)]",
    "800 to 500: dialog (600, 106, 280, 250) row0 [(616, 142, 248, 22)] foot Some((817.2, 317.2, 58, 34)) held Some(false) | wheel: row0 [(616, 22, 248, 22)]",
    "500 to 800: dialog (600, 106, 280, 400) row0 [(616, 142, 248, 22)] foot Some((817.2, 467.2, 58, 34)) held Some(false) | wheel: row0 [(616, 22, 248, 22)]",
    "opened at 500: dialog (600, 106, 280, 250) row0 [(616, 142, 248, 22)] foot Some((817.2, 317.2, 58, 34)) held Some(false) | wheel: row0 [(616, 22, 248, 22)]",
  ])
}

///|
/// A panel's body: the words `words` says.
fn fits_words_body(words : @signals.Signal[String]) -> (@ui.Ctx, () -> Unit) -> Unit {
  fn(c, _) { @sf.panel_text(c, fn() { c.text(words.get(), style=@sf.paragraph) |> ignore }) }
}

///|
/// A button `label` of a panel's as the window shows it: where it is, how much of its ground the clips' rects it is drawn
/// in leave (x0, y0, x1, y1: its own, scene.mbt 16-19, and the rounded one outside it, 40-43; their round corners not:
/// the corner rule's), and whether presses just inside its capsule by its edges are its own (`pressed` told so): 0.5 in
/// from its right end and from its foot, each at its middle (`top`: from its top instead of its foot).
fn panel_reach_said(t : @ui.Tester, label : String, pressed : Ref[Int], top? : Bool = false) -> String raise {
  let (x, y, w, h) = t.get(Button, label~).rect
  let shown = t
    .drawn_instances()
    .filter(fn(d) { d[5] == 0.0 && (d[0] - x).abs() < 0.01 && (d[1] - y).abs() < 0.01 && (d[2] - w).abs() < 0.01 && (d[3] - h).abs() < 0.01 })
    .map(fn(d) {
      let outer = d[44] > 0.0 || d[45] > 0.0 || d[46] > 0.0 || d[47] > 0.0
      let (x0, y0) = (dmax(x, dmax(d[16], if outer { d[40] } else { x })), dmax(y, dmax(d[17], if outer { d[41] } else { y })))
      let (x1, y1) = (dmin(x + w, dmin(d[18], if outer { d[42] } else { x + w })), dmin(y + h, dmin(d[19], if outer { d[43] } else { y + h })))
      tenth4((x0, y0, x1, y1))
    })
  let points = [(x + w - 0.5, y + h / 2.0), (x + w / 2.0, if top { y + 0.5 } else { y + h - 0.5 })]
  let presses = []
  for q in points {
    let was = pressed.val
    t.tap(q.0, q.1)
    t.run_for(@ui.move_most_ms)
    presses.push(pressed.val - was)
  }
  "\{tenth4((x, y, w, h))} shows \{shown} pressed \{presses}"
}

///|
test "panel, 大屏 keyboard and mouse: tall 0.5 and not, a foot's button in its foot corner, a head's at its end in its top corner: drawn whole where they reach into the panel's padding, pressed there: as main has it" {
  let out = []
  for kind in ["tall foot", "foot", "head end"] {
    let t = menu_tester(1280.0, 800.0, 0)
    let pressed = Ref(0)
    let foot = fn(c : @ui.Ctx, _close : () -> Unit) {
      if @sf.button(c, "好的", key="ok34", tone=Primary) {
        pressed.val = pressed.val + 1
      }
    }
    match kind {
      "tall foot" =>
        @sf.panel("面板", panel_column_body(@signals.signal(40), []), from=At(600.0, 100.0, 0.0, 0.0), tall=0.5, foot~)
      "foot" => @sf.panel("面板", fits_words_body(@signals.signal("面板里的话")), from=At(600.0, 100.0, 0.0, 0.0), foot~)
      _ =>
        @sf.panel("面板", fits_words_body(@signals.signal("面板里的话")), from=At(600.0, 100.0, 0.0, 0.0), head_end=fn(c) {
          if @sf.button(c, "尾", key="end34", tone=Primary) {
            pressed.val = pressed.val + 1
          }
        })
    }
    t.run_for(@ui.move_most_ms)
    out.push("\{kind}: \{panel_reach_said(t, if kind == "head end" { "尾" } else { "好的" }, pressed, top=kind == "head end")}")
  }
  // (as main has it, a4c845604: each wholly within the panel's clip there, (601, 107) to (879, 505), (879, 209.8),
  // (879, 175.8))
  assert_eq(out, [
    "tall foot: (817.2, 467.2, 58, 34) shows [(817.2, 467.2, 875.2, 501.2)] pressed [1, 1]",
    "foot: (817.2, 172, 58, 34) shows [(817.2, 172, 875.2, 206)] pressed [1, 1]",
    "head end: (654, 110.8, 221.2, 34) shows [(654, 110.8, 875.2, 144.8)] pressed [1, 1]",
  ])
}

///|
test "panel, 大屏 keyboard and mouse: at a point, what it holds told whether it stands above what opened it: under it, flipped over it for want of room below, said to go over it: as main has it" {
  let out = []
  for (y, side) in [(100.0, @ui.Side::Bottom), (780.0, @ui.Side::Bottom), (400.0, @ui.Side::Top)] {
    let t = menu_tester(1280.0, 800.0, 0)
    let up : Array[Bool] = []
    @sf.panel(
      "面板",
      fn(c, _) {
        up.push(@sf.panel_opens_up())
        @sf.panel_text(c, fn() { c.text("面板里的话", style=@sf.paragraph) |> ignore })
      },
      from=At(600.0, y, 0.0, 0.0),
      side~,
    )
    t.run_for(@ui.move_most_ms)
    out.push((y, t.get(Dialog, label="面板").rect.1 < y, up.last()))
  }
  // (as main has it, a4c845604)
  assert_eq(out, [(100.0, false, Some(false)), (780.0, true, Some(true)), (400.0, true, Some(true))])
}

///|
test "panel, 大屏 keyboard and mouse: at a point, open as the window is made too short for it below what opened it and tall again: what it holds told it stands above it the frame it goes there, below it again the frame it comes back: as main has it" {
  let t = menu_tester(1280.0, 800.0, 0)
  let up : Array[Bool] = []
  @sf.panel(
    "面板",
    fn(c, _) {
      up.push(@sf.panel_opens_up())
      @sf.panel_text(c, fn() { c.text("面板里的话", style=@sf.paragraph) |> ignore })
    },
    from=At(600.0, 500.0, 0.0, 0.0),
  )
  t.run_for(@ui.move_most_ms)
  let out = []
  let said = fn(t : @ui.Tester, h : Double) { (h, t.query(Dialog, label="面板").map(fn(s) { s.rect.1 < 500.0 }), up.last()) }
  out.push(said(t, 800.0))
  for h in [560.0, 800.0] {
    // (the frame it is drawn at that height, then once it is at rest)
    t.resize(1280.0, h)
    out.push(said(t, h))
    t.run_for(@ui.move_most_ms)
    out.push(said(t, h))
  }
  // (as main has it, a4c845604)
  assert_eq(out, [
    (800.0, Some(false), Some(false)),
    (560.0, Some(true), Some(true)),
    (560.0, Some(true), Some(true)),
    (800.0, Some(false), Some(false)),
    (800.0, Some(false), Some(false)),
  ])
}
