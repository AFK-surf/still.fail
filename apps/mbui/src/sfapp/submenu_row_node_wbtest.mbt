// A panel's row opening the next menu beside it (@sf.submenu_row_node, submenu_row's as nodes) set beside the old one
// (@sf.submenu_row) in the same panel: where its rows and its menu stand, and how each opens and closes, the same.

///|
/// The app over the fixture's chat `w` by `h` as `platform` plays it, a panel over it (`from`: Unanchored a dialog in the
/// middle of the window on a wide one, beside what opened it else) holding words, then the row 甲 (while `shown`) and the
/// row 乙, each opening its items beside it, then words again (no row in a dialog's foot corners); the old view's rows (`old`) or the window's tree's. What is chosen is put in
/// `chosen` by its words.
fn sub_panel(
  old : Bool,
  from : @sf.Anchor,
  chosen : Array[String],
  shown : @signals.Signal[Bool],
  w? : Double = 1280.0,
  h? : Double = 800.0,
  platform? : Int = 0,
) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  wide_src.val = Some(src)
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  let item = fn(l : String) -> @sf.MenuItem? { Some(@sf.menu_item_of(l, fn() { chosen.push(l) })) }
  let a = [item("甲一"), item("甲二")]
  let b = [item("乙一")]
  if old {
    @sf.panel(
      "子菜单",
      fn(c, _) {
        c.text("说明文字", style=@sf.meta) |> ignore
        if shown.get() {
          @sf.submenu_row(c, "sub-test/a", "甲", a)
        }
        @sf.submenu_row(c, "sub-test/b", "乙", b)
        c.text("末尾文字", style=@sf.meta) |> ignore
      },
      from~,
    )
  } else {
    @sf.panel_nodes(
      "子菜单",
      fn(v, _) {
        @sf.words_node(v, fn() { "说明文字" }, fn() { @sf.meta }) |> ignore
        v.show(fn() { shown.get() }, fn(x) { @sf.submenu_row_node(x, fn() { "甲" }, fn() { a }) })
        @sf.submenu_row_node(v, fn() { "乙" }, fn() { b })
        @sf.words_node(v, fn() { "末尾文字" }, fn() { @sf.meta }) |> ignore
      },
      from~,
    )
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Where each of `words` is drawn (the last of each: the panel's and its menu's, over what is under them), to a tenth.
fn sub_at(t : @ui.Tester, words : Array[String]) -> Array[String] {
  words.map(fn(s) {
    match t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 }).last() {
      Some(w) => "\{s} \{@ui.rect_text(tenth4((w.1, w.2, w.3, w.4)))}"
      None => "\{s} -"
    }
  })
}

