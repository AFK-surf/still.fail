// The library's button as a node of the window's tree (button_node) drawn as the old one (button) is: at rest, its
// words its content's width or as wide as a column (its own height kept); at work, its spinner's room opening and the
// spinner turning, then closing; its words changed, going to their place; nothing turning at rest, before or after.

///|
/// What a button draws: its ground's rects (x, y, w, h) and its glyphs' places.
fn button_drawn(t : @ui.Tester) -> (Array[(Double, Double, Double, Double)], Array[(Double, Double)]) {
  (t.drawn_rects().map(fn(r) { (r.0, r.1, r.2, r.3) }), t.drawn_glyphs().map(fn(g) { (g.0, g.1) }))
}

///|
/// A button in a column 300 wide and 200 tall at the window's top left, its words `words`, `tone`, at work as `busy`
/// says, as wide as the column where `across`: an old view's (button) or the tree's (button_node). The Tester.
fn button_case(
  words : @signals.Signal[String],
  busy : @signals.Signal[Bool],
  node : Bool,
  tone? : Tone = Plain,
  across? : Bool = false,
  there? : @signals.Signal[Bool] = @signals.signal(true),
  start? : Bool = true,
) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      if !node {
        // (at the column's start where `start`, as the tree's column lines them up: lines_up Start; else stretched
        // across it, as both lay out what they hold by default)
        c.box(w=Px(300.0), h=Px(200.0), align=if start { AStart } else { AStretch }, fn() {
          button(c, words.get(), key="b", tone~, busy=busy.get(), w=if across { Fill(1.0) } else { Auto }) |> ignore
        })
        |> ignore
      }
    },
    w=400.0,
    h=300.0,
  )
  t.check_looks(false)
  if node {
    @ui.set_view_app(fn(root) {
      root.box(fn(col) {
        col.width(Is(Some(300.0))).height(Is(Some(200.0))).lines_up(Is(if start { Some(Start) } else { None })) |> ignore
        col.show(fn() { there.get() }, fn(at) {
          // (what it is shown in as wide as the column and lining it up as the column does: the button laid out as
          // in the column itself)
          at.width_share(Is(1.0)).lines_up(Is(if start { Some(Start) } else { None })) |> ignore
          button_node(at, fn() { words.get() }, fn() {  }, tone~, busy=fn() { busy.get() }, across~) |> ignore
        })
      })
      |> ignore
    })
  }
  t.draw()
  t
}

///|
fn drawn_near(
  a : (Array[(Double, Double, Double, Double)], Array[(Double, Double)]),
  b : (Array[(Double, Double, Double, Double)], Array[(Double, Double)]),
) -> Bool {
  let n = fn(x : Double, y : Double) { (x - y).abs() <= 1.0e-9 }
  a.0.length() == b.0.length() &&
  a.0.iter().zip(b.0.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) && n(p.0.2, p.1.2) && n(p.0.3, p.1.3) }) &&
  a.1.length() == b.1.length() &&
  a.1.iter().zip(b.1.iter()).all(fn(p) { n(p.0.0, p.1.0) && n(p.0.1, p.1.1) })
}

///|
test "the button as a node at rest, its words its width or as wide as a column, plain or the one thing to do: drawn as the old one is; its height its own" {
  // (its tone, whether as wide as a column, whether at the column's start or stretched across it)
  let cases : Array[(Tone, Bool, Bool)] = [
    (Plain, false, true),
    (Primary, false, true),
    (Plain, true, true),
    (Primary, true, true),
    (Plain, false, false),
    (Primary, true, false),
  ]
  let seen = []
  let same = cases.map(fn(k) {
    let (tone, across, start) = k
    let old = button_drawn(button_case(@signals.signal("Join"), @signals.signal(false), false, tone~, across~, start~))
    let new = button_drawn(button_case(@signals.signal("Join"), @signals.signal(false), true, tone~, across~, start~))
    seen.push("old \{old.0} \{old.1[:1]}, node \{new.0} \{new.1[:1]}")
    drawn_near(old, new) && new.0.iter().all(fn(r) { r.3 == button_height() })
  })
  assert_eq(same, Array::make(cases.length(), true), msg="\{seen}")
}

