// What a group lends its rows and their descendants, made now or later.

///|
test "a group's list context belongs to its card, reaches late descendants, and goes with it" {
  for look in [Narrow, Wide] {
    for card in [false, true] {
      for pane in [false, true] {
        let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0)
        let shown = @signals.signal(false)
        let later = @signals.signal(false)
        let seen : Array[(Look, Bool, Bool)] = []
        let held : Ref[@view.View?] = Ref(None)
        @ui.set_view_app(fn(root) {
          root.box(fn(page) {
            page.lends(part_at, { look, section: true, list: false }).lends(pane_lent, pane) |> ignore
            let at = part_of(page)
            seen.push((at.look, at.section, at.list))
            page.show(fn() { shown.get() }, fn(slot) {
              group_node(slot, card~, fn(g) {
                held.val = Some(g)
                let at = part_of(g)
                seen.push((at.look, at.section, at.list))
                g.show(fn() { later.get() }, fn(s) {
                  s.box(fn(child) {
                    let at = part_of(child)
                    seen.push((at.look, at.section, at.list))
                  })
                  |> ignore
                })
              })
            })
            page.box(fn(sibling) {
              let at = part_of(sibling)
              seen.push((at.look, at.section, at.list))
            })
            |> ignore
          })
          |> ignore
        })
        t.draw()
        assert_true(seen == [(look, true, false), (look, true, false)])
        shown.set(true)
        t.draw()
        let listed = if look is Narrow { true } else { !card }
        assert_true(seen == [(look, true, false), (look, true, false), (look, true, listed)])
        later.set(true)
        t.draw()
        assert_true(seen == [(look, true, false), (look, true, false), (look, true, listed), (look, true, listed)])
        let old = held.val.unwrap()
        shown.set(false)
        t.draw()
        assert_false(old.alive())
        shown.set(true)
        t.draw()
        assert_true(seen == [
          (look, true, false), (look, true, false), (look, true, listed), (look, true, listed),
          (look, true, listed), (look, true, listed),
        ])
      }
    }
  }
}

///|
test "nested groups lend the nearest card's context without changing their siblings" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0)
    let seen : Array[Bool] = []
    @ui.set_view_app(fn(root) {
      root.box(fn(page) {
        page.lends(part_at, { look, section: true, list: false }) |> ignore
        group_node(page, fn(outer) {
          seen.push(part_of(outer).list)
          group_node(outer, card=true, fn(inner) { seen.push(part_of(inner).list) })
          outer.box(fn(sibling) { seen.push(part_of(sibling).list) }) |> ignore
        })
        page.box(fn(sibling) { seen.push(part_of(sibling).list) }) |> ignore
      })
      |> ignore
    })
    t.draw()
    assert_true(seen == [true, look is Narrow, true, false])
  }
}

///|
test "a page's groups keep their list context when its width changes and rows are shown later" {
  let t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=700.0)
  let width = @signals.signal(900.0)
  let shown = @signals.signal(false)
  let outside : Array[(Look, Bool)] = []
  let groups : Array[(Look, Bool)] = []
  let later : Array[(Look, Bool)] = []
  @ui.set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(Is(Some(700.0))) |> ignore
      page_node(page, fn() { "Title" }, fn() { ["one"] }, fn(block, _) {
        let at = part_of(block)
        outside.push((at.look, at.list))
        group_node(block, fn(g) {
          let at = part_of(g)
          groups.push((at.look, at.list))
          g.show(fn() { shown.get() }, fn(row) {
            let at = part_of(row)
            later.push((at.look, at.list))
          })
        })
      }, on_back=fn() {  }, width=fn() { width.get() })
    })
    |> ignore
  })
  t.draw()
  assert_true(outside == [(Wide, false)])
  assert_true(groups == [(Wide, true)])
  width.set(700.0)
  t.draw()
  assert_true(groups == [(Wide, true)])
  shown.set(true)
  t.draw()
  assert_true(later == [(Wide, true)])
  width.set(500.0)
  t.draw()
  assert_true(outside == [(Wide, false), (Narrow, false)])
  assert_true(groups == [(Wide, true), (Narrow, true)])
  assert_true(later == [(Wide, true), (Narrow, true)])
  width.set(900.0)
  t.draw()
  assert_true(outside == [(Wide, false), (Narrow, false), (Wide, false)])
  assert_true(groups == [(Wide, true), (Narrow, true), (Wide, true)])
  assert_true(later == [(Wide, true), (Narrow, true), (Wide, true)])
}

