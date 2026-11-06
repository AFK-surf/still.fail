// What a windowed list tells seen (View::scrolls_window's `seen`): the blocks that came in sight, as it was laid out
// or as it went across them by itself; not those a move at once went past, which it made only to measure them. So what
// a page keeps for a block (a draft) is started for what was shown, whether the frames between were many or one.

///|
priv struct SeenCase {
  tree : @view.Tree
  seen : Array[Int]
  made : Array[Int]
  live : Map[Int, @view.View]
  mut now : Double
}

///|
/// Blocks `0..<400` in a column 300 by 100 (from its top), 40 and 80 tall in turn, counted 80 till laid out: what it
/// told seen (in the order told, each layout's as it is done), what it made, what of it is made now; its first frame
/// drawn.
fn seen_case() -> SeenCase {
  let scroll = @view.Scroll::list()
  let seen = []
  let made = []
  let live : Map[Int, @view.View] = {}
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { Array::makei(400, fn(i) { i }) }, est=80.0, seen=fn(came) { seen.append(came) }, fn(
        b,
        k,
      ) {
        made.push(k)
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(if k % 2 == 0 { 40.0 } else { 80.0 }))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let c : SeenCase = { tree, seen, made, live, now: 0.0 }
  c.frame(0.0)
  c
}

///|
/// The frame `dt` on, what it said to tell once it is painted told (what it tells seen told as it is laid out).
fn SeenCase::frame(self : SeenCase, dt : Double) -> Unit {
  self.now = self.now + dt
  self.tree.frame(300.0, 100.0, now=self.now) |> ignore
  for f in self.tree.take_after_paint() {
    f()
  }
}

///|
/// The blocks in sight, from the top: each its key and where its top is.
fn SeenCase::in_sight(self : SeenCase) -> Array[(Int, Double)] {
  let out = []
  for k, v in self.live {
    let (_, y, _, h) = v.rect()
    if y + h > 0.0 && y < 100.0 {
      out.push((k, y))
    }
  }
  out.sort_by(fn(a, b) { a.0.compare(b.0) })
  out
}

///|
/// What it told seen, each once, by key.
fn SeenCase::told(self : SeenCase) -> Array[Int] {
  let once : Set[Int] = Set::new()
  for k in self.seen {
    once.add(k)
  }
  let out = once.iter().collect()
  out.sort()
  out
}

///|
/// `steps` wheels of `dy` each (down), a frame after each, then the frame 5 s on: the blocks told seen, those in sight,
/// and the case.
fn wheeled_seen(steps : Int, dy : Double) -> (Array[Int], Array[(Int, Double)], SeenCase) {
  let c = seen_case()
  for _ in 0..<steps {
    c.tree.wheel_at(150.0, 50.0, 0.0, dy, 0, c.now + 1.0) |> ignore
    c.frame(16.0)
  }
  c.frame(5000.0)
  (c.told(), c.in_sight(), c)
}

///|
test "scrolls_window: a wheel of 3000 tells seen what showed before it and where it stops, none of the blocks it went past (made only to be measured); three hundred of 10 tell every block they showed; both stop on the same blocks, where they are" {
  let (one, one_sight, c) = wheeled_seen(1, 3000.0)
  let (many, many_sight, _) = wheeled_seen(300, 10.0)
  // (3000 down, 120 a pair: block 50 at the top)
  assert_eq((one_sight, many_sight), ([(50, 0.0), (51, 40.0)], [(50, 0.0), (51, 40.0)]))
  assert_eq(one, [0, 1, 50, 51])
  assert_eq(many, Array::makei(52, fn(i) { i }))
  // (those it went past made, each to be measured, none of them told)
  let went_past = Array::makei(48, fn(i) { i + 2 })
  assert_eq(went_past.filter(fn(k) { !c.made.contains(k) }), [])
}

///|
/// A finger up 80 in 10 ms, let go as it moves, then a frame every `dt` till 6 s: the blocks told seen and those in
/// sight.
fn flung_seen(dt : Double) -> (Array[Int], Array[(Int, Double)]) {
  let c = seen_case()
  guard c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    abort("nothing takes the finger")
  }
  let t = c.now + 1.0
  c.tree.drag_at(id, Down, 150.0, 90.0, t) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 50.0, t + 5.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 10.0, t + 10.0) |> ignore
  c.tree.drag_at(id, Up, 150.0, 10.0, t + 10.0) |> ignore
  while c.now < 6000.0 {
    c.frame(dt)
  }
  (c.told(), c.in_sight())
}

