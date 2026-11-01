// A button's ground and its words going together for its words' change (moves_together: the ground changing shape,
// the words going), as an old view's do (reshape and layout with the same cause, a Move together as
// long as the furthest goes): on the way and at its end; frames drawn all along or none; turned back half way; changed
// twice with no frame between; moved by nothing it moves for, at once; at rest, the clock read no more.

///|
let short_words : String = "Copy"

///|
let long_words : String = "Copied to the clipboard"

///|
/// What is drawn of a button: its ground (x, width) and its words' first glyph (x).
fn button_seen(t : @ui.Tester) -> (Double, Double, Double) {
  let rects = t.drawn_rects().filter(fn(r) { r.4 == 0x3366CCFFL })
  let g = t.drawn_glyphs()
  match (rects.get(0), g.get(0)) {
    (Some(r), Some(f)) => (r.0, r.2, f.0)
    _ => (-1.0, -1.0, -1.0)
  }
}

///|
/// A button at the window's top, in its middle across, its words as `words` says: an old view's (reshape and layout by
/// its words) or the tree's (moves_together). The Tester.
fn button_pair(
  words : @signals.Signal[String],
  node : Bool,
  w? : @signals.Signal[Double] = @signals.signal(400.0),
  group? : Ref[MoveGroup?] = Ref(None),
  half? : Bool = false,
) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        let outer = c.box(w=Px(w.get()), align=ACenter, fn() {
          let label = words.get()
          let mut at = -1
          let b = c.box(dir=Row, h=Px(36.0), padx=16.0, bg=0x3366CCFFL, radius=18.0, align=ACenter, fn() {
            at = c.text(label, size=13.0, line=18.0, wrap=false, color=0xFFFFFFFFL)
          })
          reshape(c, b, "t/shape", by=label, spec=move())
          layout(c, at, "t/words", by=label, spec=move())
        })
        if half {
          c.look(outer, @ui.look(scale=0.5))
        }
      }
    },
    w=400.0,
    h=200.0,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(o) {
        o.width(By(fn() { Some(w.get()) })).lines_up(Is(Some(Middle))).scale(Is(if half { 0.5 } else { 1.0 })) |> ignore
        o.box(fn(b) {
          b.row(Is(true)).height(Is(Some(36.0))).padding(Is((16.0, 0.0, 16.0, 0.0))).ground(Is(0x3366CCFFL)).radius(Is(18.0)).lines_up(Is(Some(Middle))) |> ignore
          let words_at = b.box(fn(k) {
            k.words(By(fn() { words.get() }), ink=0xFFFFFFFFL, look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore
          })
          let g = moves_together(b, fn() { words.get() })
          g.add(b, reshapes=true)
          g.add(words_at)
          group.val = Some(g)
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
fn seen_near(a : (Double, Double, Double), b : (Double, Double, Double)) -> Bool {
  (a.0 - b.0).abs() <= 1.0e-9 && (a.1 - b.1).abs() <= 1.0e-9 && (a.2 - b.2).abs() <= 1.0e-9
}

///|
test "a button's words longer, then shorter again: its ground and its words where an old view's go, on the way and at the end (the old one's way set off at its first frame after the change, 16 later here)" {
  let seen = fn(node : Bool) {
    let words = @signals.signal(short_words, same=fn(a, b) { a == b })
    let t = button_pair(words, node)
    let rest = button_seen(t)
    let lag = if node { 0.0 } else { 16.0 }
    let out = [rest]
    for change in [long_words, short_words] {
      let t0 = t.time()
      words.set(change)
      t.frame_at(t0 + 16.0)
      for at in [40.0, 100.0, 200.0, past_all_ms] {
        t.frame_at(t0 + lag + at)
        out.push(button_seen(t))
      }
    }
    out
  }
  let old = seen(false)
  let new = seen(true)
  let same = Array::makei(old.length(), fn(k) { seen_near(old[k], new[k]) })
  assert_eq(same, Array::make(old.length(), true), msg="old \{old}\nnode \{new}")
}

///|
/// The node's button, its words made longer at its moment, looked at `at` after: frames all along, or none before.
fn node_at(at : Double, stepped : Bool) -> (Double, Double, Double) {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let t = button_pair(words, true)
  let t0 = t.time()
  words.set(long_words)
  if stepped {
    while t.time() + 16.0 < t0 + at {
      t.frame_at(t.time() + 16.0)
    }
  }
  t.frame_at(t0 + at)
  button_seen(t)
}

///|
test "a button's words longer: at each moment the same, frames drawn all along or none before it" {
  let moments = [16.0, 60.0, 120.0, 240.0]
  let all = moments.map(fn(at) { node_at(at, true) })
  let none = moments.map(fn(at) { node_at(at, false) })
  assert_eq(Array::makei(4, fn(k) { seen_near(all[k], none[k]) }), [true, true, true, true], msg="\{all}\n\{none}")
}

///|
///|
/// The node's button told "Copied" long at 0, the short words at 70 and "Copied" at 80, looked at 90 and once all of
/// it is over: frames drawn every 16 all along, or none till 90. What is drawn then, and the group.
fn three_changes(stepped : Bool) -> ((Double, Double, Double), (Double, Double, Double), Bool) {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let group : Ref[MoveGroup?] = Ref(None)
  let t = button_pair(words, true, group~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  let tell = fn(at : Double, said : String) {
    if stepped {
      while t.time() + 16.0 < t0 + at {
        t.frame_at(t.time() + 16.0)
      }
    }
    t.advance(t0 + at - t.time())
    tree.event(t.time(), fn() { words.set(said) })
  }
  tell(0.0, long_words)
  tell(70.0, short_words)
  tell(80.0, "Copied")
  if stepped {
    while t.time() + 16.0 < t0 + 90.0 {
      t.frame_at(t.time() + 16.0)
    }
  }
  t.frame_at(t0 + 90.0)
  let at_90 = button_seen(t)
  t.run_for(past_all_ms)
  // (whether its tree reads the clock still, at rest: read before another Tester makes another tree)
  (at_90, button_seen(t), tree.clock_read())
}

///|
/// Longer than any of a button's ways here takes.
let past_all_ms : Double = 1000.0

///|
test "a button's words longer, the short ones 70 after and others 80 after, no frame needed between: the same at 90 and at its end, frames drawn all along or none; at its end where the last words lay it out at rest, the clock read no more" {
  let (a90, a_end, a_clock) = three_changes(true)
  let (b90, b_end, b_clock) = three_changes(false)
  // (the last words at rest, in a button of their own)
  let words = @signals.signal("Copied", same=fn(a, b) { a == b })
  let rest = button_seen(button_pair(words, true))
  assert_eq(
    (seen_near(a90, b90), seen_near(a_end, b_end), seen_near(b_end, rest), a_clock, b_clock),
    (true, true, true, false, false),
    msg="\{a90} \{b90}; \{a_end} \{b_end} \{rest}",
  )
}

///|
test "a button's words longer, then the short ones at 70: each way set off from where the one before had it at 70, as fast as it went then" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let group : Ref[MoveGroup?] = Ref(None)
  let t = button_pair(words, true, group~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { words.set(long_words) })
  let g = group.val.unwrap()
  // (each way of each as the first change set it off: where it is at 70 and how fast)
  let before = g.movers.map(fn(m) { m.ways.map(fn(w) { w.way.at(t0 + turned_back_ms) }) })
  t.advance(t0 + turned_back_ms - t.time())
  tree.event(t.time(), fn() { words.set(short_words) })
  let after = g.movers.map(fn(m) { m.ways.map(fn(w) { w.way.at(t0 + turned_back_ms) }) })
  // (the same where each was and as fast, in the window's terms, whatever its layout did meanwhile: nothing here)
  let near = fn(a : (Double, Double), b : (Double, Double)) { (a.0 - b.0).abs() <= 1.0e-9 && (a.1 - b.1).abs() <= 1.0e-9 }
  let same = Array::makei(before.length(), fn(i) { Array::makei(4, fn(k) { near(before[i][k], after[i][k]) }) })
  assert_eq(same, Array::make(before.length(), Array::make(4, true)), msg="\{before}\n\{after}")
}

///|
/// The node's button growing for its words from 0, what holds it made narrower at 50, its words changed again at 60:
/// a frame drawn at 50 between or none; what is drawn at 60 as the last change is told, and just before it.
fn narrowed_then_changed(
  frame_between : Bool,
  timed? : Bool = false,
  direct? : Bool = false,
) -> ((Double, Double, Double), (Double, Double, Double)) {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  if direct {
    // (both signals set from outside the tree at their moments, nothing drawn between)
    t.advance(t0 + 50.0 - t.time())
    w.set(300.0)
    t.advance(t0 + 60.0 - t.time())
    words.set("Copied")
    t.frame_at(t.time())
  } else if timed {
    // (both at moments of the tree's timeline, nothing drawn between: at_moment's)
    tree.root().at_moment(t0 + 50.0, fn() { w.set(300.0) }) |> ignore
    tree.root().at_moment(t0 + 60.0, fn() { words.set("Copied") }) |> ignore
    t.frame_at(t0 + 60.0)
  } else {
    t.advance(t0 + 50.0 - t.time())
    tree.event(t.time(), fn() { w.set(300.0) })
    if frame_between {
      t.frame_at(t.time())
    }
    t.advance(t0 + 60.0 - t.time())
    tree.event(t.time(), fn() { words.set("Copied") })
    t.frame_at(t.time())
  }
  let told = button_seen(t)
  (told, told)
}

///|
test "a button growing for its words while what holds it is made narrower, then its words changed again: drawn where it was as the change is told, a frame drawn between the two or none" {
  // (where it is at 60, narrowed at 50, its words not changed again)
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  t.advance(t0 + 50.0 - t.time())
  tree.event(t.time(), fn() { w.set(300.0) })
  t.frame_at(t0 + 60.0)
  let left_alone = button_seen(t)
  let (with_frame, _) = narrowed_then_changed(true)
  let (no_frame, _) = narrowed_then_changed(false)
  let (timed, _) = narrowed_then_changed(false, timed=true)
  let (direct, _) = narrowed_then_changed(false, direct=true)
  assert_true(
    seen_near(left_alone, with_frame) &&
    seen_near(left_alone, no_frame) &&
    seen_near(left_alone, timed) &&
    seen_near(left_alone, direct),
    msg="\{left_alone} \{with_frame} \{no_frame} \{timed} \{direct}",
  )
}

///|
test "a button's words let go of while it goes: from that moment no more of it, not counted, its group set off again without it; at rest, the clock read no more" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let group : Ref[MoveGroup?] = Ref(None)
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.row(Is(true)).height(Is(Some(36.0))).ground(Is(0x3366CCFFL)) |> ignore
      let g = moves_together(b, fn() { words.get() })
      g.add(b, reshapes=true)
      b.show(fn() { shown.get() }, fn(k) {
        k.words(By(fn() { words.get() }), look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore
        g.add(k)
      })
      group.val = Some(g)
    })
    |> ignore
  })
  t.draw()
  let g = group.val.unwrap()
  let tree = @ui.view_tree().unwrap()
  let t0 = t.time()
  // (on its way, both of it)
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  let both = g.movers.length()
  // (its words let go of on the way: no more of it as that is told)
  tree.event(t.time(), fn() { shown.set(false) })
  let left = g.movers.length()
  // (set off again: only what is left of it goes)
  tree.event(t.time(), fn() { words.set(short_words) })
  let going = g.movers.length()
  t.run_for(past_all_ms)
  assert_eq((both, left, going, tree.clock_read()), (2, 1, 1, false))
}