///|
test "the button as a node idle: nothing turning; at work, its spinner turning; at rest again once its room has closed, nothing turning" {
  let busy = @signals.signal(false, same=fn(a, b) { a == b })
  let t = button_case(@signals.signal("Join"), busy, true)
  let tree = @ui.view_tree().unwrap()
  let idle = tree.cycle_read()
  busy.set(true)
  t.frame()
  t.run_for(past_button_ms)
  let turn_a = t.drawn_instances().filter(fn(i) { i[5] == 10.0 }).map(fn(i) { i[32] })
  t.frame_at(t.time() + 100.0)
  let turn_b = t.drawn_instances().filter(fn(i) { i[5] == 10.0 }).map(fn(i) { i[32] })
  let working = tree.cycle_read()
  busy.set(false)
  t.frame()
  t.run_for(past_button_ms)
  let rested = tree.cycle_read()
  assert_eq((idle, turn_a.length() > 0, turn_a != turn_b, working, rested), (false, true, true, true, false))
}

///|
test "the button as a node let go at work, its spinner's room opening: none of it left, drawn or turning" {
  let busy = @signals.signal(false, same=fn(a, b) { a == b })
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = button_case(@signals.signal("Join"), busy, true, there~)
  let tree = @ui.view_tree().unwrap()
  busy.set(true)
  t.frame()
  t.run_for(button_half_ms)
  let (alive, turning) = (tree.alive(), tree.cycle_read())
  there.set(false)
  t.frame()
  let pieces = t.drawn_instances().filter(fn(i) { i[5] == 10.0 }).length()
  let left = tree.alive()
  t.run_for(past_button_ms)
  assert_eq(
    (turning, tree.cycle_read(), pieces, t.drawn_rects().length(), alive > left, tree.alive() == left),
    (true, false, 0, 0, true, true),
  )
}

///|
/// Less than a button's spinner's room takes to open.
let button_half_ms : Double = 60.0

///|
/// Longer than any of a button's ways takes.
let past_button_ms : Double = 1000.0

///|
/// The pieces of lines a button draws (its spinner's: kind 10), each but how far it is turned (which the clock says,
/// spinner_node_wbtest): where and how big, its ends, its colour and opacity, the point it turns about, whether what
/// cuts it stays.
fn button_pieces(t : @ui.Tester) -> Array[Array[Double]] {
  t
  .drawn_instances()
  .filter(fn(i) { i[5] == 10.0 })
  .map(fn(i) { [i[0], i[1], i[2], i[3], i[4], i[8], i[9], i[10], i[11], i[12], i[13], i[14], i[15], i[33], i[34], i[35]] })
}

///|
/// Whether two buttons' spinners are drawn alike but for how far they are turned (each number the same to the last few
/// digits of a double).
fn pieces_near(a : Array[Array[Double]], b : Array[Array[Double]]) -> Bool {
  a.length() == b.length() &&
  a
  .iter()
  .zip(b.iter())
  .all(fn(p) { p.0.length() == p.1.length() && p.0.iter().zip(p.1.iter()).all(fn(v) { (v.0 - v.1).abs() <= 1.0e-9 }) })
}

///|
/// What a button draws (its ground, its words, its spinner's pieces) on the way after each of `steps` at each of
/// `moments`: an old view's or the tree's, its words `words`, at work as `busy` says. Each step is said with no frame
/// drawn (a value set): the tree's way sets off at that moment, the old one's at its first frame after, 16 later here.
fn button_along(
  node : Bool,
  words : @signals.Signal[String],
  busy : @signals.Signal[Bool],
  steps : Array[() -> Unit],
  moments : Array[Double],
) -> Array[((Array[(Double, Double, Double, Double)], Array[(Double, Double)]), Array[Array[Double]])] {
  let t = button_case(words, busy, node)
  let lag = if node { 0.0 } else { 16.0 }
  let out = [(button_drawn(t), button_pieces(t))]
  for step in steps {
    let t0 = t.time()
    step()
    t.frame_at(t0 + 16.0)
    for at in moments {
      t.frame_at(t0 + lag + at)
      out.push((button_drawn(t), button_pieces(t)))
    }
  }
  out
}

