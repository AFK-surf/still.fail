// Live's Roomed said under a holder already laid out in the same layout (a node made as a list lays out its rows): it is
// told the room its holder was laid out in at once, not the next time that holder is laid out; a probe's room is not
// that (flex's room_said, Tree::roomed_add).

///|
/// A node `talk` given `width` (None: as wide as it holds) and 300 tall, holding a layout_box that makes `n()` children
/// as it is laid out, as wide as it and each as tall as `tall` says of talk's room (Roomed), one under another; in a row
/// beside a fixed 100 where `beside` (talk grown into what is left: flex probes it first).
fn made_in_layout(
  n : () -> Int,
  tall : (Double, Double) -> Double,
  width? : Double,
  beside? : Bool = false,
  across? : Bool = false,
) -> (@view.Tree, Map[String, @view.NodeId]) {
  let ids : Map[String, @view.NodeId] = {}
  let talk_in = fn(talk : @view.View) {
    talk.height(Is(Some(300.0))) |> ignore
    match width {
      Some(w) => talk.width(Is(Some(w))) |> ignore
      None => ()
    }
    if beside {
      talk.grow(Is(1.0)) |> ignore
    }
    talk.box(fn(lb) {
      lb.grow(Is(1.0)).layout_box(By(fn() { n() }), fn(l, count) {
        let mut y = 0.0
        for i in 0..<count {
          let c = l.child("c\{i}", fn(v) {
            ids["c\{i}"] = v.id()
            v.height(Roomed(talk, fn(w, h) { Some(tall(w, h)) })) |> ignore
          })
          let (_, h) = l.measure(c, l.width)
          l.place(c, 0.0, y)
          y = y + h
        }
      }) |> ignore
    }) |> ignore
  }
  let tree = @view.Tree::new(
    fn(root) {
      if across {
        root.width(Is(Some(400.0))).height(Is(Some(300.0))).scrolls(@view.Scroll::across(), fn(held) {
          held.box(fn(talk) { ids["talk"] = talk.id(); talk_in(talk) }) |> ignore
        }) |> ignore
      } else if beside {
        root.row(Is(true)).width(Is(Some(400.0))) |> ignore
        root.box(fn(talk) { ids["talk"] = talk.id(); talk_in(talk) }) |> ignore
        root.box(fn(b) { b.width(Is(Some(100.0))).height(Is(Some(20.0))) |> ignore }) |> ignore
      } else {
        root.box(fn(talk) { ids["talk"] = talk.id(); talk_in(talk) }) |> ignore
      }
    },
    time=fn() { 0.0 },
  )
  (tree, ids)
}

///|
/// A twentieth of its holder's width (7 where that is unbounded).
fn by_width(w : Double, _h : Double) -> Double {
  if w == w { w / 20.0 } else { 7.0 }
}

///|
test "Roomed: a node made as its holder's subtree is laid out told the holder's room in that layout" {
  let (tree, ids) = made_in_layout(fn() { 1 }, by_width, width=400.0)
  tree.frame(800.0, 600.0, now=0.0) |> ignore
  let d = tree.drawn_of(ids["c0"]).unwrap()
  assert_eq(d.h, 20.0, msg="400 / 20, its holder's width, in the first frame: \{(d.x, d.y, d.w, d.h)}")
  tree.dispose()
}

///|
test "Roomed: its holder's height told though its width is unbounded (what scrolls across holds it)" {
  let (tree, ids) = made_in_layout(fn() { 1 }, fn(_, h) { if h == h { h / 30.0 } else { 7.0 } }, across=true)
  tree.frame(800.0, 600.0, now=0.0) |> ignore
  let d = tree.drawn_of(ids["c0"]).unwrap()
  assert_eq(d.h, 10.0, msg="300 / 30, its holder's height, in the first frame")
  tree.dispose()
}

