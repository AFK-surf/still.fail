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
  let told : Array[Int] = []
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_anchored(scroll, fn() { Array::makei(3000, fn(i) { i }) }, est=80.0, ahead=0.0, sighted=fn(ks) { told.append(ks) }, fn(b, k) {
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
  told.filter(fn(k) { if seen.contains(k) { false } else { seen.add(k); true } })
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