///|
/// The middle of the last of `words` drawn.
fn sub_mid(t : @ui.Tester, words : String) -> (Double, Double) {
  match t.words().filter(fn(w) { w.0 == words && w.5 > 0.5 }).last() {
    Some(w) => (w.1 + w.3 / 2.0, w.2 + w.4 / 2.0)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
/// Whether `words` are drawn.
fn sub_has(t : @ui.Tester, words : String) -> Bool {
  t.words().any(fn(w) { w.0 == words && w.5 > 0.5 })
}

///|
/// The two ways a wide window shows the panel: a dialog in its middle, a small panel beside what opened it.
let sub_froms : Array[(String, @sf.Anchor)] = [("dialog", Unanchored), ("beside", At(300.0, 120.0, 80.0, 30.0))]

///|
test "a submenu row, old and as nodes, on a wide window: the rows, and its menu pressed open beside it, at the same places" {
  for f in sub_froms {
    let at : Array[Array[String]] = []
    for old in [true, false] {
      let t = sub_panel(old, f.1, [], @signals.signal(true))
      let rows = sub_at(t, ["说明文字", "甲", "乙", "末尾文字"])
      let (x, y) = sub_mid(t, "甲")
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
      at.push(rows + sub_at(t, ["甲一", "甲二"]))
    }
    assert_eq(at[1], at[0], msg="\{f.0}: old \{Repr(at[0])}, nodes \{Repr(at[1])}")
    assert_true(!at[0].iter().any(fn(s) { s.has_suffix(" -") }), msg="\{f.0}: \{Repr(at[0])}")
  }
}

///|
test "a submenu row, old and as nodes, on 小屏: pressed, a sheet of its items titled by it, at the same places; one chosen, done once, the sheet gone" {
  let at : Array[Array[String]] = []
  for old in [true, false] {
    let chosen = []
    let t = sub_panel(old, Unanchored, chosen, @signals.signal(true), w=390.0, h=844.0, platform=2)
    let (x, y) = sub_mid(t, "甲")
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    at.push(sub_at(t, ["甲一", "甲二"]))
    let (x, y) = sub_mid(t, "甲二")
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq(chosen, ["甲二"], msg="old \{old}")
    assert_true(!sub_has(t, "甲一"), msg="old \{old}")
  }
  assert_eq(at[1], at[0], msg="old \{Repr(at[0])}, nodes \{Repr(at[1])}")
}

///|
test "a submenu row, old and as nodes: the mouse's pointer onto it opens its menu at once; off it onto the panel's words, open still; onto the other row, that one's in its place" {
  for f in sub_froms {
    for old in [true, false] {
      let about = "\{f.0}, old \{old}"
      let t = sub_panel(old, f.1, [], @signals.signal(true))
      let (x, y) = sub_mid(t, "甲")
      t.move_to(x, y)
      t.frame()
      // (there at once, on its way in)
      assert_true(t.words().any(fn(w) { w.0 == "甲一" }), msg="\{about}: at once")
      let (wx, wy) = sub_mid(t, "说明文字")
      t.move_to(wx, wy)
      t.run_for(@ui.move_most_ms)
      assert_true(sub_has(t, "甲一"), msg="\{about}: open still")
      let (bx, by) = sub_mid(t, "乙")
      t.move_to(bx, by)
      t.frame()
      assert_true(t.words().any(fn(w) { w.0 == "乙一" }), msg="\{about}: the other's")
      t.run_for(@ui.move_most_ms)
      assert_true(!sub_has(t, "甲一"), msg="\{about}: the first's gone")
    }
  }
}

///|
test "a submenu row, old and as nodes: Escape closes its menu alone; Right, the focus back on its row, opens it again; Left closes it alone" {
  for f in sub_froms {
    for old in [true, false] {
      let about = "\{f.0}, old \{old}"
      let t = sub_panel(old, f.1, [], @signals.signal(true))
      let (x, y) = sub_mid(t, "甲")
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_true(!sub_has(t, "甲一") && sub_has(t, "说明文字"), msg="\{about}: Escape: \{Repr(sub_at(t, ["甲一", "说明文字"]))}")
      t.key(@ui.key_code_right)
      t.run_for(@ui.move_most_ms)
      assert_true(sub_has(t, "甲一"), msg="\{about}: Right: \{Repr(t.focused())}")
      t.key(@ui.key_code_left)
      t.run_for(@ui.move_most_ms)
      assert_true(!sub_has(t, "甲一") && sub_has(t, "说明文字"), msg="\{about}: Left")
    }
  }
}

///|
test "a submenu row, old and as nodes: a press on the panel's words closes its menu alone; on the other row, that one's opens in one press; an item pressed, done once, closed, the panel kept" {
  for f in sub_froms {
    for old in [true, false] {
      let about = "\{f.0}, old \{old}"
      let chosen = []
      let t = sub_panel(old, f.1, chosen, @signals.signal(true))
      let (x, y) = sub_mid(t, "甲")
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
      let (wx, wy) = sub_mid(t, "说明文字")
      t.tap(wx, wy)
      t.run_for(@ui.move_most_ms)
      assert_true(!sub_has(t, "甲一") && sub_has(t, "说明文字"), msg="\{about}: the words")
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
      let (bx, by) = sub_mid(t, "乙")
      t.tap(bx, by)
      t.run_for(@ui.move_most_ms)
      assert_true(sub_has(t, "乙一") && !sub_has(t, "甲一"), msg="\{about}: the other row: \{Repr(sub_at(t, ["甲一", "乙一"]))}")
      let (ix, iy) = sub_mid(t, "乙一")
      t.tap(ix, iy)
      t.run_for(@ui.move_most_ms)
      assert_eq(chosen, ["乙一"], msg="\{about}: \{Repr(sub_at(t, ["乙一", "说明文字"]))}")
      assert_true(!sub_has(t, "乙一") && sub_has(t, "说明文字"), msg="\{about}: chosen")
    }
  }
}

///|
test "a submenu row as nodes: its row going (its room closing on a Move), its menu out of sight and out of reach from that moment" {
  for f in sub_froms {
    let shown = @signals.signal(true)
    let t = sub_panel(false, f.1, [], shown)
    let (x, y) = sub_mid(t, "甲")
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_true(sub_has(t, "甲一"), msg="\{f.0}: open")
    shown.set(false)
    t.frame()
    assert_true(
      !t.words().any(fn(w) { w.0 == "甲一" }) && t.query(MenuItem, label="甲一") is None,
      msg="\{f.0}: at that moment",
    )
    t.run_for(@ui.move_most_ms)
    assert_true(!sub_has(t, "甲") && !sub_has(t, "甲一"), msg="\{f.0}: gone")
  }
}

///|
/// How long after its row starts going it is called back: half the way of the longest Move, the row still going (a
/// frame on, the panel's height turning back from rest is judged: View::come_back's, the smoothness line's).
let sub_back_after : Double = @ui.move_most_ms / 2.0

///|
/// The panel of `f` (sub_panel), the row 甲's menu pressed open, then the row going (`shown` false) and called back
/// sub_back_after that, the pointer moved off the panel to the window's corner before it is called back where `away`:
/// the Tester as the row is back and its Move over.
fn sub_called_back(f : (String, @sf.Anchor), away : Bool) -> @ui.Tester raise {
  let shown = @signals.signal(true)
  let t = sub_panel(false, f.1, [], shown)
  let (x, y) = sub_mid(t, "甲")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(sub_has(t, "甲一"), msg="\{f.0}: open")
  shown.set(false)
  t.run_for(sub_back_after)
  assert_true(t.query(MenuItem, label="甲一") is None, msg="\{f.0}: out of reach as it goes")
  if away {
    t.move_to(4.0, 4.0)
  }
  // (shown again before its Move is over: the same row, back)
  shown.set(true)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a submenu row as nodes, called back as it goes, the mouse's pointer resting on it: its menu opens again" {
  for f in sub_froms {
    let t = sub_called_back(f, false)
    assert_true(sub_has(t, "甲") && sub_has(t, "甲一"), msg="\{f.0}: back, open again: \{Repr(sub_at(t, ["甲", "甲一"]))}")
  }
}

///|
test "a submenu row as nodes, called back as it goes, the mouse's pointer moved off first: its menu closed; pointed at, open" {
  for f in sub_froms {
    let t = sub_called_back(f, true)
    assert_true(sub_has(t, "甲") && !sub_has(t, "甲一"), msg="\{f.0}: back, closed: \{Repr(sub_at(t, ["甲", "甲一"]))}")
    let (x, y) = sub_mid(t, "甲")
    t.move_to(x, y)
    t.run_for(@ui.move_most_ms)
    assert_true(sub_has(t, "甲一"), msg="\{f.0}: pointed at, open")
  }
}
