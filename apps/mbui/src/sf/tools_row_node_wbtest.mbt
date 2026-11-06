// A toolbar of tree nodes: its row, its menu, their input and what they say as the room and the tools change.

///|
fn row_test_tool(
  key : String,
  drop : Int,
  width : Double,
  hits : Map[String, Int],
  nodes : Map[String, @view.View],
  off : @signals.Signal[Bool],
  choice : @signals.Signal[Bool],
) -> RowTool {
  let press = fn() { hits[key] = hits.get(key).unwrap_or(0) + 1 }
  row_tool_of(
    key,
    fn(slot) {
      slot.width(Is(Some(width))) |> ignore
      let b = icon_button_node(slot, "copy", fn() { key }, press)
      nodes[key] = b
      b.owns(fn() { nodes.remove(key) }) |> ignore
    },
    drop~,
    instead=fn() {
      if key == "view" {
        [
          menu_item_of("columns", fn() { hits["columns"] = hits.get("columns").unwrap_or(0) + 1 }, icon="view-columns", chosen=choice.get()),
          menu_item_of("list", fn() { hits["list"] = hits.get("list").unwrap_or(0) + 1 }, icon="list", disabled=off.get()),
        ]
      } else {
        [menu_item_of(key + " menu", press, icon="copy", disabled=off.get() && key == "preview")]
      }
    },
  )
}

///|
fn row_test_case(
  width : @signals.Signal[Double],
  fixed : @signals.Signal[Bool],
  preview : @signals.Signal[Bool],
  off : @signals.Signal[Bool],
  choice : @signals.Signal[Bool],
  hits : Map[String, Int],
  nodes : Map[String, @view.View],
  shown? : @signals.Signal[Bool] = @signals.signal(true),
  platform? : Int = 0,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=500.0, h=400.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(fn() { shown.get() }, fn(place) {
      place.padding(Is((30.0, 40.0, 0.0, 0.0))) |> ignore
      tools_row_node(
        place,
        fn() {
          let all : Array[RowTool] = [row_test_tool("view", 2, 68.0, hits, nodes, off, choice)]
          if preview.get() {
            all.push(row_test_tool("preview", 1, 32.0, hits, nodes, off, choice))
          }
          all.push(row_test_tool("upload", 4, 32.0, hits, nodes, off, choice))
          all.push(row_test_tool("mkdir", 3, 32.0, hits, nodes, off, choice))
          all
        },
        fn() { if fixed.get() { [Some(menu_item_of("refresh", fn() { hits["refresh"] = hits.get("refresh").unwrap_or(0) + 1 }))] } else { [] } },
        fn() { "more" },
      )
      .width(By(fn() { Some(width.get()) })) |> ignore
    })
  })
  t.draw()
  t
}

///|
test "tools row nodes: actual width drops whole tools in priority order and brings the same nodes back" {
  let width = @signals.signal(220.0)
  let hits : Map[String, Int] = {}
  let nodes : Map[String, @view.View] = {}
  let t = row_test_case(width, @signals.signal(true), @signals.signal(true), @signals.signal(false), @signals.signal(false), hits, nodes)
  let old = nodes["preview"].id()
  for k in ["view", "preview", "upload", "mkdir", "more"] {
    assert_true(t.query(Button, label=k) is Some(_), msg="wide: \{k}")
  }
  width.set(219.0)
  t.draw()
  assert_true(t.query(Button, label="preview") is None, msg="preview leaves first")
  assert_true(t.query(Button, label="view") is Some(_))
  width.set(181.0)
  t.draw()
  assert_true(t.query(Button, label="view") is None, msg="view leaves second")
  assert_true(t.query(Button, label="mkdir") is Some(_))
  width.set(107.0)
  t.draw()
  assert_true(t.query(Button, label="mkdir") is None, msg="mkdir leaves third")
  assert_true(t.query(Button, label="upload") is Some(_))
  width.set(69.0)
  t.draw()
  assert_true(t.query(Button, label="upload") is None, msg="upload leaves last")
  width.set(220.0)
  t.draw()
  assert_eq(nodes["preview"].id(), old, msg="the original node returned")
  t.click(Button, label="preview")
  assert_eq(hits.get("preview"), Some(1))
}

