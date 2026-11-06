///|
/// Where a node moved by the clock alone is drawn as an event at `at` reads it, after a frame the host showed at 0 and
/// sampled for `drawn_for` (a predicted frame: Tree::at ahead of the frame's `now`).
fn drawn_in_event_after(drawn_for : Double, at : Double) -> Double? {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0))).offset(By(fn() { (v.drawn_at(), 0.0) })) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let read : Ref[Double?] = Ref(None)
  tree.event(at, fn() { read.val = page.val.unwrap().drawn_now().map(fn(d) { d.rect.0 }) })
  read.val
}

///|
test "drawn_now in an event reads where a node moved by the clock is at the event's moment, whichever frame was drawn before" {
  // (the host at 0 both times, its frame sampled ahead of the event, for 50 ms, or at 0: the event at 40 reads the same)
  let ahead = drawn_in_event_after(50.0, 40.0)
  let behind = drawn_in_event_after(0.0, 40.0)
  assert_eq(behind, Some(40.0))
  assert_eq(ahead, behind)
}

///|
/// What a reaction to whether the drawing is past 45 is told, a frame sampled for 50 with the host at 0, then an event
/// at 40 asking where a node is drawn now or not asking, and then the same asked in no event.
fn told_past_45(asks : Bool) -> Array[String] {
  let told : Array[String] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(40.0))).offset(By(fn() { (v.drawn_at(), 0.0) })) |> ignore
      v.reacts(fn() { v.drawn_past(45.0) }, fn(past) { told.push(past.to_string()) })
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.event(40.0, fn() { if asks { page.val.unwrap().drawn_now() |> ignore } })
  told.push("event done")
  if asks {
    page.val.unwrap().drawn_now() |> ignore
  }
  told
}

///|
test "drawn_now, in an event or in none, tells nothing to what reacts to the drawing's moment" {
  assert_eq(told_past_45(true), told_past_45(false))
}

///|
/// The width of a node as wide as whether the drawing is past 45 says, drawn as an event at 40 reads it after a frame
/// the host showed at 0 and sampled for `drawn_for`; then as the next frame, sampled for 50, draws it.
fn width_past_45(drawn_for : Double) -> (Double?, Double?) {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(if v.drawn_past(45.0) { 40.0 } else { 20.0 }) })).height(Is(Some(40.0))) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let read : Ref[Double?] = Ref(None)
  tree.event(40.0, fn() { read.val = page.val.unwrap().drawn_now().map(fn(d) { d.rect.2 }) })
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  (read.val, tree.drawn_of(page.val.unwrap().id()).map(fn(d) { d.w }))
}

///|
test "drawn_now reads what is drawn by the drawing's moment as of the event's moment, and the next frame draws its own" {
  assert_eq(width_past_45(0.0), (Some(20.0), Some(40.0)))
  assert_eq(width_past_45(50.0), width_past_45(0.0))
}

///|
/// How often what shows once the drawing is past 45 is made, and what an effect reading whether it is past 45 reads, a
/// frame sampled for 50 with the host at 0, then where it is drawn asked in an event at 40 and in none.
fn made_and_read_past_45() -> (Int, Array[Bool]) {
  let made = Ref(0)
  let read : Array[Bool] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.row(Is(true)).height(Is(Some(40.0))) |> ignore
      v.show(fn() { v.drawn_past(45.0) }, fn(c) {
        made.val += 1
        c.width(Is(Some(30.0))).height(Is(Some(40.0))) |> ignore
      })
      let stop = @signals.effect(fn() { read.push(v.drawn_past(45.0)) })
      v.owns(stop) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let before = (made.val, read.length())
  tree.event(40.0, fn() { page.val.unwrap().drawn_now() |> ignore })
  page.val.unwrap().drawn_now() |> ignore
  (made.val - before.0, read[before.1:].to_array())
}

///|
test "drawn_now makes and lets go of nothing by the drawing's moment, and tells an effect none of its look" {
  // (a structure stands as drawn; an effect told of a read that changed and came back may run again, and reads it as
  // drawn: never the look's moment)
  let (made, read) = made_and_read_past_45()
  assert_eq(made, 0)
  assert_true(read.iter().all(fn(past) { past }), msg="\{read}")
}

///|
/// How often what shows while a node drawn by whether the drawing is past 45 is laid out wider than 30 is made and let
/// go, a frame sampled for 50 with the host at 0, then where it is drawn asked in an event at 40 and in none, and the
/// next frame drawn for 50; and whether it shows then.
fn made_by_size_past_45() -> (Int, Int, Bool) {
  let made = Ref(0)
  let gone = Ref(0)
  let shows = Ref(false)
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(300.0))) |> ignore
      let a = o.box(fn(a) {
        a.width(By(fn() { Some(if a.drawn_past(45.0) { 40.0 } else { 20.0 }) })).height(Is(Some(10.0))) |> ignore
      })
      page.val = Some(a)
      o.show(fn() { a.owed_laid_size().map(fn(z) { z.0 }).unwrap_or(0.0) > 30.0 }, fn(b) {
        made.val += 1
        shows.val = true
        b.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore
        b.owns(fn() {
          gone.val += 1
          shows.val = false
        })
        |> ignore
      })
    })
    |> ignore
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let before = (made.val, gone.val)
  tree.event(40.0, fn() { page.val.unwrap().drawn_now() |> ignore })
  page.val.unwrap().drawn_now() |> ignore
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  (made.val - before.0, gone.val - before.1, shows.val)
}

