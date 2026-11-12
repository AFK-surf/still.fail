// What the focus is on in a page's list (a field in a block, given it by the app) is kept in sight by the list as the
// room it shows in changes (a keyboard coming up a step at a time, and going): whole between what floats over its top
// and its pinned foot at every step, the list at its foot for as long as that leaves it so, and at its foot again once
// the room is back; never pulled back where the hand scrolled it away, nor held where rows come with the room the same
// (at its foot the list follows it, the field going up with its rows). list_foot_focus_test's case; in one jump and at
// 60, 120, 24 and 7 a second.

///|
/// What floats over the list's top, the block whose field is given the focus (five over the last), and the room each of
/// the keyboard's ten steps takes.
let fh_cover : Double = 50.0

///|
let fh_block : Int = 25

///|
let fh_step : Double = 30.0

///|
/// Where block `k`'s top and foot are drawn.
fn fh_block_at(c : FfCase, k : Int) -> (Double, Double) {
  let y = rc_y(c.tree, "行\{k}")
  (y, y + ff_tall)
}

///|
/// The field given the focus by the app at `at`, the room then taken by the keyboard's ten steps 100 apart and given
/// back at once after: at each step's look (just after it), where the field is, the last block's distance over the
/// foot's top, the room.
fn fh_walk(c : FfCase, at : Double, rate : Double) -> Array[((Double, Double), Double, Double)] {
  let id = match c.field.val {
    Some(id) => id
    None => @halt.saying("no field")
  }
  let events : Array[(Double, () -> Unit)] = [(at, fn() { c.tree.focus_to(Some(id)) |> ignore })]
  let looks = [at + 50.0]
  for i in 1..=10 {
    let t = at + 100.0 * i.to_double()
    let room = ff_room - fh_step * i.to_double()
    events.push((t, fn() { c.room.set(room) }))
    looks.push(t + 50.0)
  }
  events.push((at + 1100.0, fn() { c.room.set(ff_room) }))
  looks.push(at + 1150.0)
  rc_walk(c.tree, events, looks, rate, fn() { (fh_block_at(c, fh_block), ff_gap(c), c.room.untracked()) })
}

///|
test "a page's list at its foot, a field in a block given the focus by the app, the room taken by a keyboard's ten steps then given back: the field whole between the covers at every step, the list at its foot as long as that leaves it so, at its foot again after, at every rate" {
  for rate in rc_rates {
    let c = ff_case(block_field=fh_block, top_cover=fh_cover)
    let seen = fh_walk(c, rc_at, rate)
    for i, s in seen {
      let ((top, foot), gap, room) = s
      let edge = room - ff_foot
      let at = "at \{rate} a second, step \{i}: the field at \{top}..\{foot}, room \{room}, the last block \{gap} over"
      if edge - fh_cover >= ff_tall {
        // (room for it: whole between the covers)
        assert_true(top >= fh_cover - 0.5 && foot <= edge + 0.5, msg=at)
      } else {
        // (no room for all of it: its top kept)
        assert_true((top - fh_cover).abs() < 0.5, msg=at)
      }
      // (at its foot while that leaves it under the top's cover: five blocks over the last)
      if edge - 5.0 * ff_tall - ff_tall >= fh_cover {
        assert_true(gap.abs() < 0.5, msg=at)
      }
    }
    // (the room given back: at its foot again)
    let (_, last_gap, _) = seen[seen.length() - 1]
    assert_true(last_gap.abs() < 0.5, msg="at \{rate} a second: the room back, the last block \{last_gap} over")
  }
}

///|
test "a page's list at its foot, a field in a block given the focus, the hand scrolling it out of sight, then the room taken: the list not pulled back to it, at every rate" {
  for rate in rc_rates {
    let c = ff_case(block_field=fh_block, top_cover=fh_cover)
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    rc_walk(c.tree, [(at, fn() { c.tree.focus_to(Some(id)) |> ignore })], [at + 50.0], rate, fn() { () }) |> ignore
    // (dragged down 200: the list up its rows, the field out of sight under the foot)
    let chain = c.tree.claimers_at(150.0, 100.0)
    let took = match c.tree.claimer_of(chain, 0.0, 20.0) {
      Some(t) => t
      None => @halt.saying("not taken over")
    }
    let t0 = at + 100.0
    c.tree.drag_at(took, Down, 150.0, 100.0, t0) |> ignore
    for i in 1..=10 {
      c.tree.drag_at(took, Moved, 150.0, 100.0 + 20.0 * i.to_double(), t0 + 100.0 * i.to_double()) |> ignore
    }
    c.tree.drag_at(took, Up, 150.0, 300.0, t0 + 1100.0) |> ignore
    let after_hand = rc_walk(c.tree, [], [t0 + 1200.0], rate, from=at + 50.0, fn() { c.scroll.at(c.tree) })[0]
    let looks = [t0 + 1400.0]
    let shrunk = [(t0 + 1300.0, fn() { c.room.set(ff_room - 4.0 * fh_step) })]
    let then = rc_walk(c.tree, shrunk, looks, rate, from=t0 + 1200.0, fn() { c.scroll.at(c.tree) })[0]
    // (the room taken from its foot: what shows the same at its top, the field not brought back)
    assert_true((then - after_hand).abs() < 0.5, msg="at \{rate} a second: \{after_hand} by hand, then \{then}")
  }
}

///|
test "a page's list at its foot, a field in a block given the focus, rows come with the room the same: at its foot, the field gone up with them, not held, at every rate" {
  for rate in rc_rates {
    let c = ff_case(block_field=fh_block, top_cover=fh_cover)
    let id = match c.field.val {
      Some(id) => id
      None => @halt.saying("no field")
    }
    let at = rc_at
    let events = [
      (at, fn() { c.tree.focus_to(Some(id)) |> ignore }),
      (at + 100.0, fn() { c.count.set(36) }),
    ]
    let looks = rc_looks(at + 100.0 + @flex.move_most_ms + 100.0)
    let seen = rc_walk(c.tree, events, looks, rate, fn() { ff_gap(c) })
    let last = seen[seen.length() - 1]
    assert_true(last.abs() < 0.5, msg="at \{rate} a second: the last block \{last} over the foot")
    let (top, _) = fh_block_at(c, fh_block)
    assert_true(top < fh_cover, msg="at \{rate} a second: the field at \{top}, held")
  }
}
