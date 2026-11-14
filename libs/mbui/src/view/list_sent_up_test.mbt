// What is sent takes a page's list up only (the coordinator of the migration's rule, 2026-11-13, for the owner's
// 2026-11-12: a turn that ends with no answer must not carry what is read up and let it down again): at its foot, in a
// change by which a key comes at its foot (by data, seen), the column is never shorter than it was at the change's
// moment while that change's ways go, and it rests as tall as it came to, the room under the last block what keeps it
// so, never less than none. So what is over the key coming goes up only, by what the key needs past all the room that
// change gives it (the room there, the pinned foot's shrink, a block over closing a part), never down. Not so (as
// before): the foot shrinking with no key coming, a block's part closing alone, a key coming while read up, a key coming
// with nothing giving room back. Acceptance tests: where the words over the key are drawn at every look on the way (10
// ms apart), in one jump and at 60, 120, 24 and 7 a second (rc_walk, list_rows_come_test's).

///|
/// The list's pinned foot (a composer's), and the foot grown (a composer of two lines more).
let su_foot : Double = 30.0

///|
let su_foot_grown : Double = 70.0

///|
/// The keys: 0 to 9 the rows read (40 each), 70 the sent words (40, over a part of its own that may close), 50 the
/// agent's line (said to go leaving its room), 72 the next to come at its foot.
let su_line : Int = 50

///|
let su_sent : Int = 70

///|
let su_next : Int = 72

///|
/// When the sent words come, the line under them, the line gone (leaving its room), the foot grown, and the change
/// looked at (a key coming at its foot, with what it says given back in it); how long a look goes on past it.
let su_sent_at : Double = 100.5

///|
let su_line_at : Double = 700.5

///|
let su_gone_at : Double = 1000.5

///|
let su_grown_at : Double = 1600.5

///|
let su_change_at : Double = 2500.5

///|
let su_after_ms : Double = 1200.0

///|
priv struct SuCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  foot : @signals.Signal[Double]
  foot_box : Ref[@view.View?]
  part : @signals.Signal[Bool]
  part_h : Double
  next_h : Double
  rows : Int
}

