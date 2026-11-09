// A node laid out never narrower than it has been (View::keeps_width): at each change of what sets its width, as wide
// as that change laid it out, kept; what it holds narrower, as wide as it was; wider, as wide as that, whatever frames
// come between; no wider than its most as that is made less.

///|
test "keeps_width: what it holds made narrower, as wide as it was; wider, wider; its most made less than that, no wider than its most, laid out so at once" {
  let inner = @signals.signal(120.0, same=fn(a, b) { a == b })
  let most = @signals.signal(400.0, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      // (in a row: as wide as what it holds, not stretched across)
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(n) {
          id.val = Some(n.id())
          n.keeps_width(fn() { inner.get() }, most=fn() { most.get() }) |> ignore
          n.box(fn(k) { k.width(By(fn() { Some(inner.get()) })).height(Is(Some(10.0))) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let w = fn() {
    t.frame(500.0, 300.0) |> ignore
    t.drawn_of(id.val.unwrap()).map(fn(d) { d.w })
  }
  assert_eq(w(), Some(120.0), msg="as wide as what it holds")
  t.event(10.0, fn() { inner.set(60.0) })
  assert_eq(w(), Some(120.0), msg="what it holds narrower: as wide as it was")
  t.event(20.0, fn() { inner.set(200.0) })
  assert_eq(w(), Some(200.0), msg="wider: as wide as that")
  t.event(30.0, fn() { inner.set(60.0) })
  t.event(30.0, fn() { most.set(150.0) })
  assert_eq(w(), Some(150.0), msg="its most less than it has been: its most, the frame it is")
  // (wider then narrower, no frame between: as wide as the wider laid it out)
  t.event(40.0, fn() { most.set(400.0) })
  t.event(41.0, fn() { inner.set(300.0) })
  t.event(42.0, fn() { inner.set(60.0) })
  assert_eq(w(), Some(300.0), msg="wider then narrower, no frame between: as the wider")
}

///|
/// A node keeping its width (by `on`) holding 100 and, while `on`, 80 more shown after it (made as the same change
/// tells it, after the node said what it keeps by; as wide as `on` says, none as it goes), `on` told true then false:
/// in two events (`how` 0), two sets outside any (1), two moments come on its timeline (2); a frame drawn between them
/// (`between`) or none: how wide it is laid out with it shown (none: no frame between), and after it goes.
fn shown_in_it(how : Int, between : Bool) -> (Double?, Double?) raise {
  let on = @signals.signal(false)
  let now = Ref(0.0)
  let id : Ref[@view.NodeId?] = Ref(None)
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(r) {
        r.row(Is(true)) |> ignore
        r.box(fn(n) {
          id.val = Some(n.id())
          node.val = Some(n)
          n.row(Is(true)).keeps_width(fn() { on.get() }) |> ignore
          n.box(fn(k) { k.width(Is(Some(100.0))).height(Is(Some(10.0))) |> ignore }) |> ignore
          // (as wide as `on` says, 80 or none: as words said by what shows them, "" as it goes)
          n.show(fn() { on.get() }, fn(m) {
            m.width(By(fn() { Some(if on.get() { 80.0 } else { 0.0 }) })).height(Is(Some(10.0))) |> ignore
          })
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  let w = fn() {
    t.frame(500.0, 300.0, now=now.val) |> ignore
    t.drawn_of(id.val.unwrap()).map(fn(d) { d.w })
  }
  w() |> ignore
  let mut shown = None
  // (the moments come: each at its own, in order)
  let came : Array[(Bool, Double)] = []
  match how {
    0 => {
      t.event(10.0, fn() { on.set(true) })
      if between {
        now.val = 15.0
        shown = w()
      }
      t.event(20.0, fn() { on.set(false) })
    }
    1 => {
      on.set(true)
      if between {
        shown = w()
      }
      on.set(false)
    }
    _ => {
      let n = node.val.unwrap()
      n.at_moment(10.0, fn() {
        came.push((true, n.cause_at()))
        on.set(true)
      })
      |> ignore
      n.at_moment(20.0, fn() {
        came.push((false, n.cause_at()))
        on.set(false)
      })
      |> ignore
      if between {
        now.val = 15.0
        shown = w()
      }
    }
  }
  now.val = 30.0
  let gone = w()
  if how == 2 {
    assert_eq(came, [(true, 10.0), (false, 20.0)], msg="its moments come, each at its own")
  }
  (shown, gone)
}

///|
test "keeps_width: what the change that tells it shows in it counted, in an event, outside any or at a moment, a frame drawn between or none: as wide once that goes" {
  for how in [0, 1, 2] {
    for between in [true, false] {
      let (shown, gone) = shown_in_it(how, between)
      if between {
        assert_eq(shown, Some(180.0), msg="\{how}: shown, as wide as it and the rest")
      }
      assert_eq(gone, Some(180.0), msg="\{how} between \{between}: gone, as wide as it was")
    }
  }
}
