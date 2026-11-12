// What is pressed in a page's list stays where it was (press_stays.mbt) as what the press opens or shuts round it makes
// its way, over it or under it: what is over it read as tall as its way has it at each moment, not measured whole (as
// it was till 2026-11-12: the button went down with what opened over it). Looked at at moments it declares (rc_walk,
// list_rows_come_test's), the press told at its moment, in one jump and at 60, 120, 24 and 7 a second. A press while the
// list holds a block so (its scroll put each layout) finds what it reaches where it is drawn (Tree::bring_to: what the
// event's layout told laid out in it too; a second press of the button reached the row four under it, 2026-11-12). The
// last two, an input 88 or 150 ms after the last frame (a phone's frames hang 40 to 90 ms), told as inputs are
// (Tree::input): its layout outside its event's batch, what it sets of the slots told to the spacers' bound heights in
// it; inside the batch it laid the list's blocks out 120 lower than the frame at that moment draws them (2026-11-12).

///|
/// How tall what opens over each row's button.
let ps_ways_open : Double = 300.0

///|
/// How tall what opens over the button in the scenes of a way under way at a press: so tall that it grows past a row's
/// height between two frames, and turned back half way its way lasts past a Move's longest.
let ps_long_open : Double = 3000.0

///|
/// How long after the press opening it the second press comes, shutting it on its way.
let ps_long_again_ms : Double = 100.0

///|
/// How long after the press it is looked at, past the end of any way it set off.
let ps_ways_look_ms : Double = 1500.0

///|
/// A page's list of 12 rows, 300 wide and 400 tall: each a button 40 tall saying it opens or shuts (`expanded`) a show
/// `open` tall, over it where `over`, under it where not; with each row's button.
fn ps_ways_list(open : Double, over : Bool) -> (@view.Tree, Map[Int, @view.View]) {
  let (tree, buttons, _) = ps_ways_list_opened(open, over)
  (tree, buttons)
}

///|
/// ps_ways_list, with what each row's show made as it opened (its last).
fn ps_ways_list_opened(open : Double, over : Bool) -> (@view.Tree, Map[Int, @view.View], Map[Int, @view.View]) {
  let buttons : Map[Int, @view.View] = Map([])
  let opened : Map[Int, @view.View] = Map([])
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(win) {
      win.width(Is(Some(300.0))).height(Is(Some(400.0))) |> ignore
      win.scrolls_window(@view.Scroll::list(), fn() { Array::makei(12, fn(i) { i }) }, est=40.0, fn(b, k) {
        let on = @signals.signal(false, same=fn(a, b) { a == b })
        let opens = fn() {
          b.show(fn() { on.get() }, fn(o) {
            opened[k] = o
            o.height(Is(Some(open))) |> ignore
          })
          |> ignore
        }
        if over {
          opens()
        }
        b.box(fn(p) {
          buttons[k] = p
          p
          .height(Is(Some(40.0)))
          .shrink(Is(0.0))
          .words(Is("行\{k}"))
          .on_press(fn() { on.set(!on.untracked()) })
          .says(By(fn() { Some(@view.said(Button, label="row \{k}", expanded=on.get())) }))
          |> ignore
        })
        |> ignore
        if !over {
          opens()
        }
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  (tree, buttons, opened)
}

///|
/// Row `k`'s button in `buttons` pressed in the middle (told at its moment: rc_walk's events).
fn ps_ways_press(tree : @view.Tree, buttons : Map[Int, @view.View], k : Int) -> Unit {
  let (x, y, w, h) = buttons[k].rect()
  tree.press(x + w / 2.0, y + h / 2.0) |> ignore
}

///|
test "a page's list, a row's button pressed opening 300 over it or under it: what was pressed stays where it was at every moment of the way, the same at every rate" {
  let looks = []
  let mut at = rc_at
  while at <= rc_at + ps_ways_look_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  for over in [true, false] {
    let by_rate = rc_rates.map(fn(rate) {
      let (tree, buttons) = ps_ways_list(ps_ways_open, over)
      let was = rc_y(tree, "行3")
      let got = rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) })], looks, rate, fn() {
        rc_y(tree, "行3")
      })
      (was, got)
    })
    for i, rate in rc_rates {
      let (was, got) = by_rate[i]
      assert_eq(was, 120.0, msg="over \{over} at \{rate} a second")
      assert_true(got.iter().all(fn(y) { y == was }), msg="over \{over} at \{rate} a second: \{was} \{Repr(got)}")
      assert_eq(got, by_rate[0].1, msg="over \{over} at \{rate} a second")
    }
  }
}

