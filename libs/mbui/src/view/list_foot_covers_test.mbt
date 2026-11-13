// What shows of a page's list, for what is brought into sight, is what its pinned foot does not cover: a block's field
// given the focus by the app under the foot comes to rest over it (list_foot_focus_test's case). In one jump and at 60,
// 120, 24 and 7 a second.

///|
test "a page's list at its top, a block under its foot given the focus by the app: brought to rest over the foot, at every rate" {
  for rate in rc_rates {
    // (block 9 at 360 to 400 of what shows, under the foot's top at 340)
    let c = ff_case(follows=false, block_field=9)
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    let looks = rc_looks(at + 400.0)
    let feet = rc_walk(c.tree, [(at, fn() { c.tree.focus_to(Some(id)) |> ignore })], looks, rate, fn() {
      rc_y(c.tree, "行9") + ff_tall
    })
    let edge = ff_room - ff_foot
    for i, y in feet {
      assert_true(y <= edge + 0.5, msg="at \{rate} a second, at \{looks[i]}: its foot at \{y}, the foot's top at \{edge}")
    }
  }
}