///|
/// A row 3.3 in from its sides at the window's top, in its middle: room `room.get()` wide, a box of its own (2.7 in, its
/// words "Hi"), and a dot 10.5 across that is not said to go; the row and the box going for `room` (an old view's layout,
/// or the tree's moves_together, the box said first where `box_first`). The Tester.
fn nested_pair(room : @signals.Signal[Double], node : Bool, box_first? : Bool = false) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        c.box(w=Px(400.0), align=ACenter, fn() {
          let r = room.get()
          let mut inner = -1
          let row = c.box(dir=Row, padx=3.3, bg=0x20A040FFL, align=ACenter, fn() {
            c.box(w=Px(r), h=Px(4.0), fn() {  }) |> ignore
            inner = c.box(pad=2.7, bg=0x3366CCFFL, fn() { c.text("Hi", size=13.0, line=18.0, wrap=false, color=0xFFFFFFFFL) |> ignore })
            c.box(w=Px(10.5), h=Px(10.5), bg=0xCC3333FFL, fn() {  }) |> ignore
          })
          layout(c, row, "t/row", by=r.to_string(), spec=move())
          layout(c, inner, "t/inner", by=r.to_string(), spec=move())
        })
        |> ignore
      }
    },
    w=400.0,
    h=200.0,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(400.0))).lines_up(Is(Some(Middle))) |> ignore
        o.box(fn(row) {
          row.row(Is(true)).padding(Is((3.3, 0.0, 3.3, 0.0))).ground(Is(0x20A040FFL)).lines_up(Is(Some(Middle))) |> ignore
          row.box(fn(sp) { sp.width(By(fn() { Some(room.get()) })).height(Is(Some(4.0))) |> ignore }) |> ignore
          let inner = row.box(fn(b) {
            b.pad(Is(2.7)).ground(Is(0x3366CCFFL)) |> ignore
            b.box(fn(k) { k.words(Is("Hi"), ink=0xFFFFFFFFL, look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore }) |> ignore
          })
          row.box(fn(d) { d.width(Is(Some(10.5))).height(Is(Some(10.5))).ground(Is(0xCC3333FFL)) |> ignore }) |> ignore
          let g = moves_together(row, fn() { room.get() })
          if box_first {
            g.add(inner)
            g.add(row)
          } else {
            g.add(row)
            g.add(inner)
          }
        })
        |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
/// Where the row, its box, its dot and its words are drawn across: each rect's x by its colour, the first glyph's x.
fn nested_seen(t : @ui.Tester) -> Array[Double] {
  let x_of = fn(colour : Int64) {
    match t.drawn_rects().iter().find_first(fn(r) { r.4 == colour }) {
      Some(r) => r.0
      None => -1.0
    }
  }
  let g = match t.drawn_glyphs().get(0) {
    Some(f) => f.0
    None => -1.0
  }
  [x_of(0x20A040FFL), x_of(0x3366CCFFL), x_of(0xCC3333FFL), g]
}

///|
test "a row and a box in it going together, what is in it not said to go carried with the row once: where an old view's go on the way and at the end, the box said first or last" {
  let seen = fn(node : Bool, box_first : Bool) {
    let room = @signals.signal(20.25, same=fn(a, b) { a == b })
    let t = nested_pair(room, node, box_first~)
    let lag = if node { 0.0 } else { 16.0 }
    let out = [nested_seen(t)]
    for r in [70.75, 20.25] {
      let t0 = t.time()
      room.set(r)
      t.frame_at(t0 + 16.0)
      for at in [40.0, 100.0, 200.0, past_all_ms] {
        t.frame_at(t0 + lag + at)
        out.push(nested_seen(t))
      }
    }
    out
  }
  let old = seen(false, false)
  let near = fn(a : Array[Double], b : Array[Double]) { a.length() == b.length() && a.iter().zip(b.iter()).all(fn(p) { (p.0 - p.1).abs() <= 1.0e-9 }) }
  let row_first = seen(true, false)
  let box_first = seen(true, true)
  let same = Array::makei(old.length(), fn(k) { (near(old[k], row_first[k]), near(old[k], box_first[k])) })
  assert_eq(same, Array::make(old.length(), (true, true)), msg="old \{old}\nnode \{row_first}\nbox first \{box_first}")
}

///|
test "a button in a box made narrower, its words the same: where it is laid out at once, no way of its own set off" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let before = button_seen(t)
  w.set(300.0)
  t.frame()
  let after = button_seen(t)
  assert_eq(((before.0 - after.0) * 1000.0).round(), 50000.0, msg="\{before} \{after}")
  assert_true(!@ui.view_tree().unwrap().clock_read())
}