///|
test "a presented panel's group is a panel card at either width and with either card argument" {
  for dark in [false, true] {
    for look in [Narrow, Wide] {
      for card in [false, true] {
        // A centred dialog, a tall sheet whose column starts at the edge, and a panel with no column insets.
        for (sides, words, x) in [(24.0, 0.0, -8.0), (0.0, 24.0, 16.0), (0.0, 0.0, 0.0)] {
          let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0, dark~)
          let held : Ref[@view.View?] = Ref(None)
          @ui.set_view_app(fn(root) {
            root.box(fn(page) {
              page.width(Is(Some(300.0))).lends(part_at, { look, section: false, list: false }) |> ignore
              panel_rows_lent(page, fn() { { sides_in: sides, rows_out: 0.0, words_in: words, small: false } })
              group_node(page, card~, fn(g) {
                held.val = Some(g)
                g.box(fn(row) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
              })
            }) |> ignore
          })
          t.draw()
          let group = held.val.unwrap()
          assert_true(part_of(group).list)
          assert_eq(group.rect(), (x, 0.0, 300.0 - 2.0 * x, 56.0), msg="\{look}, card \{card}, dark \{dark}")
          let drawn = @ui.view_tree().unwrap().drawn_of(group.id()).unwrap()
          assert_eq(drawn.radius, card_corner)
          assert_eq(drawn.ground, @ui.tree_theme().color(A(Fg, O5)))
          assert_true(drawn.clips)
        }
      }
    }
  }
}

///|
test "a panel group's card follows the column without remaking its rows" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=200.0)
  let context = @signals.signal(PanelRowContext::{ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
  let held : Ref[@view.View?] = Ref(None)
  let made = Ref(0)
  @ui.set_view_app(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(200.0))).lends(part_at, { look: Wide, section: false, list: false }) |> ignore
      panel_rows_lent(page, fn() { context.get() })
      group_node(page, card=true, fn(g) {
        held.val = Some(g)
        made.val += 1
        g.box(fn(row) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  let card = held.val.unwrap()
  assert_true(part_of(card).list)
  assert_eq(card.rect(), (-8.0, 0.0, 216.0, 56.0))
  context.set({ sides_in: 16.0, rows_out: 8.0, words_in: 8.0, small: false })
  t.draw()
  assert_true(card.alive())
  assert_eq(card.rect(), (0.0, 0.0, 200.0, 56.0))
  context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
  t.draw()
  assert_true(card.alive())
  assert_eq(card.rect(), (16.0, 0.0, 168.0, 56.0))
  assert_eq(made.val, 1)
  let tree = @ui.view_tree().unwrap()
  let drawn = tree.drawn_of(card.id()).unwrap()
  assert_eq(drawn.radius, card_corner)
  assert_eq(drawn.ground, @ui.tree_theme().color(A(Fg, O5)))
  assert_true(drawn.clips)
}

///|
test "a group in nested panel card rooms follows the nearest room's card line" {
  for look in [Narrow, Wide] {
    let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0)
    let context = @signals.signal(PanelRowContext::{ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
    let held : Ref[@view.View?] = Ref(None)
    let made = Ref(0)
    @ui.set_view_app(fn(root) {
      root.box(fn(body) {
        body.width(Is(Some(240.0))).padding(Is((20.0, 0.0, 20.0, 0.0))).lends(part_at, { look, section: false, list: false }) |> ignore
        panel_rows_lent(body, fn() { context.get() })
        panel_card_room_node(body, fn(room) {
          panel_card_room_node(room, fn(inner) {
            group_node(inner, card=true, fn(g) {
              held.val = Some(g)
              made.val += 1
              g.box(fn(row) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
            })
          }) |> ignore
        }) |> ignore
      }) |> ignore
    })
    t.draw()
    let card = held.val.unwrap()
    assert_true(part_of(card).list)
    assert_eq((card.rect().0, card.rect().2), (12.0, 216.0))
    context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
    t.draw()
    assert_true(card.alive())
    assert_eq((card.rect().0, card.rect().2), (36.0, 168.0))
    context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false })
    t.draw()
    assert_true(card.alive())
    assert_eq((card.rect().0, card.rect().2), (20.0, 200.0))
    assert_eq(made.val, 1)
  }
}

///|
test "a small popover keeps the page group's card argument behavior" {
  for look in [Narrow, Wide] {
    for card in [false, true] {
      let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0)
      let held : Ref[@view.View?] = Ref(None)
      @ui.set_view_app(fn(root) {
        root.box(fn(body) {
          body.lends(part_at, { look, section: false, list: false }) |> ignore
          panel_rows_lent(body, fn() { { sides_in: panel_pad, rows_out: 0.0, words_in: text_in, small: true } })
          group_node(body, card~, fn(g) { held.val = Some(g) })
        }) |> ignore
      })
      t.draw()
      assert_eq(part_of(held.val.unwrap()).list, if look is Narrow { true } else { !card })
    }
  }
}

///|
test "a new presenter body lends the group its own card context when the panel kind changes" {
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  let small = @signals.signal(false)
  let seen : Array[Bool] = []
  let held : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    root.pick(fn() { small.get() }, fn(body, kind) {
      body.lends(part_at, { look: Wide, section: false, list: false }) |> ignore
      panel_rows_lent(body, fn() { { sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: kind } })
      group_node(body, card=true, fn(g) {
        held.val = Some(g)
        seen.push(part_of(g).list)
      })
    })
  })
  t.draw()
  let old = held.val.unwrap()
  assert_true(seen == [true])
  small.set(true)
  t.draw()
  assert_false(old.alive())
  assert_true(seen == [true, false])
  small.set(false)
  t.draw()
  assert_true(seen == [true, false, true])
}