///|
test "drawn_now lays out as drawn again: what a size told in its look makes or lets go of nothing" {
  assert_eq(made_by_size_past_45(), (0, 0, true))
}

///|
/// What waits on the next layout reads when done (the node's width, the moment of its cause) and how often it is done
/// before the next frame and after it, asked for in an event at 40 that then asks where the node is drawn now or not,
/// a frame sampled for `drawn_for` with the host at 0 before. The node `moves` by the drawing's moment or not.
fn waited(drawn_for : Double, asks : Bool, moves : Bool) -> (Array[(Double, Double)], Int) {
  let seen : Array[(Double, Double)] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      if moves {
        v.width(By(fn() { Some(if v.drawn_past(45.0) { 40.0 } else { 20.0 }) })) |> ignore
      } else {
        v.width(Is(Some(30.0))) |> ignore
      }
      v.height(Is(Some(10.0))) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let v = page.val.unwrap()
  tree.event(40.0, fn() {
    v.owed_once_laid_out(fn() { seen.push((v.rect().2, v.cause_at())) })
    if asks {
      v.drawn_now() |> ignore
    }
  })
  let before_frame = seen.length()
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  (seen, before_frame)
}

///|
test "drawn_now's look does none of what waits on a layout: done as it is without the look, at the same moment" {
  for moves in [true, false] {
    for drawn_for in [0.0, 50.0] {
      assert_eq(waited(drawn_for, true, moves), waited(drawn_for, false, moves), msg="moves \{moves}, drawn for \{drawn_for}")
    }
  }
}

///|
/// How often an effect with a cleanup that reads whether the drawing is past 45 runs and is cleaned up, beside a
/// property of the same node drawn by it, a frame sampled for 50 with the host at 0, then where the node is drawn asked
/// in an event at 40 or not asked.
fn effect_runs_past_45(asks : Bool) -> (Int, Int) {
  let runs = Ref(0)
  let cleaned = Ref(0)
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(if v.drawn_past(45.0) { 40.0 } else { 20.0 }) })).height(Is(Some(10.0))) |> ignore
      let stop = @signals.effect_cleanup(fn() {
        v.drawn_past(45.0) |> ignore
        runs.val += 1
        fn() { cleaned.val += 1 }
      })
      v.owns(stop) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let before = (runs.val, cleaned.val)
  tree.event(40.0, fn() { if asks { page.val.unwrap().drawn_now() |> ignore } })
  (runs.val - before.0, cleaned.val - before.1)
}

///|
test "drawn_now: an effect with a cleanup beside a property reading the same moment is run and cleaned up as it is without the look" {
  assert_eq(effect_runs_past_45(true), effect_runs_past_45(false))
}

///|
/// The width of a node as wide as where a cycle of 100 ms is as it is drawn, as an event at 40 reads it after a frame the
/// host showed at 0 and sampled for `drawn_for`.
fn width_by_cycle(drawn_for : Double) -> Double? {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(10.0 + 100.0 * v.cycle(100.0)) })).height(Is(Some(10.0))) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(drawn_for)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let read : Ref[Double?] = Ref(None)
  tree.event(40.0, fn() { read.val = page.val.unwrap().drawn_now().map(fn(d) { d.rect.2 }) })
  read.val
}

///|
test "drawn_now reads what is drawn by a cycle as of the event's moment, whichever frame was drawn before" {
  assert_eq(width_by_cycle(0.0), Some(50.0))
  assert_eq(width_by_cycle(50.0), width_by_cycle(0.0))
}

///|
/// Whether a still tree (one node, its size followed, nothing by the time) has something to draw after an event at 40
/// asking where it is drawn now or not, a frame sampled for 50 with the host at 0 before; and the layout's work and the
/// nodes laid out by the next frame.
fn still_after(asks : Bool) -> (Bool, Int, Int) {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(30.0))).height(Is(Some(10.0))) |> ignore
      v.reacts(fn() { v.owed_laid_size() }, fn(_) {  })
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.event(40.0, fn() { if asks { page.val.unwrap().drawn_now() |> ignore } })
  let told = tree.told_since()
  let before = tree.work()
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  let after = tree.work()
  (told, after.computes - before.computes, after.laid - before.laid)
}

