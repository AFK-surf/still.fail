// The retained panel body's row geometry agrees with the old body's row_line and follows the body's lifetime.

///|
test "panel row geometry: the old row_line's margins, padding and inner corner on both widths and in cards" {
  let tree = @view.Tree::new(fn(_root) {  }, time=fn() { 0.0 })
  let root = tree.root()
  let current = @signals.signal(PanelRowContext::{ sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false })
  panel_rows_lent(root, fn() { current.get() })
  // A page, anchored panel, unanchored sheet/dialog, anchored sheet and tall sheet, plus reach larger than a row's.
  let contexts : Array[PanelRowContext] = [
    { sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false },
    { sides_in: panel_pad, rows_out: 0.0, words_in: text_in, small: true },
    { sides_in: panel_words, rows_out: panel_words - panel_card_in, words_in: 0.0, small: false },
    { sides_in: panel_card_in, rows_out: 0.0, words_in: panel_words - panel_card_in, small: false },
    { sides_in: 0.0, rows_out: 0.0, words_in: panel_words, small: false },
    { sides_in: 46.0, rows_out: 30.0, words_in: 0.0, small: false },
    { sides_in: 24.0, rows_out: 8.0, words_in: 4.0, small: false },
  ]
  for at in contexts {
    current.set(at)
    rows_out.val = at.rows_out
    words_in_now.val = at.words_in
    small_panel_now.val = at.small
    for narrow in [true, false] {
      for card in [true, false] {
        in_card.val = if card { 1 } else { 0 }
        let old = row_line(narrow).base
        let line = panel_row_layout(root, narrow, card)
        let expected_margin = if line.out > 0.0 { Some(room(-line.out)) } else { None }
        let expected_pad = line.padding.map(fn(p) { room(p) })
        assert_true(old.mx == expected_margin, msg="margin \{at}, narrow \{narrow}, card \{card}: \{line}")
        assert_true(old.px == expected_pad, msg="padding \{at}, narrow \{narrow}, card \{card}: \{line}")
        assert_true((old.radius == Some(Inner)) == line.inner, msg="corner \{at}, narrow \{narrow}, card \{card}: \{line}")
      }
    }
  }
  rows_out.val = 0.0
  words_in_now.val = 0.0
  small_panel_now.val = false
  in_card.val = 0
  tree.dispose()
}

