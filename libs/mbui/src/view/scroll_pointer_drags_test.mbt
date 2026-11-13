// Where the pointer drags nothing that scrolls up or down (Tree::pointer_drags_scroll false: a desktop's page, the mouse
// dragging no list, as an old view's are not), a hold moved past the slop on a page's list or on a plain column is
// taken over by neither: what it holds stays where it was and no glide is set off, the wheel still scrolls them, and
// a row scrolled across still takes a hold moved along it as its own. Said true (none said), as ever. In one jump and at
// 60, 120, 24 and 7 a second.

///|
/// A hold down at (x, y) on `tree` at `at`, moved by (dx, dy) in three steps 10 ms apart and let go there: what took it
/// over (none: nothing).
fn pd_hold(tree : @view.Tree, x : Double, y : Double, dx : Double, dy : Double, at : Double) -> @view.NodeId? {
  let chain = tree.claimers_at(x, y)
  let took = tree.claimer_of(chain, dx / 3.0 * 2.0, dy / 3.0 * 2.0)
  match took {
    Some(id) => {
      tree.drag_at(id, Down, x, y, at) |> ignore
      for i in 1..=3 {
        let k = i.to_double() / 3.0
        tree.drag_at(id, Moved, x + dx * k, y + dy * k, at + 10.0 * i.to_double()) |> ignore
      }
      tree.drag_at(id, Up, x + dx, y + dy, at + 30.0) |> ignore
    }
    None => ()
  }
  took
}

///|
test "a page's list where the pointer drags nothing that scrolls: a hold moved up past the slop is not taken over, the list where it was, no glide; the wheel scrolls it; where it drags, dragged and flung as ever; at every rate" {
  for rate in rc_rates {
    for drags in [false, true] {
      let c = sg_case(60, follows=false)
      c.tree.pointer_drags_scroll(fn() { drags })
      let at = rc_at
      let took = pd_hold(c.tree, 150.0, 150.0, 0.0, -90.0, at)
      let held = c.scroll.at(c.tree)
      rc_walk(c.tree, [], [at + 1000.0], rate, fn() { () }, from=at) |> ignore
      let after = c.scroll.at(c.tree)
      if drags {
        assert_true(took is Some(_), msg="at \{rate} a second: dragging, not taken over")
        assert_true(held > 0.0 && after > held, msg="at \{rate} a second: dragged to \{held}, flung on to \{after}")
      } else {
        assert_eq((took, held, after), (None, 0.0, 0.0), msg="at \{rate} a second")
        // (the wheel scrolls it as ever)
        c.tree.wheel_at(150.0, 150.0, 0.0, 100.0, 0, at + 1000.0) |> ignore
        rc_walk(c.tree, [], [at + 2000.0], rate, fn() { () }, from=at + 1000.0) |> ignore
        assert_true(c.scroll.at(c.tree) > 0.0, msg="at \{rate} a second: the wheel scrolled nothing")
      }
    }
  }
}

///|
test "a plain column where the pointer drags nothing that scrolls: a hold moved up past the slop is not taken over, the column where it was, no glide; a row in it scrolled across still takes a hold moved along it; the wheel scrolls the column; where it drags, as ever; at every rate" {
  for rate in rc_rates {
    for drags in [false, true] {
      let now = Ref(0.0)
      let k = across_case(now~)
      k.tree.pointer_drags_scroll(fn() { drags })
      // (the column scrolled to show the row: it at 150 to 190 of it, 100 down shows 50 to 90 of the window)
      k.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
      k.tree.frame(390.0, 844.0, now=5.0) |> ignore
      let at = rc_at
      // (up on the gap under the row: the column's, where it drags)
      let up = pd_hold(k.tree, 150.0, 95.0, 0.0, -60.0, at)
      let held = k.column.at(k.tree)
      rc_walk(k.tree, [], [at + 1000.0], rate, fn() { () }, from=at) |> ignore
      let after = k.column.at(k.tree)
      // (along the row, in the column where it was: the row's, either way)
      let r = across_case()
      r.tree.pointer_drags_scroll(fn() { drags })
      r.tree.wheel_at(150.0, 50.0, 0.0, 100.0, 0, 5.0) |> ignore
      r.tree.frame(390.0, 844.0) |> ignore
      let along = pd_hold(r.tree, 160.0, 70.0, -60.0, 0.0, at)
      rc_walk(r.tree, [], [at + 5000.0], rate, fn() { () }, from=at) |> ignore
      let across = r.across.at(r.tree)
      if drags {
        assert_true(up is Some(_), msg="at \{rate} a second: dragging, not taken over")
        assert_true(held > 100.0 && after > held, msg="at \{rate} a second: dragged to \{held}, flung on to \{after}")
      } else {
        assert_eq((up, held, after), (None, 100.0, 100.0), msg="at \{rate} a second")
      }
      assert_true(along is Some(_) && across > 0.0, msg="at \{rate} a second, dragging \{drags}: along the row, \{across}")
    }
  }
}