///|
test "drawn_now on a still tree leaves it as it is without the look: nothing to draw, no layout more" {
  assert_eq(still_after(true), still_after(false))
}

///|
/// A node whose width (and colour) the event at 40 sets, asking where it is drawn now after or not, a frame sampled for
/// 50 with the host at 0 before: what its size's follower is told by the next frame, whether there is something to draw
/// after the event, the width and colour the next frame draws.
fn set_then_looked(asks : Bool) -> (Array[Double], Bool, Double?, Int64?) {
  let width = @signals.signal(20.0, same=fn(a, b) { a == b })
  let ground = @signals.signal(0x000000FFL, same=fn(a, b) { a == b })
  let told : Array[Double] = []
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(width.get()) })).height(Is(Some(10.0))).ground(By(fn() { ground.get() })) |> ignore
      v.reacts(fn() { v.owed_laid_size() }, fn(z) {
        match z {
          Some((w, _)) => told.push(w)
          None => ()
        }
      })
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let v = page.val.unwrap()
  told.clear()
  tree.event(40.0, fn() {
    width.set(70.0)
    ground.set(0xFF0000FFL)
    if asks {
      v.drawn_now() |> ignore
    }
  })
  let to_draw = tree.told_since()
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  let drawn = tree.drawn_of(v.id())
  (told, to_draw, drawn.map(fn(d) { d.w }), drawn.map(fn(d) { d.ground }))
}

///|
test "drawn_now after a change in the same event: told, laid out and drawn as without the look" {
  assert_eq(set_then_looked(true), set_then_looked(false))
}

///|
/// The bindings a look at 40 works out (anew, and again as drawn) over 100 nodes drawn by whether the drawing is past
/// `mark`, a frame sampled for 50 with the host at 0 before.
fn bound_in_look(mark : Double) -> Int {
  let first : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    for i in 0..<100 {
      let n = root.box(fn(v) {
        v.width(By(fn() { Some(if v.drawn_past(mark) { 40.0 } else { 20.0 }) })).height(Is(Some(1.0))) |> ignore
      })
      if i == 0 {
        first.val = Some(n)
      }
    }
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  let before = tree.work().bound
  tree.event(40.0, fn() { first.val.unwrap().drawn_now() |> ignore })
  tree.work().bound - before
}

///|
test "drawn_now works out again only what the look's moment is on the other side of a mark for" {
  // (past 1000 at neither 40 nor 50: nothing; past 45 at 50 alone: each, anew and as drawn again)
  let crossed = bound_in_look(45.0)
  println("bindings worked out by a look over 100 nodes: mark not crossed \{bound_in_look(1000.0)}, crossed \{crossed}")
  assert_eq(bound_in_look(1000.0), 0)
  assert_true(crossed >= 100)
}

///|
/// What the host is to take after an event at 40 asking where a node drawn by whether the drawing is past 45 is drawn
/// now or not (made again, placed otherwise), taken empty before it, a frame sampled for 50 with the host at 0 before.
fn host_takes(asks : Bool) -> (Int, Int) {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(By(fn() { Some(if v.drawn_past(45.0) { 40.0 } else { 20.0 }) })).height(Is(Some(40.0))) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.take_changed() |> ignore
  tree.take_placed() |> ignore
  tree.event(40.0, fn() { if asks { page.val.unwrap().drawn_now() |> ignore } })
  (tree.take_changed().length(), tree.take_placed().length())
}

///|
test "drawn_now leaves the host nothing more to take than without the look" {
  assert_eq(host_takes(true), host_takes(false))
}

///|
/// A still node of a fixed size and a ground, its ground said at once anew in an event at 40 that then asks where it is
/// drawn now or not, a frame sampled for 50 with the host at 0 before, the host's changes taken before it: whether the
/// host is to take it made again after the event, and the ground the next frame draws.
fn ground_said_then_looked(asks : Bool) -> (Bool, Int64?) {
  let page : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(fn(root) {
    page.val = Some(root.box(fn(v) {
      v.width(Is(Some(30.0))).height(Is(Some(10.0))).ground(Is(0x112233FFL)) |> ignore
    }))
  }, time=fn() { 0.0 })
  defer { tree.dispose() }
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.at(50.0)
  tree.frame(400.0, 300.0, now=0.0) |> ignore
  tree.take_changed() |> ignore
  tree.take_placed() |> ignore
  let v = page.val.unwrap()
  tree.event(40.0, fn() {
    v.ground(Is(0x445566FFL)) |> ignore
    if asks {
      v.drawn_now() |> ignore
    }
  })
  tree.frame(400.0, 300.0, now=40.0) |> ignore
  (tree.take_changed().contains(v.id()), tree.drawn_of(v.id()).map(fn(d) { d.ground }))
}

///|
test "drawn_now after a look said at once in the same event: made again for the host and drawn as without the look" {
  assert_eq(ground_said_then_looked(true), ground_said_then_looked(false))
}
