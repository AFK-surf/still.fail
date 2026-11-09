// A row leaving out what it has not the room for (View::drops, fits, left_out): what is left out, and all it holds,
// out of the scene, of what is pressed (by a finger, by its id, by a screen reader), of what is read out (its own and
// what it hosts) and of what takes input, at once; back, the same nodes, as the room comes; a node made again in the
// place of one left out none of it.

///|
/// A row as wide as `w` says (16 tall at the window's top left) holding four buttons 100 wide (called b1 to b4, the
/// last leaving first), the second hosting another's, and a ⋯ 40 wide there only while something of it is left out;
/// each button's presses counted in `pressed`, each node's id in `ids`. Laid out once, 400 wide.
fn drops_row(
  w : @signals.Signal[Double],
  pressed : Map[String, Int],
  ids : Map[String, @view.NodeId],
  views : Map[String, @view.View],
) -> @view.Tree {
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.over(Is(true)).row(Is(true)).fits(Is(true)).width(By(fn() { Some(w.get()) })).height(Is(Some(16.0))) |> ignore
        for i in 1..=4 {
          let name = "b\{i}"
          row.box(fn(b) {
            ids[name] = b.id()
            views[name] = b
            b
            .width(Is(Some(100.0)))
            .drops(Is(5 - i))
            .presses(Is(true))
            .says(Is(Some(@view.said(Button, label=name))))
            .on_press(fn() { pressed[name] = pressed.get(name).unwrap_or(0) + 1 })
            |> ignore
            if i == 2 {
              b.box(fn(h) {
                ids["hosted"] = h.id()
                h.grow(Is(1.0)) |> ignore
              })
              |> ignore
              b.hosted() |> ignore
            }
          })
          |> ignore
        }
        row.box(fn(m) {
          ids["more"] = m.id()
          views["more"] = m
          // (how many are left out, said as the row says it: View::left_out)
          m
          .width(Is(Some(40.0)))
          .drops(Is(-1))
          .words(By(fn() { "+\{["b1", "b2", "b3", "b4"].filter(fn(k) { views[k].left_out() }).length()}" }))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(800.0, 300.0) |> ignore
  t
}

///|
test "drops: a row 400 wide holding four 100 wide: all of them, no ⋯; 260 wide: the last two left out, the ⋯ in, none of them drawn, pressed by id or by a screen reader, read out, taking input; 400 again: the same nodes back" {
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let pressed : Map[String, Int] = {}
  let ids : Map[String, @view.NodeId] = {}
  let views : Map[String, @view.View] = {}
  let t = drops_row(w, pressed, ids, views)
  let outs = fn() { ["b1", "b2", "b3", "b4", "more"].filter(fn(k) { views[k].left_out() }) }
  assert_eq(outs(), ["more"], msg="400: all four, no ⋯")
  // (what the last two take input as, followed together)
  let takes : Array[(Bool, Bool)] = []
  let stop = @signals.effect(fn() { takes.push((views["b3"].takes_input(), views["b4"].takes_input())) })
  t.event(10.0, fn() { w.set(260.0) })
  t.frame(800.0, 300.0) |> ignore
  assert_eq(outs(), ["b3", "b4"], msg="260: the last two left out, the ⋯ in")
  for k in ["b3", "b4"] {
    assert_true(t.drawn_of(ids[k]) is None, msg="\{k}: not drawn")
    assert_false(t.reads_out(ids[k]), msg="\{k}: not read out")
    assert_false(t.said_order().iter().any(fn(s) { s.id == ids[k] }), msg="\{k}: not among what is read out")
    assert_false(t.run_press_at(ids[k], 20.0), msg="\{k}: not pressed by its id")
    assert_false(t.activate_at(ids[k], 20.0), msg="\{k}: not pressed by a screen reader")
  }
  assert_eq(pressed.get("b4").unwrap_or(0), 0, msg="b4: nothing pressed")
  assert_eq(takes, [(true, true), (false, false)], msg="b3, b4: taking no input, told at once, never half of it")
  assert_eq(t.drawn_of(ids["more"]).map(fn(d) { d.words }), Some("+2"), msg="the ⋯: drawn, saying how many, in the frame that left them out")
  // (what the second hosts read out where it is not left out)
  assert_true(t.reads_out(ids["hosted"]), msg="what b2 hosts: read out")
  t.event(30.0, fn() { w.set(400.0) })
  t.frame(800.0, 300.0) |> ignore
  assert_eq(outs(), ["more"], msg="400 again: all four back, no ⋯")
  for k in ["b3", "b4"] {
    assert_true(t.drawn_of(ids[k]) is Some(_), msg="\{k}: the same node drawn again")
  }
  assert_eq(takes, [(true, true), (false, false), (true, true)], msg="b3, b4: taking input again, told at once")
  assert_true(t.run_press_at(ids["b4"], 40.0), msg="b4: pressed by its id again")
  stop()
}

///|
test "drops: what a node left out hosts not read out by its id; that node let go and another made in its place, room for it: the new one not left out" {
  let w = @signals.signal(150.0, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let ids : Map[String, @view.NodeId] = {}
  let views : Map[String, @view.View] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.over(Is(true)).row(Is(true)).fits(Is(true)).width(By(fn() { Some(w.get()) })).height(Is(Some(16.0))) |> ignore
        row.box(fn(a) { a.width(Is(Some(100.0))).drops(Is(2)) |> ignore }) |> ignore
        row.show(fn() { shown.get() }, fn(b) {
          ids["b"] = b.id()
          views["b"] = b
          b.width(Is(Some(100.0))).drops(Is(1)) |> ignore
          b.box(fn(h) {
            ids["hosted"] = h.id()
            h.grow(Is(1.0)) |> ignore
          })
          |> ignore
          b.hosted() |> ignore
        })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(800.0, 300.0) |> ignore
  assert_true(views["b"].left_out(), msg="150 wide: the second left out")
  assert_false(t.reads_out(ids["hosted"]), msg="what it hosts: not read out by its id")
  let was = ids["b"]
  t.event(10.0, fn() { shown.set(false) })
  t.frame(800.0, 300.0) |> ignore
  t.event(20.0, fn() {
    w.set(300.0)
    shown.set(true)
  })
  // (made, not laid out yet: nothing of the one before in it)
  assert_true(ids["b"].at == was.at && ids["b"].gen != was.gen, msg="made again in its place: \{was.at} \{was.gen}, \{ids["b"].at} \{ids["b"].gen}")
  assert_false(views["b"].left_out(), msg="made, before a frame: not left out")
  assert_true(t.reads_out(ids["hosted"]), msg="what it hosts, before a frame: read out")
  t.frame(800.0, 300.0) |> ignore
  assert_false(views["b"].left_out(), msg="room for it: the new one not left out")
  assert_true(t.drawn_of(ids["b"]) is Some(_), msg="the new one drawn")
}

///|
test "drops: a finger held on a node as its row leaves it out, then let go: told called off once, nothing after" {
  let w = @signals.signal(400.0, same=fn(a, b) { a == b })
  let seen : Array[@view.Drag] = []
  let ids : Map[String, @view.NodeId] = {}
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(row) {
        row.over(Is(true)).row(Is(true)).fits(Is(true)).width(By(fn() { Some(w.get()) })).height(Is(Some(16.0))) |> ignore
        row.box(fn(a) { a.width(Is(Some(100.0))).drops(Is(2)) |> ignore }) |> ignore
        row.box(fn(b) {
          ids["b"] = b.id()
          b.width(Is(Some(100.0))).drops(Is(1)).on_drag(fn(d) { seen.push(d) }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(800.0, 300.0) |> ignore
  t.drag_at(ids["b"], Down, 150.0, 8.0, 10.0) |> ignore
  t.event(20.0, fn() { w.set(150.0) })
  t.frame(800.0, 300.0) |> ignore
  // (called off as it is left out, the finger still down: not as it lifts)
  assert_eq(seen.map(fn(d) { d.kind == Off }), [false, true], msg="left out, the finger still down: called off then")
  t.drag_at(ids["b"], Up, 150.0, 8.0, 30.0) |> ignore
  t.frame(800.0, 300.0) |> ignore
  let kinds = seen.map(fn(d) {
    match d.kind {
      Down => "down"
      Off => "off"
      Up => "up"
      _ => "moved"
    }
  })
  assert_eq(kinds, ["down", "off"], msg="held as it is left out: called off once, nothing after")
}
