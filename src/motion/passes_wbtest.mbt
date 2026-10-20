///|
/// Rows keyed to move to their places (layout), a box above them in the first build of a frame only: what it read
/// changed (Ctx::read_changed), the frame is built again without it (frame_body), so its rows are other nodes.
fn rows_built_twice(extra : Ref[Bool]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      c.column(fn() {
        if extra.val {
          c.box(h=Px(10.0), fn() { c.text("above") |> ignore }) |> ignore
          extra.val = false
          // (what the view read changed: built again in this frame)
          c.list_scroll_by("nothing", 0.0)
        }
        for k in ["a", "b", "c"] {
          let n = c.box(w=Fill(1.0), h=Px(40.0), fn() { c.text("row " + k) |> ignore })
          layout(c, n, "row/" + k, listed=false)
        }
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
}

///|
test "a frame built twice: its keyed nodes are the last build's, moved from where the last frame drew them" {
  let extra = Ref::new(false)
  let t = rows_built_twice(extra)
  t.frame()
  let a = t.drawn_of("row a").unwrap()
  let b = t.drawn_of("row b").unwrap()
  let c = t.drawn_of("row c").unwrap()
  let builds = t.ctx().build_number()
  // the next frame built twice: the first build with a box above the rows, the second (drawn) without
  extra.val = true
  t.frame()
  assert_eq(t.ctx().build_number(), builds + 2)
  // one set of entries, the last build's: one a row (asked before the rows are looked at, as a stale one would move one)
  let entries = mo.entries.length()
  for e in mo.entries {
    assert_true(e.name.has_prefix("row/"), msg=e.name)
  }
  // where they were laid out the last frame, they are now: none drawn from another's place, none moving
  assert_eq(t.drawn_of("row a"), Some(a))
  assert_eq(t.drawn_of("row b"), Some(b))
  assert_eq(t.drawn_of("row c"), Some(c))
  t.frame()
  assert_eq(t.drawn_of("row c"), Some(c))
  assert_eq(layout_rest("row/a"), -1.0)
  assert_eq(layout_rest("row/b"), -1.0)
  assert_eq(layout_rest("row/c"), -1.0)
  assert_eq(entries, 3)
  t.assert_idle()
}

///|
/// The move of a row pushed down (its tween's length), and a moment within it.
let push_ms : Double = 200.0

///|
let push_midway_ms : Double = 100.0

///|
test "a frame built twice whose rows did move: moved once, from where the last frame drew them" {
  let extra = Ref::new(false)
  let top = Ref::new(0.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.column(fn() {
        c.box(h=Px(top.val), fn() {  }) |> ignore
        if extra.val {
          c.box(h=Px(10.0), fn() { c.text("above") |> ignore }) |> ignore
          extra.val = false
          c.list_scroll_by("nothing", 0.0)
        }
        for k in ["a", "b"] {
          let n = c.box(w=Fill(1.0), h=Px(40.0), fn() { c.text("row " + k) |> ignore })
          layout(c, n, "row/" + k, listed=false, spec=tween(push_ms, ease=Linear))
        }
      })
      |> ignore
    },
    w=200.0,
    h=400.0,
  )
  t.frame()
  let a = t.drawn_of("row a").unwrap()
  // pushed down 40, in a frame built twice: drawn where it was (its offset the move's whole, not twice it)
  top.val = 40.0
  extra.val = true
  t.frame()
  assert_eq(t.drawn_of("row a"), Some(a))
  // on its way, between the two places (not past where it was, as a move added twice would start)
  t.run_for(push_midway_ms)
  let y = t.drawn_of("row a").unwrap().1
  assert_true(y > a.1 && y < a.1 + 40.0, msg="\{y}")
  t.run_for(layout_rest("row/a") - t.time())
  assert_eq(t.drawn_of("row a").unwrap().1, a.1 + 40.0)
  t.assert_idle()
}