///|
test "scrolls_window flung: every block it glides across told seen (each in sight at a moment of the way), drawn every 16 ms or in one frame at its end" {
  let often = flung_seen(16.0)
  let once = flung_seen(6000.0)
  assert_eq(once, often)
  // (all from the first to where it stops, each once)
  let (told, sight) = often
  let last = sight.last().map(fn(r) { r.0 }).unwrap_or(-1)
  assert_eq(told, Array::makei(last + 1, fn(i) { i }))
  assert_true(last > 10, msg="glided on: \{sight}")
}

///|
/// A column 300 by 100 holding, while `there` says so, a list of `0..<400` 40 tall from its top: windowed (what it told
/// seen pushed to `told`) or anchored (what it told sighted as come, there): its tree, and its frame `at` drawn with what
/// it said to tell once it is painted told. `scroll`: what it scrolls by; `gone_at`: a moment it is let go at, come due
/// on the timeline (its page closed then).
fn gone_case(
  windowed : Bool,
  there : @signals.Signal[Bool],
  told : Array[Int],
  scroll? : @view.Scroll = @view.Scroll::list(),
  gone_at? : Double,
) -> (@view.Tree, (Double) -> Unit) {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      match gone_at {
        Some(at) => o.at_moment(at, fn() { there.set(false) }) |> ignore
        None => ()
      }
      o.show(fn() { there.get() }, fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        let keys = fn() { Array::makei(400, fn(i) { i }) }
        let row = fn(b : @view.View, _k : Int) { b.height(Is(Some(40.0))) |> ignore }
        if windowed {
          p.scrolls_window(scroll, keys, est=40.0, seen=fn(came) { told.append(came) }, row) |> ignore
        } else {
          p.scrolls_anchored(scroll, keys, est=40.0, ahead=0.0, from_end=false, sighted=fn(s) { told.append(s.came) }, row)
          |> ignore
        }
      })
    })
    |> ignore
  })
  let frame = fn(at : Double) {
    tree.frame(300.0, 100.0, now=at) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  (tree, frame)
}

///|
test "scrolls_window: what came in sight as it was laid out at an input's moment told seen as that layout is done, before any frame is painted; let go at a later input's moment, what it told the same whether a frame was painted between or not" {
  let runs : Array[Array[Int]] = []
  for painted in [false, true] {
    let there = @signals.signal(true)
    let told : Array[Int] = []
    let (tree, frame) = gone_case(true, there, told)
    frame(0.0)
    let first = told.length()
    // (a wheel down 400, then another: laid out at the second's moment, rows 10 to 12 in sight then)
    tree.wheel_at(150.0, 50.0, 0.0, 400.0, 0, 1.0) |> ignore
    tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, 2.0) |> ignore
    let at_second = told[first:].to_array()
    assert_true(at_second.contains(10), msg="painted \{painted}: \{at_second}")
    if painted {
      frame(8.0)
    }
    // (let go at an input's moment: the tree brought to it first, as an input brings it)
    tree.bring_to(10.0)
    there.set(false)
    frame(16.0)
    runs.push(told[first:].to_array())
    tree.dispose()
  }
  assert_eq(runs[1], runs[0])
}

///|
test "scrolls_anchored: a list let go after it was laid out at an input's moment, before the frame is painted, tells nothing sighted of what came in sight then (what asks the host for its pictures once drawn); one still there tells it as the frame is painted" {
  for let_go in [false, true] {
    let there = @signals.signal(true)
    let told : Array[Int] = []
    let (tree, frame) = gone_case(false, there, told)
    frame(0.0)
    let first = told.length()
    // (a wheel down 400, then another: laid out at the second's moment, rows 10 to 12 in sight then)
    tree.wheel_at(150.0, 50.0, 0.0, 400.0, 0, 1.0) |> ignore
    tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, 2.0) |> ignore
    if let_go {
      there.set(false)
    }
    frame(16.0)
    let after = told[first:].to_array()
    if let_go {
      assert_eq(after, [])
    } else {
      assert_true(after.contains(10), msg="\{after}")
    }
    tree.dispose()
  }
}

