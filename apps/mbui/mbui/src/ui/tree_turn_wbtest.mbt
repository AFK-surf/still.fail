// What a node of the window's tree draws itself turned about its middle (View::turn), and the lines it draws
// (View::lines): drawn as an old view's box draws its lines turned by a look (Ctx::lines, Ctx::look's rot); turned
// again where it is drawn, nothing of it made, laid out or built again; about its middle as it is drawn, what holds it
// scaled and moved; cut as what holds it cuts; not what it holds, nor where it takes a press; turned as the clock says
// at a moment however the frames before it came; its clock let go with it.

///|
/// A bar 40 long across a box 40 by 10, 4 wide, red.
let turn_bar : Array[Line] = [line([(0.0, 5.0), (40.0, 5.0)], width=4.0, color=0xCC2020FFL)]

///|
let quarter : Double = 1.5707963267948966

///|
/// The instances drawn in the last frame that are pieces of lines (kind 10): where and how big, their ends, their colour
/// and opacity, and how they are turned (the turn, its point, whether what cuts them stays).
fn line_pieces(t : Tester) -> Array[Array[Double]] {
  t
  .drawn_instances()
  .filter(fn(i) { i[5] == 10.0 })
  .map(fn(i) { [i[0], i[1], i[2], i[3], i[4], i[8], i[9], i[10], i[11], i[12], i[13], i[14], i[15], i[32], i[33], i[34], i[35]] })
}

///|
/// The bar in an old view's box at (20, 30), turned `r` about its middle (a look's turn).
fn old_turned(r : Double) -> Array[Array[Double]] {
  let t = Tester::new(
    fn(c) {
      c.box(left=20.0, top=30.0, fn() {
        let b = c.lines(turn_bar, w=Px(40.0), h=Px(10.0))
        c.look(b, look(rot=r))
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  t.draw()
  line_pieces(t)
}

///|
/// The bar in a node of the tree at (20, 30), turned as `turn` says, in a window 400 by 300.
fn tree_turned(turn : @signals.Signal[Double]) -> (Tester, Ref[@view.View?]) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let bar : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.padding(Is((20.0, 30.0, 0.0, 0.0))) |> ignore
      bar.val = Some(
        p.box(fn(b) {
          b
          .width(Is(Some(40.0)))
          .height(Is(Some(10.0)))
          .lines(Is(turn_bar))
          .turn(By(fn() { turn.get() }))
          |> ignore
        }),
      )
    })
    |> ignore
  })
  t.draw()
  (t, bar)
}

///|
test "a node's lines turned a quarter about its middle, drawn as an old view's box draws them turned so; not turned, as it draws them so" {
  let turn = @signals.signal(quarter, same=fn(a, b) { a == b })
  let (t, _) = tree_turned(turn)
  let turned = line_pieces(t)
  turn.set(0.0)
  t.frame()
  let plain = line_pieces(t)
  assert_eq(
    (turned == old_turned(quarter), plain == old_turned(0.0), turned != plain, turned.length() > 0),
    (true, true, true, true),
    msg="tree \{turned}\nold \{old_turned(quarter)}",
  )
}

///|
test "a node turned again: its lines drawn turned anew, nothing of it made, laid out or built again" {
  let turn = @signals.signal(0.0, same=fn(a, b) { a == b })
  let (t, _) = tree_turned(turn)
  let before = line_pieces(t)
  let work = view_tree().unwrap().work()
  let (made, laid, nodes, structure) = (view_paint_work.made, work.laid, work.made, work.structure)
  turn.set(quarter)
  t.frame()
  let after = line_pieces(t)
  let now = view_tree().unwrap().work()
  assert_eq(
    (before != after, after[0][13], view_paint_work.made - made, now.laid - laid, now.made - nodes, now.structure - structure),
    (true, quarter, 0, 0, 0, 0),
  )
}

///|
test "a node turned in one that is drawn half as big and moved: about its own middle where it is drawn" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let bar : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.width(Is(Some(200.0))).height(Is(Some(100.0))).scale(Is(0.5), about=At(0.0, 0.0)).offset(Is((30.0, 40.0))) |> ignore
      p.box(fn(q) {
        q.padding(Is((20.0, 30.0, 0.0, 0.0))) |> ignore
        bar.val = Some(
          q.box(fn(b) {
            b.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(Is(turn_bar)).turn(Is(quarter)) |> ignore
          }),
        )
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (x, y, w, h) = bar.val.unwrap().rect()
  let pieces = line_pieces(t)
  assert_eq(
    (pieces.length() > 0, pieces[0][13], pieces[0][14], pieces[0][15], (x, y, w, h)),
    (true, quarter, x + w / 2.0, y + h / 2.0, (40.0, 55.0, 20.0, 5.0)),
  )
}

///|
test "a node turned in one that cuts what it holds: cut where the one that holds it is drawn, not turned with it" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.width(Is(Some(30.0))).height(Is(Some(30.0))).clips(Is(true)) |> ignore
      p.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(Is(turn_bar)).turn(Is(quarter)) |> ignore })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let cut = t.drawn_instances().filter(fn(i) { i[5] == 10.0 }).map(fn(i) { (i[16], i[17], i[18], i[19], i[35]) })
  assert_eq((cut.length() > 0, cut.iter().all(fn(c) { c == (0.0, 0.0, 30.0, 30.0, 1.0) })), (true, true), msg="\{cut}")
}