///|
test "Roomed: one made in a later layout, its holder probed before it is laid out, as one made at once at that room" {
  let n = @signals.signal(1, same=fn(a, b) { a == b })
  let (grown, ids) = made_in_layout(fn() { n.get() }, by_width, beside=true)
  grown.frame(800.0, 600.0, now=0.0) |> ignore
  n.set(2)
  grown.frame(800.0, 600.0, now=16.0) |> ignore
  let later = grown.drawn_of(ids["c1"]).unwrap()
  let talk = grown.drawn_of(ids["talk"]).unwrap()
  grown.dispose()
  let (opened, ids2) = made_in_layout(fn() { 2 }, by_width, beside=true)
  opened.frame(800.0, 600.0, now=0.0) |> ignore
  let at_once = opened.drawn_of(ids2["c1"]).unwrap()
  opened.dispose()
  assert_eq(later.h, talk.w / 20.0, msg="a twentieth of what talk grew into: \{(talk.w, later.h)}")
  assert_eq((later.x, later.y, later.w, later.h), (at_once.x, at_once.y, at_once.w, at_once.h))
}

///|
/// A box as tall as what it holds (layout_box sized: its holder probes it, width given, for its height), `wide()` wide,
/// making `n()` children as it is laid out, each as tall as a tenth of its width (Roomed by it), one under another; a
/// 20 tall node under it in a column.
fn sized_made(wide : () -> Double, n : () -> Int) -> (@view.Tree, Map[String, @view.NodeId]) {
  let ids : Map[String, @view.NodeId] = {}
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(col) {
        col.width(By(fn() { Some(wide()) })) |> ignore
        col.box(fn(holder) {
          ids["holder"] = holder.id()
          holder.layout_box(By(fn() { n() }), sized=true, fn(l, count) {
            let mut y = 0.0
            for i in 0..<count {
              let c = l.child("c\{i}", fn(v) {
                ids["c\{i}"] = v.id()
                v.height(Roomed(holder, fn(w, _) { Some(if w == w { w / 10.0 } else { 1.0 }) })) |> ignore
              })
              let (_, h) = l.measure(c, l.width)
              l.place(c, 0.0, y)
              y = y + h
            }
            l.size_to(y)
          }) |> ignore
        }) |> ignore
        col.box(fn(under) {
          ids["under"] = under.id()
          under.height(Is(Some(20.0))) |> ignore
        }) |> ignore
      }) |> ignore
    },
    time=fn() { 0.0 },
  )
  (tree, ids)
}

///|
test "Roomed: made as its holder is probed for its height (sized), told the probe's room, in the first frame and after it is narrower" {
  let wide = @signals.signal(400.0, same=fn(a, b) { a == b })
  let n = @signals.signal(1, same=fn(a, b) { a == b })
  let (tree, ids) = sized_made(fn() { wide.get() }, fn() { n.get() })
  tree.frame(800.0, 600.0, now=0.0) |> ignore
  assert_eq(tree.drawn_of(ids["holder"]).unwrap().h, 40.0, msg="one child, 400 / 10 tall, in the first frame")
  wide.set(200.0)
  n.set(2)
  tree.frame(800.0, 600.0, now=16.0) |> ignore
  let holder = tree.drawn_of(ids["holder"]).unwrap()
  let under = tree.drawn_of(ids["under"]).unwrap()
  let second = tree.drawn_of(ids["c1"]).unwrap()
  tree.dispose()
  let (fresh, ids2) = sized_made(fn() { 200.0 }, fn() { 2 })
  fresh.frame(800.0, 600.0, now=0.0) |> ignore
  let holder2 = fresh.drawn_of(ids2["holder"]).unwrap()
  let under2 = fresh.drawn_of(ids2["under"]).unwrap()
  let second2 = fresh.drawn_of(ids2["c1"]).unwrap()
  fresh.dispose()
  assert_eq(holder.h, 40.0, msg="two children, 200 / 10 tall each")
  assert_eq((holder.h, under.y, second.y, second.h), (holder2.h, under2.y, second2.y, second2.h))
}