///|
test "scrolls_window: put where rows 10 to 12 show in an event and laid out there at once, as an event finds where things are: told seen of them as that layout is done, in the event; let go in that same event or a later one, what it told the same whether a frame was painted between or not" {
  for same_event in [true, false] {
    let runs : Array[(Array[Int], Array[Int])] = []
    for painted in [false, true] {
      let there = @signals.signal(true)
      let told : Array[Int] = []
      let scroll = @view.Scroll::list()
      let (tree, frame) = gone_case(true, there, told, scroll~)
      frame(0.0)
      let first = told.length()
      tree.event_said(5.0, fn() {  }, fn() {
        scroll.put(400.0)
        tree.laid_as_now()
        if same_event {
          there.set(false)
        }
      })
      let in_event = told[first:].to_array()
      if painted {
        frame(8.0)
      }
      if !same_event {
        tree.event_said(10.0, fn() {  }, fn() { there.set(false) })
      }
      frame(16.0)
      runs.push((in_event, told[first:].to_array()))
      tree.dispose()
    }
    assert_true(runs[0].0.contains(10), msg="same event \{same_event}: \{runs[0].0}")
    assert_eq(runs[1], runs[0], msg="same event \{same_event}")
  }
}

///|
/// Two windowed lists side by side, each a column 300 by 100 of `0..<400` 40 tall, the first while `there` says so:
/// each telling said into `log` (which list, the first block told, the moment it was told at), what the first told
/// then told `first_told` with the tree. The tree and the two lists' scrolls, its first frame drawn.
fn two_lists(
  log : Array[(Int, Int, Double?)],
  there : @signals.Signal[Bool],
  first_told : (@view.Tree, Array[Int]) -> Unit,
) -> (@view.Tree, @view.Scroll, @view.Scroll) {
  let one = @view.Scroll::list()
  let two = @view.Scroll::list()
  let held : Ref[@view.Tree?] = Ref(None)
  let keys = fn() { Array::makei(400, fn(i) { i }) }
  let row = fn(b : @view.View, _k : Int) { b.height(Is(Some(40.0))) |> ignore }
  let said = fn(list : Int, came : Array[Int]) {
    match held.val {
      Some(t) => {
        log.push((list, came[0], t.moment()))
        if list == 1 {
          first_told(t, came)
        }
      }
      None => ()
    }
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(600.0))).height(Is(Some(100.0))).row(Is(true)) |> ignore
      o.box(fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        p.show(fn() { there.get() }, fn(q) {
          q.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
          q.scrolls_window(one, keys, est=40.0, seen=fn(came) { said(1, came) }, row) |> ignore
        })
      })
      |> ignore
      o.box(fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        p.scrolls_window(two, keys, est=40.0, seen=fn(came) { said(2, came) }, row) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  held.val = Some(tree)
  tree.frame(600.0, 100.0, now=0.0) |> ignore
  (tree, one, two)
}

///|
test "scrolls_window: two lists' blocks come in sight in one layout, the first's telling putting it on and laying the tree out at once: what that layout finds told after the second's telling, not within the first's, each of the event's moment" {
  let log : Array[(Int, Int, Double?)] = []
  let there = @signals.signal(true)
  let one : Ref[@view.Scroll?] = Ref(None)
  let (tree, s1, s2) = two_lists(log, there, fn(t, came) {
    // (rows 10 on come in sight: put on to 20 and laid out at once, as an event reads where things are)
    if came.contains(10) {
      one.val.unwrap().put(800.0)
      t.laid_as_now()
    }
  })
  one.val = Some(s1)
  let first = log.length()
  tree.event_said(5.0, fn() {  }, fn() {
    s1.put(400.0)
    s2.put(400.0)
    tree.laid_as_now()
  })
  assert_eq(log[first:].to_array(), [(1, 10, Some(5.0)), (2, 10, Some(5.0)), (1, 20, Some(5.0))])
  tree.dispose()
}

///|
test "scrolls_window: two lists' blocks come in sight in a frame's layout, the first's telling putting it on, laying the tree out at once, letting it go and laying out again: what that layout found not told, the list gone before its turn, the second's told; the same with a frame after or none" {
  let runs : Array[Array[(Int, Int)]] = []
  for painted in [false, true] {
    let log : Array[(Int, Int, Double?)] = []
    let there = @signals.signal(true)
    let one : Ref[@view.Scroll?] = Ref(None)
    let (tree, s1, s2) = two_lists(log, there, fn(t, came) {
      if came.contains(10) {
        one.val.unwrap().put(800.0)
        t.laid_as_now()
        there.set(false)
        t.laid_as_now()
      }
    })
    one.val = Some(s1)
    let first = log.length()
    // (outside an event, no batch round it: what it sets told as it is set)
    s1.put(400.0)
    s2.put(400.0)
    tree.frame(600.0, 100.0, now=5.0) |> ignore
    if painted {
      tree.frame(600.0, 100.0, now=16.0) |> ignore
    }
    runs.push(log[first:].to_array().map(fn(e) { (e.0, e.1) }))
    tree.dispose()
  }
  assert_eq(runs[0], [(1, 10), (2, 10)])
  assert_eq(runs[1], runs[0])
}