///|
test "a button in a box drawn half as big about its middle, its words longer then shorter: where an old view's go, on the way and at the end; its ground where it was as the change is told" {
  let seen = fn(node : Bool) {
    let words = @signals.signal(short_words, same=fn(a, b) { a == b })
    let t = button_pair(words, node, half=true)
    let lag = if node { 0.0 } else { 16.0 }
    let out = [button_seen(t)]
    for change in [long_words, short_words] {
      let t0 = t.time()
      words.set(change)
      t.frame_at(t0 + 16.0)
      for at in [40.0, 100.0, 200.0, past_all_ms] {
        t.frame_at(t0 + lag + at)
        out.push(button_seen(t))
      }
    }
    out
  }
  let old = seen(false)
  let new = seen(true)
  // (as the change is told, before any of its way: the node's ground where it was)
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let t = button_pair(words, true, half=true)
  let before = button_seen(t)
  @ui.view_tree().unwrap().event(t.time(), fn() { words.set(long_words) })
  t.frame_at(t.time())
  let told = button_seen(t)
  let ground_same = (before.0 - told.0).abs() <= 1.0e-9 && (before.1 - told.1).abs() <= 1.0e-9
  let same = Array::makei(old.length(), fn(k) { seen_near(old[k], new[k]) })
  assert_eq((same, ground_same), (Array::make(old.length(), true), true), msg="old \{old}\nnode \{new}\n\{before} \{told}")
}

