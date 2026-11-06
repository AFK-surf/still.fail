// A windowed list (View::scrolls_window) as the hand moves it and as its blocks change: what shows where it is and
// pressed there, each frame laid out once, its blocks counted shorter than they come to, wheeled in one jump or in
// many, dragged and let go, grown or shrunk over what shows and in it, come and gone over, in and under it, scrolled
// away and back.

///|
priv struct Edges {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  tall : Map[Int, @signals.Signal[Double]]
  live : Map[Int, @view.View]
  made : Array[Int]
  pressed : Ref[Int?]
  mut now : Double
}

///|
/// Blocks `0..<n` in a column 300 by 100 (from its top), block `k` `tall(k)` high till its signal in `tall` (made as it
/// is first made) says otherwise, counted `est` till laid out; its first frame drawn.
fn edges(n : Int, tall : (Int) -> Double, est : Double) -> Edges {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let talls : Map[Int, @signals.Signal[Double]] = {}
  let live : Map[Int, @view.View] = {}
  let made = []
  let pressed : Ref[Int?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys.get() }, est~, fn(b, k) {
        made.push(k)
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        let s = match talls.get(k) {
          Some(s) => s
          None => {
            let s = @signals.signal(tall(k), same=fn(a, b) { a == b })
            talls[k] = s
            s
          }
        }
        b.height(By(fn() { Some(s.get()) })).on_press(fn() { pressed.val = Some(k) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let c : Edges = { tree, scroll, keys, tall: talls, live, made, pressed, now: 0.0 }
  c.frame() |> ignore
  c
}

///|
/// The frame `dt` on drawn; how many layouts it did.
fn Edges::frame(self : Edges, dt? : Double = 16.0) -> Int {
  let was = self.tree.work().computes
  self.now = self.now + dt
  self.tree.frame(300.0, 100.0, now=self.now) |> ignore
  self.tree.work().computes - was
}

///|
/// The wheel turned `dy` (toward its end) over the column, a millisecond on.
fn Edges::wheel(self : Edges, dy : Double) -> Unit {
  self.tree.wheel_at(150.0, 50.0, 0.0, dy, 0, self.now + 1.0) |> ignore
}

///|
/// The blocks made, by key: each one's key, top down the column and height.
fn Edges::rows(self : Edges) -> Array[(Int, Double, Double)] {
  let ks = self.live.keys().collect()
  ks.sort()
  ks.map(fn(k) {
    let (_, y, _, h) = self.live[k].rect()
    (k, y, h)
  })
}

///|
/// Where block `k`'s top is down the column, where it is made.
fn Edges::top(self : Edges, k : Int) -> Double? {
  self.live.get(k).map(fn(b) { b.rect().1 })
}

///|
/// What a press at (150, `y`) hits among the blocks.
fn Edges::hit(self : Edges, y : Double) -> Int? {
  self.pressed.val = None
  self.tree.press(150.0, y) |> ignore
  self.pressed.val
}

///|
test "scrolls_window, its blocks counted a twentieth as tall as they come to, wheeled on and back: each as far as the wheel turned, pressed where it is" {
  // (200 high each, counted 10: the wheel's 350 is a block and three quarters of them, not 35 counted ones)
  let c = edges(50, fn(_) { 200.0 }, 10.0)
  let first = (c.rows(), c.hit(50.0))
  c.wheel(350.0)
  let layouts = [c.frame()]
  let on = (c.rows(), c.scroll.at(c.tree), c.hit(25.0), c.hit(75.0))
  c.wheel(-1000.0)
  layouts.push(c.frame())
  assert_eq(first, ([(0, 0.0, 200.0)], Some(0)))
  assert_eq(on, ([(1, -150.0, 200.0), (2, 50.0, 200.0)], 350.0, Some(1), Some(2)))
  assert_eq((c.rows(), c.scroll.at(c.tree), c.hit(50.0)), ([(0, 0.0, 200.0)], 0.0, Some(0)))
  assert_eq(layouts.filter(fn(n) { n > 1 }), [])
}

///|
/// The block whose top is the nearest at or over the column's top once `steps` wheels of `dy` each are done and five
/// seconds more gone, and where its top is: blocks 40 and 80 high in turn, counted 80 (the mean of those measured, 60,
/// neither).
fn window_wheeled_to(steps : Int, dy : Double) -> (Int, Double) {
  let c = edges(3000, fn(k) { if k % 2 == 0 { 40.0 } else { 80.0 } }, 80.0)
  for _ in 0..<steps {
    c.wheel(dy)
    c.frame() |> ignore
  }
  c.frame(dt=5000.0) |> ignore
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
test "scrolls_window: a wheel of 3000 toward its end stops on the same block as three hundred of 10, blocks 40 and 80 high in turn" {
  // (by the heights of the blocks it passes, each measured as it is passed: 25 pairs of 40 and 80, block 50 at the top)
  assert_eq(window_wheeled_to(1, 3000.0), (50, 0.0))
  assert_eq(window_wheeled_to(300, 10.0), (50, 0.0))
}

///|
test "scrolls_window dragged, held a while and let go still: what it holds goes as far as the finger, at rest where it was let go; each frame laid out once" {
  let c = edges(200, fn(_) { 40.0 }, 80.0)
  guard c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    fail("nothing takes the finger")
  }
  // (a finger on block 2 (80 to 120), 10 into it, up 40 and a frame (the column taken past its slop); 20 more and a
  // frame; still a while and let go)
  c.tree.drag_at(id, Down, 150.0, 90.0, c.now + 1.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 50.0, c.now + 9.0) |> ignore
  let layouts = [c.frame()]
  // (what it holds moved as one, as far as it is scrolled)
  let taken = (c.top(2).unwrap_or(-1.0) + c.scroll.at(c.tree), c.scroll.at(c.tree) > 0.0)
  let (top_was, at_was) = (c.top(2).unwrap_or(-1.0), c.scroll.at(c.tree))
  c.tree.drag_at(id, Moved, 150.0, 30.0, c.now + 1.0) |> ignore
  layouts.push(c.frame())
  // (held, as far as the finger: block 2 and where it is scrolled to 20 on)
  let held = (top_was - c.top(2).unwrap_or(-1.0), c.scroll.at(c.tree) - at_was)
  let still = c.scroll.at(c.tree)
  c.now = c.now + 200.0
  c.tree.drag_at(id, Moved, 150.0, 30.0, c.now) |> ignore
  c.tree.drag_at(id, Up, 150.0, 30.0, c.now) |> ignore
  while c.now < 2000.0 {
    layouts.push(c.frame())
  }
  assert_eq((taken, held, c.scroll.at(c.tree), c.scroll.glides_till()), ((80.0, true), (20.0, 20.0), still, None))
  assert_eq(layouts.filter(fn(n) { n > 1 }), [])
}

///|
test "scrolls_window flung (let go as the finger moves): gliding on, at rest each block where it is said to be scrolled to, pressed there; each frame laid out once" {
  let c = edges(200, fn(_) { 40.0 }, 80.0)
  guard c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    fail("nothing takes the finger")
  }
  // (a finger up 80 in 10 ms, let go as it moves)
  let t = c.now + 1.0
  c.tree.drag_at(id, Down, 150.0, 90.0, t) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 50.0, t + 5.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 10.0, t + 10.0) |> ignore
  c.tree.drag_at(id, Up, 150.0, 10.0, t + 10.0) |> ignore
  let layouts = []
  while c.now < 6000.0 {
    layouts.push(c.frame())
  }
  let at = c.scroll.at(c.tree)
  // (each block passed laid out on the way: what the column is said to be scrolled to is where the blocks are)
  let off = c.rows().filter(fn(r) { (r.1 - (r.0.to_double() * 40.0 - at)).abs() > 0.01 })
  let at_50 = c.rows().filter(fn(r) { r.1 <= 50.0 && 50.0 < r.1 + r.2 }).map(fn(r) { Some(r.0) })
  assert_eq((c.scroll.glides_till(), off, layouts.filter(fn(n) { n > 1 })), (None, [], []))
  assert_true(at > 400.0, msg="glided on: at \{at}")
  assert_eq(at_50, [c.hit(50.0)])
}

///|
test "scrolls_window: a block over what shows grows, one in sight shrinks: what shows stays, those under the one shrunk come up; back at its top, the one grown as tall as it is; each frame laid out once" {
  let c = edges(30, fn(_) { 40.0 }, 80.0)
  c.wheel(100.0)
  let layouts = [c.frame()]
  let on = c.rows()
  c.tall[1].set(70.0)
  layouts.push(c.frame())
  let grown_over = c.rows()
  c.tall[3].set(10.0)
  layouts.push(c.frame())
  let shrunk_in = (c.rows(), c.hit(50.0))
  c.wheel(-1000.0)
  layouts.push(c.frame())
  assert_eq(on, [(2, -20.0, 40.0), (3, 20.0, 40.0), (4, 60.0, 40.0)])
  assert_eq(grown_over, on)
  assert_eq(shrunk_in, ([(2, -20.0, 40.0), (3, 20.0, 10.0), (4, 30.0, 40.0), (5, 70.0, 40.0)], Some(4)))
  assert_eq((c.rows(), c.hit(90.0)), ([(0, 0.0, 40.0), (1, 40.0, 70.0)], Some(1)))
  assert_eq(layouts.filter(fn(n) { n > 1 }), [])
}

///|
test "scrolls_window: blocks come and gone over, in and under what shows: what shows stays where it is, those under one gone come up into its place; each frame laid out once" {
  let c = edges(30, fn(_) { 40.0 }, 80.0)
  c.wheel(100.0)
  let layouts = [c.frame()]
  // (its keys gone through none of them as it is first laid out, none of its blocks measured, nor as it scrolls)
  let first = c.tree.work().keys_swept
  c.keys.set([-1, ..c.keys.get()])
  layouts.push(c.frame())
  // (its keys changed, blocks measured: the 31 gone through twice, those measured counted anew, those gone forgotten)
  let edited = c.tree.work().keys_swept - first
  let come_over = (c.rows(), c.hit(50.0))
  c.keys.set(c.keys.get().filter(fn(k) { k != 3 }))
  layouts.push(c.frame())
  let gone_in = (c.rows(), c.hit(50.0))
  let with_100 = []
  for k in c.keys.get() {
    with_100.push(k)
    if k == 4 {
      with_100.push(100)
    }
  }
  c.keys.set(with_100)
  layouts.push(c.frame())
  let come_in = (c.rows(), c.hit(90.0))
  let all = c.keys.get().copy()
  all.pop() |> ignore
  c.keys.set(all)
  layouts.push(c.frame())
  assert_eq(come_over, ([(2, -20.0, 40.0), (3, 20.0, 40.0), (4, 60.0, 40.0)], Some(3)))
  assert_eq(gone_in, ([(2, -20.0, 40.0), (4, 20.0, 40.0), (5, 60.0, 40.0)], Some(4)))
  assert_eq(come_in, ([(2, -20.0, 40.0), (4, 20.0, 40.0), (100, 60.0, 40.0)], Some(100)))
  assert_eq(c.rows(), come_in.0)
  assert_eq(layouts.filter(fn(n) { n > 1 }), [])
  assert_eq((first, edited), (0, 62))
}

///|
test "scrolls_window: a block scrolled away and back: let go, made again known as the same row, pressed where it is" {
  let c = edges(30, fn(_) { 40.0 }, 80.0)
  let (row, place) = c.live[2].row_place()
  c.wheel(400.0)
  c.frame() |> ignore
  let away = (c.live.contains(2), c.rows().map(fn(r) { r.0 }))
  c.made.clear()
  c.wheel(-400.0)
  c.frame() |> ignore
  assert_eq(away, (false, [10, 11, 12]))
  assert_eq((c.made.contains(2), c.live[2].row_place() == (row, place), c.top(2), c.hit(90.0)), (true, true, Some(80.0), Some(2)))
}

///|
/// A windowed list of 3000 blocks 40 high (counted 40) from its end, in a column 300 by 100, block 0 put `off` over the
/// window's top; then laid out again 20 narrower (what it measured of the blocks not laid out forgotten) and 40 taller:
/// the nodes made and let go in the frame it was put, those made and laid out by the two layouts after, the blocks in
/// sight then (each one's key, top and height), what a press 50 down hits, whether block 0 is made then, and whether it
/// is after a wheel.
fn put_far_over(off : Double) -> ((Int, Int), (Int, Int), Array[(Int, Double, Double)], Int?, Bool, Bool) {
  let scroll = @view.Scroll::list()
  let keys = Array::makei(3000, fn(i) { i })
  let wide = @signals.signal(300.0)
  let tall = @signals.signal(100.0)
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(None)
  let live : Map[Int, @view.View] = {}
  let pressed : Ref[Int?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(By(fn() { Some(wide.get()) })).height(By(fn() { Some(tall.get()) })) |> ignore
      o.scrolls_window(scroll, fn() { keys }, est=40.0, from_end=true, put~, fn(b, k) {
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(40.0))).on_press(fn() { pressed.val = Some(k) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  let w0 = tree.work()
  put.set(Some((0, off)))
  tree.frame(390.0, 844.0, now=16.0) |> ignore
  let w1 = tree.work()
  wide.set(280.0)
  tree.frame(390.0, 844.0, now=32.0) |> ignore
  tall.set(140.0)
  tree.frame(390.0, 844.0, now=48.0) |> ignore
  let w2 = tree.work()
  let ks = live.keys().collect().filter(fn(k) { k > 0 })
  ks.sort()
  let in_sight = ks.map(fn(k) {
    let (_, y, _, h) = live[k].rect()
    (k, y, h)
  })
  tree.press(150.0, 50.0) |> ignore
  let kept = live.contains(0)
  tree.wheel_at(150.0, 50.0, 0.0, -10.0, 0, 49.0) |> ignore
  tree.frame(390.0, 844.0, now=1000.0) |> ignore
  (
    (w1.made - w0.made, w1.let_go - w0.let_go),
    (w2.made - w1.made, w2.laid - w1.laid),
    in_sight,
    pressed.val,
    kept,
    live.contains(0),
  )
}

///|
test "scrolls_window from its end, its first block put 4000 and 40000 over the window's top: in the frame it is put, the blocks it goes past made, measured and let go; the layouts after it, narrower and taller, the same however far it was put; the block put at kept made till the hand moves the list" {
  let near = put_far_over(-4000.0)
  let far = put_far_over(-40000.0)
  // (the frame put: block 0 and those in sight made, those between made, measured and let go, those shown before let
  // go: 99 between and 999, two nodes a block)
  assert_eq((near.0, far.0), ((206, 204), (2006, 2004)))
  // (narrower, then taller: the block over those in sight come in, nothing of the blocks between gone through)
  assert_eq(near.1, far.1)
  assert_eq(near.2, [(99, 0.0, 40.0), (100, 40.0, 40.0), (101, 80.0, 40.0), (102, 120.0, 40.0)])
  assert_eq(far.2, [(999, 0.0, 40.0), (1000, 40.0, 40.0), (1001, 80.0, 40.0), (1002, 120.0, 40.0)])
  assert_eq((near.3, far.3), (Some(100), Some(1000)))
  assert_eq((near.4, near.5, far.4, far.5), (true, false, true, false))
}
