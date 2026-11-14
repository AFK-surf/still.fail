// A column or a row that scrolls brought on by the hand held past its edge (Scroll::edge_toward), steady, where it is a
// function of the time; and found by what it holds (View::scroll_holding).

///|
test "brought on past its edge: steady at its speed, as far as it goes at most, wherever the frames fall; said anew, on from there; 0, stopped" {
  let now = Ref(0.0)
  let k = across_case(now~)
  let at = fn(t : Double) {
    now.val = t
    k.tree.frame(390.0, 844.0, now=t) |> ignore
    k.column.at(k.tree)
  }
  k.column.edge_toward(0.5)
  let one = at(100.0)
  // (said anew, faster: from where it is then)
  k.column.edge_toward(1.0)
  let two = at(200.0)
  k.column.edge_toward(0.0)
  let stopped = (at(300.0), at(400.0))
  // (back toward its top, past it: at its top, at rest)
  k.column.edge_toward(-2.0)
  let back = (at(450.0), at(1000.0), k.column.glides_till())
  // (on toward its foot: as far as it can go, at rest there)
  k.column.edge_toward(3.0)
  let foot = (at(2000.0), k.column.glides_till())
  assert_eq((one, two, stopped, back, foot), (50.0, 150.0, (150.0, 150.0), (50.0, 0.0, None), (490.0, None)))
}