///|
/// The node's button growing for its words from 0, then at one moment, 50 on: what holds it made narrower (to 300) and
/// its words changed again, two changes told one after the other (events, frames drawn between or none) or one batch of
/// signals set from outside with the width set again (250) in it. What is drawn as the last is told.
fn same_moment(way : Int, frame_between : Bool) -> (Double, Double, Double) {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  t.advance(t0 + 50.0 - t.time())
  match way {
    0 => {
      tree.event(t.time(), fn() { w.set(300.0) })
      if frame_between {
        t.frame_at(t.time())
      }
      tree.event(t.time(), fn() { words.set("Copied") })
    }
    _ => {
      // (set from outside: the width once, then in one batch again and the words)
      w.set(300.0)
      if frame_between {
        t.frame_at(t.time())
      }
      @signals.start_batch()
      w.set(250.0)
      words.set("Copied")
      @signals.end_batch()
    }
  }
  t.frame_at(t.time())
  button_seen(t)
}

///|
/// The same, the last change not told: where the narrowing alone leaves it at 50.
fn narrowed_at_50(width : Double) -> (Double, Double, Double) {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let t0 = t.time()
  let tree = @ui.view_tree().unwrap()
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  t.advance(t0 + 50.0 - t.time())
  tree.event(t.time(), fn() { w.set(width) })
  t.frame_at(t.time())
  button_seen(t)
}

