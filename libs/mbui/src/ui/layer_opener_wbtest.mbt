// A layer of the tree's said opened by a node (View::opened_by) gives the focus back to that node as it goes, not to
// what had the focus as it opened: a row a pointer opened a menu from had none (the dialog's 关闭 had it), and the
// focus comes back to the row, as Radix's and the old kit's `return_focus=trigger`; by the keyboard, the same. Where
// that node is let go of while the layer is open, back to what had the focus as it opened. Nested (a dialog's row's
// menu's row's submenu), each given back to what opened it, one after another.

///|
/// A modal dialog at 1 (while `dialog`) giving the focus to its 关闭 as it opens, holding 关闭 and the row 行 (while
/// `row_kept`), which opens the menu; the menu at 2 (while `menu`), opened by 行 (View::opened_by), giving the focus to
/// its 菜单项 and holding the row 子行, which opens the submenu; the submenu at 3 (while `sub`), opened by 子行, giving
/// the focus to its 子项. Each a column at the top left, its rows 120 by 40.
fn opener_tester(
  dialog : @signals.Signal[Bool],
  row_kept : @signals.Signal[Bool],
  menu : @signals.Signal[Bool],
  sub : @signals.Signal[Bool],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let button = fn(l : @view.View, label : String, press : () -> Unit) {
    l.box(fn(x) {
      x
      .width(Is(Some(120.0)))
      .height(Is(Some(40.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label~))))
      .on_press(press)
      |> ignore
    })
  }
  set_view_app(fn(root) {
    root.box(fn(h) { h.grow(Is(1.0)) |> ignore }) |> ignore
    let row : Ref[@view.View?] = Ref(None)
    let sub_row : Ref[@view.View?] = Ref(None)
    root.show(fn() { dialog.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(1)).modal(Is(true)) |> ignore
      let close = button(l, "关闭", fn() { dialog.set(false) })
      l.show(fn() { row_kept.get() }, fn(r) { row.val = Some(button(r, "行", fn() { menu.set(true) })) }) |> ignore
      l.focus_opens(close) |> ignore
    })
    root.show(fn() { menu.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).modal(Is(true)).offset(Is((200.0, 0.0))) |> ignore
      match row.val {
        Some(r) => l.opened_by(@view.ByNode(r.id())) |> ignore
        None => ()
      }
      let item = button(l, "菜单项", fn() {  })
      sub_row.val = Some(button(l, "子行", fn() { sub.set(true) }))
      l.focus_opens(item) |> ignore
    })
    root.show(fn() { sub.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(3)).modal(Is(true)).offset(Is((200.0, 150.0))) |> ignore
      match sub_row.val {
        Some(r) => l.opened_by(@view.ByNode(r.id())) |> ignore
        None => ()
      }
      l.focus_opens(button(l, "子项", fn() {  })) |> ignore
    })
  })
  t.draw()
  dialog.set(true)
  t.draw()
  t
}

///|
fn opener_focused(t : Tester) -> String {
  t.focused().map(fn(s) { s.label }).unwrap_or("none")
}

///|
test "a menu opened by a pointer's tap on a dialog's row (the dialog's 关闭 with the focus, the row none): the focus on its 菜单项; closed, back on the row, not on 关闭" {
  let (dialog, row_kept, menu, sub) = (
    @signals.signal(false),
    @signals.signal(true),
    @signals.signal(false),
    @signals.signal(false),
  )
  let t = opener_tester(dialog, row_kept, menu, sub)
  let before = opener_focused(t)
  // (行: the dialog's second row, 40 down)
  t.tap(60.0, 60.0)
  t.draw()
  let opened = (menu.get(), opener_focused(t))
  menu.set(false)
  t.draw()
  assert_eq((before, opened, opener_focused(t)), ("关闭", (true, "菜单项"), "行"))
}

///|
test "a menu opened by the keyboard from a dialog's row with the focus (Enter): the focus on its 菜单项; closed, back on the row" {
  let (dialog, row_kept, menu, sub) = (
    @signals.signal(false),
    @signals.signal(true),
    @signals.signal(false),
    @signals.signal(false),
  )
  let t = opener_tester(dialog, row_kept, menu, sub)
  t.act(Button, Focus, label="行")
  let before = opener_focused(t)
  t.key(key_enter)
  t.draw()
  let opened = (menu.get(), opener_focused(t))
  menu.set(false)
  t.draw()
  assert_eq((before, opened, opener_focused(t)), ("行", (true, "菜单项"), "行"))
}

///|
test "a menu opened by a dialog's row, the row let go of while it is open: closed, back on what had the focus as it opened (the dialog's 关闭)" {
  let (dialog, row_kept, menu, sub) = (
    @signals.signal(false),
    @signals.signal(true),
    @signals.signal(false),
    @signals.signal(false),
  )
  let t = opener_tester(dialog, row_kept, menu, sub)
  let before = opener_focused(t)
  menu.set(true)
  t.draw()
  let opened = opener_focused(t)
  row_kept.set(false)
  t.draw()
  menu.set(false)
  t.draw()
  assert_eq((before, opened, opener_focused(t)), ("关闭", "菜单项", "关闭"))
}

///|
test "a dialog's row's menu's row's submenu, each opened by a pointer's tap: the submenu closed, back on 子行; the menu closed, back on 行" {
  let (dialog, row_kept, menu, sub) = (
    @signals.signal(false),
    @signals.signal(true),
    @signals.signal(false),
    @signals.signal(false),
  )
  let t = opener_tester(dialog, row_kept, menu, sub)
  t.tap(60.0, 60.0)
  t.draw()
  // (子行: the menu's second row, at 200 across, 40 down)
  t.tap(260.0, 60.0)
  t.draw()
  let opened = opener_focused(t)
  sub.set(false)
  t.draw()
  let sub_closed = opener_focused(t)
  menu.set(false)
  t.draw()
  let menu_closed = opener_focused(t)
  assert_eq((opened, sub_closed, menu_closed), ("子项", "子行", "行"))
}

///|
test "a dialog's row's menu's row's submenu closed in one change with the menu: back on the menu's opener, 行" {
  let (dialog, row_kept, menu, sub) = (
    @signals.signal(false),
    @signals.signal(true),
    @signals.signal(false),
    @signals.signal(false),
  )
  let t = opener_tester(dialog, row_kept, menu, sub)
  t.tap(60.0, 60.0)
  t.draw()
  t.tap(260.0, 60.0)
  t.draw()
  @signals.start_batch()
  sub.set(false)
  menu.set(false)
  @signals.end_batch()
  t.draw()
  assert_eq(opener_focused(t), "行")
}
