// The list head as a node: its room, and the life and input of what is made inside it.

///|
fn rows_head_rect(ink : Int64) -> (Double, Double, Double, Double) {
  let drawn = @ui.view_tree().unwrap().drawn()
  match drawn.search_by(fn(d) { d.ground == ink }) {
    Some(i) => (drawn[i].x, drawn[i].y, drawn[i].w, drawn[i].h)
    None => (-1.0, -1.0, -1.0, -1.0)
  }
}

///|
test "a list head's two lines and what follows it: narrow and wide, first or not, in a page and a pane" {
  for look in [Narrow, Wide] {
    for first in [false, true] {
      for pane in [false, true] {
        let t = @ui.Tester::new(fn(_c) {  }, w=320.0, h=200.0)
        @ui.set_view_app(fn(root) {
          look_lent(root, look)
          root.lends(pane_lent, pane) |> ignore
          page_block(root, fn(room) {
            // Full width is still required when a holder lines up its children at the start.
            room.lines_up(Is(Some(Start))) |> ignore
            rows_head_node(room, first=fn() { first }, fn(head) {
              head.box(fn(a) { a.height(Is(Some(20.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
              head.box(fn(b) { b.height(Is(Some(10.0))).ground(Is(0x667799FFL)) |> ignore }) |> ignore
            })
            room.box(fn(after) { after.height(Is(Some(5.0))).width(Is(Some(20.0))).ground(Is(0x773399FFL)) |> ignore }) |> ignore
          })
        })
        t.draw()
        let outside = if pane { 16.0 } else { 12.0 }
        let side = if look is Narrow { 8.0 } else { 12.0 }
        let top = if !first { 0.0 } else if look is Narrow { 2.0 } else { 12.0 }
        let foot = if look is Narrow { 6.0 } else { 10.0 }
        let w = 320.0 - 2.0 * (outside + side)
        assert_eq(rows_head_rect(0x996633FFL), (outside + side, top, w, 20.0))
        assert_eq(rows_head_rect(0x667799FFL), (outside + side, top + 26.0, w, 10.0))
        assert_eq(rows_head_rect(0x773399FFL), (outside, top + 36.0 + foot, 20.0, 5.0))
      }
    }
  }
}

///|
test "a list head follows a page changing arrangement and resizes without remaking its child within one arrangement" {
  let width = @signals.signal(390.0)
  let made = Ref(0)
  let dropped = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=200.0)
  @ui.set_view_app(fn(root) {
    root.pick(fn() { look_for(width.get()) }, fn(page, look) {
      look_lent(page, look)
      rows_head_node(page, first=fn() { true }, fn(head) {
        made.val += 1
        head.owns(fn() { dropped.val += 1 }) |> ignore
        head.box(fn(line) { line.height(Is(Some(20.0))).ground(Is(0x996633FFL)) |> ignore }) |> ignore
      })
    })
  })
  t.draw()
  assert_eq(rows_head_rect(0x996633FFL), (8.0, 2.0, 374.0, 20.0))
  width.set(800.0)
  t.resize(800.0, 200.0)
  assert_eq(rows_head_rect(0x996633FFL), (12.0, 12.0, 776.0, 20.0))
  assert_eq((made.val, dropped.val), (2, 1))
  width.set(700.0)
  t.resize(700.0, 200.0)
  assert_eq(rows_head_rect(0x996633FFL), (12.0, 12.0, 676.0, 20.0))
  assert_eq((made.val, dropped.val), (2, 1))
}

///|
test "a list head keeps its live child and focus through updates, passes touch and accessible and keyboard presses, and lets it go" {
  let present = @signals.signal(true)
  let first = @signals.signal(false)
  let words = @signals.signal("Open")
  let made = Ref(0)
  let dropped = Ref(0)
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=320.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.show(fn() { present.get() }, fn(room) {
      rows_head_node(room, first=fn() { first.get() }, fn(head) {
        made.val += 1
        head.box(fn(button) {
          button.height(Is(Some(44.0))).ground(Is(0x996633FFL)).says(Is(Some(@view.said(Button, label="Open")))) |> ignore
          presses_node(button, fn() { presses.val += 1 })
          button.owns(fn() { dropped.val += 1 }) |> ignore
          button.box(fn(text) { text.words(By(fn() { words.get() })) |> ignore }) |> ignore
        })
        |> ignore
      })
    })
  })
  t.draw()
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Open"))
  t.act(Button, Focus, label="Open")
  words.set("Updated")
  first.set(true)
  t.draw()
  assert_eq((made.val, dropped.val, t.focused().map(fn(s) { s.label }), t.find("Updated") is Some(_)), (1, 0, Some("Open"), true))
  assert_eq(rows_head_rect(0x996633FFL).1, 2.0)
  t.enter()
  t.key(@ui.key_space)
  t.act(Button, Activate, label="Open")
  t.tap(20.0, 20.0)
  assert_eq(presses.val, 4)
  present.set(false)
  t.draw()
  assert_eq((made.val, dropped.val, t.focused() is None), (1, 1, true))
  present.set(true)
  t.draw()
  assert_eq((made.val, dropped.val), (2, 1))
}