///|
/// A page's list 300 by 400 of the rows 0 to `rows` − 1 (est 40), following its foot, its pinned foot su_foot tall; the
/// sent words' block 40 over a part `part_h` tall (none where 0) its show makes, shown at first; the line `line_h` tall,
/// the key its page says goes leaving its room; the next key `next_h` tall. `reduced`: its motion reduced. `gone_at_once`:
/// its page says the sent words are simply gone (`goes` false for them). `g`: its rows on a host's grid of so many pixels a
/// point (none where 0). Drawn once, at 0.
fn su_case(
  line_h : Double,
  part_h : Double,
  next_h : Double,
  reduced? : Bool = false,
  rows? : Int = 10,
  gone_at_once? : Bool = false,
  g? : Double = 0.0,
) -> SuCase {
  let keys = @signals.signal(Array::makei(rows, fn(i) { i }), same=fn(a, b) { a == b })
  let foot = @signals.signal(su_foot, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let part = @signals.signal(true, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        leaves_room=fn(k) { k == su_line },
        goes=fn(k) { !(gone_at_once && k == su_sent) },
        foot=fn(f) {
          f.box(fn(b) {
            b.height(By(fn() { Some(foot.get()) })).shrink(Is(0.0)) |> ignore
            foot_box.val = Some(b)
          })
          |> ignore
        },
        fn(b, k) {
          if k == su_sent {
            b.box(fn(w) { w.height(Is(Some(40.0))).shrink(Is(0.0)).words(Is("行\{k}")) |> ignore }) |> ignore
            if part_h > 0.0 {
              b.show(fn() { part.get() }, fn(p) { p.height(Is(Some(part_h))).shrink(Is(0.0)) |> ignore })
            }
          } else {
            let h = if k == su_line {
              line_h
            } else if k == su_next {
              next_h
            } else {
              40.0
            }
            b.height(Is(Some(h))).words(Is(if k == su_line { "线" } else { "行\{k}" })) |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  if g > 0.0 {
    tree.set_rows_grid(g)
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, foot, foot_box, part, part_h, next_h, rows }
}

///|
/// The rows 0 to 9, then `more`.
fn su_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// Its rows, then `more`; the first `head` of its rows taken (more than none), or as many as −`head` put in over them
/// (200 on).
fn SuCase::keys_with(self : SuCase, more : Array[Int], head? : Int = 0) -> Array[Int] {
  let all = if head < 0 {
    Array::makei(-head, fn(i) { 200 + i })
  } else {
    []
  }
  for i in head.max(0)..<self.rows {
    all.push(i)
  }
  all.append(more)
  all
}

///|
/// What gives room back in the change, and what comes.
priv struct SuGive {
  room : Bool // the line gone before, leaving its room
  foot : Bool // the foot grown before, back in the change
  declared : Bool // its going back declared (View::resizes), or at once
  part : Bool // the sent words' part closing in the change
  comes : Bool // the next key coming in the change
}

///|
/// The case walked from su_sent_at to the change's rest at `rate`, the sent words coming, then as `give` says (and in
/// the change its head as `head` says: SuCase::keys_with): at each look, where its last two rows and the sent words are drawn.
fn su_walk(c : SuCase, give : SuGive, rate : Double, head? : Int = 0) -> Array[Array[Double]] {
  let events : Array[(Double, () -> Unit)] = [(su_sent_at, fn() { c.keys.set(c.keys_with([su_sent])) })]
  if give.room {
    events.push((su_line_at, fn() { c.keys.set(c.keys_with([su_sent, su_line])) }))
    events.push((su_gone_at, fn() { c.keys.set(c.keys_with([su_sent])) }))
  }
  if give.foot {
    events.push((su_grown_at, fn() { c.foot.set(su_foot_grown) }))
  }
  events.push((su_change_at, fn() {
    if give.foot {
      if give.declared {
        c.foot_box.val.unwrap().resizes() |> ignore
      }
      c.foot.set(su_foot)
    }
    if give.part {
      c.part.set(false)
    }
    if give.comes {
      c.keys.set(c.keys_with([su_sent, su_next], head~))
    }
  }))
  let looks = []
  let mut at = su_sent_at
  while at <= su_change_at + su_after_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  let names = ["行\{c.rows - 2}", "行\{c.rows - 1}", "行\{su_sent}"]
  rc_walk(c.tree, events, looks, rate, fn() { names.map(fn(w) { rc_y(c.tree, w) }) })
}

///|
/// The index of the look at `at` (su_walk's looks).
fn su_look(at : Double) -> Int {
  ((at - su_sent_at) / rc_look_ms).ceil().to_int()
}

///|
/// Where among `seen`, from the look before the change on, a row over the key went further down than the highest it
/// had been since, by more than half a point: none, or what and where.
fn su_down(seen : Array[Array[Double]]) -> String? {
  let from = su_look(su_change_at) - 1
  let high = seen[from].copy()
  for i in from..<seen.length() {
    for j, y in seen[i] {
      guard y != rc_none && high[j] != rc_none else { continue }
      if y > high[j] + 0.5 {
        return Some("look \{i}: row \{j} down from \{high[j]} to \{y}")
      }
      if y < high[j] {
        high[j] = y
      }
    }
  }
  None
}

///|
/// How far up the sent words are at rest from where they were the look before the change (down less than 0).
fn su_up(seen : Array[Array[Double]]) -> Double {
  seen[su_look(su_change_at) - 1][2] - seen[seen.length() - 1][2]
}

///|
/// The room under the last block and over the pinned foot, as drawn: the next key's foot (or the sent words' block's,
/// where it did not come) to the foot's top.
fn su_room(c : SuCase, came : Bool) -> Double {
  let last = if came {
    rc_y(c.tree, "行\{su_next}") + c.next_h
  } else {
    rc_y(c.tree, "行\{su_sent}") + 40.0 + (if c.part.untracked() { c.part_h } else { 0.0 })
  }
  400.0 - c.foot.untracked() - last
}

///|
/// Every look from the one before the change on: no row over the key more than half a point from where it was then.
fn su_still(seen : Array[Array[Double]]) -> String? {
  let from = su_look(su_change_at) - 1
  for i in from..<seen.length() {
    for j, y in seen[i] {
      if (y - seen[from][j]).abs() > 0.5 {
        return Some("look \{i}: row \{j} at \{y}, \{seen[from][j]} before")
      }
    }
  }
  None
}

///|
test "1. the room 44 there, the foot grown 40; in one change the foot back (declared, and at once) and a key of 60 comes: what is over it never down at any look, up none, the room 24 at rest" {
  for declared in [true, false] {
    for rate in rc_rates {
      let c = su_case(44.0, 0.0, 60.0)
      let seen = su_walk(c, { room: true, foot: true, declared, part: false, comes: true }, rate)
      let at = "foot back \{if declared { "declared" } else { "at once" }}, at \{rate} a second"
      match su_down(seen) {
        Some(d) => fail("\{at}: \{d}")
        None => ()
      }
      assert_true(su_up(seen).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, none wanted")
      assert_true((su_room(c, true) - 24.0).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, 24 wanted")
    }
  }
}

///|
test "2. no room, the foot grown 40; the foot back and a key of 20 comes: nothing moves, the room 20; a key of 60: up 20 only" {
  for (next_h, up, room) in [(20.0, 0.0, 20.0), (60.0, 20.0, 0.0)] {
    for declared in [true, false] {
      for rate in rc_rates {
        let c = su_case(44.0, 0.0, next_h)
        let seen = su_walk(c, { room: false, foot: true, declared, part: false, comes: true }, rate)
        let at = "a key of \{next_h}, foot back \{if declared { "declared" } else { "at once" }}, at \{rate} a second"
        match su_down(seen) {
          Some(d) => fail("\{at}: \{d}")
          None => ()
        }
        if up == 0.0 {
          match su_still(seen) {
            Some(m) => fail("\{at}: \{m}")
            None => ()
          }
        }
        assert_true((su_up(seen) - up).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, \{up} wanted")
        assert_true((su_room(c, true) - room).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, \{room} wanted")
      }
    }
  }
}

///|
test "3. the room 52 there; a block over closes a part of 22 by its way in the change a key of 64 comes: nothing moves, the room 10; with no room (guard): up 42, as before" {
  for rate in rc_rates {
    let c = su_case(52.0, 22.0, 64.0)
    let seen = su_walk(c, { room: true, foot: false, declared: false, part: true, comes: true }, rate)
    let at = "the room 52, at \{rate} a second"
    match su_down(seen) {
      Some(d) => fail("\{at}: \{d}")
      None => ()
    }
    match su_still(seen) {
      Some(m) => fail("\{at}: \{m}")
      None => ()
    }
    assert_true((su_room(c, true) - 10.0).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, 10 wanted")
  }
  for rate in rc_rates {
    let c = su_case(52.0, 22.0, 64.0)
    let seen = su_walk(c, { room: false, foot: false, declared: false, part: true, comes: true }, rate)
    let at = "no room, at \{rate} a second"
    assert_true((su_up(seen) - 42.0).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, 42 wanted")
    assert_true(su_room(c, true).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, none wanted")
  }
}

///|
test "4. the room 52, the foot back 40 and a part of 22 closing, all in the change a key of 150 comes (taller than all of it): up only, by the rest (36), no room" {
  for declared in [true, false] {
    for rate in rc_rates {
      let c = su_case(52.0, 22.0, 150.0)
      let seen = su_walk(c, { room: true, foot: true, declared, part: true, comes: true }, rate)
      let at = "foot back \{if declared { "declared" } else { "at once" }}, at \{rate} a second"
      match su_down(seen) {
        Some(d) => fail("\{at}: \{d}")
        None => ()
      }
      assert_true((su_up(seen) - 36.0).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, 36 wanted")
      assert_true(su_room(c, true).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, none wanted")
    }
  }
}

///|
test "5. guards, as before: the foot back with no key coming, what is over it down 40; a part closing alone at its foot, down 22; a key of 60 with nothing given back, up 60" {
  let cases : Array[(String, Double, SuGive, Double)] = [
    ("the foot back alone", 0.0, { room: false, foot: true, declared: true, part: false, comes: false }, -40.0),
    ("the foot back alone, at once", 0.0, { room: false, foot: true, declared: false, part: false, comes: false }, -40.0),
    ("a part closing alone", 22.0, { room: false, foot: false, declared: false, part: true, comes: false }, -22.0),
    ("a key with nothing given back", 0.0, { room: false, foot: false, declared: false, part: false, comes: true }, 60.0),
  ]
  for cs in cases {
    let (name, part_h, give, up) = cs
    for rate in rc_rates {
      let c = su_case(44.0, part_h, 60.0)
      let seen = su_walk(c, give, rate)
      let at = "\{name}, at \{rate} a second"
      assert_true((su_up(seen) - up).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, \{up} wanted")
      assert_true(su_room(c, give.comes).abs() < 0.5, msg="\{at}: the room \{su_room(c, give.comes)} at rest, none wanted")
    }
  }
}

///|
test "5b. guard: read up (off its foot) as the foot goes back and a key comes: what is read stays" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0)
    // (the foot grown at rest first, then read up 100)
    rc_walk(c.tree, [(su_sent_at, fn() { c.foot.set(su_foot_grown) })], [su_sent_at + 600.0], rate, fn() { () })
    |> ignore
    c.tree.wheel_at(150.0, 100.0, 0.0, -100.0, 0, su_sent_at + 610.0) |> ignore
    let read_at = su_sent_at + 1300.0
    let events : Array[(Double, () -> Unit)] = [
      (read_at + 10.0, fn() {
        c.foot.set(su_foot)
        c.keys.set(su_keys([su_next]))
      }),
    ]
    let looks = []
    let mut at = read_at
    while at <= read_at + su_after_ms {
      looks.push(at)
      at = at + rc_look_ms
    }
    let ys = rc_walk(c.tree, events, looks, rate, from=su_sent_at + 610.0, fn() { rc_y(c.tree, "行5") })
    for i, y in ys {
      assert_true((y - ys[0]).abs() <= 0.5, msg="at \{rate} a second, look \{i}: 行5 at \{y}, read at \{ys[0]}")
    }
  }
}

///|
test "6. motion reduced: 1 and 3 at once: in the change's frame nothing over the key moved, the room 24 and 10" {
  for (line_h, part_h, next_h, give, room) in [
    (44.0, 0.0, 60.0, { room: true, foot: true, declared: false, part: false, comes: true }, 24.0),
    (52.0, 22.0, 64.0, { room: true, foot: false, declared: false, part: true, comes: true }, 10.0),
  ] {
    for rate in rc_rates {
      let c = su_case(line_h, part_h, next_h, reduced=true)
      let seen = su_walk(c, give, rate)
      let at = "reduced, the room \{room} wanted, at \{rate} a second"
      let before = seen[su_look(su_change_at) - 1]
      let after = seen[su_look(su_change_at)]
      for j, y in after {
        assert_true((y - before[j]).abs() < 0.5, msg="\{at}: row \{j} from \{before[j]} to \{y} in the change's frame")
      }
      match su_still(seen) {
        Some(m) => fail("\{at}: \{m}")
        None => ()
      }
      assert_true((su_room(c, true) - room).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, \{room} wanted")
    }
  }
}

///|
test "7. a key at its foot, a second (the line, said to leave its room) 100 ms after in the first's way, a third in the second's place 300 ms after the first, taller and shorter than it: what is over them never down at any look" {
  for next_h in [60.0, 20.0] {
    for rate in rc_rates {
      let c = su_case(44.0, 0.0, next_h)
      let events : Array[(Double, () -> Unit)] = [
        (su_sent_at, fn() { c.keys.set(su_keys([su_sent])) }),
        (su_sent_at + 100.0, fn() { c.keys.set(su_keys([su_sent, su_line])) }),
        (su_sent_at + 300.0, fn() { c.keys.set(su_keys([su_sent, su_next])) }),
      ]
      let looks = []
      let mut at = su_sent_at - rc_look_ms
      while at <= su_sent_at + 300.0 + su_after_ms {
        looks.push(at)
        at = at + rc_look_ms
      }
      let seen = rc_walk(c.tree, events, looks, rate, fn() {
        ["行8", "行9", "行\{su_sent}"].map(fn(w) { rc_y(c.tree, w) })
      })
      let high = seen[0].copy()
      for i, ys in seen {
        for j, y in ys {
          guard y != rc_none else { continue }
          if high[j] != rc_none {
            assert_true(y <= high[j] + 0.5, msg="a third of \{next_h}, at \{rate} a second, look \{i}: row \{j} down from \{high[j]} to \{y}")
          }
          if high[j] == rc_none || y < high[j] {
            high[j] = y
          }
        }
      }
    }
  }
}

///|
test "8. armed (test 1's change, the foot back at once), the hand wheels up 30 in the middle of the way and back: no jump at the wheel's frame, the room after what showed of it then less the 30, at its foot" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0)
    let wheel_at = su_change_at + 150.0
    // (walked to the look before the wheel, the room then)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(su_keys([su_sent])) }),
      (su_line_at, fn() { c.keys.set(su_keys([su_sent, su_line])) }),
      (su_gone_at, fn() { c.keys.set(su_keys([su_sent])) }),
      (su_grown_at, fn() { c.foot.set(su_foot_grown) }),
      (su_change_at, fn() {
        c.foot.set(su_foot)
        c.keys.set(su_keys([su_sent, su_next]))
      }),
    ]
    let before = rc_walk(c.tree, events, [wheel_at - rc_look_ms], rate, fn() {
      (rc_y(c.tree, "行9"), su_room(c, true))
    })[0]
    let (y_was, room_was) = before
    c.tree.wheel_at(150.0, 100.0, 0.0, -30.0, 0, wheel_at) |> ignore
    let looks = []
    let mut at = wheel_at
    while at <= wheel_at + 600.0 {
      looks.push(at)
      at = at + rc_look_ms
    }
    let ys = rc_walk(c.tree, [], looks, rate, from=wheel_at - rc_look_ms, fn() { rc_y(c.tree, "行9") })
    let at = "at \{rate} a second"
    // (no jump: from the look before the wheel, never further down than the wheel's 30, never up)
    for i, y in ys {
      assert_true(y >= y_was - 0.5 && y <= y_was + 30.0 + 2.0, msg="\{at}, look \{i} from the wheel: 行9 at \{y}, \{y_was} before it")
    }
    c.tree.wheel_at(150.0, 100.0, 0.0, 2000.0, 0, wheel_at + 700.0) |> ignore
    c.tree.frame(390.0, 844.0, now=wheel_at + 1400.0) |> ignore
    let want = if room_was > 30.0 { room_was - 30.0 } else { 0.0 }
    assert_true((su_room(c, true) - want).abs() < 2.0, msg="\{at}: the room \{su_room(c, true)} after, \{want} wanted (\{room_was} before the wheel)")
    assert_true(c.scroll.at_foot_now(), msg="\{at}: not at its foot")
  }
}

///|
test "9. guard: a key its page lets go (not said to leave its room) going at its foot in the change another, shorter, comes: what is over it down with it, as list_rows_come_test's, no room" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 20.0)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(su_keys([su_sent])) }),
      (su_change_at, fn() { c.keys.set(su_keys([su_next])) }),
    ]
    let seen = rc_walk(c.tree, events, [su_change_at - rc_look_ms, su_change_at + su_after_ms], rate, fn() {
      rc_y(c.tree, "行9")
    })
    let at = "at \{rate} a second"
    assert_true((seen[1] - seen[0] - 20.0).abs() < 0.5, msg="\{at}: 行9 from \{seen[0]} to \{seen[1]}, down 20 wanted")
    assert_true(su_room(c, true).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, none wanted")
  }
}

///|
test "10. the room 44, the foot back 40, a key of 60 comes and five rows of 40 are taken at its head (out of sight, at once) in that change: what is over the key never down, up none, the room 24 at rest, no more" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0, rows=20)
    let seen = su_walk(c, { room: true, foot: true, declared: false, part: false, comes: true }, rate, head=5)
    let at = "five taken at its head, at \{rate} a second"
    match su_down(seen) {
      Some(d) => fail("\{at}: \{d}")
      None => ()
    }
    assert_true(su_up(seen).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, none wanted")
    assert_true((su_room(c, true) - 24.0).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, 24 wanted")
  }
}

///|
test "11. the same with five rows put in at its head in that change: the room 24" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0, rows=20)
    let seen = su_walk(c, { room: true, foot: true, declared: false, part: false, comes: true }, rate, head=-5)
    let at = "five put in at its head, at \{rate} a second"
    match su_down(seen) {
      Some(d) => fail("\{at}: \{d}")
      None => ()
    }
    assert_true(su_up(seen).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, none wanted")
    assert_true((su_room(c, true) - 24.0).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, 24 wanted")
  }
}

///|
test "12. nothing given back (no room, the foot still), a key of 60 comes and five rows are taken at its head: up 60, no room, as before" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0, rows=20)
    let seen = su_walk(c, { room: false, foot: false, declared: false, part: false, comes: true }, rate, head=5)
    let at = "at \{rate} a second"
    assert_true((su_up(seen) - 60.0).abs() < 0.5, msg="\{at}: up \{su_up(seen)} at rest, 60 wanted")
    assert_true(su_room(c, true).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, none wanted")
  }
}

