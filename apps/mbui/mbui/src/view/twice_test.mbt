///|
/// Two boxes side by side, each 40 × 40: the left pressed and pressed twice (what each did, in order), the right pressed
/// alone; the clock `now`.
fn twice_tree(now : Ref[Double], did : Array[String]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.row(Is(true)) |> ignore
        row.box(fn(b) {
          b
          .width(Is(Some(40.0)))
          .height(Is(Some(40.0)))
          .on_press(fn() { did.push("press") })
          .on_double_press(fn() { did.push("twice") })
          |> ignore
        })
        |> ignore
        row.box(fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(40.0))).on_press(fn() { did.push("other") }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
}

///|
fn press_at(t : @view.Tree, now : Ref[Double], at : Double, x : Double, y : Double) -> Bool {
  now.val = at
  t.press(x, y)
}

///|
test "twice: the second of two presses soon and near does its own in place of the press; a third starts anew" {
  let now = Ref(0.0)
  let did : Array[String] = []
  let t = twice_tree(now, did)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  assert_true(press_at(t, now, 100.0, 10.0, 10.0))
  assert_true(press_at(t, now, 300.0, 12.0, 11.0))
  assert_true(press_at(t, now, 400.0, 12.0, 11.0))
  assert_eq(did, ["press", "twice", "press"])
}

///|
test "twice: too late, too far, or another pressed between, each is a press of its own" {
  let now = Ref(0.0)
  let did : Array[String] = []
  let t = twice_tree(now, did)
  t.frame(390.0, 844.0, now=0.0) |> ignore
  // (as late as the window itself: not within it)
  press_at(t, now, 0.0, 10.0, 10.0) |> ignore
  press_at(t, now, @view.double_press_ms, 10.0, 10.0) |> ignore
  // (past the slop)
  press_at(t, now, 2000.0, 10.0, 10.0) |> ignore
  press_at(t, now, 2100.0, 10.0 + @view.double_press_slop + 1.0, 10.0) |> ignore
  // (another between)
  press_at(t, now, 4000.0, 10.0, 10.0) |> ignore
  press_at(t, now, 4100.0, 50.0, 10.0) |> ignore
  press_at(t, now, 4200.0, 10.0, 10.0) |> ignore
  assert_eq(did, ["press", "press", "press", "press", "press", "other", "press"])
}

///|
test "twice: by the hand the host says, as each is let go" {
  let now = Ref(0.0)
  let did : Array[String] = []
  let t = twice_tree(now, did)
  // (a finger's: sooner, less exact)
  t.twice_within(fn() { (300.0, 30.0) })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  press_at(t, now, 0.0, 5.0, 5.0) |> ignore
  press_at(t, now, 250.0, 30.0, 30.0) |> ignore
  press_at(t, now, 1000.0, 5.0, 5.0) |> ignore
  press_at(t, now, 1350.0, 5.0, 5.0) |> ignore
  assert_eq(did, ["press", "twice", "press", "press"])
}

///|
test "twice: one that only says the second does nothing pressed once, and a screen reader's press is a press alone" {
  let now = Ref(0.0)
  let twice = Ref(0)
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        id.val = Some(b.id())
        b
        .width(Is(Some(40.0)))
        .height(Is(Some(40.0)))
        .says(Is(Some(@view.said(Button, label="放大"))))
        .on_double_press(fn() { twice.val = twice.val + 1 })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  t.frame(390.0, 844.0, now=0.0) |> ignore
  // (it takes a press: the first of two)
  assert_true(press_at(t, now, 10.0, 5.0, 5.0))
  assert_eq(twice.val, 0)
  assert_true(press_at(t, now, 20.0, 5.0, 5.0))
  assert_eq(twice.val, 1)
  // (a screen reader's two in a row: neither a second)
  assert_true(t.activate_at(id.val.unwrap(), 30.0))
  assert_true(t.activate_at(id.val.unwrap(), 40.0))
  assert_eq(twice.val, 1)
}

///|
test "twice: what takes the finger itself asks of its own presses, forgetting one let go as another's" {
  let now = Ref(0.0)
  let said : Array[Bool] = []
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        node.val = Some(b)
        b
        .width(Is(Some(40.0)))
        .height(Is(Some(40.0)))
        .on_drag(fn(d) {
          if d.kind == Up {
            said.push(b.twice(d))
          }
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  t.frame(390.0, 844.0, now=0.0) |> ignore
  let tap = fn(at : Double) {
    now.val = at
    let id = node.val.unwrap().id()
    t.drag_at(id, Down, 5.0, 5.0, at) |> ignore
    t.drag_at(id, Up, 5.0, 5.0, at + 1.0) |> ignore
  }
  tap(0.0)
  tap(100.0)
  tap(200.0)
  node.val.unwrap().twice_forgot()
  tap(300.0)
  assert_eq(said, [false, true, false, false])
}
