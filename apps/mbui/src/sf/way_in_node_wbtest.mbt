// The way in as nodes (way_in_node) drawn as the old view's (way_in) is: on a tall page and on one too short for the
// room above its picture, to touch and to keyboard and mouse, with what is said under its button or none; at work and
// back, its spinner's room opening and closing as the old one's does.

///|
/// What a page draws: its rects (where, how big, their colour), its glyphs' places and its shapes (the picture's).
fn way_in_drawn(
  t : @ui.Tester,
) -> (
  Array[(Double, Double, Double, Double, Int64)],
  Array[(Double, Double)],
  Array[(Double, Double, Double, Double, Double, Int64)],
) {
  (t.drawn_rects(), t.drawn_glyphs().map(fn(g) { (g.0, g.1) }), t.drawn_shapes())
}

///|
/// The way in, `w` by `h`, started with `native` (touch or keyboard and mouse), its button at work as `busy` says and
/// `said` under it: an old view's (way_in) or the tree's (way_in_node). The Tester.
fn way_in_case(
  node : Bool,
  native : @ui.Pointing,
  w : Double,
  h : Double,
  busy : @signals.Signal[Bool],
  said : @signals.Signal[(String, Bool)],
  note? : String = "Agents for your team, wherever you are.",
) -> @ui.Tester {
  let (art, title, label, foot) = ("illus_sign_in", "Sign in", "Continue with Google", "Several accounts can be signed in")
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        way_in(c, art, title, note, label, foot, busy=busy.get(), said=said.get().0, bad=said.get().1) |> ignore
      }
    },
    w~,
    h~,
    native~,
    pointing=native,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      way_in_node(
        root,
        fn() { art },
        fn() { title },
        fn() { note },
        fn() { label },
        fn() { foot },
        fn() {  },
        busy=fn() { busy.get() },
        said=fn() { said.get() },
      )
      |> ignore
    })
  }
  t.draw()
  t
}

///|
fn way_in_near(
  a : (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
  b : (Array[(Double, Double, Double, Double, Int64)], Array[(Double, Double)], Array[(Double, Double, Double, Double, Double, Int64)]),
) -> Bool {
  let n = fn(x : Double, y : Double) { (x - y).abs() <= 1.0e-9 }
  a.0.length() == b.0.length() &&
  a.0.iter().zip(b.0.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) && n(p.0.2, p.1.2) && n(p.0.3, p.1.3) && p.0.4 == p.1.4 }) &&
  a.1.length() == b.1.length() &&
  a.1.iter().zip(b.1.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) }) &&
  a.2.length() == b.2.length() &&
  a.2.iter().zip(b.2.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) && n(p.0.2, p.1.2) && n(p.0.3, p.1.3) && p.0.5 == p.1.5 })
}

///|
/// All a page draws, instance by instance (where and how big, its colour and alpha, what cuts it and how softly, its
/// corners, its kind's own numbers), but how far a spinner's pieces are turned (the clock's: spinner_node_wbtest).
fn way_in_all(t : @ui.Tester) -> Array[Array[Double]] {
  t
  .drawn_instances()
  .map(fn(i) {
    let i = i.copy()
    if i[5] == 10.0 && i.length() > 32 {
      i[32] = 0.0
    }
    i
  })
}

///|
fn way_in_all_near(a : Array[Array[Double]], b : Array[Array[Double]]) -> Bool {
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(fn(p) {
    p.0.length() == p.1.length() &&
    Array::makei(p.0.length(), fn(k) { k }).iter().all(fn(k) { way_in_same(k, p.0[k], p.1[k]) })
  })
}

///|
/// Instance number `k` of two draws the same: to a billionth of a point (its place added up in another order); what
/// cuts it (16 to 19: a billion across where nothing does) to its last few bits, as it is worked out from places in the
/// window (a thousand or so across) or from a billion: their rounding.
fn way_in_same(k : Int, a : Double, b : Double) -> Bool {
  if k >= 16 && k <= 19 {
    (a - b).abs() <= 4.0 * 2.220446049250313e-16 * dmax(1024.0, dmax(a.abs(), b.abs()))
  } else {
    (a - b).abs() <= 1.0e-9
  }
}

///|
/// The first instance where two pages' draws differ, and both of it there (None: none).
fn way_in_first_apart(a : Array[Array[Double]], b : Array[Array[Double]]) -> String {
  for k in 0..<@cmp.minimum(a.length(), b.length()) {
    if !way_in_all_near([a[k]], [b[k]]) {
      return "at \{k} of \{a.length()}/\{b.length()}: old \{a[k]}\n node \{b[k]}"
    }
  }
  "lengths \{a.length()}/\{b.length()}"
}

