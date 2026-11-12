// What shows of a page's list, for what is brought into sight, is what floats over its top does not cover (what its bar
// keeps clear of: View::scrolls' `bar_clear`, its top end): a block's field given the focus by the app under it comes
// to rest under it, not at the list's top (list_foot_focus_test's case; list_foot_covers_test's mirror). In one jump
// and at 60, 120, 24 and 7 a second.

///|
/// How tall what floats over the list's top is, and where the list is put: block 5 at 200 to 240 of what it holds,
/// 0 to 40 of what shows, all of it under what floats over its top.
let tc_cover : Double = 50.0

///|
let tc_at : Double = 200.0

///|
test "a page's list put so a block is under what floats over its top, the block given the focus by the app: brought to rest under that, at every rate" {
  for rate in rc_rates {
    let c = ff_case(follows=false, block_field=5, top_cover=tc_cover)
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    c.tree.event(at - 1.0, fn() { c.scroll.put(tc_at) })
    let looks = rc_looks(at + 400.0)
    let tops = rc_walk(c.tree, [(at, fn() { c.tree.focus_to(Some(id)) |> ignore })], looks, rate, from=at - 1.0, fn() {
      rc_y(c.tree, "行5")
    })
    for i, y in tops {
      assert_true(
        y >= tc_cover - 0.5,
        msg="at \{rate} a second, at \{looks[i]}: its top at \{y}, the cover's foot at \{tc_cover}",
      )
    }
  }
}