///|
test "a button narrowed and its words changed at one moment, two changes one after the other, a frame between or none: drawn as the narrowing left it as the second is told" {
  let narrowed = narrowed_at_50(300.0)
  let (a, b) = (same_moment(0, true), same_moment(0, false))
  assert_true(seen_near(a, narrowed) && seen_near(b, narrowed), msg="\{narrowed} \{a} \{b}")
}

///|
test "a button narrowed from outside, then narrowed again with its words changed in one batch: drawn as the first narrowing left it (not the second) as the batch is told, a frame between or none" {
  let narrowed = narrowed_at_50(300.0)
  let (a, b) = (same_moment(1, true), same_moment(1, false))
  assert_true(seen_near(a, narrowed) && seen_near(b, narrowed), msg="\{narrowed} \{a} \{b}")
}

///|
/// When a button's words are turned back to the short ones, on their way to the long ones.
let turned_back_ms : Double = 70.0

///|
/// Two buttons one over the other, each in the middle across, each going for the same words with a group of its own
/// (the second's group made first where `second_first`): what each draws (as button_seen, by its ground's colour).
fn two_buttons(words : @signals.Signal[String], second_first : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(400.0))).lines_up(Is(Some(Middle))) |> ignore
      let make = fn(ground : Int64) {
        let b = o.box(fn(b) {
          b.row(Is(true)).height(Is(Some(36.0))).padding(Is((16.0, 0.0, 16.0, 0.0))).ground(Is(ground)).radius(Is(18.0)).lines_up(Is(Some(Middle))) |> ignore
        })
        let k = b.box(fn(k) {
          k.words(By(fn() { words.get() }), ink=0xFFFFFFFFL, look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore
        })
        (b, k)
      }
      let first = make(0x3366CCFFL)
      let second = make(0x20A040FFL)
      let group = fn(p : (@view.View, @view.View)) {
        let g = moves_together(p.0, fn() { words.get() })
        g.add(p.0, reshapes=true)
        g.add(p.1)
      }
      if second_first {
        group(second)
        group(first)
      } else {
        group(first)
        group(second)
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// Where the button with ground `ground` is drawn across (x, width) as the last frame has it.
fn ground_across(t : @ui.Tester, ground : Int64) -> (Double, Double) {
  match t.drawn_rects().iter().find_first(fn(r) { r.4 == ground }) {
    Some(r) => (r.0, r.2)
    None => (-1.0, -1.0)
  }
}

///|
test "two buttons going for the same words, each with a group of its own, their words longer in one batch: each from where it stood as it is told and on its way as one alone goes, whichever group was made first" {
  // (one alone, at 60)
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let one = button_pair(words, true)
  let t0 = one.time()
  words.set(long_words)
  one.frame_at(t0 + 60.0)
  let alone = button_seen(one)
  let seen = fn(second_first : Bool) {
    let words = @signals.signal(short_words, same=fn(a, b) { a == b })
    let t = two_buttons(words, second_first)
    let before = (ground_across(t, 0x3366CCFFL), ground_across(t, 0x20A040FFL))
    let t0 = t.time()
    @signals.start_batch()
    words.set(long_words)
    @signals.end_batch()
    t.frame_at(t0)
    let told = (ground_across(t, 0x3366CCFFL), ground_across(t, 0x20A040FFL))
    t.frame_at(t0 + 60.0)
    let on_way = (ground_across(t, 0x3366CCFFL), ground_across(t, 0x20A040FFL))
    (before == told, on_way.0 == (alone.0, alone.1), on_way.1 == (alone.0, alone.1))
  }
  assert_eq((seen(false), seen(true)), ((true, true, true), (true, true, true)))
}

///|
/// A room over a button (or under it, where `button_first`), the room opening and the button going for its words: the
/// Tester.
fn room_and_button(open : @signals.Signal[Bool], words : @signals.Signal[String], button_first : Bool) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(400.0))).lines_up(Is(Some(Middle))) |> ignore
      let room = fn() {
        reveal_node(o, fn() { open.get() }, fn(h) {
          h.width(Is(Some(300.0))).words(Is("Waiting for the browser to finish"), look={ size: 13.0, weight: 400, line: 18.0, wrap: true }) |> ignore
        })
        |> ignore
      }
      let button = fn() {
        let b = o.box(fn(b) {
          b.row(Is(true)).height(Is(Some(36.0))).padding(Is((16.0, 0.0, 16.0, 0.0))).ground(Is(0x3366CCFFL)).radius(Is(18.0)).lines_up(Is(Some(Middle))) |> ignore
        })
        let k = b.box(fn(k) {
          k.words(By(fn() { words.get() }), ink=0xFFFFFFFFL, look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore
        })
        let g = moves_together(b, fn() { words.get() })
        g.add(b, reshapes=true)
        g.add(k)
      }
      if button_first {
        button()
        room()
      } else {
        room()
        button()
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a room opening and a button's words longer in one batch: the button from where it stood as it is told and on its way across as one alone goes, the room made before it or after" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let one = button_pair(words, true)
  let t0 = one.time()
  words.set(long_words)
  one.frame_at(t0 + 60.0)
  let alone = button_seen(one)
  let seen = fn(button_first : Bool) {
    let open = @signals.signal(false, same=fn(a, b) { a == b })
    let words = @signals.signal(short_words, same=fn(a, b) { a == b })
    let t = room_and_button(open, words, button_first)
    let before = ground_across(t, 0x3366CCFFL)
    let t0 = t.time()
    @signals.start_batch()
    open.set(true)
    words.set(long_words)
    @signals.end_batch()
    t.frame_at(t0)
    let told = ground_across(t, 0x3366CCFFL)
    t.frame_at(t0 + 60.0)
    (before == told, ground_across(t, 0x3366CCFFL) == (alone.0, alone.1))
  }
  assert_eq((seen(false), seen(true)), ((true, true), (true, true)))
}

///|
test "a button going for its words, what holds it narrowed from outside while it goes, then narrowed again: each change laid out and placed once as it is told, its clock set to the change's moment and back telling no change of its own; drawn as the narrowings leave it" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t = button_pair(words, true, w~)
  let tree = @ui.view_tree().unwrap()
  let t0 = t.time()
  tree.event(t0, fn() { words.set(long_words) })
  t.frame_at(t0 + 40.0)
  // (a frame drawn: what its frames lay out is theirs, not a change's)
  let before = tree.work().settles
  t.advance(t0 + 50.0 - t.time())
  w.set(300.0)
  let first = tree.work().settles - before
  t.advance(t0 + 60.0 - t.time())
  w.set(250.0)
  let second = tree.work().settles - before
  t.frame_at(t.time())
  let drawn = button_seen(t)
  // (the same narrowings told as events, a frame between each)
  let words2 = @signals.signal(short_words, same=fn(a, b) { a == b })
  let w2 = @signals.signal(400.0, same=fn(a, b) { a == b })
  let t2 = button_pair(words2, true, w=w2)
  let tree2 = @ui.view_tree().unwrap()
  let s0 = t2.time()
  tree2.event(s0, fn() { words2.set(long_words) })
  t2.frame_at(s0 + 40.0)
  t2.advance(s0 + 50.0 - t2.time())
  tree2.event(t2.time(), fn() { w2.set(300.0) })
  t2.frame_at(t2.time())
  t2.advance(s0 + 60.0 - t2.time())
  tree2.event(t2.time(), fn() { w2.set(250.0) })
  t2.frame_at(t2.time())
  assert_true(first == 1 && second == 2 && seen_near(drawn, button_seen(t2)), msg="\{first} \{second} \{drawn} \{button_seen(t2)}")
}

