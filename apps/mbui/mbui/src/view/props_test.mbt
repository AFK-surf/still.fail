// A node's properties each bound on its own (View::bind, by Prop): many of one node each followed as what says it
// changes, none letting go of another's; the two ways of saying its width one binding, the last said in force.
// Where what a node holds lies along it (View::lies_along, Lies): at its start, its end, or spread between them.
// One filling what holds it across (View::fills_across), whatever that lines it up by, its margin kept.

///|
test "props: one node's ground, opacity, scale, corner, words centred and words each followed as they change, none letting go of another" {
  let ground = @signals.signal(0x112233FFL, same=fn(a, b) { a == b })
  let alpha = @signals.signal(1.0, same=fn(a, b) { a == b })
  let scale = @signals.signal(1.0, same=fn(a, b) { a == b })
  let radius = @signals.signal(0.0, same=fn(a, b) { a == b })
  let centred = @signals.signal(false, same=fn(a, b) { a == b })
  let words = @signals.signal("a", same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .width(Is(Some(100.0)))
        .height(Is(Some(40.0)))
        .ground(By(fn() { ground.get() }))
        .alpha(By(fn() { alpha.get() }))
        .scale(By(fn() { scale.get() }), about=At(0.0, 0.0))
        .radius(By(fn() { radius.get() }))
        .words_centered(By(fn() { centred.get() }))
        .words(By(fn() { words.get() }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let seen = fn() {
    let d = t.drawn_of(id.val.unwrap()).unwrap()
    (d.ground, d.alpha, d.w, d.radius, d.words_center, d.words)
  }
  assert_eq(seen(), (0x112233FFL, 1.0, 100.0, 0.0, false, "a"), msg="as made")
  t.event(10.0, fn() {
    ground.set(0x445566FFL)
    alpha.set(0.5)
    scale.set(0.5)
    radius.set(8.0)
    centred.set(true)
    words.set("b")
  })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(seen(), (0x445566FFL, 0.5, 50.0, 8.0, true, "b"), msg="each as it changed")
  t.event(20.0, fn() {
    ground.set(0x778899FFL)
    words.set("c")
  })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(seen(), (0x778899FFL, 0.5, 50.0, 8.0, true, "c"), msg="each again, the rest as they were")
}

///|
test "props: a node's width bound in points, then bound as a share of what holds it: one binding, the first let go of; its points changed after take nothing back, its share changed is followed" {
  let points = @signals.signal(100.0, same=fn(a, b) { a == b })
  let share = @signals.signal(0.5, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .width(By(fn() { Some(points.get()) }))
        .width_share(By(fn() { share.get() }))
        .height(Is(Some(10.0)))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let w = fn() { t.drawn_of(id.val.unwrap()).unwrap().w }
  assert_eq(w(), 200.0, msg="the share in force")
  t.event(10.0, fn() { points.set(120.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(w(), 200.0, msg="its points changed: nothing taken back")
  t.event(20.0, fn() { share.set(0.25) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(w(), 100.0, msg="its share changed: followed")
}

///|
test "props: a node's words bound, then bound in pieces: one binding, the first let go of; its words changed after take nothing back, its pieces changed are followed" {
  let words = @signals.signal("plain", same=fn(a, b) { a == b })
  let runs = @signals.signal("pieces", same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n
        .over(Is(true))
        .words(By(fn() { words.get() }))
        .words_runs(By(fn() { [@view.words_run(runs.get())] }))
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let shown = fn() { t.drawn_of(id.val.unwrap()).unwrap().runs.map(fn(r) { r.text }) }
  assert_eq(shown(), ["pieces"], msg="the pieces in force")
  t.event(10.0, fn() { words.set("again") })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(shown(), ["pieces"], msg="its words changed: nothing taken back")
  t.event(20.0, fn() { runs.set("more") })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(shown(), ["more"], msg="its pieces changed: followed")
}

///|
/// `n` boxes `side` long along a box 100 long (a row, else a column), 10 apart and lying along it as `lies` says
/// (`lines`: a row wrapping, its lines so far apart): where each is drawn.
fn lies_tree(lies : @signals.Signal[@view.Lies], n : Int, row? : Bool = true, side? : Double = 20.0, lines? : Double? = None) -> () -> Array[(Double, Double)] {
  let ids : Array[@view.NodeId] = []
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.row(Is(row)).gap(Is(10.0)).wraps(Is(lines)).lies_along(By(fn() { lies.get() })) |> ignore
        if row {
          r.width(Is(Some(100.0))) |> ignore
        } else {
          r.height(Is(Some(100.0))) |> ignore
        }
        for _ in 0..<n {
          r.box(fn(b) {
            ids.push(b.id())
            b.ground(Is(0x336699FFL)) |> ignore
            if row {
              b.width(Is(Some(side))).height(Is(Some(10.0))) |> ignore
            } else {
              b.width(Is(Some(10.0))).height(Is(Some(side))) |> ignore
            }
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  fn() {
    t.frame(390.0, 844.0) |> ignore
    ids.map(fn(id) {
      match t.drawn().search_by(fn(d) { d.id == id }) {
        Some(i) => (t.drawn()[i].x, t.drawn()[i].y)
        None => (-1.0, -1.0)
      }
    })
  }
}

///|
test "props: what a row holds lies between its ends (Lies's Between), the first at its start and the last at its end, what is left shared between them; one alone at its start; from its start as said, and back" {
  let lies = @signals.signal(@view.Lies::Between)
  let two = lies_tree(lies, 2)
  assert_eq(two(), [(0.0, 0.0), (80.0, 0.0)], msg="two: at its ends")
  let three = lies_tree(lies, 3)
  assert_eq(three(), [(0.0, 0.0), (40.0, 0.0), (80.0, 0.0)], msg="three: the middle one halfway")
  let one = lies_tree(lies, 1)
  assert_eq(one(), [(0.0, 0.0)], msg="one alone: at its start")
  // (said otherwise as it changes, and back)
  lies.set(Start)
  assert_eq(two(), [(0.0, 0.0), (30.0, 0.0)], msg="said from its start: 10 apart")
  lies.set(End)
  assert_eq(two(), [(50.0, 0.0), (80.0, 0.0)], msg="said at its end")
  lies.set(Between)
  assert_eq(two(), [(0.0, 0.0), (80.0, 0.0)], msg="between again")
}

///|
test "props: a row that wraps lies between its ends line by line: a line of two at its ends, a line of one at its start" {
  let lies = @signals.signal(@view.Lies::Between)
  // (40 and 10 and 40 fit in 100, the third does not: on a line of its own, 10 and 4 down)
  let at = lies_tree(lies, 3, side=40.0, lines=Some(4.0))
  assert_eq(at(), [(0.0, 0.0), (60.0, 0.0), (0.0, 14.0)])
}

///|
test "props: what a column holds lies between its top and its foot (Lies's Between)" {
  let lies = @signals.signal(@view.Lies::Between)
  let at = lies_tree(lies, 3, row=false)
  assert_eq(at(), [(0.0, 0.0), (0.0, 40.0), (0.0, 80.0)])
}

///|
/// A box 100 across (a column 100 wide, or a row 100 high) lining what it holds up as `lines` says, holding one 20
/// across (along the way it lays it out, 10) that fills it across as `fills` says, `margin` round it: where that one is
/// drawn and how big (x, y, w, h).
fn fills_tree(
  fills : @signals.Signal[Bool],
  lines : @view.Along,
  row? : Bool = false,
  margin? : (Double, Double, Double, Double) = (0.0, 0.0, 0.0, 0.0),
) -> () -> (Double, Double, Double, Double) {
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.row(Is(row)).lines_up(Is(Some(lines))) |> ignore
        if row {
          r.width(Is(Some(10.0))).height(Is(Some(100.0))) |> ignore
        } else {
          r.width(Is(Some(100.0))).height(Is(Some(10.0))) |> ignore
        }
        r.box(fn(b) {
          id.val = Some(b.id())
          b.ground(Is(0x336699FFL)).margin(Is(margin)).fills_across(By(fn() { fills.get() })) |> ignore
          if row {
            b.width(Is(Some(10.0))) |> ignore
          } else {
            b.height(Is(Some(10.0))) |> ignore
          }
          // (20 across of its own: what it holds)
          b.box(fn(i) {
            if row {
              i.height(Is(Some(20.0))) |> ignore
            } else {
              i.width(Is(Some(20.0))) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  fn() {
    t.frame(390.0, 844.0) |> ignore
    match t.drawn().search_by(fn(d) { d.id == id.val.unwrap() }) {
      Some(i) => (t.drawn()[i].x, t.drawn()[i].y, t.drawn()[i].w, t.drawn()[i].h)
      None => (-1.0, -1.0, -1.0, -1.0)
    }
  }
}

///|
test "props: one said to fill what holds it across does, whatever that lines what it holds up by, in a column and in a row" {
  let fills = @signals.signal(true)
  for lines in [@view.Along::Start, Middle, End] {
    assert_eq(fills_tree(fills, lines)(), (0.0, 0.0, 100.0, 10.0), msg="a column lining up \{Repr(lines)}")
    assert_eq(fills_tree(fills, lines, row=true)(), (0.0, 0.0, 10.0, 100.0), msg="a row lining up \{Repr(lines)}")
  }
}

///|
test "props: one filling what holds it across keeps its margin there" {
  let fills = @signals.signal(true)
  assert_eq(fills_tree(fills, Middle, margin=(6.0, 0.0, 4.0, 0.0))(), (6.0, 0.0, 90.0, 10.0))
  assert_eq(fills_tree(fills, Middle, row=true, margin=(0.0, 6.0, 0.0, 4.0))(), (0.0, 6.0, 10.0, 90.0))
}

///|
test "props: one said to fill what holds it across, then said not to, is lined up as what holds it says again" {
  let fills = @signals.signal(false)
  let starts = fills_tree(fills, Start)
  let middles = fills_tree(fills, Middle)
  let ends = fills_tree(fills, End)
  let before = [starts(), middles(), ends()]
  assert_eq(before, [(0.0, 0.0, 20.0, 10.0), (40.0, 0.0, 20.0, 10.0), (80.0, 0.0, 20.0, 10.0)])
  fills.set(true)
  assert_eq([starts(), middles(), ends()], [(0.0, 0.0, 100.0, 10.0), (0.0, 0.0, 100.0, 10.0), (0.0, 0.0, 100.0, 10.0)])
  fills.set(false)
  assert_eq([starts(), middles(), ends()], before)
}
