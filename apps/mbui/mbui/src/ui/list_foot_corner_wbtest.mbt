// What a page's list holds pinned in its foot (View::scrolls_window's `foot`: over the foot of what shows) stands where
// it shows as the list scrolls under it: the corner rule takes it as anything outside what scrolls, by the corner of
// what holds the list, not as scrolled with the list's rows (sizes steady's: sizes_steady_scroll_wbtest.mbt).

///|
let foot_corner_ink : Int64 = 0x3066CCFFL

///|
test "a page's list's foot in a window's corner: judged as anything outside what scrolls is, by the window's corner, not as scrolled with the rows" {
  // (a box 8 in from the window's sides and foot, 2 round where the window's 16 wants 8 there: in the foot, and the
  // same box laid over the window outside any list, said alike)
  let box_in = fn(v : @view.View) {
    v.box(fn(p) {
      p.pad(Is(8.0)).shrink(Is(0.0)) |> ignore
      p.box(fn(b) { b.height(Is(Some(40.0))).radius(Is(2.0)).ground(Is(foot_corner_ink)) |> ignore }) |> ignore
    })
    |> ignore
  }
  let footed = Tester::new(fn(_c) {  }, w=300.0, h=400.0, window_corner=16.0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      col.scrolls_window(@view.Scroll::list(), fn() { Array::makei(30, fn(i) { i }) }, est=40.0, foot=box_in, fn(r, _) {
        r.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  footed.draw()
  let in_foot = footed.corner_faults()
  let alone = Tester::new(fn(_c) {  }, w=300.0, h=400.0, window_corner=16.0, corners_held=false)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      col.box(fn(o) {
        o.over(Is(true)).offset(Is((0.0, 344.0))).width(Is(Some(300.0))) |> ignore
        box_in(o)
      })
      |> ignore
    })
    |> ignore
  })
  alone.draw()
  let outside = alone.corner_faults()
  let corners = fn(faults : Array[String]) {
    faults.map(fn(f) {
      if f.contains("in what scrolls") {
        "scrolled"
      } else if f.contains("bottom left") {
        "bottom left"
      } else if f.contains("bottom right") {
        "bottom right"
      } else {
        f
      }
    })
  }
  assert_true(outside.length() > 0, msg="the box outside any list: nothing said")
  assert_eq(corners(in_foot), corners(outside), msg="\{Repr(in_foot)} against \{Repr(outside)}")
}