///|
test "scrolls_window flung, let go at a moment come due on the way (its page closed then): told seen of every block it glided across up to that moment, laid out before it there alone, drawn every 16 ms or in one frame long after" {
  let runs : Array[Array[Int]] = []
  let settles : Array[Int] = []
  for dt in [16.0, 6000.0] {
    let there = @signals.signal(true)
    let told : Array[Int] = []
    let (tree, frame) = gone_case(true, there, told, gone_at=200.0)
    frame(0.0)
    let first = told.length()
    let before = tree.work().settles
    guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
      abort("nothing takes the finger")
    }
    // (a finger up 80 in 10 ms, let go as it moves: flung on past 200 ms)
    tree.drag_at(id, Down, 150.0, 90.0, 1.0) |> ignore
    tree.drag_at(id, Moved, 150.0, 50.0, 6.0) |> ignore
    tree.drag_at(id, Moved, 150.0, 10.0, 11.0) |> ignore
    tree.drag_at(id, Up, 150.0, 10.0, 11.0) |> ignore
    let mut at = 0.0
    while at < 6000.0 {
      at = at + dt
      frame(at)
    }
    runs.push(told[first:].to_array())
    settles.push(tree.work().settles - before)
    tree.dispose()
  }
  assert_eq(runs[1], runs[0])
  assert_true(runs[0].length() > 5, msg="glided on: \{runs[0]}")
  // (at 200 alone: none once it is let go, nothing left that moves by itself)
  assert_eq(settles, [1, 1])
}

///|
/// gone_case's windowed list flung (a finger up 80 in 10 ms, let go at 11), `between` done with its tree and its frame
/// (a frame, or none), `end` at `at` (what stops it or lets it go then), frames every 16 ms from then to 6 s: the blocks
/// it told seen after its first frame, as told (each telling's, in its order, one after another)
fn flung_then(
  between : (@view.Tree, (Double) -> Unit) -> Unit,
  at : Double,
  end : (@view.Tree, @signals.Signal[Bool], Double) -> Unit,
) -> Array[Int] {
  let there = @signals.signal(true)
  let told : Array[Int] = []
  let (tree, frame) = gone_case(true, there, told)
  frame(0.0)
  let first = told.length()
  guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    abort("nothing takes the finger")
  }
  tree.drag_at(id, Down, 150.0, 90.0, 1.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 50.0, 6.0) |> ignore
  tree.drag_at(id, Moved, 150.0, 10.0, 11.0) |> ignore
  tree.drag_at(id, Up, 150.0, 10.0, 11.0) |> ignore
  between(tree, frame)
  end(tree, there, at)
  let mut t = at
  while t < 6000.0 {
    t = t + 16.0
    frame(t)
  }
  let out = told[first:].to_array()
  tree.dispose()
  out
}

///|
/// Whether what flung_then's list told is each block once, in the order they came in sight gliding down, from the one
/// under those its first frame showed (0 to 2).
fn once_each(told : Array[Int]) -> Bool {
  told == Array::makei(told.length(), fn(i) { 3 + i })
}

///|
/// A finger down at `at` on the list, stopping it, up 10 ms later where it went down.
fn pressed_at(tree : @view.Tree, _there : @signals.Signal[Bool], at : Double) -> Unit {
  guard tree.claimer_of(tree.claimers_at(150.0, 50.0), 0.0, -20.0) is Some(id) else {
    abort("nothing takes the finger")
  }
  tree.drag_at(id, Down, 150.0, 50.0, at) |> ignore
  tree.drag_at(id, Up, 150.0, 50.0, at + 10.0) |> ignore
}

///|
/// The list let go by an input at `at` (its page closed: the tree brought to that moment first, as an input brings it).
fn closed_by_input(tree : @view.Tree, there : @signals.Signal[Bool], at : Double) -> Unit {
  tree.bring_to(at)
  there.set(false)
}

///|
/// The list let go in an event at `at` (a message come then, its page closed by it).
fn closed_in_event(tree : @view.Tree, there : @signals.Signal[Bool], at : Double) -> Unit {
  tree.event_said(at, fn() {  }, fn() { there.set(false) })
}

