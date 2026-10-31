// A node drawn bigger or smaller than it is laid out (View::scale): what it holds with it, about the point said of it
// (its middle; the edge toward what it goes beside, on the side it went on); laid out, pressed and placed as before.

///|
test "scale: a node drawn half as big about its middle, what it holds with it; about its edge toward its anchor, the side it went on" {
  let s = @signals.signal(0.5, same=fn(a, b) { a == b })
  let ay = @signals.signal(100.0, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        ids["n"] = n.id()
        n.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(40.0))).offset(Is((10.0, 10.0))).scale(By(fn() { s.get() })) |> ignore
        n.box(fn(k) {
          ids["k"] = k.id()
          k.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0))).offset(Is((20.0, 0.0))) |> ignore
        })
        |> ignore
      })
      |> ignore
      root.box(fn(a) {
        ids["a"] = a.id()
        a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0))).offset(By(fn() { (100.0, ay.get()) })) |> ignore
      })
      |> ignore
      root.box(fn(b) {
        ids["b"] = b.id()
        b
        .width(Is(Some(60.0)))
        .height(Is(Some(30.0)))
        .beside(ids["a"], side=Bottom, along=Middle, offset=6.0)
        .scale(Is(0.5), about=FromBeside)
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let at = fn(k : String) {
    let d = t.drawn_of(ids[k]).unwrap()
    (d.x, d.y, d.w, d.h)
  }
  assert_eq(at("n"), (35.0, 20.0, 50.0, 20.0), msg="half as big about its middle")
  assert_eq(at("k"), (45.0, 20.0, 5.0, 5.0), msg="what it holds with it")
  let drawn = t.drawn().filter(fn(d) { d.id == ids["k"] })
  assert_eq(drawn.map(fn(d) { (d.x, d.y, d.w, d.h) }), [at("k")], msg="as the scene is gone through")
  // (below its anchor: about its top's middle, toward it)
  assert_eq(at("b"), (105.0, 126.0, 30.0, 15.0), msg="about its edge toward its anchor, below")
  // (no room below: above it, about its foot's middle)
  t.event(10.0, fn() { ay.set(260.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at("b"), (105.0, 239.0, 30.0, 15.0), msg="about its edge toward its anchor, above")
  // (whole again: as laid out)
  t.event(20.0, fn() { s.set(1.0) })
  t.frame(400.0, 300.0) |> ignore
  assert_eq(at("n"), (10.0, 10.0, 100.0, 40.0), msg="whole: as laid out")
}

///|
/// A node drawn `s` as big holding an old view (View::hosted) where `hosted` holds, each as it changes: drawn once.
fn scaled_hosting(s : @signals.Signal[Double], hosted : @signals.Signal[Bool]) -> @view.Tree {
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        n.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(40.0))).scale(By(fn() { s.get() })) |> ignore
        n.show(fn() { hosted.get() }, fn(h) { h.hosted() |> ignore })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  t
}

///|
test "scale holding an old view, both whole: drawn as ever" {
  let t = scaled_hosting(@signals.signal(1.0), @signals.signal(true))
  assert_true(t.drawn().length() > 0)
}

///|
/// What is refused while `f` runs (@view.refused_so told instead of stopping): each, in turn.
fn refusals(f : () -> Unit) -> Array[String] {
  let was = @view.refused_so.val
  let out = []
  @view.refused_so.val = fn(why) { out.push(why) }
  f()
  @view.refused_so.val = was
  out
}

///|
test "scale holding an old view: refused as the old view is put in it (shown after), and as what holds one is said to be scaled after: refused as that change is taken" {
  let hosted = @signals.signal(false, same=fn(a, b) { a == b })
  let mut t : @view.Tree? = None
  let made = refusals(fn() { t = Some(scaled_hosting(@signals.signal(0.5), hosted)) })
  assert_eq(made, [], msg="scaled, holding none: as ever")
  let shown = refusals(fn() {
    t.unwrap().event(10.0, fn() { hosted.set(true) })
    t.unwrap().frame(400.0, 300.0) |> ignore
  })
  assert_true(shown.length() > 0, msg="an old view put in it after: refused at that change")
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let mut t2 : @view.Tree? = None
  let whole = refusals(fn() { t2 = Some(scaled_hosting(s, @signals.signal(true))) })
  assert_eq(whole, [], msg="holding one, whole: as ever")
  let scaled = refusals(fn() {
    t2.unwrap().event(10.0, fn() { s.set(0.5) })
    t2.unwrap().frame(400.0, 300.0) |> ignore
  })
  assert_true(scaled.length() > 0, msg="what holds one scaled after: refused at that change")
}

///|
/// A node 100 by 40 at the window's top left taking presses while `p` says, drawn `s` as big about its top left, its
/// scale said before its presses (`scale_first`) or after: as both change, how big it is drawn and whether a press at
/// (5, 5) finds it, in turn.
fn scale_and_presses(scale_first : Bool) -> Array[(Double, Bool)] {
  let s = @signals.signal(1.0, same=fn(a, b) { a == b })
  let p = @signals.signal(true, same=fn(a, b) { a == b })
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(n) {
        id.val = Some(n.id())
        n.over(Is(true)).width(Is(Some(100.0))).height(Is(Some(40.0))).on_press(fn() {  }) |> ignore
        if scale_first {
          n.scale(By(fn() { s.get() }), about=At(0.0, 0.0)).presses(By(fn() { p.get() })) |> ignore
        } else {
          n.presses(By(fn() { p.get() })).scale(By(fn() { s.get() }), about=At(0.0, 0.0)) |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let out = []
  let look = fn() {
    t.frame(400.0, 300.0) |> ignore
    out.push((t.drawn_of(id.val.unwrap()).unwrap().w, t.target_at(5.0, 5.0) is Pressed(_)))
  }
  look()
  t.event(10.0, fn() { s.set(0.5) })
  look()
  t.event(20.0, fn() { p.set(false) })
  look()
  t.event(30.0, fn() { s.set(0.25) })
  look()
  t.event(40.0, fn() { p.set(true) })
  look()
  out
}

///|
test "scale and presses on one node, either said first: each followed as it changes, neither letting go of the other's" {
  let want = [(100.0, true), (50.0, true), (50.0, false), (25.0, false), (25.0, true)]
  let first = scale_and_presses(true)
  assert_eq(first, want, msg="scale said first: \{first}")
  let after = scale_and_presses(false)
  assert_eq(after, want, msg="presses said first: \{after}")
}
