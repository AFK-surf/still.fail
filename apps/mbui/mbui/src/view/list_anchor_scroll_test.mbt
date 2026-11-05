// How far a scroll goes in a list laid out from its anchor: by the heights of the rows it passes, each measured as it
// is passed where it was not, never by what one is guessed to be; so where it stops is the same in one jump as in many
// (retained.md, "Layout read back": 258dee's −3000 wheel stopped 3 rows short of main's).

///|
/// The rows in sight, from the top, once `steps` wheels of `dy` each (toward its start) are done and the list is still.
fn wheeled_to(steps : Int, dy : Double) -> (Int, Double) {
  // (rows 40 and 80 tall in turn: what one is guessed to be, 80 said, the mean of those measured, 60, neither)
  let c = anchored_case(3000, tall_of=fn(k) { if k % 2 == 0 { 40.0 } else { 80.0 } })
  let mut t = 1000.0
  for _ in 0..<steps {
    c.tree.wheel_at(150.0, 50.0, 0.0, dy, 0, t) |> ignore
    t = t + 16.0
    c.tree.frame(390.0, 844.0, now=t) |> ignore
  }
  c.tree.frame(390.0, 844.0, now=t + 5000.0) |> ignore
  // (the row whose top is the nearest at or over the window's top, and where its top is)
  let mut best = -1
  let mut at = 0.0
  for k, v in c.live {
    let y = v.rect().1
    if y <= 0.001 && (best < 0 || y > at) {
      best = k
      at = y
    }
  }
  (best, at)
}

///|
test "scrolls_anchored: a wheel of 3000 toward its start stops on the same row as three hundred of 10, rows 40 and 80 tall in turn" {
  let one = wheeled_to(1, -3000.0)
  let many = wheeled_to(300, -10.0)
  assert_eq(one, many)
}

///|
/// The rows told sighted (scrolls_anchored's `sighted`) once `steps` wheels of `dy` each are done and the list is still,
/// each frame's told as its paint is over: in the order told, each once.
fn sighted_by(steps : Int, dy : Double) -> Array[Int] {
  sighted_as(steps, dy).0
}

///|
/// sighted_by's, and the rows in sight as what is told keeps them (came, then left), sorted.
fn sighted_as(steps : Int, dy : Double) -> (Array[Int], Array[Int]) {
  let told : Array[Int] = []
  let in_it : Set[Int] = Set::new()
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(3000, fn(i) { i }) }, est=80.0, ahead=0.0, sighted=fn(s) {
        told.append(s.came)
        for k in s.came { in_it.add(k) }
        for k in s.left { in_it.remove(k) }
      }, fn(b, k) {
        b.height(Is(Some(if k % 2 == 0 { 40.0 } else { 80.0 }))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let frame = fn(t : Double) {
    tree.frame(390.0, 844.0, now=t) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  frame(0.0)
  let mut t = 1000.0
  for _ in 0..<steps {
    tree.wheel_at(150.0, 50.0, 0.0, dy, 0, t) |> ignore
    t = t + 16.0
    frame(t)
  }
  frame(t + 5000.0)
  let seen : Set[Int] = Set::new()
  let once = told.filter(fn(k) { if seen.contains(k) { false } else { seen.add(k); true } })
  let window = in_it.iter().collect()
  window.sort()
  (once, window)
}

///|
test "scrolls_anchored: the rows sighted on a wheel of 3000 are those sighted on three hundred of 10, each told once the frame is painted" {
  let one = sighted_by(1, -3000.0)
  let many = sighted_by(300, -10.0)
  one.sort()
  many.sort()
  assert_eq(one, many)
  // (the 3000 points gone past: every row of them, 40 and 80 tall in turn, 50 rows; and those in sight at the end)
  assert_true(one.length() >= 50, msg="\{one.length()} sighted")
}

///|
test "a node first drawn: told once, after the frame that draws it is painted, not before it is there" {
  let there = @signals.signal(false, same=fn(a, b) { a == b })
  let told = Ref(0)
  let tree = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(f) {
        f.height(Is(Some(30.0))).on_first_drawn(fn() { told.val += 1 }) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  let frame = fn(t : Double) {
    tree.frame(390.0, 844.0, now=t) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  frame(0.0)
  assert_eq(told.val, 0)
  there.set(true)
  frame(16.0)
  assert_eq(told.val, 1)
  frame(32.0)
  assert_eq(told.val, 1, msg="once")
  tree.dispose()
}

///|
test "scrolls_anchored: laid out at another width, the rows in sight told sighted again with it, the same rows" {
  let told : Array[(Array[Int], Double)] = []
  let wide = @signals.signal(300.0, same=fn(a, b) { a == b })
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(wide.get()) })).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(30, fn(i) { i }) }, est=40.0, ahead=0.0, sighted=fn(s) { told.push((s.came, s.width)) }, fn(b, _) {
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let frame = fn(t : Double) {
    tree.frame(390.0, 844.0, now=t) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  frame(0.0)
  let first = told.copy()
  // (nothing moved: nothing told again)
  frame(16.0)
  assert_eq(told.length(), first.length())
  wide.set(360.0)
  frame(32.0)
  let last = told[told.length() - 1]
  assert_eq(last.1, 360.0)
  let was = first[first.length() - 1].0.copy()
  let now = last.0.copy()
  was.sort()
  now.sort()
  assert_eq(now, was)
}

///|
test "scrolls_anchored: what is told sighted, came and then left, keeps the rows in sight, the same in one jump as in many" {
  let (_, one) = sighted_as(1, -3000.0)
  let (_, many) = sighted_as(300, -10.0)
  assert_eq(one, many)
  // (a window 100 tall: two or three rows 40 and 80 tall, none of those gone past)
  assert_true(one.length() >= 1 && one.length() <= 3, msg="\{one}")
}

///|
test "scrolls_anchored: rows moved in sight, none come or gone: told again where they are, as the frame is painted" {
  let told : Array[@view.Sighted[Int]] = []
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(30, fn(i) { i }) }, est=40.0, ahead=0.0, sighted=fn(s) { told.push(s) }, fn(b, _) {
        b.height(Is(Some(40.0))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let frame = fn(t : Double) {
    tree.frame(390.0, 844.0, now=t) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  frame(0.0)
  let first = told[told.length() - 1]
  assert_eq(first.height, 100.0)
  // (the last at the foot: its top 60 under the window's)
  assert_eq(first.rows[first.rows.length() - 1], (29, 60.0, 40.0))
  // (wheeled 4 toward its start: the same rows, each 4 lower)
  tree.wheel_at(150.0, 50.0, 0.0, -4.0, 0, 1000.0) |> ignore
  frame(1000.0 + 5000.0)
  let last = told[told.length() - 1]
  assert_eq(last.came, [])
  assert_eq(last.rows[last.rows.length() - 1], (29, 64.0, 40.0))
}
