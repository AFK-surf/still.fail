// A column's blocks of one kind taken by those that come to show as others no more do (View::scrolls_window's
// `reused`): 100 tall, 30 blocks of 40, 50 or 60 (by their keys) counted as 80 before they are first laid out; how many
// are made, which block holds which key, and where.

///|
priv struct ReuseCase {
  tree : @view.Tree
  scroll : @view.Scroll
  on : @signals.Signal[Bool]
  /// how many blocks were made, how many live now
  made : Ref[Int]
  live : Ref[Int]
  /// each live block with what says its key now
  blocks : Array[(@view.View, () -> Int)]
  /// what each block's width reads besides, and how many times one was worked out of it
  outside : @signals.Signal[Int]
  reads : Ref[Int]
}

///|
fn reuse_case() -> ReuseCase {
  let scroll = @view.Scroll::list()
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let made = Ref(0)
  let live = Ref(0)
  let blocks : Array[(@view.View, () -> Int)] = []
  let outside = @signals.signal(0, same=fn(a, b) { a == b })
  let reads = Ref(0)
  let tree = @view.Tree::new(fn(root) {
    root.show(at_once=true, fn() { on.get() }, fn(s) {
      s.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        o.scrolls_window(
          scroll,
          fn() { Array::makei(30, fn(i) { i }) },
          est=80.0,
          fn(_, _) { @halt.saying("every block is of a kind another may take") },
          reused=fn(_) { Some(0) },
          make_reused=fn(b, key) {
            made.val = made.val + 1
            live.val = live.val + 1
            blocks.push((b, key))
            b.owns(fn() {
              live.val = live.val - 1
              match blocks.search_by(fn(x) { physical_equal(x.1, key) }) {
                Some(i) => blocks.remove(i) |> ignore
                None => ()
              }
            })
            |> ignore
            b.height(By(fn() { Some(reuse_tall(key())) })) |> ignore
            b.width(By(fn() {
              reads.val = reads.val + 1
              Some(200.0 + outside.get().to_double())
            }))
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    })
  })
  tree.frame(390.0, 844.0) |> ignore
  { tree, scroll, on, made, live, blocks, outside, reads }
}

///|
/// How tall block `k` is.
fn reuse_tall(k : Int) -> Double {
  40.0 + (k % 3).to_double() * 10.0
}

///|
/// Where block `k` stands in the column.
fn reuse_top(k : Int) -> Double {
  let mut y = 0.0
  for i in 0..<k {
    y = y + reuse_tall(i)
  }
  y
}

///|
/// The blocks that show (held by the column, a key each), their keys in order, each where its key's block is.
fn ReuseCase::placed(self : ReuseCase) -> (Array[Int], Bool) {
  let at = self.scroll.at(self.tree)
  let keys = []
  let mut placed = true
  for b in self.blocks {
    let (v, key) = b
    guard v.parent() is Some(_) else { continue }
    let k = key()
    keys.push(k)
    let (_, y, _, h) = v.rect()
    if y != reuse_top(k) - at || h != reuse_tall(k) {
      placed = false
    }
  }
  keys.sort()
  (keys, placed)
}

///|
test "scrolls_window reused: scrolled down a block at a time, those that leave taken by those that come, each where its key's is" {
  let c = reuse_case()
  let first = (c.made.val, c.placed())
  // (a wheel's twelve turns of 40, each at its moment, each drawn)
  for t in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 110.0, 120.0] {
    c.tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, t) |> ignore
    c.tree.frame(390.0, 844.0) |> ignore
  }
  let (keys, placed) = c.placed()
  // (made: those that showed first, and no more than one put by for each that came at once)
  assert_true(c.made.val <= 6, msg="made \{c.made.val}")
  assert_eq((first.1, placed, keys.length() >= 2, keys[0] <= 11 && keys[keys.length() - 1] >= 10), (([0, 1, 2], true), true, true, true))
}

///|
test "scrolls_window reused: those put by and those that show let go with the column" {
  let c = reuse_case()
  // (a wheel's six turns of 120, each at its moment, each drawn)
  for t in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0] {
    c.tree.wheel_at(150.0, 50.0, 0.0, 120.0, 0, t) |> ignore
    c.tree.frame(390.0, 844.0) |> ignore
  }
  assert_true(c.live.val > 0)
  c.on.set(false)
  c.tree.frame(390.0, 844.0) |> ignore
  assert_eq(c.live.val, 0)
}

