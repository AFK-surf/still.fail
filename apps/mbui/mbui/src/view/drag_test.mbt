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
test "a finger moved past the slop: a drag begun where it is then, its moves, its end; no tap" {
  let said = []
  let t = gesture_tree(said)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  t.drag_at(id, Moved, 30.0, 10.0, 20.0) |> ignore
  t.drag_at(id, Up, 40.0, 10.0, 30.0) |> ignore
  assert_eq(said, ["drag Down 30,10 at 20", "drag Up 40,10 at 30"])
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
    ["drag Down 40,10 at 400"],
    ["drag Down 40,10 at 400", "drag Up 10,10 at 800"],
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
  assert_eq((still, said), (["tap"], ["drag Up"]))
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

///|
test "takes presses said anew: what was said before followed no more (said fixed, then by another value, either way)" {
  let a = @signals.signal(true, same=fn(x, y) { x == y })
  let b = @signals.signal(true, same=fn(x, y) { x == y })
  let said : Array[String] = []
  let held : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      held.val = Some(
        root.box(fn(h) {
          h
          .width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .presses(By(fn() { a.get() }))
          .on_drag(fn(d) { said.push("\{d.kind}") })
          |> ignore
        }),
      )
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let v = held.val.unwrap()
  let id = gesture_id(t)
  v.presses(Is(true)) |> ignore
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  // (what it was said by before: no longer followed)
  t.event(20.0, fn() { a.set(false) })
  let after_fixed = (said.copy(), t.target_at(10.0, 10.0) is Dragged(_))
  v.presses(By(fn() { b.get() })) |> ignore
  t.event(30.0, fn() { a.set(true) })
  t.event(40.0, fn() { a.set(false) })
  t.drag_at(id, Moved, 50.0, 50.0, 50.0) |> ignore
  // (and by the new one: followed)
  t.event(60.0, fn() { b.set(false) })
  assert_eq((after_fixed, said), ((["Down"], true), ["Down", "Moved", "Off"]))
}

///|
/// Inside one event at 50: `s` set 1, something said for 50 that reads it, a held finger told (where things are found:
/// `ask` it or not), `s` set 2: what that something read.
fn read_in_event(ask : Bool) -> Array[Int] {
  let s = @signals.signal(0, same=fn(x, y) { x == y })
  let read : Array[Int] = []
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      node.val = Some(
        root.box(fn(h) { h.width(Is(Some(100.0))).height(Is(Some(100.0))).on_drag(fn(_) {  }) |> ignore }),
      )
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.event(50.0, fn() {
    s.set(1)
    node.val.unwrap().at_moment(50.0, fn() { read.push(@signals.untracked(fn() { s.get() })) }) |> ignore
    if ask {
      t.drag_at(id, Down, 10.0, 10.0, 50.0) |> ignore
    }
    s.set(2)
  })
  t.frame(390.0, 844.0, now=60.0) |> ignore
  read
}

///|
test "where things are found in an event's change runs nothing of the logic: what is due then, done as it would be with nothing asked" {
  assert_eq(read_in_event(true), read_in_event(false))
}

///|
test "a gesture ended mid-call (its node let go by what it told, its on_drag said anew while held): nothing more told, its hold never come" {
  let there = @signals.signal(true, same=fn(x, y) { x == y })
  let said : Array[String] = []
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        node.val = Some(
          v.box(fn(b) {
            b
            .width(Is(Some(100.0)))
            .height(Is(Some(100.0)))
            .gesture(6.0, hold=(100.0, fn(_) { said.push("hold") }), drag=fn(d) {
              said.push("\{d.kind}")
              // (the drag's first word lets its node go)
              if d.kind == Down {
                there.set(false)
              }
            })
            |> ignore
          }),
        )
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  t.drag_at(id, Moved, 40.0, 10.0, 20.0) |> ignore
  let gone = said.copy()
  // (another: held, its on_drag said anew; its hold's moment comes)
  said.clear()
  there.set(true)
  t.frame(390.0, 844.0, now=30.0) |> ignore
  let id2 = gesture_id(t)
  t.drag_at(id2, Down, 10.0, 10.0, 40.0) |> ignore
  node.val.unwrap().on_drag(fn(_) { said.push("new") }) |> ignore
  t.frame(390.0, 844.0, now=300.0) |> ignore
  assert_eq((gone, said), (["Down"], []))
}

///|
/// A box whose finger's drag words are said in `said` (with where the finger went down), the first word of each
/// gesture saying it takes no press (`how`: "presses") or letting it go ("gone").
fn far_up(how : String) -> Array[String] {
  let there = @signals.signal(true, same=fn(x, y) { x == y })
  let takes = @signals.signal(true, same=fn(x, y) { x == y })
  let said : Array[String] = []
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { there.get() }, fn(v) {
        v.box(fn(b) {
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .presses(By(fn() { takes.get() }))
          .gesture(6.0, tap=fn(_) { said.push("tap") }, drag=fn(d) {
            said.push("\{d.kind} \{d.x},\{d.y} from \{d.ox},\{d.oy} at \{d.at}")
            if how == "presses" {
              takes.set(false)
            } else {
              there.set(false)
            }
          })
          |> ignore
        })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0) |> ignore
  t.drag_at(id, Up, 40.0, 10.0, 30.0) |> ignore
  said
}

///|
test "let go past the slop with no move told: one word, its end, where it went down said with it; what that word does ends it there" {
  let end = ["Up 40,10 from 10,10 at 30"]
  assert_eq((far_up("presses"), far_up("gone")), (end, end))
}

///|
test "a drag's words each say where the finger went down" {
  let said = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b
        .width(Is(Some(100.0)))
        .height(Is(Some(100.0)))
        .gesture(6.0, drag=fn(d) { said.push("\{d.kind} \{d.x} from \{d.ox},\{d.oy}") })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 20.0, 10.0) |> ignore
  t.drag_at(id, Moved, 30.0, 20.0, 20.0) |> ignore
  t.drag_at(id, Moved, 50.0, 20.0, 30.0) |> ignore
  t.drag_at(id, Up, 60.0, 20.0, 40.0) |> ignore
  assert_eq(said, ["Down 30 from 10,20", "Moved 50 from 10,20", "Up 60 from 10,20"])
}

