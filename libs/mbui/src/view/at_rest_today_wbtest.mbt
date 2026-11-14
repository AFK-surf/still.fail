// What "at rest" is today (2026-11-12, an audit for keeping a place of the bottom bar instead of letting it go): a node
// put by (View::park, then View::take_in elsewhere, as a page's list moves a block put by into another slot) and a node
// rested where it is (View::rests, as a page's list leaves a block put by in its slot), each holding what a page holds:
// a reaction (View::reacts), a moment asked (View::at_moment), a way going read by the clock (View::drawn_while), a
// mark of a moment (View::drawn_past), what it lets go (View::owns), a binding reading what is held while it is read (a
// core's topic: Signal::on_unwatched), the hold, the focus, what takes back, what the pointer is over and a modal layer.
// Each is said as it is at each step, the steps the same for both: what holds today, pinned. (What the pointer is over
// is said too, but the bare tree here never comes to say the key is pointed at, put by or not: that one is not pinned
// by this file; View::park says it lets it go: Tree::pointed_within_at, pointed_to(None).)

///|
/// One case, `how` "park" or "rests": what was said at each step, in order.
fn at_rest_case(how : String, modal : Bool) -> Array[String] {
  let out : Array[String] = []
  let src = @signals.signal(0, same=fn(a, b) { a == b })
  // (held while it is read, as a core's topic is: let go of as its last reader goes)
  let held = @signals.signal(0, same=fn(a, b) { a == b })
  let unheld = Ref(0)
  held.on_unwatched(fn() { unheld.val += 1 })
  let holder : Ref[View?] = Ref(None)
  let other : Ref[View?] = Ref(None)
  let page : Ref[View?] = Ref(None)
  let key : Ref[View?] = Ref(None)
  let moving : Ref[View?] = Ref(None)
  let layer : Ref[View?] = Ref(None)
  let back : Ref[View?] = Ref(None)
  let t = Tree::new(fn(root) {
    root.box(fn(h) {
      holder.val = Some(h)
      h.width(Is(Some(390.0))).height(Is(Some(400.0))) |> ignore
      h.box(fn(p) {
        page.val = Some(p)
        p.width(Is(Some(390.0))).height(Is(Some(400.0))) |> ignore
        p.reacts(fn() { src.get() }, fn(v) { out.push("reacts \{v} at \{p.cause_at()}") })
        p.at_moment(100.0, fn() { out.push("moment 100 done at \{p.cause_at()}") }) |> ignore
        p.owns(fn() { out.push("owns run") }) |> ignore
        // (a binding reading what is held while it is read, and a mark of the moment 120)
        p.box(fn(w) {
          w.height(Is(Some(20.0))).words(By(fn() { "held \{held.get()} past120 \{w.drawn_past(120.0)}" })) |> ignore
        })
        |> ignore
        // (a way from 0 to 90 over 0..300, read as it is drawn)
        p.box(fn(m) {
          moving.val = Some(m)
          m
          .width(Is(Some(30.0)))
          .height(Is(Some(30.0)))
          .offset(By(fn() {
            let d = m.drawn_while(fn(at) { at < 300.0 })
            if d == @double.infinity {
              (90.0, 0.0)
            } else {
              (d * 0.3, 0.0)
            }
          }))
          |> ignore
        })
        |> ignore
        p.box(fn(k) {
          key.val = Some(k)
          k
          .width(Is(Some(100.0)))
          .height(Is(Some(40.0)))
          .on_press(fn() { out.push("pressed") })
          .focusable(Is(true))
          .says(Is(Some(said(Button, label="key"))))
          .ground(By(fn() { if k.pointed() { 1L } else { 0L } }))
          |> ignore
        })
        |> ignore
        p.box(fn(b) {
          back.val = Some(b)
          b.width(Is(Some(10.0))).height(Is(Some(10.0))).takes_back(fn() { out.push("back") }) |> ignore
        })
        |> ignore
        p.box(fn(l) {
          layer.val = Some(l)
          l.width(Is(Some(50.0))).height(Is(Some(50.0))).modal(Is(modal)) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    root.box(fn(o) {
      other.val = Some(o)
      o.width(Is(Some(390.0))).height(Is(Some(400.0))) |> ignore
    })
    |> ignore
  })
  let frame = fn(at : Double) {
    t.at(at)
    t.frame(390.0, 844.0, now=at) |> ignore
  }
  let p = page.val.unwrap()
  let h = holder.val.unwrap()
  let o = other.val.unwrap()
  let k = key.val.unwrap()
  let m = moving.val.unwrap()
  let l = layer.val.unwrap()
  let b = back.val.unwrap()
  let mine = fn(id : NodeId) { t.holds(p.id(), id) }
  let state = fn(step : String) {
    let drawn = t.drawn().iter().any(fn(d) { mine(d.id) })
    let focused = match t.focused_now().0 {
      Some(f) => mine(f)
      None => false
    }
    let held_in = match t.held {
      Some(x) => mine(x)
      None => false
    }
    let pointed = match t.pointed_now() {
      Some(x) => mine(x)
      None => false
    }
    let backs = match t.back_taker() {
      Some(x) => mine(x)
      None => false
    }
    let modal = match t.modal_top() {
      Some(x) => mine(x)
      None => false
    }
    let said_out = t.said_order().iter().any(fn(s) { mine(s.id) })
    let (mx, _, _, _) = m.rect()
    out.push(
      "\{step}: drawn \{drawn} focused \{focused} held \{held_in} pointed \{pointed} backs \{backs} modal \{modal} read_out \{said_out} watched \{held.watched()} unheld \{unheld.val} way_x \{mx} parent \{t.nodes[p.at].parent}",
    )
  }
  frame(0.0)
  // (the focus in its key, a finger held on the key, the pointer over it)
  ignore(t.focus_to(Some(k.id())))
  t.held_to(Some(k.id()))
  let (kx, ky, kw, kh) = k.rect()
  t.pointer_is(kx + kw / 2.0, ky + kh / 2.0)
  frame(10.0)
  ignore(l)
  ignore(b)
  state("before (10)")
  // put by at 50
  let wake : Ref[() -> Unit] = Ref(fn() {  })
  t.event(50.0, fn() { wake.val = if how == "park" { h.park(p) } else { p.rests() } })
  frame(50.0)
  state("put by (50)")
  // what it reacts to changed while it rests (60), its moment due (100), its mark due (120)
  t.event(60.0, fn() { src.set(1) })
  t.event(70.0, fn() { held.set(5) })
  frame(60.0)
  frame(110.0)
  frame(130.0)
  state("resting (130)")
  // taken again at 200 (put by: into the other node), woken
  t.event(200.0, fn() {
    if how == "park" {
      o.take_in(p)
    }
    (wake.val)()
  })
  frame(200.0)
  state("taken again (200)")
  frame(400.0)
  state("after the way's end (400)")
  // let go at 500
  t.event(500.0, fn() { if how == "park" { o.drop(p) } else { h.drop(p) } })
  frame(500.0)
  out.push("let go (500): unheld \{unheld.val} watched \{held.watched()}")
  out
}

///|
/// What the steps all four cases share once put by (50) and while resting (130), by how it was put by: a node put by is
/// none of the tree's (not drawn, no focus, no hold, no back, no modal layer, not read out) and what it held while read
/// is let go of; one rested where it is stays all of that but what it held while read, drawn as it was at 50 (its way
/// where it was then).
fn at_rest_expected(how : String, modal : Bool) -> Array[String] {
  let keyed = !modal
  let before = "drawn true focused \{keyed} held true pointed false backs \{keyed} modal \{modal} read_out true"
  let parked = how == "park"
  let resting = if parked {
    "drawn false focused false held false pointed false backs false modal false read_out false watched false unheld 1 way_x 0 parent -1"
  } else {
    "\{before} watched false unheld 1 way_x 3 parent 1"
  }
  // (taken again: a node put by has given its focus and hold up for good, its back and modal layer back with it; one
  // rested in place never lost them)
  let again = if parked {
    "drawn true focused false held false pointed false backs \{keyed} modal \{modal} read_out true"
  } else {
    before
  }
  let parent = if parked { "8" } else { "1" }
  [
    "reacts 0 at 0",
    "before (10): \{before} watched true unheld 0 way_x 3 parent 1",
    "put by (50): \{resting}",
    // (its moment done at its own moment while it rests, put by or not)
    "moment 100 done at 100",
    "resting (130): \{resting}",
    // (what it reacts to, changed at 60 while it rested: done as it is woken, once, as of the waking's moment)
    "reacts 1 at 200",
    // (its way followed the clock all along: where it is at 200, not where it was put by)
    "taken again (200): \{again} watched true unheld 1 way_x 60 parent \{parent}",
    "after the way's end (400): \{again} watched true unheld 1 way_x 90 parent \{parent}",
    // (what it lets go, only as it is let go)
    "owns run",
    "let go (500): unheld 2 watched false",
  ]
}

///|
test "at rest today: a node put by (park, take_in) and one rested in place (rests), with and without a modal layer in it" {
  for how in ["park", "rests"] {
    for modal in [false, true] {
      let lines = at_rest_case(how, modal)
      for line in lines {
        println("at-rest \{how} modal=\{modal}: \{line}")
      }
      assert_eq(lines, at_rest_expected(how, modal), msg="\{how} modal=\{modal}")
    }
  }
}