///|
test "what scrolls round it found by what it holds: the row across, the column up and down; above the column, nothing" {
  let column = @view.Scroll::new()
  let across = @view.Scroll::across()
  let cell : Ref[@view.View?] = Ref(None)
  let outside : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        outside.val = Some(o)
        o
        .height(Is(Some(100.0)))
        .scrolls(column, fn(oh) {
          oh.box(fn(r) {
            r.scrolls(across, fn(rh) {
              rh.row(Is(true)) |> ignore
              rh.box(fn(c) {
                cell.val = Some(c)
                c.width(Is(Some(600.0))).height(Is(Some(400.0))) |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let c = cell.val.unwrap()
  let same = fn(found : @view.Scroll?, s : @view.Scroll) { found.map(fn(f) { physical_equal(f, s) }) == Some(true) }
  assert_eq(
    (same(c.scroll_holding(across=true), across), same(c.scroll_holding(), column), root_holds_none(outside.val.unwrap())),
    (true, true, true),
  )
}

///|
/// Whether nothing round what holds `v` scrolls (its holder's: what scrolls in `v` itself left out).
fn root_holds_none(v : @view.View) -> Bool {
  match v.parent() {
    Some(h) => h.scroll_holding() is None && h.scroll_holding(across=true) is None
    None => true
  }
}

///|
priv struct EdgeCase {
  tree : @view.Tree
  s : @view.Scroll
  now : Ref[Double]
  /// how tall what it holds is, whether the column is shown
  tall : @signals.Signal[Double]
  shown : @signals.Signal[Bool]
}

///|
/// A column 100 tall scrolling `s` (a box kept to a height's, or a page's list's where `list`), what it holds `tall`
/// tall (at first 400: it can go 300), shown while `shown` says.
fn edge_case(list? : Bool = false) -> EdgeCase {
  let s = if list { @view.Scroll::list() } else { @view.Scroll::new() }
  let now = Ref(0.0)
  let tall = @signals.signal(400.0, same=fn(a, b) { a == b })
  let shown = @signals.signal(true, same=fn(a, b) { a == b })
  let tree = @view.Tree::new(
    fn(root) {
      root.show(at_once=true, fn() { shown.get() }, fn(o) {
        o
        .height(Is(Some(100.0)))
        .scrolls(s, fn(h) { h.box(fn(b) { b.height(By(fn() { Some(tall.get()) })) |> ignore }) |> ignore })
        |> ignore
      })
    },
    time=fn() { now.val },
  )
  tree.frame(390.0, 844.0, now=0.0) |> ignore
  { tree, s, now, tall, shown }
}

///|
/// Where it is at `t`, laid out as it is then.
fn EdgeCase::at(self : EdgeCase, t : Double) -> Double {
  self.now.val = t
  self.tree.frame(390.0, 844.0, now=t) |> ignore
  self.s.at(self.tree)
}

///|
test "brought on past its edge, let go of on its way and made again: where it had it then, not going on; let go of at its end: there" {
  let k = edge_case()
  k.s.edge_toward(0.5)
  let going = k.at(100.0)
  k.shown.set(false)
  k.at(100.0) |> ignore
  k.shown.set(true)
  let again = (k.at(200.0), k.at(400.0))
  // (to its end, then let go of and made again)
  k.s.edge_toward(2.0)
  let foot = k.at(1000.0)
  k.shown.set(false)
  k.at(1100.0) |> ignore
  k.shown.set(true)
  assert_eq((going, again, foot, k.at(1200.0)), (50.0, (50.0, 50.0), 300.0, 300.0))
}

///|
test "brought on past its edge, what it holds grown taller or shorter as it goes, the hand still: on to its foot as it is now, at rest there; grown again at rest there, on from there" {
  let k = edge_case()
  k.s.edge_toward(1.0)
  // (going on by itself till its foot as it is: 300 on)
  let till = k.s.glides_till()
  let first = k.at(100.0)
  // (taller, laid out so at once: on past where its foot was, to where it is now, its end later)
  k.tall.set(700.0)
  k.at(100.0) |> ignore
  let later = k.s.glides_till()
  let past = (k.at(400.0), k.at(700.0))
  // (shorter than where it has got to: there, at rest)
  k.tall.set(300.0)
  let shorter = (k.at(700.0), k.at(900.0))
  // (taller again, the hand still past its edge: on from its foot as it was, from then)
  k.tall.set(500.0)
  let on = (k.at(900.0), k.at(1000.0), k.at(1100.0), k.at(1500.0))
  let parked = k.s.glides_till()
  k.s.edge_toward(0.0)
  k.tall.set(900.0)
  assert_eq(
    (till, first, later, past, shorter, on, parked, k.at(2000.0), k.s.glides_till()),
    (Some(300.0), 100.0, Some(600.0), (400.0, 600.0), (200.0, 200.0), (200.0, 300.0, 400.0, 400.0), None, 400.0, None),
  )
}

///|
test "a page's list brought on past its edge, rows above what is in sight measured anew, going down or up: what is in sight where it is, going on as it was to its end, at rest there" {
  let k = edge_case(list=true)
  k.s.edge_toward(0.5)
  let first = k.at(100.0)
  k.s.grew_above(30.0)
  k.tall.set(430.0)
  let grown = (k.at(100.0), k.at(200.0), k.s.glides_till())
  // (on to its foot as it is now, at rest there: nothing going on)
  let foot = (k.at(2000.0), k.s.glides_till())
  // (back up toward its top, rows above grown again on its way: on to its top, at rest there)
  k.s.edge_toward(-1.0)
  let up = k.at(2100.0)
  k.s.grew_above(50.0)
  k.tall.set(480.0)
  let up_grown = (k.at(2100.0), k.s.glides_till())
  let top = (k.at(3000.0), k.s.glides_till())
  assert_eq(
    (first, grown, foot, up, up_grown, top),
    (50.0, (80.0, 130.0, Some(600.0)), (330.0, None), 230.0, (280.0, Some(2380.0)), (0.0, None)),
  )
}

///|
test "what scrolls round it asked of a node let go of: nothing, whatever is made in its place" {
  let s = @view.Scroll::new()
  let first = @signals.signal(true)
  let gone : Ref[@view.View?] = Ref(None)
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o
        .height(Is(Some(100.0)))
        .scrolls(s, fn(h) {
          h.show(at_once=true, fn() { first.get() }, fn(c) {
            gone.val = Some(c)
            c.height(Is(Some(400.0))) |> ignore
          })
          h.show(at_once=true, fn() { !first.get() }, fn(c) { c.height(Is(Some(400.0))) |> ignore })
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  let v = gone.val.unwrap()
  let before = v.scroll_holding() is Some(_)
  first.set(false)
  tree.frame(390.0, 844.0) |> ignore
  assert_eq((before, v.scroll_holding() is Some(_)), (true, false))
}