///|
test "a node turned: what it holds drawn as it is, not turned; a press taken where it is laid out, not where it is drawn turned" {
  let presses = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.width(Is(Some(100.0))).height(Is(Some(10.0))).lines(Is(turn_bar)).turn(Is(quarter)).on_press(fn() { presses.val += 1 }) |> ignore
      p.box(fn(k) { k.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(Is(turn_bar)) |> ignore }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let turns = line_pieces(t).map(fn(i) { i[13] })
  // (90 along its length, 5 down: in it as laid out, outside it turned a quarter about (50, 5))
  t.tap(90.0, 5.0)
  assert_eq((turns.contains(quarter), turns.contains(0.0), presses.val), (true, true, 1))
}

///|
/// The bar in a node of the tree turned by the clock, once round every 800 ms, drawn once.
fn clock_turned(t : Tester) -> Unit {
  set_view_app(fn(root) {
    root.box(fn(b) {
      b.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(Is(turn_bar)).turn(By(fn() { b.cycle(800.0) * 2.0 * quarter * 2.0 })) |> ignore
    })
    |> ignore
  })
  t.draw()
}

///|
test "a node turned by the clock: at a moment, turned as far as that moment says, the frames before drawn one after another or not at all" {
  let stepped = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  clock_turned(stepped)
  let end = stepped.time() + 1300.0
  while stepped.time() + 16.0 < end {
    stepped.frame_at(stepped.time() + 16.0)
  }
  stepped.frame_at(end)
  let a = line_pieces(stepped)
  let jumped = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  clock_turned(jumped)
  jumped.frame_at(jumped.time() + 1300.0)
  let b = line_pieces(jumped)
  assert_eq((a == b, a.length() > 0 && a[0][13] != 0.0), (true, true))
}

///|
test "a node turned by the clock let go: nothing reads the clock for it any more" {
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(b) {
      b.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(Is(turn_bar)).turn(By(fn() { b.cycle(800.0) * 4.0 * quarter })) |> ignore
    })
  })
  t.draw()
  let reading = view_tree().unwrap().cycle_read()
  shown.set(false)
  t.frame()
  assert_eq((reading, view_tree().unwrap().cycle_read()), (true, false))
}

///|
test "a node turned about the middle of what it draws, its lines changed: turned about the middle of the new ones, the node the same; turned again alone, nothing made again" {
  let lines = @signals.signal(turn_bar)
  let turn = @signals.signal(quarter, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let bar : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    bar.val = Some(
      root.box(fn(b) {
        b.width(Is(Some(40.0))).height(Is(Some(10.0))).lines(By(fn() { lines.get() })).turn(By(fn() { turn.get() }), drawn=true) |> ignore
      }),
    )
  })
  t.draw()
  let about = fn() { line_pieces(t).map(fn(p) { (p[14], p[15]) }) }
  let first = about()
  let id = bar.val.unwrap().id()
  // (a short bar at the left: what it draws now covers 0 to 10 across, its middle 5 in, not 20)
  lines.set([line([(0.0, 5.0), (10.0, 5.0)], width=4.0, color=0xCC2020FFL)])
  t.frame()
  let second = about()
  let made = view_paint_work.made
  turn.set(quarter * 2.0)
  t.frame()
  assert_eq(
    (first[0], second[0], bar.val.unwrap().id() == id, view_paint_work.made - made, about()[0] == second[0]),
    ((20.0, 5.0), (5.0, 5.0), true, 0, true),
  )
}

///|
/// A node drawn half as big about the middle of what it draws (View::scale's Drawn), holding a block 60 wide at its
/// left, of colour, and one 60 wide beside it, of none unless `lit` says, drawn off `off` across: the node.
fn drawn_pivot(lit : @signals.Signal[Bool], off : @signals.Signal[Double]) -> (Tester, @view.View) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    node.val = Some(
      root.box(fn(p) {
        p.row(Is(true)).width(Is(Some(120.0))).height(Is(Some(20.0))).scale(Is(0.5), about=Drawn) |> ignore
        p.box(fn(a) { a.width(Is(Some(60.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
        p.box(fn(b) {
          b.width(Is(Some(60.0))).ground(By(fn() { if lit.get() { 0xCC3333FFL } else { 0L } })).offset(By(fn() { (off.get(), 0.0) })) |> ignore
        })
        |> ignore
      }),
    )
  })
  t.draw()
  (t, node.val.unwrap())
}

///|
test "a node grown about the middle of what it draws: a block beside the drawn one given a colour, or drawn off, grown about the middle of both from the first frame after; drawn smaller again alone, about the same" {
  let lit = @signals.signal(false, same=fn(a, b) { a == b })
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let (t, node) = drawn_pivot(lit, off)
  // (drawn half as big about a point `px` in: its left drawn px / 2 in)
  let left = fn() { node.rect().0 }
  let alone = left()
  lit.set(true)
  t.frame()
  let both = left()
  off.set(40.0)
  t.frame()
  let moved = left()
  assert_eq((alone, both, moved), (15.0, 30.0, 40.0))
}
