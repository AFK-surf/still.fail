// A long list's group made a row at a time: its geometry, changing ends and the row's own interaction.

///|
/// The row bodies and the marker after them in a page's long-list room.
fn group_row_node_geometry(look : Look, pane : Bool, count : Int) -> Array[(Double, Double, Double, Double)] {
  let ink = 0x987654FFL
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=600.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      look_lent(page, look)
      page.lends(pane_lent, pane) |> ignore
      let rows = fn(room : @view.View) {
        for i in 0..<count {
          group_row_node(room, fn() { i == 0 }, fn() { i == count - 1 }, fn(row) {
            row.height(Is(Some(40.0))).ground(Is(ink)) |> ignore
          })
        }
        room.box(fn(after) { after.height(Is(Some(4.0))).ground(Is(ink)) |> ignore }) |> ignore
      }
      if look is Narrow { page_block(page, rows) } else { rows(page) }
    })
    |> ignore
  })
  t.draw()
  t.drawn_rects().filter(fn(r) { r.4 == ink }).map(fn(r) { (r.0, r.1, r.2, r.3) })
}

///|
test "group row node: one and several rows keep the page room, card insets and foot in narrow and wide pages and panes" {
  for look in [Narrow, Wide] {
    for pane in [false, true] {
      for count in [1, 3] {
        let side = if look is Narrow { if pane { panel_card_in } else { pg_room_in } } else { 0.0 }
        let pad = if look is Narrow { list_pad } else { 0.0 }
        let want = Array::makei(count, fn(i) { (side + pad, pad + i.to_double() * 40.0, 390.0 - 2.0 * (side + pad), 40.0) })
        want.push((side, count.to_double() * 40.0 + 2.0 * pad + (if look is Narrow { 10.0 } else { 0.0 }), 390.0 - 2.0 * side, 4.0))
        assert_eq(group_row_node_geometry(look, pane, count), want, msg="look \{look}, pane \{pane}, rows \{count}")
      }
    }
  }
}

///|
test "group row node: first and last follow the list without remaking or unfocusing its body" {
  let first = @signals.signal(false)
  let last = @signals.signal(false)
  let made = Ref(0)
  let pressed = Ref(0)
  let row : Ref[@view.View?] = Ref(None)
  let card : Ref[@view.View?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      group_row_node(page, fn() { first.get() }, fn() { last.get() }, fn(body) {
        made.val += 1
        row.val = Some(body)
        card.val = body.parent()
        body.height(Is(Some(40.0))).says(Is(Some(@view.said(Button, label="File")))) |> ignore
        presses_node(body, fn() { pressed.val += 1 })
      })
      page.box(fn(after) { after.height(Is(Some(4.0))).ground(Is(0x987654FFL)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let radius = @ui.tree_theme().corner(Xl2)
  let seen = fn() {
    let d = tree.drawn_of(card.val.unwrap().id()).unwrap()
    let r = tree.drawn_of(row.val.unwrap().id()).unwrap()
    let after = tree.drawn().filter(fn(x) { x.ground == 0x987654FFL })[0]
    (d.corners, r.x, r.y, after.y)
  }
  assert_eq(seen(), (Some((0.0, 0.0, 0.0, 0.0)), list_pad, 0.0, 40.0))
  t.act(Button, Focus, label="File")
  first.set(true)
  last.set(true)
  t.draw()
  assert_eq(seen(), (Some((radius, radius, radius, radius)), list_pad, list_pad, 40.0 + 2.0 * list_pad + 10.0))
  assert_eq((made.val, t.focused().map(fn(s) { s.label })), (1, Some("File")))
  t.enter()
  t.act(Button, Activate, label="File")
  t.tap(20.0, 20.0)
  assert_eq(pressed.val, 3)
  first.set(false)
  t.draw()
  assert_eq(seen(), (Some((0.0, 0.0, radius, radius)), list_pad, 0.0, 40.0 + list_pad + 10.0))
  last.set(false)
  t.draw()
  assert_eq(seen(), (Some((0.0, 0.0, 0.0, 0.0)), list_pad, 0.0, 40.0))
  assert_eq(made.val, 1)
}

///|
test "group row node: a windowed list holds only visible rows and disposes each body with its row" {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(200, fn(i) { i }), same=fn(a, b) { a == b })
  let live : Map[Int, Bool] = Map([])
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(list) {
      list.height(Is(Some(100.0))) |> ignore
      list.scrolls_window(scroll, fn() { keys.get() }, est=40.0, from_end=true, fn(slot, k) {
        group_row_node(slot, fn() { keys.get().get(0) == Some(k) }, fn() { keys.get().last() == Some(k) }, fn(body) {
          live[k] = true
          body.height(Is(Some(40.0))).owns(fn() { live.remove(k) }) |> ignore
        })
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_true(live.contains(199))
  assert_false(live.contains(0))
  assert_true(live.length() < 20)
  keys.set(Array::makei(199, fn(i) { i }))
  t.draw()
  assert_false(live.contains(199))
  keys.set(Array::makei(200, fn(i) { i }))
  t.draw()
  assert_true(live.contains(199))
}

///|
test "group row node: the departing last row and its replacement each keep their end while a list closes" {
  let items = @signals.signal([("a", true, false), ("b", false, true)], same=fn(a, b) { a == b })
  let cards : Map[String, @view.View] = {}
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=300.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(list) {
      let rows = @ui.ListRows::new().in_node(list, fn() { items.get() }, fn(x) { x.0 }, fn(_) { "" })
      list.height(Is(Some(200.0))).scrolls_window(@view.Scroll::list(), fn() { (rows.read)().1 }, est=50.0,
        room=rows.room, fn(slot, k) {
          let item = fn() { (rows.read)().0.iter().find_first(fn(x) { x.0 == k }).unwrap() }
          group_row_node(slot, fn() { item().1 }, fn() { item().2 }, fn(body) {
            cards[k] = body.parent().unwrap()
            body.height(Is(Some(40.0))).owns(fn() { cards.remove(k) }) |> ignore
          })
        }) |> ignore
    }) |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let radius = @ui.tree_theme().corner(Xl2)
  let ends = fn(k : String) { tree.drawn_of(cards[k].id()).unwrap().corners }
  assert_eq(ends("a"), Some((radius, radius, 0.0, 0.0)))
  assert_eq(ends("b"), Some((0.0, 0.0, radius, radius)))
  items.set([("a", true, true)])
  t.draw()
  assert_eq(ends("a"), Some((radius, radius, radius, radius)))
  assert_eq(ends("b"), Some((0.0, 0.0, radius, radius)))
  t.run_for(@ui.row_size_ms)
  assert_false(cards.contains("b"))
}
