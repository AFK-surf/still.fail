// A choice that opens a menu of what it can be (@sf.chooser_node, chooser's as a node) set beside the old one
// (@sf.chooser) in the same panel, on a phone's window with touch and with keyboard and mouse (a sheet) and on a wide one
// (a dialog in its middle): where it and its menu stand, what it draws at rest, pointed at and open, how its menu opens,
// chooses and closes, by the hand and by the keys, and what it is read out as.

///|
/// The app over the fixture's chat `w` by `h` as `platform` plays it, a panel opened by nothing over it holding words,
/// then a chooser of 小时 and 分钟 (小时 chosen), then words again; the old view's chooser (`old`) or the window's tree's.
/// What is chosen is put in `chosen`.
fn ch_panel(old : Bool, chosen : Array[String], platform~ : Int, wide~ : Bool) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.run_for(@ui.move_most_ms)
  let words = fn(u : String) { if u == "hours" { "小时" } else { "分钟" } }
  if old {
    let unit = Ref("hours")
    let open = Ref(false)
    @sf.panel(
      "单位",
      fn(c, _) {
        c.text("说明文字", style=@sf.meta) |> ignore
        let entries = ["hours", "minutes"].map(fn(u) { @kit.menu_radio(u, u == unit.val, label=words(u)) })
        let m = @sf.chooser(c, "ch-test", words(unit.val), entries, fn() { open.val }, fn(on) { open.val = on })
        match m.chosen {
          Some(u) => {
            unit.val = u
            open.val = false
            chosen.push(u)
          }
          None => ()
        }
        c.text("末尾文字", style=@sf.meta) |> ignore
      },
      from=Unanchored,
    )
  } else {
    let unit = @signals.signal("hours", same=fn(a, b) { a == b })
    @sf.panel_nodes(
      "单位",
      fn(v, _) {
        @sf.words_node(v, fn() { "说明文字" }, fn() { @sf.meta }) |> ignore
        v.box(fn(b) {
          @sf.chooser_node(b, fn() { words(unit.get()) }, fn() { [("hours", "小时"), ("minutes", "分钟")] }, fn() {
            unit.get()
          }, fn(u) {
            unit.set(u)
            chosen.push(u)
          })
          |> ignore
        })
        |> ignore
        @sf.words_node(v, fn() { "末尾文字" }, fn() { @sf.meta }) |> ignore
      },
      from=Unanchored,
    )
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The three screens: a phone's window with touch, with keyboard and mouse, a wide window with keyboard and mouse.
// kept across runs: a value (no field of it changes)
let ch_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// The chooser, as a screen reader reads it (a button named by its words), where it is.
fn ch_button(t : @ui.Tester, words : String) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Button && s.label == words && !s.hidden })
}

///|
/// Where each of `words` is drawn last (over what is under it), to a tenth.
fn ch_at(t : @ui.Tester, words : Array[String]) -> Array[String] {
  words.map(fn(s) {
    match t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }).last() {
      Some(w) => "\{s} \{@ui.rect_text(tenth4((w.1, w.2, w.3, w.4)))}"
      None => "\{s} -"
    }
  })
}

///|
/// What is drawn inside rectangle `r` (the chooser's): each rectangle, to a tenth, with its colour.
fn ch_drawn_in(t : @ui.Tester, r : (Double, Double, Double, Double)) -> Array[String] {
  t
  .drawn_rects()
  .filter(fn(d) { d.0 >= r.0 - 0.5 && d.1 >= r.1 - 0.5 && d.0 + d.2 <= r.0 + r.2 + 0.5 && d.1 + d.3 <= r.1 + r.3 + 0.5 })
  .map(fn(d) { "\{@ui.rect_text(tenth4((d.0, d.1, d.2, d.3)))} \{d.4}" })
}

///|
/// The middle of the last of `words` drawn, where they are.
fn ch_seen(t : @ui.Tester, words : String) -> (Double, Double)? {
  t.words().filter(fn(w) { w.0 == words && w.5 > 0.5 }).last().map(fn(w) { (w.1 + w.3 / 2.0, w.2 + w.4 / 2.0) })
}

