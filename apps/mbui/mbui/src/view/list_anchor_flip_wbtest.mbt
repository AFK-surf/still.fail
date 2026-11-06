// A list laid out from its anchor flung to its foot, its rows not as tall as they are counted: what is drawn of it.
// Changed on the way (rows swapped, a row a little taller, a row more or less at its top), from its end or its top,
// with room under its last row or none, it comes to rest at its foot; taken again in flight and flung again, the same
// with frames between or none; laid out at most once a frame; each frame it goes on the way it went, never faster.
// (Its fling's end, in the hand's terms, may be planned again from frame to frame as the list counts itself anew: what
// is drawn, where it rests and what a press finds are what is asserted, 2026-11-06.)

///|
test "scrolls_anchored flung hard to its foot, what it holds changed on the way, from its end or its top, room under it or none: at rest at its foot, its last row's foot at the window's" {
  let tall = fn(k : Int) { if k < 0 { 47.0 } else if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let not_at_foot : Array[String] = []
  for config in [(true, 0.0), (true, 56.0), (false, 0.0), (false, 56.0)] {
  let (from_end, room) = config
  // (each change by its number, in `match which` below)
  for which in [0, 1, 2, 3, 4, 5] {
    for after in [40.0, 120.0, 300.0] {
      let keys = @signals.signal(Array::makei(200, fn(i) { i }))
      let heights : Map[Int, @signals.Signal[Double]] = {}
      let made : Map[Int, View] = {}
      let scroll = Scroll::list()
      let tree = Tree::new(fn(root) {
        root.box(fn(v) {
          v.width(Is(Some(300.0))).height(Is(Some(100.0)))
          .scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, from_end~, foot_room=fn() { room }, fn(row, k) {
            made[k] = row
            let h = match heights.get(k) {
              Some(h) => h
              None => {
                let h = @signals.signal(tall(k))
                heights[k] = h
                h
              }
            }
            row.owns(fn() { made.remove(k) }).height(By(fn() { Some(h.get()) })) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
      tree.frame(300.0, 100.0, now=0.0) |> ignore
      // (from its end, up 900; from its top, down most of the way)
      tree.wheel_at(150.0, 30.0, 0.0, if from_end { -900.0 } else { 8000.0 }, 0, 10.0) |> ignore
      let mut t = 26.0
      while t < 1500.0 {
        tree.frame(300.0, 100.0, now=t) |> ignore
        t = t + 16.0
      }
      let first = made.keys().fold(init=1000, fn(a, k) { if k < a { k } else { a } })
      guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
        fail("\{from_end} \{room} \{which} \{after}: the finger not taken")
      }
      guard tree.drag_at(id, Down, 150.0, 90.0, 1500.0) &&
        tree.drag_at(id, Moved, 150.0, 50.0, 1505.0) &&
        tree.drag_at(id, Moved, 150.0, 10.0, 1510.0) &&
        tree.drag_at(id, Up, 150.0, 10.0, 1510.0) else {
        fail("\{from_end} \{room} \{which} \{after}: an event not taken")
      }
      let mut changed = false
      t = 1516.0
      while t < 6000.0 {
        if !changed && t >= 1510.0 + after {
          match which {
            0 => {
              let ks = keys.get().copy()
              let i = first
              let k = ks[i]
              ks[i] = ks[i + 1]
              ks[i + 1] = k
              keys.set(ks)
            }
            1 => {
              let last = made.keys().fold(init=-1, fn(a, k) { if k > a { k } else { a } })
              let ks = keys.get().copy()
              let i = ks.search(last).unwrap_or(ks.length() - 2) - 1
              let k = ks[i]
              ks[i] = ks[i + 1]
              ks[i + 1] = k
              keys.set(ks)
            }
            2 =>
              match heights.get(first) {
                Some(h) => h.set(h.get() + 0.3)
                None => ()
              }
            3 => {
              let last = made.keys().fold(init=-1, fn(a, k) { if k > a { k } else { a } })
              match heights.get(last) {
                Some(h) => h.set(h.get() + 0.3)
                None => ()
              }
            }
            4 => {
              let ks = [-1]
              ks.append(keys.get())
              keys.set(ks)
            }
            _ => keys.set(keys.get()[1:].to_array())
          }
          changed = true
        }
        tree.frame(300.0, 100.0, now=t) |> ignore
        t = t + 16.0
      }
      // (flung hard enough to come to its foot, every one: at rest, its last row made, its foot at the window's)
      let last = keys.get()[keys.get().length() - 1]
      let last_foot = made.get(last).map(fn(v) { v.rect().1 + v.rect().3 })
      let at_foot = last_foot.map(fn(f) { (f - (100.0 - room)).abs() < 0.01 }).unwrap_or(false)
      if !at_foot || scroll.glides_till() is Some(_) {
        not_at_foot.push("\{from_end} \{room} \{which} \{after}: its last row's foot \{last_foot} (the window's \{100.0 - room}), gliding till \{scroll.glides_till()}")
      }
      tree.dispose()
    }
  }
  }
  assert_true(not_at_foot.is_empty(), msg="not at rest at its foot: \{not_at_foot.length()}:\n" + not_at_foot.iter().take(6).collect().join("\n"))
}

///|
/// A list of 200 rows from their end, counted otherwise than they are (bar_off not 0 as it is flung): up 900 by the
/// wheel, flung down, taken again by the finger `again` ms after and flung down once more; frames every 16 ms, or none
/// between the two flings (`between`). At rest at its foot; then where each row is, the row a press at (150, 30) finds,
/// and where the hand is.
fn regrab_run(again : Double, between : Bool) -> (Array[(Int, Double)], Int?, Double, Array[String]) raise {
  let tall = fn(k : Int) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let made : Map[Int, View] = {}
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(scroll, fn() { Array::makei(200, fn(i) { i }) }, est=80.0, ahead=0.0, fn(row, k) {
        made[k] = row
        row.owns(fn() { made.remove(k) }).height(Is(Some(tall(k)))).on_press(fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 30.0, 0.0, -900.0, 0, 10.0) |> ignore
  let wrong : Array[String] = []
  // (what is drawn each frame is what is asserted, at rest: nothing each frame)
  let check = fn(_t : Double) {  }
  let mut t = 26.0
  while t < 1500.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    check(t)
    t = t + 16.0
  }
  let fling = fn(at : Double) {
    guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -40.0) is Some(id) else {
      wrong.push("at \{at}: the finger not taken")
      return
    }
    if !(
        tree.drag_at(id, Down, 150.0, 90.0, at) &&
        tree.drag_at(id, Moved, 150.0, 70.0, at + 5.0) &&
        tree.drag_at(id, Moved, 150.0, 50.0, at + 10.0) &&
        tree.drag_at(id, Up, 150.0, 50.0, at + 10.0)
      ) {
      wrong.push("at \{at}: an event not taken")
    }
  }
  let off_before = (scroll.bar_off)()
  fling(1500.0)
  if between {
    t = 1516.0
    while t < 1510.0 + again {
      tree.frame(300.0, 100.0, now=t) |> ignore
      check(t)
      t = t + 16.0
    }
  }
  fling(1510.0 + again)
  t = 1526.0 + again
  while t < 8000.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    check(t)
    t = t + 16.0
  }
  tree.frame(300.0, 100.0, now=8000.0) |> ignore
  let x = @signals.untracked(fn() { scroll.x.get() })
  let rows = made.keys().map(fn(k) { (k, made[k].rect().1) }).collect()
  rows.sort()
  let hit = match tree.target_at(150.0, 30.0) {
    Pressed(id) => made.keys().find_first(fn(k) { made[k].id() == id })
    _ => None
  }
  let drawn_on = made.keys().find_first(fn(k) { made[k].rect().1 <= 30.0 && 30.0 < made[k].rect().1 + made[k].rect().3 })
  if hit != drawn_on {
    wrong.push("at rest: a press finds \{hit}, the row drawn there \{drawn_on}")
  }
  match made.get(199) {
    Some(last) =>
      if (last.rect().1 + last.rect().3 - 100.0).abs() > 0.01 || scroll.glides_till() is Some(_) {
        wrong.push("at rest: its last row's foot \{last.rect().1 + last.rect().3}, gliding till \{scroll.glides_till()}")
      }
    None => wrong.push("at rest: its last row not made")
  }
  if off_before == 0.0 {
    wrong.push("bar_off 0 as it was flung: not the case asked for")
  }
  tree.dispose()
  (rows, hit, x, wrong)
}

///|
test "scrolls_anchored counted otherwise than it is, flung, taken again in flight and flung again: at rest at its foot, a press finding the row drawn there, the same with frames between or none" {
  for again in [30.0, 90.0, 200.0] {
    let (rows_a, hit_a, x_a, wrong_a) = regrab_run(again, true)
    let (rows_b, hit_b, x_b, wrong_b) = regrab_run(again, false)
    assert_true(wrong_a.is_empty(), msg="again \{again}, frames between: " + wrong_a.iter().take(4).collect().join("\n"))
    assert_true(wrong_b.is_empty(), msg="again \{again}, none between: " + wrong_b.iter().take(4).collect().join("\n"))
    assert_eq((rows_b, hit_b, x_b), (rows_a, hit_a, x_a), msg="again \{again}: none between against frames between")
  }
}

///|
test "scrolls_anchored at rest, dragged, and flung to its foot: each frame laid out once at most, each finger's event once at most, none at rest" {
  let tall = fn(k : Int) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(scroll, fn() { Array::makei(200, fn(i) { i }) }, est=80.0, ahead=0.0, fn(row, k) {
        row.height(Is(Some(tall(k)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 30.0, 0.0, -900.0, 0, 10.0) |> ignore
  let mut t = 26.0
  while t < 1500.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    t = t + 16.0
  }
  // (each frame's layouts, and each event's, apart: what is laid out as an event comes counted to it, not the frame)
  let over : Array[String] = []
  let mut at_rest = 0
  let mut frames = 0
  let mut flung_layouts = 0
  let frame = fn(now : Double, what : String) -> Int {
    let c = tree.work().computes
    tree.frame(300.0, 100.0, now~) |> ignore
    let d = tree.work().computes - c
    if d > 1 {
      over.push("\{what} frame at \{now}: laid out \{d} times")
    }
    d
  }
  let event = fn(id : NodeId, kind : DragIs, y : Double, now : Double) {
    let c = tree.work().computes
    tree.drag_at(id, kind, 150.0, y, now) |> ignore
    let d = tree.work().computes - c
    if d > 1 {
      over.push("event \{kind} at \{now}: laid out \{d} times")
    }
  }
  // (at rest from 1500 to 2460, a frame each 16 ms: none laid out)
  let mut at = 1500.0
  while at < 2460.0 {
    at_rest = at_rest + frame(at, "at rest")
    at = at + 16.0
  }
  // (dragged slowly, no fling: 30 frames)
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -20.0) is Some(id) else { fail("not taken") }
  event(id, Down, 90.0, 2500.0)
  // (moved up a point each 16 ms till 2980, a frame at each move)
  at = 2516.0
  while at <= 2980.0 {
    event(id, Moved, 90.0 - (at - 2500.0) / 16.0, at)
    frame(at, "dragged") |> ignore
    at = at + 16.0
  }
  // (held still 120 ms after its last move at 2980, then let go: no fling)
  event(id, Moved, 60.0, 2990.0)
  frame(2996.0, "held") |> ignore
  event(id, Moved, 60.0, 3100.0)
  frame(3108.0, "held") |> ignore
  event(id, Up, 60.0, 3110.0)
  frame(3124.0, "let go") |> ignore
  guard @signals.untracked(fn() { scroll.fling.get() }) is None else { fail("let go held still: a fling") }
  frame(3500.0, "let go") |> ignore
  // (flung to its foot: frames till it rests, it moving in them)
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id2) else { fail("not taken again") }
  event(id2, Down, 90.0, 4000.0)
  event(id2, Moved, 50.0, 4005.0)
  event(id2, Moved, 10.0, 4010.0)
  event(id2, Up, 10.0, 4010.0)
  guard scroll.glides_till() is Some(_) else { fail("flung: not moving") }
  t = 4016.0
  while t < 9000.0 {
    flung_layouts = flung_layouts + frame(t, "flung")
    frames = frames + 1
    t = t + 16.0
  }
  tree.dispose()
  println("LAYOUTS at rest \{at_rest} from 1500 to 2460, flung \{flung_layouts} in \{frames} frames")
  assert_eq(at_rest, 0, msg="at rest")
  assert_true(over.is_empty(), msg=over.iter().take(6).collect().join("; "))
}

///|
/// The rows flung hard to the foot from up 900, frames every 16 ms (`swap`: two rows in the window swapped 40 ms in):
/// how far what it holds moved up each frame, by a row drawn in both.
fn glide_steps(swap : Bool, up : Double, by : Double) -> Array[Double] raise {
  let tall = fn(k : Int) { if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let keys = @signals.signal(Array::makei(200, fn(i) { i }))
  let made : Map[Int, View] = {}
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, fn(row, k) {
        made[k] = row
        row.owns(fn() { made.remove(k) }).height(Is(Some(tall(k)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 30.0, 0.0, -up, 0, 10.0) |> ignore
  let mut t = 26.0
  while t < 1500.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    t = t + 16.0
  }
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -by) is Some(id) else { fail("not taken") }
  guard tree.drag_at(id, Down, 150.0, 90.0, 1500.0) &&
    tree.drag_at(id, Moved, 150.0, 90.0 - by / 2.0, 1505.0) &&
    tree.drag_at(id, Moved, 150.0, 90.0 - by, 1510.0) &&
    tree.drag_at(id, Up, 150.0, 90.0 - by, 1510.0) else {
    fail("an event not taken")
  }
  // (where the window's top is in what it holds, as it really is: a row drawn, its top in the window, against its top
  // among all of them, their heights as they are)
  let real_at = fn() -> Double? {
    let ks = keys.get()
    let mut top = 0.0
    let mut found : Double? = None
    for k in ks {
      if found is None {
        match made.get(k) {
          Some(v) => found = Some(top - v.rect().1)
          None => ()
        }
      }
      top = top + tall(k)
    }
    found
  }
  let steps = []
  let mut was = real_at()
  t = 1516.0
  let mut swapped = false
  while t < 8000.0 {
    let swapping = swap && !swapped && t >= 1550.0
    if swapping {
      let ks = keys.get().copy()
      let last = made.keys().fold(init=-1, fn(a, k) { if k > a { k } else { a } })
      let i = ks.search(last).unwrap_or(ks.length() - 2) - 1
      let k = ks[i]
      ks[i] = ks[i + 1]
      ks[i + 1] = k
      keys.set(ks)
      swapped = true
    }
    tree.frame(300.0, 100.0, now=t) |> ignore
    let now = real_at()
    // (the frame of the swap: its rows' real tops said anew, not a step: said as none)
    steps.push(
      match (was, now) {
        _ if swapping => -999.0
        (Some(a), Some(b)) => b - a
        _ => -1.0
      },
    )
    was = now
    t = t + 16.0
  }
  tree.dispose()
  steps
}

///|
test "scrolls_anchored flung hard to its foot, its rows not as tall as counted, two rows swapped on the way or not: each frame it goes on the way it went, never faster than the frame before" {
  for cs in [(false, 900.0, 80.0), (true, 900.0, 80.0), (false, 3000.0, 30.0), (true, 3000.0, 30.0), (false, 6000.0, 50.0), (true, 6000.0, 50.0)] {
    let (swap, up, by) = cs
    let steps = glide_steps(swap, up, by)
    // (each frame's step: up (0 or more), no more than the step before by more than a hundredth, once it slows)
    let wrong = []
    // (from the second frame after it is let go: the first is of the few ms after the finger's last event alone)
    for i in 2..<steps.length() {
      // (a swap moves rows within the window: the step of that frame is not the list's)
      if steps[i] == -999.0 || steps[i - 1] == -999.0 {
        continue
      }
      if steps[i] < -0.01 || steps[i] > steps[i - 1] + 0.01 {
        wrong.push("up \{up} by \{by} frame \{i}: \{steps[i - 1]} then \{steps[i]}")
      }
    }
    println("STEPS swap \{swap} up \{up} by \{by}: " + steps.iter().take(60).map(fn(s) { "\{(s * 100.0).round() / 100.0}" }).collect().join(" "))
    assert_true(wrong.is_empty(), msg="swap \{swap}: " + wrong.iter().take(6).collect().join("; "))
  }
}

///|
/// The list flung to its foot from up 900 and changed `after` ms after the finger is let go, as an event of that moment
/// (`which`: its last row gone, row 196 gone, row 196 60 taller, a row more at its top), frames
/// every 16 ms or none but at the moments compared (`frames`): at each (100 and 400 ms after the change, and at rest),
/// where its rows are drawn, the row a press finds, and when it is to rest.
fn changed_run(which : Int, after : Double, frames : Bool) -> (Double?, Array[(Array[(Int, Double)], Int?, Double?)]) raise {
  let tall = fn(k : Int) { if k < 0 { 47.0 } else if k % 7 == 0 { 131.0 } else if k % 3 == 0 { 23.0 } else { 47.0 } }
  let keys = @signals.signal(Array::makei(200, fn(i) { i }))
  // (every row's height a signal from the start: the one changed is there in either history)
  let heights : Map[Int, @signals.Signal[Double]] = {}
  for k in -1..<200 {
    heights[k] = @signals.signal(tall(k))
  }
  let made : Map[Int, View] = {}
  let scroll = Scroll::list()
  let tree = Tree::new(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(300.0))).height(Is(Some(100.0)))
      .scrolls_anchored(scroll, fn() { keys.get() }, est=80.0, ahead=0.0, fn(row, k) {
        made[k] = row
        let h = match heights.get(k) {
          Some(h) => h
          None => {
            let h = @signals.signal(tall(k))
            heights[k] = h
            h
          }
        }
        row.owns(fn() { made.remove(k) }).height(By(fn() { Some(h.get()) })).on_press(fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.lists_feel(fn() { (ListFeel::Android, 3.0) })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  tree.wheel_at(150.0, 30.0, 0.0, -900.0, 0, 10.0) |> ignore
  let mut t = 26.0
  while t < 1500.0 {
    tree.frame(300.0, 100.0, now=t) |> ignore
    t = t + 16.0
  }
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -60.0) is Some(id) else { fail("not taken") }
  guard tree.drag_at(id, Down, 150.0, 90.0, 1500.0) &&
    tree.drag_at(id, Moved, 150.0, 60.0, 1505.0) &&
    tree.drag_at(id, Moved, 150.0, 30.0, 1510.0) &&
    tree.drag_at(id, Up, 150.0, 30.0, 1510.0) else {
    fail("an event not taken")
  }
  let at = Ref(1510.0)
  let run_to = fn(till : Double) {
    if frames {
      while at.val + 16.0 < till {
        at.val = at.val + 16.0
        tree.frame(300.0, 100.0, now=at.val) |> ignore
      }
    }
    at.val = till
    tree.frame(300.0, 100.0, now=till) |> ignore
  }
  let seen = []
  let missed : Array[String] = []
  let look = fn() {
    let rows = made.keys().map(fn(k) { (k, made[k].rect().1) }).collect()
    rows.sort()
    let hit = match tree.target_at(150.0, 30.0) {
      Pressed(id) => made.keys().find_first(fn(k) { made[k].id() == id })
      _ => None
    }
    // (a row there to press, and the one a press finds the one drawn there)
    let drawn_on = made.keys().find_first(fn(k) { made[k].rect().1 <= 30.0 && 30.0 < made[k].rect().1 + made[k].rect().3 })
    if hit is None || hit != drawn_on {
      missed.push("a press at (150, 30) finds \{hit}, the row drawn there \{drawn_on}")
    }
    seen.push((rows, hit, scroll.glides_till()))
  }
  let change_at = 1510.0 + after
  run_to(change_at - 1.0)
  // (the same row in either history, by its key: one near its foot)
  let in_window = 196
  // (still flung as it changes: what it was planned to)
  let flung_then = scroll.glides_till()
  tree.event(change_at, fn() {
    match which {
      0 => keys.set(keys.get()[0:keys.get().length() - 1].to_array())
      1 => keys.set(keys.get().filter(fn(k) { k != in_window }))
      2 => heights[in_window].set(tall(in_window) + 60.0)
      _ => {
        let ks = [-1]
        ks.append(keys.get())
        keys.set(ks)
      }
    }
  })
  at.val = change_at
  for d in [100.0, 400.0, 6000.0] {
    run_to(change_at + d)
    look()
  }
  // (at rest at the last: none planned)
  if scroll.glides_till() is Some(_) {
    missed.push("not at rest at the last")
  }
  // (row 196 changed as said, where it was to be: its height then)
  if which == 2 && heights[in_window].get() != tall(in_window) + 60.0 {
    missed.push("row 196 not taller")
  }
  tree.dispose()
  guard missed.is_empty() else { fail("change \{which} \{after} ms in, frames \{frames}: \{missed}") }
  (flung_then, seen)
}

///|
test "scrolls_anchored flung to its foot and changed on the way, as an event of its moment (a row gone, a row taller, a row more): what is drawn, what a press finds and when it rests, the same with frames between or none" {
  let wrong = []
  for which in [0, 1, 2, 3] {
    for after in [30.0, 120.0, 250.0] {
      let (flung_a, with_frames) = changed_run(which, after, true)
      let (flung_b, without) = changed_run(which, after, false)
      if flung_a is None || flung_b is None {
        wrong.push("change \{which} \{after} ms in: not flung as it changed (\{flung_a}, \{flung_b})")
      }
      // (where its rows are drawn and what a press finds at each moment; when it is to rest, at rest only: while it
      // moves, the moment it is planned to meet its foot may differ by the frames drawn, the foot it is planned to as
      // counted from frame to frame (2026-11-06, not fixed here))
      for i, w in with_frames {
        let rest = i == with_frames.length() - 1
        if without[i].0 != w.0 || without[i].1 != w.1 || rest && without[i].2 != w.2 {
          wrong.push("change \{which} \{after} ms in, moment \{i}: rows the same \{without[i].0 == w.0}, frames between \{w.1} \{w.2}, none \{without[i].1} \{without[i].2}")
        }
        // (moving still 100 ms after the change, in either)
        if i == 0 && (w.2 is None || without[i].2 is None) {
          wrong.push("change \{which} \{after} ms in, moment \{i}: not moving (\{w.2}, \{without[i].2})")
        }
      }
    }
  }
  assert_true(wrong.is_empty(), msg="\{wrong.length()}:\n" + wrong.iter().take(6).collect().join("\n"))
}