///|
test "a node that stays: its gestures pressed and let go again and again, its timed work come or called off: what it owns back to what it was" {
  let node : Ref[@view.View?] = Ref(None)
  let said : Array[String] = []
  let t = @view.Tree::new(
    fn(root) {
      node.val = Some(
        root.box(fn(b) {
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .gesture(6.0, tap=fn(_) { said.push("tap") }, hold=(100.0, fn(_) { said.push("hold") }), drag=fn(_) {  })
          |> ignore
        }),
      )
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let v = node.val.unwrap()
  let base = v.owned_count()
  let id = gesture_id(t)
  let mut at = 10.0
  for _ in 0..<5 {
    // (let go before its hold: the hold's moment called off)
    t.drag_at(id, Down, 10.0, 10.0, at) |> ignore
    t.drag_at(id, Up, 10.0, 10.0, at + 10.0) |> ignore
    // (held past it: come)
    t.drag_at(id, Down, 10.0, 10.0, at + 20.0) |> ignore
    t.frame(390.0, 844.0, now=at + 200.0) |> ignore
    t.drag_at(id, Up, 10.0, 10.0, at + 210.0) |> ignore
    // (a moment come, one called off, steps run out and steps stopped)
    v.at_moment(at + 220.0, fn() { said.push("come") }) |> ignore
    let off = v.at_moment(at + 230.0, fn() { said.push("never") })
    off()
    off()
    v.steps(100, 2, fn(_, _) {  }) |> ignore
    let stop = v.steps(100, 5, fn(_, _) {  })
    t.frame(390.0, 844.0, now=at + 250.0) |> ignore
    stop()
    stop()
    at = at + 300.0
  }
  assert_eq((v.owned_count(), said.length(), said.contains("never")), (base, 15, false))
}

///|
/// A box taking `fingers` fingers at once, what its on_drag was told (which, which finger).
fn fingers_tree(fingers : Int, seen : Array[String]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b
        .width(Is(Some(100.0)))
        .height(Is(Some(100.0)))
        .on_drag(fn(d) { seen.push("\{d.kind} \{d.finger}") }, fingers~)
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
}

///|
test "held by as many fingers as it takes, each told by its own; one more: each of those down called off, the rest of it nobody's" {
  let seen = []
  let t = fingers_tree(2, seen)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  let took = [
    t.drag_at(id, Down, 10.0, 10.0, 10.0, finger=0),
    t.drag_at(id, Down, 50.0, 50.0, 20.0, finger=1),
    t.drag_at(id, Moved, 60.0, 60.0, 30.0, finger=1),
    // (a finger it was not told of: nothing)
    t.drag_at(id, Moved, 60.0, 60.0, 35.0, finger=7),
    t.drag_at(id, Up, 10.0, 10.0, 40.0, finger=0),
    t.drag_at(id, Moved, 70.0, 70.0, 50.0, finger=1),
    t.drag_at(id, Down, 20.0, 20.0, 60.0, finger=2),
    t.drag_at(id, Down, 30.0, 30.0, 70.0, finger=3),
    t.drag_at(id, Moved, 30.0, 30.0, 80.0, finger=3),
  ]
  assert_eq(seen, ["Down 0", "Down 1", "Moved 1", "Up 0", "Moved 1", "Down 2", "Off 1", "Off 2"])
  assert_eq(took, [true, true, true, true, true, true, true, false, false])
  // (taking one: a second calls it off)
  let one = []
  let t1 = fingers_tree(1, one)
  t1.frame(390.0, 844.0) |> ignore
  let id1 = gesture_id(t1)
  t1.drag_at(id1, Down, 10.0, 10.0, 10.0, finger=0) |> ignore
  let second = t1.drag_at(id1, Down, 50.0, 50.0, 20.0, finger=1)
  t1.drag_at(id1, Up, 10.0, 10.0, 30.0, finger=0) |> ignore
  assert_eq((one, second), (["Down 0", "Off 0"], false))
}

///|
/// Two fingers held on a box taking two, then called off, the first Off told doing `what` ("dispose": the tree let
/// go of; "anew": another on_drag said): what each on_drag was told after the fingers went down.
fn off_mid(what : String) -> (Array[String], Array[String]) {
  let first : Array[String] = []
  let after : Array[String] = []
  let node : Ref[@view.View?] = Ref(None)
  let tree : Ref[@view.Tree?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      node.val = Some(
        root.box(fn(b) {
          b
          .width(Is(Some(100.0)))
          .height(Is(Some(100.0)))
          .on_drag(
            fn(d) {
              first.push("\{d.kind} \{d.finger}")
              if d.kind == Off {
                if what == "dispose" {
                  tree.val.unwrap().dispose()
                } else {
                  node.val.unwrap().on_drag(fn(d) { after.push("\{d.kind} \{d.finger}") }) |> ignore
                }
              }
            },
            fingers=2,
          )
          |> ignore
        }),
      )
    },
    time=fn() { 0.0 },
  )
  tree.val = Some(t)
  t.frame(390.0, 844.0) |> ignore
  let id = gesture_id(t)
  t.drag_at(id, Down, 10.0, 10.0, 10.0, finger=0) |> ignore
  t.drag_at(id, Down, 50.0, 50.0, 20.0, finger=1) |> ignore
  t.drag_at(id, Off, 10.0, 10.0, 30.0) |> ignore
  (first, after)
}

///|
test "called off with two fingers down, what the first Off told lets the node go or says another on_drag: nothing more told to what it let go of, nothing to the new one" {
  assert_eq(off_mid("dispose"), (["Down 0", "Down 1", "Off 0"], []))
  assert_eq(off_mid("anew"), (["Down 0", "Down 1", "Off 0"], []))
}

///|
test "timed work called off again and again with no frame, the clock never moved: nothing of it left on the timeline, nothing kept by its node" {
  let node : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(fn(root) { node.val = Some(root.box(fn(_) {  })) }, time=fn() { 0.0 })
  t.frame(390.0, 844.0) |> ignore
  let v = node.val.unwrap()
  let (due, owned) = (t.due_count(), v.owned_count())
  for i in 0..<50 {
    let off = v.at_moment(1000.0 + i.to_double(), fn() {  })
    off()
    let stop = v.steps(60, 10, fn(_, _) {  })
    stop()
  }
  assert_eq((t.due_count(), v.owned_count()), (due, owned))
}