///|
test "tools row nodes: its open menu follows left-out tools and live items, and selects what it shows" {
  let width = @signals.signal(107.0)
  let fixed = @signals.signal(true)
  let preview = @signals.signal(true)
  let off = @signals.signal(false)
  let choice = @signals.signal(false)
  let hits : Map[String, Int] = {}
  let nodes : Map[String, @view.View] = {}
  let t = row_test_case(width, fixed, preview, off, choice, hits, nodes)
  t.click(Button, label="more")
  assert_eq(t.all(MenuItem).map(fn(s) { s.label }), ["list", "preview menu", "mkdir menu", "refresh"])
  assert_true(t.query(MenuItemRadio, label="columns") is Some(_), msg="a tool can offer multiple choices")
  off.set(true)
  choice.set(true)
  preview.set(false)
  t.draw()
  assert_true(t.query(MenuItem, label="preview menu") is None, msg="removed tool's item gone while open")
  assert_true(t.get(MenuItem, label="list").disabled, msg="menu's disabled state follows its source")
  assert_true(t.get(MenuItemRadio, label="columns").check is Some(On), msg="choice follows its source")
  t.click(MenuItem, label="refresh")
  assert_eq(hits.get("refresh"), Some(1))
  assert_true(t.query(Menu) is None, msg="choosing closes the menu")
}

///|
test "tools row nodes: without fixed items the more button comes and goes with overflow, closing an open menu" {
  let width = @signals.signal(120.0)
  let fixed = @signals.signal(false)
  let hits : Map[String, Int] = {}
  let nodes : Map[String, @view.View] = {}
  let t = row_test_case(width, fixed, @signals.signal(true), @signals.signal(false), @signals.signal(false), hits, nodes)
  assert_true(t.query(Button, label="more") is Some(_))
  t.click(Button, label="more")
  assert_true(t.query(Menu) is Some(_))
  width.set(220.0)
  t.draw()
  assert_true(t.query(Menu) is None, msg="the trigger and its menu leave together")
  assert_true(t.query(Button, label="more") is None)
  width.set(120.0)
  t.draw()
  assert_true(t.query(Button, label="more") is Some(_))
  assert_true(t.query(Menu) is None, msg="it does not reopen when the trigger returns")
}

///|
test "tools row nodes: keyboard opens its menu, moves, chooses and restores focus; removing the row removes its menu" {
  let shown = @signals.signal(true)
  let hits : Map[String, Int] = {}
  let nodes : Map[String, @view.View] = {}
  let t = row_test_case(@signals.signal(69.0), @signals.signal(true), @signals.signal(true), @signals.signal(false), @signals.signal(false), hits, nodes, shown~)
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("more"))
  t.key(@ui.key_code_down)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("columns"))
  t.key(@ui.key_code_down)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("list"))
  t.key(@ui.key_code_enter)
  assert_eq(hits.get("list"), Some(1))
  assert_eq(t.focused().map(fn(s) { s.label }), Some("more"))
  t.key(@ui.key_code_enter)
  assert_true(t.query(Menu) is Some(_))
  shown.set(false)
  t.draw()
  assert_true(t.query(Menu) is None, msg="its popup lives with the toolbar")
}

///|
test "tools row nodes: a finger holding a tool as it leaves cannot press it; its menu item still works" {
  let width = @signals.signal(245.0)
  let hits : Map[String, Int] = {}
  let nodes : Map[String, @view.View] = {}
  let t = row_test_case(width, @signals.signal(true), @signals.signal(true), @signals.signal(false), @signals.signal(false), hits, nodes, platform=2)
  let r = t.get(Button, label="preview").rect
  let x = r.0 + r.2 / 2.0
  let y = r.1 + r.3 / 2.0
  t.touch_raw(0, 1, x, y, t.time())
  width.set(200.0)
  t.draw()
  t.touch_raw(2, 1, x, y, t.time())
  assert_eq(hits.get("preview"), None, msg="the held press was called off as it left")
  t.click(Button, label="more")
  t.click(MenuItem, label="preview menu")
  assert_eq(hits.get("preview"), Some(1), msg="the replacement does the same action")
}
