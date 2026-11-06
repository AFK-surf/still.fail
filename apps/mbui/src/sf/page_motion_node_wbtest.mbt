// A page's business blocks use the same keyed row motion as a windowed list. Their values stay with a departing row
// and with the copy at a moved row's old place.

///|
fn motion_page(
  items : @signals.Signal[Array[(String, String)]],
  presses : Ref[Int],
  look? : Look = Narrow,
  pane? : Bool = false,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(p) {
      p.height(Is(Some(700.0))) |> ignore
      if pane { p.lends(pane_lent, true) |> ignore }
      page_node_items(p, fn() { "Title" }, fn() { items.get() }, fn(item) { item.0 }, fn(b, item) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(By(fn() { item().1 }))
          .says(By(fn() { Some(@view.said(Button, label=item().1)) })) |> ignore
          presses_node(row, fn() { presses.val += 1 })
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, look=fn() { Some(look) }, moves=true,
        continuity=fn(item) { item.0 != "waiting" })
    }) |> ignore
  })
  t.draw()
  t
}

///|
test "a page reports newly visible business keys while blocks move and leave" {
  let items = @signals.signal([("a", "Alpha"), ("b", "Beta"), ("c", "Old Gamma")])
  let look = @signals.signal(Narrow)
  let seen : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
  @ui.set_view_app(fn(root) {
    page_node_items(root, fn() { "Title" }, fn() { items.get() }, fn(item) { item.0 }, fn(b, item) {
      b.height(Is(Some(60.0))).words(By(fn() { item().1 })) |> ignore
    }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, moves=true, look=fn() { Some(look.get()) },
      seen=fn(keys) { seen.append(keys) })
  })
  t.draw()
  assert_true(seen.contains("a") && seen.contains("b") && seen.contains("c"))
  items.set([("c", "New Gamma"), ("a", "Alpha")])
  t.draw()
  t.run_for(@ui.row_size_ms / 4.0)
  // Both old-position and removed snapshots still show when the rebuilt list reports what it sees.
  assert_true(t.find("Old Gamma") is Some(_) && t.find("Beta") is Some(_))
  seen.clear()
  look.set(Wide)
  t.draw()
  assert_true(seen.contains("a") && seen.contains("c"))
  assert_true(seen.iter().all(fn(k) { k == "a" || k == "c" }))
}

///|
test "keyed page motion uses the actual room in both wide side panes" {
  for pane in [false, true] {
    let items = @signals.signal([("a", "Alpha"), ("b", "Beta")])
    let t = motion_page(items, Ref(0), look=Wide, pane~)
    let (_, before) = t.drawn_of("Beta").unwrap()
    items.set([("a", "Alpha"), ("phone", "Phone setup"), ("b", "Beta")])
    t.draw()
    t.run_for(@ui.row_size_ms / 2.0)
    let (_, halfway) = t.drawn_of("Beta").unwrap()
    t.run_for(@ui.row_size_ms)
    let (_, after) = t.drawn_of("Beta").unwrap()
    assert_true(before < halfway && halfway < after, msg="pane=\{pane}: \{before}, \{halfway}, \{after}")
    items.set([("a", "Alpha"), ("b", "Beta")])
    t.draw()
    t.run_for(@ui.row_size_ms / 2.0)
    assert_true(t.find("Phone setup") is Some(_))
  }
}

