// A viewer closed sets out no way once it has landed: its layer (viewer_tree's `viewer_node`) and a thumbnail's flight
// slot are let go with nothing left to show of them, so they go at once (the coordinator of the migration, 2026-11-13:
// a way is set out only for a cause; these set out one at +300 ms or so, as the leaving viewer was let go, with no
// frame of it to see). A picture and a film, in a phone's window by touch and a wide one by the mouse, at four rates.

///|
test "a viewer closed sets out no way after it lands, and the thumbnail it landed on opens it again" {
  for film in [false, true] {
    for wide in [false, true] {
      for period in [1000.0 / 7.0, 1000.0 / 24.0, 1000.0 / 60.0, 1000.0 / 120.0] {
        let (w, p) = if wide { (1280.0, 0) } else { (390.0, 2) }
        let (t, x, y) = if film {
          film_in_chat(platform=p, w~)
        } else {
          image_in_chat("compare.png", platform=p, w~)
        }
        let name = "\{if film { "film" } else { "picture" }} \{w} at \{(1000.0 / period).round()} Hz"
        t.set_frame_period(period)
        t.tap(x, y)
        t.run_for(@ui.move_most_ms * 2.0)
        assert_true(viewer.get() is Some(_), msg="\{name}: the viewer opened")
        t.back()
        if film {
          film_frame_answered(t)
        }
        // (what sets out as it closes, its flight back included, is the close's own; from the frame it has landed on,
        // none)
        let start = t.time()
        while pv_leaving.get() is Some(_) || viewer.get() is Some(_) {
          t.ways_set_out() |> ignore
          assert_true(t.time() < start + 2000.0, msg="\{name}: the viewer closed")
          t.frame_at(t.time() + period)
        }
        let landed = t.time()
        let ways = t.ways_set_out()
        while t.time() < landed + 1000.0 {
          t.frame_at(t.time() + period)
          ways.push_iter(t.ways_set_out().iter())
        }
        assert_eq(
          ways.map(fn(s) { "\{s.kind} \{s.made} +\{(s.at - landed).round()}" }),
          [],
          msg="\{name}: ways set out after it landed",
        )
        t.tap(x, y)
        t.run_for(period)
        assert_true(viewer.get() is Some(_), msg="\{name}: the thumbnail it landed on opens it again")
      }
    }
  }
}