///|
test "scrolls_window reused: those put by follow nothing, those that show what they bind" {
  let c = reuse_case()
  // (a wheel's turn of 40: the first, 40 tall, no more shows, put by)
  c.tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, 10.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  // (those in sight: those put by are left where they were, out of it)
  let showing = c.blocks
    .filter(fn(b) {
      let (_, y, _, h) = b.0.rect()
      y + h > 0.0 && y < 100.0
    })
    .length()
  let before = c.reads.val
  c.outside.set(1)
  c.tree.frame(390.0, 844.0) |> ignore
  // (worked out again for the two that show, none for the one put by)
  assert_eq((c.reads.val - before, showing, c.live.val), (2, 2, 3))
}

///|
test "scrolls_window reused: what a block taken for another key shows or no more shows by that key is so at once, as were the block made anew, no way made in or closed" {
  let scroll = @view.Scroll::list()
  let blocks : Array[@view.View] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { Array::makei(30, fn(i) { i }) },
        est=50.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) {
          blocks.push(b)
          b.box(fn(line) {
            line.height(Is(Some(40.0))) |> ignore
          })
          |> ignore
          // (a line shown by its key alone: every other block has it)
          b.show(fn() { key() % 2 == 1 }, fn(s) {
            s.box(fn(more) { more.height(Is(Some(10.0))) |> ignore }) |> ignore
          })
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  // (a wheel's twelve turns of 40, each at its moment, each drawn: blocks taken by keys odd where theirs were even)
  for t in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 110.0, 120.0] {
    tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  let ways = blocks.filter(fn(b) { b.alive() && b.comes_end() >= 0.0 }).length()
  assert_eq(ways, 0, msg="blocks whose line made its way in or closed as they were taken for another key")
}

///|
test "scrolls_window reused: blocks taken for other keys by a wheel, the mark put back with each change: a show elsewhere after them makes its way in" {
  let scroll = @view.Scroll::list()
  let more = @signals.signal(false)
  let shown : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(col) {
      col.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        o.scrolls_window(
          scroll,
          fn() { Array::makei(30, fn(i) { i }) },
          est=50.0,
          fn(_, _) { @halt.saying("every block is of a kind another may take") },
          reused=fn(_) { Some(0) },
          make_reused=fn(b, key) {
            b.show(fn() { key() % 2 == 1 }, fn(s) { s.box(fn(l) { l.height(Is(Some(10.0))) |> ignore }) |> ignore })
            b.box(fn(line) { line.height(Is(Some(40.0))) |> ignore }) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
      col.show(fn() { more.get() }, fn(s) {
        shown.val = Some(s)
        s.box(fn(l) { l.height(Is(Some(30.0))) |> ignore }) |> ignore
      })
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  for t in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0] {
    tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  assert_true(!@view.answer_marks_left())
  more.set(true)
  tree.frame(390.0, 844.0) |> ignore
  let came = match shown.val {
    Some(v) => v.comes_end()
    None => -1.0
  }
  assert_true(came >= 0.0, msg="the show after the wheel's blocks made no way in: \{came}")
}

///|
test "scrolls_window reused: a block taken for another key as the column's fill runs in a frame's layout draws its new key's words in that frame" {
  let scroll = @view.Scroll::list()
  // (each block's line with what says its key)
  let lines : Array[(@view.View, () -> Int)] = []
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(
        scroll,
        fn() { Array::makei(40, fn(i) { i }) },
        est=22.0,
        fn(_, _) { @halt.saying("every block is of a kind another may take") },
        reused=fn(_) { Some(0) },
        make_reused=fn(b, key) {
          b.box(fn(line) {
            lines.push((line, key))
            line.height(Is(Some(22.0))).words(By(fn() { "row \{key()}" })) |> ignore
          })
          |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(390.0, 844.0) |> ignore
  // (one turn of 400: the window 18 rows down in one go, what it takes taken as the frame lays the column out)
  tree.wheel_at(150.0, 50.0, 0.0, 400.0, 0, 10.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  let wrong = []
  let mut seen = 0
  for l in lines {
    let (line, key) = l
    guard line.alive() else { continue }
    let (_, y, _, h) = line.rect()
    guard y + h > 0.0 && y < 200.0 else { continue }
    seen = seen + 1
    let k = @signals.untracked(key)
    match tree.drawn_of(line.id()) {
      Some(d) if d.words == "row \{k}" => ()
      Some(d) => wrong.push("key \{k} drawn \{d.words}")
      None => wrong.push("key \{k} not drawn")
    }
  }
  assert_eq((seen > 0, wrong), (true, []))
}
