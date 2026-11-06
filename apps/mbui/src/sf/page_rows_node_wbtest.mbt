// The page's room around each row of a windowed list (rows_room_node): its look and pane, row lifetime and input.

///|
test "rows_room_node: each arrangement and pane gives one row the page's room" {
  let cases : Array[(Look, Bool, Double, Double)] = [
    (Narrow, false, 12.0, 276.0),
    (Narrow, true, 16.0, 268.0),
    (Wide, false, 0.0, 300.0),
    (Wide, true, 0.0, 300.0),
  ]
  for (look, pane, left, width) in cases {
    let row : Ref[@view.View?] = Ref(None)
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(p) {
        p.width(Is(Some(300.0))) |> ignore
        look_lent(p, look)
        p.lends(pane_lent, pane) |> ignore
        rows_room_node(p, fn(room) {
          room.box(fn(content) {
            row.val = Some(content)
            content.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
      })
      |> ignore
    })
    tree.frame(300.0, 100.0) |> ignore
    assert_eq(row.val.unwrap().rect(), (left, 0.0, width, 40.0), msg="\{look}, pane \{pane}")
    tree.dispose()
  }
}

///|
test "rows_room_node: a page changing width or pane gives its new rows the new room" {
  let width = @signals.signal(300.0)
  let pane = @signals.signal(false)
  let row : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(p) {
      p.width(By(fn() { Some(width.get()) })) |> ignore
      p.pick(fn() { (look_for(width.get()), pane.get()) }, fn(page, arrangement) {
        look_lent(page, arrangement.0)
        page.lends(pane_lent, arrangement.1) |> ignore
        rows_room_node(page, fn(room) {
          room.box(fn(content) {
            row.val = Some(content)
            content.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
        })
      })
    })
    |> ignore
  })
  tree.frame(900.0, 100.0) |> ignore
  let original = row.val.unwrap()
  assert_eq(original.rect(), (12.0, 0.0, 276.0, 40.0))
  width.set(400.0)
  tree.frame(900.0, 100.0) |> ignore
  assert_true(original.alive())
  assert_eq(original.rect(), (12.0, 0.0, 376.0, 40.0))
  pane.set(true)
  tree.frame(900.0, 100.0) |> ignore
  assert_false(original.alive())
  assert_eq(row.val.unwrap().rect(), (16.0, 0.0, 368.0, 40.0))
  width.set(800.0)
  tree.frame(900.0, 100.0) |> ignore
  assert_eq(row.val.unwrap().rect(), (0.0, 0.0, 800.0, 40.0))
  width.set(300.0)
  pane.set(false)
  tree.frame(900.0, 100.0) |> ignore
  assert_eq(row.val.unwrap().rect(), (12.0, 0.0, 276.0, 40.0))
  tree.dispose()
}

///|
test "rows_room_node: windowed rows are made individually, inherit their page, and are let go when scrolled away" {
  for (look, pane, left, width) in [
    (Narrow, false, 12.0, 276.0),
    (Narrow, true, 16.0, 268.0),
    (Wide, false, 0.0, 300.0),
    (Wide, true, 0.0, 300.0),
  ] {
    let scroll = @view.Scroll::list()
    let live : Map[Int, @view.View] = Map([])
    let made : Array[Int] = []
    let released : Array[Int] = []
    let tree = @view.Tree::new(fn(root) {
      root.box(fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        look_lent(p, look)
        p.lends(pane_lent, pane) |> ignore
        p.scrolls_window(scroll, fn() { Array::makei(1000, fn(i) { i }) }, est=40.0, fn(slot, k) {
          rows_room_node(slot, fn(room) {
            room.box(fn(content) {
              made.push(k)
              live[k] = content
              content.height(Is(Some(40.0))).owns(fn() { live.remove(k); released.push(k) }) |> ignore
            })
            |> ignore
          })
        })
        |> ignore
      })
      |> ignore
    })
    tree.frame(300.0, 100.0) |> ignore
    assert_eq(made, [0, 1, 2])
    assert_eq(live[0].rect(), (left, 0.0, width, 40.0))
    tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 10.0) |> ignore
    tree.frame(300.0, 100.0) |> ignore
    let now = live.keys().collect()
    now.sort()
    released.sort()
    assert_eq(now, [2, 3, 4])
    assert_eq(released, [0, 1])
    assert_eq(live[3].rect(), (left, 20.0, width, 40.0))
    tree.dispose()
    assert_eq(live.keys().collect().length(), 0)
  }
}

///|
test "rows_room_node: touch, keyboard and accessibility reach a row; resizing within its look keeps a field focused" {
  for platform in [0, 2] {
    let width = @signals.signal(300.0)
    let presses = Ref(0)
    let field = @ui.Field::new()
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=300.0, platform~)
    @ui.set_view_app(fn(root) {
      root.box(fn(p) {
        p.width(By(fn() { Some(width.get()) })) |> ignore
        look_lent(p, Narrow)
        p.lends(pane_lent, true) |> ignore
        rows_room_node(p, fn(room) {
          button_node(room, fn() { "Open row" }, fn() { presses.val += 1 }) |> ignore
          input_node(room, field, placeholder="Rename row") |> ignore
        })
      })
      |> ignore
    })
    t.draw()
    let (x, y, w, h) = t.get(Button, label="Open row").rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.act(Button, Focus, label="Open row")
    t.enter()
    t.act(Button, Activate, label="Open row")
    assert_eq(presses.val, 3, msg="platform \{platform}")
    t.act(TextField, Focus, label="Rename row")
    t.type_text("name")
    width.set(360.0)
    t.draw()
    assert_eq((t.focused().map(fn(s) { s.label }), field.text()), (Some("Rename row"), "name"))
    t.type_text("d")
    assert_eq(field.text(), "named")
  }
}