///|
test "the way in as nodes at rest: drawn as the old one is, on a tall page and a short one, to touch and to keyboard and mouse, with what is said under its button and without" {
  let cases : Array[(@ui.Pointing, Double, Double, (String, Bool))] = [
    (Finger, 390.0, 844.0, ("", false)),
    (Finger, 390.0, 520.0, ("", false)),
    (Finger, 390.0, 844.0, ("Sign-in failed", true)),
    (Mouse, 1280.0, 800.0, ("", false)),
    (Mouse, 1280.0, 800.0, ("Waiting for the browser", false)),
  ]
  let seen = []
  let same = cases.map(fn(k) {
    let (native, w, h, said) = k
    let draw = fn(node) {
      way_in_drawn(way_in_case(node, native, w, h, @signals.signal(false), @signals.signal(said, same=fn(a, b) { a == b })))
    }
    let (old, new) = (draw(false), draw(true))
    let (old_all, new_all) = (
      way_in_all(way_in_case(false, native, w, h, @signals.signal(false), @signals.signal(said, same=fn(a, b) { a == b }))),
      way_in_all(way_in_case(true, native, w, h, @signals.signal(false), @signals.signal(said, same=fn(a, b) { a == b }))),
    )
    let near = way_in_near(old, new) && way_in_all_near(old_all, new_all)
    if !near {
      seen.push("\{k}: \{way_in_first_apart(old_all, new_all)}")
    }
    near
  })
  assert_eq(same, Array::make(cases.length(), true), msg="\{seen}")
}

///|
test "the way in as nodes set to work and back: its button's spinner's room opening and closing, all of it where the old one's is, on the way and at the end" {
  let along = fn(node : Bool) {
    let busy = @signals.signal(false, same=fn(a, b) { a == b })
    let t = way_in_case(node, Finger, 390.0, 844.0, busy, @signals.signal(("", false), same=fn(a, b) { a == b }))
    let lag = if node { 0.0 } else { 16.0 }
    let out = [way_in_all(t)]
    for on in [true, false] {
      let t0 = t.time()
      busy.set(on)
      t.frame_at(t0 + 16.0)
      for at in way_in_moments {
        t.frame_at(t0 + lag + at)
        out.push(way_in_all(t))
      }
    }
    out
  }
  let (old, new) = (along(false), along(true))
  let same = Array::makei(old.length(), fn(k) { way_in_all_near(old[k], new[k]) })
  let apart = Array::makei(old.length(), fn(k) { way_in_first_apart(old[k], new[k]) })
  // (its spinner's pieces drawn on the way in and at work)
  let spun = new.map(fn(d) { d.iter().any(fn(i) { i[5] == 10.0 }) })
  assert_eq((same, spun[0], spun[1], spun[4]), (Array::make(old.length(), true), false, true, true), msg="\{apart}")
}

///|
/// Moments on the way in's ways: early, about half way, near the end, past all of them.
let way_in_moments : Array[Double] = [40.0, 100.0, 200.0, way_in_past_ms]

///|
/// What the way in draws at each of way_in_moments after what is said under its button is set to each of `steps` in
/// turn: an old view's or the tree's.
fn way_in_said_along(node : Bool, steps : Array[(String, Bool)]) -> Array[Array[Array[Double]]] {
  let said = @signals.signal(("", false), same=fn(a, b) { a == b })
  let t = way_in_case(node, Finger, 390.0, 844.0, @signals.signal(false), said)
  let lag = if node { 0.0 } else { 16.0 }
  let out = [way_in_all(t)]
  for to in steps {
    let t0 = t.time()
    said.set(to)
    t.frame_at(t0 + 16.0)
    for at in way_in_moments {
      t.frame_at(t0 + lag + at)
      out.push(way_in_all(t))
    }
  }
  out
}

///|
test "the way in as nodes, what is said under its button coming, said otherwise in the red, and gone, as it is again once the old one has laid it out: its room opening and closing, its words' colour and how faded and cut, all of it where the old one's is, on the way and at the end; the first time as it is again" {
  let (waits, fails) = (("Waiting for the browser", false), ("Sign-in failed", true))
  // (the old one's room opens by the height it was last laid out at, none the first time (@motion.reveal_height):
  // compared from its second, the node's the same from its first)
  let steps = [waits, ("", false), waits, fails, ("", false)]
  let (old, new) = (way_in_said_along(false, steps), way_in_said_along(true, steps))
  let n = way_in_moments.length()
  let again = 1 + 2 * n
  let same = Array::makei(old.length() - again, fn(k) { way_in_all_near(old[again + k], new[again + k]) })
  let apart = Array::makei(old.length() - again, fn(k) { way_in_first_apart(old[again + k], new[again + k]) })
  let first_as_again = Array::makei(n, fn(k) { way_in_all_near(new[1 + k], new[again + k]) })
  assert_eq(
    (same, first_as_again),
    (Array::make(old.length() - again, true), Array::make(n, true)),
    msg="\{apart}",
  )
}

///|
/// Longer than any of the way in's ways takes.
let way_in_past_ms : Double = 1000.0