///|
test "a button that goes for its words given another colour, then its words changed twice in one batch: nothing laid out for the colour, and one change's layout for the batch" {
  let words = @signals.signal(short_words, same=fn(a, b) { a == b })
  let ground = @signals.signal(0x3366CCFFL, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) {
      b.row(Is(true)).height(Is(Some(36.0))).ground(By(fn() { ground.get() })) |> ignore
      let k = b.box(fn(k) { k.words(By(fn() { words.get() }), look={ size: 13.0, weight: 400, line: 18.0, wrap: false }) |> ignore })
      let g = moves_together(b, fn() { words.get() })
      g.add(b, reshapes=true)
      g.add(k)
    })
    |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let w0 = tree.work()
  ground.set(0xCC3333FFL)
  let w1 = tree.work()
  @signals.start_batch()
  words.set(long_words)
  words.set("Copied")
  @signals.end_batch()
  let w2 = tree.work()
  t.frame()
  // (drawn in its new colour, its last words said)
  let coloured = t.drawn_rects().iter().any(fn(r) { r.4 == 0xCC3333FFL })
  let said = t.find("Copied") is Some(_)
  assert_eq(
    (w1.computes - w0.computes, w2.settles - w1.settles, w2.computes - w1.computes, coloured, said),
    (0, 1, 1, true, true),
  )
}