///|
/// What the hand finds of it on a screen: at rest, pointed at (with a mouse), pressed open, a choice pressed, opened and
/// Escape. Each fact a line.
fn ch_hand(old : Bool, platform : Int, wide : Bool) -> Array[String] {
  let chosen : Array[String] = []
  let t = ch_panel(old, chosen, platform~, wide~)
  let out : Array[String] = []
  guard ch_button(t, "小时") is Some(b) else {
    out.push("rest: no 小时 \{@ui.list_text(ch_at(t, ["小时", "单位"]))}")
    return out
  }
  let r = b.rect
  out.push("rest: \{@ui.rect_text(tenth4(r))} expanded \{@ui.some_text(b.expanded)} \{@ui.list_text(ch_at(t, ["小时", "说明文字", "末尾文字"]))}")
  out.push("rest drawn: \{@ui.list_text(ch_drawn_in(t, r))}")
  let (x, y) = (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
  if platform == 0 {
    t.move_to(x, y)
    t.run_for(@ui.move_most_ms)
    out.push("pointed drawn: \{@ui.list_text(ch_drawn_in(t, r))}")
  }
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  out.push("open: expanded \{@ui.some_text(ch_button(t, "小时").map(fn(s) { @ui.some_text(s.expanded) }))} \{@ui.list_text(ch_at(t, ["小时", "分钟"]))}")
  out.push("open drawn: \{@ui.list_text(ch_drawn_in(t, r))}")
  // (its menu as a screen reader reads it: a choice each, the one chosen checked)
  let items = t.semantics().filter(fn(n) { (n.role == @ui.Role::MenuItemRadio || n.role == @ui.Role::MenuItem) && !n.hidden })
  out.push("menu: \{@ui.list_text(items.map(fn(n) { "(\{n.role}, \{n.label}, \{@ui.some_text(n.check)})" }))}")
  guard ch_seen(t, "分钟") is Some((mx, my)) else {
    out.push("open: no 分钟")
    return out
  }
  t.tap(mx, my)
  t.run_for(@ui.move_most_ms)
  out.push("chosen: \{@ui.list_text(chosen)} \{@ui.list_text(ch_at(t, ["小时", "分钟", "单位"]))}")
  // (opened again, Escape: its menu alone)
  guard ch_button(t, "分钟") is Some(b2) else {
    out.push("chosen: no 分钟 to press")
    return out
  }
  t.tap(b2.rect.0 + b2.rect.2 / 2.0, b2.rect.1 + b2.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  out.push("again: \{@ui.list_text(ch_at(t, ["小时", "分钟"]))}")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  out.push("escape: \{@ui.list_text(ch_at(t, ["小时", "分钟", "单位"]))}")
  out.push("escape focus: \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
  // (a press outside it, on the panel's title: its menu alone)
  t.tap(b2.rect.0 + b2.rect.2 / 2.0, b2.rect.1 + b2.rect.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  let (wx, wy) = ch_seen(t, "单位").unwrap_or((0.0, 0.0))
  t.tap(wx, wy)
  t.run_for(@ui.move_most_ms)
  out.push("outside: \{@ui.list_text(ch_at(t, ["小时", "分钟", "单位"]))} chosen \{@ui.list_text(chosen)}")
  // (pressed 3 over its top, within the room a press is given round it)
  t.tap(x, r.1 - 3.0)
  t.run_for(@ui.move_most_ms)
  out.push("over its edge: \{@ui.list_text(ch_at(t, ["小时", "分钟"]))}")
  out
}

///|
/// What the keys find of it, with keyboard and mouse: Tab's way to it, Enter on it, Escape, Down on it, Down in its
/// menu and Enter there. Each fact a line.
fn ch_keys(old : Bool, wide : Bool) -> Array[String] {
  let chosen : Array[String] = []
  let t = ch_panel(old, chosen, platform=0, wide~)
  let out : Array[String] = []
  let mut n = 0
  while n < 8 && !(t.focused() is Some(s) && s.label == "小时") {
    t.tab()
    t.run_for(@ui.move_most_ms)
    n += 1
  }
  out.push("tab: \{n} \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
  guard ch_button(t, "小时") is Some(b) else { return out }
  if t.focused() is Some(s) && s.label == "小时" {
    out.push("focused drawn: \{@ui.list_text(ch_drawn_in(t, b.rect))}")
    t.enter()
    t.run_for(@ui.move_most_ms)
    out.push("enter: \{@ui.list_text(ch_at(t, ["分钟"]))} focus \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    out.push("escape: \{@ui.list_text(ch_at(t, ["分钟", "单位"]))} focus \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
    t.key(@ui.key_code_down)
    t.run_for(@ui.move_most_ms)
    out.push("down: \{@ui.list_text(ch_at(t, ["分钟"]))} focus \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
    t.key(@ui.key_code_down)
    t.run_for(@ui.move_most_ms)
    t.enter()
    t.run_for(@ui.move_most_ms)
    out.push("chosen by keys: \{@ui.list_text(chosen)} \{@ui.list_text(ch_at(t, ["小时", "分钟", "单位"]))} focus \{@ui.some_text(t.focused().map(fn(s) { s.label }))}")
  }
  out
}

///|
test "a chooser, old and as nodes, on the three screens: where it stands, what it draws at rest, pointed at and open, its menu under it read out a choice each, a choice pressed, Escape and a press outside closing its menu alone, a press just over its edge" {
  for s in ch_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let old = ch_hand(true, platform, wide)
    let made = ch_hand(false, platform, wide)
    let same = fn(l : Array[String]) { l.filter(fn(x) { !x.has_prefix("escape focus:") }) }
    assert_eq(same(made), same(old), msg=at)
    assert_true(made.length() > 8, msg="\{at}: \{Repr(made)}")
    // (its menu closed by Escape, the focus back on it, on a sheet too: the old one's left it nowhere there)
    assert_true(made.contains("escape focus: Some(分钟)"), msg="\{at}: \{Repr(made)}")
  }
}

///|
test "a chooser, old and as nodes, with keyboard and mouse: Tab to it, Enter opening its menu, Escape, Down opening it, a choice by the keys" {
  for wide in [false, true] {
    let old = ch_keys(true, wide)
    let made = ch_keys(false, wide)
    // (in a dialog in the window's middle the old panel gives its first part the focus as it opens, unshown; a panel
    // of nodes gives it none: that is the dialog's, not the chooser's, so how it came to the focus is not compared there)
    let same = fn(l : Array[String]) { l.filter(fn(x) { !wide || !(x.has_prefix("tab:") || x.has_prefix("focused drawn:")) }) }
    assert_eq(same(made), same(old), msg="wide \{wide}")
    assert_true(made.length() == 6 && made[0].has_suffix("Some(小时)"), msg="wide \{wide}: \{Repr(made)}")
  }
}
