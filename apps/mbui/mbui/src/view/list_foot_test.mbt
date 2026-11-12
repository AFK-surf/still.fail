// A page's list that follows its foot (View::scrolls_window's `follows`) taking the room left under a head, in a panel
// beside a page, in a window taller than that room (an agent's history beside its chat): its blocks as tall as each
// says, none 48 as they are counted before they are laid out. Moved off its foot a little at a time, it goes as far as
// it is moved, what was seen staying where the move put it, each block made once; the page before asked for as it
// nears its top, once.

///|
priv struct FootCase {
  tree : @view.Tree
  scroll : @view.Scroll
  keys : @signals.Signal[Array[Int]]
  made : Array[Int]
  live : Map[Int, @view.View]
  /// what the head says, said again to lay the column out
  head : @signals.Signal[Double]
  /// how much taller than it says each block is (what the reader opened in it), by its key
  more : Map[Int, @signals.Signal[Double]]
}

///|
/// How tall block `k` is: 30, 90, 150 or 210, none as tall as it is counted before it is laid out.
fn foot_tall(k : Int) -> Double {
  30.0 + (((k % 4) + 4) % 4).to_double() * 60.0
}

///|
/// A window 600 wide and 400 tall: over it a layer (a stack's page), in it a page and beside it a panel 300 wide, a
/// head of 100 and the list of `n` blocks in the 300 left under it. What is laid over the window is measured within
/// the window's height before it is laid out as tall as it: the list, taking what its head leaves, is measured within
/// 400 first, then laid out 300 tall. `near_top`: the list's.
fn foot_case(n : Int, near_top? : (Double, () -> Bool, () -> Unit)) -> FootCase {
  let scroll = @view.Scroll::list()
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { a == b })
  let made = []
  let live : Map[Int, @view.View] = Map([])
  let head = @signals.signal(100.0, same=fn(a, b) { a == b })
  let more : Map[Int, @signals.Signal[Double]] = Map([])
  let more_of = fn(k : Int) {
    match more.get(k) {
      Some(m) => m
      None => {
        let m = @signals.signal(0.0, same=fn(a, b) { a == b })
        more[k] = m
        m
      }
    }
  }
  for k in 0..<80 {
    more_of(k - 20) |> ignore
  }
  let fills = fn(v : @view.View) {
    v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
  }
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(win) {
      win.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      win.box(fn(layer) {
        layer.over(Is(true)) |> ignore
        layer.box(fn(row) {
          row.row(Is(true)).grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          row.box(fn(page) { page.grow(Is(1.0)) |> ignore }) |> ignore
          row.box(fn(col) {
            col.width(Is(Some(300.0))).shrink(Is(0.0)) |> ignore
            col.box(fn(h) { h.height(By(fn() { Some(head.get()) })).shrink(Is(0.0)) |> ignore }) |> ignore
            col.box(fn(body) {
              fills(body)
              body.box(fn(l) {
                fills(l)
                l.scrolls_window(scroll, fn() { keys.get() }, est=48.0, follows=fn() { true }, near_top?, fn(b, k) {
                  made.push(k)
                  live[k] = b
                  b.owns(fn() { live.remove(k) }) |> ignore
                  let m = more_of(k)
                  b.height(By(fn() { Some(foot_tall(k) + m.get()) })) |> ignore
                })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  tree.frame(600.0, 400.0) |> ignore
  { tree, scroll, keys, made, live, head, more }
}

///|
/// How far off its foot it is.
fn FootCase::off_foot(self : FootCase) -> Double {
  self.scroll.most() - self.scroll.at(self.tree)
}

///|
test "scrolls_window following its foot under a head: opened, each block that shows made once, none that does not" {
  let k = foot_case(40)
  let shown = k.live.keys().collect()
  shown.sort()
  let made = k.made.copy()
  made.sort()
  // (its last two blocks, 210 and 150 tall: all of 39, and 90 of 38, in the 300 it shows)
  assert_eq((k.off_foot(), shown, made), (0.0, [38, 39], [38, 39]))
}

///|
test "scrolls_window following its foot under a head: the wheel turned up 12 at a time moves it 12 each time, blocks come in over what shows or not" {
  let k = foot_case(40)
  let offs = []
  let want = []
  // (forty turns of 12, each drawn as it comes)
  let turns = Array::make(40, -12.0)
  for i, turn in turns {
    k.tree.wheel_at(450.0, 250.0, 0.0, turn, 0, 10.0 + i.to_double()) |> ignore
    k.tree.frame(600.0, 400.0) |> ignore
    offs.push(k.off_foot())
    want.push(12.0 * (i + 1).to_double())
  }
  assert_eq(offs, want)
}

///|
test "scrolls_window following its foot under a head: moved off its foot, laid out again for what its head says: where it was" {
  let k = foot_case(40)
  k.tree.wheel_at(450.0, 250.0, 0.0, -24.0, 0, 10.0) |> ignore
  k.tree.frame(600.0, 400.0) |> ignore
  let (_, y, _, _) = k.live[38].rect()
  // (its head 10 shorter: the list 10 taller from its top, what shows 10 further up the window, as far off its foot
  // less the 10 more that shows)
  k.head.set(90.0)
  k.tree.frame(600.0, 400.0) |> ignore
  let (_, y_now, _, _) = k.live[38].rect()
  assert_eq((k.off_foot(), y_now), (14.0, y - 10.0))
}

///|
test "scrolls_window following its foot under a head: what shows stays where the wheel put it as taller blocks come in over it, none of it made again" {
  let k = foot_case(40)
  // (block 38, seen from the start, 240 further down by the end: its top still in sight)
  let mut y = k.live[38].rect().1
  let turns = Array::make(20, -12.0)
  for i, turn in turns {
    k.tree.wheel_at(450.0, 250.0, 0.0, turn, 0, 10.0 + i.to_double()) |> ignore
    k.tree.frame(600.0, 400.0) |> ignore
    let now = k.live[38].rect().1
    assert_eq(now - y, 12.0)
    y = now
  }
  assert_eq(k.made.filter(fn(b) { b == 38 }).length(), 1)
}

///|
test "scrolls_window near_top: asked as it comes within a height of its top while it wants; the page come in over what shows as it is asked leaves what shows where it was, far from its top by its blocks: not asked again" {
  let asked = Ref(0)
  let more : Ref[() -> Unit] = Ref(fn() {  })
  let k = foot_case(8, near_top=(1.0, fn() { true }, fn() {
    asked.val += 1
    (more.val)()
  }))
  // (opened at its foot, blocks 6 and 7 laid out, 150 and 210 tall, the six over them counted 48 each: 348 down, at
  // its foot with blocks over what shows: not asked)
  let far = asked.val
  more.val = fn() {
    // (the page before, ten blocks, as the list asks: answered at once)
    let now = Array::makei(10, fn(i) { i - 10 })
    now.append(k.keys.get())
    k.keys.set(now)
  }
  // (up 340, to 8 from its top as its blocks are counted: within the 300 it shows. Block 6, seen at 40 down the
  // window, is at 380; over it 5, 4 and 3 laid out, 90, 30 and 210 tall, 3 from 50 down)
  k.tree.wheel_at(450.0, 250.0, 0.0, -340.0, 0, 10.0) |> ignore
  k.tree.frame(600.0, 400.0) |> ignore
  let shown = k.live.keys().collect()
  shown.sort()
  let y = fn(b : Int) { k.live.get(b).map(fn(v) { v.rect().1 }) }
  assert_eq((far, asked.val, shown, y(6), y(3), k.keys.get().length()), (0, 1, [3, 4, 5, 6], Some(380.0), Some(50.0), 18))
  // (the frames after: nothing more asked, what shows where it was)
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((asked.val, y(6)), (1, Some(380.0)))
}

///|
test "scrolls_window following its foot under a head: 100 off its foot, blocks taller than counted come in over what shows: left where it is, not taken to its foot" {
  let k = foot_case(40)
  // (up 100: block 38's top, 60 over the top of what shows, 40 under it; 37, 90 tall and counted 48, comes to show)
  k.tree.wheel_at(450.0, 250.0, 0.0, -100.0, 0, 10.0) |> ignore
  k.tree.frame(600.0, 400.0) |> ignore
  let shown = k.live.keys().collect()
  shown.sort()
  assert_eq((k.off_foot(), shown, k.live.get(38).map(fn(v) { v.rect().1 })), (100.0, [37, 38, 39], Some(140.0)))
}

///|
test "scrolls_window near_top: at its foot with all it holds in sight, asked till what it holds is taller than it shows" {
  let asked = Ref(0)
  let more : Ref[() -> Unit] = Ref(fn() {  })
  let k = foot_case(1, near_top=(1.0, fn() { true }, fn() {
    asked.val += 1
    (more.val)()
  }))
  // (one block, 30 of the 300 it shows: asked as it opens, answered nothing)
  let first = asked.val
  let next = Ref(-2)
  more.val = fn() {
    let now = [next.val]
    next.val -= 1
    now.append(k.keys.get())
    k.keys.set(now)
  }
  // (a block come over it: asked again, answered at once with one more, each counted 48 till it is laid out, asked on
  // till the seven of them are counted taller than the 300 it shows; laid out, at its foot)
  k.keys.set([-1, 0])
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((first, asked.val, k.keys.get(), k.off_foot()), (1, 6, [-6, -5, -4, -3, -2, -1, 0], 0.0))
}

///|
test "Scroll::holds_here: at the foot it follows, a block opened by the reader opens down from where it is; shut again, at its foot, followed again as blocks come" {
  let k = foot_case(40)
  let y = fn(b : Int) { k.live.get(b).map(fn(v) { v.rect().1 }) }
  let was = (y(38), y(39))
  // (block 38, from 40 down the window, comes to be 120 taller as the reader opens what is in it: it and what is over
  // it where they were, 39 gone 120 down under it, the column 120 off its foot)
  k.scroll.holds_here()
  k.tree.frame(600.0, 400.0) |> ignore
  k.more[38].set(60.0)
  k.tree.frame(600.0, 400.0) |> ignore
  k.more[38].set(120.0)
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((was, y(38), y(39), k.off_foot()), ((Some(40.0), Some(190.0)), Some(40.0), Some(310.0), 120.0))
  // (shut again: at its foot as it was, and followed there as a block comes at its end)
  k.more[38].set(0.0)
  k.tree.frame(600.0, 400.0) |> ignore
  k.keys.set(Array::makei(41, fn(i) { i }))
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((k.off_foot(), k.live.contains(40)), (0.0, true))
}

///|
test "Scroll::holds_here: nothing opened after all, a block come at its end: followed, as ever" {
  let k = foot_case(40)
  k.scroll.holds_here()
  k.tree.frame(600.0, 400.0) |> ignore
  k.keys.set(Array::makei(41, fn(i) { i }))
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((k.off_foot(), k.live.contains(40)), (0.0, true))
}

///|
test "scrolls_window following its foot: not held, a block in sight grown at its foot is followed, what is over it gone up" {
  let k = foot_case(40)
  let was = k.live.get(38).map(fn(v) { v.rect().1 })
  k.more[39].set(50.0)
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((was, k.live.get(38).map(fn(v) { v.rect().1 }), k.off_foot()), (Some(40.0), Some(-10.0), 0.0))
}

///|
test "scrolls_window following its foot under a head: read 60 up from its foot, a block under what shows grown (words come at its end): where the wheel put it, not back at its foot" {
  let k = foot_case(40)
  k.tree.wheel_at(450.0, 250.0, 0.0, -60.0, 0, 10.0) |> ignore
  k.tree.frame(600.0, 400.0) |> ignore
  let was = k.live.get(38).map(fn(v) { v.rect().1 })
  // (its last block, its foot 60 under what shows, comes to be 20 taller: the list, laid out again for it, is measured
  // within the window's 400 first; by that it could go 100 less far than it can in the 300 it shows, and it was put
  // there, then, at its foot by that, back to its foot)
  k.more[39].set(20.0)
  k.tree.frame(600.0, 400.0) |> ignore
  assert_eq((was, k.live.get(38).map(fn(v) { v.rect().1 }), k.off_foot()), (Some(100.0), Some(100.0), 80.0))
}

///|
test "scrolls_window following its foot under a head: a block come at its foot, not measured yet, is made alone, what showed over it kept made" {
  // (its last two, 150 and 210 tall, showing; one come under them 30 tall, counted 48: a job's output's line more)
  let k = foot_case(40)
  let made = k.made.length()
  k.keys.set(Array::makei(41, fn(i) { i }))
  k.tree.frame(600.0, 400.0) |> ignore
  let shown = k.live.keys().collect()
  shown.sort()
  // (made: the one come alone, those over it the blocks they were; at its foot, all three showing)
  assert_eq((k.made[made:].to_owned(), shown, k.off_foot()), ([40], [38, 39, 40], 0.0))
}

///|
test "scrolls_window following its foot: not held, a block over its last grown at rest (no block come or gone) is followed in that layout, what is over it gone up by as much" {
  let k = foot_case(40)
  let y37 = k.live.get(37).map(fn(v) { v.rect().1 })
  let y39 = k.live.get(39).map(fn(v) { v.rect().1 })
  // (block 38, 150 tall, the one over the last, comes to be 50 taller: nothing come or gone, only a height)
  k.more[38].set(50.0)
  k.tree.frame(600.0, 400.0) |> ignore
  let up = fn(y : Double?) { y.map(fn(v) { v - 50.0 }) }
  assert_eq(
    (k.live.get(37).map(fn(v) { v.rect().1 }), k.live.get(39).map(fn(v) { v.rect().1 }), k.off_foot()),
    (up(y37), y39, 0.0),
  )
}
