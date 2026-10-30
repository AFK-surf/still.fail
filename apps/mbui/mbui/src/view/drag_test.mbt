// A finger held on a node (View::on_drag): the node's from down to up, wherever it moves meanwhile, each event handled
// at its own moment in the node's own terms, whatever frames are drawn between; one let go told nothing more.

///|
/// A tree with a box held (100 by 100 at the window's top left) while `there`, what its on_drag was told.
fn held_tree(seen : Array[@view.Drag], there : @signals.Signal[Bool]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v.box(fn(b) {
          b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d) }) |> ignore
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
}

///|
test "held: down, moved anywhere, up: the node's, each at its own moment, in its own terms" {
  let seen : Array[@view.Drag] = []
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = held_tree(seen, there)
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  t.drag_at(id, Moved, 300.0, 500.0, 120.0) |> ignore
  t.drag_at(id, Up, 310.0, 510.0, 130.0) |> ignore
  assert_eq(seen.map(fn(d) { (d.kind, d.x, d.y, d.at) }), [
    (Down, 10.0, 10.0, 100.0),
    (Moved, 300.0, 500.0, 120.0),
    (Up, 310.0, 510.0, 130.0),
  ])
}

///|
test "held, then let go of as the finger moves: told nothing more" {
  let seen : Array[@view.Drag] = []
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = held_tree(seen, there)
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  there.set(false)
  // (let go at once, no frame needed)
  assert_false(t.drag_at(id, Moved, 20.0, 20.0, 120.0))
  assert_eq(seen.length(), 1)
}

///|
test "held node let go, another made in its place with nothing held on it: not held there, nothing of the one before called" {
  let which = @signals.signal(0, same=fn(a, b) { a == b })
  let seen : Array[Int] = []
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { which.get() == 0 }, fn(v) {
        v.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(_) { seen.push(0) }) |> ignore })
        |> ignore
      })
      root.show(fn() { which.get() == 1 }, fn(v) {
        v.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore }) |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  which.set(1)
  t.frame(390.0, 844.0) |> ignore
  assert_true(t.target_at(10.0, 10.0) is Nothing)
  assert_eq(seen, [])
}

///|
test "held, then what holds it takes no press (or it leaves): the hold called off, told so once, nothing more" {
  let seen : Array[@view.DragIs] = []
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        p.presses(By(fn() { on.get() })) |> ignore
        p.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d.kind) }) |> ignore })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  on.set(false)
  let more = t.drag_at(id, Moved, 20.0, 20.0, 20.0)
  t.drag_at(id, Up, 20.0, 20.0, 30.0) |> ignore
  assert_eq((seen, more), ([Down, Off], false))
}

///|
test "held, its events told inside another event: at that one's moment; where it is drawn, as of then, no frame between" {
  let seen : Array[@view.Drag] = []
  let pad = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        p.pad(By(fn() { pad.get() })) |> ignore
        p.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d) }) |> ignore })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.event(50.0, fn() { t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore })
  pad.set(20.0)
  t.drag_at(id, Moved, 30.0, 30.0, 60.0) |> ignore
  assert_eq(seen.map(fn(d) { (d.kind, d.x, d.y, d.at) }), [(Down, 10.0, 10.0, 50.0), (Moved, 10.0, 10.0, 60.0)])
}

///|
/// A tree with a box (100 by 100 at the window's top left) whose finger comes to taps, holds (500 ms) and drags, each
/// said in `said`.
fn gesture_tree(said : Array[String]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b
        .width(Is(Some(100.0)))
        .height(Is(Some(100.0)))
        .gesture(
          6.0,
          tap=fn(_) { said.push("tap") },
          hold=(500.0, fn(d) { said.push("hold \{d.x},\{d.y} at \{d.at}") }),
          drag=fn(d) { said.push("drag \{d.kind} \{d.x},\{d.y} at \{d.at}") },
        )
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
}

///|
fn gesture_id(t : @view.Tree) -> @view.NodeId {
  match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
}

///|
test "a finger let go where it went down: a tap; moved within the slop, still a tap" {
  let said = []
  let t = gesture_tree(said)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  t.drag_at(id, Moved, 13.0, 12.0, 20.0) |> ignore
  t.drag_at(id, Up, 13.0, 12.0, 30.0) |> ignore
  assert_eq(said, ["tap"])
}

///|
test "a finger moved past the slop: a drag from where it went down, its moves, its end; no tap" {
  let said = []
  let t = gesture_tree(said)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  t.drag_at(id, Moved, 30.0, 10.0, 20.0) |> ignore
  t.drag_at(id, Up, 40.0, 10.0, 30.0) |> ignore
  assert_eq(said, ["drag Down 10,10 at 20", "drag Moved 30,10 at 20", "drag Up 40,10 at 30"])
}

