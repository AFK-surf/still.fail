// View::each's `keeps` (each_kept.mbt): a row whose key leaves while it is kept is put by at rest and taken in again,
// the same nodes, in its order, as its key comes back; out of the tree meanwhile (not laid out, drawn, pressed, focused
// or read out), what it held while it read let go of and asked again as it wakes; let go as it is no more kept, and
// with the each.

///|
/// What one case holds: the items and the kept keys, the rows made by key (how many times) and their nodes, what each
/// row's press did, how often a binding of each row's ran, a value held while it is read and how often it was let go.
priv struct KeptCase {
  t : Tree
  items : @signals.Signal[Array[String]]
  keeps : @signals.Signal[Array[String]]
  here : @signals.Signal[Bool]
  made : Map[String, Int]
  nodes : Map[String, View]
  keys : Map[String, View]
  pressed : Map[String, Int]
  widths : Map[String, Int]
  width : @signals.Signal[Double]
  held : @signals.Signal[Int]
  unheld : Ref[Int]
  owned : Map[String, Int]
  out : Array[String]
}

///|
/// Rows 50 high down a column, one for each key of `items` (each its words, the held value with them; pressed, taken
/// the focus, read out as a button by its key; as wide as `width`, how often that is worked out counted; a box going
/// from 0 to 90 across as the clock goes from 0 to 300; a moment asked at 100), `keeps` kept, all of it in a show.
fn kept_case(items : Array[String], keeps : Array[String]) -> KeptCase {
  let items = @signals.signal(items, same=fn(a, b) { a == b })
  let keeps = @signals.signal(keeps, same=fn(a, b) { a == b })
  let here = @signals.signal(true, same=fn(a, b) { a == b })
  let made : Map[String, Int] = Map([])
  let nodes : Map[String, View] = Map([])
  let keys : Map[String, View] = Map([])
  let pressed : Map[String, Int] = Map([])
  let widths : Map[String, Int] = Map([])
  let owned : Map[String, Int] = Map([])
  let width = @signals.signal(200.0, same=fn(a, b) { a == b })
  let held = @signals.signal(0, same=fn(a, b) { a == b })
  let unheld = Ref(0)
  held.on_unwatched(fn() { unheld.val += 1 })
  let out : Array[String] = []
  let t = Tree::new(fn(root) {
    root.show(fn() { here.get() }, fn(col) {
      col.each(
        fn() { items.get() },
        fn(k) { k },
        fn(r, item) {
          let k = item.untracked()
          made[k] = made.get(k).unwrap_or(0) + 1
          nodes[k] = r
          r.owns(fn() { owned[k] = owned.get(k).unwrap_or(0) + 1 }) |> ignore
          r.at_moment(100.0, fn() { out.push("\{k} moment 100 at \{r.cause_at()}") }) |> ignore
          r.box(fn(b) {
            keys[k] = b
            b
            .height(Is(Some(40.0)))
            .width(By(fn() {
              widths[k] = widths.get(k).unwrap_or(0) + 1
              Some(width.get())
            }))
            .words(By(fn() { "\{item.get()} held \{held.get()}" }))
            .on_press(fn() { pressed[k] = pressed.get(k).unwrap_or(0) + 1 })
            .focusable(Is(true))
            .says(Is(Some(said(Button, label=k))))
            |> ignore
          })
          |> ignore
          r.box(fn(m) {
            m
            .width(Is(Some(30.0)))
            .height(Is(Some(10.0)))
            .words(Is("\{k}~"))
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
        },
        keeps=fn() { keeps.get() },
      )
    })
  })
  { t, items, keeps, here, made, nodes, keys, pressed, widths, width, held, unheld, owned, out }
}

///|
fn KeptCase::frame(self : KeptCase, at : Double) -> Unit {
  self.t.at(at)
  self.t.frame(390.0, 844.0, now=at) |> ignore
}

///|
/// Each row's words drawn now, top to bottom, with where (y).
fn KeptCase::rows(self : KeptCase) -> Array[(String, Double)] {
  self.t.drawn().filter(fn(d) { d.words.contains(" held ") }).map(fn(d) { (d.words, d.y) })
}

///|
/// Whether key `k`'s row is drawn, focused, read out (any node of it).
fn KeptCase::seen(self : KeptCase, k : String) -> (Bool, Bool, Bool) {
  let r = self.nodes[k]
  let mine = fn(id : NodeId) { r.alive() && self.t.holds(r.id(), id) }
  let drawn = self.t.drawn().iter().any(fn(d) { mine(d.id) })
  let focused = match self.t.focused_now().0 {
    Some(f) => mine(f)
    None => false
  }
  let read_out = self.t.said_order().iter().any(fn(s) { mine(s.id) })
  (drawn, focused, read_out)
}

///|
test "a row kept as its key leaves is put by and taken in again: the same node, there at once, in its order among the others" {
  let c = kept_case(["a", "b", "c"], ["b"])
  c.frame(0.0)
  let b = c.nodes["b"]
  assert_eq(c.rows(), [("a held 0", 0.0), ("b held 0", 50.0), ("c held 0", 100.0)])
  c.items.set(["a", "c"])
  c.frame(1000.0)
  // (put by: held by no node, alive; what was after it in its place at once, no way closing)
  assert_eq(c.rows(), [("a held 0", 0.0), ("c held 0", 50.0)])
  assert_true(b.alive())
  assert_eq(c.t.nodes[b.at].parent, -1)
  // (back, after the others: the same node, made once, there whole at once)
  c.items.set(["a", "c", "b"])
  c.frame(2000.0)
  assert_eq(c.rows(), [("a held 0", 0.0), ("c held 0", 50.0), ("b held 0", 100.0)])
  assert_true(physical_equal(c.nodes["b"], b))
  assert_eq(c.made, Map([("a", 1), ("b", 1), ("c", 1)]))
  // (put by again, then back among them, first)
  c.items.set(["a", "c"])
  c.frame(3000.0)
  c.items.set(["b", "a", "c"])
  c.frame(3016.0)
  assert_eq(c.rows(), [("b held 0", 0.0), ("a held 0", 50.0), ("c held 0", 100.0)])
  assert_eq(c.made["b"], 1)
  assert_eq(c.owned.get("b"), None)
}

///|
test "a row put by is not laid out, drawn, pressed, focused or read out, and what it held while it read is let go of and asked again as it wakes" {
  let c = kept_case(["a", "b"], ["b"])
  c.frame(0.0)
  ignore(c.t.focus_to(Some(c.keys["b"].id())))
  c.frame(16.0)
  assert_eq(c.seen("b"), (true, true, true))
  assert_true(c.t.takes_keys(c.keys["b"].id()))
  assert_true(c.t.press(10.0, 70.0))
  assert_eq(c.pressed.get("b"), Some(1))
  assert_eq((c.held.watched(), c.unheld.val), (true, 0))
  let widths = c.widths["b"]
  c.items.set(["a"])
  c.frame(1000.0)
  // (out of the tree: nothing of it drawn, the focus let go, nothing read out, nothing pressed where it was)
  assert_eq(c.seen("b"), (false, false, false))
  assert_eq(c.t.focused_now().0, None)
  // (what Tab, what gives the focus and what gives it back ask: no for what is put by)
  assert_false(c.t.takes_keys(c.keys["b"].id()))
  assert_false(c.t.press(10.0, 70.0))
  assert_eq(c.pressed.get("b"), Some(1))
  // (what it held while it read let go of; another row still reads it: held for that one)
  assert_eq(c.unheld.val, 0)
  // (what it binds changed as it rests: nothing worked out)
  c.width.set(150.0)
  c.held.set(7)
  c.frame(1100.0)
  assert_eq(c.widths["b"], widths)
  // (back: worked out anew as it wakes, as it is now; the focus not given back)
  c.items.set(["a", "b"])
  c.frame(2000.0)
  assert_eq(c.rows(), [("a held 7", 0.0), ("b held 7", 50.0)])
  assert_eq(c.widths["b"], widths + 1)
  assert_eq(c.seen("b"), (true, false, true))
  assert_true(c.t.takes_keys(c.keys["b"].id()))
  assert_true(c.t.press(10.0, 70.0))
  assert_eq(c.pressed.get("b"), Some(2))
}

///|
test "a row put by lets go of what it alone held while it read, and asks it again as it wakes" {
  let c = kept_case(["b"], ["b"])
  c.frame(0.0)
  assert_eq((c.held.watched(), c.unheld.val), (true, 0))
  c.items.set([])
  c.frame(1000.0)
  assert_eq((c.held.watched(), c.unheld.val), (false, 1))
  c.held.set(3)
  c.frame(1100.0)
  assert_eq((c.held.watched(), c.unheld.val), (false, 1))
  c.items.set(["b"])
  c.frame(2000.0)
  assert_eq((c.held.watched(), c.unheld.val), (true, 1))
  assert_eq(c.rows(), [("b held 3", 0.0)])
}

///|
test "a row put by is let go as its key is no more kept, and with the each; one let go so is made anew as its key comes" {
  let c = kept_case(["a", "b"], ["b"])
  c.frame(0.0)
  let b = c.nodes["b"]
  c.items.set(["a"])
  c.frame(1000.0)
  assert_true(b.alive())
  c.keeps.set([])
  c.frame(1100.0)
  assert_false(b.alive())
  assert_eq(c.owned.get("b"), Some(1))
  // (its key again: a row made anew)
  c.items.set(["a", "b"])
  c.frame(2000.0)
  assert_eq(c.made["b"], 2)
  assert_false(physical_equal(c.nodes["b"], b))
  // (put by again, then the each let go: what it put by let go with it)
  c.keeps.set(["b"])
  c.frame(2100.0)
  let b2 = c.nodes["b"]
  c.items.set(["a"])
  c.frame(3000.0)
  assert_true(b2.alive())
  c.here.set(false)
  c.frame(4000.0)
  assert_false(b2.alive())
  assert_eq(c.owned.get("b"), Some(2))
  assert_eq(c.owned.get("a"), Some(1))
}

///|
test "a row put by and taken in within its way shows that way where the clock has it, its moment come due as it rested" {
  let c = kept_case(["b"], ["b"])
  c.frame(0.0)
  let way_x = fn() {
    match c.t.drawn().iter().find_first(fn(d) { d.words == "b~" }) {
      Some(d) => d.x
      None => -1.0
    }
  }
  c.frame(10.0)
  assert_eq(way_x(), 3.0)
  assert_true(c.t.clock_read(), msg="its way followed as it goes")
  c.items.set([])
  c.frame(50.0)
  assert_eq(way_x(), -1.0)
  // (put by mid-way: nothing drawn by the clock, so the tree is not moving for it)
  assert_false(c.t.clock_read(), msg="nothing follows the clock for a row put by")
  c.frame(110.0)
  c.frame(130.0)
  // (its moment done at its own moment as it rested)
  assert_eq(c.out, ["b moment 100 at 100"])
  // (back at 200: where its way is at 200, not where it was put by)
  c.t.event(200.0, fn() { c.items.set(["b"]) })
  c.frame(200.0)
  assert_eq(way_x(), 60.0)
  assert_true(c.t.clock_read(), msg="followed again as it is taken back within its way")
  c.frame(400.0)
  assert_eq(way_x(), 90.0)
}