///|
/// A frame drawn for `shown`, its host come to `now` (as a phone draws its frame for its next vsync: what is drawn
/// sampled then, the logic no further than `now`), what it said to tell once it is painted told.
fn drawn_ahead(tree : @view.Tree, now : Double, shown : Double) -> Unit {
  tree.at(shown)
  tree.frame(300.0, 100.0, now~) |> ignore
  for f in tree.take_after_paint() {
    f()
  }
}

///|
test "scrolls_window flung, a frame on the way drawn for 200 with its host at 100, then stopped by a finger at 150, its page closed by an input then or in an event then: told seen of what it glided across up to 150, each once in the order it came in sight, as with a frame drawn at 100 or none; none of what it was drawn showing by 200" {
  let ends = [("pressed", pressed_at), ("input", closed_by_input), ("event", closed_in_event)]
  let apart : Array[String] = []
  for e in ends {
    let (name, end) = e
    let none = flung_then(fn(_, _) {  }, 150.0, end)
    let at_now = flung_then(fn(_, frame) { frame(100.0) }, 150.0, end)
    let ahead = flung_then(fn(tree, _) { drawn_ahead(tree, 100.0, 200.0) }, 150.0, end)
    // (glided on past the first few, each once in the order it came in sight)
    if (at_now, ahead) != (none, none) || !once_each(none) || none.length() <= 5 {
      apart.push("\{name}: none \{none}; drawn at 100 \{at_now}; drawn for 200 at 100 \{ahead}")
    }
  }
  assert_eq(apart, [], msg=apart.join("\n"))
}

///|
test "scrolls_window flung, a frame on the way drawn for 200 with its host at 100, its page closed by an input at 200 itself or in an event then: told seen of what it glided across up to 200, each once in the order it came in sight, as with none between" {
  let apart : Array[String] = []
  for e in [("input", closed_by_input), ("event", closed_in_event)] {
    let (name, end) = e
    let none = flung_then(fn(_, _) {  }, 200.0, end)
    let ahead = flung_then(fn(tree, _) { drawn_ahead(tree, 100.0, 200.0) }, 200.0, end)
    if ahead != none || !once_each(none) || none.length() <= 5 {
      apart.push("\{name}: none \{none}; drawn for 200 at 100 \{ahead}")
    }
  }
  assert_eq(apart, [], msg=apart.join("\n"))
}

///|
/// A column 300 by 100 of `0..<400` 40 tall at rest, telling seen where `seen` says so, with what is due that holds
/// nothing of it (three at 100; one at 150 saying another there as it is done; one at 200), drawn at 0 and every `dt`
/// till 1 s: the work its tree did after its first frame (layouts where things stood before what was due, nodes laid
/// out again, nodes visited, computes, bindings run), how many of what was due were done, and how often what asks to be
/// laid out before what is due was asked whether it went on by itself.
fn at_rest_due(seen : Bool, dt : Double) -> (Int, Int, Int, Int, Int, Int, Int) {
  let keys = fn() { Array::makei(400, fn(i) { i }) }
  let row = fn(b : @view.View, _k : Int) { b.height(Is(Some(40.0))) |> ignore }
  let told : ((Array[Int]) -> Unit)? = if seen { Some(fn(_) {  }) } else { None }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(@view.Scroll::list(), keys, est=40.0, seen?=told, row) |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  let root = tree.root()
  let done = Ref(0)
  let due = fn() { done.val = done.val + 1 }
  for _ in 0..<3 {
    root.at_moment(100.0, due) |> ignore
  }
  root.at_moment(150.0, fn() {
    due()
    root.at_moment(150.0, due) |> ignore
  })
  |> ignore
  root.at_moment(200.0, due) |> ignore
  let w0 = tree.work()
  let mut at = 0.0
  while at < 1000.0 {
    at = at + dt
    tree.frame(300.0, 100.0, now=at) |> ignore
  }
  let w = tree.work()
  tree.dispose()
  (
    w.settles - w0.settles,
    w.laid - w0.laid,
    w.visited - w0.visited,
    w.computes - w0.computes,
    w.bound - w0.bound,
    done.val,
    w.due_asked - w0.due_asked,
  )
}