///|
test "panel row geometry: inherited late, updated on the same node, shadowed by a nested panel and released" {
  let context = @signals.signal(PanelRowContext::{ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
  let show = @signals.signal(false)
  let body : Ref[@view.View?] = Ref(None)
  let row : Ref[@view.View?] = Ref(None)
  let words : Ref[@view.View?] = Ref(None)
  let side_probe : Ref[@view.View?] = Ref(None)
  let late : Ref[@view.View?] = Ref(None)
  let nested : Ref[@view.View?] = Ref(None)
  let outside : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(b) {
      body.val = Some(b)
      b.width(Is(Some(240.0))).padding(Is((20.0, 0.0, 20.0, 0.0))) |> ignore
      panel_rows_lent(b, fn() { context.get() })
      b.box(fn(r) {
        row.val = Some(r)
        r.height(Is(Some(40.0)))
        .margin(By(fn() {
          let out = panel_row_layout(r, false, false).out
          (-out, 0.0, -out, 0.0)
        }))
        .padding(By(fn() {
          let p = panel_row_layout(r, false, false).padding.unwrap_or(12.0)
          (p, 0.0, p, 0.0)
        })) |> ignore
        r.box(fn(w) {
          words.val = Some(w)
          w.width(Is(Some(8.0))).height(Is(Some(10.0))) |> ignore
        }) |> ignore
      }) |> ignore
      b.box(fn(probe) {
        side_probe.val = Some(probe)
        probe.width(By(fn() { Some(panel_row_context(probe).sides_in) })).height(Is(Some(1.0))) |> ignore
      }) |> ignore
      b.show(fn() { show.get() }, fn(later) {
        later.box(fn(child) { late.val = Some(child) }) |> ignore
        later.box(fn(p) {
          panel_rows_lent(p, fn() { { sides_in: panel_pad, rows_out: 0.0, words_in: text_in, small: true } })
          p.box(fn(child) { nested.val = Some(child) }) |> ignore
        }) |> ignore
      })
    }) |> ignore
    root.box(fn(v) { outside.val = Some(v) }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  let r = row.val.unwrap()
  let original_id = r.id()
  let initial = r.rect()
  assert_eq((initial.0, initial.2), (12.0, 216.0))
  assert_eq(words.val.unwrap().rect().0, 20.0)
  assert_eq(side_probe.val.unwrap().rect().2, 24.0)
  assert_true(panel_row_layout(outside.val.unwrap(), false, false) == { out: 0.0, padding: None, inner: false })
  assert_true(panel_row_context(outside.val.unwrap()) == { sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false })
  assert_true(in_panel_node(r))
  assert_true(!in_panel_node(outside.val.unwrap()))
  context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
  show.set(true)
  tree.frame(300.0, 300.0) |> ignore
  let after = r.rect()
  assert_eq(r.id(), original_id)
  assert_eq((after.0, after.2), (20.0, 200.0))
  assert_eq(words.val.unwrap().rect().0, 44.0)
  assert_eq(side_probe.val.unwrap().rect().2, 0.0)
  assert_true(panel_row_context(r) == { sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
  assert_true(panel_row_context(late.val.unwrap()) == { sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
  assert_true(panel_row_layout(r, false, false) == { out: 0.0, padding: Some(24.0), inner: false })
  let child = nested.val.unwrap()
  assert_true(panel_row_layout(child, true, false) == { out: 0.0, padding: Some(text_in), inner: true })
  context.set({ sides_in: panel_card_in, rows_out: 0.0, words_in: 24.0, small: false })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(side_probe.val.unwrap().rect().2, panel_card_in)
  assert_true(panel_row_layout(r, false, false) == { out: 0.0, padding: Some(24.0), inner: false })
  context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 0.0, small: false })
  tree.frame(300.0, 300.0) |> ignore
  assert_true(in_panel_node(r))
  assert_true(panel_row_context(r) == panel_row_context(outside.val.unwrap()))
  show.set(false)
  tree.frame(300.0, 300.0) |> ignore
  assert_true(!child.alive())
  assert_true(!late.val.unwrap().alive())
  tree.dispose()
  assert_true(panel_row_layout(body.val.unwrap(), false, false) == { out: 0.0, padding: None, inner: false })
  assert_true(!in_panel_node(body.val.unwrap()))
}

///|
test "panel card room: card line and inherited words follow the panel, with no reach outside or in a small panel" {
  let context = @signals.signal(PanelRowContext::{ sides_in: 24.0, rows_out: 8.0, words_in: 0.0, small: false })
  let room : Ref[@view.View?] = Ref(None)
  let child : Ref[@view.View?] = Ref(None)
  let nested_room : Ref[@view.View?] = Ref(None)
  let nested_child : Ref[@view.View?] = Ref(None)
  let page_child : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(body) {
      body.width(Is(Some(240.0))).padding(Is((20.0, 0.0, 20.0, 0.0))) |> ignore
      panel_rows_lent(body, fn() { context.get() })
      room.val = Some(panel_card_room_node(body, fn(card_room) {
        card_room.height(Is(Some(40.0))) |> ignore
        card_room.box(fn(c) { child.val = Some(c) }) |> ignore
        nested_room.val = Some(panel_card_room_node(card_room, fn(inner) {
          inner.box(fn(c) { nested_child.val = Some(c) }) |> ignore
        }))
      }))
    }) |> ignore
    panel_card_room_node(root, fn(r) { r.box(fn(c) { page_child.val = Some(c) }) |> ignore }) |> ignore
  }, time=fn() { 0.0 })
  tree.frame(300.0, 300.0) |> ignore
  let r = room.val.unwrap()
  let c = child.val.unwrap()
  let inner = nested_room.val.unwrap()
  let in_card = nested_child.val.unwrap()
  let id = r.id()
  assert_eq((r.rect().0, r.rect().2), (12.0, 216.0))
  assert_true(panel_row_context(c) == { sides_in: 16.0, rows_out: 8.0, words_in: 8.0, small: false })
  assert_eq((inner.rect().0, inner.rect().2), (12.0, 216.0))
  assert_true(panel_row_context(in_card) == panel_row_context(c))
  assert_true(page_child.val.unwrap().lent(panel_rows_at) is None)
  context.set({ sides_in: 0.0, rows_out: 0.0, words_in: 24.0, small: false })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq(r.id(), id)
  assert_eq((r.rect().0, r.rect().2), (36.0, 168.0))
  assert_true(panel_row_context(c) == { sides_in: 16.0, rows_out: 0.0, words_in: 8.0, small: false })
  assert_eq((inner.rect().0, inner.rect().2), (36.0, 168.0))
  assert_true(panel_row_context(in_card) == panel_row_context(c))
  context.set({ sides_in: 16.0, rows_out: 0.0, words_in: 16.0, small: true })
  tree.frame(300.0, 300.0) |> ignore
  assert_eq((r.rect().0, r.rect().2), (20.0, 200.0))
  assert_true(panel_row_context(c) == { sides_in: 16.0, rows_out: 0.0, words_in: 16.0, small: true })
  tree.dispose()
  assert_true(!c.alive())
  assert_true(!in_card.alive())
}
