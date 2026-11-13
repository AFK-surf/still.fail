// A key a page's list's page says so of goes leaving its room (the coordinator of the migration's rule, 2026-11-13,
// for the owner's 2026-11-12: an agent's line at the list's foot, a turn ending with no answer, must not carry what is
// read up and let it down again; a line going while an answer takes its place closes with it in one way; the line
// going fades where it is, the owner, 2026-11-11): what it showed fades out where it is, the room it had stays under
// the last block, nothing over it moving then or after; what comes at the foot takes that room first, what is over it
// going up only by what it needs more; the room goes as it is scrolled off, as the room kept under what was pressed;
// at its foot means at the room's foot. Only the key its page marks, never a kind of the list's. Acceptance tests:
// where the words are drawn at every look on the way (10 ms apart), in one jump and at 60, 120, 24 and 7 a second.

///|
/// The list's pinned foot (a composer's).
let lr_foot : Double = 30.0

///|
/// The keys: 0 to 9 the rows read (40 each), 70 the sent words (60), 72 the next words sent (60), 50 the agent's line
/// (44), 51 to 53 an answer taller than the line, as tall, shorter (70, 44, 20), 71 a row put in over the line (40).
fn lr_tall(k : Int) -> Double {
  match k {
    70 => 60.0
    72 => 60.0
    50 => 44.0
    51 => 70.0
    52 => 44.0
    53 => 20.0
    _ => 40.0
  }
}

///|
let lr_line : Int = 50

///|
let lr_sent : Int = 70

///|
/// When the sent words come, when the line comes under them, and how long a look goes on past the last change.
let lr_sent_at : Double = 100.5

///|
let lr_line_at : Double = 700.5

///|
let lr_after_ms : Double = 1200.0

///|
priv struct LrCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  room : @signals.Signal[Double]
  place : @view.ListPlace[Int]
  foot : @signals.Signal[Double]
  foot_box : Ref[@view.View?]
}

///|
/// A page's list 300 wide, as tall as `room` (200), of `keys` (rows 0 to 9 at first), each block as tall as lr_tall says
/// with words 行k (the line's 线), following its foot, its pinned foot lr_foot tall; told what is in sight. The line's
/// key is the one its page says goes leaving its room. `reduced`: its motion reduced. Drawn once, at 0.
fn lr_case(reduced? : Bool = false) -> LrCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  place.on_sight(fn(_) {  })
  let keys = @signals.signal(Array::makei(10, fn(i) { i }), same=fn(a, b) { a == b })
  let room = @signals.signal(200.0, same=fn(a, b) { a == b })
  let foot = @signals.signal(lr_foot, same=fn(a, b) { a == b })
  let foot_box : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(By(fn() { Some(room.get()) })) |> ignore
      o.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        follows=fn() { true },
        place~,
        // (the line's key: said to go leaving its room, once the list can be told so; till then as every key)
        goes=fn(_) { true },
        foot=fn(f) {
          f.box(fn(b) {
            b.height(By(fn() { Some(foot.get()) })).shrink(Is(0.0)) |> ignore
            foot_box.val = Some(b)
          })
          |> ignore
        },
        fn(b, k) {
          b.height(Is(Some(lr_tall(k)))).words(Is(if k == lr_line { "线" } else { "行\{k}" })) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  if reduced {
    tree.reduces_motion(fn() { true })
  }
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, room, place, foot, foot_box }
}

///|
/// The rows 0 to 9, then `more`.
fn lr_keys(more : Array[Int]) -> Array[Int] {
  let all = Array::makei(10, fn(i) { i })
  all.append(more)
  all
}

///|
/// Where `w`'s words are drawn and how seen (rc_none, 0 where they are not).
fn lr_seen(t : @view.Tree, w : String) -> (Double, Double) {
  match t.drawn().filter(fn(d) { d.words == w }) {
    [d, ..] => (d.y, d.alpha)
    _ => (rc_none, 0.0)
  }
}

///|
/// The room under block `k` and over the pinned foot, as drawn (block k's foot to the foot's top).
fn lr_room(c : LrCase, k : Int) -> Double {
  c.room.untracked() - c.foot.untracked() - (rc_y(c.tree, "行\{k}") + lr_tall(k))
}