///|
/// A finger down at 100, frames drawn whose logic comes to each of `frames` (and moved at `moved` if given): what it came
/// to before it is let go, and after it is, at 800.
fn held_for(frames : Array[Double], moved? : Double) -> (Array[String], Array[String]) {
  let said = []
  let t = gesture_tree(said)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  for f in frames {
    t.at(f)
    t.frame(390.0, 844.0, now=f) |> ignore
  }
  match moved {
    Some(m) => t.drag_at(id, Moved, 40.0, 10.0, m) |> ignore
    None => ()
  }
  let before = said.copy()
  t.drag_at(id, Up, 10.0, 10.0, 800.0) |> ignore
  (before, said)
}

///|
test "held still: a hold at its moment, by the frame whose logic comes to it, whatever frames came; let go after, its end and no tap" {
  let held = ["hold 10,10 at 600"]
  let ended = ["hold 10,10 at 600", "drag Up 10,10 at 800"]
  assert_eq(held_for([200.0, 300.0, 600.0, 700.0]), (held, ended))
  assert_eq(held_for([700.0]), (held, ended))
  // (no frame: come as the next event takes the logic past it)
  assert_eq(held_for([]), ([], ended))
  // (moved first: no hold)
  assert_eq(held_for([300.0], moved=400.0), (
    ["drag Down 10,10 at 400", "drag Moved 40,10 at 400"],
    ["drag Down 10,10 at 400", "drag Moved 40,10 at 400", "drag Up 10,10 at 800"],
  ))
}

///|
test "held still, a frame drawn ahead of the logic (its clock past the hold's moment, its logic short of it): no hold yet" {
  let said = []
  let t = gesture_tree(said)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 100.0) |> ignore
  t.at(700.0)
  t.frame(390.0, 844.0, now=500.0) |> ignore
  assert_eq(said, [])
}

///|
test "a finger still while what it is on moves: no drag; let go far from where it went down with no move said: a drag, no tap" {
  let said = []
  let pad = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        p.pad(By(fn() { pad.get() })) |> ignore
        p.box(fn(b) {
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .gesture(6.0, tap=fn(_) { said.push("tap") }, drag=fn(d) { said.push("drag \{d.kind}") })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  pad.set(30.0)
  t.drag_at(id, Moved, 10.0, 10.0, 20.0) |> ignore
  t.drag_at(id, Up, 10.0, 10.0, 30.0) |> ignore
  let still = said.copy()
  said.clear()
  pad.set(0.0)
  t.drag_at(id, Down, 10.0, 10.0, 40.0) |> ignore
  t.drag_at(id, Up, 300.0, 300.0, 50.0) |> ignore
  assert_eq((still, said), (["tap"], ["drag Down", "drag Up"]))
}

///|
/// A box held by a finger set down at 0, a hold of 100 ms waited for on it, what holds it taking no press from 20 on
/// (`how`: said to take none; leaving over 300 ms), no finger's event after, frames drawn at each of `frames`: what it
/// came to.
fn held_then_lost(how : String, frames : Array[Double]) -> Array[String] {
  let said = []
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      root.show(
        fn() { how != "leaving" || on.get() },
        fn(v) {
          v.box(fn(p) {
            p.presses(By(fn() { how != "pressless" || on.get() })) |> ignore
            p.box(fn(b) {
              b
              .width(Is(Some(100.0)))
              .height(Is(Some(100.0)))
              .gesture(
                6.0,
                hold=(100.0, fn(d) { said.push("hold at \{d.at}") }),
                drag=fn(d) { said.push("\{d.kind} at \{d.at}") },
              )
              |> ignore
            })
            |> ignore
          })
          |> ignore
        },
        leave=300.0,
      )
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.drag_at(id, Down, 10.0, 10.0, 0.0) |> ignore
  t.event(20.0, fn() { on.set(false) })
  for f in frames {
    t.at(f)
    t.frame(390.0, 844.0) |> ignore
  }
  t.at(400.0)
  t.frame(390.0, 844.0) |> ignore
  said
}

///|
test "held, what holds it said to take no press, or leaving, no finger's event after: called off at that moment, its hold never come" {
  let want = ["Off at 20"]
  assert_eq(held_then_lost("pressless", []), want)
  assert_eq(held_then_lost("pressless", [50.0, 100.0, 150.0]), want)
  assert_eq(held_then_lost("leaving", []), want)
  assert_eq(held_then_lost("leaving", [50.0, 100.0, 150.0]), want)
}

///|
test "held, told inside an event whose change moved it, before it ended: where it is as of that event" {
  let seen : Array[@view.Drag] = []
  let pad = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        p.pad(By(fn() { pad.get() })) |> ignore
        p.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(d) { seen.push(d) }) |> ignore })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = match t.target_at(10.0, 10.0) {
    Dragged(id) => id
    _ => abort("not held")
  }
  t.event(50.0, fn() {
    pad.set(20.0)
    t.drag_at(id, Down, 30.0, 30.0, 100.0) |> ignore
  })
  assert_eq(seen.map(fn(d) { (d.kind, d.x, d.y, d.at) }), [(Down, 10.0, 10.0, 50.0)])
}
