// A page's list at its foot, a field in its last block, in sight, given the focus by the app: nothing of the list moves
// for it, so it stays at its foot, following it; the foot growing after, and the room it shows in shrinking (a keyboard
// come up), the last block stays on the foot's top at every moment (list_foot_focus_test's case). In one jump and at 60,
// 120, 24 and 7 a second.

///|
test "a page's list at its foot, a field in its last block given the focus by the app, then the foot grown and the room shrunk: the last block on the foot's top at every moment, at every rate" {
  for rate in rc_rates {
    let c = ff_case(block_field=29)
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    let events = [
      (at, fn() { c.tree.focus_to(Some(id)) |> ignore }),
      (at + 400.0, fn() { c.foot.set(ff_foot_more) }),
      (at + 800.0, fn() { c.room.set(ff_room_kb) }),
    ]
    let looks = rc_looks(at + 1200.0)
    let gaps = rc_walk(c.tree, events, looks, rate, fn() { ff_gap(c) })
    for i, g in gaps {
      assert_true(g.abs() < 0.5, msg="at \{rate} a second, at \{looks[i]}: the last block \{g} over the foot's top")
    }
  }
}