///|
test "a page's list, a row's button pressed again as what it opened over it is on its way: that button reached, what was pressed stays where it was at every moment till the way turned back ends, past a Move's longest, the same at every rate" {
  let second = rc_at + ps_long_again_ms
  let looks = []
  let mut at = rc_at
  while at <= second + ps_ways_look_ms {
    looks.push(at)
    at = at + rc_look_ms
  }
  let by_rate = rc_rates.map(fn(rate) {
    let (tree, _) = ps_ways_list(ps_long_open, true)
    let was = rc_y(tree, "行3")
    // (opened at rc_at, shut on its way at `second`: its way turned back; pressed at its middle as drawn)
    let press = fn() {
      match tree.drawn().filter(fn(d) { d.words == "行3" }) {
        [d, ..] => tree.press(d.x + d.w / 2.0, d.y + d.h / 2.0) |> ignore
        _ => ()
      }
    }
    let got = rc_walk(tree, [(rc_at, press), (second, press)], looks, rate, fn() {
      (rc_y(tree, "行3"), rc_y(tree, "行7"))
    })
    (was, got)
  })
  for i, rate in rc_rates {
    let (was, got) = by_rate[i]
    assert_true(
      got.iter().all(fn(y) { (y.0 - was).abs() < 1.0e-6 && (y.1 - was - 160.0).abs() < 1.0e-6 }),
      msg="at \{rate} a second: \{was} \{Repr(got)}",
    )
    assert_eq(got, by_rate[0].1, msg="at \{rate} a second")
  }
}

///|
test "a page's list holding a pressed block as what it opened over it grows: a press at the drawn middle of each row in sight, between frames at three moments of the way, reaches that row, the same at every rate" {
  // (looked at every rc_look_ms, a frame each; a press asked 8 ms after three of them, between it and the next)
  let moments = [rc_at + 20.0, rc_at + 60.0, rc_at + 150.0]
  let looks = []
  let mut at = rc_at
  while at <= rc_at + 200.0 {
    looks.push(at)
    at = at + rc_look_ms
  }
  let by_rate = rc_rates.map(fn(rate) {
    let (tree, buttons) = ps_ways_list(ps_long_open, true)
    let reached = []
    let asks = moments.map(fn(m) {
      (m + 8.0, fn() {
        // (where each is drawn as the last frame drew it, then what a press there finds, the tree brought to the
        // press's moment as Tree::press brings it)
        let middles = Array::makei(5, fn(i) {
          match tree.drawn().filter(fn(d) { d.words == "行\{i + 3}" }) {
            [d, ..] => Some((d.x + d.w / 2.0, d.y + d.h / 2.0))
            _ => None
          }
        })
        tree.bring_to(m + 8.0)
        for i, mid in middles {
          let k = i + 3
          match mid {
            Some((x, y)) => reached.push((k, tree.target_at(x, y) is Pressed(id) && id == buttons[k].id()))
            None => reached.push((k, false))
          }
        }
      })
    })
    let events = [(rc_at, fn() { ps_ways_press(tree, buttons, 3) })]
    events.append(asks)
    rc_walk(tree, events, looks, rate, fn() { 0 }) |> ignore
    reached
  })
  for i, rate in rc_rates {
    assert_eq(by_rate[i].length(), 15, msg="at \{rate} a second")
    assert_true(by_rate[i].iter().all(fn(r) { r.1 }), msg="at \{rate} a second: \{Repr(by_rate[i])}")
  }
}

///|
test "a page's list holding a pressed block as what it opened over it grows, no frame drawn for 88 ms or 150 ms: an input then at the button's drawn middle reaches it, and the frame then and every one after shows it where it was" {
  for gap in [88.0, 150.0] {
    let (tree, buttons, opened) = ps_ways_list_opened(ps_long_open, true)
    let reached = Ref(false)
    let ask = fn() {
      match tree.drawn().filter(fn(d) { d.words == "行3" }) {
        [d, ..] => {
          tree.bring_to(rc_at + gap)
          reached.val = tree.target_at(d.x + d.w / 2.0, d.y + d.h / 2.0) is Pressed(id) && id == buttons[3].id()
        }
        _ => ()
      }
    }
    // (a frame at the press, none then till the input `gap` later, then one every rc_look_ms)
    let looks = [rc_at]
    let mut at = rc_at + gap
    while at <= rc_at + ps_ways_look_ms {
      looks.push(at)
      at = at + rc_look_ms
    }
    // (what row 3 opened over it, there and as tall as its way has it: what holds the row up is there, not none)
    let got = rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) }), (rc_at + gap, ask)], looks, 0.0, fn() {
      (rc_y(tree, "行3"), opened.get(3).map(fn(o) { if o.alive() { o.rect().3 } else { -1.0 } }).unwrap_or(-1.0))
    }, inputs=true)
    assert_true(reached.val, msg="after \{gap} ms")
    assert_true(got.iter().all(fn(y) { (y.0 - 120.0).abs() < 1.0e-6 }), msg="after \{gap} ms: \{Repr(got)}")
    assert_true(got[1:].iter().all(fn(y) { y.1 > 0.0 }), msg="after \{gap} ms, what it opened: \{Repr(got)}")
    assert_eq(got[got.length() - 1].1, ps_long_open, msg="after \{gap} ms, what it opened at its end")
  }
}

