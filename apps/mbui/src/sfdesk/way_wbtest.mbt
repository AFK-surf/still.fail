// A way to where something is (way.mbt) short of room: those between leave it for its …, nothing scrolled or wrapped.

///|
test "a way short of room: the first and the last whole, those between leaving from the one after the first, a … offering them in their order; picked there, gone to" {
  let steps = ["Home", "Projects", "Reports", "Quarterly", "Drafts", "Final notes"]
  let went : Array[Int] = []
  @sf.presenters_reset()
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=way_test_room, fn() { @sf.way_line(c, "way", steps, narrow_way(), fn(i) { went.push(i) }) }) |> ignore
        @sf.presented(c)
      })
    },
    w=600.0,
    h=700.0,
    platform=2,
  )
  t.draw()
  // (room for all: each whole, no …)
  for s in steps {
    assert_eq(t.lines_of(s), [s], msg=s)
  }
  assert_true(way_left(t, -1))
  t.resize(280.0, 700.0)
  t.draw()
  let shown = steps.mapi(fn(i, _) { !way_left(t, i) })
  assert_true(shown[0] && shown[5], msg="\{shown}")
  assert_eq(t.lines_of("Home"), ["Home"])
  assert_eq(t.lines_of("Final notes"), ["Final notes"])
  // (some left, the one after the first first: those still there the last ones between)
  assert_true(!shown[1], msg="\{shown}")
  for i in 1..<4 {
    assert_true(!shown[i] || shown[i + 1], msg="\{shown}")
  }
  // in a line, in their order, all in the room (16 in either side)
  let (mx, _, mw, _) = t.rect_of(@sf.way_more).unwrap()
  let (hx, _, hw, _) = t.rect_of("Home").unwrap()
  let (lx, _, lw, _) = t.rect_of("Final notes").unwrap()
  assert_true(hx >= 16.0 && hx + hw <= mx && mx + mw <= lx && lx + lw <= 264.5, msg="\{hx} \{mx} \{lx} \{lw}")
  assert_eq(t.squeeze_faults(), [])
  // the …: those that left, in their order; one picked, gone to
  t.tap_text(@sf.way_more)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  let left = [1, 2, 3, 4].filter(fn(i) { !shown[i] })
  let ys = left.map(fn(i) { t.find_last(steps[i]).unwrap().1 })
  for k in 1..<ys.length() {
    assert_true(ys[k - 1] < ys[k], msg="\{ys}")
  }
  let (px, py) = t.find_last("Projects").unwrap()
  t.tap(px, py)
  assert_eq(went, [1])
}

///|
test "a way with no room even for its first and last: all but the last left for the …, only the last's words cut short, nothing over another" {
  let steps = ["Home", "Projects", "Reports", "A folder with a rather long name"]
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        c.box(style=way_test_room, fn() { @sf.way_line(c, "way", steps, narrow_way(), fn(_) {  }) }) |> ignore
      })
    },
    w=220.0,
    h=400.0,
    platform=2,
  )
  t.draw()
  assert_true(way_left(t, 0) && way_left(t, 1) && way_left(t, 2))
  assert_true(!way_left(t, -1))
  let last = t.lines_of("A folder")
  assert_eq(last.length(), 1)
  assert_true(last[0].has_suffix("…"), msg="\{last}")
  let (mx, _, mw, _) = t.rect_of(@sf.way_more).unwrap()
  let (lx, _, lw, _) = t.rect_of("A folder").unwrap()
  assert_true(mx + mw <= lx && lx + lw <= 184.5, msg="\{mx} \{lx} \{lw}")
  assert_eq(t.squeeze_faults(), [])
  // given the room: the first back, whole, before those between
  t.resize(600.0, 400.0)
  t.draw()
  assert_true(!way_left(t, 0) && way_left(t, -1))
  assert_eq(t.lines_of("A folder with a rather long name"), ["A folder with a rather long name"])
}

///|
test "a way of ancestors can open its last visible step when the current place is named separately" {
  let went : Array[Int] = []
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      c.box(style=way_test_room, fn() {
        @sf.way_line(c, "way", ["Home", "Projects"], narrow_way(), fn(i) { went.push(i) }, last_link=true)
      }) |> ignore
    })
  }, w=600.0, h=400.0, platform=2)
  t.draw()
  t.tap_text("Projects")
  assert_eq(went, [1])
}

///|
/// Whether the way left its `i`th step out (way_line's slots, as laid out last; -1 its …).
fn way_left(t : @ui.Tester, i : Int) -> Bool {
  let c = t.ctx()
  c.left_out(c.id("way/slot/\{i}"))
}

///|
/// Where the way is: a phone's page, 16 in from its sides.
// kept across runs: a value (no field of it changes)
let way_test_room : @ui.Style = @ui.css("w=Full px=S4")
