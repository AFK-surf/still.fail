// A window's top row does not say a cursor. Match the old frame when picked words lie under it, while the row still
// owns the press that moves the window.

///|
fn toprow_picked_cursor(node : Bool) -> (Cursor, Int) {
  let t = Tester::new(fn(c) {
    if !node {
      c.mouse_drags_lists(false)
      c.selectable(fn() {
        c.box(left=20.0, top=40.0, w=Px(300.0), fn() {
          c.rich([plain("A paragraph behind the window bar")], size=15.0, line=22.0) |> ignore
        }) |> ignore
      })
      let top = c.id("top")
      c.window_drag(top)
      c.box(id=top, left=0.0, top=0.0, w=Px(400.0), h=Px(60.0), fn() { }) |> ignore
    }
  }, w=400.0, h=300.0, platform=0)
  if node {
    set_view_app(fn(root) {
      root.box(fn(page) {
        page.width(Is(Some(400.0))).height(Is(Some(300.0))) |> ignore
        words_picked(page)
        page.box(fn(words) {
          words.over(Is(true)).offset(Is((20.0, 40.0))).width(Is(Some(300.0))).height(Is(Some(22.0)))
          .words_runs(Is([plain("A paragraph behind the window bar")]), look={ size: 15.0, weight: 400,
            line: 22.0, wrap: true, tracking: @view.letters_own, balance: false }) |> ignore
        }) |> ignore
        page.box(fn(top) {
          top.over(Is(true)).width(Is(Some(400.0))).height(Is(Some(60.0))).moves_window(Is(true)) |> ignore
        }) |> ignore
      }) |> ignore
    })
  }
  t.draw()
  t.move(60.0, 51.0)
  let shape = t.cursor()
  t.press_at(60.0, 51.0)
  t.release(60.0, 51.0)
  (shape, t.window_drags())
}

///|
test "a window bar over picked words has the old frame's pointer and keeps its window drag" {
  let old = toprow_picked_cursor(false)
  let node = toprow_picked_cursor(true)
  assert_eq(old, (IBeam, 1), msg="the old frame")
  assert_eq(node, old, msg="the window tree")
}