///|
test "a page's list holding a pressed block as what it opened over it grows, no frame drawn for 88 ms or 150 ms: each row in sight laid out by an input's bring then where the frame then draws it" {
  for gap in [88.0, 150.0] {
    let (tree, buttons) = ps_ways_list(ps_long_open, true)
    let laid : Array[Double] = []
    let ask = fn() {
      tree.bring_to(rc_at + gap)
      for k in 3..<8 {
        laid.push(buttons[k].rect().1)
      }
    }
    let drawn = rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) }), (rc_at + gap, ask)], [rc_at, rc_at + gap], 0.0, fn() {
      Array::makei(5, fn(i) { rc_y(tree, "行\{i + 3}") })
    }, inputs=true)
    let then = drawn[1]
    assert_eq(laid.length(), 5, msg="after \{gap} ms")
    for i in 0..<5 {
      assert_true((laid[i] - then[i]).abs() < 1.0e-6, msg="after \{gap} ms, 行\{i + 3}: laid \{laid[i]}, drawn \{then[i]}")
    }
  }
}

///|
test "a page's list holding a pressed block as what it opened over it grows, Page Down 88 ms or 150 ms after the last frame (a key told in its event, as a host tells it: no bring of its own): where its rows are drawn from then on is the same as with frames drawn till it, at every rate" {
  for gap in [88.0, 150.0] {
    let looks = [rc_at]
    let mut at = rc_at + gap
    while at <= rc_at + gap + ps_ways_look_ms {
      looks.push(at)
      at = at + rc_look_ms * 10.0
    }
    let by_rate = rc_rates.map(fn(rate) {
      let (tree, buttons) = ps_ways_list(ps_long_open, true)
      let key = fn() { tree.stroke(16, 0, rc_at + gap, from=Some(buttons[3].id())) |> ignore }
      rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) }), (rc_at + gap, key)], looks, rate, fn() {
        Array::makei(12, fn(k) { rc_y(tree, "行\{k}") })
      })
    })
    for i, rate in rc_rates {
      assert_eq(by_rate[i], by_rate[2], msg="after \{gap} ms at \{rate} a second (120 a second the other)")
    }
  }
}

///|
test "a page's list holding a pressed block as what it opened over it grows, the frames after the press 88 ms or 150 ms late, or two and then none till its end: what it opened is drawn as tall and the row pressed where they are at 120 a second, at every moment looked at" {
  let cases : Array[(String, Array[Double])] = [
    ("88", [rc_at + 88.0, rc_at + 98.0, rc_at + 300.0, rc_at + ps_ways_look_ms]),
    ("150", [rc_at + 150.0, rc_at + 160.0, rc_at + 400.0, rc_at + ps_ways_look_ms]),
    ("two then none", [rc_at + 10.0, rc_at + 20.0, rc_at + ps_ways_look_ms]),
  ]
  for c in cases {
    let (name, then) = c
    let looks = [rc_at]
    looks.append(then)
    let by_rate = [0.0, 120.0].map(fn(rate) {
      let (tree, buttons, opened) = ps_ways_list_opened(ps_long_open, true)
      rc_walk(tree, [(rc_at, fn() { ps_ways_press(tree, buttons, 3) })], looks, rate, fn() {
        let o = match opened.get(3) {
          Some(o) if o.alive() => o.rect()
          _ => (-1.0, -1.0, -1.0, -1.0)
        }
        (rc_y(tree, "行3"), o)
      }, inputs=true)
    })
    let (sparse, dense) = (by_rate[0], by_rate[1])
    assert_true(sparse.iter().all(fn(r) { (r.0 - 120.0).abs() < 1.0e-6 }), msg="\{name}: \{Repr(sparse)}")
    assert_eq(sparse[sparse.length() - 1].1.3, ps_long_open, msg="\{name}: what it opened at its end")
    assert_eq(sparse, dense, msg="\{name}: the frames as they came, then at 120 a second")
  }
}