///|
test "13. guard: the sent words, not said to leave their room, simply gone at its foot (goes false) as a key of 60 comes, the room 44 there and the foot back 40: as before, whole, what is over it down 64 (40 + 44 + 40 − 60), no room" {
  for rate in rc_rates {
    let c = su_case(44.0, 0.0, 60.0, gone_at_once=true)
    let events : Array[(Double, () -> Unit)] = [
      (su_sent_at, fn() { c.keys.set(c.keys_with([su_sent])) }),
      (su_line_at, fn() { c.keys.set(c.keys_with([su_sent, su_line])) }),
      (su_gone_at, fn() { c.keys.set(c.keys_with([su_sent])) }),
      (su_grown_at, fn() { c.foot.set(su_foot_grown) }),
      (su_change_at, fn() {
        c.foot.set(su_foot)
        c.keys.set(c.keys_with([su_next]))
      }),
    ]
    // (looked at every 10 ms on the way, as su_walk does: the line seen to go, leaving its room)
    let looks = []
    let mut t = su_sent_at
    while t <= su_change_at + su_after_ms {
      looks.push(t)
      t = t + rc_look_ms
    }
    let all = rc_walk(c.tree, events, looks, rate, fn() { (rc_y(c.tree, "行9"), su_room(c, false)) })
    let seen = [all[su_look(su_change_at) - 1], all[all.length() - 1]]
    let at = "at \{rate} a second"
    assert_true((seen[0].1 - 44.0).abs() < 0.5, msg="\{at}: the room \{seen[0].1} before, 44 wanted")
    assert_true((seen[1].0 - seen[0].0 - 64.0).abs() < 0.5, msg="\{at}: 行9 from \{seen[0].0} to \{seen[1].0}, down 64 wanted")
    assert_true(su_room(c, true).abs() < 0.5, msg="\{at}: the room \{su_room(c, true)} at rest, none wanted")
  }
}

///|
test "4 on a host's grid (2, 2.75, 3, 3.5): the room 52, the foot back 40 (declared) and a part of 22 closing as a key of 150 comes: up only, never a device pixel down" {
  for g in [2.0, 2.75, 3.0, 3.5] {
    for rate in rc_rates {
      let c = su_case(52.0, 22.0, 150.0, g~)
      let seen = su_walk(c, { room: true, foot: true, declared: true, part: true, comes: true }, rate)
      let from = su_look(su_change_at) - 1
      for i in (from + 1)..<seen.length() {
        for j, y in seen[i] {
          let was = seen[i - 1][j]
          guard y != rc_none && was != rc_none else { continue }
          assert_true(y <= was + 0.01, msg="grid \{g}, at \{rate} a second, look \{i}: row \{j} down from \{was} to \{y}")
        }
      }
    }
  }
}