///|
test "scrolls_window at rest, telling seen: nothing laid out for it at the moments come due (three at one, one said at a moment as it comes, another), the layouts' work as with nothing told seen; asked whether it went on by itself once a moment, three times, however many were due then, drawn every 16 ms or once long after" {
  for dt in [16.0, 1000.0] {
    let told = at_rest_due(true, dt)
    let none = at_rest_due(false, dt)
    assert_eq((told.0, told.1, told.2, told.3, told.4, told.5), (none.0, none.1, none.2, none.3, none.4, none.5), msg="every \{dt} ms")
    // (no layout for it; all six done; asked at 100, 150 and 200, once each; a list telling nothing, never asked)
    assert_eq((told.0, told.5, told.6, none.6), (0, 6, 3, 0), msg="every \{dt} ms")
  }
}

///|
test "scrolls_window: two lists, the first flung, the second at rest: laid out before what is due at a moment come on the first's way, once a moment (three at 100; one at 150 saying another there as it is done) and at its end, none for the one at rest nor once both are, drawn every 16 ms or in one frame long after" {
  let runs : Array[(Int, Int)] = []
  for dt in [16.0, 6000.0] {
    let log : Array[(Int, Int, Double?)] = []
    let there = @signals.signal(true)
    let (tree, one, _) = two_lists(log, there, fn(_, _) {  })
    let root = tree.root()
    let done = Ref(0)
    let due = fn() { done.val = done.val + 1 }
    for _ in 0..<3 {
      root.at_moment(100.0, due) |> ignore
    }
    root.at_moment(150.0, fn() {
      due()
      root.at_moment(150.0, due) |> ignore
    })
    |> ignore
    guard tree.claimer_of(tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
      abort("nothing takes the finger")
    }
    // (a finger up 80 in 10 ms on the first, let go as it moves: flung on past 150 ms, at rest at `rest`)
    tree.drag_at(id, Down, 150.0, 90.0, 1.0) |> ignore
    tree.drag_at(id, Moved, 150.0, 50.0, 6.0) |> ignore
    tree.drag_at(id, Moved, 150.0, 10.0, 11.0) |> ignore
    tree.drag_at(id, Up, 150.0, 10.0, 11.0) |> ignore
    guard one.glides_till() is Some(rest) else { abort("not flung") }
    assert_true(rest > 150.0 && rest < 5000.0, msg="at rest at \{rest}")
    // (and two due once both are at rest)
    root.at_moment(rest + 50.0, due) |> ignore
    root.at_moment(rest + 80.0, due) |> ignore
    let before = tree.work().settles
    let mut at = 0.0
    while at < 6000.0 {
      at = at + dt
      tree.frame(600.0, 100.0, now=at) |> ignore
    }
    runs.push((tree.work().settles - before, done.val))
    tree.dispose()
  }
  // (at 100, at 150 and at its end: three; all seven done)
  assert_eq(runs, [(3, 7), (3, 7)])
}

///|
/// Flung as above, a frame shown at 100 sampled ahead for 300, then an event at 150 asking where the first block in
/// sight is drawn now or not, then a frame every 16 ms till 6 s: what it told seen after the event, by the event's end
/// and in all; what was said to tell once painted, by the next frame; the blocks in sight at the end.
fn flung_then_looked(asks : Bool) -> (Array[Int], Array[Int], Int, Array[(Int, Double)]) {
  let c = seen_case()
  guard c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    abort("nothing takes the finger")
  }
  let t = c.now + 1.0
  c.tree.drag_at(id, Down, 150.0, 90.0, t) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 50.0, t + 5.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 10.0, t + 10.0) |> ignore
  c.tree.drag_at(id, Up, 150.0, 10.0, t + 10.0) |> ignore
  c.now = 100.0
  c.tree.at(300.0)
  c.tree.frame(300.0, 100.0, now=100.0) |> ignore
  for f in c.tree.take_after_paint() {
    f()
  }
  let before = c.seen.length()
  c.tree.event(150.0, fn() {
    if asks {
      match c.in_sight().get(0) {
        Some((k, _)) => c.live.get(k).map(fn(v) { v.drawn_now() }) |> ignore
        None => ()
      }
    }
  })
  let by_event = c.seen[before:].to_array()
  let painted = c.tree.take_after_paint()
  let said = painted.length()
  for f in painted {
    f()
  }
  c.now = 150.0
  while c.now < 6000.0 {
    c.frame(16.0)
  }
  (by_event, c.seen.copy(), said, c.in_sight())
}

///|
test "scrolls_window flung and drawn ahead: a look at an event's moment tells seen, sighted and scrolled as without it" {
  assert_eq(flung_then_looked(true), flung_then_looked(false))
}
