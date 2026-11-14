// A panel's ground (ground_node): with a mouse, the arrow over what of each of the library's panels takes a press and
// does nothing (its padding, the line between a menu's parts), the hand over what in it is pressed; a confirm's the
// same as ever. (The others it is said of, each in its own file: offers_node_wbtest, sfapp's reader_layout_wbtest,
// rail_cards_wbtest, things_sheet_wbtest.)

///|
/// How long the pointer rests where it is moved before its shape is read: a frame's worth is enough, a shape shown as
/// the frame then owed ends (View::cursor).
let ground_look_ms : Double = 20.0

///|
/// The pointer's shape at (x, y), moved there.
fn shape_at(t : @ui.Tester, x : Double, y : Double) -> @view.Cursor {
  t.move_to(x, y)
  t.run_for(ground_look_ms)
  t.cursor()
}

///|
/// Each of the library's panels of nodes, as a mouse's window has it (1200 by 800; a sheet, 390 by 800): its name, the
/// window, how it is opened, what of it is pressed (what is read out so, by its name).
fn ground_kinds() -> Array[(String, (Int, Double, Double), (Anchor) -> Unit, String)] {
  // (its words, then its key under them: not right under a centred one's close button, apart from it)
  let body = fn(v : @view.View, _close : () -> Unit) {
    v.box(fn(w) { w.words(Is("面板里的字")) |> ignore }) |> ignore
    button_node(v, fn() { "里面的键" }, fn() {  }) |> ignore
  }
  // (a long pick: as many choices as one searched takes, pick_node)
  let choices = Array::makei(pick_search_from + 2, fn(i) { choice("c\{i}", "第\{i}项") })
  [
    (
      "menu_node",
      (0, 1200.0, 800.0),
      fn(from) {
        menu([Some(menu_item_of("一项", fn() {  })), None, Some(menu_item_of("二项", fn() {  }))], from=beside_of(from))
      },
      "一项",
    ),
    ("panel_node", (0, 1200.0, 800.0), fn(from) { panel_nodes("面板", body, from~) }, "里面的键"),
    ("panel_centred_node", (0, 1200.0, 800.0), fn(_) { panel_nodes("面板", body, from=Unanchored) }, "里面的键"),
    ("confirm_node", (0, 1200.0, 800.0), fn(from) { confirm("确定吗？", "这里说明它做什么。", "好", fn() {  }, from~) }, "好"),
    ("sheet_node", (0, 390.0, 800.0), fn(from) { panel_nodes("面板", body, from~) }, "里面的键"),
    ("ask_node", (0, 1200.0, 800.0), fn(from) { ask("写一句", "好", fn(_) {  }, empty=true, from~) }, "common.cancel"),
    ("pick_node", (0, 1200.0, 800.0), fn(from) { pick("选一个", choices, "c0", fn(_) {  }, from=beside_of(from)) }, "第1项"),
  ]
}

///|
test "a mouse's pointer over a panel's ground is the arrow, over what in it is pressed the hand: a menu, a panel beside what opened it, one in the middle, a confirm, a sheet, a question, a long pick" {
  for k in ground_kinds() {
    let (name, at, open, label) = k
    let t = presenting_tester(at, open)
    t.tap_text("打开")
    t.run_for(@ui.move_most_ms)
    let shown = t.semantics().filter(fn(s) { (s.role == Menu || s.role == Dialog || s.role == AlertDialog) && !s.hidden })
    guard shown is [panel, ..] else { fail("\{name}: none shown") }
    let (x, y, w, h) = panel.rect
    // (where its ground is: four points 3 in from its edges; a menu's rows reach out over its padding to its edges, so
    // the line between its parts, midway between the rows over and under it)
    let points = if name == "menu_node" {
      let one = t.get(MenuItem, label="一项").rect
      let two = t.get(MenuItem, label="二项").rect
      [(x + w / 2.0, (one.1 + one.3 + two.1) / 2.0)]
    } else {
      [(x + 3.0, y + h / 2.0), (x + w / 2.0, y + 3.0), (x + w / 2.0, y + h - 3.0), (x + w - 3.0, y + h / 2.0)]
    }
    let grounds = points.map(fn(p) { shape_at(t, p.0, p.1) })
    assert_eq(grounds, points.map(fn(_) { Arrow }), msg="\{name}: its ground at \{Repr(points)}: \{Repr(grounds)}, it \{Repr(panel.rect)}")
    let key = match t.semantics().filter(fn(s) { s.label == label && !s.hidden }) {
      [s, ..] => s.rect
      [] => fail("\{name}: no \{label}")
    }
    let over = shape_at(t, key.0 + key.2 / 2.0, key.1 + key.3 / 2.0)
    assert_eq(over, Hand, msg="\{name}: \{label} at \{Repr(key)}: \{over}")
    // (a centred one's close button drawn over the top of what it holds by a point (`apart`): so on main before this,
    // none of its own; told, left to its own change. Every other fault none)
    let faults = t
      .audit()
      .filter(fn(f) {
        !(name == "panel_centred_node" && f.has_prefix("apart: ") && f.contains("icon_button_node.mbt") && f.contains("drawn over each other by 58×1"))
      })
    assert_eq(faults, [], msg="\{name}: \{Repr(faults)}")
  }
}
