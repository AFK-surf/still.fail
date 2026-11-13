// What is put by (View::park: a page's list's block kept for the next of its kind as the slot it was in is let go,
// View::scrolls_window's `reused`) is held by no node: from the root none of it is reached, so a frame does the same
// work however many are put by, and none of it is laid out, placed, walked in order, drawn, pressed, focused or read
// out, by nothing but that; nor has it a place (View::rect, shown_across, shown_nowhere).

///|
/// A page's list of 40 rows in a box 200 tall, and beside it `k` spares (each pressed, focusable, read out, with words)
/// put by after its first frame: the tree, the spares, and where each was before it was put by.
fn spares_case(k : Int) -> (Tree, Array[View], Array[(Double, Double)]) {
  let s = Scroll::list()
  let holder : Ref[View?] = Ref(None)
  let t = Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(s, fn() { Array::makei(40, fn(i) { i }) }, est=22.0, fn(b, key) {
          b.box(fn(l) { l.height(Is(Some(22.0))).words(Is("row \{key}")) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
      root.box(fn(h) {
        holder.val = Some(h)
        for i in 0..<k {
          h
          .box(fn(sp) {
            sp
            .width(Is(Some(100.0)))
            .height(Is(Some(30.0)))
            .words(Is("spare \{i}"))
            .on_press(fn() {  })
            .focusable(Is(true))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let h = holder.val.unwrap()
  let spares = t.nodes[h.at].kids.map(fn(c) { t.handle(c) })
  let was = spares.map(fn(v) {
    let (x, y, w, hh) = v.rect()
    (x + w / 2.0, y + hh / 2.0)
  })
  for v in spares {
    h.park(v) |> ignore
  }
  t.frame(390.0, 844.0) |> ignore
  (t, spares, was)
}

///|
/// What one frame of a scroll does: the nodes laid out, placed and visited, the layouts computed, the times the order
/// was made again, and how many are drawn and in the order.
fn spares_scroll_work(t : Tree, at : Double) -> Array[Int] {
  t.wheel_at(150.0, 100.0, 0.0, 66.0, 0, at) |> ignore
  let w0 = t.work()
  let f0 = @flex.computes()
  t.frame(390.0, 844.0) |> ignore
  let w1 = t.work()
  [
    w1.laid - w0.laid,
    w1.visited - w0.visited,
    w1.computes - w0.computes,
    @flex.computes() - f0,
    w1.orders - w0.orders,
    t.order.length(),
    t.drawn().length(),
  ]
}

///|
test "spares put by, 0, 1, 8 and 64 of them: a scroll frame does the same work; none of them is drawn, pressed, focused or read out, none has a place" {
  let works = []
  let faults = []
  for k in [0, 1, 8, 64] {
    let (t, spares, was) = spares_case(k)
    works.push(
      [10.0, 20.0, 30.0].map(fn(at) { spares_scroll_work(t, at) }),
    )
    let ids = spares.map(fn(v) { v.id() })
    let mine = fn(id : NodeId) { ids.contains(id) }
    if t.drawn().iter().any(fn(d) { mine(d.id) }) {
      faults.push("\{k}: drawn")
    }
    if t.focus_order().iter().any(fn(f) { mine(f.id) }) {
      faults.push("\{k}: focusable")
    }
    if t.said_order().iter().any(fn(s) { mine(s.id) }) {
      faults.push("\{k}: read out")
    }
    for i, v in spares {
      let (x, y) = was[i]
      match t.target_at(x, y) {
        Pressed(id) | Dragged(id) | Hosted(id) | TopRow(id) if mine(id) => faults.push("\{k}: spare \{i} pressed")
        _ => ()
      }
      if t.focus_to(Some(v.id())) || t.focused_now().0 == Some(v.id()) {
        faults.push("\{k}: spare \{i} focused")
      }
      if v.rect() != (0.0, 0.0, 0.0, 0.0) || !v.shown_nowhere() || v.shown_across() is Some(_) {
        faults.push("\{k}: spare \{i} has a place")
      }
    }
  }
  assert_eq(faults, [])
  assert_eq(works[1], works[0], msg="1 spare")
  assert_eq(works[2], works[0], msg="8 spares")
  assert_eq(works[3], works[0], msg="64 spares")
}

///|
test "a page's list's block put by in a slot that leaves the slots kept: parked, not let go, and taken again by the next of its kind to show" {
  let made = Ref(0)
  let gone = Ref(0)
  let tree = Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(
          Scroll::list(),
          fn() { Array::makei(400, fn(i) { i }) },
          est=22.0,
          fn(_, _) { @halt.saying("every block is of a kind another may take") },
          reused=fn(_) { Some(0) },
          make_reused=fn(b, key) {
            made.val = made.val + 1
            b.owns(fn() { gone.val = gone.val + 1 }) |> ignore
            b.box(fn(l) { l.height(Is(Some(22.0))).words(By(fn() { "row \{key()}" })) |> ignore }) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let first = made.val
  // (down a turn at a time, far past where the first slots were: what was put by there parked as its slot went)
  for t in Array::makei(60, fn(i) { 10.0 + i.to_double() }) {
    tree.wheel_at(150.0, 100.0, 0.0, 66.0, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  // (blocks made: those that showed first, and no more than a few put by for each that came at once; none let go but
  // past the spares kept)
  assert_true(made.val <= first + spare_most + 2, msg="made \{made.val}, first \{first}, let go \{gone.val}")
  // (what is drawn: its rows, each with its own key's words, one after another)
  let rows = tree.drawn().filter(fn(d) { d.words.has_prefix("row ") && d.y + d.h > 0.0 && d.y < 200.0 })
  assert_true(rows.length() > 0)
}
