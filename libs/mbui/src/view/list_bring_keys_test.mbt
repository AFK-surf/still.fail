// A page's list following its foot, at it, given keys under what shows in one change and asked in that change to bring
// one of them to its top (ListPlace::bring) or its middle (centre), as a chat's page brings its unread line with what
// came while the app was away (the coordinator of the migration, 2026-11-13: the chat's page made as nodes drew none of
// its rows then). Their ways going, the list goes down with its foot till the block asked is where it was asked and
// stays there as the rest opens under it; said `at_once`, it is there at once. What is drawn of the list covers what
// shows at every look, 10 ms apart, never an empty list; in one jump and at 60, 120, 24 and 7 a second.

///|
/// How tall what shows of the list is; the keys at first (17 rows 40 tall: at its foot), the unread line's key, 30
/// tall, and the three long messages that come under it, 300 each.
let bk_shows : Double = 400.0

///|
let bk_line : Int = 100

///|
fn bk_tall(k : Int) -> Double {
  if k == bk_line {
    30.0
  } else if k > bk_line {
    300.0
  } else {
    40.0
  }
}

///|
priv struct BkCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  place : @view.ListPlace[Int]
}

///|
/// The list, following its foot, made at it, its keys' ways their own where not `at_once`. Drawn once, at 0.
fn bk_case(at_once : Bool) -> BkCase {
  let scroll = @view.Scroll::list()
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let keys = @signals.signal(Array::makei(17, fn(i) { i }), same=fn(a, b) { a == b })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(bk_shows))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est=40.0, follows=fn() { true }, place~, at_once~, fn(b, k) {
        b.height(Is(Some(bk_tall(k)))).words(Is("行\{k}")) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, keys, place }
}

///|
/// Where what is drawn of the list fails to cover what shows (0 to bk_shows, to half a point): none, or the first gap.
fn bk_gap(t : @view.Tree) -> String? {
  let spans = t
    .drawn()
    .filter(fn(d) { d.words.has_prefix("行") && d.y < bk_shows && d.y + d.h > 0.0 })
    .map(fn(d) { (d.y, d.y + d.h) })
  spans.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut reached = 0.0
  for s in spans {
    if s.0 > reached + 0.5 {
      return Some("nothing drawn from \{reached} to \{s.0}")
    }
    if s.1 > reached {
      reached = s.1
    }
  }
  if reached < bk_shows - 0.5 {
    Some("nothing drawn from \{reached} to \{bk_shows} (\{spans.length()} blocks drawn)")
  } else {
    None
  }
}

///|
/// The case walked from the change (rc_at) for as long as a Move takes and more, 10 ms apart, at `rate`, the line
/// asked (`ask`) in the change: at each look where the line's top is drawn and what is not covered.
fn bk_walk(at_once : Bool, rate : Double, ask : (@view.ListPlace[Int]) -> Unit) -> Array[(Double, String?)] {
  let c = bk_case(at_once)
  let change = fn() {
    let ks = Array::makei(17, fn(i) { i })
    ks.append([bk_line, bk_line + 1, bk_line + 2, bk_line + 3])
    c.keys.set(ks)
    ask(c.place)
  }
  rc_walk(c.tree, [(rc_at, change)], rc_looks(rc_at + @flex.move_most_ms + 300.0), rate, fn() {
    (rc_y(c.tree, "行\{bk_line}"), bk_gap(c.tree))
  })
}

///|
/// What shows drawn at every look; the line never over where it was asked (`want`, its top), there once it reached it
/// (not drawn before that: under what shows, coming up with its foot), and there at rest; `at_once`, there from the
/// first look.
fn bk_held(seen : Array[(Double, String?)], want : Double, at_once : Bool, what : String) -> Unit raise {
  let mut reached = false
  for i, s in seen {
    let (y, gap) = s
    match gap {
      Some(g) => fail("\{what}, look \{i}: \{g}")
      None => ()
    }
    // (not drawn yet: under what shows, coming up with its foot, before it has reached where it was asked)
    if y == rc_none && !reached && !at_once {
      continue
    }
    assert_true(y > want - 1.0, msg="\{what}, look \{i}: the line at \{y}, over where it was asked (\{want})")
    if (y - want).abs() < 1.0 {
      reached = true
    }
    assert_true(
      !(reached || at_once) || (y - want).abs() < 1.0,
      msg="\{what}, look \{i}: the line at \{y}, \{want} asked",
    )
  }
  let (y, _) = seen[seen.length() - 1]
  assert_true((y - want).abs() < 1.0, msg="\{what}: the line at rest at \{y}, \{want} asked")
}

///|
test "a list at its foot, following it, given keys under what shows with one asked brought to its top in the same change: down with its foot till the block is there, there from then, what shows drawn at every look, their ways going" {
  for rate in rc_rates {
    bk_held(bk_walk(false, rate, fn(p) { p.bring(bk_line) }), 0.0, false, "at \{rate} a second")
  }
}

///|
test "the same, the block asked to the middle of what shows (Centre)" {
  for rate in rc_rates {
    let want = bk_shows / 2.0 - bk_tall(bk_line) / 2.0
    bk_held(bk_walk(false, rate, fn(p) { p.centre(bk_line) }), want, false, "centred, at \{rate} a second")
  }
}

///|
test "the same, the list said at_once: the block brought there in the one fill, what shows drawn at every look" {
  for rate in rc_rates {
    bk_held(bk_walk(true, rate, fn(p) { p.bring(bk_line) }), 0.0, true, "at once, at \{rate} a second")
  }
}

///|
test "the bring cut short by its foot still going down, the wheel up while the ways go: the list where the wheel put it from then, the block not brought, nothing going back down" {
  for rate in rc_rates {
    let c = bk_case(false)
    let change = fn() {
      let ks = Array::makei(17, fn(i) { i })
      ks.append([bk_line, bk_line + 1, bk_line + 2, bk_line + 3])
      c.keys.set(ks)
      c.place.bring(bk_line)
    }
    let wheel_at = rc_at + 40.0
    rc_walk(c.tree, [(rc_at, change)], [wheel_at - 0.5], rate, fn() { () }) |> ignore
    c.tree.wheel_at(150.0, 200.0, 0.0, -120.0, 0, wheel_at) |> ignore
    let seen = rc_walk(
      c.tree,
      [],
      rc_looks(wheel_at + @flex.move_most_ms + 300.0).filter(fn(t) { t > wheel_at }),
      rate,
      from=wheel_at - 0.5,
      fn() { (c.scroll.at(c.tree), rc_y(c.tree, "行\{bk_line}"), bk_gap(c.tree)) },
    )
    let what = "at \{rate} a second"
    for i, s in seen {
      let (x, _, gap) = s
      match gap {
        Some(g) => fail("\{what}, look \{i}: \{g}")
        None => ()
      }
      // (up by the wheel only: never down again towards the block asked)
      if i > 0 {
        let (was, _, _) = seen[i - 1]
        assert_true(x <= was + 0.5, msg="\{what}, look \{i}: the list down again, \{was} to \{x}")
      }
    }
    let (_, y, _) = seen[seen.length() - 1]
    assert_true(y == rc_none || y > 1.0, msg="\{what}: the line brought to \{y} after the wheel")
  }
}
