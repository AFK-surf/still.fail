// A row that wraps the other way (View::wraps `reverse`, an old view's `flow_reverse`): each line it goes on to over the
// one before it, the first at its foot, what each line holds in its order along it; where all of it has the room, as a
// row that wraps the usual way; what each line holds lined up in it from the line's foot (its start across, as flex's
// WrapReverse has it); read out and stepped through by the keyboard in the order it is held, not by where it is drawn.

///|
/// Boxes as wide and tall as `sizes` say, each pressed and read out as "b<k>", in a row as wide as `width` says, 10 apart
/// along it, its lines 4 apart, wrapping the other way where `reverse` says; laid out (390 by 844), where each is drawn.
fn reverse_tree(
  sizes : Array[(Double, Double)],
  width : @signals.Signal[Double],
  reverse : Bool,
  ids : Array[@view.NodeId],
) -> (@view.Tree, () -> Array[(Double, Double)]) {
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.width(By(fn() { Some(width.get()) })).row(Is(true)).gap(Is(10.0)).wraps(Is(Some(4.0)), reverse~) |> ignore
        for k, s in sizes {
          r.box(fn(b) {
            ids.push(b.id())
            b
            .width(Is(Some(s.0)))
            .height(Is(Some(s.1)))
            .ground(Is(0x336699FFL))
            .focusable(Is(true))
            .says(Is(Some(@view.said(Button, label="b\{k}"))))
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let at = fn() {
    t.frame(390.0, 844.0) |> ignore
    ids.map(fn(id) {
      match t.drawn().search_by(fn(d) { d.id == id }) {
        Some(i) => (t.drawn()[i].x, t.drawn()[i].y)
        None => (-1.0, -1.0)
      }
    })
  }
  (t, at)
}

///|
test "wraps the other way: each line over the one before it, the first at the foot, each in its order along it; with the room, as wrapping the usual way" {
  let width = @signals.signal(100.0)
  let (_, at) = reverse_tree([(40.0, 20.0), (40.0, 20.0), (40.0, 20.0)], width, true, [])
  // (40 + 10 + 40 + 10 + 40 is more than 100: the third on a line of its own, over the first two, 20 and 4 up)
  assert_eq(at(), [(0.0, 24.0), (50.0, 24.0), (0.0, 0.0)])
  // (three lines: the last on top)
  width.set(45.0)
  assert_eq(at(), [(0.0, 48.0), (0.0, 24.0), (0.0, 0.0)])
  // (the room for all of it: one line, as wrapping the usual way)
  width.set(200.0)
  let reversed = at()
  let (_, usual) = reverse_tree([(40.0, 20.0), (40.0, 20.0), (40.0, 20.0)], width, false, [])
  assert_eq(reversed, usual())
  assert_eq(reversed, [(0.0, 0.0), (50.0, 0.0), (100.0, 0.0)])
}

///|
test "wraps the other way: lines of other heights each as tall as its tallest, what it holds lined up from its foot" {
  let width = @signals.signal(100.0)
  let (_, at) = reverse_tree([(60.0, 20.0), (40.0, 30.0), (30.0, 20.0)], width, true, [])
  // (60 + 10 + 40 is more than 100: the first alone at the foot; the second and third over it, a line 30 tall, the
  // third's 20 at that line's foot)
  assert_eq(at(), [(0.0, 34.0), (0.0, 0.0), (50.0, 10.0)])
}

///|
test "wraps the other way: read out and stepped through by the keyboard in the order it is held, not by where it is drawn" {
  let ids : Array[@view.NodeId] = []
  let (t, at) = reverse_tree([(40.0, 20.0), (40.0, 20.0), (40.0, 20.0)], @signals.signal(100.0), true, ids)
  ignore(at())
  assert_eq(t.focus_order().map(fn(f) { f.id }), ids)
  assert_eq(t.said_order().filter(fn(s) { s.said is Some(_) }).map(fn(s) { t.said_label(s.id) }), ["b0", "b1", "b2"])
}