///|
/// The moments from `from` to `to`, rc_look_ms apart.
fn lr_looks(from : Double, to : Double) -> Array[Double] {
  let out = []
  let mut at = from
  while at <= to {
    out.push(at)
    at = at + rc_look_ms
  }
  out
}

///|
/// The case walked from lr_sent_at to `to` at `rate`, the sent words coming then, the line at lr_line_at, `events`
/// after: at each look, where 行8, 行9 and the sent words are drawn, and where the line's words are and how seen.
fn lr_walk(
  c : LrCase,
  events : Array[(Double, () -> Unit)],
  to : Double,
  rate : Double,
) -> Array[(Array[Double], (Double, Double))] {
  let all : Array[(Double, () -> Unit)] = [
    (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
    (lr_line_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
  ]
  all.append(events)
  rc_walk(c.tree, all, lr_looks(lr_sent_at, to), rate, fn() {
    (["行8", "行9", "行\{lr_sent}"].map(fn(w) { rc_y(c.tree, w) }), lr_seen(c.tree, "线"))
  })
}

///|
/// Where among `seen` (from look `from` on) a row over the line goes further down than at the look before, by more
/// than a point: none, or what and where.
fn lr_down(seen : Array[(Array[Double], (Double, Double))], from : Int) -> String? {
  for i in (from + 1)..<seen.length() {
    for j, y in seen[i].0 {
      let was = seen[i - 1].0[j]
      if y != rc_none && was != rc_none && y > was + 0.5 {
        return Some("look \{i}: row \{j} \{was} to \{y}")
      }
    }
  }
  None
}

///|
/// The room an answer `k` in the line's place leaves of the line's: what it did not need.
fn lr_left(k : Int) -> Double {
  let d = lr_tall(lr_line) - lr_tall(k)
  if d > 0.0 {
    d
  } else {
    0.0
  }
}

///|
/// What is wrong with what the list last told in sight, at its foot with the sent words its last: none, or what.
fn lr_sight_wrong(c : LrCase) -> String? {
  match c.place.sight_now() {
    Some(s) if s.at_foot && s.last == lr_sent => None
    Some(s) => Some("told \{Repr(s)}")
    None => Some("nothing told in sight")
  }
}

///|
/// The index of the look at `at`.
fn lr_look(at : Double) -> Int {
  ((at - lr_sent_at) / rc_look_ms).ceil().to_int()
}

///|
/// Where the line's words went down while still seen after it went (from look `from` on): none, or where. Up they may
/// go, with what is over them, where its way in was still opening as it went (that way goes on to its end).
fn lr_line_moved(seen : Array[(Array[Double], (Double, Double))], from : Int) -> String? {
  for i in (from + 1)..<seen.length() {
    let (y, a) = seen[i].1
    let (was, a_was) = seen[i - 1].1
    if a > 0.0 && a_was > 0.0 && y != rc_none && was != rc_none && y > was + 0.5 {
      return Some("look \{i}: 线 down from \{was} to \{y} as it fades")
    }
  }
  None
}

///|
test "1. at its foot, the sent words come, the line under them; the line goes 100, 300, 1000, 3000 ms after, nothing in its place: no row over it down at any look, the room the line's height at rest, its words faded where they were, never down" {
  for x in [100.0, 300.0, 1000.0, 3000.0] {
    for rate in rc_rates {
      let c = lr_case()
      let gone_at = lr_line_at + x
      let seen = lr_walk(c, [(gone_at, fn() { c.keys.set(lr_keys([lr_sent])) })], gone_at + lr_after_ms, rate)
      let at = "line \{x} ms, at \{rate} a second"
      match lr_down(seen, 0) {
        Some(d) => fail("\{at}: \{d}")
        None => ()
      }
      match lr_line_moved(seen, lr_look(gone_at)) {
        Some(m) => fail("\{at}: \{m}")
        None => ()
      }
      let room = lr_room(c, lr_sent)
      assert_true((room - lr_tall(lr_line)).abs() < 0.5, msg="\{at}: the room at rest \{room}")
      let (_, a) = lr_seen(c.tree, "线")
      assert_true(a == 0.0, msg="\{at}: the line's words still seen at \{a}")
    }
  }
}

///|
test "2. the line goes 300 ms after it came, an answer in its place in the same change, taller, as tall, shorter: up only or not at all, the line's words not seen from the look after (never both), the room left what the answer did not need" {
  for answer in [51, 52, 53] {
    for rate in rc_rates {
      let c = lr_case()
      let gone_at = lr_line_at + 300.0
      let seen = lr_walk(
        c,
        [(gone_at, fn() { c.keys.set(lr_keys([lr_sent, answer])) })],
        gone_at + lr_after_ms,
        rate,
      )
      let at = "answer \{lr_tall(answer)} tall, at \{rate} a second"
      match lr_down(seen, 0) {
        Some(d) => fail("\{at}: \{d}")
        None => ()
      }
      match lr_line_moved(seen, lr_look(gone_at)) {
        Some(m) => fail("\{at}: \{m}")
        None => ()
      }
      for i in (lr_look(gone_at) + 1)..<seen.length() {
        let (_, a) = seen[i].1
        assert_true(a == 0.0, msg="\{at}, look \{i}: the line's words seen at \{a} with the answer in its place")
      }
      let left = lr_room(c, answer)
      let want = lr_left(answer)
      assert_true((left - want).abs() < 0.5, msg="\{at}: the room left \{left}, \{want} wanted")
    }
  }
}

///|
test "3. the line gone with nothing in its place, the answer 500 ms after: it takes the room then, up only" {
  for answer in [51, 52, 53] {
    for rate in rc_rates {
      let c = lr_case()
      let gone_at = lr_line_at + 300.0
      let answer_at = gone_at + 500.0
      let seen = lr_walk(
        c,
        [
          (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
          (answer_at, fn() { c.keys.set(lr_keys([lr_sent, answer])) }),
        ],
        answer_at + lr_after_ms,
        rate,
      )
      let at = "answer \{lr_tall(answer)} tall, at \{rate} a second"
      match lr_down(seen, 0) {
        Some(d) => fail("\{at}: \{d}")
        None => ()
      }
      let left = lr_room(c, answer)
      let want = lr_left(answer)
      assert_true((left - want).abs() < 0.5, msg="\{at}: the room left \{left}, \{want} wanted")
    }
  }
}

///|
test "4. the line gone leaving its room, then the line again (its next turn), nothing between: where it was, nothing moving" {
  for rate in rc_rates {
    let c = lr_case()
    let gone_at = lr_line_at + 300.0
    let again_at = gone_at + 800.0
    let seen = lr_walk(
      c,
      [
        (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
        (again_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
      ],
      again_at + lr_after_ms,
      rate,
    )
    let at = "at \{rate} a second"
    // (from the line's first rest on: nothing over it moves; the line where it was)
    let rest = lr_look(lr_line_at + @flex.move_most_ms + 50.0)
    for i in rest..<seen.length() {
      for j, y in seen[i].0 {
        assert_true((y - seen[rest].0[j]).abs() <= 0.5, msg="\{at}, look \{i}: row \{j} at \{y}, \{seen[rest].0[j]} at rest")
      }
    }
    // (where the line was as it went: the look before)
    let (y_was, _) = seen[lr_look(gone_at) - 1].1
    let (y_now, a_now) = seen[seen.length() - 1].1
    assert_true((y_now - y_was).abs() <= 0.5 && a_now > 0.99, msg="\{at}: the line again at \{y_now} seen \{a_now}, \{y_was} before")
  }
}

///|
test "5. the line gone leaving its room: the wheel up by less than the room and back, what is left of it; by more than the room and back, none" {
  for (up, left) in [(20.0, 24.0), (100.0, 0.0)] {
    let c = lr_case()
    let gone_at = lr_line_at + 300.0
    lr_walk(c, [(gone_at, fn() { c.keys.set(lr_keys([lr_sent])) })], gone_at + lr_after_ms, 0.0) |> ignore
    let t = gone_at + lr_after_ms + 10.0
    c.tree.wheel_at(150.0, 100.0, 0.0, -up, 0, t) |> ignore
    c.tree.frame(390.0, 844.0, now=t + 600.0) |> ignore
    assert_false(c.scroll.at_foot_now(), msg="up \{up}: still at its foot")
    c.tree.wheel_at(150.0, 100.0, 0.0, 2000.0, 0, t + 700.0) |> ignore
    c.tree.frame(390.0, 844.0, now=t + 1400.0) |> ignore
    let room = lr_room(c, lr_sent)
    assert_true((room - left).abs() < 0.5, msg="up \{up} and back: the room \{room}, \{left} wanted")
    assert_true(c.scroll.at_foot_now(), msg="up \{up} and back: not at its foot")
  }
}

///|
test "6. read up (off its foot) as the line comes and goes: what is read stays, as today; back at its foot, no room" {
  for rate in rc_rates {
    let c = lr_case()
    c.tree.wheel_at(150.0, 100.0, 0.0, -100.0, 0, 50.0) |> ignore
    c.tree.frame(390.0, 844.0, now=90.0) |> ignore
    let read = rc_y(c.tree, "行5")
    let gone_at = lr_line_at + 300.0
    let all : Array[(Double, () -> Unit)] = [
      (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
      (lr_line_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
      (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
    ]
    let ys = rc_walk(c.tree, all, lr_looks(lr_sent_at, gone_at + lr_after_ms), rate, from=90.0, fn() {
      rc_y(c.tree, "行5")
    })
    for i, y in ys {
      assert_true((y - read).abs() <= 0.5, msg="at \{rate} a second, look \{i}: 行5 at \{y}, read at \{read}")
    }
    let t = gone_at + lr_after_ms + 10.0
    c.tree.wheel_at(150.0, 100.0, 0.0, 2000.0, 0, t) |> ignore
    c.tree.frame(390.0, 844.0, now=t + 700.0) |> ignore
    let room = lr_room(c, lr_sent)
    assert_true(room.abs() < 0.5, msg="at \{rate} a second: back at its foot, the room \{room}")
  }
}

///|
test "7. the line gone leaving its room, the list's room taken by a keyboard's steps and given back: at its foot all the way, the room kept" {
  for rate in rc_rates {
    let c = lr_case()
    let gone_at = lr_line_at + 300.0
    let rest_at = gone_at + lr_after_ms
    let events : Array[(Double, () -> Unit)] = [
      (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
      (lr_line_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
      (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
    ]
    for i in 1..=5 {
      let r = 200.0 - 20.0 * i.to_double()
      events.push((rest_at + 50.0 * i.to_double(), fn() { c.room.set(r) }))
    }
    events.push((rest_at + 400.0, fn() { c.room.set(200.0) }))
    let looks = lr_looks(lr_sent_at, rest_at + 400.0 + lr_after_ms)
    let seen = rc_walk(c.tree, events, looks, rate, fn() { (c.scroll.at_foot_now(), lr_room(c, lr_sent)) })
    for i, s in seen {
      guard i >= lr_look(rest_at) else { continue }
      let (foot, room) = s
      assert_true(foot, msg="at \{rate} a second, look \{i}: not at its foot")
      assert_true((room - lr_tall(lr_line)).abs() < 0.5, msg="at \{rate} a second, look \{i}: the room \{room}")
    }
  }
}

///|
test "8. guard: a key not said so (the sent words) going at the foot closes as today, what is over it coming down by its height, no room left" {
  for rate in rc_rates {
    let c = lr_case()
    let all : Array[(Double, () -> Unit)] = [
      (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
      (lr_sent_at + 700.0, fn() { c.keys.set(lr_keys([])) }),
    ]
    let was = rc_walk(c.tree, all, [lr_sent_at + 650.0], rate, fn() { rc_y(c.tree, "行9") })[0]
    let now = rc_walk(c.tree, [all[1]], [lr_sent_at + 700.0 + lr_after_ms], rate, from=lr_sent_at + 650.0, fn() {
      rc_y(c.tree, "行9")
    })[0]
    assert_true((now - was - lr_tall(lr_sent)).abs() < 0.5, msg="at \{rate} a second: 行9 \{was} to \{now}")
    assert_true(lr_room(c, 9).abs() < 0.5, msg="at \{rate} a second: room \{lr_room(c, 9)} left")
  }
}

///|
test "9. the line gone leaving its room: in its fade's middle told in sight the page's keys alone; at rest at its foot as the page reads it (Scroll::at_foot_now) and its last key told in sight, at its foot; the wheel up a little and back: so again" {
  let c = lr_case()
  let gone_at = lr_line_at + 300.0
  // (in the fade's middle: the line still drawn, fading; told in sight the page's keys alone, the sent words its last)
  lr_walk(c, [(gone_at, fn() { c.keys.set(lr_keys([lr_sent])) })], gone_at + 100.0, 0.0) |> ignore
  assert_eq(lr_sight_wrong(c), None)
  rc_walk(c.tree, [], [gone_at + lr_after_ms], 0.0, from=gone_at + 100.0, fn() { () }) |> ignore
  assert_true((lr_room(c, lr_sent) - lr_tall(lr_line)).abs() < 0.5, msg="the room at rest \{lr_room(c, lr_sent)}")
  assert_true(c.scroll.at_foot_now(), msg="at rest: not at its foot")
  assert_eq(lr_sight_wrong(c), None)
  let t = gone_at + lr_after_ms + 10.0
  c.tree.wheel_at(150.0, 100.0, 0.0, -10.0, 0, t) |> ignore
  c.tree.frame(390.0, 844.0, now=t + 600.0) |> ignore
  c.tree.wheel_at(150.0, 100.0, 0.0, 2000.0, 0, t + 700.0) |> ignore
  c.tree.frame(390.0, 844.0, now=t + 1400.0) |> ignore
  assert_true(c.scroll.at_foot_now(), msg="up a little and back: not at its foot")
  assert_eq(lr_sight_wrong(c), None)
}

///|
/// The case walked with motion reduced (lr_case's `reduced`), the sent words and the line come at once, `events`
/// after: at the looks `looks`, where 行8, 行9 and the sent words are drawn, the room under the sent words, and how seen
/// the line's words are.
fn lr_walk_reduced(
  c : LrCase,
  events : Array[(Double, () -> Unit)],
  looks : Array[Double],
  rate : Double,
  last : Int,
) -> Array[(Array[Double], Double, Double)] {
  let all : Array[(Double, () -> Unit)] = [
    (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
    (lr_line_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
  ]
  all.append(events)
  rc_walk(c.tree, all, looks, rate, fn() {
    (["行8", "行9", "行\{lr_sent}"].map(fn(w) { rc_y(c.tree, w) }), lr_room(c, last), lr_seen(c.tree, "线").1)
  })
}

///|
test "10. motion reduced: the line gone with an answer in its place, taller, as tall, shorter: in the change's frame the line gone, what is over it up only by what the answer needs past the room, the room left what it did not need; the line again next turn: nothing moves" {
  for answer in [51, 52, 53] {
    for rate in rc_rates {
      let c = lr_case(reduced=true)
      let gone_at = lr_line_at + 300.0
      let seen = lr_walk_reduced(
        c,
        [(gone_at, fn() { c.keys.set(lr_keys([lr_sent, answer])) })],
        [gone_at - 10.0, gone_at],
        rate,
        answer,
      )
      let at = "reduced, answer \{lr_tall(answer)} tall, at \{rate} a second"
      let (before, _, _) = seen[0]
      let (after, room, a) = seen[1]
      let up = lr_tall(answer) - lr_tall(lr_line)
      let up = if up > 0.0 { up } else { 0.0 }
      for j, y in after {
        // (one taken wholly over the top by it: not drawn)
        if y == rc_none && before[j] - up + 40.0 <= 0.5 {
          continue
        }
        assert_true((before[j] - y - up).abs() < 0.5, msg="\{at}: row \{j} from \{before[j]} to \{y}, up \{up} wanted")
      }
      assert_true((room - lr_left(answer)).abs() < 0.5, msg="\{at}: the room \{room}, \{lr_left(answer)} wanted")
      assert_true(a == 0.0, msg="\{at}: the line's words seen at \{a}")
    }
  }
  for rate in rc_rates {
    let c = lr_case(reduced=true)
    let gone_at = lr_line_at + 300.0
    let again_at = gone_at + 300.0
    let seen = lr_walk_reduced(
      c,
      [
        (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
        (again_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
      ],
      [gone_at - 10.0, gone_at, again_at - 10.0, again_at],
      rate,
      lr_sent,
    )
    let at = "reduced, the line again, at \{rate} a second"
    let (first, _, _) = seen[0]
    let (_, room, a) = seen[1]
    assert_true((room - lr_tall(lr_line)).abs() < 0.5 && a == 0.0, msg="\{at}: gone, the room \{room}, seen \{a}")
    for i in 1..<seen.length() {
      let (ys, _, _) = seen[i]
      for j, y in ys {
        assert_true((y - first[j]).abs() < 0.5, msg="\{at}, look \{i}: row \{j} at \{y}, \{first[j]} first")
      }
    }
  }
}

///|
test "11. the line gone leaving its room, the pinned foot grown by 20 (its change declared) then by 40 more at once, and back: at its foot all the way, the room kept, the sent words up by what the foot grew, down as it shrank back" {
  for rate in rc_rates {
    let c = lr_case()
    let gone_at = lr_line_at + 300.0
    let rest = gone_at + lr_after_ms
    let grow = fn(by : Double, declared : Bool) {
      fn() {
        if declared {
          c.foot_box.val.unwrap().resizes() |> ignore
        }
        c.foot.set(lr_foot + by)
      }
    }
    let events : Array[(Double, () -> Unit)] = [
      (lr_sent_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
      (lr_line_at, fn() { c.keys.set(lr_keys([lr_sent, lr_line])) }),
      (gone_at, fn() { c.keys.set(lr_keys([lr_sent])) }),
      (rest, grow(20.0, true)),
      (rest + 800.0, grow(60.0, false)),
      (rest + 1600.0, grow(0.0, false)),
    ]
    let looks = lr_looks(lr_sent_at, rest + 2400.0)
    let seen = rc_walk(c.tree, events, looks, rate, fn() {
      (c.scroll.at_foot_now(), rc_y(c.tree, "行\{lr_sent}"), c.foot.untracked())
    })
    let at = "at \{rate} a second"
    let (_, y0, _) = seen[lr_look(rest) - 1]
    for i, s in seen {
      guard i >= lr_look(rest) else { continue }
      let (foot, _, _) = s
      assert_true(foot, msg="\{at}, look \{i}: not at its foot")
    }
    // (at rest after each: the sent words up by what the foot grew, the room as it was)
    for when in [rest + 790.0, rest + 1590.0, rest + 2390.0] {
      let (_, y, f) = seen[lr_look(when)]
      let want = y0 - (f - lr_foot)
      assert_true((y - want).abs() < 0.5, msg="\{at}, at \{when}: the sent words at \{y}, \{want} wanted (foot \{f})")
    }
    assert_true((lr_room(c, lr_sent) - lr_tall(lr_line)).abs() < 0.5, msg="\{at}: the room \{lr_room(c, lr_sent)}")
  }
}

///|
test "12. the line showing, a key put in just over it by data at its foot (makes_way's): one way, what is over it up only, the line never down and back" {
  for rate in rc_rates {
    let c = lr_case()
    let put_at = lr_line_at + 600.0
    let seen = lr_walk(
      c,
      [(put_at, fn() { c.keys.set(lr_keys([lr_sent, 71, lr_line])) })],
      put_at + lr_after_ms,
      rate,
    )
    let at = "at \{rate} a second"
    match lr_down(seen, lr_look(put_at) - 1) {
      Some(d) => fail("\{at}: \{d}")
      None => ()
    }
    for i in lr_look(put_at)..<seen.length() {
      let (y, _) = seen[i].1
      let (was, _) = seen[i - 1].1
      assert_true(y <= was + 0.5, msg="\{at}, look \{i}: the line down from \{was} to \{y}")
    }
  }
}