///|
/// Moments on a button's ways: early, about half way, near the end, past all of them.
let button_moments : Array[Double] = [40.0, 100.0, 200.0, past_button_ms]

///|
test "the button as a node, its words longer and shorter again: its ground and its words where the old one's go, on the way and at the end" {
  let seen = fn(node : Bool) {
    let words = @signals.signal("Join", same=fn(a, b) { a == b })
    let busy = @signals.signal(false, same=fn(a, b) { a == b })
    button_along(node, words, busy, [fn() { words.set("Join the chat") }, fn() { words.set("Join") }], button_moments)
  }
  let (old, new) = (seen(false), seen(true))
  let same = Array::makei(old.length(), fn(k) { drawn_near(old[k].0, new[k].0) && pieces_near(old[k].1, new[k].1) })
  assert_eq(same, Array::make(old.length(), true), msg="old \{old}\nnode \{new}")
}

///|
test "the button as a node set to work and back: its spinner's room opening and closing, its ground, its words and its spinner's pieces (as big, where, as faded) where the old one's are, on the way and at the end" {
  let seen = fn(node : Bool) {
    let words = @signals.signal("Join", same=fn(a, b) { a == b })
    let busy = @signals.signal(false, same=fn(a, b) { a == b })
    button_along(node, words, busy, [fn() { busy.set(true) }, fn() { busy.set(false) }], button_moments)
  }
  let (old, new) = (seen(false), seen(true))
  let same = Array::makei(old.length(), fn(k) { drawn_near(old[k].0, new[k].0) && pieces_near(old[k].1, new[k].1) })
  // (no spinner at rest, before or after; one on the way in and at work)
  let spun = new.map(fn(k) { k.1.length() > 0 })
  assert_eq(
    (same, spun[0], spun[1], spun[4], spun[8]),
    (Array::make(old.length(), true), false, true, true, false),
    msg="old \{old}\nnode \{new}",
  )
}

///|
/// A button's ground's colours at `moments` after the pointer comes onto it, and after it goes, by `on` and `off`
/// (each drawing its frame at its moment, as a host takes an input: both ways set off then).
fn button_answers(
  node : Bool,
  on : (@ui.Tester, Double, Double) -> Unit,
  off : (@ui.Tester, Double, Double) -> Unit,
) -> Array[Array[Int64]] {
  let t = button_case(@signals.signal("Join"), @signals.signal(false), node)
  let (x, y) = {
    let r = t.drawn_rects()[0]
    (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
  }
  let out = [t.drawn_rects().map(fn(r) { r.4 })]
  for go in [on, off] {
    let t0 = t.time()
    go(t, x, y)
    for at in button_moments {
      t.frame_at(t0 + at)
      out.push(t.drawn_rects().map(fn(r) { r.4 }))
    }
  }
  out
}

///|
test "the button as a node, the pointer come onto it and gone: its ground's colour as the old one's, on the way and at the end" {
  let on = fn(t : @ui.Tester, x, y) { t.move(x, y) }
  let off = fn(t : @ui.Tester, _x, _y) { t.move(390.0, 290.0) }
  let (old, new) = (button_answers(false, on, off), button_answers(true, on, off))
  assert_eq((new == old, new[0] != new[3]), (true, true), msg="old \{old}\nnode \{new}")
}

///|
test "the button as a node pressed and let go: its ground's colour as the old one's, on the way and at the end" {
  let on = fn(t : @ui.Tester, x, y) { t.press_at(x, y) }
  let off = fn(t : @ui.Tester, x, y) { t.release(x, y) }
  let (old, new) = (button_answers(false, on, off), button_answers(true, on, off))
  assert_eq((new == old, new[0] != new[3]), (true, true), msg="old \{old}\nnode \{new}")
}