///|
test "a page's first reading and an unrelated replacement appear at once; later keyed changes keep exiting snapshots" {
  let items = @signals.signal([("waiting", "Waiting")])
  let presses = Ref(0)
  let t = motion_page(items, presses)
  items.set([("a", "Alpha"), ("b", "Beta")])
  t.draw()
  let (_, first) = t.drawn_of("Beta").unwrap()
  t.run_for(@ui.row_size_ms / 2.0)
  assert_eq(t.drawn_of("Beta").unwrap().1, first)
  // An item inserted in the same list opens at its place, making the one after it move down.
  items.set([("a", "Alpha"), ("phone", "Phone setup"), ("b", "Beta")])
  t.draw()
  let (_, before) = t.drawn_of("Beta").unwrap()
  t.run_for(@ui.row_size_ms / 2.0)
  let (_, half) = t.drawn_of("Beta").unwrap()
  t.run_for(@ui.row_size_ms)
  let (_, after) = t.drawn_of("Beta").unwrap()
  assert_true(before < half && half < after, msg="opening: \{before}, \{half}, \{after}")
  // The removed item's data no longer exists in `items`; its last value stays in its closing room and cannot be pressed.
  items.set([("a", "Alpha"), ("b", "Beta")])
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  assert_true(t.find("Phone setup") is Some(_))
  t.tap_text("Phone setup")
  assert_eq(presses.val, 0)
  t.run_for(@ui.row_size_ms)
  assert_true(t.find("Phone setup") is None)
  // Completely unrelated business keys are a new reading, not a transition from the old list.
  items.set([("c", "Gamma"), ("d", "Delta")])
  t.draw()
  let (_, replaced) = t.drawn_of("Delta").unwrap()
  t.run_for(@ui.row_size_ms / 2.0)
  assert_eq(t.drawn_of("Delta").unwrap().1, replaced)
  assert_true(t.find("Alpha") is None)
}

///|
test "a page's reordered block shows the old snapshot at its former place and the new value at its destination" {
  let items = @signals.signal([("a", "Alpha"), ("b", "Beta"), ("c", "Old Gamma")])
  let t = motion_page(items, Ref(0))
  items.set([("c", "New Gamma"), ("a", "Alpha"), ("b", "Beta")])
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  assert_true(t.find("Old Gamma") is Some(_))
  assert_true(t.find("New Gamma") is Some(_))
  t.run_for(@ui.row_size_ms)
  assert_true(t.find("Old Gamma") is None)
  assert_true(t.find("New Gamma") is Some(_))
}

///|
test "a departing first block keeps its inset while its successor gains the first inset" {
  let items = @signals.signal([("a", "Alpha"), ("b", "Beta")])
  let held : Ref[PageBlocks[(String, String)]?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(v) {
      v.height(Is(Some(700.0))) |> ignore
      held.val = Some(page_blocks(v, fn() { items.get() }, fn(it) { it.0 }, fn(_) { "" },
        animated=true, moves=true, continuity=fn(_) { true }))
    }) |> ignore
  })
  t.draw()
  let blocks = held.val.unwrap()
  assert_true((blocks.first)("a"))
  assert_false((blocks.first)("b"))
  items.set([("b", "Beta")])
  t.draw()
  t.run_for(@ui.row_size_ms / 2.0)
  assert_true((blocks.first)("a"))
  assert_true((blocks.first)("b"))
  t.run_for(@ui.row_size_ms)
  assert_false((blocks.first)("a"))
}

///|
test "a moving page block retains keyboard focus and a leaving copy is hidden from accessibility" {
  let items = @signals.signal([("a", "Alpha"), ("b", "Beta"), ("c", "Gamma")])
  let presses = Ref(0)
  let t = motion_page(items, presses)
  t.act(Button, Focus, label="Beta")
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Beta"))
  items.set([("b", "Beta"), ("a", "Alpha"), ("c", "Gamma")])
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Beta"))
  t.key(@ui.key_space)
  assert_eq(presses.val, 1)
  items.set([("a", "Alpha"), ("c", "Gamma")])
  t.draw()
  assert_true(t.all(Button, label="Beta").is_empty())
  t.key(@ui.key_space)
  assert_eq(presses.val, 1)
}

///|
/// The position halfway through a block's opening, drawn either at intermediate frames or directly at that moment.
fn page_motion_halfway(intermediate : Bool) -> Double {
  let items = @signals.signal([("a", "Alpha"), ("b", "Beta")])
  let t = motion_page(items, Ref(0))
  items.set([("a", "Alpha"), ("new", "New"), ("b", "Beta")])
  t.draw()
  let start = t.time()
  if intermediate { t.frame_at(start + @ui.row_size_ms / 4.0) }
  t.frame_at(start + @ui.row_size_ms / 2.0)
  t.drawn_of("Beta").unwrap().1
}

///|
test "a page's keyed motion at its cause time does not depend on intermediate frames" {
  assert_eq(page_motion_halfway(false), page_motion_halfway(true))
}
