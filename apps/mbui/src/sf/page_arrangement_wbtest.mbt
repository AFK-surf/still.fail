// A page's arrangement may be supplied by its frame, independently of the room it is given. Its panel context must
// still reach blocks made later by the windowed list.

///|
test "a page's dynamic arrangement override follows the frame, or its width when none is said" {
  let t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=700.0)
  let width = @signals.signal(500.0)
  let chosen : @signals.Signal[Look?] = @signals.signal(None)
  let shown = @signals.signal(false)
  let made : Array[Look] = []
  let later : Array[Look] = []
  let room : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    root.box(fn(p) {
      p.width(By(fn() { Some(width.get()) })).height(Is(Some(700.0))).lends(pane_lent, true) |> ignore
      page_node(p, fn() { "Title" }, fn() { ["block"] }, fn(b, _) {
        made.push(look_node(b))
        b.box(fn(content) {
          content.height(Is(Some(10.0))) |> ignore
          room.val = Some(content)
        }) |> ignore
        b.show(fn() { shown.get() }, fn(s) { later.push(look_node(s)) })
      }, on_back=fn() {  }, width=fn() { width.get() }, look=fn() { chosen.get() })
    })
    |> ignore
  })
  t.draw()
  assert_true(made == [Narrow])
  // Width changes within an arrangement keep its nodes; the panel's actual width is still their room.
  width.set(520.0)
  t.draw()
  assert_true(made == [Narrow])
  let (x, _, w, _) = room.val.unwrap().rect()
  assert_eq((x, w), (panel_card_in, 520.0 - 2.0 * panel_card_in))
  // A wide frame may be used in that narrow box without pretending the box is 640 wide.
  chosen.set(Some(Wide))
  t.draw()
  assert_true(made == [Narrow, Wide])
  let (x, _, w, _) = room.val.unwrap().rect()
  assert_eq((x, w), (panel_card_in, 520.0 - 2.0 * panel_card_in))
  shown.set(true)
  t.draw()
  assert_true(later == [Wide])
  // Hand control back to width while it still says Wide: no rebuilding. Crossing the boundary rebuilds once.
  width.set(700.0)
  chosen.set(None)
  t.draw()
  assert_true(made == [Narrow, Wide])
  width.set(500.0)
  t.draw()
  assert_true(made == [Narrow, Wide, Narrow])
  assert_true(later == [Wide, Narrow])
}

///|
/// The horizontal room given to a block made later in a 400-wide page, with or without a rounded pane.
fn arrangement_block_room(pane : Bool, look : Look) -> (Double, Double, Bool) {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
  let keys : @signals.Signal[Array[String]] = @signals.signal([])
  let room : Ref[@view.View?] = Ref(None)
  let in_pane = Ref(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(p) {
      p.height(Is(Some(700.0))) |> ignore
      if pane { p.lends(pane_lent, true) |> ignore }
      page_node(p, fn() { "Title" }, fn() { keys.get() }, fn(b, _) {
        b.box(fn(content) {
          content.height(Is(Some(10.0))) |> ignore
          room.val = Some(content)
        }) |> ignore
        in_pane.val = in_pane_node(b)
      }, on_back=fn() {  }, width=fn() { 400.0 }, look=fn() { Some(look) })
    })
    |> ignore
  })
  t.draw()
  keys.set(["later"])
  t.draw()
  let (x, _, w, _) = room.val.unwrap().rect()
  (x, w, in_pane.val)
}

///|
test "a page's later blocks retain pane padding for each arrangement, and a plain side pane keeps its own padding" {
  assert_eq(arrangement_block_room(true, Narrow), (panel_card_in, 400.0 - 2.0 * panel_card_in, true))
  assert_eq(arrangement_block_room(true, Wide), (panel_card_in, 400.0 - 2.0 * panel_card_in, true))
  assert_eq(arrangement_block_room(false, Narrow), (pg_room_in, 400.0 - 2.0 * pg_room_in, false))
  assert_eq(arrangement_block_room(false, Wide), (desk_lane_in + desk_column_in, 400.0 - 2.0 * (desk_lane_in + desk_column_in), false))
}

///|
test "a narrow page's lead is chrome under a pane bar, and keeps its ordinary room elsewhere" {
  for pane in [false, true] {
    let named = @signals.signal(true)
    let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=700.0)
    @ui.set_view_app(fn(root) {
      root.box(fn(p) {
        p.height(Is(Some(700.0))) |> ignore
        if pane { p.lends(pane_lent, true) |> ignore }
        page_node(p, fn() { "Title" }, fn() { ["block"] }, fn(b, _) {
          b.height(Is(Some(40.0))) |> ignore
        }, on_back=fn() {  }, lead=fn() { "Page lead" }, width=fn() { 400.0 },
          frame=fn() { { ..no_frame, named: named.get() } })
      }) |> ignore
    })
    t.draw()
    let side = if pane { panel_card_in } else { pg_room_in }
    assert_eq(t.rect_of("Page lead").unwrap().0, pg_lead_x + (if pane { 0.0 } else { side }))
    named.set(false)
    t.draw()
    assert_eq(t.rect_of("Page lead").unwrap().0, pg_lead_x + side)
    named.set(true)
    t.draw()
    assert_eq(t.rect_of("Page lead").unwrap().0, pg_lead_x + (if pane { 0.0 } else { side }))
  }
}
